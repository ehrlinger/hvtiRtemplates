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
#' @param name Character(1). The \code{cache_fit()} name; the cache file is
#'   \code{<dir>/<name>.rds}.
#' @param dir Character(1). The \code{cache_fit()} directory.
#' @param why Character(1). Why the fit is long, shown in the error.
#' @return \code{invisible(FALSE)} when the fit may proceed; otherwise an error.
#' @examples
#' guard_long_fit("example-fit", dir = tempdir(), why = "it takes hours")
#' @export
guard_long_fit <- function(name, dir, why) {
  if (!is.character(name) || length(name) != 1L || is.na(name) || !nzchar(name)) {
    stop("guard_long_fit(): `name` must be a single, non-empty string.", call. = FALSE)
  }
  if (!is.character(dir) || length(dir) != 1L || is.na(dir)) {
    stop("guard_long_fit(): `dir` must be a single directory path.", call. = FALSE)
  }
  if (!rlang::is_interactive() || isTRUE(getOption("hvtiRtemplates.allow_interactive_fit")) ||
        file.exists(file.path(dir, paste0(name, ".rds")))) {
    return(invisible(FALSE))
  }
  job <- if (requireNamespace("knitr", quietly = TRUE)) knitr::current_input(dir = TRUE) else NULL
  call <- sprintf("hvtiRtemplates::submit_job(\"%s\")", if (is.null(job)) "<this job>.qmd" else job)
  stop("This fit is not cached yet, and ", why, ": run interactively it dies with the session. ",
       "Run the job in the background instead:\n  ", call, "\nthen check it with job_status(). ",
       "Once the fit is cached, these chunks run interactively and load it. ",
       "For a deliberate small test, set options(hvtiRtemplates.allow_interactive_fit = TRUE).", call. = FALSE)
}
