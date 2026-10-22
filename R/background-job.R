.run_files <- function(path) {
  stem <- sub("[.]qmd$", "", path)
  list(log = paste0(stem, ".run.log"), status = paste0(stem, ".run.yml"), runner = paste0(stem, ".runner"),
       progress = paste0(stem, ".run.progress"), lock = paste0(stem, ".run.lock"))
}

# A pid alone is not an identity: after reuse, any live process answers to it. When the status recorded the process's
# creation time, both must match; an older status without one is judged by the pid alone. NULL when no such process.
.job_handle <- function(pid, created = NULL) {
  if (is.null(pid) || is.na(suppressWarnings(as.integer(pid)))) return(NULL)
  tryCatch({
    h <- ps::ps_handle(as.integer(pid))
    ok <- ps::ps_is_running(h)
    created <- suppressWarnings(as.numeric(created))
    if (ok && length(created) == 1L && !is.na(created)) {
      # 60 s, erring toward "alive": pid reuse means a NEW process, whose creation time differs from a long-running
      # job's by far more than a minute, while Linux derives it from btime in /proc/stat (whole seconds) and clock
      # steps (chrony makestep, VM resume) shift it, so a tight bound could read a live job as vanished and let a
      # duplicate render start.
      ok <- abs(as.numeric(ps::ps_create_time(h)) - created) < 60
    }
    if (isTRUE(ok)) h else NULL
  }, error = function(e) NULL)
}

