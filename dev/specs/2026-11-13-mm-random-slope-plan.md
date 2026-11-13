# mm random slope Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `STRUCTURE = "slope"` to the `mm` template: a random intercept and an independent random slope on one
time term, as SAS's `RANDOM int <slope> / subject=id`.

**Architecture:** Everything lives in `inst/templates/30_analyses/mm.qmd`. The `mm-helpers` chunk gains the
`"slope"` structure in `mm_check()`, `mm_fit()` and `mm_covariance()`; the study choices gain `SLOPE`; the fit,
counts and save chunks pass it through. Tests in `tests/testthat/test-mm-template.R` evaluate the helpers chunk
directly (`mm_helpers()` in `tests/testthat/helper-mm.R`) and render the template end to end.

**Tech Stack:** R, nlme (`lme`, `pdDiag`), testthat edition 3, Quarto.

## Global Constraints

- The design is spec `dev/specs/2026-11-12-mm-template-design.md` §11. Decided by John Ehrlinger on 2026-11-13.
- Covariance of the random effects is independent, `nlme::pdDiag`, SAS `type=vc`. Not `pdSymm`.
- `SLOPE` defaults to `NULL`, meaning the first entry of `TIME_TERMS`, and must be one of `TIME_TERMS`.
- Covariance table labels: `"Intercept variance"`, `"<SLOPE> variance"`, `"residual variance"`.
- Lines are at most 135 characters; US spelling (`tools/check-us-spelling.sh`).
- Every study-specific line in the template is marked `EDIT:`; comments say why a choice matters.
- Templates carry no study identifiers (`test-add-job.R` checks).
- No `Version:` bump and no `NEWS.md` edit: a fragment in `news/feat-mm-random-slope.md`.
- Never `git add -A`; stage explicit paths.
- Render tests need this branch installed in a private library (the installed package is what Quarto loads):
  `R CMD INSTALL -l <scratch>/lib .` then run tests with `R_LIBS=<scratch>/lib` and `NOT_CRAN=true`. Expect `SKIP 0`.

---

### Task 1: the `"slope"` structure in the helpers

**Files:**
- Modify: `inst/templates/30_analyses/mm.qmd` (the `mm-helpers` chunk: `.mm_structures`, `mm_check()`, `mm_fit()`,
  `mm_covariance()`)
- Modify: `tests/testthat/helper-mm.R` (add `mm_slopes()`)
- Test: `tests/testthat/test-mm-template.R`

**Interfaces:**
- Produces: `mm_check(d, id, time, structure, imputation, visit = NULL, slope = NULL, time_terms = NULL)`;
  `mm_fit(d, formula, id, time, structure, method, visit = NULL, slope = NULL)` whose result adds `slope`
  (character or `NULL`) and `n_single_time` (integer: used patients with one distinct time);
  `mm_covariance(fit)` rows for `"slope"` as in Global Constraints.

- [ ] **Step 1: Add the simulation helper** to `tests/testthat/helper-mm.R`, after `mm_visits()`:

```r
# A cohort whose log response has an independent random intercept (SD 0.2) and random slope on
# log(time + 1) (SD 0.1), residual SD 0.1: what SAS's RANDOM int <slope> / subject=id fits.
mm_slopes <- function(n = 300L) {
  withr::local_seed(7)
  per <- sample(4:6, n, replace = TRUE)
  id <- rep(seq_len(n), per)
  time <- unlist(lapply(per, function(k) sort(stats::runif(k, 0, 10))))
  age <- rep(stats::rnorm(n, 60, 10), per)
  b0 <- rep(stats::rnorm(n, 0, 0.2), per)
  b1 <- rep(stats::rnorm(n, 0, 0.1), per)
  lt <- log(time + 1)
  ly <- 3 + 0.2 * lt + 0.01 * (age - 60) + b0 + b1 * lt + stats::rnorm(length(id), 0, 0.1)
  data.frame(ccfid = id, time = time, age = age, ly = ly)
}
```

