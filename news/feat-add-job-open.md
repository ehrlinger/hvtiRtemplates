- `add_job()` and `upgrade_job()` open the job in the editor when they finish,
  as `open_job()` does, in an interactive session only. Pass `open = FALSE` to
  leave it closed. `upgrade_job()` now opens a job that was already current
  too, where before it opened one only after changing it.
- An editor that fails to open after `add_job()`, `open_job()`,
  `upgrade_job()` or `migrate_job()` has written the job is a warning of class
  `hvtiRtemplates_editor_failed`, not an error: the job is in place and its path
  is returned.
