# Reading and writing an ar job file: one item per ar_item("<job>#<label>")
# call, running to the next; its ::: methods div; and the review stamp, the
# first line inside that div. Run from the console, never during render: a
# render that edits its own source breaks the checksum provenance records.
# dev/specs/2026-11-11-ar-question-report-design.md, sections 5.4 and 5.5.

.ar_call_pattern <- '^\\s*(hvtiRtemplates::)?ar_item\\(\\s*"([^"]+)"'
.ar_stamp_pattern <- "^<!-- ar-stamp (\\{.*\\}) -->$"

.ar_parse <- function(lines) {
  calls <- grep(.ar_call_pattern, lines)
  ids <- sub(paste0(.ar_call_pattern, ".*$"), "\\2", lines[calls])
  for (id in ids) .ar_parse_id(id)
  dup <- anyDuplicated(ids)
  if (dup) stop("Item '", ids[[dup]], "' is cited twice in this report; cite each exhibit once.", call. = FALSE)
  ends <- c(calls[-1L] - 1L, length(lines))
  lapply(seq_along(calls), function(i) {
    region <- seq.int(calls[[i]], ends[[i]])
    open <- region[grepl("^:::+\\s*\\{?\\.?methods\\}?\\s*$", lines[region])][1L]
    close <- if (is.na(open)) NA_integer_ else region[region > open & grepl("^:::+\\s*$", lines[region])][1L]
    body <- if (is.na(open) || is.na(close)) integer() else seq_len(close - open - 1L) + open
    stamp_line <- body[grepl(.ar_stamp_pattern, lines[body])][1L]
    stamp <- if (is.na(stamp_line)) {
      NULL
    } else {
      jsonlite::fromJSON(sub(.ar_stamp_pattern, "\\1", lines[[stamp_line]]), simplifyVector = FALSE)
    }
    prose <- lines[setdiff(body, stamp_line)]
    list(id = ids[[i]], index = i, call_line = calls[[i]], open = open, close = close, stamp_line = stamp_line,
         stamp = stamp, empty = is.na(stamp_line) && all(grepl("^\\s*$", prose) | grepl("^\\s*<!--.*-->\\s*$", prose)))
  })
}

.ar_stamp_line <- function(r) {
  paste0("<!-- ar-stamp ", jsonlite::toJSON(list(
    item = r$id, methods_sha256 = .ar_methods(r)$sha256,
    rendered = r$sidecar$rendered, exhibit_sha256 = r$exhibit$sha256
  ), auto_unbox = TRUE), " -->")
}

.ar_root <- function(path) normalizePath(.find_study_root(dirname(normalizePath(path, mustWork = TRUE))), winslash = "/")

.ar_write <- function(lines, path) {
  tmp <- tempfile(tmpdir = dirname(path), fileext = ".qmd")
  writeLines(lines, tmp)
  Sys.chmod(tmp, file.mode(path), use_umask = FALSE)
  if (!file.rename(tmp, path)) {
    unlink(tmp)
    stop("Could not write '", path, "'.", call. = FALSE)
  }
}

.ar_console_only <- function(fn) {
  if (isTRUE(getOption("knitr.in.progress"))) {
    stop(fn, "() edits the report's source, so run it from the console; it must not be called inside a render.", call. = FALSE)
  }
}

.ar_need_div <- function(it) {
  if (is.na(it$open) || is.na(it$close)) {
    stop("Item '", it$id, "' has no ::: methods div; add one under its ar_item() chunk.", call. = FALSE)
  }
}

#' Paste each item's Methods boilerplate into an ar report
#'
#' @description Writes the Methods paragraph each cited job recorded into every
#'   \strong{empty} \code{::: methods} div of an \code{ar} analysis report, with a
#'   review stamp, so the analyst edits text that starts from the job's own
#'   choices. A div that already holds text is never touched.
#'
#' @details Run from the console, not from inside the render: a render that
#'   edits its own source would break the checksum its provenance records. Every
#'   item is resolved before anything is written, so an item that fails (a draft
#'   source, a missing exhibit) leaves the file exactly as it was.
#'
#' @param path Path to the \code{ar} job file.
#' @param root The study root. \code{NULL} finds it above \code{path}.
#' @return The ids of the items pasted, invisibly, in file order.
#' @seealso \code{\link{ar_review}}, \code{\link{ar_item}}
#' @examples
#' \donttest{
#' # ar_paste_methods("documents/ar.dead.question.qmd")
#' }
#' @export
ar_paste_methods <- function(path, root = NULL) {
  .ar_console_only("ar_paste_methods")
  lines <- readLines(path, warn = FALSE)
  if (is.null(root)) root <- .ar_root(path)
  items <- .ar_parse(lines)
  if (!length(items)) stop("No ar_item() calls in '", path, "'.", call. = FALSE)
  plans <- lapply(items, function(it) {
    .ar_need_div(it)
    if (!it$empty) return(NULL)
    r <- .ar_resolve(it$id, root)
    list(it = it, insert = c(.ar_stamp_line(r), "", .ar_methods(r)$text))
  })
  plans <- Filter(Negate(is.null), plans)
  for (p in rev(plans)) {
    lines <- c(lines[seq_len(p$it$open)], p$insert, lines[p$it$close:length(lines)])
  }
  if (length(plans)) .ar_write(lines, path)
  invisible(vapply(plans, function(p) p$it$id, ""))
}

#' Mark ar report items as reviewed against their sources' current runs
#'
#' @description After rereading an item's methods, results and interpretation
#'   against a source job that has been rendered again, \code{ar_review()}
#'   moves that item's review stamp to the job's current run, which clears the
#'   report's callout. The analyst's text is not changed.
#'
#' @param path Path to the \code{ar} job file.
#' @param item Item ids to stamp, such as \code{"hz.dead.hz#fig-fit"}.
#'   \code{NULL} stamps every item.
#' @param root The study root. \code{NULL} finds it above \code{path}.
#' @return The ids of the items stamped, invisibly.
#' @seealso \code{\link{ar_paste_methods}}
#' @examples
#' \donttest{
#' # ar_review("documents/ar.dead.question.qmd", "hz.dead.hz#fig-fit")
#' }
#' @export
ar_review <- function(path, item = NULL, root = NULL) {
  .ar_console_only("ar_review")
  lines <- readLines(path, warn = FALSE)
  if (is.null(root)) root <- .ar_root(path)
  items <- .ar_parse(lines)
  ids <- vapply(items, `[[`, "", "id")
  if (!is.null(item)) {
    unknown <- setdiff(item, ids)
    if (length(unknown)) stop("Not an item in this report: ", paste(unknown, collapse = ", "), ".", call. = FALSE)
    items <- items[ids %in% item]
  }
  for (it in items) {
    if (is.na(it$stamp_line)) stop("Item '", it$id, "' was never pasted; run ar_paste_methods() first.", call. = FALSE)
  }
  stamps <- lapply(items, function(it) .ar_stamp_line(.ar_resolve(it$id, root)))
  for (i in seq_along(items)) lines[[items[[i]]$stamp_line]] <- stamps[[i]]
  if (length(items)) .ar_write(lines, path)
  invisible(vapply(items, `[[`, "", "id"))
}