- [ ] **Step 2: Write the failing tests** in `tests/testthat/test-mm-template.R`, after the test
  "UN labels each correlation by visit pair and matches corMatrix":

```r
test_that("slope fits an independent random intercept and slope and recovers their variances", {
  h <- mm_helpers()
  fit <- h$mm_fit(mm_slopes(), ly ~ log(time + 1) + age, "ccfid", "time", "slope", "REML", slope = "log(time + 1)")
  expect_s3_class(fit$model, "lme")
  expect_s3_class(fit$model$modelStruct$reStruct[[1L]], "pdDiag")
  expect_identical(fit$slope, "log(time + 1)")
  expect_identical(fit$n_single_time, 0L)
  cov <- h$mm_covariance(fit)
  expect_identical(cov$parameter, c("Intercept variance", "log(time + 1) variance", "residual variance"))
  expect_equal(cov$estimate, c(0.04, 0.01, 0.01), tolerance = 0.25)
})

test_that("slope counts the patients measured at one time", {
  h <- mm_helpers()
  d <- mm_slopes()
  d$time[d$ccfid %in% 1:5] <- 2
  fit <- h$mm_fit(d, ly ~ log(time + 1) + age, "ccfid", "time", "slope", "REML", slope = "log(time + 1)")
  expect_identical(fit$n_single_time, 5L)
})

test_that("mm_check refuses a SLOPE outside TIME_TERMS and data with no slope to fit", {
  h <- mm_helpers()
  d <- mm_slopes()
  expect_true(h$mm_check(d, "ccfid", "time", c("cs", "slope"), NULL, slope = "log(time + 1)",
                         time_terms = "log(time + 1)"))
  expect_error(h$mm_check(d, "ccfid", "time", "slope", NULL, slope = "time", time_terms = "log(time + 1)"),
               "SLOPE \\(time\\) is not one of TIME_TERMS")
  # A SLOPE is ignored when no structure asks for one.
  expect_true(h$mm_check(d, "ccfid", "time", "cs", NULL, slope = "time", time_terms = "log(time + 1)"))
  d$time <- 1
  expect_error(h$mm_check(d, "ccfid", "time", "slope", NULL, slope = "log(time + 1)", time_terms = "log(time + 1)"),
               "no patient is measured at two or more distinct times")
})
```

- [ ] **Step 3: Run them and see them fail**

Run: `NOT_CRAN=true Rscript -e 'devtools::test(filter = "mm-template")'`
Expected: the three new tests FAIL (`"slope"` is not one of `.mm_structures`; unused argument `slope`).

- [ ] **Step 4: Implement in the `mm-helpers` chunk of `inst/templates/30_analyses/mm.qmd`**

Replace `.mm_structures`:

```r
.mm_structures <- c("cs", "ar1", "un", "random", "slope")
```

Change the `mm_check()` signature and add the slope guards just before its final `invisible(TRUE)`:

```r
mm_check <- function(d, id, time, structure, imputation, visit = NULL, slope = NULL, time_terms = NULL) {
```

```r
  if ("slope" %in% structure) {
    if (!slope %in% time_terms) {
      stop("SLOPE (", slope, ") is not one of TIME_TERMS (", paste(time_terms, collapse = ", "), "). ",
           "Write it as it appears there, or set SLOPE <- NULL for the first.", call. = FALSE)
    }
    # A patient measured at one time has no slope of their own; with none measured twice there is no slope at all.
    if (!any(tapply(t, as.character(d[[id]]), function(x) length(unique(x)) >= 2L))) {
      stop("STRUCTURE asks for \"slope\", but no patient is measured at two or more distinct times. ",
           "Use \"cs\" or \"random\".", call. = FALSE)
    }
  }
```

In `mm_fit()`, change the signature, replace the `random = NULL` arm of `corr` with `random = NULL, slope = NULL`, and
replace the `model <- tryCatch(...)` call's first branch condition and `random =` argument:

```r
mm_fit <- function(d, formula, id, time, structure, method, visit = NULL, slope = NULL) {
```

