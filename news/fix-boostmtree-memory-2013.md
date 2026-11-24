- The memory check before an `nb-boostmtree_fit` fit is recalibrated on
  boostmtree 2.0.13 (#601). Its continuous estimate was set on 2.0.8 and asked
  for 7 to 12 times what a fit uses, so it refused fits that a smaller session
  would hold. It now rests on peaks measured at the template's `M = 500`, on
  simulated data with 4 and 24 predictors and on COMMENCE's own data, and sits
  25% above every one. Because memory grows over the boosting steps, the
  estimate gains a term in `M`. A 1,391-patient fit on 8 cores at `M = 500` now
  asks for 12.5 GiB rather than 37.5, and fits a Default session. The ordinal
  estimate is unchanged: it has not been measured on 2.0.13.
