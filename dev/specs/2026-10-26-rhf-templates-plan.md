# `rhf` templates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `rhf-fit.qmd` and `rhf-explain.qmd`, random hazard forest templates for counting-process data with time-varying covariates, as `in-flight` templates under a new `rhf` prefix.

**Architecture:** An `rhf` taxonomy row lands in hvtiRutilities first. In hvtiRtemplates, two pieces of package code come before the templates: `read_job_data(whole_patients = TRUE)` refuses a `WHERE` that keeps part of a patient, and `R/counting-process.R` checks and (in a draft only) repairs counting-process rows. The templates mirror `rfs-fit`/`rfs-explain`: fit tunes tree size, grows the forest under `cache_fit()` and saves `rhf.rds`; explain reads it and reports AUC(t), hazard curves and VarPro-based importance, caching the VarPro cache under a stable name for a later VarPro-RHF template.

**Tech Stack:** R, Quarto templates, testthat 3e, randomForestRHF 2.1.0, ggRandomForests 4.0.0, hvtiRutilities, hvtiPlotR.

**Spec:** `dev/specs/2026-10-26-rhf-templates-design.md` (approved 2026-10-26, amended while planning: §3.1 JOIN, §3.4 id recoding, §4.2 curves, §5.1, §6).

## Global Constraints

- `randomForestRHF (>= 2.1.0)` in `Suggests`; `ggRandomForests (>= 4.0.0)` and `hvtiPlotR (>= 2.8.18)` as `rfs-fit` already floors them.
- The hvtiRutilities floor moves to the version that ships the `rhf` row, and only in this package's own bump commit (AGENTS.md "Release ordering").
- Both catalog rows carry `"status": "in-flight"`.
- Lines at most 135 characters (`.lintr`). Roxygen is Rd markup: `\code{}`, never backticks.
- **Templates carry no study identifiers**: no `/studies/` path, no study name, no built-dataset file name. The Hsich study is never named in a template.
- Every study-specific template line carries `EDIT:`; the `JOIN` block carries none.
- No `news/` fragment for a change that ships nothing; `dev/` and `.github/` ship nothing. Every task below that touches `R/`, `inst/` or `DESCRIPTION` ships.
- No version bump in any task. Bump and `news.py collect` happen when John names the version.
- **Do not run R on the Mac against `/Volumes/qhsstudies`.** Everything here runs on the package checkouts and temp studies only.
- Run local tests with `_R_CHECK_LIMIT_CORES_=TRUE` and `NOT_CRAN=true`, from a private library if another session may reinstall the package (`R CMD INSTALL -l <lib> .` then `R_LIBS=<lib>`).
- Never `git add -A` after a test run: a failing run writes `tests/testthat/_problems/`.

## File map

| file | repo | change |
|---|---|---|
| `R/taxonomy.R`, `tests/testthat/test-taxonomy.R`, `news/feat-rhf-taxonomy.md` | hvtiRutilities | Task 1: `rhf` row |
| `R/job-data.R`, `tests/testthat/test-job-data.R`, `man/read_job_data.Rd` | hvtiRtemplates | Task 2: `whole_patients` |
| `R/counting-process.R`, `tests/testthat/test-counting-process.R` | hvtiRtemplates | Task 3: `.cp_check()`, `.cp_repair_notice()` |
| `inst/templates/30_analyses/rhf-fit.qmd`, `.lintr`, `inst/extdata/templates.json`, `DESCRIPTION`, `tests/testthat/helper-rf.R`, `tests/testthat/helper-seed-hygiene.R`, `tests/testthat/test-template-data-routes.R`, `tests/testthat/test-job-data.R` | hvtiRtemplates | Task 4: the fit template |
| `tests/testthat/test-rhf-templates.R`, `tests/testthat/helper-rhf.R` | hvtiRtemplates | Task 5: fit tests |
| `inst/templates/30_analyses/rhf-explain.qmd`, `.lintr`, `inst/extdata/templates.json` | hvtiRtemplates | Task 6: the explain template and its tests |
| `inst/templates/README.md`, `news/feat-rhf-templates.md` | hvtiRtemplates | Task 7: docs and news |
| (none) | both | Task 8: gate |

Branches: hvtiRutilities `feat/rhf-taxonomy`; hvtiRtemplates `feat/rhf-templates`, cut from `origin/main` after this spec and plan merge. Work in a worktree for each (`git worktree add ../<repo>-rhf -b <branch> origin/main`).

**Ordering:** Task 1's PR must be **merged to hvtiRutilities `main`** before Task 4's catalog row can pass CI, because hvtiRtemplates CI installs hvtiRutilities from `main` (`Remotes` are unpinned) and the catalog tests check every catalog prefix against `hvti_taxonomy()`. Tasks 2 and 3 do not depend on Task 1 and can run while its PR is open. Locally, install the Task 1 branch into the private library before Task 4.

---

### Task 1: `rhf` taxonomy row (hvtiRutilities)

**Files:**
- Modify: `~/Documents/GitHub/hvtiRutilities/R/taxonomy.R` (the forest rows, after `vt` at about line 182)
- Modify: `~/Documents/GitHub/hvtiRutilities/tests/testthat/test-taxonomy.R:118-129`
- Create: `~/Documents/GitHub/hvtiRutilities/news/feat-rhf-taxonomy.md`

**Interfaces:**
- Produces: `hvti_taxonomy()` has a row `prefix = "rhf"`, `folder = "analyses"`, `umbrella = FALSE`. hvtiRtemplates' `add_job("rhf", ...)` and its catalog direction-one guard rely on it.

- [ ] **Step 1: Write the failing test.** In `test-taxonomy.R`, replace the forest-family test body (lines 118-129) with:

```r
test_that("the forest family is the outcome rows, umbrellas, sid, vt and rhf", {
  # The family splits on the OUTCOME axis. Pinning the set catches the two
  # ways it can regress: a fourth outcome row appearing without a spec, and
  # `rfr`, `sid`, `vt` or `rhf` being dropped back out while the job catalog
  # still carries rows for them -- which would fail hvtiRtemplates'
  # direction-one guard in a different repository, far from the edit that
  # caused it. `rhf` is matched on its own: "^rf" does not see it.
  tx <- hvti_taxonomy()
  forest <- tx$prefix[grepl("^(rf|rhf|sid|vt)", tx$prefix) & !is.na(tx$prefix)]
  expect_setequal(forest, c("rf", "rfsrc", "rfs", "rfc", "rfr", "rhf", "sid", "vt"))
  expect_true(all(tx$folder[match(c("rfs", "rfc", "rfr", "rhf", "sid", "vt"),
                                  tx$prefix)] == "analyses"))
  expect_false(tx$umbrella[tx$prefix %in% "rhf"])
})
```

- [ ] **Step 2: Run it and watch it fail.**

Run: `Rscript -e 'devtools::test(filter = "taxonomy")'`
Expected: FAIL in "the forest family ...": `forest` lacks `"rhf"`.

- [ ] **Step 3: Add the row.** In `R/taxonomy.R`, after the `vt` row, keeping the column alignment (`commas_linter` checks it):

```r
    c("rhf",   "Random hazard forest",      "analyses",      "time-varying covariates, counting-process hazard"),
```

- [ ] **Step 4: Run the taxonomy tests, then the whole suite.**

Run: `Rscript -e 'devtools::test(filter = "taxonomy")'` then `Rscript -e 'devtools::test()'`
Expected: PASS, `FAIL 0`. A test elsewhere that counts taxonomy rows (grep `nrow(hvti_taxonomy())` / `expect_length`) may need its count raised by one; raise it and say so in the commit message.

- [ ] **Step 5: Lint, document, news fragment.**

