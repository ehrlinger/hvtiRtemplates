- The README's function table covers every export, grouped as the package is: the taxonomy and catalog,
  scaffolding and upgrading jobs, running them, the `ar` report and the `ac` life tables. It had listed 13 of
  29. It also gains an index of the articles and a list of the related packages, and the vignettes carry a date.
- The template catalog's `mi` row no longer says hvtiRimputation's `impute_multiple()` is unbuilt. It is built,
  and takes `predictors` since hvtiRimputation 0.1.4, which become required in 0.1.5; no template calls it yet.
- `install_provenance_hooks()` is exported. It adds the Quarto hooks a job that records its provenance needs to
  a study's `_quarto.yml`, as `add_job()` and `upgrade_job()` do, for a study whose jobs came from elsewhere. The
  message `render_job()` and `submit_job()` give when such a job is stopped for want of the hooks (#653) now
  names it, in place of an internal function.
- `rfc-fit` stops on an outcome with fewer than two classes among the patients the forest is grown on, saying
  which class they all have. It warned that the quantile classifier takes two classes only and went on, and a
  predictor with no values, under `na.omit`, counted the classes on no patients and raised `-Inf` warnings
  before the job's own stop on that predictor, which now comes first.
- When the patient KEY repeats in a `DATASET` named as an unregistered file, the error says the repeat is in that
  file, not in a working build, and its `duplicate_keys()` call lowercases the file's column names as the job
  does, so it runs on a file whose columns are upper case.
- If the render lock that `render_job()` takes to move a held `execute-results` folder aside cannot be released,
  it warns, naming the lock folder. The lock belonged to the R session, so every render of the study was refused
  until the session ended, the rerun that follows included, and nothing said why.
- In `rhf-fit` the note on naming a file as `DATASET` no longer splits a sentence, and in `hs-concordance`,
  `lp-mirror` and `vt-fit` it sits above `DATASET` rather than above the next choice.
