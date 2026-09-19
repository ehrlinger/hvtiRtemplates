# The rf templates are run here chunk by chunk, not through Quarto: a render
# needs a study with built data, and CI has neither. Each chunk is parsed out
# of the INSTALLED template by its label and evaluated in one environment, the
# way the hz theta test does, so what runs is the text that ships.

rf_chunk <- function(src, label) {
  # DEVIATION from the brief's verbatim listing: fixed = TRUE grep() matches
  # `label` as a SUBSTRING, so label = "set" also hits the "#| label: setup"
  # line (rfs-fit.qmd has both, per this task's own chunk-label list). Matching
  # the whole trimmed line instead makes "set" and "setup" distinguishable.
  at <- which(trimws(src) == paste0("#| label: ", label))
  if (length(at) != 1L) stop("chunk '", label, "' found ", length(at), " times", call. = FALSE)
  end <- at + which(src[(at + 1L):length(src)] == "```")[1L]
  src[(at + 1L):(end - 1L)]
}

# A throwaway study, so set_path() and study_dir() resolve as they would in a
# real one. study_setup() prints a checklist, which a test does not want.
#
# DEVIATION from the brief's verbatim listing: withr::local_tempdir() creates
# the directory before study_setup() ever sees it, and hvtiRutilities 1.3.0
# refuses an already-existing root, even an empty one, unless adopt = TRUE.
# Added that argument rather than switching to tempfile() (the pattern the
# rest of this test suite uses), so withr still owns cleanup.
#
# DEVIATION, second: hvtiRutilities::cache_fit() (>= 1.3.0) records provenance
# through record_provenance(), which hard-stops -- discarding the fit it just
# computed -- unless the study's default dataset carries a registered file and
# a cohort contract. A real study always has both by the time any job runs, so
# this is not a template gap; it is this smoke fixture skipping a setup step a
# real study never skips. register_data() needs an actual file to read, so one
# is written here -- content is irrelevant, since rf_env() overrides
# read_built() directly and never reads it back.
rf_study <- function(.local_envir = parent.frame()) {
  root <- withr::local_tempdir("rf-study-", .local_envir = .local_envir)
  utils::capture.output(suppressMessages(
    hvtiRutilities::study_setup(root, study = "RF smoke", study_tracker_id = 1L, adopt = TRUE)
  ))
  root <- normalizePath(root)
  saveRDS(data.frame(time = c(1, 2), event = c(1, 0)),
          file.path(hvtiRutilities::study_dir("datasets", root), "cohort.rds"))
  utils::capture.output(suppressMessages(
    hvtiRutilities::register_data(
      root, built = "cohort.rds", event = "event", time = "time", population = "RF smoke"
    )
  ))
  root
}

# Evaluate the chunks `labels` of template (prefix, qualifier) in `env`. After
# `study-choices` runs, `choices` overwrites the template's placeholders, as a
# study author's edits would. `setup` is never run: it resolves the study root
# from the file being rendered, so the caller sets env$.root and attaches the
# packages instead.
rf_run <- function(prefix, qualifier, labels, env, choices = list()) {
  src <- readLines(template_path(prefix, qualifier), warn = FALSE)
  for (label in labels) {
    suppressMessages(eval(parse(text = rf_chunk(src, label)), envir = env))
    if (identical(label, "study-choices")) list2env(choices, envir = env)
  }
  invisible(env)
}

rf_skip_unless_stack <- function() {
  testthat::skip_if_not_installed("randomForestSRC", minimum_version = "3.7.0")
  testthat::skip_if_not_installed("varPro", minimum_version = "3.2.0")
  testthat::skip_if_not_installed("ggRandomForests", minimum_version = "4.0.0")
  testthat::skip_if_not_installed("hvtiRutilities", minimum_version = "1.3.0")
  suppressPackageStartupMessages({
    library(randomForestSRC)
    library(varPro)
    library(ggRandomForests)
    library(hvtiRutilities)
  })
}

# A fresh environment whose read_built() returns `data` instead of reading a
# registered dataset, rooted in a throwaway study.
rf_env <- function(data, .local_envir = parent.frame()) {
  env <- new.env(parent = globalenv())
  env$.root <- rf_study(.local_envir)
  env$read_built <- function(...) data
  env
}
