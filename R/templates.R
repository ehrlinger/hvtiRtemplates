#' List the supported R job templates
#'
#' These templates are supported: they render, they are tested, and they are
#' the intended starting point for a new analysis job.
#'
#' A template is named \code{<NN.MM>-<prefix>.qmd} and lives in the taxonomy
#' folder it scaffolds into, so \code{folder} and \code{ordinal} are read from
#' the tree rather than looked up. \code{\link{hvti_taxonomy}} is a cross-check
#' on that, enforced by the test suite, not a source for it.
#'
#' @return A data frame with columns \code{name}, \code{prefix}, \code{ordinal},
#'   \code{folder} and \code{file}.
#' @export
#' @examples
#' template_list()
template_list <- function() {
  dir <- system.file("templates", package = "hvtiRtemplates")
  files <- if (nzchar(dir)) {
    list.files(dir, pattern = "[.]qmd$", full.names = TRUE, recursive = TRUE)
  } else {
    character(0)
  }
  fields <- do.call(rbind, lapply(basename(files), .template_fields))
  if (is.null(fields)) {
    fields <- data.frame(ordinal = character(0), prefix = character(0),
                         stringsAsFactors = FALSE)
  }

  data.frame(
    name    = sub("[.]qmd$", "", basename(files)),
    prefix  = fields$prefix,
    ordinal = fields$ordinal,
    folder  = basename(dirname(files)),
    file    = files,
    stringsAsFactors = FALSE
  )
}

#' Path to a supported template
#'
#' @param prefix Analysis prefix, e.g. \code{"ac"}. See \code{\link{template_list}}.
#' @return The full path, as \code{character(1)}.
#' @export
#' @examples
#' try(template_path("ac"))
template_path <- function(prefix) {
  tl <- template_list()
  i <- match(prefix, tl$prefix)
  if (is.na(i)) {
    stop("unknown template: ", prefix,
         if (nrow(tl)) paste0(". Available: ", paste(stats::na.omit(tl$prefix), collapse = ", "))
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
