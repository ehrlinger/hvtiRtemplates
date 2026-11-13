test_that("the mm cohort is longitudinal with the correlation it was built with", {
  d <- mm_data()
  per_patient <- table(d$ccfid)
  expect_true(all(per_patient >= 2L & per_patient <= 6L))
  expect_false(anyDuplicated(d[c("ccfid", "time")]) > 0L)
  expect_true(all(d$y > 0))
  # The between-patient share of the log-scale variance is the CS correlation.
  fit <- nlme::lme(log(y) ~ log(time + 1) + age + female, random = ~ 1 | ccfid, data = d)
  vc <- as.numeric(nlme::VarCorr(fit)[, "Variance"])
  expect_equal(vc[[1L]] / sum(vc), 0.5, tolerance = 0.1)
})

test_that("mm scaffolds with its study choices and EDIT: markers", {
  root <- withr::local_tempdir("mm-scaffold-")
  suppressMessages(hvtiRutilities::study_setup(root, study = "Synthetic mm study", study_tracker_id = 42L,
                                               adopt = TRUE, cleanup = FALSE, renv = FALSE))
  job <- add_job("mm", "outcome", "mixed", dir = root)
  src <- readLines(job, warn = FALSE)
  # tbl-data resolves RESPONSE_SCALE and IMPUTATION again; the study choices are the lines before it.
  src <- src[seq_len(grep("label: tbl-data", src, fixed = TRUE) - 1L)]
  for (field in c("TIME", "KEY", "OUTCOME", "RESPONSE_SCALE", "TIME_TERMS", "PREDICTORS", "STRUCTURE", "SLOPE", "METHOD",
                  "PREDICT_AT", "PREDICT_TIMES", "IMPUTATION")) {
    expect_length(grep(paste0("^", field, " <- "), src), 1L)
  }
  expect_true(any(grepl('^STRUCTURE <- "cs"', src)))
  expect_true(any(grepl("^KEY <- c\\(ID, TIME\\)", src)))
  expect_gt(sum(grepl("EDIT:", src, fixed = TRUE)), 5L)
})

test_that("mm reads every measurement, not one row per patient", {
  src <- readLines(template_path("mm"), warn = FALSE)
  expect_true(any(grepl("one_row_per_patient = FALSE", src, fixed = TRUE)))
})

mm_formula <- log(y) ~ log(time + 1) + age + female

test_that("mm_check stops on data that is not longitudinal", {
  h <- mm_helpers()
  d <- mm_data()
  expect_true(h$mm_check(d, "ccfid", "time", "cs", NULL))
  one <- d[!duplicated(d$ccfid), ]
  expect_error(h$mm_check(one, "ccfid", "time", "cs", NULL), "a single row")
})

test_that("mm_check stops on a missing or negative time", {
  h <- mm_helpers()
  d <- mm_data()
  d$time[[1L]] <- NA
  expect_error(h$mm_check(d, "ccfid", "time", "cs", NULL), "TIME")
  d$time[[1L]] <- -1
  expect_error(h$mm_check(d, "ccfid", "time", "cs", NULL), "TIME")
})

test_that("mm_check refuses AR(1) and UN on free times, and accepts them on visits", {
  h <- mm_helpers()
  d <- mm_data()
  expect_error(h$mm_check(d, "ccfid", "time", "ar1", NULL), "20 distinct")
  expect_error(h$mm_check(d, "ccfid", "time", c("cs", "un"), NULL), "20 distinct")
  d$time <- stats::ave(d$time, d$ccfid, FUN = seq_along)
  expect_true(h$mm_check(d, "ccfid", "time", "ar1", NULL))
})

test_that("mm_check refuses an unknown structure and any imputation column", {
  h <- mm_helpers()
  d <- mm_data()
  expect_error(h$mm_check(d, "ccfid", "time", "sp(pow)", NULL), "STRUCTURE")
  # RANDOM with REPEATED in one fit is not offered: one corpus study wrote it.
  expect_error(h$mm_check(d, "ccfid", "time", "random+cs", NULL), "STRUCTURE")
  expect_error(h$mm_check(d, "ccfid", "time", "cs", "imp"), "IMPUTATION")
})

