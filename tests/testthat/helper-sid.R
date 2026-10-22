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
