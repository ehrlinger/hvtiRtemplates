# hs-concordance: every patient through every group's hm model, as the
# design in the 2026-09-30 hs-concordance spec describes.

# Every test reads one estate, fitted on first use and removed when the file
# ends. A test that writes into the study works on a copy of it.
estate <- concordance_estate_once(environment())

test_that("the fixture fits one hm model per group, in its own set", {
  skip_on_cran()
  skip_concordance()
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  e <- estate()
  for (g in c("a", "b")) {
    path <- file.path(hvtiRutilities::study_dir("estimates", e$root), paste0("dead-", g), "hm.rds")
    expect_true(file.exists(path), info = g)
    expect_identical(nrow(readRDS(path)$reported$data$frame), sum(e$data$group == g), info = g)
  }
})

test_that("hs-concordance predicts every patient through every model and saves no identifier", {
  skip_concordance()
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  e <- concordance_copy(estate())
  env <- concordance_run(e$root, concordance_choices(e$data))
  path <- file.path(hvtiRutilities::study_dir("estimates", e$root), "dead-ab", "hs-concordance.rds")
  art <- readRDS(path)
  expect_identical(nrow(art$pred), 2L * nrow(e$data))
  expect_setequal(unique(art$pred$model), c("a", "b"))
  expect_identical(as.vector(table(art$pred$row)), rep(2L, nrow(e$data)))
  expect_identical(names(art$patients), c("row", "group", "age"))
  expect_identical(art$overlap, "none")
  expect_identical(art$time, "iv_dead")
  expect_equal(art$clevel, 0.68268948)
  bytes <- hazard_rds_bytes(path)
  expect_false(any(vapply(e$data$ccfid, function(v) hazard_bytes_hold(bytes, v), logical(1L))))
  lineage <- attr(art, "hvti_provenance")
  expect_identical(sum(grepl("hm.rds$", vapply(lineage$artifacts, `[[`, "", "path"))), 2L)
})

test_that("hs-concordance refuses what would make the comparison meaningless", {
  skip_concordance()
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  e <- estate()
  core <- concordance_core
  bad <- function(..., msg) {
    expect_error(concordance_run(e$root, concordance_choices(e$data, ...), core), msg)
  }
  bad(OVERLAP = NULL, msg = "OVERLAP must be one of")
  bad(MODELS = c(a = "dead-a", a = "dead-b"), msg = "must be unique")
  bad(MODELS = c("dead-a", "dead-b"), msg = "needs a name")
  bad(MODELS = c(a = "dead-a", b = "dead-a"), msg = "resolve to the same file")
  bad(MODELS = c(a = "dead-a"), msg = "have no model in MODELS")
  bad(HORIZON = 1e6, msg = "beyond the last observed time of the model for a")
  bad(CARRY = "ccfid", msg = "may not name a patient identifier")
  bad(CARRY = c("age", "group"), msg = "already has")
  other <- file.path(hvtiRutilities::study_dir("estimates", e$root), "dead-b", "hm.rds")
  bad(MODELS = c(a = "dead-a", b = other), msg = "Set CROSS_STUDY")
  bad(MODELS = c(a = "dead-a", b = gsub("/", "\\", other, fixed = TRUE)), msg = "Set CROSS_STUDY")
  # TIME and EVENT come from the models; a value set here only confirms them.
  bad(TIME = "age", msg = "TIME here \\(age\\) differs from the upstream job's \\(iv_dead\\)")
  bad(EVENT = "other", msg = "EVENT here \\(other\\) differs from the upstream job's \\(dead\\)")
})

test_that("hs-concordance takes TIME and EVENT from the hm models, not from its own settings", {
  skip_concordance()
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  e <- estate()
  # Nothing in the choices names either column: the models' recorded selection does.
  choices <- concordance_choices(e$data)
  expect_false(any(c("TIME", "EVENT") %in% names(choices)))
  env <- concordance_run(e$root, choices, c("tbl-data", "models", "cohort"))
  expect_identical(env$TIME, "iv_dead")
  expect_identical(env$EVENT, "dead")
  # Naming the same columns is a confirmation, and passes.
  expect_no_error(concordance_run(e$root, concordance_choices(e$data, TIME = "iv_dead", EVENT = "dead"),
                                  c("tbl-data", "models", "cohort")))
  # The template declares neither column.
  src <- readLines(hazard_template("hs-concordance"), warn = FALSE)
  expect_true(all(c("TIME <- NULL", "EVENT <- NULL") %in% trimws(sub("#.*$", "", src))))
  expect_false(any(grepl('^(TIME|EVENT)\\s+<- "', src)))
})

