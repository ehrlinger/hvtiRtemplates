# Template data contract: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every hvtiRtemplates template chooses its data, identifies its patients and names its outcome the same way, through one exported function, `read_job_data()`, as `dev/specs/2026-09-29-template-data-contract-design.md` specifies.

**Architecture:** `read_job_data()` (new, `R/job-data.R`) reads the registered dataset or analysis set through the existing provenance readers, resolves the patient ID, drops `MRN`/`eMRN`, applies `WHERE` with `dplyr::filter()` rules, checks `KEY`, and returns the data, a printable record, and the provenance record. Templates call it from a chunk named `data`; the record also rides in a new optional `selection` slot of the hand-off lineage so downstream jobs can check against it. Families convert one PR at a time, each shrinking a contract test's pending list.

**Tech Stack:** R (package hvtiRtemplates, Rd-markup roxygen), testthat edition 3, rlang (`eval_tidy`), Quarto templates under `inst/templates/`.

## Global Constraints

- Roxygen here is **Rd markup, not markdown**: `\code{}`, `\strong{}`, `\itemize{}`, `\link{}`. No backticks or `**` in roxygen.
- Lines up to **135** characters (`.lintr`). `lintr::lint_package()` must report 0; CI's lintr also flags unqualified calls inside helper functions, so qualify `testthat::` and package calls in helpers.
- Every template keeps exactly one `^SUBJECT\s+<- ` and one `^TYPE\s+<- ` line, and every study-specific line is marked `EDIT:`.
- A chunk is labelled `edit-` exactly when it holds an `EDIT:` marker (test in `test-templates.R`). The new `data` chunk holds **no** `EDIT:` marker.
- Shared settings and defaults, verbatim from the spec: `DATASET <- "study"`, `ANALYSIS_SET <- NULL`, `WHERE <- NULL`, `ID <- "ccfid"`, `KEY <- ID`. Family names: `TIME` (default `"iv_dead"`), `EVENT` (default `"dead"`), `OUTCOME`, `TREATMENT`, `PREDICTORS`.
- Identifiers dropped at read: columns named exactly `MRN` or `eMRN`, ignoring case, unless serving as the ID. No other names.
- ID fallback when `ID` is the default `"ccfid"` and absent: `MRN`, then `eMRN`; otherwise stop naming `ID` in `edit-study-choices`.
- Messages never print an ID, key or date value; only counts.
- US spelling (`tools/check-us-spelling.sh`); no em dashes in prose.
- No version bump in any PR: NEWS entries go under `# hvtiRtemplates (unreleased)`. `dev/` ships nothing.
- Never push to `main`; one branch and PR per task group below. Run `/code-review` (or a careful self-review) before each PR and say so in the body.
- Test runs that render templates use hvtiRutilities from GitHub `main` (as CI does). Locally: install it into a scratch library and set `R_LIBS` to it.

---

## File structure

| File | Responsibility |
|---|---|
| `R/job-data.R` (create) | `read_job_data()` (exported) and its internal steps: `.check_job_settings()`, `.read_job_source()`, `.resolve_job_id()`, `.drop_identifiers()`, `.apply_where()`, `.check_job_key()`, `.job_record()` |
| `R/study-root.R` (create) | `.find_study_root()`: `hvtiRutilities::study_root()` with the new-analyst message |
| `R/provenance.R` (modify) | optional `selection` slot in `.handoff_lineage()`, `.attach_handoff_lineage()`, `.validate_handoff_lineage()`; `.check_upstream_selection()` |
| `DESCRIPTION` (modify) | `rlang` in Imports |
| `NAMESPACE`, `man/read_job_data.Rd` (generated) | `devtools::document()` |
| `tests/testthat/test-job-data.R` (create) | unit tests for `read_job_data()` and its steps |
| `tests/testthat/test-data-contract.R` (create) | the contract test over every template, with a pending-families list |
| `tests/testthat/helper-migration.R`, `helper-lm.R`, `helper-rf.R`, `test-template-provenance.R` (modify) | fixtures gain a `ccfid` column |
| `inst/templates/**.qmd` (modify, per family) | shared settings, `data` chunk, vocabulary |
| `R/migrate-*.R` (modify, per family) | write the new names |
| `dev/gallery/family-*.R` (modify, last) | drop data-path workarounds |

---

### Task 1: `read_job_data()` selection steps on a data frame

**Files:**
- Create: `R/job-data.R`
- Modify: `DESCRIPTION` (Imports: add `rlang`)
- Test: `tests/testthat/test-job-data.R`

**Interfaces:**
- Produces (internal, used by Task 2):
  - `.resolve_job_id(d, id)` returns `list(id = <character(1)>, fallback = <logical(1)>)`
  - `.drop_identifiers(d, id)` returns `list(data = <data.frame>, dropped = <character>)`
  - `.apply_where(d, where, env = parent.frame())` returns `list(data = <data.frame>, steps = <data.frame: condition, removed, missing>)`; `env` is where `.env$` names are looked up
  - `.check_job_key(d, key, id)` returns `list(rows = <int>, patients = <int>)` or stops

- [ ] **Step 1: Add rlang to Imports**

In `DESCRIPTION`, under `Imports:`, add a line `    rlang,` in alphabetical order (after `ps,`, before `stats,`).

- [ ] **Step 2: Write the failing tests**

Create `tests/testthat/test-job-data.R`:

```r
# read_job_data() steps on plain data frames. No identifier value appears in
# any message: the tests assert counts only.

d0 <- data.frame(
  ccfid = 1:6, MRN = 101:106, eMRN = 201:206, pt_mrn = 1:6,
  age = c(15, 40, 55, NA, 70, 80), hx_chf = c(0L, 1L, 1L, 0L, 1L, NA)
)

test_that("the ID is ccfid when present, else MRN, then eMRN, else a stop", {
  expect_identical(hvtiRtemplates:::.resolve_job_id(d0, "ccfid"), list(id = "ccfid", fallback = FALSE))
  expect_identical(hvtiRtemplates:::.resolve_job_id(d0[-1], "ccfid"), list(id = "MRN", fallback = TRUE))
  expect_identical(hvtiRtemplates:::.resolve_job_id(d0[c("eMRN", "age")], "ccfid"), list(id = "eMRN", fallback = TRUE))
  expect_error(hvtiRtemplates:::.resolve_job_id(d0["age"], "ccfid"), "ID in edit-study-choices")
  # A non-default ID never falls back: the analyst named it.
  expect_error(hvtiRtemplates:::.resolve_job_id(d0, "randid"), "randid")
})

test_that("MRN and eMRN are dropped unless one is the ID; no other name is", {
  out <- hvtiRtemplates:::.drop_identifiers(d0, "ccfid")
  expect_setequal(out$dropped, c("MRN", "eMRN"))
  expect_true("pt_mrn" %in% names(out$data))
  expect_false(any(c("MRN", "eMRN") %in% names(out$data)))
  kept <- hvtiRtemplates:::.drop_identifiers(d0[-1], "MRN")
  expect_identical(kept$dropped, "eMRN")
  expect_true("MRN" %in% names(kept$data))
  lower <- d0; names(lower)[2] <- "mrn"
  expect_true("mrn" %in% hvtiRtemplates:::.drop_identifiers(lower, "ccfid")$dropped)
})

test_that("WHERE follows filter(): NA rows are dropped and counted, conditions apply in order", {
  none <- hvtiRtemplates:::.apply_where(d0, NULL)
  expect_identical(nrow(none$data), 6L)
  expect_identical(nrow(none$steps), 0L)
  one <- hvtiRtemplates:::.apply_where(d0, quote(age >= 18))
  expect_identical(one$data$ccfid, c(2L, 3L, 5L, 6L))
  expect_identical(one$steps$removed, 2L)
  expect_identical(one$steps$missing, 1L)
  two <- hvtiRtemplates:::.apply_where(d0, rlang::exprs(age >= 18, hx_chf == 1))
  expect_identical(two$data$ccfid, c(2L, 3L, 5L))
  expect_identical(two$steps$condition, c("age >= 18", "hx_chf == 1"))
  expect_identical(two$steps$removed, c(2L, 1L))
  expect_identical(two$steps$missing, c(1L, 1L))
  min_age <- 50
  expect_identical(hvtiRtemplates:::.apply_where(d0, quote(age >= .env$min_age))$data$ccfid, c(3L, 5L, 6L))
  expect_error(hvtiRtemplates:::.apply_where(d0, "age >= 18"), "WHERE must be NULL")
  expect_error(hvtiRtemplates:::.apply_where(d0, quote(age + 1)), "TRUE or FALSE")
})

test_that("rows must be unique on KEY; patients are counted on ID", {
  expect_identical(hvtiRtemplates:::.check_job_key(d0, "ccfid", "ccfid"), list(rows = 6L, patients = 6L))
  long <- data.frame(ccfid = c(1L, 1L, 2L), iv_echo = c(0.1, 1.2, 0.3))
  expect_identical(hvtiRtemplates:::.check_job_key(long, c("ccfid", "iv_echo"), "ccfid"), list(rows = 3L, patients = 2L))
  expect_error(hvtiRtemplates:::.check_job_key(long, "ccfid", "ccfid"), "1 value of KEY repeats")
  err <- tryCatch(hvtiRtemplates:::.check_job_key(long, "ccfid", "ccfid"), error = conditionMessage)
  expect_false(grepl("\\b1\\b.*\\b1\\b.*\\b2\\b", err))
  expect_error(hvtiRtemplates:::.check_job_key(long, "visit", "ccfid"), "KEY names a column")
})
```

- [ ] **Step 3: Run to verify they fail**

Run: `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-job-data.R")'`
Expected: FAIL, "could not find function .resolve_job_id".

- [ ] **Step 4: Write the implementation**

Create `R/job-data.R`:

```r
# The shared data step every template calls. See
# dev/specs/2026-09-29-template-data-contract-design.md.

.job_identifier_names <- c("mrn", "emrn")

.resolve_job_id <- function(d, id) {
  if (!is.character(id) || length(id) != 1L || is.na(id) || !nzchar(id)) {
    stop("ID must name one column, such as \"ccfid\".", call. = FALSE)
  }
  if (id %in% names(d)) return(list(id = id, fallback = FALSE))
  if (identical(id, "ccfid")) {
    for (candidate in c("mrn", "emrn")) {
      hit <- names(d)[tolower(names(d)) == candidate]
      if (length(hit)) return(list(id = hit[[1L]], fallback = TRUE))
    }
    stop("This dataset has no ccfid, MRN or eMRN column. Name the patient identifier in ID ",
         "in edit-study-choices, for example ID <- \"randid\".", call. = FALSE)
  }
  stop("ID names a column this dataset does not have: ", id,
       ". Change ID in edit-study-choices.", call. = FALSE)
}

.drop_identifiers <- function(d, id) {
  drop <- names(d)[tolower(names(d)) %in% .job_identifier_names & names(d) != id]
  list(data = d[setdiff(names(d), drop)], dropped = drop)
}

.where_conditions <- function(where) {
  if (is.null(where)) return(list())
  if (is.call(where) || is.name(where)) return(list(where))
  if (is.list(where) && length(where) && all(vapply(where, function(x) is.call(x) || is.name(x), logical(1L)))) {
    return(unname(where))
  }
  stop("WHERE must be NULL, one condition from quote(), or a list from rlang::exprs().", call. = FALSE)
}

.apply_where <- function(d, where, env = parent.frame()) {
  conditions <- .where_conditions(where)
  steps <- data.frame(condition = character(), removed = integer(), missing = integer())
  for (cond in conditions) {
    keep <- rlang::eval_tidy(cond, data = d, env = env)
    label <- paste(deparse(cond, width.cutoff = 500L), collapse = " ")
    if (!is.logical(keep) || !length(keep) %in% c(1L, nrow(d))) {
      stop("Each WHERE condition must give TRUE or FALSE for every row: ", label, call. = FALSE)
    }
    keep <- rep_len(keep, nrow(d))
    missing <- sum(is.na(keep))
    kept <- !is.na(keep) & keep
    steps[nrow(steps) + 1L, ] <- list(label, sum(!kept), missing)
    d <- d[kept, , drop = FALSE]
  }
  rownames(d) <- NULL
  list(data = d, steps = steps)
}

.check_job_key <- function(d, key, id) {
  if (!is.character(key) || !length(key) || anyNA(key)) {
    stop("KEY must name one or more columns, such as ID or c(ID, \"iv_echo\").", call. = FALSE)
  }
  absent <- setdiff(key, names(d))
  if (length(absent)) {
    stop("KEY names a column this dataset does not have: ", paste(absent, collapse = ", "),
         ". Change KEY in edit-study-choices.", call. = FALSE)
  }
  repeats <- sum(duplicated(d[key]))
  if (repeats) {
    stop(repeats, if (repeats == 1L) " value of KEY repeats" else " values of KEY repeat",
         ". Each row must be unique on KEY; for repeated measures add the visit time or ",
         "date, for example KEY <- c(ID, \"iv_echo\").", call. = FALSE)
  }
  list(rows = nrow(d), patients = length(unique(d[[id]])))
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-job-data.R")'`
Expected: PASS (4 tests, 0 failures).

- [ ] **Step 6: Commit**

```bash
git add DESCRIPTION R/job-data.R tests/testthat/test-job-data.R
git commit -m "feat: read_job_data() steps: ID fallback, identifier drop, WHERE, KEY"
```

---

### Task 2: `read_job_data()` itself, its record, and the missing-study message

**Files:**
- Modify: `R/job-data.R`
- Create: `R/study-root.R`
- Generate: `NAMESPACE`, `man/read_job_data.Rd`
- Test: `tests/testthat/test-job-data.R`

**Interfaces:**
- Consumes: Task 1's `.resolve_job_id()`, `.drop_identifiers()`, `.apply_where()`, `.check_job_key()`; existing `.provenance_read(dataset, cfg, reader, role)` and `.provenance_file_read(dataset, path, cfg, reader, role)` in `R/provenance.R`.
- Produces:
  - `read_job_data(cfg, dataset = "study", analysis_set = NULL, where = NULL, id = "ccfid", key = id)` (exported) returns `list(data, record, provenance)`. `record` is a `data.frame(step, value)` for printing, with `attr(record, "selection")` = `list(dataset, analysis_set, where = <character>, id = <resolved>, key = <resolved>, rows, patients)`.
  - `.find_study_root(start)` returns the study root or stops with the new-analyst message.

- [ ] **Step 1: Write the failing tests** (append to `tests/testthat/test-job-data.R`)

