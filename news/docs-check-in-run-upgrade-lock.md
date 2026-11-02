* `?render_job` no longer says every stale render lock is taken over: one left on another node reads as still running and
  must be deleted by hand. `work-a-job` gains sections on `run_job()` and `upgrade_job()` and an entry for the render-lock
  error, which a renamed copy of a job does not get past. `?run_job`, `?job_status`, `?upgrade_job` and `dc-eda`'s
  `VARIABLE_SET` comment say more about what each does.
