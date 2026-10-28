# The start/stop response, SAS `lcensor <start>; time <stop>; event <e>;`
# (#436). hz fits Surv(START, TIME, EVENT) when START is set, the selection it
# saves carries the start, and hm builds the same response from it. Each way
# of losing the start stops: a KEY that collapses the segments, a downstream
# formula without it, a bootstrap of rows, and a prediction with no rule yet.

# The templates attach these in their setup chunk, which the tests run without attaching.
skip_start_stop <- function(.local_envir = parent.frame()) {
  testthat::skip_on_cran()
  # 1.2.13: hzr_deciles() subtracts H(start), which hm's calibration needs.
  testthat::skip_if_not_installed("TemporalHazard", minimum_version = "1.2.13")
  withr::local_package("TemporalHazard", .local_envir = .local_envir)
  withr::local_package("hvtiRutilities", .local_envir = .local_envir)
}

hz_control <- list(conserve = TRUE, n_starts = 1, maxit = 2000)

test_that("hz fits Surv(START, TIME, EVENT), equal to a direct hazard() fit and not to one without the start", {
  skip_start_stop()
  data <- start_stop_data()
  expect_gt(nrow(data), length(unique(data$ccfid)))
  env <- hz_fit_run("tbl-convergence", data = data, choices = start_stop_choices)
  expect_identical(deparse(env$surv_formula), "Surv(start, time, status) ~ 1")
  expect_identical(env$cc$n, nrow(data))
  direct <- suppressWarnings(TemporalHazard::hazard(
    survival::Surv(iv_start, iv_dead, dead) ~ 1, data = data, dist = "multiphase",
    phases = env$phases, theta = env$theta0, fit = TRUE, control = hz_control
  ))
  expect_equal(env$fit_det$fit$objective, direct$fit$objective, tolerance = 1e-8)
  expect_equal(unname(env$fit_det$fit$theta), unname(direct$fit$theta), tolerance = 1e-6)
  expect_equal(env$fit_det$data$time_lower, data$iv_start)
  # The start reaches the likelihood: every segment fitted from zero is another model.
  no_start <- suppressWarnings(TemporalHazard::hazard(
    survival::Surv(iv_dead, dead) ~ 1, data = data, dist = "multiphase",
    phases = env$phases, theta = env$theta0, fit = TRUE, control = hz_control
  ))
  expect_gt(abs(env$fit_det$fit$objective - no_start$fit$objective), 1)
})

test_that("hz stops when KEY would collapse the segments, or a segment does not start before it stops", {
  skip_start_stop()
  data <- start_stop_data()
  expect_error(hz_fit_run("tbl-data", data = data, choices = list(START = "iv_start", KEY = "ccfid")),
               "KEY \\(ccfid\\) does not include it")
  # TIME pointed at the stop with no START: the one-row-per-patient read stops
  # rather than fit every segment from zero.
  expect_error(hz_fit_run("tbl-data", data = data, choices = list(KEY = c("ccfid", "iv_start"))),
               "patient")
  bad <- data
  # A patient's last segment, so moving its start to its stop repeats no key.
  last <- !duplicated(bad$ccfid, fromLast = TRUE)
  at <- which(bad$iv_start > 0 & last)[[1L]]
  bad$iv_start[[at]] <- bad$iv_dead[[at]]
  expect_error(hz_fit_run("edit-response", data = bad, choices = start_stop_choices),
               "not before iv_dead on 1")
})

