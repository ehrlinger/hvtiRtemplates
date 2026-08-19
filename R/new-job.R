#' Scaffold a new analysis job from a template
#'
#' @description
#' Copies a supported job template into \code{dir}, named
#' \code{<prefix>.<basename>.qmd}. Refuses to overwrite an existing job: a job
#' file accumulates a study's edits, and silently replacing one would discard
#' them.
#'
#' @param prefix Job type: one of the prefixes reported by
#'   \code{\link{template_list}}.
#' @param basename Job name, appended after the prefix.
#' @param dir Directory to write into. Created if it does not exist.
#'
#' @return The path written, invisibly.
#'
#' @seealso \code{\link{template_list}}, \code{\link{template_path}}
#'
#' @export
#'
#' @examples
#' d <- file.path(tempdir(), "new-job-example")
#' new_job("ac", "dead", dir = d)
#' list.files(d)
#' unlink(d, recursive = TRUE)
new_job <- function(prefix, basename, dir = "qmd") {
  valid <- sort(unique(stats::na.omit(template_list()$prefix)))
  if (!prefix %in% valid) {
    stop("new_job(): unknown prefix '", prefix, "'. Valid prefixes: ",
         paste(valid, collapse = ", "), call. = FALSE)
  }
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  out <- file.path(dir, paste0(prefix, ".", basename, ".qmd"))
  if (file.exists(out)) {
    stop("new_job(): '", out, "' already exists; refusing to overwrite.",
         call. = FALSE)
  }
  file.copy(template_path(prefix), out)
  invisible(out)
}
