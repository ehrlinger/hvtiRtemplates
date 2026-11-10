* hs-concordance tests observed against expected deaths: for each model and each group received, the deaths
  observed to `TAU` against the sum of each patient's cumulative hazard from the model at their own follow-up,
  the one-sample log-rank, with O/E, its exact Poisson interval at `TEST_LEVEL` (95% by default, switchable)
  and a p-value. The expected count is treated as fixed; adding the model's own uncertainty waits on
  TemporalHazard#731. A cell whose patients are the model's fitted patients is marked `in-sample` and carries
  no test, since the fit makes O/E 1 there. `TAU` defaults to the shortest of the models' follow-up.
* hs-concordance accepts `GROUP <- NULL` when `MODELS` has one entry, so a cohort scored through one model
  fitted on another cohort is an hs-concordance job.
* hs-concordance draws each group's average expected curve against its Kaplan-Meier estimate, with the test in
  each panel's title, and a spaghetti figure of the patients' curves. The band around the average is chosen by
  `BAND`, with no default: `"limits_mean"`, the average of the patients' 68% limits, labelled an upper bound
  on the interval of the mean, or `"spread"`, the 15th to 85th percentiles of the predictions, labelled not a
  confidence interval. The interval of the mean curve itself waits on TemporalHazard#731.
* hs-setup and hs-concordance stop if the averaged curve they draw is not the mean of the patients'
  predictions their table reports, and their prediction tables add the mean and the 15th and 85th
  percentiles beside the median.
* hs-setup's saved `hs.rds` renames `obs_vs_exp` to `model_vs_population`, its columns `observed` and
  `expected` to `model` and `population`, and the per-patient life table `expected` to `population`, as the
  figure already named the two curves. Neither column was observed. A study job reading the old names from
  `hs.rds` reads `NULL` until it is updated.
* vt-explain points to the hs-concordance test and band for observed-against-expected work on arm forests.
