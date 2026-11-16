* Templates and the bootstrap runners call the family packages by their new
  argument names (`time_col`, `event_col`, `time_cols`, `id_col`, `var_cols`,
  `class_cols`, `key_cols`, `facet_col`, `arm_col`, `covariate_cols`, the
  `ps_stddiff()` `*_cols` arguments and `boot_select(n_boot =)`), and pass
  `root =` last to `declare_data()` and `register_data()`. The old names still
  work in the family's current releases but warn on every render, and stop
  working in their next releases. `read_job_data()`'s cohort check calls
  `cohort_counts()` the same way. **A job already in a study keeps the old
  names until it is brought up to date with `upgrade_job()`; it renders, with
  deprecation warnings, until those packages drop the old names.**
* The `bh` hazard bootstrap runner records its screen the way the `bc`, `bl` and
  `br` runners do: the fitter, the model formula with each phase's scope, the
  selection method, the draw fraction, the RNG kind, TemporalHazard's commit
  when the installer recorded one, and the family's seven-field `$provenance`.
  `boot_pool_chunks()` therefore checks that a hazard run's chunks share a model
  instead of reading every one as "hazard runner (unrecorded)". **A run whose
  chunks were written partly before this change refuses to pool**, because the
  older chunks record no model; rerun those chunks with the current runner.
* `dc-tables`' scatter-plot matrix caption says that its panels carry no
  coefficient and that the table above gives Spearman's (`hvtiPlotR`'s default
  from its next release) and Pearson's.
