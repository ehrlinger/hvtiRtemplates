#' Bring a job from another study into this one
#'
#' @description
#' Copies a job \code{.qmd} from another study into the current study, keeping
#' the source study's edits, so a job adapted once, such as an aorta-specific
#' \code{ac} job, can be adapted again rather than rebuilt from the template.
#'
#' @details
#' The job is written where \code{\link{add_job}} would write a new job from
#' the same template, under the name it would give it, and with the same
#' setup: the template's packages and any further packages the job's own
#' setup chunk attaches are installed into the study's renv library, the
#' Quarto provenance hooks are installed, and an existing job is never
#' overwritten. The template is read from the job's file name, in either
#' spelling \code{add_job()} has used.
#'
#' \code{subject} and \code{type} default to the source job's own. Either can
#' be changed on the way in, and the job's \code{SUBJECT} and \code{TYPE}
#' lines are rewritten to match its new name, as \code{add_job()} does.
#'
#' A job that runs from a companion runner script brings its runner too, when
#' one sits beside it. Without one, the job gets the template's runner, and the
#' message says so.
#'
#' \strong{What to review.} Everything else is carried as the source study left
#' it, including choices that were right for that study and may be wrong for
#' this one. \code{import_job()} rewrites none of them. Instead its message
#' lists, by line number, each one to check:
#' \itemize{
#'   \item the \code{DATASET} the job reads;
#'   \item a \code{WHERE} row selection, unless it is \code{NULL};
#'   \item every \code{EDIT:} marker still in the job;
#'   \item every absolute file path, such as \code{"/studies/aorta/..."} or
#'     \code{"C:/..."}, which names a file in the other study or on another
#'     machine.
#' }
#' Values are never quoted in the message, because a selection can name a
#' patient. Paths relative to the study, which is how a template refers to its
#' study's files, are not listed.
#'
#' The job keeps the template version it was written from, so
#' \code{\link{upgrade_job}} can bring an older job up to the current template
#' afterwards: \code{upgrade_job(import_job(from))}.
#'
#' @param from The job to import: a \code{.qmd} file in another study, named
#'   as \code{add_job()} names jobs.
#' @param subject,type The job's set in this study. \code{NULL}, the default,
#'   keeps the source job's. See \code{\link{add_job}} for what they decide.
#' @param dir The study root to import into. \code{NULL}, the default, finds
#'   it by walking up from the working directory, as \code{add_job()} does.
#'
#' @return The imported job's path, invisibly. On any failure no file is left
#'   behind, the runner included.
#'
#' @seealso \code{\link{add_job}}, \code{\link{upgrade_job}}
#'
#' @examples
#' other <- file.path(tempdir(), "import-job-other")
#' here <- file.path(tempdir(), "import-job-here")
#' for (d in c(other, here)) {
#'   invisible(hvtiRutilities::study_setup(d, study = "Example", study_tracker_id = 1L, renv = FALSE))
#' }
#' job <- add_job("ac", subject = "death", type = "hz", dir = other)
#' # The other study's edit.
#' lines <- readLines(job)
#' lines <- sub("^DATASET <- \"built\"", "DATASET <- \"built_aorta\"", lines)
#' writeLines(lines, job)
#'
#' imported <- import_job(job, subject = "reop", dir = here)
#' grep("^(DATASET|SUBJECT) ", readLines(imported), value = TRUE)
#'
#' # An existing job is never overwritten.
#' try(import_job(job, subject = "reop", dir = here))
#' unlink(c(other, here), recursive = TRUE)
#' @export
import_job <- function(from, subject = NULL, type = NULL, dir = NULL) {
  tryCatch(.check_scalar_string("from", from), error = function(e) {
    stop("import_job(): ", sub("^template selection: ", "", conditionMessage(e)), call. = FALSE)
  })
  if (!file.exists(from) || dir.exists(from)) stop("import_job(): job not found: ", from, call. = FALSE)
  if (!grepl("[.]qmd$", from)) stop("import_job(): a job is a .qmd file: ", from, call. = FALSE)
  fields <- .job_template_fields(from)
  if (is.null(fields)) {
    stop("import_job(): '", basename(from), "' does not name a template; expected ",
         "<prefix>[.<qualifier>].<subject>.<type>.qmd.", call. = FALSE)
  }
  if (is.null(subject)) subject <- fields$subject
  if (is.null(type)) type <- fields$type
  .check_field("subject", subject, fn = "import_job")
  .check_field("type", type, fn = "import_job")
  row <- tryCatch(
    .select_template(template_list(), fields$prefix, fields$qualifier),
    error = function(e) stop("import_job(): ", conditionMessage(e), call. = FALSE)
  )
  .warn_if_deprecated(row, "import_job")
  if (is.null(dir)) dir <- .default_study_root("import_job")

  lines <- readLines(from, warn = FALSE)
  # The SUBJECT and TYPE lines are checked before anything is written.
  lines <- .set_marker_lines(lines, subject, type, from)
  src_runner <- c(sub("[.]qmd$", ".runner.R", from), sub("[.]qmd$", "-runner.R", from))
  src_runner <- src_runner[file.exists(src_runner)]

  # Packages the other study added to the job's setup chunk, before anything is
  # written, so a refusal leaves this study as it was. add_job() installs the
  # template's own.
  extra <- tryCatch(.template_packages(from)$package, error = function(e) character())
  if (length(extra) && dir.exists(dir)) {
    hvtiRutilities::study_need(extra, root = dir, caller = "import_job", only_in_renv = TRUE)
  }

  # add_job() refuses an existing job in any spelling, installs packages and
  # hooks, and leaves nothing behind on failure. Its job and runner are then
  # replaced with the imported text.
  qualifier <- if (is.na(row$qualifier[[1L]])) NULL else row$qualifier[[1L]]
  out <- withCallingHandlers(
    tryCatch(add_job(row$prefix[[1L]], subject, type, dir = dir, qualifier = qualifier),
             error = function(e) stop(sub("^add_job\\(\\): ", "import_job(): ", conditionMessage(e)), call. = FALSE)),
    hvtiRtemplates_deprecated = function(w) invokeRestart("muffleWarning")
  )
  runner <- sub("[.]qmd$", ".runner.R", out)
  has_runner <- file.exists(runner)
  ok <- FALSE
  on.exit(if (!ok) unlink(c(out, if (has_runner) runner)), add = TRUE)
  writeLines(lines, out)
  review <- list(.import_review(lines, basename(out)))
  if (has_runner && length(src_runner)) {
    runner_lines <- .set_marker_lines(readLines(src_runner[[1L]], warn = FALSE), subject, type, src_runner[[1L]])
    writeLines(runner_lines, runner)
    review <- c(review, list(.import_review(runner_lines, basename(runner))))
  }
  ok <- TRUE

  message("import_job(): wrote '", out, "' from '", normalizePath(from, winslash = "/"), "'.",
          if (has_runner && !length(src_runner)) {
            paste0("\nThe source job has no runner beside it, so '", basename(runner), "' is the template's.")
          },
          paste(unlist(review), collapse = ""))
  invisible(out)
}

