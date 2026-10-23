# Fixtures for `.diagnose_failure()`

Each `.log` is the real output of a failed render, captured the way `submit_job()`'s runner captures it
(`Rscript` running `quarto::quarto_render()` inside `tryCatch`, standard output and error to one file,
`QUARTO_R` set), on a synthetic `.qmd` in a scratch directory. Quarto's own color codes are kept.
Local paths (temp directories, and the R home in `render-r.log`) are replaced by `<tmp>`, and the one subject id
boostmtree prints by `<id>`.

Versions: Quarto CLI 1.10.18, quarto R package 1.5.1, knitr 1.51, boostmtree 2.0.7, testthat 3.3.2, R 4.6.1.
`guard.log` and `render-r.log` were rendered on 2026-10-22 against the `feat/run-job` branch, with rlang 1.3.0.

| file | job | how it was made |
|---|---|---|
| `guard.log` | chunk `fit`: writes a fake cgroup v1 tree capped at 19.2 GiB, then `hvtiRtemplates::guard_memory(100, "this fit", proc = , sys = )` against it | rendered as is; the refusal is raised inside `guard_memory()`, so rlang prints a `Backtrace:` after it |
| `render-r.log` | chunk `setup`: `.job_setup("cohort", "eda")` in a temp study, rendered with `HVTI_RUN_R=/opt/R/4.5.3/lib/R/bin` and `HVTI_RUN_R_VERSION=4.5.3` | rendered as is; the two-line `render_r` refusal, raised inside `.job_setup()`, then a `Backtrace:` |
| `no-package.log` | chunk `setup`: `library(notapkg)` | rendered as is |
| `quitting.log` | chunk `fit`: `stop("boom")` | rendered as is |
| `oom-workers.log` | chunk `fit`: `boostmtree(..., cv.flag = TRUE, control = boostmtree.control(cv.cores = 2L))` on `simLong(n = 20, n.time = 4, model = 2, family = "continuous")`, with `parallel::mclapply` mocked (`testthat::with_mocked_bindings`) to return NULL for the first worker, as boostmtree's `test-cv-cores.R` does | rendered as is |
| `unknown.log` | a `.qmd` whose YAML front matter does not parse | rendered as is; Quarto stops before any chunk |
| `memory-and-package.log` | both signatures | **hand-assembled**: `oom-workers.log` followed by `no-package.log` |
| `guard-and-package.log` | both signatures | **hand-assembled**: `guard.log` followed by `no-package.log` |

The two assembled files exist so the order of the branches in `.diagnose_failure()` is tested: with the
signatures each real fixture carries alone, any order would pass.

`quitting-backtrace.log`: chunk `fit` calling `outer(1)` -> `inner()` -> `stop("inner failure\nsecond line")`, rendered as is; the
error is followed by a `Backtrace:` block.
