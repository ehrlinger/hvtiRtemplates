* `dc-tables` draws the `%summarytable` table the team asked for on
  2026-10-16: one table with continuous and categorical variables together,
  and, with `STDDIFF <- TRUE`, the standardized difference `%stddiff` printed
  beside the p-value. The difference comes from `hvtiRpropensity::ps_stddiff()`
  through `hvtiRtables::hv_tbl_compare()`. `MEAN_SD` shows named continuous
  variables as mean ± SD and the rest as `CONTINUOUS_STAT`, with every one
  still tested by Wilcoxon. `ORDINAL` names ordered categorical variables,
  which `%stddiff` ranks rather than treats as nominal. `GROUP_1` names the
  treated group when `BY` is not 0/1. `SHOW_VARIABLE <- FALSE` drops the new
  Variable column for a manuscript. The report now shows the table exactly as
  it is saved to Word, not gtsummary's working copy. Needs hvtiRtables 1.0.6.
