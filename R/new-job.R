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
#' d <- file.path(tempdir(), "new-job-example")
#' new_job("ac", "dead_pa", "hz", dir = d)
#' list.files(d, recursive = TRUE)
#' unlink(d, recursive = TRUE)
new_job <- function(prefix, endpoint, type, dir = ".", qualifier = NULL) {
  .check_field("endpoint", endpoint)
  .check_field("type", type)
  if (!is.null(qualifier)) .check_field("qualifier", qualifier)

  # One row or an error. Selecting with match() took the FIRST row for a
  # prefix and said nothing about the others, which is safe only while every
  # prefix has one template.
  # Re-raised with this function's own prefix. .select_template() is shared
  # with template_path(), so its messages say "template selection:" and
  # "unknown template:", where every other error this function raises says
  # "new_job():". A user-facing API should be greppable by one name.
  # Raised by Copilot on #76.
  row <- tryCatch(
    .select_template(template_list(), prefix, qualifier),
    error = function(e) stop("new_job(): ", conditionMessage(e), call. = FALSE)
  )

  out_dir <- file.path(dir, row$folder[[1L]])
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  # The job carries the template's qualifier. A job scaffolded from
  # dp-trends.qmd is a trends job, and a filename that drops that says only
  # "some dp job", which is the thing the template split exists to fix.
  #
  # No ordinal: it was dropped on 2026-09-03, and the taxonomy folder the job
  # lands in is what the old `NN` duplicated. `row$folder` is the BARE name,
  # not the numbered directory the template sits in, because a study's own
  # folders are `distributions/` and `analyses/`; writing to a numbered one
  # would split the study's estate across two spellings.
  stem <- paste0(endpoint, "-", type, "-", prefix,
                 if (!is.na(row$qualifier[[1L]])) paste0("-", row$qualifier[[1L]]) else "")
  out <- file.path(out_dir, paste0(stem, ".qmd"))

  if (file.exists(out)) {
    stop("new_job(): '", out, "' already exists; refusing to overwrite.",
         call. = FALSE)
  }
  if (!file.copy(row$file[[1L]], out, overwrite = FALSE)) {
    stop("new_job(): failed to write '", out, "'.", call. = FALSE)
  }
  # A job file named for one set but declaring another is exactly the defect
  # the marker substitution below exists to prevent, so it must not survive
  # the failure that produced it. Remove the copy on any error past this
  # point -- otherwise a retry after a fixed template hits the
  # refuse-to-overwrite guard above and reports "already exists", pointing at
  # the wrong cause.
  ok <- FALSE
  on.exit(if (!ok) unlink(out), add = TRUE)
  .set_markers(out, endpoint, type)
  ok <- TRUE
  invisible(out)
}

# `endpoint` and `type` are written straight into the filename, which is
# `-`-separated and ends in a `.`-separated extension, so neither character
# may appear in either field. Reject anything else that would
# produce a filename the naming scheme cannot parse back: not length-1,
# `NA`, or outside `[A-Za-z0-9_]+` -- which also excludes a leading `../`
# that would otherwise write outside the taxonomy folder.
.check_field <- function(arg, value) {
  ok <- is.character(value) && length(value) == 1L && !is.na(value) &&
    grepl("^[A-Za-z0-9_]+$", value)
  if (!ok) {
    stop("new_job(): `", arg, "` must be a single non-NA string matching ",
         "'^[A-Za-z0-9_]+$' (it becomes a '-'-separated filename field, so '-' ",
         "is reserved as the separator and '.' to the extension); got ",
         paste(deparse(value), collapse = ", "), ".", call. = FALSE)
  }
}

# Rewrite the template's ENDPOINT/TYPE declarations to the values `new_job()`
# already put in the filename, so a scaffolded job arrives self-consistent
# rather than naming one set and declaring another. `set_path()` in the job
# body resolves from the declarations, not the filename, so a mismatch would
# silently write into another set's artifact directory -- exactly the
# collision the (endpoint, type) key exists to prevent.
#
# Each line is required to appear exactly once: a template whose markers moved
# or were removed must fail loudly here rather than hand back a job that looks
# scaffolded but silently kept the template's placeholder values.
#
# Requires `endpoint` and `type` to already be validated by .check_field():
# they are interpolated straight into an R string literal with no escaping,
# so an unvalidated `"` or `\` would emit a syntactically broken job. A future
# caller (a planned `new_job_set()`) must run .check_field() first too.
.set_markers <- function(path, endpoint, type) {
  txt <- readLines(path, warn = FALSE)

  i_endpoint <- grep("^ENDPOINT\\s+<- ", txt)
  if (length(i_endpoint) != 1L) {
    stop("new_job(): '", path, "' has ", length(i_endpoint), " lines matching ",
         "'^ENDPOINT\\\\s+<- ', expected exactly 1; cannot substitute the set markers.",
         call. = FALSE)
  }
  i_type <- grep("^TYPE\\s+<- ", txt)
  if (length(i_type) != 1L) {
    stop("new_job(): '", path, "' has ", length(i_type), " lines matching ",
         "'^TYPE\\\\s+<- ', expected exactly 1; cannot substitute the set markers.",
         call. = FALSE)
  }

  # Keep the alignment style of the original lines: TYPE is padded so its
  # `<-` lines up under ENDPOINT's.
  txt[[i_endpoint]] <- paste0("ENDPOINT <- \"", endpoint, "\"")
  txt[[i_type]]     <- paste0("TYPE     <- \"", type, "\"")
  writeLines(txt, path)
}
