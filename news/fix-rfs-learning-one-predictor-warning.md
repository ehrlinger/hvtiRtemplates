* `rfs-fit` with a single predictor no longer passes on `gg_learning()`'s
  warning that `top_k` covers every predictor. The job already says the
  agreement measures are not informative with one predictor, and the
  warning's advice to lower `top_k` cannot apply there.
