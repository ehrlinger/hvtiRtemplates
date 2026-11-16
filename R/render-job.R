#' Render a job
#'
#' @description
#' Renders a job from its own directory. By default the render is a draft:
#' open \code{EDIT:} markers appear in the report's DRAFT banner. With
#' \code{final = TRUE} an unfinished job stops instead, as the render of an
#' accepted result should.
#'
#' @details
#' \code{final = TRUE} sets \code{HVTI_TEMPLATE_STRICT} to \code{1} for this
#' render only and restores its previous value afterwards, including after an
#' error. The job's own edit guard decides whether it is finished; this
#' function does not search for markers itself, so it cannot disagree with a
#' render started from the editor or from Quarto.
#'
#' Quarto starts its own R to run the job's chunks, and by default it takes
#' whichever R comes first on the \code{PATH}, which on a server with several
#' versions installed need not be the R that called this function. A study
#' whose \code{renv} library belongs to the calling R then fails to find its
#' packages. So the render sets \code{QUARTO_R} to this R's \code{bin}
#' directory, \code{R.home("bin")}, and restores it afterwards. A
#' non-empty \code{QUARTO_R} that is already set is left alone, and Quarto
#' honors it with a Quarto CLI of 1.8.13 or later. With an older CLI the
#' quarto package itself sets \code{QUARTO_R} to the calling R for every
#' render, so a value set by the user does not reach Quarto there.
#'
#' Jobs scaffolded by \code{\link{add_job}} capture their data provenance while
#' executing and embed it in the completed HTML. The same project hooks used by
#' the Render button and bare Quarto commands then publish a same-stem
#' \code{.provenance.json} sidecar beside the actual output. A failed execution
#' that leaves the prior HTML untouched also leaves its sidecar in place. If
#' publication fails after an output changes, the hooks expose a prior sidecar
#' only when its recorded output hash still matches. Otherwise they withhold the
#' sidecar and retain its recovery backup with a warning.
#'
#' Render a job rather than running its chunks in the console: a render starts
#' in a clean session, so the report comes from this job alone. A console run,
#' chunk by chunk or with Run All, still gets through every chunk but the last.
#' That chunk records provenance, which needs a render, so a console run stops
#' there with an error of class \code{hvtiRtemplates_not_rendered} that says to
#' render the job. Everything computed above it is still in the session.
#'
#' Quarto's bundled Deno runtime can crash as it starts, on macOS at least,
#' before it has read the job. The quarto package then reports something
#' unrelated: "Could not evaluate cli \code{\{\}} expression:
#' \code{QUARTO_DENO}". A render that fails that way stops with an error of
#' class \code{hvtiRtemplates_quarto_crashed} that says Quarto crashed, not the
#' job, and that rendering again usually works. The original error is kept as
#' its parent.
#'
#' On a network share Quarto can fail after every chunk has run, unable to
#' remove the job's \code{_files/execute-results} folder ("Directory not empty
#' (os error 39)"), because it deletes a file there before the share has let go
#' of it. A render that fails with that error, read from Quarto's own message or
#' from what the render added to the job's run log, is rendered once more, with a
#' message saying so; the job runs twice, which for a long fit means twice the
#' time. Any other failure is passed through unchanged, and nothing is deleted. A
#' second such failure stops with an error of class
#' \code{hvtiRtemplates_execute_results_stuck}. Rendering from the RStudio
#' Render button does not go through \code{render_job()} and is not retried.
#'
#' One job renders at a time in a study. A render started while another is
#' still running in the same study stops with a message naming the running
#' Quarto process; render again once it finishes. A lock left by a render that
#' crashed on this node is taken over automatically. A process on another node
#' cannot be checked from here, so a running render touches a heartbeat file in
#' the lock from its own node, and a lock whose heartbeat has stopped for ten
#' minutes is taken over too. A lock from a render too old to keep a heartbeat
#' reads as still running: the message names the node and the lock directory to
#' delete once you know nothing is rendering there. The lock is the study's, so a
#' renamed copy of the job meets the same one.
#'
#' @param path Character. Path to a job \code{.qmd} file.
#' @param final Logical. \code{TRUE} for the accepted result. A final render reads registered data
#'   only: a job whose data, or whose upstream hand-off, came from an unregistered build stops and
#'   names \code{hvtiRutilities::update_manifest()}.
#' @param quiet Logical. Passed to \code{quarto::quarto_render()}.
#' @param params A named list of single values, or \code{NULL}. The job's Quarto
#'   \code{params}, as \code{quarto render -P name:value} sets them; passed to
#'   \code{quarto::quarto_render()} as \code{execute_params}.
#' @param output_file Character(1) or \code{NULL}. The report's file name, as
#'   \code{quarto render --output} sets it: a name with an extension and no
#'   directory, written beside the job. Give each set of \code{params} its own,
#'   so one report does not overwrite another. The run's progress file is named
#'   for it too.
#'
#' @return \code{path}, invisibly.
#'
#' @seealso \code{\link{open_job}}
#' @examples
#' \donttest{
#' if (requireNamespace("quarto", quietly = TRUE) && quarto::quarto_available()) {
#'   root <- file.path(tempdir(), "render-job-example")
#'   invisible(hvtiRutilities::study_setup(root, "Example", 1L, renv = FALSE))
#'   d <- data.frame(ccfid = 1:6, dead = c(0, 1, 0, 1, 0, 0),
#'                   iv_dead = c(1.2, 0.4, 3.1, 2.2, 0.8, 4.5))
#'   utils::write.csv(d, file.path(hvtiRutilities::study_dir("datasets", root), "built.csv"),
#'                    row.names = FALSE)
#'   invisible(hvtiRutilities::register_data(root, "built.csv"))
#'   job <- add_job("dc.gfup", subject = "dead", type = "hz", dir = root)
#'
#'   # A draft: the new job still holds EDIT: markers, so the report carries a
#'   # DRAFT banner listing them, and renders all the same.
#'   render_job(job, quiet = TRUE)
#'   print(file.exists(sub("[.]qmd$", ".html", job)))
#'
#'   # A final render is the accepted result, so it stops while any of the
#'   # job's open markers remains. This many:
#'   print(sum(grepl("EDIT:", readLines(job), fixed = TRUE)))
#'   try(render_job(job, final = TRUE, quiet = TRUE))
#'   unlink(root, recursive = TRUE)
#' }
#' }
#' @export
render_job <- function(path, final = FALSE, quiet = FALSE, params = NULL, output_file = NULL) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !file.exists(path) || dir.exists(path)) {
    stop("render_job(): `path` must be an existing job file.", call. = FALSE)
  }
  if (!is.logical(final) || length(final) != 1L || is.na(final)) {
    stop("render_job(): `final` must be TRUE or FALSE.", call. = FALSE)
  }
  .check_params(params, "render_job")
  .check_output_file(output_file, path, "render_job")
  if (!requireNamespace("quarto", quietly = TRUE)) {
    stop("render_job(): the quarto package is required; install.packages(\"quarto\").", call. = FALSE)
  }
  path <- normalizePath(path, winslash = "/")
  if (final) {
    old <- Sys.getenv("HVTI_TEMPLATE_STRICT", unset = NA)
    on.exit(if (is.na(old)) Sys.unsetenv("HVTI_TEMPLATE_STRICT") else Sys.setenv(HVTI_TEMPLATE_STRICT = old),
            add = TRUE)
    Sys.setenv(HVTI_TEMPLATE_STRICT = "1")
  }
  old_r <- Sys.getenv("QUARTO_R", unset = NA)
  if (is.na(old_r) || !nzchar(old_r)) {
    on.exit(if (is.na(old_r)) Sys.unsetenv("QUARTO_R") else Sys.setenv(QUARTO_R = old_r), add = TRUE)
    Sys.setenv(QUARTO_R = R.home("bin"))
  }
  # The render's own R writes <stem>.run.progress, and learns the stem from this: set for an output_file, and unset
  # otherwise, so a value inherited from a parent render cannot send this one's progress to another run's file.
  old_out <- Sys.getenv("HVTI_OUTPUT_FILE", unset = NA)
  on.exit(if (is.na(old_out)) Sys.unsetenv("HVTI_OUTPUT_FILE") else Sys.setenv(HVTI_OUTPUT_FILE = old_out), add = TRUE)
  if (is.null(output_file)) Sys.unsetenv("HVTI_OUTPUT_FILE") else Sys.setenv(HVTI_OUTPUT_FILE = output_file)
  log <- .run_files(.run_key(path, output_file))$log
  render <- function() {
    quarto::quarto_render(path, execute_dir = dirname(path), quiet = quiet, execute_params = params,
                          output_file = output_file)
  }
  attempt <- function() {
    from <- .file_size(log)
    tryCatch(render(), error = function(e) {
      if (.quarto_crashed(e)) {
        rlang::abort(c(
          paste0("render_job(): Quarto crashed before rendering ", basename(path), "; the job itself did not fail."),
          i = "Its Deno runtime was killed by a signal, most often a crash as it starts. Render the job again."
        ), class = "hvtiRtemplates_quarto_crashed", parent = e, call = NULL)
      }
      if (.execute_results_race(e, log, from, .execute_results_dir(path))) {
        rlang::abort("Quarto could not remove execute-results.", class = "hvtiRtemplates_execute_results_race",
                     parent = e, call = NULL)
      }
      stop(e)
    })
  }
  tryCatch(attempt(), hvtiRtemplates_execute_results_race = function(e) {
    message("render_job(): every chunk ran, then Quarto could not remove ", .execute_results_dir(path),
            " (Directory not empty): the network share had not yet let go of a file it had just written. ",
            "Rendering again.")
    tryCatch(attempt(), hvtiRtemplates_execute_results_race = function(e2) {
      rlang::abort(c(
        paste0("render_job(): Quarto could not remove ", .execute_results_dir(path),
               " twice (Directory not empty); the job itself did not fail."),
        i = "Something on the share still holds a file there; find it with `lsof +D` on the folder.",
        i = "Delete the folder and render the job again."
      ), class = "hvtiRtemplates_execute_results_stuck", parent = e2$parent, call = NULL)
    })
  })
  invisible(path)
}

