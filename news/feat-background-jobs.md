* New `submit_job()` and `job_status()` render a job in the background,
  detached from the session, so a long fit survives a Workbench session that
  times out. The render is `render_job()` unchanged; it writes `<job>.run.log`
  and `<job>.run.yml` beside the job. Not available on Windows.
* New `guard_long_fit()` stops a long fit from starting in an interactive
  session when it is not cached yet, and names the `submit_job()` call to use.
  `nb-boostmtree` calls it before its cross-validated fit.