```r
job_study <- function(data, .local_envir = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = .local_envir)
  suppressMessages(hvtiRutilities::study_setup(root, "Job data", 1L, adopt = TRUE))
  utils::write.csv(data, file.path(hvtiRutilities::study_dir("datasets", root), "built.csv"), row.names = FALSE)
  suppressMessages(hvtiRutilities::register_data(root, "built.csv"))
  hvtiRutilities::study_config(start = root)
}

test_that("read_job_data() reads, selects and records what it did", {
  cfg <- job_study(d0)
  out <- read_job_data(cfg, where = rlang::exprs(age >= 18, hx_chf == 1))
  expect_identical(out$data$ccfid, c(2L, 3L, 5L))
  expect_false(any(c("MRN", "eMRN") %in% names(out$data)))
  expect_s3_class(out$record, "data.frame")
  expect_identical(names(out$record), c("step", "value"))
  expect_match(paste(out$record$value, collapse = " "), "3 rows on 3 patients")
  sel <- attr(out$record, "selection")
  expect_identical(sel$id, "ccfid")
  expect_identical(sel$key, "ccfid")
  expect_identical(sel$where, c("age >= 18", "hx_chf == 1"))
  expect_identical(out$provenance$dataset, "study")
  # No identifier value reaches the record.
  expect_false(any(grepl("\\b10[1-6]\\b|\\b20[1-6]\\b", out$record$value)))
})

test_that("KEY follows the ID when the ID falls back", {
  cfg <- job_study(d0[-1])
  out <- read_job_data(cfg)
  expect_identical(attr(out$record, "selection")$id, "MRN")
  expect_identical(attr(out$record, "selection")$key, "MRN")
  expect_match(paste(out$record$value, collapse = " "), "fell back to MRN")
})

test_that("an analysis set with another dataset is refused", {
  cfg <- job_study(d0)
  expect_error(read_job_data(cfg, dataset = "other", analysis_set = "eda"), "written from the study dataset")
})

test_that("a job outside a study is told to run study_setup()", {
  expect_error(hvtiRtemplates:::.find_study_root(withr::local_tempdir()), "study_setup")
})
```

- [ ] **Step 2: Run to verify they fail**

Run: `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-job-data.R")'`
Expected: FAIL, "could not find function read_job_data".

- [ ] **Step 3: Implement** (append to `R/job-data.R`)

```r
#' Read a job's data, keep its rows, and record what was done
#'
#' @description The shared data step of every analysis template. It reads a
#'   registered dataset (or an hvtiRdatabuild analysis set), resolves the
#'   patient identifier, drops the medical record number columns, keeps the rows
#'   \code{where} selects and checks that rows are unique on \code{key}.
#'
#' @param cfg Study configuration, from \code{\link[hvtiRutilities]{study_config}}.
#' @param dataset Name of a dataset registered in \code{_study.yml};
#'   \code{"study"} is the built dataset.
#' @param analysis_set Name of an analysis set written by
#'   \code{hvtiRdatabuild::write_analysis_set()}, or \code{NULL} to read
#'   \code{dataset} whole. Analysis sets derive from \code{"study"} only.
#' @param where Rows to keep: \code{NULL}, one condition from \code{quote()}, or
#'   a list from \code{rlang::exprs()}, all of which must hold. Conditions follow
#'   \code{dplyr::filter()}: a row where a condition is \code{NA} is dropped.
#' @param id The patient identifier column. When it is the default
#'   \code{"ccfid"} and absent, \code{MRN} and then \code{eMRN} are used.
#' @param key Columns that make a row unique; defaults to \code{id}, one row
#'   per patient. Add a visit time or date for repeated measures.
#'
#' @details Columns named \code{MRN} or \code{eMRN} (ignoring case) are
#'   dropped unless one is the identifier. No identifier, key or date value is
#'   ever printed; the record holds counts.
#'
#' @return A list: \code{data}, the selected rows; \code{record}, a data frame
#'   of steps and values to print, carrying the settings used in its
#'   \code{"selection"} attribute; \code{provenance}, the read's provenance
#'   record.
#' @export
read_job_data <- function(cfg, dataset = "study", analysis_set = NULL, where = NULL,
                          id = "ccfid", key = id) {
  if (!is.character(dataset) || length(dataset) != 1L || is.na(dataset) || !nzchar(dataset)) {
    stop("DATASET must name one dataset registered in _study.yml, such as \"study\".", call. = FALSE)
  }
  if (!is.null(analysis_set) && !identical(dataset, "study")) {
    stop("An analysis set is written from the study dataset, not `", dataset,
         "`. Set ANALYSIS_SET <- NULL to read `", dataset, "` whole.", call. = FALSE)
  }
  read <- .read_job_source(cfg, dataset, analysis_set)
  d <- read$value
  rows_read <- nrow(d)
  who <- .resolve_job_id(d, id)
  key <- replace(key, key == id, who$id)
  ids <- .drop_identifiers(d, who$id)
  kept <- .apply_where(ids$data, where, env = parent.frame())
  counts <- .check_job_key(kept$data, key, who$id)
  record <- .job_record(read$source, rows_read, who, ids$dropped, kept$steps, counts)
  attr(record, "selection") <- list(
    dataset = dataset, analysis_set = analysis_set, where = kept$steps$condition,
    id = who$id, key = key, rows = counts$rows, patients = counts$patients
  )
  list(data = kept$data, record = record, provenance = read$record)
}

.read_job_source <- function(cfg, dataset, analysis_set) {
  if (is.null(analysis_set)) {
    read <- .provenance_read(dataset, cfg, function() hvtiRutilities::read_built(cfg = cfg, dataset = dataset))
    read$source <- paste0("dataset `", dataset, "` (", basename(hvtiRutilities::built_path(cfg = cfg, dataset = dataset)), ")")
    return(read)
  }
  if (!requireNamespace("hvtiRdatabuild", quietly = TRUE)) {
    stop("ANALYSIS_SET needs the hvtiRdatabuild package; install it or set ANALYSIS_SET <- NULL.", call. = FALSE)
  }
  path <- file.path(hvtiRutilities::study_dir("datasets", cfg$root), paste0(analysis_set, ".parquet"))
  read <- .provenance_file_read(
    paste0("analysis_set:", analysis_set), path, cfg,
    function() hvtiRdatabuild::read_analysis_set(analysis_set, cfg = cfg),
    role = paste0("analysis_set:", analysis_set)
  )
  read$source <- paste0("analysis set `", analysis_set, "` of the study dataset")
  read
}

