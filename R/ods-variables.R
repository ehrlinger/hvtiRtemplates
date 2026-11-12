# The house descriptive variable list, grouped by section, as the templates'
# jobs read it. It carries every variable the SAS ODS table template
# (descriptive/dc.tables.ods.sas, 2023) reports, under that template's section
# banners, plus the house summary-table categories where they differ. The
# names are CORR database columns, lowercase as read_built() returns them.
# dc-eda draws these by default; dc-tables carries the same list as its
# commented GROUPS example, and a test holds the two together.
# present: column names to keep, or NULL for the whole list. A section left
# with no column is dropped.
.ods_groups <- function(present = NULL) {
  path <- system.file("extdata", "ods-variables.csv", package = "hvtiRtemplates")
  rows <- utils::read.csv(path, stringsAsFactors = FALSE)
  if (!is.null(present)) rows <- rows[rows$variable %in% tolower(present), , drop = FALSE]
  sections <- unique(rows$section)
  stats::setNames(lapply(sections, function(s) rows$variable[rows$section == s]), sections)
}

# The variable sets dc-eda's VARIABLE_SET names, each a list of sections, each
# section the columns it draws in order. First the house sets: "ods", the list
# above, then the modules the SAS ODS template carries commented out
# (extdata/variable-sets.csv; its Surgeon block is left out, as columns named
# for people). Then a study's own, from variable_sets: in _study.yml, either a
# plain list of columns, one section named for the set, or sections each
# listing columns. Names are matched in lowercase, as read_built() returns them.
# cfg: the study's study_config(), or NULL for the house sets alone.
.variable_sets <- function(cfg = NULL) {
  path <- system.file("extdata", "variable-sets.csv", package = "hvtiRtemplates")
  rows <- utils::read.csv(path, stringsAsFactors = FALSE)
  by_section <- function(r) {
    sections <- unique(r$section)
    stats::setNames(lapply(sections, function(s) r$variable[r$section == s]), sections)
  }
  modules <- unique(rows$set)
  house <- c(list(ods = .ods_groups()),
             stats::setNames(lapply(modules, function(m) by_section(rows[rows$set == m, , drop = FALSE])), modules))
  study <- cfg$variable_sets
  if (is.null(study)) return(house)
  where <- "_study.yml's variable_sets:"
  if (!is.list(study) || is.null(names(study)) || any(!nzchar(names(study)))) {
    stop(where, " must map each set's name to its columns.", call. = FALSE)
  }
  columns <- function(x) is.character(x) && length(x) && !anyNA(x) && all(nzchar(x))
  for (name in names(study)) {
    if (!grepl("^[A-Za-z0-9_]+$", name)) {
      stop(where, " ", name, " is not a set name. Use letters, digits and _.", call. = FALSE)
    }
    if (name %in% c(names(house), "all")) {
      stop(where, " ", name, " is a house variable set", if (name == "all") " name, meaning every column", ". ",
           "Give the study's set a name of its own.", call. = FALSE)
    }
    set <- study[[name]]
    sectioned <- is.list(set) && length(set) && !is.null(names(set)) && all(nzchar(names(set))) &&
      all(vapply(set, columns, logical(1L)))
    if (!sectioned && !columns(set)) {
      stop(where, " ", name, " names no column. Give a list of columns, or sections each listing columns.",
           call. = FALSE)
    }
    study[[name]] <- if (sectioned) lapply(set, tolower) else stats::setNames(list(tolower(set)), name)
  }
  c(house, study)
}
