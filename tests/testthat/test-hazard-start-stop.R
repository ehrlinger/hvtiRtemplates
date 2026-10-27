# The start/stop response, SAS `lcensor <start>; time <stop>; event <e>;`
# (#436). hz fits Surv(START, TIME, EVENT) when START is set, the selection it
# saves carries the start, and hm builds the same response from it. Each way
# of losing the start stops: a KEY that collapses the segments, a downstream
# formula without it, a bootstrap of rows, and a prediction with no rule yet.

# The templates attach these in their setup chunk, which the tests run without attaching.
skip_start_stop <- function(.local_envir = parent.frame()) {
  testthat::skip_on_cran()
  testthat::skip_if_not_installed("TemporalHazard", minimum_version = "1.2.8")
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
  hm_labels <- c("read-upstream", "tbl-data", "tbl-cohort", "tbl-audit", "tbl-phases", "edit-fit")
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

test_that("a start/stop bootstrap stops, naming TemporalHazard#667, and other responses pass", {
  skip_start_stop()
  stop_row <- hvtiRtemplates:::.stop_row_bootstrap
  entry <- hvtiRtemplates:::.has_entry_times
  data <- start_stop_data(60L)
  fit <- function(f, d) {
    suppressWarnings(TemporalHazard::hazard(f, data = d, dist = "weibull", theta = c(1, 1), fit = TRUE))
  }
  expect_true(entry(fit(survival::Surv(iv_start, iv_dead, dead) ~ 1, data)))
  expect_false(entry(fit(survival::Surv(iv_dead, dead) ~ 1, data)))
  interval <- data.frame(lo = c(1, 2, 3, 1, 2, 0.5, 2, 3), hi = c(1, NA, 4, 2, NA, 1, 2.5, NA))
  expect_false(entry(fit(survival::Surv(lo, hi, type = "interval2") ~ 1, interval)))
  expect_error(stop_row(TRUE), "TemporalHazard/issues/667")
  expect_true(stop_row(FALSE))
  # The runner checks its base fit before the screen, and the report the rows it screened.
  runner <- readLines(system.file("runners", "bh-runner.R", package = "hvtiRtemplates"), warn = FALSE)
  base_at <- grep("^base <- hazard\\(", runner)
  guard_at <- grep(".stop_row_bootstrap(hvtiRtemplates:::.has_entry_times(base))", runner, fixed = TRUE)
  boot_at <- grep("^bs <- hzr_bootstrap\\(", runner)
  expect_true(length(guard_at) == 1L && base_at < guard_at && guard_at < boot_at)
  report <- readLines(hazard_template("bh"), warn = FALSE)
  expect_length(grep(".stop_row_bootstrap(isTRUE(.sel$rows > .sel$patients))", report, fixed = TRUE), 1L)
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