test_that("a horizon beyond one model's follow-up names that model alone", {
  skip_concordance()
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  e <- estate()
  env <- concordance_run(e$root, concordance_choices(e$data), c("tbl-data", "models", "cohort"))
  last <- vapply(env$models, function(a) max(a$reported$data$frame$iv_dead), numeric(1L))
  h <- mean(last)
  short <- names(which.min(last))
  err <- tryCatch(concordance_run(e$root, concordance_choices(e$data, HORIZON = h), concordance_core),
                  error = conditionMessage)
  expect_match(err, paste0("model for ", short, " \\("))
  expect_no_match(err, paste0("model for ", setdiff(names(last), short)))
})

test_that("a model no patient received is reported, not refused", {
  skip_concordance()
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  e <- estate()
  choices <- concordance_choices(e$data[e$data$group == "a", ], WHERE = quote(group == "a"))
  env <- concordance_run(e$root, choices, concordance_core)
  expect_setequal(unique(env$pred$model), c("a", "b"))
})

test_that("the decision calls a choice optimal only when the limits separate it", {
  skip_concordance()
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  e <- estate()
  env <- concordance_run(e$root, concordance_choices(e$data), concordance_core)
  n <- nrow(e$data)
  # Patient 1: an exact tie. Patient 2: a near-tie inside the limits.
  # Patient 3: separated. Patient 4: b ineligible, so no choice to make.
  env$pred$fit[env$pred$row %in% 1:4 & env$pred$model == "a"] <- c(0.5, 0.5, 0.9, 0.5)
  env$pred$fit[env$pred$row %in% 1:4 & env$pred$model == "b"] <- c(0.5, 0.5001, 0.2, 0.9)
  env$pred$lower[env$pred$row %in% 1:4] <- env$pred$fit[env$pred$row %in% 1:4] - 0.05
  env$pred$upper[env$pred$row %in% 1:4] <- env$pred$fit[env$pred$row %in% 1:4] + 0.05
  env$d$elig_b <- seq_len(n) != 4L
  before <- env$pred
  # ELIGIBLE is set inside the decision chunk, so the edit is made to its text,
  # as a study author would make it.
  src <- readLines(hazard_template("hs-concordance"), warn = FALSE)
  chunk_of <- function(label) {
    chunk <- src[(match(paste0("#| label: ", label), src) + 1L):length(src)]
    chunk[seq_len(match("```", chunk) - 1L)]
  }
  chunk <- chunk_of("edit-decision")
  edited <- sub("^ELIGIBLE <- list\\(\\)$", 'ELIGIBLE <- list(b = "elig_b")', chunk)
  expect_false(identical(edited, chunk))
  utils::capture.output({
    eval(parse(text = edited), envir = env)
    eval(parse(text = chunk_of("decision")), envir = env)
  })
  dec <- env$decision[1:4, ]
  expect_identical(dec$tie, c(TRUE, FALSE, FALSE, FALSE))
  expect_identical(dec$optimal, rep(NA_character_, 4L) |> replace(3L, "a"))
  expect_identical(dec$best[2:4], c("b", "a", "a"))
  expect_identical(env$pred, before)
  # Every patient is in the best-treatment table, ties and non-choices included.
  expect_identical(sum(env$best_tbl), n)
  expect_equal(unname(colSums(env$best_tbl)[c("(tie)", "(no choice)")]), c(1, 0))
  expect_error({
    eval(parse(text = sub("^ELIGIBLE <- list\\(\\)$", 'ELIGIBLE <- list("elig_b")', chunk)), envir = env)
    eval(parse(text = chunk_of("decision")), envir = env)
  }, "unique name")
})

test_that("deleting the decision leaves a job that saves", {
  skip_concordance()
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  e <- concordance_copy(estate())
  concordance_run(e$root, concordance_choices(e$data), c(concordance_core, "save"))
  art <- readRDS(file.path(hvtiRutilities::study_dir("estimates", e$root), "dead-ab", "hs-concordance.rds"))
  expect_null(art$decision)
  expect_identical(nrow(art$pred), 2L * nrow(e$data))
})

