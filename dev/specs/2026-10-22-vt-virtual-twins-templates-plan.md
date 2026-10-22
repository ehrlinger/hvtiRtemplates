# `vt` templates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `vt-fit.qmd` (eligibility by a choice of methods, one survival forest per arm, swapped-arm twin curves and a per-patient RMST difference) and `vt-explain.qmd` (the contrast, its sensitivity to eligibility, an optional stratifier, standardized betas and who might benefit) under the existing `vt` prefix, both at ledger status `in-flight`.

**Architecture:** Two self-contained Quarto templates in `inst/templates/30_analyses/`, built from the Virtual Twins study's notebook chapters 03 to 08 and report chapters 05 to 08. The method helpers (`vt_ood()`, `vt_elig_gower()`, `vt_elig_sid()`, `vt_combine()`, `vt_curves()`, `vt_rmst()`) live in chunks of their own inside `vt-fit`, as `vp_judge()` does in `vp-fit`, until `hvtiRforests` exists. `vt-fit` saves one handoff, `vt.rds`; `vt-explain` reads it and never grows a forest. `vt` is already in `hvti_taxonomy()`, so this is one repository and no cross-repo order.

**Tech Stack:** R, Quarto, randomForestSRC 3.9.0, cluster (`daisy()`), survival (`concordance()`), hvtiRpropensity (`ps_forest()`, `ps_support()`), hvtiPlotR (`hv_rmst_curves()`), hvtiRutilities (`cache_fit()`), testthat edition 3.

**Spec:** [`2026-10-22-vt-virtual-twins-templates-design.md`](2026-10-22-vt-virtual-twins-templates-design.md).

## Global Constraints