test_that("the start travels in hz's selection, and hm fits Surv(START, TIME, EVENT) with no edit", {
  skip_start_stop()
  data <- start_stop_data()
  root <- hazard_study(data)
  cc <- hvtiRutilities::cohort_counts(data, event = "dead", time = "iv_dead")
  env <- globalenv()
  before <- ls(env, all.names = TRUE)
  withr::defer(rm(list = setdiff(ls(env, all.names = TRUE), before), envir = env))
  list2env(as.list(hazard_env(root), all.names = TRUE), envir = env)
  hm_labels <- c("read-upstream", "tbl-data", "tbl-cohort", "tbl-audit", "tbl-phases", "edit-fit", "edit-reported",
                 "tbl-calibration", "tbl-gof", "save")
  suppressWarnings(utils::capture.output({
    hazard_run("hz", c("set", "edit-study-choices"), env,
               c(list(EXPECTED = list(n = cc$n, n_events = cc$n_events, n_censored = cc$n_censored)),
                 start_stop_choices))
    hazard_run("hz", c("tbl-data", "tbl-cohort", "tbl-phases", "edit-start", "edit-response", "tbl-response-check",
                       "guard", "fit-deterministic", "tbl-convergence", "edit-multistart", "tbl-multistart", "noconserve",
                       "tbl-conservation-binding", "edit-estimates", "tbl-estimates", "fig-fit", "save"), env)
    hazard_run("hm", c("set", "edit-study-choices"), env)
    env$COVARIATES <- list(early = "x1", late = c("x1", "age"))
    hazard_run("hm", hm_labels, env)
  }))
  saved <- readRDS(hazard_set_path(root, "hz.rds"))
  expect_identical(attr(saved, "hvti_provenance")$selection$start, "iv_start")
  expect_identical(env$START, "iv_start")
  expect_identical(deparse(env$form), "Surv(iv_start, iv_dead, dead) ~ 1")
  expect_equal(env$stage1$data$time_lower, data$iv_start)
  # The calibration's expected events are the fitted hazard over each segment,
  # H(stop) - H(start) to the horizon, not H(stop): exposure before entry is not counted.
  h <- function(t) unname(predict(env$reported, newdata = transform(env$dd, time = t), type = "cumulative_hazard"))
  at <- env$dd$iv_start < env$DECILE_TIME
  increments <- h(pmin(env$dd$iv_dead, env$DECILE_TIME)) - h(env$dd$iv_start)
  expect_equal(sum(env$dec$expected), sum(increments[at]), tolerance = 1e-4)
  expect_gt(sum(h(pmin(env$dd$iv_dead, env$DECILE_TIME))[at]) - sum(env$dec$expected), 1)
  # hm.rds carries the start on, and hs-setup stops on it.
  expect_identical(attr(readRDS(hazard_set_path(root, "hm.rds")), "hvti_provenance")$selection$start, "iv_start")
  hs <- hazard_env(root)
  hazard_run("hs-setup", c("set", "edit-study-choices"), hs, list(HORIZONS = c(1, 2), VINTAGE = "table2023"))
  expect_error(hazard_run("hs-setup", "read-upstream", hs), "start/stop rows.*hvtiRtemplates/issues/436")

  # An hm whose response drops the start stops rather than fit from zero.
  src <- readLines(hazard_template("hm"), warn = FALSE)
  at <- grep("^form <- stats::as.formula\\(", src)
  expect_length(at, 1L)
  src[[at]] <- 'form <- stats::as.formula(paste0("Surv(", TIME, ", ", EVENT, ") ~ 1"))'
  expect_error(suppressWarnings(utils::capture.output(hazard_run("hm", "edit-fit", env, src = src))),
               "Surv\\(iv_start, iv_dead, dead\\)")
})

test_that("hp and hs stop on a start/stop fit, naming the open question", {
  root <- hazard_study()
  lineage <- hazard_lineage(root)
  lineage$selection$start <- "iv_start"
  hazard_upstream(root, lineage)
  for (prefix in c("hp", "hs-setup")) {
    expect_error(hazard_downstream(prefix, root), "start/stop rows.*hvtiRtemplates/issues/436", info = prefix)
  }
})

test_that("a downstream response must match the selection's start", {
  check <- hvtiRtemplates:::.check_surv_start
  expect_true(check(Surv(iv_start, iv_dead, dead) ~ 1, "iv_start", "iv_dead", "dead"))
  expect_true(check(Surv(iv_dead, dead) ~ 1, NULL, "iv_dead", "dead"))
  expect_error(check(Surv(iv_dead, dead) ~ 1, "iv_start", "iv_dead", "dead"), "followed from time zero")
  expect_error(check(Surv(iv_start, iv_dead, dead) ~ 1, NULL, "iv_dead", "dead"), "Surv\\(iv_dead, dead\\)")
})

