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
  for (field in c("TIME", "KEY", "OUTCOME", "RESPONSE_SCALE", "TIME_TERMS", "PREDICTORS", "STRUCTURE", "METHOD",
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
  expect_error(h$mm_check(d, "ccfid", "time", "cs", "imp"), "IMPUTATION")
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

# The data with visit numbers for TIME.
mm_visits <- function() {
  d <- mm_data()
  d$time <- stats::ave(d$time, d$ccfid, FUN = seq_along)
  d
}

test_that("every STRUCTURE fits and reports its own parameters", {
  h <- mm_helpers()
  d <- mm_visits()
  f <- log(y) ~ time + age + female
  expected <- list(
    cs = c("residual variance", "within-patient correlation"),
    ar1 = c("residual variance", "correlation"),
    un = c("residual variance at visit 1", paste0("SD ratio, visit ", 2:6, " to visit 1"),
           paste0("correlation, visits ", combn(6, 2)[1, ], " and ", combn(6, 2)[2, ])),
    random = c("between-patient variance", "residual variance", "within-patient correlation"),
    `random+cs` = c("between-patient variance", "residual variance", "residual correlation beyond the random intercept",
                    "implied within-patient correlation"),
    `random+ar1` = c("between-patient variance", "residual variance",
                     "residual correlation beyond the random intercept, adjacent visits",
                     "implied within-patient correlation, adjacent visits")
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

test_that("random+cs reports the implied correlation and never mislabels the residual one", {
  h <- mm_helpers()
  fit <- h$mm_fit(mm_data(), mm_formula, "ccfid", "time", "random+cs", "REML")
  cov <- h$mm_covariance(fit)
  expect_equal(cov$estimate[cov$parameter == "implied within-patient correlation"], 0.5, tolerance = 0.1)
  expect_false("within-patient correlation" %in% cov$parameter)
  expect_true("residual correlation beyond the random intercept" %in% cov$parameter)
  for (s in c("cs", "ar1", "un", "random")) {
    other <- h$mm_fit(mm_visits(), log(y) ~ time + age + female, "ccfid", "time", s, "REML")
    expect_null(h$mm_note(other), info = s)
  }
  expect_match(h$mm_note(fit), "not identified")
  ar <- h$mm_fit(mm_visits(), log(y) ~ time + age + female, "ccfid", "time", "random+ar1", "REML")
  expect_match(h$mm_note(ar), "not identified")
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

test_that("mm_grid uses the profiles and times it is given", {
  h <- mm_helpers()
  d <- mm_data()
  grid <- h$mm_grid(d, c("age", "female"), "time",
                    list(list(age = 50, female = 0), list(age = 70, female = 1)), NULL)
  expect_identical(nrow(grid), 100L)
  expect_identical(sort(unique(grid$age)), c(50, 70))
  expect_equal(range(grid$time), range(d$time))
})