- Never push to `main`. Every task's changes go on branch `feat/vt-templates`, cut from `origin/main` after `git fetch`, never from local `main`: other sessions merge here concurrently. One PR for Tasks 1 to 6.
- Versions are three digits. No PR touches `Version:` or `NEWS.md`. The PR ships files, so it adds `news/feat-vt-templates.md` holding its bullet(s) and no heading.
- Roxygen is Rd markup (no markdown). Lines are at most 135 characters (`.lintr`).
- A template carries its own `format:` block (copy `vp-fit.qmd`'s verbatim), opens with ONE `setup` chunk, has exactly one `^SUBJECT\s+<- ` and one `^TYPE\s+<- ` line, puts every `EDIT:` marker in a chunk labeled `edit-…`, carries no study identifiers (no study name, no `/studies/`, no built-dataset filename, no "AVSD", "BVR", "UVR", "Fontan"), and ends with one `provenance` chunk.
- Each template gets its own **file** key in `.lintr` excluding exactly `object_name_linter`, `commented_code_linter` and `object_usage_linter`.
- Version floors in the templates match `DESCRIPTION`'s `Suggests`: `randomForestSRC (>= 3.7.0)`, `hvtiRpropensity (>= 0.2.0)`, `hvtiPlotR (>= 2.8.9)`. `cluster` is added to `Suggests` with no floor (Task 1).
- `options(rf.cores = 1L, mc.cores = 1L)` in every `setup` chunk.
- Every random call is seeded: `set.seed(SEED)` before it, and `rfsrc()` also gets `seed = -abs(SEED)`.
- Rows are joined by `ID` coerced to character, never by position.
- Tests run the INSTALLED templates chunk by chunk via `rf_run()` (`tests/testthat/helper-rf.R`). Install into a private library before each test run (concurrent sessions overwrite the shared one): `R CMD INSTALL -l "$VT_LIB" . && R_LIBS="$VT_LIB" Rscript -e 'devtools::test(filter = "vt")'`. Tests that grow a forest carry `skip_on_cran()` and use `NTREE = 50`.
- Never `git add -A` after a test run: a failing testthat run writes `tests/testthat/_problems/`. Add files by name.
- Run `/code-review` locally before opening the PR and say in the PR body that it stood in for Copilot, whose credits are exhausted.
- **IDs are digested on read** (`.id_digest()` under `.study_id_key(.root)`), and nothing this job saves holds a raw ID. The `sid` handoff, confirmed with the sid session on 2026-10-22: `<sid set>/sid.rds$dist`, an n x n matrix whose dimnames are ID digests, with `id_key` (the key fingerprint); `<sid set>/sid-clusters.rds$clusters`, `data.frame(id = <digest>, cluster = <letter>)` plus `group` when collapsed, `NULL` until K is set, with `id_key`. Re-read `dev/specs/2026-10-22-sid-templates-design.md` before Task 2 in case it moved.

## File map

| File | Task | Responsibility |
|---|---|---|
| `DESCRIPTION` | 1 | `cluster` in `Suggests` |
| `.lintr` | 1, 4 | file keys for both templates |
| `inst/extdata/templates.json` | 1, 4 | `(vt, NA)` replaced by `(vt, fit)` (1) and `(vt, explain)` (4), both `in-flight` |
| `dev/specs/2026-08-29-template-conversion-roadmap.md` | 1, 4 | regenerated tables |
| `tests/testthat/test-template-catalog.R` | 4 | 68 → 69 rows |
| `inst/templates/30_analyses/vt-fit.qmd` | 1, 2, 3 | the fit |
| `inst/templates/30_analyses/vt-explain.qmd` | 4, 5 | the report |
| `tests/testthat/helper-vt.R` | 1 | `vt_data()`, `vt_choices`, `vt_fit_labels`, `vt_fit_first()` |
| `tests/testthat/test-vt-templates.R` | 1–6 | the vt tests |
| `inst/templates/README.md` | 6 | the two templates listed, figure names |
| `news/feat-vt-templates.md` | 6 | the NEWS fragment |

---

### Task 1: `vt-fit.qmd` skeleton: setup, choices, data, predictors; ledger row

**Files:**
- Create: `inst/templates/30_analyses/vt-fit.qmd`, `tests/testthat/helper-vt.R`, `tests/testthat/test-vt-templates.R`
- Modify: `DESCRIPTION` (Suggests), `.lintr`, `inst/extdata/templates.json`, `dev/specs/2026-08-29-template-conversion-roadmap.md`

**Interfaces:**
- Produces, in the job environment after chunk `predictors`: `d` (data frame, one row per patient, columns `ID`, `ARM`, `TIME`, `STATUS` and the predictors), `.treated` (logical, `ARM` in `ARMS`), `.no_arm` (logical), `.predictors` (character), `.vp_read` (`NULL` or the `.read_handoff()` result).
- Produces for tests: `vt_data(n = 300L, seed = 20261022L)`, `vt_choices` (list), `vt_fit_labels` (character), `vt_fit_first(data, choices, labels)`.

- [ ] **Step 1: Branch and dependency**

```bash
git fetch origin && git switch -c feat/vt-templates origin/main
```

Add `cluster,` to `DESCRIPTION`'s `Suggests` in alphabetical position (no floor). Run `Rscript -e 'packageVersion("cluster")'` and confirm it is installed.

- [ ] **Step 2: Write `helper-vt.R`**

```r
# The vt templates are run chunk by chunk through rf_run() (helper-rf.R).

# Two arms of unequal size with a planted arm-by-covariate effect: high `xs`
# does better on arm "A", low `xs` on arm "B". `x1` and `g1` are null. Five arm
# "A" patients are planted far from every arm "B" patient in `xs`, and ten
# rows have no arm. Seeded, so a test sees the same patients every run.
vt_data <- function(n = 300L, seed = 20261022L) {
  withr::with_seed(seed, {
    arm <- sample(c("A", "B"), n, replace = TRUE, prob = c(0.65, 0.35))
    xs <- stats::rnorm(n)
    d <- data.frame(
      ccfid = seq_len(n), arm = arm, xs = xs, x1 = stats::rnorm(n),
      g1 = factor(sample(c("u", "v", "w"), n, replace = TRUE))
    )
    d$xs[which(d$arm == "A")[1:5]] <- 6 + (1:5) / 10
    lp <- ifelse(d$arm == "A", -1.2 * d$xs, 1.2 * d$xs)
    event_time <- stats::rexp(n, 0.2 * exp(lp))
    censor <- stats::runif(n, 2, 8)
  })
  d$time <- pmin(event_time, censor)
  d$event <- as.integer(event_time <= censor)
  d$arm[(n - 9):n] <- NA
  d
}

vt_choices <- list(
  TIME = "time", STATUS = "event", ID = "ccfid", ARM = "arm", ARMS = c("A", "B"),
  VP_SET = NULL, PREDICTORS = c("xs", "x1", "g1"), EXCLUDE = character(),
  ELIGIBILITY = "gower", COMBINE = "any", SID_SET = NULL,
  NA_ACTION = "na.impute", IMPUTATION = NULL, IMPUTATION_USE = 1L,
  HORIZON = 2, NTREE = 50, NSPLIT = 8, SEED = 1, SAVE_FIGURES = FALSE
)

# Every chunk of vt-fit, in order. Tasks 2 and 3 extend it.
vt_fit_labels <- c("setup", "edit-study-choices", "tbl-data", "predictors")

# The digest the job keys a raw ID by, in a fixture study.
vt_digest <- function(env, ids) hvtiRtemplates:::.id_digest(ids, hvtiRtemplates:::.study_id_key(env$.root))

vt_fit_first <- function(data = vt_data(), choices = vt_choices, labels = vt_fit_labels,
                         .local_envir = parent.frame()) {
  # rf_run() strips library() from setup, so attach the template's own stack
  # (and skip when it is absent) rather than rely on an earlier test having.
  rf_skip_unless_stack(rf_template_packages("vt", "fit"))  # nolint: object_usage_linter.
  env <- rf_env(data, .local_envir)  # nolint: object_usage_linter.
  rf_run("vt", "fit", labels, env, choices)  # nolint: object_usage_linter.
  env
}
```

- [ ] **Step 3: Write the failing tests**

`tests/testthat/test-vt-templates.R`:

```r
test_that("vt-fit reads the cohort and resolves the predictors", {
  skip_on_cran()
  env <- vt_fit_first()
  expect_setequal(env$.predictors, c("xs", "x1", "g1"))
  expect_equal(sum(env$.no_arm), 10L)
  expect_equal(sum(env$.treated), 290L)
})

test_that("the predictor contract refuses the arm, the outcome and the ID", {
  skip_on_cran()
  for (leak in c("arm", "time", "event", "ccfid")) {
    ch <- utils::modifyList(vt_choices, list(PREDICTORS = c("xs", leak)))
    expect_error(vt_fit_first(choices = ch), "PREDICTORS", info = leak)
  }
})

test_that("patient IDs are digested on read", {
  skip_on_cran()
  env <- vt_fit_first()
  expect_identical(env$d[[env$ID]][1:3],
                   hvtiRtemplates:::.id_digest(1:3, hvtiRtemplates:::.study_id_key(env$.root)))
})

test_that("EXCLUDE drops post-treatment columns", {
  skip_on_cran()
  ch <- utils::modifyList(vt_choices, list(EXCLUDE = "x1"))
  expect_setequal(vt_fit_first(choices = ch)$.predictors, c("xs", "g1"))
})

test_that("na.omit drops and counts patients missing a predictor", {
  skip_on_cran()
  d <- vt_data(); d$x1[1:3] <- NA
  env <- vt_fit_first(data = d, choices = utils::modifyList(vt_choices, list(NA_ACTION = "na.omit")))
  expect_equal(nrow(env$d), 297L)
})

test_that("with stacked imputations only IMPUTATION_USE reaches the job", {
  skip_on_cran()
  d1 <- vt_data(); d1$imp <- 1L
  d2 <- vt_data(); d2$imp <- 2L; d2$xs <- d2$xs + 100
  ch <- utils::modifyList(vt_choices, list(IMPUTATION = "imp", IMPUTATION_USE = 2L))
  env <- vt_fit_first(data = rbind(d1, d2), choices = ch)
  expect_equal(nrow(env$d), 300L)
  expect_gt(min(env$d$xs), 90)
})
```

- [ ] **Step 4: Run them to verify they fail**

Run: `R CMD INSTALL -l "$VT_LIB" . && R_LIBS="$VT_LIB" Rscript -e 'devtools::test(filter = "vt")'`
Expected: FAIL, `template_path("vt", "fit")` finds no template.

- [ ] **Step 5: Write `vt-fit.qmd` through `predictors`**

YAML: `title: "Virtual twins: fit"` and `vp-fit.qmd`'s `date`, comment and `format:` block verbatim. Then a short introduction: what a virtual twin is (two predicted curves per patient, one per arm, each from a forest grown on that arm alone), and that the RMST difference to `HORIZON` is the patient's estimated effect.

`setup` chunk, following `vp-fit.qmd`'s setup chunk line for line except:

```r
SUBJECT <- "dead"
TYPE    <- "vt"
.in <- knitr::current_input(dir = TRUE)
suppressPackageStartupMessages({
  library(randomForestSRC)
  library(cluster)
  library(hvtiRpropensity)
  library(hvtiPlotR)
  library(hvtiRutilities)
})
# One thread, so a fit reproduces from machine to machine. Left unset,
# randomForestSRC runs on every core its OpenMP build can see, and the forests
# changed with the thread count with every seed held fixed.
options(rf.cores = 1L, mc.cores = 1L)
```

followed by the floor checks for `randomForestSRC` 3.7.0, `hvtiRpropensity` 0.2.0 and `hvtiPlotR` 2.8.9 in `vp-fit`'s form, then `.job_setup()`, `.root`, `set_path`, `.provenance_data`, `save_figure()` and `.job$notice` exactly as `vp-fit` has them.

`## Study choices` and chunk `edit-study-choices`:

```r
DATASET <- "study"                          # EDIT: the dataset, as named in _study.yml.
ANALYSIS_SET <- NULL
WHERE <- NULL
ID <- "ccfid"                               # EDIT: the patient identifier.
KEY <- NULL
JOIN <- NULL
JOIN_VARS <- NULL
REDUCE <- NULL
JOIN_KEY <- NULL
TIME <- "iv_dead"                           # EDIT: follow-up time.
STATUS <- "dead"                            # EDIT: the event, coded 0/1.
ARM <- "treatment"                          # EDIT: the treatment arm.
# EDIT: the two arms, in the order the difference is taken: a positive diff
# favours ARMS[1].
ARMS <- c("arm1", "arm2")
# EDIT: rows that received neither arm are predicted under both and fit by
# neither. NULL treats a missing ARM as no arm; a vector of levels names them.
NO_ARM <- NULL
# EDIT: a vp-fit set ("<subject>-<type>") whose selected set the forests use,
# or NULL to use PREDICTORS. The screen must not have seen the arm: that is what
# makes it treatment-blind, and this job checks it.
VP_SET <- NULL
PREDICTORS <- c("age", "sex")               # EDIT: used when VP_SET is NULL.
# EDIT: anything measured after the treatment decision. A screen does not know
# when a variable was measured, and a later procedure flag predicts the outcome
# because it is part of the path to it.
EXCLUDE <- character()
# EDIT: eligibility methods, one or more of "gower" and "sid". "sid" reads the
# SID distance of the sid set named in SID_SET.
ELIGIBILITY <- "gower"
COMBINE <- "any"                            # EDIT: "any" flags a patient any method flags; "all" only when all do.
SID_SET <- NULL                             # EDIT: a sid set ("<subject>-<type>") when ELIGIBILITY has "sid".
# EDIT: "na.impute" imputes missing predictors inside each forest; "na.omit"
# drops the patient. The outcome is required either way.
NA_ACTION <- "na.impute"
# EDIT: for stacked multiple imputations, the column numbering them. This
# release uses one completed dataset, IMPUTATION_USE; pooling is not done.
IMPUTATION <- NULL
IMPUTATION_USE <- 1L
# EDIT: the RMST horizon, in TIME's units. Keep it inside the follow-up of both
# arms; past the last follow-up every curve is cut at the same place and the
# difference means nothing. This job stops if it is not.
HORIZON <- 4
NTREE <- 1000                               # EDIT: trees per arm forest.
NSPLIT <- 8
SEED <- 1024                                # EDIT: part of every cache key.
REFIT <- FALSE
SAVE_FIGURES <- TRUE
FIGURES <- NULL
```

with the `REFIT` and `SAVE_FIGURES` comments copied from `vp-fit`.

Chunk `tbl-data`: `verify_manifest()`, `read_job_data(..., one_row_per_patient = TRUE, imputation = IMPUTATION)` and the provenance lines as in `vp-fit`'s `tbl-data`, then:

```r
if (!is.null(IMPUTATION)) {
  IMPUTATION <- attr(job_data$record, "selection")$imputation
  .m <- length(unique(d[[IMPUTATION]]))
  if (!IMPUTATION_USE %in% d[[IMPUTATION]]) {
    stop("IMPUTATION_USE = ", IMPUTATION_USE, " is not an imputation in ", IMPUTATION, ".", call. = FALSE)
  }
  d <- d[d[[IMPUTATION]] == IMPUTATION_USE, setdiff(names(d), IMPUTATION), drop = FALSE]
  cat("This job uses imputation ", IMPUTATION_USE, " of ", .m, ". The forests are not pooled across imputations.\n",
      sep = "")
}
# read_job_data() matches ID case-insensitively and falls back from ccfid to an
# MRN, without changing ID here. Take the name it resolved.
ID <- attr(job_data$record, "selection")$id
# This job saves one row per patient (vt.rds), and a sid set joins on it. No
# saved artifact holds a raw identifier, an MRN least of all (#203), so the ID
# is replaced here by its digest under the study's key, the form a sid set
# saves too. Everything below, and everything saved, carries only the digest.
.id_key <- hvtiRtemplates:::.study_id_key(.root)
d[[ID]] <- hvtiRtemplates:::.id_digest(d[[ID]], .id_key)
.no_arm <- if (is.null(NO_ARM)) is.na(d[[ARM]]) else d[[ARM]] %in% NO_ARM
.treated <- d[[ARM]] %in% ARMS
.other <- !.no_arm & !.treated
if (any(.other)) {
  stop(sum(.other), " row(s) have an ARM that is neither in ARMS nor NO_ARM: ",
       paste(unique(d[[ARM]][.other]), collapse = ", "), ".", call. = FALSE)
}
if (!all(d[[STATUS]][.treated] %in% c(0, 1))) stop(STATUS, " must be coded 0 and 1.", call. = FALSE)
.no_outcome <- .treated & (is.na(d[[TIME]]) | is.na(d[[STATUS]]))
if (any(.no_outcome)) {
  stop(sum(.no_outcome), " treated patient(s) have no outcome. A forest cannot learn from them, and imputing one ",
       "would invent follow-up. Resolve them in the dataset build.", call. = FALSE)
}
```

and a `knitr::kable()` of patients and events by arm plus the no-arm count.

Chunk `predictors`:

```r
.vp_read <- NULL
if (!is.null(VP_SET)) {
  .vp_path <- file.path(dirname(dirname(set_path("estimates", "vt.rds"))), VP_SET, "vp.rds")
  if (!file.exists(.vp_path)) stop("No vp-fit screen at ", .vp_path, ". Render that job first.", call. = FALSE)
  .vp_read <- hvtiRtemplates:::.read_handoff(.vp_path, "screen", .cfg, "the vp-fit job")
  if (ARM %in% .vp_read$value$coverage$variable) {
    stop("The screen in ", VP_SET, " was given ", ARM, " as a candidate, so it is not treatment-blind. ",
         "Re-run vp-fit without the arm.", call. = FALSE)
  }
  .predictors <- .vp_read$value$selected
  .provenance_data <- c(.provenance_data, .vp_read$lineage$data)
} else {
  .predictors <- PREDICTORS
}
.predictors <- setdiff(.predictors, EXCLUDE)
.leaks <- intersect(tolower(.predictors), tolower(c(ARM, TIME, STATUS, ID)))
if (length(.leaks)) {
  stop("PREDICTORS (or the screen) includes the arm, outcome or ID: ", paste(.leaks, collapse = ", "), ".",
       call. = FALSE)
}
.missing <- setdiff(.predictors, names(d))
if (length(.missing)) stop("Not in the data this job read: ", paste(.missing, collapse = ", "), call. = FALSE)
if (!length(.predictors)) stop("No predictors are left after EXCLUDE.", call. = FALSE)
.chr <- .predictors[vapply(d[.predictors], is.character, logical(1L))]
d[.chr] <- lapply(d[.chr], factor)
if (NA_ACTION == "na.omit") {
  .kept <- stats::complete.cases(d[.predictors])
  cat(sum(!.kept), "patient(s) missing a predictor were dropped (NA_ACTION = \"na.omit\").\n")
  d <- d[.kept, , drop = FALSE]
  .no_arm <- .no_arm[.kept]
  .treated <- .treated[.kept]
}
d <- d[, c(ID, ARM, TIME, STATUS, .predictors), drop = FALSE]
cat("Predictors:", paste(.predictors, collapse = ", "), "\n")
```

Close the file with the `provenance` chunk copied from `vp-fit.qmd`, `extra = list(subject = SUBJECT, type = TYPE)`.

- [ ] **Step 6: `.lintr` and the ledger row**

Add a `.lintr` file key for `inst/templates/30_analyses/vt-fit.qmd` copying `vp-fit.qmd`'s entry. In `inst/extdata/templates.json`, change the `vt` row: `"qualifier": "fit"`, `"name": "Virtual twins: fit"`, add `"description": "Per-arm survival forests, swapped-arm twin curves and a per-patient RMST difference, with eligibility judged by a choice of methods."`, `"status": "in-flight"`, `"blocked_on": null`, `"spec": "dev/specs/2026-10-22-vt-virtual-twins-templates-design.md"`, `"disposition": "scaffold"`, `"uses": ["hvtiRpropensity::ps_forest", "hvtiRpropensity::ps_support", "hvtiPlotR::hv_rmst_curves", "hvtiRutilities::cache_fit"]`, and `"note": "Released for review in a real study. Built from the Virtual Twins study, its only exemplar; becomes shipped once a second study runs vt-fit through vt-explain. The method helpers live in the template until hvtiRforests#1 gives them a package."`. Then:

```bash
python3 dev/specs/artifacts/roadmap_render.py && python3 dev/specs/artifacts/check-roadmap-counts.py
```

Expected: both exit 0.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `R CMD INSTALL -l "$VT_LIB" . && R_LIBS="$VT_LIB" Rscript -e 'devtools::test(filter = "vt|template-catalog|add-job")'`
Expected: PASS, 0 failures. `test-template-catalog.R` still reads 68 rows and 45 prefixes.

- [ ] **Step 8: Commit**

```bash
git add DESCRIPTION .lintr inst/extdata/templates.json dev/specs/2026-08-29-template-conversion-roadmap.md \
  inst/templates/30_analyses/vt-fit.qmd tests/testthat/helper-vt.R tests/testthat/test-vt-templates.R
git commit -m "feat(vt-fit): setup, study choices, data and the predictor contract"
```

---

### Task 2: Eligibility by a choice of methods

**Files:**
- Modify: `inst/templates/30_analyses/vt-fit.qmd` (chunks `ood`, `eligibility`, `tbl-ood`, `fig-ood`, `tbl-agreement` after `predictors`), `tests/testthat/helper-vt.R`, `tests/testthat/test-vt-templates.R`

**Interfaces:**
- Consumes: `d`, `.treated`, `.no_arm`, `.predictors` (Task 1).
- Produces: `vt_ood(dist, ids, arm, arms) -> data.frame(ID, method, arm, nn_id, distance, reference, ratio, in_distribution, reason)` with `method = NA` (the caller sets it); `vt_elig_gower(d, predictors, id) -> matrix` (IDs as dimnames); `vt_elig_sid(path, ids, cfg) -> matrix`; `vt_combine(rows, combine) -> data.frame(ID, elig)`; job objects `.elig_rows` (all methods bound), `.elig` (data frame `ID`, `elig`, `elig_<method>`..., `elig_propensity`, `elig_none`), `.ps` (the `ps_forest()` result).

- [ ] **Step 1: Write the failing tests (no forest, so no `skip_on_cran()`)**

Add to `helper-vt.R`:

```r
# The helper chunks of vt-fit, evaluated alone, so a test can call vt_ood()
# without a study or a forest.
vt_helpers <- function() {
  env <- new.env()
  src <- readLines(template_path("vt", "fit"), warn = FALSE)
  for (label in c("ood", "curves-helper", "rmst-helper")) {
    if (any(trimws(src) == paste0("#| label: ", label))) eval(parse(text = rf_chunk(src, label)), envir = env)  # nolint: object_usage_linter.
  }
  env
}
```

Add to `test-vt-templates.R`:

```r
test_that("vt_ood flags a patient beyond the arm's largest nearest-neighbour gap", {
  h <- vt_helpers()
  # Arm A at 0, 1, 2 (largest within-arm gap 1); arm B at 2.5 and 10.
  x <- c(a1 = 0, a2 = 1, a3 = 2, b1 = 2.5, b2 = 10)
  D <- as.matrix(stats::dist(x))
  arm <- c("A", "A", "A", "B", "B")
  r <- h$vt_ood(D, names(x), arm, c("A", "B"))
  b <- r[r$arm == "A" & r$ID %in% c("b1", "b2"), ]
  expect_equal(b$in_distribution[b$ID == "b1"], TRUE)
  expect_equal(b$in_distribution[b$ID == "b2"], FALSE)
  expect_match(b$reason[b$ID == "b2"], "A")
})

test_that("a distance exactly at the reference is in distribution (strict >)", {
  h <- vt_helpers()
  x <- c(a1 = 0, a2 = 1, b1 = 2)  # b1's distance to arm A is 1, the reference is 1
  r <- h$vt_ood(as.matrix(stats::dist(x)), names(x), c("A", "A", "B"), c("A", "B"))
  expect_true(r$in_distribution[r$ID == "b1" & r$arm == "A"])
})

test_that("a no-arm row must pass against both arms", {
  h <- vt_helpers()
  x <- c(a1 = 0, a2 = 1, b1 = 20, b2 = 21, n1 = 0.5)
  r <- h$vt_ood(as.matrix(stats::dist(x)), names(x), c("A", "A", "B", "B", NA), c("A", "B"))
  r$method <- "gower"  # aggregate() drops rows whose group is NA, as the caller's method never is
  n1 <- r[r$ID == "n1", ]
  expect_setequal(n1$arm, c("A", "B"))
  expect_false(all(n1$in_distribution))
  expect_false(h$vt_combine(r, "any")$elig[h$vt_combine(r, "any")$ID == "n1"])
})

test_that("a patient with no distance to an arm is out of distribution, not NA", {
  h <- vt_helpers()
  D <- as.matrix(stats::dist(c(a1 = 0, a2 = 1, b1 = 0.5)))
  D["b1", c("a1", "a2")] <- D[c("a1", "a2"), "b1"] <- NA
  r <- h$vt_ood(D, rownames(D), c("A", "A", "B"), c("A", "B"))
  b1 <- r[r$ID == "b1" & r$arm == "A", ]
  expect_false(b1$in_distribution)
  expect_match(b1$reason, "no comparable")
  expect_false(anyNA(r$in_distribution))
})

test_that("Gower on a patient missing every predictor gives a flag", {
  skip_if_not_installed("cluster")
  h <- vt_helpers()
  d <- data.frame(ID = as.character(1:5), x = c(0, 1, 2, 1.5, NA), g = factor(c("u", "v", "u", "v", NA)))
  r <- h$vt_ood(h$vt_elig_gower(d, c("x", "g"), "ID"), d$ID, c("A", "A", "A", "B", "B"), c("A", "B"))
  expect_false(r$in_distribution[r$ID == "5" & r$arm == "A"])
})

test_that("methods combine by any and all, with one row shape", {
  h <- vt_helpers()
  base <- data.frame(ID = c("p1", "p2", "p3"), method = NA, arm = "A", nn_id = "q", distance = 1,
                     reference = 1, ratio = 1, in_distribution = TRUE, reason = "")
  g <- transform(base, method = "gower", in_distribution = c(FALSE, TRUE, TRUE))
  s <- transform(base, method = "sid", in_distribution = c(TRUE, FALSE, TRUE))
  expect_identical(names(g), names(s))
  any_ <- h$vt_combine(rbind(g, s), "any")
  all_ <- h$vt_combine(rbind(g, s), "all")
  expect_equal(any_$elig[order(any_$ID)], c(FALSE, FALSE, TRUE))
  expect_equal(all_$elig[order(all_$ID)], c(TRUE, TRUE, TRUE))
})

test_that("the sid method uses a set's distance and refuses a missing patient", {
  h <- vt_helpers()
  ids <- c("1", "2", "3")
  path <- withr::local_tempfile(fileext = ".rds")
  saveRDS(list(dist = stats::dist(c(`1` = 0, `2` = 1, `3` = 2))), path)
  m <- h$vt_elig_sid(path, ids, cfg = NULL, read = function(p) list(value = readRDS(p)))
  expect_equal(dimnames(m)[[1]], ids)
  expect_false(is.null(attr(m, "read")))
  expect_error(h$vt_elig_sid(path, c(ids, "4"), cfg = NULL, read = function(p) list(value = readRDS(p))),
               "1 patient")
})
```

- [ ] **Step 2: Run them to verify they fail**

Run: `R CMD INSTALL -l "$VT_LIB" . && R_LIBS="$VT_LIB" Rscript -e 'devtools::test(filter = "vt")'`
Expected: FAIL, `could not find function "vt_ood"`.

- [ ] **Step 3: Write chunk `ood`**

Under a heading `## Eligibility` with the spec's section 4.1 prose made general (what out of distribution means, why the reference is the arm's own largest gap, that patients are flagged and not dropped), chunk `ood`:

```r
# One rule, applied to any patient-by-patient distance. For each arm, each
# patient's nearest neighbour in that arm (never themself) is compared with the
# largest nearest-neighbour distance among the arm's own patients. Farther than
# that, STRICTLY, and the arm's forest would be extrapolating. A treated patient
# is judged against the other arm; a row with no arm against both.
#
# A distance can be unavailable: Gower gives NA for two patients who share no
# observed predictor. An unavailable distance is no evidence of nearness, so it
# counts as infinitely far. A patient with no finite distance to any patient in
# an arm has no comparable neighbour there and is out of distribution for it,
# with that reason; an arm member with no finite within-arm neighbour does not
# set the arm's reference. Every judged patient therefore gets TRUE or FALSE,
# never NA.
vt_ood <- function(dist, ids, arm, arms) {
  dist <- as.matrix(dist)[ids, ids, drop = FALSE]
  dist[is.na(dist)] <- Inf
  diag(dist) <- Inf
  rows <- lapply(arms, function(a) {
    members <- which(arm %in% a)
    nn_within <- apply(dist[members, members, drop = FALSE], 1L, min)
    nn_within <- nn_within[is.finite(nn_within)]
    if (!length(nn_within)) stop("No two patients in arm ", a, " have a finite distance.", call. = FALSE)
    reference <- max(nn_within)
    judged <- which(is.na(arm) | !arm %in% c(a, NA))
    if (!length(judged)) return(NULL)
    sub <- dist[judged, members, drop = FALSE]
    nn <- apply(sub, 1L, which.min)
    distance <- sub[cbind(seq_along(judged), nn)]
    none <- !is.finite(distance)
    out <- none | distance > reference
    reason <- ifelse(none, sprintf("no comparable %s patient (no predictor observed in common)", a),
                     ifelse(out, sprintf("nearest %s patient at %.3f, beyond that arm's largest gap %.3f",
                                         a, distance, reference), ""))
    data.frame(ID = ids[judged], method = NA_character_, arm = a, nn_id = ifelse(none, NA, ids[members][nn]),
               distance = distance, reference = reference, ratio = distance / stats::median(nn_within),
               in_distribution = !out, reason = reason)
  })
  do.call(rbind, rows)
}

# Gower over the model predictors only: mixed types, no model, bounded in [0, 1].
vt_elig_gower <- function(d, predictors, id) {
  m <- as.matrix(cluster::daisy(d[predictors], metric = "gower"))
  dimnames(m) <- list(d[[id]], d[[id]])
  m
}

# The SID distance a sid job saved. Read, never refit, and refused when it does
# not cover every patient here.
# Returns the distance with the whole reader result as attribute "read", so the
# eligibility chunk can carry the sid set's record and lineage into vt.rds.
vt_elig_sid <- function(path, ids, cfg, key = NULL, read = function(p) hvtiRtemplates:::.read_handoff(p, "clustering", cfg, "the sid job")) {
  if (!file.exists(path)) stop("No sid clustering at ", path, ". Render that job first.", call. = FALSE)
  got <- read(path)
  # A sid set's distance is labelled by ID digests under the study key, with the
  # key's fingerprint saved beside it. A different fingerprint means the key
  # changed since, and every digest would miss.
  if (!is.null(key) && !identical(got$value$id_key, hvtiRtemplates:::.id_key_fingerprint(key))) {
    stop("The sid set at ", path, " was digested under a different study key. Re-render it.", call. = FALSE)
  }
  m <- as.matrix(got$value$dist)
  absent <- setdiff(ids, rownames(m))
  if (length(absent)) {
    stop(length(absent), " patient(s) in this job are not in the sid distance at ", path, ".", call. = FALSE)
  }
  structure(m[ids, ids, drop = FALSE], read = got)
}

# A patient is eligible when every arm they were judged against passed, per
# method; then methods combine: "any" flag excludes, or "all" must.
vt_combine <- function(rows, combine = c("any", "all")) {
  combine <- match.arg(combine)
  per <- stats::aggregate(in_distribution ~ ID + method, rows, all)
  flagged <- stats::aggregate(!in_distribution ~ ID, per, if (combine == "any") any else all)
  data.frame(ID = flagged$ID, elig = !flagged[[2]])
}
```

