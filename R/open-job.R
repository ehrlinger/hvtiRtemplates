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
#' @param dir Character. Any directory inside the study. \code{NULL}, the
#'   default, starts from the working directory, and is an error outside a
#'   study.
#'
#' @return The path to the job file, invisibly.
#'
#' @seealso \code{\link{add_job}}, \code{\link{render_job}}
#' @examples
#' root <- file.path(tempdir(), "open-job-example")
#' suppressMessages(hvtiRutilities::study_setup(
#'   root, study = "Example", study_tracker_id = 1L
#' ))
#' open_job(prefix = "ac", subject = "death", type = "eda", dir = root)
#' unlink(root, recursive = TRUE)
#' @export
open_job <- function(prefix, subject, type, dir = NULL, qualifier = NULL) {
  # The same message as add_job(), since a new user scaffolds through either.
  absent <- c("subject", "type")[c(missing(subject), missing(type))]
  if (length(absent)) {
    stop(.missing_field_message(absent, if (!missing(prefix)) prefix, qualifier, fn = "open_job"), call. = FALSE)
  }
  root <- if (is.null(dir)) .default_study_root("open_job") else hvtiRutilities::study_root(dir)
  row <- tryCatch(
    .select_template(template_list(), prefix, qualifier),
    error = function(e) stop("open_job(): ", conditionMessage(e), call. = FALSE)
  )
  .check_field("subject", subject, fn = "open_job")
  .check_field("type", type, fn = "open_job")
  .warn_if_deprecated(row, "open_job")
  out <- .job_path(row, subject, type, root)
  if (file.exists(out)) {
    message("open_job(): '", out, "' already exists; opening it unchanged.")
  } else {
    # Warned above already; add_job()'s own warning would say it twice.
    out <- withCallingHandlers(
      add_job(prefix, subject, type, dir = root, qualifier = qualifier),
      hvtiRtemplates_deprecated = function(w) invokeRestart("muffleWarning")
    )
  }
  .open_in_editor(out)
}

# utils::file.edit() opens the RStudio source pane when RStudio is running and
# the configured editor otherwise, with no dependency on rstudioapi.
.open_in_editor <- function(path) {
  if (interactive()) utils::file.edit(path)
  invisible(path)
}
