# `bd` build job Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `inst/templates/00_datasets/bd.qmd`, a build job that cuts a study's dataset from a master parquet snapshot, records attrition, and publishes and registers a dated release that downstream jobs such as `ac` read, plus the exported helper `build_cohort()`.

**Architecture:** The template does the visible work in plain-R chunks (read the master, cut, derive, write a draft, publish, register, report), so `knitr::purl()` yields a script that a scheduled refresh can run. `build_cohort()` in `R/build-cohort.R` carries the cohort-list join and the ordered `EXCLUDE` rules, and returns the kept rows and an attrition table that names steps by reason, never by rule text. The report renders with `echo: false`, so no line of the job, identifiers in `EXCLUDE` included, reaches the HTML.

**Tech Stack:** R, Quarto 1.5+, arrow (`read_parquet(col_select =)`), hvtiRdatabuild (`publish_dataset()`, `snapshot_master()` for the test fixture), hvtiRutilities (`study_setup()`, `study_dir()`, `register_data()`, `adopt_data_update()`, `study_config()`, `verify_manifest()`), testthat 3e.

**Spec:** `dev/specs/2026-10-02-bd-build-job-design.md` (approved and merged as #229, including its section 11 revisions).

## Global Constraints

- Prose (roxygen, template narration, NEWS, README) follows the house voice: no em dashes, US spelling.
- Roxygen here is Rd markup, not markdown: `\code{}`, `\strong{}`, `\itemize{}`. No backticks in roxygen.
- Lines up to 135 characters (`.lintr`). Every other default linter is on in `R/`.
- `hvtiRdatabuild (>= 0.2.3)` in Suggests (today `>= 0.2.1`). Add `haven` to Suggests, used only by the test fixture.
- `hvtiRutilities (>= 1.4.2)` in Imports is unchanged: release-aware `register_data()` shipped in 1.4.1 (checked 2026-10-02).
- No patient value in any message, attrition table or rendered HTML. Counts and column names only.
- Templates carry no study identifiers; every study-specific line is marked `EDIT:`; one `^SUBJECT\s+<- ` line and one `^TYPE\s+<- ` line.
- The `.lintr` key for the new template is the FILE `inst/templates/00_datasets/bd.qmd`, never a directory.
- No version bump in the PR. NEWS gets an entry under `# hvtiRtemplates (unreleased)` (it already exists at the top of `NEWS.md`).
- Never push to `main`. Branch `feat/bd-build-job` from `origin/main`.
- Synthetic data only. The fixture's IDs come from `hvtiRutilities::generate_survival_data()` (`PT00001`...) and a simulated `mrn` column (`M0000001`...).

## Facts verified before planning (2026-10-02)

- `study_setup()` creates `00_datasets/`; `study_dir("datasets", root)` resolves to it; `add_job()` places through `study_dir(row$folder)`.
- `publish_dataset(draft, dataset_id, datasets_dir, extract_date, source)` returns a list with `release_id`, `file` (a basename such as `syn_study_20261002.rds`), `sha256`, `n_rows`, and more. Publishing the same `saveRDS()` bytes again returns the same release.
- After `register_data(root, built = <file>, catalog_dataset =, release_id =)`, `study_config(root)$release$release_id` is the registered release and `$built` its file. A second `register_data()` stops with "the default dataset is already registered".
- `adopt_data_update(study_config(root), release_id = <newer>)` adopts a same-date `-r2` and `verify_manifest()` passes after it.
- `snapshot_master()` on a SAS file written by `haven::write_sas()` from `generate_survival_data(n = 200)` plus a `Date` column writes `built.parquet` and `built.meta.json` (fields `parquet_sha256`, `n_rows`, `lineage$parent_release`), and `dt_surg` reads back as `Date`.
- `generate_survival_data()` columns include `ccfid`, `iv_dead`, `dead`, `age`, `sex`, `origin_year`: the ones `ac` needs by default.

## File Structure

| File | Responsibility |
|---|---|
| Create `R/build-cohort.R` | `build_cohort()` and its private helpers: rule validation, cohort-list join, rule evaluation, attrition rows |
| Create `tests/testthat/test-build-cohort.R` | unit tests for `build_cohort()` |
| Create `inst/templates/00_datasets/bd.qmd` | the template |
| Create `tests/testthat/helper-bd.R` | synthetic master snapshot, study, scaffolded job, render |
| Create `tests/testthat/test-bd-template.R` | placement, draft run, failure messages, carried columns (chunk by chunk, no Quarto) |
| Create `tests/testthat/test-bd-e2e.R` | full renders: publish, adopt, draft, HTML free of IDs, `ac` against the release, purled script |
| Modify `.lintr` | file key for `bd.qmd` |
| Modify `DESCRIPTION` | Suggests: `hvtiRdatabuild (>= 0.2.3)`, `haven` |
| Modify `inst/extdata/templates.json` | `bd` row shipped; then `roadmap_render.py` regenerates the roadmap tables |
| Modify `inst/templates/README.md` | the `00_datasets` row in "What is here" |
| Modify `NEWS.md` | entry under `(unreleased)` |
| Generated `man/build_cohort.Rd`, `NAMESPACE` | by `devtools::document()` |

---

### Task 1: `build_cohort()`

**Files:**
- Create: `R/build-cohort.R`
- Create: `tests/testthat/test-build-cohort.R`
- Generated: `man/build_cohort.Rd`, `NAMESPACE`

**Interfaces:**
- Consumes: `.id_text(x)` from `R/id-digest.R` (identifiers as text; whole numbers without an exponent).
- Produces: `build_cohort(data, exclude = NULL, cohort = NULL, join_by = NULL, id = "ccfid")` returning `list(data = <data.frame>, attrition = <data.frame>)`. `attrition` columns, in order: `step` (chr: `"master"`, `"cohort"`, `"cohort list"`, `"exclude"`), `reason` (chr), `rows_before`, `removed`, `missing_condition`, `rows_after`, `patients_after` (all integer). Every error message starts `build_cohort(): `.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-build-cohort.R`:

```r
# build_cohort() is the cohort step of the bd build job. Every value here is
# simulated; the IDs are made up.

bc_data <- function() {
  data.frame(
    ccfid = c("A0001", "A0002", "A0003", "A0004", "A0005", "A0005"),
    dt_surg = as.Date(c("2010-01-05", "2011-02-06", "2012-03-07", "2013-04-08", "2014-05-09", "2015-06-10")),
    age = c(17, 40, NA, 66, 70, 71),
    stringsAsFactors = FALSE
  )
}

bc_list <- function(rows, .local_envir = parent.frame()) {
  path <- withr::local_tempfile(fileext = ".csv", .local_envir = .local_envir)
  utils::write.csv(rows, path, row.names = FALSE)
  path
}

test_that("with no cohort and no rules every row is kept, and the master row is recorded", {
  out <- build_cohort(bc_data())
  expect_identical(nrow(out$data), 6L)
  expect_identical(names(out$attrition),
                   c("step", "reason", "rows_before", "removed", "missing_condition", "rows_after", "patients_after"))
  expect_identical(out$attrition$step, "master")
  expect_identical(out$attrition$patients_after, 5L)
})

test_that("EXCLUDE rules apply in order; a missing condition is not excluded, and is counted", {
  out <- build_cohort(bc_data(), exclude = list(age < 18 ~ "Under 18", duplicated(ccfid) ~ "Later operation"))
  expect_identical(out$data$ccfid, c("A0002", "A0003", "A0004", "A0005"))
  att <- out$attrition
  expect_identical(att$reason, c("Rows read", "Under 18", "Later operation"))
  expect_identical(att$removed, c(0L, 1L, 1L))
  expect_identical(att$missing_condition, c(0L, 1L, 0L))
  expect_identical(att$rows_after, c(6L, 5L, 4L))
  expect_identical(att$patients_after, c(5L, 4L, 4L))
})

test_that("a rule naming a patient works, and its text never reaches the attrition table", {
  out <- build_cohort(bc_data(), exclude = list(ccfid == "A0004" ~ "Withdrew consent"))
  expect_false("A0004" %in% out$data$ccfid)
  expect_false(any(grepl("A0004", unlist(out$attrition))))
})

test_that("an outside vector of IDs works through the rule's environment", {
  withdrawn <- c("A0001", "A0002")
  out <- build_cohort(bc_data(), exclude = list(ccfid %in% withdrawn ~ "Withdrew consent"))
  expect_identical(nrow(out$data), 4L)
})

test_that("a cohort list keeps matched rows and counts list rows that matched nothing", {
  path <- bc_list(data.frame(ccfid = c("A0002", "A0004", "Z9999"), dt_surg = c("2011-02-06", "2013-04-08", "2013-04-08")))
  out <- build_cohort(bc_data(), cohort = path, join_by = c("ccfid", "dt_surg"))
  expect_identical(out$data$ccfid, c("A0002", "A0004"))
  expect_identical(out$attrition$step, c("master", "cohort"))
  expect_match(out$attrition$reason[[2L]], "1 list row\\(s\\) matched no master row")
  expect_false(any(grepl("Z9999", unlist(out$attrition))))
})

test_that("numbers and text match as identifiers: 100000 and \"100000\"", {
  d <- data.frame(ccfid = c(100000, 100001), dt_surg = as.Date(c("2010-01-01", "2010-01-02")))
  path <- bc_list(data.frame(ccfid = "100000", dt_surg = "2010-01-01"))
  out <- build_cohort(d, cohort = path, join_by = c("ccfid", "dt_surg"))
  expect_identical(nrow(out$data), 1L)
})

test_that("a cohort list's exclude and reason columns become steps, and the helper column is dropped", {
  path <- bc_list(data.frame(ccfid = c("A0002", "A0004", "A0003"), dt_surg = c("2011-02-06", "2013-04-08", "2012-03-07"),
                             exclude = c(0, 1, 1), reason = c("", "Redo", "Redo")))
  out <- build_cohort(bc_data(), cohort = path, join_by = c("ccfid", "dt_surg"))
  expect_identical(out$data$ccfid, "A0002")
  expect_identical(out$attrition$step, c("master", "cohort", "cohort list"))
  expect_identical(out$attrition$reason[[3L]], "Redo")
  expect_identical(out$attrition$removed[[3L]], 2L)
  expect_identical(names(out$data), names(bc_data()))
})

test_that("cohort-list problems stop with the file and the setting, never a value", {
  d <- bc_data()
  no_col <- bc_list(data.frame(ccfid = "A0002"))
  expect_error(build_cohort(d, cohort = no_col, join_by = c("ccfid", "dt_surg")), "has no column\\(s\\) dt_surg")
  bad_date <- bc_list(data.frame(ccfid = "A0002", dt_surg = "02/06/2011"))
  err <- expect_error(build_cohort(d, cohort = bad_date, join_by = c("ccfid", "dt_surg")), "YYYY-MM-DD")
  expect_false(grepl("A0002|02/06/2011", conditionMessage(err)))
  repeated <- bc_list(data.frame(ccfid = c("A0002", "A0002"), dt_surg = c("2011-02-06", "2011-02-06")))
  expect_error(build_cohort(d, cohort = repeated, join_by = c("ccfid", "dt_surg")), "repeats 1 JOIN_BY key")
  expect_error(build_cohort(d, cohort = file.path(tempdir(), "absent.csv"), join_by = "ccfid"), "does not exist")
  no_reason <- bc_list(data.frame(ccfid = "A0002", dt_surg = "2011-02-06", exclude = 1))
  expect_error(build_cohort(d, cohort = no_reason, join_by = c("ccfid", "dt_surg")), "no reason column")
})

test_that("a malformed rule names its number and reason, never its text", {
  d <- bc_data()
  expect_error(build_cohort(d, exclude = list(age < 18)), "EXCLUDE rule 1 is not written condition ~ \"Reason\"")
  expect_error(build_cohort(d, exclude = list(age ~ 18)), "EXCLUDE rule 1 is not written")
  err <- expect_error(build_cohort(d, exclude = list(age > 1 ~ "Fine", ccfid == "A0001" & nope ~ "Broken")),
                      "EXCLUDE rule 2 \\(\"Broken\"\\) could not be evaluated")
  expect_false(grepl("A0001", conditionMessage(err)))
  expect_error(build_cohort(d, exclude = list(age ~ "Not logical")), "must give TRUE or FALSE for each of the 6 rows")
  expect_error(build_cohort(d, exclude = list(TRUE ~ "Too short")), "must give TRUE or FALSE for each of the 6 rows")
})

test_that("a step that empties the data stops and names it", {
  expect_error(build_cohort(bc_data(), exclude = list(!is.na(ccfid) ~ "Everyone")), "\"Everyone\" excluded every remaining row")
})

test_that("the ID column must exist", {
  expect_error(build_cohort(bc_data(), id = "mrn"), "the ID column mrn is not in the data")
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'devtools::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-build-cohort.R")'`
Expected: FAIL, `could not find function "build_cohort"`.

- [ ] **Step 3: Write the implementation**

Create `R/build-cohort.R`:

```r
#' Cut a study cohort from a master, recording who was dropped and why
#'
#' @description
#' The cohort step of a \code{bd} build job. It keeps the master rows a study
#' is made of and returns, beside them, an attrition table: one row per step,
#' with the rows each step removed and the patients left. A step is named by its
#' reason, never by its rule's text, so the table is safe to print whatever a
#' rule names.
#'
#' @param data A data frame read from the master.
#' @param exclude \code{NULL}, or a list of rules written
#'   \code{condition ~ "Reason"}, applied in order to the rows still kept. Each
#'   condition is evaluated against the data, with the rule's own environment
#'   for anything else it names, and must give \code{TRUE} or \code{FALSE} for
#'   every row. A row whose condition is missing is \strong{not} excluded, as SAS
#'   \code{if ... then delete} and an hvtiRdatabuild analysis set treat it, and
#'   the number of such rows is counted. A downstream job's \code{WHERE} drops
#'   such rows instead.
#' @param cohort \code{NULL}, or the path to a CSV cohort list, such as a REDCap
#'   export, carrying the \code{join_by} columns. Only master rows matched by a
#'   list row are kept. Dates are written YYYY-MM-DD. A list may carry
#'   \code{exclude} (1 to exclude) and \code{reason} columns; each reason becomes
#'   a step of its own.
#' @param join_by The columns that match a cohort-list row to a master row. Used
#'   only with \code{cohort}.
#' @param id The patient identifier column, used to count patients.
#'
#' @details Identifiers are compared as text, so \code{100000} in the master
#'   matches \code{"100000"} in a list. No message names a data value: list rows
#'   that matched no master row are counted, never listed, and a rule that fails
#'   is named by its number and reason.
#'
#' @return A list:
#'   \itemize{
#'     \item \code{data}, the kept rows, with the master's columns;
#'     \item \code{attrition}, a data frame with one row per step and the
#'       columns \code{step}, \code{reason}, \code{rows_before},
#'       \code{removed}, \code{missing_condition}, \code{rows_after} and
#'       \code{patients_after}.
#'   }
#'
#' @examples
#' d <- data.frame(ccfid = c("S1", "S2", "S3"), age = c(17, 45, NA))
#' build_cohort(d, exclude = list(age < 18 ~ "Under 18"))$attrition
#' @export
build_cohort <- function(data, exclude = NULL, cohort = NULL, join_by = NULL, id = "ccfid") {
  if (!is.data.frame(data)) stop("build_cohort(): data must be a data frame.", call. = FALSE)
  if (!is.character(id) || length(id) != 1L || !id %in% names(data)) {
    stop("build_cohort(): the ID column ", id, " is not in the data. Set ID in edit-study-choices.", call. = FALSE)
  }
  rules <- .cohort_rules(exclude)
  patients <- function(d) length(unique(d[[id]]))
  row <- function(step, reason, before, missing, d) {
    data.frame(step = step, reason = reason, rows_before = as.integer(before), removed = as.integer(before - nrow(d)),
               missing_condition = as.integer(missing), rows_after = nrow(d), patients_after = patients(d),
               stringsAsFactors = FALSE)
  }
  attrition <- list(row("master", "Rows read", nrow(data), 0L, data))
  if (!is.null(cohort)) {
    cut <- .cohort_join(data, cohort, join_by)
    attrition[[length(attrition) + 1L]] <- row("cohort", cut$reason, nrow(data), 0L, cut$data)
    data <- cut$data
    if (!nrow(data)) stop("build_cohort(): no master row matched the cohort list (", cohort, "). Check JOIN_BY.", call. = FALSE)
    rules <- c(cut$rules, rules)
  }
  for (i in seq_along(rules)) {
    rule <- rules[[i]]
    reason <- rlang::f_rhs(rule)
    hit <- .eval_cohort_rule(rule, data, i, reason)
    before <- nrow(data)
    data <- data[!(hit %in% TRUE), , drop = FALSE]
    step <- if (is.null(attr(rule, "step"))) "exclude" else attr(rule, "step")
    attrition[[length(attrition) + 1L]] <- row(step, reason, before, sum(is.na(hit)), data)
    if (!nrow(data)) stop("build_cohort(): \"", reason, "\" excluded every remaining row.", call. = FALSE)
  }
  data$.cohort_reason <- NULL
  rownames(data) <- NULL
  list(data = data, attrition = do.call(rbind, attrition))
}

# Every rule is `condition ~ "Reason"`, a single non-empty quoted reason.
.cohort_rules <- function(exclude) {
  if (is.null(exclude)) return(list())
  if (inherits(exclude, "formula")) exclude <- list(exclude)
  if (!is.list(exclude)) {
    stop("build_cohort(): EXCLUDE must be NULL or a list of rules written condition ~ \"Reason\".", call. = FALSE)
  }
  for (i in seq_along(exclude)) {
    rule <- exclude[[i]]
    ok <- inherits(rule, "formula") && length(rule) == 3L
    reason <- if (ok) rlang::f_rhs(rule) else NULL
    if (!ok || !is.character(reason) || length(reason) != 1L || is.na(reason) || !nzchar(reason)) {
      stop("build_cohort(): EXCLUDE rule ", i, " is not written condition ~ \"Reason\". Give every rule a condition ",
           "and a quoted reason.", call. = FALSE)
    }
  }
  exclude
}

# The rule's error message is withheld: it can quote a data value.
.eval_cohort_rule <- function(rule, data, i, reason) {
  label <- paste0("build_cohort(): EXCLUDE rule ", i, " (\"", reason, "\")")
  failed <- structure(list(), class = "cohort_rule_failed")
  hit <- tryCatch(rlang::eval_tidy(rlang::f_lhs(rule), data = data, env = rlang::f_env(rule)), error = function(e) failed)
  if (inherits(hit, "cohort_rule_failed")) {
    stop(label, " could not be evaluated. Run its condition in the console against the data to see why; the message ",
         "is withheld here because it can carry a data value.", call. = FALSE)
  }
  if (!is.logical(hit) || length(hit) != nrow(data)) {
    stop(label, " must give TRUE or FALSE for each of the ", nrow(data), " rows; it gave a ", class(hit)[[1L]],
         " of length ", length(hit), ".", call. = FALSE)
  }
  hit
}

# Keep the master rows a cohort list names. A list carrying exclude and reason
# columns contributes one rule per reason, applied to a helper column that
# build_cohort() drops before it returns.
.cohort_join <- function(data, cohort, join_by) {
  where <- paste0("build_cohort(): the cohort list (", cohort, ")")
  if (!is.character(cohort) || length(cohort) != 1L || !file.exists(cohort)) {
    stop(where, " does not exist. Set COHORT in edit-study-choices.", call. = FALSE)
  }
  if (!is.character(join_by) || !length(join_by)) {
    stop("build_cohort(): JOIN_BY must name the columns that match the cohort list to the master.", call. = FALSE)
  }
  absent <- setdiff(join_by, names(data))
  if (length(absent)) {
    stop("build_cohort(): JOIN_BY column(s) ", toString(absent), " are not in the master. Set JOIN_BY.", call. = FALSE)
  }
  listed <- utils::read.csv(cohort, colClasses = "character", check.names = FALSE, na.strings = "")
  names(listed) <- tolower(names(listed))
  absent <- setdiff(join_by, names(listed))
  if (length(absent)) {
    stop(where, " has no column(s) ", toString(absent), ". Set JOIN_BY, or fix the list's header.", call. = FALSE)
  }
  list_key <- .cohort_key(listed, join_by, data, where)
  if (anyNA(list_key)) {
    stop(where, " has ", sum(is.na(list_key)), " row(s) with a blank JOIN_BY value. Complete or remove them.",
         call. = FALSE)
  }
  if (any(duplicated(list_key))) {
    stop(where, " repeats ", sum(duplicated(list_key)), " JOIN_BY key(s). Each list row must name one master row.",
         call. = FALSE)
  }
  master_key <- .cohort_key(data, join_by)
  keep <- !is.na(master_key) & master_key %in% list_key
  out <- data[keep, , drop = FALSE]
  rules <- list()
  if ("exclude" %in% names(listed)) {
    if (!"reason" %in% names(listed)) {
      stop(where, " has an exclude column and no reason column. Add one, so each exclusion is counted under its ",
           "reason.", call. = FALSE)
    }
    flagged <- listed$exclude %in% "1"
    if (any(flagged & (is.na(listed$reason) | !nzchar(trimws(listed$reason))))) {
      stop(where, " flags ", sum(flagged & (is.na(listed$reason) | !nzchar(trimws(listed$reason)))),
           " row(s) for exclusion with no reason. Give each one a reason.", call. = FALSE)
    }
    out$.cohort_reason <- ifelse(flagged, trimws(listed$reason), NA_character_)[match(master_key[keep], list_key)]
    for (r in unique(trimws(listed$reason[flagged]))) {
      rule <- rlang::new_formula(rlang::expr(.cohort_reason %in% !!r), r, env = baseenv())
      rules[[length(rules) + 1L]] <- structure(rule, step = "cohort list")
    }
  }
  unmatched <- sum(!list_key %in% master_key)
  reason <- if (unmatched) {
    paste0("Not in the cohort list (", unmatched, " list row(s) matched no master row)")
  } else {
    "Not in the cohort list"
  }
  list(data = out, rules = rules, reason = reason)
}

# One text key per row: dates as YYYY-MM-DD, identifiers through .id_text(), so
# 100000 and "100000" agree. A row with any missing part has an NA key. When
# `master` is given, list columns are read as the master's types require.
.cohort_key <- function(d, cols, master = NULL, where = NULL) {
  parts <- lapply(cols, function(col) {
    x <- d[[col]]
    if (!is.null(master) && inherits(master[[col]], "Date")) {
      parsed <- as.Date(x, format = "%Y-%m-%d")
      bad <- sum(!is.na(x) & is.na(parsed))
      if (bad) {
        stop(where, ": ", bad, " value(s) of ", col, " are not dates written YYYY-MM-DD, as the master's ", col,
             " is a date.", call. = FALSE)
      }
      x <- format(parsed, "%Y-%m-%d")
    } else if (inherits(x, "Date")) {
      x <- format(x, "%Y-%m-%d")
    } else {
      x <- .id_text(x)
    }
    trimws(x)
  })
  key <- do.call(paste, c(parts, sep = "\r"))
  key[Reduce(`|`, lapply(parts, is.na))] <- NA_character_
  key
}
```

- [ ] **Step 4: Regenerate docs and run the tests**

Run: `Rscript -e 'devtools::document(); devtools::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-build-cohort.R")'`
Expected: `NAMESPACE` gains `export(build_cohort)`, `man/build_cohort.Rd` is created, all tests PASS.

- [ ] **Step 5: Lint the new file**

Run: `Rscript -e 'lintr::lint("R/build-cohort.R")'`
Expected: no lints.

- [ ] **Step 6: Commit**

```bash
git add R/build-cohort.R tests/testthat/test-build-cohort.R man/build_cohort.Rd NAMESPACE
git commit -m "build_cohort(): the cohort and attrition step of the bd build job (#223)"
```

---

### Task 2: the `bd.qmd` template, its fixture, and the chunk tests

**Files:**
- Create: `inst/templates/00_datasets/bd.qmd`
- Create: `tests/testthat/helper-bd.R`
- Create: `tests/testthat/test-bd-template.R`
- Modify: `.lintr` (add the file key beside the other template keys)
- Modify: `DESCRIPTION` (Suggests)
- Modify: `inst/extdata/templates.json` (the `bd` row), then regenerate the roadmap tables
- Modify: `inst/templates/README.md`

**Interfaces:**
- Consumes: `build_cohort()` from Task 1; `hazard_run(prefix, labels, env, choices)` from `tests/testthat/helper-hazard.R`, which evaluates named chunks of any template, despite its name.
- Produces, for Task 3: the template's chunk labels `setup`, `guard-edits`, `set`, `edit-study-choices`, `check-choices`, `read-master`, `cohort`, `derive`, `write-draft`, `publish`, `report-source`, `report-attrition`, `report-columns`. Single-line settings `MASTER <- `, `VERIFY_MASTER <- `, `COHORT <- `, `JOIN_BY <- `, `KEEP <- `, `EXCLUDE <- `, `ID <- `, `KEY <- `, `DATASET_ID <- `, `PUBLISH <- `, so a test can replace each by one regex line edit. Objects after a run: `d` (the dataset), `.cut` (the `build_cohort()` result), `.draft`, `.record_file`, `.release` (NULL in draft mode), `.registered_before`, `.register_step`. Helpers in `helper-bd.R`: `bd_skip()`, `bd_master(n = 200L, .local_envir)` returning `list(parquet, data)`, `bd_study(.local_envir)` returning the root, `bd_job(root, edits = list())` returning the job path, `bd_run(root, choices, labels)` returning the chunk environment.

- [ ] **Step 1: Add the Suggests and the `.lintr` key**

In `DESCRIPTION`, change `    hvtiRdatabuild (>= 0.2.1),` to `    hvtiRdatabuild (>= 0.2.3),` and add `    haven,` after `    ggplot2,` (alphabetical order as the list has it).

In `.lintr`, add beside the other template file keys:

```
    "inst/templates/00_datasets/bd.qmd" = list(
      object_name_linter = Inf,
      commented_code_linter = Inf,
      object_usage_linter = Inf
    ),
```

- [ ] **Step 2: Write the fixture helper**

Create `tests/testthat/helper-bd.R`:

```r
# The bd build job's fixture: a synthetic master snapshot made the way a real
# one is, a SAS dataset run through hvtiRdatabuild::snapshot_master(), so the
# parquet and its sidecar are the real formats. Every value is simulated.

bd_skip <- function() {
  testthat::skip_if_not_installed("hvtiRdatabuild", "0.2.3")
  testthat::skip_if_not_installed("arrow")
  testthat::skip_if_not_installed("haven")
}

bd_master <- function(n = 200L, .local_envir = parent.frame()) {
  dir <- withr::local_tempdir("bd-master-", .local_envir = .local_envir)
  d <- hvtiRutilities::generate_survival_data(n = n, seed = 20261002)
  d$dt_surg <- as.Date(paste0(d$origin_year, "-06-15"))
  d$mrn <- sprintf("M%07d", seq_len(n))
  # write_sas() is superseded in haven, and warns so; it still writes a file
  # haven and snapshot_master() read back.
  suppressWarnings(haven::write_sas(d, file.path(dir, "built.sas7bdat")))
  writeLines("data m; run;", file.path(dir, "bd.data.sas"))
  cfg <- file.path(dir, "master.yml")
  writeLines(c("name: master_syn", "key: [ccfid]", paste0("snapshots: ", dir), "current: built.sas7bdat",
               paste0("build_program: ", file.path(dir, "bd.data.sas"))), cfg)
  out <- file.path(dir, "snapshot")
  utils::capture.output(suppressMessages(
    hvtiRdatabuild::snapshot_master(hvtiRdatabuild::read_master_config(cfg), out, which = "current")
  ))
  list(parquet = file.path(out, "built.parquet"), data = d)
}

bd_study <- function(.local_envir = parent.frame()) {
  root <- withr::local_tempdir("bd-study-", .local_envir = .local_envir)
  suppressMessages(hvtiRutilities::study_setup(root, study = "bd test", study_tracker_id = 9L, adopt = TRUE))
  normalizePath(root)
}

# Scaffold the job and apply `edits`, each a regex matching exactly one line
# and the line that replaces it, as a study author's edits would.
bd_job <- function(root, edits = list()) {
  job <- add_job("bd", "study", "build", dir = root)
  lines <- readLines(job, warn = FALSE)
  for (pattern in names(edits)) {
    hit <- grep(pattern, lines)
    if (length(hit) != 1L) stop("Expected one line matching ", pattern, call. = FALSE)
    lines[hit] <- edits[[pattern]]
  }
  writeLines(lines, job)
  job
}

# Run the job's chunks in a fresh environment from inside the study, so the
# setup chunk finds the root from the working directory as it does outside a
# render. `choices` overwrite the study choices after that chunk runs.
bd_run <- function(root, choices, labels = c("setup", "set", "edit-study-choices", "check-choices", "read-master",
                                              "cohort", "derive", "write-draft", "publish")) {
  env <- new.env(parent = globalenv())
  withr::with_dir(root, utils::capture.output(hazard_run("bd", labels, env, choices)))
  env
}
```

- [ ] **Step 3: Write the failing chunk tests**

Create `tests/testthat/test-bd-template.R`:

```r
test_that("add_job() scaffolds bd into the study's 00_datasets folder", {
  root <- bd_study()
  job <- add_job("bd", "study", "build", dir = root)
  expect_identical(basename(dirname(job)), "00_datasets")
  lines <- readLines(job, warn = FALSE)
  expect_true(any(lines == "SUBJECT <- \"study\""))
  expect_true(any(lines == "TYPE    <- \"build\""))
})

test_that("a draft run writes the draft and its record and publishes nothing", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  env <- bd_run(root, list(MASTER = m$parquet, KEEP = c("age", "iv_dead", "dead", "dt_surg"),
                           EXCLUDE = list(age < 40 ~ "Under 40")))
  datasets <- hvtiRutilities::study_dir("datasets", root)
  expect_true(file.exists(file.path(datasets, "draft-study_cohort.rds")))
  expect_true(file.exists(file.path(datasets, "draft-study_cohort.build.yml")))
  expect_false(file.exists(file.path(datasets, "dataset-catalog.yml")))
  expect_null(env$.release)
  expect_identical(env$.cut$attrition$reason, c("Rows read", "Under 40"))
  # A missing age is not excluded.
  expect_identical(nrow(env$d), nrow(m$data) - sum(m$data$age < 40, na.rm = TRUE))
})

test_that("the dataset carries ID, KEY, JOIN_BY and KEEP columns, and drops MRN", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  env <- bd_run(root, list(MASTER = m$parquet, KEEP = c("age", "mrn"), EXCLUDE = NULL))
  expect_setequal(names(env$d), c("ccfid", "dt_surg", "age"))
  draft <- readRDS(file.path(hvtiRutilities::study_dir("datasets", root), "draft-study_cohort.rds"))
  expect_identical(names(draft), names(env$d))
})

test_that("the build record holds the master's hash and the rules in full, beside the data", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  env <- bd_run(root, list(MASTER = m$parquet, KEEP = "age", EXCLUDE = list(ccfid == "PT00003" ~ "Withdrew consent")))
  rec <- yaml::read_yaml(env$.record_file)
  meta <- jsonlite::read_json(sub("[.]parquet$", ".meta.json", m$parquet))
  expect_identical(rec$master$sha256, meta$parquet_sha256)
  expect_match(rec$settings$exclude, "PT00003", fixed = TRUE)
  expect_identical(rec$attrition$reason, c("Rows read", "Withdrew consent"))
})

