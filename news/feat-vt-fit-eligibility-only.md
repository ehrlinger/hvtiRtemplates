- `vt-fit` runs eligibility alone when `TIME` and `STATUS` are both `NULL`,
  for a cohort that has no outcome yet or whose outcomes someone else will
  analyze. It reads no outcome and grows no forest. The report keeps the cohort,
  predictor and eligibility sections, notes each skipped section, and saves a
  `vt.rds` that carries the eligibility flags with its outcome parts empty.
  `vt-explain` refuses that fit and says why. Eligibility never read the outcome,
  so the flags are the ones a full fit of the same cohort gives. An arm then
  needs two patients rather than an event.
- `vt-fit`'s `GOWER_REFERENCE` sets the Gower eligibility line at a quantile of
  the arm's own nearest-neighbor gaps, such as `0.99`, rather than the largest
  gap. One isolated patient in an arm sets its largest gap and so loosens the
  line for everyone judged against it; a quantile keeps that one gap from
  deciding. `"max"`, the default, is the rule as it was. A SID distance keeps
  the largest gap, and `vt.rds` records the rule used.
