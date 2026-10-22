# The sid templates are run chunk by chunk through rf_run() (helper-rf.R),
# whose chunk runner is not specific to random forests.

# The helpers in sid-clusters' `sid-helpers` chunk, evaluated alone, so they
# can be tested on hand-built inputs with no fit.
sid_helpers_env <- function() {
  src <- readLines(template_path("sid", "clusters"), warn = FALSE)
  env <- new.env(parent = globalenv())
  eval(parse(text = rf_chunk(src, "sid-helpers")), envir = env)  # nolint: object_usage_linter.
  env
}

# Three well-separated groups of 50 on four continuous variables and one
# factor, with a few values missing so the imputation has work to do. Seeded,
# so a test sees the same patients every run. `truth` is the planted group;
# it is not a clustering variable.
sid_data <- function(n_per = 50L, seed = 20261022L) {
  withr::with_seed(seed, {
    truth <- rep(1:3, each = n_per)
    centre <- c(-3, 0, 3)[truth]
    d <- data.frame(
      a = stats::rnorm(3 * n_per, centre), b = stats::rnorm(3 * n_per, -centre),
      c = stats::rnorm(3 * n_per, centre / 2), e = stats::rnorm(3 * n_per),
      f = factor(ifelse(truth == 3, "y", sample(c("x", "y"), 3 * n_per, replace = TRUE, prob = c(0.8, 0.2))))
    )
    d$a[sample(nrow(d), 5)] <- NA
    d$f[sample(nrow(d), 3)] <- NA
  })
  d$truth <- truth
  d
}

# NTREE = 500: at 50 trees the planted groups were not recovered (normalized
# measure 0.92, measured in review); at 200 it was 0.12. Each fit takes well
# under a second on 150 rows.
sid_fit_choices <- list(
  VARS = c("a", "b", "c", "e", "f"), MAX_MISSING = 0.4, NTREE = 500, SID_REDUCE = FALSE,
  IMPUTE = "mice", M = 1, MICE_MAXIT = 5, SEED = 1, REFIT = FALSE
)

# Every chunk of sid-fit, in order.
sid_fit_labels <- c("setup", "edit-study-choices", "tbl-data", "tbl-missing", "impute", "fit", "tbl-used", "save")

# sid-fit run end to end in a throwaway study.
sid_fit_first <- function(data = sid_data(), choices = sid_fit_choices, .local_envir = parent.frame()) {
  env <- rf_env(data, .local_envir)  # nolint: object_usage_linter.
  rf_run("sid", "fit", sid_fit_labels, env, choices)  # nolint: object_usage_linter.
  env
}
