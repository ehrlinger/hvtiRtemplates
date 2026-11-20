* A full test run no longer leaves `Rplots.pdf` in `tests/testthat`. Three groups of tests drew with no device
  open, so R opened its default one, which in `Rscript` is `pdf()` writing to the working directory. The
  `dc-tables` label test ran the template's `table-label-changes` chunk, whose `knitr::knit_child()` opens a device
  with `dev.new()` when no render is in progress; it now points the `device` option at a null pdf. The
  `sid-clusters` and `sid-stability` tests ran the `fig-silhouette` and `fig-agreement` chunks, which print their
  plots; the helpers that run them now open a null pdf of their own. The suite also checks for a stray
  `Rplots*.pdf` after every test: the test that left one gets a warning naming it, and the run stops at teardown
  (#494).
