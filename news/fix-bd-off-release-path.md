* `bd` no longer publishes catalog releases, which hvtiRutilities 1.5.3 retired.
  It writes the study's working file, `datasets/<DATASET_ID>.rds`, with a schema 1
  build record beside it, `<DATASET_ID>.build.yml`, and with `REGISTER <- TRUE`
  registers that file as a dated version with `register_data()` the first time
  and `update_manifest()` after that. The version's manifest provenance then reads
  `origin: bd`. The study choice `PUBLISH` is now `REGISTER`, and the `write-draft`
  and `publish` chunks are now `write-built` and `register`. The build record
  keeps a hash of the cohort rules, never their text, so an `EXCLUDE` rule that
  names a patient stays in the job file. A study registered under a file this job
  does not write still stops, now in `register`. A `DATASET_ID` ending in a date,
  or naming a file `dataset-catalog.yml` lists as a published release, stops before
  anything is written, so a working file never overwrites a release. `bd` needs hvtiRutilities 1.5.3
  and checks for it in its setup chunk. Its tests no longer call
  `publish_dataset()`, `register_data(release_id =)` or `adopt_data_update()`, so
  they run with no deprecation warning.
