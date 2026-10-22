# Fixtures for `.diagnose_failure()`

Each `.log` is the real output of a failed render, captured the way `submit_job()`'s runner captures it
(`Rscript` running `quarto::quarto_render()` inside `tryCatch`, standard output and error to one file,
`QUARTO_R` set), on a synthetic `.qmd` in a scratch directory. Quarto's own colour codes are kept.
Temp paths are replaced by `<tmp>`, and the one subject id boostmtree prints by `<id>`.

Versions: Quarto CLI 1.10.18, quarto R package 1.5.1, knitr 1.51, boostmtree 2.0.7, testthat 3.3.2, R 4.6.1.

| file | job | how it was made |
|---|---|---|
| `guard.log` | chunk `fit`: `stop("memory: probe refusal.\nStart a Large session.")` | rendered as is |
| `no-package.log` | chunk `setup`: `library(notapkg)` | rendered as is |
| `quitting.log` | chunk `fit`: `stop("boom")` | rendered as is |
| `oom-workers.log` | chunk `fit`: `boostmtree(..., cv.flag = TRUE, control = boostmtree.control(cv.cores = 2L))` on `simLong(n = 20, n.time = 4, model = 2, family = "continuous")`, with `parallel::mclapply` mocked (`testthat::with_mocked_bindings`) to return NULL for the first worker, as boostmtree's `test-cv-cores.R` does | rendered as is |
| `unknown.log` | a `.qmd` whose YAML front matter does not parse | rendered as is; Quarto stops before any chunk |
| `memory-and-package.log` | both signatures | **hand-assembled**: `oom-workers.log` followed by `no-package.log` |
| `guard-and-package.log` | both signatures | **hand-assembled**: `guard.log` followed by `no-package.log` |

The two assembled files exist so the order of the branches in `.diagnose_failure()` is tested: with the
signatures each real fixture carries alone, any order would pass.