# In a project render Quarto writes <stem>_files/execute-results/, copies it to the freezer and deletes it at once.
# On the NFS study share the delete can come before the share lets go of the new file, which leaves a hidden .nfs*
# entry and fails the render with "Directory not empty (os error 39)" after every chunk has run. Only that error, on
# that folder, is the race: the folder alone is not evidence, since a failure earlier in Quarto's freezer step (a
# read-only _freeze/, a full disk) leaves it too, and nothing here deletes it, since another render of the job may
# own it. Quarto's stderr is kept on the processx error in the condition chain, unless cli fails while wrapping it,
# as it did on lri, so the lines this attempt added to the run log are read as well.
.execute_results_dir <- function(path) {
  file.path(dirname(path), paste0(tools::file_path_sans_ext(basename(path)), "_files"), "execute-results")
}

# TRUE when `text` holds Quarto's own refusal to remove `expected`: the "remove '<path>'" form Quarto prints, naming
# this job's folder. Two substrings are not enough: another document's folder, or a job's own error that happens to
# mention both words, would rerun the whole job and be reported as this race.
.is_execute_results_race <- function(text, expected) {
  text <- unlist(strsplit(text, "\n", fixed = TRUE))
  m <- regmatches(text, regexec("ERROR: Directory not empty \\(os error 39\\): remove '([^']+)'", text))
  removed <- vapply(m, function(x) if (length(x) == 2L) x[2L] else NA_character_, character(1L))
  # The folder may be gone by now, and normalizePath() leaves a missing path's symlinked parents unresolved, so resolve
  # the job's directory, which exists, and compare the two names below it as written.
  key <- function(p) c(normalizePath(dirname(dirname(p)), winslash = "/", mustWork = FALSE), basename(dirname(p)),
                       basename(p))
  same <- function(a) identical(key(a), key(expected))
  any(vapply(removed[!is.na(removed)], same, logical(1L)))
}

