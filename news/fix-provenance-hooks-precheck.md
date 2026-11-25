- `render_job()`, `submit_job()` and `run_job()` stop a job that records its
  provenance before the render starts when the study lacks the Quarto
  provenance hooks: a root `_quarto.yml` that runs them, and `.hvtiR/hooks`.
  Such a job used to fail only at its provenance chunk, after its last fit. The
  message gives the command that installs the hooks and, in a study that had no
  `_quarto.yml`, says that deleting it once the job has rendered restores the
  study's own rendering. The check and the provenance chunk test the same
  conditions, from one helper (#645).
