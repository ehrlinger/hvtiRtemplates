* The tests of the stale-install guard pass on Windows: the guard finds Quarto's R as `Rscript.exe` there, and
  the test that gives each study its own `.Rprofile` is skipped on Windows, where the check's R reads none.
