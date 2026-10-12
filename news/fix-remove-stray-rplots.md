* The package no longer ships two stray, blank `Rplots.pdf` files (at the top
  level and in `tests/testthat/`) that a test run had left in the source; `R CMD
  check` flagged the top-level one as a non-standard file.