test_that("mm_check refuses a VISIT that cannot place each measurement once", {
  h <- mm_helpers()
  d <- mm_visits()
  d$visit <- d$time
  expect_true(h$mm_check(d, "ccfid", "time", "ar1", NULL, "visit"))
  expect_error(h$mm_check(d, "ccfid", "time", "ar1", NULL, "visits"), "is not a column")
  half <- d
  half$visit <- half$visit + 0.5
  expect_error(h$mm_check(half, "ccfid", "time", "ar1", NULL, "visit"), "whole visit number")
  twice <- d
  twice$visit[2] <- twice$visit[1]
  expect_error(h$mm_check(twice, "ccfid", "time", "ar1", NULL, "visit"), "repeats a visit")
  many <- d
  many$visit <- seq_len(nrow(many))
  expect_error(h$mm_check(many, "ccfid", "time", "ar1", NULL, "visit"), "VISIT has .* 20 distinct")
})

test_that("mm_fit with cs recovers the correlation and the time effect", {
  h <- mm_helpers()
  fit <- h$mm_fit(mm_data(), mm_formula, "ccfid", "time", "cs", "REML")
  expect_s3_class(fit$model, "gls")
  cov <- h$mm_covariance(fit)
  rho <- cov$estimate[cov$parameter == "within-patient correlation"]
  expect_equal(rho, 0.5, tolerance = 0.1)
  est <- summary(fit$model)$tTable["log(time + 1)", ]
  expect_lt(abs(est[["Value"]] - 0.2), 2 * est[["Std.Error"]])
  expect_identical(fit$n_patients, 200L)
})

test_that("mm_fit counts the patients and rows it used, not every row read", {
  h <- mm_helpers()
  d <- mm_data()
  d$y[d$ccfid %in% 1:20] <- NA
  fit <- h$mm_fit(d, log(y) ~ log(time + 1) + age + female, "ccfid", "time", "cs", "REML")
  expect_identical(length(fit$per_patient), fit$n_patients)
  expect_identical(sum(fit$per_patient), fit$n_measurements)
  # A factor ID read from RDS keeps the dropped patients as levels; they must not count as zero rows.
  d$ccfid <- factor(d$ccfid)
  fit <- h$mm_fit(d, log(y) ~ log(time + 1) + age + female, "ccfid", "time", "cs", "REML")
  expect_identical(length(fit$per_patient), fit$n_patients)
  expect_gt(min(fit$per_patient), 0L)
})

test_that("every STRUCTURE fits and reports its own parameters", {
  h <- mm_helpers()
  d <- mm_visits()
  f <- log(y) ~ time + age + female
  expected <- list(
    cs = c("residual variance", "within-patient correlation"),
    ar1 = c("residual variance", "correlation, adjacent visits"),
    un = c("residual variance at visit 1", paste0("SD ratio, visit ", 2:6, " to visit 1"),
           paste0("correlation, visits ", combn(6, 2)[1, ], " and ", combn(6, 2)[2, ])),
    random = c("between-patient variance", "residual variance", "within-patient correlation")
  )
  for (s in names(expected)) {
    fit <- h$mm_fit(d, f, "ccfid", "time", s, "REML")
    expect_true(is.finite(stats::AIC(fit$model)), info = s)
    expect_identical(h$mm_covariance(fit)$parameter, expected[[s]], info = s)
  }
})

