# Maze Hazard Chain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run an `ac` → `hz` → `hp` job chain plus a parity check in
`maze/atricure/gender`, giving `hvtiRtemplates` the second exemplar its
template gate requires for `ac`, `hz` and `hp`.

**Architecture:** Four Quarto documents in the taxonomy layout, plus a study
scaffold. `ac` is scaffolded by `new_job()` from the shipped template; `hz`,
`hp` and the parity job are hand-written, following preserve_root's
`02-hz-dead_pa.qmd` as the skeleton but dropping everything specific to
interval censoring. Every job gates on the cohort before it computes, and the
parity job checks R against SAS's own printed nomogram.

**Tech Stack:** R 4.6.0, Quarto, `TemporalHazard` (≥ 1.2.6), `hvtiRutilities`,
`hvtiRtemplates`, `survival`, `haven`.

**Spec:** `specs/2026-08-26-maze-hazard-chain-design.md`

## Global Constraints

- **Study root:** `/studies/cardiac/rhythm/maze/atricure/gender` (SMB mount:
  `/Volumes/qhsstudies/cardiac/rhythm/maze/atricure/gender`).
- **The study tree is NOT a git workspace.** `preserve_root` carries a stray
  2023 `.git` with no remote; do not `git init`, branch, or commit anywhere
  under `/studies`. **Each task's gate is a verification, not a commit.** Only
  changes to `hvtiRtemplates` / `hvtiRutilities` get committed, in their own
  repos, on a branch.
