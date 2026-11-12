# mm: the mixed-model template. lm_chunk() in helper-lm.R is generic over a template's source.

# A synthetic longitudinal cohort: n patients with 2 to 6 measurements each, a log-normal response
# whose log has a random intercept, and a within-patient correlation of rho on the log scale.
mm_data <- function(n = 200L, rho = 0.5) {
  withr::local_seed(42)
  per <- sample(2:6, n, replace = TRUE)
  id <- rep(seq_len(n), per)
  time <- unlist(lapply(per, function(k) sort(stats::runif(k, 0, 10))))
  age <- rep(stats::rnorm(n, 60, 10), per)
  female <- rep(rep(0:1, length.out = n), per)
  total <- 0.04
  b <- rep(stats::rnorm(n, 0, sqrt(rho * total)), per)
  e <- stats::rnorm(length(id), 0, sqrt((1 - rho) * total))
  y <- exp(3 + 0.2 * log(time + 1) + 0.01 * (age - 60) - 0.1 * female + b + e)
  data.frame(ccfid = id, id = id, time = time, age = age, female = female, y = y)
}

# The functions the template's mm-helpers chunk defines, in an environment of their own.
mm_helpers <- function() {
  src <- readLines(template_path("mm"), warn = FALSE)
  env <- new.env(parent = globalenv())
  eval(parse(text = lm_chunk(src, "mm-helpers")), envir = env)  # nolint: object_usage_linter.
  env
}

# Evaluate the template's chunks by label into env, setting `choices` after the study choices,
# as rm_run() does for the rm templates.
mm_run <- function(labels, env, choices = list()) {
  src <- readLines(template_path("mm"), warn = FALSE)
  for (label in unique(vapply(labels, setup_label, ""))) {  # nolint: object_usage_linter.
    code <- lm_chunk(src, label)  # nolint: object_usage_linter.
    if (identical(label, "setup")) {
      eval_setup_chunk(code, env)  # nolint: object_usage_linter.
    } else {
      suppressMessages(eval(parse(text = code), envir = env))
    }
    if (identical(label, "edit-study-choices")) {
      list2env(choices, envir = env)
      if (!"tbl-data" %in% labels) {
        if (!exists(".id", envir = env, inherits = FALSE)) env$.id <- env$ID
        env$RESPONSE_SCALE <- hvtiRtemplates:::.response_scale(env$RESPONSE_SCALE)
        env$.response <- hvtiRtemplates:::.response_term(env$d, env$OUTCOME, env$RESPONSE_SCALE)
        if (!exists("job_data", envir = env, inherits = FALSE)) env$job_data <- list()
      }
    }
  }
  invisible(env)
}
