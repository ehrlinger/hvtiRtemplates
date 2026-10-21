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
