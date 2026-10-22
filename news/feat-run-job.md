* New `run_job()` checks a job before it starts a long render, then submits it with
  `submit_job()`. It refuses, all at once and with what fixes each, a session
  on a different R from the one `renv.lock` records (`r_version`), packages missing, unrecorded
  in `renv.lock`, or at a different version from it (`packages`), no Quarto (`quarto`), a job already running
  (`run_state`) and another job already rendering in the same study (`study_render`).
  It then waits for the render's own checks, the R it runs on (`render_r`) and the memory
  its fit needs (`memory`), and prints the diagnosis if one fails. A job scaffolded before
  the setup consolidation has no in-render checks; `run_job()` says so and names
  `upgrade_job()`.
* New `hvti` shell command and `install_hvti()`, which copies it onto your `PATH`.
  `hvti run <job> [--final]`, `hvti status <job>` and `hvti cancel <job>` run
  `run_job()`, `job_status()` and `cancel_job()` on the R the study's `renv.lock` records,
  whichever R your own session started. `install_hvti("~/bin")` is the usual call; `dir` has no
  default. Run it again after updating the package.
* New `guard_memory()` stops a fit in the first minutes of a render when its expected
  memory exceeds 90 percent of the session's limit, and names the Workbench profile that
  would hold it and, given `cores_fit`, the largest core count that fits. Its estimator
  for boostmtree refuses the two fits measured being killed; it is not verified between
  them, and its coefficients are provisional until they are reviewed.
* `job_status()` now says why a failed run failed, with a fix, for out of memory, a package
  missing on the render's R, and the chunk and lines where the job stopped. It also shows
  the memory in use while the job runs, and its peak against the session's limit after.
* `nb-boostmtree` calls `guard_memory()` ahead of its cross-validated fit, with an
  estimate from the patients, visits, family and cores.
