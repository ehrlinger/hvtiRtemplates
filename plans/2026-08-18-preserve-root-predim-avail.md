# preserve_root `predim_avail` Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reproduce the preserve_root `predim_avail` death chain (actuarial → hazard fit → nomogram) in R with `TemporalHazard`, and check every estimate against the committed SAS reference.

**Architecture:** Reusable machinery goes into the package that owns it — readers of `PROC HAZARD` output into `TemporalHazard`, environment and comparison utilities into `hvtiRutilities`, job templates into `hvtiRtemplates`. The study tree holds only a manifest of what to compare plus generated job files. Tasks 2–4 build machinery; 5–8 consume it and produce the parity answer; 9 generalises the job files into templates once two studies have exercised them. Task 1 shipped ahead of this plan and is now a verification step plus one open decision.

**Tech Stack:** R (>= 4.1), `TemporalHazard` (>= 1.2.0), `hvtiRutilities`, `haven`, `testthat` (3rd edition), Quarto, `hvtiPlotR`.

**Spec:** `specs/2026-08-18-preserve-root-predim-avail-parity-design.md` in this repository. Section references below (§N) are to that document.

## Global Constraints

- **No literal study path anywhere in R code or `.qmd`.** The study resolves to `/studies/...` on the RStudio server and to a local mount point on a Mac. Paths come from `study_root()` only. (§3.1)
- **No git in the study tree, and no commits on the share.** Git applies normally in the package repositories. (§3.2)
- **Read-only discipline:** nothing under the study's `R_hazard/` writes outside itself — not to `datasets/`, `distributions/`, `graphs/`, `estimates/`, nor to its parent `analyses/`. (§3)
- **No PHI** in any package, test, or fixture.
- **Versioning:** straight three digits, patch bumps only (`1.0.0 → 1.0.1`). Never a `.9000` suffix. Bump `DESCRIPTION` and `NEWS.md` together.
- **Cohort gate is exact and blocking:** N = 291, 77 events (72 uncensored + 5 interval-censored), 214 right-censored; `g_root3` cells 112 / 89 / 90. Stages 2–3 do not run if it misses. (§4.2)
- **`CLEVEL = 0.68268948`** — one standard deviation, not 95%. `hzr_kaplan()` defaults `conf_level = 0.95` and `predict.hazard()` defaults `level = 0.95`; both must be set explicitly on every call. (§7.3)
- **Survival confidence limits use `conf.type = "logit"`.** `predict.hazard()` defaults to `"log-log"`. (§7.3)
- **`control$conserve` defaults to `TRUE`.** The `noconserve` comparison must set it explicitly. (§7.2)
- **`compare_parity()` errors — never warns, never skips — when a requested quantity is absent on either side.** (§6.4)
- **A `tolerance = 0` literal must be written with 18 significant digits, not 17, and checked.** IEEE754 guarantees a double round-trips through 17, but R's parser does not deliver that here: the 17-digit form of one Task 3 value read back one ULP low and failed its own assertion. Write the literal with `sprintf("%.18g", x)` and confirm `identical(as.numeric(s), x)` before pasting it into a test. This applies to every machine-precision comparison in Tasks 3, 4 and 6–8, and to the reference values quoted in this plan — several of those are 17 digits and are **not** safe to paste.
- **Tolerances are derived, not tuned.** A failing comparison is diagnosed to a named cause before anything is adjusted. (§6.3, §9)

## Verified API surface

Confirmed against the installed `TemporalHazard` 1.2.0. Do not deviate without re-checking.

```r
hazard(formula, data, time, status, time_lower, time_upper, x, time_windows,
       theta, dist = "weibull", phases = NULL, fit = FALSE, weights = NULL,
       control = list(), ...)

hzr_phase(type = c("cdf", "hazard", "constant", "g3"),
          t_half = 1, nu = 1, m = 0, tau = 1, gamma = 1, alpha = 1, eta = 1,
          formula = NULL, fixed = character(0))

hzr_kaplan(time, status, conf_level = 0.95, event_only = TRUE)

predict(object, newdata = NULL,
        type = c("hazard", "linear_predictor", "survival", "cumulative_hazard"),
        decompose = FALSE, se.fit = FALSE, level = 0.95,
        conf.type = c("log-log", "logit"), ...)
```

- `type = "cdf"` is the early resolving phase (SAS `THALF`/`NU`/`M`); `type = "constant"` is the flat background rate (SAS `MUC`). `fixed = "m"` reproduces SAS `m=0 fixm`.
- Status coding: `1` exact event, `0` right-censored, `-1` left-censored, `2` interval-censored.
- `control` accepts `maxit`, `n_starts` (default 5), `reltol`, `abstol`, `method`, `condition` (default 14 — matches SAS `condition=14`), and `conserve` (default `TRUE`).
- SAS `.lst` parsers install at `system.file("sas-parity", "helper-sas-parity.R", package = "TemporalHazard")` and are loaded with `sys.source()` into an environment. Available: `.hzr_parse_sas_lst`, `.hzr_parse_sas_lifetable`, `.hzr_parse_sas_nomogram`, `.hzr_extract_loglik`, `.hzr_extract_natural`, `.hzr_extract_param_summary`, `.hzr_extract_matrix`, `.hzr_extract_obs_counts`, `.hzr_extract_events_conserved`, `.hzr_read_lst`.

---

## File structure

| Repository | File | Responsibility |
|---|---|---|
| `hvtiRutilities` | `R/study_paths.R` | locate a study tree with no literal prefix — **already shipped in 1.0.8** |
| `hvtiRutilities` | `R/preflight.R` | environment audit before any analysis |
| `hvtiRutilities` | `R/parity-tolerance.R` | the tolerance class table |
| `hvtiRutilities` | `R/parity-compare.R` | `compare_parity()`, `parity_headline()` |
| `TemporalHazard` | `R/read-outhaz.R` | read a SAS `outhaz` estimate dataset |
| study `R_hazard/R/` | `study.R` | cohort gate, `g_root3`, comparison manifest |
| study `R_hazard/qmd/` | `01-ac-dead_pa.qmd`, `02-hz-dead_pa.qmd`, `03-hp-dead_pa.qmd` | the analysis |
| study `R_hazard/parity/` | `0N-…-parity.qmd` | the comparison |
| `hvtiRtemplates` | `inst/templates/{ac,hz,hp}.qmd` | generalised job templates |
| `hvtiRtemplates` | `R/new-job.R` | `new_job()` scaffolding |

---

## Task 1: `study_root()` in hvtiRutilities — ALREADY SHIPPED

**Status (verified 2026-08-18): do not build this.** `study_root()` and `sas_path()`
are already exported from `hvtiRutilities` **1.0.8** on `main`, in `R/study_paths.R`.
They arrived with the Stage 1 provenance work, after this plan's first draft was
written. `sas_path()` is identical to what this task specified.

```bash
# Verification, the whole of this task:
Rscript -e 'stopifnot(all(c("study_root", "sas_path") %in% getNamespaceExports("hvtiRutilities")))'
```

### ✅ Resolved 2026-08-19: run `study_init()`; the shipped marker stands

| | this plan assumed | what shipped (1.0.8) |
|---|---|---|
| marker | the four sibling directories `datasets`, `distributions`, `graphs`, `analyses` | `_study.yml`, via `study_root() <- study_config(start)$root` |
| error names | `datasets, distributions, graphs, analyses` | the absent `_study.yml` |
| preserve_root before 2026-08-19 | resolves — all four directories are present | did not resolve — the tree had no `_study.yml` |
| preserve_root now | — | **resolves — `_study.yml` written by `study_init()` 2026-08-19** |

The two markers answer different questions. The structural one asks *does this
directory look like a SAS study*, and works on any legacy tree untouched. The
content one asks *was this study deliberately initialised*, and carries the study
identity, dataset checksum and cohort counts with it — but something must write it
first.

**Resolved: initialise the study rather than weaken the marker.** `study_init()`
was run against preserve_root on 2026-08-19
and `_study.yml` + `manifest.yaml` now sit at the study root. `study_root()` and
`sas_path()` resolve from `analyses/` and land on real `distributions/*.lst`
files; **Task 5 is unblocked** and no fallback was added to the package.

Three things measured during the decision, none of which this task's original
write-up had right:

- **No study on the share had ever been initialised** — `lv_function/survival`,
  the tree `study_init()` was designed against, has no `_study.yml` either. The
  content marker had zero adopters, so this was not preserve_root being the
  exception. preserve_root is now the first declared study.
- **The `_study.yml` cohort block is 378 / 115 / 263, not 291 / 77 / 214.**
  `cohort_counts()` derives from the whole of `built.sas7bdat`, while this
  plan's cohort is the `pr_avail == 1` subset. Both numbers are true and they
  answer different questions: study-level identity versus job-level analysable
  cohort. **The parity gate stays in Task 5's `assert_cohort_gate()`** — do not
  reach for `assert_cohort()` from the package, which would gate on 378.
