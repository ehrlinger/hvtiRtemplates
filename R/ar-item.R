# What an ar render shows for one item: the callouts that say what to check,
# the exhibit and a link to the job's full report. Nothing is re-run.
# dev/specs/2026-11-11-ar-question-report-design.md, sections 6.1 and 6.2.

.ar_relative <- function(path, from) {
  p <- strsplit(normalizePath(path, winslash = "/"), "/", fixed = TRUE)[[1L]]
  f <- strsplit(normalizePath(from, winslash = "/"), "/", fixed = TRUE)[[1L]]
  n <- 0L
  while (n < min(length(p), length(f)) && identical(p[[n + 1L]], f[[n + 1L]])) n <- n + 1L
  paste(c(rep("..", length(f) - n), p[-seq_len(n)]), collapse = "/")
}

.ar_callout <- function(text) paste0("::: {.callout-warning}\n", text, "\n:::\n")

.ar_callouts <- function(r, it) {
  m <- .ar_methods(r)
  s <- it$stamp
  notes <- c(
    if (isTRUE(r$source_changed)) {
      sprintf("The source job `%s` has been edited since its last render. Render it again before relying on this item.",
              r$job)
    },
    if (m$floor) {
      sprintf(paste("The `%s` job's template writes no Methods paragraph yet, so the Methods draft names the software,",
                    "versions and data only."), r$job)
    },
    if (isTRUE(it$empty)) "The Methods slot is empty. Run `hvtiRtemplates::ar_paste_methods()` on this file from the console.",
    if (!is.null(s) && !identical(s$methods_sha256, m$sha256)) {
      "The source job's Methods paragraph has changed since it was pasted here. Compare and update it, then run `ar_review()`."
    },
    if (!is.null(s) && (!identical(s$rendered, r$sidecar$rendered) || !identical(s$exhibit_sha256, r$exhibit$sha256))) {
      paste("The source job has been rendered again since this item's text was reviewed. Reread its methods, results",
            "and interpretation, then run `hvtiRtemplates::ar_review()`.")
    }
  )
  vapply(notes, .ar_callout, "", USE.NAMES = FALSE)
}

# Cells reach the report as Markdown, and Quarto passes raw HTML through.
.ar_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
}

.ar_escape_table <- function(x) {
  for (col in names(x)) if (is.character(x[[col]]) || is.factor(x[[col]])) x[[col]] <- .ar_escape(as.character(x[[col]]))
  names(x) <- .ar_escape(names(x))
  x
}

# A figure is embedded by Quarto's embed-resources; the download link carries
# the PNG itself, so it still works in the one HTML file researchers receive.
.ar_exhibit_body <- function(r, from) {
  switch(r$exhibit$kind,
    figure = {
      rel <- .ar_relative(r$path, from)
      png <- openssl::base64_encode(readBin(r$path, "raw", file.size(r$path)))
      c(sprintf("![](%s)", rel), "",
        sprintf('<a href="data:image/png;base64,%s" download="%s">Download the figure (PNG)</a>', png, basename(rel)))
    },
    table = knitr::kable(.ar_escape_table(readRDS(r$path)), format = "pipe", row.names = FALSE),
    value = sprintf("Values saved for the text: %s.", paste0("`", .ar_escape(names(readRDS(r$path))), "`", collapse = ", ")),
    stop("Item '", r$id, "' has an exhibit of unknown kind '", r$exhibit$kind, "'.", call. = FALSE)
  )
}

.ar_item_markdown <- function(r, it, from) {
  c(.ar_callouts(r, it), sprintf("**Item %d** \u00b7 `%s`", it$index, r$id), "", .ar_exhibit_body(r, from), "",
    sprintf("[The full report of `%s`, in the study folder](%s)", r$job, .ar_relative(r$html, from)), "")
}

.ar_input <- function() {
  input <- knitr::current_input(dir = TRUE)
  if (is.null(input)) stop("ar_item() shows an item while an ar report renders.", call. = FALSE)
  input
}

