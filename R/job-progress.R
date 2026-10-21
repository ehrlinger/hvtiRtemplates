# How far a long render has got: which chunk is running, how far into it, and how
# long is left. The design is dev/specs/2026-10-21-job-progress-design.md.
#
# The render's own process writes <job>.run.progress. It is a file of its own,
# not part of <job>.run.yml, because submit_job()'s runner writes that one from
# another process, and two processes renaming over one file overwrite each other.
# Log lines go to stderr(), which reaches the render log; knitr would put a
# message() or a cat() to stdout into the report instead. Progress is advisory:
# nothing here may stop a render.

.progress_state <- new.env(parent = emptyenv())

# The one clock, so tests can move it.
.now <- function() Sys.time()

.progress_every <- function() {
  every <- getOption("hvtiRtemplates.progress_every", 10)
  if (!is.numeric(every) || length(every) != 1L || is.na(every) || every <= 0) {
    stop("options(hvtiRtemplates.progress_every = ) must be a positive number of minutes.", call. = FALSE)
  }
  every
}

.fmt_dur <- function(secs) {
  secs <- max(0, round(secs))
  if (secs < 60) return(paste0(secs, "s"))
  mins <- secs %/% 60
  if (mins < 60) return(paste0(mins, "m"))
  sprintf("%dh%02dm", as.integer(mins %/% 60), as.integer(mins %% 60))
}

.parse_stamp <- function(x) as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%S%z")

.progress_eta <- function(elapsed, step, steps) if (step > 0) elapsed / step * (steps - step) else NA_real_

.progress_log <- function(text) {
  cat(format(.now(), "%Y-%m-%d %H:%M"), "  ", text, "\n", sep = "", file = stderr())
  .progress_state$last_log <- .now()
  invisible(NULL)
}

# .stamp() and .write_status() live in background-job.R, which object_usage_linter reads only per file;
# the calls are fine at run time, so the linter is switched off for this one function.
# nolint start: object_usage_linter.
.progress_write <- function() {
  s <- .progress_state
  if (is.null(s$file)) return(invisible(NULL))
  rec <- list(pid = Sys.getpid(), host = Sys.info()[["nodename"]], started = .stamp(s$started), updated = .stamp(.now()),
              stage = s$stage, stage_index = s$stage_index, stage_count = length(s$stages),
              stage_started = if (!is.null(s$stage_started)) .stamp(s$stage_started),
              step = s$step, steps = s$steps, unit = s$unit, stages = s$stages, done = s$done)
  # yaml::write_yaml() can warn (a file that will not open) before it errors; both stop the reporting.
  stop_reporting <- function(e) {
    cat("progress reporting stopped: ", conditionMessage(e), "\n", sep = "", file = stderr())
    s$file <- NULL
  }
  tryCatch(do.call(.write_status, c(list(s$file), Filter(Negate(is.null), rec))),
           error = stop_reporting, warning = stop_reporting)
  invisible(NULL)
}
# nolint end.

.progress_begin <- function(file, stages) {
  s <- .progress_state
  rm(list = ls(s, all.names = TRUE), envir = s)
  s$file <- file
  s$stages <- as.character(stages)
  s$started <- .now()
  s$last_log <- s$started
  s$done <- list()
  .progress_write()
}

.progress_stage <- function(label, before) {
  s <- .progress_state
  if (is.null(s$file) || !isTRUE(label %in% s$stages)) return(invisible(NULL))
  if (isTRUE(before)) {
    s$stage <- label
    s$stage_index <- match(label, s$stages)
    s$stage_started <- .now()
    s$step <- s$steps <- s$unit <- NULL
    .progress_log(sprintf("%s  started (%d of %d)", label, s$stage_index, length(s$stages)))
  } else if (identical(label, s$stage)) {
    elapsed <- as.numeric(difftime(.now(), s$stage_started, units = "secs"))
    s$done[[length(s$done) + 1L]] <- list(stage = label, elapsed_s = as.integer(round(elapsed)))
    .progress_log(sprintf("%s  done in %s", label, .fmt_dur(elapsed)))
  }
  .progress_write()
}

# The callback a long computation calls once per step. It writes the file every
# step and a log line only once `every` minutes have passed, or at the last step:
# R runs one thing at a time, so no timer can fire inside a fit, but a step can
# look at the clock.
.progress_step <- function(unit) {
  force(unit)
  function(step, steps) {
    s <- .progress_state
    if (is.null(s$file)) return(invisible(NULL))
    s$step <- as.integer(step)
    s$steps <- as.integer(steps)
    s$unit <- unit
    now <- .now()
    if (step >= steps || as.numeric(difftime(now, s$last_log, units = "mins")) >= .progress_every()) {
      elapsed <- as.numeric(difftime(now, if (is.null(s$stage_started)) s$started else s$stage_started, units = "secs"))
      left <- if (step < steps) paste0("  ~", .fmt_dur(.progress_eta(elapsed, step, steps)), " left in stage") else ""
      .progress_log(sprintf("%s  %s %d/%d  %s in stage%s", if (is.null(s$stage)) "-" else s$stage, unit,
                            as.integer(step), as.integer(steps), .fmt_dur(elapsed), left))
    }
    .progress_write()
  }
}
