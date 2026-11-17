* `build_cohort()` excludes a patient whose cohort-list `exclude` cell is padded
  with spaces (`" 1"`). The value was trimmed when checked and read untrimmed
  when applied, so the patient stayed in the cohort while the attrition table
  counted the rule.
* A 64-bit integer (`integer64`) patient identifier, as `arrow` reads one from
  Parquet, is written and digested by its value. Every such ID was written as
  `"0"`, so `read_job_data()`'s refusal of a WHERE condition that names an
  identifier's value missed an MRN-sized literal, and every patient in a
  hand-off bundle shared one digest. An upstream output saved before this
  change recorded that shared digest, so a downstream job reads it as changed
  data until the upstream job is rendered again.
* Two renders that both find a dead render's lock can no longer both take it.
  The second now checks that the lock it moved aside is the dead one's; if the
  first render took it over in the meantime, the lock goes back and the second
  render stops, as it would against any live render. Before, the second render
  rolled back the first one's live provenance files. The lock is put back by
  claiming it afresh, never by renaming over the path, so a lock a third render
  created in the meantime is never replaced.
* `add_job()` refuses a dangling symbolic link where the job would go, or at
  the job's or runner's name before 2026-10 or before a template rename, as
  `upgrade_job()` already did, rather than writing the job wherever the link
  points.
* `submit_job()` writes its run's process marker into the `submitted` record,
  and `job_status()` looks for a process carrying it before reading a run that
  has not started after two minutes as vanished. A slow `.Rprofile` or `renv`
  start on a loaded share therefore reads as submitted rather than dead, and
  cannot be submitted a second time. A run recorded on another host is still
  read by the two-minute window, since its processes cannot be seen from here.
  `cancel_job()` stops such a starting run through its marker and records it
  cancelled, so a runner that hangs before it records itself can still be
  stopped. When this host's processes cannot be listed at all, as in a sandbox,
  the run stays submitted and `job_status()` says why: a second copy is still
  refused, and `cancel_job()` refuses too, signalling nothing.
* `ar_value()` stops in a final render (`render_job(final = TRUE)`) when the job
  it quotes has been edited since its last render, and still warns in a draft.
  A final report quoting a number its job no longer produces is the failure the
  `ar` report exists to prevent.
