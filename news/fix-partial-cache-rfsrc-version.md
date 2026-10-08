* `rfc-explain`, `rfs-explain` and `rfr-explain` key their partial-dependence
  cache on randomForestSRC, which computes it. The cache was keyed on
  ggRandomForests alone, so after a randomForestSRC upgrade it stayed valid and
  `REFIT = TRUE` kept the old result while the variable importance beside it was
  recomputed. The `gg_partial_rfsrc()` call now passes
  `packages = "randomForestSRC"` to `cache_fit()`; the VarPro partial is
  unchanged, since its varpro fit already carries varPro's version. Each
  existing `rf?-partial` cache goes stale exactly once, reporting
  `packages$randomForestSRC (absent) -> x.y.z`, and needs one render with
  `REFIT = TRUE`. Requires hvtiRutilities 1.5.0 or newer, up from 1.4.5.
