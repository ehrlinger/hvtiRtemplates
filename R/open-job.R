#' Open a job, creating it from its template if needed
#'
#' @description
#' Finds the study root from \code{dir}, creates the job with
#' \code{\link{add_job}} when it does not exist, and opens it in the editor.
#' An existing job is opened as it stands, never overwritten.
#'
#' @details
#' The study root is the nearest directory at or above \code{dir} holding
#' \code{_study.yml}, so this can be called from anywhere inside a study.
#' Naming, prefix and qualifier rules are those of \code{\link{add_job}}.
#' The editor is opened only in an interactive session.
#'
#' @inheritParams add_job
#' @param dir Character. Any directory inside the study. Defaults to the
#'   working directory.
#'
#' @return The path to the job file, invisibly.
#'
#' @seealso \code{\link{add_job}}, \code{render_job()}
#' @examples
#' root <- file.path(tempdir(), "open-job-example")
#' suppressMessages(hvtiRutilities::study_setup(
#'   root, study = "Example", study_tracker_id = 1L
#' ))
#' open_job("ac", "dead", "eda", dir = root)
#' unlink(root, recursive = TRUE)
#' @export
open_job <- function(prefix, endpoint, type, qualifier = NULL, dir = ".") {
  root <- hvtiRutilities::study_root(dir)
  row <- tryCatch(
    .select_template(template_list(), prefix, qualifier),
    error = function(e) stop("open_job(): ", conditionMessage(e), call. = FALSE)
  )
  .check_field("endpoint", endpoint, fn = "open_job")
  .check_field("type", type, fn = "open_job")
  out <- .job_path(row, endpoint, type, root)
  if (file.exists(out)) {
    message("open_job(): '", out, "' already exists; opening it unchanged.")
  } else {
    out <- add_job(prefix, endpoint, type, dir = root, qualifier = qualifier)
  }
  .open_in_editor(out)
}

# utils::file.edit() opens the RStudio source pane when RStudio is running and
# the configured editor otherwise, with no dependency on rstudioapi.
.open_in_editor <- function(path) {
  if (interactive()) utils::file.edit(path)
  invisible(path)
}
