# Descriptives demo: reference set

What a render of the demo study (`../demo-study.R`) should produce. Use it to
check a run of the slides (`../descriptives-slides.qmd`) or of
`../descriptives-demo.R`.

- `key-numbers.csv`: numbers the reports print. The data come from a fixed
  seed and R draws the same values on every platform, so these must match
  **exactly**. A difference means the data, a template or an upstream
  package has changed.
- `*.png`: one figure of each kind. Compare by eye. Font and antialiasing may
  differ between machines; the shape of the data should not.

`dp-postage` has no figure here: `tests/testthat/test-dp-eda.R` proves its
pages are byte-identical to `dp-eda`'s.

Regenerate with `Rscript dev/demo/make-reference.R` from the repository root.
It renders all six jobs in a temporary study, copies the figures, and computes
the numbers with the functions the jobs call. It stops if a rendered report
does not print a number the reference records. Review the diff before
committing: an unexpected change here is the thing this set exists to catch.