test_that("AR(1) and UN place a measurement by its visit, not its row, when a visit is missed", {
  h <- mm_helpers()
  d <- mm_visits()
  n <- stats::ave(d$time, d$ccfid, FUN = length)
  gap <- d[!(d$time == 2 & n >= 3), ]
  moved <- gap
  moved$time <- moved$time * 10 + 5
  f <- log(y) ~ age + female
  for (s in c("un", "ar1")) {
    fit <- h$mm_fit(gap, f, "ccfid", "time", s, "REML")
    covariate <- unlist(nlme::getCovariate(fit$model$modelStruct$corStruct))
    # corSymm stores its covariate zero-based.
    stored <- as.integer(covariate) + as.integer(identical(s, "un"))
    expect_identical(sort(stored), sort(match(gap$time, sort(unique(gap$time)))), info = s)
    shifted <- h$mm_fit(moved, f, "ccfid", "time", s, "REML")
    expect_equal(as.numeric(stats::logLik(fit$model)), as.numeric(stats::logLik(shifted$model)), info = s)
  }
})

test_that("UN labels each correlation by visit pair and matches corMatrix", {
  h <- mm_helpers()
  d <- mm_visits()
  d <- d[d$time <= 4, ]
  fit <- h$mm_fit(d, log(y) ~ age + female, "ccfid", "time", "un", "REML")
  cov <- h$mm_covariance(fit)
  corr <- cov[startsWith(cov$parameter, "correlation, visits"), ]
  expect_identical(nrow(corr), 6L)
  expect_identical(anyDuplicated(corr$parameter), 0L)
  full <- nlme::corMatrix(fit$model$modelStruct$corStruct)
  mat <- full[[which(vapply(full, nrow, 1L) == 4L)[[1L]]]]
  for (i in seq_len(nrow(corr))) {
    v <- as.integer(regmatches(corr$parameter[[i]], gregexpr("[0-9]+", corr$parameter[[i]]))[[1L]])
    expect_equal(corr$estimate[[i]], mat[v[[1L]], v[[2L]]], info = corr$parameter[[i]])
  }
})

test_that("slope fits an independent random intercept and slope and recovers their variances", {
  h <- mm_helpers()
  fit <- h$mm_fit(mm_slopes(), ly ~ log(time + 1) + age, "ccfid", "time", "slope", "REML", slope = "log(time + 1)")
  expect_s3_class(fit$model, "lme")
  expect_s3_class(fit$model$modelStruct$reStruct[[1L]], "pdDiag")
  expect_identical(fit$slope, "log(time + 1)")
  expect_identical(fit$n_single_time, 0L)
  cov <- h$mm_covariance(fit)
  expect_identical(cov$parameter, c("Intercept variance", "log(time + 1) variance", "residual variance"))
  expect_equal(cov$estimate, c(0.04, 0.01, 0.01), tolerance = 0.25)
})

test_that("slope counts the patients measured at one time", {
  h <- mm_helpers()
  d <- mm_slopes()
  d$time[d$ccfid %in% 1:5] <- 2
  fit <- h$mm_fit(d, ly ~ log(time + 1) + age, "ccfid", "time", "slope", "REML", slope = "log(time + 1)")
  expect_identical(fit$n_single_time, 5L)
})

test_that("mm_check refuses a SLOPE outside TIME_TERMS and data with no slope to fit", {
  h <- mm_helpers()
  d <- mm_slopes()
  expect_true(h$mm_check(d, "ccfid", "time", c("cs", "slope"), NULL, slope = "log(time + 1)",
                         time_terms = "log(time + 1)"))
  expect_error(h$mm_check(d, "ccfid", "time", "slope", NULL, slope = "time", time_terms = "log(time + 1)"),
               "SLOPE \\(time\\) is not one of TIME_TERMS")
  # A SLOPE is ignored when no structure asks for one.
  expect_true(h$mm_check(d, "ccfid", "time", "cs", NULL, slope = "time", time_terms = "log(time + 1)"))
  # A term that expands to several columns would fit several slope variances under one label.
  expect_error(h$mm_check(d, "ccfid", "time", "slope", NULL, slope = "splines::ns(time, 2)",
                          time_terms = "splines::ns(time, 2)"),
               "single numeric column")
  # With no time term there is no slope to ask for.
  expect_error(h$mm_check(d, "ccfid", "time", "slope", NULL, slope = NULL, time_terms = character(0)),
               "SLOPE names no time term")
  expect_true(h$mm_check(d, "ccfid", "time", "cs", NULL, slope = NULL, time_terms = character(0)))
})