test_that("entry times and repeated patients are told apart from other responses", {
  skip_start_stop()
  entry <- hvtiRtemplates:::.has_entry_times
  data <- start_stop_data(60L)
  fit <- function(f, d) {
    suppressWarnings(TemporalHazard::hazard(f, data = d, dist = "weibull", theta = c(1, 1), fit = TRUE))
  }
  expect_true(entry(fit(survival::Surv(iv_start, iv_dead, dead) ~ 1, data)))
  expect_false(entry(fit(survival::Surv(iv_dead, dead) ~ 1, data)))
  interval <- data.frame(lo = c(1, 2, 3, 1, 2, 0.5, 2, 3), hi = c(1, NA, 4, 2, NA, 1, 2.5, NA))
  expect_false(entry(fit(survival::Surv(lo, hi, type = "interval2") ~ 1, interval)))
  repeats <- hvtiRtemplates:::.repeats_patients
  expect_true(repeats(list(rows = 87L, patients = 30L)))
  expect_false(repeats(list(rows = 30L, patients = 30L)))
  expect_false(repeats(list(rows = 90L, patients = 30L, imputation = "imp")))
  expect_false(repeats(list()))
  # A segmented bag must have resampled patients; one row per patient may resample rows.
  check <- hvtiRtemplates:::.check_bag_resampling
  expect_true(check(TRUE, list(list(resampled = "patients"), list(resampled = "patients"))))
  expect_true(check(FALSE, list(list(resampled = "rows"), list())))
  expect_error(check(TRUE, list(list(resampled = "patients"), list())), "1 of 2 bag file\\(s\\) resampled rows")
  expect_error(check(TRUE, list(list(resampled = "patients")), pooled = TRUE), "one pooled bag")
  expect_true(check(FALSE, list(list(resampled = "rows")), pooled = TRUE))
  # Jobs scaffolded before patient resampling call the old helper by name, in
  # these two forms; a study's copy is not updated with the package.
  old <- hvtiRtemplates:::.stop_row_bootstrap
  expect_true(old(repeats(list(rows = 30L, patients = 30L))))
  expect_true(old(isTRUE(list(rows = 30L, patients = 30L)$rows > 30L)))
  expect_error(old(repeats(list(rows = 87L, patients = 30L))), "TemporalHazard/issues/667")
  conc <- readLines(hazard_template("hs-concordance"), warn = FALSE)
  expect_length(grep(".stop_start_stop_prediction(.rec$start,", conc, fixed = TRUE), 1L)
})

test_that("hz's start settings stop before the read", {
  check <- hvtiRtemplates:::.check_start_settings
  expect_true(check(NULL, "ccfid"))
  expect_true(check("iv_start", c("ccfid", "iv_start")))
  expect_true(check("IV_START", c("ccfid", "iv_start")))
  expect_error(check("iv_start", "ccfid"), "set KEY <- c\\(ID, \"iv_start\"\\)")
  expect_error(check(c("a", "b"), c("a", "b")), "one column name")
  expect_error(check("iv_start", c("ccfid", "iv_start"), join = "labs"), "JOIN has no REDUCE")
})

# The bh runner add_job() writes in `root`, edited as a study author would for
# start/stop rows, run in `env` with hzr_bootstrap() traced to record its `id`.
# `with_start = FALSE` keeps the shipped formula and columns, which leave the start
# out. Returns what hzr_bootstrap() was called with, NULL when it was not.
start_stop_runner <- function(root, env, with_start = TRUE) {
  path <- boot_scaffold("bh", root)  # nolint: object_usage_linter.
  runner <- readLines(path, warn = FALSE)
  # Each edit as text to find and its replacement; the scope's is on two phases.
  edits <- list(c("FINISHED <- FALSE", "FINISHED <- TRUE"), c('POOL <- c("age", "female")', 'POOL <- c("age", "x1")'),
                c("KEY <- ID", 'KEY <- c(ID, "iv_start")'), c("N_BOOT <- 20L", "N_BOOT <- 4L"),
                c("~ age + female", "~ age + x1"))
  if (with_start) {
    edits <- c(edits, list(c('job$data[c("iv_dead", "dead", POOL)]', 'job$data[c("iv_start", "iv_dead", "dead", POOL)]'),
                           c("survival::Surv(iv_dead, dead)", "survival::Surv(iv_start, iv_dead, dead)")))
  }
  for (e in edits) {
    at <- grep(e[[1L]], runner, fixed = TRUE)
    testthat::expect_gte(length(at), 1L)
    runner[at] <- gsub(e[[1L]], e[[2L]], runner[at], fixed = TRUE)
  }
  writeLines(runner, path)
  seen <- new.env()
  # Traced where the runner finds it, on the search path: skip_start_stop() attached it.
  suppressMessages(trace("hzr_bootstrap", where = as.environment("package:TemporalHazard"), print = FALSE,
                         tracer = bquote(assign("id", id, envir = .(seen)))))
  on.exit(suppressMessages(untrace("hzr_bootstrap", where = as.environment("package:TemporalHazard"))), add = TRUE)
  withr::local_dir(root)
  suppressWarnings(suppressMessages(sys.source(path, envir = env)))
  if (exists("id", envir = seen, inherits = FALSE)) list(id = seen$id) else NULL
}