# Every stop names the step and this file, and no message carries a value.
bd_expect_stop <- function(root, choices, step, labels = NULL) {
  ids <- c(sprintf("PT%05d", 1:200), sprintf("M%07d", 1:200))
  run <- if (is.null(labels)) function() bd_run(root, choices) else function() bd_run(root, choices, labels)
  err <- testthat::expect_error(run(), paste0("^bd: ", step, " \\("))
  testthat::expect_false(any(vapply(ids, grepl, logical(1L), x = conditionMessage(err), fixed = TRUE)))
}

test_that("failures name the step and the file, never a value", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  ok <- list(MASTER = m$parquet, KEEP = "age", EXCLUDE = NULL)
  bd_expect_stop(root, utils::modifyList(ok, list(DATASET_ID = "Study-1")), "check-choices")
  bd_expect_stop(root, utils::modifyList(ok, list(KEEP = character())), "check-choices")
  bd_expect_stop(root, utils::modifyList(ok, list(MASTER = file.path(tempdir(), "absent.parquet"))), "read-master")
  bd_expect_stop(root, utils::modifyList(ok, list(KEEP = c("age", "no_such_column"))), "read-master")
  bd_expect_stop(root, utils::modifyList(ok, list(EXCLUDE = list(ccfid == "PT00001" & nope ~ "Broken"))), "cohort")
  bd_expect_stop(root, utils::modifyList(ok, list(EXCLUDE = list(!is.na(ccfid) ~ "Everyone"))), "cohort")
  bd_expect_stop(root, utils::modifyList(ok, list(KEY = "dead")), "write-draft")
  # A sidecar that disagrees with its parquet, under VERIFY_MASTER.
  bad <- bd_master()
  meta <- sub("[.]parquet$", ".meta.json", bad$parquet)
  json <- jsonlite::read_json(meta)
  json$parquet_sha256 <- strrep("0", 64L)
  jsonlite::write_json(json, meta, auto_unbox = TRUE, null = "null")
  bd_expect_stop(root, utils::modifyList(ok, list(MASTER = bad$parquet, VERIFY_MASTER = TRUE)), "read-master")
})

