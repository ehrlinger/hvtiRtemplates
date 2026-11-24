#' Open a job, creating it from its template if needed
#'
#' @description
#' Finds the study root from `root`, creates the job with
#' [add_job()] when it does not exist, and opens it in the editor.
#' An existing job is opened as it stands, never overwritten.
#'
#' @details
#' The study root is the nearest directory at or above `root` holding
#' `_study.yml`, so this can be called from anywhere inside a study.
#' Naming, prefix and qualifier rules are those of [add_job()].
#' A job scaffolded before 2026-10, named
#' `<subject>-<type>-<prefix>[-<qualifier>].qmd`, is found and opened
#' under that name. So is a job scaffolded under a template's name before a
#' rename, such as `graphs/dp.trends.<subject>.<type>.qmd` for
#' `dc.trends`, when the call names the new one.
#' The editor is opened only in an interactive session.
#'
#' @inheritParams add_job
#' @param root Character. Any directory inside the study. `NULL`, the
#'   default, starts from the working directory, and is an error outside a
#'   study.
#' @param dir Deprecated: the old name of `root`. It works, with a warning,
#'   for one more release; giving both is an error.
#'
#' @return The path to the job file, invisibly.
#'
#' @seealso [add_job()], [render_job()]
#' @examples
#' root <- file.path(tempdir(), "open-job-example")
#' suppressMessages(hvtiRutilities::study_setup(
#'   root, study = "Example", study_tracker_id = 1L, renv = FALSE
#' ))
#' open_job(prefix = "ac", subject = "death", type = "eda", root = root)
#' unlink(root, recursive = TRUE)
#' @export
open_job <- function(prefix, subject, type, root = NULL, qualifier = NULL, dir) {
  if (!missing(dir)) root <- .take_renamed("open_job", "dir", "root", dir, !missing(root))
  # The same message as add_job(), since a new user scaffolds through either.
  absent <- c("subject", "type")[c(missing(subject), missing(type))]
  if (length(absent)) {
    stop(.missing_field_message(absent, if (!missing(prefix)) prefix, qualifier, fn = "open_job"), call. = FALSE)
  }
  root <- if (is.null(root)) .default_study_root("open_job") else hvtiRutilities::study_root(root)
  row <- tryCatch(
    .select_template(template_list(), prefix, qualifier),
    error = function(e) stop("open_job(): ", conditionMessage(e), call. = FALSE)
  )
  .check_field("subject", subject, fn = "open_job")
  .check_field("type", type, fn = "open_job")
  .warn_if_deprecated(row, "open_job")
  out <- .job_path(row, subject, type, root)
  # A job scaffolded before 2026-10 keeps its dash spelling, and one scaffolded
  # under the template's name before a rename keeps that name; open either
  # rather than scaffold a second, empty copy under the new name.
  if (!file.exists(out)) {
    earlier <- c(.job_path_legacy(row, subject, type, root), .job_paths_renamed(row, subject, type, root))
    earlier <- earlier[file.exists(earlier)]
    if (length(earlier)) out <- earlier[[1L]]
  }
  if (file.exists(out)) {
    .hvti_inform("open_job(): '", out, "' already exists; opening it unchanged.")
  } else {
    # Warned above already; add_job()'s own warning would say it twice.
    out <- withCallingHandlers(
      add_job(prefix, subject, type, root = root, qualifier = qualifier, open = FALSE),
      hvtiRtemplates_deprecated = function(w) invokeRestart("muffleWarning")
    )
  }
  .open_in_editor(out)
}

# utils::file.edit() opens the RStudio source pane when RStudio is running and
# the configured editor otherwise, with no dependency on rstudioapi.
# Every caller has written its file by now, so an editor that fails to open is a
# warning, never an error: an error would report a job that exists as not
# written, and a retry would then meet add_job()'s refusal to overwrite it.
.open_in_editor <- function(path) {
  if (rlang::is_interactive()) {
    tryCatch(utils::file.edit(path), error = function(e) {
      warning(warningCondition(
        paste0("'", path, "' was written, but the editor could not open it: ", conditionMessage(e),
               "\nOpen it yourself; nothing needs to be run again."),
        class = "hvtiRtemplates_editor_failed"
      ))
    })
  }
  invisible(path)
}
