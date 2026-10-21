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
    # Progress is advisory and this runs inside the step callback, so a bad option must never stop a fit.
    if (!isTRUE(.progress_state$bad_every_noted)) {
      cat("options(hvtiRtemplates.progress_every = ) must be a positive number of minutes; using 10.\n", file = stderr())
      .progress_state$bad_every_noted <- TRUE
    }
    return(10)
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

# `elapsed` is the time since the loop's counter stood at `base`, so the time per step leaves out whatever came before.
.progress_eta <- function(elapsed, step, steps, base = 0) {
  if (step > base) elapsed / (step - base) * (steps - step) else NA_real_
}

# Quarto knits through <stem>.rmarkdown, so the job's own name is put back before the path is made:
# the file job_status() reads is <job>.run.progress, beside the .qmd.
.progress_path <- function(input) {
  if (is.null(input)) NULL else .run_files(file.path(dirname(input), .job_file_name(input)))$progress
}

.progress_log <- function(text) {
  cat(format(.now(), "%Y-%m-%d %H:%M"), "  ", text, "\n", sep = "", file = stderr())
  .progress_state$last_log <- .now()
  invisible(NULL)
}

.progress_write <- function() {
  s <- .progress_state
  if (is.null(s$file)) return(invisible(NULL))
  rec <- list(pid = Sys.getpid(), host = Sys.info()[["nodename"]], started = .stamp(s$started), updated = .stamp(.now()),
              stage = s$stage, stage_index = s$stage_index, stage_count = length(s$stages),
              stage_started = if (!is.null(s$stage_started)) .stamp(s$stage_started),
              step = s$step, steps = s$steps, unit = s$unit,
              step_started = if (!is.null(s$step_started)) .stamp(s$step_started), step_base = s$step_base,
              stages = s$stages, done = s$done)
  # yaml::write_yaml() can warn (a file that will not open) before it errors; both stop the reporting.
  stop_reporting <- function(e) {
    cat("progress reporting stopped: ", conditionMessage(e), "\n", sep = "", file = stderr())
    s$file <- NULL
  }
  tryCatch(do.call(.write_status, c(list(s$file), Filter(Negate(is.null), rec))),
           error = stop_reporting, warning = stop_reporting)
  invisible(NULL)
}

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

.progress_done_stages <- function(done) vapply(done, function(d) d$stage, "")

# Records `stages` as done without having run, and says why: "skipped" after a stop_here(), else "cached".
.progress_fill <- function(stages) {
  s <- .progress_state
  stopped <- any(vapply(.partial_state$points, function(p) identical(p$kind, "stop"), NA))
  for (m in setdiff(stages, .progress_done_stages(s$done))) {
    s$done[[length(s$done) + 1L]] <- c(list(stage = m, elapsed_s = 0L), if (stopped) list(skipped = TRUE) else list(cached = TRUE))
  }
}

.progress_stage <- function(label, before) {
  s <- .progress_state
  if (is.null(s$file) || !isTRUE(label %in% s$stages)) return(invisible(NULL))
  if (isTRUE(before)) {
    # knitr runs no hook for a chunk it reuses from its cache, so an earlier stage that never reported was cached.
    .progress_fill(s$stages[seq_len(match(label, s$stages) - 1L)])
    s$stage <- label
    s$stage_index <- match(label, s$stages)
    s$stage_started <- .now()
    s$step <- s$steps <- s$unit <- s$step_started <- s$step_base <- NULL
    .progress_log(sprintf("%s  started (%d of %d)", label, s$stage_index, length(s$stages)))
  } else if (identical(label, s$stage) && !label %in% .progress_done_stages(s$done)) {
    elapsed <- as.numeric(difftime(.now(), s$stage_started, units = "secs"))
    s$done[[length(s$done) + 1L]] <- list(stage = label, elapsed_s = as.integer(round(elapsed)))
    .progress_log(sprintf("%s  done in %s", label, .fmt_dur(elapsed)))
  }
  .progress_write()
}

