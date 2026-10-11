* `dp-eda` and `dp-trends` are renamed `dc-eda` and `dc-trends`, so every
  descriptive template now carries the `dc` prefix. The old names, `dp.eda` and
  `dp.trends`, still work in `add_job()`, `open_job()`, `template_path()` and
  `migrate_job()` through the next release, each call warning once that the
  name is deprecated in favor of its `dc` replacement, and are removed in the
  release after. A job already scaffolded as `dp.eda.*` or `dp.trends.*` (or
  `*-dp-eda.qmd`, `*-dp-trends.qmd`) keeps its name and keeps rendering:
  `open_job()` opens it under either name, and `add_job()` refuses to write a
  second copy under the new one. A legacy SAS source named `dp.trends.*`
  migrates into `dc-trends` without a warning. The taxonomy keeps its `dp`
  row, since legacy jobs carry that prefix; the queued `dp-variable` and
  `dp-boxplot` templates are planned as `dc-variable` and `dc-boxplot`.

* A new `dc-trends` job is written to the study's descriptive folder
  (`10_descriptive/`, or `descriptive/` in a legacy study), where `dp-trends`
  wrote it to `graphs/`. Its figures are still saved under
  `graphs/<subject>-<type>/`, and the report links them from its new folder.

* `dp-gfup`, deprecated in favor of `dc-gfup` in 1.3.0, is removed.
  `add_job("dc.gfup", subject, type)` draws the same panels beside the
  follow-up tables. Asking for `dp.gfup` now stops with an error naming
  `dc.gfup`: an unknown template's error lists any template with the same
  qualifier under another prefix.
