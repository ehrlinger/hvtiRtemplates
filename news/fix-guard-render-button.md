- `guard_long_fit()` now also stops an uncached long fit rendered with the RStudio or Posit Workbench **Render
  button**, not only one run interactively. That render belongs to the Workbench session and dies when the session
  times out, as a boostmtree fit did mid-`predict()` on 2026-11-16. The error names the Render button and gives the
  `hvtiRtemplates::run_job()` call; once the fit is cached the Render button works again. A render from
  `submit_job()` or `run_job()`, or from a terminal (including `nohup quarto render` in the Workbench Terminal tab),
  still passes. A Render-button render is told apart by `RSTUDIO=1` with no `RSTUDIO_TERM`, which only the Terminal
  tab sets; RStudio on Windows does not set it, so there a terminal render inside RStudio is stopped too.
