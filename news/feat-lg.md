* New template `lg`, logit calibration: `add_job("lg", subject, type)`, usually
  with the outcome as the subject, as in `lg.dead.calibration`. It decides which
  scale a covariate should enter a model on, before it goes into `PREDICTORS` in
  an `lm` job. Each covariate in `VARIABLES`, continuous or ordinal, is ranked
  into groups as `PROC RANK GROUPS=` does, or takes each level as a group, as
  `%logitgr` did. The job takes each group's event rate on the logit, or, for
  time-related death, the log of the constant hazard, and plots it against the
  covariate on six scales (raw, log, inverse, inverse squared, squared and
  exponential), each panel with the R-squared of a straight line weighted by
  group size. `INTERVAL = c(start, end)` takes one phase of follow-up as the SAS
  early, constant and late jobs did: patients who ended before `start` are left
  out, and the rest are censored at `end`, so an event after `end` no longer
  counts. Under the hazard link the time at risk is the time inside the window,
  `pmin(TIME, end) - start`; the SAS template summed it from 0, which is the one
  deliberate difference. Under the logit link the same patients are kept and an
  event counts only inside the window. The job reports how many patients it left
  out, how many it censored and how many events fell after `end`. The scale
  chosen for each covariate is saved as `lg-scales.rds` with the term to write
  for it, such as `log(age)` or `I(50 / weight)`, and the job prints the
  `PREDICTORS` line to copy into an `lm` job. A blank `chosen` warns in a draft
  and stops a final render, as an open `EDIT:` marker does, and so does a chosen
  scale that is not a number for some patient, such as the log of a covariate
  that is 0 for a few, though every group mean is fine; the message counts those
  patients and shows no value. A group whose link value cannot be computed keeps
  its row, blank, and is named under its table; a scale that cannot be computed
  for a covariate is drawn as an empty panel. A patient with no event value is
  ranked but counts in no group's patients, events or follow-up. A covariate
  whose median rounds to 0, such as a 0/1 indicator, has no default `constant`:
  the inverse, inverse squared, squared and exponential scales are not computable
  for it until `constant` is set, and raw and log remain. Two checks keep a
  figure from resting on groups too small to read: an ordinal covariate with more
  than 20 levels stops the job, and so does any group with fewer than 5 patients,
  naming the covariate and never a value. The catalog name of `lg` becomes
  "Logit calibration": the 12 `lg.trends` jobs go to `dc-trends`.
