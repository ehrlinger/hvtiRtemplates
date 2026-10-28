# hs-score: each start/stop segment scored with the time-varying hm model at
# its own start, as SAS hs.*.mort_score.tvc does with `years = iv_start` before
# %HAZPRED (#436 item 4). The scores are checked against predict() on the
# original rows, not against anything the job computed.

skip_hs_score <- function(.local_envir = parent.frame()) {
  testthat::skip_on_cran()
  testthat::skip_if_not_installed("TemporalHazard", minimum_version = "1.2.13")
  withr::local_package("TemporalHazard", .local_envir = .local_envir)
  withr::local_package("hvtiRutilities", .local_envir = .local_envir)
}

hs_score_labels <- c("read-upstream", "tbl-data", "cohort", "model", "tbl-score", "save")

# The scaffolded job's lines, as add_job() writes them into the study.
hs_score_scaffold <- function(root) {
  path <- suppressMessages(add_job("hs", subject = "dead_pa", type = "hz", dir = root, qualifier = "score"))
  readLines(path, warn = FALSE)
}

# Run the scaffolded job from `src` on `root`, whose hm.rds is already written.
hs_score_run <- function(root, src, choices = list()) {
  env <- hazard_env(root)  # nolint: object_usage_linter.
  hazard_run("hs-score", c("setup", "edit-study-choices"), env, choices, src = src)  # nolint: object_usage_linter.
  hazard_run("hs-score", hs_score_labels, env, src = src)  # nolint: object_usage_linter.
  env
}

# TRUE when every segment's scores are the model at that segment's start with
# that segment's covariates, predicted here from the original rows.
scores_at_start <- function(score, ids, data, fit) {
  key <- paste(ids, score$iv_start)
  rows <- data[match(key, paste(data$ccfid, data$iv_start)), ]
  nd <- data.frame(x1 = rows$x1, age = rows$age, time = rows$iv_start)
  isTRUE(all.equal(score$scr_haz, 100 * unname(predict(fit, newdata = nd, type = "hazard")), tolerance = 1e-10)) &&
    isTRUE(all.equal(score$scr_mort, 100 * (1 - unname(predict(fit, newdata = nd, type = "survival"))),
                     tolerance = 1e-10))
}

test_that("hs-score scores every segment at its own start, one row per segment, and saves no identifier", {
  skip_hs_score()
  data <- start_stop_data()
  root <- hazard_study(data)
  env <- globalenv()
  before <- ls(env, all.names = TRUE)
  withr::defer(rm(list = setdiff(ls(env, all.names = TRUE), before), envir = env))
  start_stop_hm(root, env, data)
  fit <- env$reported

  src <- hs_score_scaffold(root)
  hs <- hs_score_run(root, src, list(CARRY = "x1"))
  score <- hs$score
  expect_identical(nrow(score), nrow(data))
  expect_identical(max(score$patient), length(unique(data$ccfid)))
  expect_true(any(score$iv_start > 0))
  expect_true(scores_at_start(score, hs$d$ccfid[score$row], data, fit))
  # A segment starting at zero has had no time to die in.
  expect_equal(score$scr_mort[score$iv_start == 0], rep(0, sum(score$iv_start == 0)))
  expect_true(all(score$scr_mort[score$iv_start > 0] > 0))
  expect_identical(score$x1, hs$d$x1[score$row])

  path <- file.path(hvtiRutilities::study_dir("estimates", root), "dead_pa-hz", "hs-score.rds")
  art <- readRDS(path)
  expect_identical(art$score, score)
  expect_identical(art$start, "iv_start")
  expect_identical(attr(art, "hvti_provenance")$analysis$time$variable, "iv_dead")
  bytes <- hazard_rds_bytes(path)
  expect_false(any(vapply(unique(data$ccfid), function(v) hazard_bytes_hold(bytes, v), logical(1L))))

  # The mutant: scored at each segment's stop instead. The check above must fail on it.
  at <- grep("^nd\\$time <- d\\[\\[START\\]\\]$", src)
  expect_length(at, 1L)
  mutant <- src
  mutant[[at]] <- "nd$time <- d[[TIME]]"
  wrong <- hs_score_run(root, mutant)$score
  expect_false(scores_at_start(wrong, hs$d$ccfid[wrong$row], data, fit))

  # An early phase shaped as the HSICH model's (nu = -1, m = 0, fixed) scores
  # the first segments, which start at zero, with a finite hazard: SAS writes a
  # non-missing _hazard on every row there. The scoring chunk runs on that fit.
  phases <- list(early = TemporalHazard::hzr_phase("cdf", t_half = 0.5, nu = -1, m = 0, fixed = c("nu", "m"),
                                                   formula = ~ x1),
                 late = TemporalHazard::hzr_phase("constant", formula = ~ x1 + age))
  early <- suppressWarnings(TemporalHazard::hazard(
    survival::Surv(iv_start, iv_dead, dead) ~ 1, data = data, dist = "multiphase", phases = phases,
    theta = c(log(0.3), log(0.5), -1, 0, 0, log(0.1), 0, 0), fit = TRUE, control = list(n_starts = 1, maxit = 2000)
  ))
  hs$fit <- early
  hazard_run("hs-score", "tbl-score", hs, src = src)  # nolint: object_usage_linter.
  first <- hs$score$iv_start == 0
  expect_true(all(is.finite(hs$score$scr_haz[first])))
  expect_true(all(hs$score$scr_haz[first] > 0))
  expect_equal(hs$score$scr_mort[first], rep(0, sum(first)))
  expect_true(scores_at_start(hs$score, hs$d$ccfid[hs$score$row], data, early))

  # CARRY may not save the identifier.
  expect_error(hs_score_run(root, src, list(CARRY = "ccfid")), "CARRY may not name a patient identifier: ccfid")
})

test_that("hs-score stops on a model fitted with one row per patient", {
  root <- hazard_study()
  hazard_upstream(root, hazard_lineage(root))
  src <- hs_score_scaffold(root)
  env <- hazard_env(root)  # nolint: object_usage_linter.
  hazard_run("hs-score", c("setup", "edit-study-choices"), env, src = src)
  expect_error(hazard_run("hs-score", "read-upstream", env, src = src), "one row per patient.*use hs-setup")
})
