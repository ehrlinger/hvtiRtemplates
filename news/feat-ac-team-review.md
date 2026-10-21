* The `ac` template takes the biostats team's review of 2026-10-21. It now reports the number at risk beside
  survival at every horizon, overall and by stratum; prints the whole life table, with `EVENT_ONLY <- FALSE`
  adding a row for each censored patient as SAS `PEVENT=0` does; compares strata with the log-rank, Wilcoxon and
  `-2Log(LR)` tests; summarizes follow-up overall and among survivors with SAS's percentile definition; and draws
  its own figures: survival and four views of the cumulative hazard for reading, and a manuscript survival figure
  with the numbers at risk, saved as `ac-survival` (and `ac-survival-<variable>` for each stratification). A
  missing or mean-imputed stratum is now dropped, as `%KAPLAN` drops it, and the dropped patients are listed.
  `EXPECTED` is optional (`NULL` by default), `STRATA` defaults to the whole cohort only, derived strata are an
  optional, commented example, `labs` may be `NULL` to label each horizon by its value, and `TYPE` is explained as
  the chain the set belongs to. The nested-stratification chunk is gone: run a second job with a `WHERE` instead.
* New exported functions `life_table()`, `life_table_at()`, `life_table_tests()` and `life_table_keep()`, the
  R counterpart of `%KAPLAN` that the `ac` job calls, so its helpers are documented in `?life_table` rather than
  written out in every job. The tests reproduce SAS `PROC LIFETEST` on the Gehan leukemia data.