test_that("a derivation that changes the row count stops in derive", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  env <- new.env(parent = globalenv())
  choices <- list(MASTER = m$parquet, KEEP = "age", EXCLUDE = NULL)
  withr::with_dir(root, utils::capture.output(hazard_run("bd", c("setup", "set", "edit-study-choices", "check-choices",
                                                                 "read-master", "cohort"), env, choices)))
  env$d <- env$d[-1L, , drop = FALSE]
  # Simulate a derive chunk that dropped a row: the check compares with the
  # count the cohort step left.
  env$.rows_before_derive <- nrow(env$.cut$data)
  src <- readLines(hazard_template("bd"), warn = FALSE)
  at <- which(trimws(src) == "#| label: derive")
  end <- at + which(src[(at + 1L):length(src)] == "```")[1L]
  check <- grep("^if \\(nrow\\(d\\) != [.]rows_before_derive\\)", src[(at + 1L):(end - 1L)], value = TRUE)
  expect_length(check, 1L)
  expect_error(eval(parse(text = check), envir = env), "^bd: derive \\(")
})
```

- [ ] **Step 4: Run them to verify they fail**

Run: `Rscript -e 'devtools::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-bd-template.R")'`
Expected: FAIL, `add_job()` errors that no template matches prefix `bd`.

- [ ] **Step 5: Write the template**

Create `inst/templates/00_datasets/bd.qmd`:

````markdown
---
title: "Study dataset build"
# Carried in the file rather than inherited from _quarto.yml, as every template
# is: a file meant to be copied must not depend on the directory it sits in.
format:
  html:
    theme: cosmo
    toc: true
    toc-depth: 3
    df-print: default
    embed-resources: true
# A build report shows no code, where other templates fold it. This job's
# EXCLUDE rules may name patients, and the source of a folded chunk is in the
# HTML, which gets shared. The report is read for its counts; reviewers read
# this file. Warnings and messages go to the console for the same reason.
execute:
  echo: false
  warning: false
  message: false
---

<!-- EDIT: name the SAS job this replaces (usually datasets/bd.data.sas) and the master it read. -->

Replaces `datasets/<job>.sas`. This job cuts the study's dataset from a master
snapshot, records who was excluded and why, writes a draft, and, when
`PUBLISH` is `TRUE`, publishes a dated release and registers it as this study's
`"study"` dataset, the one every analysis job reads.

What does not belong here: corrections to a patient's values (they belong to
the master's corrections, in hvtiRdatabuild, so every study sees them);
imputation, propensity scores and variables for one model (a `vars` job);
printing patient rows to check them (do that in the console, never in a
report).

```{r}
#| label: setup
# The study root is the nearest directory above this file holding _study.yml,
# so the job runs the same from the Render button, quarto render, or as a
# script run from inside the study.
.in <- knitr::current_input(dir = TRUE)
.root <- hvtiRtemplates:::.find_study_root(if (is.null(.in)) getwd() else dirname(.in))
# Quarto knits through an intermediate, so the name is put back to .qmd.
.job_file <- if (is.null(.in)) "this job" else sub("[.][^.]+$", ".qmd", basename(.in))
# Every stop names its step and this file, and never a data value.
.bd_stop <- function(step, ...) stop("bd: ", step, " (", .job_file, "): ", ..., call. = FALSE)
```

```{r}
#| label: guard-edits
#| results: asis
# A job with unresolved markers renders as a draft, as every template does.
# Unlike the others, the banner gives only the COUNT: a marker line could sit
# beside a rule naming a patient, and this report shows no source. The marker
# text goes to the console in the warning.
.tok <- paste0("ED", "IT", ":")
.cur <- knitr::current_input()
if (!is.null(.cur)) {
  .src <- readLines(.cur, warn = FALSE)
  .hits <- grep(.tok, .src, fixed = TRUE)
  if (length(.hits)) {
    .msg <- paste0(length(.hits), " unresolved ", .tok, " marker(s) remain in this job:\n",
                   paste0("  - ", trimws(substr(.src[.hits], 1L, 96L)), collapse = "\n"))
    if (tolower(Sys.getenv("HVTI_TEMPLATE_STRICT")) %in% c("", "0", "false", "no")) {
      warning(.msg, call. = FALSE)
      cat("\n::: {.callout-important title=\"DRAFT -- this job is unfinished\"}\n")
      cat(length(.hits), "unresolved markers remain. **This dataset is not finished.**\n")
      cat(":::\n\n")
    } else {
      stop(.msg, "\nThis render stops because HVTI_TEMPLATE_STRICT is set.", call. = FALSE)
    }
  }
}
```

```{r}
#| label: set
SUBJECT <- "study"
TYPE    <- "build"

