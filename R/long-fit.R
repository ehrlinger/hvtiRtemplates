#' Stop a long fit from starting in an interactive session
#'
#' @description
#' A template calls this just before an expensive \code{cache_fit()}. In an
#' interactive session (the console, or running chunks one by one) with no
#' cached result yet, it stops and says to run the job with
#' \code{\link{submit_job}} instead, because a fit that runs for hours dies
#' with the session. A render, a cached result, or
#' \code{options(hvtiRtemplates.allow_interactive_fit = TRUE)} lets it pass.
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
  if (!rlang::is_interactive() || isTRUE(getOption("hvtiRtemplates.allow_interactive_fit")) ||
        (!isTRUE(refit) && all(file.exists(file.path(dir, paste0(name, ".rds")))))) {
    return(invisible(FALSE))
  }
  job <- if (requireNamespace("knitr", quietly = TRUE)) knitr::current_input(dir = TRUE) else NULL
  call <- sprintf("hvtiRtemplates::submit_job(\"%s\")", if (is.null(job)) "<this job>.qmd" else job)
  state <- if (isTRUE(refit)) "is being recomputed (REFIT)" else "is not cached yet"
  stop("This fit ", state, ", and ", why, ": run interactively it dies with the session. ",
       "Run the job in the background instead:\n  ", call, "\nthen check it with hvtiRtemplates::job_status(). ",
       "Once the fit is cached, these chunks run interactively and load it. ",
       "For a deliberate small test, set options(hvtiRtemplates.allow_interactive_fit = TRUE).", call. = FALSE)
}
