* The `lm` templates read stacked multiple imputations again. Since 1.3.0 their data table stopped with "This job models
  one row per patient" on any `IMPUTATION`, because `read_job_data()` counted a patient once per row rather than once per
  imputation. It takes a new `imputation` argument, which each `lm` template passes as `IMPUTATION`, and counts a patient
  within each imputation: a patient once in each passes, a patient twice in one imputation, or in a long dataset with no
  imputation, still stops. The data table now says how many imputations the rows hold, for example
  "240 rows on 120 patients, in 2 imputations".