# add_job() writes SUBJECT and TYPE from the file's name; a hand-edited
# declaration that drifts from it stops here.
.current <- knitr::current_input()
if (!is.null(.current)) {
  .fields <- strsplit(sub("[.][^.]+$", "", basename(.current)), "-", fixed = TRUE)[[1L]]
  if (!identical(.fields[1L], SUBJECT) || !identical(.fields[2L], TYPE)) {
    .bd_stop("set", "the file's name and its SUBJECT and TYPE disagree. Fix the declaration or the name.")
  }
}
```

## Study choices

```{r}
#| label: edit-study-choices
# EDIT: the master snapshot this study is cut from: the parquet file that hvtiRdatabuild::snapshot_master() wrote.
# Its .meta.json sidecar must sit beside it. Name one dated snapshot, so a rebuild reads the same master.
MASTER <- "/path/to/snapshots/built_YYYYMMDD.parquet"

# TRUE rehashes the whole snapshot against its sidecar, which takes minutes on a
# large master. Worth it on the render that publishes.
VERIFY_MASTER <- FALSE

# EDIT: a cohort list (a REDCap export or data-request CSV) kept beside the data, or NULL for a cohort the rules define.
# For example file.path(hvtiRutilities::study_dir("datasets", .root), "cohort.csv"). Only master rows the list
# names are kept. A list may carry exclude (1 to exclude) and reason columns.
COHORT <- NULL

