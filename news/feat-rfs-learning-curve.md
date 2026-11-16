* `rfs-fit` gains a learning curve under "Does the forest work?": it refits
  the forest on subsamples of the cohort and reports, against the number of
  deaths, the out-of-bag error and whether the top variables by importance
  agree between refits (`ggRandomForests::learning_subsample()` and
  `gg_learning()`). The error usually settles long before the ranking does,
  so the curve answers what `MIN_EVENTS_PER_FEATURE` only guesses: whether
  this cohort is large enough for the importance and dependence results
  `rfs-explain` reports. The refits use their own 250-tree forest, are
  cached, and run under `guard_long_fit()`. New study choices:
  `LEARNING_FRACTIONS`, `LEARNING_B`, `LEARNING_TOP_K` and `LEARNING_NTREE`.
  The top set compared is at most one fewer than the number of predictors,
  since a set holding all of them agrees perfectly however the ranking moves.
  Needs a ggRandomForests that exports both functions.