- [ ] **Step 4: Write chunks `eligibility`, `tbl-ood`, `fig-ood`, `tbl-agreement`**

```r
#| label: eligibility
.methods <- match.arg(ELIGIBILITY, c("gower", "sid"), several.ok = TRUE)
.ids <- d[[ID]]
.arm <- ifelse(.no_arm, NA_character_, as.character(d[[ARM]]))
.sid_read <- NULL
.dist <- list(
  gower = function() vt_elig_gower(d, .predictors, ID),
  sid = function() {
    if (is.null(SID_SET)) stop("ELIGIBILITY includes \"sid\"; name the sid set in SID_SET.", call. = FALSE)
    m <- vt_elig_sid(file.path(dirname(dirname(set_path("estimates", "vt.rds"))), SID_SET, "sid.rds"), .ids, .cfg,
                     key = .id_key)
    # The sid set decided some flags, so its record and data lineage travel
    # into vt.rds with the vp screen's (see `save`).
    .sid_read <<- attr(m, "read")
    .provenance_data <<- c(.provenance_data, .sid_read$lineage$data)
    m
  }
)
.elig_rows <- do.call(rbind, lapply(.methods, function(m) transform(vt_ood(.dist[[m]](), .ids, .arm, ARMS), method = m)))
.elig <- vt_combine(.elig_rows, COMBINE)
for (m in .methods) .elig[[paste0("elig_", m)]] <- vt_combine(.elig_rows[.elig_rows$method == m, ], "any")$elig
# Sensitivity only, never part of the combined rule: forest propensity common support.
# ps_forest() refuses missing predictors, while the arm forests impute them
# (NA_ACTION = "na.impute"). So the propensity model gets a forest-imputed copy
# of the treated patients' predictors, seeded, and the arm forests keep the
# data as read. Under "na.omit" nothing is missing and the copy equals d.
.ps_data <- d[.treated, c(ID, ARM, .predictors), drop = FALSE]
if (anyNA(.ps_data[.predictors])) {
  set.seed(SEED)
  .ps_data[.predictors] <- randomForestSRC::impute(data = .ps_data[c(ARM, .predictors)], ntree = 100L,
                                                   seed = -abs(SEED))[.predictors]
}
set.seed(SEED)
.ps <- ps_forest(stats::reformulate(.predictors, ARM), data = .ps_data, treatment_col = ARM, id_col = ID,
                 treated_level = ARMS[1], ntree = NTREE, seed = -abs(SEED))
.support <- ps_support(.ps)
.elig$elig_propensity <- .elig$ID %in% .support[[ID]][.support$in_support]
.elig$elig_none <- TRUE
```

Check `ps_forest()`/`ps_support()` return shapes with `tools::Rd2txt()` before writing the last three lines (AGENTS.md: "Looking up a dependency's API"), and adapt the two `.support` lines to the documented columns. Then `tbl-ood` (a `knitr::kable()` of `.elig_rows[!.elig_rows$in_distribution, c("ID", "method", "arm", "distance", "reference", "reason")]`, every patient listed), `fig-ood` (per method, `distance` against patient rank faceted by `arm`, the `reference` as a dashed line, saved as `vt-fit-eligibility`), and `tbl-agreement` (`table()` of each pair of `elig_<method>` columns when more than one method ran).

- [ ] **Step 5: Add the chunks to `vt_fit_labels` and an end-to-end eligibility test**

```r
vt_fit_labels <- c("setup", "edit-study-choices", "tbl-data", "predictors",
                   "ood", "eligibility", "tbl-ood", "fig-ood", "tbl-agreement")
```

```r
test_that("the propensity sensitivity renders with missing predictors under na.impute", {
  skip_on_cran()
  d <- vt_data(); d$x1[c(20, 40, 60)] <- NA
  env <- vt_fit_first(data = d)
  expect_false(anyNA(env$.elig$elig_propensity))
})

test_that("vt-fit flags the planted outliers against arm B", {
  skip_on_cran()
  env <- vt_fit_first()
  flagged <- env$.elig$ID[!env$.elig$elig_gower]
  expect_true(all(vt_digest(env, which(vt_data()$arm == "A")[1:5]) %in% flagged))
})
```

- [ ] **Step 6: Run the tests, then prove the strict rule by mutation**

Run: `R CMD INSTALL -l "$VT_LIB" . && R_LIBS="$VT_LIB" Rscript -e 'devtools::test(filter = "vt")'`
Expected: PASS. Then change `distance > reference` to `distance >= reference` in the template, reinstall, rerun: "a distance exactly at the reference is in distribution" must FAIL. Revert and rerun to PASS.

- [ ] **Step 7: Commit**

```bash
git add inst/templates/30_analyses/vt-fit.qmd tests/testthat/helper-vt.R tests/testthat/test-vt-templates.R
git commit -m "feat(vt-fit): eligibility as a choice of methods (gower, sid), combined any/all"
```

---

### Task 3: Arm forests, twin curves, RMST and the handoff

**Files:**
- Modify: `inst/templates/30_analyses/vt-fit.qmd` (chunks `fit`, `tbl-performance`, `curves-helper`, `curves`, `rmst-helper`, `rmst`, `fig-curves`, `save`), `tests/testthat/helper-vt.R`, `tests/testthat/test-vt-templates.R`

**Interfaces:**
- Consumes: `d`, `.treated`, `.no_arm`, `.predictors`, `.elig`, `.elig_rows`, `.ps` (Tasks 1, 2).
- Produces: `vt_curves(forests, d, id, arm, arms) -> data.frame(ID, arm_of_curve, time, surv)` (long; one curve per patient per arm); `vt_rmst(curves, horizon, arms, followup) -> data.frame(ID, rmst_<arm>, risk_<arm>, diff, log_rr)`; `.forests` (named list by arm); `.rmst` (the per-patient table joined to `.elig`); `estimates/<subject>-vt/vt.rds` = `list(rmst, curves, forests, eligibility, predictors, settings)` with lineage.

- [ ] **Step 1: Write the failing tests**

CRAN-safe, in `test-vt-templates.R`:

```r
test_that("vt_rmst integrates a step curve to the horizon and takes the difference in ARMS order", {
  h <- vt_helpers()
  curves <- data.frame(ID = "p", arm_of_curve = rep(c("A", "B"), each = 3),
                       time = rep(c(1, 2, 3), 2), surv = c(0.9, 0.8, 0.7, 0.5, 0.5, 0.5))
  r <- h$vt_rmst(curves, horizon = 2, arms = c("A", "B"), followup = c(A = 5, B = 5))
  expect_equal(r$rmst_A, 1 * 1 + 1 * 0.9)
  expect_equal(r$rmst_B, 1 * 1 + 1 * 0.5)
  expect_equal(r$diff, r$rmst_A - r$rmst_B)
  expect_equal(r$risk_A, 1 - 0.8)
})

test_that("a horizon beyond either arm's follow-up stops", {
  h <- vt_helpers()
  curves <- data.frame(ID = "p", arm_of_curve = c("A", "B"), time = 1, surv = 0.9)
  expect_error(h$vt_rmst(curves, horizon = 6, arms = c("A", "B"), followup = c(A = 8, B = 5)),
               "HORIZON.*B")
})

test_that("vt_curves keys by ID, whatever the row order", {
  skip_on_cran()
  env <- vt_fit_first(labels = c(vt_fit_labels, "fit", "curves-helper", "curves"))
  shuffled <- env$d[rev(seq_len(nrow(env$d))), ]
  again <- env$vt_curves(env$.forests, env$.train_ids, shuffled, env$ID, env$ARM, env$ARMS, no_arm = rev(env$.no_arm))
  key <- function(x) x[order(x$ID, x$arm_of_curve, x$time), ]
  expect_equal(key(again)$surv, key(env$.curves)$surv)
})

test_that("a patient's own-arm curve is out of bag", {
  skip_on_cran()
  env <- vt_fit_first(labels = c(vt_fit_labels, "fit", "curves-helper", "curves"))
  fA <- env$.forests[["A"]]
  first <- env$d[[env$ID]][env$d[[env$ARM]] %in% "A"][1]
  own <- env$.curves[env$.curves$ID == first & env$.curves$arm_of_curve == "A", "surv"]
  expect_equal(own, unname(fA$survival.oob[1, ]))
})
```

