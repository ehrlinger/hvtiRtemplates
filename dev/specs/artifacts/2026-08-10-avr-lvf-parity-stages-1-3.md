# AVR / LV-function TemporalHazard Parity — Stages 1–3 Implementation Plan

> **Migrated 2026-08-18** from `/Volumes/qhsstudies/cardiac/valves/aortic/replacement/pericardial/lv_function/survival/analyses/R_parity/docs/plans/2026-08-10-avr-lvf-parity-stages-1-3.md`.
> Cross-references to the other migrated documents have been repointed to their
> paths in this repository; the text is otherwise unchanged. Study folders on the
> share do not host git repositories, so the design record lives with the package
> that owns the migration programme. `specs/artifacts/README.md` records what
> moved and from where.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reproduce stages 1–3 of the AVR/LV-function survival study (actuarial, unadjusted temporal-hazard fit, hazard figure) in R with `TemporalHazard`, cross-checked against the SAS `.lst` reference outputs, delivered as a rendered Quarto report.

**Architecture:** A Quarto project at `analyses/R_parity/`. Two R source files carry all reusable logic — `R/parity.R` (tolerance policy, `.lst` parsing, comparison harness) and `R/read_built.R` (labelled data read, manifest pinning, cohort gate). Three stage `.qmd` files consume them and render one report. The R tree reads its SAS parent; it never writes to it.

**Tech Stack:** R 4.6.0, `TemporalHazard`, `hvtiRutilities`, `haven`, `survival`, `hvtiPlotR`, `testthat` (3rd edition), Quarto, `renv`.

**Spec:** `dev/specs/2026-08-10-avr-lvf-temporalhazard-parity-design.md`

## Global Constraints

- **Execution target is the CCF server**, not a Mac. The Mac mount is authoring only.
- **No R file may hardcode a study path.** Server is `/studies/cardiac/...`; Mac mount is `/Volumes/qhsstudies/cardiac/...`. All paths resolve at runtime from the study root.
- **Read-only discipline:** nothing under `analyses/R_parity/` writes outside itself — not to `datasets/`, `distributions/`, `graphs/`, `estimates/`, nor to the SAS files in its own parent `analyses/`.
- **Target cohort: N = 3049, 1032 events, 2017 right-censored.** `n=3316` and `n=3687` in the SAS sources are stale strings; ignore them.
- **Tolerance classes** (spec §5.2.1) — `exact` (atol 0, rtol 0); `printed` (atol = half-ULP of printed value, rtol 0); `optimizer` (atol 1e-6, rtol 1e-3); `curvature` (atol 1e-6, rtol 1e-2).
- **Outcome is three-state:** `PASS` / `DIFFERS` / `R_BETTER`. `R_BETTER` only for log-likelihood when R exceeds SAS beyond tolerance.
- **Every stage reports the headline max relative discrepancy**, and a max of exactly `0` is a failure signal, not a success.
- **`compare_parity()` errors** — never warns, never skips — when a requested quantity is absent on either side.
- **SAS confidence level is `CLEVEL = 0.68268948`** (±1 SD), not 0.95.
- **Survival CLs use `conf.type = "logit"`** to match HAZPRED (`predict.hazard()` defaults to `"log-log"`).
- **Failure handling:** any miss is diagnosed to a named cause — pipeline bug, parser bug, or package gap — before anything is adjusted. Never tune tolerances or starting values to force a match.
- **Commit to branch `feat/r-analysis-temporalhazard-parity`.** Never to `master`.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `_quarto.yml` | Quarto project definition; render order; output to `_output/` |
| `.gitignore` | Ignore `_output/`, `*_files/`, `.quarto/` |
| `R/paths.R` | Resolve the study root at runtime; build paths to SAS reference files |
| `R/parity.R` | Tolerance policy, `compare_parity()`, `parity_headline()`, `parse_lst()` |
| `R/read_built.R` | Labelled dataset read, manifest pin, cohort gate |
| `qmd/index.qmd` | Study framing, Rajeswaran's email, stage table, environment record |
| `qmd/01-ac-dead.qmd` | Stage 1 — cohort gate + Kaplan–Meier parity |
| `qmd/02-hz-dead.qmd` | Stage 2 — two-phase hazard fit parity |
| `qmd/03-hp-dead.qmd` | Stage 3 — nomogram prediction parity + figures |
| `tests/testthat/test-parity.R` | Unit tests for the tolerance policy and comparison harness |
| `tests/testthat/test-paths.R` | Unit tests for path resolution |
| `tests/testthat.R` | testthat runner |
| `docs/preflight/SERVER-PREFLIGHT.md` | Recorded server environment audit (Task 1 output) |

**Why `paths.R` is separate from `parity.R`:** path resolution is the one thing every other file depends on and the one thing that differs between the Mac and the server. Isolating it means a single file changes if the deployment layout changes, and it can be unit-tested without any SAS files present.

---

## Task 1: Server preflight — environment audit and parser access

The spec assumed `.lst` parsers were reachable via `TemporalHazard:::`. **They are not.** The installed package contains no `tests` directory; the parsers live only in the source repo at `tests/testthat/helper-sas-parity.R`. This task resolves that before any code depends on it.

**Files:**
- Create: `analyses/R_parity/docs/preflight/SERVER-PREFLIGHT.md`
- Create: `analyses/R_parity/R/preflight.R`

**Interfaces:**
- Consumes: nothing (first task)
- Produces: `preflight_report()` returning a `data.frame` with columns `component` (character), `found` (logical), `version` (character), `notes` (character). Also produces the documented decision on parser access, consumed by Task 4.

- [ ] **Step 1: Write the preflight script**

Create `analyses/R_parity/R/preflight.R`:

```r
# Environment audit. Run on the SERVER before any other task.
# Produces a data.frame; prints a human-readable table.

preflight_report <- function() {
  pkgs <- c("TemporalHazard", "hvtiRutilities", "haven", "survival",
            "hvtiPlotR", "testthat", "quarto", "ggplot2", "here")

  rows <- lapply(pkgs, function(p) {
    v <- tryCatch(as.character(utils::packageVersion(p)),
                  error = function(e) NA_character_)
    data.frame(component = p,
               found     = !is.na(v),
               version   = ifelse(is.na(v), "", v),
               notes     = "",
               stringsAsFactors = FALSE)
  })

  out <- do.call(rbind, rows)

  out <- rbind(
    data.frame(component = "R", found = TRUE,
               version = paste0(R.version$major, ".", R.version$minor),
               notes = R.version$platform, stringsAsFactors = FALSE),
    out
  )

  # Quarto CLI is not an R package; probe the executable.
  q <- tryCatch(system2("quarto", "--version", stdout = TRUE, stderr = NULL),
                error = function(e) character(0), warning = function(w) character(0))
  out <- rbind(out, data.frame(
    component = "quarto CLI", found = length(q) > 0,
    version = if (length(q)) q[1] else "",
    notes = if (length(q)) "" else "report will not render", 
    stringsAsFactors = FALSE))

  # The .lst parsers are NOT installed with the package. Locate the source repo.
  helper <- Sys.getenv("TEMPORAL_HAZARD_SRC", unset = "")
  helper_path <- if (nzchar(helper)) {
    file.path(helper, "tests", "testthat", "helper-sas-parity.R")
  } else ""
  out <- rbind(out, data.frame(
    component = "helper-sas-parity.R", found = nzchar(helper_path) && file.exists(helper_path),
    version = "", 
    notes = if (nzchar(helper_path)) helper_path else "set TEMPORAL_HAZARD_SRC",
    stringsAsFactors = FALSE))

  out
}
```

- [ ] **Step 2: Run the preflight on the server**

Run: `Rscript -e 'source("analyses/R_parity/R/preflight.R"); print(preflight_report(), row.names = FALSE)'`

Expected: a table with one row per component. Record the actual output verbatim in Step 3. Do **not** proceed past this task if `TemporalHazard` reports `found = FALSE`.

- [ ] **Step 3: Record the audit**

Create `analyses/R_parity/docs/preflight/SERVER-PREFLIGHT.md` with this structure, filling in the real output from Step 2:

```markdown
# Server preflight — <YYYY-MM-DD>

Host: <hostname from `Sys.info()[["nodename"]]`>

## Environment

<paste the preflight_report() table here, verbatim>

## Parser access decision

The `.lst` parsers (`.hzr_parse_sas_lst`, `.hzr_parse_sas_lifetable`,
`.hzr_parse_sas_nomogram`) are NOT in the installed `TemporalHazard`
namespace. The installed package ships no `tests` directory.

Resolution taken: <one of A / B below>

- **A — source from a checkout.** `TEMPORAL_HAZARD_SRC` points at a
  `temporal_hazard` git checkout on the server; `parse_lst()` sources
  `tests/testthat/helper-sas-parity.R` from it. Preferred: no fork, and any
  parser fix flows back upstream.
- **B — blocked.** No checkout available on the server. Stages 1–3 cannot
  compare against `.lst` until one exists. Record this and stop.

## Upstream fix to raise

The parsers should move to `inst/` in `TemporalHazard` so `system.file()`
reaches them from an installed package. Raise as an issue against
`temporal_hazard`; do not vendor a copy into this study (that forks a
validated parser, which the spec forbids).

## Deviations from spec §9.1

<list any version differences from the Mac reference table, or "none">
```