Run: `Rscript -e 'lintr::lint_package()'` (expect no lints) and `Rscript -e 'devtools::document()'` (expect no `man/` change; the taxonomy's Rd does not list rows. If it does, commit the change).

Create `news/feat-rhf-taxonomy.md`:

```markdown
* `hvti_taxonomy()` has an `rhf` row, "Random hazard forest", in `analyses`: random hazard forests on counting-process data with time-varying covariates. It is the prefix of the `rhf-fit` and `rhf-explain` templates in hvtiRtemplates.
```

- [ ] **Step 6: Commit and open the PR.**

```bash
git add R/taxonomy.R tests/testthat/test-taxonomy.R news/feat-rhf-taxonomy.md
git commit -m "Add the rhf prefix to the taxonomy"
git push -u origin feat/rhf-taxonomy
gh pr create --title "Add the rhf prefix to the taxonomy" --body "..."
```

The PR body says the local `/code-review` stood in for Copilot if Copilot's quota is still out (AGENTS.md). John merges it; Task 4's CI waits on that merge.

---

### Task 2: `read_job_data(whole_patients = TRUE)`

**Files:**
- Modify: `R/job-data.R` (roxygen above `read_job_data` near line 633; signature at 747; the call to `.check_job_settings` at 750; after `kept <- .apply_where(...)` near line 818; `.check_job_settings` at 992)
- Test: `tests/testthat/test-job-data.R` (append)

**Interfaces:**
- Produces: `read_job_data(..., whole_patients = FALSE)`. With `TRUE` and a non-NULL `where`, it stops when any patient kept by `WHERE` lost some of their rows. Internal `.check_whole_patients(before, after, id)`.

- [ ] **Step 1: Write the failing tests.** Append to `test-job-data.R`:

```r
test_that("read_job_data(whole_patients = TRUE) refuses a WHERE that keeps part of a patient", {
  long <- data.frame(ccfid = c(1L, 1L, 1L, 2L, 2L, 3L), iv_start = c(0, 1, 2, 0, 1, 0),
                     iv_stop = c(1, 2, 3, 1, 2, 4), lab = c(5, 9, 5, 5, 5, 9), female = c(1, 1, 1, 0, 0, 1))
  cfg <- job_study(long)
  key <- c("ccfid", "iv_start")
  # A baseline column keeps or drops a patient whole.
  out <- read_job_data(cfg, where = quote(female == 1), key = key, whole_patients = TRUE)
  expect_identical(sort(unique(out$data$ccfid)), c(1L, 3L))
  expect_identical(nrow(out$data), 4L)
  # A time-varying one keeps part of patient 1 (and drops patient 3 whole, which is fine).
  expect_error(read_job_data(cfg, where = quote(lab < 9), key = key, whole_patients = TRUE),
               "1 patient kept by WHERE lost some of their rows")
  # The default changes nothing: the same WHERE keeps the partial patient.
  expect_identical(nrow(read_job_data(cfg, where = quote(lab < 9), key = key)$data), 4L)
  # No WHERE, nothing to check.
  expect_identical(nrow(read_job_data(cfg, key = key, whole_patients = TRUE)$data), 6L)
  expect_error(read_job_data(cfg, key = key, whole_patients = NA), "whole_patients must be TRUE or FALSE")
})
```

- [ ] **Step 2: Run them and watch them fail.**

Run: `Rscript -e 'devtools::test(filter = "job-data")'`
Expected: FAIL, "unused argument (whole_patients = TRUE)".

- [ ] **Step 3: Implement.**

Signature (line 747):

```r
read_job_data <- function(cfg, dataset = "study", analysis_set = NULL, where = NULL,
                          id = "ccfid", key = NULL, join = NULL, join_vars = NULL, reduce = NULL,
                          join_key = NULL, one_row_per_patient = FALSE, imputation = NULL,
                          whole_patients = FALSE) {
  .check_job_settings(dataset, analysis_set, where, id, key, join, join_vars, reduce, join_key, one_row_per_patient,
                      imputation, whole_patients)
```

After `kept <- .apply_where(...)` and before `counts <- .check_job_key(...)`:

```r
  if (whole_patients && !is.null(where)) .check_whole_patients(ids$data, kept$data, who$id)
```

`.check_job_settings` gains a last parameter `whole_patients = FALSE` and, after the `one_row_per_patient` check:

```r
  if (!is.logical(whole_patients) || length(whole_patients) != 1L || is.na(whole_patients)) {
    stop("whole_patients must be TRUE or FALSE.", call. = FALSE)
  }
```

New helper, after `.stop_repeated_patients()`:

```r
# A WHERE that keeps some of a patient's rows and drops others shortens that
# patient's follow-up without a word, and a job over intervals of follow-up
# cannot tell the rows it lost from time the patient was not at risk. So a job
# that models intervals asks for whole patients: each one kept with every row,
# or dropped. Counts only; no identifier reaches the message.
.check_whole_patients <- function(before, after, id) {
  n_before <- table(.id_text(before[[id]]))
  n_after <- table(.id_text(after[[id]]))
  kept <- names(n_after)
  partial <- sum(n_after[kept] < n_before[kept])
  if (partial) {
    stop(partial, if (partial == 1L) " patient" else " patients", " kept by WHERE lost some of their rows but not ",
         "all. This job models intervals of follow-up, so WHERE must keep or drop a patient whole: select on a ",
         "column whose value is the same on every row of a patient, such as a baseline one.", call. = FALSE)
  }
  invisible(NULL)
}
```

Roxygen, after `@param one_row_per_patient`:

```r
#' @param whole_patients \code{TRUE} for a job that models intervals of a
#'   patient's follow-up, such as a random hazard forest on counting-process
#'   rows. With a \code{where}, it stops when a patient kept by \code{where}
#'   lost some of their rows but not all, since that shortens follow-up without
#'   a word. \code{FALSE}, the default, checks nothing.
```

- [ ] **Step 4: Run the tests and the whole file.**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "job-data")'`
Expected: PASS. `man/read_job_data.Rd` gains the parameter.

- [ ] **Step 5: Mutation check.** Comment out the `.check_whole_patients(...)` call, rerun the filter, and confirm "refuses a WHERE that keeps part of a patient" fails. Restore it.

- [ ] **Step 6: Lint and commit.**

```bash
Rscript -e 'lintr::lint_package()'
git add R/job-data.R man/read_job_data.Rd tests/testthat/test-job-data.R
git commit -m "Let read_job_data() refuse a WHERE that keeps part of a patient"
```

---

### Task 3: `.cp_check()` and `.cp_repair_notice()`

**Files:**
- Create: `R/counting-process.R`
- Create: `tests/testthat/test-counting-process.R`

**Interfaces:**
- Produces:
  - `.cp_check(d, id, start, stop, event, predictors, repair = character())` returns `list(data, counts, repaired)`. `data` holds the columns `c(id, start, stop, event, predictors)` ordered by id then start; `counts` is a `data.frame(measure, value)` of character columns; `repaired` is a named character vector, names from `c("clip", "drop_na")`, one entry per repair that **changed rows**, empty otherwise.
  - `.cp_repair_notice(repaired)` returns `""` for no repairs; otherwise stops under a strict render, or calls `.run_mark_draft()` and returns a Quarto callout string.
- Consumes: `.strict_render()` (R/partial-render.R:172), `.run_mark_draft()` (R/run-info.R:104), `.id_text()` (R/job-data.R).

- [ ] **Step 1: Write the failing tests.** `tests/testthat/test-counting-process.R`:

```r
# A small counting-process data set: patient 1 has three intervals and dies
# in the last, patient 2 two intervals and is censored, patient 3 one.
cp_rows <- function() {
  data.frame(id = c(1L, 1L, 1L, 2L, 2L, 3L), t0 = c(0, 1, 2, 0, 1, 0), t1 = c(1, 2, 3, 1, 2, 4),
             dead = c(0L, 0L, 1L, 0L, 0L, 0L), lab = c(5, 6, 7, 5, 5, 9), age = c(60, 60, 60, 70, 70, 50))
}
cp <- function(d, repair = character()) {
  hvtiRtemplates:::.cp_check(d, id = "id", start = "t0", stop = "t1", event = "dead",
                             predictors = c("lab", "age"), repair = repair)
}

test_that(".cp_check() passes clean rows through and counts them", {
  out <- cp(cp_rows()[c(6, 2, 1, 3, 5, 4), ])
  expect_identical(out$data$id, c(1L, 1L, 1L, 2L, 2L, 3L))
  expect_identical(out$data$t0, c(0, 1, 2, 0, 1, 0))
  expect_identical(names(out$data), c("id", "t0", "t1", "dead", "lab", "age"))
  expect_length(out$repaired, 0L)
  value <- function(m) out$counts$value[out$counts$measure == m]
  expect_identical(value("Patients"), "3")
  expect_identical(value("Intervals"), "6")
  expect_identical(value("Events"), "1")
  expect_identical(value("Gaps between intervals"), "0")
})

test_that(".cp_check() stops on an overlap unless REPAIR clips it", {
  d <- cp_rows()
  d$t0[2] <- 0.5                      # patient 1's second interval starts inside the first
  expect_error(cp(d), "1 overlapping interval.*REPAIR <- \"clip\"")
  out <- cp(d, "clip")
  expect_identical(out$data$t0[2], 1)
  expect_match(out$repaired[["clip"]], "1 overlapping interval clipped")
})

test_that("clip drops an interval it leaves empty, and refuses to drop an event", {
  d <- rbind(cp_rows(), data.frame(id = 2L, t0 = 1.2, t1 = 1.8, dead = 0L, lab = 5, age = 70))
  out <- cp(d, "clip")                # the extra interval lies inside patient 2's second
  expect_identical(nrow(out$data), 6L)
  expect_match(out$repaired[["clip"]], "1 interval left empty and dropped")
  d <- cp_rows()
  d$t0[3] <- 1; d$t1[3] <- 2          # patient 1's event interval duplicates the one before it
  expect_error(cp(d, "clip"), "would drop an interval that carries the event")
})

test_that(".cp_check() stops on a zero-length interval unless REPAIR clips it", {
  d <- cp_rows()
  d$t1[6] <- 0
  expect_error(cp(d), "1 interval of zero or negative length")
  expect_identical(nrow(cp(d, "clip")$data), 5L)
})

test_that(".cp_check() stops on an event before a patient's last interval, with no repair", {
  d <- cp_rows()
  d$dead[1] <- 1L
  expect_error(cp(d, c("clip", "drop_na")), "1 patient has an event before their last interval")
})

test_that(".cp_check() stops on an event not coded 0/1 and on a missing id, start, stop or event", {
  d <- cp_rows()
  d$dead[3] <- 2L
  expect_error(cp(d), "dead must be coded 0 and 1")
  d <- cp_rows()
  d$t1[4] <- NA
  expect_error(cp(d, c("clip", "drop_na")), "1 interval has no id, start, stop or event")
})

test_that(".cp_check() stops on a missing predictor unless REPAIR drops it", {
  d <- cp_rows()
  d$lab[4] <- NA
  expect_error(cp(d), "1 interval is missing a predictor.*REPAIR <- \"drop_na\"")
  out <- cp(d, "drop_na")
  expect_identical(nrow(out$data), 5L)
  expect_match(out$repaired[["drop_na"]], "1 interval missing a predictor dropped")
  d <- cp_rows()
  d$lab[3] <- NA                      # the event interval
  expect_error(cp(d, "drop_na"), "would drop an interval that carries the event")
  d <- cp_rows()
  d$lab <- NA_real_
  expect_error(cp(d, "drop_na"), "no values: lab")
})

test_that(".cp_check() counts gaps and refuses an unknown repair", {
  d <- cp_rows()
  d$t0[5] <- 1.5                      # patient 2 is not at risk from 1 to 1.5
  out <- cp(d)
  expect_identical(out$counts$value[out$counts$measure == "Gaps between intervals"], "1")
  expect_error(cp(cp_rows(), "fill"), "REPAIR may name only \"clip\" and \"drop_na\"")
})

test_that("a repair that changes nothing is not reported", {
  expect_length(cp(cp_rows(), c("clip", "drop_na"))$repaired, 0L)
})

test_that(".cp_repair_notice() marks a draft, and stops a final render", {
  expect_identical(hvtiRtemplates:::.cp_repair_notice(character()), "")
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "")
  marked <- NULL
  local_mocked_bindings(.run_mark_draft = function(reason) marked <<- reason, .package = "hvtiRtemplates")
  note <- hvtiRtemplates:::.cp_repair_notice(c(clip = "1 overlapping interval clipped"))
  expect_match(note, "callout-important")
  expect_match(note, "1 overlapping interval clipped")
  expect_match(marked, "rows repaired in the job")
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "1")
  expect_error(hvtiRtemplates:::.cp_repair_notice(c(clip = "1 overlapping interval clipped")),
               "HVTI_TEMPLATE_STRICT")
})
```

- [ ] **Step 2: Run them and watch them fail.**