test_that("a group model without a variance matrix stops the predictions, naming the model (#227)", {
  skip_concordance()
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  e <- concordance_copy(estate())
  # Model b as a fit that lost its variance matrix: predict() then returns a
  # finite fit with every limit NA.
  path <- file.path(hvtiRutilities::study_dir("estimates", e$root), "dead-b", "hm.rds")
  art <- readRDS(path)
  art$reported$fit$vcov <- NULL
  saveRDS(art, path)
  err <- tryCatch(concordance_run(e$root, concordance_choices(e$data)), error = conditionMessage)
  expect_match(err, "No confidence limits from the model(s) for b:", fixed = TRUE)
  expect_match(err, "no usable variance matrix", fixed = TRUE)
  expect_no_match(err, "missing value where TRUE/FALSE needed", fixed = TRUE)
})

test_that("limits undefined at a survival of 1 are not reported as a missing variance matrix", {
  skip_concordance()
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  e <- estate()
  # At a horizon of 1e-300 every prediction rounds to survival 1, where the logit limits are
  # undefined, though both fits keep their variance matrices. Raised by Codex
  # on #251: the first guard blamed the variance matrix for this too.
  err <- tryCatch(concordance_run(e$root, concordance_choices(e$data, HORIZON = 1e-300)), error = conditionMessage)
  expect_match(err, "have a standard error but no confidence limits", fixed = TRUE)
  expect_match(err, "exactly 0 or 1", fixed = TRUE)
  expect_no_match(err, "variance matrix", fixed = TRUE)
})

test_that("observed against expected counts each patient's own follow-up, and marks in-sample cells", {
  skip_concordance()
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  e <- estate()
  env <- concordance_run(e$root, concordance_choices(e$data), concordance_core)
  oe <- env$oe
  # TAU defaults to the shorter of the two models' follow-up.
  last <- vapply(env$models, function(a) max(a$reported$data$frame$iv_dead), numeric(1L))
  expect_identical(env$TAU, min(last))
  # Each cell's E is the model's cumulative hazard at each patient's own time, cut at TAU,
  # computed here apart from the template. A job predicting at HORIZON or at TAU fails this.
  # The job's own rows: the built data is read back, so its times are compared with TAU as read.
  d <- env$d
  t_oe <- pmin(d$iv_dead, env$TAU)
  for (m in c("a", "b")) {
    nd <- env$dd[, env$covariates[[m]], drop = FALSE]
    nd$time <- t_oe
    h <- predict(env$models[[m]]$reported, newdata = nd, type = "cumulative_hazard")
    for (g in c("a", "b")) {
      rows <- d$group == g
      cell <- oe[oe$model == m & oe$group == g, ]
      expect_equal(cell$expected, sum(h[rows]), info = paste(m, g))
      expect_identical(cell$observed, sum(d$dead[rows] == 1 & d$iv_dead[rows] <= env$TAU), info = paste(m, g))
      expect_identical(cell$fit_overlap, if (m == g) "in-sample" else "external", info = paste(m, g))
    }
  }
  # Conservation of events: under its own model, a group whose follow-up TAU does not cut
  # has O/E = 1, and the in-sample cell carries no test.
  uncut <- names(which.min(last))
  expect_equal(oe$ratio[oe$model == uncut & oe$group == uncut], 1, tolerance = 1e-4)
  expect_true(all(is.na(oe$p[oe$fit_overlap == "in-sample"])))
  expect_true(all(is.finite(oe$p[oe$fit_overlap == "external"])))
  expect_identical(unique(oe$level), 0.95)
  # The level is a choice, and the saved file carries it with TAU.
  e2 <- concordance_copy(e)
  concordance_run(e2$root, concordance_choices(e2$data, TEST_LEVEL = 0.68268948), c(concordance_core, "save"))
  art <- readRDS(file.path(hvtiRutilities::study_dir("estimates", e2$root), "dead-ab", "hs-concordance.rds"))
  expect_identical(unique(art$oe$level), 0.68268948)
  expect_identical(art$test_level, 0.68268948)
  expect_identical(art$tau, env$TAU)
  expect_error(concordance_run(e$root, concordance_choices(e$data, TAU = max(last)), concordance_core),
               "TAU \\(.*\\) is beyond the last observed time of the model for")
  # A model read by path is never called in-sample, even on the same patients: it is
  # another study's by declaration, so its cell keeps its test.
  path_a <- file.path(hvtiRutilities::study_dir("estimates", e$root), "dead-a", "hm.rds")
  env <- concordance_run(e$root, concordance_choices(e$data, MODELS = c(a = path_a, b = "dead-b"), CROSS_STUDY = TRUE),
                         concordance_core)
  cell <- env$oe[env$oe$model == "a" & env$oe$group == "a", ]
  expect_identical(cell$fit_overlap, "partial")
  expect_identical(cell$in_fit, cell$n)
  expect_true(is.finite(cell$p))
})

