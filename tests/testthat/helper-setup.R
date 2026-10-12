# Shared by the tests that run a template's chunks by label. Every template has
# one `setup` chunk (design: dev/specs/2026-10-12-setup-and-run-info-design.md),
# where it had `setup`, `guard-edits`, `guard-partial` and `set`. The helpers
# that run chunks by label map the old `set` to `setup` through
# setup_label() and run it through eval_setup_chunk(), so the tests that name
# "set" are not edited one by one.

setup_label <- function(label) if (identical(label, "set")) "setup" else label

# Evaluate a template's setup chunk in `env` the way a test needs it. A render
# supplies the study root through the file being rendered; a test supplies it
# as env$.root, so the chunk runs from there, and the root the test chose is
# kept afterward (a tempdir() spelling can differ from the one the chunk
# resolves). Its library() calls come out, so a test attaches nothing for the
# rest of the run; the version floors and the setup itself run as shipped. The
# top box it prints is the report's, so it is captured here.
eval_setup_chunk <- function(code, env) {
  root <- get0(".root", envir = env, inherits = FALSE)
  code <- code[!grepl("^\\s*library\\(", code)]
  dir <- if (is.null(root)) getwd() else root
  utils::capture.output(withr::with_dir(dir, eval(parse(text = code), envir = env)))
  if (!is.null(root)) assign(".root", root, envir = env)
  invisible(env)
}

# A study with a registered dataset and an R/ folder, and a job file in it. The
# job is named for the template a real one would carry. knitr::current_input()
# is mocked to name it, as a render does, and the working directory is the job's.
setup_fixture <- function(lines = "A finished job.", .local_envir = parent.frame()) {
  root <- hazard_study(.local_envir = .local_envir)
  dir.create(file.path(root, "R"))
  writeLines("study_helper <- function() \"from the study\"", file.path(root, "R", "helpers.R"))
  dir <- hvtiRutilities::study_dir("descriptive", root)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  job <- file.path(dir, "dc.general.cohort.eda.qmd")
  writeLines(lines, job)
  withr::local_dir(dir, .local_envir = .local_envir)
  testthat::local_mocked_bindings(
    current_input = function(dir = FALSE) if (isTRUE(dir)) job else basename(job),
    .package = "knitr", .env = .local_envir
  )
  withr::local_envvar(HVTI_TEMPLATE_STRICT = NA, .local_envir = .local_envir)
  list(root = root, job = job)
}

# .job_setup() as a setup chunk calls it: the console output is the report's.
run_setup <- function(subject = "cohort", type = "eda", env = new.env(parent = globalenv())) {
  out <- utils::capture.output(job <- hvtiRtemplates:::.job_setup(subject, type, envir = env))
  # What the chunk's last line prints, the notice, is the report's.
  list(job = job, out = c(out, strsplit(as.character(job$notice), "\n", fixed = TRUE)[[1L]]), env = env)
}

edit_marker <- function(text = "choose the endpoint") paste0("# ", paste0("ED", "IT", ":"), " ", text)