Run: `Rscript -e 'devtools::test(filter = "counting-process")'`
Expected: FAIL, "object '.cp_check' not found".

- [ ] **Step 3: Implement `R/counting-process.R`.**

```r
# Counting-process rows: one row per interval of a patient's follow-up, each
# with its start, stop and event, so a predictor may change over time. The rhf
# templates fit a hazard forest on them, and randomForestRHF refuses some
# defects only after the data are loaded, naming no patient. These checks run
# first and say what to fix.

.cp_repairs <- c("clip", "drop_na")

.cp_n <- function(n, noun, plural = paste0(noun, "s")) paste(n, if (n == 1L) noun else plural)

# The first few patients `ids` names, for a message that has to say where to look.
.cp_ids <- function(ids) {
  ids <- unique(.id_text(ids))
  paste0(" (", paste(utils::head(ids, 5L), collapse = ", "), if (length(ids) > 5L) ", ...", ")")
}

# Checks counting-process rows and, when `repair` names it, repairs a defect a
# job may repair while the dataset fix is in flight. Returns the rows ordered by
# patient and start, a table of counts, and what each repair changed. A defect
# not repaired stops, naming its kind, its count and the first few patients.
.cp_check <- function(d, id, start, stop, event, predictors, repair = character()) {
  unknown <- setdiff(repair, .cp_repairs)
  if (length(unknown)) {
    stop("REPAIR may name only \"clip\" and \"drop_na\"; it names ", paste(unknown, collapse = ", "), ".", call. = FALSE)
  }
  d <- d[, c(id, start, stop, event, predictors), drop = FALSE]
  incomplete <- is.na(d[[id]]) | is.na(d[[start]]) | is.na(d[[stop]]) | is.na(d[[event]])
  if (any(incomplete)) {
    stop(.cp_n(sum(incomplete), "interval has", "intervals have"), " no id, start, stop or event. ",
         "Resolve them in the dataset build; no repair can.", call. = FALSE)
  }
  if (!all(d[[event]] %in% c(0, 1))) {
    stop(event, " must be coded 0 and 1 (1 = event); found ", paste(sort(unique(d[[event]])), collapse = ", "),
         ". Code a competing event 0, so it censors.", call. = FALSE)
  }
  empty <- predictors[vapply(d[predictors], function(x) all(is.na(x)), logical(1L))]
  if (length(empty)) {
    stop("PREDICTORS names a column with no values: ", paste(empty, collapse = ", "), ". Remove it from PREDICTORS.",
         call. = FALSE)
  }
  d <- d[order(d[[id]], d[[start]]), , drop = FALSE]
  rownames(d) <- NULL
  repaired <- character()
  same <- function(d) c(FALSE, d[[id]][-1L] == d[[id]][-nrow(d)])
  prev_stop <- function(d) c(-Inf, d[[stop]][-nrow(d)])
  # An event on a row that would be removed is an outcome lost, which no repair may do.
  refuse_event_drop <- function(drop, why) {
    if (any(d[[event]][drop] == 1)) {
      stop("REPAIR \"", why, "\" would drop an interval that carries the event", .cp_ids(d[[id]][drop & d[[event]] == 1]),
           ". Fix it in the dataset build.", call. = FALSE)
    }
  }

  overlap <- same(d) & d[[start]] < prev_stop(d)
  if (any(overlap)) {
    if (!"clip" %in% repair) {
      stop(.cp_n(sum(overlap), "overlapping interval"), .cp_ids(d[[id]][overlap]), ": an interval starts before the ",
           "one before it ends. Fix it in the dataset build, or set REPAIR <- \"clip\" to render a draft meanwhile.",
           call. = FALSE)
    }
    d[[start]][overlap] <- prev_stop(d)[overlap]
  }
  short <- d[[stop]] <= d[[start]]
  if (any(short)) {
    if (!"clip" %in% repair) {
      stop(.cp_n(sum(short), "interval"), " of zero or negative length", .cp_ids(d[[id]][short]),
           ". Fix it in the dataset build, or set REPAIR <- \"clip\" to render a draft meanwhile.", call. = FALSE)
    }
    refuse_event_drop(short, "clip")
    d <- d[!short, , drop = FALSE]
  }
  if (any(overlap) || any(short)) {
    repaired[["clip"]] <- paste0(.cp_n(sum(overlap), "overlapping interval"), " clipped, ",
                                 .cp_n(sum(short), "interval"), " left empty and dropped")
  }

  last <- !duplicated(d[[id]], fromLast = TRUE)
  early <- d[[event]] == 1 & !last
  if (any(early)) {
    n <- length(unique(d[[id]][early]))
    stop(.cp_n(n, "patient has", "patients have"), " an event before their last interval", .cp_ids(d[[id]][early]),
         ". An event ends follow-up; fix it in the dataset build.", call. = FALSE)
  }

  missing <- !stats::complete.cases(d[predictors])
  if (any(missing)) {
    if (!"drop_na" %in% repair) {
      stop(.cp_n(sum(missing), "interval is", "intervals are"), " missing a predictor", .cp_ids(d[[id]][missing]),
           ". randomForestRHF cannot use them and dropping one opens a hole in the time at risk. Fill them in the ",
           "dataset build, or set REPAIR <- \"drop_na\" to render a draft meanwhile.", call. = FALSE)
    }
    refuse_event_drop(missing, "drop_na")
    d <- d[!missing, , drop = FALSE]
    repaired[["drop_na"]] <- paste(.cp_n(sum(missing), "interval"), "missing a predictor dropped")
  }

  gaps <- sum(same(d) & d[[start]] > prev_stop(d))
  per <- as.integer(table(d[[id]]))
  counts <- data.frame(
    measure = c("Patients", "Intervals", "Events", "Intervals per patient, median (range)", "Gaps between intervals",
                "Follow-up, from earliest start to latest stop"),
    value = c(length(per), nrow(d), sum(d[[event]] == 1),
              sprintf("%g (%d to %d)", stats::median(per), min(per), max(per)), gaps,
              paste(signif(min(d[[start]]), 4), "to", signif(max(d[[stop]]), 4))),
    stringsAsFactors = FALSE
  )
  list(data = d, counts = counts, repaired = repaired)
}

# What a job says when it repaired its own rows. A repair belongs in the dataset
# build, so that every job in the study reads the same rows: a draft may carry
# one, marked as a draft, and a final render refuses it, as it refuses an open
# EDIT: marker.
.cp_repair_notice <- function(repaired) {
  if (!length(repaired)) return("")
  msg <- paste0("The counting-process rows were repaired in this job, not in the dataset: ",
                paste(repaired, collapse = "; "), ". Fix them in the dataset build, then set REPAIR <- character().")
  if (.strict_render()) {
    stop(msg, "\nThis render stops because HVTI_TEMPLATE_STRICT is '", Sys.getenv("HVTI_TEMPLATE_STRICT"),
         "': a final report rests on the dataset's own rows. Unset it, or set it to 0, false or no, to render a ",
         "draft instead.", call. = FALSE)
  }
  .run_mark_draft(paste0("rows repaired in the job: ", paste(repaired, collapse = "; ")))
  paste0("\n::: {.callout-important title=\"DRAFT -- rows repaired in the job\"}\n", msg, "\n:::\n\n")
}
```

- [ ] **Step 4: Run the tests.**

Run: `Rscript -e 'devtools::test(filter = "counting-process")'`
Expected: PASS. If `local_mocked_bindings` cannot mock `.run_mark_draft` (an internal called from the same namespace), mock it the way `test-run-info.R` does; read that file before changing the test.

- [ ] **Step 5: Mutation checks.** One at a time, revert each check and rerun the filter; each must turn its own test red: (a) make `overlap` always `FALSE`; (b) remove `refuse_event_drop(short, "clip")`; (c) make `early` always `FALSE`; (d) make `missing` always `FALSE`; (e) remove the `.strict_render()` stop. Restore after each.

- [ ] **Step 6: Lint and commit.**

```bash
Rscript -e 'lintr::lint_package()'
git add R/counting-process.R tests/testthat/test-counting-process.R
git commit -m "Check counting-process rows, with draft-only repairs"
```

---

### Task 4: `rhf-fit.qmd`, its catalog row and the repo-wide tests it moves

**Files:**
- Create: `inst/templates/30_analyses/rhf-fit.qmd`
- Modify: `.lintr` (add a file key after the `rfs-explain.qmd` key, about line 215)
- Modify: `inst/extdata/templates.json` (insert after the `rfs` explain row)
- Modify: `DESCRIPTION` (`Suggests`: `randomForestRHF (>= 2.1.0)`, alphabetical, after `randomForestSRC`)
- Modify: `tests/testthat/helper-rf.R` (`rf_pkg_floors` gains `randomForestRHF = "2.1.0"`)
- Modify: `tests/testthat/helper-seed-hygiene.R` (`seed_random_calls` gains `"rhf"`, `"tune.treesize.rhf"`, `"varpro.cache.rhf"`, `"importance.rhf"`; `seed_negative_calls` gains `"rhf"`)
- Modify: `tests/testthat/test-template-data-routes.R:267-270` (readers 28 → 29; long list adds `"rhf-fit"`)
- Modify: `tests/testthat/test-job-data.R:1082` (`"... dc-trends, nb-boostmtree or rhf-fit."`)

**Interfaces:**
- Consumes: Task 2 `read_job_data(whole_patients = TRUE)`; Task 3 `.cp_check()`, `.cp_repair_notice()`; Task 1 taxonomy row (installed).
- Produces: `set_path("estimates", "rhf.rds")` holds an `rhf` object with `attr(, "hvti_provenance")$analysis` = `list(start = list(variable = START), stop = list(variable = STOP), event = list(variable = EVENT, event = 1L, censored = 0L), repair = <named character>)`. Cache names `rhf-treesize`, `rhf-forest`. Chunk labels `setup`, `edit-study-choices`, `tbl-data`, `tbl-cohort`, `repair`, `fit`, `fig-tuning`, `save`, `provenance`. Figure `rhf-fit-tuning`.

- [ ] **Step 1: Write the template.** `inst/templates/30_analyses/rhf-fit.qmd`, in full:

