# From an ar item id, "<job>#<label>", to evidence the report can show: the
# job's sidecar, the exhibit it recorded and the file, verified against the
# digest. Stops on everything that would let a draft or a stray file pass as
# finished evidence. dev/specs/2026-11-11-ar-question-report-design.md, 6.2.

.ar_parse_id <- function(id) {
  if (!is.character(id) || length(id) != 1L || is.na(id) || !grepl("^[A-Za-z0-9_.-]+#[A-Za-z0-9_-]+$", id)) {
    stop("An item is named '<job>#<label>', such as 'hz.dead.hz#fig-fit'; got ",
         encodeString(as.character(id)[1L], quote = "\""), ".", call. = FALSE)
  }
  parts <- strsplit(id, "#", fixed = TRUE)[[1L]]
  list(id = id, job = parts[[1L]], label = parts[[2L]])
}

# Jobs sit flat in the study's top-level folders, under either the numbered or
# the legacy bare layout, so one level of glob finds them.
.ar_find_job <- function(job, root) {
  hits <- Sys.glob(file.path(root, "*", paste0(job, ".qmd")))
  if (length(hits) == 0L) stop("There is no job '", job, ".qmd' in this study.", call. = FALSE)
  if (length(hits) > 1L) {
    stop("Job '", job, ".qmd' is in more than one folder: ", paste(hits, collapse = ", "), ".", call. = FALSE)
  }
  normalizePath(hits, winslash = "/")
}

.ar_read_sidecar <- function(qmd, job) {
  sidecar <- hvtiRutilities::provenance_path(sub("[.]qmd$", ".html", qmd))
  if (!file.exists(sidecar)) stop("Job '", job, "' has no provenance record; render it first.", call. = FALSE)
  jsonlite::read_json(sidecar, simplifyVector = FALSE)
}

.ar_draft_detail <- function(run) {
  c(if (isTRUE(run$open_markers > 0L)) paste(run$open_markers, "open EDIT: marker(s)"),
    if (isTRUE(run$skipped_chunks > 0L)) paste(run$skipped_chunks, "skipped chunk(s)"),
    if (isTRUE(run$stopped_early)) "a stop_here()",
    unlist(run$draft_reasons, use.names = FALSE))
}

# A sidecar is a file on a share; its records are checked before one names a path.
.ar_check_record <- function(rec, root, job) {
  one <- function(x) is.character(x) && length(x) == 1L && !is.na(x)
  label <- if (one(rec$label)) rec$label else "<no label>"
  bad <- function(why) {
    stop("Job '", job, "' has a malformed exhibit record (label '", label, "'): ", why, ".", call. = FALSE)
  }
  for (f in c("label", "kind", "file", "sha256")) if (!one(rec[[f]])) bad(paste0("`", f, "` is not a single string"))
  if (!rec$kind %in% c("figure", "table", "value")) bad(paste0("unknown kind '", rec$kind, "'"))
  parts <- strsplit(rec$file, "[/\\\\]")[[1L]]
  if (grepl("^([/\\\\]|[A-Za-z]:)", rec$file) || ".." %in% parts) bad("the file is not a path inside the study")
  if (!grepl("^[A-Za-z0-9_.-]+$", basename(rec$file))) bad("the file name has unexpected characters")
  path <- file.path(root, rec$file)
  if (file.exists(path)) {
    prefix <- paste0(normalizePath(root, winslash = "/"), "/")
    if (!startsWith(normalizePath(path, winslash = "/"), prefix)) bad("the file resolves outside the study")
  }
  invisible(TRUE)
}

.ar_resolve <- function(id, root) {
  item <- .ar_parse_id(id)
  qmd <- .ar_find_job(item$job, root)
  side <- .ar_read_sidecar(qmd, item$job)
  status <- side$run$status
  if (is.null(status)) {
    stop("Item '", id, "': job '", item$job, "' was rendered before runs recorded their status, so it cannot be ",
         "presumed final. Render it again with the current hvtiRtemplates.", call. = FALSE)
  }
  if (!identical(status, "final")) {
    stop("Item '", id, "': job '", item$job, "' last rendered as a draft (",
         paste(.ar_draft_detail(side$run), collapse = "; "),
         "). A draft is not evidence: finish the job and render it again.", call. = FALSE)
  }
  recs <- if (is.null(side$exhibits)) list() else side$exhibits
  for (r in recs) .ar_check_record(r, root, item$job)
  labels <- vapply(recs, function(r) r$label, "")
  hit <- which(labels == item$label)
  if (length(hit) != 1L) {
    stop("Item '", id, "': job '", item$job, "' recorded no exhibit labeled '", item$label, "' (",
         if (length(labels)) paste("it recorded:", paste(labels, collapse = ", "))
         else "it recorded none; its template may not save exhibits yet, or SAVE_FIGURES may be off",
         ").", call. = FALSE)
  }
  rec <- recs[[hit]]
  path <- file.path(root, rec$file)
  if (!file.exists(path)) {
    stop("Item '", id, "': the file '", rec$file, "' its job recorded is missing. Render the job again.", call. = FALSE)
  }
  if (!identical(digest::digest(path, algo = "sha256", file = TRUE), rec$sha256)) {
    stop("Item '", id, "': '", rec$file, "' no longer holds the bytes its job's last completed render recorded. ",
         "A later render may have failed after writing it, or it was changed by hand. Render the job again.",
         call. = FALSE)
  }
  changed <- !is.null(side$source_sha256) &&
    !identical(digest::digest(qmd, algo = "sha256", file = TRUE), side$source_sha256)
  c(item, list(qmd = qmd, html = sub("[.]qmd$", ".html", qmd), sidecar = side, exhibit = rec,
               path = normalizePath(path, winslash = "/"), source_changed = changed))
}

# The template's paragraph, or, until its template writes one, a floor built
# from what the sidecar records: date, R, data and non-base packages.
.ar_methods <- function(r) {
  m <- r$sidecar$methods
  if (!is.null(m)) return(list(text = m$text, sha256 = m$sha256, floor = FALSE))
  pk <- Filter(function(p) !identical(p$source, "base"), r$sidecar$packages)
  pk <- vapply(pk, function(p) paste(p$package, p$version), "")
  ds <- unique(vapply(r$sidecar$data, function(x) if (is.null(x$dataset)) x$path else x$dataset, ""))
  text <- paste0("Job ", r$job, " was rendered on ", substr(r$sidecar$rendered, 1L, 10L), " with R ",
                 r$sidecar$r$version, if (length(ds)) paste0(", reading ", paste(ds, collapse = ", ")),
                 if (length(pk)) paste0(". Packages: ", paste(pk, collapse = ", ")), ".")
  list(text = text, sha256 = digest::digest(text, algo = "sha256", serialize = FALSE), floor = TRUE)
}
