# hs-setup matches each patient to the US life tables, which split by male and
# by white versus non-white and so take two 0/1 indicators. A study codes sex
# and race its own way, as `female` or a sex factor, a race factor or a 0/1
# `other`, so each indicator is derived from the column's own values: `levels`
# are the values that count as 1. A missing value stays missing. A level the
# column never takes stops, because a typo in one would set every patient to 0
# without a word. The mapping, each value with its count and what it was
# counted as, is returned as the "mapping" attribute so the report can show it:
# a race level left out of OTHER_LEVELS counts as white, and only the table
# would say so.
.lifetable_indicator <- function(x, levels, col, setting, counted = c("0", "1")) {
  if (!length(levels) || anyNA(levels)) {
    stop(setting, " must name at least one value of ", col, ", and no NA.", call. = FALSE)
  }
  # A logical column reads as 0/1, as us_matched() took it before the levels
  # existed, so the default level 1 still means TRUE.
  if (is.logical(x)) x <- as.integer(x)
  values <- as.character(x)
  absent <- setdiff(as.character(levels), values)
  if (length(absent)) {
    seen <- sort(unique(stats::na.omit(values)))
    stop(setting, " names ", if (length(absent) == 1L) "a value" else "values", " that ", col, " never takes: ",
         paste(absent, collapse = ", "), ". It takes: ", paste(seen, collapse = ", "), ". Change ", setting,
         " in edit-study-choices.", call. = FALSE)
  }
  out <- ifelse(is.na(values), NA_integer_, as.integer(values %in% as.character(levels)))
  tab <- table(value = values, useNA = "ifany")
  keys <- names(tab)
  attr(out, "mapping") <- data.frame(
    column = col, value = ifelse(is.na(keys), "(missing)", keys), n = as.integer(tab),
    counted_as = ifelse(is.na(keys), "missing", ifelse(keys %in% as.character(levels), counted[[2L]], counted[[1L]])),
    row.names = NULL
  )
  out
}
