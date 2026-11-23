* A job's `DATASET` may now name a file in the study's datasets folder, such as
  `DATASET <- "match_set.rds"`, to run on data that is not registered: `.rds`, `.rda`, `.RData`, `.parquet`,
  `.csv`, `.sas7bdat`, `.xlsx` or `.xls`, whatever `read_clinical_data()` reads.
  `read_job_data()` reads it as a draft: the render warns, the data table and
  "About this run" say the data are unregistered and give the
  `hvtiRutilities::register_data()` call that fixes it, and a final render
  downstream refuses a hand-off saved from those rows. Every template's
  `DATASET` comment names the option.
