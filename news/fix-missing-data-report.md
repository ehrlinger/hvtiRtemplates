* The `lm-*` and `rf*-fit` templates now show a table of missing values right
  after the data are read: each model variable that has any, with its count, and
  the cohort the fit will use ("725 of 800 rows analysed; 75 dropped", or under
  `na.impute`, how many rows are imputed). Until now the drop showed only as a
  smaller sample size in the fit's own output. `hm` stops at that point instead,
  naming each column and its count, where `hazard()` had failed with "Predictor
  rows must match the length of 'time'" (#174).
