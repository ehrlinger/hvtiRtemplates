#' Stop a long fit from starting where it would die with the session
#'
#' @description
#' A template calls this just before an expensive \code{cache_fit()}. With no
#' cached result yet, it stops and says to run the job with \code{\link{run_job}}
#' instead, because a fit that runs for hours dies with the Workbench session
#' that started it. It stops in an interactive session (the console, or running
#' chunks one by one) and in a render the session launched, which is what the
#' RStudio or Posit Workbench Render button does. A cached result, a render
#' started by \code{\link{submit_job}} or \code{\link{run_job}}, a render from a
#' terminal, or \code{options(hvtiRtemplates.allow_interactive_fit = TRUE)} lets
#' it pass, so once the fit is cached the Render button works again.
#'
#' @details
#' A render is session-launched when \env{RSTUDIO} is \code{"1"} and
#' \env{RSTUDIO_TERM} is unset. Every process the RStudio session starts inherits
#' \env{RSTUDIO}; only a shell in its Terminal tab also carries
#' \env{RSTUDIO_TERM}, so a \code{nohup quarto render} typed there, or from an
#' ssh login, passes. A render from \code{submit_job()} carries
#' \env{HVTI_JOB_MARKER} and passes wherever it was submitted from. RStudio on
#' Windows does not set \env{RSTUDIO_TERM}, so there a terminal render inside
#' RStudio is stopped too.
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
  interactive <- rlang::is_interactive()
  if ((!interactive && !.session_render()) || isTRUE(getOption("hvtiRtemplates.allow_interactive_fit")) ||
        (!isTRUE(refit) && all(file.exists(file.path(dir, paste0(name, ".rds")))))) {
    return(invisible(FALSE))
  }
  job <- if (requireNamespace("knitr", quietly = TRUE)) knitr::current_input(dir = TRUE) else NULL
  call <- sprintf("hvtiRtemplates::run_job(\"%s\")", if (is.null(job)) "<this job>.qmd" else job)
  state <- if (isTRUE(refit)) "is being recomputed (REFIT)" else "is not cached yet"
  where <- if (interactive) {
    "run interactively it dies with the session"
  } else {
    "rendered with the Render button it runs inside the Workbench session and dies when that session times out"
  }
  after <- if (interactive) {
    "Once the fit is cached, these chunks run interactively and load it. "
  } else {
    "Once the fit is cached, the Render button works again and re-renders the figures from the cache. "
  }
  stop("This fit ", state, ", and ", why, ": ", where, ". ",
       "Run the job in the background instead:\n  ", call, "\nthen check it with hvtiRtemplates::job_status(). ",
       after, "For a deliberate small test, set options(hvtiRtemplates.allow_interactive_fit = TRUE).", call. = FALSE)
}

# TRUE for a non-interactive render the RStudio / Posit Workbench session launched itself (the Render button, or
# render_job() from the console), which dies with the session. submit_job() marks its renders with HVTI_JOB_MARKER;
# a Terminal-tab shell carries RSTUDIO_TERM beside the RSTUDIO=1 every child of the session inherits.
.session_render <- function() {
  !nzchar(Sys.getenv("HVTI_JOB_MARKER")) && identical(Sys.getenv("RSTUDIO"), "1") && !nzchar(Sys.getenv("RSTUDIO_TERM"))
}