- **`TemporalHazard` must be ≥ 1.2.6** (`.hzr_parse_sas_nomogram()` structural
  counter fix, #184). On the analysis host: `env -u R_HOME /opt/R/4.6.0/bin/Rscript`.
  The host default `Rscript` is 4.4.1 and dies on `undefined symbol:
  R_MakeMissingBinding`.
- **Never run a recursive traversal over the SMB mount.** Named files only.
  Anything corpus-wide runs server-side.
- **Ordinals are fixed by** `specs/2026-08-21-template-set-layout-design.md`
  §5: major from the taxonomy folder (`03` distributions, `04` analyses,
  `06` graphs), minor the next free slot. `ac` = `03.01`, **`hz` = `03.02`**,
  `hp` = `06.01`. A test asserts major-matches-folder.
- **Parity lives in a top-level `parity/` folder** (§5.1), borrowing the
  checked job's ordinal with a `-parity` suffix. Parity is never a taxonomy
  prefix.
- **Set key is `(endpoint, type)` = `("dead", "hz")`.** Every artifact path is
  derived from it; nothing hand-edits an output path.
- **`theta` is positional, 9 values, order fixed by the package:**
  `early.log_mu, early.log_t_half, early.nu, early.m, late.log_mu,
  late.log_tau, late.gamma, late.alpha, late.eta`.
- **SAS targets.** Three fits, all `conserve`, all `DELTA = 0` and
  `TAU = GAMMA = ALPHA = 1` fixed (pure Weibull late phase, `G3 = t^eta`):

  | fit | source `.lst` | n / events | branch | LL |
  |---|---|---|---|---|
  | overall | `hz.dead.lst` fit 1 | 512 / 53 | Case 2 (`m<0, nu>0`) | **−176.934** |
  | male (`female=0`) | `hz.dead.female.lst` fit 1 | 297 / 28 | Case 1L (`m=0` fixed) | **−92.9158** |
  | female (`female=1`) | `hz.dead.female.lst` fit 2 | 215 / 25 | **Case 3** (`m>0, nu<0`) | **−81.7217** |

  297+215 = 512 and 28+25 = 53. ⚠️ `hz.dead.female.sas`'s comment says the male
  LL is `-92.777`; the `.lst` says `-92.9158`. The comment is a stale
  starting-value annotation — **take results from the `.lst`, and what was
  asked from the `.sas`.** ⚠️ **Fit 2's −176.746 is NOT a `noconserve` target.**
  `hz.dead.sas` shows fit 2 turns conservation off *and* adds a `female`
  covariate to both phases (`early female; late female;`), so its LL confounds
  two changes — the same defect that makes preserve_root's fit 2 unusable. Do
  not quote it.
- ⚠️ **Read the `.sas`, not only the `.lst`, before characterising any job.**
  The `.lst` says what SAS printed; the `.sas` says what SAS was asked. Two of
  this plan's original premises were wrong because they were inferred from
  printed output alone.
- **Cohort:** N 512, events 53, right censored 459, time ∈
  [0.008213721, 4.175308]. This is Shape A — job cohort = study cohort.
- ⚠️ **`read_built()` lower-cases every column name** (hvtiRutilities 1.0.11),
  regardless of the source file's casing. `built.sas7bdat` stores the time
  column as `IV_DEAD`; anything from `read_built()` only ever has `iv_dead`.
  So `TIME <- "iv_dead"`, and `study_init(time = "iv_dead")` — the upper-case
  form makes `study_init()` fail outright and breaks every `d[[TIME]]` lookup.
  Verified 2026-08-26.
- **Gate time-range comparisons at the PRINTED precision, not an arbitrary
  relative tolerance.** SAS printed `0.008213721`; the stored value is
  `0.008213721021` (rel 2.55e-09), and the max is `4.175308186` against a
  printed `4.175308` (rel 4.45e-08). The principled check is that the stored
  value rounds to the printed one at the printed number of decimals — the same
  half-ulp rule the parity job uses on the nomogram. A hand-picked `1e-9`
  fails a value that is in fact exact to every digit SAS printed.
- ⚠️ **The parity number is the objective evaluated AT SAS's estimates, NOT a
  refit.** `hazard(..., fit = TRUE)` re-optimises and moves off SAS's point; on
  this study it lands on a *better* optimum (overall −176.842 against SAS's
  −176.934). Evaluated without refitting, R reproduces SAS to **2.9e-4
  (overall), 2.0e-5 (male), 1.2e-5 (female)** — the objective is right and the
  optimiser simply finds a different maximum. §12 of the parity handoff draws
  exactly this line: *pinning at SAS's estimates does not show R's optimiser
  finds them.* Report the two separately; never quote a refit as parity.
- **Evaluate the objective with the internal
  `.hzr_logl_multiphase(theta, time, status, phases, covariate_counts, x_list)`.**
  `hazard(..., fit = FALSE)` leaves `$fit$objective` as `NA`
  ([#144](https://github.com/ehrlinger/temporal_hazard/issues/144)), so it
  cannot serve. ⚠️ It returns the **log-likelihood directly** (negative for
  these fits, e.g. `-176.9337136`) — do **not** negate it. An earlier draft of
  this plan said the opposite; negating produces a sign-flip that reads as a
  ~354-unit parity failure and looks catastrophic. Verified by printing the
  raw return value.
- **`predict()` API — verified 2026-08-26, do not guess it:**

  ```r
  predict(object,
          newdata = NULL,
          type    = c("hazard", "linear_predictor", "survival", "cumulative_hazard"),
          ...)
  ```

  There is **no `newtime` argument** and **no `"cumhaz"` type**. To evaluate at
  arbitrary times pass `newdata = data.frame(time = tt)`. With no `newdata` it
  returns one value per training row. The returned vector carries misleading
  names (`early.log_mu` repeated) — `unname()` it.
- **`hzr_kaplan()` API — verified 2026-08-26:**

  ```r
  hzr_kaplan(time, status, conf_level = 0.95, event_only = TRUE)
  ```

  It takes **separate vectors, not a formula**, and returns a **data frame**
  (class `hzr_kaplan`) directly — there is no `$table`. Columns: `time`,
  `n_risk`, `n_event`, `n_censor`, `survival`, `std_err`, `cl_lower`,
  `cl_upper`, `cumhaz`, `hazard`, `density`, `life`. The survival column is
  `survival`, not `surv`.
- ⚠️ **maze carries a stray `.git` too** — `Daily Commit ... 2014`, no remote,
  135 uncommitted paths, toplevel at the study root. Same trap as
  preserve_root: a careless `git checkout` there destroys working files. The
  no-commits-under-`/studies` rule is not preserve_root-specific.

---

## File Structure

Under the study root:

| path | responsibility |
|---|---|
| `_study.yml` | study identity + cohort; written by `study_init()`, never hand-typed |
| `manifest.yaml` | dataset checksum; written by `study_init()` |
| `_quarto.yml` | project root marker; the templates resolve `.` vs `..` against it |
| `R/study.R` | study-local helpers sourced by every job |
| `distributions/dead-hz-03.01-ac.qmd` | actuarial life table |
| `distributions/dead-hz-03.02-hz.qmd` | the parametric fit |
| `graphs/dead-hz-06.01-hp.qmd` | nomogram figures |
| `parity/dead-hz-03.02-hz-parity.qmd` | R vs SAS on the printed nomogram |
| `estimates/dead-hz/{ac,hz}.rds` | generated |
| `graphs/dead-hz/hp-*.png` | generated |
| `parity/dead-hz/hz-diff.csv` | generated |

---

## Task 1: Study scaffold and the cohort gate

**Files:**
- Create: `<root>/_study.yml`, `<root>/manifest.yaml` (both via `study_init()`)
- Create: `<root>/_quarto.yml`
- Create: `<root>/R/study.R`
- Verify: `<root>/scratch-gate.R` (throwaway; delete in Step 6)

**Interfaces:**
- Consumes: nothing.
- Produces: `_study.yml` with `cohort: {n: 512, n_events: 53, n_censored: 459}`;
  `study_config()` resolvable from any job directory; `read_built()` returning
  a 512-row data frame; `STATUS` and `TIME` constants from `R/study.R`.

- [ ] **Step 1: Write the failing gate check**

Create `<root>/scratch-gate.R`:

```r
# Throwaway. Proves the scaffold before any job depends on it.
suppressMessages({ library(hvtiRutilities) })
cfg <- study_config(".")
d   <- read_built()
stopifnot(
  identical(as.integer(cfg$cohort$n),          512L),
  identical(as.integer(cfg$cohort$n_events),    53L),
  identical(as.integer(cfg$cohort$n_censored), 459L),
  identical(nrow(d), 512L)
)
assert_cohort(d)
cat("scaffold gate PASS: 512 / 53 / 459\n")
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd /Volumes/qhsstudies/cardiac/rhythm/maze/atricure/gender && Rscript scratch-gate.R
```

Expected: FAIL — `study_config()` errors naming the directories it walked,
because no `_study.yml` exists yet.

- [ ] **Step 3: Create the scaffold**

```r
# Run from the study root.
suppressMessages(library(hvtiRutilities))
study_init(
  root       = "/Volumes/qhsstudies/cardiac/rhythm/maze/atricure/gender",
  study      = "Gender differences in post-op outcomes of RF ablation for AFIB",
  population = "CCF 2001 to 2004",
  built      = "built.sas7bdat",
  event      = "dead",
  time       = "IV_DEAD"
)
```

`study_init()` reads the counts off the dataset — it accepts no cohort
argument, by design, because a number a human types can disagree with the data.

Then create `<root>/_quarto.yml`. The templates resolve their project root by
looking for this file, so it must exist even though the project needs no
settings of its own:

```yaml
project:
  type: default
```

And `<root>/R/study.R`:

```r
# Study-local helpers for maze/atricure/gender. Sourced by every job in this
# study: the shipped templates source every .R file under the project's R/.
#
# The event flag arrives as `logical` from read_clinical_data(), which infers
# binary columns that way, while hzr_kaplan() and Surv() both need numeric.
# Coerce in one place rather than at each call site.

STATUS <- "dead"     # event indicator, 0/1
TIME   <- "iv_dead"  # interval (years) to death; read_built() lower-cases

# SAS's own printed cohort for hz.dead.lst fit 1. Kept here so the hz and
# parity jobs assert against one copy rather than three.
SAS_COHORT <- list(n = 512L, n_events = 53L, n_censored = 459L)
SAS_TIME_RANGE <- c(0.008213721, 4.175308)

status_numeric <- function(d) as.numeric(d[[STATUS]])
```

- [ ] **Step 4: Run the gate to verify it passes**

```bash
cd /Volumes/qhsstudies/cardiac/rhythm/maze/atricure/gender && Rscript scratch-gate.R
```

Expected: `scaffold gate PASS: 512 / 53 / 459`

- [ ] **Step 5: Verify the time range too**

The `.lst` gate is counts **and** the printed time min/max (§6.1). Counts alone
let a 394-row dataset filtered to 389 stand in for a 389-row job cohort.

```bash
cd /Volumes/qhsstudies/cardiac/rhythm/maze/atricure/gender && Rscript -e '
suppressMessages(library(hvtiRutilities)); for (f in list.files("R", "[.]R$", full.names=TRUE)) source(f)
d <- read_built(); iv <- d[[TIME]]
# Compare at the precision SAS actually printed. round(x, dp) == printed is the
# same half-ulp rule the parity job applies to the nomogram; an arbitrary
# relative tolerance either fabricates a failure (1e-9 rejects a value exact to
# every printed digit) or hides a real one.
dp <- function(x) { for (d in 0:12) if (isTRUE(all.equal(x, round(x, d), tolerance = 0))) return(d); 12L }
stopifnot(identical(round(min(iv), dp(SAS_TIME_RANGE[1])), SAS_TIME_RANGE[1]),
          identical(round(max(iv), dp(SAS_TIME_RANGE[2])), SAS_TIME_RANGE[2]))
cat("time-range gate PASS:", format(min(iv), digits = 10), "-", format(max(iv), digits = 10), "\n")'
```

Expected: `time-range gate PASS: 0.008213721 - 4.175308`

- [ ] **Step 6: Remove the scratch file**

```bash
rm /Volumes/qhsstudies/cardiac/rhythm/maze/atricure/gender/scratch-gate.R
```

No commit — the study tree is not a git workspace (see Global Constraints).
The deliverable is the scaffold plus two passing gates.

---

## Task 2: The `ac` job — actuarial life table

**Files:**
- Create: `<root>/distributions/dead-hz-03.01-ac.qmd` (via `new_job()`)
- Generated: `<root>/estimates/dead-hz/ac.rds`

**Interfaces:**
- Consumes: `R/study.R`'s `STATUS`, `TIME`, `status_numeric()`; `read_built()`,
  `assert_cohort()`, `cohort_counts()` from `hvtiRutilities`.
- Produces: `estimates/dead-hz/ac.rds` =
  `list(overall = <hzr_kaplan data frame>, by_female = <list of hzr_kaplan data
  frames, one per sex, each carrying a `female` column>)`, read by Task 4's
  `hp` job via `set_path("estimates", "ac.rds")`. **Both** tables are required:
  `ac.dead.sas` computes an unstratified table and a `stratify=female` one.

- [ ] **Step 1: Scaffold the job**

```bash
cd /Volumes/qhsstudies/cardiac/rhythm/maze/atricure/gender && Rscript -e '
suppressMessages(library(hvtiRtemplates)); new_job("ac", "dead", "hz", dir = ".")'
```

Expected: writes `distributions/dead-hz-03.01-ac.qmd`. `new_job()` derives the
folder from the template's taxonomy row, so it cannot misfile; it refuses to
overwrite an existing job.

- [ ] **Step 2: Verify it fails to render unedited**

```bash
cd /Volumes/qhsstudies/cardiac/rhythm/maze/atricure/gender && quarto render distributions/dead-hz-03.01-ac.qmd
```

Expected: FAIL. The template ships `EDIT:` markers, and the derived-strata
chunk references study-specific variables that do not exist here. A job still
carrying an unresolved marker is not finished — that is what the markers are
for.

- [ ] **Step 3: Work the EDIT markers**

Three edits, in order:

1. **Header prose** — name the SAS job: `distributions/ac.dead.sas`.
2. **Cohort chunk — keep Shape A, delete Shape B.** maze's job cohort is the
   whole study cohort (512 = 512, verified in Task 1), so `assert_cohort()` is
   a real gate here:

```r
# ---- Shape A: whole-study cohort ------------------------------------------
d <- read_built()
assert_cohort(d)
cc <- cohort_counts(d)
```

3. **Life tables — TWO of them.** ⚠️ An earlier version of this step said
   `ac.dead.sas` computes one overall table with no stratification. **That was
   wrong**, asserted without opening the file. `ac.dead.sas` issues two
   `%kaplan` calls: an unstratified one (line 78) and
   `%kaplan(..., stratify=female, ...)` (line 84, titled *"Stratify by
   Female"*). In a study called *Gender differences in post-op outcomes*, the
   by-sex table is arguably the point of the job, not an extra.

```r
# hzr_kaplan() takes separate vectors, NOT a formula, and returns a data frame
# directly -- there is no $table. Verified against args(hzr_kaplan) rather than
# assumed from the survival package's interface, which it does not share.

# Overall -- ac.dead.sas line 78.
km <- hzr_kaplan(time = d[[TIME]], status = status_numeric(d))
knitr::kable(head(km, 12), digits = 5)

# Stratified by sex -- ac.dead.sas line 84, `stratify=female`. hzr_kaplan()
# has no stratify argument, so fit once per level and keep the level on each
# frame. Gate on the split adding back to the whole: a stratification that
# silently drops rows is the failure this whole chain guards against.
stopifnot("female" %in% names(d), !anyNA(d$female))
km_by <- lapply(split(d, d$female), function(g)
  cbind(female = g$female[1L],
        hzr_kaplan(time = g[[TIME]], status = status_numeric(g))))
stopifnot(sum(vapply(split(d, d$female), nrow, integer(1))) == nrow(d))
knitr::kable(do.call(rbind, lapply(km_by, head, 4)), digits = 5)

saveRDS(list(overall = km, by_female = km_by), set_path("estimates", "ac.rds"))
```

- [ ] **Step 4: Render and verify**

```bash
cd /Volumes/qhsstudies/cardiac/rhythm/maze/atricure/gender && quarto render distributions/dead-hz-03.01-ac.qmd
```

Expected: PASS. The rendered HTML reports `n_analysable` 512, `n_events` 53,
`n_censored` 459. A rendered page is itself evidence the gate passed.

- [ ] **Step 5: Verify the artifact landed in the set directory**

```bash
ls -l /Volumes/qhsstudies/cardiac/rhythm/maze/atricure/gender/estimates/dead-hz/ac.rds
```

Expected: the file exists. If it is at `estimates/ac.rds` instead, `set_path()`
was bypassed — fix the chunk rather than moving the file.

- [ ] **Step 6: Confirm no `EDIT:` markers remain**

```bash
grep -n "EDIT:" /Volumes/qhsstudies/cardiac/rhythm/maze/atricure/gender/distributions/dead-hz-03.01-ac.qmd
```

Expected: no output. A job that still contains one has not been finished.

---

## Task 3: The `hz` job — the parametric fit

**Files:**
- Create: `<root>/distributions/dead-hz-03.02-hz.qmd`
- Generated: `<root>/estimates/dead-hz/hz.rds`

**Interfaces:**
- Consumes: `R/study.R` (`STATUS`, `TIME`, `status_numeric()`, `SAS_COHORT`);
  `read_built()`, `assert_cohort()` from `hvtiRutilities`.
- Produces: `estimates/dead-hz/hz.rds` =
  `list(deterministic = <hazard>, multistart = <hazard>, noconserve = <hazard>,
  male = <hazard>, female = <hazard>)`. Task 4 (`hp`) reads `$male` and `$female`,
  because `hp.dead.female.sas` plots the per-sex fits, not the overall one.
  Task 5 (parity) reads **none** of this file — it evaluates at SAS's own
  printed estimates, so it depends on the `.lst` listings and not on any R
  artifact. **This shape is
  provisional** pending the first `hm` port — see spec §5.

- [ ] **Step 1: Write the job with its target assertions**

Create `distributions/dead-hz-03.02-hz.qmd`. Copy the YAML header block
verbatim from `dead-hz-03.01-ac.qmd` (same `format: html` settings — a file
meant to be copied must not depend on the directory it sits in), then:

````markdown
---
title: "Temporal hazard fit — death, maze/atricure/gender"
---

Replaces `distributions/hz.dead.sas`. Two-phase `Early + Late`, no interval
censoring, whole-study cohort.

```{r}
#| label: setup
.root <- if (file.exists("_quarto.yml")) "." else ".."
if (!file.exists(file.path(.root, "_quarto.yml"))) {
  stop("Neither . nor .. contains _quarto.yml, so the project root cannot be ",
       "resolved. Render this from the project root or from the job directory.",
       call. = FALSE)
}
for (f in list.files(file.path(.root, "R"), pattern = "[.]R$", full.names = TRUE)) source(f)
suppressPackageStartupMessages({
  library(TemporalHazard)
  library(hvtiRutilities)
  library(survival)
})
stopifnot(packageVersion("TemporalHazard") >= "1.2.6")
```

```{r}
#| label: set
ENDPOINT <- "dead"
TYPE     <- "hz"
set_path <- function(kind, file) {
  d <- file.path(.root, kind, paste0(ENDPOINT, "-", TYPE))
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  file.path(d, file)
}
```

```{r}
#| label: cohort
# Shape A: the job cohort IS the study cohort. hz.dead.sas applies no filter --
# `data built; set library.built;` plus a column drop -- so assert_cohort() is
# a real gate here and not a restatement of itself. Blocking: the fit does not
# run on a wrong cohort.
d <- read_built()
assert_cohort(d)
cc <- cohort_counts(d)
stopifnot(identical(as.integer(cc$n),          SAS_COHORT$n),
          identical(as.integer(cc$n_events),   SAS_COHORT$n_events),
          identical(as.integer(cc$n_censored), SAS_COHORT$n_censored))
knitr::kable(data.frame(quantity = c("n", "n_events", "n_censored"),
                        n = c(cc$n, cc$n_events, cc$n_censored)))
```

## Model

Four free early parameters (`THALF`, `NU`, `M`, `MUE`) and two late
(`ETA`, `MUL`). `DELTA` is 0 and `TAU = GAMMA = ALPHA = 1` are fixed, which
makes the late phase the pure Weibull `G3 = t^eta`. Branch is Case 2
(`m < 0`, `nu > 0`).

```{r}
#| label: phases
phases <- list(
  early = hzr_phase("cdf", t_half = 0.9996401, nu = 2.550286, m = -0.337948),
  late  = hzr_phase("g3", tau = 1, gamma = 1, alpha = 1, eta = 2.574888,
                    fixed = c("tau", "gamma", "alpha"))
)

# theta is POSITIONAL, nine values, in the order the package reports from
# .hzr_phase_theta_names():
#   early.log_mu, early.log_t_half, early.nu, early.m,
#   late.log_mu,  late.log_tau,     late.gamma, late.alpha, late.eta
# Note the asymmetry: the late phase logs mu and tau but carries gamma, alpha
# and eta on the natural scale. Values are SAS's own converged estimates from
# hz.dead.lst, so any disagreement is about the likelihood rather than about
# where the search began.
theta0 <- c(log(0.1736496), log(0.9996401), 2.550286, -0.337948,
            log(0.004307385), log(1), 1, 1, 2.574888)
stopifnot(length(theta0) == 9L)
```

```{r}
#| label: response
# No interval censoring in this study: SAS's `time iv_dead; event dead;` maps
# straight onto Surv(time, event). None of preserve_root's interval2 machinery
# applies, and objective = "sas" is not needed.
resp <- data.frame(time = d[[TIME]], status = status_numeric(d))
stopifnot(all(resp$status %in% c(0, 1)), !anyNA(resp$time))
```

```{r}
#| label: guard
# The objective is a log-likelihood. A positive one is impossible and signals a
# response that was mis-specified rather than a fit -- assert it instead of
# reporting a plateau as a result.
check_fit <- function(f, label) {
  o <- f$fit$objective
  if (!is.finite(o) || o > 0) {
    stop(label, ": objective is ", o, ", which is not a log-likelihood.",
         call. = FALSE)
  }
  invisible(f)
}
```

### Fit 1 — deterministic, from SAS's estimates

```{r}
#| label: fit-deterministic
fit_det <- hazard(Surv(time, status) ~ 1, data = resp, dist = "multiphase",
                  phases = phases, theta = theta0, fit = TRUE,
                  control = list(conserve = TRUE, condition = 14,
                                 n_starts = 1, maxit = 2000))
check_fit(fit_det, "deterministic")
summary(fit_det)
```

### Fit 2 — independent, multi-start

Answers *is SAS at the optimum*, which is a different question from *does R
agree with SAS*. Reported alongside, never as the parity number.

```{r}
#| label: fit-multistart
set.seed(20260826)
fit_ms <- hazard(Surv(time, status) ~ 1, data = resp, dist = "multiphase",
                 phases = phases, theta = theta0, fit = TRUE,
                 control = list(conserve = TRUE, condition = 14,
                                n_starts = 5, maxit = 2000))
check_fit(fit_ms, "multistart")
```

### Fit 3 — `noconserve` sensitivity

⚠️ **This has NO SAS reference.** `hz.dead.lst`'s fit 2 is `noconserve` *and*
adds a `female` covariate to both phases (`hz.dead.sas`: `early female; late
female;`), so its LL of −176.746 confounds two changes and cannot serve as a
conservation target — the identical defect that disqualifies preserve_root's
fit 2. Reported as a sensitivity only; never as a parity number.

```{r}
#| label: fit-noconserve
fit_nc <- hazard(Surv(time, status) ~ 1, data = resp, dist = "multiphase",
                 phases = phases, theta = theta0, fit = TRUE,
                 control = list(conserve = FALSE, condition = 14,
                                n_starts = 1, maxit = 2000))
check_fit(fit_nc, "noconserve")
```

```{r}
#| label: parity-at-sas-estimates
# THE PARITY NUMBERS. Evaluate the objective at the parameters SAS converged
# to, with no refitting: this asks "does R agree with SAS", and nothing else.
# The refits above answer "is SAS at the optimum", a different question.
#
# .hzr_logl_multiphase() returns the log-likelihood DIRECTLY -- negative for
# these fits. Do not negate it: doing so flips the sign and reads as a ~354-unit
# parity failure. hazard(fit = FALSE) cannot be used here: it leaves
# $fit$objective NA (temporal_hazard#144).
E <- asNamespace("TemporalHazard")
ll_at <- function(theta, phases, keep) {
  E$.hzr_logl_multiphase(
     theta = theta, time = resp$time[keep], status = resp$status[keep],
     phases = phases, covariate_counts = c(early = 0L, late = 0L),
     x_list = list(early = NULL, late = NULL))
}
parity <- data.frame(
  fit = c("overall", "male (female=0)", "female (female=1)"),
  sas = c(-176.934, -92.9158, -81.7217),
  r   = c(ll_at(theta0,  phases,   rep(TRUE, nrow(resp))),
          ll_at(theta_m, phases_m, d$female == 0),
          ll_at(theta_f, phases_f, d$female == 1)))
parity$abs_diff <- abs(parity$r - parity$sas)
knitr::kable(parity, digits = 7)

# Blocking. SAS prints 6 significant figures, so ~1e-3 absolute or better is
# expected; looser means the OBJECTIVE disagrees, not merely the optimiser --
# which is the failure this job exists to detect.
if (any(parity$abs_diff > 1e-3)) {
  stop("PARITY FAILED at SAS's own estimates: max abs diff ",
       signif(max(parity$abs_diff), 3), call. = FALSE)
}
```

The refits are reported apart from parity, because a refit that lands
elsewhere is not evidence of disagreement — here R finds a *higher* likelihood
than SAS reports.

```{r}
#| label: optimiser-comparison
optimiser <- data.frame(
  fit     = c("overall", "male", "female"),
  sas_ll  = c(-176.934, -92.9158, -81.7217),
  r_refit = c(fit_det$fit$objective, fit_m$fit$objective, fit_f$fit$objective))
optimiser$r_better_by <- optimiser$r_refit - optimiser$sas_ll
knitr::kable(optimiser, digits = 6)
```

### Fits 4 and 5 — per sex

`hz.dead.female.sas` fits each sex separately on a `where female=?` subset,
both with `conserve`. These are what `hp.dead.female.sas` actually plots, so
`hp` cannot be built without them. ⚠️ An earlier draft said neither prints a
nomogram and neither can be pinned on `S(t)`. **That was wrong**, and wrong the
same way three earlier premises here were: it checked the *fitting* job's
listing (`hz.dead.female.lst`, which indeed prints none) and never checked the
*plotting* job's. `graphs/hp.dead.female.lst` line 570 prints a 7-point table
with `_SURVIV` and `_MSURVIV` — one column per sex — giving **14 pinnable
survival points**, all reproduced exactly at 5 dp. Only survival is printed,
so this adds no hazard coverage — but reproducing SAS's LL at SAS's own converged
estimates still tests the objective, and the female fit is **Case 3**
(`m > 0, nu < 0`), a branch with exactly one pinned fit in the whole corpus.

Note the structural differences from the overall fit: male fixes `m` at 0
(Case 1L), female has `nu` negative and `m` large and positive (Case 3).

```{r}
#| label: fit-by-sex
male   <- resp[d$female == 0, , drop = FALSE]
female <- resp[d$female == 1, , drop = FALSE]
stopifnot(nrow(male) == 297L, nrow(female) == 215L,
          nrow(male) + nrow(female) == nrow(resp),
          sum(male$status) == 28L, sum(female$status) == 25L)

phases_m <- list(
  early = hzr_phase("cdf", t_half = 0.9996396, nu = 2.46917, m = 0, fixed = "m"),
  late  = hzr_phase("g3", tau = 1, gamma = 1, alpha = 1, eta = 2.254129,
                    fixed = c("tau", "gamma", "alpha")))
theta_m <- c(log(0.1583327), log(0.9996396), 2.46917, 0,
             log(0.005469243), log(1), 1, 1, 2.254129)

phases_f <- list(
  early = hzr_phase("cdf", t_half = 0.9996399, nu = -0.427237, m = 7.267309),
  late  = hzr_phase("g3", tau = 1, gamma = 1, alpha = 1, eta = 2.862257,
                    fixed = c("tau", "gamma", "alpha")))
theta_f <- c(log(0.1939737), log(0.9996399), -0.427237, 7.267309,
             log(0.003603803), log(1), 1, 1, 2.862257)

fit_m <- hazard(Surv(time, status) ~ 1, data = male, dist = "multiphase",
                phases = phases_m, theta = theta_m, fit = TRUE,
                control = list(conserve = TRUE, condition = 14,
                               n_starts = 1, maxit = 2000))
fit_f <- hazard(Surv(time, status) ~ 1, data = female, dist = "multiphase",
                phases = phases_f, theta = theta_f, fit = TRUE,
                control = list(conserve = TRUE, condition = 14,
                               n_starts = 1, maxit = 2000))
check_fit(fit_m, "male"); check_fit(fit_f, "female")

by_sex <- data.frame(
  fit = c("male (female=0)", "female (female=1)"),
  n   = c(nrow(male), nrow(female)),
  sas = c(-92.9158, -81.7217),
  r   = c(fit_m$fit$objective, fit_f$fit$objective))
by_sex$abs_diff <- abs(by_sex$r - by_sex$sas)
knitr::kable(by_sex, digits = 6)
```

```{r}
#| label: save
saveRDS(list(deterministic = fit_det, multistart = fit_ms, noconserve = fit_nc,
             male = fit_m, female = fit_f),
        set_path("estimates", "hz.rds"))
```
````

- [ ] **Step 2: Render and verify it fails on nothing but the numbers**

```bash
cd /Volumes/qhsstudies/cardiac/rhythm/maze/atricure/gender && quarto render distributions/dead-hz-03.02-hz.qmd
```

Expected: renders. The cohort table shows 512 / 53 / 459.

- [ ] **Step 3: Check the fit against SAS**

```bash
cd /Volumes/qhsstudies/cardiac/rhythm/maze/atricure/gender && Rscript -e '
f <- readRDS("estimates/dead-hz/hz.rds")
cat("deterministic:", f$deterministic$fit$objective, " SAS -176.934\n")
cat("noconserve   :", f$noconserve$fit$objective,    " (no SAS reference)\n")
cat("male         :", f$male$fit$objective,          " SAS  -92.9158\n")
cat("female       :", f$female$fit$objective,        " SAS  -81.7217\n")'
```

Expected: the **refits will NOT match** SAS's printed values, and that is not a
failure — R finds a better optimum. The number that must match is in the
`parity-at-sas-estimates` chunk. **If THAT one misses, stop and diagnose — do
not tune.** The two most likely causes, in order: the
`theta0` order does not match `.hzr_phase_theta_names()`, or the late phase's
fixed parameters were not actually held fixed. Check both before suspecting the
model.

- [ ] **Step 4: Verify conservation**

```bash
cd /Volumes/qhsstudies/cardiac/rhythm/maze/atricure/gender && Rscript -e '
suppressMessages(library(TemporalHazard))
f <- readRDS("estimates/dead-hz/hz.rds")$deterministic
# No newdata -> one value per training row, which is exactly sum_i Lambda(t_i).
cat("events conserved (R):", sum(predict(f, type = "cumulative_hazard")), " SAS: 53\n")'
```

Expected: ≈ 53. If `predict()` errors, that is
[temporal_hazard#144](https://github.com/ehrlinger/temporal_hazard/issues/144)
— compute Λ from the fitted parameters by hand as preserve_root's parity
documents do, and note it in the job.

- [ ] **Step 5: Confirm the artifact path**

```bash
ls -l /Volumes/qhsstudies/cardiac/rhythm/maze/atricure/gender/estimates/dead-hz/hz.rds
```

Expected: the file exists at that exact path.

---

## Task 4: The `hp` job — nomogram figures

**Files:**
- Create: `<root>/graphs/dead-hz-06.01-hp.qmd`
- Generated: `<root>/graphs/dead-hz/hp-survival.png`, `<root>/graphs/dead-hz/hp-hazard.png`

**Interfaces:**
- Consumes: `estimates/dead-hz/ac.rds` (Task 2 — `$overall` and `$by_female`),
  `estimates/dead-hz/hz.rds` (Task 3 — **`$male` and `$female`**, not
  `$deterministic`: `hp.dead.female.sas` plots the per-sex fits).
- Produces: two PNGs under `graphs/dead-hz/`. Produces **no** parity numbers —
  that is Task 5.

- [ ] **Step 1: Write the job**

Create `graphs/dead-hz-06.01-hp.qmd` with the same header, `setup` and `set`
chunks as Task 3 (with `ENDPOINT <- "dead"`, `TYPE <- "hz"`), then:

````markdown
```{r}
#| label: read-upstream
# hp overlays the actuarial estimate with the parametric fit, so it reads both
# upstream artifacts by set rather than recomputing either. A job that
# recomputes its upstream can silently disagree with it.
#
# This job is STRATIFIED BY SEX, because hp.dead.female.sas is: it reads
# est.hzd_male and est.hzd_female, never the overall fit. So take the per-sex
# fits and the per-sex life tables.
ac  <- readRDS(set_path("estimates", "ac.rds"))
hz  <- readRDS(set_path("estimates", "hz.rds"))
fits <- list(male = hz$male, female = hz$female)
kms  <- ac$by_female          # names are the `female` levels: "0", "1"
stopifnot(length(kms) == 2L)
```

```{r}
#| label: grid
# Match the SAS job's evaluation grid rather than inventing one:
# hp.dead.female.sas uses `max=log(3); min=-8; inc=(max-min)/999.9` -- 1000
# points LOG-SPACED from exp(-8) to 3 years. A linear grid to the last event
# time would under-resolve the early phase, which is where the action is.
tt <- exp(seq(-8, log(3), length.out = 1000))

# SAS scales for display: survival as a PERCENT, hazard as PERCENT PER MONTH
# (_hazard*100/12), with the x axis in months. Plot in those units so the
# figures are comparable to the 2006 originals rather than merely correct.
S_pct  <- function(f) 100 * unname(predict(f, newdata = data.frame(time = tt), type = "survival"))
H_pcpm <- function(f) 100 / 12 * unname(predict(f, newdata = data.frame(time = tt), type = "hazard"))
months <- tt * 12
lev    <- c("0", "1"); lab <- c("male", "female")
```

```{r}
#| label: fig-survival
png(set_path("graphs", "hp-survival.png"), width = 1400, height = 1000, res = 150)
plot(NA, xlim = range(months), ylim = c(0, 100), xlab = "Months after operation",
     ylab = "Survival (%)", main = "Death — actuarial and parametric, by sex")
for (i in seq_along(lev)) {
  lines(months, S_pct(fits[[i]]), col = i, lty = 1)
  k <- kms[[lev[i]]]                      # hzr_kaplan data frame; column is `survival`
  lines(k$time * 12, 100 * k$survival, col = i, lty = 2, type = "s")
}
legend("bottomleft", c(paste(lab, "(hz)"), paste(lab, "(ac)")),
       col = c(1, 2, 1, 2), lty = c(1, 1, 2, 2), bty = "n")
dev.off()
```

```{r}
#| label: fig-hazard
png(set_path("graphs", "hp-hazard.png"), width = 1400, height = 1000, res = 150)
plot(NA, xlim = range(months), ylim = range(vapply(fits, function(f) range(H_pcpm(f)), numeric(2))),
     log = "y", xlab = "Months after operation", ylab = "Hazard (% per month)",
     main = "Death — hazard function, by sex")
for (i in seq_along(lev)) lines(months, H_pcpm(fits[[i]]), col = i)
legend("topright", lab, col = seq_along(lab), lty = 1, bty = "n")
dev.off()
```
````

- [ ] **Step 2: Render**

```bash
cd /Volumes/qhsstudies/cardiac/rhythm/maze/atricure/gender && quarto render graphs/dead-hz-06.01-hp.qmd
```

Expected: renders; two PNGs written.

- [ ] **Step 3: Verify both figures landed in the set directory**

```bash
ls -l /Volumes/qhsstudies/cardiac/rhythm/maze/atricure/gender/graphs/dead-hz/
```

Expected: `hp-survival.png` and `hp-hazard.png`, both non-empty.

- [ ] **Step 4: Eyeball the survival curve**

Open `hp-survival.png`. Within each sex the parametric and actuarial curves
should track each other closely. Do **not** check them against the overall
nomogram's 0.83075 at t = 3 — that figure belongs to the pooled fit, and this
plot shows the two per-sex fits, which straddle it. A parametric curve that
diverges badly from the actuarial curve *of the same sex* means the fit is
wrong, not the figure — go back to Task 3.

For reference, the 2006 originals are `graphs/hp.dead.female.survival.pdf` and
`graphs/hp.dead.female.hazard.pdf`. ⚠️ Their axis label reads "Years After
Tricuspid Valve Replacement" — a copy-paste error in the SAS source; this is an
AFIB ablation study. Do not reproduce that label.

---

## Task 5: The parity job — R against SAS's printed nomogram

**Files:**
- Create: `<root>/parity/dead-hz-03.02-hz-parity.qmd`
- Generated: `<root>/parity/dead-hz/hz-diff.csv`

**Interfaces:**
- Consumes: `estimates/dead-hz/hz.rds` (`$deterministic`);
  `distributions/hz.dead.lst`.
- Produces: `parity/dead-hz/hz-diff.csv` with one row per nomogram point and
  columns `YEARS, sas_surv, r_surv, surv_ok, sas_haz, r_haz, haz_ok`.

- [ ] **Step 1: Write the parity job**

Create `parity/dead-hz-03.02-hz-parity.qmd`. Same header and `setup` chunk as
Task 3, plus `set_path()` from the `set` chunk, then:

````markdown
```{r}
#| label: sas-nomogram
# Parse the nomogram out of the FIT BLOCK, not the whole file: a listing can
# print several fits and .hzr_parse_sas_nomogram() keeps only the first table
# it finds (temporal_hazard#183). Splitting first attributes the table to the
# fit whose block contains it.
E <- new.env()
source(system.file("sas-parity", "helper-sas-parity.R", package = "TemporalHazard"),
       local = E)
lst <- file.path(.root, "distributions", "hz.dead.lst")
blk <- E$.hzr_split_fits(E$.hzr_read_lst(lst))[[1L]]
tmp <- tempfile(fileext = ".lst"); writeLines(blk, tmp)
nom <- E$.hzr_parse_sas_nomogram(tmp); unlink(tmp)
stopifnot(!is.null(nom), nrow(nom) == 8L)
knitr::kable(nom, digits = 5)
```

```{r}
#| label: precision-rule
# Print precision is INFERRED per column per file, never assumed: this listing
# prints YEARS to 5 dp where the g3 oracle listings print 4, and SAS's SURVIV
# width varies between files too. Hard-coding either fabricates failures.
decimals_of <- function(v) {
  v <- v[is.finite(v)]
  for (d in 0:12) if (isTRUE(all.equal(v, round(v, d), tolerance = 0))) return(d)
  12L
}
```

### Evaluate at the times the `.sas` states, not the times the `.lst` printed

`hz.dead.sas` line 99 gives the evaluation grid exactly:

```sas
do years=15/365.2425, 30/365.2425, 3/12, 6/12, 1, 1.5, 2, 3;
```

The `.lst` prints those rounded to 5 dp. Evaluating at the **rounded** values
needs a tolerance rule to pass — row 2's hazard comes out 0.24834 against a
printed 0.24835. Evaluating at the **exact** values needs none: all eight
points match to the last printed digit, for survival *and* hazard.

This is the branch's own rule applied once more — the `.lst` says what SAS
printed, the `.sas` says what SAS was asked. Reading the source removes the
slack rather than accommodating it.

```{r}
#| label: compare
t_exact <- c(15/365.2425, 30/365.2425, 3/12, 6/12, 1, 1.5, 2, 3)
# Fail loudly if a future listing's times differ, rather than silently
# comparing R at one set of times against SAS at another.
stopifnot(identical(round(t_exact, decimals_of(nom$YEARS)), nom$YEARS))

sas <- list(mue = 0.1736496, thalf = 0.9996401, nu = 2.550286, m = -0.337948,
            mul = 0.004307385, eta = 2.574888)   # hz.dead.lst fit 1
Lam <- function(p, t) with(p, mue * hzr_decompos(t, t_half = thalf, nu = nu, m = m)$G +
                              mul * hzr_decompos_g3(t, tau = 1, gamma = 1, alpha = 1, eta = eta)$G3)
haz <- function(p, t) with(p, mue * hzr_decompos(t, t_half = thalf, nu = nu, m = m)$g +
                              mul * hzr_decompos_g3(t, tau = 1, gamma = 1, alpha = 1, eta = eta)$g3)

dpS <- decimals_of(nom$SURVIV); dpH <- decimals_of(nom$HAZARD)
ok_S <- round(exp(-Lam(sas, t_exact)), dpS) == nom$SURVIV
ok_H <- round(haz(sas, t_exact),        dpH) == nom$HAZARD
```

### The per-sex fits are pinnable too — from the `hp` listing

`hz.dead.female.lst` prints no nomogram, but `graphs/hp.dead.female.lst`
line 570 does, at the times `hp.dead.female.sas` line 78 states
(`30/365.2425, 0.25, 0.5, 1, 1.5, 2, 3`). It carries **two** survival columns:
`_MSURVIV` (male) and `_SURVIV` (female). Only survival — no hazard column —
so this adds no `h(t)` coverage for the per-sex fits.

Worth the trouble because the female fit is **Case 3** (`m>0, nu<0`) and the
male is **Case 1L** (`m=0` fixed) — branches the corpus barely covers.

```{r}
#| label: per-sex
male   <- list(mue = 0.1583327, thalf = 0.9996396, nu = 2.46917,   m = 0,
               mul = 0.005469243, eta = 2.254129)
female <- list(mue = 0.1939737, thalf = 0.9996399, nu = -0.427237, m = 7.267309,
               mul = 0.003603803, eta = 2.862257)
t_hp <- c(30/365.2425, 0.25, 0.5, 1, 1.5, 2, 3)

# PROVE the column-to-arm mapping rather than trusting the column name. Guessing
# an arm from a suffix is how two cohorts get silently swapped -- the same trap
# the resilia matched-pair arms set, where only the printed time maxima could
# tell them apart.
hitS <- function(p, tgt) sum(round(exp(-Lam(p, t_hp)), decimals_of(tgt)) == tgt)
if (!(hitS(male, hp$MSURVIV) == length(t_hp) && hitS(male, hp$SURVIV) == 0L &&
      hitS(female, hp$SURVIV) == length(t_hp) && hitS(female, hp$MSURVIV) == 0L)) {
  stop("per-sex column mapping is not discriminating: _MSURVIV should match ",
       "male exactly and female not at all, and vice versa.", call. = FALSE)
}
ok_M <- round(exp(-Lam(male,   t_hp)), decimals_of(hp$MSURVIV)) == hp$MSURVIV
ok_F <- round(exp(-Lam(female, t_hp)), decimals_of(hp$SURVIV))  == hp$SURVIV
```

```{r}
#| label: verdict
# Blocking. A parity document that renders green while failing its own check is
# worse than no document: the rendered page is the evidence. 30 checks across
# 22 rows -- overall survival and hazard (8 each), per-sex survival (7 each).
bad <- c(overall_surv = sum(!ok_S), overall_haz = sum(!ok_H),
         male_surv = sum(!ok_M), female_surv = sum(!ok_F))
if (any(bad > 0)) stop("PARITY FAILED: ", paste(names(bad), bad, sep = "=", collapse = ", "),
                       call. = FALSE)
cat(sprintf("PARITY PASS: overall survival %d/%d, overall hazard %d/%d, male survival %d/%d, female survival %d/%d\n",
            sum(ok_S), length(ok_S), sum(ok_H), length(ok_H),
            sum(ok_M), length(ok_M), sum(ok_F), length(ok_F)))
```
````

- [ ] **Step 2: Render**

```bash
cd /Volumes/qhsstudies/cardiac/rhythm/maze/atricure/gender && quarto render parity/dead-hz-03.02-hz-parity.qmd
```

Expected: `PARITY PASS: overall survival 8/8, overall hazard 8/8, male survival 7/7, female survival 7/7`

- [ ] **Step 3: If it fails, check the two rounding traps before the model**

Both have fabricated failures before:

```bash
cd /Volumes/qhsstudies/cardiac/rhythm/maze/atricure/gender && Rscript -e '
r <- read.csv("parity/dead-hz/hz-diff.csv")
r$rel_surv <- abs(r$r_surv - r$sas_surv) / r$sas_surv
r$rel_haz  <- abs(r$r_haz  - r$sas_haz)  / r$sas_haz
print(r[, c("YEARS","rel_surv","rel_haz","surv_ok","haz_ok")], digits = 3)
cat("\n15/365.25 =", 15/365.25, "  30/365.25 =", 30/365.25, "\n")'
```

If only rows 1–2 fail, it is the `YEARS` rounding, not the fit: those rows are
15 and 30 days, and evaluating at the printed 0.04107 / 0.08214 rather than
across the rounding interval is the known trap.

- [ ] **Step 4: Verify the CSV landed under `parity/dead-hz/`**

```bash
ls -l /Volumes/qhsstudies/cardiac/rhythm/maze/atricure/gender/parity/dead-hz/hz-diff.csv
```

Expected: exists. `parity/` obeys the same layout rule as every taxonomy
folder — authored files flat, generated output under `<set>/`.

---

## Task 6: Record the outcome and close the template gate

**Files:**
- Modify: `hvtiRtemplates/inst/templates/README.md` ("What is not here yet")
- Modify: `/Volumes/.../preserve_root/PARITY-HANDOFF.md` §14 Next item 4

**Interfaces:**
- Consumes: the verified outcomes of Tasks 1–5.
- Produces: a README that no longer claims `hz`/`hp` exist in only one study.

- [ ] **Step 1: Branch in hvtiRtemplates**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git checkout main && git pull --ff-only && git checkout -b feat/second-exemplar-run
```

- [ ] **Step 2: Update the README's gate paragraph**

In `inst/templates/README.md`, replace the "What is not here yet" text about
`hz` and `hp` with the current state: both shapes now exist in **two** studies
(`preserve_root` and `maze/atricure/gender`), so the gate is open and template
extraction is the next piece of work. Leave `bh` and `hm` as pending — they
exist only in preserve_root (0 in maze), which Task 5 does not change.

- [ ] **Step 3: Commit**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git add inst/templates/README.md && \
git commit -m "docs: hz and hp now have a second exemplar

maze/atricure/gender has run ac, hz and hp, so the two-studies gate is open
for those three. bh and hm stay pending: they exist only in preserve_root."
```

- [ ] **Step 4: Update the parity handoff**

In `PARITY-HANDOFF.md` §14, mark Next item 4 done, recording the LL and parity
results. Do **not** `git commit` there — the study tree is not a git workspace.

- [ ] **Step 5: Open the PR**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git push -u origin feat/second-exemplar-run && \
gh pr create --base main --title "docs: hz and hp have a second exemplar" \
  --body "maze/atricure/gender ran ac/hz/hp with parity at 8/8. Opens the template gate for those three; bh and hm remain single-study."
```

---

## Self-Review

**Spec coverage:** §2 study choice → Task 1. §2 gate → Task 1 Steps 4–5. §3
layout and ordinals → Tasks 2–5 file paths. §4 scaffold → Task 1 Step 3. §5 the
`hz` job, phases, theta, targets → Task 3. §5 artifact contract → Task 3
Interfaces. §6 `noconserve` → Task 3 Fit 3 and Step 3. §7 parity in `parity/`
→ Task 5. §8 no `hm`/`hs`/`bh` mocks → no task creates them; Task 6 Step 2
keeps them listed as pending. §9 Shape A/B seam → Task 2 Step 3 and Task 3
`cohort` chunk both name the shape explicitly. §11 theta order and `ac`
template → resolved and used verbatim in Task 3.

**Placeholders:** none. Every code step carries the code; every command carries
its expected output. `<flag>`/`<N>` appear only inside a quotation of the
shipped template's own Shape B comment, which is not a step to execute.

**Type consistency:** `set_path(kind, file)` has the same signature in Tasks
2–5. `STATUS`, `TIME`, `status_numeric()`, `SAS_COHORT`, `SAS_TIME_RANGE` are
defined once in Task 1 and used with those exact names after. `hz.rds` is
written as `list(deterministic=, multistart=, noconserve=)` in Task 3 and read
as `$deterministic` in Tasks 4 and 5.

**Pre-flight corrections (2026-08-26):** the first draft of this plan used
`predict(fit, newtime = tt, type = "cumhaz")` in Tasks 3–5 and a formula
interface for `hzr_kaplan()` in Task 2. Both APIs were invented rather than
checked, and every one of those calls would have failed on the first render.
The signatures above are now verified against the installed package. It also
asserted maze had no git context; it has a 2014 stray repo, same as
preserve_root.

**Known risk carried forward:** Tasks 3–5 call `predict()` on a fitted object.
[temporal_hazard#144](https://github.com/ehrlinger/temporal_hazard/issues/144)
concerns `predict()` on a `fit = FALSE` object, which is not this case, but if
`predict()` errors anyway, compute Λ(t) and h(t) from the fitted parameters via
`hzr_decompos()` / `hzr_decompos_g3()` as preserve_root's parity documents do,
and record that the workaround was needed.
