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
# is written here. It is `data`, which the fit jobs read back through
# read_job_data(); saved as .rds so a factor or a missing value arrives as the
# test wrote it. read_built() lowercases the column names.
rf_study <- function(data = data.frame(ccfid = 1:2, time = c(1, 2), event = c(1, 0)), .local_envir = parent.frame()) {
  root <- withr::local_tempdir("rf-study-", .local_envir = .local_envir)
  utils::capture.output(suppressMessages(
    hvtiRutilities::study_setup(root, study = "RF smoke", study_tracker_id = 1L, adopt = TRUE)
  ))
  root <- normalizePath(root)
  saveRDS(data, file.path(hvtiRutilities::study_dir("datasets", root), "cohort.rds"))
  utils::capture.output(suppressMessages(
    hvtiRutilities::register_data(
      root, built = "cohort.rds", population = "RF smoke"
    )
  ))
  root
}

# Evaluate the chunks `labels` of template (prefix, qualifier) in `env`. After
# `edit-study-choices` runs, `choices` overwrites the template's placeholders, as a
# study author's edits would. `setup` is never run: it resolves the study root
# from the file being rendered, so the caller sets env$.root and attaches the
# packages instead.
rf_run <- function(prefix, qualifier, labels, env, choices = list()) {
  src <- readLines(template_path(prefix, qualifier), warn = FALSE)
  for (label in labels) {
    suppressMessages(eval(parse(text = rf_chunk(src, label)), envir = env))
    if (identical(label, "edit-study-choices")) list2env(choices, envir = env)
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

# A fresh chunk environment rooted in a throwaway study whose built dataset is
# `data`, so the fit's data chunk reads it through read_job_data() as a render
# would. A patient identifier is added when `data` has none, as a built
# dataset always carries one.
rf_env <- function(data, .local_envir = parent.frame()) {
  if (!any(tolower(names(data)) %in% c("ccfid", "mrn", "emrn"))) data$ccfid <- seq_len(nrow(data))
  env <- new.env(parent = globalenv())
  env$.root <- rf_study(data, .local_envir)
  env$.provenance_data <- list()
  env
}

# An explain job needs a fit in the same set first; this runs one. Defined
# here rather than in test-rf-templates.R so it resolves rf_env/rf_run in the
# SAME file: object_usage_linter's codetools check only runs on `function(...)`
# literals (not on a block passed to test_that()), and it resolves symbols
# from the file's own top-level bindings, not across test files.
rf_fit_first <- function(prefix, data, choices, .local_envir = parent.frame()) {
  env <- rf_env(data, .local_envir)
  rf_run(prefix, "fit", c("set", "edit-study-choices", "tbl-data", "fit", "save"), env, choices)
  env
}

# ---- #203: searching a saved forest for patient identifiers --------------------

# One cohort all three forests can be grown on, keyed on MRN and with no ccfid,
# so the job's ID falls back to MRN. `grp` is text, for the factor conversion.
# The MRN has ten digits: it is read as a double, so it can sit in a file as
# text or as eight bytes, either long enough that a forest's own numbers do
# not match it by chance, which a four-byte integer could.
rf_mrn_data <- function(n = 120L, id = "MRN") {
  withr::local_seed(20260930)
  age <- round(stats::runif(n, 20, 85))
  x1 <- stats::rnorm(n)
  death <- stats::rweibull(n, shape = 2, scale = 6 * exp(-0.3 * x1))
  censor <- stats::runif(n, 1, 8)
  d <- data.frame(
    id = 7350000000 + seq_len(n), age = age, x1 = x1,
    grp = sample(c("a", "b", "c"), n, replace = TRUE),
    iv_dead = pmax(pmin(death, censor), 0.01), dead = as.integer(death <= censor),
    los = 3 + 0.05 * age + stats::rnorm(n)
  )
  names(d)[[1L]] <- id
  d
}

# The study choices that grow each forest on rf_mrn_data().
rf_mrn_choices <- function(prefix, ...) {
  outcome <- list(
    rfs = list(TIME = "iv_dead", EVENT = "dead"),
    rfc = list(RESPONSE = "dead", ROC_CLASS = "1"),
    rfr = list(RESPONSE = "los")
  )[[prefix]]
  utils::modifyList(c(outcome, list(PREDICTORS = c("age", "x1", "grp"), NTREE = 25, SEED = 1)), list(...))
}

# Run `code` with `env` put back as it was when `.local_envir` ends: the names
# the chunks create are removed, and a name they replace, such as a `d` or a
# `forest` already in the global environment, gets its value back. The random
# seed is left as the run leaves it when the session already had one.
rf_restore_later <- function(env, .local_envir) {
  before <- as.list(env, all.names = TRUE)
  before$.Random.seed <- NULL
  withr::defer({
    rm(list = setdiff(ls(env, all.names = TRUE), c(names(before), ".Random.seed")), envir = env)
    list2env(before, envir = env)
  }, envir = .local_envir)
}

# Grow and save the `prefix` forest on `data` with every chunk evaluated in
# `env`. A render evaluates its chunks in the global environment, so a test
# passes that. Returns the set's estimates directory and what the data chunk
# printed.
rf_fit_in <- function(prefix, data, env, choices = rf_mrn_choices(prefix), .local_envir = parent.frame()) {
  rf_restore_later(env, .local_envir)
  env$.root <- rf_study(data, .local_envir)
  env$.provenance_data <- list()
  printed <- utils::capture.output(
    rf_run(prefix, "fit", c("set", "edit-study-choices", "tbl-data", "fit", "save"), env, choices)
  )
  list(dir = env$CACHE_DIR, printed = printed, job_data = env$job_data, forest = env$forest, root = env$.root)
}

# Run every chunk of the `prefix` explain job in `env`, on the forest the fit
# saved in the study at `root`. Returns the names of the files it wrote.
rf_explain_in <- function(prefix, root, env, .local_envir = parent.frame()) {
  rf_restore_later(env, .local_envir)
  env$.root <- root
  choices <- c(list(TOP_K = 2, SEED = 1), if (identical(prefix, "rfs")) list(TIMES = c(1, 3)))
  labels <- c("set", "edit-study-choices", "forest", "tbl-data", "fig-importance", "tbl-importance", "select", "fig-varpro",
              "fig-dependence-marginal", "fig-dependence-partial", "fig-dependence-varpro")
  # VarPro keeps only the variables it selects, so a top variable by VIMP can be
  # absent from its partial, and it says so. That one notice is about the
  # explanation, not the files; any other warning still reaches the summary.
  withCallingHandlers(
    utils::capture.output(rf_run(prefix, "explain", labels, env, choices)),
    warning = function(w) {
      if (grepl("^partialpro\\(\\): skipping xvar.names not found in object\\$xvar.names", conditionMessage(w))) {
        invokeRestart("muffleWarning")
      }
    }
  )
  setdiff(list.files(env$CACHE_DIR), paste0(prefix, c(".rds", "-forest.rds", "-forest.provenance.json")))
}

# TRUE when `bytes` hold `value` as text or as R's big-endian double encoding.
rf_bytes_hold <- function(bytes, value) {
  patterns <- list(charToRaw(format(value, scientific = FALSE)), writeBin(as.double(value), raw(), endian = "big"))
  any(vapply(patterns, function(p) length(grepRaw(p, bytes, fixed = TRUE)) > 0L, logical(1L)))
}

# The bytes of a saved file, decompressed when it is an .rds. Read to the end
# in pieces: a fixed cap would let an identifier past it go unseen.
rf_rds_bytes <- function(path) {
  con <- gzfile(path, "rb")
  on.exit(close(con))
  pieces <- list()
  repeat {
    piece <- readBin(con, "raw", n = 1e7)
    if (!length(piece)) break
    pieces[[length(pieces) + 1L]] <- piece
  }
  do.call(c, pieces)
}

# The files in `dir` that hold any of `ids`: the forest, its cache, and the
# cache's provenance sidecar, which gzfile() reads as the plain text it is.
rf_files_holding <- function(dir, ids) {
  files <- list.files(dir, full.names = TRUE)
  held <- vapply(files, function(f) {
    bytes <- rf_rds_bytes(f)
    any(vapply(ids, function(v) rf_bytes_hold(bytes, v), logical(1L)))
  }, logical(1L))
  basename(files[held])
}

# ---- the bootstrap reports -------------------------------------------------------

# The bootstrap reports (bl, br, bc, bh) are run chunk by chunk, as the rf
# templates are, on the same study fixtures, and so are the runners add_job()
# writes beside them from inst/runners/. Nothing else runs a runner. They live in this file
# because they call its helpers: object_usage_linter resolves a helper only
# from the file that defines it.

boot_thin <- c("bl", "br", "bc")
boot_all <- c(boot_thin, "bh")

# The set the templates' `set` chunk resolves: SUBJECT dead_pa, TYPE hz.
boot_set <- "dead_pa-hz"

# The settings a study author would give each runner for rf_mrn_data(): an
# outcome with a known driver, so every screen selects something, and
# FINISHED, which an author sets once every marker is worked.
boot_settings <- function(prefix, ...) {
  outcome <- list(
    bl = list(OUTCOME = "dead"),
    br = list(OUTCOME = "los"),
    bc = list(TIME = "iv_dead", EVENT = "dead", BASE = "x1")
  )[[prefix]]
  utils::modifyList(c(outcome, list(FINISHED = TRUE, POOL = c("age", "x1"), N_REP = 30, SEED = 1)), list(...))
}

# The runner add_job() writes beside the `prefix` report in the study at
# `root`, for the set the report's `set` chunk names.
boot_scaffold <- function(prefix, root) {
  suppressMessages(add_job(prefix, "dead_pa", "hz", dir = root))
  sub("[.]qmd$", "-runner.R", hvtiRtemplates:::.job_path(
    hvtiRtemplates:::.select_template(template_list(), prefix, NULL), "dead_pa", "hz", root
  ))
}

# Scaffold the `prefix` job in the study at `root` and evaluate the runner
# add_job() wrote, in `env`, from the study, as a script run there would be.
# `settings` replace the runner's own top-level assignments of the same names,
# as a study author's edits would; a setting the runner does not assign is an
# error, so a renamed one cannot be skipped.
boot_run_runner <- function(prefix, root, env, settings = boot_settings(prefix)) {
  code <- parse(file = boot_scaffold(prefix, root), keep.source = FALSE)
  assigned <- vapply(code, function(expr) {
    if (is.call(expr) && identical(expr[[1L]], quote(`<-`)) && is.name(expr[[2L]])) as.character(expr[[2L]]) else ""
  }, character(1L))
  if (!all(names(settings) %in% assigned)) {
    stop("the ", prefix, " runner does not assign: ", paste(setdiff(names(settings), assigned), collapse = ", "), call. = FALSE)
  }
  withr::local_dir(root)
  for (i in seq_along(code)) {
    if (assigned[[i]] %in% names(settings)) {
      assign(assigned[[i]], settings[[assigned[[i]]]], envir = env)
    } else {
      suppressPackageStartupMessages(eval(code[[i]], envir = env))
    }
  }
  file.path(hvtiRutilities::study_dir("estimates", root), boot_set)
}

# Every chunk of a boot_select() report, in order, that a render evaluates
# after `setup` and `guard-edits`.
boot_report_labels <- c(
  "set", "edit-study-choices", "load", "tbl-data", "completeness", "contract", "bootstrap-provenance", "seeds",
  "dropped-summary", "dropped-detail", "health", "frequencies", "retained", "edit-concept-map",
  "concept-frequencies", "concept-union", "concept-counts", "cluster-matrix", "edit-clusters", "edit-collinear",
  "save"
)

# A fresh chunk environment for the study at `root`. `setup` is not run, so
# what it defines is supplied.
boot_env <- function(root, parent = globalenv()) {
  env <- new.env(parent = parent)
  env$.root <- root
  env$.provenance_data <- list()
  env$.provenance_artifacts <- list()
  env
}

# Run the chunks `labels` of the `prefix` report in `env`. The study choices
# are the run's size and a cluster naming a term every screen here carries.
boot_report <- function(prefix, env, labels = boot_report_labels, choices = list()) {
  defaults <- list(EXPECT_BOOT = 30L, CLUSTERS = list(Age = "age"))
  choices <- c(choices, defaults[setdiff(names(defaults), names(choices))])
  src <- readLines(template_path(prefix), warn = FALSE)
  utils::capture.output(for (label in labels) {
    eval(parse(text = rf_chunk(src, label)), envir = env)
    if (identical(label, "edit-study-choices")) list2env(choices, envir = env)
  })
  invisible(env)
}

# A hazard chunk as the bh runner writes it, with two replicates made up here:
# a hazard screen runs for minutes, and what these tests exercise is the
# report's reading of the chunk, not the screen. `extra` adds fields.
boot_hazard_chunk <- function(k, job, selection = attr(job$record, "selection"), extra = list()) {
  reps <- data.frame(
    replicate = rep(1:2, each = 3L),
    parameter = rep(c("early.log_mu", "constant.log_mu", "early.age"), 2L),
    estimate = c(-1, -2, 0.03, -1.1, -2.2, 0.04) + k / 100
  )
  offered <- c(early = 2L, constant = 2L)
  chunk <- c(list(
    n_boot = 2L, seed = 20260100L + k, slentry = 0.10, slstay = 0.05, max_steps = 50L,
    base_params = c("early.log_mu", "constant.log_mu"), requested = offered, usable = offered,
    n_rows = nrow(job$data), elapsed_mins = 0.1, manifest = list(sha256 = job$provenance$sha256),
    th_version = "1.2.12",
    boot = list(replicates = reps, summary = data.frame(parameter = unique(reps$parameter), n = 2L, pct = 100),
                n_success = 2L, n_failed = 0L)
  ), extra)
  attr(chunk, "hvti_provenance") <- c(
    list(data = list(job$provenance), artifacts = list(), analysis = NULL, cohort = NULL),
    if (!is.null(selection)) list(selection = selection)
  )
  chunk
}

# Save hazard chunks into the set of the study at `root`, where bh reads them.
boot_save_chunks <- function(root, chunks) {
  dir <- file.path(hvtiRutilities::study_dir("estimates", root), boot_set)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  for (k in seq_along(chunks)) saveRDS(chunks[[k]], file.path(dir, sprintf("bh.chunk%02d.rds", k)))
  dir
}

# Skip unless the report's own packages are installed, and survival for the
# Cox runner, then attach the report's packages.
boot_skip_unless_stack <- function(prefix) {
  rf_skip_unless_stack(rf_template_packages(prefix, NULL))
  if (identical(prefix, "bc")) testthat::skip_if_not_installed("survival")
}

# Run the `prefix` runner in `runner_env` and its whole report in `report_env`,
# on a study keyed on MRN. Returns the data, the set directory and the report's
# environment.
boot_mrn_run <- function(prefix, runner_env, report_env, .local_envir = parent.frame()) {
  data <- rf_mrn_data()
  root <- rf_study(data, .local_envir)
  rf_restore_later(runner_env, .local_envir)
  rf_restore_later(report_env, .local_envir)
  dir <- boot_run_runner(prefix, root, runner_env)
  report_env$.root <- root
  report_env$.provenance_data <- list()
  report_env$.provenance_artifacts <- list()
  boot_report(prefix, report_env)
  list(data = data, dir = dir, env = report_env)
}