Forest-growing, in `test-vt-templates.R`:

```r
test_that("the twin difference recovers the planted effect", {
  skip_on_cran()
  env <- vt_fit_first(labels = vt_fit_labels_all)
  r <- merge(env$.rmst, data.frame(ID = vt_digest(env, vt_data()$ccfid), xs = vt_data()$xs))
  r <- r[r$elig, ]
  expect_gt(stats::median(r$diff[r$xs > 1]), 0)
  expect_lt(stats::median(r$diff[r$xs < -1]), 0)
})

test_that("vt-fit saves one handoff with every element", {
  skip_on_cran()
  env <- vt_fit_first(labels = vt_fit_labels_all)
  h <- readRDS(env$set_path("estimates", "vt.rds"))
  expect_named(h, c("rmst", "curves", "forests", "eligibility", "predictors", "settings"))
  expect_true(all(c("elig", "elig_gower", "elig_propensity", "elig_none", "diff", "log_rr") %in% names(h$rmst)))
  expect_false(is.null(attr(h, "hvti_provenance")))
})
```

and in `helper-vt.R`:

```r
vt_fit_labels_all <- c(vt_fit_labels, "fit", "tbl-performance", "curves-helper", "curves", "rmst-helper",
                       "rmst", "fig-curves", "save")
```

- [ ] **Step 2: Run them to verify they fail**

Run: `R CMD INSTALL -l "$VT_LIB" . && R_LIBS="$VT_LIB" Rscript -e 'devtools::test(filter = "vt")'`
Expected: FAIL, `could not find function "vt_rmst"`.

- [ ] **Step 3: Write chunks `fit` and `tbl-performance`**

```r
#| label: fit
#| message: true
CACHE_DIR <- dirname(set_path("estimates", "vt.rds"))
.model <- stats::as.formula(paste0("Surv(", TIME, ", ", STATUS, ") ~ ", paste(.predictors, collapse = " + ")))
# The saved forest keeps this formula, and a formula keeps the environment it
# was made in, `job_data` and its patient IDs included. Point it at the global
# environment, which a saved file only refers to (rfs-fit does the same).
environment(.model) <- globalenv()
# The IDs of each forest's training rows, in training order. survival.oob rows
# follow this order, and vt_curves() matches on it rather than on d's order.
.train_ids <- stats::setNames(lapply(ARMS, function(a) d[[ID]][d[[ARM]] %in% a & .treated]), ARMS)
.forests <- stats::setNames(lapply(ARMS, function(a) {
  da <- d[d[[ARM]] %in% a & .treated, c(TIME, STATUS, .predictors), drop = FALSE]
  set.seed(SEED)
  cache_fit(paste0("vt-fit-", a),
            rfsrc(.model, data = da, ntree = NTREE, nsplit = NSPLIT, na.action = NA_ACTION,
                  importance = "none", block.size = 1, seed = -abs(SEED)),
            seed = SEED, dir = CACHE_DIR, refit = REFIT)
}), ARMS)
```

```r
#| label: tbl-performance
#| tbl-cap: "Each arm's forest, judged out of bag"
.perf <- do.call(rbind, lapply(ARMS, function(a) {
  f <- .forests[[a]]
  cc <- survival::concordance(survival::Surv(f$yvar[[1]], f$yvar[[2]]) ~ f$predicted.oob, reverse = TRUE)
  se <- sqrt(cc$var)
  data.frame(arm = a, patients = f$n, events = sum(f$yvar[[2]] == 1), c_index = cc$concordance,
             lower = cc$concordance - 1.96 * se, upper = cc$concordance + 1.96 * se)
}))
knitr::kable(.perf, digits = 3)
.weak <- .perf$arm[.perf$lower <= 0.5]
if (length(.weak)) {
  cat("\n**The interval for", paste(.weak, collapse = " and "), "includes 0.5.** That arm's half of every",
      "contrast below is exploratory.\n")
}
```

Prose above it says the C-index here is computed from the OOB predictions, not the forest's stored error rate (the study's 2026-09-23 correction).

- [ ] **Step 4: Write chunks `curves-helper` and `curves`**

```r
#| label: curves-helper
# Two curves per patient. The arm a patient received comes from that arm's
# forest OUT OF BAG, so no one is predicted by trees grown on them. The other
# arm comes from predict() on the other forest. Rows with no arm get both from
# predict(). Everything is keyed by ID: predict() returns rows in the order it
# was given them, and pairing by position silently swaps patients.
vt_curves <- function(forests, train_ids, d, id, arm, arms, no_arm) {
  out <- list()
  for (a in arms) {
    f <- forests[[a]]
    own <- d[[arm]] %in% a & !no_arm
    own_ids <- d[[id]][own]
    # survival.oob rows are in TRAINING order, which train_ids records; d may
    # be in any order, so each own-arm patient is matched to their row by ID.
    at <- match(own_ids, train_ids[[a]])
    if (anyNA(at)) stop(sum(is.na(at)), " arm ", a, " patient(s) are not among its forest's training rows.", call. = FALSE)
    oob <- f$survival.oob[at, , drop = FALSE]
    out[[length(out) + 1L]] <- data.frame(ID = rep(own_ids, each = length(f$time.interest)), arm_of_curve = a,
                                          time = f$time.interest, surv = as.vector(t(oob)))
    other <- d[!own, , drop = FALSE]
    p <- predict(f, newdata = other[, f$xvar.names, drop = FALSE], na.action = "na.impute")
    out[[length(out) + 1L]] <- data.frame(ID = rep(other[[id]], each = length(f$time.interest)), arm_of_curve = a,
                                          time = f$time.interest, surv = as.vector(t(p$survival)))
  }
  do.call(rbind, out)
}
```

The OOB rows are matched to patients through `.train_ids`, recorded in the `fit` chunk in training order, so `d`'s order at prediction time does not matter:

```r
#| label: curves
.own_n <- vapply(ARMS, function(a) .forests[[a]]$n, integer(1L))
stopifnot(all(.own_n == lengths(.train_ids[ARMS])))
.curves <- vt_curves(.forests, .train_ids, d, ID, ARM, ARMS, no_arm = .no_arm)
```

With `NA_ACTION = "na.omit"` rows were dropped in `predictors`, so `d` and the forests still agree, and the `stopifnot()` stops the render if a forest ever drops a row on its own.

- [ ] **Step 5: Write chunks `rmst-helper`, `rmst`, `fig-curves`**

```r
#| label: rmst-helper
# RMST to the horizon: the area under a step survival curve, which starts at 1.
# The horizon must sit inside both arms' follow-up; past it every curve is cut
# at the same place and the difference is an artefact (a horizon in days on a
# fit in years gave identical curves once).
vt_rmst <- function(curves, horizon, arms, followup) {
  past <- names(followup)[followup < horizon]
  if (length(past)) {
    stop("HORIZON (", horizon, ") is beyond the largest follow-up time in arm(s) ", paste(past, collapse = ", "),
         " (", paste(signif(followup[past], 3), collapse = ", "), "). Check its units against TIME.", call. = FALSE)
  }
  # The risk is 1 - S(horizon), where S includes a step AT the horizon; the
  # area stops at the horizon, so a step there adds nothing to it.
  one <- function(t, s) {
    keep <- t < horizon
    knots <- c(0, t[keep], horizon)
    steps <- c(1, s[keep])
    at <- c(1, s[t <= horizon])
    c(rmst = sum(diff(knots) * steps), risk = 1 - utils::tail(at, 1L))
  }
  per <- lapply(split(curves, list(curves$ID, curves$arm_of_curve), drop = TRUE), function(x) {
    x <- x[order(x$time), ]
    v <- one(x$time, x$surv)
    data.frame(ID = x$ID[1L], arm_of_curve = x$arm_of_curve[1L], rmst = v[["rmst"]], risk = v[["risk"]])
  })
  long <- do.call(rbind, per)
  wide <- stats::reshape(long, idvar = "ID", timevar = "arm_of_curve", direction = "wide", sep = "_")
  wide$diff <- wide[[paste0("rmst_", arms[1])]] - wide[[paste0("rmst_", arms[2])]]
  wide$log_rr <- log(wide[[paste0("risk_", arms[1])]] / wide[[paste0("risk_", arms[2])]])
  rownames(wide) <- NULL
  wide
}
```

```r
#| label: rmst
.followup <- vapply(ARMS, function(a) max(d[[TIME]][d[[ARM]] %in% a & .treated]), numeric(1L))
.rmst <- vt_rmst(.curves, HORIZON, ARMS, .followup)
.rmst <- merge(data.frame(ID = d[[ID]], arm = ifelse(.no_arm, "none", as.character(d[[ARM]]))), .rmst, by = "ID")
.rmst <- merge(.rmst, .elig, by = "ID")
```

`fig-curves`: `hv_rmst_curves()` on the mean curve per received arm and curve arm, in-distribution patients only, `tau = HORIZON`, saved as `vt-fit-curves`. Read `hv_rmst_curves`'s help first for the column names it expects (`arm`, `time`, `surv`, `facet`), and shape the mean curves to them.

- [ ] **Step 6: Write chunk `save`**

