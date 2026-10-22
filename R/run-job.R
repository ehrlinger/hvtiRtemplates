# Prints one line per check, and the fix under each failure. TRUE when every check passed.
.report_checks <- function(checks) {
  for (ck in checks) {
    cat(if (ck$ok) "  ok    " else "  FAIL  ", ck$name, "\n", sep = "")
    if (!ck$ok) cat("        ", ck$message, "\n        fix: ", gsub("\n", "\n             ", ck$fix), "\n", sep = "")
    if (!is.null(ck$note)) cat("        note: ", ck$note, "\n", sep = "")
  }
  all(vapply(checks, `[[`, NA, "ok"))
}

# A job scaffolded before the setup consolidation keeps its four old chunks and never calls
# .job_setup(), so it never records render_r; waiting for it would only time out. Such a job gets
# no in-render checks, and run_job() says so and names upgrade_job() (spec section 5.3).
.expected_checks <- function(path) {
  src <- readLines(path, warn = FALSE)
  c(character(0), if (any(grepl(".job_setup(", src, fixed = TRUE))) "render_r",
    if (any(grepl("guard_memory(", src, fixed = TRUE))) "memory")
}

.wait_for_checks <- function(path, expected, wait, poll = 5) {
  deadline <- Sys.time() + wait
  repeat {
    st <- job_status(path, quiet = TRUE)
    # Finished, failed or gone: say so at once, whatever the check markers show.
    if (st$state %in% c("finished", "failed", "vanished", "cancelled")) return(invisible(job_status(path)))
    if (all(expected %in% st$progress$checks) && identical(st$state, "running")) {
      cat(sprintf("%s; running (process %s on %s). Follow it with `hvti status %s`.\n",
                  if (length(expected)) "checks passed" else "started", st$pid, st$host, basename(path)))
      return(invisible(st))
    }
    if (Sys.time() >= deadline) {
      cat(sprintf("still starting; follow it with `hvti status %s`.\n", basename(path)))
      return(invisible(st))
    }
    Sys.sleep(poll)
  }
}

#' Check a job, run it in the background, and wait for its own checks
#'
#' @description
#' Starts a job the way a long fit should be started, and tells you at once if
#' it is going to fail. Before it submits anything, \code{run_job()} checks the
#' things that otherwise fail minutes or hours in: that this session's R is the
#' one the study's \code{renv.lock} records, that the packages the job needs are
#' installed at the versions locked, that Quarto can be found, that the job is
#' not already running, and that no other job is rendering in the same study
#' (Quarto allows one render per study). Every failure is listed with how to
#' fix it, and nothing is started until all of them are cleared.
#'
#' Then it submits the job with \code{\link{submit_job}} and waits for the
#' render's own checks, the R it runs on and, where the job calls
#' \code{\link{guard_memory}}, the memory its fit needs. Those can only run
#' inside the render. If one fails, the diagnosis is printed here rather than
#' left in a log.
#'
#' @details
#' A job scaffolded before the setup consolidation has no in-render checks to
#' wait for. \code{run_job()} says so and names \code{upgrade_job()}, which adds
#' them. The wait ends early when the render finishes, fails or is cancelled.
#' If the checks have not all reported when \code{wait} runs out, the render
#' carries on regardless; follow it with \code{\link{job_status}}. Stop it with
#' \code{\link{cancel_job}}.
#' Not available on Windows, as for \code{\link{submit_job}}.
#'
#' @param path Character(1). The job's \code{.qmd} file.
#' @param final Logical(1). Passed to \code{\link{submit_job}}.
#' @param wait Numeric(1), seconds, at least 0. How long to wait for the render's
#'   own checks. \code{0} submits and returns at once.
#' @return Invisibly, the job's status, as \code{\link{job_status}} returns it.
#'   A job refused by the checks is an error and returns nothing.
#' @seealso \code{\link{submit_job}}, \code{\link{job_status}},
#'   \code{\link{cancel_job}}, \code{\link{guard_memory}}
#' @examples
#' # Not run by check: it would start a real render.
#' \dontrun{
#' run_job("analyses/nb.boostmtree.lvef.boost.qmd")
#' }
#' @export
run_job <- function(path, final = FALSE, wait = 300) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !file.exists(path) || dir.exists(path)) {
    stop("run_job(): `path` must be an existing job file.", call. = FALSE)
  }
  if (!is.numeric(wait) || length(wait) != 1L || is.na(wait) || wait < 0) {
    stop("run_job(): `wait` must be a single number of seconds, 0 or more.", call. = FALSE)
  }
  path <- normalizePath(path, winslash = "/")
  root <- .find_study_root(dirname(path))
  cat("Checking ", basename(path), "\n", sep = "")
  checks <- list(.check_r_version(root), .check_packages(path, root), .check_quarto(), .check_run_state(path),
                 .check_study_render(path, root))
  if (!.report_checks(checks)) stop("run_job(): refused; fix the checks marked FAIL above and run again.", call. = FALSE)
  expected <- .expected_checks(path)
  if (!"render_r" %in% expected) {
    cat("  note  this job predates the in-render checks (no .job_setup() call), so the render's R and memory\n",
        "        are not checked inside the render. upgrade_job(\"", basename(path), "\") adds them.\n", sep = "")
  }
  submit_job(path, final = final)
  if (wait == 0) return(invisible(job_status(path, quiet = TRUE)))
  .wait_for_checks(path, expected, wait)
}
