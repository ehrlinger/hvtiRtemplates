* `migrate_job()` on a `%desc_tab` job now writes the table that job printed:
  `COMPARE <- "pvalue"` when `by=` named a group, `CONTINUOUS_STAT <- "both"`
  for mean ± SD beside the percentiles, and `PERCENTILES` from `perctile=` when
  every call agrees on a low/median/high triple. Until now it wrote "none",
  "median" and 15, 85 whatever the SAS said. `exposure=0` (the group as an
  outcome, incidence by row) is listed as unresolved, since `dc-tables` does not
  draw it. The report lists where the R table differs from `%desc_tab` on
  purpose: Fisher's exact test for sparse categorical rows, the Wilcoxon test
  (exact in small groups) where `%desc_tab` reported Kruskal-Wallis for two
  groups, and percentiles: `%desc_tab` computed them with
  `PCTLDEF=4`, where the R table uses SAS's default definition, so the low and
  high percentiles can differ in small groups.
