* New `cancel_job()` stops a job `submit_job()` started, on the job's own host:
  SIGTERM, then SIGKILL after a grace period, to the render and every process
  it started. It then records `cancelled` in `<job>.run.yml` and removes
  `<job>.run.progress`, so the job can be submitted again. `submit_job()` now
  marks the render's environment, which is how `cancel_job()` finds the Quarto
  and knitr processes that run in sessions of their own, out of reach of a
  `kill` on the runner's process group. It refuses a job recorded on another
  host, naming the host, and never signals a pid another process has since
  taken. A run whose runner is already gone is recorded `failed`, with the
  reason, after any render it left running is stopped.
* `submit_job()`'s "already running" refusal now points at `cancel_job()` and,
  for a job recorded on another host, names both `<job>.run.yml` and
  `<job>.run.progress`: deleting the status file alone left the job refused.