- [ ] **Step 4: Commit**

```bash
git add analyses/R_parity/R/preflight.R analyses/R_parity/docs/preflight/SERVER-PREFLIGHT.md
git commit -m "chore: server environment preflight and parser access decision"
```

---

## Task 2: Project scaffold and path resolution

**Files:**
- Create: `analyses/R_parity/_quarto.yml`
- Create: `analyses/R_parity/.gitignore`
- Create: `analyses/R_parity/R/paths.R`
- Create: `analyses/R_parity/tests/testthat.R`
- Test: `analyses/R_parity/tests/testthat/test-paths.R`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `study_root()` → character scalar, absolute path to the study root (the directory containing `datasets/`, `analyses/`, `distributions/`, `graphs/`)
  - `sas_path(...)` → character scalar, absolute path built from the study root
  - `lst_path(stage)` → character scalar, absolute path to a stage's `.lst`; `stage` is one of `"ac"`, `"hz"`, `"hp"`, `"hm"`

- [ ] **Step 1: Write the failing test**

Create `analyses/R_parity/tests/testthat/test-paths.R`:

```r
test_that("study_root finds the directory containing the SAS trees", {
  root <- study_root()
  expect_true(dir.exists(root))
  expect_true(dir.exists(file.path(root, "datasets")))
  expect_true(dir.exists(file.path(root, "distributions")))
  expect_true(dir.exists(file.path(root, "graphs")))
  expect_true(dir.exists(file.path(root, "analyses")))
})

test_that("study_root contains no hardcoded deployment prefix", {
  src <- readLines(file.path(study_root(), "analyses", "R_parity", "R", "paths.R"))
  expect_false(any(grepl("/Volumes/qhsstudies", src, fixed = TRUE)))
  expect_false(any(grepl("/studies/cardiac", src, fixed = TRUE)))
})

test_that("lst_path resolves each stage to an existing file", {
  for (s in c("ac", "hz", "hp", "hm")) {
    p <- lst_path(s)
    expect_true(file.exists(p), info = paste("missing .lst for stage", s))
  }
})

test_that("lst_path rejects an unknown stage", {
  expect_error(lst_path("zz"), "unknown stage")
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Rscript -e 'library(testthat); testthat::test_local("analyses/R_parity")'`

Expected: FAIL — `could not find function "study_root"`.

- [ ] **Step 3: Write the implementation**

Create `analyses/R_parity/R/paths.R`:

```r
# Runtime path resolution. The study resolves to different absolute paths on
# the server and on a Mac mount, so nothing here may contain a literal prefix.
# The root is found by walking up until the SAS sibling directories appear.

study_root <- function(start = getwd()) {
  markers <- c("datasets", "distributions", "graphs", "analyses")
  dir <- normalizePath(start, mustWork = TRUE)
  repeat {
    if (all(dir.exists(file.path(dir, markers)))) return(dir)
    parent <- dirname(dir)
    if (identical(parent, dir)) {
      stop("study_root(): walked to the filesystem root without finding ",
           paste(markers, collapse = ", "), " under a common parent. ",
           "Start from inside the study tree.", call. = FALSE)
    }
    dir <- parent
  }
}

sas_path <- function(...) {
  file.path(study_root(), ...)
}

# Stage -> reference .lst. The three stages live in three different SAS
# directories, which is why this is a lookup and not a single template.
lst_path <- function(stage) {
  map <- c(
    ac = file.path("distributions", "ac.dead_JR.lst"),
    hz = file.path("distributions", "hz.dead_JR.lst"),
    hp = file.path("graphs",        "hp.dead_JR.lst"),
    hm = file.path("analyses",      "hm.dead_s3_JR.lst")
  )
  if (!stage %in% names(map)) {
    stop("unknown stage: ", stage, ". Expected one of: ",
         paste(names(map), collapse = ", "), call. = FALSE)
  }
  sas_path(map[[stage]])
}
```

- [ ] **Step 4: Write the testthat runner**

Create `analyses/R_parity/tests/testthat.R`:

```r
library(testthat)
for (f in list.files(file.path("..", "R"), pattern = "[.]R$", full.names = TRUE)) {
  source(f)
}
test_check("R_parity")
```

Create `analyses/R_parity/tests/testthat/helper-source.R`:

```r
# testthat::test_local() does not know this is a package, so source R/ by hand.
.r_dir <- file.path(rprojroot::find_root_file(criterion = rprojroot::has_file("_quarto.yml")), "R")
for (.f in list.files(.r_dir, pattern = "[.]R$", full.names = TRUE)) source(.f)
```

If `rprojroot` is unavailable on the server (check the Task 1 audit), replace the first line with:

```r
.r_dir <- normalizePath(file.path(dirname(dirname(getwd())), "R"))
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `Rscript -e 'testthat::test_local("analyses/R_parity")'`

Expected: PASS — 4 tests, 0 failures.

- [ ] **Step 6: Write the Quarto project file**

Create `analyses/R_parity/_quarto.yml`:

```yaml
project:
  type: book
  output-dir: _output

book:
  title: "AVR / LV function survival — TemporalHazard parity"
  subtitle: "Stages 1–3: actuarial, temporal hazard fit, hazard figure"
  author: "Cardiovascular Outcomes, Registries and Research (CORR)"
  chapters:
    - qmd/index.qmd
    - qmd/01-ac-dead.qmd
    - qmd/02-hz-dead.qmd
    - qmd/03-hp-dead.qmd

format:
  html:
    theme: cosmo
    toc: true
    code-fold: true
    df-print: paged

execute:
  echo: true
  warning: true
  error: false
  freeze: false
```

- [ ] **Step 7: Write the gitignore**

Create `analyses/R_parity/.gitignore`:

```
_output/
.quarto/
*_files/
*.rds
```

- [ ] **Step 8: Commit**

```bash
git add analyses/R_parity/_quarto.yml analyses/R_parity/.gitignore \
        analyses/R_parity/R/paths.R analyses/R_parity/tests
git commit -m "feat: quarto scaffold and runtime path resolution"
```

---

## Task 3: The tolerance policy and comparison harness

This is the reusable core. It is built test-first because every downstream number depends on it being right, and because a comparison harness that cannot fail is the specific failure mode this project has hit before.

**Files:**
- Create: `analyses/R_parity/R/parity.R`
- Test: `analyses/R_parity/tests/testthat/test-parity.R`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `parity_tol(class, printed_dp = NULL)` → `list(atol = numeric(1), rtol = numeric(1))`. `class` is one of `"exact"`, `"printed"`, `"optimizer"`, `"curvature"`.
  - `compare_parity(quantity, r, sas, class, printed_dp = NULL, higher_is_better = FALSE)` → `data.frame` with columns `quantity` (character), `r` (numeric), `sas` (numeric), `abs_diff` (numeric), `rel_diff` (numeric), `atol` (numeric), `rtol` (numeric), `outcome` (character, one of `"PASS"`, `"DIFFERS"`, `"R_BETTER"`).
  - `parity_headline(df)` → `list(n = integer(1), max_rel_diff = numeric(1), n_pass = integer(1), n_differs = integer(1), n_better = integer(1))`
  - `parity_badge(df)` → character scalar, a one-line markdown summary for a `.qmd`.

- [ ] **Step 1: Write the failing tests**

Create `analyses/R_parity/tests/testthat/test-parity.R`:

```r
test_that("parity_tol derives the printed tolerance from decimal places", {
  expect_equal(parity_tol("printed", printed_dp = 2)$atol, 0.005)
  expect_equal(parity_tol("printed", printed_dp = 5)$atol, 5e-6)
  expect_equal(parity_tol("printed", printed_dp = 2)$rtol, 0)
})

test_that("parity_tol returns the documented class constants", {
  expect_equal(parity_tol("exact"),     list(atol = 0,    rtol = 0))
  expect_equal(parity_tol("optimizer"), list(atol = 1e-6, rtol = 1e-3))
  expect_equal(parity_tol("curvature"), list(atol = 1e-6, rtol = 1e-2))
})

test_that("parity_tol requires printed_dp for the printed class", {
  expect_error(parity_tol("printed"), "printed_dp")
})

test_that("parity_tol rejects an unknown class", {
  expect_error(parity_tol("approximately"), "unknown class")
})

test_that("compare_parity passes a value inside the printed interval", {
  out <- compare_parity("log_likelihood", r = -3363.5813, sas = -3363.58,
                        class = "printed", printed_dp = 2)
  expect_equal(out$outcome, "PASS")
  expect_equal(nrow(out), 1L)
})