# The columns that match a cohort-list row to a master row. Dates in the list are written YYYY-MM-DD.
JOIN_BY <- c("ccfid", "dt_surg")

# EDIT: the master columns this study's dataset carries, in lower case. ID and KEY are added for you.
KEEP <- c("age", "sex", "dt_surg")

# EDIT: who is excluded, and why, in order, as condition ~ "Reason".
# A row whose condition is MISSING is NOT excluded, as SAS `if ... then delete` treats it, and the report counts
# such rows. That is the opposite of a downstream job's WHERE, which drops them, so write is.na() into a rule
# when a missing value should exclude. Rules may name patients, for example
#   ccfid %in% c("<id>", "<id>") ~ "Withdrew consent"
# and one row per patient is a rule after ordering the rows in the derive chunk's place, for example
#   duplicated(ccfid) ~ "Later operation"
# The report shows each rule's reason and counts, never its text.
EXCLUDE <- list(is.na(dt_surg) ~ "No surgery date")

# The patient, and what makes a row unique: one row per patient unless repeated measures.
ID  <- "ccfid"
KEY <- ID

# EDIT: the catalog name of this study's dataset: lower-case letters, digits and underscores.
DATASET_ID <- "study_cohort"

# FALSE writes a draft and publishes nothing. TRUE publishes a dated release and
# makes it this study's "study" dataset, which every analysis job then reads.
PUBLISH <- FALSE
```

```{r}
#| label: check-choices
# Checked before the master is read, so a bad setting fails in seconds rather
# than after a long read.
if (!is.character(DATASET_ID) || length(DATASET_ID) != 1L || !grepl("^[a-z0-9_]+$", DATASET_ID)) {
  .bd_stop("check-choices", "DATASET_ID must be lower-case letters, digits and underscores.")
}
if (!is.character(KEEP) || !length(KEEP)) .bd_stop("check-choices", "KEEP is empty. Name the master columns to carry.")
if (!is.logical(PUBLISH) || length(PUBLISH) != 1L || is.na(PUBLISH)) {
  .bd_stop("check-choices", "PUBLISH must be TRUE or FALSE.")
}
if (!is.character(MASTER) || length(MASTER) != 1L) .bd_stop("check-choices", "MASTER must be one path.")
KEEP <- tolower(KEEP)
JOIN_BY <- tolower(JOIN_BY)
ID <- tolower(ID)
KEY <- tolower(KEY)
```

```{r}
#| label: read-master
# The one chunk that changes when the master is read from a warehouse table
# instead of a snapshot file: everything after it sees only `d`.
.sidecar <- sub("[.]parquet$", ".meta.json", MASTER)
if (!file.exists(MASTER)) .bd_stop("read-master", "the master snapshot ", MASTER, " does not exist. Set MASTER.")
if (!file.exists(.sidecar)) {
  .bd_stop("read-master", "the master snapshot has no sidecar ", .sidecar,
           ". Snapshot the master with hvtiRdatabuild::snapshot_master(), which writes both.")
}
.meta <- jsonlite::read_json(.sidecar)
if (isTRUE(VERIFY_MASTER) && !identical(digest::digest(MASTER, algo = "sha256", file = TRUE), .meta$parquet_sha256)) {
  .bd_stop("read-master", MASTER, " does not match the SHA-256 in its sidecar. It changed after it was written; ",
           "snapshot the master again.")
}
.master <- list(file = MASTER, sha256 = .meta$parquet_sha256, rows = .meta$n_rows,
                parent_release = if (is.null(.meta$lineage$parent_release)) NA else .meta$lineage$parent_release,
                verified = isTRUE(VERIFY_MASTER))