# The end of the document: any stage still not done ran no hook, which means knitr reused it from its cache. This is
# how a document that ends on cached chunks, or is cached throughout, still reads finished.
.progress_finish <- function() {
  s <- .progress_state
  if (is.null(s$file)) return(invisible(NULL))
  if (!length(setdiff(s$stages, .progress_done_stages(s$done)))) return(invisible(NULL))
  .progress_fill(s$stages)
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
    now <- .now()
    # A new loop: the first step, a different unit, or a counter that went back. The estimate counts from here,
    # so the time the stage spent before its loop does not stretch it.
    if (is.null(s$step_started) || !identical(s$unit, unit) || step < s$step) {
      s$step_started <- now
      s$step_base <- as.integer(step)
    }
    s$step <- as.integer(step)
    s$steps <- as.integer(steps)
    s$unit <- unit
    if (step >= steps || as.numeric(difftime(now, s$last_log, units = "mins")) >= .progress_every()) {
      elapsed <- as.numeric(difftime(now, if (is.null(s$stage_started)) s$started else s$stage_started, units = "secs"))
      eta <- .progress_eta(as.numeric(difftime(now, s$step_started, units = "secs")), step, steps, s$step_base)
      left <- if (step < steps && !is.na(eta)) paste0("  ~", .fmt_dur(eta), " left in stage") else ""
      .progress_log(sprintf("%s  %s %d/%d  %s in stage%s", if (is.null(s$stage)) "-" else s$stage, unit,
                            as.integer(step), as.integer(steps), .fmt_dur(elapsed), left))
    }
    .progress_write()
  }
}

# knitr calls this before and after every chunk that has the hvti_progress option,
# which .progress_install() sets for all of them. It returns NULL so nothing
# reaches the report.
.progress_hook <- function(before, options, ...) {
  .progress_stage(options$label, before)
  invisible(NULL)
}

# Called from .job_setup(), in the setup chunk. The stages are the chunks that come after
# the setup chunk, which installs the hook and so never sees its own end. knitr keeps ONE
# registry of labels for the session and a render appends its labels to whatever is
# already there, so labels left by a child knitted outside any render (the template tests
# do) come first. The setup chunk is the first of this document's, so what follows it is
# exactly this document. Chunks made by knitr::knit_child() have labels outside the list and are
# ignored: they run inside a parent chunk, whose stage covers them.
.progress_install <- function(file) {
  if (is.null(file) || !isTRUE(getOption("knitr.in.progress"))) return(function(unit) NULL)
  labels <- unique(knitr::all_labels())
  at <- match(knitr::opts_current$get("label"), labels)
  stages <- if (is.na(at)) labels else labels[-seq_len(at)]
  .progress_begin(file, stages)
  knitr::knit_hooks$set(hvti_progress = .progress_hook)
  # Chained to the document hook already set, so Quarto's and rmarkdown's behavior is unchanged. knitr resets the
  # document hook at the start of each knit, so this does not stack across renders.
  previous <- knitr::knit_hooks$get("document")
  knitr::knit_hooks$set(document = function(x) {
    # knitr applies the document hook to every knit_child() too, which is not the end of the document.
    if (!isTRUE(knitr::opts_knit$get("child"))) tryCatch(.progress_finish(), error = function(e) NULL)
    previous(x)
  })
  knitr::opts_chunk$set(hvti_progress = TRUE)
  .progress_step
}

# TRUE when x is absent or one finite number.
.num1_or_null <- function(x) is.null(x) || (is.numeric(x) && length(x) == 1L && is.finite(x))

# TRUE when the fields job_status() does arithmetic on have the shape the writer gives them.
.progress_shape_ok <- function(p) {
  stamp_ok <- function(x) is.character(x) && length(x) == 1L && !is.na(.parse_stamp(x))
  flag_ok <- function(x) is.null(x) || (is.logical(x) && length(x) == 1L && !is.na(x))
  done_ok <- is.null(p$done) || (is.list(p$done) && all(vapply(p$done, function(d) {
    is.list(d) && is.character(d$stage) && length(d$stage) == 1L && is.numeric(d$elapsed_s) && length(d$elapsed_s) == 1L &&
      is.finite(d$elapsed_s) && flag_ok(d$cached) && flag_ok(d$skipped)
  }, NA)))
  process_ok <- .num1_or_null(p$pid) && (is.null(p$host) || (is.character(p$host) && length(p$host) == 1L))
  process_ok && stamp_ok(p$updated) && stamp_ok(p$started) && (is.null(p$stage_started) || stamp_ok(p$stage_started)) &&
    (is.null(p$step_started) || stamp_ok(p$step_started)) && done_ok &&
    all(vapply(p[c("step", "steps", "step_base", "stage_index", "stage_count")], .num1_or_null, NA)) &&
    (is.null(p$step) || !is.null(p$steps)) && (is.null(p$stages) || is.character(p$stages))
}

.progress_read <- function(file) {
  if (!file.exists(file)) return(NULL)
  p <- tryCatch(yaml::read_yaml(file), error = function(e) NULL)
  if (!is.list(p) || !isTRUE(.progress_shape_ok(p))) {
    return(list(error = paste0("cannot read ", file, "; progress not shown")))
  }
  p
}

