* Template comments and narration added since the sweep: `sid-stability` describes the refit seeds as the code
  computes them, `SEED_OFFSET + (r - 1) * M + 1`, and says a seed clash stops the render; `vt-fit` says what
  Gower distance and an isolation forest each fold into one number; `hs-concordance` and `hs-setup` say that a
  few high-risk patients pull the mean predicted survival below the median, rather than above the 85th
  percentile; `hs-concordance` says the 68% limits belong to `BAND <- "limits_mean"` only, and no longer calls
  its event and follow-up columns unused; `hs-setup`'s `SCALE` warning compares against model predictions,
  not observed values.
* The template archive `upgrade_job()` reads now holds `sid-stability`, so a job copied from its earlier text drops
  the old `REPEATS` and `SEED_OFFSET` comments on upgrade instead of keeping them as the study's own.
