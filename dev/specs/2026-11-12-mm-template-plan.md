# `mm` Mixed-Model Template Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `inst/templates/30_analyses/mm.qmd`, one unqualified template that fits a linear mixed model to a repeated continuous response with `nlme` and saves back-transformed population-average predictions for a later `mp` plot.

**Architecture:** The template follows `rm-linear.qmd`'s chunk layout (`setup`, `edit-study-choices`, `tbl-data`, fit, tables, `save`, `provenance`). The fit, the guards and the prediction code live in one `mm-helpers` chunk inside the template, as `vt-fit` keeps its helpers, so tests evaluate that chunk directly. Nothing new goes into `R/`.

**Tech Stack:** R, `nlme` (`gls`, `lme`), Quarto, testthat edition 3, `hvtiRutilities` study fixtures.

**Spec:** `dev/specs/2026-11-12-mm-template-design.md`. Work in the worktree `<repo>-mm-census`, branch `chore/mm-census`. Never `git add -A`: a failing testthat run writes `tests/testthat/_problems/`.

## Global Constraints

- Lines at most 135 characters (`.lintr`); every other default linter is on.
- Roxygen is Rd markup, not markdown (no roxygen changes are planned).
- The template carries no study identifiers; `test-add-job.R` asserts it.
- Every study-specific line in the template is marked `EDIT:`, with a comment that says why the choice matters.
- Exactly one `^SUBJECT\s+<- ` line and one `^TYPE\s+<- ` line; `SUBJECT <- "outcome"`, `TYPE <- "mixed"`.
- The template carries its own `format:` block, copied from `rm-linear.qmd`.
- `STRUCTURE` values: `"cs"`, `"ar1"`, `"un"`, `"random"`, `"random+cs"`, `"random+ar1"`; the first listed is the reported model; default `"cs"`.
- `METHOD` is `"REML"` (default) or `"ML"`.
- AR(1)/UN guard: more than 20 distinct `TIME` values stops.
- `IMPUTATION` set stops: multiple-imputation pooling is out of scope for the first cut.
- Predictions: 95% limits by the delta method on the linear predictor, back-transformed with `exp()` when `RESPONSE_SCALE` is `"log"`; `PREDICT_TIMES = NULL` means 50 points over the observed range.
- The catalog row reads `in-flight` until the lri port in Task 6 matches SAS; only then `shipped`.
- Versions: no `DESCRIPTION` `Version:` bump and no `NEWS.md` edit; the entry goes in `news/chore-mm-census.md`.
- Server jobs run on lri, never over the Mac's SMB mount.

### Amendment to the spec, made in Task 3

The spec (§6) says `estimates/mm.rds` holds "the fitted model". An `nlme` fit carries the grouping factor, which is the patient ID, in `$groups` and in its correlation structure, where `.digest_bundle_ids()` cannot reach it. The bundle therefore saves the coefficients, their covariance, the tables and the predictions, not the `nlme` object. Task 3 edits spec §6 to say so.

---

## File map

| file | change | responsibility |
|---|---|---|
| `inst/templates/30_analyses/mm.qmd` | create | the template |
| `tests/testthat/helper-mm.R` | create | the synthetic longitudinal cohort, the chunk runner and the render fixture |
| `tests/testthat/test-mm-template.R` | create | the helper, guard, fit, prediction and render tests |
| `inst/extdata/templates.json` | modify the `mm` row | catalog status, spec, uses, downstream, note |
| `dev/specs/2026-08-29-template-conversion-roadmap.md` | regenerate | roadmap tables |
| `.lintr` | add a file key | per-linter exclusions for `mm.qmd` |
| `inst/templates/README.md` | modify | the template's row and its figure-less line |
| `DESCRIPTION` | modify `Suggests` | add `nlme` |
| `news/chore-mm-census.md` | create | the NEWS bullet |
| `dev/specs/2026-11-12-mm-template-design.md` | modify §6 | the bundle amendment |

---

### Task 1: The synthetic cohort and the chunk runner

**Files:**
- Create: `tests/testthat/helper-mm.R`
- Test: `tests/testthat/test-mm-template.R`

**Interfaces:**
- Consumes: `lm_chunk(src, label)` (`helper-lm.R`), `eval_setup_chunk(code, env)` and `setup_label(label)` (`helper-setup.R`).
- Produces: `mm_data(n = 200L, rho = 0.5)` returning a data frame with columns `ccfid`, `id`, `time`, `age`, `female`, `y`, one row per patient and time; `mm_helpers()` returning an environment holding the `mm-helpers` chunk's functions; `mm_run(labels, env, choices = list())`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-mm-template.R`:

```r
test_that("the mm cohort is longitudinal with the correlation it was built with", {
  d <- mm_data()
  per_patient <- table(d$ccfid)
  expect_true(all(per_patient >= 2L & per_patient <= 6L))
  expect_false(anyDuplicated(d[c("ccfid", "time")]) > 0L)
  expect_true(all(d$y > 0))
  # The between-patient share of the log-scale variance is the CS correlation.
  fit <- nlme::lme(log(y) ~ log(time + 1) + age + female, random = ~ 1 | ccfid, data = d)
  vc <- as.numeric(nlme::VarCorr(fit)[, "Variance"])
  expect_equal(vc[[1L]] / sum(vc), 0.5, tolerance = 0.1)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-mm-template.R")'`
Expected: FAIL with `could not find function "mm_data"`.

- [ ] **Step 3: Write the helper**

Create `tests/testthat/helper-mm.R`:

```r
# mm: the mixed-model template. lm_chunk() in helper-lm.R is generic over a template's source.

# A synthetic longitudinal cohort: n patients with 2 to 6 measurements each, a log-normal response
# whose log has a random intercept, and a within-patient correlation of rho on the log scale.
mm_data <- function(n = 200L, rho = 0.5) {
  withr::local_seed(42)
  per <- sample(2:6, n, replace = TRUE)
  id <- rep(seq_len(n), per)
  time <- unlist(lapply(per, function(k) sort(round(stats::runif(k, 0, 10), 2))))
  age <- rep(stats::rnorm(n, 60, 10), per)
  female <- rep(rep(0:1, length.out = n), per)
  total <- 0.04
  b <- rep(stats::rnorm(n, 0, sqrt(rho * total)), per)
  e <- stats::rnorm(length(id), 0, sqrt((1 - rho) * total))
  y <- exp(3 + 0.2 * log(time + 1) + 0.01 * (age - 60) - 0.1 * female + b + e)
  data.frame(ccfid = id, id = id, time = time, age = age, female = female, y = y)
}

# The functions the template's mm-helpers chunk defines, in an environment of their own.
mm_helpers <- function() {
  src <- readLines(template_path("mm"), warn = FALSE)
  env <- new.env(parent = globalenv())
  eval(parse(text = lm_chunk(src, "mm-helpers")), envir = env)  # nolint: object_usage_linter.
  env
}

# Evaluate the template's chunks by label into env, setting `choices` after the study choices,
# as rm_run() does for the rm templates.
mm_run <- function(labels, env, choices = list()) {
  src <- readLines(template_path("mm"), warn = FALSE)
  for (label in unique(vapply(labels, setup_label, ""))) {  # nolint: object_usage_linter.
    code <- lm_chunk(src, label)  # nolint: object_usage_linter.
    if (identical(label, "setup")) {
      eval_setup_chunk(code, env)  # nolint: object_usage_linter.
    } else {
      suppressMessages(eval(parse(text = code), envir = env))
    }
    if (identical(label, "edit-study-choices")) {
      list2env(choices, envir = env)
      if (!"tbl-data" %in% labels) {
        if (!exists(".id", envir = env, inherits = FALSE)) env$.id <- env$ID
        env$RESPONSE_SCALE <- hvtiRtemplates:::.response_scale(env$RESPONSE_SCALE)
        env$.response <- hvtiRtemplates:::.response_term(env$d, env$OUTCOME, env$RESPONSE_SCALE)
        if (!exists("job_data", envir = env, inherits = FALSE)) env$job_data <- list()
      }
    }
  }
  invisible(env)
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-mm-template.R")'`
Expected: PASS (1 test). If the correlation falls outside 0.5 ± 0.1, raise `n` to 300 rather than widening the tolerance.

- [ ] **Step 5: Commit**

```bash
git add tests/testthat/helper-mm.R tests/testthat/test-mm-template.R
git commit -m "mm: synthetic longitudinal cohort and chunk runner for the template tests"
```

---

### Task 2: The template skeleton, scaffolded and catalogued

**Files:**
- Create: `inst/templates/30_analyses/mm.qmd`
- Modify: `inst/extdata/templates.json` (the `"prefix": "mm"` row), `.lintr`, `DESCRIPTION`
- Regenerate: `dev/specs/2026-08-29-template-conversion-roadmap.md`
- Test: `tests/testthat/test-mm-template.R`

**Interfaces:**
- Consumes: `.job_setup()`, `read_job_data()`, `.check_job_columns()`, `.response_scale()`, `.response_term()`.
- Produces: chunk labels `setup`, `edit-study-choices`, `tbl-data`; study-choice names exactly as the Global Constraints and spec §4 give them; in `tbl-data`, `d`, `.id`, `.response`, and `IMPUTATION` resolved.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-mm-template.R`:

```r
test_that("mm scaffolds with its study choices and EDIT: markers", {
  root <- withr::local_tempdir("mm-scaffold-")
  suppressMessages(hvtiRutilities::study_setup(root, study = "Synthetic mm study", study_tracker_id = 42L, renv = FALSE))
  job <- add_job("mm", "outcome", "mixed", dir = root)
  src <- readLines(job, warn = FALSE)
  for (field in c("TIME", "KEY", "OUTCOME", "RESPONSE_SCALE", "TIME_TERMS", "PREDICTORS", "STRUCTURE", "METHOD",
                  "PREDICT_AT", "PREDICT_TIMES", "IMPUTATION")) {
    expect_length(grep(paste0("^", field, " <- "), src), 1L)
  }
  expect_true(any(grepl('^STRUCTURE <- "cs"', src)))
  expect_true(any(grepl("^KEY <- c\\(ID, TIME\\)", src)))
  expect_gt(sum(grepl("EDIT:", src, fixed = TRUE)), 5L)
})

