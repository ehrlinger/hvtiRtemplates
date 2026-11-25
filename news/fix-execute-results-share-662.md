- `render_job()` no longer fails on a network share that refuses, on every attempt, to remove a job's
  `_files/execute-results` folder ("Directory not empty (os error 39)", #662). In a project render, as every study's is,
  that folder is now a symbolic link to a temporary folder on local disk, so Quarto writes, reads and removes the
  results there and the share sees only the link. Execution is not frozen: every chunk runs, and the job's caches stay
  beside it. The retries from #637 and #650 remain for a render that meets the race without the link.
- A render that fails no longer costs the job its last report. `render_job()` copies the report to local disk before
  rendering and, if the render fails and the report is gone, puts it back with its own time and a message saying it
  predates the run.