.job_record <- function(source, rows_read, who, dropped, steps, counts) {
  rows <- list(
    c("Source", source),
    c("Rows read", format(rows_read, big.mark = ",")),
    c("ID", if (who$fallback) paste0("`", who$id, "` (no ccfid; fell back to ", who$id, ")") else paste0("`", who$id, "`")),
    c("Identifiers dropped", if (length(dropped)) paste0("`", dropped, "`", collapse = ", ") else "none")
  )
  for (i in seq_len(nrow(steps))) {
    rows[[length(rows) + 1L]] <- c(
      paste0("`", steps$condition[[i]], "`"),
      paste0("removed ", steps$removed[[i]], if (steps$missing[[i]]) paste0(" (", steps$missing[[i]], " missing)") else "")
    )
  }
  rows[[length(rows) + 1L]] <- c("Rows kept", paste0(format(counts$rows, big.mark = ","), " rows on ",
                                                    format(counts$patients, big.mark = ","), " patients"))
  data.frame(step = vapply(rows, `[[`, "", 1L), value = vapply(rows, `[[`, "", 2L))
}
```

Create `R/study-root.R`:

```r
# The study root for a template's setup chunk, with a message a new analyst can
# act on. hvtiRutilities::study_root()'s own message points to a server-side
# recovery command, which is the wrong first step for a study never set up.
.find_study_root <- function(start) {
  tryCatch(hvtiRutilities::study_root(start), error = function(e) {
    stop("This job is not inside a set-up study (no _study.yml above it). Create one with ",
         "hvtiRutilities::study_setup(\"<study folder>\", ...), register its data with register_data(), ",
         "then scaffold jobs with add_job() or open_job() from inside it. If this study had a ",
         "_study.yml and lost it, recover it with study-setup --recover.", call. = FALSE)
  })
}
```

- [ ] **Step 4: Document, then run the tests**

Run: `Rscript -e 'devtools::document(); devtools::load_all(); testthat::test_file("tests/testthat/test-job-data.R")'`
Expected: `NAMESPACE` gains `export(read_job_data)`; `man/read_job_data.Rd` is written; tests PASS.

- [ ] **Step 5: Full suite, lint, check**

Run: `Rscript -e 'devtools::test(); lintr::lint_package(cache = FALSE)'`
Expected: `FAIL 0`; 0 lints.

- [ ] **Step 6: Commit**

```bash
git add R/job-data.R R/study-root.R NAMESPACE man/read_job_data.Rd tests/testthat/test-job-data.R
git commit -m "feat: read_job_data(), its record, and a missing-study message that names study_setup()"
```

---

### Task 3: the selection travels with hand-offs; downstream jobs check it

**Files:**
- Modify: `R/provenance.R` (`.handoff_lineage()` near line 589, `.attach_handoff_lineage()` near 596, `.validate_handoff_lineage()` near 602; the bootstrap reader's shape check near 657)
- Test: `tests/testthat/test-job-data.R`

**Interfaces:**
- Consumes: `attr(record, "selection")` from Task 2.
- Produces:
  - `.attach_handoff_lineage(object, data, artifacts = list(), analysis = NULL, cohort = NULL, selection = NULL)`; lineage names are `data, artifacts, analysis, cohort`, plus `selection` when given.
  - `.check_upstream_selection(upstream, settings)`: `upstream` is a lineage's `selection` (or `NULL`); `settings` is a named list of this job's `where`, `id`, `key` (and `time`, `event` where used). Stops, naming both values, when a setting is set and differs; returns `upstream` merged over unset settings.

- [ ] **Step 1: Write the failing tests** (append)

```r
test_that("a hand-off carries the selection, and older four-slot lineage still validates", {
  sel <- list(dataset = "study", analysis_set = NULL, where = "age >= 18", id = "ccfid", key = "ccfid",
              rows = 3L, patients = 3L)
  obj <- hvtiRtemplates:::.attach_handoff_lineage(list(), data = list(list(dataset = "study")), selection = sel)
  expect_identical(attr(obj, "hvti_provenance")$selection, sel)
  old <- hvtiRtemplates:::.attach_handoff_lineage(list(), data = list(list(dataset = "study")))
  expect_identical(names(attr(old, "hvti_provenance")), c("data", "artifacts", "analysis", "cohort"))
  expect_silent(hvtiRtemplates:::.validate_handoff_lineage(old, "x.rds", "hz"))
  expect_silent(hvtiRtemplates:::.validate_handoff_lineage(obj, "x.rds", "hz"))
})

test_that("a downstream job's settings must agree with its upstream selection", {
  up <- list(where = "age >= 18", id = "ccfid", key = "ccfid", time = "iv_dead", event = "dead")
  expect_identical(hvtiRtemplates:::.check_upstream_selection(up, list(where = NULL, id = NULL))$where, "age >= 18")
  expect_error(hvtiRtemplates:::.check_upstream_selection(up, list(where = "age >= 65")),
               "WHERE.*age >= 65.*age >= 18")
  expect_error(hvtiRtemplates:::.check_upstream_selection(up, list(event = "reop")), "EVENT")
  expect_identical(hvtiRtemplates:::.check_upstream_selection(NULL, list(id = "ccfid"))$id, "ccfid")
})
```

- [ ] **Step 2: Run to verify they fail**

Run: `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-job-data.R")'`
Expected: FAIL on the `selection` argument ("unused argument").

- [ ] **Step 3: Implement**

In `R/provenance.R`, replace `.handoff_lineage()` and `.attach_handoff_lineage()` with:

```r
.handoff_lineage <- function(data, artifacts = list(), analysis = NULL,
                             cohort = NULL, selection = NULL) {
  if (!is.list(data)) stop("Handoff lineage data must be a list of provenance records.", call. = FALSE)
  if (!is.list(artifacts)) stop("Handoff lineage artifacts must be a list of provenance records.", call. = FALSE)
  out <- list(data = data, artifacts = artifacts, analysis = analysis, cohort = cohort)
  if (!is.null(selection)) out$selection <- selection
  out
}

.attach_handoff_lineage <- function(object, data, artifacts = list(),
                                    analysis = NULL, cohort = NULL, selection = NULL) {
  attr(object, "hvti_provenance") <- .handoff_lineage(data, artifacts, analysis, cohort, selection)
  object
}
```

In `.validate_handoff_lineage()`, replace
`valid <- is.list(lineage) && identical(names(lineage), required) &&`
with
`valid <- is.list(lineage) && identical(setdiff(names(lineage), "selection"), required) &&`.

In the bootstrap reader (near line 657), replace
`identical(names(lineage), c("data", "artifacts", "analysis", "cohort")) &&`
with
`identical(setdiff(names(lineage), "selection"), c("data", "artifacts", "analysis", "cohort")) &&`.

Append to `R/job-data.R`:

```r
# A downstream job reuses its upstream job's selection. A setting the job sets
# itself must agree; one left NULL is taken from upstream.
.check_upstream_selection <- function(upstream, settings) {
  if (is.null(upstream)) return(settings)
  names_shown <- c(where = "WHERE", id = "ID", key = "KEY", time = "TIME", event = "EVENT")
  for (field in intersect(names(settings), names(upstream))) {
    mine <- settings[[field]]
    if (is.null(mine)) next
    if (is.call(mine) || is.list(mine)) mine <- .where_conditions(mine) |> vapply(function(x) paste(deparse(x), collapse = " "), "")
    if (!identical(as.character(mine), as.character(upstream[[field]]))) {
      stop(names_shown[[field]], " here (", paste(mine, collapse = ", "), ") differs from the upstream job's (",
           paste(upstream[[field]], collapse = ", "), "). Leave it NULL to use the upstream value, or rerun ",
           "the upstream job with the new value.", call. = FALSE)
    }
  }
  utils::modifyList(upstream, Filter(Negate(is.null), settings))
}
```

- [ ] **Step 4: Run the tests and the full suite**

Run: `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-job-data.R"); devtools::test()'`
Expected: PASS; full suite `FAIL 0` (existing four-slot hand-offs still validate).

- [ ] **Step 5: Commit**

```bash
git add R/provenance.R R/job-data.R tests/testthat/test-job-data.R
git commit -m "feat: hand-offs carry the job's selection; downstream jobs check it"
```