```r
#| label: save
# The product of this job, and what vt-explain reads, in one file so its parts
# cannot drift apart. The forests are kept so vt-explain grows none.
vt_handoff <- hvtiRtemplates:::.attach_handoff_lineage(
  list(rmst = .rmst, curves = .curves, forests = .forests,
       eligibility = list(rows = .elig_rows, methods = .methods, combine = COMBINE, sid_set = SID_SET, ps = .ps),
       predictors = list(names = .predictors, vp_set = VP_SET),
       settings = list(arms = ARMS, horizon = HORIZON, ntree = NTREE, seed = SEED, time = TIME, status = STATUS,
                       id = ID, id_key = hvtiRtemplates:::.id_key_fingerprint(.id_key),
                       arm = ARM, imputation = IMPUTATION, imputation_use = IMPUTATION_USE,
                       # Everything read_job_data() was given, so vt-explain reads the same patients and values.
                       read = list(dataset = DATASET, analysis_set = ANALYSIS_SET, where = WHERE, key = KEY,
                                   join = JOIN, join_vars = JOIN_VARS, reduce = REDUCE, join_key = JOIN_KEY))),
  # .provenance_data already holds the vp and sid sets' data lineage (appended
  # where each was read); their handoff records go in as artifacts.
  data = .provenance_data,
  artifacts = c(if (!is.null(.vp_read)) c(.vp_read$lineage$artifacts, list(.vp_read$record)),
                if (!is.null(.sid_read)) c(.sid_read$lineage$artifacts, list(.sid_read$record))),
  analysis = list(time = list(variable = TIME), event = list(variable = STATUS, event = 1L, censored = 0L)),
  selection = attr(job_data$record, "selection")
)
saveRDS(vt_handoff, set_path("estimates", "vt.rds"))
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `R CMD INSTALL -l "$VT_LIB" . && R_LIBS="$VT_LIB" Rscript -e 'devtools::test(filter = "vt")'`
Expected: PASS. Then mutate `vt_curves()` to pair `other` rows by position against a shuffled frame (drop the `ID` keying) and confirm "vt_curves keys by ID" FAILS; revert.

- [ ] **Step 8: Commit**

```bash
git add inst/templates/30_analyses/vt-fit.qmd tests/testthat/helper-vt.R tests/testthat/test-vt-templates.R
git commit -m "feat(vt-fit): arm forests, out-of-bag twin curves, RMST difference and the vt.rds handoff"
```

---

### Task 4: `vt-explain.qmd`: the handoff and the core contrast; second ledger row

**Files:**
- Create: `inst/templates/30_analyses/vt-explain.qmd`
- Modify: `.lintr`, `inst/extdata/templates.json`, `dev/specs/2026-08-29-template-conversion-roadmap.md`, `tests/testthat/test-template-catalog.R`, `tests/testthat/helper-vt.R`, `tests/testthat/test-vt-templates.R`

**Interfaces:**
- Consumes: `vt.rds` (Task 3).
- Produces: job objects `.vt` (the handoff value), `r` (`.vt$rmst`), `.eligible` (logical: `r$elig`; never `.in`, which `setup` sets to the source path the `provenance` chunk passes to `.embed_provenance()`), `.d_all` (the fit's patients, re-read by chunk `explain-data`); chunks `handoff`, `fig-contrast`, `fig-ranking`, `fig-twin-curves`, `fig-received-best`, `tbl-sensitivity`; `vt_explain_labels` in `helper-vt.R`.

- [ ] **Step 1: Write the failing tests**

```r
vt_explain_labels <- c("setup", "edit-study-choices", "handoff", "explain-data", "fig-contrast", "fig-ranking",
                       "fig-twin-curves", "fig-received-best", "tbl-sensitivity", "provenance")

# rf_run() strips library() from setup; attach the explain stack itself.
vt_explain <- function(env, labels = vt_explain_labels, choices = list(STRATIFY = NULL, BOOT = 0L, GAIN_MIN = 0,
                                                                      SAVE_FIGURES = FALSE)) {
  rf_skip_unless_stack(rf_template_packages("vt", "explain"))  # nolint: object_usage_linter.
  rf_run("vt", "explain", labels, env, choices)  # nolint: object_usage_linter.
}
```

```r
test_that("vt-explain reads vt.rds and never grows a forest", {
  skip_on_cran()
  env <- vt_fit_first(labels = vt_fit_labels_all)
  vt_explain(env)
  expect_true(all(c("gower", "propensity", "none") %in% env$.sens$rule))
  # provenance ran: .in is still the source path, not the eligibility mask.
  expect_type(env$.in, "character")
  src <- readLines(template_path("vt", "explain"), warn = FALSE)
  expect_false(any(grepl("rfsrc(", src, fixed = TRUE)))
})

test_that("vt-explain stops naming the file when no fit has run", {
  skip_on_cran()
  env <- rf_env(vt_data())
  expect_error(vt_explain(env, c("setup", "edit-study-choices", "handoff"), list()), "vt.rds")
})

test_that("vt-explain reads the fit's own selection, stacked imputations included", {
  skip_on_cran()
  d1 <- vt_data(); d1$imp <- 1L
  d2 <- vt_data(); d2$imp <- 2L; d2$x1 <- d2$x1 + 100
  env <- vt_fit_first(data = rbind(d1, d2), labels = vt_fit_labels_all,
                      choices = utils::modifyList(vt_choices, list(IMPUTATION = "imp", IMPUTATION_USE = 2L)))
  vt_explain(env, c(setdiff(vt_explain_labels, "provenance"), "stratify", "tbl-stratum"),
             list(STRATIFY = "x1", BOOT = 0L, GAIN_MIN = 0, SAVE_FIGURES = FALSE))
  expect_equal(nrow(env$.d_all), 300L)
  expect_gt(min(as.numeric(env$.strata$stratum)), 90)
})
```

In `test-template-catalog.R`, change `expect_equal(nrow(catalog), 68L)` to `69L`.

- [ ] **Step 2: Run them to verify they fail**

Run: `R CMD INSTALL -l "$VT_LIB" . && R_LIBS="$VT_LIB" Rscript -e 'devtools::test(filter = "vt|template-catalog")'`
Expected: FAIL, no `vt-explain` template; catalog reads 68.

- [ ] **Step 3: Write `vt-explain.qmd` through `tbl-sensitivity`**

YAML `title: "Virtual twins: explain"` and the `format:` block. `setup` as `vt-fit`'s, with `TYPE <- "vt"`, libraries `hvtiPlotR`, `hvtiRpropensity`, `hvtiRutilities`, `ggplot2`, and the same floors. `edit-study-choices`:

```r
# EDIT: NULL, a column of the data, or list(set = "<subject>-<type>") naming a
# sid-clusters set whose clusters stratify the result (add column = "group" for
# its collapsed groups). Strata are never a model
# covariate: they are built from what the forests already use.
STRATIFY <- NULL
BOOT <- 1000                                # EDIT: bootstraps for the standardized betas; 0 skips the intervals.
GAIN_MIN <- 0                               # EDIT: a twin must favour the other arm by more than this, in TIME's units.
SAVE_FIGURES <- TRUE
FIGURES <- NULL
```

`handoff`:

```r
.handoff <- set_path("estimates", "vt.rds")
if (!file.exists(.handoff)) {
  stop("No fit at ", .handoff, ". Render the vt-fit job in this set first; this job explains that fit and ",
       "never grows its own.", call. = FALSE)
}
.cfg <- study_config(start = .root)
.vt_read <- hvtiRtemplates:::.read_handoff(.handoff, "twins", .cfg, "the vt-fit job")
.vt <- .vt_read$value
.provenance_data <- .vt_read$lineage$data
.provenance_artifacts <- c(.vt_read$lineage$artifacts, list(.vt_read$record))
ARMS <- .vt$settings$arms
HORIZON <- .vt$settings$horizon
r <- .vt$rmst
.eligible <- r$elig
```

`explain-data`, the one read of patient data in this job, reused by `stratify`, `betas` and `tbl-benefit`. It repeats the fit's own `read_job_data()` call from the settings `vt-fit` saved, so a named dataset, analysis set, filter, join or stacked imputation gives the same patients and values the forests saw:

```r
#| label: explain-data
.s <- .vt$settings
.jd <- hvtiRtemplates::read_job_data(.cfg, dataset = .s$read$dataset, analysis_set = .s$read$analysis_set,
                                     where = .s$read$where, id = .s$id, key = .s$read$key, join = .s$read$join,
                                     join_vars = .s$read$join_vars, reduce = .s$read$reduce,
                                     join_key = .s$read$join_key, one_row_per_patient = TRUE,
                                     imputation = .s$imputation)
.d_all <- .jd$data
if (!is.null(.s$imputation)) .d_all <- .d_all[.d_all[[.s$imputation]] == .s$imputation_use, , drop = FALSE]
# vt.rds holds ID digests, so the data are digested with the same study key.
.id_key <- hvtiRtemplates:::.study_id_key(.root, create = FALSE)
if (!identical(.s$id_key, hvtiRtemplates:::.id_key_fingerprint(.id_key))) {
  stop("vt.rds was digested under a different study key. Re-render vt-fit.", call. = FALSE)
}
.d_all[[.s$id]] <- hvtiRtemplates:::.id_digest(.d_all[[.s$id]], .id_key)
.d_all <- .d_all[.d_all[[.s$id]] %in% r$ID, , drop = FALSE]
```

`fig-contrast`: percentile boxes of `r$diff[.eligible]` by `r$arm` (box 15th–85th, whiskers 5th–95th, median line), built with `ggplot2::stat_summary()` over a `quantile()` helper; caption says a positive difference favours `ARMS[1]`; saved `vt-explain-contrast`. `fig-ranking`: `r[.eligible, ]` ordered by `diff`, points coloured by `arm`, a zero line; saved `vt-explain-ranking`. `fig-twin-curves`: per received arm, the mean of each curve arm over in-distribution patients from `.vt$curves`, through `hv_rmst_curves(tau = HORIZON)`; saved `vt-explain-twin-curves`. `fig-received-best`:

```r
.rb <- r[.eligible & r$arm %in% ARMS, ]
.own <- ifelse(.rb$arm == ARMS[1], .rb[[paste0("rmst_", ARMS[1])]], .rb[[paste0("rmst_", ARMS[2])]])
.alt <- ifelse(.rb$arm == ARMS[1], .rb[[paste0("rmst_", ARMS[2])]], .rb[[paste0("rmst_", ARMS[1])]])
.rb$best <- ifelse(.own >= .alt, "Received best", "Alternative best")
```

as a stacked bar per arm, footnoted with each arm's event count from `.vt$forests` when its C-index interval includes 0.5 (recompute with `survival::concordance()` as in `vt-fit`'s `tbl-performance`); saved `vt-explain-received-best`. `tbl-sensitivity`:

```r
.rules <- c(sub("^elig_", "", grep("^elig_", names(r), value = TRUE)))
.sens <- do.call(rbind, lapply(c("combined", .rules), function(rule) {
  keep <- if (rule == "combined") r$elig else r[[paste0("elig_", rule)]]
  do.call(rbind, lapply(split(r[keep, ], r$arm[keep]), function(x) {
    q <- stats::quantile(x$diff, c(0.15, 0.5, 0.85), names = FALSE)
    data.frame(rule = rule, arm = x$arm[1L], kept = nrow(x), p15 = q[1], median = q[2], p85 = q[3],
               favour_first = mean(x$diff > 0))
  }))
}))
knitr::kable(.sens, digits = 2)
```

Close with the `provenance` chunk (`data = .provenance_data`, `artifacts = .provenance_artifacts` if `vp-explain` passes them; copy its call).

- [ ] **Step 4: `.lintr`, ledger, roadmap**

`.lintr` file key for `vt-explain.qmd` as for `vt-fit.qmd`. In `templates.json`, add a `(vt, explain)` row after `(vt, fit)`: `"name": "Virtual twins: explain"`, `"description": "The twin contrast a vt-fit job saved: by arm, by eligibility rule and by stratum, with standardized betas and who might benefit. It never grows a forest."`, `"status": "in-flight"`, the same `spec`, `note`, `family`, `folder` and `kind`, `"blocked_on": null`, `"uses": ["hvtiPlotR::hv_rmst_curves"]`. Then `python3 dev/specs/artifacts/roadmap_render.py && python3 dev/specs/artifacts/check-roadmap-counts.py`, expected exit 0.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `R CMD INSTALL -l "$VT_LIB" . && R_LIBS="$VT_LIB" Rscript -e 'devtools::test(filter = "vt|template-catalog|add-job")'`
Expected: PASS; catalog 69 rows, 45 prefixes.

- [ ] **Step 6: Commit**

```bash
git add .lintr inst/extdata/templates.json dev/specs/2026-08-29-template-conversion-roadmap.md \
  tests/testthat/test-template-catalog.R inst/templates/30_analyses/vt-explain.qmd \
  tests/testthat/helper-vt.R tests/testthat/test-vt-templates.R
