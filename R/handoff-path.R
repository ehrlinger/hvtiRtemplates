#' Where a job's saved upstream bundle is, checked
#'
#' A downstream job names its upstream bundle by a file name and, when the
#' bundle is in another set, that set's name. Neither may hold a folder, so
#' no setting can reach outside the study's estimates. Shared by
#' \code{lm-checkpred} and \code{lp-mirror}.
#'
#' @param file The bundle's file name, \code{MODEL_FILE}.
#' @param set The set holding it, \code{MODEL_SET}, or \code{NULL} for the
#'   job's own set.
#' @param root The study root.
#' @param own A function of a file name giving its path in the job's own set.
#' @param upstream The upstream template's name, for the messages.
#' @param set_example A set name to show in the message about \code{set}.
#' @return The bundle's path. Stops when either setting is malformed or the
#'   file does not exist.
#' @noRd
.handoff_path <- function(file, set, root, own, upstream, set_example) {
  if (!is.character(file) || length(file) != 1L || is.na(file) || !grepl("^[^/\\\\]+[.]rds$", file)) {
    stop("MODEL_FILE must name one .rds file, such as \"", upstream, ".rds\", with no folder: ",
         "name another set in MODEL_SET.", call. = FALSE)
  }
  if (!is.null(set) &&
        (!is.character(set) || length(set) != 1L || is.na(set) || !grepl("^[A-Za-z0-9_]+-[A-Za-z0-9_]+$", set))) {
    stop("MODEL_SET must be NULL or one set name, \"<subject>-<type>\", such as \"", set_example, "\".",
         call. = FALSE)
  }
  path <- if (is.null(set)) own(file) else file.path(hvtiRutilities::study_dir("estimates", root), set, file)
  if (!file.exists(path)) {
    stop("Saved model not found: ", path, ". Render the ", upstream, " job first, or set MODEL_FILE and ",
         "MODEL_SET to where it saved its model.", call. = FALSE)
  }
  path
}

#' A job's patient IDs, in the form a saved bundle holds them
#'
#' A bundle saved by a current template holds a study-keyed digest of each ID,
#' so a job digests its own IDs with the same key before comparing or joining.
#' One saved before that holds raw identifiers, and is compared as text.
#'
#' @param bundle A saved bundle.
#' @param ids The job's identifiers.
#' @param root The study root.
#' @return A character vector as long as \code{ids}.
#' @noRd
.bundle_ids <- function(bundle, ids, root) {
  if (isTRUE(bundle$meta$id_digest)) .id_digest(ids, .bundle_id_key(bundle, root)) else as.character(ids)
}
