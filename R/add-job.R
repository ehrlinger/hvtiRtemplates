#' Scaffold a new analysis job from a template
#'
#' @description
#' Copies a supported job template into the taxonomy folder it belongs to,
#' named \code{<endpoint>-<type>-<prefix>[-<qualifier>].qmd}. Refuses to overwrite an
#' existing job: a job file accumulates a study's edits, and silently replacing
#' one would discard them.
#'
#' @details
#' A job is identified by three or four fields. One or two come from the
#' template, its \code{prefix} and, where the prefix carries several job types,
#' its \code{qualifier}; two come from the caller. The pair
#' \code{(endpoint, type)} names the \strong{set} the job belongs to, and both
#' are required: one endpoint is analysed by several methods, and the jobs those
#' chains share would otherwise collide. A death-hazard set and a death
#' random-forest-survival set both begin from the same life table, so keyed on
#' the endpoint alone both would be written to one filename.
#'
#' @param qualifier Job type within the prefix, e.g. \code{"trends"} for
#'   \code{dp}. Required only where a prefix carries more than one template;
#'   omitting it there is an error naming the choices, never a silent pick.
#'   Restricted to \code{[A-Za-z0-9_]+}, because \code{-} separates the
#'   filename's fields.
#' @param prefix Job type: one of the prefixes reported by
#'   \code{\link{template_list}}.
#' @param endpoint The endpoint this job analyses, e.g. \code{"dead_pa"}. Must
#'   match \code{^[A-Za-z0-9_]+$}: \code{-} separates the filename's fields and
#'   \code{.} separates the extension, so neither may appear here.
#' @param type The analysis type the job's set belongs to, e.g. \code{"hz"}.
#'   Must match \code{^[A-Za-z0-9_]+$}, for the same reason as \code{endpoint}.
#' @param dir The study root to write into. The taxonomy folder beneath it is
#'   created if it does not exist.
#'
#' @return The path written, invisibly. On any failure -- including one after
#'   the copy, while substituting the set markers -- no file is left behind,
#'   so a returned path always names a complete, correctly-declared job.
#'
#' @seealso \code{\link{template_list}}, \code{\link{template_path}}
#'
#' @export
#'
#' @examples
#' d <- file.path(tempdir(), "add-job-example")
#' invisible(hvtiRutilities::study_setup(
#'   d, study = "Example", study_tracker_id = 1L
#' ))
#' add_job("ac", "dead_pa", "hz", dir = d)
#' list.files(d, recursive = TRUE)
#' unlink(d, recursive = TRUE)
add_job <- function(prefix, subject, type, dir = ".", qualifier = NULL) {
  .check_field("subject", subject)
  .check_field("type", type)
  if (!is.null(qualifier)) .check_field("qualifier", qualifier)

  # One row or an error. Selecting with match() took the FIRST row for a
  # prefix and said nothing about the others, which is safe only while every
  # prefix has one template.
  # Re-raised with this function's own prefix. .select_template() is shared
  # with template_path(), so its messages say "template selection:" and
  # "unknown template:", where every other error this function raises says
  # "add_job():". A user-facing API should be greppable by one name.
  # Raised by Copilot on #76.
  row <- tryCatch(
    .select_template(template_list(), prefix, qualifier),
    error = function(e) stop("add_job(): ", conditionMessage(e), call. = FALSE)
  )

  out_dir <- hvtiRutilities::study_dir(row$folder[[1L]], root = dir)
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  out <- .job_path(row, subject, type, dir)

  if (file.exists(out)) {
    stop("add_job(): '", out, "' already exists; refusing to overwrite.",
         call. = FALSE)
  }
  if (!file.copy(row$file[[1L]], out, overwrite = FALSE)) {
    stop("add_job(): failed to write '", out, "'.", call. = FALSE)
  }
  # A job file named for one set but declaring another is exactly the defect
  # the marker substitution below exists to prevent, so it must not survive
  # the failure that produced it. Remove the copy on any error past this
  # point -- otherwise a retry after a fixed template hits the
  # refuse-to-overwrite guard above and reports "already exists", pointing at
  # the wrong cause.
  ok <- FALSE
  on.exit(if (!ok) unlink(out), add = TRUE)
  .set_markers(out, subject, type)
  ok <- TRUE
  invisible(out)
}

