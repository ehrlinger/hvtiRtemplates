- `guard_long_fit()` now stops an uncached long fit everywhere but a render `run_job()` or `submit_job()` started.
  Until now it stopped one only in an interactive session, so the RStudio or Posit Workbench **Render button** let an
  hours-long fit start inside the session, where it died on the session's timeout, as a boostmtree fit did
  mid-`predict()` on 2026-11-16. A `quarto render` typed in the Workbench Terminal is a child of the session too,
  `nohup` or not, and is stopped as well. The error names the `hvtiRtemplates::run_job()` call to use. A cached
  result passes, so once `run_job()` has done the fit the Render button works again. For a fit known to be short,
  `options(hvtiRtemplates.allow_interactive_fit = TRUE)` still lets it through, and the new environment variable
  `HVTI_ALLOW_LONG_FIT=true` does the same for a render's own R process, which an option set in the session does
  not reach.
- `nb-boostmtree`, `rfs-fit`, `rhf-fit` and `rhf-explain` now call `guard_long_fit()` only when
  `hvtiRutilities::cache_would_fit()` says the fit will be computed, as the `rf*-explain` and
  `sid-stability` templates already did. A cache whose key matches loads even under `REFIT <- TRUE`, so it is no
  longer refused. **A job already in a study changes only when it is brought up to date with `upgrade_job()`.**
