# The vp templates are run chunk by chunk through rf_run() (helper-rf.R), whose
# chunk runner is not specific to random forests.

# A survival cohort with a planted signal: the hazard rises with `xs` and with
# level "b" of `fs`; `x1`, `x2` and `g1` are null. Seeded, so a test sees the
# same patients every run.
vp_data <- function(n = 200L, seed = 20261021L) {
  withr::with_seed(seed, {
    d <- data.frame(
      xs = stats::rnorm(n), fs = factor(sample(c("a", "b"), n, replace = TRUE)),
      x1 = stats::rnorm(n), x2 = stats::rnorm(n), g1 = factor(sample(c("u", "v", "w"), n, replace = TRUE))
    )
    event_time <- stats::rexp(n, exp(1.2 * d$xs + 1.2 * (d$fs == "b")))
    censor <- stats::rexp(n, 0.3)
  })
  d$time <- pmin(event_time, censor)
  d$event <- as.integer(event_time <= censor)
  d
}

# Every choice a vp-fit test sets. RESPONSE = NULL is kept as an element: the
# chunks read it, and list2env() assigns a NULL element.
vp_choices <- list(
  TIME = "time", EVENT = "event", RESPONSE = NULL,
  PREDICTORS = c("xs", "fs", "x1", "x2", "g1"),
  NTREE = 50, REPEATS = 2, SEED = 1, SAVE_FIGURES = FALSE
)

# vp_choices with the three outcome choices replaced. utils::modifyList() would
# DROP an element set to NULL, so the outcome is rebuilt with c(), which keeps it.
vp_outcome <- function(choices, TIME, EVENT, RESPONSE) {  # nolint: object_name_linter.
  c(choices[setdiff(names(choices), c("TIME", "EVENT", "RESPONSE"))],
    list(TIME = TIME, EVENT = EVENT, RESPONSE = RESPONSE))
}

# Every chunk of vp-fit, in order. Tasks 4 and 5 extend it.
vp_fit_labels <- c("setup", "edit-study-choices", "tbl-data", "tbl-missing", "noise", "judge", "fit",
                   "tbl-coverage", "tbl-funnel", "fig-coverage", "fig-varpro", "tbl-stability", "save")

# vp-fit run end to end in a throwaway study.
vp_fit_first <- function(data = vp_data(), choices = vp_choices, .local_envir = parent.frame()) {
  env <- rf_env(data, .local_envir)  # nolint: object_usage_linter.
  rf_run("vp", "fit", vp_fit_labels, env, choices)  # nolint: object_usage_linter.
  env
}

# The dependence helpers, parsed out of the installed vp-dependence and run in
# an environment of their own, so they are tested without a fit.
vpd_helpers_env <- function() {
  env <- new.env(parent = globalenv())
  src <- readLines(template_path("vp", "dependence"), warn = FALSE)
  eval(parse(text = rf_chunk(src, "dependence-helpers")), envir = env)  # nolint: object_usage_linter.
  env
}

# A cohort with one planted dependence: c follows a. b, x2 and the two-level
# fs are null. No three-level factor: its levels would dominate the release
# rows (spec section 8).
vpd_data <- function(n = 200L, seed = 20261022L) {
  withr::with_seed(seed, {
    d <- data.frame(a = stats::rnorm(n), b = stats::rnorm(n), x2 = stats::rnorm(n),
                    fs = factor(sample(c("a", "b"), n, replace = TRUE)))
    d$c <- d$a + stats::rnorm(n, 0, 0.3)
  })
  d
}

# OUTCOME and ORDINAL are NULL elements on purpose: the chunks read them, and
# list2env() assigns a NULL element.
vpd_choices <- list(VARIABLES = c("a", "b", "x2", "fs", "c"), OUTCOME = NULL, ORDINAL = NULL,
                    NOISE_N = 4, NTREE = 30, REPEATS = 0, SEED = 1, SAVE_FIGURES = FALSE)

# Every chunk of vp-dependence, in order.
vpd_labels <- c("setup", "edit-study-choices", "tbl-data", "tbl-missing", "noise", "dependence-helpers",
                "fit", "matrix", "fig-graph", "fig-heatmap", "tbl-stability", "tbl-stability-signal", "save")

# vp-dependence run end to end in a throwaway study.
vpd_first <- function(data = vpd_data(), choices = vpd_choices, .local_envir = parent.frame()) {
  env <- rf_env(data, .local_envir)  # nolint: object_usage_linter.
  rf_run("vp", "dependence", vpd_labels, env, choices)  # nolint: object_usage_linter.
  env
}

# Every chunk of vp-individual, in order.
vpi_labels <- c("setup", "edit-study-choices", "screen", "tbl-data", "individual-helpers", "gradients",
                "tbl-coverage", "fig-beeswarm", "gradient-pages", "save")

# The individual helpers, parsed out of the installed vp-individual.
vpi_helpers_env <- function() {
  env <- new.env(parent = globalenv())
  src <- readLines(template_path("vp", "individual"), warn = FALSE)
  eval(parse(text = rf_chunk(src, "individual-helpers")), envir = env)  # nolint: object_usage_linter.
  env
}

# vp-individual run in the set of a vp-fit already run in `fit`.
vpi_run <- function(fit, choices) {
  env <- new.env(parent = globalenv())
  env$.root <- fit$.root
  rf_run("vp", "individual", vpi_labels, env, choices)  # nolint: object_usage_linter.
}

# The vp-dependence and vp-individual setup chunks need varPro 3.3.0, above the
# 3.2.0 rf_pkg_floors records for vp-fit and vp-explain, so their tests skip
# below it rather than fail at the guard.
vp33_skip_unless_stack <- function(pkgs) {
  testthat::skip_if_not_installed("varPro", minimum_version = "3.3.0")
  rf_skip_unless_stack(pkgs)  # nolint: object_usage_linter.
}