test_that("slope refuses data whose fitted rows hold no patient at two or more times", {
  h <- mm_helpers()
  d <- mm_slopes()
  # Every patient has several times, but a missing response leaves each with one fitted row.
  d$ly[duplicated(d$ccfid)] <- NA
  expect_error(h$mm_fit(d, ly ~ log(time + 1) + age, "ccfid", "time", "slope", "REML", slope = "log(time + 1)"),
               "no patient has two or more fitted measurements at distinct times")
  d <- mm_slopes()
  d$age[duplicated(d$ccfid)] <- NA
  expect_error(h$mm_fit(d, ly ~ log(time + 1) + age, "ccfid", "time", "slope", "REML", slope = "log(time + 1)"),
               "no patient has two or more fitted measurements at distinct times")
})

test_that("a model with no time term still fits a structure other than slope", {
  h <- mm_helpers()
  fit <- h$mm_fit(mm_slopes(), ly ~ age, "ccfid", "time", "cs", "REML")
  expect_s3_class(fit$model, "gls")
})

test_that("UN names the variance reference from the fit when the first patient misses visit 1", {
  h <- mm_helpers()
  d <- mm_visits()
  d <- d[d$time <= 4 & !(d$ccfid == 1 & d$time == 1), ]
  fit <- h$mm_fit(d, log(y) ~ age + female, "ccfid", "time", "un", "REML")
  vs <- fit$model$modelStruct$varStruct
  ref <- attr(vs, "groupNames")[[1L]]
  expect_false(identical(ref, "1"))
  ratio <- stats::coef(vs, unconstrained = FALSE)
  cov <- h$mm_covariance(fit)
  expect_equal(cov$estimate[cov$parameter == paste0("residual variance at visit ", ref)], fit$model$sigma^2)
  for (k in names(ratio)) {
    expect_equal(cov$estimate[cov$parameter == paste0("SD ratio, visit ", k, " to visit ", ref)], ratio[[k]], info = k)
  }
})

test_that("with VISIT, AR(1) counts a visit nobody attended and recovers the correlation", {
  h <- mm_helpers()
  set.seed(20261112)
  n <- 300L
  rho <- 0.6
  e <- as.vector(replicate(n, as.numeric(stats::arima.sim(list(ar = rho), 6L, sd = sqrt(1 - rho^2)))))  # one column per patient
  d <- data.frame(ccfid = rep(seq_len(n), each = 6L), visit = rep(1:6, n))
  d$time <- d$visit
  d$y <- exp(1 + 0.1 * d$time + e)
  d <- d[d$visit != 2L, ]  # visit 2 is on the schedule, and no patient attended it
  f <- log(y) ~ time
  fit <- h$mm_fit(d, f, "ccfid", "time", "ar1", "REML", visit = "visit")
  steps <- unlist(lapply(nlme::getCovariate(fit$model$modelStruct$corStruct), diff))
  expect_true(2L %in% steps)
  est <- h$mm_covariance(fit)$estimate
  expect_lt(abs(est[[2L]] - rho), 0.08)
  ranked <- h$mm_fit(d, f, "ccfid", "time", "ar1", "REML")
  expect_false(2L %in% unlist(lapply(nlme::getCovariate(ranked$model$modelStruct$corStruct), diff)))
})

test_that("with VISIT, UN labels each visit by its number", {
  h <- mm_helpers()
  d <- mm_visits()
  d$visit <- d$time
  d <- d[d$visit != 2L, ]
  cov <- h$mm_covariance(h$mm_fit(d, log(y) ~ time + age + female, "ccfid", "time", "un", "REML", visit = "visit"))
  expect_true(all(c("correlation, visits 1 and 3", "SD ratio, visit 3 to visit 1") %in% cov$parameter))
  expect_false(any(grepl("visit 2\\b", cov$parameter)))
})

