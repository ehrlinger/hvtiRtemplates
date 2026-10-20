* `nb-boostmtree` gains a study choice, `MTRY`: the number of predictors tried
  at each split of each tree, passed to `boostmtree(mtry = )`. `NULL`, the
  default, tries every predictor, as the template has always done, so existing
  fits are unchanged. Set it to reproduce a study fitted with a smaller
  `mtry`. It is part of the cache key, because a different `MTRY` is a
  different fit. A job upgraded to this version finds its cached fit stale
  once, because the fit call changed.
