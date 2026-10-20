.run_files <- function(path) {
  stem <- sub("[.]qmd$", "", path)
  list(log = paste0(stem, ".run.log"), status = paste0(stem, ".run.yml"), runner = paste0(stem, ".runner"))
}

.pid_alive <- function(pid) {
  if (is.null(pid) || is.na(suppressWarnings(as.integer(pid)))) return(FALSE)
  isTRUE(tryCatch(ps::ps_is_running(ps::ps_handle(as.integer(pid))), error = function(e) FALSE))
}

.write_status <- function(file, ...) {
  tmp <- paste0(file, ".tmp")
  yaml::write_yaml(list(...), tmp)
  file.rename(tmp, file)
  invisible(file)
}

.stamp <- function(time = Sys.time()) format(time, "%Y-%m-%dT%H:%M:%S%z")

#' Report a background job's state
#'
#' @description
#' Reads the status \code{\link{submit_job}} keeps beside a job,
#' \code{<job>.run.yml}. A job whose process was killed never records its
#' end, so a recorded \code{running} is checked against the process itself.
#'
#' @param path Character(1). The job's \code{.qmd} file.
#' @param quiet Logical(1). \code{FALSE} prints a one-line summary.
#' @return Invisibly, a list: \code{state} is one of \code{"none"},
#'   \code{"submitted"}, \code{"running"}, \code{"finished"}, \code{"failed"}
#'   or \code{"vanished"}; the other elements are what the status file
#'   recorded (\code{pid}, \code{started}, \code{ended}, \code{exit_code},
#'   \code{elapsed_s}, \code{r_version}), and \code{log}, the log file's path.
#' @examples
#' job <- file.path(tempdir(), "example.qmd")
#' writeLines("---\ntitle: example\n---", job)
#' job_status(job)
#' @export
job_status <- function(path, quiet = FALSE) {
  files <- .run_files(path)
  st <- if (file.exists(files$status)) {
    tryCatch(yaml::read_yaml(files$status), error = function(e) NULL)
  } else {
    list(state = "none")
  }
  if (is.null(st) || !is.character(st$state) || length(st$state) != 1L) {
    stop("job_status(): the status file ", files$status, " cannot be read or records no state.", call. = FALSE)
  }
  known <- c("none", "submitted", "running", "finished", "failed", "vanished")
  if (!st$state %in% known) {
    stop("job_status(): the status file ", files$status, " records an unexpected state \"", st$state, "\".", call. = FALSE)
  }
  if (identical(st$state, "running") && !.pid_alive(st$pid)) st$state <- "vanished"
  if (identical(st$state, "submitted")) {
    at <- as.POSIXct(st$submitted, format = "%Y-%m-%dT%H:%M:%S%z")
    if (is.na(at) || difftime(Sys.time(), at, units = "secs") > 120) st$state <- "vanished"
  }
  st$log <- files$log
  if (!isTRUE(quiet)) {
    detail <- switch(st$state,
                     running = sprintf(" (process %s, since %s)", st$pid, st$started),
                     finished = sprintf(" in %s s", st$elapsed_s),
                     failed = sprintf(" with exit code %s; see %s", st$exit_code, files$log),
                     vanished = sprintf(": the process is gone without recording an end; see %s", files$log),
                     "")
    cat(basename(path), ": ", st$state, detail, "\n", sep = "")
  }
  invisible(st)
}