test_that("compare_parity flags a value outside the printed interval", {
  out <- compare_parity("log_likelihood", r = -3363.50, sas = -3363.58,
                        class = "printed", printed_dp = 2)
  expect_equal(out$outcome, "DIFFERS")
})

test_that("compare_parity reports R_BETTER when R's likelihood is higher", {
  out <- compare_parity("log_likelihood", r = -3300.00, sas = -3363.58,
                        class = "printed", printed_dp = 2,
                        higher_is_better = TRUE)
  expect_equal(out$outcome, "R_BETTER")
})

test_that("compare_parity does not report R_BETTER when R is worse", {
  out <- compare_parity("log_likelihood", r = -3400.00, sas = -3363.58,
                        class = "printed", printed_dp = 2,
                        higher_is_better = TRUE)
  expect_equal(out$outcome, "DIFFERS")
})

test_that("compare_parity applies relative tolerance at optimizer class", {
  # 0.05% off a coefficient of 1.2 is inside rtol = 1e-3
  expect_equal(compare_parity("mue", 1.2006, 1.2, "optimizer")$outcome, "PASS")
  # 1% off is outside
  expect_equal(compare_parity("mue", 1.212,  1.2, "optimizer")$outcome, "DIFFERS")
})

test_that("compare_parity uses atol near zero where rtol cannot help", {
  expect_equal(compare_parity("beta", 1e-7, 0, "optimizer")$outcome, "PASS")
  expect_equal(compare_parity("beta", 1e-3, 0, "optimizer")$outcome, "DIFFERS")
})

test_that("compare_parity requires exact agreement for counts", {
  expect_equal(compare_parity("n_events", 1032, 1032, "exact")$outcome, "PASS")
  expect_equal(compare_parity("n_events", 1031, 1032, "exact")$outcome, "DIFFERS")
})

test_that("compare_parity is vectorised over a quantity block", {
  out <- compare_parity(c("a", "b", "c"), c(1, 2, 3), c(1, 2, 3.5), "optimizer")
  expect_equal(nrow(out), 3L)
  expect_equal(out$outcome, c("PASS", "PASS", "DIFFERS"))
})

test_that("compare_parity errors when the SAS side is absent", {
  expect_error(compare_parity("mue", r = 1.2, sas = NULL, class = "optimizer"),
               "absent")
  expect_error(compare_parity("mue", r = 1.2, sas = NA_real_, class = "optimizer"),
               "absent")
})

test_that("compare_parity errors when the R side is absent", {
  expect_error(compare_parity("mue", r = NULL, sas = 1.2, class = "optimizer"),
               "absent")
})

test_that("compare_parity errors on a length mismatch", {
  expect_error(compare_parity(c("a", "b"), c(1, 2), 1, "optimizer"), "length")
})

test_that("parity_headline summarises a comparison block", {
  df <- rbind(
    compare_parity("a", 1.0000, 1.0, "optimizer"),
    compare_parity("b", 2.0300, 2.0, "optimizer")
  )
  h <- parity_headline(df)
  expect_equal(h$n, 2L)
  expect_equal(h$n_pass, 1L)
  expect_equal(h$n_differs, 1L)
  expect_equal(h$max_rel_diff, 0.015, tolerance = 1e-9)
})

