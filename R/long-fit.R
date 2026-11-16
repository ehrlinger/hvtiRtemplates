#' Stop a long fit from starting anywhere but a background run
#'
#' @description
#' A template calls this just before an expensive \code{cache_fit()}, once
#' \code{hvtiRutilities::cache_would_fit()} has said the fit will be computed
#' rather than loaded. With no cached result it stops and says to run the job
#' with \code{\link{run_job}}, because a fit that runs for hours dies with the
#' Workbench session that started it: the console, a chunk run by hand, the
#' Render button, and a \code{quarto render} typed in the Terminal tab, which is
#' a child of the session too, \code{nohup} or not. Only a render started by
#' \code{\link{run_job}} or \code{\link{submit_job}} passes, with a cached result
#' or an explicit opt-in. Once the fit is cached, the Render button works again
#' and re-renders the job from the cache.
#'
#' @details
#' A render started by \code{submit_job()} carries \env{HVTI_JOB_MARKER}, which
#' is how it is told apart. The opt-in is
#' \code{options(hvtiRtemplates.allow_interactive_fit = TRUE)} in the session, or
#' \env{HVTI_ALLOW_LONG_FIT} set to \code{"true"}, which a render's own R
#' process inherits where an option set in the session does not: the package's
#' tests and the template gallery render small fits that way. Set either only
#' for a fit you know to be short.
#'
#' @param name Character. The \code{cache_fit()} name, or several when one long step writes several caches;
#'   each cache file is \code{<dir>/<name>.rds}, and the call is refused while any of them is missing.
#' @param dir Character(1). The \code{cache_fit()} directory.
#' @param why Character(1). Why the fit is long, shown in the error.
#' @param refit Logical(1). \code{TRUE} when the job will recompute the fit even though a cached file exists (the
#'   template's \code{REFIT}); the cached file then does not make the call safe, so it is refused too.
#' @return \code{invisible(FALSE)} when the fit may proceed; otherwise an error.
#' @examples
#' guard_long_fit("example-fit", dir = tempdir(), why = "it takes hours")
#' @export
guard_long_fit <- function(name, dir, why, refit = FALSE) {
  if (!is.character(name) || !length(name) || anyNA(name) || !all(nzchar(name))) {
    stop("guard_long_fit(): `name` must be one or more non-empty strings.", call. = FALSE)
  }
  if (!is.character(dir) || length(dir) != 1L || is.na(dir)) {
    stop("guard_long_fit(): `dir` must be a single directory path.", call. = FALSE)
  }
  if (!is.logical(refit) || length(refit) != 1L || is.na(refit)) {
    stop("guard_long_fit(): `refit` must be TRUE or FALSE.", call. = FALSE)
  }
  if (nzchar(Sys.getenv("HVTI_JOB_MARKER")) || isTRUE(getOption("hvtiRtemplates.allow_interactive_fit")) ||
        isTRUE(as.logical(Sys.getenv("HVTI_ALLOW_LONG_FIT"))) ||
        (!isTRUE(refit) && all(file.exists(file.path(dir, paste0(name, ".rds")))))) {
    return(invisible(FALSE))
  }
  job <- if (requireNamespace("knitr", quietly = TRUE)) knitr::current_input(dir = TRUE) else NULL
  call <- sprintf("hvtiRtemplates::run_job(\"%s\")", if (is.null(job)) "<this job>.qmd" else job)
  state <- if (isTRUE(refit)) "is being recomputed (REFIT)" else "is not cached yet"
  stop("This fit ", state, ", and ", why, ": run from the console, the Render button or a terminal it dies with the ",
       "Workbench session. Run the job in the background instead, from the study's R console:\n  ", call,
       "\nthen check it with hvtiRtemplates::job_status(). Once the fit is cached, the Render button and these chunks ",
       "work again and load it. For a fit you know to be short, set ",
       "options(hvtiRtemplates.allow_interactive_fit = TRUE).", call. = FALSE)
}
