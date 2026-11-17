* `rfc-fit` and `rfr-fit` gain the learning curve `rfs-fit` has, under "Is the
  cohort large enough?": out-of-bag error and the agreement of the top
  variables by importance across refits on subsamples, against the cases in
  the smallest class (`rfc`) or the patients (`rfr`). Same study choices
  (`LEARNING_FRACTIONS`, `LEARNING_B`, `LEARNING_TOP_K`, `LEARNING_NTREE`),
  cached and run under `guard_long_fit()`. New figures
  `rfc-fit-learning-stability`, `rfc-fit-learning-error`,
  `rfr-fit-learning-stability` and `rfr-fit-learning-error`. `rfs-fit`'s
  captions now name the square that marks the whole-cohort bootstrap.
* The learning curve in `rfs-fit`, `rfc-fit` and `rfr-fit` leaves out the
  whole-cohort bootstrap when `NA_ACTION` is `"na.impute"` and the data have
  missing values, and says so. randomForestSRC 3.10.0 crashes R when it
  double-bootstraps a forest that imputed missing values; the plain
  subsamples are unaffected. Before this, such an `rfs-fit` render crashed.
