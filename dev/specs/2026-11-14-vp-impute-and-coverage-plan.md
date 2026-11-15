# vp impute and coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `vp-fit` and `vp-dependence` impute missing predictor values once before varPro instead of dropping
patients, and every vp report keeps "not examined" apart from "examined, not selected".

**Architecture:** One internal helper, `.vp_missing()` in a new `R/vp-missing.R`, does the outcome drops, the
missingness ceiling and the counts table for both templates; each template's `tbl-missing` chunk then imputes with
`randomForestSRC::impute()` under `cache_fit()`. The refit vote gains a pure helper, `vp_vote()`, in `vp-fit`'s
`judge` chunk. The handoff `vp.rds` gains `not_examined` and `not_examined_refits`, which `vp-explain` and
`vp-individual` read.

**Tech Stack:** R, varPro 3.3.0, randomForestSRC 3.10.0 (`impute()`), testthat edition 3, Quarto.

## Global Constraints

- The design is `dev/specs/2026-11-14-vp-impute-and-coverage-design.md`, decisions D1 to D9 of 2026-11-14.
- `NA_ACTION` values are `"na.impute"` (default) and `"na.omit"`, validated with `match.arg()`.
- The outcome is never imputed and never enters the imputation model; a row missing it is dropped and counted.
- `MAX_MISSING <- 0.4`; `MAX_UNTESTED <- 0.1`; `MIN_TESTED_SHARE <- 0.5`; all `EDIT:`-marked in the study choices.
- Imputation: `randomForestSRC::impute(data = <predictors only>, ntree = 250, verbose = FALSE)`, once, before
  noise and before subsampling, cached as `"vp-fit-impute"` / `"vp-dependence-impute"` with `seed = SEED`.
- No `upgrade_job()` change (D2). No `"mice"` option (D6).
- Lines are at most 135 characters; US spelling (`tools/check-us-spelling.sh`).
- Every study-specific line in a template is marked `EDIT:`; comments say why a choice matters.
- Templates carry no study identifiers (`test-add-job.R` checks).
- Roxygen is Rd markup; the new helper is internal (`@noRd`).
- No `Version:` bump and no `NEWS.md` edit: a fragment in `news/feat-vp-impute.md`.
- Never `git add -A`; stage explicit paths.
- Template tests run the INSTALLED templates. Before each test run:
  `R CMD INSTALL -l "$SCRATCH/lib" . >/dev/null` and run tests with `R_LIBS="$SCRATCH/lib" NOT_CRAN=true`,
  where `SCRATCH` is a session scratch directory. Never run anything against `/Volumes/qhsstudies`.
- Test command used below (call it `VPTEST`):
  `R_LIBS="$SCRATCH/lib" NOT_CRAN=true Rscript -e 'devtools::test(filter = "vp-templates|vp-missing")'`

---

### Task 1: `.vp_missing()` helper

**Files:**
- Create: `R/vp-missing.R`
- Test: `tests/testthat/test-vp-missing.R`

**Interfaces:**
- Produces: `.vp_missing(d, predictors, outcome = character(), na_action = c("na.impute", "na.omit"),
  max_missing = 0.4)` returning a list:
  `d` (rows kept; predictors still `NA` in `"na.impute"` mode), `table` (data.frame `Row`, `Count`),
  `cohort` (list: `na_action`, `n_supplied`, `n_outcome_missing`, `n_imputed` named integer, `n_dropped` integer).

- [ ] **Step 1: Write the failing tests**

