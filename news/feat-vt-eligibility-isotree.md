* vt-fit judges eligibility by an isolation forest as well: `"isolation"` is a third `ELIGIBILITY` method,
  beside `"gower"` and `"sid"`. The forest is grown on each arm with the isotree package. The arm's own
  patients are scored cross-fitted over five folds, and a judged patient is scored by the mean of the same
  five forests, so neither side is scored by a forest that saw it. A patient scoring above
  `ISOLATION_CUTOFF` (default 0.99), a quantile of the arm's own scores, is flagged, and a new table counts
  the flags at the 95th and 99.5th percentiles beside it. `COMBINE` already decides how the methods join:
  `"any"` keeps a patient only when every method keeps them, the "both" rule; to decide by one method,
  name only that one. isotree joins Suggests.
* vt-fit counts eligible patients with a value outside what the arm they were judged against shows, a number
  outside its observed range or a level none of its patients has. Gower and the isolation forest average
  over every variable, so one extreme value can leave a patient eligible. The patients themselves are saved
  in `vt.rds`, under `eligibility$outside_range`.
* vt-fit's optional `AGE_CAP`, such as `c(age = 90)`, caps an age column in every arm when one arm's ages were
  capped for de-identification, so an uncapped 95 does not look out of range. It is `NULL` by default, and
  vt-explain applies the same cap to the data it re-reads.
* vt-explain's distance figure says that an isolation-forest row is a score, and its line the cutoff.
