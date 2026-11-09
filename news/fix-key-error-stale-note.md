* `read_job_data()`'s KEY errors now say whether the data read were the latest.
  When the source has been rebuilt since it was registered, the job reads the
  older registered version, and a rebuild that removed a repeat is not read
  until it is registered; the note saying so sat in the data table, which the
  error stops the job before. It now ends the error, naming
  `update_manifest()`, and a joined dataset's key errors carry it too. When
  the data read are current, the error says so, and gives the
  `hvtiRutilities::duplicate_keys()` call that lists the repeated rows to
  correct in the build.