```r
# tests/testthat/test-vp-missing.R
vpm_data <- function() {
  d <- data.frame(y = c(1, 2, NA, 4, 5, 6, 7, 8, 9, 10), a = c(NA, 2:10), b = c(1, NA, 3:10), c = 1:10)
  d$a[5] <- NA
  d
}

test_that(".vp_missing drops a missing outcome in either mode and counts it on its own", {
  for (na in c("na.impute", "na.omit")) {
    m <- .vp_missing(vpm_data(), c("a", "b", "c"), outcome = "y", na_action = na)
    expect_false(anyNA(m$d$y))
    expect_identical(m$cohort$n_supplied, 10L)
    expect_identical(m$cohort$n_outcome_missing, 1L)
  }
})

test_that(".vp_missing keeps every row with an outcome under na.impute, and counts what it will impute", {
  m <- .vp_missing(vpm_data(), c("a", "b", "c"), outcome = "y", na_action = "na.impute")
  expect_identical(nrow(m$d), 9L)
  expect_identical(m$cohort$n_imputed, c(a = 2L, b = 1L, c = 0L))
  expect_identical(m$cohort$n_dropped, 0L)
  expect_true(anyNA(m$d$a))
})

test_that(".vp_missing drops incomplete rows under na.omit, exactly as complete.cases() did", {
  d <- vpm_data()
  m <- .vp_missing(d, c("a", "b", "c"), outcome = "y", na_action = "na.omit")
  expect_identical(m$d, d[stats::complete.cases(d), , drop = FALSE])
  expect_identical(m$cohort$n_dropped, 3L)
  expect_identical(m$cohort$n_imputed, c(a = 0L, b = 0L, c = 0L))
})

test_that(".vp_missing refuses to impute a predictor above the ceiling, and names it", {
  d <- vpm_data()
  d$b[1:6] <- NA
  expect_error(.vp_missing(d, c("a", "b", "c"), outcome = "y", max_missing = 0.4), "b \\(56%\\)")
  expect_no_error(.vp_missing(d, c("a", "b", "c"), outcome = "y", na_action = "na.omit", max_missing = 0.4))
})

test_that(".vp_missing's table states n supplied, n used and the rule", {
  m <- .vp_missing(vpm_data(), c("a", "b", "c"), outcome = "y")
  expect_identical(m$table$Row[1], "Supplied")
  expect_identical(m$table$Count[m$table$Row == "Used"], "9")
  expect_identical(m$table$Count[m$table$Row == "Imputed: a"], "2 (22%)")
  expect_match(attr(m$table, "rule"), "imputed once by random forest")
})

test_that(".vp_missing works with no outcome, as vp-dependence calls it", {
  m <- .vp_missing(vpm_data(), c("a", "b"), na_action = "na.impute")
  expect_identical(nrow(m$d), 10L)
  expect_identical(m$cohort$n_outcome_missing, 0L)
})
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `Rscript -e 'devtools::test(filter = "vp-missing")'`
Expected: FAIL, `could not find function ".vp_missing"`.

- [ ] **Step 3: Implement**

```r
# R/vp-missing.R

