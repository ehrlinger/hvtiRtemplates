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
# computed -- unless the study's default dataset carries a registered file. A
# real study always has one by the time any job runs, so
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
      root, built = "cohort.rds", population = "RF smoke"
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

# Version floors verified end-to-end on 2026-09-19. Keyed by package name so
# a package a template does not use is never looked up here.
rf_pkg_floors <- c(
  randomForestSRC  = "3.7.0",
  varPro           = "3.2.0",
  ggRandomForests  = "4.0.0",
  hvtiRutilities   = "1.3.0"
)

# Parses the `library(...)` calls out of a template's own `setup` chunk, so
# a test attaches exactly what the template attaches -- never a fixed stack
# borrowed from whichever template was written first. This is what makes a
# template that forgets a `library()` call in its own setup fail ITS OWN
# tests instead of riding on a package a sibling test happened to attach
# earlier in the session -- the coverage hole AGENTS.md records biting
# hvtiRlifetables. It is also what keeps a fit template (no varPro) from
# skipping on a varPro problem it does not have.
rf_template_packages <- function(prefix, qualifier) {
  src <- readLines(template_path(prefix, qualifier), warn = FALSE)
  setup <- rf_chunk(src, "setup")
  calls <- regmatches(setup, regexpr("library\\([[:alnum:].]+\\)", setup))
  calls <- calls[nzchar(calls)]
  sub("^library\\(([[:alnum:].]+)\\)$", "\\1", calls)
}

# Skips only on the packages `pkgs` names, at the floor recorded above when
# one is recorded, then attaches exactly those packages.
rf_skip_unless_stack <- function(pkgs) {
  for (pkg in pkgs) {
    # Single-bracket indexing on this named character vector returns NA for
    # an absent name; `[[` throws "subscript out of bounds" instead, which
    # made the is.null() fallback below unreachable.
    floor <- rf_pkg_floors[pkg]
    if (is.na(floor)) {
      testthat::skip_if_not_installed(pkg)
    } else {
      testthat::skip_if_not_installed(pkg, minimum_version = floor)
    }
  }
  suppressPackageStartupMessages(
    for (pkg in pkgs) library(pkg, character.only = TRUE)
  )
}

# A fresh environment whose read_built() returns `data` instead of reading a
# registered dataset, rooted in a throwaway study.
rf_env <- function(data, .local_envir = parent.frame()) {
  env <- new.env(parent = globalenv())
  env$.root <- rf_study(.local_envir)
  env$read_built <- function(...) data
  env
}

# An explain job needs a fit in the same set first; this runs one. Defined
# here rather than in test-rf-templates.R so it resolves rf_env/rf_run in the
# SAME file: object_usage_linter's codetools check only runs on `function(...)`
# literals (not on a block passed to test_that()), and it resolves symbols
# from the file's own top-level bindings, not across test files.
rf_fit_first <- function(prefix, data, choices, .local_envir = parent.frame()) {
  env <- rf_env(data, .local_envir)
  rf_run(prefix, "fit", c("set", "study-choices", "read", "fit", "save"), env, choices)
  env
}