test_that("mm reads every measurement, not one row per patient", {
  src <- readLines(template_path("mm"), warn = FALSE)
  expect_true(any(grepl("one_row_per_patient = FALSE", src, fixed = TRUE)))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-mm-template.R")'`
Expected: FAIL; `template_path("mm")` finds no file.

- [ ] **Step 3: Create the template skeleton**

Create `inst/templates/30_analyses/mm.qmd`. The front matter is `rm-linear.qmd`'s with the title changed; the `setup` chunk is `rm-linear.qmd`'s with the package lines changed:

````markdown
---
title: "Mixed model for a repeated measurement"
date: now
date-format: "YYYY-MM-DD HH:mm"
format:
  html:
    fig-width: 9
    fig-height: 6
    theme: cosmo
    toc: true
    toc-location: left
    page-layout: full
    grid:
      body-width: 2000px
      sidebar-width: 250px
    code-fold: true
    df-print: default
    embed-resources: true
---

Fits a linear mixed model to a continuous response measured repeatedly on each
patient, as PROC MIXED did with a REPEATED or RANDOM statement, and saves the
population-average course over time, with its confidence limits, for a plot.

```{r}
#| label: setup
#| results: asis
SUBJECT  <- "outcome"
TYPE     <- "mixed"
.in <- knitr::current_input(dir = TRUE)
suppressPackageStartupMessages({
  library(nlme)
  library(hvtiRutilities)
})
# To render a job you have not finished, leave a chunk out with the chunk
# option skip, giving the reason in quotes, or call hvtiRtemplates::stop_here()
# in a chunk to leave out everything below it. A draft lists each one in a
# callout; a final render refuses them, as it refuses an unresolved marker.
# ?stop_here has more.
.job <- hvtiRtemplates:::.job_setup(SUBJECT, TYPE, envir = environment())
.root <- .job$root
set_path <- .job$set_path
.provenance_data <- list()
# The draft banners, if any, and the box under the title, after all the code above.
.job$notice
```

```{r}
#| label: edit-study-choices
# EDIT: the registered dataset this job reads ("built" is the study dataset).
DATASET <- "built"
# EDIT: a named analysis set, or NULL for every row WHERE keeps.
ANALYSIS_SET <- NULL
# EDIT: a filter on the rows, e.g. WHERE <- quote(echo_type == "TTE"), or NULL.
WHERE <- NULL
# EDIT: the patient identifier. If the data has no "ccfid" column, the job uses MRN, then eMRN;
# name another column, such as "randid", if the study uses one.
ID <- "ccfid"
# EDIT: the column giving each measurement's time since the reference event, in the units
# the time terms below expect. Every row needs one; a missing or negative time stops the job.
TIME <- "time"
# EDIT: what makes a row unique. A repeated measurement is one row per patient and time;
# add a sequence column if a patient can have two measurements at the same time.
KEY <- c(ID, TIME)
# Optional: NULL reads the cohort alone. To model measurements held in a registered
# ancillary dataset (echoes, labs), name it in JOIN; each joined record is a row.
# REDUCE stays NULL here: collapsing to one record per patient would remove the
# repeated measurements this job exists to model.
JOIN <- NULL
JOIN_VARS <- NULL
REDUCE <- NULL
JOIN_KEY <- NULL

# EDIT: the repeated continuous response, named as the column.
OUTCOME <- "continuous_outcome"
# EDIT: the scale the response is modeled on. "identity" models it as measured; "log"
# models log(OUTCOME), what most corpus jobs did, writing ln_ in a DATA step. A
# coefficient is then a change in the log, and the predictions are back-transformed.
RESPONSE_SCALE <- "identity"
# EDIT: the time terms, as R expressions in TIME. A SAS job's DATA-step transforms
# carry over line for line: in_t = 1/(t+1) is "I(1/(time + 1))", ln_t = log(t+1) is
# "log(time + 1)". The +1 keeps a measurement at time zero finite.
TIME_TERMS <- c("time")
PREDICTORS <- c("age", "female")           # EDIT: the declared fixed effects besides time; this job selects nothing.
# EDIT: the within-patient correlation, first listed is reported; list several to compare them.
#   "cs"         REPEATED / type=cs sub=id: one correlation between any two of a patient's
#                measurements. What 37 of 56 corpus studies used.
#   "ar1"        REPEATED visit / type=ar(1): correlation falls with the number of visits
#                apart. Needs shared, ordered visits, not free times; more than 20 distinct
#                times stops the job.
#   "un"         REPEATED visit / type=un: a correlation and a variance per visit pair.
#                Same visit requirement; costs many parameters.
#   "random"     RANDOM intercept / subject=id.
#   "random+cs", "random+ar1"  both statements, as 15 corpus studies wrote them.
# A spatial structure (type=sp(pow)) is not offered; nlme::corExp(form = ~ time | id)
# is its R form if a study needs one.
STRUCTURE <- "cs"
# EDIT: "REML", as SAS's default, unless models with different fixed effects are to be
# compared by likelihood, which needs "ML".
METHOD <- "REML"
# EDIT: the covariate profiles the predicted course is drawn for, as a list of named
# lists, e.g. list(list(age = 60, female = 0), list(age = 60, female = 1)). NULL draws
# one profile: the median of each numeric predictor and the first level of the others.
PREDICT_AT <- NULL
# EDIT: the times to predict at, or NULL for 50 points over the observed range.
PREDICT_TIMES <- NULL
IMPUTATION <- NULL                          # EDIT: must stay NULL; this job does not pool imputations yet.
```

```{r}
#| label: tbl-data
#| tbl-cap: "The data this job read"
# The checksum of every dataset in manifest.yaml is checked before anything is
# read, so a result can name the data that produced it. It stops on a mismatch.
hvtiRutilities::verify_manifest(file.path(.root, "manifest.yaml"))
.cfg <- study_config(start = .root)
job_data <- hvtiRtemplates::read_job_data(.cfg, dataset = DATASET, analysis_set = ANALYSIS_SET,
                                          where = WHERE, id = ID, key = KEY, join = JOIN, join_vars = JOIN_VARS,
                                          reduce = REDUCE, join_key = JOIN_KEY, one_row_per_patient = FALSE,
                                          imputation = IMPUTATION)
job_data$provenance$role <- "training"
if (!is.null(job_data$provenance_join)) job_data$provenance_join$role <- "training"
d <- job_data$data
.provenance_data <- c(if (exists(".provenance_data")) .provenance_data else list(), list(job_data$provenance),
                      if (!is.null(job_data$provenance_join)) list(job_data$provenance_join))
# The identifier column read_job_data() used: MRN or eMRN when there is no ccfid.
.id <- attr(job_data$record, "selection")$id
IMPUTATION <- attr(job_data$record, "selection")$imputation
knitr::kable(job_data$record, col.names = c("Data", ""))
# A column the study choices name that the data lack stops here, naming the setting to change.
hvtiRtemplates:::.check_job_columns(d, OUTCOME = OUTCOME, TIME = TIME, PREDICTORS = PREDICTORS)
RESPONSE_SCALE <- hvtiRtemplates:::.response_scale(RESPONSE_SCALE)
.response <- hvtiRtemplates:::.response_term(d, OUTCOME, RESPONSE_SCALE)
```
````

- [ ] **Step 4: Catalogue it, lint it and declare `nlme`**

In `inst/extdata/templates.json`, replace the `mm` row's fields, keeping its other keys:

```json
"description": "Linear mixed model of a repeated continuous response, with the population-average course over time.",
"status": "in-flight",
"spec": "dev/specs/2026-11-12-mm-template-design.md",
"uses": ["nlme::gls", "nlme::lme"],
"downstream": ["mp"],
"note": "Measured by the 2026-11-12 shape census over mm jobs, excluding 1,091 legacy tp.* template copies: 263 SAS programs in 56 studies. REPEATED alone 38 studies, both statements 15, RANDOM alone 7. type=cs in 37 studies. In flight until a corpus job ported on lri matches its SAS estimates."
```

In `.lintr`, after the `rm-linear.qmd` key, add:

```r
    "inst/templates/30_analyses/mm.qmd" = list(
      object_name_linter = Inf,
      commented_code_linter = Inf,
      object_usage_linter = Inf
    ),
```

In `DESCRIPTION`, add `nlme,` to `Suggests` in alphabetical position.

Regenerate the roadmap and run the guards:

```bash
python3 dev/specs/artifacts/roadmap_render.py
python3 dev/specs/artifacts/check-roadmap-counts.py
python3 dev/specs/artifacts/check-spec-counts.py
```

Expected: `Catalog agrees with disk: 75 template rows routed to hvtiRtemplates, 49 on disk.`, and the spec check passes.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-mm-template.R")'`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add inst/templates/30_analyses/mm.qmd inst/extdata/templates.json .lintr DESCRIPTION \
  dev/specs/2026-08-29-template-conversion-roadmap.md tests/testthat/test-mm-template.R
git commit -m "mm: template skeleton with its study choices, catalogued in flight"
```

---

### Task 3: Guards, fit and predictions (`mm-helpers`)

**Files:**
- Modify: `inst/templates/30_analyses/mm.qmd` (add the `mm-helpers` chunk after `tbl-data`)
- Modify: `dev/specs/2026-11-12-mm-template-design.md` §6 (the amendment)
- Test: `tests/testthat/test-mm-template.R`

**Interfaces:**
- Produces, all defined in the `mm-helpers` chunk:
  - `mm_check(d, id, time, structure, imputation)`: returns `invisible(TRUE)` or stops;
  - `mm_fit(d, formula, id, time, structure, method)`: returns `list(model, structure, method, formula, n_patients, n_measurements)`;
  - `mm_covariance(fit)`: returns `data.frame(parameter, estimate)`;
  - `mm_predict(fit, newdata, scale)`: returns `newdata` plus `estimate`, `lower`, `upper`;
  - `mm_grid(d, predictors, time, predict_at, predict_times)`: returns the prediction data frame.

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-mm-template.R`:

```r
mm_formula <- log(y) ~ log(time + 1) + age + female

test_that("mm_check stops on data that is not longitudinal", {
  h <- mm_helpers()
  d <- mm_data()
  expect_true(h$mm_check(d, "ccfid", "time", "cs", NULL))
  one <- d[!duplicated(d$ccfid), ]
  expect_error(h$mm_check(one, "ccfid", "time", "cs", NULL), "one row per patient")
})

test_that("mm_check stops on a missing or negative time", {
  h <- mm_helpers()
  d <- mm_data()
  d$time[[1L]] <- NA
  expect_error(h$mm_check(d, "ccfid", "time", "cs", NULL), "TIME")
  d$time[[1L]] <- -1
  expect_error(h$mm_check(d, "ccfid", "time", "cs", NULL), "TIME")
})

test_that("mm_check refuses AR(1) and UN on free times, and accepts them on visits", {
  h <- mm_helpers()
  d <- mm_data()
  expect_error(h$mm_check(d, "ccfid", "time", "ar1", NULL), "20 distinct")
  expect_error(h$mm_check(d, "ccfid", "time", c("cs", "un"), NULL), "20 distinct")
  d$time <- stats::ave(d$time, d$ccfid, FUN = seq_along)
  expect_true(h$mm_check(d, "ccfid", "time", "ar1", NULL))
})

test_that("mm_check refuses an unknown structure and any imputation column", {
  h <- mm_helpers()
  d <- mm_data()
  expect_error(h$mm_check(d, "ccfid", "time", "sp(pow)", NULL), "STRUCTURE")
  expect_error(h$mm_check(d, "ccfid", "time", "cs", "imp"), "IMPUTATION")
})

test_that("mm_fit with cs recovers the correlation and the time effect", {
  h <- mm_helpers()
  fit <- h$mm_fit(mm_data(), mm_formula, "ccfid", "time", "cs", "REML")
  expect_s3_class(fit$model, "gls")
  cov <- h$mm_covariance(fit)
  rho <- cov$estimate[cov$parameter == "within-patient correlation"]
  expect_equal(rho, 0.5, tolerance = 0.1)
  est <- summary(fit$model)$tTable["log(time + 1)", ]
  expect_lt(abs(est[["Value"]] - 0.2), 2 * est[["Std.Error"]])
  expect_identical(fit$n_patients, 200L)
})

test_that("every STRUCTURE fits", {
  h <- mm_helpers()
  d <- mm_data()
  d$time <- stats::ave(d$time, d$ccfid, FUN = seq_along)
  f <- log(y) ~ time + age + female
  for (s in c("cs", "ar1", "un", "random", "random+cs", "random+ar1")) {
    fit <- h$mm_fit(d, f, "ccfid", "time", s, "REML")
    expect_true(is.finite(stats::AIC(fit$model)), info = s)
    expect_gt(nrow(h$mm_covariance(fit)), 0L)
  }
})

test_that("mm_predict back-transforms the log scale and keeps the limits around the estimate", {
  h <- mm_helpers()
  d <- mm_data()
  fit <- h$mm_fit(d, mm_formula, "ccfid", "time", "cs", "REML")
  grid <- h$mm_grid(d, c("age", "female"), "time", NULL, c(0, 5, 10))
  expect_identical(nrow(grid), 3L)
  log_scale <- h$mm_predict(fit, grid, "identity")
  natural <- h$mm_predict(fit, grid, "log")
  expect_equal(natural$estimate, exp(log_scale$estimate))
  expect_equal(natural$lower, exp(log_scale$lower))
  expect_true(all(natural$lower < natural$estimate & natural$estimate < natural$upper))
  expect_equal(natural$estimate[[1L]], exp(3 + 0.01 * (stats::median(d$age) - 60)), tolerance = 0.05)
})

test_that("mm_grid uses the profiles and times it is given", {
  h <- mm_helpers()
  d <- mm_data()
  grid <- h$mm_grid(d, c("age", "female"), "time",
                    list(list(age = 50, female = 0), list(age = 70, female = 1)), NULL)
  expect_identical(nrow(grid), 100L)
  expect_identical(sort(unique(grid$age)), c(50, 70))
  expect_equal(range(grid$time), range(d$time))
})
```

- [ ] **Step 2: Run them to verify they fail**

Run: `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-mm-template.R")'`
Expected: FAIL; the `mm-helpers` chunk is not found.

- [ ] **Step 3: Add the `mm-helpers` chunk**

Insert after the `tbl-data` chunk in `inst/templates/30_analyses/mm.qmd`:

````markdown
```{r}
#| label: mm-helpers
# The fit lives here rather than in a package until a second longitudinal template
# (mp or gm) shows what a package function should be; see the design note.
.mm_structures <- c("cs", "ar1", "un", "random", "random+cs", "random+ar1")

# Each check stops on data the fit would accept and then get wrong without saying so.
mm_check <- function(d, id, time, structure, imputation) {
  bad <- setdiff(structure, .mm_structures)
  if (length(bad)) {
    stop("STRUCTURE ", paste(dQuote(bad, FALSE), collapse = ", "), " is not one of ",
         paste(dQuote(.mm_structures, FALSE), collapse = ", "), ". Change it in edit-study-choices.", call. = FALSE)
  }
  if (!is.null(imputation)) {
    stop("IMPUTATION is set, and this job does not pool imputations: a fit to stacked imputations ",
         "would count every patient once per imputation. Set IMPUTATION <- NULL.", call. = FALSE)
  }
  if (max(table(d[[id]])) < 2L) {
    stop("Every patient has one row per patient, so there is nothing repeated to model. ",
         "KEY should include TIME, and the data should hold every measurement.", call. = FALSE)
  }
  t <- d[[time]]
  if (anyNA(t) || any(t < 0)) {
    stop("TIME (", time, ") has ", sum(is.na(t) | (!is.na(t) & t < 0)),
         " missing or negative values. Every measurement needs its time since the reference event.", call. = FALSE)
  }
  if (any(c("ar1", "un", "random+ar1") %in% structure) && length(unique(t)) > 20L) {
    stop("STRUCTURE asks for AR(1) or UN, which assume shared, ordered visits, but TIME has ",
         length(unique(t)), " distinct values, more than 20 distinct visits. Use \"cs\" or \"random\" for free ",
         "times, or set TIME to a visit number.", call. = FALSE)
  }
  invisible(TRUE)
}

mm_fit <- function(d, formula, id, time, structure, method) {
  d <- d[order(d[[id]], d[[time]]), , drop = FALSE]
  d$.order <- stats::ave(seq_len(nrow(d)), d[[id]], FUN = seq_along)
  d$.visit <- factor(d$.order)
  by_id <- function(lhs) stats::as.formula(paste(lhs, "|", id))
  corr <- switch(structure,
    cs = , `random+cs` = nlme::corCompSymm(form = by_id("~ 1")),
    ar1 = , `random+ar1` = nlme::corAR1(form = by_id("~ .order")),
    un = nlme::corSymm(form = by_id("~ .order")),
    random = NULL
  )
  model <- if (startsWith(structure, "random")) {
    nlme::lme(formula, data = d, random = by_id("~ 1"), correlation = corr, method = method,
              na.action = stats::na.omit)
  } else {
    nlme::gls(formula, data = d, correlation = corr, method = method, na.action = stats::na.omit,
              weights = if (identical(structure, "un")) nlme::varIdent(form = ~ 1 | .visit))
  }
  used <- stats::complete.cases(d[all.vars(formula)])
  # The levels of each categorical predictor, so a prediction grid holding one level still codes it as the fit did.
  categorical <- Filter(function(x) is.factor(x) || is.character(x), d[intersect(all.vars(formula), names(d))])
  list(model = model, structure = structure, method = method, formula = formula,
       xlev = lapply(categorical, function(x) levels(factor(x))),
       n_patients = length(unique(d[[id]][used])), n_measurements = sum(used))
}

# The covariance parameters, with the within-patient correlation stated once for every structure.
mm_covariance <- function(fit) {
  m <- fit$model
  out <- list()
  if (inherits(m, "lme")) {
    vc <- suppressWarnings(as.numeric(nlme::VarCorr(m)[, "Variance"]))
    out[["between-patient variance"]] <- vc[[1L]]
    out[["residual variance"]] <- vc[[length(vc)]]
    if (identical(fit$structure, "random")) out[["within-patient correlation"]] <- vc[[1L]] / sum(vc)
  } else {
    out[["residual variance"]] <- m$sigma^2
  }
  cs <- m$modelStruct$corStruct
  if (!is.null(cs)) {
    rho <- stats::coef(cs, unconstrained = FALSE)
    label <- if (fit$structure %in% c("cs", "random+cs")) "within-patient correlation" else "correlation"
    for (i in seq_along(rho)) out[[if (length(rho) == 1L) label else paste(label, names(rho)[[i]])]] <- rho[[i]]
  }
  data.frame(parameter = names(out), estimate = unname(unlist(out)), row.names = NULL)
}

# The covariate profiles crossed with the prediction times.
mm_grid <- function(d, predictors, time, predict_at, predict_times) {
  times <- if (is.null(predict_times)) {
    seq(min(d[[time]]), max(d[[time]]), length.out = 50L)
  } else {
    predict_times
  }
  if (is.null(predict_at)) {
    predict_at <- list(lapply(stats::setNames(predictors, predictors), function(v) {
      x <- d[[v]]
      if (is.numeric(x)) stats::median(x, na.rm = TRUE) else sort(unique(x))[[1L]]
    }))
  }
  grid <- do.call(rbind, lapply(seq_along(predict_at), function(i) {
    row <- as.data.frame(predict_at[[i]], stringsAsFactors = FALSE)
    out <- row[rep(1L, length(times)), , drop = FALSE]
    out[[time]] <- times
    out$profile <- i
    out
  }))
  rownames(grid) <- NULL
  grid
}

# Population-average predictions: the fixed effects alone, with 95% limits from their
# covariance on the linear predictor, back-transformed when the response is logged.
mm_predict <- function(fit, newdata, scale) {
  fixed <- stats::delete.response(stats::terms(fit$formula))
  x <- stats::model.matrix(fixed, stats::model.frame(fixed, newdata, xlev = fit$xlev))
  # nlme::fixef() has no gls method; coef() of a gls is its fixed effects.
  beta <- if (inherits(fit$model, "lme")) nlme::fixef(fit$model) else stats::coef(fit$model)
  v <- stats::vcov(fit$model)
  eta <- drop(x %*% beta)
  se <- sqrt(rowSums((x %*% v) * x))
  z <- stats::qnorm(0.975)
  back <- if (identical(scale, "log")) exp else identity
  cbind(newdata, estimate = back(eta), lower = back(eta - z * se), upper = back(eta + z * se))
}
```
````

- [ ] **Step 4: Run them to verify they pass**

Run: `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-mm-template.R")'`
Expected: PASS (11 tests).

- [ ] **Step 5: Prove the guards by mutation**

Comment out each `stop()` branch of `mm_check()` in turn and confirm its test goes red; restore it each time:

```bash
bak=$(mktemp) && cp inst/templates/30_analyses/mm.qmd "$bak"
sed -i '' 's/if (max(table(d\[\[id\]\])) < 2L)/if (FALSE)/' inst/templates/30_analyses/mm.qmd
Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-mm-template.R")' | grep -E "FAIL|one row per patient"
cp "$bak" inst/templates/30_analyses/mm.qmd
```

Expected: the "not longitudinal" test fails while mutated. Repeat for the TIME, 20-distinct and IMPUTATION branches.

- [ ] **Step 6: Amend spec §6**

In `dev/specs/2026-11-12-mm-template-design.md` §6, replace the first bullet under "The job saves two files" with:

```markdown
- `estimates/mm.rds`: the coefficients, their covariance, the report's tables, the
  predictions and the study choices, in a bundle whose `meta$id_col` names the ID
  column. It holds no `nlme` object, because an `nlme` fit carries the patient ID
  as its grouping factor (`$groups`, and inside its correlation structure), where
  `.digest_bundle_ids()` cannot reach it. A study needing the model refits it from
  the job.
```

- [ ] **Step 7: Commit**

```bash
git add inst/templates/30_analyses/mm.qmd tests/testthat/test-mm-template.R dev/specs/2026-11-12-mm-template-design.md
git commit -m "mm: guards, nlme fit for every STRUCTURE, and back-transformed predictions"
```

---

### Task 4: Report, saved bundle and end-to-end render

**Files:**
- Modify: `inst/templates/30_analyses/mm.qmd` (the chunks after `mm-helpers`)
- Modify: `tests/testthat/helper-mm.R` (the render fixture)
- Test: `tests/testthat/test-mm-template.R`

**Interfaces:**
- Consumes: `mm_check`, `mm_fit`, `mm_covariance`, `mm_grid`, `mm_predict` (Task 3); `.attach_handoff_lineage()`, `.digest_bundle_ids()`, `.embed_provenance()`.
- Produces: chunk labels `fit`, `tbl-counts`, `tbl-estimates`, `tbl-covariance`, `tbl-compare`, `tbl-predictions`, `save`, `provenance`; `MODEL_PATH`, `PREDICTIONS_PATH`; `mm_render_fixture()`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/helper-mm.R`:

```r
# Scaffold an mm job in a fresh study holding mm_data(), work its EDIT: markers and render it.
mm_render_fixture <- function(choices = character(), .local_envir = parent.frame()) {
  root <- tempfile("mm-study-")
  withr::defer(unlink(root, recursive = TRUE), envir = .local_envir)
  suppressMessages(hvtiRutilities::study_setup(root, study = "Synthetic mm study", study_tracker_id = 42L, renv = FALSE))
  utils::write.csv(mm_data(), file.path(hvtiRutilities::study_dir("datasets", root), "built.csv"), row.names = FALSE)
  suppressMessages(hvtiRutilities::register_data(root, file = "built.csv", role = "study",
                                                 population = "Synthetic cohort", key = c("ccfid", "time")))
  job <- add_job("mm", "outcome", "mixed", dir = root)
  lines <- gsub("EDIT:", "REVIEWED:", readLines(job, warn = FALSE), fixed = TRUE)
  defaults <- c('OUTCOME <- "y"', 'RESPONSE_SCALE <- "log"', 'TIME_TERMS <- c("log(time + 1)")')
  for (replacement in c(defaults, choices)) {
    key <- sub(" .*", "", replacement)
    lines[which(grepl(paste0("^", key, " <- "), lines))[1L]] <- replacement
  }
  writeLines(lines, job)
  quarto::quarto_render(job, execute_dir = dirname(job), quiet = TRUE)
  list(root = root, job = job, output = sub("[.]qmd$", ".html", job))
}
```

Append to `tests/testthat/test-mm-template.R`:

```r
test_that("mm renders end to end and saves a bundle with no nlme object and no raw IDs", {
  skip_on_cran()
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  out <- mm_render_fixture()
  expect_true(file.exists(out$output))
  set <- file.path(hvtiRutilities::study_dir("estimates", out$root), "outcome-mixed")
  bundle <- readRDS(file.path(set, "mm.rds"))
  expect_false(any(vapply(bundle, function(x) inherits(x, c("gls", "lme")), logical(1L))))
  expect_true(bundle$meta$id_digest)
  expect_identical(bundle$meta$structure, "cs")
  pred <- utils::read.csv(file.path(set, "mm-predictions.csv"))
  expect_identical(nrow(pred), 50L)
  expect_true(all(pred$lower < pred$estimate & pred$estimate < pred$upper))
  html <- paste(readLines(out$output, warn = FALSE), collapse = "\n")
  expect_match(html, "within-patient correlation", fixed = TRUE)
  expect_no_match(html, "Comparison of covariance structures", fixed = TRUE)
})

test_that("mm compares structures only when STRUCTURE lists several", {
  skip_on_cran()
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  out <- mm_render_fixture(choices = 'STRUCTURE <- c("cs", "random")')
  html <- paste(readLines(out$output, warn = FALSE), collapse = "\n")
  expect_match(html, "Comparison of covariance structures", fixed = TRUE)
})
```

- [ ] **Step 2: Run them to verify they fail**

Run: `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-mm-template.R")'`
Expected: FAIL; the render produces no `mm.rds`. If `register_data()` refuses `key = c("ccfid", "time")`, read `?hvtiRutilities::register_data` and use the form it documents, then rerun.

- [ ] **Step 3: Add the report and save chunks**

Append to `inst/templates/30_analyses/mm.qmd`:

````markdown
```{r}
#| label: fit
mm_check(d, .id, TIME, STRUCTURE, IMPUTATION)
model_formula <- stats::reformulate(c(TIME_TERMS, PREDICTORS), response = .response)
fits <- lapply(stats::setNames(STRUCTURE, STRUCTURE), function(s) mm_fit(d, model_formula, .id, TIME, s, METHOD))
fit <- fits[[1L]]
```

```{r}
#| label: model-scale
#| results: asis
cat(hvtiRtemplates:::.response_note(model_formula, RESPONSE_SCALE, "outcome"))
cat("\n\nThe reported model is the ", dQuote(STRUCTURE[[1L]], FALSE), " structure, fitted by ", METHOD, ".\n", sep = "")
```

```{r}
#| label: tbl-counts
#| tbl-cap: "Patients and measurements in the fit"
.per <- table(d[[.id]])
knitr::kable(data.frame(
  quantity = c("patients", "measurements", "measurements per patient, median", "measurements per patient, range"),
  value = c(fit$n_patients, fit$n_measurements, stats::median(.per), paste(range(.per), collapse = " to "))
))
```

```{r}
#| label: tbl-estimates
#| tbl-cap: "Fixed-effect estimates of the reported model"
.tt <- summary(fit$model)$tTable
estimates <- data.frame(term = rownames(.tt), estimate = .tt[, "Value"], std_error = .tt[, "Std.Error"],
                        p_value = .tt[, "p-value"], row.names = NULL)
knitr::kable(estimates, digits = 4)
```

```{r}
#| label: tbl-covariance
#| tbl-cap: "Covariance parameters of the reported model"
covariance <- mm_covariance(fit)
knitr::kable(covariance, digits = 4)
```

```{r}
#| label: tbl-compare
#| results: asis
# AIC and BIC compare covariance structures fairly under REML only because every
# fit here has the same fixed effects; a table of different fixed effects needs ML.
comparison <- NULL
if (length(fits) > 1L) {
  comparison <- data.frame(structure = names(fits),
                           AIC = vapply(fits, function(f) stats::AIC(f$model), numeric(1L)),
                           BIC = vapply(fits, function(f) stats::BIC(f$model), numeric(1L)), row.names = NULL)
  cat(knitr::knit_print(knitr::kable(comparison, digits = 1,
                                     caption = "Comparison of covariance structures, same fixed effects")), sep = "\n")
}
```

```{r}
#| label: tbl-predictions
#| tbl-cap: "Population-average course of the response, first and last times of each profile"
predictions <- mm_predict(fit, mm_grid(d, PREDICTORS, TIME, PREDICT_AT, PREDICT_TIMES), RESPONSE_SCALE)
.ends <- predictions[!duplicated(predictions$profile) | !duplicated(predictions$profile, fromLast = TRUE), ]
knitr::kable(.ends, digits = 3, row.names = FALSE)
```

```{r}
#| label: save
MODEL_PATH <- set_path("estimates", "mm.rds")
PREDICTIONS_PATH <- set_path("estimates", "mm-predictions.csv")
utils::write.csv(predictions, PREDICTIONS_PATH, row.names = FALSE)
# No nlme object is saved: it carries the patient ID as its grouping factor.
bundle <- list(
  meta = list(id_col = .id, outcome = OUTCOME, response_scale = RESPONSE_SCALE, time = TIME, time_terms = TIME_TERMS,
              predictors = PREDICTORS, structure = fit$structure, method = METHOD,
              formula = paste(deparse(model_formula), collapse = " "), n_patients = fit$n_patients,
              n_measurements = fit$n_measurements, nlme_version = as.character(utils::packageVersion("nlme"))),
  coefficients = if (inherits(fit$model, "lme")) nlme::fixef(fit$model) else stats::coef(fit$model),
  vcov = stats::vcov(fit$model),
  tables = list(estimates = estimates, covariance = covariance, comparison = comparison),
  predictions = predictions
)
.analysis <- list(outcome = list(variable = OUTCOME, scale = RESPONSE_SCALE),
                  model = list(engine = "nlme", structure = fit$structure, method = METHOD, formula = bundle$meta$formula))
.cohort <- list(patients = fit$n_patients, measurements = fit$n_measurements)
bundle <- hvtiRtemplates:::.attach_handoff_lineage(
  bundle, data = if (exists(".provenance_data")) .provenance_data else list(),
  analysis = .analysis, cohort = .cohort, selection = attr(job_data$record, "selection")
)
saveRDS(hvtiRtemplates:::.digest_bundle_ids(bundle, .root), MODEL_PATH)
```

```{r}
#| label: provenance
#| echo: false
#| results: asis
cat(hvtiRtemplates:::.embed_provenance(
  .in,
  data = .provenance_data,
  run = .job$run,
  extra = list(subject = SUBJECT, type = TYPE, analysis = .analysis, cohort = .cohort)
))
```
````

- [ ] **Step 4: Run them to verify they pass**

Run: `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-mm-template.R")'`
Expected: PASS (13 tests). Renders use the installed package; per the project memory on render tests, install this branch into a private library first and run with that library ahead of the default:

```bash
lib=$(mktemp -d) && R CMD INSTALL -l "$lib" .
R_LIBS="$lib" Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-mm-template.R")'
```

- [ ] **Step 5: Run the template-wide tests**

Run: `Rscript -e 'devtools::test(filter = "add-job|template-format|roadmap|taxonomy|mm")'`
Expected: PASS, with no study identifier found in `mm.qmd`.

- [ ] **Step 6: Commit**

```bash
git add inst/templates/30_analyses/mm.qmd tests/testthat/helper-mm.R tests/testthat/test-mm-template.R
git commit -m "mm: report tables, saved bundle and predictions, rendered end to end"
```

---

### Task 5: Documentation, full check and pull request

**Files:**
- Modify: `inst/templates/README.md`
- Create: `news/chore-mm-census.md`

- [ ] **Step 1: README**

In `inst/templates/README.md`, add a row to the template table beside `rm-linear`:

```markdown
| `30_analyses/mm.qmd` | linear mixed model of a repeated continuous response, with its population-average course over time | `30_analyses/` or `analyses/` |
```

and change the sentence at line 149 that begins "Mixed," so it reads: "Mixed models are `mm`; generalized and non-linear models belong to `gm` and `nm`." Remove `mm` from the untemplated list near line 245 if it is named there.

- [ ] **Step 2: News fragment**

Create `news/chore-mm-census.md`:

```markdown
* New template `mm`: a linear mixed model of a repeated continuous response, fitted
  with `nlme`. `STRUCTURE` chooses the within-patient correlation, as PROC MIXED's
  REPEATED and RANDOM statements did (`"cs"`, the corpus default, `"ar1"`, `"un"`,
  `"random"`, and the two combined forms), and the job saves the population-average
  course over time with 95% limits, back-transformed from the log scale, for a plot.
  It does not yet pool multiple imputations, and stops if `IMPUTATION` is set.
```

- [ ] **Step 3: Document, lint and check**

```bash
Rscript -e 'devtools::document()'
Rscript -e 'lintr::lint_package()'
Rscript -e 'devtools::check()'
```

Expected: `document()` changes nothing; no lints; check `0 errors ✔ | 0 warnings ✔ | 0 notes ✔`. Read the testthat summary line: `SKIP` must not rise above `main`'s count except by the two new `skip_on_cran()` render tests under a CRAN-mode check.

- [ ] **Step 4: Local review, then commit and open the PR**

Run `/code-review` on the branch diff against `origin/main`, and fix what it confirms. Then:

```bash
git add inst/templates/README.md news/chore-mm-census.md
git commit -m "mm: README row and news fragment"
git push -u origin chore/mm-census
gh pr create --base main --title "mm: mixed-model template, with its shape census and design" --body-file /tmp/mm-pr.md
```

The PR body states that the local `/code-review` stood in for Copilot, lists the census numbers, and says the catalog reads `in-flight` until Task 6.

---

### Task 6: The ship gate, on lri (John)

Not code. It turns `in-flight` into `shipped`.

- [ ] **Step 1:** Choose one `repeated_covariance` job with `type=cs` from the private CSV, `general/_development/mm-shape-census-20261112/out/mm-shapes-private.csv`, whose `.lst` is beside it.
- [ ] **Step 2:** On lri, in a scratch folder under `/studies/general/_development/mm-port-20261112/`, scaffold `add_job("mm", ...)`, set its study choices to the SAS job's model, and render it.
- [ ] **Step 3:** Compare the fixed effects and the CS covariance parameter with the SAS `.lst`. They agree to the printed precision, since both fit by REML.
- [ ] **Step 4:** If they agree, set the `mm` row's `status` to `"shipped"`, drop the last sentence of its `note`, regenerate the roadmap, and commit on the PR branch. If they do not, the difference goes in the PR before anything ships.
