# The bd build job's fixture: a synthetic master snapshot made the way a real
# one is, a SAS dataset run through hvtiRdatabuild::snapshot_master(), so the
# parquet and its sidecar are the real formats. Every value is simulated.

bd_skip <- function() {
  # The job stops below 1.5.17, the first hvtiRutilities with proc_print() for its named checks, and below
  # hvtiRdatabuild 0.3.3, the first with compare_built() for the rebuild comparison.
  testthat::skip_if_not_installed("hvtiRutilities", "1.5.17")
  testthat::skip_if_not_installed("hvtiRdatabuild", "0.3.3")
  testthat::skip_if_not_installed("arrow")
  testthat::skip_if_not_installed("haven")
}

# The end-to-end tests also render through Quarto.
bd_quarto_skip <- function() {
  bd_skip()
  testthat::skip_if_not_installed("quarto")
  testthat::skip_if_not(quarto::quarto_available())
}

bd_master <- function(n = 200L, .local_envir = parent.frame()) {
  dir <- withr::local_tempdir("bd-master-", .local_envir = .local_envir)
  d <- hvtiRutilities::generate_survival_data(n = n, seed = 20261002)
  d$dt_surg <- as.Date(paste0(d$origin_year, "-06-15"))
  d$mrn <- sprintf("M%07d", seq_len(n))
  # write_sas() is superseded in haven, and warns so; it still writes a file
  # haven and snapshot_master() read back.
  suppressWarnings(haven::write_sas(d, file.path(dir, "built.sas7bdat")))
  writeLines("data m; run;", file.path(dir, "bd.data.sas"))
  cfg <- file.path(dir, "master.yml")
  writeLines(c("name: master_syn", "key: [ccfid]", paste0("snapshots: ", dir), "current: built.sas7bdat",
               paste0("build_program: ", file.path(dir, "bd.data.sas"))), cfg)
  out <- file.path(dir, "snapshot")
  utils::capture.output(suppressMessages(
    hvtiRdatabuild::snapshot_master(hvtiRdatabuild::read_master_config(cfg), out, which = "current")
  ))
  list(parquet = file.path(out, "built.parquet"), data = d)
}

bd_study <- function(.local_envir = parent.frame()) {
  root <- withr::local_tempdir("bd-study-", .local_envir = .local_envir)
  suppressMessages(hvtiRutilities::study_setup(
    root, study = "bd test", study_tracker_id = 9L,
    adopt = TRUE, cleanup = FALSE, renv = FALSE
  ))
  normalizePath(root)
}

# Scaffold the job and apply `edits`, each a regex matching exactly one line
# and the line that replaces it, as a study author's edits would.
bd_job <- function(root, edits = list()) {
  job <- add_job("bd", "study", "build", dir = root)
  lines <- readLines(job, warn = FALSE)
  for (pattern in names(edits)) {
    hit <- grep(pattern, lines)
    if (length(hit) != 1L) stop("Expected one line matching ", pattern, call. = FALSE)
    lines[hit] <- edits[[pattern]]
  }
  writeLines(lines, job)
  job
}

# Run the job's chunks in a fresh environment from inside the study, so the
# setup chunk finds the root from the working directory as it does outside a
# render. `choices` overwrite the study choices after that chunk runs.
bd_run <- function(root, choices,
                   labels = c("setup", "set", "edit-study-choices", "check-choices", "read-master",
                              "cohort", "derive", "write-built", "register")) {
  env <- new.env(parent = globalenv())
  withr::with_dir(root, utils::capture.output(hazard_run("bd", labels, env, choices))) # nolint: object_usage_linter.
  env
}

# The dated versions registered from the study's working file, and the provenance
# row the manifest records for one of them.
# Since hvtiRutilities#243 a superseded version moves to datasets/_archive/, so
# both folders are listed, current and superseded alike.
bd_versions <- function(root, stem = "study_cohort") {
  datasets <- hvtiRutilities::study_dir("datasets", root)
  pattern <- paste0("^", stem, "_[0-9]{8}(_r[0-9]+)?[.]parquet$")
  sort(c(list.files(datasets, pattern = pattern), list.files(file.path(datasets, "_archive"), pattern = pattern)))
}

bd_current_version <- function(root) {
  .manifest_find(root, source = hvtiRutilities::study_config(root)$built)$version_file
}

bd_provenance <- function(root, version = bd_current_version(root)) {
  yaml::read_yaml(file.path(root, "manifest.yaml"))$provenance[[version]]
}

# The build's own choices for the check tests, with the four check sections set to columns the
# synthetic master carries. `...` overrides any of them.
bd_check_choices <- function(m, register = FALSE, ...) {
  utils::modifyList(
    list(MASTER = m$parquet, KEEP = c("age", "sex", "iv_dead", "dead", "dt_surg"),
         EXCLUDE = list(age < 40 ~ "Under 40"), REGISTER = register,
         CROSSTABS = list(c("dead", "sex")), EVENT = "dead", FOLLOWUP = "iv_dead",
         CHECKS = list(iv_dead <= 0 ~ "Follow-up of zero or less"), PRINT_COLS = c("ccfid", "iv_dead")),
    list(...)
  )
}

bd_check_labels <- c("rebuild", "crosstabs", "followup", "tbl-checks")

# Run bd through write-built, apply `change` to the data frame it wrote, as a rebuild with a changed
# derivation would leave it, then run the check chunks in `labels`. Returns the environment, with the
# check chunks' stdout in $.stdout.
bd_check_run <- function(root, choices, change = identity, labels = bd_check_labels) {
  env <- bd_run(root, choices, labels = c("setup", "edit-study-choices", "check-choices", "read-master", "cohort",
                                          "derive", "write-built"))
  env$d <- change(env$d)
  env$.stdout <- withr::with_dir(root, utils::capture.output(
    hazard_run("bd", labels, env), type = "output"  # nolint: object_usage_linter.
  ))
  env
}