```r
    random = NULL,
    slope = NULL
  )
  # SAS's RANDOM int <slope> / subject=id is type=vc by default: intercept and slope independent, so pdDiag,
  # not nlme's own default pdSymm, which would estimate a correlation the SAS fit did not.
  random <- switch(structure,
    random = by_id("~ 1"),
    slope = stats::setNames(list(nlme::pdDiag(stats::as.formula(paste("~", slope)))), id),
    NULL
  )
  model <- tryCatch(
    if (!is.null(random)) {
      nlme::lme(formula, data = d, random = random, correlation = corr, method = method,
                na.action = stats::na.omit)
    } else {
```

(the `else` branch and the `error =` handler are unchanged). In the returned `list(...)`, after
`per_patient = table(as.character(d[[id]][used]))`, add:

```r
       per_patient = table(as.character(d[[id]][used])), slope = slope,
       n_single_time = sum(tapply(d[[time]][used], as.character(d[[id]][used]), function(x) length(unique(x))) < 2L))
```

In `mm_covariance()`, replace the body of `if (inherits(m, "lme")) { ... }` with:

```r
  if (inherits(m, "lme")) {
    vc <- suppressWarnings(as.numeric(nlme::VarCorr(m)[, "Variance"]))
    if (identical(structure, "slope")) {
      # Labeled as SAS's Covariance Parameter Estimates name them, so a port reads against its .lst.
      out[["Intercept variance"]] <- vc[[1L]]
      out[[paste(fit$slope, "variance")]] <- vc[[2L]]
      out[["residual variance"]] <- vc[[length(vc)]]
    } else {
      out[["between-patient variance"]] <- vc[[1L]]
      out[["residual variance"]] <- vc[[length(vc)]]
      out[["within-patient correlation"]] <- vc[[1L]] / sum(vc)
    }
  } else {
```

Update the comment above `mm_covariance()` to end: `..., and un one correlation per visit pair; slope the intercept,
slope and residual variances.`

- [ ] **Step 5: Run the tests and see them pass**

Run: `NOT_CRAN=true Rscript -e 'devtools::test(filter = "mm-template")'`
Expected: 0 failures. Then mutation-check the covariance choice: change `pdDiag` to `pdSymm`, rerun, and confirm
"slope fits an independent random intercept and slope" fails on the `pdDiag` class; restore.

- [ ] **Step 6: Lint and commit**

Run: `Rscript -e 'lintr::lint("inst/templates/30_analyses/mm.qmd"); lintr::lint("tests/testthat/helper-mm.R")'`
Expected: no lints.

```bash
git add inst/templates/30_analyses/mm.qmd tests/testthat/helper-mm.R tests/testthat/test-mm-template.R
git commit -m "mm: a random slope in time, STRUCTURE \"slope\" (helpers)"
```

### Task 2: the `SLOPE` study choice, report and render

**Files:**
- Modify: `inst/templates/30_analyses/mm.qmd` (chunks `edit-study-choices`, `fit`, `tbl-counts`, `save`)
- Create: `news/feat-mm-random-slope.md`
- Test: `tests/testthat/test-mm-template.R`

**Interfaces:**
- Consumes: Task 1's `mm_check(..., visit, slope, time_terms)`, `mm_fit(..., visit, slope)`, `fit$n_single_time`.
- Produces: the study choice `SLOPE`; `bundle$meta$slope`.

- [ ] **Step 1: Write the failing tests.** In the test "mm scaffolds with its study choices and EDIT: markers", add
  `"SLOPE"` to the field vector, after `"STRUCTURE"`. After the test "mm compares structures only when STRUCTURE lists
  several", add:

```r
test_that("mm renders a reported slope model with its variances and the one-time count", {
  skip_on_cran()
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  out <- mm_render_fixture(choices = 'STRUCTURE <- c("slope", "cs")')
  html <- gsub("(?s)<pre[^>]*>.*?</pre>", "", paste(readLines(out$output, warn = FALSE), collapse = "\n"), perl = TRUE)
  expect_match(html, "log(time + 1) variance", fixed = TRUE)
  expect_match(html, "patients measured at one time", fixed = TRUE)
  expect_match(html, compare_table)
  set <- file.path(hvtiRutilities::study_dir("estimates", out$root), "outcome-mixed")
  bundle <- readRDS(file.path(set, "mm.rds"))
  expect_identical(bundle$meta$structure, "slope")
  expect_identical(bundle$meta$slope, "log(time + 1)")
})
```

