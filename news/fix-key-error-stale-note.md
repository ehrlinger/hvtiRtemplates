* `read_job_data()`'s KEY errors now say when the job read an older registered
  version because the source has been rebuilt since. A rebuild that removed a
  repeat is not read until it is registered, and the note saying so sat in the
  data table, which the error stops the job before. The note now ends the
  error, naming `update_manifest()`. The same holds for a joined dataset's key.