#' Show one item of an ar analysis report
#'
#' @description Called once per item in an `ar` job. Finds the exhibit a
#'   finished job recorded under `id`, checks that the job last rendered as
#'   final and that the file still holds the bytes it recorded, and shows the
#'   exhibit with a link to the job's report. Callouts above it say what to
#'   check: a job edited since its render, Methods boilerplate that changed, or
#'   text written against an earlier run.
#'
#' @param id The item, `"<job>#<label>"`: the source job's file name
#'   without `.qmd`, and the chunk label it saved the exhibit under.
#' @return A `knit_asis` object holding the item's Markdown.
#' @seealso [ar_value()], [ar_paste_methods()], [ar_review()]
#' @examples
#' if (requireNamespace("knitr", quietly = TRUE)) {
#'   # A copy of a small study shipped with the package: one finished hz job and
#'   # an ar report citing two of its exhibits.
#'   dir <- tempfile("ar-")
#'   dir.create(dir)
#'   src <- system.file("extdata", "ar-study", package = "hvtiRtemplates")
#'   file.copy(src, dir, recursive = TRUE)
#'   study <- file.path(dir, "ar-study")
#'   report <- file.path(study, "50_documents", "ar.dead.question.qmd")
#'   # ar_item() runs inside the report's chunks, so knit the report.
#'   md <- knitr::knit(report, output = tempfile(fileext = ".md"), quiet = TRUE)
#'   writeLines(grep("^[*][*]Item|^[[]The full", readLines(md), value = TRUE))
#'   unlink(dir, recursive = TRUE)
#' }
#' @export
ar_item <- function(id) {
  input <- .ar_input()
  root <- .ar_root(input)
  items <- .ar_parse(readLines(input, warn = FALSE))
  it <- items[vapply(items, `[[`, "", "id") == id]
  if (length(it) != 1L) stop("ar_item() takes its id as a literal string, so ar_paste_methods() can read it.", call. = FALSE)
  r <- .ar_resolve(id, root)
  knitr::asis_output(paste(.ar_item_markdown(r, it[[1L]], dirname(input)), collapse = "\n"))
}

#' Quote a saved value in an ar analysis report
#'
#' @description Reads one field of a value a finished job saved for its report,
#'   so a number in the Results text comes from the fit and goes stale with it,
#'   rather than being retyped. The source run must be final and its file
#'   unchanged, as for [ar_item()]. When the source job has been
#'   edited since its render, a final render (`render_job(final = TRUE)`)
#'   stops, and a draft warns.
#'
#' @param id The value's item id, `"<job>#<label>"`.
#' @param field The field to return.
#' @return The field's value.
#' @examples
#' if (requireNamespace("knitr", quietly = TRUE)) {
#'   # A copy of a small study shipped with the package: one finished hz job and
#'   # an ar report citing two of its exhibits.
#'   dir <- tempfile("ar-")
#'   dir.create(dir)
#'   src <- system.file("extdata", "ar-study", package = "hvtiRtemplates")
#'   file.copy(src, dir, recursive = TRUE)
#'   study <- file.path(dir, "ar-study")
#'   # In a report this is inline R: `r hvtiRtemplates::ar_value("hz.dead.hz#methods", "n")`.
#'   # From the console it finds the study above the working directory.
#'   old <- setwd(study)
#'   print(ar_value("hz.dead.hz#methods", "n"))
#'   setwd(old)
#'   unlink(dir, recursive = TRUE)
#' }
#' @export
ar_value <- function(id, field) {
  if (!requireNamespace("knitr", quietly = TRUE)) stop("ar_value() needs the knitr package.", call. = FALSE)
  input <- knitr::current_input(dir = TRUE)
  root <- if (is.null(input)) normalizePath(.find_study_root(getwd()), winslash = "/") else .ar_root(input)
  r <- .ar_resolve(id, root)
  if (!identical(r$exhibit$kind, "value")) {
    stop("Item '", id, "' is a ", r$exhibit$kind, ", not a saved value; ar_value() reads values only.", call. = FALSE)
  }
  # A final report quoting a number its job no longer produces is the failure the ar layer exists to stop, so a final
  # render refuses; a draft warns, so the report can still be read while the job is reworked.
  if (isTRUE(r$source_changed)) {
    if (.strict_render()) {
      stop("ar_value(): the source job '", r$job, "' has been edited since its last render, so '", id, "' may be out ",
           "of date, and a final render does not quote it. Render the job again, then this report.", call. = FALSE)
    }
    warning("ar_value(): the source job '", r$job, "' has been edited since its last render, so '", id,
            "' may be out of date. Render the job again before relying on this value.", call. = FALSE)
  }
  x <- readRDS(r$path)
  if (!is.character(field) || length(field) != 1L || !field %in% names(x)) {
    stop("Item '", id, "' has no field ", encodeString(as.character(field)[1L], quote = "'"), "; it has: ",
         paste(names(x), collapse = ", "), ".", call. = FALSE)
  }
  x[[field]]
}
