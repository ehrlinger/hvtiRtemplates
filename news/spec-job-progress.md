* A render records its progress in `<job>.run.progress`: the chunk running, the step within
  it, and how long each finished chunk took. `job_status()` prints it, with an estimate of
  the time left in the chunk, flags a render that has not moved for half an hour, and reads
  a render started without `submit_job()` from that file alone. Long chunks write a line to
  the render log at most every `hvtiRtemplates.progress_every` minutes (default 10).
