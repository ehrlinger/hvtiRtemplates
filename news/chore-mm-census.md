* New template `mm`: a linear mixed model of a repeated continuous response, fitted
  with `nlme`. `STRUCTURE` chooses the within-patient correlation, as PROC MIXED's
  REPEATED and RANDOM statements did (`"cs"`, the corpus default, `"ar1"`, `"un"`,
  `"random"`, and the two combined forms), and the job saves the population-average
  course over time with 95% limits, back-transformed from the log scale as geometric means, for a plot.
  It does not yet pool multiple imputations, and stops if `IMPUTATION` is set.
