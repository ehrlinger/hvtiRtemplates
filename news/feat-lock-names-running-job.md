- A render held off by another render in the same study now names the jobs
  that render is working on and the user who started it, as in
  `(process 101, rendering distributions/ac.dead.hz.qmd for lauren)`, where it
  named the process alone. It adds how to check on or stop that job with
  `job_status()` and `cancel_job()` when it was started with `run_job()`. The
  note is kept in the lock beside its owner record and is read only while it
  belongs to the render holding the lock.