.pid_alive <- function(pid, created = NULL) !is.null(.job_handle(pid, created))

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
#' A render also keeps \code{<job>.run.progress}, read here; a render started
#' without \code{\link{submit_job}}, after the last submitted run or with none, is reported from that file alone.
#' A progress file older than the run the status file records is ignored.
#'
#' @details
#' A long step writes a line to the render log at most every
#' \code{getOption("hvtiRtemplates.progress_every", 10)} minutes.
#'
#' @param path Character(1). The job's \code{.qmd} file.
#' @param quiet Logical(1). \code{FALSE} prints a one-line summary.
#' @return Invisibly, a list: \code{state} is one of \code{"none"},
#'   \code{"submitted"}, \code{"running"}, \code{"finished"}, \code{"failed"},
#'   \code{"vanished"} or \code{"cancelled"} (stopped by \code{\link{cancel_job}}); the other elements are what the status file
#'   recorded (\code{pid}, \code{created}, \code{host}, \code{started},
#'   \code{ended}, \code{exit_code}, \code{elapsed_s}, \code{r_version},
#'   \code{reason}), and \code{log}, the log file's path.
#'   \code{progress}, the render's progress record when there is one, with
#'   \code{eta_s}, the estimated seconds left in the current stage, and
#'   \code{stale}, \code{TRUE} when it has not changed for three reporting
#'   intervals and at least 30 minutes. \code{diagnosis}, for a \code{failed}
#'   or \code{vanished} run whose log can be read, a list of \code{reason}, what
#'   went wrong in plain words, and \code{fix}, what to do about it; it is
#'   returned when \code{quiet} is \code{TRUE} too.
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
  known <- c("none", "submitted", "running", "finished", "failed", "vanished", "cancelled")
  if (!st$state %in% known) {
    stop("job_status(): the status file ", files$status, " records an unexpected state \"", st$state, "\".", call. = FALSE)
  }
  prog <- .progress_read(files$progress)
  # Progress is advisory: whatever its file holds, it must not stop the report of the job's state.
  unreadable <- list(error = paste0("cannot read ", files$progress, "; progress not shown"))
  # A progress file left by an earlier run is not this run's: compare it with the run the status file records.
  vs_run <- if (!identical(st$state, "none") && is.list(prog) && is.null(prog$error)) {
    tryCatch(.progress_vs_run(prog, st), error = function(e) "current")
  } else {
    "current"
  }
  if (identical(vs_run, "older")) prog <- NULL
  from_progress <- (identical(st$state, "none") || identical(vs_run, "newer")) && is.list(prog) && is.null(prog$error)
  if (from_progress) {
    st <- tryCatch(.state_from_progress(prog), error = function(e) {
      prog <<- unreadable
      st
    })
  }
  never_started <- FALSE
  other_host <- NULL
  if (identical(st$state, "running")) {
    host <- st$host
    if (is.character(host) && length(host) == 1L && !is.na(host) && !identical(host, Sys.info()[["nodename"]])) {
      other_host <- host  # sessions can land on different hosts; a pid can only be checked on its own
    } else if (!.pid_alive(st$pid, st$created)) {
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
  st$progress <- tryCatch(.progress_view(prog), error = function(e) unreadable)
  # The diagnosis is advisory and read from a log that may be anything; it must not stop the report.
  if (st$state %in% c("failed", "vanished") && !never_started && file.exists(files$log)) {
    st$diagnosis <- tryCatch(.diagnose_failure(readLines(files$log, warn = FALSE), st), error = function(e) NULL)
  }
  if (!isTRUE(quiet)) {
    detail <- switch(st$state,
                     running = if (is.null(other_host)) {
                       sprintf(" (process %s, since %s)", st$pid, st$started)
                     } else {
                       sprintf(" (process %s, since %s, on host %s, so it cannot be checked from here)",
                               st$pid, st$started, other_host)
                     },
                     finished = sprintf(" in %s s", st$elapsed_s),
                     failed = if (is.null(st$reason)) {
                       sprintf(" with exit code %s; see %s", st$exit_code, files$log)
                     } else {
                       sprintf(": %s; see %s", st$reason, files$log)
                     },
                     cancelled = sprintf(" at %s%s", st$ended, if (is.null(st$reason)) "" else paste0(": ", st$reason)),
                     vanished = if (never_started) {
                       sprintf(": never started: no 'running' within 120 s; see %s%s", files$log,
                               if (!file.exists(files$log) || file.size(files$log) == 0L) " (log missing or empty)" else "")
                     } else {
                       sprintf(": the process is gone without recording an end; see %s", files$log)
                     },
                     "")
    cat(basename(path), ": ", st$state, detail, "\n", sep = "")
    if (is.numeric(st$mem_peak_gib) && is.numeric(st$mem_limit_gib)) {
      cat(sprintf("  memory: %.1f of %.1f GiB (peak)\n", st$mem_peak_gib, st$mem_limit_gib))
    } else if (identical(st$state, "running") && .num1(st$progress$mem_gib)) {
      # While it runs, the use at the render's last progress write; the limit when that write could read it.
      cat(if (.num1(st$progress$mem_limit_gib)) {
        sprintf("  memory: %.1f of %.1f GiB (now)\n", st$progress$mem_gib, st$progress$mem_limit_gib)
      } else {
        sprintf("  memory: %.1f GiB in use\n", st$progress$mem_gib)
      })
    }
    if (!is.null(st$diagnosis)) {
      cat("  why: ", st$diagnosis$reason, "\n", sep = "")
      if (nzchar(st$diagnosis$fix)) cat("  fix: ", st$diagnosis$fix, "\n", sep = "")
    }
    lines <- tryCatch(.progress_lines(st$progress, st$state), error = function(e) paste0("  progress: ", unreadable$error))
    if (length(lines)) cat(lines, sep = "\n")
  }
  invisible(st)
}

.num1 <- function(x) is.numeric(x) && length(x) == 1L && !is.na(x)

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
    # The creation time lets job_status() tell this process from a later one that reuses the pid. Recording nothing is
    # safe: job_status() then falls back to the pid alone.
    paste0("created <- tryCatch(list(created = sprintf('%.6f', as.numeric(ps::ps_create_time(ps::ps_handle())))), ",
           "error = function(e) list())"),
    "stamp <- function(t) format(t, '%Y-%m-%dT%H:%M:%S%z')",
    paste0("base <- c(list(pid = Sys.getpid()), created, list(marker = Sys.getenv('HVTI_JOB_MARKER'), ",
           "host = Sys.info()[['nodename']], ",
           "r_version = as.character(getRversion()), started = stamp(started)))"),
    "put(c(list(state = 'running'), base))",
    sprintf("ok <- tryCatch({ %s; TRUE }, error = function(e) { message('Error: ', conditionMessage(e)); FALSE })",
            render_call),
    "ended <- Sys.time()",
    # Telemetry is advisory: any failure in reading or converting it yields list(), never an error that
    # would skip the terminal put() and leave a finished run looking vanished.
    "mem <- tryCatch(hvtiRtemplates:::.run_memory_fields(), error = function(e) list())",
    paste0("put(c(list(state = if (ok) 'finished' else 'failed', exit_code = if (ok) 0L else 1L), base, ",
           "list(ended = stamp(ended), elapsed_s = round(as.numeric(difftime(ended, started, units = 'secs')))), mem))"),
    "quit(save = 'no', status = if (ok) 0L else 1L)")
}

