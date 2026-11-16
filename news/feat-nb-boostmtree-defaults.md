- `nb-boostmtree` now defaults to `M <- 500` (was 1000). A study of 1,391 patients at `NU = 0.05` that fitted
  1000 chose Best M = 751, but its cross-validated error at 500 was within 0.3% of that best, so 500 does the
  job at half the run time. A job already in a study keeps its own `M`.
- `nb-boostmtree` writes out its tree and spline settings as study choices, `K <- 5` terminal nodes and
  `N_KNOTS <- 10`, passed to `boostmtree()` as `k` and `n.knots`. Both are boostmtree's own defaults, and the
  choice comments now say how to set them, and `M`, `NU` and `MTRY`, from what the studies learned: fix `NU`
  and let cross-validation choose Best M; treat `M` as a ceiling, because boostmtree's default of 200 is too
  low for clinical longitudinal data; and keep `N_KNOTS` well below the number of distinct visit times. A fit whose
  `N_KNOTS` is not below them stops before it starts. **A job upgraded with `upgrade_job()` stops at its cached
  fit until `REFIT <- TRUE`, even at these default values, because the fit's code now names `k` and `n.knots`.**
- The `nb-boostmtree` report now warns, in the report itself, when Best M lands in the last tenth of `M` and the
  cross-validated error fell by more than 0.1% over that tenth (still falling by enough to matter; Best M near
  `M` on a flat curve passes) and when the smoothing parameter lambda reached boostmtree's `lambda.max` at Best M
  (a flat trajectory or too many knots). The fit table records `K`, the knots and `mtry`, and the saved fit and
  provenance record `k`, `n_knots` and `mtry` (`"all"` when `MTRY` is `NULL`).
- `nb-boostmtree` has a new `SENSITIVITY` choice, off by default. Set to `TRUE`, it refits over `NU` in
  {0.01, 0.05} and `K` in {3, 5, 8}, with `M` scaled to hold `M * NU` fixed, caches each fit beside the job's,
  and reports Best M and the cross-validated error of each, with the largest change from the job's own fit.
  It is five more fits, two of them five times as long.
- The `nb-boostmtree` choice comments say what to do about a skewed continuous response: `"continuous"` is
  squared-error boosting, and a fit on log(y) gives geometric means on the raw scale (medians only if the
  log-scale error is symmetric); arithmetic means need a retransformation, whose smearing factor usually depends on
  time, that the template does not do. They cite Pande et al. (2017), *Machine Learning* 106:277-305.