# Read only the columns the job uses: a master can hold thousands.
.available <- names(arrow::open_dataset(MASTER))
.need <- unique(c(KEEP, ID, KEY, if (!is.null(COHORT)) JOIN_BY))
.absent <- .need[!.need %in% tolower(.available)]
if (length(.absent)) {
  .bd_stop("read-master", "column(s) ", toString(.absent), " are not in the master. Check KEEP, ID, KEY and JOIN_BY.")
}
.rule_vars <- unlist(lapply(EXCLUDE, function(rule) all.vars(rlang::f_lhs(rule))))
.cols <- .available[tolower(.available) %in% c(.need, JOIN_BY, tolower(.rule_vars))]
d <- as.data.frame(arrow::read_parquet(MASTER, col_select = tidyselect::all_of(.cols)))
names(d) <- tolower(names(d))
```

## Cohort

```{r}
#| label: cohort
.cut <- tryCatch(
  hvtiRtemplates::build_cohort(d, exclude = EXCLUDE, cohort = COHORT, join_by = JOIN_BY, id = ID),
  error = function(e) .bd_stop("cohort", conditionMessage(e))
)
d <- .cut$data
```

```{r}
#| label: derive
.rows_before_derive <- nrow(d)
.columns_before_derive <- names(d)

# EDIT: the study's own derived variables, the ones every analysis of this dataset needs.
# Follow-up intervals and event indicators belong here; imputation, propensity
# scores and variables for one model belong in a vars job. For example, with
# columns your master may name differently:
#   d$iv_dead <- as.numeric(d$dt_last - d$dt_surg) / 365.25
#   d$dead    <- as.integer(!is.na(d$dt_death))

if (nrow(d) != .rows_before_derive) {
  .bd_stop("derive", "the derivations changed the number of rows from ", .rows_before_derive, " to ", nrow(d),
           ". Derive columns here and exclude rows in EXCLUDE.")
}
```

```{r}
#| label: write-draft
.datasets <- hvtiRutilities::study_dir("datasets", .root)
.derived <- setdiff(names(d), .columns_before_derive)
.carry <- unique(c(ID, KEY, JOIN_BY, KEEP, .derived))
d <- d[, intersect(.carry, names(d)), drop = FALSE]
# MRN and eMRN are dropped unless one is the ID, as read_job_data() drops them.
d <- d[, !(names(d) %in% setdiff(c("mrn", "emrn"), ID)), drop = FALSE]
.repeats <- sum(duplicated(d[KEY]))
if (.repeats) {
  .bd_stop("write-draft", .repeats, " row(s) repeat a value of KEY (", toString(KEY), "). Exclude the extra rows in ",
           "EXCLUDE, or add a column to KEY.")
}
.draft <- file.path(.datasets, paste0("draft-", DATASET_ID, ".rds"))
saveRDS(d, .draft)

# The build record sits beside the data and is never rendered, so it holds the
# rules in full: it is how a release can be cut again.
.record <- list(
  master = .master,
  settings = list(cohort = COHORT, join_by = JOIN_BY, keep = KEEP, id = ID, key = KEY, dataset_id = DATASET_ID,
                  exclude = vapply(EXCLUDE, function(rule) paste(deparse(rule), collapse = " "), "")),
  attrition = .cut$attrition,
  hvtiRtemplates = as.character(utils::packageVersion("hvtiRtemplates"))
)
.record_file <- file.path(.datasets, paste0("draft-", DATASET_ID, ".build.yml"))
yaml::write_yaml(.record, .record_file)
```

## Publish

```{r}
#| label: publish
.registered <- hvtiRutilities::study_config(.root)
.registered_before <- .registered$release$release_id
.release <- NULL
.register_step <- "Draft only: nothing published"
if (PUBLISH) {
  # Publishing the same bytes again returns the same release, so a rerender
  # that changed nothing mints nothing.
  .release <- tryCatch(
    hvtiRdatabuild::publish_dataset(.draft, dataset_id = DATASET_ID, datasets_dir = .datasets,
                                    source = paste0("hvtiRtemplates bd job ", .job_file, "; master sha256 ",
                                                    .master$sha256)),
    error = function(e) .bd_stop("publish", "publish_dataset() stopped: ", conditionMessage(e))
  )
  file.copy(.record_file, file.path(.datasets, sub("[.][^.]+$", ".build.yml", .release$file)), overwrite = TRUE)
  # Publish and register stay two steps: a study that READS another's dataset
  # adopts its releases deliberately, with adopt_data_update(). Here the study
  # adopts its own build, and this render is the deliberate act.
  .register_step <- tryCatch({
    if (is.null(.registered_before) && !is.null(.registered$built)) {
      .bd_stop("publish", "this study's dataset was registered without a release (", .registered$built,
               "), so a build cannot replace it. Ask for it to be moved to this job's releases.")
    } else if (is.null(.registered_before)) {
      .status <- hvtiRutilities::register_data(.root, built = .release$file, catalog_dataset = DATASET_ID,
                                               release_id = .release$release_id)
      "Registered as the study dataset"
    } else if (identical(.registered_before, .release$release_id)) {
      "Already the study dataset: nothing to do"
    } else {
      .status <- hvtiRutilities::adopt_data_update(hvtiRutilities::study_config(.root), release_id = .release$release_id)
      "Adopted as the study dataset"
    }
  }, error = function(e) {
    if (startsWith(conditionMessage(e), "bd: ")) stop(e)
    .bd_stop("publish", "registering the release stopped: ", conditionMessage(e))
  })
}
```

## Report

```{r}
#| label: report-source
knitr::kable(data.frame(
  Item = c("Mode", "Master snapshot", "Master SHA-256", "Rehashed this render", "Master parent release",
           "Rows in the dataset", "Patients", "Columns", "Study dataset before", "Study dataset after", "Registration"),
  Value = c(if (PUBLISH) "Published" else "Draft", basename(.master$file), .master$sha256,
            if (.master$verified) "yes" else "no", as.character(.master$parent_release), nrow(d),
            length(unique(d[[ID]])), ncol(d),
            if (is.null(.registered_before)) "none" else .registered_before,
            if (is.null(.release)) "unchanged" else .release$release_id, .register_step)
))
```

### Who was excluded, and why

```{r}
#| label: report-attrition
knitr::kable(.cut$attrition, col.names = c("Step", "Reason", "Rows before", "Removed", "Condition missing",
                                           "Rows after", "Patients after"))
