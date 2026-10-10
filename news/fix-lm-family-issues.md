* Every `lm` template now checks the columns its study choices name before it
  fits, and a missing one stops with the setting to change, such as "OUTCOME
  names a column this dataset does not have: severity. Change OUTCOME in
  edit-study-choices." `OUTCOME` or `TREATMENT` and `PREDICTORS` are checked,
  including a variable used inside a term such as `I(age^2)`; `ID` and `KEY`
  were already checked by `read_job_data()`. Before, only `lm-binary` checked,
  and elsewhere a wrong name failed inside hvtiRpropensity with an error naming
  one of its functions (#179).

* `lm-checkpred` can read a model saved in another set. A new optional
  `MODEL_SET` names the training job's set, such as `"stroke-model"`, so a
  validation job no longer has to share the subject and type of its `lm-binary`
  job. `MODEL_FILE` must be a file name and `MODEL_SET` a set name, so neither
  can reach outside the study's estimates. The template now says how to register
  a validation cohort as a dataset of its own and read it with `DATASET`; it is
  checked against the training patients like any other cohort (#180).

* `lm-propensity_ordinal` and `lm-propensity_nominal` print a balance table, the
  standardized mean difference of each covariate between each treatment level
  and the reference level, in the place `lm-propensity_binary` prints its own.
  `lm-propensity_ordinal` also prints the cumulative direction of its
  proportional-odds model, as `lm-ordinal` does, which a reader needs to
  interpret the signs of its coefficients (#191).

* hvtiRpropensity 0.1.10 or later is now required, up from 0.1.7, by
  `DESCRIPTION` and by the version check of every `lm` template and of
  `dc-stddiff`. 0.1.10 returns the multi-level balance tables, labels the count
  family's exponentiated coefficients `rate_ratio` rather than `odds_ratio`,
  and names the declared treatment levels in `lm-propensity_binary`'s group
  counts rather than "control" and "treated" (#206).