git commit -m "feat(vt-explain): the twin contrast, received best and the eligibility sensitivity table"
```

---

### Task 5: `vt-explain.qmd`: stratifier, standardized betas, who might benefit, reading

**Files:**
- Modify: `inst/templates/30_analyses/vt-explain.qmd` (chunks `stratify`, `tbl-stratum`, `betas`, `fig-betas`, `tbl-benefit`, then `## Reading the result` prose), `tests/testthat/helper-vt.R`, `tests/testthat/test-vt-templates.R`

**Interfaces:**
- Consumes: `.vt`, `r`, `.eligible` (Task 4).
- Produces: `.strata` (data frame `ID`, `stratum`) or `NULL`; `.betas` (data frame `variable`, `beta`, `lower`, `upper`); `.benefit` (data frame).

- [ ] **Step 1: Write the failing tests**

```r
# provenance stays last: it reads what stratify appends.
vt_explain_labels_all <- c(setdiff(vt_explain_labels, "provenance"), "stratify", "tbl-stratum", "overlap-weights", "betas", "fig-betas",
                           "tbl-benefit", "provenance")
```

```r
test_that("the stratifier joins sid-clusters on the ID digest", {
  skip_on_cran()
  env <- vt_fit_first(labels = vt_fit_labels_all)
  sid_dir <- file.path(dirname(dirname(env$set_path("estimates", "vt.rds"))), "dead-sid")
  dir.create(sid_dir, recursive = TRUE)
  key <- hvtiRtemplates:::.study_id_key(env$.root)
  saveRDS(list(clusters = data.frame(id = vt_digest(env, factor(vt_data()$ccfid)),
                                     cluster = ifelse(vt_data()$xs > 0, "hi", "lo")),
               id_key = hvtiRtemplates:::.id_key_fingerprint(key)),
          file.path(sid_dir, "sid-clusters.rds"))
  vt_explain(env, vt_explain_labels_all,
             list(STRATIFY = list(set = "dead-sid"), BOOT = 0L, GAIN_MIN = 0, SAVE_FIGURES = FALSE,
                  .vt_read_sid = function(p) list(value = readRDS(p), lineage = list(data = list(), artifacts = list()),
                                                  record = list(path = p))))
  expect_setequal(unique(env$.strata$stratum), c("hi", "lo"))
  expect_equal(sum(is.na(merge(env$r, env$.strata, by = "ID", all.x = TRUE)$stratum)), 0L)
})

test_that("a rare factor level does not abort the bootstrap", {
  skip_on_cran()
  d <- vt_data(); d$rare <- factor(ifelse(seq_len(nrow(d)) %in% c(3, 150), "yes", "no"))
  env <- vt_fit_first(data = d, labels = vt_fit_labels_all,
                      choices = utils::modifyList(vt_choices, list(PREDICTORS = c("xs", "x1", "g1", "rare"))))
  vt_explain(env, vt_explain_labels_all, list(STRATIFY = NULL, BOOT = 50L, GAIN_MIN = 0, SAVE_FIGURES = FALSE))
  row <- env$.betas[startsWith(env$.betas$variable, "rare"), ]
  expect_match(row$variable, "yes vs no")
  expect_gt(row$unestimable, 0L)
})

test_that("BOOT = 0 skips the intervals and the betas still render", {
  skip_on_cran()
  env <- vt_fit_first(labels = vt_fit_labels_all)
  vt_explain(env, vt_explain_labels_all)
  expect_true(all(is.na(env$.betas$lower)))
  expect_true(all(is.finite(env$.betas$beta)))
})
```

The first test needs the `stratify` chunk to read a sid set through an injectable reader, `.vt_read_sid`, defaulting to `.read_handoff()`; a fixture `sid.rds` carries no lineage.

- [ ] **Step 2: Run them to verify they fail**

Run: `R CMD INSTALL -l "$VT_LIB" . && R_LIBS="$VT_LIB" Rscript -e 'devtools::test(filter = "vt")'`
Expected: FAIL, chunk `stratify` not found.

- [ ] **Step 3: Write `stratify` and `tbl-stratum`**

```r
#| label: stratify
.strata <- NULL
if (!exists(".vt_read_sid")) .vt_read_sid <- function(p) hvtiRtemplates:::.read_handoff(p, "clustering", .cfg, "the sid job")
if (is.list(STRATIFY)) {
  .sid_path <- file.path(dirname(dirname(.handoff)), STRATIFY$set, "sid-clusters.rds")
  if (!file.exists(.sid_path)) stop("No sid clusters at ", .sid_path, ". Render sid-clusters first.", call. = FALSE)
  .sid_strata <- .vt_read_sid(.sid_path)
  if (!identical(.sid_strata$value$id_key, .vt$settings$id_key)) {
    stop("The sid clusters at ", .sid_path, " were digested under a different study key from vt.rds.", call. = FALSE)
  }
  .cl <- .sid_strata$value$clusters
  if (is.null(.cl)) stop("The sid set has no clusters yet: set K in sid-clusters and render it.", call. = FALSE)
  # "cluster" (the letter at the chosen K) unless STRATIFY names "group", the
  # collapsed groups sid-clusters writes when COLLAPSE is set.
  .col <- if (is.null(STRATIFY$column)) "cluster" else STRATIFY$column
  .strata <- data.frame(ID = .cl$id, stratum = as.character(.cl[[.col]]))
  # The clustering defines the strata, so the report names it and its data.
  .provenance_data <- c(.provenance_data, .sid_strata$lineage$data)
  .provenance_artifacts <- c(.provenance_artifacts, .sid_strata$lineage$artifacts, list(.sid_strata$record))
} else if (is.character(STRATIFY)) {
  if (!STRATIFY %in% names(.d_all)) stop(STRATIFY, " is not in the data the fit read.", call. = FALSE)
  .strata <- data.frame(ID = .d_all[[.vt$settings$id]], stratum = as.character(.d_all[[STRATIFY]]))
}
```

`tbl-stratum` (when `.strata` is not `NULL`): merge on `ID`; `table(stratum, arm)` for in-distribution patients; then per stratum and arm, `n`, median `diff` and share favouring `ARMS[1]`, with the median set to `NA` where `n < 5`, and a sentence saying so.

- [ ] **Step 4: Write `betas` and `fig-betas`**

