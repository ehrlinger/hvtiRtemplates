* `Remotes:` installs `boostmtree` 2.0.11 from the CCF fork (`v2.0.11-ccf`),
  matching the pin `ggBoostedTrees` already carries, and `nb-boostmtree`'s
  setup chunk names that tag in its install line. 2.0.11 makes
  `nb-boostmtree`'s partial effects faster: `partial.plot()` predicts only at
  the time points it plots, and a cross-validated prediction walks each step's
  out-of-bag list once. 2.0.9 holds less memory per boosting step. The floor
  stays at 2.0.8, but that does not keep a study on 2.0.8: `ggBoostedTrees`
  imports `boostmtree` and pins 2.0.11 itself, so updating the package family
  (or reinstalling `ggBoostedTrees`) installs 2.0.11. That makes an existing
  job's cached fit stale, because `cache_fit()` records package versions, and
  the next render stops until `REFIT <- TRUE`. Before updating a study with
  cached `nb-boostmtree` fits, check that hours of refitting are acceptable.
