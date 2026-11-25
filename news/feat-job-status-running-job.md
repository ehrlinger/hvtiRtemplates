- A job held off by another render in the same study now says which job that
  render is working on. `run_job()`'s check names the jobs and user a render
  started outside `run_job()` recorded, where it said "its job is not known",
  and `job_status()` on a run that failed on the render lock gives the holder's
  jobs as its reason and `job_status()`/`cancel_job()` for them as the fix,
  where it gave only the exit code.
