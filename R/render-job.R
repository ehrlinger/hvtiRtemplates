#' Render a job
#'
#' @description
#' Renders a job from its own directory. By default the render is a draft:
#' open \code{EDIT:} markers appear in the report's DRAFT banner. With
#' \code{final = TRUE} an unfinished job stops instead, as the render of an
#' accepted result should.
#'
#' @details
#' \code{final = TRUE} sets \code{HVTI_TEMPLATE_STRICT} to \code{1} for this
#' render only and restores its previous value afterwards, including after an
#' error. The job's own edit guard decides whether it is finished; this
#' function does not search for markers itself, so it cannot disagree with a
#' render started from the editor or from Quarto.
#'
#' Jobs scaffolded by \code{\link{add_job}} capture their data provenance while
#' executing and embed it in the completed HTML. The same project hooks used by
#' the Render button and bare Quarto commands then publish a same-stem
#' \code{.provenance.json} sidecar beside the actual output. A failed render or
#' publication leaves no current sidecar.
#'
#' @param path Character. Path to a job \code{.qmd} file.
#' @param final Logical. \code{TRUE} for the accepted result.
#' @param quiet Logical. Passed to \code{quarto::quarto_render()}.
#'
#' @return \code{path}, invisibly.
#'
#' @seealso \code{\link{open_job}}
#' @export
render_job <- function(path, final = FALSE, quiet = FALSE) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !file.exists(path) || dir.exists(path)) {
    stop("render_job(): `path` must be an existing job file.", call. = FALSE)
  }
  if (!is.logical(final) || length(final) != 1L || is.na(final)) {
    stop("render_job(): `final` must be TRUE or FALSE.", call. = FALSE)
  }
  if (!requireNamespace("quarto", quietly = TRUE)) {
    stop("render_job(): the quarto package is required; install.packages(\"quarto\").", call. = FALSE)
  }
  path <- normalizePath(path, winslash = "/")
  if (final) {
    old <- Sys.getenv("HVTI_TEMPLATE_STRICT", unset = NA)
    on.exit(if (is.na(old)) Sys.unsetenv("HVTI_TEMPLATE_STRICT") else Sys.setenv(HVTI_TEMPLATE_STRICT = old),
            add = TRUE)
    Sys.setenv(HVTI_TEMPLATE_STRICT = "1")
  }
  quarto::quarto_render(path, execute_dir = dirname(path), quiet = quiet)
  invisible(path)
}