test_that("parity_headline flags a suspiciously perfect block", {
  df <- rbind(
    compare_parity("a", 1, 1, "optimizer"),
    compare_parity("b", 2, 2, "optimizer")
  )
  expect_warning(parity_headline(df), "exactly zero")
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'testthat::test_local("analyses/R_parity")'`

Expected: FAIL — `could not find function "parity_tol"`.

- [ ] **Step 3: Write the implementation**

Create `analyses/R_parity/R/parity.R`:

```r
# Parity comparison harness.
#
# Tolerance policy (spec 5.2.1). The .lst does not contain numbers, it contains
# intervals: "Log likelihood = -3363.58" means the true value lies in
# [-3363.585, -3363.575). Half a unit in the last printed place is therefore a
# floor derived from the reference, not a tuned constant.
#
# Underneath that floor sits optimizer divergence: R runs multi-start ->
# Nelder-Mead -> BFGS with an analytic gradient; SAS runs `steepest quasi`
# single-start. Two correct implementations land on different points within
# their own convergence tolerances. So tolerance is set by the noisiest step in
# each quantity's computation chain, which differs by quantity.

parity_tol <- function(class, printed_dp = NULL) {
  if (identical(class, "printed")) {
    if (is.null(printed_dp)) {
      stop("parity_tol(): class 'printed' requires printed_dp ",
           "(decimal places shown in the .lst)", call. = FALSE)
    }
    return(list(atol = 0.5 * 10^(-printed_dp), rtol = 0))
  }
  switch(class,
    exact     = list(atol = 0,    rtol = 0),
    optimizer = list(atol = 1e-6, rtol = 1e-3),
    curvature = list(atol = 1e-6, rtol = 1e-2),
    stop("unknown class: ", class,
         ". Expected exact, printed, optimizer, or curvature.", call. = FALSE)
  )
}

# Fail loud. A comparison that silently skips an absent quantity is worse than
# no comparison: it reports PASS for something never checked. compare_parity()
# is vectorised over a block, so the realistic failure is one missing element
# among several (e.g. sas = c(1.0, NA_real_)) — anyNA() catches that, not just
# a wholly-absent vector.
.parity_require <- function(x, side, quantity) {
  absent <- is.null(x) || length(x) == 0L || anyNA(x)
  if (absent) {
    # Name the offending quantities, not just "absent", so a caller can act
    # on it when a block has thirty rows. Fall back to the full list when
    # positional pairing with `quantity` isn't possible (NULL/empty x, or a
    # length mismatch that compare_parity() will separately reject).
    which_absent <- if (is.null(x) || length(x) != length(quantity)) {
      quantity
    } else {
      quantity[is.na(x)]
    }
    stop("compare_parity(): ", side, " value absent for quantity(s) ",
         paste(which_absent, collapse = ", "),
         ". Nothing was compared.", call. = FALSE)
  }
  invisible(TRUE)
}

compare_parity <- function(quantity, r, sas, class,
                           printed_dp = NULL, higher_is_better = FALSE) {
  .parity_require(r,   "R",   quantity)
  .parity_require(sas, "SAS", quantity)

  n <- length(quantity)
  if (length(r) != n || length(sas) != n) {
    stop("compare_parity(): length mismatch — quantity (", n, "), r (",
         length(r), "), sas (", length(sas), ") must agree.", call. = FALSE)
  }

  tol <- parity_tol(class, printed_dp)
  abs_diff <- abs(r - sas)
  rel_diff <- ifelse(sas == 0, NA_real_, abs_diff / abs(sas))
  within   <- abs_diff <= tol$atol + tol$rtol * abs(sas)

  outcome <- ifelse(within, "PASS",
              ifelse(higher_is_better & r > sas, "R_BETTER", "DIFFERS"))

  data.frame(
    quantity = quantity, r = r, sas = sas,
    abs_diff = abs_diff, rel_diff = rel_diff,
    atol = tol$atol, rtol = tol$rtol,
    outcome = outcome,
    stringsAsFactors = FALSE
  )
}

# The reviewer-facing number. Not the PASS badge: the max discrepancy is true
# regardless of whether the reader accepts our thresholds.
parity_headline <- function(df) {
  if (!nrow(df)) stop("parity_headline(): empty comparison block", call. = FALSE)

  # sum(df$outcome == "PASS") with no na.rm poisons every count with NA the
  # instant one outcome is NA. That should be unreachable now that
  # .parity_require() catches partial absence, but if it ever happens anyway
  # it is a programming error, not a result — fail loudly rather than return
  # NA counts that read as "nothing to report."
  if (anyNA(df$outcome)) {
    stop("parity_headline(): outcome is NA for quantity(s) ",
         paste(df$quantity[is.na(df$outcome)], collapse = ", "),
         ". This is a programming error upstream in compare_parity(), ",
         "not a real comparison result.", call. = FALSE)
  }

  mx <- suppressWarnings(max(df$rel_diff, na.rm = TRUE))
  if (!is.finite(mx)) mx <- NA_real_

  if (isTRUE(mx == 0)) {
    warning("parity_headline(): max relative discrepancy is exactly zero ",
            "across ", nrow(df), " quantities. That is a signal that nothing ",
            "was really compared, not a success.", call. = FALSE)
  }

  list(
    n            = nrow(df),
    max_rel_diff = mx,
    n_pass       = sum(df$outcome == "PASS"),
    n_differs    = sum(df$outcome == "DIFFERS"),
    n_better     = sum(df$outcome == "R_BETTER")
  )
}

parity_badge <- function(df) {
  h <- parity_headline(df)
  sprintf(
    "**%d quantities compared — largest relative discrepancy %.2e.** PASS %d / DIFFERS %d / R_BETTER %d",
    h$n, h$max_rel_diff, h$n_pass, h$n_differs, h$n_better
  )
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript -e 'testthat::test_local("analyses/R_parity")'`

Expected: PASS — 20 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add analyses/R_parity/R/parity.R analyses/R_parity/tests/testthat/test-parity.R
git commit -m "feat: tolerance policy and parity comparison harness"
```

---

## Task 4: `.lst` parser access

**Files:**
- Modify: `analyses/R_parity/R/parity.R` (append)
- Test: `analyses/R_parity/tests/testthat/test-parse-lst.R`

**Interfaces:**
- Consumes: `lst_path()` from Task 2; the parser-access decision from Task 1
- Produces:
  - `parse_lst_env()` → an `environment` holding the sourced helper functions
  - `parse_lst(path, what, ...)` → the parsed object. `what` is one of `"fit"`, `"lifetable"`, `"nomogram"`. Returns whatever the underlying helper returns (`.hzr_parse_sas_lst` → list; `.hzr_parse_sas_lifetable` → `data.frame`; `.hzr_parse_sas_nomogram` → `data.frame` with columns `YEARS`, `MONTHS`, `SURVIV`, `CLLSURV`, `CLUSURV`, `HAZARD`, `CLLHAZ`, `CLUHAZ`). **Errors** if the helper returns `NULL`.

- [ ] **Step 1: Write the failing tests**

Create `analyses/R_parity/tests/testthat/test-parse-lst.R`:

```r
test_that("parse_lst_env exposes the SAS parsers", {
  e <- parse_lst_env()
  expect_true(is.environment(e))
  for (f in c(".hzr_parse_sas_lst", ".hzr_parse_sas_lifetable",
              ".hzr_parse_sas_nomogram")) {
    expect_true(exists(f, envir = e, inherits = FALSE), info = f)
  }
})

test_that("parse_lst reads the stage-2 fit from the real .lst", {
  fit <- parse_lst(lst_path("hz"), "fit")
  expect_true(is.list(fit))
  expect_false(is.null(fit))
})

test_that("parse_lst reads the stage-3 nomogram with the documented columns", {
  nom <- parse_lst(lst_path("hz"), "nomogram")
  expect_s3_class(nom, "data.frame")
  expect_true(all(c("YEARS", "SURVIV", "CLLSURV", "CLUSURV",
                    "HAZARD", "CLLHAZ", "CLUHAZ") %in% names(nom)))
  expect_gt(nrow(nom), 0L)
})

test_that("parse_lst errors rather than returning NULL when a table is absent", {
  # ac.dead_JR.lst has no parametric fit block.
  expect_error(parse_lst(lst_path("ac"), "fit"), "no .* table")
})

test_that("parse_lst rejects an unknown `what`", {
  expect_error(parse_lst(lst_path("hz"), "sandwich"), "unknown")
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'testthat::test_local("analyses/R_parity")'`

Expected: FAIL — `could not find function "parse_lst_env"`.

- [ ] **Step 3: Append the implementation to `R/parity.R`**

```r
# The .lst parsers are not exported and not in the TemporalHazard namespace.
# Upstream PR #108 moved them under inst/, so an installed package reaches them
# via system.file(). Before that they lived only in tests/testthat/, which
# R CMD INSTALL skips.
#
# Resolution order -- three routes, because a checkout can be either vintage:
#   1. system.file("sas-parity", "helper-sas-parity.R", package = "TemporalHazard")
#   2. $TEMPORAL_HAZARD_SRC/inst/sas-parity/helper-sas-parity.R   (post-#108)
#   3. $TEMPORAL_HAZARD_SRC/tests/testthat/helper-sas-parity.R    (pre-#108)
#
# Route 2 must be tried BEFORE route 3. In a post-#108 checkout the file at
# tests/testthat/helper-sas-parity.R is a *shim* that calls system.file() --
# sourcing it on a machine whose installed package lacks the parsers fails with
# a confusing error about the installed package, when a perfectly good copy is
# sitting in the checkout at inst/sas-parity/.
#
# Deliberately NOT gated on a version number. After upstream PR #109 renumbers
# 2.0.0 -> 1.2.0, two different packages both claim 1.2.0: main's without the
# parsers, dev's with them. Probe the file, never the version.
#
# We source rather than vendor a copy: a forked parser is how a validated
# parser rots, and with two copies a divergence shows up as both sides passing.

.parse_env <- new.env(parent = emptyenv())

# Which route resolved, for the report header. "The parsers were reachable"
# and "the parsers came from the version we think" are different claims.
parse_lst_source <- function() {
  parse_lst_env()
  get("route", envir = .parse_env)
}

parse_lst_env <- function() {
  if (exists("helpers", envir = .parse_env, inherits = FALSE)) {
    return(get("helpers", envir = .parse_env))
  }

  installed <- tryCatch(
    system.file("sas-parity", "helper-sas-parity.R", package = "TemporalHazard"),
    error = function(e) "")

  src <- Sys.getenv("TEMPORAL_HAZARD_SRC", unset = "")
  ck_inst <- if (nzchar(src)) {
    file.path(src, "inst", "sas-parity", "helper-sas-parity.R")
  } else ""
  ck_test <- if (nzchar(src)) {
    file.path(src, "tests", "testthat", "helper-sas-parity.R")
  } else ""

  th_ver <- tryCatch(as.character(utils::packageVersion("TemporalHazard")),
                     error = function(e) "not installed")

  if (nzchar(installed) && file.exists(installed)) {
    helper <- installed
    route  <- sprintf("installed TemporalHazard %s: %s", th_ver, installed)
  } else if (nzchar(ck_inst) && file.exists(ck_inst)) {
    helper <- ck_inst
    route  <- paste0("checkout inst/ (TEMPORAL_HAZARD_SRC): ", ck_inst)
  } else if (nzchar(ck_test) && file.exists(ck_test)) {
    helper <- ck_test
    route  <- paste0("checkout tests/ (TEMPORAL_HAZARD_SRC, pre-#108): ", ck_test)
  } else {
    stop("parse_lst_env(): SAS .lst parsers not found. Tried\n",
         "  1. system.file(\"sas-parity\", \"helper-sas-parity.R\", ",
         "package = \"TemporalHazard\") -> ",
         if (nzchar(installed)) installed else
           paste0("<empty; installed TemporalHazard is ", th_ver,
                  ", which ships no sas-parity/>"),
         "\n  2. $TEMPORAL_HAZARD_SRC/inst/sas-parity/helper-sas-parity.R -> ",
         if (nzchar(ck_inst)) ck_inst else "<TEMPORAL_HAZARD_SRC unset>",
         "\n  3. $TEMPORAL_HAZARD_SRC/tests/testthat/helper-sas-parity.R -> ",
         if (nzchar(ck_test)) ck_test else "<TEMPORAL_HAZARD_SRC unset>",
         "\nInstall the dev ref (install_github(\"ehrlinger/temporal_hazard@dev\")) ",
         "or point TEMPORAL_HAZARD_SRC at a temporal_hazard checkout. ",
         "See docs/preflight/SERVER-PREFLIGHT.md.",
         call. = FALSE)
  }

  e <- new.env(parent = globalenv())
  sys.source(helper, envir = e)
  assign("helpers", e, envir = .parse_env)
  assign("route", route, envir = .parse_env)
  e
}

parse_lst <- function(path, what, ...) {
  if (!file.exists(path)) {
    stop("parse_lst(): no such .lst: ", path, call. = FALSE)
  }
  e <- parse_lst_env()

  fn <- switch(what,
    fit       = get(".hzr_parse_sas_lst",       envir = e),
    lifetable = get(".hzr_parse_sas_lifetable", envir = e),
    nomogram  = get(".hzr_parse_sas_nomogram",  envir = e),
    stop("parse_lst(): unknown `what`: ", what,
         ". Expected fit, lifetable, or nomogram.", call. = FALSE)
  )

  out <- fn(path, ...)

  # Fail loud: the helpers return NULL when a table is absent, which would
  # otherwise propagate into compare_parity() as a silent skip.
  if (is.null(out)) {
    stop("parse_lst(): no ", what, " table found in ", basename(path),
         ". The parser returned NULL — either the table is genuinely absent ",
         "or the parser does not recognise this .lst vintage.", call. = FALSE)
  }
  out
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `TEMPORAL_HAZARD_SRC=<path from Task 1> Rscript -e 'testthat::test_local("analyses/R_parity")'`

Expected: PASS — 25 tests, 0 failures.

**If the nomogram or fit test fails with a parser error rather than a missing-file error:** this is the parser-generality finding the spec anticipated (§5.1). These `.lst` files are 2006–2009 vintage, older than the AVC/KUL captures the parsers were built against. Record the exact failure, fix it **in the `temporal_hazard` repo**, and open a PR there. Do not patch a copy in this study.

- [ ] **Step 5: Commit**

```bash
git add analyses/R_parity/R/parity.R analyses/R_parity/tests/testthat/test-parse-lst.R
git commit -m "feat: .lst parser access via sourced upstream helpers"
```

---

## Task 5: Data contract, manifest, and cohort gate

**Files:**
- Create: `analyses/R_parity/R/read_built.R`
- Test: `analyses/R_parity/tests/testthat/test-read-built.R`

**Interfaces:**
- Consumes: `sas_path()` from Task 2; `compare_parity()` from Task 3
- Produces:
  - `built_manifest()` → `data.frame` with columns `file`, `size_bytes`, `mtime`, `md5`
  - `read_built()` → `data.frame`, the labelled `built080426` dataset
  - `cohort_counts(d)` → `list(n = integer(1), n_events = integer(1), n_censored = integer(1))`
  - `assert_cohort(d)` → invisibly `TRUE`; **errors** if counts are not 3049 / 1032 / 2017

- [ ] **Step 1: Write the failing tests**

Create `analyses/R_parity/tests/testthat/test-read-built.R`:

```r
test_that("built_manifest pins file identity", {
  m <- built_manifest()
  expect_s3_class(m, "data.frame")
  expect_true(all(c("file", "size_bytes", "mtime", "md5") %in% names(m)))
  expect_equal(nrow(m), 1L)
  expect_true(nchar(m$md5) == 32L)
})

test_that("read_built returns the analysis dataset", {
  d <- read_built()
  expect_s3_class(d, "data.frame")
  expect_gt(nrow(d), 3000L)
})

test_that("read_built carries the variables all three stages need", {
  d <- read_built()
  needed <- c("iv_dead", "dead", "iu_dead", "il_dead", "ic_dead", "idead",
              "im_dead", "female", "hx_htn", "z_value", "plvmassi")
  expect_true(all(needed %in% tolower(names(d))),
              info = paste("missing:",
                           paste(setdiff(needed, tolower(names(d))), collapse = ", ")))
})

test_that("cohort_counts reproduces the .lst cohort", {
  cc <- cohort_counts(read_built())
  expect_equal(cc$n,          3049L)
  expect_equal(cc$n_events,   1032L)
  expect_equal(cc$n_censored, 2017L)
})

test_that("assert_cohort errors on a truncated cohort", {
  d <- read_built()
  expect_error(assert_cohort(d[seq_len(100), , drop = FALSE]), "cohort gate")
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'testthat::test_local("analyses/R_parity")'`

Expected: FAIL — `could not find function "built_manifest"`.

- [ ] **Step 3: Write the implementation**

Create `analyses/R_parity/R/read_built.R`:

```r
# Data contract.
#
# Source is built080426.sas7bdat -- built103006 already passed through vars.sas
# (Rajeswaran's email). We do not reimplement vars.sas: it is ~48KB of macro
# doing derivation, missing-value flagging and mean imputation, and porting it
# is a separate project. Reading the post-vars dataset isolates the question
# this pass is actually testing.
#
# These .sas7bdat files live on a mutable network share outside version
# control. built080426.sas7bdat was rewritten 2026-08-04 20:29 by the SAS run
# we validate against; nothing stops the next run rewriting it mid-analysis.
# Every stage records the manifest and refuses to straddle two dataset states.

BUILT_FILE <- "built080426.sas7bdat"

built_path <- function() sas_path("datasets", BUILT_FILE)

built_manifest <- function() {
  p <- built_path()
  if (!file.exists(p)) stop("built_manifest(): missing ", p, call. = FALSE)
  info <- file.info(p)
  data.frame(
    file       = BUILT_FILE,
    size_bytes = as.numeric(info$size),
    mtime      = format(info$mtime, "%Y-%m-%d %H:%M:%S"),
    md5        = unname(tools::md5sum(p)),
    stringsAsFactors = FALSE
  )
}

read_built <- function() {
  p <- built_path()
  d <- if (requireNamespace("hvtiRutilities", quietly = TRUE)) {
    # Carries SAS variable labels through; the .lst prints labels, not names.
    hvtiRutilities::read_clinical_data(p)
  } else {
    warning("hvtiRutilities unavailable; falling back to haven::read_sas(). ",
            "Variable labels and manifest helpers are not available.",
            call. = FALSE)
    haven::read_sas(p)
  }
  d <- as.data.frame(d)
  names(d) <- tolower(names(d))
  d
}

# The analysable cohort is defined by the stage-1 time/event pair. The .lst
# prints: 3049 observations, 1032 events, 2017 right censored.
cohort_counts <- function(d) {
  ok <- !is.na(d$iv_dead) & !is.na(d$dead)
  n  <- sum(ok)
  ev <- sum(d$dead[ok] == 1)
  list(n = as.integer(n),
       n_events = as.integer(ev),
       n_censored = as.integer(n - ev))
}

assert_cohort <- function(d) {
  cc  <- cohort_counts(d)
  want <- list(n = 3049L, n_events = 1032L, n_censored = 2017L)
  if (!identical(cc, want)) {
    stop("cohort gate: expected N=3049 / events=1032 / censored=2017, got ",
         "N=", cc$n, " / events=", cc$n_events, " / censored=", cc$n_censored,
         ". Stages 2-3 must not run on an unreconciled cohort.", call. = FALSE)
  }
  invisible(TRUE)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript -e 'testthat::test_local("analyses/R_parity")'`

Expected: PASS — 30 tests, 0 failures.

**If `cohort_counts` does not return 3049/1032/2017:** stop and diagnose before touching anything else. The likely causes, in order: (a) `built080426` differs from `built103006` on these columns — check with `hvtiRutilities::compare_datasets()`; (b) the analysable subset is defined by a different variable than `iv_dead`; (c) `dead` is coded other than 0/1. Record the finding; do not adjust the expected counts to match what you got.

- [ ] **Step 5: Commit**

```bash
git add analyses/R_parity/R/read_built.R analyses/R_parity/tests/testthat/test-read-built.R
git commit -m "feat: data contract, dataset manifest, and cohort gate"
```

---

## Task 6: Stage 1 — actuarial (`01-ac-dead.qmd`)

**Files:**
- Create: `analyses/R_parity/qmd/index.qmd`
- Create: `analyses/R_parity/qmd/01-ac-dead.qmd`

**Interfaces:**
- Consumes: `read_built()`, `assert_cohort()`, `built_manifest()` (Task 5); `compare_parity()`, `parity_badge()`, `parse_lst()` (Tasks 3–4); `lst_path()` (Task 2)
- Produces: `derive_cats(d)` → the input `data.frame` with integer columns `z_cat` and `lvm_cat` added (defined in `01-ac-dead.qmd`, reused by no later stage)

- [ ] **Step 1: Write `index.qmd`**

Create `analyses/R_parity/qmd/index.qmd`:

````markdown
# Overview

Parity validation of the AVR / LV-function survival study against its SAS
`PROC HAZARD` reference output, using the `TemporalHazard` R package.

**Study:** *Survival after valve replacement for aortic stenosis: implications
for decision making.* Mihaljevic T, Nowicki ER, Rajeswaran J, Blackstone EH,
Lagazzi L, Thomas J, Lytle BW, Cosgrove DM. J Thorac Cardiovasc Surg.
2008;135(6):1270-9.

## Job flow

| # | Stage | SAS program | R target | In this report |
|---|-------|-------------|----------|----------------|
| 1 | Actuarial | `distributions/ac.dead_JR.sas` | `hzr_kaplan()` | yes |
| 2 | Temporal hazard fit | `distributions/hz.dead_JR.sas` | `hazard()` | yes |
| 3 | Hazard figure | `graphs/hp.dead_JR.sas` | `predict()` | yes |
| 4 | Bagging | `analyses/bh.dead_s3_JR.sas` | `hzr_bootstrap()` | deferred |
| 5 | Multivariable | `analyses/hm.dead_s3_JR.sas` | `hazard()` | deferred |

## How to read the parity tables

Each stage reports the number of quantities compared and **the largest relative
discrepancy observed**. That number, not a pass badge, is the claim being made.

Tolerances are derived per quantity class, not tuned:

| Class | `atol` | `rtol` | Why |
|-------|--------|--------|-----|
| `exact` | 0 | 0 | counts — exact or it is a bug |
| `printed` | half-ULP of print | 0 | the `.lst` prints an interval, not a number |
| `optimizer` | 1e-6 | 1e-3 | R and SAS run different optimizers |
| `curvature` | 1e-6 | 1e-2 | standard errors come from a Hessian on both sides |

Outcomes are three-state. `R_BETTER` means R's log-likelihood exceeded SAS's
beyond tolerance — R's multi-start finding a better optimum is not a failure.

```{r}
#| label: env
#| code-fold: true
for (f in list.files("../R", pattern = "[.]R$", full.names = TRUE)) source(f)

data.frame(
  component = c("R", "TemporalHazard", "hvtiRutilities", "survival", "haven"),
  version = c(
    paste(R.version$major, R.version$minor, sep = "."),
    as.character(packageVersion("TemporalHazard")),
    tryCatch(as.character(packageVersion("hvtiRutilities")), error = function(e) "absent"),
    as.character(packageVersion("survival")),
    as.character(packageVersion("haven"))
  )
)
```

## Dataset

```{r}
#| label: manifest
knitr::kable(built_manifest())
```
````

- [ ] **Step 2: Write `01-ac-dead.qmd`**

Create `analyses/R_parity/qmd/01-ac-dead.qmd`:

````markdown
# Stage 1 — Actuarial

Reproduces `distributions/ac.dead_JR.sas`: seven `%KAPLAN` calls — overall,
stratified by `female`, stratified by `hx_htn`, and stratified by `z_cat`
within each of four `lvm_cat` strata.

This stage's survival numbers are the least interesting thing it produces. What
it actually tests is the data contract, the cohort gate, the `.lst` parser
against a 2006-vintage file, and the render.

```{r}
#| label: setup
for (f in list.files("../R", pattern = "[.]R$", full.names = TRUE)) source(f)
library(TemporalHazard)
d <- read_built()
```

## Cohort gate

```{r}
#| label: gate
assert_cohort(d)
cc <- cohort_counts(d)
gate <- compare_parity(
  quantity = c("n_analysable", "n_events", "n_censored"),
  r        = c(cc$n, cc$n_events, cc$n_censored),
  sas      = c(3049, 1032, 2017),
  class    = "exact"
)
knitr::kable(gate)
```

`assert_cohort()` errors if this does not hold, so a rendered report is itself
evidence the gate passed.

## Derived strata

The SAS derives `z_cat` and `lvm_cat` inline with cumulative overwrites. The
order matters, not just the cutpoints — each later condition overwrites the
earlier assignment.

```{r}
#| label: derive
derive_cats <- function(d) {
  d$z_cat <- 4L
  d$z_cat[!is.na(d$z_value) & d$z_value <  0.00] <- 3L
  d$z_cat[!is.na(d$z_value) & d$z_value < -0.60] <- 2L
  d$z_cat[!is.na(d$z_value) & d$z_value < -1.25] <- 1L

  d$lvm_cat <- 4L
  d$lvm_cat[!is.na(d$plvmassi) & d$plvmassi < 180] <- 3L
  d$lvm_cat[!is.na(d$plvmassi) & d$plvmassi < 150] <- 2L
  d$lvm_cat[!is.na(d$plvmassi) & d$plvmassi < 100] <- 1L
  d
}
d <- derive_cats(d)

knitr::kable(table(d$z_cat,   useNA = "ifany"))
knitr::kable(table(d$lvm_cat, useNA = "ifany"))
```

**Verify these cell counts against the `PROC FREQ` output in
`ac.dead_JR.lst` before reading anything below.** If the derivation is wrong,
every stratified survival estimate downstream is wrong in a way that still
looks plausible.

## Overall Kaplan–Meier

`hzr_kaplan()` takes vectors, not a formula with a `strata` term, so stratified
fits are computed by splitting the data and calling it per stratum.

```{r}
#| label: km-overall
ok  <- !is.na(d$iv_dead) & !is.na(d$dead)
km  <- hzr_kaplan(time = d$iv_dead[ok], status = d$dead[ok],
                  conf_level = 0.68268948)
head(km, 10)
```

The confidence level is SAS's `CLEVEL` default of `0.68268948` — one standard
deviation, not 95%. The paper states this explicitly: *"Uncertainty is expressed
by 68% confidence limits equivalent to ±1 standard error."*

## Parity against `ac.dead_JR.lst`

```{r}
#| label: km-parity
ref <- parse_lst(lst_path("ac"), "lifetable", which = "kaplan")
str(ref)
```

Align the R life table to the reference rows on the time column, then compare
the survival estimate and its standard error. The reference column names come
from the parser (`.hzr_parse_sas_lifetable` returns the `.lst` header verbatim);
inspect `names(ref)` above and map them to the `hzr_kaplan()` output columns
before writing the comparison.

```{r}
#| label: km-compare
#| eval: false
# Fill in the column names from the str() output above, then set eval: true.
cmp <- compare_parity(
  quantity = paste0("surv_t", ref$INT_DEAD),
  r        = km_matched$survival,
  sas      = ref$SURVIVAL,
  class    = "printed",
  printed_dp = 5
)
knitr::kable(cmp)
cat(parity_badge(cmp))
```

## Published cross-check

Independent of the `.lst` and of our parser: the paper reports non-risk-adjusted
survival of 97%, 93%, 91%, 75% and 47% at 30 days, 6 months, 1, 5 and 10 years.

```{r}
#| label: published
#| eval: false
grid <- c(30 / 365.2425, 0.5, 1, 5, 10)
# Read survival off km at these times and compare to c(97, 93, 91, 75, 47) / 100
# at whole-percent precision.
```
````

**Note on the two `eval: false` blocks:** these depend on the reference column
names, which are read off the `.lst` at runtime and cannot be known before the
parser runs on the server. Step 3 resolves them.

- [ ] **Step 3: Resolve the reference column names and enable the blocks**

Run: `TEMPORAL_HAZARD_SRC=<path> Rscript -e 'source("analyses/R_parity/R/paths.R"); source("analyses/R_parity/R/parity.R"); str(parse_lst(lst_path("ac"), "lifetable", which = "kaplan"))'`

Expected: a `data.frame` structure listing the SAS column names.

Using the real names, replace the placeholder column references in the
`km-compare` and `published` chunks and set both to `eval: true`. Add the
row-matching code that aligns `km` to `ref` on the time column.

- [ ] **Step 4: Render the stage and confirm it completes**

Run: `cd analyses/R_parity && TEMPORAL_HAZARD_SRC=<path> quarto render qmd/01-ac-dead.qmd`

Expected: renders without error; the parity table shows a non-zero max relative discrepancy.

- [ ] **Step 5: Commit**

```bash
git add analyses/R_parity/qmd/index.qmd analyses/R_parity/qmd/01-ac-dead.qmd
git commit -m "feat: stage 1 actuarial parity"
```

---

## Task 7: Stage 2 — temporal hazard fit (`02-hz-dead.qmd`)

The first real test. Six free parameters, interval-censored response, conservation of events on. Interval censoring has **no existing SAS parity fixture** — this is the first such check ever run.

**Files:**
- Create: `analyses/R_parity/qmd/02-hz-dead.qmd`

**Interfaces:**
- Consumes: `read_built()`, `assert_cohort()` (Task 5); `compare_parity()`, `parity_badge()`, `parse_lst()` (Tasks 3–4)
- Produces: an `.rds` at `analyses/R_parity/_output/fit_hz.rds` holding the fitted `hazard` object, consumed by Task 8

- [ ] **Step 1: Determine the parameter ordering in `theta`**

Before writing the fit, establish what `theta` positions mean. `hazard()` with `fit = FALSE` builds the model without optimising.

Run:

```bash
TEMPORAL_HAZARD_SRC=<path> Rscript -e '
source("analyses/R_parity/R/paths.R"); source("analyses/R_parity/R/read_built.R")
library(TemporalHazard); library(survival)
d <- read_built(); ok <- !is.na(d$iu_dead) & !is.na(d$idead)
m <- hazard(Surv(iu_dead, idead) ~ 1, data = d[ok, ], dist = "multiphase",
  phases = list(
    early = hzr_phase("cdf", t_half = 0.1573284, nu = 0.928347, m = 1.116333),
    late  = hzr_phase("g3", tau = 1, gamma = 1, alpha = 1, eta = 1.687817,
                      fixed = c("tau", "gamma", "alpha"))),
  fit = FALSE)
str(m, max.level = 1)
'
```

Expected: a `hazard` object. Read off the parameter names/order it reports. **Record the ordering in a comment in the `.qmd`.** The SAS-to-R mapping is fixed by `hzr_argument_mapping()`: SAS `THALF`/`NU`/`M` → `hzr_phase("cdf", t_half=, nu=, m=)`; SAS `TAU`/`GAMMA`/`ALPHA`/`ETA` → `hzr_phase("g3", tau=, gamma=, alpha=, eta=)`.

- [ ] **Step 2: Write `02-hz-dead.qmd`**

Create `analyses/R_parity/qmd/02-hz-dead.qmd`:

````markdown
# Stage 2 — Temporal hazard fit

Reproduces the `PROC HAZARD` call in `distributions/hz.dead_JR.sas`:

```sas
proc hazard data=built conserve p outhaz=outest steepest quasi mi=200 condition=14;
     event idead;
     icensor ic_dead=il_dead;
     time iu_dead;
     parms mue=0.08620027 thalf=0.1573284 nu=0.928347 m=1.116333
           mul=0.01358171 tau=1 fixtau alpha=1 fixalpha gamma=1 fixgamma
           eta=1.687817 weibull;
```

Two phases, no covariates. Six free parameters: `mue`, `thalf`, `nu`, `m`
(early) and `mul`, `eta` (late). `tau`, `alpha`, `gamma` are fixed at 1.

Two things make this the first genuinely new test in the pipeline. **Interval
censoring has no existing SAS parity fixture** — it is an open gap in
`DEVELOPMENT-PLAN.md` §7c, checked only against R-only invariants until now.
And **conservation of events is on**, which required two rounds of
reconciliation in prior parity work.

```{r}
#| label: setup
for (f in list.files("../R", pattern = "[.]R$", full.names = TRUE)) source(f)
library(TemporalHazard); library(survival)
d <- read_built(); assert_cohort(d)
```

## Does this fit actually exercise the interval-censoring path?

The `.lst` reports 2017 **right**-censored observations despite the `icensor`
statement. Establish whether the interval specification is doing any work here
before interpreting the fit.

```{r}
#| label: censoring
data.frame(
  n_rows          = nrow(d),
  n_il_nonmiss    = sum(!is.na(d$il_dead)),
  n_ic_nonmiss    = sum(!is.na(d$ic_dead)),
  n_il_lt_iu      = sum(d$il_dead < d$iu_dead, na.rm = TRUE),
  n_il_eq_iu      = sum(d$il_dead == d$iu_dead, na.rm = TRUE)
)
```

If `n_il_lt_iu` is zero, every record has a degenerate interval and the fit is
effectively right-censored — the interval path is declared but not exercised.
Say so plainly in the parity conclusion rather than claiming interval-censoring
coverage this fit does not provide.

## Fit A — deterministic, initialised at the SAS estimates

This is the like-for-like comparison. Starting from SAS's converged values
removes the optimiser's search path as a source of difference.

```{r}
#| label: fit-a
# theta ordering established in Task 7 Step 1 -- record it here.
ok <- !is.na(d$iu_dead) & !is.na(d$idead)
dd <- d[ok, ]

theta0 <- c(
  log(0.08620027),   # log mu, early
  log(0.1573284),    # log t_half, early
  0.928347,          # nu, early
  1.116333,          # m, early
  log(0.01358171),   # log mu, late
  1.687817           # eta, late
)

fit_a <- hazard(
  Surv(iu_dead, idead) ~ 1,
  data   = dd,
  dist   = "multiphase",
  phases = list(
    early = hzr_phase("cdf", t_half = 0.1573284, nu = 0.928347, m = 1.116333),
    late  = hzr_phase("g3", tau = 1, gamma = 1, alpha = 1, eta = 1.687817,
                      fixed = c("tau", "gamma", "alpha"))
  ),
  theta      = theta0,
  time_lower = dd$il_dead,
  fit        = TRUE,
  control    = list(n_starts = 1, maxit = 2000, conserve = TRUE)
)
summary(fit_a)
```

## Fit B — independent optimisation from rough starts

Reported alongside, **not** as the parity number. R's multi-start regularly
finds a better optimum than a single-start C optimiser; that is a different
question from whether the two agree.

```{r}
#| label: fit-b
old_seed <- if (exists(".Random.seed", .GlobalEnv)) .GlobalEnv$.Random.seed else NULL
set.seed(20260810)
fit_b <- hazard(
  Surv(iu_dead, idead) ~ 1,
  data   = dd,
  dist   = "multiphase",
  phases = list(
    early = hzr_phase("cdf", t_half = 0.2, nu = 1, m = 1),
    late  = hzr_phase("g3", tau = 1, gamma = 1, alpha = 1, eta = 1,
                      fixed = c("tau", "gamma", "alpha"))
  ),
  fit     = TRUE,
  control = list(n_starts = 5, maxit = 2000, conserve = TRUE)
)
if (!is.null(old_seed)) .GlobalEnv$.Random.seed <- old_seed
summary(fit_b)
```

## Parity

```{r}
#| label: ref
ref <- parse_lst(lst_path("hz"), "fit")
str(ref)
```

```{r}
#| label: ll-parity
#| eval: false
# Map the reference field names from the str() output above.
ll <- compare_parity("log_likelihood",
                     r = as.numeric(logLik(fit_a)), sas = ref$loglik,
                     class = "printed", printed_dp = 2,
                     higher_is_better = TRUE)
knitr::kable(ll)
```

```{r}
#| label: mle-parity
#| eval: false
mle <- compare_parity(
  quantity = c("mue", "thalf", "nu", "m", "mul", "eta"),
  r        = <R estimates on the SAS natural scale>,
  sas      = <ref estimates>,
  class    = "optimizer"
)
se <- compare_parity(
  quantity = paste0("se_", c("mue", "thalf", "nu", "m", "mul", "eta")),
  r        = <R standard errors>,
  sas      = <ref standard errors>,
  class    = "curvature"
)
all_cmp <- rbind(ll, mle, se)
knitr::kable(all_cmp)
cat(parity_badge(all_cmp))
```

**Reading a mismatch.** Near an optimum the log-likelihood is quadratic, so a
parameter error of ε costs the likelihood only O(ε²). The two disagreeing in
opposite directions tells you which problem you have:

| LL | Parameters | Interpretation |
|----|-----------|----------------|
| agrees | agree | parity |
| agrees tightly | one differs ~5% | flat direction — not an error |
| differs by ~10 | agree | structural problem — data, likelihood, or censoring |
| R higher | differ | R found a better optimum |

```{r}
#| label: save
dir.create("../_output", showWarnings = FALSE, recursive = TRUE)
saveRDS(fit_a, "../_output/fit_hz.rds")
```
````

- [ ] **Step 3: Resolve the reference field names and enable the parity blocks**

Run: `TEMPORAL_HAZARD_SRC=<path> Rscript -e 'source("analyses/R_parity/R/paths.R"); source("analyses/R_parity/R/parity.R"); str(parse_lst(lst_path("hz"), "fit"))'`

Expected: a list showing the parsed log-likelihood, parameter estimates and standard errors.

Fill the real field names into the `ll-parity` and `mle-parity` chunks and set both to `eval: true`. **The R estimates must be transformed to the same scale SAS reports** — `theta` holds `log(mu)` and `log(t_half)`, while the `.lst` prints `MUE` and `THALF` on the natural scale.

- [ ] **Step 4: Render and record the outcome**

Run: `cd analyses/R_parity && TEMPORAL_HAZARD_SRC=<path> quarto render qmd/02-hz-dead.qmd`

Expected: renders; parity table populated; headline discrepancy non-zero.

**If parity fails:** diagnose to a named cause before changing anything. Do not adjust `theta0`, tolerances, or `control` to make numbers agree. Record the finding — a documented gap is worth more than a forced match, and interval-censoring parity has never been checked before, so a genuine gap here is a result, not a setback.

- [ ] **Step 5: Commit**

```bash
git add analyses/R_parity/qmd/02-hz-dead.qmd
git commit -m "feat: stage 2 temporal hazard fit parity"
```

---

## Task 8: Stage 3 — hazard figure (`03-hp-dead.qmd`)

**Files:**
- Create: `analyses/R_parity/qmd/03-hp-dead.qmd`

**Interfaces:**
- Consumes: `_output/fit_hz.rds` (Task 7); `compare_parity()`, `parity_badge()`, `parse_lst()` (Tasks 3–4)
- Produces: three figures written under `analyses/R_parity/_output/`

- [ ] **Step 1: Write `03-hp-dead.qmd`**

Create `analyses/R_parity/qmd/03-hp-dead.qmd`:

````markdown
# Stage 3 — Hazard figure

Reproduces the digital nomogram and figures from `distributions/hz.dead_JR.sas`
and `graphs/hp.dead_JR.sas`. This stage consumes the stage-2 fit; if stage 2
failed parity, everything here is conditional on that discrepancy.

```{r}
#| label: setup
for (f in list.files("../R", pattern = "[.]R$", full.names = TRUE)) source(f)
library(TemporalHazard); library(ggplot2)
fit <- readRDS("../_output/fit_hz.rds")
```

## Prediction grid

The SAS builds its nomogram over an irregular grid:

```sas
do years=30/365.2425,3/12,6/12,1 to 10 by 1; output; end;
```

```{r}
#| label: grid
years <- c(30 / 365.2425, 3 / 12, 6 / 12, 1:10)
years
```

## Predictions

Two settings must be right or every number below mismatches. SAS's `CLEVEL`
default is `0.68268948` — one standard deviation, not 95%. And HAZPRED forms
survival confidence limits on the **logit** scale, where `predict.hazard()`
defaults to `"log-log"` (the `survfit` standard).

```{r}
#| label: predict
newd <- data.frame(time = years)

pred_surv <- predict(fit, newdata = newd, type = "survival",
                     se.fit = TRUE, level = 0.68268948,
                     conf.type = "logit")

pred_haz  <- predict(fit, newdata = newd, type = "hazard",
                     se.fit = TRUE, level = 0.68268948)

knitr::kable(cbind(years = years, pred_surv))
```

## Parity against the nomogram

```{r}
#| label: ref
ref <- parse_lst(lst_path("hz"), "nomogram")
knitr::kable(ref)
```

The parser returns columns `YEARS`, `MONTHS`, `SURVIV`, `CLLSURV`, `CLUSURV`,
`HAZARD`, `CLLHAZ`, `CLUHAZ` with the leading underscores stripped.

```{r}
#| label: nomogram-parity
#| eval: false
# Align on YEARS, then compare. Set eval: true once row alignment is confirmed.
cmp <- rbind(
  compare_parity(paste0("surv_y",   ref$YEARS), pred_surv$fit,   ref$SURVIV,  "printed", printed_dp = 5),
  compare_parity(paste0("cllsurv_y", ref$YEARS), pred_surv$lower, ref$CLLSURV, "curvature"),
  compare_parity(paste0("clusurv_y", ref$YEARS), pred_surv$upper, ref$CLUSURV, "curvature"),
  compare_parity(paste0("haz_y",    ref$YEARS), pred_haz$fit,    ref$HAZARD,  "printed", printed_dp = 5),
  compare_parity(paste0("cllhaz_y", ref$YEARS), pred_haz$lower,  ref$CLLHAZ,  "curvature"),
  compare_parity(paste0("cluhaz_y", ref$YEARS), pred_haz$upper,  ref$CLUHAZ,  "curvature")
)
knitr::kable(cmp)
cat(parity_badge(cmp))
```

## Published cross-check

```{r}
#| label: published
#| eval: false
pub <- data.frame(
  years = c(30 / 365.2425, 0.5, 1, 5, 10),
  published_pct = c(97, 93, 91, 75, 47)
)
# Compare round(100 * predicted survival) to published_pct at whole-percent
# precision. This is independent of both the .lst and our parser.
```

## Figures

Rebuilt in house style — the three PDFs in `graphs/` are a visual check, not a
numerical one. The numerical check is the nomogram table above.

```{r}
#| label: fig-survival
#| eval: false
p_surv <- ggplot(data.frame(years = years, s = pred_surv$fit,
                            lo = pred_surv$lower, hi = pred_surv$upper),
                 aes(years, 100 * s)) +
  geom_ribbon(aes(ymin = 100 * lo, ymax = 100 * hi), alpha = 0.2) +
  geom_line() +
  labs(x = "Years after operation", y = "Survival (%)",
       title = "Survival after AVR", subtitle = "Parametric estimate, 68% CL") +
  ylim(0, 100)
p_surv
ggsave("../_output/hp.dead_JR.survival.pdf", p_surv, width = 7, height = 5)
```

```{r}
#| label: fig-hazard
#| eval: false
p_haz <- ggplot(data.frame(years = years, h = pred_haz$fit),
                aes(years, h)) +
  geom_line() +
  labs(x = "Years after operation", y = "Hazard (deaths/patient-year)",
       title = "Hazard function for death after AVR")
p_haz
ggsave("../_output/hp.dead_JR.hazard.pdf", p_haz, width = 7, height = 5)
```

```{r}
#| label: fig-phases
#| eval: false
# Per-phase decomposition, matching hp.dead_JR's _earlyh / _lateh overlay.
dec <- predict(fit, newdata = newd, type = "hazard", decompose = TRUE)
p_ph <- ggplot(dec, aes(time, fit, colour = component)) +
  geom_line() +
  labs(x = "Years after operation", y = "Hazard",
       title = "Early and late hazard phases", colour = NULL)
p_ph
ggsave("../_output/hp.dead_JR.hazard_phases.pdf", p_ph, width = 7, height = 5)
```
````

- [ ] **Step 2: Confirm the `predict()` return shape and enable the blocks**

Run:

```bash
cd analyses/R_parity && TEMPORAL_HAZARD_SRC=<path> Rscript -e '
for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)
library(TemporalHazard)
fit <- readRDS("_output/fit_hz.rds")
p <- predict(fit, newdata = data.frame(time = c(1, 5, 10)), type = "survival",
             se.fit = TRUE, level = 0.68268948, conf.type = "logit")
str(p)
d <- predict(fit, newdata = data.frame(time = c(1, 5, 10)), type = "hazard",
             decompose = TRUE)
str(d)
'
```

Expected: `p` is a `data.frame` with `fit`, `se.fit`, `lower`, `upper`; `d` is a long frame with `time`, `component`, `fit`.

Adjust the column references in the chunks to match, then set `nomogram-parity`, `published`, `fig-survival`, `fig-hazard` and `fig-phases` to `eval: true`.

- [ ] **Step 3: Render and compare figures against the SAS PDFs**

Run: `cd analyses/R_parity && TEMPORAL_HAZARD_SRC=<path> quarto render qmd/03-hp-dead.qmd`

Expected: renders; nomogram parity table populated; three PDFs written to `_output/`.

Open `graphs/hp.dead_JR.survival.pdf`, `hp.dead_JR.hazard.pdf` and
`hp.dead_JR.hazard_phases.pdf` alongside the new ones. Shapes should agree; house
styling will differ by design.

- [ ] **Step 4: Commit**

```bash
git add analyses/R_parity/qmd/03-hp-dead.qmd
git commit -m "feat: stage 3 nomogram parity and figures"
```

---

## Task 9: Full render and parity summary

**Files:**
- Modify: `analyses/R_parity/qmd/index.qmd` (append a summary section)

**Interfaces:**
- Consumes: everything
- Produces: `analyses/R_parity/_output/` — the rendered report

- [ ] **Step 1: Run the full test suite**

Run: `TEMPORAL_HAZARD_SRC=<path> Rscript -e 'testthat::test_local("analyses/R_parity")'`

Expected: PASS, 0 failures. If any test fails, stop — a green report over a red suite is not a result.

- [ ] **Step 2: Render the whole project**

Run: `cd analyses/R_parity && TEMPORAL_HAZARD_SRC=<path> quarto render`

Expected: `_output/index.html` plus one page per stage, no errors.

- [ ] **Step 3: Append the cross-stage summary to `index.qmd`**

Add at the end of `analyses/R_parity/qmd/index.qmd`:

````markdown
## Result summary

| Stage | Quantities compared | Max relative discrepancy | Outcome |
|-------|--------------------|--------------------------|---------|
| 1 — actuarial | <n> | <max_rel_diff> | <PASS / DIFFERS> |
| 2 — hazard fit | <n> | <max_rel_diff> | <PASS / DIFFERS / R_BETTER> |
| 3 — nomogram | <n> | <max_rel_diff> | <PASS / DIFFERS> |

Fill from each stage's `parity_badge()` output after the full render.

### Findings

For each stage that did not report PASS, name the cause — **pipeline bug**,
**parser bug**, or **package gap** — and where it is tracked. A gap documented
as a gap is the deliverable; a number tuned into agreement is not.

### Interval-censoring coverage

State plainly whether stage 2 exercised the interval-censoring likelihood or
merely declared it, per the censoring diagnostic in that stage.

### For Rajeswaran

- `bh.dead_s3_JR.sas` uses `sle=0.07, sls=0.05`, but the paper states a
  P-value retention criterion of .05. Which describes the published run?
- The published Table 1 coefficients differ from the `parms` starting values in
  `hm.dead_s3_JR.sas`. Which run produced the publication?
````

- [ ] **Step 4: Snapshot the R environment**

Run on the server: `cd <study root> && Rscript -e 'renv::snapshot()'`

Expected: `renv.lock` gains `TemporalHazard`, `hvtiRutilities`, `haven`, `survival`, `ggplot2`, `testthat` and their dependencies. **This must run on the server** — snapshotting on a Mac records the wrong library.

- [ ] **Step 5: Commit**

```bash
git add analyses/R_parity/qmd/index.qmd renv.lock
git commit -m "feat: full render, cross-stage parity summary, renv snapshot"
```

- [ ] **Step 6: Report back**

Summarise for review: the three headline discrepancies, any stage that did not
PASS with its named cause, whether interval censoring was genuinely exercised,
and any parser fix that needs a PR against `temporal_hazard`.

---

## Spec coverage check

| Spec section | Task |
|--------------|------|
| §3 Layout | 2 |
| §4 Data contract | 5 |
| §4.1 Dataset manifest | 5 |
| §4.2 Cohort gate | 5, 6 |
| §5.1 Parsing | 4 |
| §5.2 / §5.2.1 Tolerance | 3 |
| §5.2.2 Headline metric | 3, 9 |
| §5.3 Published third reference | 6, 8 |
| §6.1 Stage 1 | 6 |
| §6.2 Stage 2 | 7 |
| §6.3 Stage 3 | 8 |
| §7 Success criteria | 9 |
| §9.2 Server audit | 1 |
| §9.3 Path portability | 2 |
| §9.4 renv snapshot | 9 |

**Deviation from spec §5.1:** the spec states parsers are reachable via
`TemporalHazard:::`. They are not — the installed package ships no `tests`
directory. Task 1 records the resolution and Task 4 implements it by sourcing
from a checkout. The upstream fix (move parsers to `inst/`) is raised as an
issue against `temporal_hazard`, not patched here.