test_that("with one model, GROUP may be NULL and the whole cohort is scored through it", {
  skip_concordance()
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  e <- estate()
  env <- concordance_run(e$root, concordance_choices(e$data, MODELS = c(a = "dead-a"), GROUP = NULL), concordance_core)
  expect_identical(nrow(env$oe), 1L)
  expect_identical(env$oe$n, nrow(e$data))
  # Group a's patients are in the fit and group b's are not.
  expect_identical(env$oe$fit_overlap, "partial")
  expect_identical(env$oe$in_fit, sum(e$data$group == "a"))
  expect_error(concordance_run(e$root, concordance_choices(e$data, GROUP = NULL), concordance_core),
               "may be NULL only when MODELS has one entry")
})

test_that("the prediction table shows the mean beside the median and the 15th and 85th percentiles", {
  skip_concordance()
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  e <- estate()
  env <- concordance_run(e$root, concordance_choices(e$data), concordance_core)
  tbl <- env$summary_tbl
  expect_identical(names(tbl), c("model", "group", "n", "mean", "q15", "median", "q85"))
  fit <- env$pred$fit[env$pred$model == "a" & env$pred$group == "b"]
  row <- tbl[tbl$model == "a" & tbl$group == "b", ]
  expect_equal(row$mean, mean(fit))
  expect_equal(c(row$q15, row$q85), unname(stats::quantile(fit, c(0.15, 0.85))))
})

test_that("the average expected curve and the spaghetti draw with no warning, under either band", {
  skip_on_cran()
  skip_concordance()
  skip_if_not_installed("ragg")
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  e <- concordance_copy(estate())
  for (band in c("limits_mean", "spread")) {
    env <- concordance_run(e$root, concordance_choices(e$data, BAND = band), concordance_core)
    warned <- character(0)
    withCallingHandlers(
      utils::capture.output(hazard_run("hs-concordance", c("curves", "fig-expected-km", "fig-spaghetti"), env)),
      warning = function(w) {
        warned <<- c(warned, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    )
    expect_identical(warned, character(0), info = band)
    for (name in c("hs-concordance-expected-km", "hs-concordance-spaghetti")) {
      expect_true(all(file.exists(env$set_path("graphs", paste0(name, c(".png", ".pdf", ".tiff"))))), info = name)
    }
    expect_match(env$.cap_km, if (band == "spread") "not a confidence interval" else "upper bound", info = band)
    # At HORIZON each curve is the mean of the predictions table's patients.
    at <- env$curves$time == env$HORIZON
    expect_identical(sum(at), 4L)
    expect_identical(grDevices::dev.cur(), c("null device" = 1L))
  }
  # The spaghetti thins to SPAGHETTI_N patients per panel.
  env <- concordance_run(e$root, concordance_choices(e$data, BAND = "spread", SPAGHETTI_N = 10), concordance_core)
  utils::capture.output(hazard_run("hs-concordance", "curves", env))
  expect_true(all(tapply(env$.lines$patient, env$.lines$panel, function(p) length(unique(p))) == 10L))
})

test_that("the average curve must be the mean of the patients' predictions, and the band must be named", {
  skip_concordance()
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  e <- estate()
  env <- concordance_run(e$root, concordance_choices(e$data), concordance_core)
  expect_error(utils::capture.output(hazard_run("hs-concordance", "curves", env)), "BAND must be one of")
  env$BAND <- "spread"
  # A predictions table that no longer matches the curve stops the chunk.
  env$pred$fit[1L] <- env$pred$fit[1L] / 2
  expect_error(utils::capture.output(hazard_run("hs-concordance", "curves", env)), "all.equal")
})
