* `dc-tables` saves its Word table in hvtiRtables' manuscript style: a full
  grid, a two-row header when the table is grouped, with the grouping spanning its levels, shaded section
  rows that span the table, the notes below it, and a caption above it. Three
  study choices set it: `MANUSCRIPT_LAYOUT` (`"compare"`, one `n` column beside
  the groups, or `"describe"`, a count beside each group), `MANUSCRIPT_CAPTION`
  and `MANUSCRIPT_FILL`. The report keeps the report style, with the Variable
  column, and shows the Word table beneath it. `SHOW_VARIABLE` now applies to
  the report only. `migrate_job()` writes `MANUSCRIPT_LAYOUT <- "describe"` for
  a `%desc_tab` job that printed mean ± SD beside the percentiles, which the
  compare layout cannot draw. Needs hvtiRtables 1.0.8. A job scaffolded before
  this keeps working and keeps its report-style Word table; `upgrade_job()`
  adds the three choices, each with its `EDIT:` marker. An upgraded job with
  `CONTINUOUS_STAT "both"` stops at its Word table until `MANUSCRIPT_LAYOUT` is
  set to `"describe"`. hvtiRtables' error names `layout =`; the study choice that sets it is
  `MANUSCRIPT_LAYOUT`.