- **`population` was wrong in the source it was copied from.** The SAS header
  `STUDYPOP = 2009 to 2021`, carried by 349 jobs, does not describe the
  operative window: `dt_surg` runs 2009-02-10 to 2019-12-23 study-wide and
  2009-03-20 to 2019-12-23 in the cohort, with `surg_yr` agreeing and no
  missing values. Nor is it the follow-up window — `dt_fsta` now reaches
  2023-12-22, because `built.sas7bdat` was rebuilt on 2026-06-09 with extended
  follow-up. `_study.yml` records the derived **2009 to 2019**. A checksum
  catches a dataset that moved; nothing catches a description that quietly
  stopped being true.

The plan's stated reason for passing `event`/`time` to `study_init()` was also
wrong: `cohort_counts()` does not hardcode them, it reads `cfg$cohort$event`
and `cfg$cohort$time`. They are passed because `study_init()` writes the very
manifest that would otherwise supply them.

**The constraint this task existed to serve is unchanged**: no literal study
path in any R file or `.qmd`.


---

## Task 2: `preflight_report()` in hvtiRutilities — DONE 2026-08-19

**Shipped as [hvtiRutilities #60](https://github.com/ehrlinger/hvtiRutilities/pull/60)** (base `main`), 4 tests / 7 expectations passing, `devtools::check()` 0 errors / 0 warnings / 1 NOTE. The NOTE is the untracked `.remember` session-tooling directory, which is not in this diff and fires on any branch of this repository; `.Rbuildignore` does not list it. No deviations from the steps below.

**Files:**
- Create: `~/Documents/GitHub/hvtiRutilities/R/preflight.R`
- Test: `~/Documents/GitHub/hvtiRutilities/tests/testthat/test-preflight.R`

**Interfaces:**
- Consumes: nothing.
- Produces: `preflight_report(extra = character(0))` → `data.frame` with columns `component` (character), `found` (logical), `version` (character), `notes` (character).

- [x] **Step 1: Branch**

```bash
cd ~/Documents/GitHub/hvtiRutilities && git checkout main && git pull --ff-only
git checkout -b feat/preflight-report
```

- [x] **Step 2: Write the failing test**

Create `tests/testthat/test-preflight.R`:

```r
test_that("preflight_report returns the documented shape", {
  out <- preflight_report()
  expect_s3_class(out, "data.frame")
  expect_named(out, c("component", "found", "version", "notes"))
  expect_type(out$found, "logical")
})

test_that("preflight_report always reports R itself and numDeriv", {
  out <- preflight_report()
  expect_true("R" %in% out$component)
  expect_true("numDeriv" %in% out$component)
})

test_that("numDeriv carries a note explaining why its absence matters", {
  out <- preflight_report()
  note <- out$notes[out$component == "numDeriv"]
  expect_match(note, "standard errors", fixed = TRUE)
})

test_that("extra packages are appended", {
  out <- preflight_report(extra = "utils")
  expect_true("utils" %in% out$component)
})
```

- [x] **Step 3: Run the test and confirm it fails**

```bash
cd ~/Documents/GitHub/hvtiRutilities && Rscript -e 'devtools::test(filter="preflight")'
```

Expected: FAIL — `could not find function "preflight_report"`.

- [x] **Step 4: Write the implementation**

Create `R/preflight.R`:

```r
#' Audit the analysis environment before running an analysis
#'
#' Reports the version of every package a hazard-family analysis depends on.
#' Run it on the machine that will do the work, before anything else.
#'
#' `numDeriv` is only a *Suggests* of `TemporalHazard`, so `install_github()`
#' does not pull it. Its absence silently costs standard errors on any
#' interval- or left-censored multiphase fit: the analytic multiphase Hessian
#' declines for those statuses by design and the optimizer falls back to
#' `numDeriv`; with it missing there is no third option, and `vcov()` returns a
#' bare logical while `rcond` and `pd` come back `NA` with nothing naming the
#' cause.
#'
#' @param extra Character vector of additional package names to report.
#' @return A data frame with columns `component`, `found`, `version`, `notes`.
#' @export
#' @examples
#' preflight_report()
preflight_report <- function(extra = character(0)) {
  pkgs <- c("TemporalHazard", "hvtiRutilities", "haven", "survival",
            "hvtiPlotR", "testthat", "quarto", "ggplot2", "numDeriv",
            extra)
  pkgs <- unique(pkgs)

  notes <- c(numDeriv = paste(
    "Suggests-only for TemporalHazard; absence silently costs standard",
    "errors on interval- or left-censored multiphase fits."
  ))

  rows <- lapply(pkgs, function(p) {
    v <- tryCatch(as.character(utils::packageVersion(p)),
                  error = function(e) NA_character_)
    data.frame(component = p,
               found     = !is.na(v),
               version   = if (is.na(v)) "" else v,
               notes     = if (p %in% names(notes)) notes[[p]] else "",
               stringsAsFactors = FALSE)
  })

  rbind(
    data.frame(component = "R",
               found     = TRUE,
               version   = paste(R.version$major, R.version$minor, sep = "."),
               notes     = "",
               stringsAsFactors = FALSE),
    do.call(rbind, rows)
  )
}
```

- [x] **Step 5: Run the tests**

```bash
cd ~/Documents/GitHub/hvtiRutilities && Rscript -e 'devtools::document(); devtools::test(filter="preflight")'
```

Expected: 4 PASS, 0 FAIL.

- [x] **Step 6: Bump the version and NEWS**

In `DESCRIPTION` change `Version: 1.0.8` to `Version: 1.0.9`. `NEWS.md` has no
title line — its first line is the newest version heading — so insert this at the
very top of the file, at heading level one to match the entries below it:

```markdown
# hvtiRutilities 1.0.9

## New features

- `preflight_report()` — environment audit naming every package a hazard-family
  analysis depends on, including `numDeriv`.
```

- [x] **Step 7: Full check, then commit**

```bash
cd ~/Documents/GitHub/hvtiRutilities && Rscript -e 'devtools::check()'
```

Expected: 0 errors, 0 warnings. Record any NOTE and confirm it predates this branch.

```bash
git add R/preflight.R man/preflight_report.Rd NAMESPACE tests/testthat/test-preflight.R DESCRIPTION NEWS.md
git commit -m "feat: add preflight_report(); bump to 1.0.9"
git push -u origin feat/preflight-report
gh pr create --title "feat: preflight_report()" --body "Environment audit for the SAS-to-R migration, generalised from the lv_function study. See hvtiRtemplates specs/2026-08-18-preserve-root-predim-avail-parity-design.md §3.1."
```

---

## Task 3: `hzr_read_outhaz()` in TemporalHazard — DONE 2026-08-18

**Shipped as [temporal_hazard #131](https://github.com/ehrlinger/temporal_hazard/pull/131)** (base `dev`), 13 tests, full suite 0 fail / 2049 pass. Two deviations from the steps below, both deliberate:

- **The fixture is synthetic, not cut from `hzdead_pa.sas7bdat`.** The PHI clearance in Step 1 is right as far as it goes — the dataset holds parameters, not patient rows — but `temporal_hazard` is a **public** repository and preserve_root is unpublished. So the layout is reproduced faithfully (17 rows, `NA`-status flag rows, fixed parameters holding zero-filled vcov rows and columns, the two vcov triangles written independently) and the values are invented from reciprocals of irrationals and primes. Generator at `data-raw/outhaz_fixture.R`, which is `.Rbuildignore`d. The parser was verified against the real `.sas7bdat` locally and nothing real was committed. **Tasks 6–8 must apply the same test to anything else they propose to commit.**
- **The test literals are 18 significant digits, not the 17 written below.** See the new global constraint.

Reads the SAS `outhaz` estimate dataset. It stores converged estimates and the full variance-covariance matrix at double precision, where the `.lst` prints seven figures — so it, not the printout, is the reference for every quantity it carries (§6.1). There are 69 such datasets across the three studies.

**Files:**
- Create: `~/Documents/GitHub/temporal_hazard/R/read-outhaz.R`
- Test: `~/Documents/GitHub/temporal_hazard/tests/testthat/test-read-outhaz.R`
- Create: `~/Documents/GitHub/temporal_hazard/inst/extdata/outhaz-fixture.rds`

**Interfaces:**
- Consumes: nothing.
- Produces: `hzr_read_outhaz(path)` → named list with elements `estimates` (named numeric), `status` (named integer; 1 free, 0 fixed), `vcov` (numeric matrix over free parameters only, dimnames set), `flags` (named numeric).

- [x] **Step 1: Branch and build a fixture that contains no PHI**

The `outhaz` dataset holds model parameters only — no patient rows — but the fixture is committed, so build it from the study file and verify its contents before writing it.

```bash
cd ~/Documents/GitHub/temporal_hazard && git checkout dev && git pull --ff-only
git checkout -b feat/read-outhaz
```

```r
# Run from inside the study tree so study_root() resolves.
src <- hvtiRutilities::sas_path("estimates", "hzdead_pa.sas7bdat")
d <- haven::read_sas(src)
stopifnot(nrow(d) == 17, "_NAME_" %in% names(d))
print(names(d))          # confirm: no patient identifiers
saveRDS(as.data.frame(d),
        "~/Documents/GitHub/temporal_hazard/inst/extdata/outhaz-fixture.rds")
```

- [x] **Step 2: Write the failing test**

Create `tests/testthat/test-read-outhaz.R`:

```r
fixture <- function() {
  system.file("extdata", "outhaz-fixture.rds", package = "TemporalHazard")
}

test_that("hzr_read_outhaz returns the four documented elements", {
  out <- hzr_read_outhaz(fixture())
  expect_named(out, c("estimates", "status", "vcov", "flags"))
})

test_that("estimates carry full double precision, not the .lst's 7 figures", {
  out <- hzr_read_outhaz(fixture())
  expect_equal(out$estimates[["THALF"]], 0.012336635510161828, tolerance = 0)
  expect_equal(out$estimates[["C0"]], -3.4853216662142557, tolerance = 0)
})

test_that("status marks free parameters 1 and fixed parameters 0", {
  out <- hzr_read_outhaz(fixture())
  expect_equal(unname(out$status[["THALF"]]), 1L)
  expect_equal(unname(out$status[["M"]]), 0L)
})

test_that("vcov covers only free parameters and is symmetric", {
  out <- hzr_read_outhaz(fixture())
  expect_setequal(rownames(out$vcov), c("THALF", "NU", "E0", "C0"))
  expect_equal(rownames(out$vcov), colnames(out$vcov))
  expect_equal(out$vcov, t(out$vcov))
  expect_equal(out$vcov[["THALF", "THALF"]], 0.33356641372425322, tolerance = 0)
})

test_that("a file that is not an outhaz dataset errors, naming the columns", {
  tmp <- withr::local_tempfile(fileext = ".rds")
  saveRDS(data.frame(a = 1), tmp)
  expect_error(hzr_read_outhaz(tmp), "_NAME_")
})
```

- [x] **Step 3: Run the test and confirm it fails**

```bash
cd ~/Documents/GitHub/temporal_hazard && Rscript -e 'devtools::test(filter="read-outhaz")'
```

Expected: FAIL — `could not find function "hzr_read_outhaz"`.

- [x] **Step 4: Write the implementation**

Create `R/read-outhaz.R`:

```r
#' Read a SAS `outhaz` estimate dataset
#'
#' `PROC HAZARD`'s `outhaz=` dataset stores the converged estimates and the
#' asymptotic variance-covariance matrix at full double precision, where the
#' printed `.lst` carries about seven significant figures. For any quantity the
#' dataset holds, it is the better parity reference: print precision stops
#' being the binding constraint and optimizer convergence takes over.
#'
#' The log-likelihood is *not* stored here; take it from the `.lst`.
#'
#' @param path Path to a `.sas7bdat` written by `outhaz=`, or to an `.rds`
#'   holding the same data frame.
#' @return A list with `estimates` (named numeric), `status` (named integer,
#'   1 free / 0 fixed), `vcov` (matrix over free parameters, dimnames set) and
#'   `flags` (named numeric of model-structure flags).
#' @export
#' @examples
#' f <- system.file("extdata", "outhaz-fixture.rds", package = "TemporalHazard")
#' if (nzchar(f)) str(hzr_read_outhaz(f))
hzr_read_outhaz <- function(path) {
  if (grepl("[.]rds$", path, ignore.case = TRUE)) {
    d <- readRDS(path)
  } else {
    if (!requireNamespace("haven", quietly = TRUE)) {
      stop("hzr_read_outhaz() needs the 'haven' package to read a .sas7bdat.",
           call. = FALSE)
    }
    d <- as.data.frame(haven::read_sas(path))
  }

  if (!all(c("_NAME_", "_EST_", "_STATUS_") %in% names(d))) {
    stop("hzr_read_outhaz(): '", path, "' is not an outhaz dataset -- it must ",
         "carry columns _NAME_, _EST_ and _STATUS_. Found: ",
         paste(names(d), collapse = ", "), call. = FALSE)
  }

  nm <- as.character(d[["_NAME_"]])
  est <- stats::setNames(as.numeric(d[["_EST_"]]), nm)
  st_raw <- suppressWarnings(as.integer(d[["_STATUS_"]]))

  # Rows with NA status are model-structure flags (G1FLAG, FIXDEL0, ...),
  # not parameters. They carry no estimate row in the vcov block.
  is_param <- !is.na(st_raw)
  status <- stats::setNames(st_raw[is_param], nm[is_param])
  flags <- est[!is_param]

  free <- names(status)[status == 1L]
  vcov <- as.matrix(d[match(free, nm), free, drop = FALSE])
  dimnames(vcov) <- list(free, free)
  storage.mode(vcov) <- "double"

  list(estimates = est[is_param], status = status, vcov = vcov, flags = flags)
}
```

- [x] **Step 5: Run the tests**

```bash
cd ~/Documents/GitHub/temporal_hazard && Rscript -e 'devtools::document(); devtools::test(filter="read-outhaz")'
```

Expected: 5 PASS, 0 FAIL. If the `vcov` symmetry test fails, print `d[match(free, nm), free]` and check whether SAS wrote the block transposed before changing the tolerance.

- [x] **Step 6: Commit and open the PR**

```bash
cd ~/Documents/GitHub/temporal_hazard
git add R/read-outhaz.R man/hzr_read_outhaz.Rd NAMESPACE tests/testthat/test-read-outhaz.R inst/extdata/outhaz-fixture.rds
git commit -m "feat: add hzr_read_outhaz() for full-precision parity references"
git push -u origin feat/read-outhaz
gh pr create --base dev --title "feat: hzr_read_outhaz()" --body "Reads outhaz estimate datasets, which store estimates and the full vcov at double precision where the .lst prints seven figures. 69 such datasets exist across the three prototype studies."
```

---

## Task 4: `compare_parity()` in hvtiRutilities

**Files:**
- Create: `~/Documents/GitHub/hvtiRutilities/R/parity-tolerance.R`
- Create: `~/Documents/GitHub/hvtiRutilities/R/parity-compare.R`
- Test: `~/Documents/GitHub/hvtiRutilities/tests/testthat/test-parity.R`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `parity_tolerance(class)` → list with `rtol`, `atol`. Valid classes: `"count"`, `"printed"`, `"loglik"`, `"mle_stored"`, `"mle_printed"`, `"vcov_stored"`, `"curvature"`.
  - `compare_parity(quantity, r, sas, class, source = "lst", digits = NA_integer_)` → one-row `data.frame` with columns `quantity`, `r`, `sas`, `source`, `abs_diff`, `rel_diff`, `rtol`, `atol`, `outcome`.
  - `parity_headline(df)` → single string.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-parity.R`:

```r
test_that("tolerance classes are the ones the design names", {
  expect_equal(parity_tolerance("count"), list(rtol = 0, atol = 0))
  expect_equal(parity_tolerance("loglik"), list(rtol = 0, atol = 0.0005))
  expect_equal(parity_tolerance("mle_stored"), list(rtol = 1e-6, atol = 1e-9))
  expect_equal(parity_tolerance("vcov_stored"), list(rtol = 1e-4, atol = 1e-9))
  expect_error(parity_tolerance("invented"), "invented")
})

test_that("agreement inside tolerance is PASS", {
  out <- compare_parity("mue", r = 0.1022604, sas = 0.1022604, class = "mle_printed")
  expect_equal(out$outcome, "PASS")
  expect_equal(out$abs_diff, 0)
})

test_that("disagreement beyond tolerance is DIFFERS", {
  out <- compare_parity("mue", r = 0.11, sas = 0.1022604, class = "mle_printed")
  expect_equal(out$outcome, "DIFFERS")
})

test_that("a log-likelihood higher than SAS beyond tolerance is R_BETTER", {
  out <- compare_parity("log_likelihood", r = -239.10, sas = -239.194, class = "loglik")
  expect_equal(out$outcome, "R_BETTER")
})

test_that("a log-likelihood lower than SAS beyond tolerance is DIFFERS", {
  out <- compare_parity("log_likelihood", r = -239.30, sas = -239.194, class = "loglik")
  expect_equal(out$outcome, "DIFFERS")
})

test_that("a missing value on either side errors and never returns a row", {
  expect_error(
    compare_parity("mue", r = NULL, sas = 0.1, class = "mle_printed"),
    "absent"
  )
  expect_error(
    compare_parity("mue", r = 0.1, sas = NA_real_, class = "mle_printed"),
    "absent"
  )
})

test_that("printed class derives its tolerance from the printed digits", {
  out <- compare_parity("surv_5yr", r = 0.75001, sas = 0.75, class = "printed",
                        digits = 2)
  expect_equal(out$atol, 0.005)
  expect_equal(out$outcome, "PASS")
})

test_that("parity_headline reports the largest relative discrepancy", {
  df <- rbind(
    compare_parity("a", 1.0000, 1.0, class = "mle_printed"),
    compare_parity("b", 1.0002, 1.0, class = "mle_printed")
  )
  expect_match(parity_headline(df), "2 compared quantities")
  expect_match(parity_headline(df), "2.00e-04")
})

test_that("parity_headline flags an all-zero discrepancy as suspicious", {
  df <- rbind(
    compare_parity("a", 1, 1, class = "mle_printed"),
    compare_parity("b", 2, 2, class = "mle_printed")
  )
  expect_match(parity_headline(df), "exactly zero", fixed = TRUE)
})
```

- [ ] **Step 2: Run the test and confirm it fails**

```bash
cd ~/Documents/GitHub/hvtiRutilities && Rscript -e 'devtools::test(filter="parity")'
```

Expected: FAIL — `could not find function "parity_tolerance"`.

- [ ] **Step 3: Write the tolerance table**

Create `R/parity-tolerance.R`:

```r
#' Tolerance classes for SAS parity comparison
#'
#' Tolerances are derived from what limits agreement for each quantity, not
#' tuned until things pass. Three regimes:
#'
#' * **Printed references are intervals, not numbers.** When SAS prints
#'   `-239.194`, the value that produced it lies in `[-239.1945, -239.1935)`.
#'   Half a unit in the last printed place is a floor that is derived.
#' * **Stored references carry machine precision**, so that floor does not
#'   apply. What remains is that two implementations run different optimizers
#'   on the same likelihood and converge to different points.
#' * **Counts are exact, or there is a bug.**
#'
#' @param class One of `"count"`, `"printed"`, `"loglik"`, `"mle_stored"`,
#'   `"mle_printed"`, `"vcov_stored"`, `"curvature"`.
#' @return A list with `rtol` and `atol`.
#' @export
#' @examples
#' parity_tolerance("loglik")
parity_tolerance <- function(class) {
  table <- list(
    count       = list(rtol = 0,     atol = 0),
    printed     = list(rtol = 0,     atol = NA_real_),  # set from digits
    loglik      = list(rtol = 0,     atol = 0.0005),
    mle_stored  = list(rtol = 1e-6,  atol = 1e-9),
    mle_printed = list(rtol = 1e-3,  atol = 1e-6),
    vcov_stored = list(rtol = 1e-4,  atol = 1e-9),
    curvature   = list(rtol = 1e-2,  atol = 1e-6)
  )
  if (!class %in% names(table)) {
    stop("parity_tolerance(): unknown class '", class, "'. Valid classes: ",
         paste(names(table), collapse = ", "), call. = FALSE)
  }
  table[[class]]
}
```

- [ ] **Step 4: Write the comparison**

Create `R/parity-compare.R`:

```r
#' Compare one R quantity against its SAS reference
#'
#' Errors — never warns, never skips — when the quantity is absent on either
#' side. A comparison that cannot fail is worse than no comparison.
#'
#' The outcome is three-state. `R_BETTER` fires only for a log-likelihood that
#' exceeds SAS's beyond tolerance: a multi-start optimizer regularly beats a
#' single-start one, and recording that as a failure would train the reader to
#' distrust a real improvement.
#'
#' @param quantity Name of the quantity, used in the report.
#' @param r Value computed in R.
#' @param sas Value from the SAS reference.
#' @param class Tolerance class; see [parity_tolerance()].
#' @param source Where the SAS value came from — `"lst"` or `"outhaz"`.
#' @param digits For `class = "printed"`, the number of decimal places the
#'   reference was printed to. The tolerance becomes half of the last place.
#' @return A one-row data frame.
#' @export
#' @examples
#' compare_parity("log_likelihood", r = -239.1941, sas = -239.194,
#'                class = "loglik")
compare_parity <- function(quantity, r, sas, class, source = "lst",
                           digits = NA_integer_) {
  absent <- function(x) is.null(x) || length(x) != 1L || is.na(x)
  if (absent(r) || absent(sas)) {
    stop("compare_parity(): '", quantity, "' is absent on ",
         if (absent(r)) "the R side" else "the SAS side",
         ". Every requested quantity must be present on both sides -- a ",
         "comparison that cannot fail is worse than no comparison.",
         call. = FALSE)
  }

  tol <- parity_tolerance(class)
  if (class == "printed") {
    if (is.na(digits)) {
      stop("compare_parity(): class 'printed' needs `digits`, the number of ",
           "decimal places '", quantity, "' was printed to.", call. = FALSE)
    }
    tol$atol <- 0.5 * 10^(-digits)
  }

  abs_diff <- abs(r - sas)
  rel_diff <- if (sas == 0) NA_real_ else abs_diff / abs(sas)
  within <- abs_diff <= tol$atol + tol$rtol * abs(sas)

  outcome <- if (within) {
    "PASS"
  } else if (identical(quantity, "log_likelihood") && r > sas) {
    "R_BETTER"
  } else {
    "DIFFERS"
  }

  data.frame(quantity = quantity, r = r, sas = sas, source = source,
             abs_diff = abs_diff, rel_diff = rel_diff,
             rtol = tol$rtol, atol = tol$atol, outcome = outcome,
             stringsAsFactors = FALSE)
}

#' Summarise a parity table as one reviewer-facing claim
#'
#' The headline, not the badge, is the claim to report. It is falsifiable and
#' independent of whatever thresholds were chosen. A maximum relative
#' discrepancy of exactly zero across many quantities is not a triumph — it
#' means nothing was really compared — so it is flagged rather than celebrated.
#'
#' @param df A data frame of [compare_parity()] rows.
#' @return A single string.
#' @export
#' @examples
#' parity_headline(compare_parity("a", 1.0001, 1, class = "mle_printed"))
parity_headline <- function(df) {
  n <- nrow(df)
  worst <- suppressWarnings(max(df$rel_diff, na.rm = TRUE))
  if (!is.finite(worst)) worst <- 0
  base <- sprintf("Across %d compared quantities, the largest relative discrepancy was %.2e.",
                  n, worst)
  if (worst == 0) {
    paste(base,
          "A maximum relative discrepancy of exactly zero is a warning sign,",
          "not a result -- check that the comparison is reaching real values.")
  } else {
    base
  }
}
```

- [ ] **Step 5: Run the tests**

```bash
cd ~/Documents/GitHub/hvtiRutilities && Rscript -e 'devtools::document(); devtools::test(filter="parity")'
```

Expected: 9 PASS, 0 FAIL.

- [ ] **Step 6: Bump, check and commit**

In `DESCRIPTION` change `Version: 1.0.9` to `Version: 1.0.10`. Add to the very top of `NEWS.md`:

```markdown
# hvtiRutilities 1.0.10

## New features

- `parity_tolerance()`, `compare_parity()` and `parity_headline()` — the
  comparison half of the SAS parity harness. `compare_parity()` errors when a
  quantity is absent on either side, and reports `PASS` / `DIFFERS` /
  `R_BETTER`.
```

```bash
cd ~/Documents/GitHub/hvtiRutilities && Rscript -e 'devtools::check()'
git add R/parity-tolerance.R R/parity-compare.R man/ NAMESPACE tests/testthat/test-parity.R DESCRIPTION NEWS.md
git commit -m "feat: add the parity comparison harness; bump to 1.0.10"
git push
```

---

## Task 5: study data contract

**Files:**
- Create: `<study>/analyses/R_hazard/R/study.R`
- Create: `<study>/analyses/R_hazard/.gitignore`
- Create: `<study>/analyses/R_hazard/_quarto.yml`

`<study>` is the preserve_root tree. **Never write its absolute path into any file** — every path is built with `sas_path()`.

**Interfaces:**
- Consumes: `study_root()`, `sas_path()` (shipped in `hvtiRutilities` 1.0.8; the root-marker question in Task 1 was resolved 2026-08-19 — preserve_root is initialised and this task is unblocked).
- Produces:
  - `read_preserve_root()` → labelled data frame filtered to `pr_avail == 1`.
  - `add_g_root3(d)` → the same frame with integer column `g_root3`.
  - `assert_cohort_gate(d)` → invisibly `TRUE`, or stops.

- [ ] **Step 1: Create the project scaffolding**

`<study>/analyses/R_hazard/.gitignore`:

```
_output/
.quarto/
*_files/
*.knit.md
*.rds
```

`<study>/analyses/R_hazard/_quarto.yml`:

```yaml
# A `default` project, not a `book`. The book format resolves its whole chapter
# manifest before rendering anything, so it refuses a single-file render while
# any listed chapter is missing. That is hostile to authoring one stage at a
# time. `default` renders whatever file it is handed.
project:
  type: default
  output-dir: _output
  render:
    - qmd/01-ac-dead_pa.qmd
    - qmd/02-hz-dead_pa.qmd
    - qmd/03-hp-dead_pa.qmd
    - parity/01-ac-dead_pa-parity.qmd
    - parity/02-hz-dead_pa-parity.qmd
    - parity/03-hp-dead_pa-parity.qmd

format:
  html:
    theme: cosmo
    toc: true
    toc-depth: 3
    code-fold: true
    # NOT df-print: paged -- it pulls a JS/CSS tree into <file>_files/, and
    # this renders onto a network share whose clients disagree about directory
    # contents, which makes Quarto's post-render cleanup fail. Every table here
    # goes through knitr::kable() anyway.
    df-print: default
    # Standalone HTML: the report gets sent to collaborators, and a file that
    # depends on a sibling _files/ directory does not survive that.
    embed-resources: true

execute:
  echo: true
  warning: true
  error: false
  freeze: false
```

- [ ] **Step 2: Write `R/study.R`**

```r
# Study-specific declarations for the preserve_root predim_avail death chain.
# This is the ONLY study-specific R in the project: a cohort gate, one derived
# variable, and the comparison manifest. All machinery comes from the packages.

library(hvtiRutilities)

#' Read the built dataset, filtered to the predim_avail cohort.
#'
#' `%vars` is deliberately not applied. The interval-censoring variables
#' (`iu_dead`, `il_dead`, `ic_dead`, `idead`, `im_dead`) are not defined
#' anywhere in `datasets/vars.sas`; they already exist in the built dataset.
#' The one cohort-dependent operation in that macro, `proc standard ...
#' replace`, is gated behind `%if &missing=1`, and the analysis programs call
#' bare `%vars;`, whose default is `missing=0`.
read_preserve_root <- function() {
  path <- sas_path("datasets", "built.sas7bdat")
  d <- hvtiRutilities::read_clinical_data(path)
  d[!is.na(d$pr_avail) & d$pr_avail == 1, , drop = FALSE]
}

#' Preoperative root diameter strata.
#'
#' Ported from `ac.dead_predim_avail.sas`, which initialises to missing and
#' assigns in ascending order. The `g_root1`/`g_root2` dummy pair in
#' `hz.dead_predim_avail.sas` uses the same cutpoints in a different shape;
#' this is the form the actuarial stage uses.
add_g_root3 <- function(d) {
  g <- rep(NA_integer_, nrow(d))
  g[!is.na(d$z0axdpr) & d$z0axdpr <= 40] <- 1L
  g[!is.na(d$z0axdpr) & d$z0axdpr > 40 & d$z0axdpr <= 45] <- 2L
  g[!is.na(d$z0axdpr) & d$z0axdpr > 45] <- 3L
  d$g_root3 <- g
  d
}

#' The cohort gate. Blocking: stages 2 and 3 do not run if this fails.
#'
#' A parity comparison on the wrong cohort produces a number that looks like an
#' answer.
assert_cohort_gate <- function(d) {
  n_total <- nrow(d)
  n_events <- sum(d$idead == 1, na.rm = TRUE)
  n_interval <- sum(d$ic_dead == 1, na.rm = TRUE)
  n_right <- n_total - n_events

  expected <- list(total = 291L, events = 77L, interval = 5L, right = 214L)
  actual <- list(total = n_total, events = n_events,
                 interval = n_interval, right = n_right)

  bad <- vapply(names(expected),
                function(k) !identical(as.integer(actual[[k]]),
                                       as.integer(expected[[k]])),
                logical(1))
  if (any(bad)) {
    stop("Cohort gate FAILED. Expected ",
         paste(sprintf("%s=%d", names(expected), unlist(expected)),
               collapse = ", "),
         "; got ",
         paste(sprintf("%s=%d", names(actual), unlist(actual)),
               collapse = ", "),
         ". Stages 2 and 3 must not run.", call. = FALSE)
  }
  invisible(TRUE)
}

#' Pin the dataset state. A parity result is only meaningful against a named,
#' pinned dataset -- `built.sas7bdat` is live and was rewritten 2026-06-09.
dataset_manifest <- function() {
  path <- sas_path("datasets", "built.sas7bdat")
  info <- file.info(path)
  data.frame(path = basename(path), size = info$size,
             mtime = format(info$mtime, "%Y-%m-%d %H:%M:%S"),
             md5 = tools::md5sum(path)[[1]],
             stringsAsFactors = FALSE)
}
```

- [ ] **Step 3: Run the gate against the real data**

On the RStudio server, from inside `<study>/analyses/R_hazard/`:

```r
source("R/study.R")
d <- add_g_root3(read_preserve_root())
assert_cohort_gate(d)
table(d$g_root3, useNA = "ifany")
```

Expected: `assert_cohort_gate()` returns invisibly, and the table prints `1: 112, 2: 89, 3: 90`.

**If the gate fails, stop.** Diagnose to a named cause before changing anything: dataset drift (§4.1), a wrong `pr_avail` filter, or a genuinely different cohort. Do not adjust the expected counts to match — they come from two independent `.lst` files that agree.

---

## Task 6: Stage 1 — actuarial

**Files:**
- Create: `<study>/analyses/R_hazard/qmd/01-ac-dead_pa.qmd`
- Create: `<study>/analyses/R_hazard/parity/01-ac-dead_pa-parity.qmd`

**Interfaces:**
- Consumes: `read_preserve_root()`, `add_g_root3()`, `assert_cohort_gate()`, `dataset_manifest()` (Task 5); `compare_parity()`, `parity_headline()`, `preflight_report()` (Tasks 2, 4).
- Produces: `_output/01-ac-dead_pa.html`, and an `.rds` of the fitted life tables at `_output/01-ac-life-tables.rds` for the parity document.

Stage 1 uses `iv_dead` / `dead` — **right-censored**, a different response from stage 2's interval-censored `iu_dead`/`idead`. A stage-1 pass says nothing about the fitting path.

- [ ] **Step 1: Write the analysis document**

`qmd/01-ac-dead_pa.qmd`:

````markdown
---
title: "Stage 1 — Actuarial, predim_avail death"
---

```{r}
#| label: setup
library(TemporalHazard)
library(hvtiRutilities)
source("../R/study.R")
knitr::kable(preflight_report())
knitr::kable(dataset_manifest())
```

## Cohort gate

```{r}
#| label: gate
d <- add_g_root3(read_preserve_root())
assert_cohort_gate(d)
knitr::kable(as.data.frame(table(g_root3 = d$g_root3, useNA = "ifany")))
```

## Overall life table

`conf_level` is set explicitly: `%KAPLAN` defaults to `CLEVEL = 0.68268948`,
one standard deviation, while `hzr_kaplan()` defaults to 0.95.

```{r}
#| label: overall
km_overall <- hzr_kaplan(time = d$iv_dead, status = d$dead,
                         conf_level = 0.68268948)
knitr::kable(utils::head(km_overall, 20))
```

## Stratified by preoperative root diameter

```{r}
#| label: stratified
km_strata <- lapply(sort(unique(stats::na.omit(d$g_root3))), function(g) {
  s <- d[!is.na(d$g_root3) & d$g_root3 == g, ]
  cbind(g_root3 = g,
        hzr_kaplan(time = s$iv_dead, status = s$dead,
                   conf_level = 0.68268948))
})
names(km_strata) <- sort(unique(stats::na.omit(d$g_root3)))
saveRDS(list(overall = km_overall, strata = km_strata),
        "../_output/01-ac-life-tables.rds")
```
````

- [ ] **Step 2: Render it**

```bash
cd <study>/analyses/R_hazard && quarto render qmd/01-ac-dead_pa.qmd
```

Expected: renders without error; the gate table shows 112 / 89 / 90.

- [ ] **Step 3: Write the parity document**

`parity/01-ac-dead_pa-parity.qmd`:

````markdown
---
title: "Stage 1 parity — actuarial vs ac.dead_predim_avail.lst"
---

```{r}
#| label: setup
library(hvtiRutilities)
source("../R/study.R")

helpers <- new.env()
h <- system.file("sas-parity", "helper-sas-parity.R", package = "TemporalHazard")
if (!nzchar(h)) {
  src <- Sys.getenv("TEMPORAL_HAZARD_SRC")
  h <- if (nzchar(src)) file.path(src, "tests", "testthat", "helper-sas-parity.R") else ""
}
if (!nzchar(h) || !file.exists(h)) {
  stop("SAS .lst parsers not found. Tried system.file('sas-parity', ",
       "'helper-sas-parity.R', package = 'TemporalHazard') and ",
       "Sys.getenv('TEMPORAL_HAZARD_SRC')/tests/testthat/helper-sas-parity.R.")
}
sys.source(h, helpers)
cat("parsers from:", h, "| TemporalHazard", as.character(packageVersion("TemporalHazard")), "\n")
```

::: callout-warning
`ac.dead_predim_avail.lst` is dated 2026-05-26; `built.sas7bdat` was rewritten
2026-06-09. This reference predates the dataset. Any discrepancy must consider
reference staleness as a candidate cause before it is attributed to
`TemporalHazard`. See §4.3.
:::

```{r}
#| label: compare-counts
lst <- helpers$.hzr_parse_sas_lifetable(sas_path("distributions", "ac.dead_predim_avail.lst"))
r <- readRDS("../_output/01-ac-life-tables.rds")
d <- add_g_root3(read_preserve_root())

# Cell counts are verified BEFORE any survival estimate is compared: the
# derivation being right is a precondition for the estimates meaning anything.
counts <- rbind(
  compare_parity("n_total",   nrow(d),                     291, class = "count"),
  compare_parity("n_events",  sum(d$dead == 1, na.rm = TRUE),  77, class = "count"),
  compare_parity("g_root3_1", sum(d$g_root3 == 1, na.rm = TRUE), 112, class = "count"),
  compare_parity("g_root3_2", sum(d$g_root3 == 2, na.rm = TRUE),  89, class = "count"),
  compare_parity("g_root3_3", sum(d$g_root3 == 3, na.rm = TRUE),  90, class = "count")
)
knitr::kable(counts)
stopifnot(all(counts$outcome == "PASS"))
```

```{r}
#| label: compare-survival
# Column mapping, verified against the .lst header:
#   hzr_kaplan()   SAS %KAPLAN    printed decimals
#   time           iv_dead        4
#   n_risk         NUMBER         exact
#   n_event        dead           exact
#   n_censor       CENSORED       exact
#   survival       CUM_SURV       5
#   std_err        SE_EXACT       6
#   cl_lower       CL_LOWER       5
#   cl_upper       CL_UPPER       5
#   cumhaz         CUM_HAZ        5
map <- list(
  list(r = "n_risk",   sas = "NUMBER",   class = "count",   digits = NA),
  list(r = "n_event",  sas = "dead",     class = "count",   digits = NA),
  list(r = "n_censor", sas = "CENSORED", class = "count",   digits = NA),
  list(r = "survival", sas = "CUM_SURV", class = "printed", digits = 5),
  list(r = "std_err",  sas = "SE_EXACT", class = "printed", digits = 6),
  list(r = "cl_lower", sas = "CL_LOWER", class = "printed", digits = 5),
  list(r = "cl_upper", sas = "CL_UPPER", class = "printed", digits = 5),
  list(r = "cumhaz",   sas = "CUM_HAZ",  class = "printed", digits = 5)
)

# Join on time. The .lst prints iv_dead to 4 decimals, so match on that.
rk <- as.data.frame(r$overall)
rk$key <- round(rk$time, 4)
lt <- as.data.frame(lst)
lt$key <- round(lt$iv_dead, 4)
j <- merge(rk, lt, by = "key", suffixes = c("_r", "_sas"))
stopifnot(nrow(j) > 0)

rows <- list()
for (i in seq_len(nrow(j))) {
  for (m in map) {
    rows[[length(rows) + 1L]] <- compare_parity(
      quantity = sprintf("%s@t=%.4f", m$r, j$key[i]),
      r = j[[m$r]][i], sas = j[[m$sas]][i],
      class = m$class, source = "lst", digits = m$digits
    )
  }
}
res_ac <- do.call(rbind, rows)
knitr::kable(utils::head(res_ac[res_ac$outcome != "PASS", ], 20))
table(res_ac$outcome)
```

```{r}
#| label: headline
cat(parity_headline(rbind(counts, res_ac)))
```
````

- [ ] **Step 4: Render and inspect**

```bash
cd <study>/analyses/R_hazard && quarto render parity/01-ac-dead_pa-parity.qmd
```

Expected: counts all PASS; `table(res_ac$outcome)` all PASS; the headline reports a non-zero maximum relative discrepancy. The parser was confirmed to return a 66-row data frame with the 14 documented columns on this `.lst`.

If it returns zero rows, that is a **finding about parser generality** (§6.2): report it, fix it in `TemporalHazard`, do not work around it here.

---

## Task 7: Stage 2 — the hazard fit

**Files:**
- Create: `<study>/analyses/R_hazard/qmd/02-hz-dead_pa.qmd`
- Create: `<study>/analyses/R_hazard/parity/02-hz-dead_pa-parity.qmd`

**Interfaces:**
- Consumes: Task 5 functions; `hzr_read_outhaz()` (Task 3); `compare_parity()` (Task 4).
- Produces: `_output/02-hz-fits.rds`, a list with elements `deterministic`, `multistart`, `noconserve`, each a fitted `hazard` object.

**The `parms` statement does not describe the fitted model.** It declares both `muc` and `eta ... weibull`; the `.lst` shows four fitted parameters with a **constant** late phase. Build the model from the `.lst`, never from `parms`. (§5.1)

- [ ] **Step 1: Write the analysis document**

`qmd/02-hz-dead_pa.qmd`:

````markdown
---
title: "Stage 2 — Temporal hazard fit, predim_avail death"
---

```{r}
#| label: setup
library(TemporalHazard)
library(hvtiRutilities)
source("../R/study.R")
d <- add_g_root3(read_preserve_root())
assert_cohort_gate(d)   # blocking -- stage 2 does not run on a wrong cohort
knitr::kable(dataset_manifest())
```

## Model

Four free parameters: three early (`E2`, `E3`, `E0`) and one constant (`C0`).
`m` is fixed at 0. `condition = 14` matches the SAS call.

```{r}
#| label: phases
phases <- list(
  early = hzr_phase("cdf", t_half = 0.0114, nu = 1.6, m = 0, fixed = "m"),
  late  = hzr_phase("constant")
)
```

Interval censoring: SAS `time iu_dead; icensor ic_dead=il_dead;` means `iu_dead`
is the upper bound, `il_dead` the lower, and `ic_dead` flags the interval. In R,
status 2 is interval-censored.

```{r}
#| label: response
status <- ifelse(d$ic_dead == 1 & !is.na(d$ic_dead), 2,
          ifelse(d$idead == 1, 1, 0))
lower <- ifelse(status == 2, d$il_dead, d$iu_dead)
upper <- d$iu_dead
```

### Fit 1 — deterministic, from the SAS starting values

This is the number that goes in the parity table.

```{r}
#| label: fit-deterministic
fit_det <- hazard(time_lower = lower, time_upper = upper, status = status,
                  dist = "multiphase", phases = phases, fit = TRUE,
                  control = list(conserve = TRUE, condition = 14, n_starts = 1))
summary(fit_det)
```

### Fit 2 — independent, multi-start

Answers *is SAS at the optimum*, which is a different question from *does R
agree with SAS*. Reported alongside, never as the parity number.

```{r}
#| label: fit-multistart
set.seed(20260818)
fit_ms <- hazard(time_lower = lower, time_upper = upper, status = status,
                 dist = "multiphase", phases = phases, fit = TRUE,
                 control = list(conserve = TRUE, condition = 14, n_starts = 5))
```

### Fit 3 — `noconserve` sensitivity

**This has no SAS reference.** The `.lst`'s second fit is *not* a `noconserve`
version of this model — it also adds a `G_ROOT` covariate to both phases and
fits 6 parameters (§5.4). Its LL of -239.019 confounds both changes, so it
cannot serve as a conservation target.

Reported as an R-only sensitivity: what conservation is worth on this fit.
`control$conserve` defaults to `TRUE`, so it must be set explicitly.

```{r}
#| label: fit-noconserve
fit_nc <- hazard(time_lower = lower, time_upper = upper, status = status,
                 dist = "multiphase", phases = phases, fit = TRUE,
                 control = list(conserve = FALSE, condition = 14, n_starts = 1))
```

```{r}
#| label: save
saveRDS(list(deterministic = fit_det, multistart = fit_ms, noconserve = fit_nc),
        "../_output/02-hz-fits.rds")
```

```{r}
#| label: conditioning
# N = 291 with 4 parameters is small-sample territory this package has not been
# exercised in. Report rcond and pd whatever they come out as. SAS reported
# log10(condition) = 1.225803, i.e. well conditioned.
v <- vcov(fit_det)
cat("rcond:", rcond(v), "\n")
cat("pd:", all(eigen(v, only.values = TRUE)$values > 0), "\n")
```
````

- [ ] **Step 2: Render it**

```bash
cd <study>/analyses/R_hazard && quarto render qmd/02-hz-dead_pa.qmd
```

Expected: three fits converge. If `vcov()` returns a bare logical and `rcond` is `NA`, check `preflight_report()` for `numDeriv` — that is the documented cause on an interval-censored fit.

- [ ] **Step 3: Write the parity document**

`parity/02-hz-dead_pa-parity.qmd`:

````markdown
---
title: "Stage 2 parity — hazard fit vs hz.dead_predim_avail.lst"
---

```{r}
#| label: setup
library(TemporalHazard)
library(hvtiRutilities)
source("../R/study.R")

helpers <- new.env()
h <- system.file("sas-parity", "helper-sas-parity.R", package = "TemporalHazard")
if (!nzchar(h)) {
  src <- Sys.getenv("TEMPORAL_HAZARD_SRC")
  h <- if (nzchar(src)) file.path(src, "tests", "testthat", "helper-sas-parity.R") else ""
}
if (!nzchar(h) || !file.exists(h)) stop("SAS .lst parsers not found; tried system.file() and TEMPORAL_HAZARD_SRC.")
sys.source(h, helpers)

fits <- readRDS("../_output/02-hz-fits.rds")
lst  <- helpers$.hzr_read_lst(sas_path("distributions", "hz.dead_predim_avail.lst"))
oh   <- hzr_read_outhaz(sas_path("estimates", "hzdead_pa.sas7bdat"))
```

The `.lst` and the `outhaz` dataset are two SAS references. **A disagreement
between them is itself a finding** — it means they came from different runs,
which is the staleness risk of §4.3.

```{r}
#| label: cross-check-references
# Fit 1 is the conserve, 4-parameter model -- the parity target. Fits 2 and 3
# are covariate models (6 and 8 parameters); see §5.4.
f1 <- lst$fits[[1]]
stopifnot(nrow(f1$params) == 4, f1$n_obs == 291, f1$n_events == 77)

nat <- f1$natural
ref_check <- do.call(rbind, lapply(c("THALF", "NU"), function(k) {
  compare_parity(paste0("ref_", k),
                 r = nat$estimate[nat$name == k],       # from the .lst
                 sas = oh$estimates[[k]],               # from outhaz
                 class = "printed", source = "lst-vs-outhaz", digits = 7)
}))
knitr::kable(ref_check)
if (any(ref_check$outcome != "PASS")) {
  stop("The .lst and outhaz disagree. They came from different runs; ",
       "resolve which is current before reading anything below (§4.3).")
}
```

```{r}
#| label: loglik
# The log-likelihood is not stored in outhaz; it comes from the .lst only.
res_ll <- compare_parity("log_likelihood",
                         r = as.numeric(logLik(fits$deterministic)),
                         sas = f1$loglik, class = "loglik", source = "lst")
knitr::kable(res_ll)

# The noconserve fit has no SAS reference (§5.4). Reported, not compared.
cat(sprintf("noconserve sensitivity: LL = %.4f (conserve: %.4f, difference %.4f)\n",
            as.numeric(logLik(fits$noconserve)),
            as.numeric(logLik(fits$deterministic)),
            as.numeric(logLik(fits$noconserve)) - as.numeric(logLik(fits$deterministic))))
```

```{r}
#| label: mles
# outhaz carries these at machine precision, so they use the tight class.
# Free parameters, from the .lst's natural-scale block: THALF, NU, MUE, MUC.
print(coef(fits$deterministic))   # confirm the R-side names once
free_nat <- nat$name[!nat$fixed]

# EDIT ONE LINE: fill in the R coefficient name for each SAS name, reading the
# printed coef() vector above. The SAS names and their outhaz values are fixed.
r_name_for <- c(THALF = "", NU = "", MUE = "", MUC = "")

res_mle <- do.call(rbind, lapply(free_nat, function(k) {
  in_outhaz <- k %in% names(oh$estimates)
  compare_parity(k,
    r = unname(coef(fits$deterministic)[r_name_for[[k]]]),
    sas = if (in_outhaz) oh$estimates[[k]] else nat$estimate[nat$name == k],
    class = if (in_outhaz) "mle_stored" else "mle_printed",
    source = if (in_outhaz) "outhaz" else "lst",
    digits = if (in_outhaz) NA_integer_ else 7)
}))
knitr::kable(res_mle)
```

```{r}
#| label: vcov
# The full 4x4 matrix -- a direct test of the Hessian under conservation, which
# needed two rounds of reconciliation in prior work. outhaz labels the free
# parameters THALF, NU, E0, C0.
v_r <- vcov(fits$deterministic)
v_s <- oh$vcov
stopifnot(is.matrix(v_r), nrow(v_r) == nrow(v_s))

# R and SAS order the free parameters the same way (early shapes, early mu,
# constant mu); assert it rather than assume, then compare the upper triangle.
res_vcov <- list()
for (i in seq_len(nrow(v_s))) {
  for (j in i:ncol(v_s)) {
    res_vcov[[length(res_vcov) + 1L]] <- compare_parity(
      sprintf("vcov[%s,%s]", rownames(v_s)[i], colnames(v_s)[j]),
      r = v_r[i, j], sas = v_s[i, j],
      class = "vcov_stored", source = "outhaz")
  }
}
res_vcov <- do.call(rbind, res_vcov)
knitr::kable(res_vcov)
```

```{r}
#| label: events-conserved
d <- add_g_root3(read_preserve_root())
status <- ifelse(d$ic_dead == 1 & !is.na(d$ic_dead), 2,
          ifelse(d$idead == 1, 1, 0))
res_events <- compare_parity("events_conserved",
                             r = sum(status %in% c(1, 2)),
                             sas = f1$events_conserved, class = "count")
knitr::kable(res_events)
```

```{r}
#| label: headline
all_results <- rbind(ref_check, res_ll, res_mle, res_vcov, res_events)
knitr::kable(as.data.frame(table(outcome = all_results$outcome)))
cat(parity_headline(all_results))
```
````

- [ ] **Step 4: Render and complete the marked chunks**

```bash
cd <study>/analyses/R_hazard && quarto render parity/02-hz-dead_pa-parity.qmd
```

One line needs completing — `r_name_for`, mapping SAS parameter names onto R coefficient names — from the `coef()` vector the document prints. Everything else is executable as written.

Expected: `log_likelihood` PASS or `R_BETTER`; MLEs and vcov PASS.

**If the tight `outhaz` tolerances fail, that is a result, not a provocation to loosen them.** It localises the disagreement to the optimizer. Re-run the same quantities at `class = "mle_printed"` alongside and report both.

---

## Task 8: Stage 3 — nomogram and figures

**Files:**
- Create: `<study>/analyses/R_hazard/qmd/03-hp-dead_pa.qmd`
- Create: `<study>/analyses/R_hazard/parity/03-hp-dead_pa-parity.qmd`

**Interfaces:**
- Consumes: `_output/02-hz-fits.rds` (Task 7).
- Produces: `_output/03-hp-predictions.rds`, a data frame with columns `years`, `digital` (logical), `survival`, `surv_lower`, `surv_upper`, `hazard`, `haz_lower`, `haz_upper`.

- [ ] **Step 1: Write the analysis document**

`qmd/03-hp-dead_pa.qmd`:

````markdown
---
title: "Stage 3 — Nomogram and figures, predim_avail death"
---

```{r}
#| label: setup
library(TemporalHazard)
library(hvtiRutilities)
library(hvtiPlotR)
source("../R/study.R")
fits <- readRDS("../_output/02-hz-fits.rds")
fit <- fits$deterministic
```

Two settings must be right or everything mismatches. `%hazplot` defaults to
`CLEVEL = 0.68268948`, one standard deviation. `HAZPRED` uses a **logit**
transform for survival confidence limits, while `predict.hazard()` defaults to
`"log-log"`.

```{r}
#| label: grids
CLEVEL <- 0.68268948

# Curve grid: 1000 points log-spaced, as the SAS builds it.
curve_grid <- data.frame(years = exp(seq(-5, log(10), length.out = 1000)),
                         digital = FALSE)

# Digital nomogram: the published grid.
digital_grid <- data.frame(years = c(30 / 365.2425, 0.25, 0.5, 1:10),
                           digital = TRUE)

grid <- rbind(curve_grid, digital_grid)
```

```{r}
#| label: predict
# With se.fit = TRUE, predict.hazard() returns a data frame with columns
# fit, se.fit, lower, upper.
srv <- predict(fit, newdata = grid, type = "survival", se.fit = TRUE,
               level = CLEVEL, conf.type = "logit")
haz <- predict(fit, newdata = grid, type = "hazard", se.fit = TRUE,
               level = CLEVEL)
stopifnot(all(c("fit", "se.fit", "lower", "upper") %in% names(srv)))

predictions <- data.frame(
  years      = grid$years,
  digital    = grid$digital,
  survival   = srv$fit,
  surv_lower = srv$lower,
  surv_upper = srv$upper,
  hazard     = haz$fit,
  haz_lower  = haz$lower,
  haz_upper  = haz$upper
)
knitr::kable(predictions[predictions$digital, ], digits = 5)
```

```{r}
#| label: save
saveRDS(predictions, "../_output/03-hp-predictions.rds")
```

```{r}
#| label: figures
# A VISUAL check against the existing PDFs in graphs/. The numerical check is
# the nomogram table in the parity document.
#
# hv_hazard() is the curve plotter -- despite the name it takes any curve frame
# via estimate_col, so it draws both panels.
curves <- predictions[!predictions$digital, ]

hv_hazard(curves, x_col = "years", estimate_col = "survival",
          lower_col = "surv_lower", upper_col = "surv_upper")

hv_hazard(curves, x_col = "years", estimate_col = "hazard",
          lower_col = "haz_lower", upper_col = "haz_upper")
```
````

- [ ] **Step 2: Render, complete the marked chunks, re-render**

```bash
cd <study>/analyses/R_hazard && quarto render qmd/03-hp-dead_pa.qmd
```

- [ ] **Step 3: Write the parity document**

`parity/03-hp-dead_pa-parity.qmd`:

````markdown
---
title: "Stage 3 parity — nomogram vs hp.dead_predim_avail.lst"
---

```{r}
#| label: setup
library(hvtiRutilities)
source("../R/study.R")
helpers <- new.env()
h <- system.file("sas-parity", "helper-sas-parity.R", package = "TemporalHazard")
if (!nzchar(h)) {
  src <- Sys.getenv("TEMPORAL_HAZARD_SRC")
  h <- if (nzchar(src)) file.path(src, "tests", "testthat", "helper-sas-parity.R") else ""
}
if (!nzchar(h) || !file.exists(h)) stop("SAS .lst parsers not found; tried system.file() and TEMPORAL_HAZARD_SRC.")
sys.source(h, helpers)

pred <- readRDS("../_output/03-hp-predictions.rds")
nom  <- helpers$.hzr_parse_sas_nomogram(sas_path("graphs", "hp.dead_predim_avail.lst"))
```

::: callout-warning
`hp.dead_predim_avail.lst` is dated 2026-05-06 against a dataset rewritten
2026-06-09. Reference staleness is a candidate cause for any discrepancy (§4.3).

This stage consumes the stage-2 fit. If stage 2 did not reach parity, these
results are **conditional on that discrepancy**.
:::

```{r}
#| label: compare-nomogram
# The parser returns 13 rows with columns YEARS, SURVIV, CLLSURV, CLUSURV,
# HAZARD, CLLHAZ, CLUHAZ -- exactly the digital grid, all printed to 5 decimals.
nom <- as.data.frame(nom)
digital <- pred[pred$digital, ]
stopifnot(nrow(nom) == 13, nrow(digital) == 13)

nom$key <- round(nom$YEARS, 4)
digital$key <- round(digital$years, 4)
j <- merge(digital, nom, by = "key")
stopifnot(nrow(j) == 13)

map <- list(
  list(r = "survival",   sas = "SURVIV"),
  list(r = "surv_lower", sas = "CLLSURV"),
  list(r = "surv_upper", sas = "CLUSURV"),
  list(r = "hazard",     sas = "HAZARD"),
  list(r = "haz_lower",  sas = "CLLHAZ"),
  list(r = "haz_upper",  sas = "CLUHAZ")
)

rows <- list()
for (i in seq_len(nrow(j))) {
  for (m in map) {
    rows[[length(rows) + 1L]] <- compare_parity(
      sprintf("%s@t=%.4f", m$r, j$key[i]),
      r = j[[m$r]][i], sas = j[[m$sas]][i],
      class = "printed", source = "lst", digits = 5)
  }
}
res_hp <- do.call(rbind, rows)
knitr::kable(as.data.frame(table(outcome = res_hp$outcome)))
knitr::kable(utils::head(res_hp[res_hp$outcome != "PASS", ], 20))
```

```{r}
#| label: headline
cat(parity_headline(res_hp))
```
````

- [ ] **Step 4: Render, complete, re-render**

```bash
cd <study>/analyses/R_hazard && quarto render parity/03-hp-dead_pa-parity.qmd
```

`.hzr_parse_sas_nomogram()` was confirmed to return 13 rows on this `.lst`, despite it having no `MONTHS` column — the parser gap found in a prior study is fixed. If it returns zero rows, that is a parser-generality finding to fix upstream in `TemporalHazard`, not to work around here.

- [ ] **Step 5: Render the whole project**

```bash
cd <study>/analyses/R_hazard && quarto render
```

Expected: all six documents render. This is the deliverable.

---

## Task 9: generalise into `hvtiRtemplates`

Two studies have now exercised these job shapes. What differs between them is the abstraction information; what is identical is the template.

**Files:**
- Create: `~/Documents/GitHub/hvtiRtemplates/inst/templates/ac.qmd`, `hz.qmd`, `hp.qmd`
- Create: `~/Documents/GitHub/hvtiRtemplates/R/new-job.R`
- Test: `~/Documents/GitHub/hvtiRtemplates/tests/testthat/test-new-job.R`
- Modify: `DESCRIPTION`, `NEWS.md`, `inst/templates/README.md`

**Interfaces:**
- Consumes: `template_path(name)`, `template_list()` (existing exports).
- Produces: `new_job(prefix, basename, dir = "qmd")` → the path of the file written.

- [ ] **Step 1: Branch and diff the two studies' job files**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git checkout main && git pull --ff-only
git checkout -b feat/job-templates
```

Diff each preserve_root stage document against the corresponding lv_function `example-jobs/*.qmd`. Every line that differs is a candidate for `# EDIT:`; every line that matches is template body. Record the count of each in the PR description.

- [ ] **Step 2: Write the failing test**

Create `tests/testthat/test-new-job.R`:

```r
test_that("template_list reports the three job templates", {
  tl <- template_list()
  expect_true(all(c("ac", "hz", "hp") %in% tl$prefix))
})

test_that("every template is free of study identifiers", {
  for (p in c("ac", "hz", "hp")) {
    txt <- readLines(template_path(p), warn = FALSE)
    expect_false(any(grepl("/studies/|preserve_root|lv_function|built[.]sas7bdat",
                           txt)),
                 label = paste("template", p, "carries a study identifier"))
  }
})

test_that("new_job writes a file and returns its path", {
  dir <- withr::local_tempdir()
  out <- new_job("hz", "dead_pa", dir = dir)
  expect_true(file.exists(out))
  expect_match(out, "hz[.]dead_pa[.]qmd$")
})

test_that("new_job refuses an unknown prefix, naming the valid ones", {
  dir <- withr::local_tempdir()
  expect_error(new_job("zz", "x", dir = dir), "ac, hp, hz")
})

test_that("new_job refuses to overwrite an existing job", {
  dir <- withr::local_tempdir()
  new_job("ac", "dead", dir = dir)
  expect_error(new_job("ac", "dead", dir = dir), "already exists")
})
```

- [ ] **Step 3: Run the test and confirm it fails**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && Rscript -e 'devtools::test(filter="new-job")'
```

Expected: FAIL — `could not find function "new_job"`.

- [ ] **Step 4: Write the templates and `new_job()`**

Copy each preserve_root stage document to `inst/templates/<prefix>.qmd`, replacing every study-specific value with a `# EDIT:` marker. The cohort gate numbers, the `g_root3` cutpoints, the SAS `.lst` filenames and the starting values are all study-specific; the structure, the explicit `conf_level`/`level`/`conf.type` settings and the parser-resolution block are not.

Create `R/new-job.R`:

```r
#' Scaffold a new analysis job from a template
#'
#' @param prefix Job type: one of the prefixes reported by [template_list()].
#' @param basename Job name, appended after the prefix.
#' @param dir Directory to write into.
#' @return The path written, invisibly.
#' @export
#' @examples
#' new_job("ac", "dead", dir = tempdir())
new_job <- function(prefix, basename, dir = "qmd") {
  valid <- sort(unique(template_list()$prefix))
  if (!prefix %in% valid) {
    stop("new_job(): unknown prefix '", prefix, "'. Valid prefixes: ",
         paste(valid, collapse = ", "), call. = FALSE)
  }
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  out <- file.path(dir, paste0(prefix, ".", basename, ".qmd"))
  if (file.exists(out)) {
    stop("new_job(): '", out, "' already exists; refusing to overwrite.",
         call. = FALSE)
  }
  file.copy(template_path(prefix), out)
  invisible(out)
}
```

- [ ] **Step 5: Run the tests**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && Rscript -e 'devtools::document(); devtools::test(filter="new-job")'
```

Expected: 5 PASS, 0 FAIL.

- [ ] **Step 6: Prove the abstraction by regenerating a study job**

```r
# From inside <study>/analyses/R_hazard/
hvtiRtemplates::new_job("hz", "regen_check", dir = tempdir())
```

Diff the generated file against `qmd/02-hz-dead_pa.qmd`. Every difference must be an `# EDIT:` line. **A component that cannot serve both studies is not finished.**

- [ ] **Step 7: Bump, check and open the PR**

Set `Version: 1.0.1` in `DESCRIPTION`, add the matching `NEWS.md` entry, and replace `inst/templates/README.md`'s "Empty until stage 3" text.

```bash
cd ~/Documents/GitHub/hvtiRtemplates && Rscript -e 'devtools::check()'
git add -A && git commit -m "feat: add ac/hz/hp job templates and new_job(); bump to 1.0.1"
git push -u origin feat/job-templates
gh pr create --title "feat: job templates and new_job()" --body "Stage 3 of the templates-and-provenance design, with two consumers behind it."
```

---

## Definition of done

| # | Criterion | Where verified |
|---|---|---|
| 1 | Cohort gate 291 / 77 (72 + 5) / 214 and `g_root3` 112 / 89 / 90, exact | Task 5 Step 3, Task 6 |
| 2 | Stage 1 life-table quantities match to print precision | Task 6 |
| 3 | Stage 2 log-likelihood matches -239.194; MLEs match `outhaz` | Task 7 |
| 4 | Stage 2 4x4 vcov matches `outhaz` | Task 7 |
| 5 | `noconserve` reported as an R-only sensitivity, with no PASS/FAIL claimed (§5.4) | Task 7 |
| 6 | Stage 3 nomogram and confidence limits match to ~1e-4 | Task 8 |
| 7 | Every stage reports its max relative discrepancy, **non-zero** | Tasks 6–8 |
| 8 | `.lst` and `outhaz` agree wherever both carry a quantity | Task 7 |
| 9 | A regenerated job differs from the study's only at `# EDIT:` lines | Task 9 Step 6 |

Any failure is diagnosed to a **named cause** — pipeline bug, parser bug, package gap, or reference staleness — before anything is adjusted. Gaps are documented as gaps. Numbers are never forced to match by tuning tolerances or starting values.
