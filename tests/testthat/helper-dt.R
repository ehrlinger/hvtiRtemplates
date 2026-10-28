# The dt check job's fixtures. dt reads the working file a bd job writes, so its
# studies are made by running bd (helper-bd.R) and then changing that file the way a
# rebuild would. Every value is simulated.

dt_skip <- function() {
  bd_skip()  # nolint: object_usage_linter.
  # The named checks need proc_print(), added to hvtiRutilities after 1.5.16 (hvtiRutilities#262).
  testthat::skip_if_not("proc_print" %in% getNamespaceExports("hvtiRutilities"), "hvtiRutilities has no proc_print()")
  testthat::skip_if_not_installed("hvtiRdatabuild", "0.3.3")
}

dt_quarto_skip <- function() {
  dt_skip()
  testthat::skip_if_not_installed("quarto")
  testthat::skip_if_not(quarto::quarto_available())
}

dt_bd_choices <- function(m, register) {
  list(MASTER = m$parquet, KEEP = c("age", "sex", "iv_dead", "dead", "dt_surg"),
       EXCLUDE = list(age < 40 ~ "Under 40"), REGISTER = register)
}

# A study whose bd job has run, chunk by chunk, with REGISTER as given.
dt_study <- function(register = TRUE, .local_envir = parent.frame()) {
  m <- bd_master(.local_envir = .local_envir)  # nolint: object_usage_linter.
  root <- bd_study(.local_envir = .local_envir)  # nolint: object_usage_linter.
  bd_run(root, dt_bd_choices(m, register))  # nolint: object_usage_linter.
  list(m = m, root = root)
}

dt_working <- function(root, dataset_id = "study_cohort") {
  file.path(hvtiRutilities::study_dir("datasets", root), paste0(dataset_id, ".rds"))
}

# The rebuild a check is for: the working file rewritten in place, as a second bd
# render with a changed derivation would leave it.
dt_rebuild <- function(root, change, dataset_id = "study_cohort") {
  path <- dt_working(root, dataset_id)
  saveRDS(change(readRDS(path)), path)
  invisible(path)
}

dt_choices <- function(...) {
  utils::modifyList(list(CROSSTABS = list(c("dead", "sex")), EVENT = "dead", FOLLOWUP = "iv_dead",
                         CHECKS = list(iv_dead <= 0 ~ "Follow-up of zero or less"), PRINT_COLS = c("ccfid", "iv_dead")),
                    list(...))
}

# Run dt's chunks from inside the study, as bd_run() does for bd.
dt_run <- function(root, choices = dt_choices(),
                   labels = c("setup", "edit-study-choices", "check-choices", "read-working", "rebuild")) {
  env <- new.env(parent = globalenv())
  out <- withr::with_dir(root, utils::capture.output(
    hazard_run("dt", labels, env, choices), type = "output"  # nolint: object_usage_linter.
  ))
  env$.stdout <- out
  env
}

# Scaffold dt and apply `edits`, each a regex matching exactly one line and its replacement.
dt_job <- function(root, edits = list()) {
  job <- add_job("dt", "study", "check", dir = root)
  lines <- readLines(job, warn = FALSE)
  for (pattern in names(edits)) {
    hit <- grep(pattern, lines)
    if (length(hit) != 1L) stop("Expected one line matching ", pattern, call. = FALSE)
    lines[hit] <- edits[[pattern]]
  }
  writeLines(lines, job)
  job
}

dt_render <- function(job) {
  quarto::quarto_render(job, execute_dir = dirname(job), quiet = TRUE)
  paste(readLines(sub("[.]qmd$", ".html", job), warn = FALSE), collapse = "\n")
}
