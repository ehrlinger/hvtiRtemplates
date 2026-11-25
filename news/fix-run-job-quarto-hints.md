- `run_job()` names a fix that works for each package it finds out of step.
  `hvtiR::update()` only for hvtiR family packages; for any other,
  `renv::restore()` when `renv.lock` records it, and `renv::install()` then
  `renv::record()` when it does not (#612).
- The quarto R package moves from Suggests to Imports: `render_job()` and
  `run_job()` need it, so installing hvtiRtemplates now brings it into a
  study renv (#612).