test_that("the bh runner resamples patients on start/stop rows, and its replicates differ", {
  skip_start_stop()
  skip_if_not_installed("TemporalHazard", minimum_version = "1.2.17")
  boot_skip_unless_stack("bh")  # nolint: object_usage_linter.
  data <- start_stop_data(60L)
  root <- hazard_study(data)
  env <- new.env(parent = globalenv())
  called <- start_stop_runner(root, env)
  expect_false(is.null(called))
  # One patient per row, in the rows the fit used: each patient's segments travel together.
  expect_identical(as.numeric(called$id), as.numeric(env$job$data$ccfid))
  expect_gt(length(called$id), length(unique(called$id)))
  bag <- readRDS(file.path(hvtiRutilities::study_dir("estimates", root), "dead_pa-hz", "bh.chunk01.rds"))
  expect_identical(bag$resampled, "patients")
  reps <- bag$boot$replicates
  expect_gt(length(unique(reps$replicate)), 1L)
  first <- reps$estimate[reps$parameter == unique(reps$parameter)[[1L]]]
  expect_gt(stats::sd(first), 0)
  # The report reads the bag; one that resampled rows stops it.
  report <- c("set", "edit-study-choices", "load", "tbl-data")
  settings <- list(EXPECT_BOOT = bag$n_boot, EXPECT_CHUNKS = 1L)
  expect_no_error(boot_report("bh", boot_env(root), report, settings))  # nolint: object_usage_linter.
  set_dir <- file.path(hvtiRutilities::study_dir("estimates", root), "dead_pa-hz")
  bag$resampled <- "rows"
  saveRDS(bag, file.path(set_dir, "bh.chunk01.rds"))
  expect_error(boot_report("bh", boot_env(root), report, settings), "resampled rows")  # nolint: object_usage_linter.
  # A pre-pooled bag keeps only its first chunk's record, so even one that says
  # "patients" cannot show every chunk did: the report wants the chunk files.
  bag$resampled <- "patients"
  saveRDS(bag, file.path(set_dir, "bh.rds"))
  unlink(file.path(set_dir, "bh.chunk01.rds"))
  expect_error(boot_report("bh", boot_env(root), report, settings),  # nolint: object_usage_linter.
               "found one pooled bag rather than the runner's chunk files")
})

test_that("the bh runner stops on start/stop rows fitted without their start, before the screen", {
  skip_start_stop()
  skip_if_not_installed("TemporalHazard", minimum_version = "1.2.17")
  boot_skip_unless_stack("bh")  # nolint: object_usage_linter.
  root <- hazard_study(start_stop_data(60L))
  env <- new.env(parent = globalenv())
  # The shipped formula, Surv(iv_dead, dead), fits every segment from zero.
  expect_error(start_stop_runner(root, env, with_start = FALSE), "base fit has no entry times")
  expect_false(exists("bs", envir = env, inherits = FALSE))
})

test_that("hm refuses start/stop rows on a TemporalHazard whose calibration ignores entry", {
  check <- hvtiRtemplates:::.check_start_engine
  expect_error(check("iv_start", package_version("1.2.12")), "Before 1.2.13 hzr_deciles\\(\\)")
  expect_true(check("iv_start", package_version("1.2.13")))
  expect_true(check(NULL, package_version("1.2.12")))
})
