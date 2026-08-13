#' List the supported R job templates
#'
#' Unlike [corpus_manifest()], these templates are supported: they render, they
#' are tested, and they are the intended starting point for a new analysis job.
#'
#' Returns zero rows until the templates are added in stage 3 of the
#' templates-and-provenance design.
#'
#' @return A data frame with columns `name`, `prefix`, `folder` and `file`.
#' @export
#' @examples
#' template_list()
template_list <- function() {
  dir <- system.file("templates", package = "hvtiRtemplates")
  files <- if (nzchar(dir)) {
    list.files(dir, pattern = "[.]qmd$", full.names = TRUE)
  } else {
    character(0)
  }
  name <- sub("[.]qmd$", "", basename(files))
  prefix <- vapply(basename(files), .prefix_of, character(1), USE.NAMES = FALSE)
  tx <- hvti_taxonomy()

  data.frame(
    name   = name,
    prefix = prefix,
    folder = tx$folder[match(prefix, tx$prefix)],
    file   = files,
    stringsAsFactors = FALSE
  )
}

#' Path to a supported template
#'
#' @param name Template name, e.g. `"hz"`. See [template_list()].
#' @return The full path, as `character(1)`.
#' @export
#' @examples
#' try(template_path("hz"))
template_path <- function(name) {
  tl <- template_list()
  i <- match(name, tl$name)
  if (is.na(i)) {
    stop("unknown template: ", name,
         if (nrow(tl)) paste0(". Available: ", paste(tl$name, collapse = ", "))
         else ". No templates are installed yet.",
         call. = FALSE)
  }
  tl$file[[i]]
}
