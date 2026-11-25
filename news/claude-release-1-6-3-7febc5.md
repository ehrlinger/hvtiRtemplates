- The README's function table covers every export, grouped as the package is: the taxonomy and catalog,
  scaffolding and upgrading jobs, running them, the `ar` report and the `ac` life tables. It had listed 13 of
  29. It also gains an index of the articles and a list of the related packages, and the vignettes carry a date.
- The template catalog's `mi` row no longer says hvtiRimputation's `impute_multiple()` is unbuilt. It is built,
  and takes `predictors` since hvtiRimputation 0.1.4, which become required in 0.1.5; no template calls it yet.
- `install_provenance_hooks()` is exported. It adds the Quarto hooks a job that records its provenance needs to
  a study's `_quarto.yml`, as `add_job()` and `upgrade_job()` do, for a study whose jobs came from elsewhere. The
  message `render_job()` and `submit_job()` give when such a job is stopped for want of the hooks (#653) now
  names it, in place of an internal function.
