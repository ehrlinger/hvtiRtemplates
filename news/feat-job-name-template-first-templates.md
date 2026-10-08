* **Jobs are named template first, with periods.** `add_job()` writes
  `<prefix>[.<qualifier>].<subject>.<type>.qmd`, such as `ac.death.hz.qmd` or
  `dp.trends.cohort.eda.qmd`, and a bootstrap job's runner beside it as
  `<prefix>.<subject>.<type>.runner.R`, so a study's jobs sort by template,
  then subject, then type. Jobs scaffolded before this release keep their
  `<subject>-<type>-<prefix>[-<qualifier>]` names and keep rendering: every
  template's name check reads both spellings. `add_job()` and `migrate_job()`
  refuse to write a second copy of a job that exists under its old name, and
  `open_job()` opens it. `template_list()` shows qualified templates as
  `dp.trends`, and its `call` column uses that name; `"dp-trends"` is still
  accepted. Results folders (`estimates/<subject>-<type>/`,
  `graphs/<subject>-<type>/`) are unchanged.