# `subject` and `type` are written straight into the filename, which is
# `-`-separated and ends in a `.`-separated extension, so neither character
# may appear in either field. Reject anything else that would
# produce a filename the naming scheme cannot parse back: not length-1,
# `NA`, or outside `[A-Za-z0-9_]+` -- which also excludes a leading `../`
# that would otherwise write outside the taxonomy folder.
#
# `fn` labels the message with the caller's own name, so a bad field blames
# whichever exported function was actually called -- open_job() shares this
# validator with add_job() and must not have its errors say "add_job():".
.check_field <- function(arg, value, fn = "add_job") {
  ok <- is.character(value) && length(value) == 1L && !is.na(value) &&
    grepl("^[A-Za-z0-9_]+$", value)
  if (!ok) {
    stop(fn, "(): `", arg, "` must be a single non-NA string matching ",
         "'^[A-Za-z0-9_]+$' (it becomes a '-'-separated filename field, so '-' ",
         "is reserved as the separator and '.' to the extension); got ",
         paste(deparse(value), collapse = ", "), ".", call. = FALSE)
  }
}

# Full path for the job the selected template row scaffolds into: the study's
# taxonomy folder (numbered or legacy, resolved by hvtiRutilities::study_dir())
# joined to the subject/type/prefix[/qualifier] stem. Shared by add_job(),
# which writes here, and open_job(), which only needs to test the path for
# existence and must not create the directory as a side effect of looking.
#
# The job carries the template's qualifier. A job scaffolded from
# dp-trends.qmd is a trends job, and a filename that drops that says only
# "some dp job", which is the thing the template split exists to fix.
#
# No ordinal in the filename: the taxonomy folder records placement. The
# shared resolver keeps a numbered new study and a bare legacy study in its
# own directory scheme.
.job_path <- function(row, subject, type, root) {
  out_dir <- hvtiRutilities::study_dir(row$folder[[1L]], root = root)
  stem <- paste0(subject, "-", type, "-", row$prefix[[1L]],
                 if (!is.na(row$qualifier[[1L]])) paste0("-", row$qualifier[[1L]]) else "")
  file.path(out_dir, paste0(stem, ".qmd"))
}

# Rewrite the template's SUBJECT/TYPE declarations to the values `add_job()`
# already put in the filename, so a scaffolded job arrives self-consistent
# rather than naming one set and declaring another. `set_path()` in the job
# body resolves from the declarations, not the filename, so a mismatch would
# silently write into another set's artifact directory -- exactly the
# collision the (subject, type) key exists to prevent.
#
# Each line is required to appear exactly once: a template whose markers moved
# or were removed must fail loudly here rather than hand back a job that looks
# scaffolded but silently kept the template's placeholder values.
#
# Requires `subject` and `type` to already be validated by .check_field():
# they are interpolated straight into an R string literal with no escaping,
# so an unvalidated `"` or `\` would emit a syntactically broken job. A future
# caller (a planned `add_job_set()`) must run .check_field() first too.
.set_markers <- function(path, subject, type) {
  txt <- readLines(path, warn = FALSE)

  i_subject <- grep("^SUBJECT\\s+<- ", txt)
  if (length(i_subject) != 1L) {
    stop("add_job(): '", path, "' has ", length(i_subject), " lines matching ",
         "'^SUBJECT\\\\s+<- ', expected exactly 1; cannot substitute the set markers.",
         call. = FALSE)
  }
  i_type <- grep("^TYPE\\s+<- ", txt)
  if (length(i_type) != 1L) {
    stop("add_job(): '", path, "' has ", length(i_type), " lines matching ",
         "'^TYPE\\\\s+<- ', expected exactly 1; cannot substitute the set markers.",
         call. = FALSE)
  }

  # Keep the alignment style of the original lines: TYPE is padded so its
  # `<-` lines up under SUBJECT's.
  txt[[i_subject]] <- paste0("SUBJECT <- \"", subject, "\"")
  txt[[i_type]]    <- paste0("TYPE    <- \"", type, "\"")
  writeLines(txt, path)
}
