# Known ways a render dies, matched in order; the first that matches explains it. Design:
# dev/specs/2026-10-22-run-job-design.md section 6, failure 7.
.diagnose_failure <- function(log, st, job = NULL) {
  # Quarto colors its output even into a file; the escapes sit at the start of the lines matched below.
  log <- gsub("\033\\[[0-9;]*m", "", log, perl = TRUE)
  # rlang/knitr print a condition's lines with "! ", "i " or "x " bullets; strip them so a check's own
  # refusal is matched the same whether it came through Quarto or a plain Rscript.
  log <- sub("^[!ix\u2139\u2716] ", "", log)
  hit <- function(p) grep(p, log, perl = TRUE)
  g <- hit("^(r_version|packages|run_state|quarto|render_r|memory|study_render): ")
  if (length(g)) {
    # Convention: a multi-line refusal's last line is its fix; a one-line refusal has none (fix is "").
    # The refusal runs to the next blank line, the quitting marker, rlang's Backtrace (a refusal raised inside a function,
    # as guard_memory() and .job_setup() raise theirs), or an indented repeat of it; its last line is the fix.
    stop_at <- grep("^$|^Quitting from|^Backtrace|^[ \t]", log)
    stop_at <- stop_at[stop_at > g[1L]]
    refusal <- log[seq.int(g[1L], (if (length(stop_at)) stop_at[1L] else length(log) + 1L) - 1L)]
    n <- length(refusal)
    return(list(reason = paste(refusal[seq_len(max(n - 1L, 1L))], collapse = " "), fix = if (n > 1L) refusal[n] else ""))
  }
  # The log only: the runner records exit code 0 or 1, never the signal that killed a render.
  killed <- length(hit("worker result\\(s\\) were not delivered|^Killed\\s*$|exit status 137")) > 0L
  if (killed) {
    peak <- st$mem_peak_gib
    lim <- st$mem_limit_gib
    if (is.numeric(peak) && is.numeric(lim) && peak >= 0.95 * lim) {
      need <- st$progress$mem_need_gib
      # The peak proves the cap that failed was too small, so the estimate only picks among larger caps: an underestimate
      # must not name the same profile again. A need of 0 is a cached rerender's record, not an estimate.
      prof <- .workbench_profiles
      i <- if (.num1(need) && need > 0) which(prof$cap_gib > lim & prof$cap_gib * 0.9 >= need)[1L] else NA
      to <- if (is.na(i)) "none" else prof$profile[i]
      fix <- if (to != "none") {
        sprintf("Start a \"%s\" session or larger (this fit was estimated at %.0f GiB), or lower CORES.", to, need)
      } else {
        sprintf("Start a Workbench session larger than this one (%.1f GiB), or lower CORES.", lim)
      }
      return(list(reason = sprintf("the session ran out of memory: peak %.1f of a %.1f GiB cap.", peak, lim), fix = fix))
    }
    return(list(reason = "probably memory: forked workers were killed, and this run recorded no memory peak.",
                fix = "Start a larger Workbench session, or lower CORES, and run again."))
  }
  m <- regmatches(log, regexpr("there is no package called .[A-Za-z0-9.]+.", log))
  if (length(m)) {
    return(list(reason = sprintf("the render ran on an R or library that lacks a package (%s).", m[1L]),
                fix = paste0("Run it with hvtiRtemplates::run_job(\"<job>\") from a console on the study's R, in its project; ",
                             "if it still fails, fix what run_job's packages check reports.")))
  }
  q <- hit("^Quitting from .*\\[[^]]+\\]")
  if (length(q)) {
    label <- sub("^.*\\[([^]]+)\\].*$", "\\1", log[q[1L]])
    span <- sub("^Quitting from [^:]*:([0-9-]+).*$", "\\1", log[q[1L]])
    # Quarto prints the error BEFORE the quitting marker: take the last "Error" line above it and
    # the condition lines between them.
    e <- utils::tail(grep("^Error", log[seq_len(q[1L] - 1L)]), 1L)
    err <- if (length(e)) {
      cond <- log[seq.int(e, q[1L] - 1L)]
      bt <- grep("^Backtrace", cond)
      if (length(bt)) cond <- cond[seq_len(bt[1L] - 1L)]
      paste(trimws(cond[nzchar(trimws(cond))]), collapse = " ")
    }
    return(list(reason = sprintf("the job stopped in chunk `%s`, lines %s.", label, span),
                fix = if (length(err)) err else "See the log for the error."))
  }
  # Quarto's own failures print "ERROR: <message>" and then a Deno stack trace long enough to push the message out of
  # any fixed tail, so take the message itself.
  qe <- utils::tail(hit("^ERROR: "), 1L)
  if (length(qe)) {
    msg <- sub("^ERROR: ", "", log[qe])
    # The race is this job's folder only, by the same test render_job() retries on; a retry is claimed only when the
    # log records render_job()'s own line for one, since a render outside it, or one that stopped at once, has none.
    if (!is.null(job) && .is_execute_results_race(log[qe], .execute_results_dir(job))) {
      retried <- any(grepl("render_job(): every chunk ran, then Quarto could not remove", log, fixed = TRUE))
      return(list(reason = paste0("Quarto could not remove this job's execute-results folder (", msg, "), most often ",
                                  "because the network share had not let go of a file there; not an error in the job."),
                  fix = if (retried) {
                    paste0("render_job() already rendered it twice. Delete the job's _files folder ",
                           "(`lsof +D` on it names what holds a file there), then run the job again.")
                  } else {
                    "Run the job again; if it fails the same way, delete the job's _files folder first."
                  }))
    }
    return(list(reason = paste0("Quarto failed: ", msg), fix = "See the log above the Stack trace for what led to it."))
  }
  list(reason = "no known cause; the end of the log follows.", fix = paste(utils::tail(log, 20L), collapse = "\n"))
}