---

### Task 4: the contract test and `ccfid` in the fixtures

**Files:**
- Create: `tests/testthat/test-data-contract.R`
- Modify: `tests/testthat/helper-migration.R:6-13` (`migration_study_fixture()` data), `tests/testthat/test-template-provenance.R:595` (`make_provenance_study()` data), and the fixture data in `helper-lm.R` and `helper-rf.R`

**Interfaces:**
- Produces: `pending_contract_families`, a character vector in `test-data-contract.R` listing template names not yet converted; each family task removes its names.

- [ ] **Step 1: Add `ccfid` to every fixture**

In `migration_study_fixture()`, add `ccfid = 1000L + i,` as the first column of `built`. In `make_provenance_study()`, change `data.frame(id = 1:3, ...)` to `data.frame(ccfid = 1:3, id = 1:3, ...)`. In `helper-lm.R` and `helper-rf.R`, add `ccfid = seq_len(n)` (or `1000L + seq_len(n)`, whatever the row index is called there) as the first column of each fixture data frame. Run `Rscript -e 'devtools::test()'`: expected `FAIL 0` (nothing reads `ccfid` yet).

- [ ] **Step 2: Write the contract test**

Create `tests/testthat/test-data-contract.R`:

```r
# Every template takes its data the same way:
# dev/specs/2026-09-29-template-data-contract-design.md. Families not yet
# converted are listed here; each family's conversion removes its names, and
# the list is empty when the work is done.
pending_contract_families <- template_list()$name

template_chunk <- function(src, label) {
  at <- match(paste0("#| label: ", label), src)
  if (is.na(at)) return(NULL)
  end <- at + match("```", src[-seq_len(at)])
  src[(at + 1L):(end - 1L)]
}

# Downstream templates take the selection their upstream job recorded: WHERE,
# ID and KEY default to NULL ("take the upstream value") and their data chunk
# checks it. hm, hp and hs also read data; the explain jobs and the bootstrap
# reports read a saved forest or bag, so they have no DATASET or ANALYSIS_SET.
downstream_templates <- c("hm", "hp", "hs", "rfs-explain", "rfc-explain", "rfr-explain",
                          "bl", "br", "bc", "bh")
reads_data <- function(name) !name %in% c("rfs-explain", "rfc-explain", "rfr-explain", "bl", "br", "bc", "bh")

expected_defaults <- function(name) {
  if (name %in% downstream_templates) {
    out <- c(WHERE = "WHERE <- NULL", ID = "ID <- NULL", KEY = "KEY <- NULL")
  } else {
    out <- c(WHERE = "WHERE <- NULL", ID = 'ID <- "ccfid"', KEY = "KEY <- ID")
  }
  if (reads_data(name)) out <- c(DATASET = 'DATASET <- "study"', ANALYSIS_SET = "ANALYSIS_SET <- NULL", out)
  out
}

test_that("every converted template has the shared settings and a conforming data chunk", {
  tl <- template_list()
  todo <- setdiff(tl$name, pending_contract_families)
  for (i in match(todo, tl$name)) {
    name <- tl$name[[i]]
    src <- readLines(tl$file[[i]], warn = FALSE)
    choices <- template_chunk(src, "edit-study-choices")
    expect_false(is.null(choices), info = name)
    defaults <- expected_defaults(name)
    for (setting in names(defaults)) {
      expect_true(any(trimws(sub("#.*$", "", choices)) == defaults[[setting]]), info = paste(name, setting))
    }
    data <- template_chunk(src, "data")
    expect_false(is.null(data), info = name)
    if (reads_data(name)) {
      expect_true(any(grepl("hvtiRtemplates::read_job_data(", data, fixed = TRUE)), info = name)
    }
    if (name %in% downstream_templates) {
      expect_true(any(grepl(".check_upstream_selection(", data, fixed = TRUE)), info = name)
    }
  }
})

test_that("no converted template uses a retired name for the shared vocabulary", {
  tl <- template_list()
  retired <- c("^STATUS\\s*<-", "^KEY_COLS\\s*<-", '"iu_dead"', '"idead"', '^ID\\s*<-\\s*"id"')
  for (i in match(setdiff(tl$name, pending_contract_families), tl$name)) {
    src <- readLines(tl$file[[i]], warn = FALSE)
    for (pattern in retired) expect_false(any(grepl(pattern, src)), info = paste(tl$name[[i]], pattern))
  }
})

test_that("the pending and downstream lists name only real templates", {
  expect_true(all(pending_contract_families %in% template_list()$name))
  expect_true(all(downstream_templates %in% template_list()$name))
})
```

- [ ] **Step 3: Prove the test works, by mutation**

Temporarily set `pending_contract_families <- setdiff(template_list()$name, "dc-general")` and run `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-data-contract.R")'`. Expected: FAIL for `dc-general` (no `WHERE`, no `data` call). Restore the line.

- [ ] **Step 4: Commit and open the PR for Tasks 1 to 4**

```bash
git add tests/testthat/test-data-contract.R tests/testthat/helper-migration.R tests/testthat/test-template-provenance.R tests/testthat/helper-lm.R tests/testthat/helper-rf.R
git commit -m "test: the data contract test (every family pending) and ccfid in every fixture"
```

Add a NEWS bullet under `# hvtiRtemplates (unreleased)`: "`read_job_data()` is the shared data step for templates: it reads a registered dataset or analysis set, resolves the patient ID (`ccfid`, then `MRN`, then `eMRN`), drops `MRN` and `eMRN`, keeps the rows `WHERE` selects with `dplyr::filter()` rules, checks rows are unique on `KEY`, and records what it did. Templates adopt it family by family." Commit, push `feat/read-job-data`, open the PR.

---

### Task 5: descriptive family (`dc-general`, `dc-gfup`, `dc-tables`, `dp-eda`, `dp-gfup`, `dp-postage`) and `dp-trends`

**Files:**
- Modify: `inst/templates/10_descriptive/{dc-general,dc-gfup,dc-tables,dp-eda,dp-postage}.qmd`, `inst/templates/40_graphs/{dp-gfup,dp-trends}.qmd`
- Modify: `R/migrate-*.R` for these jobs, where they write `ANALYSIS_SET`, `KEY_COLS` or the identifier rule
- Test: `tests/testthat/test-data-contract.R` (remove these seven from `pending_contract_families`), and the family's existing tests

**Interfaces:**
- Consumes: `hvtiRtemplates::read_job_data()`, `hvtiRtemplates:::.find_study_root()`.

- [ ] **Step 1: Remove the seven names from the pending list, run, see it fail**

Change the first line of the list to `pending_contract_families <- setdiff(template_list()$name, c("dc-general", "dc-gfup", "dc-tables", "dp-eda", "dp-gfup", "dp-postage", "dp-trends"))`.
Run: `Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-data-contract.R")'`. Expected: FAIL for all seven.

- [ ] **Step 2: Replace each template's data settings with the shared block**

In each template's `edit-study-choices` chunk, delete the existing `DATASET`, `ANALYSIS_SET` (and `dc-general`'s `KEY_COLS`) lines with their comments and put this block first:

```r
# EDIT: the registered dataset this job reads ("study" is the built dataset).
DATASET <- "study"

# EDIT: an hvtiRdatabuild analysis set, or NULL to read the whole dataset.
ANALYSIS_SET <- NULL

# EDIT: rows to keep, dplyr::filter() style, or NULL to keep every row:
#   WHERE <- quote(age >= 18)
#   WHERE <- rlang::exprs(age >= 18, hx_chf == 1)
WHERE <- NULL

# EDIT: the patient identifier. Without "ccfid" the job uses MRN, then eMRN;
# name another column, such as "randid", if the study uses one.
ID <- "ccfid"

# EDIT: what makes a row unique; one row per patient unless repeated measures
# add their visit time or date, for example KEY <- c(ID, "iv_echo").
KEY <- ID
```

In `dc-general`, every later use of `KEY_COLS` becomes `ID` (it is the column kept out of summaries); `ID_COL` stays as it is (labelling extremes is a separate, opt-in choice).

- [ ] **Step 3: Replace each data chunk with the shared one**

Replace the whole body of the chunk labelled `data` (in `dp-trends`, the chunk labelled `edit-data`, which is renamed `data`; any `EDIT:` lines it held that are not data selection move into `edit-study-choices`) with:

```r
#| label: data
hvtiRutilities::verify_manifest(file.path(.root, "manifest.yaml"))
.cfg <- study_config(start = .root)
job_data <- hvtiRtemplates::read_job_data(.cfg, dataset = DATASET, analysis_set = ANALYSIS_SET,
                                          where = WHERE, id = ID, key = KEY)
d <- job_data$data
.provenance_data <- c(if (exists(".provenance_data")) .provenance_data else list(), list(job_data$provenance))
knitr::kable(job_data$record, col.names = c("Data", ""), caption = "The data this job read")
```

Keep the chunk's `#| results: asis` option where the old chunk had it. Where the old chunk printed an analysis set's attrition table, keep that table after the record, guarded by `if (!is.null(ANALYSIS_SET))`.

- [ ] **Step 4: Find the study root with the helper**

In every template's `setup` chunk, replace
`.root <- hvtiRutilities::study_root(if (is.null(.in)) getwd() else dirname(.in))`
with
`.root <- hvtiRtemplates:::.find_study_root(if (is.null(.in)) getwd() else dirname(.in))`.
Do this for **all 30 templates** in this task, since it is one line and has no dependency on the family's settings.

- [ ] **Step 5: Narrow the EDA identifier rule**

In `dp-eda.qmd` and `dp-postage.qmd` (identically; `test-dp-eda.R` compares them), change `looks_like_id()` to drop its name rules for identifiers and keep the date and distinct-text rules:

```r
looks_like_id <- function(v) {
  grepl("(^|_)(date|datetime)($|_)|_dt$", v, ignore.case = TRUE) |
    vapply(d[v], function(x) {
      seen <- x[!is.na(x)]
      inherits(x, c("Date", "POSIXt")) ||
        ((is.character(x) || is.factor(x)) && length(seen) >= 10L && !anyDuplicated(seen))
    }, logical(1L))
}
```

and update the comment above it: identifiers are dropped at read by `read_job_data()`; this rule finds dates and free-text columns that should not be drawn. Update `test-migrate-dp-postage.R` and `test-dp-eda.R`'s identifier tests: `ccfid` and `MRN` are now absent from `d` after the data chunk, so the tests assert they are not drawn because they were dropped at read, and `pt_mrn_num` is now drawn.

- [ ] **Step 6: Run the family's tests and the contract test**

Run: `R_LIBS=<scratch lib with hvtiRutilities main> Rscript -e 'devtools::test()'`
Expected: `FAIL 0`, `SKIP 0`. Fix any test that set `ANALYSIS_SET <- NULL` by edit (now the default) or read `KEY_COLS`.

- [ ] **Step 7: Lint, spelling, NEWS, commit, PR**

Run: `Rscript -e 'lintr::lint_package(cache = FALSE)'` (0) and `bash tools/check-us-spelling.sh`.
NEWS bullet: "The descriptive templates and `dp-trends` read their data through `read_job_data()`: `ANALYSIS_SET` defaults to `NULL`, so they run on a newly registered study; `WHERE`, `ID` and `KEY` are new settings; `dc-general`'s `KEY_COLS` is `ID`; and the EDA templates' identifier rule is narrowed to dates and free text, since identifiers are dropped at read. Every template's setup chunk says to run `study_setup()` when it is not inside a study."

```bash
git add inst/templates R tests NEWS.md
git commit -m "feat(templates): descriptive family and dp-trends adopt the data contract"
```

---

### Task 6: logistic family (the eight `lm-*` templates)

**Files:**
- Modify: `inst/templates/30_analyses/lm-*.qmd`
- Modify: `R/migrate-*.R` where lm jobs write `ID <- "id"`
- Test: `test-data-contract.R` (remove the eight), `test-lm-templates.R`

- [ ] **Step 1: Remove the eight lm names from `pending_contract_families`; run the contract test; expect FAIL for them.**

- [ ] **Step 2: Settings.** In each `edit-study-choices`, replace the `DATASET <- "study"` line and `ID <- "id"` line (with their comments) by the shared block from Task 5 Step 2 (reproduced here so this task reads alone):

```r
# EDIT: the registered dataset this job reads ("study" is the built dataset).
DATASET <- "study"

# EDIT: an hvtiRdatabuild analysis set, or NULL to read the whole dataset.
ANALYSIS_SET <- NULL

# EDIT: rows to keep, dplyr::filter() style, or NULL to keep every row:
#   WHERE <- quote(age >= 18)
#   WHERE <- rlang::exprs(age >= 18, hx_chf == 1)
WHERE <- NULL

# EDIT: the patient identifier. Without "ccfid" the job uses MRN, then eMRN;
# name another column, such as "randid", if the study uses one.
ID <- "ccfid"

# EDIT: what makes a row unique; one row per patient unless repeated measures
# add their visit time or date, for example KEY <- c(ID, "iv_echo").
KEY <- ID
```

Where a template handles stacked imputations (`IMPUTATION` set), add after that setting: `if (!is.null(IMPUTATION)) KEY <- c(ID, IMPUTATION)`. `OUTCOME`, `TREATMENT` and `PREDICTORS` keep their names.

- [ ] **Step 3: Data chunk.** Rename the chunk labelled `read` to `data` and replace its data-reading lines with:

```r
.cfg <- study_config(start = .root)
job_data <- hvtiRtemplates::read_job_data(.cfg, dataset = DATASET, analysis_set = ANALYSIS_SET,
                                          where = WHERE, id = ID, key = KEY)
d <- job_data$data
.provenance_data <- c(if (exists(".provenance_data")) .provenance_data else list(), list(job_data$provenance))
knitr::kable(job_data$record, col.names = c("Data", ""), caption = "The data this job read")
```

Keep the chunk's existing column checks after it. Where the template passed its read record to `.lm_fit_provenance()` or `.attach_handoff_lineage()`, pass `job_data$provenance`, and add `selection = attr(job_data$record, "selection")` to `.attach_handoff_lineage()`.

- [ ] **Step 4: `lm-checkpred`.** Its validation cohort is `DATASET` or `WHERE` like any job. After reading the saved `lm-binary` bundle, stop if the validation rows share an `ID` value with the training selection: compare `unique(d[[ID]])` with the bundle's training IDs if the bundle stores them; if it stores only counts, stop when `DATASET`, `ANALYSIS_SET` and `WHERE` are all identical to the bundle's selection (`attr(... , "hvti_provenance")$selection`) with the message "The validation data are the training data: set DATASET or WHERE to the validation cohort." Add a test in `test-lm-templates.R` for that stop.

