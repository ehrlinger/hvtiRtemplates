* `nb-boostmtree` reports each boosting iteration and each partial-effect prediction to
  `<job>.run.progress` and the render log, so `job_status()` can say how far a fit has got
  and how long its stage has left. It needs boostmtree 2.0.8. Existing jobs need not
  change: they still report stages. Two things make an existing job's cached fit stale, so
  the next render stops until `REFIT`, and each is worth doing only when hours of refitting
  are acceptable: adding these lines to a job, which `upgrade_job()` does, and installing
  boostmtree 2.0.8, which the new floor requires, because `cache_fit()` records package
  versions.
