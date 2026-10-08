* **Templates name the study dataset `"built"`, the team's word for it.** Every
  job's study choices now say `DATASET <- "built"`, and so do the `bc`, `bh`,
  `bl` and `br` runners and the jobs `migrate_job()` writes. `"study"` still
  works, so a job scaffolded before this change keeps running unchanged, and a
  downstream job agrees with an upstream one whichever name each used. Records
  still say `"study"`: the selection a job hands on and its provenance sidecar
  compare equal under either name. Requires hvtiRutilities 1.5.1, which made
  `"built"` a second name for the study dataset.
