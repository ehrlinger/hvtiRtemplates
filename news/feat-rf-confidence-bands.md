* `rfs-explain`, `rfc-explain` and `rfr-explain` can draw 95% subsampling intervals on VIMP (randomForestSRC's
  anti-split importance) and pointwise bands on the partial-dependence plots. Set `BANDS_B` to the number of subsample
  forests (0, the default, draws none); `SUBRATIO`, `BAND_STYLE` (`"ribbon"` or `"bars"`) and `BAND_AT` tune them. The
  bands are cached per variable and run for hours at study size, so submit the job with `submit_job()`. The importance
  interval is the figure's own estimate plus and minus 1.96 jackknife standard errors taken about that estimate.
* The importance figure and table captions in `rfs-explain`, `rfc-explain` and `rfr-explain` now call the quantity VIMP
  (anti-split importance), which is what `vimp()` computes here, and not permutation importance.
* `guard_long_fit()` takes several cache names and refuses while any of them is missing.