````markdown
---
title: "Random hazard forest: fit"
date: now
date-format: "YYYY-MM-DD HH:mm"
# Carried in the file rather than inherited from _quarto.yml. A file meant to be
# COPIED should not depend on settings from the directory it happens to sit in:
# rendered as a standalone document the project's format block never applies,
# which is how server-rendered reports end up with sibling _files/ trees instead
# of being self-contained.
#
# NOTE: output-dir is a PROJECT setting and cannot be set here, so the .html
# lands next to its source. With embed-resources that is a single standalone
# file, which is the property that actually matters when a report is sent on.
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
    toc-depth: 3
    code-fold: true
    df-print: default
    embed-resources: true
---

<!-- EDIT: say which outcome this forest models, which time-varying predictors
     it uses, and what question it answers. Replace this comment with that
     text. -->

An `rhf-fit` job grows a random hazard forest on counting-process data: one row
for each interval of a patient's follow-up, with its start, stop and event, so a
predictor such as a laboratory value or a device may change over time. It checks
those rows, chooses the tree size, and saves the forest. **Discrimination,
hazard curves and importance are not here.** They are the `rhf-explain` job in
this same set, which reads the forest this job saves instead of growing its own.

A random hazard forest models one event. A competing event, such as transplant
when the event is death on the waiting list, is coded 0 and censors, so the
forest estimates the cause-specific hazard of the event alone.

<!-- The two values below are written by add_job() from the subject/type it
     was called with, which are also the filename's first two fields. They
     name the SET this job belongs to, and every artifact path in the
     document is computed from them, so no output path below needs editing.

     Do NOT hand-edit these declarations: the render-time guard below checks
     them against this file's own name and stops if they disagree. To put
     this job in a different set, call add_job() again with the new
     subject/type rather than editing this copy in place. -->

```{r}
#| label: setup
#| results: asis
SUBJECT <- "dead"
TYPE    <- "rhf"
.in <- knitr::current_input(dir = TRUE)
suppressPackageStartupMessages({
  library(randomForestRHF)
  library(ggRandomForests)
  library(hvtiRutilities)
})
# One thread, so a forest reproduces from machine to machine. Left unset,
# randomForestRHF runs on every core its OpenMP build can see. Raise it for
# speed on a large forest, at the cost of that guarantee: a cached fit records
# its seed, data and package versions, never the threads it ran on.
options(rf.cores = 1L)
# The versions this template was verified against, end to end, on 2026-10-26.
# Below them a call here can fail or change meaning, and the message would
# arrive mid-render rather than here.
if (utils::packageVersion("randomForestRHF") < "2.1.0") {
  stop("This job needs randomForestRHF >= 2.1.0; ", utils::packageVersion("randomForestRHF"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
if (utils::packageVersion("ggRandomForests") < "4.0.0") {
  stop("This job needs ggRandomForests >= 4.0.0; ", utils::packageVersion("ggRandomForests"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
if (utils::packageVersion("hvtiPlotR") < "2.8.18") {
  stop("This job needs hvtiPlotR >= 2.8.18 for the house theme; ", utils::packageVersion("hvtiPlotR"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
# The study root is the nearest directory above this file holding _study.yml,
# so the job renders the same from the Render button, quarto render, or
# render_job(), at any depth, with no path in this document to edit.
# Without the guard in .job_setup(), an unedited job renders green over a
# meaningless analysis: a forest grown on the template's placeholder columns.
# To render a job you have not finished, leave a chunk out with the chunk
# option skip, giving the reason in quotes, or call hvtiRtemplates::stop_here()
# in a chunk to leave out everything below it. ?stop_here has more.
.job <- hvtiRtemplates:::.job_setup(SUBJECT, TYPE, envir = environment())
.root <- .job$root
set_path <- .job$set_path
.provenance_data <- list()
# Saves a figure as <name>.png, .pdf and .tiff in this set's graphs/ folder (or `kind`'s),
# under the SAVE_FIGURES and FIGURES study choices.
save_figure <- function(plot, name, width = 6, height = 4, kind = "graphs", linked = FALSE) {
  hvtiRtemplates:::.save_figure(plot, set_path(kind, paste0(name, ".png")), width, height,
                                SAVE_FIGURES, FIGURES, linked)
}
# `rhf-fit` writes the forest through set_path() and `rhf-explain` reads it
# back, both by set. The write is the `save` chunk at the foot of this file.
# The draft banners, if any, and the box under the title, after all the code above.
.job$notice
```

## Study choices

Edit these values for this study before rendering.

```{r}
#| label: edit-study-choices
# EDIT: the registered dataset this job reads ("built" is the study dataset).
# It can be the counting-process rows themselves, or the one-row cohort with
# the rows named in JOIN below.
DATASET <- "built"

# EDIT: an hvtiRdatabuild analysis set, or NULL to read the whole dataset.
ANALYSIS_SET <- NULL

# EDIT: rows to keep, dplyr::filter() style, or NULL to keep every row. A
# condition must keep or drop a patient whole, so name a column whose value is
# the same on every row of a patient, such as age at listing. A condition on a
# time-varying column would cut follow-up short, and stops the render.
WHERE <- NULL

# EDIT: the patient identifier. Without "ccfid" the job uses MRN, then eMRN.
ID <- "ccfid"

# EDIT: what makes a row unique: the patient and the start of the interval.
KEY <- c(ID, "iv_start")

# Optional, and needs no edit: NULL reads DATASET alone. When DATASET is the
# one-row cohort, name the registered counting-process dataset here and leave
# REDUCE NULL, so each joined record is one interval of a patient's follow-up.
# The cohort decides the patients; the joined records of other patients are
# dropped and counted in the data table.
#   JOIN_VARS: the cohort columns each joined row carries; NULL carries all,
#     and a column both datasets have stops, so list only those the job needs,
#     such as the baseline predictors.
#   REDUCE: keeps one record per patient, which this job does not want.
#   JOIN_KEY: overrides the joined dataset's registered key.
JOIN <- NULL
JOIN_VARS <- NULL
REDUCE <- NULL
JOIN_KEY <- NULL

# EDIT: each interval's start and stop, and its event, coded 1 when the event
# ends that interval and 0 otherwise. Only a patient's last interval can carry
# an event. Code a competing event 0: it censors.
START <- "iv_start"
STOP  <- "iv_stop"
EVENT <- "dead"

# EDIT: the candidate predictors, baseline and time-varying alike. Name them
# rather than taking every column: a dataset carries identifiers, dates and
# derived outcomes, and a forest will split on a date that encodes follow-up.
PREDICTORS <- c("age", "female", "bun_tc")

# EDIT: forest size and seed. SEED makes the forest reproducible and is part of
# its cache key. It is used twice, on purpose: cache_fit() seeds R's generator
# with it, and rhf() is handed it as `seed =`, negated as randomForestRHF
# documents.
NTREE <- 500
SEED  <- 2026

# EDIT: the number of terminal nodes in each tree. NULL chooses it by
# out-of-bag risk with tune.treesize.rhf(), and the figure below shows the
# search. Tree size is the setting a hazard forest is most sensitive to, which
# is why this template tunes it where the rfs templates tune nothing; a number
# skips the search, which is slow on a large study.
TREESIZE <- NULL

# Needs no edit unless the dataset has a defect. Repairs this job makes to the
# counting-process rows while the dataset fix is in flight; each one marks the
# report a draft, and a final render refuses it, because the rows a final
# result rests on come from the dataset, so every job in the study agrees.
#   "clip"    clips an interval that starts before the one before it ends back
#             to that end, and drops an interval left empty
#   "drop_na" drops intervals missing a predictor
REPAIR <- character()

# Set TRUE after changing a choice above. A cache whose inputs changed stops the
# render instead of returning the old forest; TRUE recomputes only the caches
# that are out of date, so it is safe to leave on while iterating.
REFIT <- FALSE

# Each figure is saved to graphs/ as a PNG (for Word), and a PDF and a TIFF (for the publisher).
# SAVE_FIGURES <- FALSE saves none; FIGURES keeps only the figures whose names
# start with one of its entries, e.g. FIGURES <- c("rhf-fit-tuning"). The names
# are the file names, listed for each template in the templates README.
SAVE_FIGURES <- TRUE
FIGURES <- NULL
```

## Cohort

```{r}
#| label: tbl-data
#| tbl-cap: "The data this job read"
# The checksum of every dataset in manifest.yaml is checked before anything is
# read, so a result can name the data that produced it. It stops on a mismatch.
hvtiRutilities::verify_manifest(file.path(.root, "manifest.yaml"))
.cfg <- study_config(start = .root)
job_data <- hvtiRtemplates::read_job_data(.cfg, dataset = DATASET, analysis_set = ANALYSIS_SET,
                                          where = WHERE, id = ID, key = KEY, join = JOIN, join_vars = JOIN_VARS,
                                          reduce = REDUCE, join_key = JOIN_KEY, whole_patients = TRUE)
d <- job_data$data
.provenance_data <- c(if (exists(".provenance_data")) .provenance_data else list(), list(job_data$provenance),
                      if (!is.null(job_data$provenance_join)) list(job_data$provenance_join))
knitr::kable(job_data$record, col.names = c("Data", ""))
.selection <- attr(job_data$record, "selection")
.outcomes <- intersect(c(START, STOP, EVENT), PREDICTORS)
if (length(.outcomes)) {
  stop("Do not include the interval or event columns in PREDICTORS: ", paste(.outcomes, collapse = ", "), ".",
       call. = FALSE)
}
.duplicated <- unique(PREDICTORS[duplicated(PREDICTORS)])
if (length(.duplicated)) {
  stop("PREDICTORS names a variable more than once: ", paste(.duplicated, collapse = ", "), ".", call. = FALSE)
}
# A forest must not be trained on an identifier. It would split on who a
# patient is, and the saved forest keeps its training columns.
.identifiers <- PREDICTORS[tolower(PREDICTORS) %in% tolower(c(.selection$id, .selection$key))]
if (length(.identifiers)) {
  stop("Do not include the patient identifier or a KEY column in PREDICTORS: ",
       paste(.identifiers, collapse = ", "), ".", call. = FALSE)
}
# The forest is grown on columns named id, start, stop and event, so a
# predictor may not take one of those names.
.reserved <- intersect(tolower(PREDICTORS), c("id", "start", "stop", "event"))
if (length(.reserved)) {
  stop("PREDICTORS may not name a column id, start, stop or event: ", paste(.reserved, collapse = ", "),
       ". Rename it in the dataset build.", call. = FALSE)
}
.missing <- setdiff(c(START, STOP, EVENT, PREDICTORS), names(d))
if (length(.missing)) {
  stop("Not in the data this job read: ", paste(.missing, collapse = ", "), call. = FALSE)
}
# A forest splits a text column only as a factor, so text predictors are
# converted here, and named, rather than left for the fit to refuse or coerce.
.chr <- PREDICTORS[vapply(d[PREDICTORS], is.character, logical(1L))]
if (length(.chr)) {
  d[.chr] <- lapply(d[.chr], factor)
  cat("Text predictors converted to factors: ", paste(.chr, collapse = ", "), "\n", sep = "")
}
```