- [ ] **Step 5: Run tests (`FAIL 0`, `SKIP 0`), lint (0), spelling; NEWS bullet: "The logistic templates read their data through `read_job_data()`; `ID` defaults to `\"ccfid\"` (it was `\"id\"`, which no built dataset carries), and `lm-checkpred` stops when its validation data are its training data." Commit `feat(templates): logistic family adopts the data contract`; PR.**

---

### Task 7: hazard chain (`ac`, `hz`, `hm`, `hp`, `hs`)

**Files:**
- Modify: `inst/templates/20_distributions/{ac,hz}.qmd`, `inst/templates/30_analyses/hm.qmd`, `inst/templates/40_graphs/{hp,hs}.qmd`
- Modify: `R/migrate-*.R` for hazard jobs where they write `STATUS`, `iu_dead` or `idead`
- Test: `test-data-contract.R` (remove the five), the hazard tests in `test-templates.R`

- [ ] **Step 1: Remove the five names from `pending_contract_families`; run; expect FAIL.**

- [ ] **Step 2: Upstream jobs (`ac`, `hz`).** In `edit-study-choices` put the shared block:

```r
# EDIT: the registered dataset this job reads ("study" is the built dataset).
DATASET <- "study"

# EDIT: an hvtiRdatabuild analysis set, or NULL to read the whole dataset.
ANALYSIS_SET <- NULL

# EDIT: rows to keep, dplyr::filter() style, or NULL to keep every row:
#   WHERE <- quote(age >= 18)
#   WHERE <- rlang::exprs(age >= 18, hx_chf == 1)
WHERE <- NULL

# EDIT: the patient identifier. Without "ccfid" the job uses MRN, then eMRN;
# name another column, such as "randid", if the study uses one.
ID <- "ccfid"

# EDIT: what makes a row unique; one row per patient unless repeated measures
# add their visit time or date, for example KEY <- c(ID, "iv_echo").
KEY <- ID
```

Rename `STATUS` to `EVENT` everywhere in the file (setting, uses, messages). `TIME` stays; defaults are `TIME <- "iv_dead"`, `EVENT <- "dead"`. Delete the `edit-cohort` chunk's commented filter line (`# d <- d[!is.na(d$<flag>) ...`) and its `EDIT:` comment: `WHERE` replaces it. Keep `EXPECTED` and `assert_cohort()` as the optional check, now after the data chunk. The data chunk (renamed `data` if it was `edit-cohort`; if the chunk still holds an `EDIT:` marker keep its label `edit-cohort` and put the read in a new `data` chunk before it) becomes:

```r
.cfg <- study_config(start = .root)
job_data <- hvtiRtemplates::read_job_data(.cfg, dataset = DATASET, analysis_set = ANALYSIS_SET,
                                          where = WHERE, id = ID, key = KEY)
d <- job_data$data
.provenance_data <- c(if (exists(".provenance_data")) .provenance_data else list(), list(job_data$provenance))
knitr::kable(job_data$record, col.names = c("Data", ""), caption = "The data this job read")
```

Where `hz` saves `hz.rds` (and `ac` saves `ac.rds`) with `.attach_handoff_lineage()`, pass `selection = c(attr(job_data$record, "selection"), list(time = TIME, event = EVENT))`.

- [ ] **Step 3: Downstream jobs (`hm`, `hp`, `hs`).** Their settings become `WHERE <- NULL`, `ID <- NULL`, `KEY <- NULL`, `TIME <- NULL`, `EVENT <- NULL`, each commented "NULL takes the value hz used; set it only to confirm it", plus `DATASET <- "study"` and `ANALYSIS_SET <- NULL`. After reading `hz.rds` with `.read_handoff()`, resolve them:

```r
.sel <- hvtiRtemplates:::.check_upstream_selection(
  .hz_read$lineage$selection,
  list(where = WHERE, id = ID, key = KEY, time = TIME, event = EVENT)
)
job_data <- hvtiRtemplates::read_job_data(.cfg, dataset = DATASET, analysis_set = ANALYSIS_SET,
                                          where = if (length(.sel$where)) lapply(.sel$where, str2lang) else NULL,
                                          id = .sel$id, key = .sel$key)
d <- job_data$data
TIME <- .sel$time
EVENT <- .sel$event
```

