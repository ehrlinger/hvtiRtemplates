# Prints one line per check, and the fix under each failure, unless quiet. TRUE when every check passed.
.report_checks <- function(checks, quiet = FALSE) {
  for (ck in if (!quiet) checks) {
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
  src <- src[!grepl("^\\s*#", src)]  # a commented-out call runs nothing
  c(character(0), if (any(grepl(".job_setup(", src, fixed = TRUE))) "render_r",
    if (any(grepl("guard_memory(", src, fixed = TRUE))) "memory")
}

# `rel` is the job's path from the study root, which is what job_status() takes from a console there.
# `path` is the run's key (.run_key()), which job_status() reads like a job.
.wait_for_checks <- function(path, expected, wait, poll = 5, rel = basename(path), quiet = FALSE) {
  deadline <- Sys.time() + wait
  repeat {
    st <- job_status(path, quiet = TRUE)
    # Finished, failed, cancelled or gone: say so at once, whatever the check markers show.
    if (st$state %in% c("finished", "failed", "vanished", "cancelled")) return(invisible(job_status(path, quiet = quiet)))
    if (all(expected %in% st$progress$checks) && identical(st$state, "running")) {
      if (!quiet) {
        cat(sprintf("%s; running (process %s on %s). Follow it with hvtiRtemplates::job_status(%s).\n",
                    if (length(expected)) "checks passed" else "started", st$pid, st$host, .run_arg(path, rel)))
      }
      return(invisible(st))
    }
    if (Sys.time() >= deadline) {
      if (!quiet) cat(sprintf("still starting; follow it with hvtiRtemplates::job_status(%s).\n", .run_arg(path, rel)))
      return(invisible(st))
    }
    Sys.sleep(poll)
  }
}

# hvti's whole R side. The path arrives as data (commandArgs), never as source. Exit 1 on a refusal,
# or a launch that failed or vanished during the wait, so a shell `&&` chain stops there.
# From hvti-version 2 the fourth argument is --output ("" for none) and any after it are -P "name:value" pairs; a copy
# of version 1 passes three, and runs as it always did.
.hvti_main <- function(args) {
  cmd <- args[1L]
  path <- args[2L]
  final <- identical(args[3L], "TRUE")
  output_file <- if (length(args) >= 4L && nzchar(args[4L])) args[4L]
  st <- tryCatch({
    params <- .hvti_params(args[-seq_len(4L)])
    switch(cmd,
           run = run_job(path, final = final, params = params, output_file = output_file),
           status = job_status(path, output_file = output_file),
           cancel = cancel_job(path, output_file = output_file))
  }, error = function(e) {
    message(conditionMessage(e))
    NULL
  })
  if (is.null(st)) return(1L)
  if (identical(cmd, "run") && isTRUE(st$state %in% c("failed", "vanished", "cancelled"))) 1L else 0L
}

# hvti's -P "name:value" pairs as run_job()'s params, NULL for none. A value is read as quarto render -P reads it, as a
# YAML scalar, so fit_m:1000 is the number 1000 and flag:true is TRUE; anything that is not a single value stays text.
.hvti_params <- function(pairs) {
  if (!length(pairs)) return(NULL)
  name <- sub(":.*$", "", pairs)
  value <- sub("^[^:]*:", "", pairs)
  if (any(!grepl(":", pairs, fixed = TRUE)) || any(!nzchar(name))) {
    stop("hvti: -P takes name:value, such as -P fit_m:1000.", call. = FALSE)
  }
  stats::setNames(lapply(value, function(v) {
    x <- tryCatch(yaml::yaml.load(v), error = function(e) NULL)
    if ((is.character(x) || is.numeric(x) || is.logical(x)) && length(x) == 1L && !is.na(x)) x else v
  }), name)
}

# Once per session, so a long script of run_job() calls says it once.
.hvti_state <- new.env(parent = emptyenv())
.hvti_state$warned <- FALSE

# The hvti on PATH, or "". A wrapper so tests can stand in for Sys.which(), which cannot be mocked.
.hvti_on_path <- function() unname(Sys.which("hvti"))

# The `hvti-version: N` stamp in a copy of the script; NA when the file or stamp is missing.
.hvti_version <- function(file) {
  if (!nzchar(file) || !file.exists(file)) return(NA_integer_)
  head <- readLines(file, n = 5L, warn = FALSE)
  m <- regmatches(head, regexpr("hvti-version: *[0-9]+", head))
  if (!length(m)) return(NA_integer_)
  as.integer(sub("hvti-version: *", "", m[1L]))
}

# Warns, once, when the hvti on PATH is an older copy than the package's. No copy on PATH, no warning.
.warn_stale_hvti <- function() {
  if (.hvti_state$warned) return(invisible(FALSE))
  installed <- .hvti_version(.hvti_on_path())
  shipped <- .hvti_version(system.file("bin", "hvti", package = "hvtiRtemplates"))
  if (is.na(installed) || is.na(shipped) || installed >= shipped) return(invisible(FALSE))
  .hvti_state$warned <- TRUE
  warning("The hvti command on your PATH is older than this package's (version ", installed, " against ", shipped,
          "). Run hvtiRtemplates::install_hvti(\"", dirname(.hvti_on_path()), "\") to update it.", call. = FALSE)
  invisible(TRUE)
}

#' Install the hvti command
#'
#' @description
#' Copies the `hvti` shell command into a directory on your `PATH`.
#' `hvti run job.qmd` then starts [run_job()] on the R that the
#' study's `renv.lock` records, from a terminal, whichever R your own
#' session would have started. `hvti status` and `hvti cancel` do the
#' same for [job_status()] and [cancel_job()].
#'
#' `hvti run` takes `--final`, and the job's Quarto parameters as
#' `quarto render` does, `-P name:value` once per parameter, with
#' `--output file` naming the report; each becomes [run_job()]'s
#' `params` and `output_file`. A value is read as `quarto render`
#' reads it, so `-P fit_m:1000` is a number. `hvti status` and
#' `hvti cancel` take the same `--output` to name the run:
#' \preformatted{hvti run analyses/job.qmd -P fit_m:1000 --output job.M1000.html
#' hvti status analyses/job.qmd --output job.M1000.html}
#'
#' @details
#' The command is a copy, not a symlink. The library path it would point at
#' changes with the R version, and surviving that change is what the command
#' is for. Run `install_hvti("~/bin")` again after updating the package;
#' `run_job()` warns, once per session, when the copy on your
#' `PATH` is older than the one the package ships.
#' It writes only into `dir`, which has no default: `install_hvti("~/bin")`
#' is the usual call.
#'
#' @param dir Character(1). The directory to install into, created if absent,
#'   usually `"~/bin"`. It should be on your `PATH`; a message gives
#'   the line to add if not.
#' @return Invisibly, the path of the installed command.
#' @seealso [run_job()]
#' @examples
#' if (.Platform$OS.type != "windows") {
#'   d <- tempfile("bin")
#'   install_hvti(d)
#'   unlink(d, recursive = TRUE)
#' }
#' @export
install_hvti <- function(dir) {
  dir <- path.expand(dir)
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  to <- file.path(dir, "hvti")
  # A copy, not a symlink: the library path changes with the R version, which is what hvti exists to survive.
  if (!file.copy(system.file("bin", "hvti", package = "hvtiRtemplates"), to, overwrite = TRUE)) {
    stop("install_hvti(): could not write ", to, ".", call. = FALSE)
  }
  Sys.chmod(to, "755")
  on_path <- normalizePath(dir) %in% normalizePath(strsplit(Sys.getenv("PATH"), ":", fixed = TRUE)[[1]], mustWork = FALSE)
  if (!on_path) .hvti_inform("install_hvti(): add it to your PATH: echo 'export PATH=\"", dir, ":$PATH\"' >> ~/.profile")
  invisible(to)
}

#' Check a job, run it in the background, and wait for its own checks
#'
#' @description
#' Starts a job the way a long fit should be started, and tells you at once if
#' it is going to fail. Before it submits anything, `run_job()` checks the
#' things that otherwise fail minutes or hours in: that this session's R is the
#' one the study's `renv.lock` records, that the packages the job needs are
#' installed at the versions locked, that Quarto can be found, that the job is
#' not already running, and that no other job is rendering in the same study
#' (one render at a time per study). Every failure is listed with how to
#' fix it, and nothing is started until all of them are cleared.
#'
#' Then it submits the job with [submit_job()] and waits for the
#' render's own checks, the R it runs on and, where the job calls
#' [guard_memory()], the memory its fit needs. Those can only run
#' inside the render. If one fails, the diagnosis is printed here rather than
#' left in a log.
#'
#' @details
#' Use this rather than the Render button or a background job in RStudio for
#' anything long. Those stay tied to your session, and when the session ends the
#' render ends with it. A render started here is detached and carries on. Open a
#' new session, call [job_status()] with the same file, and it tells you
#' where the job has got to. There is no R script to write.
#'
#' A job scaffolded before the setup consolidation has no in-render checks to
#' wait for. `run_job()` says so and names `upgrade_job()`, which adds
#' them. The wait ends early when the render finishes, fails or is cancelled.
#' If the checks have not all reported when `wait` runs out, the render
#' carries on regardless; follow it with [job_status()]. Stop it with
#' [cancel_job()].
#' Not available on Windows, as for [submit_job()].
#'
#' A job with Quarto `params` takes them here, as
#' `quarto render -P` would, with `output_file` naming the report as
#' `--output` would. A run given an `output_file` is its own run, with
#' its own run files, so one job rendered for several parameter values keeps
#' each report and each run apart; give [job_status()] and
#' [cancel_job()] the same `output_file` to follow or stop it.
#' The checks above apply to each run, and Quarto still renders one job at a
#' time in a study.
#'
#' @param path Character(1). The job's `.qmd` file.
#' @param final Logical(1). Passed to [submit_job()].
#' @param wait Numeric(1), seconds, at least 0. How long to wait for the render's
#'   own checks. `0` submits and returns at once.
#' @param quiet Logical(1). `TRUE` prints nothing: not the checks, the note
#'   for a legacy job, or the lines the wait ends on. A refusal is still an
#'   error, and its message then lists the failed checks and their fixes. Defaults to the family
#'   option `hvti.quiet`; an explicit value wins.
#' @param params,output_file Passed to [render_job()] through
#'   [submit_job()].
#' @return Invisibly, the job's status, as [job_status()] returns it.
#'   A job refused by the checks is an error and returns nothing.
#' @seealso [submit_job()], [job_status()],
#'   [cancel_job()], [guard_memory()]
#' @examples
#' # Not run by check: it would start a real render.
#' \dontrun{
#' run_job("analyses/nb.boostmtree.lvef.boost.qmd")
#'
#' # A parameterized job, one report per value: run the second once the first
#' # has finished, since Quarto renders one job at a time in a study.
#' run_job("job.qmd", params = list(fit_m = 1000), output_file = "job.M1000.html")
#' job_status("job.qmd", output_file = "job.M1000.html")
#' }
#' @export
run_job <- function(path, final = FALSE, wait = 300, quiet = isTRUE(getOption("hvti.quiet")), params = NULL, output_file = NULL) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !file.exists(path) || dir.exists(path)) {
    stop("run_job(): `path` must be an existing job file.", call. = FALSE)
  }
  .check_params(params, "run_job")
  .check_output_file(output_file, path, "run_job")
  if (!is.numeric(wait) || length(wait) != 1L || is.na(wait) || wait < 0) {
    stop("run_job(): `wait` must be a single number of seconds, 0 or more.", call. = FALSE)
  }
  if (!is.logical(quiet) || length(quiet) != 1L || is.na(quiet)) {
    stop("run_job(): `quiet` must be TRUE or FALSE.", call. = FALSE)
  }
  .warn_stale_hvti()
  path <- normalizePath(path, winslash = "/")
  root <- .find_study_root(dirname(path))
  key <- .run_key(path, output_file)
  rel <- .study_rel(key, root)
  if (!quiet) cat("Checking ", basename(path), if (!is.null(output_file)) paste0(" for ", output_file), "\n", sep = "")
  checks <- list(.check_r_version(root), .check_packages(path, root), .check_quarto(root), .check_run_state(key, root),
                 .check_study_render(key, root))
  if (!.report_checks(checks, quiet)) {
    # Quiet printed nothing, so the error itself has to say what failed and how to fix it.
    failed <- if (quiet) {
      vapply(Filter(function(ck) !ck$ok, checks), function(ck) paste0("\n  ", ck$message, "\n  fix: ", ck$fix), "")
    }
    .abort("run_job(): refused; fix the checks marked FAIL ", if (quiet) "below" else "above", " and run again.",
           paste(failed, collapse = ""), class = "run_refused")
  }
  expected <- .expected_checks(path)
  if (!quiet && !"render_r" %in% expected) {
    cat("  note  this job predates the in-render checks (no .job_setup() call), so the render's R and memory\n",
        "        are not checked inside the render. upgrade_job(\"", basename(path), "\") adds them.\n", sep = "")
  }
  submit_job(path, final = final, params = params, output_file = output_file)
  if (wait == 0) return(invisible(job_status(key, quiet = TRUE)))
  .wait_for_checks(key, expected, wait, rel = rel, quiet = quiet)
}