```{r}
#| label: tbl-cohort
#| tbl-cap: "The counting-process rows the forest is grown on"
# randomForestRHF refuses overlapping intervals only after the data are loaded,
# and names no patient. These checks run first and say what to fix: an overlap,
# an interval of zero length, an event before a patient's last interval, an
# event not coded 0/1, or a missing predictor stops the render here. Gaps
# between intervals are allowed, and counted.
.cp <- hvtiRtemplates:::.cp_check(d, id = .selection$id, start = START, stop = STOP, event = EVENT,
                                  predictors = PREDICTORS, repair = REPAIR)
d <- .cp$data
knitr::kable(.cp$counts, col.names = c("Rows", ""))
```

```{r}
#| label: repair
#| results: asis
# A repair is a draft's: this says so where the reader looks, and a final render
# stops here instead.
cat(hvtiRtemplates:::.cp_repair_notice(.cp$repaired))
```

## Forest

```{r}
#| label: fit
#| message: true
# cache_fit() writes <dir>/<name>.rds and its default dir is the study's
# estimates folder, not this set's, so every call here names the set's.
CACHE_DIR <- dirname(set_path("estimates", "rhf.rds"))
# rhf() needs each row's patient, and a saved forest keeps its data, so the
# study's identifiers would be written into rhf.rds. Each patient is numbered
# 1 to n instead, in the order of the rows: the forest can still tell one
# patient's intervals from another's, and no number can be read back to a
# patient.
.fit_data <- data.frame(id = match(d[[.selection$id]], unique(d[[.selection$id]])),
                        start = d[[START]], stop = d[[STOP]], event = d[[EVENT]], d[PREDICTORS])
model <- survival::Surv(id, start, stop, event) ~ .
# The saved forest keeps this formula, and a formula keeps the environment it
# was made in; set it, so a job run anywhere else does not write every object
# beside the formula, `job_data` and its patient IDs included, into the forest.
environment(model) <- globalenv()
# Hours at study size. Started from the console it dies with the session, so an
# uncached fit is refused there: run the job with hvtiRtemplates::submit_job().
hvtiRtemplates::guard_long_fit("rhf-forest", dir = CACHE_DIR,
                               why = "a hazard forest on every interval of follow-up takes hours at study size",
                               refit = REFIT)
if (is.null(TREESIZE)) {
  hvtiRtemplates::guard_long_fit("rhf-treesize", dir = CACHE_DIR,
                                 why = "the tree-size search grows a forest at each size it tries",
                                 refit = REFIT)
  tuned <- cache_fit(
    "rhf-treesize",
    tune.treesize.rhf(model, .fit_data, ntree = NTREE, perf = "risk", seed = abs(SEED), verbose = FALSE,
                      forest = FALSE),
    seed = SEED, dir = CACHE_DIR, refit = REFIT
  )
  .treesize <- tuned$best.size
} else {
  tuned <- NULL
  .treesize <- TREESIZE
}
forest <- cache_fit(
  "rhf-forest",
  rhf(model, data = .fit_data, ntree = NTREE, treesize = .treesize, seed = -abs(SEED)),
  seed = SEED, dir = CACHE_DIR, refit = REFIT
)
forest
```

`forest = FALSE` in the search is deliberate. The search would otherwise return a
forest at the size it chose, and the cache would hold a second copy of the
forest the next call grows. Growing it once, under its own cache, means a
changed `NTREE` regrows the forest without repeating the search.

## Does the forest work?

```{r}
#| label: fig-tuning
#| fig-cap: "Out-of-bag risk at each tree size the search tried. The lowest point is the size the forest was grown at;
#|   a curve still falling at its right edge says the search stopped short."
# Drawn only when this job searched. A TREESIZE given as a number has nothing to show.
if (!is.null(tuned)) {
  .fig <- plot(gg_tune_rhf(tuned)) + hvtiPlotR::theme_hv_manuscript(base_size = 12)
  save_figure(.fig, "rhf-fit-tuning")
  .fig
}
```

```{r}
#| label: save
# The product of this job, and what rhf-explain reads. It is separate from the
# cache on purpose: cache_fit() stores a keyed record rather than the bare
# forest, so the cache is this job's internals and this file is its interface.
.forest_cohort <- list(
  n = length(unique(.fit_data$id)),
  n_events = as.integer(sum(.fit_data$event == 1)),
  n_censored = length(unique(.fit_data$id)) - as.integer(sum(.fit_data$event == 1))
)
.forest_analysis <- list(
  start = list(variable = START),
  stop = list(variable = STOP),
  event = list(variable = EVENT, event = 1L, censored = 0L),
  # rhf-explain reads this: a forest grown on rows this job repaired makes its
  # report a draft too.
  repair = as.list(.cp$repaired)
)
forest <- hvtiRtemplates:::.attach_handoff_lineage(
  forest,
  data = .provenance_data,
  analysis = .forest_analysis,
  cohort = .forest_cohort,
  # rhf-explain takes the rows, ID and KEY of this fit from this record.
  selection = .selection
)
saveRDS(forest, set_path("estimates", "rhf.rds"))
```

```{r}
#| label: provenance
#| echo: false
#| results: asis
cat(hvtiRtemplates:::.embed_provenance(
  .in,
  data = .provenance_data,
  run = .job$run,
  extra = list(
    subject = SUBJECT,
    type = TYPE,
    analysis = .forest_analysis,
    cohort = .forest_cohort
  )
))
```
````

- [ ] **Step 2: Check the call shapes against the installed packages.** Before running anything, read each help page this template calls and correct the template, not the plan, if one disagrees (AGENTS.md "Looking up a dependency's API"):

```bash
Rscript -e 'for (f in c("rhf", "tune.treesize.rhf")) print(args(getExportedValue("randomForestRHF", f)))'
Rscript -e 'print(args(ggRandomForests:::gg_tune_rhf.tune.treesize.rhf)); print(args(hvtiRtemplates::guard_long_fit))'
```

Expected: `rhf()` takes `seed`, `treesize`, `ntree`; `tune.treesize.rhf()` takes `seed`, `perf`, `forest`, `verbose` and returns `best.size`.

- [ ] **Step 3: Add the lint key.** In `.lintr`, after the `rfs-explain.qmd` key, copy that key's exclusion list verbatim under the new file key `"inst/templates/30_analyses/rhf-fit.qmd"`. A file key, never `inst/templates`.

- [ ] **Step 4: Add the catalog row.** In `inst/extdata/templates.json`, after the `rfs` explain row:

```json
    {
      "prefix": "rhf",
      "qualifier": "fit",
      "name": "Random hazard forest: fit",
      "description": "Grows a random hazard forest on counting-process rows with time-varying predictors: checks the rows, tunes the tree size and saves the forest.",
      "folder": "analyses",
      "family": "machine-learning",
      "kind": "job",
      "status": "in-flight",
      "batch": null,
      "sas_breadth": null,
      "r_exemplars": 1,
      "r_jobs": null,
      "upstream": [],
      "downstream": [],
      "workflows": [],
      "blocked_on": null,
      "spec": "dev/specs/2026-10-26-rhf-templates-design.md",
      "note": "Saves rhf.rds for rhf-explain in the same set. In flight on one study; a second study's job promotes it.",
      "sas_breadth_jobs": null,
      "disposition": "scaffold",
      "uses": [
        "randomForestRHF::rhf",
        "randomForestRHF::tune.treesize.rhf",
        "hvtiRutilities::cache_fit",
        "hvtiRtemplates::guard_long_fit",
        "ggRandomForests::gg_tune_rhf"
      ]
    },
```

Read the neighboring `in-flight` rows (`vt`, `sid`) first and match their use of `r_exemplars`, `sas_breadth` and `batch`; if they differ from the above, follow them.

- [ ] **Step 5: `DESCRIPTION`, helpers and the repo-wide expectations.**
  - `DESCRIPTION` `Suggests`: add `randomForestRHF (>= 2.1.0),` after `randomForestSRC (>= 3.7.0),`.
  - `helper-rf.R` `rf_pkg_floors`: add `randomForestRHF  = "2.1.0",`.
  - `helper-seed-hygiene.R`: add `"rhf", "tune.treesize.rhf", "varpro.cache.rhf", "importance.rhf"` to `seed_random_calls` and `"rhf"` to `seed_negative_calls`. Update the comment above `seed_negative_calls` to say randomForestRHF 2.1.0's `rhf()` has a `seed` and `tune.treesize.rhf()` takes a positive one for `set.seed()`.
  - `test-template-data-routes.R`: `expect_identical(readers, 29L)` and the long list `c("dc-eda", "dc-general", "dc-tables", "dc-trends", "nb-boostmtree", "rhf-fit")`.
  - `test-job-data.R:1082`: `"such as dc-eda, dc-general, dc-tables, dc-trends, nb-boostmtree or rhf-fit."`.

- [ ] **Step 6: Run the repo-wide suites the template enters.**

```bash
R CMD INSTALL -l "$LIB" . && R_LIBS="$LIB" NOT_CRAN=true _R_CHECK_LIMIT_CORES_=TRUE \
  Rscript -e 'devtools::test(filter = "template-data-routes|job-data|seed-hygiene|add-job|taxonomy|catalog|roadmap|lint")'
python3 dev/specs/artifacts/check-roadmap-counts.py
```

Expected: PASS, and the roadmap check passes in both directions. A failure in `test-seed-hygiene.R` names the line: seed it as the test asks (a `set.seed()` within three lines, or a `cache_fit(seed =)`) rather than adding an allowance. A failure in `test-add-job.R`'s study-identifier scan means a comment names a study; reword it.

- [ ] **Step 7: Commit.**