Put this in the chunk labelled `data` (the contract test looks for both `.check_upstream_selection(` and `hvtiRtemplates::read_job_data(` there). Their settings omit `DATASET`/`ANALYSIS_SET` defaults other than `DATASET <- "study"` and `ANALYSIS_SET <- NULL`. Replace `hs`'s hand-typed filter (which had to repeat `hm`'s) with this. `hp` gains the same read, closing its missing filter (#177). Add a test: render `hs` (or run its chunks) with `WHERE <- quote(age >= 65)` against an `hz.rds` whose selection has `where = "age >= 18"`; expect the stop naming both.

- [ ] **Step 4: Run tests, lint, spelling. NEWS: "The hazard chain reads its data through `read_job_data()`: `STATUS` is `EVENT`, the `iu_dead`/`idead` defaults are `iv_dead`/`dead`, the filter typed into every job is one `WHERE` in `ac` and `hz`, and `hm`, `hp` and `hs` take `WHERE`, `ID`, `KEY`, `TIME` and `EVENT` from `hz`'s saved fit, stopping if their own differ." Commit, PR.**

---

### Task 8: random-forest family (three fit/explain pairs)

**Files:**
- Modify: `inst/templates/30_analyses/rf{s,c,r}-{fit,explain}.qmd`
- Test: `test-data-contract.R` (remove the six), `test-rf-templates.R`

- [ ] **Step 1: Remove the six names from `pending_contract_families`; run; expect FAIL.**

- [ ] **Step 2: Fit jobs.** Put the shared block (as in Task 7 Step 2, verbatim) at the top of `edit-study-choices`; rename `rfs-fit`'s `STATUS` to `EVENT` with defaults `TIME <- "iv_dead"`, `EVENT <- "dead"`. Rename the `read` chunk to `data` and replace its read with:

```r
.cfg <- study_config(start = .root)
job_data <- hvtiRtemplates::read_job_data(.cfg, dataset = DATASET, analysis_set = ANALYSIS_SET,
                                          where = WHERE, id = ID, key = KEY)
d <- job_data$data
.provenance_data <- c(if (exists(".provenance_data")) .provenance_data else list(), list(job_data$provenance))
knitr::kable(job_data$record, col.names = c("Data", ""), caption = "The data this job read")
```

Keep the column subset line after it (`d <- d[, c(...), drop = FALSE]`). Before fitting, convert character predictors to factors and say so (#181):

```r
.chr <- names(d)[vapply(d, is.character, logical(1L))]
if (length(.chr)) {
  d[.chr] <- lapply(d[.chr], factor)
  cat("Text predictors converted to factors:", paste(.chr, collapse = ", "), "\n")
}
```

Pass `selection = attr(job_data$record, "selection")` to the fit's `.attach_handoff_lineage()`.

- [ ] **Step 3: Explain jobs.** Add to `edit-study-choices`, and no `DATASET` or `ANALYSIS_SET` (they read the saved forest, not data):

```r
# EDIT: the fit's selection is used; set any of these only to confirm it.
# NULL takes the value the fit job used.
WHERE <- NULL
ID <- NULL
KEY <- NULL
```

After the chunk that reads the forest, add a chunk labelled `data`:

```r
#| label: data
.sel <- hvtiRtemplates:::.check_upstream_selection(
  <fit lineage>$selection, list(where = WHERE, id = ID, key = KEY)
)
knitr::kable(data.frame(step = c("ID", "KEY", "WHERE", "Rows"),
                        value = c(.sel$id, paste(.sel$key, collapse = ", "),
                                  if (length(.sel$where)) paste(.sel$where, collapse = "; ") else "none",
                                  .sel$rows)),
             col.names = c("Data", ""), caption = "The data the fit job read")
```

(`<fit lineage>` is the lineage of the forest the template already reads, for example `.forest_read$lineage`; use that object's name.)

- [ ] **Step 4: Run tests (the test file muffles only varPro's missing-rows notice), lint, spelling. NEWS: "The random-forest templates read their data through `read_job_data()`, gaining `WHERE`, `ID` and `KEY`; text predictors are converted to factors with a note; `explain` jobs take the fit's selection." Commit, PR.**

---

### Task 9: bootstrap family (`bl`, `br`, `bc`, `bh`)

**Files:**
- Modify: `inst/templates/30_analyses/{bl,br,bc,bh}.qmd`
- Test: `test-data-contract.R` (remove the four)

- [ ] **Step 1: Remove the four names from `pending_contract_families`; run; expect FAIL.**

- [ ] **Step 2: Settings and a `data` chunk that reports the bag's selection.** These reports read a bag, not data. Add to `edit-study-choices`, and no `DATASET` or `ANALYSIS_SET` (these reports read a bag, not data):

```r
# EDIT: the bag's recorded selection is used; set any of these only to confirm
# it. NULL takes the value the bootstrap runner used.
WHERE <- NULL
ID <- NULL
KEY <- NULL
```

Add a chunk labelled `data` after the bag is read:

```r
#| label: data
.bag_selection <- attr(.bag, "hvti_provenance")$selection
if (!is.null(.bag_selection)) {
  .sel <- hvtiRtemplates:::.check_upstream_selection(.bag_selection, list(where = WHERE, id = ID, key = KEY))
  knitr::kable(data.frame(step = c("ID", "KEY", "WHERE", "Rows"),
                          value = c(.sel$id, paste(.sel$key, collapse = ", "),
                                    if (length(.sel$where)) paste(.sel$where, collapse = "; ") else "none",
                                    .sel$rows)),
               col.names = c("Data", ""), caption = "The data the bootstrap runner read")
} else {
  cat("This bag records no data selection; it predates read_job_data().\n")
}
# The contract: runners read their data with hvtiRtemplates::read_job_data(), whose
# selection travels in the bag's lineage.
```

(`.bag` is whatever object name the template already reads the bag into; use that name.) Update the runner snippets in each template's narration to call `hvtiRtemplates::read_job_data()` and attach `selection` to the bag's lineage (#185).

- [ ] **Step 3: Run tests, lint, spelling. NEWS: "The bootstrap reports print the data selection their bag carries, and their runner snippets read data through `read_job_data()`." Commit, PR.**

---

### Task 10: the gallery drops its data-path workarounds, and a final check

**Files:**
- Modify: `dev/gallery/family-{descriptive,hazard,lm,rf,bootstrap}.R`, `dev/demo/demo-study.R` choices if needed
- Test: a full gallery build

- [ ] **Step 1: Every gallery job sets `ID <- "patient_id"`** (the demo cohort's identifier) through its choices, since it has no `ccfid`. Replace workarounds with `WHERE`: the hazard chain's zero-time filter slot stays (it is #175, not selection); the logistic family's extra registered training and validation datasets become `WHERE <- quote(year < 2015)` in `lm-binary` and `WHERE <- quote(year >= 2015)` in `lm-checkpred`; `hs`'s repeated filter is removed.

- [ ] **Step 2: Build all 30.**

Run (with this branch installed into the scratch library): `Rscript dev/gallery/gallery.R <folder>/study`
Expected: 30 rows, every `error` `NA`.

- [ ] **Step 3: Commit, PR.** NEWS: none (`dev/` ships nothing).

---

### Task 11: hvtiPlotR 2.8.1: narrow `hv_eda_pages()`'s identifier default

**Repository:** `ehrlinger/hvtiPlotR`, a separate branch and PR.

**Files:**
- Modify: `R/eda-pages.R` (`.eda_identifier_name()`), `NEWS.md`
- Test: `tests/testthat/test_eda_pages.R`

- [ ] **Step 1: Change the test.** In the test "vars = NULL leaves out identifier columns, and naming one draws it", change the expectations: `ccfid`, `MRN` and `eMRN` are left out; `PatientID` and `pt_mrn_num` are now drawn.

```r
ids <- transform(dta, ccfid = seq_len(n), MRN = seq_len(n), eMRN = seq_len(n),
                 PatientID = seq_len(n), pt_mrn_num = seq_len(n), carotid = dta$male)
pct <- hv_eda_pages(ids, x_col = "year", section = "percent")
expect_identical(pct$meta$ignored, c("ccfid", "MRN", "eMRN"))
```

Run it; expect FAIL.

- [ ] **Step 2: Implement.**

```r
# Names that mark a patient identifier, matching hvtiRtemplates' data contract:
# ccfid, MRN and eMRN, ignoring case. The group's naming is controlled, so no
# other name is guessed at.
.eda_identifier_name <- function(v) tolower(v) %in% c("ccfid", "mrn", "emrn")
```

Update the `@param vars` roxygen (markdown in this package) to name exactly these three.

- [ ] **Step 3: Tests, lint, spelling check, `devtools::document()`. NEWS under `# hvtiPlotR (unreleased)`: "`hv_eda_pages()` leaves out `ccfid`, `MRN` and `eMRN` under `vars = NULL`, and no longer guesses at other identifier names, matching hvtiRtemplates' data contract." Commit, PR. The version is named 2.8.1 in a separate release commit.**

---

## Self-review

- **Spec coverage.** Section 2 (default whole dataset): Task 5 Step 2 and every family task. 3.1 `WHERE`: Task 1. 3.2 `ID`/`KEY`: Tasks 1 and 2. 3.3 vocabulary: Tasks 7 and 8 (`STATUS` to `EVENT`, defaults), contract test's retired names. 4.1 steps: Tasks 1 and 2. 4.2 record: Task 2, printed in every family task. 4.3 missing study: Task 2 and Task 5 Step 4 (all 30 setup chunks). 4.4: no task needed. 5 downstream: Task 3, used in Tasks 7, 8, 9. 6 identifier rule: Task 5 Step 5 and Task 11. 7 scope by family: Tasks 5 to 9. 8 rollout order: task order. 9 testing: Tasks 1 to 4, 7's downstream test, 10's gallery. 10 open: none.
- **Type consistency.** `read_job_data()` returns `list(data, record, provenance)` in Task 2 and every consumer uses those names; `attr(record, "selection")` fields (`dataset`, `analysis_set`, `where`, `id`, `key`, `rows`, `patients`, plus `time`, `event` added by hazard fits) match `.check_upstream_selection()`'s `names_shown`.
