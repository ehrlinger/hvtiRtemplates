#' Bring a job from another study into this one
#'
#' @description
#' Copies a job `.qmd` from another study into the current study, keeping
#' the source study's edits, so a job adapted once, such as an aorta-specific
#' `ac` job, can be adapted again rather than rebuilt from the template.
#'
#' @details
#' The job is written where [add_job()] would write a new job from
#' the same template, under the name it would give it, and with the same
#' setup: the template's packages and any further packages the job's own
#' setup chunk attaches are installed into the study's renv library, the
#' Quarto provenance hooks are installed, and an existing job is never
#' overwritten. The template is read from the job's file name, in either
#' spelling `add_job()` has used.
#'
#' `subject` and `type` default to the source job's own. Either can
#' be changed on the way in, and the job's `SUBJECT` and `TYPE`
#' lines are rewritten to match its new name, as `add_job()` does.
#'
#' A job that runs from a companion runner script brings its runner too, when
#' one sits beside it. Without one, the job gets the template's runner, and the
#' message says so.
#'
#' **What to review.** Everything else is carried as the source study left
#' it, including choices that were right for that study and may be wrong for
#' this one. `import_job()` rewrites none of them. Instead its message
#' lists, by line number, each one to check:
#' \itemize{
#'   \item the `DATASET` the job reads;
#'   \item a `WHERE` row selection, unless it is `NULL`;
#'   \item every `EDIT:` marker still in the job;
#'   \item every absolute file path, such as `"/studies/aorta/..."` or
#'     `"C:/..."`, which names a file in the other study or on another
#'     machine.
#' }
#' Values are never quoted in the message, because a selection can name a
#' patient. Paths relative to the study, which is how a template refers to its
#' study's files, are not listed.
#'
#' The job keeps the template version it was written from, so
#' [upgrade_job()] can bring an older job up to the current template
#' afterwards: `upgrade_job(import_job(path))`.
#'
#' @param path The job to import: a `.qmd` file in another study, named
#'   as `add_job()` names jobs.
#' @param subject,type The job's set in this study. `NULL`, the default,
#'   keeps the source job's. See [add_job()] for what they decide.
#' @param root The study root to import into. `NULL`, the default, finds
#'   it by walking up from the working directory, as `add_job()` does.
#' @param from,dir Deprecated: the old names of `path` and `root`.
#'   They work, with a warning, for one more release; giving an old name with
#'   its new one is an error.
#'
#' @return The imported job's path, invisibly. On any failure no file is left
#'   behind, the runner included.
#'
#' @seealso [add_job()], [upgrade_job()]
#'
#' @examples
#' other <- file.path(tempdir(), "import-job-other")
#' here <- file.path(tempdir(), "import-job-here")
#' for (d in c(other, here)) {
#'   invisible(hvtiRutilities::study_setup(d, study = "Example", study_tracker_id = 1L, renv = FALSE))
#' }
#' job <- add_job("ac", subject = "death", type = "hz", root = other)
#' # The other study's edit.
#' lines <- readLines(job)
#' lines <- sub("^DATASET <- \"built\"", "DATASET <- \"built_aorta\"", lines)
#' writeLines(lines, job)
#'
#' imported <- import_job(job, subject = "reop", root = here)
#' grep("^(DATASET|SUBJECT) ", readLines(imported), value = TRUE)
#'
#' # An existing job is never overwritten.
#' try(import_job(job, subject = "reop", root = here))
#' unlink(c(other, here), recursive = TRUE)
#' @export
import_job <- function(path, subject = NULL, type = NULL, root = NULL, from, dir) {
  if (!missing(from)) path <- .take_renamed("import_job", "from", "path", from, !missing(path))
  if (!missing(dir)) root <- .take_renamed("import_job", "dir", "root", dir, !missing(root))
  tryCatch(.check_scalar_string("path", path), error = function(e) {
    stop("import_job(): ", sub("^template selection: ", "", conditionMessage(e)), call. = FALSE)
  })
  if (!file.exists(path) || dir.exists(path)) stop("import_job(): job not found: ", path, call. = FALSE)
  if (!grepl("[.]qmd$", path)) stop("import_job(): a job is a .qmd file: ", path, call. = FALSE)
  fields <- .job_template_fields(path)
  if (is.null(fields)) {
    stop("import_job(): '", basename(path), "' does not name a template; expected ",
         "<prefix>[.<qualifier>].<subject>.<type>.qmd.", call. = FALSE)
  }
  # A job written under a template's name before a rename carries that
  # template's code, which may assume the old folder: a dp.trends job links its
  # figures as though it sat in graphs/. Copied into the renamed template's
  # folder, its report would lose them, so it is upgraded where it is first.
  renamed <- .template_rename(template_list(), fields$prefix, fields$qualifier)
  if (!is.null(renamed)) {
    stop("import_job(): '", basename(path), "' was written under ", sub("-", ".", renamed$from, fixed = TRUE),
         ", since renamed ", sub("-", ".", renamed$to, fixed = TRUE), ", and its code may assume the old folder. ",
         "Run upgrade_job() on it in its own study, then import the upgraded job.", call. = FALSE)
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
  if (is.null(root)) root <- .default_study_root("import_job")

  lines <- readLines(path, warn = FALSE)
  # The SUBJECT and TYPE lines are checked before anything is written.
  lines <- .set_marker_lines(lines, subject, type, path)
  src_runner <- c(sub("[.]qmd$", ".runner.R", path), sub("[.]qmd$", "-runner.R", path))
  src_runner <- src_runner[file.exists(src_runner)]

  # Packages the other study added to the job's setup chunk, before anything is
  # written, so a refusal leaves this study as it was. add_job() installs the
  # template's own.
  # A job with no readable setup chunk is refused, not read as needing nothing.
  pk <- tryCatch(.template_packages(path), error = function(e) {
    stop("import_job(): cannot read the packages the job attaches: ", conditionMessage(e), call. = FALSE)
  })
  extra <- pk$package
  unread <- attr(pk, "unread")
  if (length(extra) && dir.exists(root)) {
    hvtiRutilities::study_need(extra, root = root, caller = "import_job", only_in_renv = TRUE)
  }

  # add_job() refuses an existing job in any spelling, installs packages and
  # hooks, and leaves nothing behind on failure. Its job and runner are then
  # replaced with the imported text.
  qualifier <- if (is.na(row$qualifier[[1L]])) NULL else row$qualifier[[1L]]
  out <- withCallingHandlers(
    tryCatch(add_job(row$prefix[[1L]], subject, type, root = root, qualifier = qualifier),
             error = function(e) stop(sub("^add_job\\(\\): ", "import_job(): ", conditionMessage(e)), call. = FALSE)),
    hvtiRtemplates_deprecated = function(w) invokeRestart("muffleWarning")
  )
  runner <- sub("[.]qmd$", ".runner.R", out)
  has_runner <- file.exists(runner)
  ok <- FALSE
  # The runner is removed on failure whether add_job() wrote it or the source's
  # is written below, for a template that has none.
  on.exit(if (!ok) unlink(c(out, if (has_runner || length(src_runner)) runner)), add = TRUE)
  writeLines(lines, out)
  review <- list(.import_review(lines, basename(out)))
  if (length(src_runner)) {
    runner_lines <- .set_marker_lines(readLines(src_runner[[1L]], warn = FALSE), subject, type, src_runner[[1L]])
    writeLines(runner_lines, runner)
    review <- c(review, list(.import_review(runner_lines, basename(runner))))
  }
  ok <- TRUE

  .hvti_inform("import_job(): wrote '", out, "' from '", normalizePath(path, winslash = "/"), "'.",
               if (has_runner && !length(src_runner)) {
                 paste0("\nThe source job has no runner beside it, so '", basename(runner), "' is the template's.")
               },
               if (unread > 0L) {
                 paste0("\n", unread, " library() call", if (unread > 1L) "s", " in the setup chunk could not be read, ",
                        "so what ", if (unread > 1L) "they attach" else "it attaches", " was not installed. Install it with ",
                        "hvtiRutilities::study_need().")
               },
               paste(unlist(review), collapse = ""))
  invisible(out)
}

# The carried-over choices in `lines` to review, as message text naming
# `file` and line numbers, never values: a WHERE selection can name a patient.
.import_review <- function(lines, file) {
  code <- !grepl("^\\s*#", lines)
  # An assignment in any of R's spellings: <-, <<- or = (but not ==).
  assign <- "\\s*(<<?-|=($|[^=]))"
  found <- list(
    "DATASET" = which(code & grepl(paste0("^\\s*DATASET", assign), lines)),
    "WHERE selection" = which(code & grepl(paste0("^\\s*WHERE", assign), lines) &
                                !grepl("^\\s*WHERE\\s*(<<?-|=)\\s*NULL\\s*(#.*)?$", lines)),
    "EDIT: markers" = grep(.edit_token(), lines, fixed = TRUE),
    # A path from the file system's root, a home directory, a drive letter or
    # a network share (//server, or \\server written in R as "\\\\server"),
    # after a quote, a space or the start of the line. A root path's first
    # component may start with a letter, digit, dot or underscore ("/2024/").
    # A share needs four backslashes in the source, so a regex's "\\1" is not one.
    "absolute paths" = grep("(^|[[:space:]\"'`])(/{1,2}[A-Za-z0-9_.]|~/|[A-Za-z]:[/\\\\]|\\\\{4}[A-Za-z])", lines)
  )
  found <- found[lengths(found) > 0L]
  if (!length(found)) return(paste0("\nNothing in ", file, " to review."))
  paste0("\nReview in ", file, ":",
         paste0("\n  ", names(found), ": line", ifelse(lengths(found) > 1L, "s ", " "),
                vapply(found, toString, ""), collapse = ""))
}
