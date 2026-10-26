# The template gallery: every shipped and in-flight template rendered once, on
# one synthetic study, so the group can read what each job produces without
# running it. package.py marks the in-flight ones, from the catalog's status.
#
#   Rscript dev/gallery/gallery.R [output folder]
#
# Built on the descriptives demo (dev/demo/demo-study.R): the same 800
# simulated operations, plus the columns other families need. Each family
# lives in its own file, family-<name>.R, which declares
#   - columns: a function(d) that adds that family's columns to the cohort,
#     drawing from its own seed so no other family's numbers move;
#   - jobs: one entry per template, in render order, each naming the set it
#     belongs to (subject and type) and the study choices typed under its
#     EDIT: markers, as demo-study.R's set_choices() takes them. A second job
#     of one template takes a name of its own and names its template in
#     `template`, as lp-mirror-matched does.
# Every number is simulated: no study, patient or identifier appears here.

.gallery_dir <- local({
  here <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (length(here)) dirname(here) else "dev/gallery"
})
source(file.path(.gallery_dir, "..", "demo", "demo-study.R"))

# ---- Families ----------------------------------------------------------------
gallery_families <- list()
.gallery_env <- environment()

# Called once by each family file.
gallery_family <- function(name, jobs, columns = function(d) d) {
  stopifnot(is.character(name), length(name) == 1L, is.function(columns), is.list(jobs))
  for (job in names(jobs)) {
    spec <- jobs[[job]]
    if (is.null(spec$subject) || is.null(spec$type)) {
      stop("Gallery job ", job, " must name its subject and type.", call. = FALSE)
    }
  }
  .gallery_env$gallery_families[[name]] <- list(columns = columns, jobs = jobs)
  invisible(name)
}

for (.f in sort(list.files(.gallery_dir, "^family-.*[.]R$", full.names = TRUE))) source(.f)

gallery_jobs <- function() {
  jobs <- unlist(lapply(names(gallery_families), function(fam) {
    lapply(gallery_families[[fam]]$jobs, function(spec) c(spec, family = fam))
  }), recursive = FALSE)
  dup <- names(jobs)[duplicated(names(jobs))]
  if (length(dup)) stop("Gallery job named twice: ", paste(dup, collapse = ", "), call. = FALSE)
  jobs
}

# Every template on disk whose catalog status is shipped or in-flight must have
# a gallery job. The status is read from the catalog, so a template that moves
# into flight is missed loudly rather than left out of the gallery. Returns the
# names that have none.
gallery_missing <- function(jobs = gallery_jobs()) {
  repo <- file.path(.gallery_dir, "..", "..")
  rows <- jsonlite::read_json(file.path(repo, "inst", "extdata", "templates.json"))$templates
  wanted <- vapply(rows, function(r) {
    if (!r$status %in% c("shipped", "in-flight")) return(NA_character_)
    if (is.null(r$qualifier)) r$prefix else paste0(r$prefix, "-", r$qualifier)
  }, character(1L))
  disk <- sub("[.]qmd$", "", basename(list.files(file.path(repo, "inst", "templates"), "[.]qmd$", recursive = TRUE)))
  have <- vapply(names(jobs), function(name) jobs[[name]]$template %||% name, character(1L))
  setdiff(intersect(stats::na.omit(wanted), disk), have)
}

# ---- The study ---------------------------------------------------------------
# The demo cohort with every family's columns added, labels kept.
gallery_data <- function() {
  d <- demo_data()
  owner <- stats::setNames(rep("demo", ncol(d)), names(d))
  for (fam in names(gallery_families)) {
    before <- d
    d <- gallery_families[[fam]]$columns(d)
    if (!is.data.frame(d)) stop("Family ", fam, "'s columns() must return a data frame.", call. = FALSE)
    # A family may add columns, or redraw the demo's own; it may not redraw
    # another family's, which would change that family's reports silently.
    changed <- names(d)[!names(d) %in% names(before) |
                          !vapply(names(d), function(v) identical(d[[v]], before[[v]]), logical(1L))]
    taken <- changed[changed %in% names(owner) & owner[changed] != "demo"]
    if (length(taken)) {
      stop("Family ", fam, " redefines column(s) another family defined: ",
           paste0(taken, " (", owner[taken], ")", collapse = ", "), call. = FALSE)
    }
    owner[changed] <- fam
  }
  d
}