# Missing values for a vp job, before any imputation. varPro removes every
# incomplete row and ignores na.action, so the vp templates settle missing
# values here, before varPro sees the data: a row missing the outcome is
# dropped in either mode; under "na.impute" the predictors are left for the
# template to impute once, and a predictor missing in more than max_missing of
# the rows is refused rather than filled; under "na.omit" incomplete rows go,
# as the templates did before. Returns the rows, a counts table with the rule
# as its "rule" attribute, and the counts for the handoff's cohort.
#' @noRd
.vp_missing <- function(d, predictors, outcome = character(), na_action = c("na.impute", "na.omit"),
                        max_missing = 0.4) {
  na_action <- match.arg(na_action)
  outcome <- as.character(outcome)
  n_supplied <- nrow(d)
  no_outcome <- if (length(outcome)) !stats::complete.cases(d[outcome]) else logical(n_supplied)
  d <- d[!no_outcome, , drop = FALSE]
  n_missing <- vapply(d[predictors], function(x) sum(is.na(x)), integer(1L))
  share <- if (nrow(d)) n_missing / nrow(d) else n_missing * 0
  n_dropped <- 0L
  if (na_action == "na.impute") {
    sparse <- names(share)[share > max_missing]
    if (length(sparse)) {
      stop("Missing in more than ", 100 * max_missing, "% of the rows, too many to impute: ",
           paste0(sparse, " (", round(100 * share[sparse]), "%)", collapse = ", "),
           ". Remove them from the predictors, raise MAX_MISSING, or set NA_ACTION <- \"na.omit\".", call. = FALSE)
    }
    n_imputed <- n_missing
  } else {
    keep <- stats::complete.cases(d[predictors])
    n_dropped <- sum(!keep)
    d <- d[keep, , drop = FALSE]
    n_imputed <- n_missing * 0L
  }
  pct <- function(k) paste0(k, " (", round(100 * k / max(1L, n_supplied - sum(no_outcome))), "%)")
  hit <- names(n_missing)[n_missing > 0L]
  table <- data.frame(
    Row = c("Supplied", "Outcome missing, dropped", paste0("Missing: ", hit),
            if (na_action == "na.impute") paste0("Imputed: ", hit) else "Missing a predictor, dropped", "Used"),
    Count = c(as.character(n_supplied), as.character(sum(no_outcome)), vapply(n_missing[hit], pct, ""),
              if (na_action == "na.impute") vapply(n_missing[hit], pct, "") else as.character(n_dropped),
              as.character(nrow(d))),
    stringsAsFactors = FALSE
  )
  attr(table, "rule") <- if (na_action == "na.impute") {
    "Missing predictor values were imputed once by random forest, without the outcome, before the screen."
  } else {
    "Patients missing any predictor were excluded before the screen."
  }
  list(d = d, table = table,
       cohort = list(na_action = na_action, n_supplied = as.integer(n_supplied),
                     n_outcome_missing = as.integer(sum(no_outcome)),
                     n_imputed = n_imputed, n_dropped = as.integer(n_dropped)))
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `Rscript -e 'devtools::test(filter = "vp-missing")'`
Expected: `FAIL 0 | WARN 0 | SKIP 0 | PASS 20` or close; every test passes.

- [ ] **Step 5: Lint and commit**

```bash
Rscript -e 'lintr::lint("R/vp-missing.R"); lintr::lint("tests/testthat/test-vp-missing.R")'
git add R/vp-missing.R tests/testthat/test-vp-missing.R
git commit -m "Add .vp_missing(): outcome drops, the imputation ceiling and both-ways counts for the vp jobs"
```

---

### Task 2: `vp-fit` imputes before the screen

**Files:**
- Modify: `inst/templates/30_analyses/vp-fit.qmd` (study choices near `MAX_UNTESTED`; chunk `tbl-missing`, ~403-420;
  narration under "## Reading the result")
- Test: `tests/testthat/test-vp-templates.R` (replace the test at line 43)

**Interfaces:**
- Consumes: `.vp_missing()` from Task 1.
- Produces: in the job environment, `NA_ACTION`, `MAX_MISSING`, `.miss` (the `.vp_missing()` result), an imputed
  `d`, and `.cohort` holding the old `n`, `n_events`, `n_censored` plus every field of `.miss$cohort`.

- [ ] **Step 1: Write the failing tests** (replace "vp-fit drops incomplete patients before the fit, and counts them")

```r
test_that("vp-fit imputes a missing predictor by default and keeps the patient", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  data <- vp_data()
  data$x1[1:7] <- NA
  env <- rf_env(data)
  rf_run("vp", "fit", vp_data_labels, env, vp_choices)
  expect_identical(nrow(env$d), 200L)
  expect_false(anyNA(env$d[vp_choices$PREDICTORS]))
  expect_identical(env$.cohort$n, 200L)
  expect_identical(env$.cohort$n_imputed[["x1"]], 7L)
  expect_identical(env$.cohort$na_action, "na.impute")
})

test_that("vp-fit with NA_ACTION = na.omit drops incomplete patients as before, and counts them", {
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  data <- vp_data()
  data$x1[1:7] <- NA
  env <- rf_env(data)
  rf_run("vp", "fit", vp_data_labels, env, utils::modifyList(vp_choices, list(NA_ACTION = "na.omit")))
  expect_identical(nrow(env$d), 193L)
  expect_identical(env$.cohort$n, 193L)
  expect_identical(env$.cohort$n_dropped, 7L)
})

test_that("vp-fit drops a patient missing the outcome, and imputes without it", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  data <- vp_data()
  data$time[1:3] <- NA
  data$x1[4:9] <- NA
  env <- rf_env(data)
  rf_run("vp", "fit", vp_data_labels, env, vp_choices)
  expect_identical(env$.cohort$n_outcome_missing, 3L)
  expect_identical(nrow(env$d), 197L)
  # The imputation call names the predictors and nothing else.
  chunk <- rf_chunk(readLines(template_path("vp", "fit"), warn = FALSE), "tbl-missing")
  expect_true(any(grepl("impute(data = d[PREDICTORS]", chunk, fixed = TRUE)))
})

test_that("vp-fit refuses to impute a predictor missing in most patients", {
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  data <- vp_data()
  data$x2[1:150] <- NA
  expect_error(rf_run("vp", "fit", vp_data_labels, rf_env(data), vp_choices), "x2 \\(75%\\)")
})
```

- [ ] **Step 2: Install and run; confirm the new tests fail**

Run: `R CMD INSTALL -l "$SCRATCH/lib" . >/dev/null && VPTEST`
Expected: the four new tests FAIL (e.g. `nrow(env$d)` is 193, not 200; `.cohort$n_imputed` is NULL).

- [ ] **Step 3: Add the study choices.** Directly above `MAX_UNTESTED`'s comment block in `edit-study-choices`:

```r
# EDIT: missing predictor values. varPro removes every patient with a missing
# value and ignores na.action, so the choice is made here, before it runs.
# "na.impute" fills them once by random forest, from the other predictors and
# never from the outcome: imputed values that carried the outcome would let the
# screen rank a predictor on signal the imputation put there. "na.omit" keeps
# complete cases, which is right when missingness itself tracks something the
# model should not see, such as labs collected only in a later surgical era.
# A patient missing the outcome is dropped either way.
NA_ACTION <- "na.impute"
# EDIT: the largest share of patients a predictor may be missing in and still
# be imputed. Above it the render stops and names the predictor: an imputation
# that invents most of a column decides the screen's answer for it.
MAX_MISSING <- 0.4
```

- [ ] **Step 4: Replace the body of `tbl-missing`** (keep the label and caption; caption becomes
  `"Patients supplied, missing values, and patients used"`):

```r
# varPro removes every patient with a missing value, so the screen would
# describe fewer patients than this report claims. NA_ACTION settles them here.
# The imputation runs once, before the noise columns are added and before the
# refits draw their patients, so the refits subsample the same completed data
# and the stability vote holds no imputation noise.
NA_ACTION <- match.arg(NA_ACTION, c("na.impute", "na.omit"))
.empty <- PREDICTORS[vapply(d[PREDICTORS], function(x) all(is.na(x)), logical(1L))]
if (length(.empty)) {
  stop("PREDICTORS names a column with no values: ", paste(.empty, collapse = ", "),
       ". Remove it from PREDICTORS.", call. = FALSE)
}
.miss <- hvtiRtemplates:::.vp_missing(d, PREDICTORS, outcome = c(TIME, EVENT, RESPONSE), na_action = NA_ACTION,
                                      max_missing = MAX_MISSING)
d <- .miss$d
if (anyNA(d[PREDICTORS])) {
  .imputed <- cache_fit("vp-fit-impute", randomForestSRC::impute(data = d[PREDICTORS], ntree = 250, verbose = FALSE),
                        seed = SEED, dir = dirname(set_path("estimates", "vp.rds")), refit = REFIT)
  # impute() removes a row with no observed predictor; a silent loss is what this chunk exists to stop.
  if (nrow(.imputed) != nrow(d)) {
    stop(nrow(d) - nrow(.imputed), " patient(s) have no observed predictor and cannot be imputed. ",
         "Remove them in the dataset build.", call. = FALSE)
  }
  d[PREDICTORS] <- .imputed[PREDICTORS]
}
if (anyNA(d[PREDICTORS])) stop("Predictors still hold missing values after NA_ACTION; varPro would drop them.", call. = FALSE)
.missing_values <- .miss$table
.cohort <- c(list(n = as.integer(nrow(d))), .miss$cohort)
if (.survival) {
  .cohort$n_events <- as.integer(sum(d[[EVENT]] == 1))
  .cohort$n_censored <- as.integer(sum(d[[EVENT]] == 0))
}
cat(attr(.missing_values, "rule"), "\n\n")
knitr::kable(.missing_values)
```

- [ ] **Step 5: Add the methods paragraph** at the top of "## Reading the result":

```markdown
**Missing values.** With `NA_ACTION <- "na.impute"`, missing predictor values
were imputed once by random forest (`randomForestSRC::impute()`, 250 trees)
from the other predictors, never from the outcome, before the noise columns
were added and before the stability refits drew their patients. A predictor
missing in more than `MAX_MISSING` of the patients is refused, not filled.
Patients missing the outcome were excluded. With `"na.omit"`, every patient
missing a predictor was excluded instead. The table of missing values above
gives the counts either way.
```

- [ ] **Step 6: Install and run; confirm the whole vp file passes**

Run: `R CMD INSTALL -l "$SCRATCH/lib" . >/dev/null && VPTEST`
Expected: `FAIL 0`, `SKIP 0`.

- [ ] **Step 7: Commit**

```bash
git add inst/templates/30_analyses/vp-fit.qmd tests/testthat/test-vp-templates.R
git commit -m "vp-fit: impute missing predictors once before varPro (NA_ACTION), outcome excluded"
```

---

### Task 3: `vp-dependence` imputes before the graph

**Files:**
- Modify: `inst/templates/30_analyses/vp-dependence.qmd` (study choices above `SEED`, line ~206; `tbl-missing`,
  ~288-302; "## Reading the result", ~586)
- Test: `tests/testthat/test-vp-templates.R`

**Interfaces:**
- Consumes: `.vp_missing()` from Task 1.
- Produces: `.cohort` as in Task 2, without event counts. `OUTCOME`, when set, is the "outcome": rows missing it
  are dropped and it is left out of the imputation model, because the graph measures edges into it.

- [ ] **Step 1: Write the failing tests**

```r
test_that("vp-dependence imputes a missing variable by default, and leaves OUTCOME out of the imputation", {
  skip_on_cran()
  vp33_skip_unless_stack(rf_template_packages("vp", "dependence"))
  data <- vpd_data()
  data$b[1:9] <- NA
  env <- rf_env(data)
  rf_run("vp", "dependence", c("setup", "edit-study-choices", "tbl-data", "tbl-missing"), env, vpd_choices)
  expect_identical(nrow(env$d), 200L)
  expect_false(anyNA(env$d[vpd_choices$VARIABLES]))
  expect_identical(env$.cohort$n_imputed[["b"]], 9L)
  chunk <- rf_chunk(readLines(template_path("vp", "dependence"), warn = FALSE), "tbl-missing")
  expect_true(any(grepl("impute(data = d[VARIABLES]", chunk, fixed = TRUE)))
})

test_that("vp-dependence with NA_ACTION = na.omit drops incomplete patients as before", {
  vp33_skip_unless_stack(rf_template_packages("vp", "dependence"))
  data <- vpd_data()
  data$b[1:9] <- NA
  env <- rf_env(data)
  rf_run("vp", "dependence", c("setup", "edit-study-choices", "tbl-data", "tbl-missing"), env,
         utils::modifyList(vpd_choices, list(NA_ACTION = "na.omit")))
  expect_identical(nrow(env$d), 191L)
  expect_identical(env$.cohort$n_dropped, 9L)
})
```

- [ ] **Step 2: Install, run, confirm both fail.** Run: `R CMD INSTALL -l "$SCRATCH/lib" . >/dev/null && VPTEST`

- [ ] **Step 3: Add the study choices** above `# EDIT: the seed`, worded for this job:

```r
# EDIT: missing values. uvarpro() removes every patient with a missing value
# and ignores na.action, so the choice is made here. "na.impute" fills the
# VARIABLES once by random forest, from each other and never from OUTCOME: the
# graph measures edges into OUTCOME, and an imputation that used it would draw
# some of them itself. "na.omit" keeps complete cases. A patient missing
# OUTCOME, when it is set, is dropped either way.
NA_ACTION <- "na.impute"
# EDIT: the largest share of patients a variable may be missing in and still be imputed.
MAX_MISSING <- 0.4
```

- [ ] **Step 4: Replace the body of `tbl-missing`:**

```r
# uvarpro() removes every patient with a missing value. NA_ACTION settles them
# here, once, before the noise columns and the refits.
NA_ACTION <- match.arg(NA_ACTION, c("na.impute", "na.omit"))
.empty <- .cols[vapply(d[.cols], function(x) all(is.na(x)), logical(1L))]
if (length(.empty)) {
  stop("VARIABLES or OUTCOME names a column with no values: ", paste(.empty, collapse = ", "),
       ". Remove it.", call. = FALSE)
}
.miss <- hvtiRtemplates:::.vp_missing(d, VARIABLES, outcome = OUTCOME, na_action = NA_ACTION, max_missing = MAX_MISSING)
d <- .miss$d
if (anyNA(d[VARIABLES])) {
  .imputed <- cache_fit("vp-dependence-impute",
                        randomForestSRC::impute(data = d[VARIABLES], ntree = 250, verbose = FALSE),
                        seed = SEED, dir = dirname(set_path("estimates", "dependence.rds")), refit = REFIT)
  # impute() removes a row with no observed value; a silent loss is what this chunk exists to stop.
  if (nrow(.imputed) != nrow(d)) {
    stop(nrow(d) - nrow(.imputed), " patient(s) have no observed value in VARIABLES and cannot be imputed. ",
         "Remove them in the dataset build.", call. = FALSE)
  }
  d[VARIABLES] <- .imputed[VARIABLES]
}
if (anyNA(d[.cols])) stop("Variables still hold missing values after NA_ACTION; uvarpro() would drop them.", call. = FALSE)
.missing_values <- .miss$table
.cohort <- c(list(n = as.integer(nrow(d))), .miss$cohort)
cat(attr(.missing_values, "rule"), "\n\n")
knitr::kable(.missing_values)
```

- [ ] **Step 5: Add a methods paragraph** at the top of "## Reading the result", as Task 2 Step 5 with
  "predictor" read as "variable", "the outcome" as "`OUTCOME`", and "the stability refits" unchanged.

- [ ] **Step 6: Install, run, confirm `FAIL 0` and `SKIP 0`.**

- [ ] **Step 7: Commit**

```bash
git add inst/templates/30_analyses/vp-dependence.qmd tests/testthat/test-vp-templates.R
git commit -m "vp-dependence: impute missing variables once before uvarpro (NA_ACTION), OUTCOME excluded"
```

---

### Task 4: the refit vote counts only refits that examined a variable; `MAX_UNTESTED` 0.1

**Files:**
- Modify: `inst/templates/30_analyses/vp-fit.qmd` (study choices `MAX_UNTESTED` and `SELECT_SHARE`; chunk `judge`;
  chunk `tbl-stability` ~728-766; chunk `save` ~820)
- Test: `tests/testthat/test-vp-templates.R` (test at line 159; new tests beside the `vp_judge` tests)

**Interfaces:**
- Produces: `vp_vote(stab, repeats, min_tested_share)` in the `judge` chunk, returning a data.frame
  `variable`, `share_tested`, `share_selected` (over refits that tested it; `NA` when none did), `examined`
  (logical: `share_tested >= min_tested_share`), sorted by `-share_selected` then `-share_tested`.
  `.freq` in the job is its result.

- [ ] **Step 1: Write the failing tests**

```r
test_that("vp_vote counts a selection over the refits that tested the variable, not over REPEATS", {
  vote <- vp_judge_fn()$vp_vote
  stab <- rbind(
    data.frame(r = 1:20, variable = "a", tested = 1:20 <= 3, selected = 1:20 <= 3),
    data.frame(r = 1:20, variable = "b", tested = TRUE, selected = 1:20 <= 3)
  )
  v <- vote(stab, repeats = 20, min_tested_share = 0.5)
  a <- v[v$variable == "a", ]
  b <- v[v$variable == "b", ]
  expect_equal(a$share_selected, 1)
  expect_false(a$examined)
  expect_equal(b$share_selected, 0.15)
  expect_true(b$examined)
})

test_that("vp_vote gives NA, not 0, to a variable no refit tested", {
  vote <- vp_judge_fn()$vp_vote
  stab <- data.frame(r = 1:4, variable = "z", tested = FALSE, selected = FALSE)
  expect_true(is.na(vote(stab, repeats = 4, min_tested_share = 0.5)$share_selected))
})

test_that("vp-fit hands on only variables the refits examined, and names the rest", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  env <- vp_fit_first()
  h <- readRDS(env$set_path("estimates", "vp.rds"))
  expect_identical(h$selected, env$.freq$variable[env$.freq$examined & (env$.freq$share_selected >= 0.5) %in% TRUE])
})
```

Change the test at line 159 so its last line reads:

```r
  expect_true("MAX_UNTESTED <- 0.1" %in% rf_chunk(lines, "edit-study-choices"))
```

`vp_judge_fn()` is defined in the test file at line ~64 and evaluates the `judge` chunk into an environment; read it
before Step 3 and confirm it returns that environment. If it returns `vp_judge` alone, change it to
`function() { ...; env }` and update its existing callers to `vp_judge_fn()$vp_judge`.

- [ ] **Step 2: Install, run, confirm the new tests fail.**

- [ ] **Step 3: Change the study choices.** `MAX_UNTESTED <- 0.5` becomes `0.1`, and its comment's second sentence
  becomes: "0.1 lets the exploration setting pass (about 2 of 30 untested in the simulation below) and stops a
  screen that left more than one candidate in ten unexamined, which would otherwise read as having found nothing
  in them." Below `SELECT_SHARE` add:

```r
# EDIT: the share of the refits that must have tested a variable before their
# vote counts. A refit that did not test a variable says nothing about it, so
# it is left out of that variable's vote; a variable tested in fewer refits than
# this is listed as not examined, and neither handed on nor counted as rejected.
MIN_TESTED_SHARE <- 0.5
```

  and add to the existing checks beside the `SUBSAMPLE` check:

```r
if (!(MIN_TESTED_SHARE > 0 && MIN_TESTED_SHARE <= 1)) {
  stop("MIN_TESTED_SHARE must be a share in (0, 1].", call. = FALSE)
}
```

- [ ] **Step 4: Add `vp_vote()` at the end of the `judge` chunk:**

```r
# The refits' vote. A refit that did not test a variable is no evidence about it,
# so its share selected is over the refits that tested it, and a variable tested
# in fewer than min_tested_share of them is not examined: no vote either way.
vp_vote <- function(stab, repeats, min_tested_share) {
  n_tested <- tapply(stab$tested, stab$variable, sum)
  n_selected <- tapply(stab$selected, stab$variable, sum)[names(n_tested)]
  out <- data.frame(
    variable = names(n_tested),
    share_tested = as.vector(n_tested) / repeats,
    share_selected = ifelse(as.vector(n_tested) > 0, as.vector(n_selected) / pmax(1, as.vector(n_tested)), NA_real_),
    row.names = NULL
  )
  out$examined <- out$share_tested >= min_tested_share
  out[order(-out$share_selected, -out$share_tested, na.last = TRUE), ]
}
```

- [ ] **Step 5: In `tbl-stability`,** replace the block from the comment
  `# Over REPEATS, not over the refits a variable appears in` through the `.freq <- .freq[order(...)]` line with:

```r
  .freq <- vp_vote(.stab, REPEATS, MIN_TESTED_SHARE)
  .unexamined <- .freq$variable[!.freq$examined]
  if (length(.unexamined)) {
    cat("Not examined in the refits (tested in fewer than ", MIN_TESTED_SHARE * 100, "% of them), so neither ",
        "handed on nor rejected: ", paste(.unexamined, collapse = ", "), ".\n", sep = "")
  }
```

  and the `.keep` line with `.keep <- .freq$variable[.freq$examined & (.freq$share_selected >= SELECT_SHARE) %in% TRUE]`.
  Update the chunk caption to `"How often each candidate was tested, and selected when tested, across the refits"`.

- [ ] **Step 6: In `save`,** change the refit branch of `.selected` to
  `.freq$variable[.freq$examined & (.freq$share_selected >= SELECT_SHARE) %in% TRUE]`.

- [ ] **Step 7: Install, run the vp tests.** If an end-to-end test now stops with "real variables are untested"
  (the 200-patient, `NTREE = 50` fixture is smaller than what the 0.1 default is calibrated to), add
  `MAX_UNTESTED = 0.5` to `vp_choices` in `tests/testthat/helper-vp.R` with the comment
  `# The fixture is far smaller than the exploration setting MAX_UNTESTED's 0.1 is set for.`
  Re-run. Expected: `FAIL 0`, `SKIP 0`.

- [ ] **Step 8: Mutation check.** Temporarily change `vp_vote`'s `share_selected` to `as.vector(n_selected) / repeats`,
  reinstall, run; the first new test must FAIL. Revert, reinstall, run; it passes.

- [ ] **Step 9: Commit**

```bash
git add inst/templates/30_analyses/vp-fit.qmd tests/testthat/test-vp-templates.R tests/testthat/helper-vp.R
git commit -m "vp-fit: refit vote counts only refits that tested a variable; MAX_UNTESTED defaults to 0.1"
```

---

### Task 5: the handoff names what was not examined, and the explain jobs say so

**Files:**
- Modify: `inst/templates/30_analyses/vp-fit.qmd` (chunk `save`)
- Modify: `inst/templates/30_analyses/vp-explain.qmd` (chunks `screen`, `select`)
- Modify: `inst/templates/30_analyses/vp-individual.qmd` (chunk `screen`; `vpi_coverage()` in `individual-helpers`)
- Test: `tests/testthat/test-vp-templates.R` (tests at lines 410 and 483; new test)

**Interfaces:**
- Consumes: `.freq$examined` (Task 4), `.cohort` (Task 2).
- Produces: `vp.rds` names `fit, coverage, selected, family, not_examined, not_examined_refits`.
  `vpi_coverage()` output gains `state`, one of `"selected"`, `"examined, not selected"`, `"not examined"`.

- [ ] **Step 1: Update and add tests.** At line 410 the `expect_named` becomes
  `expect_named(h, c("fit", "coverage", "selected", "family", "not_examined", "not_examined_refits"))`, and add
  `expect_identical(h$not_examined, as.character(env$.real$variable[!env$.real$tested]))`.
  At line 483 the expected error becomes `"the screen did not examine"`. New test:

```r
test_that("vpi_coverage gives each predictor one of the three states", {
  e <- vpi_helpers_env()
  cov <- data.frame(variable = c("s", "e", "n"), noise = FALSE, tested = c(TRUE, TRUE, FALSE))
  grad <- data.frame(s = c(0.1, 0.2), e = c(0.1, 0.1), n = c(NA, NA))
  out <- e$vpi_coverage(grad, c(s = "s", e = "e", n = "n"), cov, selected = "s")
  expect_identical(out$state, c("selected", "examined, not selected", "not examined"))
})
```

  Before writing this test, read `vpi_coverage()`'s signature and the existing test at line 729 and shape `grad`
  and `.parent` the same way that test does; the call above follows the chunk's call
  `vpi_coverage(grad, .parent, cov, selected)`.

- [ ] **Step 2: Install, run, confirm these fail.**

- [ ] **Step 3: `save` in vp-fit.** The list becomes:

```r
  list(fit = fit, coverage = cov, selected = .selected, family = .family,
       not_examined = as.character(.real$variable[!.real$tested]),
       not_examined_refits = if (REPEATS > 0) as.character(.freq$variable[!.freq$examined]) else character()),
```

- [ ] **Step 4: `select` in vp-explain.** Replace the `cat(...)` line and the first branch of the `stop()`:

```r
  cat("Not drawn: the screen did not examine them, so it has no evidence about them either way: ",
      paste(.untested, collapse = ", "), "\n", sep = "")
```

```r
    paste0("No variable to draw: the screen did not examine ", paste(.untested, collapse = ", "),
           ", so it has no evidence about them either way. Name examined variables in PARTIAL_VARS.")
```

- [ ] **Step 5: Print the screen's patients in both explain jobs.** At the end of each `screen` chunk:

```r
.vp_cohort <- .vp_read$lineage$cohort
# A screen saved before NA_ACTION existed records only n.
if (!is.null(.vp_cohort$na_action)) {
  cat("The screen used ", .vp_cohort$n, " of ", .vp_cohort$n_supplied, " patients supplied (NA_ACTION = \"",
      .vp_cohort$na_action, "\"; ", sum(.vp_cohort$n_imputed), " value(s) imputed, ", .vp_cohort$n_outcome_missing,
      " missing the outcome dropped).\n", sep = "")
}
```

- [ ] **Step 6: `vpi_coverage()`.** After `out$selected <- ...`:

```r
  out$state <- ifelse(out$selected, "selected", ifelse(out$tested, "examined, not selected", "not examined"))
```

  Then find where `tbl-coverage` builds its displayed table from `icov` and show `state` in place of the bare
  `tested` and `selected` columns.

- [ ] **Step 7: Install, run, confirm `FAIL 0`, `SKIP 0`.**

- [ ] **Step 8: Commit**

```bash
git add inst/templates/30_analyses/vp-fit.qmd inst/templates/30_analyses/vp-explain.qmd \
  inst/templates/30_analyses/vp-individual.qmd tests/testthat/test-vp-templates.R
git commit -m "vp family: hand on what the screen did not examine, and report it as no evidence either way"
```

---

### Task 6: measure `uvarpro()` coverage (D9)

**Files:**
- Create: `dev/vp/uvarpro-coverage.R` (kept: it is the measurement's record)
- Modify: `inst/templates/30_analyses/vp-dependence.qmd` (one comment, or Task 6b below)

- [ ] **Step 1: Write the measurement script**

```r
# dev/vp/uvarpro-coverage.R
# Does uvarpro() at vp-dependence's settings build release rules for every variable?
# Run: Rscript dev/vp/uvarpro-coverage.R   (local; no study data)
suppressPackageStartupMessages(library(varPro))
sim <- function(n, p, seed) {
  set.seed(seed)
  d <- as.data.frame(matrix(stats::rnorm(n * p), n, p, dimnames = list(NULL, sprintf("x%02d", seq_len(p)))))
  d$x02 <- d$x01 + stats::rnorm(n, 0, 0.3)
  d$f1 <- factor(sample(c("a", "b"), n, replace = TRUE))
  d
}
for (cfg in list(c(n = 200, p = 5), c(n = 400, p = 30), c(n = 1900, p = 30))) {
  d <- sim(cfg[["n"]], cfg[["p"]], 2026)
  fit <- uvarpro(d, ntree = 200, seed = -2026)
  ruled <- unique(attr(fit$x, "xvar.map")[as.character(unique(fit$results$variable))])
  cat(sprintf("n = %d, p = %d: %d of %d variables have release rules; none for: %s\n",
              cfg[["n"]], ncol(d), length(ruled), ncol(d),
              paste(setdiff(names(d), ruled), collapse = ", ")))
}
```

  Before running, read `str(fit$results)` and `attr(fit$x, "xvar.map")` on the first fit, and adjust the
  `ruled` line so it maps each rule's released variable back to its source column. vp-dependence's `vpd_parent()`
  shows the template's own reading of the map.

- [ ] **Step 2: Run it** (local, no study data): `Rscript dev/vp/uvarpro-coverage.R`.

- [ ] **Step 3a: If every variable has rules in every configuration,** add above the `fit` chunk's `uvarpro()` call:
  `# Measured 2026-11-<dd> (dev/vp/uvarpro-coverage.R): at these settings every variable gets release rules,`
  `# so no variable here goes unexamined. Re-measure if NTREE or varPro changes.` Commit script and comment.

- [ ] **Step 3b: If any go without rules,** stop and report the counts to John before changing the template: the
  fix (exposing `MAX_TREE`/`MAX_RULES_TREE` and reporting the three states) is a design change to spec §4.4.

- [ ] **Step 4: Commit**

```bash
git add dev/vp/uvarpro-coverage.R inst/templates/30_analyses/vp-dependence.qmd
git commit -m "Measure uvarpro() coverage at vp-dependence's settings"
```

---

### Task 7: release note and the full gate

**Files:**
- Create: `news/feat-vp-impute.md`

- [ ] **Step 1: Write the fragment** (bullets only, no heading):

```markdown
- `vp-fit` and `vp-dependence` now impute missing predictor values once, by random forest and without the
  outcome, before the screen (`NA_ACTION <- "na.impute"`), instead of dropping every patient with a missing value.
  **Existing jobs will use more patients and may select differently on their next render.** Set
  `NA_ACTION <- "na.omit"` to keep complete cases. A predictor missing in more than `MAX_MISSING` (0.4) of the
  patients is refused, not imputed.
- The vp reports now separate *not examined* from *examined and not selected*. `vp-fit`'s refit vote counts only
  the refits that tested a variable (`MIN_TESTED_SHARE`), `MAX_UNTESTED` defaults to 0.1 (was 0.5), and `vp.rds`
  names the variables the screen did not examine.
```

- [ ] **Step 2: Full gate**

```bash
bash tools/check-us-spelling.sh
Rscript -e 'devtools::document()'   # expect no change to man/ or NAMESPACE; restore the RoxygenNote pin if it moved
Rscript -e 'lintr::lint_package()'  # expect no lints
R CMD INSTALL -l "$SCRATCH/lib" . >/dev/null
R_LIBS="$SCRATCH/lib" NOT_CRAN=true Rscript -e 'devtools::test()'   # expect FAIL 0; WARN as on main
R_LIBS="$SCRATCH/lib" Rscript -e 'devtools::check()'               # expect 0 errors, 0 warnings, 0 notes
```

- [ ] **Step 3: Commit, run the local `/code-review`, open the PR against `main`** (the PR body says the local review
  stood in for Copilot).

```bash
git add news/feat-vp-impute.md
git commit -m "News fragment for vp imputation and coverage"
```