```r
#| label: betas
# Each patient's log relative risk at HORIZON, scaled by its SD, regressed on one
# characteristic at a time with overlap weights (Ishwaran and Blackstone, 2025).
# The forests are fixed; only patients are resampled.
.bx <- merge(r[.eligible & r$arm %in% ARMS & is.finite(r$log_rr), c("ID", "log_rr")],
             .d_all[c(.vt$settings$id, .vt$predictors$names)], by.x = "ID", by.y = .vt$settings$id)
.ps <- .vt$eligibility$ps
# Overlap (ATO) weights, computed here: ps_forest()'s own weight column is the
# Li-Greene MATCHING weight, which targets a different estimand (ATM). With e
# the out-of-bag probability of ARMS[1], a patient on ARMS[1] weighs 1 - e and
# one on ARMS[2] weighs e (Li, Morgan and Zaslavsky 2018).
.bx$w <- vt_overlap_weights(.ps$data, .bx$ID, .vt$settings$id, .vt$settings$arm, ARMS)
.bx$y <- .bx$log_rr / stats::sd(.bx$log_rr)
# Each characteristic becomes ONE numeric column, fixed on the full sample before
# any resampling: a number is standardized with the full-sample mean and SD; a
# factor becomes an indicator of its most common non-reference level, against
# the reference (its first level). A resample then regresses on the same
# column, so the coefficient means the same thing in every resample, and a
# resample in which that column does not vary is unestimable: it gives NA and
# is counted, never an error.
.design <- lapply(.vt$predictors$names, function(v) {
  xv <- .bx[[v]]
  if (is.numeric(xv)) return(list(x = (xv - mean(xv, na.rm = TRUE)) / stats::sd(xv, na.rm = TRUE), label = v))
  xv <- factor(xv)
  ref <- levels(xv)[1L]
  lev <- names(sort(table(xv[xv != ref]), decreasing = TRUE))[1L]
  list(x = as.numeric(xv == lev), label = paste0(v, ": ", lev, " vs ", ref))
})
.beta_one <- function(y, x, w) {
  ok <- !is.na(x)
  if (length(unique(x[ok])) < 2L) return(NA_real_)
  unname(stats::coef(stats::lm(y[ok] ~ x[ok], weights = w[ok]))[2L])
}
.betas <- data.frame(variable = vapply(.design, `[[`, "", "label"),
                     beta = vapply(.design, function(z) .beta_one(.bx$y, z$x, .bx$w), numeric(1L)),
                     lower = NA_real_, upper = NA_real_, unestimable = NA_integer_)
if (BOOT > 0) {
  set.seed(.vt$settings$seed)
  .boot <- replicate(BOOT, {
    i <- sample.int(nrow(.bx), replace = TRUE)
    vapply(.design, function(z) .beta_one(.bx$y[i], z$x[i], .bx$w[i]), numeric(1L))
  })
  .boot <- matrix(.boot, nrow = length(.design))
  .betas$lower <- apply(.boot, 1L, stats::quantile, 0.025, na.rm = TRUE)
  .betas$upper <- apply(.boot, 1L, stats::quantile, 0.975, na.rm = TRUE)
  .betas$unestimable <- rowSums(is.na(.boot))
}
```

Confirm `ps_forest()`'s score column is `prob_t`, the probability of `treated_level` (`ARMS[1]`), from its help page. The table shows `unestimable`, the resamples in which a characteristic did not vary, and the prose says an interval resting on many fewer than `BOOT` resamples is unreliable. `vt_overlap_weights()` is defined in a chunk of its own, `overlap-weights`, ahead of `betas`, so it can be tested without a fit:

```r
#| label: overlap-weights
vt_overlap_weights <- function(ps_data, ids, id, arm, arms, score = "prob_t") {
  at <- match(ids, as.character(ps_data[[id]]))
  e <- ps_data[[score]][at]
  ifelse(ps_data[[arm]][at] == arms[1], 1 - e, e)
}
```

Its test, CRAN-safe, in Step 1:

```r
test_that("overlap weights are 1 - e on the first arm and e on the second", {
  src <- readLines(template_path("vt", "explain"), warn = FALSE)
  env <- new.env(); eval(parse(text = rf_chunk(src, "overlap-weights")), envir = env)  # nolint: object_usage_linter.
  ps <- data.frame(id = c("p", "q", "r"), arm = c("A", "B", "A"), prob_t = c(0.8, 0.3, 0.1))
  expect_equal(env$vt_overlap_weights(ps, c("r", "p", "q"), "id", "arm", c("A", "B")), c(0.9, 0.2, 0.3))
})
```

Add `"overlap-weights"` before `"betas"` in `vt_explain_labels_all`. `fig-betas`: a dot-and-interval plot of `.betas` ordered by `beta`, intervals drawn only when `BOOT > 0`; saved `vt-explain-betas`.

- [ ] **Step 5: Write `tbl-benefit` and the reading prose**

```r
#| label: tbl-benefit
.gain <- ifelse(r$arm == ARMS[1], -r$diff, ifelse(r$arm == ARMS[2], r$diff, NA))
.benefit <- r[.eligible & r$arm %in% ARMS & .gain > GAIN_MIN, ]
.future <- r[.eligible & r$arm == "none", ]
.future$favours <- ifelse(.future$diff > 0, ARMS[1], ARMS[2])
```

then a `knitr::kable()` of counts by arm whose twin favours the other arm, a table of their predictor summaries beside the rest of their arm (median and IQR for numeric, percent for factors, from `.d_all`), and a count of no-arm patients by `favours`.

`## Reading the result`: spec section 6, item 5, written for a study author: out of distribution and why those patients are not summarized; an arm whose interval includes 0.5; the difference is a per-patient model estimate, not an observed outcome; a design-based contrast (`hvtiRpropensity::ps_rmst()`) is the check on it; one imputation of m was used when the fit says so (`.vt$settings$imputation`).

- [ ] **Step 6: Run the tests to verify they pass**

Run: `R CMD INSTALL -l "$VT_LIB" . && R_LIBS="$VT_LIB" Rscript -e 'devtools::test(filter = "vt")'`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add inst/templates/30_analyses/vt-explain.qmd tests/testthat/helper-vt.R tests/testthat/test-vt-templates.R
git commit -m "feat(vt-explain): stratifier, standardized betas, who might benefit and the reading notes"
```

---

### Task 6: `vp.rds` route, MRN scan, docs and the full gate

**Files:**
- Modify: `tests/testthat/test-vt-templates.R`, `inst/templates/README.md`
- Create: `news/feat-vt-templates.md`

- [ ] **Step 1: Write the remaining tests**

```r
# A sibling vp-fit set holding a hand-built screen, then vt-fit through
# `predictors`. setup runs first so set_path() exists to place the sibling.
vt_with_screen <- function(screen, choices, .local_envir = parent.frame()) {
  env <- rf_env(vt_data(), .local_envir)  # nolint: object_usage_linter.
  rf_run("vt", "fit", "setup", env, choices)  # nolint: object_usage_linter.
  vp_dir <- file.path(dirname(dirname(env$set_path("estimates", "vt.rds"))), choices$VP_SET)
  dir.create(vp_dir, recursive = TRUE)
  saveRDS(screen, file.path(vp_dir, "vp.rds"))
  # The hand-built screen carries no lineage, which .read_handoff() would refuse.
  testthat::local_mocked_bindings(
    .read_handoff = function(path, ...) list(value = readRDS(path), lineage = list(data = list()), record = list()),
    .package = "hvtiRtemplates", .env = .local_envir
  )
  rf_run("vt", "fit", c("edit-study-choices", "tbl-data", "predictors"), env, choices)  # nolint: object_usage_linter.
  env
}

test_that("VP_SET reads a vp-fit screen's selected set, minus EXCLUDE", {
  skip_on_cran()
  screen <- list(selected = c("xs", "x1"), coverage = data.frame(variable = c("xs", "x1", "g1")))
  env <- vt_with_screen(screen, utils::modifyList(vt_choices, list(VP_SET = "dead-vp", EXCLUDE = "x1")))
  expect_equal(env$.predictors, "xs")
})

test_that("a screen that saw the arm is refused", {
  skip_on_cran()
  screen <- list(selected = "xs", coverage = data.frame(variable = c("xs", "arm")))
  expect_error(vt_with_screen(screen, utils::modifyList(vt_choices, list(VP_SET = "dead-vp"))), "treatment-blind")
})

# Keyed on an MRN (no ccfid, so read_job_data() falls back to it): the job
# digests it, and no file it writes holds one.
test_that("no MRN reaches any file vt-fit or vt-explain generates", {
  skip_on_cran()
  d <- vt_data(); d$MRN <- sprintf("%08d", d$ccfid); d$ccfid <- NULL
  env <- vt_fit_first(data = d, labels = vt_fit_labels_all, choices = utils::modifyList(vt_choices, list(ID = "ccfid")))
  vt_explain(env, vt_explain_labels_all)
  # Only what the jobs wrote: the set's estimates. The fixture's input dataset
  # under datasets/ holds the MRNs on purpose.
  set_dir <- dirname(env$set_path("estimates", "vt.rds"))
  expect_identical(rf_files_holding(set_dir, d$MRN), character())  # nolint: object_usage_linter.
})
```

Put `vt_with_screen()` in `helper-vt.R`, not the test file.

- [ ] **Step 2: Run them and make them pass**

Run: `R CMD INSTALL -l "$VT_LIB" . && R_LIBS="$VT_LIB" Rscript -e 'devtools::test(filter = "vt")'`
Expected: PASS.

- [ ] **Step 3: Docs and NEWS fragment**

In `inst/templates/README.md`, list `vt-fit.qmd` and `vt-explain.qmd` under `30_analyses` as `in-flight`, with their figure names (`vt-fit-eligibility`, `vt-fit-curves`, `vt-explain-contrast`, `vt-explain-ranking`, `vt-explain-twin-curves`, `vt-explain-received-best`, `vt-explain-betas`), and remove `vt` from the untemplated list. `news/feat-vt-templates.md`:

```markdown
* New templates `vt-fit` and `vt-explain`, released for review (`in-flight`): virtual twins with one survival forest per arm, out-of-bag own-arm and swapped-arm curves, a per-patient RMST difference, and eligibility judged by a choice of methods (Gower, SID) combined by a stated rule. `vt-fit` reads a `vp-fit` screen's selected set or a list, and one completed dataset from stacked imputations; `vt-explain` reports the contrast by arm, eligibility rule and stratum, standardized betas and who might benefit.
```

- [ ] **Step 4: The full gate**

```bash
R CMD INSTALL -l "$VT_LIB" . && NOT_CRAN=true R_LIBS="$VT_LIB" Rscript -e 'devtools::test()'
Rscript -e 'devtools::document()' && git status --short man NAMESPACE
Rscript -e 'lintr::lint_package()'
python3 dev/specs/artifacts/check-roadmap-counts.py && python3 dev/specs/artifacts/check-spec-counts.py
R_LIBS="$VT_LIB" Rscript -e 'devtools::check()'
```

Expected: tests FAIL 0, the summary's WARN count unchanged from `main` (read it against `main`, since `test-rf-templates.R`'s known warnings inflate a local run); `man/` and `NAMESPACE` unchanged; no lints; both scripts exit 0; check 0 errors, 0 warnings, 0 notes.

- [ ] **Step 5: Render once on lri (John)**

Hand John the command, written for the server, to render both templates against the Virtual Twins study as a new set, from the study directory: `Rscript -e 'hvtiRtemplates::add_job("vt", "dead", "vt", qualifier = "fit")'`, edit the `EDIT:` lines from the study's `config.yml`, then `Rscript -e 'hvtiRtemplates::render_job("<the new file>")'`. Compare the in-distribution count and the median difference by arm with the study's `rmst_all_modern.rds`. Differences are expected where `NTREE` and the eligibility methods differ; record them in the PR.

- [ ] **Step 6: Commit and open the PR**

```bash
git add tests/testthat/test-vt-templates.R inst/templates/README.md news/feat-vt-templates.md
git commit -m "test(vt): vp.rds route, treatment-blind check, MRN scan; docs and NEWS fragment"
git push -u origin feat/vt-templates
gh pr create --title "feat: vt-fit and vt-explain templates (in-flight)" --body-file <body>
```

The body names the spec and plan, the lri render comparison, the `SKIP` lines from CI (`gh run view <id> --log | grep -E "SKIP [0-9]+ \| PASS"`), and that the local `/code-review` stood in for Copilot.

## Out of scope (follow-ups)

- Moving `vt_ood()`, `vt_elig_*()`, `vt_combine()`, `vt_curves()` and `vt_rmst()` to `hvtiRforests` once `hvtiRforests#1` lands.
- Pooling across multiple imputations.
- Isolation-forest and cross-arm-distance eligibility methods; section 4.1 of the spec takes them without a redesign.
- Rows `(vt, fit)` and `(vt, explain)` to `shipped` once a second study runs them.
