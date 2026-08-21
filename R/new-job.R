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
  invisible(out)
}