test_that("mm_predict back-transforms the log scale and keeps the limits around the estimate", {
  h <- mm_helpers()
  d <- mm_data()
  fit <- h$mm_fit(d, mm_formula, "ccfid", "time", "cs", "REML")
  grid <- h$mm_grid(d, c("age", "female"), "time", NULL, c(0, 5, 10))
  expect_identical(nrow(grid), 3L)
  log_scale <- h$mm_predict(fit, grid, "identity")
  natural <- h$mm_predict(fit, grid, "log")
  expect_equal(natural$estimate, exp(log_scale$estimate))
  expect_equal(natural$lower, exp(log_scale$lower))
  expect_true(all(natural$lower < natural$estimate & natural$estimate < natural$upper))
  truth <- exp(3 + 0.01 * (grid$age[[1L]] - 60) - 0.1 * grid$female[[1L]])
  expect_equal(natural$estimate[[1L]], truth, tolerance = 0.05)
})

test_that("mm_predict reuses the fitted poly() basis and ordered-factor coding", {
  h <- mm_helpers()
  d <- mm_data()
  d$grade <- ordered(rep_len(c("low", "mid", "high"), nrow(d)), levels = c("low", "mid", "high"))
  fit <- h$mm_fit(d, log(y) ~ poly(time, 2) + grade + age, "ccfid", "time", "cs", "REML")
  # Five training rows, with the ordered factor passed as text as PREDICT_AT would give it: a basis or coding
  # rebuilt from these rows would not reproduce the fitted values.
  rows <- d[1:5, ]
  rows$grade <- as.character(rows$grade)
  pred <- h$mm_predict(fit, rows, "identity")
  expect_equal(unname(pred$estimate), unname(stats::fitted(fit$model)[1:5]), tolerance = 1e-8)
})

test_that("a level held only by rows the fit dropped neither breaks prediction nor reaches the grid", {
  h <- mm_helpers()
  d <- mm_data()
  # A factor, as an RDS dataset carries it: the empty level "c" survives the complete-case subset.
  d$group <- factor(c("a", "b", "c")[(d$ccfid %% 3L) + 1L])
  d$y[d$group == "c"] <- NA
  fit <- h$mm_fit(d, log(y) ~ log(time + 1) + group, "ccfid", "time", "cs", "REML")
  expect_identical(fit$xlev$group, c("a", "b"))
  grid <- h$mm_grid(d[fit$used, , drop = FALSE], "group", "time", NULL, c(0, 5))
  expect_true(all(is.finite(h$mm_predict(fit, grid, "log")$estimate)))
  asked <- h$mm_grid(d, "group", "time", list(list(group = "c")), c(0, 5))
  expect_error(h$mm_predict(fit, asked, "log"), "PREDICT_AT asks for group = c")
})

test_that("mm_fit returns the used rows in the order of the data it was given", {
  h <- mm_helpers()
  d <- mm_data()
  # Interleaved patients, as a dataset sorted by time or date arrives; mm_fit sorts its own copy.
  d <- d[order(d$time, -d$ccfid), , drop = FALSE]
  d$y[d$ccfid %in% 1:30] <- NA
  fit <- h$mm_fit(d, log(y) ~ log(time + 1) + age + female, "ccfid", "time", "cs", "REML")
  expect_identical(fit$used, !is.na(d$y))
  grid <- h$mm_grid(d[fit$used, , drop = FALSE], c("age", "female"), "time", NULL, c(0, 5))
  expect_identical(unique(grid$age), stats::median(d$age[!is.na(d$y)]))
})

test_that("mm_fit leaves rows with a missing ID out of every count, as nlme does", {
  h <- mm_helpers()
  d <- mm_data()
  d$ccfid[1:3] <- NA
  fit <- h$mm_fit(d, log(y) ~ log(time + 1) + age + female, "ccfid", "time", "cs", "REML")
  expect_identical(fit$n_measurements, as.integer(stats::nobs(fit$model)))
  expect_identical(sum(fit$per_patient), fit$n_measurements)
})

