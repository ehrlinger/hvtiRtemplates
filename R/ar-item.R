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
    table = knitr::kable(readRDS(r$path), format = "pipe", row.names = FALSE),
    value = sprintf("Values saved for the text: %s.", paste0("`", names(readRDS(r$path)), "`", collapse = ", "))
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
#' @description Called once per item in an \code{ar} job. Finds the exhibit a
#'   finished job recorded under \code{id}, checks that the job last rendered as
#'   final and that the file still holds the bytes it recorded, and shows the
#'   exhibit with a link to the job's report. Callouts above it say what to
#'   check: a job edited since its render, Methods boilerplate that changed, or
#'   text written against an earlier run.
#'
#' @param id The item, \code{"<job>#<label>"}: the source job's file name
#'   without \code{.qmd}, and the chunk label it saved the exhibit under.
#' @return A \code{knit_asis} object holding the item's Markdown.
#' @seealso \code{\link{ar_value}}, \code{\link{ar_paste_methods}}, \code{\link{ar_review}}
#' @examples
#' \donttest{
#' # In an ar job's chunk:
#' # hvtiRtemplates::ar_item("hz.dead.hz#fig-fit")
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
#'   unchanged, as for \code{\link{ar_item}}.
#'
#' @param id The value's item id, \code{"<job>#<label>"}.
#' @param field The field to return.
#' @return The field's value.
#' @examples
#' \donttest{
#' # Inline in an ar job: `r hvtiRtemplates::ar_value("hz.dead.hz#methods", "n")` patients
#' }
#' @export
ar_value <- function(id, field) {
  input <- knitr::current_input(dir = TRUE)
  root <- if (is.null(input)) normalizePath(.find_study_root(getwd()), winslash = "/") else .ar_root(input)
  r <- .ar_resolve(id, root)
  if (!identical(r$exhibit$kind, "value")) {
    stop("Item '", id, "' is a ", r$exhibit$kind, ", not a saved value; ar_value() reads values only.", call. = FALSE)
  }
  x <- readRDS(r$path)
  if (!is.character(field) || length(field) != 1L || !field %in% names(x)) {
    stop("Item '", id, "' has no field ", encodeString(as.character(field)[1L], quote = "'"), "; it has: ",
         paste(names(x), collapse = ", "), ".", call. = FALSE)
  }
  x[[field]]
}
