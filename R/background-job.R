.run_files <- function(path) {
  stem <- sub("[.]qmd$", "", path)
  list(log = paste0(stem, ".run.log"), status = paste0(stem, ".run.yml"), runner = paste0(stem, ".runner"),
       progress = paste0(stem, ".run.progress"))
}

.pid_alive <- function(pid) {
  if (is.null(pid) || is.na(suppressWarnings(as.integer(pid)))) return(FALSE)
  isTRUE(tryCatch(ps::ps_is_running(ps::ps_handle(as.integer(pid))), error = function(e) FALSE))
}

.write_status <- function(file, ...) {
  tmp <- paste0(file, ".tmp")
  yaml::write_yaml(list(...), tmp)
  if (!file.rename(tmp, file)) stop(".write_status(): could not rename ", tmp, " to ", file, ".", call. = FALSE)
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
  if (is.null(st) || !is.list(st) || !is.character(st$state) || length(st$state) != 1L) {
    stop("job_status(): the status file ", files$status, " cannot be read or records no state.", call. = FALSE)
  }
  known <- c("none", "submitted", "running", "finished", "failed", "vanished")
  if (!st$state %in% known) {
    stop("job_status(): the status file ", files$status, " records an unexpected state \"", st$state, "\".", call. = FALSE)
  }
  never_started <- FALSE
  other_host <- NULL
  if (identical(st$state, "running")) {
    host <- st$host
    if (is.character(host) && length(host) == 1L && !is.na(host) && !identical(host, Sys.info()[["nodename"]])) {
      other_host <- host  # sessions can land on different hosts; a pid can only be checked on its own
    } else if (!.pid_alive(st$pid)) {
      st$state <- "vanished"
    }
  }
  if (identical(st$state, "submitted")) {
    at <- as.POSIXct(st$submitted, format = "%Y-%m-%dT%H:%M:%S%z")
    if (is.na(at) || difftime(Sys.time(), at, units = "secs") > 120) {
      st$state <- "vanished"
      never_started <- TRUE
    }
  }
  st$log <- files$log
  if (!isTRUE(quiet)) {
    detail <- switch(st$state,
                     running = if (is.null(other_host)) {
                       sprintf(" (process %s, since %s)", st$pid, st$started)
                     } else {
                       sprintf(" (process %s, since %s, on host %s, so it cannot be checked from here)",
                               st$pid, st$started, other_host)
                     },
                     finished = sprintf(" in %s s", st$elapsed_s),
                     failed = sprintf(" with exit code %s; see %s", st$exit_code, files$log),
                     vanished = if (never_started) {
                       sprintf(": never started: no 'running' within 120 s; see %s%s", files$log,
                               if (!file.exists(files$log) || file.size(files$log) == 0L) " (log missing or empty)" else "")
                     } else {
                       sprintf(": the process is gone without recording an end; see %s", files$log)
                     },
                     "")
    cat(basename(path), ": ", st$state, detail, "\n", sep = "")
  }
  invisible(st)
}

.is_windows <- function() .Platform$OS.type == "windows"

# The runner is a separate Rscript process, so it uses only yaml and base R. Its status writes are atomic
# (write to .tmp, rename) because job_status() may read while it writes.
.runner_lines <- function(path, status, final, render_call) {
  c(sprintf("path <- %s", deparse(path)),
    sprintf("status <- %s", deparse(status)),
    sprintf("final <- %s", deparse(final)),
    "put <- function(x) {",
    "  tmp <- paste0(status, '.tmp'); yaml::write_yaml(x, tmp)",
    "  if (!file.rename(tmp, status)) stop('could not rename ', tmp, ' to ', status)",
    "  invisible(status)",
    "}",
    "started <- Sys.time()",
    "stamp <- function(t) format(t, '%Y-%m-%dT%H:%M:%S%z')",
    paste0("base <- list(pid = Sys.getpid(), host = Sys.info()[['nodename']], ",
           "r_version = as.character(getRversion()), started = stamp(started))"),
    "put(c(list(state = 'running'), base))",
    sprintf("ok <- tryCatch({ %s; TRUE }, error = function(e) { message('Error: ', conditionMessage(e)); FALSE })",
            render_call),
    "ended <- Sys.time()",
    paste0("put(c(list(state = if (ok) 'finished' else 'failed', exit_code = if (ok) 0L else 1L), base, ",
           "list(ended = stamp(ended), elapsed_s = round(as.numeric(difftime(ended, started, units = 'secs'))))))"),
    "quit(save = 'no', status = if (ok) 0L else 1L)")
}

