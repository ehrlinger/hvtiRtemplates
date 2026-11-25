- `vp-fit` and `vp-dependence` report each stability refit, and `sid-fit` each
  imputation and SID forest, to `job_status()` and the render log as done of
  total with an estimate of the time left, as `sid-stability`'s refits do. Only
  steps that fit are counted, not ones read from the cache (#631). The cached
  code is unchanged, so fits cached by earlier copies of these jobs still load,
  and studies' existing copies run as before.
