#' Describe the legacy reference corpus
#'
#' The corpus is the SAS template library and the legacy R-family templates as
#' they stood when the group migrated to R. It is a **reference specification,
#' not a runnable asset**: nothing here is tested, supported, or maintained.
#' The institutional SAS licence expires 2026-09-29.
#'
#' @return A data frame with one row per corpus file: `file` (full path),
#'   `prefix` (analysis prefix, `NA` where the name does not carry one),
#'   `folder` (study folder), `kind` (`"sas"`, `"r"`, `"assets"` or `"docs"`)
#'   and `bytes`.
#' @export
#' @examples
#' m <- corpus_manifest()
#' table(m$kind)
corpus_manifest <- function() {
  root <- system.file("corpus", package = "hvtiRtemplates")
  if (!nzchar(root)) {
    stop("the corpus is not installed with this package", call. = FALSE)
  }
  files <- list.files(root, recursive = TRUE, full.names = TRUE)
  rel <- substring(files, nchar(root) + 2L)
  parts <- strsplit(rel, "/", fixed = TRUE)

  # Files at the corpus root (e.g. inst/corpus/README.md) describe the corpus
  # itself, not a corpus entry -- they carry no kind subdirectory and are
  # excluded rather than misclassified.
  nested <- lengths(parts) > 1L
  files <- files[nested]
  rel <- rel[nested]
  parts <- parts[nested]

  data.frame(
    file   = files,
    prefix = vapply(basename(files), .prefix_of, character(1), USE.NAMES = FALSE),
    folder = vapply(parts, function(p) if (length(p) > 1L) p[[2L]] else NA_character_,
                    character(1)),
    kind   = vapply(parts, `[[`, character(1), 1L),
    bytes  = file.size(files),
    stringsAsFactors = FALSE
  )
}

# Shared prefix-derivation helper, used by both corpus_manifest() and
# template_list() -- there is exactly one implementation of this rule.
#
# Corpus files carry an optional "tp." marker: tp.<prefix>.<rest>. Supported
# templates never carry that marker: <prefix>.<rest> (e.g. "hz.qmd") or
# <prefix>.<rest>.<rest> (e.g. "tp.hz.dead.qmd", "hz.dead.R"). Both shapes are
# handled: an initial "tp" field is dropped if present, then the next field is
# taken as the prefix. Prefixes are short; a long candidate field, or a name
# with no further field after "tp"/the leading field, means the name does not
# carry a prefix and this returns NA.
.prefix_of <- function(name) {
  p <- strsplit(name, ".", fixed = TRUE)[[1L]]
  if (length(p) >= 1L && identical(p[[1L]], "tp")) p <- p[-1L]
  if (length(p) < 2L) return(NA_character_)
  if (nchar(p[[1L]]) > 5L) return(NA_character_)
  p[[1L]]
}

#' Path to a file in the reference corpus
#'
#' @param ... Path components below `inst/corpus`, e.g.
#'   `corpus_path("sas", "distributions", "tp.hz.dead.sas")`.
#' @return The full path, as `character(1)`.
#' @export
#' @examples
#' corpus_path("sas", "distributions", "tp.hz.dead.sas")
corpus_path <- function(...) {
  p <- system.file("corpus", ..., package = "hvtiRtemplates")
  if (!nzchar(p)) {
    stop("not found in the corpus: ", file.path(...), call. = FALSE)
  }
  p
}
