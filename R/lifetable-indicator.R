# hs-setup matches each patient to the US life tables, which split by male and
# by white versus non-white and so take two 0/1 indicators. A study codes sex
# and race its own way, as `female` or a sex factor, a race factor or a 0/1
# `other`, so each indicator is derived from the column's own values: `levels`
# are the values that count as 1. A missing value stays missing. The mapping,
# each value with its count and what it was counted as, is returned as the
# "mapping" attribute so the report can show it: a race level left out of
# OTHER_LEVELS counts as white, and only the table would say so.
.lifetable_indicator <- function(x, levels, col, setting, counted = c("0", "1")) {
  if (anyNA(levels)) stop(setting, " must not include NA.", call. = FALSE)
  # A logical column reads as 0/1, as us_matched() took it before the levels
  # existed, so the default level 1 still means TRUE.
  if (is.logical(x)) x <- as.integer(x)
  values <- as.character(x)
  # A level the column could take but does not is a cohort with no one in that
  # stratum, all female or all white, which us_matched() accepts: 0 or 1 in a
  # 0/1 column, or a level a factor declares. Any other unseen level is a typo,
  # and would set every patient to 0 without a word, so it stops. An empty
  # setting counts no one as 1.
  possible <- c(values, if (is.factor(x)) levels(x),
                if (is.numeric(x) && all(stats::na.omit(x) %in% c(0, 1))) c("0", "1"))
  absent <- setdiff(as.character(levels), possible)
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