# mkdir is atomic: of two callers that reach this point together, one creates the directory and the other is refused,
# so a caller's status check and the submit or cancel that follows it cannot interleave with another's. The caller
# releases the claim.
.claim_run <- function(path, files, fn) {
  if (!dir.create(files$lock, showWarnings = FALSE)) {
    if (!dir.exists(files$lock)) stop(fn, "(): cannot create ", files$lock, ".", call. = FALSE)
    age <- difftime(Sys.time(), file.info(files$lock)$mtime, units = "secs")
    stop(fn, "(): ", basename(path), " is being submitted or cancelled by another call (", files$lock, " exists, ",
         if (is.na(age)) "age unknown" else sprintf("%.0f s old", age), "). ",
         "If no submit or cancel is in progress, a crashed one left it behind: delete that directory and try again.",
         call. = FALSE)
  }
  invisible(files$lock)
}

# Wrapped so tests can capture the command; wait = FALSE appends the "&" itself.
.launch <- function(cmd) system(cmd, wait = FALSE)

.submit_job <- function(path, final, render_call, root) {
  files <- .run_files(path)
  .claim_run(path, files, "submit_job")
  on.exit(unlink(files$lock, recursive = TRUE), add = TRUE)
  # "submitted" too: the gap before the runner records "running" must not let a second copy start.
  now <- job_status(path, quiet = TRUE)
  if (now$state %in% c("submitted", "running")) {
    # job_status() reads <job>.run.progress as well as <job>.run.yml, so deleting the status file alone still refuses.
    hint <- if (identical(now$state, "running") && is.character(now$host) && !identical(now$host, Sys.info()[["nodename"]])) {
      paste0(" It is recorded on host ", now$host, ": stop it with cancel_job() in a session there. If that host is ",
             "gone, confirm the job is not running there, then delete both ", files$status, " and ", files$progress,
             " and submit again.")
    } else {
      " Stop it with cancel_job() first."
    }
    stop("submit_job(): ", basename(path), " is already running; see job_status().", hint, call. = FALSE)
  }
  rscript <- file.path(R.home("bin"), "Rscript")
  if (file.access(rscript, 1L) != 0L) stop("submit_job(): cannot execute ", rscript, ".", call. = FALSE)
  if (!suppressWarnings(file.create(files$log))) stop("submit_job(): cannot write the log file ", files$log, ".", call. = FALSE)
  writeLines(.runner_lines(path, files$status, final, render_call), files$runner)
  # The last run's progress is not this one's; job_status() would report it until the render writes its own.
  unlink(files$progress)
  .write_status(files$status, state = "submitted", submitted = .stamp())
  setsid <- if (nzchar(Sys.which("setsid"))) "setsid " else ""
  # Every process the render starts inherits the marker, including those processx moves into a session of its own
  # (Quarto, knitr) and those a dead parent orphans, so cancel_job() finds them all by it. ps::ps_find_tree() reads
  # it as PS<id>_<epoch>, matching only processes created after <epoch>. Built without the RNG, which is the study's.
  now <- Sys.time()
  marker <- sprintf("PSHVTI%d%s_%d", Sys.getpid(), format(now, "%H%M%OS6"), as.integer(now))
  marker <- gsub("[^A-Za-z0-9_]", "", marker)
  # HVTI_RUN_R names the R that submitted the job; .job_setup() stops the render if Quarto's knitr runs on another.
  # HVTI_RUN_R_VERSION gives its version, so the refusal can name both Rs by version as well as by path.
  cmd <- sprintf(paste0("cd %s && %s=YES HVTI_JOB_MARKER=%s HVTI_RUN_R=%s HVTI_RUN_R_VERSION=%s && ",
                        "export %s HVTI_JOB_MARKER HVTI_RUN_R HVTI_RUN_R_VERSION && ",
                        "exec %snohup %s %s > %s 2>&1 < /dev/null"),
                 shQuote(root), marker, marker, shQuote(.r_home()), shQuote(as.character(.session_r())), marker, setsid,
                 shQuote(rscript), shQuote(files$runner), shQuote(files$log))
  .launch(cmd)
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
#' with \code{\link{job_status}}. A job already running is not started twice: a
#' \code{<job>.run.lock} directory is taken while a submit is in progress, and a
#' submit that crashed can leave it behind, in which case delete it to try again.
#' Stop a submitted job with \code{\link{cancel_job}}.
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

# The job's processes: the runner and its descendants, through a handle that refuses a reused pid, and every process
# carrying the run's marker, which reaches the render that processx starts in a session of its own and any orphan.
.job_procs <- function(h, marker) {
  procs <- if (is.null(h)) list() else c(list(h), tryCatch(ps::ps_children(h, recursive = TRUE), error = function(e) list()))
  if (.is_marker(marker)) {
    procs <- c(procs, tryCatch(ps::ps_find_tree(marker), error = function(e) list()))
  }
  procs[!duplicated(vapply(procs, ps::ps_pid, 0L))]
}

.running <- function(p) isTRUE(tryCatch(ps::ps_is_running(p), error = function(e) FALSE))

.is_marker <- function(marker) is.character(marker) && length(marker) == 1L && grepl("^PS[A-Za-z0-9]+_[0-9]+$", marker)

# job_status() allows a minute of creation-time drift, so as not to read a live job as gone; signalling must not.
# The recorded process is the run's only if it carries the run's marker or, for a run recorded without one, if its
# creation time matches to the second. A live process without the marker took the pid, and is not the job's.
.cancel_handle <- function(st, fn = "cancel_job") {
  h <- .job_handle(st$pid, st$created)
  if (is.null(h)) return(NULL)
  ambiguous <- function(why) {
    stop(fn, "(): process ", st$pid, " may not be the job's, ", why, ". Check it by hand and stop it if it is the ",
         "render; cancel_job() then records the end.", call. = FALSE)
  }
  if (.is_marker(st$marker)) {
    env <- tryCatch(unclass(ps::ps_environ(h)), error = function(e) NULL)
    if (is.null(env)) ambiguous("for its environment cannot be read to look for the run's marker")
    return(if (isTRUE(env[st$marker] == "YES")) h else NULL)
  }
  drift <- abs(as.numeric(ps::ps_create_time(h)) - as.numeric(st$created))
  if (!isTRUE(drift < 1)) ambiguous(sprintf("for it began %.0f s from the recorded start", drift))
  h
}

# SIGTERM, `grace` seconds to finish, then SIGKILL and 5 more. Every check scans afresh, and a process that appears
# meanwhile (a child started from a SIGTERM handler, say) is signalled when found, so the job is stopped only once a
# fresh scan finds nothing. Returns the pids still running, none on success.
.stop_procs <- function(discover, grace) {
  key <- function(l) vapply(l, function(p) paste(ps::ps_pid(p), tryCatch(ps::ps_create_time(p), error = function(e) "")), "")
  run <- new.env()
  run$live <- list()
  run$sig <- ps::signals()$SIGTERM
  scan <- function() {
    found <- Filter(.running, c(run$live, discover()))
    found <- found[!duplicated(key(found))]
    for (p in found[!key(found) %in% key(run$live)]) try(ps::ps_send_signal(p, run$sig), silent = TRUE)
    run$live <- found
    !length(found)
  }
  gone_within <- function(secs) {
    end <- Sys.time() + secs
    repeat {
      if (scan()) return(TRUE)
      if (Sys.time() >= end) return(FALSE)
      Sys.sleep(0.25)
    }
  }
  if (!gone_within(grace)) {
    run$sig <- ps::signals()$SIGKILL
    for (p in run$live) try(ps::ps_send_signal(p, run$sig), silent = TRUE)
    gone_within(5)
  }
  vapply(run$live, ps::ps_pid, 0L)
}

#' Stop a background job
#'
#' @description
#' Stops a job \code{\link{submit_job}} started, and records the end the
#' killed process could not: \code{<job>.run.yml} then reads
#' \code{cancelled}, and \code{<job>.run.progress} is removed, so
#' \code{\link{job_status}} stops reporting the run and the job can be
#' submitted again.
#'
#' @details
#' The render and every process it started are sent \code{SIGTERM}, given
#' \code{grace} seconds to exit, then sent \code{SIGKILL}. They are found by
#' a marker \code{\link{submit_job}} puts in the render's environment, which
#' reaches processes Quarto starts in sessions of their own, and by descent
#' from the recorded process, which is signalled only while it is still the
#' one the status file records: it must carry the run's marker or, recorded
#' without one, match its creation time to the second, so a pid since reused
#' by another process is left alone, and an identity in doubt is refused. The
#' job is scanned afresh until no process of it remains, so one started while
#' it shuts down is stopped too. A run recorded without a creation
#' time, such as a render started without \code{\link{submit_job}}, is
#' refused rather than signalled by its pid alone.
#'
#' A process can only be checked and signalled on the host it runs on, so a
#' job recorded on another host is refused, naming the host to cancel it
#' from, unless \code{other_host = "abandon"}: then nothing is signalled, and
#' the run is recorded \code{cancelled}, with a reason saying so, and its
#' progress file removed. Use it only once that host's session is gone and the
#' job is confirmed not running there, for a render left running there is not
#' stopped and would go on writing the job's output. A job whose process is already gone without recording its end is
#' recorded \code{failed}, with that as its reason, once any of its render
#' still running has been stopped. A job that has finished,
#' failed or never run is left as it is. A submit or cancel in progress holds
#' \code{<job>.run.lock}, as \code{\link{submit_job}} describes, and a cancel
#' is refused while it is held.
#' Not available on Windows.
#'
#' @param path Character(1). The job's \code{.qmd} file.
#' @param grace Numeric(1). Seconds to wait after \code{SIGTERM} before
#'   \code{SIGKILL}.
#' @param other_host Character(1). For a job recorded running on another
#'   host, \code{"refuse"} (the default) stops with an error naming that host,
#'   and \code{"abandon"} records the run ended without signalling anything.
#'   Ignored for a job on this host.
#' @param quiet Logical(1). \code{FALSE} prints the job's state afterwards,
#'   as \code{\link{job_status}} does.
#' @return Invisibly, the job's status afterwards, as \code{\link{job_status}}
#'   returns it.
#' @examples
#' job <- file.path(tempdir(), "example.qmd")
#' writeLines("---\ntitle: example\n---", job)
#' if (.Platform$OS.type != "windows") cancel_job(job)
#' @export
cancel_job <- function(path, grace = 30, other_host = c("refuse", "abandon"), quiet = FALSE) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !file.exists(path) || dir.exists(path)) {
    stop("cancel_job(): `path` must be an existing job file.", call. = FALSE)
  }
  if (!is.numeric(grace) || length(grace) != 1L || is.na(grace) || grace < 0) {
    stop("cancel_job(): `grace` must be a number of seconds, 0 or more.", call. = FALSE)
  }
  other_host <- match.arg(other_host)
  if (.is_windows()) stop("cancel_job(): not available on Windows, where submit_job() is not either.", call. = FALSE)
  path <- normalizePath(path, winslash = "/")
  files <- .run_files(path)
  .claim_run(path, files, "cancel_job")
  on.exit(unlink(files$lock, recursive = TRUE), add = TRUE)
  st <- job_status(path, quiet = TRUE)
  here <- Sys.info()[["nodename"]]
  elsewhere <- identical(st$state, "running") && is.character(st$host) && !identical(st$host, here)
  if (elsewhere && identical(other_host, "refuse")) {
    stop("cancel_job(): ", basename(path), " is recorded running on host ", st$host, ", and a process can only be ",
         "checked and signalled on its own host: run cancel_job() in an R session on ", st$host, ". If that session ",
         "is gone and the job is not running there, cancel_job(other_host = \"abandon\") records it ended from here.",
         call. = FALSE)
  }
  if (identical(st$state, "submitted")) {
    stop("cancel_job(): ", basename(path), " was submitted and its process has not recorded itself yet; cancel it ",
         "again once job_status() reads running, or after two minutes, when an unstarted submission reads vanished.",
         call. = FALSE)
  }
  # Without a creation time the recorded pid cannot be told from a later process that reuses it. A render started
  # without submit_job() records none in its progress file.
  if (identical(st$state, "running") && !elsewhere && is.null(st$created)) {
    stop("cancel_job(): ", basename(path), " records process ", st$pid, " with no creation time, so it cannot be told ",
         "from a later process that took the pid. Check that process by hand and stop it if it is the render; ",
         "cancel_job() then records the end.", call. = FALSE)
  }
  record <- function(...) {
    run <- st[intersect(c("pid", "created", "marker", "host", "r_version", "started"), names(st))]
    do.call(.write_status, c(list(files$status), list(...), run, list(ended = .stamp())))
  }
  if (elsewhere) {
    record(state = "cancelled", reason = sprintf("abandoned from %s, nothing signalled: the user confirmed %s's session is gone",
                                                 here, st$host))
    unlink(files$progress)
    return(invisible(job_status(path, quiet = quiet)))
  }
  if (st$state %in% c("running", "vanished")) {
    # A vanished runner can leave its render running: the marker still finds it.
    h <- .cancel_handle(st)
    left <- .stop_procs(function() .job_procs(h, st$marker), grace)
    if (length(left)) {
      stop("cancel_job(): process(es) ", paste(left, collapse = ", "), " of ", basename(path), " did not exit after ",
           "SIGKILL; nothing was recorded.", call. = FALSE)
    }
  }
  if (identical(st$state, "running")) {
    # The render may have ended on its own while it was being stopped, and then its own record stands.
    now <- tryCatch(yaml::read_yaml(files$status), error = function(e) NULL)
    if (!(is.list(now) && identical(now$started, st$started) && isTRUE(now$state %in% c("finished", "failed")))) {
      record(state = "cancelled")
    }
    unlink(files$progress)
  } else if (identical(st$state, "vanished")) {
    record(state = "failed",
           reason = if (is.null(st$pid)) "it never started" else "its process ended without recording an end")
    unlink(files$progress)
  }
  invisible(job_status(path, quiet = quiet))
}
