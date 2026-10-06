#' Scaffold a new analysis job from a template
#'
#' @description
#' Copies a supported job template into the taxonomy folder it belongs to,
#' named \code{<subject>-<type>-<prefix>[-<qualifier>].qmd}. Refuses to overwrite an
#' existing job: a job file accumulates a study's edits, and silently replacing
#' one would discard them.
#'
#' @details
#' \strong{What each argument decides.} \code{prefix} chooses the template,
#' together with \code{qualifier} where a prefix carries several job types.
#' \code{subject} and \code{type} are yours to choose. The catalog holds no
#' list of valid values for either, only the rule that each matches
#' \code{^[A-Za-z0-9_]+$}. They are more than a filename, though. Together
#' they name the job's set, and the set is used in four places:
#' \itemize{
#'   \item the job's filename, \code{<subject>-<type>-<prefix>[-<qualifier>].qmd};
#'   \item the job's own \code{SUBJECT} and \code{TYPE} lines, which
#'     \code{add_job()} rewrites to your values;
#'   \item the render, which stops when the filename and those two lines
#'     disagree, so a job renamed by hand cannot quietly write its results
#'     into another set;
#'   \item the folder the job saves its results in, a \code{<subject>-<type>}
#'     folder under the study's \code{estimates} (and, for some templates,
#'     \code{graphs}), which is where the next job in the chain looks for
#'     them.
#' }
#' The last of these is the one that bites. \code{hm} reads the
#' \code{hz.rds} that \code{hz} saved, and finds it only when both jobs
#' carry the same subject and type. Give every job of one analysis the same
#' pair, e.g. \code{subject = "death", type = "hz"} for \code{ac}, \code{hz},
#' \code{hm} and \code{hp}, and give a different analysis a different pair.
#' The \code{call} column of \code{\link{template_list}} shows each template's
#' own example values, which are a starting point, not a requirement.
#'
#' A job is identified by three or four fields. One or two come from the
#' template, its \code{prefix} and, where the prefix carries several job types,
#' its \code{qualifier}; two come from the caller. The pair
#' \code{(subject, type)} names the \strong{set} the job belongs to, and both
#' are required. The subject is the grouping topic, not necessarily a
#' statistical endpoint. An endpoint-driven job may use \code{"death"}; an
#' endpoint-free job may use \code{"cohort"}, \code{"treatment"}, or
#' \code{"labs"} without inventing an outcome. One subject can be analyzed by
#' several methods, and the jobs those chains share would otherwise collide. A
#' death-hazard set and a death random-forest-survival set both begin from the
#' same life table, so keyed on the subject alone both would be written to one
#' filename.
#'
#' Scaffolding also installs the study's Quarto provenance hooks. Existing
#' pre-render and post-render commands and unrelated project settings are
#' preserved, while the provenance publisher is kept last. Repeated calls are
#' idempotent.
#'
#' A template whose job runs from a companion script also writes that script
#' beside the job, from \code{inst/runners/<name>-runner.R}: today the
#' bootstrap reports \code{bl}, \code{br}, \code{bc} and \code{bh}, whose
#' runner screens and saves the bag the report reads. The runner is named
#' \code{<subject>-<type>-<prefix>-runner.R}, gets the same \code{SUBJECT} and
#' \code{TYPE} substitution, and is refused, like the job, if it already
#' exists. Its study choices carry \code{EDIT:} markers for the author to
#' work.
#'
#' A template the catalog marks deprecated, such as \code{dp-postage}, still
#' scaffolds, with a warning naming its replacement; see
#' \code{\link{template_catalog}}.
#'
#' @param qualifier Job type within the prefix, e.g. \code{"trends"} for
#'   \code{dp}. Required only where a prefix carries more than one template;
#'   omitting it there is an error naming the choices, never a silent pick.
#'   Restricted to \code{[A-Za-z0-9_]+}, because \code{-} separates the
#'   filename's fields.
#' @param prefix Job type: one of the prefixes reported by
#'   \code{\link{template_list}}, or a template's full name as reported in
#'   its \code{name} column, e.g. \code{"dp-trends"}. A full name carries the
#'   qualifier, so \code{qualifier} must then be left \code{NULL}.
#' @param subject Grouping topic for the job set, e.g. \code{"death"} or
#'   \code{"cohort"}. A subject names a statistical endpoint only when the
#'   job analyses one. Your choice: there is no list of valid values, and
#'   every job of one analysis should share it (see Details). Must
#'   match \code{^[A-Za-z0-9_]+$}: \code{-} separates the filename's fields and
#'   \code{.} separates the extension, so neither may appear here.
#' @param type The analysis type the job's set belongs to, e.g. \code{"hz"}.
#'   Your choice, like \code{subject}, and shared the same way. Must match
#'   \code{^[A-Za-z0-9_]+$}, for the same reason as \code{subject}.
#' @param dir The study root to write into. The taxonomy folder beneath it is
#'   created if it does not exist.
#'
#' @return The job's path, invisibly. On any failure -- including one after
#'   the copy, while substituting the set markers -- no file is left behind,
#'   the runner included, so a returned path always names a complete,
#'   correctly-declared job.
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
#' add_job(prefix = "ac", subject = "death", type = "hz", dir = d)
#'
#' # A qualified template by its full name, the form template_list()$call prints.
#' add_job("dc-gfup", subject = "cohort", type = "eda", dir = d)
#'
#' # A deprecated template still scaffolds, and the warning names its replacement.
#' tryCatch(add_job("dp-gfup", subject = "cohort", type = "eda", dir = d),
#'          warning = conditionMessage)
#'
#' # A job accumulates a study's edits, so an existing one is never overwritten.
#' try(add_job(prefix = "ac", subject = "death", type = "hz", dir = d))
#'
#' list.files(d, pattern = "[.]qmd$", recursive = TRUE)
#' unlink(d, recursive = TRUE)
add_job <- function(prefix, subject, type, dir = ".", qualifier = NULL) {
  absent <- c("subject", "type")[c(missing(subject), missing(type))]
  if (length(absent)) {
    stop(.missing_field_message(absent, if (!missing(prefix)) prefix, qualifier), call. = FALSE)
  }
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
  .warn_if_deprecated(row, "add_job")

  out_dir <- hvtiRutilities::study_dir(row$folder[[1L]], root = dir)
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  out <- .job_path(row, subject, type, dir)
  # A job that runs from a companion script gets that script too, named to
  # pair with the job. Both are checked before either is written, so a
  # refusal leaves the study as it was.
  runner_src <- .runner_template(row$name[[1L]])
  runner <- if (nzchar(runner_src)) sub("[.]qmd$", "-runner.R", out) else character()

  for (path in c(out, runner)) {
    if (file.exists(path)) {
      stop("add_job(): '", path, "' already exists; refusing to overwrite.",
           call. = FALSE)
    }
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
  on.exit(if (!ok) unlink(c(out, runner)), add = TRUE)
  .set_markers(out, subject, type)
  if (length(runner)) {
    if (!file.copy(runner_src, runner, overwrite = FALSE)) {
      stop("add_job(): failed to write '", runner, "'.", call. = FALSE)
    }
    .set_markers(runner, subject, type)
  }
  .install_provenance_hooks(dir)
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

# The error for a call that leaves out `subject`, `type` or both (#224). R's
# own "argument is missing, with no default" tells a new user nothing about
# what to pass. Neither field has a list of valid values to show: both name
# the job's set and are the caller's choice, so the message says so, gives
# the pattern .check_field() enforces, and shows the template's own call from
# template_list() as a worked example. A prefix that cannot be resolved here
# is reported by the selection error once the fields are supplied, so this
# message only points at the catalog rather than repeating that error.
.missing_field_message <- function(absent, prefix = NULL, qualifier = NULL, fn = "add_job") {
  example <- NA_character_
  if (!is.null(prefix)) {
    tl <- template_list()
    row <- tryCatch(.select_template(tl, prefix, qualifier), error = function(e) NULL)
    if (!is.null(row)) example <- row$call[[1L]]
  }
  paste0(
    fn, "(): ", paste0("`", absent, "`", collapse = " and "),
    if (length(absent) > 1L) " are" else " is", " missing. ",
    "`subject` (the grouping topic, e.g. \"death\" or \"cohort\") and `type` (the analysis type, ",
    "e.g. \"hz\") name the job's set. They are your choice, not a list in the catalog: any name ",
    "matching '^[A-Za-z0-9_]+$'. ",
    if (length(example) == 1L && !is.na(example)) {
      paste0("This template's own call is: ", example)
    } else {
      "See template_list()$call for each template's own call."
    }
  )
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

# The companion runner a template's job runs from, or "" when it has none.
# Runners live in inst/runners/, outside inst/templates/, because they are not
# templates: template_list() and the roadmap ledger count only the reports.
.runner_template <- function(name) {
  system.file("runners", paste0(name, "-runner.R"), package = "hvtiRtemplates")
}