```bash
git add inst/templates/30_analyses/rhf-fit.qmd .lintr inst/extdata/templates.json DESCRIPTION \
  tests/testthat/helper-rf.R tests/testthat/helper-seed-hygiene.R \
  tests/testthat/test-template-data-routes.R tests/testthat/test-job-data.R
git commit -m "Add the rhf-fit template"
```

---

### Task 5: `rhf-fit` tests

**Files:**
- Create: `tests/testthat/helper-rhf.R`
- Create: `tests/testthat/test-rhf-templates.R`

**Interfaces:**
- Consumes: `rf_run()`, `rf_env()`, `rf_skip_unless_stack()`, `rf_template_packages()`, `rf_rds_bytes()`, `rf_bytes_hold()` from `helper-rf.R`; Task 4's chunk labels.
- Produces: `rhf_data()`, `rhf_choices`, `rhf_fit_first()` for Task 6.

- [ ] **Step 1: Write the helper.** `tests/testthat/helper-rhf.R`:

```r
# Counting-process data for rhf, simulated by randomForestRHF itself: one row
# per interval, with `id`, `start`, `stop`, `event`, a time-varying `xtd` and
# baseline `x.1` to `x.p`. The id becomes ccfid, as a built dataset names it,
# and is offset so the saved-forest scan below can tell a study id from the
# job-local numbers the forest is grown on. read_built() lowercases names.
rhf_data <- function(n = 60L) {
  withr::local_seed(20261026)
  sim <- randomForestRHF::hazard.simulation(type = 1, n = n, p = 3, nrecords = 4)
  d <- if (is.data.frame(sim)) sim else sim$dta
  names(d)[names(d) == "id"] <- "ccfid"
  d$ccfid <- 7350000000 + d$ccfid
  names(d) <- gsub(".", "_", names(d), fixed = TRUE)
  d
}

rhf_choices <- list(KEY = c("ccfid", "start"), START = "start", STOP = "stop", EVENT = "event",
                    PREDICTORS = c("xtd", "x_1", "x_2", "x_3"), NTREE = 20, SEED = 1, TREESIZE = NULL)

rhf_fit_labels <- c("setup", "edit-study-choices", "tbl-data", "tbl-cohort", "repair", "fit", "fig-tuning", "save")

# A fit in a throwaway study; returns its chunk environment.
rhf_fit_first <- function(data = rhf_data(), choices = rhf_choices, .local_envir = parent.frame()) {
  env <- rf_env(data, .local_envir)  # nolint: object_usage_linter.
  rf_run("rhf", "fit", rhf_fit_labels, env, choices)  # nolint: object_usage_linter.
  env
}
```

- [ ] **Step 2: Write the tests.** `tests/testthat/test-rhf-templates.R`:

```r
test_that("rhf-fit tunes, grows a hazard forest and saves the handoff", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("rhf", "fit"))
  env <- rhf_fit_first()
  expect_s3_class(env$forest, "rhf")
  expect_s3_class(env$tuned, "tune.treesize.rhf")
  for (nm in c("rhf.rds", "rhf-forest.rds", "rhf-treesize.rds")) {
    expect_true(file.exists(file.path(env$CACHE_DIR, nm)), info = nm)
  }
  saved <- readRDS(file.path(env$CACHE_DIR, "rhf.rds"))
  expect_s3_class(saved, "rhf")
  lineage <- attr(saved, "hvti_provenance")
  expect_identical(lineage$analysis$event$variable, "event")
  expect_length(lineage$analysis$repair, 0L)
  expect_s3_class(ggplot2::ggplot_build(plot(ggRandomForests::gg_tune_rhf(env$tuned))), "ggplot_built")
})

test_that("rhf-fit skips the search when TREESIZE is a number", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("rhf", "fit"))
  env <- rhf_fit_first(choices = utils::modifyList(rhf_choices, list(TREESIZE = 5L)))
  expect_null(env$tuned)
  expect_false(file.exists(file.path(env$CACHE_DIR, "rhf-treesize.rds")))
})

test_that("a saved rhf forest holds no study id", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("rhf", "fit"))
  d <- rhf_data()
  env <- rhf_fit_first(d)
  bytes <- rf_rds_bytes(file.path(env$CACHE_DIR, "rhf.rds"))
  for (id in unique(d$ccfid)) expect_false(rf_bytes_hold(bytes, id), info = format(id, scientific = FALSE))
})

test_that("rhf-fit stops on an overlap, and REPAIR clips it in a draft only", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("rhf", "fit"))
  d <- rhf_data()
  first <- which(d$ccfid == d$ccfid[[1L]])
  d$start[first[2L]] <- d$start[first[2L]] - 1e-3
  env <- rf_env(d)
  expect_error(rf_run("rhf", "fit", c("setup", "edit-study-choices", "tbl-data", "tbl-cohort"), env, rhf_choices),
               "1 overlapping interval")
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "")
  env <- rf_env(d)
  out <- utils::capture.output(rf_run("rhf", "fit", c("setup", "edit-study-choices", "tbl-data", "tbl-cohort", "repair"),
                                      env, utils::modifyList(rhf_choices, list(REPAIR = "clip"))))
  expect_true(any(grepl("DRAFT -- rows repaired in the job", out, fixed = TRUE)))
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "1")
  env <- rf_env(d)
  expect_error(rf_run("rhf", "fit", c("setup", "edit-study-choices", "tbl-data", "tbl-cohort", "repair"),
                      env, utils::modifyList(rhf_choices, list(REPAIR = "clip"))),
               "HVTI_TEMPLATE_STRICT")
})

test_that("rhf-fit refuses a WHERE on a time-varying column", {
  rf_skip_unless_stack(rf_template_packages("rhf", "fit"))
  env <- rf_env(rhf_data())
  expect_error(rf_run("rhf", "fit", c("setup", "edit-study-choices", "tbl-data"), env,
                      utils::modifyList(rhf_choices, list(WHERE = quote(start > 0)))),
               "lost some of their rows")
})

test_that("rhf-fit refuses a predictor named like the forest's own columns", {
  rf_skip_unless_stack(rf_template_packages("rhf", "fit"))
  d <- rhf_data()
  d$id <- 1
  env <- rf_env(d)
  expect_error(rf_run("rhf", "fit", c("setup", "edit-study-choices", "tbl-data"), env,
                      utils::modifyList(rhf_choices, list(PREDICTORS = c("xtd", "id")))),
               "may not name a column id, start, stop or event")
})
```

The overlap test moves one start back by 0.001: the setup chunk's `.job_setup()` guard needs the job's `EDIT:` markers resolved, which `rf_run()` handles the way the `rfs` tests do. If `rf_run()` reports the draft through a warning instead of the printed callout, read `helper-setup.R`'s `eval_setup_chunk()` and assert on what it actually surfaces.

- [ ] **Step 3: Run them.**

```bash
R CMD INSTALL -l "$LIB" . && R_LIBS="$LIB" NOT_CRAN=true _R_CHECK_LIMIT_CORES_=TRUE \
  Rscript -e 'devtools::test(filter = "rhf-templates")'
```

Expected: PASS, `SKIP 0`, `WARN 0`. Before trusting the green: if `hazard.simulation()` ever puts an event on a non-final interval, the first test fails in `tbl-cohort` with "an event before their last interval"; that is a fixture problem, so keep only each patient's rows up to and including the first event in `rhf_data()`, and say so in a comment.

- [ ] **Step 4: Mutation checks.** (a) Remove `whole_patients = TRUE` from the template's `read_job_data()` call and confirm the WHERE test fails. (b) Replace the `match(...)` id recoding with `d[[.selection$id]]` and confirm the saved-forest scan fails. Restore both.

- [ ] **Step 5: Commit.**

```bash
git add tests/testthat/helper-rhf.R tests/testthat/test-rhf-templates.R
git commit -m "Test the rhf-fit template end to end"
```

---

### Task 6: `rhf-explain.qmd`, its catalog row and tests

