* New template `lg`, logit calibration: `add_job("lg", subject, type)`, usually
  with the outcome as the subject, as in `lg.dead.calibration`. It decides which
  scale a covariate should enter a model on, before it goes into `PREDICTORS` in
  an `lm` job. Each covariate in `VARIABLES`, continuous or ordinal, is ranked
  into groups as `PROC RANK GROUPS=` does, or takes each level as a group, as
  `%logitgr` did. The job takes each group's event rate on the logit, or, for
  time-related death, the log of the constant hazard, and plots it against the
  covariate on six scales (raw, log, inverse, inverse squared, squared and
  exponential), each panel with the R-squared of a straight line weighted by
  group size. `INTERVAL` keeps the patients whose follow-up is in a window, the
  SAS early, constant and late phases. The scale chosen for each covariate is
  saved as `lg-scales.rds` with the term to write for it, such as `log(age)` or
  `I(50 / weight)`, and the job prints the `PREDICTORS` line to copy into an
  `lm` job. A blank `chosen` warns in a draft and stops a final render, as an
  open `EDIT:` marker does. A group whose link value cannot be computed keeps
  its row, blank, and is named under its table; a scale that cannot be
  computed for a covariate is drawn as an empty panel. The catalog name of `lg`
  becomes "Logit calibration": the 12 `lg.trends` jobs go to `dc-trends`.