- [ ] **Step 2: Run them and see them fail**

Run (with this branch in a private library, see Global Constraints):
`NOT_CRAN=true R_LIBS=<scratch>/lib Rscript -e 'devtools::test(filter = "mm-template")'`
Expected: the scaffold test fails (no `SLOPE <- ` line); the render test fails.

- [ ] **Step 3: Implement.** In `edit-study-choices`, add to the `STRUCTURE` comment list, after the `"random"` line:

```r
#   "slope"      RANDOM int <time term> / subject=id: a random intercept and a random slope in
#                time, independent as SAS's RANDOM default type=vc. SLOPE names the term.
```

and after the `VISIT <- NULL` line:

```r
# EDIT: for "slope", the time term the random slope is on, written as it appears in TIME_TERMS, or NULL for the first.
# A SAS job's RANDOM int iv_echo, with iv_echo = 1/(t+1) in its DATA step, is "I(1/(time + 1))". A patient measured
# at one time adds nothing to the slope; the report counts them.
SLOPE <- NULL
```

In the `fit` chunk, replace the first and third lines:

```r
.slope <- if (is.null(SLOPE)) TIME_TERMS[[1L]] else SLOPE
mm_check(d, .id, TIME, STRUCTURE, IMPUTATION, VISIT, .slope, TIME_TERMS)
model_formula <- stats::reformulate(c(TIME_TERMS, PREDICTORS), response = .response)
fits <- lapply(stats::setNames(STRUCTURE, STRUCTURE),
               function(s) mm_fit(d, model_formula, .id, TIME, s, METHOD, VISIT, if (identical(s, "slope")) .slope))
```

In `tbl-counts`, replace the `knitr::kable(data.frame(...))` call with:

```r
.counts <- data.frame(
  quantity = c("patients", "measurements", "measurements per patient, median", "measurements per patient, range"),
  value = c(fit$n_patients, fit$n_measurements, stats::median(fit$per_patient), paste(range(fit$per_patient), collapse = " to "))
)
if (identical(fit$structure, "slope")) {
  .counts <- rbind(.counts, data.frame(quantity = "patients measured at one time, adding nothing to the slope",
                                       value = fit$n_single_time))
}
knitr::kable(.counts)
```

In `save`, in `meta = list(...)`, after `visit = VISIT,` add `slope = if ("slope" %in% STRUCTURE) .slope,`.

Create `news/feat-mm-random-slope.md`:

```markdown
- `mm` fits a random slope in time: `STRUCTURE = "slope"` is SAS's `RANDOM int <slope> / subject=id`, a random intercept and an independent random slope on the time term named in the new study choice `SLOPE`. `STRUCTURE <- c("cs", "slope")` fits both and compares them, as 33 corpus programs in 10 studies did by hand.
```

- [ ] **Step 4: Run the tests and see them pass**

Reinstall into the private library, then:
`NOT_CRAN=true R_LIBS=<scratch>/lib Rscript -e 'devtools::test(filter = "mm-template|add-job")'`
Expected: 0 failures, 0 skips.

- [ ] **Step 5: Guards, lint and commit**

Run: `bash tools/check-us-spelling.sh && bash tools/check-no-site-identifiers.sh &&
python3 dev/specs/artifacts/check-roadmap-counts.py && Rscript -e 'lintr::lint("inst/templates/30_analyses/mm.qmd")'`
Expected: all pass, no lints.

```bash
git add inst/templates/30_analyses/mm.qmd tests/testthat/test-mm-template.R news/feat-mm-random-slope.md
git commit -m "mm: SLOPE study choice, slope report rows and render"
```