**Files:**
- Create: `inst/templates/30_analyses/rhf-explain.qmd`
- Modify: `.lintr` (file key after `rhf-fit.qmd`'s)
- Modify: `inst/extdata/templates.json` (after the `rhf` fit row)
- Modify: `tests/testthat/test-rhf-templates.R` (append)

**Interfaces:**
- Consumes: `rhf.rds` and its lineage from Task 4; `rhf_fit_first()`, `rhf_choices` from Task 5.
- Produces: caches `rhf-auc-cumulative`, `rhf-auc-incident`, `rhf-varpro-cache` (**stable name**: the later VarPro-RHF template reads it), `rhf-importance`. Figures `rhf-explain-auc-cumulative`, `rhf-explain-auc-incident`, `rhf-explain-hazard`, `rhf-explain-chf`, `rhf-explain-importance`.

- [ ] **Step 1: Write the template.** `inst/templates/30_analyses/rhf-explain.qmd`, in full. The `format:` block and the set-declaration comment are copied verbatim from `rhf-fit.qmd` (Task 4, Step 1); everything else:

````markdown
---
title: "Random hazard forest: explain"
date: now
date-format: "YYYY-MM-DD HH:mm"
# (the format comment and block exactly as in rhf-fit.qmd)
---

<!-- EDIT: say which rhf-fit job in this set this explains, and what question
     the importance and hazard curves are meant to answer. -->

Explains the forest the `rhf-fit` job in this set saved.

An `rhf-explain` job never grows a forest. It reads `rhf.rds`, which the fit job
writes, and reports how well the forest separates patients who have the event
from those still at risk, over follow-up; the hazard it predicts for a sample of
patients; and how much each predictor matters, at several points of follow-up.
Each expensive step is cached on its own. The importance step builds a VarPro
cache, `rhf-varpro-cache`, which later VarPro work on this forest reads instead
of building again.

<!-- (the set-declaration comment exactly as in rhf-fit.qmd) -->

```{r}
#| label: setup
#| results: asis
SUBJECT <- "dead"
TYPE    <- "rhf"
.in <- knitr::current_input(dir = TRUE)
suppressPackageStartupMessages({
  library(randomForestRHF)
  library(ggRandomForests)
  library(hvtiRutilities)
})
options(rf.cores = 1L)
if (utils::packageVersion("randomForestRHF") < "2.1.0") {
  stop("This job needs randomForestRHF >= 2.1.0; ", utils::packageVersion("randomForestRHF"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
if (utils::packageVersion("ggRandomForests") < "4.0.0") {
  stop("This job needs ggRandomForests >= 4.0.0; ", utils::packageVersion("ggRandomForests"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
if (utils::packageVersion("hvtiPlotR") < "2.8.18") {
  stop("This job needs hvtiPlotR >= 2.8.18 for the house theme; ", utils::packageVersion("hvtiPlotR"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
.job <- hvtiRtemplates:::.job_setup(SUBJECT, TYPE, envir = environment())
.root <- .job$root
set_path <- .job$set_path
.provenance_data <- list()
save_figure <- function(plot, name, width = 6, height = 4, kind = "graphs", linked = FALSE) {
  hvtiRtemplates:::.save_figure(plot, set_path(kind, paste0(name, ".png")), width, height,
                                SAVE_FIGURES, FIGURES, linked)
}
.job$notice
```

## Study choices

Edit these values for this study before rendering. The outcome and predictors
are not here: they come from the forest.

```{r}
#| label: edit-study-choices
# EDIT: the fit's selection is used; set any of these only to confirm it.
# NULL takes the value the fit job used.
WHERE <- NULL
ID <- NULL
KEY <- NULL

# EDIT: the horizon for AUC(t), in the units of the fit job's interval columns.
# NULL takes randomForestRHF's default, the range of follow-up.
TAU <- NULL

# EDIT: how many patients get hazard curves, drawn at random. The forest's
# patients are numbered 1 to n by the fit job, so a curve cannot be asked for by
# study identifier, and the plots carry no legend that could print one.
N_CURVES <- 20

# EDIT: the VarPro cache behind importance, at randomForestRHF's defaults. It is
# the slow step at full scale: a first study needed 30 rules and 20 trees to
# finish on 400 patients. Smaller values are faster and coarser.
MAX_RULES_TREE <- 150
MAX_TREE <- 150

# EDIT: importance at this many evenly spaced points of follow-up. A hazard
# forest's importance changes with time, so one number per predictor would hide
# when it matters.
N_TIMES <- 5

# EDIT: seed for the sample of curves and the VarPro cache. It is part of every
# cache key.
SEED <- 2026

# Set TRUE after changing a choice above. A cache whose inputs changed stops the
# render instead of returning the old result; TRUE recomputes only the caches
# that are out of date.
REFIT <- FALSE

# Each figure is saved to graphs/ as a PNG (for Word), and a PDF and a TIFF (for the publisher).
# SAVE_FIGURES <- FALSE saves none; FIGURES keeps only the figures whose names
# start with one of its entries, e.g. FIGURES <- c("rhf-explain-importance").
SAVE_FIGURES <- TRUE
FIGURES <- NULL
```

## The forest

```{r}
#| label: forest
#| results: asis
.handoff <- set_path("estimates", "rhf.rds")
if (!file.exists(.handoff)) {
  stop("No forest at ", .handoff, ". Render the rhf-fit job in this set first; ",
       "this job explains that forest and never grows its own.", call. = FALSE)
}
.cfg <- study_config(start = .root)
.forest_read <- hvtiRtemplates:::.read_handoff(.handoff, "forest", .cfg, "the rhf-fit job")
forest <- .forest_read$value
.provenance_data <- .forest_read$lineage$data
.provenance_artifacts <- c(.forest_read$lineage$artifacts, list(.forest_read$record))
if (!inherits(forest, "rhf")) {
  stop("rhf.rds does not hold a random hazard forest.", call. = FALSE)
}
CACHE_DIR <- dirname(.handoff)
# A forest grown on rows the fit job repaired is a draft's, and so is every
# explanation of it: a final render stops here.
cat(hvtiRtemplates:::.cp_repair_notice(unlist(.forest_read$lineage$analysis$repair)))
```

```{r}
#| label: tbl-data
#| tbl-cap: "The data the fit job read"
# This job reads no data: the forest carries its training rows. A setting above
# that differs from the fit's stops here.
.sel <- hvtiRtemplates:::.read_upstream_job_data(
  .cfg, .forest_read$lineage, list(where = WHERE, id = ID, key = KEY), read = FALSE, source = "rhf.rds"
)$selection
knitr::kable(data.frame(step = c("ID", "KEY", "WHERE", "Rows"),
                        value = c(.sel$id, paste(.sel$key, collapse = ", "),
                                  if (length(.sel$where_shown)) paste(.sel$where_shown, collapse = "; ") else "none",
                                  .sel$rows)),
             col.names = c("Data", ""))
```

## Discrimination over follow-up

```{r}
#| label: fig-auc-cumulative
#| fig-cap: "Cumulative AUC(t): how well the predicted cumulative hazard separates patients who have had the event by
#|   time t from those still at risk. 0.5 is chance."
#| message: true
auc_cum <- cache_fit("rhf-auc-cumulative",
                     auct.rhf(forest, marker = "cumhaz", method = "cumulative", tau = TAU, verbose = FALSE),
                     seed = SEED, dir = CACHE_DIR, refit = REFIT)
.fig <- plot(gg_auct(forest, auct_fit = auc_cum)) + hvtiPlotR::theme_hv_manuscript(base_size = 12)
save_figure(.fig, "rhf-explain-auc-cumulative")
.fig
```

```{r}
#| label: fig-auc-incident
#| fig-cap: "Incident AUC(t): how well the predicted hazard separates patients who have the event at time t from those
#|   still at risk then. 0.5 is chance."
#| message: true
auc_inc <- cache_fit("rhf-auc-incident",
                     auct.rhf(forest, marker = "hazard", method = "incident", riskset = "subject", tau = TAU,
                              verbose = FALSE),
                     seed = SEED, dir = CACHE_DIR, refit = REFIT)
.fig <- plot(gg_auct(forest, auct_fit = auc_inc)) + hvtiPlotR::theme_hv_manuscript(base_size = 12)
save_figure(.fig, "rhf-explain-auc-incident")
.fig
```

```{r}
#| label: tbl-auc
#| tbl-cap: "Integrated AUC over follow-up"
data.frame(measure = c("Cumulative", "Incident"),
           iAUC = round(c(auc_cum$iAUC.uno, auc_inc$iAUC.uno), 3))
```

## Hazard curves

```{r}
#| label: curves
# The forest's patients are numbered 1 to n, so the sample says nothing about who
# they are.
haz <- gg_rhf(forest, source = "oob")
set.seed(abs(SEED))
.curve_ids <- sort(sample(unique(haz$id), min(N_CURVES, length(unique(haz$id)))))
```

```{r}
#| label: fig-hazard
#| fig-cap: "Out-of-bag predicted hazard over follow-up for a random sample of patients, one line per patient."
.fig <- plot(haz, idx = .curve_ids, hazard.only = TRUE) +
  hvtiPlotR::theme_hv_manuscript(base_size = 12, legend.position = "none")
save_figure(.fig, "rhf-explain-hazard")
.fig
```

```{r}
#| label: fig-chf
#| fig-cap: "Out-of-bag predicted cumulative hazard over follow-up for the same patients, one line per patient."
.fig <- plot(haz, idx = .curve_ids, hazard.only = FALSE) +
  hvtiPlotR::theme_hv_manuscript(base_size = 12, legend.position = "none")
save_figure(.fig, "rhf-explain-chf")
.fig
```

## Importance

```{r}
#| label: fig-importance
#| fig-cap: "VarPro importance of each predictor at points across follow-up."
#| fig-height: 10.5
#| message: true
# The cache is the slow step, and its name is fixed on purpose: later VarPro
# work on this forest reads rhf-varpro-cache rather than building it again.
hvtiRtemplates::guard_long_fit("rhf-varpro-cache", dir = CACHE_DIR,
                               why = "the VarPro cache walks every rule of every tree at study size", refit = REFIT)
vp_cache <- cache_fit("rhf-varpro-cache",
                      varpro.cache.rhf(forest, max.rules.tree = MAX_RULES_TREE, max.tree = MAX_TREE, verbose = FALSE),
                      seed = SEED, dir = CACHE_DIR, refit = REFIT)
.time_index <- unique(as.integer(round(seq.int(1L, vp_cache$K, length.out = N_TIMES))))
imp <- cache_fit("rhf-importance",
                 importance.rhf(forest, cache = vp_cache, time.index = .time_index, verbose = FALSE),
                 seed = SEED, dir = CACHE_DIR, refit = REFIT)
.fig <- plot(gg_rhf_importance(forest, importance_fit = imp)) + hvtiPlotR::theme_hv_manuscript(base_size = 12)
save_figure(.fig, "rhf-explain-importance", height = 7)
.fig
```

```{r}
#| label: tbl-importance
#| tbl-cap: "VarPro importance of each predictor at each point of follow-up"
as.data.frame(imp)
```

```{r}
#| label: provenance
#| echo: false
#| results: asis
cat(hvtiRtemplates:::.embed_provenance(
  .in,
  data = .provenance_data,
  run = .job$run,
  artifacts = .provenance_artifacts,
  extra = list(
    subject = SUBJECT,
    type = TYPE,
    analysis = .forest_read$lineage$analysis,
    cohort = .forest_read$lineage$cohort
  )
))
```
````

In the file itself, replace the two `(... exactly as in rhf-fit.qmd)` lines with the verbatim text from `rhf-fit.qmd`; they are abbreviated here only to keep the plan readable.

- [ ] **Step 2: Check the call shapes** as in Task 4 Step 2:

```bash
Rscript -e 'for (f in c("auct.rhf", "varpro.cache.rhf", "importance.rhf")) print(args(getExportedValue("randomForestRHF", f)))'
Rscript -e 'for (f in c("gg_auct.rhf", "gg_rhf.rhf", "plot.gg_rhf", "gg_rhf_importance.rhf")) print(args(get(f, asNamespace("ggRandomForests"))))'
```

Expected: `auct.rhf()` returns `iAUC.uno`; `varpro.cache.rhf()`'s result has `K`; `plot.gg_rhf()` takes `idx` and `hazard.only`. Correct the template where they differ.

- [ ] **Step 3: Lint key and catalog row.** `.lintr`: a file key `"inst/templates/30_analyses/rhf-explain.qmd"` with the `rfs-explain.qmd` key's list. `templates.json`, after the `rhf` fit row:

```json
    {
      "prefix": "rhf",
      "qualifier": "explain",
      "name": "Random hazard forest: explain",
      "description": "Explains a saved hazard forest: AUC over follow-up, predicted hazard curves and VarPro importance over time. It never grows a forest.",
      "folder": "analyses",
      "family": "machine-learning",
      "kind": "job",
      "status": "in-flight",
      "batch": null,
      "sas_breadth": null,
      "r_exemplars": null,
      "r_jobs": null,
      "upstream": [],
      "downstream": [],
      "workflows": [],
      "blocked_on": null,
      "spec": "dev/specs/2026-10-26-rhf-templates-design.md",
      "note": "Reads rhf.rds from rhf-fit in the same set and never refits. Caches rhf-varpro-cache for later VarPro work on the forest. Census counts are on the fit row.",
      "sas_breadth_jobs": null,
      "disposition": "scaffold",
      "uses": [
        "randomForestRHF::auct.rhf",
        "randomForestRHF::varpro.cache.rhf",
        "randomForestRHF::importance.rhf",
        "hvtiRutilities::cache_fit",
        "hvtiRtemplates::guard_long_fit",
        "ggRandomForests::gg_auct",
        "ggRandomForests::gg_rhf",
        "ggRandomForests::gg_rhf_importance"
      ]
    },
```

- [ ] **Step 4: Write the tests.** Append to `test-rhf-templates.R`:

```r
rhf_explain_labels <- c("setup", "edit-study-choices", "forest", "tbl-data", "fig-auc-cumulative", "fig-auc-incident",
                        "tbl-auc", "curves", "fig-hazard", "fig-chf", "fig-importance", "tbl-importance")
rhf_explain_choices <- list(N_CURVES = 5, MAX_RULES_TREE = 10, MAX_TREE = 10, N_TIMES = 3, SEED = 1)

test_that("rhf-explain explains the saved forest without refitting", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("rhf", "explain"))
  fit <- rhf_fit_first()
  forest_cache <- file.path(fit$CACHE_DIR, "rhf-forest.rds")
  grown_at <- file.mtime(forest_cache)
  env <- new.env(parent = globalenv())
  env$.root <- fit$.root
  utils::capture.output(rf_run("rhf", "explain", rhf_explain_labels, env, rhf_explain_choices))
  for (nm in c("rhf-auc-cumulative", "rhf-auc-incident", "rhf-varpro-cache", "rhf-importance")) {
    expect_true(file.exists(file.path(env$CACHE_DIR, paste0(nm, ".rds"))), info = nm)
  }
  expect_length(env$.curve_ids, 5L)
  expect_true(all(is.finite(c(env$auc_cum$iAUC.uno, env$auc_inc$iAUC.uno))))
  for (p in list(ggRandomForests::gg_auct(env$forest, auct_fit = env$auc_cum), env$haz,
                 ggRandomForests::gg_rhf_importance(env$forest, importance_fit = env$imp))) {
    expect_s3_class(ggplot2::ggplot_build(plot(p)), "ggplot_built")
  }
  # It never regrows: the fit's forest cache is untouched by the explain run.
  expect_identical(file.mtime(forest_cache), grown_at)
})

test_that("rhf-explain stops when no fit has run in its set", {
  rf_skip_unless_stack(rf_template_packages("rhf", "explain"))
  env <- new.env(parent = globalenv())
  env$.root <- rf_study()
  expect_error(rf_run("rhf", "explain", c("setup", "edit-study-choices", "forest"), env),
               "Render the rhf-fit job in this set first")
})

test_that("a forest grown on repaired rows makes the explain report a draft, and stops a final one", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("rhf", "explain"))
  d <- rhf_data()
  first <- which(d$ccfid == d$ccfid[[1L]])
  d$start[first[2L]] <- d$start[first[2L]] - 1e-3
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "")
  fit <- rhf_fit_first(d, utils::modifyList(rhf_choices, list(REPAIR = "clip", TREESIZE = 5L)))
  env <- new.env(parent = globalenv())
  env$.root <- fit$.root
  out <- utils::capture.output(rf_run("rhf", "explain", c("setup", "edit-study-choices", "forest"), env))
  expect_true(any(grepl("DRAFT -- rows repaired in the job", out, fixed = TRUE)))
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "1")
  env <- new.env(parent = globalenv())
  env$.root <- fit$.root
  expect_error(rf_run("rhf", "explain", c("setup", "edit-study-choices", "forest"), env), "HVTI_TEMPLATE_STRICT")
})
```

- [ ] **Step 5: Run them, then the seed-hygiene and catalog suites.**

```bash
R CMD INSTALL -l "$LIB" . && R_LIBS="$LIB" NOT_CRAN=true _R_CHECK_LIMIT_CORES_=TRUE \
  Rscript -e 'devtools::test(filter = "rhf-templates|seed-hygiene|catalog|roadmap|add-job")'
python3 dev/specs/artifacts/check-roadmap-counts.py
```

Expected: PASS, `SKIP 0`, `WARN 0`. A loess or off-scale notice from drawing on 60 simulated patients belongs in `rf_drawing_notice()` only if it matches a pattern already listed there; anything else is a real warning to fix.

- [ ] **Step 6: Mutation check.** Remove the `.cp_repair_notice()` line from the `forest` chunk and confirm the draft test fails. Restore it.

- [ ] **Step 7: Commit.**

```bash
git add inst/templates/30_analyses/rhf-explain.qmd .lintr inst/extdata/templates.json tests/testthat/test-rhf-templates.R
git commit -m "Add the rhf-explain template"
```

---

### Task 7: README rows and news fragment

**Files:**
- Modify: `inst/templates/README.md` (the template table after the `vt-explain.qmd` row, about line 44; the figure-name list where the `rfs` names are; the walkthrough near line 152 if it lists each forest prefix)
- Create: `news/feat-rhf-templates.md`

- [ ] **Step 1: README rows.** After the `vt-explain.qmd` row:

```markdown
| `30_analyses/rhf-fit.qmd` | random hazard forest on counting-process rows with time-varying predictors: the rows checked, tree size tuned, forest grown (in flight) | `30_analyses/` or `analyses/` |
| `30_analyses/rhf-explain.qmd` | AUC over follow-up, hazard curves and VarPro importance over time for an `rhf` forest (in flight) | `30_analyses/` or `analyses/` |
```

Add `rhf-fit-tuning`, `rhf-explain-auc-cumulative`, `rhf-explain-auc-incident`, `rhf-explain-hazard`, `rhf-explain-chf` and `rhf-explain-importance` wherever the README lists each template's figure names for `FIGURES`, in the format the `rfs` entries use. Add the pair to the line-94 list of paired fit/explain jobs.

- [ ] **Step 2: News fragment.** `news/feat-rhf-templates.md`:

```markdown
* New in-flight templates `rhf-fit` and `rhf-explain`: a random hazard forest (randomForestRHF) on counting-process rows, one row per interval of a patient's follow-up, so a predictor may change over time. `rhf-fit` checks the rows before fitting and stops on an overlap, an interval of zero length, an event before a patient's last interval, or a missing predictor, naming the first few patients; `REPAIR <- "clip"` or `"drop_na"` repairs the first two kinds in a draft while the dataset fix is in flight, and a final render refuses it. It tunes the tree size and saves `rhf.rds`. `rhf-explain` reads it and reports cumulative and incident AUC(t), out-of-bag hazard curves and VarPro importance at points across follow-up, caching the VarPro cache as `rhf-varpro-cache`. Patients are numbered 1 to n before the fit, so the saved forest holds no study identifier.
* `read_job_data()` has a `whole_patients` argument. With `TRUE` it stops when `where` keeps some of a patient's rows and drops others, which would shorten follow-up without a word.
```

- [ ] **Step 3: Commit.**

```bash
git add inst/templates/README.md news/feat-rhf-templates.md
git commit -m "Document the rhf templates"
```

---

### Task 8: Gate

- [ ] **Step 1: Document and lint.** `Rscript -e 'devtools::document()'` changes nothing further; `Rscript -e 'lintr::lint_package()'` reports nothing.

- [ ] **Step 2: Full suite, CI mode.**

```bash
R CMD INSTALL -l "$LIB" . && R_LIBS="$LIB" NOT_CRAN=true _R_CHECK_LIMIT_CORES_=TRUE Rscript -e 'devtools::test()'
```

Expected: `FAIL 0`, `SKIP 0`. Read the `WARN` count against the known local figure (memory: `test-rf-templates.R` warns locally where CI does not); any warning from the rhf files is new and gets fixed.

- [ ] **Step 3: `R CMD check --as-cran` with the manual,** from a clean `git archive` export, not the worktree (`.git` is a file in a worktree):

```bash
git archive --format=tar HEAD | (mkdir -p /tmp/rhf-check && tar -x -C /tmp/rhf-check)
cd /tmp/rhf-check && R CMD build . && _R_CHECK_LIMIT_CORES_=TRUE R CMD check --as-cran hvtiRtemplates_*.tar.gz
```

Expected: 0 errors, 0 warnings, 0 notes. `check-manual.yaml` is post-merge only, so this local manual build is the only manual check before merge.

- [ ] **Step 4: The three spec-count scripts.**

```bash
for s in check-spec-counts check-flow-counts check-roadmap-counts; do python3 dev/specs/artifacts/$s.py; done
```

- [ ] **Step 5: Local `/code-review`,** then push and open the PR against `main` (not stacked). The body says Task 1's hvtiRutilities PR must merge first, and that `/code-review` stood in for Copilot if the quota body is still what Copilot returns.

- [ ] **Step 6: After CI, read every leg's summary line,** not the check mark:

```bash
gh run view <run-id> --log | grep -E "SKIP [0-9]+ \| PASS"
```

Expected: `SKIP 0` on macOS and Ubuntu, and the Windows count unchanged from `main` (no new `skip_on_os("windows")`).

## Not in this plan

- The hvtiRtemplates version bump and the hvtiRutilities floor raise: both happen when John names the version (the bump commit raises the floor to the hvtiRutilities release carrying `rhf`).
- Scaffolding the Hsich job from the template (`add_job("rhf", "dead", "rhf", qualifier = "fit")`) and running it on lri: the other session's work, once this merges and installs on lri.
- The VarPro-RHF template, which reads `rhf-varpro-cache`.
- A gallery rebuild: due on the next family release day, not on this merge.
