#' List the supported R job templates
#'
#' These templates are supported: they render, they are tested, and they are
#' the intended starting point for a new analysis job.
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

# Parse a template file name into its fields.
#
# A template is named `<NN>.<MM>-<prefix>.qmd` -- "03.01-ac.qmd". The name is
# fully structured, so it is matched by pattern rather than split on separators:
# `.` is a field separator inside the ordinal AND the extension separator, and a
# split-based parser cannot tell the two apart. This replaces `.prefix_of()`,
# whose heuristics (drop a leading "tp.", reject a first field over five
# characters) existed only because legacy names were unstructured.
#
# The two digits either side of the dot are required. The zero-padding is what
# makes a flat folder sort into run order past nine entries, so an unpadded name
# is rejected here rather than allowed to sort wrongly later.
#
# Returns `ordinal` and `prefix` as NA for a name that does not match, rather
# than erroring: `template_list()` reports what is on disk, and a stray file
# should not stop it. `test-taxonomy.R` is what turns an unclassified prefix
# into a build failure.
.template_fields <- function(name) {
  m <- regmatches(name, regexec("^(\\d{2}[.]\\d{2})-(.+)[.]qmd$", name))[[1L]]
  if (length(m) != 3L) {
    return(data.frame(ordinal = NA_character_, prefix = NA_character_,
                      stringsAsFactors = FALSE))
  }
  data.frame(ordinal = m[[2L]], prefix = m[[3L]], stringsAsFactors = FALSE)
}
