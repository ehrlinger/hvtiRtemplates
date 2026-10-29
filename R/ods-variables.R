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
