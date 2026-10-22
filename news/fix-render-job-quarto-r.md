* `render_job()`, and so `submit_job()`, now runs the job's chunks on the R
  that called it: it sets `QUARTO_R` to `R.home("bin")` for the render, unless
  `QUARTO_R` is already set. Quarto otherwise starts the first R on the `PATH`,
  which on a server with several R versions can be one whose `renv` library
  lacks the study's packages. Studies no longer need `QUARTO_R` in `.Renviron`.
* Requires hvtiRutilities 1.5.10, whose `hvti_taxonomy()` lists the `vp`
  prefix that the `vp-fit` and `vp-explain` templates use.
