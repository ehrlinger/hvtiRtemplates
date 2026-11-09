* `dc-tables` gains three study choices. `PROP_CI` (`"none"`, `"wilson"` or `"exact"`) and `PROP_CI_LEVEL` (default `0.95`)
  put a confidence interval for the percentage beside every binary and categorical cell, through `hvtiRtables`
  1.0.13's `prop_ci`. `WORD_STYLE` (`"manuscript"` or `"report"`) chooses the Word table's style; the manuscript style
  does not show the intervals yet, so a job asking for them with `WORD_STYLE <- "manuscript"` stops before the table is
  built and says to set `"report"`. The template now needs `hvtiRtables` >= 1.0.13.