# The carried-over choices in `lines` to review, as message text naming
# `file` and line numbers, never values: a WHERE selection can name a patient.
.import_review <- function(lines, file) {
  code <- !grepl("^\\s*#", lines)
  found <- list(
    "DATASET" = which(code & grepl("^\\s*DATASET\\s*<-", lines)),
    "WHERE selection" = which(code & grepl("^\\s*WHERE\\s*<-", lines) &
                                !grepl("^\\s*WHERE\\s*<-\\s*NULL\\s*(#.*)?$", lines)),
    "EDIT: markers" = grep(.edit_token(), lines, fixed = TRUE),
    # A path from the file system's root, a home directory, a drive letter or
    # a network share (//server, or \\server written in R as "\\\\server"),
    # after a quote, a space or the start of the line. A share needs four
    # backslashes in the source, so a regex's "\\1" is not one.
    "absolute paths" = grep("(^|[[:space:]\"'`])(/{1,2}[A-Za-z_]|~/|[A-Za-z]:[/\\\\]|\\\\{4}[A-Za-z])", lines)
  )
  found <- found[lengths(found) > 0L]
  if (!length(found)) return(paste0("\nNothing in ", file, " to review."))
  paste0("\nReview in ", file, ":",
         paste0("\n  ", names(found), ": line", ifelse(lengths(found) > 1L, "s ", " "),
                vapply(found, toString, ""), collapse = ""))
}
