#' Install a study's Quarto provenance hooks
#'
#' @description
#' Adds the pre-render and post-render hooks that record a job's provenance to
#' the study's Quarto project file, and copies the hook scripts beside it.
#' [add_job()] and [upgrade_job()] do this themselves; call it directly for a
#' study whose jobs came from elsewhere, as [render_job()]'s message says when
#' a job that records its provenance is stopped for want of the hooks.
#'
#' @details
#' The study root is the nearest directory at or above `root` holding
#' `_study.yml`, so this can be called from anywhere inside a study. The
#' project file is the one Quarto reads at the study root, `_quarto.yml` or
#' `_quarto.yaml`, and it is updated in place; a study with both is refused,
#' since which one Quarto reads is not this function's to guess. The hooks are
#' added last in each list, after any the study already has, and every other
#' setting in the file is kept. Running it again changes nothing. If any file
#' cannot be written, the files already changed are restored.
#'
#' A study with neither file gets a `_quarto.yml`, which makes the study one
#' Quarto project and can change how its other documents render.
#'
#' @param root Character. Any directory inside the study. `NULL`, the
#'   default, starts from the working directory, and is an error outside a
#'   study.
#'
#' @return The path to the study's project file, `_quarto.yml` or
#'   `_quarto.yaml`, invisibly.
#'
#' @seealso [add_job()], [render_job()]
#' @examples
#' root <- file.path(tempdir(), "hooks-example")
#' suppressMessages(hvtiRutilities::study_setup(
#'   root, study = "Example", study_tracker_id = 1L, renv = FALSE
#' ))
#' install_provenance_hooks(root)
#' unlink(root, recursive = TRUE)
#' @export
install_provenance_hooks <- function(root = NULL) {
  root <- if (is.null(root)) .default_study_root("install_provenance_hooks") else hvtiRutilities::study_root(root)
  .install_provenance_hooks(root)
}