.execute_results_race <- function(e, log, from, expected) {
  while (!is.null(e)) {
    text <- c(if (is.character(e$stderr)) e$stderr, tryCatch(conditionMessage(e), error = function(x) ""))
    if (.is_execute_results_race(text, expected)) return(TRUE)
    e <- e$parent
  }
  size <- .file_size(log)
  if (size <= from) return(FALSE)
  con <- file(log, "rb")
  on.exit(close(con))
  seek(con, from)
  added <- strsplit(rawToChar(readBin(con, "raw", size - from)), "\n")[[1L]]
  last <- utils::tail(grep("^ERROR: ", gsub("\033\\[[0-9;]*m", "", added), value = TRUE, useBytes = TRUE), 1L)
  length(last) == 1L && .is_execute_results_race(last, expected)
}

.file_size <- function(path) {
  size <- file.size(path)
  if (is.na(size)) 0 else size
}

# Did Quarto's Deno runtime die, rather than the job fail? The quarto launcher
# is a bash script, and bash reports a dead Deno on stderr as its unexpanded
# source line, `"${QUARTO_DENO}" ...`. quarto (1.5.1 at least) passes stderr to
# cli::cli_abort() unescaped, so cli tries to evaluate `{QUARTO_DENO}` and
# fails: "Could not evaluate cli `{}` expression: `QUARTO_DENO`.", with parent
# "object 'QUARTO_DENO' not found". Only that exact pair counts. A job's error
# that merely mentions QUARTO_DENO does not, and neither does an exit status:
# 128 or more is not proof of a signal, and processx reports a launcher killed
# by a signal as a negative status. The pair does not say which signal, so a
# memory kill mid-render matches too. dev/gallery/gallery.R retries on it.
.quarto_crashed <- function(e) {
  while (!is.null(e)) {
    if (inherits(e, "rlib_error") &&
          identical(e$message, "Could not evaluate cli `{}` expression: `QUARTO_DENO`.") &&
          inherits(e$parent, "simpleError") &&
          identical(conditionMessage(e$parent), "object 'QUARTO_DENO' not found")) {
      return(TRUE)
    }
    e <- e$parent
  }
  FALSE
}
