#' Scaffold a new analysis job from a template
#'
#' @description
#' Copies a supported job template into the taxonomy folder it belongs to,
#' named \code{<endpoint>-<type>-<NN.MM>-<prefix>.qmd}. Refuses to overwrite an
#' existing job: a job file accumulates a study's edits, and silently replacing
#' one would discard them.
#'
#' @details
#' A job is identified by four fields. Two come from the template — its
#' \code{ordinal} and \code{prefix} — and two from the caller. The pair
#' \code{(endpoint, type)} names the \strong{set} the job belongs to, and both
#' are required: one endpoint is analysed by several methods, and the jobs those
#' chains share would otherwise collide. A death-hazard set and a death
#' random-forest-survival set both begin from the same life table, so keyed on
#' the endpoint alone both would be written to one filename.
#'
#' @param prefix Job type: one of the prefixes reported by
#'   \code{\link{template_list}}.
#' @param endpoint The endpoint this job analyses, e.g. \code{"dead_pa"}.
#' @param type The analysis type the job's set belongs to, e.g. \code{"hz"}.
#' @param dir The study root to write into. The taxonomy folder beneath it is
#'   created if it does not exist.
#'
#' @return The path written, invisibly. Errors if the copy fails, so the
#'   returned path always names a file that exists.
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
new_job <- function(prefix, endpoint, type, dir = ".") {
  .check_field("endpoint", endpoint)
  .check_field("type", type)

  tl <- template_list()
  valid <- sort(unique(stats::na.omit(tl$prefix)))
  if (!prefix %in% valid) {
    stop("new_job(): unknown prefix '", prefix, "'. Valid prefixes: ",
         paste(valid, collapse = ", "), call. = FALSE)
  }
  i <- match(prefix, tl$prefix)

  out_dir <- file.path(dir, tl$folder[[i]])
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  out <- file.path(out_dir, paste0(endpoint, "-", type, "-",
                                   tl$ordinal[[i]], "-", prefix, ".qmd"))

  if (file.exists(out)) {
    stop("new_job(): '", out, "' already exists; refusing to overwrite.",
         call. = FALSE)
  }
  if (!file.copy(tl$file[[i]], out, overwrite = FALSE)) {
    stop("new_job(): failed to write '", out, "'.", call. = FALSE)
  }
  .set_markers(out, endpoint, type)
  invisible(out)
}

# `endpoint` and `type` are written straight into the filename, which is
# `-`-separated with the ordinal's `.` reserved to itself, so neither
# character may appear in either field. Reject anything else that would
# produce a filename the naming scheme cannot parse back: not length-1,
# `NA`, or outside `[A-Za-z0-9_]+` -- which also excludes a leading `../`
# that would otherwise write outside the taxonomy folder.
.check_field <- function(arg, value) {
  ok <- is.character(value) && length(value) == 1L && !is.na(value) &&
    grepl("^[A-Za-z0-9_]+$", value)
  if (!ok) {
    stop("new_job(): `", arg, "` must be a single non-NA string matching ",
         "'^[A-Za-z0-9_]+$' (it becomes a '-'-separated filename field, so '-' ",
         "is reserved as the separator and '.' to the ordinal); got ",
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
.set_markers <- function(path, endpoint, type) {
  txt <- readLines(path, warn = FALSE)

  i_endpoint <- grep("^ENDPOINT <- ", txt)
  if (length(i_endpoint) != 1L) {
    stop("new_job(): '", path, "' has ", length(i_endpoint), " lines matching ",
         "'^ENDPOINT <- ', expected exactly 1; cannot substitute the set markers.",
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
