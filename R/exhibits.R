# Exhibits: the figures, tables and values a job offers to an `ar` analysis
# report, each recorded by its chunk label with its file and a digest, and the
# job's boilerplate Methods paragraph. .embed_provenance() writes both into the
# job's sidecar through .ar_extra(). The design is
# dev/specs/2026-11-11-ar-question-report-design.md, sections 4 and 5.

.exhibit_label_ok <- function(label) {
  is.character(label) && length(label) == 1L && !is.na(label) && grepl("^[A-Za-z0-9_-]+$", label)
}

.exhibit_relative <- function(file, root) {
  file <- normalizePath(file, winslash = "/", mustWork = TRUE)
  prefix <- paste0(normalizePath(root, winslash = "/", mustWork = TRUE), "/")
  if (!startsWith(file, prefix)) stop("Exhibit '", file, "' is outside the study.", call. = FALSE)
  substring(file, nchar(prefix) + 1L)
}

# A file this run did not write records nothing: a figure with SAVE_FIGURES off
# leaves the file an earlier render wrote, and its mtime is older than the run's
# start, less 2 seconds for the timestamp granularity of an SMB share. The ar
# report then stops on the missing label and names it, as for an absent file.
.record_exhibit <- function(file, kind = c("figure", "table", "value"), label = knitr::opts_current$get("label"),
                            root = .run_state$root) {
  kind <- match.arg(kind)
  if (!.exhibit_label_ok(label)) {
    stop("An exhibit needs a chunk label of letters, digits, '-' or '_'; got ",
         if (is.null(label)) "none" else encodeString(as.character(label)[1L], quote = "\""), ".", call. = FALSE)
  }
  if (is.null(root)) stop("An exhibit can be recorded only after the job's setup chunk has run.", call. = FALSE)
  if (!file.exists(file)) return(invisible(NULL))
  started <- .run_state$started
  if (!is.null(started) && file.mtime(file) < started - 2) return(invisible(NULL))
  if (label %in% names(.run_state$exhibits)) {
    stop("Exhibit label '", label, "' is recorded twice in this run; give each exhibit its own label.", call. = FALSE)
  }
  rec <- list(label = label, kind = kind, file = .exhibit_relative(file, root),
              sha256 = digest::digest(file, algo = "sha256", file = TRUE))
  .run_state$exhibits[[label]] <- rec
  invisible(rec)
}

# Tables are saved unformatted, as data frames: the publication phase formats
# the ones researchers choose, and the report shows them as plain tables.
.save_exhibit <- function(x, kind = c("table", "value"), file, label = knitr::opts_current$get("label")) {
  kind <- match.arg(kind)
  if (identical(kind, "table") && !is.data.frame(x)) {
    stop("A table exhibit must be a data frame; format it in the report, not in the saved object.", call. = FALSE)
  }
  if (identical(kind, "value") && (!is.list(x) || is.null(names(x)) || any(!nzchar(names(x))))) {
    stop("A value exhibit must be a named list, so ar_value() can name a field.", call. = FALSE)
  }
  saveRDS(x, file)
  .record_exhibit(file, kind, label)
}

.methods_text <- function(text) {
  if (!is.character(text) || length(text) != 1L || is.na(text) || !nzchar(trimws(text))) {
    stop("A Methods paragraph must be one non-empty string.", call. = FALSE)
  }
  .run_state$methods <- list(text = text, sha256 = digest::digest(text, algo = "sha256", serialize = FALSE))
  invisible(text)
}

.ar_extra <- function(source_sha256) {
  exhibits <- .run_state$exhibits
  Filter(Negate(is.null), list(
    source_sha256 = source_sha256,
    exhibits = if (length(exhibits)) unname(exhibits),
    methods = .run_state$methods
  ))
}
