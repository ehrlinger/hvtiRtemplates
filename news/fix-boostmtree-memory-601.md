* The memory check before a continuous `nb-boostmtree_fit` (and `nb-boostmtree`) fit is recalibrated on
  boostmtree 2.0.13 (#601). It had asked for 2 to 12 times what the fit uses, enough to refuse a study that a
  Default session holds. It now grows with `M`, as the fit's memory does, and sits 1.1 to 2 times above every
  peak measured on simulated data and on a 1,391-patient study at `M = 500`. A boostmtree older than 2.0.13,
  which the deprecated `nb-boostmtree` template and jobs already in studies may still run, keeps the earlier
  estimate, since 2.0.8 was measured to need far more. The run-time and memory notes beside `CORES` in
  `nb-boostmtree_fit` are measured at `M = 500` rather than extrapolated. The ordinal estimate is unchanged.
