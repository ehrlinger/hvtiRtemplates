* `vt-fit` shows the observed outcome before any model: Kaplan-Meier by arm with 70% confidence limits,
  the numbers at risk, and a table of each arm's patients, events and survival at `HORIZON`
  (`vt-fit-km`).
* `vt-fit` checks each arm forest's calibration at `HORIZON`: out-of-bag predicted survival in fifths
  against Kaplan-Meier, with one mean error per arm in percentage points (`vt-fit-calibration`). The
  C-index says whether a forest ranks patients; calibration says whether its survival is the right
  level, which is what an RMST difference compares. The table is saved in `vt.rds` as
  `settings$calibration`.
* `vt-fit` gains the `ORDINAL` study choice: graded predictors coded as numbers are ranked in the Gower
  distance, so a grade of 0 against 3 is farther than 0 against 1. Left empty, every mismatched grade
  counts the same, as before.
* `vt-fit` names why each out-of-distribution patient is out: up to three predictors outside the range
  of the arm they were judged against, or at a level at most two of its patients share. The out-of-
  distribution table shows them, and `vt.rds` carries them as `eligibility$rows$features`.
* `vt-explain` adds three views: each patient's predicted RMST under the arm received against the other
  (`vt-explain-components`); the difference against the distance to the other arm, with its eligibility
  line and a rank correlation per arm (`vt-explain-distance`); and, with `STRATIFY` set, the difference
  by stratum and the mean twin curves per stratum (`vt-explain-stratum`, `vt-explain-stratum-curves`).
