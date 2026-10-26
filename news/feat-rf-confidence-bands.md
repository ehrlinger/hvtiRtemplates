* `rfs-explain`, `rfc-explain` and `rfr-explain` can draw 95% subsampling intervals on permutation importance
  and pointwise bands on the partial-dependence plots. Set `BANDS_B` to the number of subsample forests (0, the
  default, draws none); `SUBRATIO`, `BAND_STYLE` (`"ribbon"` or `"bars"`) and `BAND_AT` tune them. The bands are
  cached per variable and run for hours at study size, so submit the job with `submit_job()`.
* `guard_long_fit()` takes several cache names and refuses while any of them is missing.
