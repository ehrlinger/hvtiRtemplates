* `nb-boostmtree`'s variable importance is seeded, so a re-render reproduces
  it. `vimp.boostmtree()` permutes each predictor at random and the template
  called it unseeded, so the importance figure, and the six most important
  variables the partial effects are drawn for, could change from one render
  of the same fit to the next. It now runs under `SEED` through
  `cache_fit()`, as the fit does. The seed-hygiene test now lists
  `vimp.boostmtree()` among the calls that draw from R's generator, which is
  how it had been missed.
* `nb-boostmtree` caches its partial effects beside the fit, as
  `nb-boostmtree-partial.rds`. `partial.plot()` makes one prediction over
  every patient for each of 25 grid values per continuous covariate, and was
  the slowest step after the fit; it re-ran on every render, even one that
  changed only prose. A changed `EFFECT_VARIABLES` or a refit stops the render
  until `REFIT = TRUE`, as a changed fit setting does. The importances are
  cached too, as `nb-boostmtree-vimp.rds`.