```

### Columns

```{r}
#| label: report-columns
# Aggregates only: the type, missing count and range of each column. The ID and
# KEY columns get no range, since a range of identifiers is two identifiers.
.no_range <- c(ID, KEY)
knitr::kable(data.frame(
  Column = names(d),
  Type = vapply(d, function(x) class(x)[[1L]], ""),
  Missing = vapply(d, function(x) sum(is.na(x)), 0L),
  Range = vapply(names(d), function(col) {
    x <- d[[col]]
    if (col %in% .no_range || !is.numeric(x) || all(is.na(x))) "" else paste(format(range(x, na.rm = TRUE), digits = 4),
                                                                              collapse = " to ")
  }, ""),
  row.names = NULL
))
```
````

Note for the implementer: the test helper's `hazard_run()` finds a chunk by its `#| label:` line and ends it at the next line that is exactly three backticks, so keep every chunk's closing fence on its own line, with no trailing space.

- [ ] **Step 6: Mark the ledger row shipped and regenerate the roadmap**

Run:

```bash
python3 - <<'EOF'
import json
p = "inst/extdata/templates.json"
d = json.load(open(p))
for r in d["templates"]:
    if r["prefix"] == "bd" and r["qualifier"] is None:
        r["status"] = "shipped"
        r["blocked_on"] = None
        r["spec"] = "dev/specs/2026-10-02-bd-build-job-design.md"
        r["description"] = ("Cuts a study's dataset from a master snapshot: cohort list, exclusions with attrition "
                            "and derived variables, then a dated release registered as the study dataset.")
        r["uses"] = ["hvtiRdatabuild::publish_dataset", "hvtiRutilities::register_data",
                     "hvtiRutilities::adopt_data_update"]
with open(p, "w") as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
    f.write("\n")
EOF
git diff --stat inst/extdata/templates.json
python3 dev/specs/artifacts/roadmap_render.py
for s in dev/specs/artifacts/check-*.py; do python3 "$s" || exit 1; done
```

Expected: the diff touches only the `bd` row. If `--stat` shows the whole file changed, the dump's formatting differs from the file's: restore it with `git checkout inst/extdata/templates.json` and make the same five edits by hand. Then all three checks print their agreement lines.

- [ ] **Step 7: Add the README row**

In `inst/templates/README.md`, add as the FIRST row of the table under `## What is here`:

```
| `00_datasets/bd.qmd` | study dataset build: master snapshot to a registered release | `00_datasets/` or `datasets/` |
```

- [ ] **Step 8: Run the chunk tests and the suite**

Run: `Rscript -e 'devtools::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-bd-template.R")'`
Expected: PASS.

Run: `Rscript -e 'devtools::test()'`
Expected: no failures. Read the summary line: `SKIP` must not rise above what `main` reports locally, and `WARN` must not rise (`test-rf-templates.R` carries known local warnings; compare against a `main` run rather than expecting 0).

- [ ] **Step 9: Lint**

Run: `Rscript -e 'lintr::lint_package()'`
Expected: no lints.

- [ ] **Step 10: Commit**

```bash
git add inst/templates/00_datasets/bd.qmd tests/testthat/helper-bd.R tests/testthat/test-bd-template.R .lintr DESCRIPTION \
  inst/extdata/templates.json inst/templates/README.md dev/specs/
git commit -m "bd: the 00_datasets build job template (#223)"
```

`dev/specs/` is in the add because `roadmap_render.py` rewrites the roadmap document there.

---

### Task 3: end to end, through Quarto, and as a script

**Files:**
- Create: `tests/testthat/test-bd-e2e.R`

**Interfaces:**
- Consumes: `bd_skip()`, `bd_master()`, `bd_study()`, `bd_job()` from `helper-bd.R`; `hazard_env(root)` and `hazard_run()` from `helper-hazard.R`; the template's settings lines from Task 2.
- Produces: nothing later tasks use.

- [ ] **Step 1: Write the end-to-end tests**

Create `tests/testthat/test-bd-e2e.R`:

```r
bd_quarto_skip <- function() {
  bd_skip()
  testthat::skip_if_not_installed("quarto")
  testthat::skip_if_not(quarto::quarto_available())
}

bd_edits <- function(m, publish, exclude = "list(age < 40 ~ \"Under 40\", ccfid == \"PT00007\" ~ \"Withdrew consent\")") {
  list(
    "^MASTER <- " = paste0("MASTER <- \"", m$parquet, "\""),
    "^KEEP <- " = "KEEP <- c(\"age\", \"iv_dead\", \"dead\", \"dt_surg\")",
    "^EXCLUDE <- " = paste0("EXCLUDE <- ", exclude),
    "^PUBLISH <- " = paste0("PUBLISH <- ", publish)
  )
}

bd_render <- function(job) {
  quarto::quarto_render(job, execute_dir = dirname(job), quiet = TRUE)
  paste(readLines(sub("[.]qmd$", ".html", job), warn = FALSE), collapse = "\n")
}

bd_catalog_releases <- function(root) {
  cat <- yaml::read_yaml(file.path(hvtiRutilities::study_dir("datasets", root), "dataset-catalog.yml"))
  unlist(lapply(cat$datasets, function(ds) vapply(ds$releases, function(r) r$release_id, "")))
}

test_that("bd publishes and registers a release, and ac reads it", {
  bd_quarto_skip()
  m <- bd_master()
  root <- bd_study()
  job <- bd_job(root, bd_edits(m, publish = "TRUE"))
  html <- bd_render(job)

  cfg <- hvtiRutilities::study_config(root)
  expect_match(cfg$release$release_id, "^study_cohort-[0-9]{8}-r1$")
  status <- hvtiRutilities::verify_manifest(file.path(root, "manifest.yaml"))
  expect_true(all(status$status == "OK"))

  # No identifier anywhere in the report: not the master's IDs, not its MRNs,
  # and not the one an EXCLUDE rule names in the job's source.
  ids <- c(m$data$ccfid, m$data$mrn)
  expect_false(any(vapply(ids, grepl, logical(1L), x = html, fixed = TRUE)))
  expect_match(html, "Withdrew consent", fixed = TRUE)

  # ac, chunk by chunk as the hazard chain tests run it, reads the release.
  release <- readRDS(file.path(hvtiRutilities::study_dir("datasets", root), cfg$built))
  cc <- hvtiRutilities::cohort_counts(release, event = "dead", time = "iv_dead")
  env <- hazard_env(root)
  suppressWarnings(utils::capture.output({
    hazard_run("ac", c("set", "edit-study-choices"), env,
               list(EXPECTED = list(n = cc$n, n_events = cc$n_events, n_censored = cc$n_censored)))
    hazard_run("ac", c("data", "cohort", "km-helpers", "km-overall"), env)
  }))
  expect_identical(nrow(env$d), nrow(release))
})

test_that("a second publishing render with a changed rule adopts -r2, and a draft render publishes nothing", {
  bd_quarto_skip()
  m <- bd_master()
  root <- bd_study()
  job <- bd_job(root, bd_edits(m, publish = "TRUE"))
  bd_render(job)
  first <- hvtiRutilities::study_config(root)$release$release_id

  # The same job rendered again mints nothing.
  bd_render(job)
  expect_identical(hvtiRutilities::study_config(root)$release$release_id, first)
  expect_length(bd_catalog_releases(root), 1L)

  lines <- readLines(job, warn = FALSE)
  lines[grep("^EXCLUDE <- ", lines)] <- "EXCLUDE <- list(age < 50 ~ \"Under 50\")"
  writeLines(lines, job)
  html <- bd_render(job)
  second <- hvtiRutilities::study_config(root)$release$release_id
  expect_match(second, "-r2$")
  expect_match(html, "Adopted as the study dataset", fixed = TRUE)
  expect_true(all(hvtiRutilities::verify_manifest(file.path(root, "manifest.yaml"))$status == "OK"))

  lines[grep("^EXCLUDE <- ", lines)] <- "EXCLUDE <- list(age < 60 ~ \"Under 60\")"
  lines[grep("^PUBLISH <- ", lines)] <- "PUBLISH <- FALSE"
  writeLines(lines, job)
  html <- bd_render(job)
  expect_match(html, "Draft only: nothing published", fixed = TRUE)
  expect_length(bd_catalog_releases(root), 2L)
  expect_identical(hvtiRutilities::study_config(root)$release$release_id, second)
})

test_that("the purled job runs as a script and makes the release the render made", {
  bd_quarto_skip()
  m <- bd_master()
  root <- bd_study()
  job <- bd_job(root, bd_edits(m, publish = "TRUE"))
  bd_render(job)
  rendered <- hvtiRutilities::study_config(root)$release$release_id

  script <- withr::local_tempfile(fileext = ".R")
  knitr::purl(job, output = script, documentation = 0L, quiet = TRUE)
  withr::with_dir(dirname(job), utils::capture.output(source(script, local = new.env(parent = globalenv()))))
  expect_identical(hvtiRutilities::study_config(root)$release$release_id, rendered)
  expect_length(bd_catalog_releases(root), 1L)
})
```

The catalog's YAML layout (`datasets` then `releases` then `release_id`) is read in `bd_catalog_releases()`. Before running, confirm it against a real catalog: `Rscript -e 'str(yaml::read_yaml("<root>/00_datasets/dataset-catalog.yml"), max.level = 4)'` on a study from the Task 2 tests, and adjust the two `lapply`/`vapply` lines to the actual field names if they differ.

- [ ] **Step 2: Run them**

Run: `Rscript -e 'devtools::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-bd-e2e.R")'`
Expected: PASS. If the purl test fails because a rerun with an unchanged cohort produced different bytes, the cause is `saveRDS()` output changing between sessions; do not loosen the assertion. Report it, because it breaks the idempotency the spec relies on.

- [ ] **Step 3: Mutation check**

Prove the HTML test can fail. Temporarily change the template's `execute:` block to `echo: true`, rerun the first test, and confirm it FAILS on the ID grep (the source of the `EXCLUDE` line names `PT00007`). Restore `echo: false` and confirm it passes.

Run: `git diff --stat inst/templates/00_datasets/bd.qmd`
Expected: no diff after restoring.

- [ ] **Step 4: Commit**

```bash
git add tests/testthat/test-bd-e2e.R
git commit -m "bd: end-to-end tests: publish, adopt, draft, report free of IDs, ac on the release, purled script"
```

---

### Task 4: NEWS, full gates, and the PR

**Files:**
- Modify: `NEWS.md`

- [ ] **Step 1: Add the NEWS entry**

Under the existing `# hvtiRtemplates (unreleased)` heading at the top of `NEWS.md`, add as the first bullet:

```markdown
* New template `00_datasets/bd.qmd`, the first at the `00_datasets` level: a build job that cuts a study's dataset
  from a master snapshot, applies a cohort list and ordered exclusion rules (`condition ~ "Reason"`, where a missing
  condition is not excluded and is counted), derives the study's own variables, writes a draft, and with
  `PUBLISH <- TRUE` publishes a dated release with `hvtiRdatabuild::publish_dataset()` and registers it, or adopts it
  when an older release is registered. Its report shows counts and no code, so a rule naming a patient stays out of
  the HTML. New `build_cohort()` carries the cohort and attrition step (#223).
```

- [ ] **Step 2: Run the full gates**

Run: `Rscript -e 'devtools::document()' && git status --short man NAMESPACE`
Expected: no changes (Task 1 committed them).

Run: `Rscript -e 'devtools::check()'`
Expected: 0 errors, 0 warnings, 0 notes. In the test section of the log, read `SKIP` and `WARN`: neither may be higher than `main`'s.

Run: `Rscript -e 'lintr::lint_package()'` and `for s in dev/specs/artifacts/check-*.py; do python3 "$s" || exit 1; done`
Expected: no lints; three agreement lines.

The manual build runs only after merge (`check-manual.yaml`). `build_cohort.Rd` uses only `\code{}`, `\strong{}` and `\itemize{}`, so no PDF-only failure is expected; if you added any `\eqn{}` or non-ASCII text, run `R CMD Rd2pdf .` locally first.

- [ ] **Step 3: Run a local code review**

Run `/code-review` on the branch's diff against `origin/main` and fix what it confirms. The PR body says it stood in for the Copilot review.

- [ ] **Step 4: Commit, push, open the PR**

```bash
git add NEWS.md
git commit -m "NEWS: the bd build job (#223)"
git push -u origin feat/bd-build-job
gh pr create --base main --title "bd: the 00_datasets build job (#223)" --body-file <file written for the PR>
```

The PR body must say:
- what ships (template, `build_cohort()`, tests), with `Closes #223` left OFF: the stat programmers' review is an acceptance criterion and a merge gate;
- the two merge gates still open: (1) Moses, Linda and Beth review `bd.qmd` line by line; (2) the real-size gate below, with its numbers filled in;
- that a local `/code-review` stood in for Copilot;
- the `SKIP`/`WARN` lines from the check log.

---

### Task 5 (manual, before merge): the real-size gate

Not code, and not run in CI: it reads the real master, on Workbench, inside a real study folder.

- [ ] **Step 1:** In a study folder on Workbench with hvtiRtemplates installed from the PR branch, scaffold `add_job("bd", "study", "build")`. Set `MASTER` to the current cardiac master parquet snapshot, `KEEP` to a realistic list (30 to 60 columns), one realistic `EXCLUDE`, and `PUBLISH <- FALSE`.
- [ ] **Step 2:** Render it under `/usr/bin/time -l quarto render <job>.qmd` (macOS) or `/usr/bin/time -v` (Linux). Record wall time and maximum resident set size.
- [ ] **Step 3:** Put both numbers in the PR body, with the master's row count and the number of columns read. **No data value.** If peak memory exceeds what Workbench sessions are given, or the render takes longer than the group will wait, stop: pushing the cohort list or a pre-filter down to arrow (spec section 9) becomes a task before merge.
- [ ] **Step 4:** Delete the draft files the trial wrote: `00_datasets/draft-<DATASET_ID>.rds` and `.build.yml`.

---

## Follow-ups (not tasks in this plan)

- Reopen the new-study guide (`vignettes/new-study.qmd`) so it starts from a `bd` job. File an issue when the PR merges.
- A gallery entry for `bd` (`dev/gallery/family-*.R`): the gallery opts in per family, so its absence breaks nothing.
- `#223` closes after the stat programmers' review, not on merge.
