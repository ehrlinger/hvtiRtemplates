* Arguments now follow the hvtiR family's naming rule, and each old name works, with a warning once per session,
  for one more release. Giving an old name together with its new one is an error that names both. Each new name
  sits where the old one did, so a call that passes these arguments by position is unchanged.
  - `add_job()`, `open_job()`, `upgrade_job()`, `import_job()` and `migrate_job()` take `root` in place of `dir`.
    `import_job()` takes `path` in place of `from`. `migrate_job()` takes `path`, `lst_path`, `log_path` and
    `reference_path` in place of `source`, `lst`, `log` and `reference`.
  - `read_job_data()` takes `id_col`, `key_cols`, `join_cols`, `join_key_cols` and `imputation_col` in place of
    `id`, `key`, `join_vars`, `join_key` and `imputation`.
  - `build_cohort()` takes `path`, `join_cols` and `id_col` in place of `cohort`, `join_by` and `id`.
  - `life_table()`, `life_table_at()`, `life_table_tests()` and `life_table_keep()` take `time_col`, `event_col`
    and `strata_col` in place of `time`, `event` and `strata`.

  ⚠️ A shortened argument name that R used to complete, such as `read_job_data(cfg, imp = "imp")`, no longer
  resolves. Both the old and the new name start with the same letters, so R cannot tell which one is meant. Write
  the argument name out in full.
* `read_job_data()` and `build_cohort()` no longer assume the identifier column is `"ccfid"`, because that is one
  study's name for it. Leaving `id_col` out still reads `"ccfid"` for one more release, with a warning, and is an
  error after that. The templates already pass `ID`.
* `options(hvti.quiet = TRUE)` silences the package's informational messages in one place. `render_job()`,
  `run_job()` and `cancel_job()` take their `quiet` default from it, and an explicit `quiet`
  argument still wins. Warnings and errors are never silenced, and neither is `job_status()`, whose
  printed summary is its answer.
* A refusal that a caller might want to catch now carries a class: `hvtiRtemplates_run_refused`,
  `hvtiRtemplates_run_claimed`, `hvtiRtemplates_run_mismatch`, `hvtiRtemplates_job_running`,
  `hvtiRtemplates_cancel_incomplete`, `hvtiRtemplates_long_fit`, `hvtiRtemplates_memory` and
  `hvtiRtemplates_quarto_crashed`. A refused `WHERE` on the identifier is now `hvtiRtemplates_where_identifier`, and
  it keeps its old class `hvti_where_identifier` for one release. `render_job()` now raises base R conditions in
  place of `rlang::abort()`.
* A report's run record gains `provenance`. It holds the family's seven fields: `package`, `version`, `sha`,
  `method` (the template), `seed`, `rng_kind` and `time`. Each field is always present and always the same type,
  and it is `NA` where it does not apply.
