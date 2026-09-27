migration_study_fixture <- function(kind = NULL, .local_envir = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = .local_envir)
  folders <- c("datasets", "descriptive", "distributions", "analyses", "graphs", "documents", "estimates")
  for (folder in folders) dir.create(file.path(root, folder))
  i <- seq_len(40L)
  built <- data.frame(
    dead = i %% 2L, iv_dead = i / 10, iv_fup = i / 10 + 1,
    year = 2000L + i %% 10L, female = i %% 2L, race_grp = 1L + i %% 3L,
    repair = as.integer(i %% 3L == 0L), age = 40 + i, bmi = 20 + i / 10,
    treatment = i %% 2L,
    hx_chf = as.integer(i %% 4L == 0L), lvmassi = 80 + i,
    iv_opyrs = i + 0.25
  )
  if (identical(kind, "dp-postage")) {
    for (j in seq_len(5L)) built[[paste0("panel", j)]] <- i + j / 10
  }
  utils::write.csv(built, file.path(root, "datasets", "built.csv"), row.names = FALSE)
  utils::write.csv(built[1:24, ], file.path(root, "datasets", "complete_cases.csv"), row.names = FALSE)
  suppressMessages(hvtiRutilities::study_setup(
    root, study = "Synthetic legacy study", study_tracker_id = 42L,
    umbrella = "Synthetic fixture", owner = "hvtiRtemplates tests",
    irb_number = "SYNTHETIC", cvir_no = "SYNTHETIC", adopt = TRUE
  ))
  suppressMessages(hvtiRutilities::register_data(
    root, built = "built.csv",
    role = "study", population = "Synthetic full cohort"
  ))
  suppressMessages(hvtiRutilities::register_data(
    root, built = "complete_cases.csv",
    dataset = "complete_cases", role = "named", population = "Synthetic complete cases"
  ))
  if (!is.null(kind)) {
    fixture <- testthat::test_path("fixtures-migration", kind)
    if (!dir.exists(fixture)) stop("Missing migration fixture: ", kind)
    entries <- list.files(fixture, full.names = TRUE, all.files = TRUE, no.. = TRUE)
    folder <- if (identical(kind, "dp-trends")) "graphs" else "descriptive"
    for (entry in entries) {
      destination <- if (dir.exists(entry)) {
        root
      } else if (grepl("[.](rtf|docx)$", entry, ignore.case = TRUE)) {
        file.path(root, "documents")
      } else if (basename(entry) == "review-markers.txt") {
        root
      } else {
        file.path(root, folder)
      }
      if (!file.copy(entry, destination, recursive = dir.exists(entry))) stop("Could not copy migration fixture: ", kind)
    }
  }
  root
}

.resolve_fixture_markers <- function(job, markers) {
  if (any(!grepl("EDIT: .+", markers)) || any(!grepl("#|<!--", markers))) {
    stop("Fixture review markers must declare complete source lines containing an EDIT: comment.")
  }
  lines <- readLines(job, warn = FALSE)
  if (any(!markers %in% lines)) stop("A declared fixture review marker was not found in the migrated job.")
  hits <- lines %in% markers
  lines[hits] <- gsub("EDIT:", "REVIEWED:", lines[hits], fixed = TRUE)
  writeLines(lines, job)
}

render_migrated_fixture <- function(kind, root = NULL) {
  mapping <- list(
    "dc-tables" = c(prefix = "dc", qualifier = "tables", source = "descriptive/dc.tables.sas"),
    "dc-gfup" = c(prefix = "dc", qualifier = "gfup", source = "descriptive/dc.gfup.sas"),
    "dp-trends" = c(prefix = "dp", qualifier = "trends", source = "graphs/dp.trends.sas"),
    "dp-postage" = c(prefix = "dp", qualifier = "postage", source = "descriptive/dp.postage.qmd")
  )
  if (length(kind) != 1L || is.na(kind) || !kind %in% names(mapping)) stop("Unknown migration fixture.")
  spec <- mapping[[kind]]
  if (is.null(root)) root <- migration_study_fixture(kind, .local_envir = parent.frame())
  source <- file.path(root, spec[["source"]])
  optional <- function(extension) {
    path <- sub("[.][^.]+$", paste0(".", extension), source)
    if (file.exists(path)) path else NULL
  }
  references <- list.files(file.path(root, "documents"), pattern = "[.](rtf|docx)$",
                           full.names = TRUE, ignore.case = TRUE)
  job <- migrate_job(
    source, "cohort", "eda", spec[["prefix"]], spec[["qualifier"]],
    lst = optional("lst"), log = optional("log"),
    reference = if (length(references)) references else NULL, dir = root
  )
  declarations <- testthat::test_path("fixtures-migration", kind, "review-markers.txt")
  if (file.exists(declarations)) .resolve_fixture_markers(job, readLines(declarations, warn = FALSE))
  quarto::quarto_render(job, execute_dir = dirname(job), quiet = TRUE)
  list(
    root = root, job = job, report = sub("[.]qmd$", "-migration.md", job),
    outputs = list.files(root, pattern = "[.](html|docx|png)$", recursive = TRUE, full.names = TRUE)
  )
}

render_all_migration_fixtures <- function() {
  kinds <- c("dc-tables", "dc-gfup", "dp-trends", "dp-postage")
  # Keep all four roots alive in the caller's scope for artifact inspection.
  caller <- parent.frame()
  roots <- lapply(kinds, migration_study_fixture, .local_envir = caller)
  stats::setNames(Map(render_migrated_fixture, kinds, roots), kinds)
}

# Scaffold a dp-gfup job in a synthetic study and replace whole lines by pattern.
scaffold_gfup <- function(edits, .local_envir = parent.frame()) {
  root <- migration_study_fixture(NULL, .local_envir = .local_envir)
  job <- add_job("dp", "cohort", "eda", dir = root, qualifier = "gfup")
  lines <- readLines(job, warn = FALSE)
  for (pattern in names(edits)) {
    hit <- grep(pattern, lines)
    if (length(hit) != 1L) stop("Expected one line matching ", pattern)
    lines[hit] <- edits[[pattern]]
  }
  writeLines(lines, job)
  list(root = root, job = job)
}

# Scaffold any <prefix>-<qualifier> job as cohort-eda in a synthetic study,
# replace whole lines by pattern, and optionally move it into a subfolder of
# its taxonomy folder, the layout that once broke image embedding.
scaffold_job <- function(prefix, qualifier, edits, kind = NULL, root = NULL, subfolder = NULL,
                         .local_envir = parent.frame()) {
  if (is.null(root)) root <- migration_study_fixture(kind, .local_envir = .local_envir)
  job <- add_job(prefix, "cohort", "eda", dir = root, qualifier = qualifier)
  lines <- readLines(job, warn = FALSE)
  for (pattern in names(edits)) {
    hit <- grep(pattern, lines)
    if (length(hit) != 1L) stop("Expected one line matching ", pattern)
    lines[hit] <- edits[[pattern]]
  }
  if (!is.null(subfolder)) {
    unlink(job)
    job <- file.path(dirname(job), subfolder, basename(job))
    dir.create(dirname(job))
  }
  writeLines(lines, job)
  list(root = root, job = job)
}