# What job_status() adds to the file: how old it is, whether that is old enough
# to look stuck, and the estimate counted from now rather than from the last write.
.progress_view <- function(prog, now = .now()) {
  if (is.null(prog) || !is.null(prog$error)) return(prog)
  updated <- .parse_stamp(prog$updated)
  prog$age_s <- max(0, as.numeric(difftime(now, updated, units = "secs")))
  prog$stale <- prog$age_s > max(3 * .progress_every() * 60, 30 * 60)
  started <- if (is.null(prog$stage_started)) NA else .parse_stamp(prog$stage_started)
  prog$stage_s <- as.numeric(difftime(now, started, units = "secs"))
  step_started <- if (is.null(prog$step_started)) NA else .parse_stamp(prog$step_started)
  prog$eta_s <- if (is.null(prog$step) || is.null(prog$step_base) || is.na(step_started)) {
    NA_real_
  } else {
    eta <- .progress_eta(as.numeric(difftime(updated, step_started, units = "secs")), prog$step, prog$steps, prog$step_base)
    max(0, eta - prog$age_s)
  }
  prog
}

# A render started without submit_job() has no run.yml: its progress file says
# whether it finished, and its process whether it is still running.
.state_from_progress <- function(prog) {
  # job_status() hands this pid to the process check, which cannot take anything but one number.
  if (!(is.numeric(prog$pid) && length(prog$pid) == 1L && is.finite(prog$pid))) stop("progress record has no usable pid")
  done <- vapply(prog$done, function(d) d$stage, "")
  if (length(prog$stages) && all(prog$stages %in% done)) {
    return(list(state = "finished", pid = prog$pid, host = prog$host, started = prog$started, ended = prog$updated,
                elapsed_s = round(as.numeric(difftime(.parse_stamp(prog$updated), .parse_stamp(prog$started),
                                                      units = "secs")))))
  }
  list(state = "running", pid = prog$pid, host = prog$host, started = prog$started)
}

# How a progress file stands against the run <job>.run.yml records: "older" when it began before that run was
# submitted or started (a leftover), "newer" when it began after that run ended (a render started without
# submit_job()), else "current". Anything unparseable counts as current.
.progress_vs_run <- function(prog, st) {
  began <- .parse_stamp(prog$started)
  as_stamp <- function(x) .parse_stamp(if (is.character(x) && length(x) == 1L) x else NA_character_)
  run_began <- as_stamp(if (is.null(st$started)) st$submitted else st$started)
  run_ended <- as_stamp(st$ended)
  if (!is.na(run_began) && began < run_began) return("older")
  if (!is.na(run_ended) && began > run_ended) return("newer")
  "current"
}

.progress_lines <- function(prog, state) {
  if (is.null(prog)) return(character())
  if (!is.null(prog$error)) return(paste0("  progress: ", prog$error))
  stages_done <- vapply(prog$done, function(d) d$stage, "")
  secs_done <- vapply(prog$done, function(d) as.numeric(d$elapsed_s), 0)
  how <- vapply(prog$done, function(d) if (isTRUE(d$skipped)) "skipped" else if (isTRUE(d$cached)) "cached" else "", "")
  if (!identical(state, "running")) {
    stopped <- if (state %in% c("failed", "vanished") && !is.null(prog$stage) && !prog$stage %in% stages_done) {
      sprintf("  stopped in %s (%s of %s)", prog$stage, prog$stage_index, prog$stage_count)
    }
    times <- if (length(stages_done)) {
      c("  stage times:", sprintf("    %-28s %s", stages_done, ifelse(nzchar(how), how, vapply(secs_done, .fmt_dur, ""))))
    }
    return(c(stopped, times))
  }
  out <- character()
  if (!is.null(prog$stage)) {
    out <- c(out, sprintf("  stage   %s (%s of %s), %s in stage", prog$stage, prog$stage_index, prog$stage_count,
                          .fmt_dur(prog$stage_s)))
  }
  if (!is.null(prog$step)) {
    out <- c(out, sprintf("  step    %s %s/%s%s", prog$unit, prog$step, prog$steps,
                          if (is.na(prog$eta_s)) "" else paste0(", ~", .fmt_dur(prog$eta_s), " left in stage")))
  }
  out <- c(out, sprintf("  done    %d stages, %s in all", length(stages_done), .fmt_dur(sum(secs_done))))
  upcoming <- setdiff(prog$stages, c(stages_done, prog$stage))
  if (length(upcoming)) out <- c(out, paste0("  next    ", paste(upcoming, collapse = ", ")))
  c(out, paste0("  updated ", .fmt_dur(prog$age_s), " ago",
                if (isTRUE(prog$stale)) ", no progress since; possibly stalled" else ""))
}
