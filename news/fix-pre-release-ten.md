* The old template names `dp.eda` and `dp.trends`, renamed `dc.eda` and `dc.trends` on 2026-10-10, are removed:
  `add_job()`, `open_job()`, `template_path()` and `migrate_job()` now stop with an error naming the new name instead
  of warning. A job already written under an old name is still found by `open_job()` and `add_job()`, and
  `upgrade_job()` and `import_job()` read its name as the renamed template's, without a warning; a legacy SAS
  source named `dp.trends.sas` still migrates into `dc-trends`.
* `guard_long_fit()` names `run_job()`, which checks the job before submitting it, in place of `submit_job()`.
  The templates and `inst/templates/README.md` point at `run_job()` too.
* `lp-mirror` checks for hvtiPlotR 2.8.20, the version this package requires, in place of 2.8.9, and its matched
  figure's caption names the controls' colour as vermillion, as the other two captions do.
* Template comments and narration: each template's `FIGURES` example names one of its own figures; the figure-saving
  comment says a TIFF is written only when ragg is installed; the `ID` marker says the MRN, then eMRN, fallback
  applies when the data has no `ccfid` column; `vp-fit` names `vp-individual` as a reader of its selection;
  `hm` no longer points at `as.numeric()` calls it does not make, and says what `covariates_to_numeric()` does;
  `sid-fit` dates the `na.impute` behaviour to
  randomForestSRC 3.10.0; `br` says a screen moves with the outcome's transform, not its units; and two templates
  no longer name a person or a study.