gallery_study <- function(root) {
  root <- path.expand(root)
  if (dir.exists(root)) stop("Gallery folder already exists: ", root, ". Remove it or name another.", call. = FALSE)
  dir.create(dirname(root), recursive = TRUE, showWarnings = FALSE)
  invisible(utils::capture.output(suppressMessages(study_setup(
    root, study = "Template gallery (synthetic)", study_tracker_id = 1L,
    umbrella = "Demo", owner = "CORR", irb_number = "DEMO", cvir_no = "DEMO"
  ))))
  saveRDS(gallery_data(), file.path(study_dir("datasets", root), "built.rds"))
  invisible(utils::capture.output(suppressMessages(register_data(
    root, built = "built.rds", role = "study", population = "Synthetic cohort, 800 operations"
  ))))
  root
}

# ---- Jobs --------------------------------------------------------------------
# Scaffold one job by its "<prefix>[-<qualifier>]" name into its set, apply
# its choices, and return the job file.
gallery_job <- function(root, name, spec) {
  parts <- strsplit(spec$template %||% name, "-", fixed = TRUE)[[1L]]
  qualifier <- if (length(parts) > 1L) paste(parts[-1L], collapse = "-") else NULL
  job <- add_job(parts[[1L]], spec$subject, spec$type, dir = root, qualifier = qualifier)
  if (!is.null(spec$prepare)) spec$prepare(root, job)
  set_choices(job, spec$choices %||% list())
}

# Scaffold and render every job, in family order and each family's own order,
# so a job that reads another's saved output renders after it. Returns a data
# frame: one row per job, with its report, or the error that stopped it.
gallery_build <- function(root, quiet = TRUE, only = NULL) {
  # Every report says who rendered it and on which machine ("About this run"),
  # and the gallery is published. HVTI_RUN_USER and HVTI_RUN_HOST replace the
  # two, so no real username or host name reaches the site. Environment
  # variables, not options(): Quarto renders in a process of its own.
  withr::local_envvar(c(HVTI_RUN_USER = "gallery", HVTI_RUN_HOST = "gallery"))
  jobs <- gallery_jobs()
  if (is.null(only) && length(missing <- gallery_missing(jobs))) {
    stop("No gallery job for shipped or in-flight template(s): ", paste(missing, collapse = ", "),
         ". Add one to a family file.", call. = FALSE)
  }
  if (!is.null(only)) jobs <- jobs[names(jobs) %in% only]
  rows <- lapply(names(jobs), function(name) {
    spec <- jobs[[name]]
    message("Rendering ", name, " ...")
    t0 <- Sys.time()
    res <- tryCatch({
      job <- gallery_job(root, name, spec)
      render_job(job, final = TRUE, quiet = quiet)
      report <- sub("[.]qmd$", ".html", job)
      if (!file.exists(report)) stop("no report written")
      list(report = report, error = NA_character_)
    }, error = function(e) list(report = NA_character_, error = conditionMessage(e)))
    data.frame(template = name, family = spec$family, report = res$report, error = res$error,
               seconds = round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1))
  })
  do.call(rbind, rows)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(TRUE)
  out <- if (length(args)) args[[1L]] else file.path(tempfile("gallery-"), "study")
  root <- gallery_study(out)
  built <- gallery_build(root)
  print(built[, c("template", "family", "seconds", "error")], row.names = FALSE)
  saveRDS(built, file.path(root, "gallery-build.rds"))
  utils::write.csv(built, file.path(root, "gallery-build.csv"), row.names = FALSE)
  # Each template's run sheet, read from the installed templates this build
  # rendered. package.py publishes them as sheets/<template>.html.
  jsonlite::write_json(hvtiRtemplates:::.run_sheets(), file.path(root, "run-sheets.json"),
                       auto_unbox = TRUE, pretty = TRUE)
  if (anyNA(built$report)) quit(status = 1L)
}