test_that("mm_grid takes default values from the variables under a term", {
  h <- mm_helpers()
  grid <- h$mm_grid(mm_data(), c("I(age^2)", "age:female"), "time", NULL, c(0, 5))
  expect_setequal(setdiff(names(grid), c("time", "profile")), c("age", "female"))
  expect_false(anyNA(grid$age))
})

test_that("mm_grid uses the profiles and times it is given", {
  h <- mm_helpers()
  d <- mm_data()
  grid <- h$mm_grid(d, c("age", "female"), "time",
                    list(list(age = 50, female = 0), list(age = 70, female = 1)), NULL)
  expect_identical(nrow(grid), 100L)
  expect_identical(sort(unique(grid$age)), c(50, 70))
  expect_equal(range(grid$time), range(d$time))
})

compare_table <- paste0("Comparison of covariance structures, same fixed effects\\s*</figcaption>\\s*<div[^>]*>\\s*",
                        "<div class=\"cell-output-display\">\\s*<table")

test_that("mm renders end to end and saves a bundle with no nlme object and no raw IDs", {
  skip_on_cran()
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  out <- mm_render_fixture()
  expect_true(file.exists(out$output))
  set <- file.path(hvtiRutilities::study_dir("estimates", out$root), "outcome-mixed")
  bundle <- readRDS(file.path(set, "mm.rds"))
  expect_false(any(vapply(bundle, function(x) inherits(x, c("gls", "lme")), logical(1L))))
  expect_true(bundle$meta$id_digest)
  expect_identical(bundle$meta$structure, "cs")
  expect_identical(bundle$meta$prediction_scale, "geometric mean")
  no_ids <- function(x) {
    if (is.data.frame(x)) expect_false(any(c("ccfid", "id") %in% names(x)))
    if (is.list(x)) lapply(x, no_ids)
    invisible(NULL)
  }
  no_ids(bundle)
  pred <- utils::read.csv(file.path(set, "mm-predictions.csv"))
  expect_identical(nrow(pred), 50L)
  expect_false(any(c("ccfid", "id") %in% names(pred)))
  expect_true(all(pred$lower < pred$estimate & pred$estimate < pred$upper))
  html <- paste(readLines(out$output, warn = FALSE), collapse = "\n")
  expect_match(html, "within-patient correlation", fixed = TRUE)
  expect_match(gsub("(?s)<pre[^>]*>.*?</pre>", "", html, perl = TRUE), "the limits are for that median", fixed = TRUE)
  # include = FALSE draws no caption and no code fold; the chunk source sits in <pre>, so strip it.
  expect_no_match(gsub("(?s)<pre[^>]*>.*?</pre>", "", html, perl = TRUE), "Comparison of covariance structures")
})

test_that("mm compares structures only when STRUCTURE lists several", {
  skip_on_cran()
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  out <- mm_render_fixture(choices = 'STRUCTURE <- c("cs", "random")')
  html <- paste(readLines(out$output, warn = FALSE), collapse = "\n")
  expect_match(html, compare_table)
})

test_that("mm renders a reported slope model with its variances and the one-time count", {
  skip_on_cran()
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  out <- mm_render_fixture(choices = 'STRUCTURE <- c("slope", "cs")')
  html <- gsub("(?s)<pre[^>]*>.*?</pre>", "", paste(readLines(out$output, warn = FALSE), collapse = "\n"), perl = TRUE)
  expect_match(html, "log(time + 1) variance", fixed = TRUE)
  expect_match(html, "Intercept variance", fixed = TRUE)
  expect_match(html, "residual variance", fixed = TRUE)
  expect_match(html, "patients measured at a single time", fixed = TRUE)
  expect_match(html, compare_table)
  set <- file.path(hvtiRutilities::study_dir("estimates", out$root), "outcome-mixed")
  bundle <- readRDS(file.path(set, "mm.rds"))
  expect_identical(bundle$meta$structure, "slope")
  expect_identical(bundle$meta$slope, "log(time + 1)")
})
