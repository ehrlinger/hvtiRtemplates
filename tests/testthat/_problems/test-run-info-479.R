# Extracted from test-run-info.R:479

# prequel ----------------------------------------------------------------------
run_fixture <- function(lines = "A finished job.", .local_envir = parent.frame()) {
  fx <- setup_fixture(lines, .local_envir = .local_envir)  # nolint: object_usage_linter.
  env <- new.env(parent = globalenv())
  r <- run_setup(env = env)  # nolint: object_usage_linter.
  list(root = fx$root, env = env, run = r$job$run, out = r$out, cfg = hvtiRutilities::study_config(start = fx$root))
}
run_facts <- function(rf, data = list(), artifacts = list()) {
  hvtiRtemplates:::.run_facts(rf$run, data = data, artifacts = artifacts, cfg = rf$cfg, envir = rf$env)
}
box_of <- function(lines, .local_envir = parent.frame()) {
  fx <- setup_fixture(lines, .local_envir = .local_envir)  # nolint: object_usage_linter.
  r <- run_setup()  # nolint: object_usage_linter.
  list(box = grep("^\\*\\*final\\*\\*", r$out, value = TRUE), root = fx$root, job = fx$job)
}
skip_unless_quarto <- function() {
  testthat::skip_on_cran()
  testthat::skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
  testthat::skip_if_not_installed("quarto")
  testthat::skip_if_not(quarto::quarto_available())
}
report_html <- function(job) {
  paste(readLines(sub("[.]qmd$", ".html", job), warn = FALSE), collapse = "\n")
}

# test -------------------------------------------------------------------------
skip_unless_quarto()
skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
s <- lp_fixture()
quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = TRUE)
