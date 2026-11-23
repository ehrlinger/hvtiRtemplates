- `add_job()` and `upgrade_job()` open the job in the editor when they finish,
  as `open_job()` does, in an interactive session only. Pass `open = FALSE` to
  leave it closed. `upgrade_job()` now opens a job that was already current
  too, where before it opened one only after changing it.
