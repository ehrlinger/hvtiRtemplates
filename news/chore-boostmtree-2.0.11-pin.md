* `Remotes:` installs `boostmtree` 2.0.11 from the CCF fork (`v2.0.11-ccf`),
  and `nb-boostmtree`'s setup chunk names that tag in its install line. The
  floor stays at 2.0.8, so a study already on 2.0.8 keeps its cached fits.
  2.0.11 makes `nb-boostmtree`'s partial effects faster: `partial.plot()`
  predicts only at the time points it plots, and a cross-validated prediction
  walks each step's out-of-bag list once. 2.0.9 holds less memory per boosting
  step. Installing it makes an existing job's cached fit stale, because
  `cache_fit()` records package versions, so the next render stops until
  `REFIT <- TRUE`; upgrade when hours of refitting are acceptable.