.submit_job <- function(path, final, render_call, root) {
  files <- .run_files(path)
  # "submitted" too: the gap before the runner records "running" must not let a second copy start.
  now <- job_status(path, quiet = TRUE)
  if (now$state %in% c("submitted", "running")) {
    other <- if (identical(now$state, "running") && is.character(now$host) && !identical(now$host, Sys.info()[["nodename"]])) {
      paste0(" Recorded on host ", now$host, "; if that host is gone, confirm the job is not running there, then delete ",
             files$status, " and submit again.")
    } else {
      ""
    }
    stop("submit_job(): ", basename(path), " is already running; see job_status().", other, call. = FALSE)
  }
  rscript <- file.path(R.home("bin"), "Rscript")
  if (file.access(rscript, 1L) != 0L) stop("submit_job(): cannot execute ", rscript, ".", call. = FALSE)
  if (!suppressWarnings(file.create(files$log))) stop("submit_job(): cannot write the log file ", files$log, ".", call. = FALSE)
  writeLines(.runner_lines(path, files$status, final, render_call), files$runner)
  .write_status(files$status, state = "submitted", submitted = .stamp())
  setsid <- if (nzchar(Sys.which("setsid"))) "setsid " else ""
  cmd <- sprintf("cd %s && exec %snohup %s %s > %s 2>&1 < /dev/null",
                 shQuote(root), setsid, shQuote(rscript), shQuote(files$runner), shQuote(files$log))
  system(cmd, wait = FALSE)  # wait = FALSE appends the "&" itself
  invisible(job_status(path, quiet = TRUE))
}

#' Render a job in the background, detached from the session
#'
#' @description
#' Starts \code{\link{render_job}} on the job in a separate process that
#' outlives the R session, the way \code{nohup} from a terminal does, and
#' returns at once. Use it for a job whose fit runs for hours: a Workbench
#' session that times out takes a console run with it.
#'
#' @details
#' The process runs the \code{Rscript} of the R that called
#' \code{submit_job()}, from the study root, so the study's \code{renv} and
#' \code{.Renviron} apply. It writes \code{<job>.run.log} (everything the render
#' prints) and \code{<job>.run.yml} (its state) beside the job; read the state
#' with \code{\link{job_status}}. A job already running is not started twice.
#' Not available on Windows, which cannot detach a process this way.
#'
#' @param path Character(1). The job's \code{.qmd} file.
#' @param final Logical(1). Passed to \code{\link{render_job}}.
#' @return Invisibly, the job's status, as \code{\link{job_status}} returns it.
#' @examples
#' # Not run by check: it would start a real render.
#' \dontrun{
#' submit_job("analyses/nb.boostmtree.lvef.boost.qmd")
#' }
#' @export
submit_job <- function(path, final = FALSE) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !file.exists(path) || dir.exists(path)) {
    stop("submit_job(): `path` must be an existing job file.", call. = FALSE)
  }
  if (!is.logical(final) || length(final) != 1L || is.na(final)) {
    stop("submit_job(): `final` must be TRUE or FALSE.", call. = FALSE)
  }
  if (.is_windows()) {
    stop("submit_job(): Windows cannot detach a process from the session; render from a terminal instead.",
         call. = FALSE)
  }
  path <- normalizePath(path, winslash = "/")
  root <- .find_study_root(dirname(path))
  .submit_job(path, final, sprintf("hvtiRtemplates::render_job(path, final = %s)", deparse(final)), root)
}
