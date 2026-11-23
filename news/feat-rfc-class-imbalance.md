* `rfc-fit` guards against class imbalance. When the larger of two classes outnumbers the smaller by
  `IMBALANCE_RATIO` (new `EDIT:`, default 3, a start rather than evidence) or more, the forest is grown as
  randomForestSRC's quantile classifier (`rfq = TRUE`, `splitrule = "auc"`) and scored by normalized Brier rather
  than misclassification, which rewards predicting the larger class every time. A callout says so, and the error
  captions name the score. The learning-curve refits and `rfc-explain`'s importance and intervals read the setting
  off the forest, so they follow without changes. More than two classes past the ratio get a warning callout, since
  RFQ is two-class. A balanced outcome grows the same forest under the same cache key as before.
