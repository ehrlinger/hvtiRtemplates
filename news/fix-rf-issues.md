* `rfs-fit`, `rfc-fit` and `rfr-fit` now draw the out-of-bag error by number of
  trees as a curve. With importance off, randomForestSRC records the error only
  at the last tree, so the figure was one point and could not show whether
  `NTREE` was large enough. The fit now passes `block.size = 1`, which records
  the error after every tree and leaves importance off (#165).

* `rfs-explain`, `rfc-explain` and `rfr-explain` give VarPro the forest's
  imputed data when the fit used `na.impute`, so VarPro and the forest describe
  the same patients. Before, varPro dropped every patient with a missing value
  and its importance and partials described fewer patients than the forest, with
  a notice in the rendered report. The report now says that VarPro was given the
  imputed data. A saved `-varpro` result from an earlier render describes the
  old, smaller cohort, so `cache_fit()` stops on it and names the change: set
  `REFIT <- TRUE` once to recompute it (#166).

* The marginal plot of `rfs-explain`, `rfc-explain` and `rfr-explain` draws no
  loess smooth through a predictor with fewer than six distinct values, which
  stops the dozens of loess warnings a four-valued predictor raised in the
  rendered report. `rfc-explain` also draws its points for a 0/1 outcome:
  ggRandomForests read the outcome's levels "0" and "1" as missing, so every
  point was removed and only the smooths were left (#167).
