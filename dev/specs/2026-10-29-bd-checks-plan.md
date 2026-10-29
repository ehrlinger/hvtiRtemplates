# Fold the `dt` checks into `bd`: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `bd.qmd` runs `dt`'s four check sections between `write-built` and Register, reporting counts only, and
the standalone `dt` template is removed.

**Architecture:** The four `dt` chunks (`rebuild`, `crosstabs`, `followup`, `tbl-checks`) move into a new
`## Checks` section of `bd.qmd`, reading the data frame `d` that `write-built` has just written instead of reading
the working file back. `dt`'s choices join `bd`'s Study choices; `bd` already has `ID`, `KEY` and `DATASET_ID`. The
`dt` tests become `bd` tests that run `bd`'s chunks through `write-built`, change `d` the way a rebuild would, then
run the check chunks.

**Tech Stack:** R, Quarto, testthat 3e, hvtiRutilities (`proc_print()`, `proc_freq()`, `followup_check()`),
hvtiRdatabuild (`compare_built()`).

**Spec:** `dev/specs/2026-10-29-bd-checks-design.md` (PR #454). Read it first.

## Global Constraints

- Branch `feat/bd-checks` from `origin/main`, never commit to `main`. One PR for the whole plan, opened against `main`.
- Quarto renders use the INSTALLED hvtiRtemplates, which other sessions overwrite. Install the branch into a private
  library, `LIB=$(mktemp -d)/lib; mkdir -p $LIB; R CMD INSTALL -l $LIB .`, and run render tests with `R_LIBS=$LIB`.
- `bd.qmd`'s setup stops below **hvtiRutilities 1.5.17** (`proc_print()`) and **hvtiRdatabuild 0.3.3**
  (`compare_built()`). `DESCRIPTION` floors do **not** move in this PR: a floor moves only in the package's own bump.
- The checks only report. No check changes what the `register` chunk does.
- The report holds counts only. Rows behind a check, and identifiers on one side of a rebuild, go to `stderr()`.
- Every stop is `.bd_stop("<step>", ...)`: it names the step and the file, never a data value.
- Lines are at most 135 characters (`.lintr`). Roxygen is Rd markup, but this plan touches no roxygen.
- Do not run `git add -A`: failing testthat runs write `tests/testthat/_problems/`. Stage named paths.
- Run tests with `NOT_CRAN=true`. Local TemporalHazard older than 1.2.17 skips two `test-hazard-start-stop.R`
  tests; that is environmental and expected.
- No em dashes (U+2014) in anything written, including commit messages.
- `dt`'s row in `hvti_taxonomy()` stays. Corpus artifacts under `dev/specs/artifacts/` that count SAS `dt` jobs stay.

## Files

| file | change |
|---|---|
| `inst/templates/00_datasets/bd.qmd` | setup floors and `.bd_table()`; five new choices; their validation; new `## Checks` section; intro and `REGISTER` comment |
| `tests/testthat/helper-bd.R` | `bd_skip()` floors; new `bd_check_choices()`, `bd_check_run()` |
| `tests/testthat/test-bd-checks.R` | new: the chunk-level `dt` tests, ported |
| `tests/testthat/test-bd-e2e.R` | two render tests, ported from `test-dt-e2e.R` |
| `tests/testthat/helper-dt.R`, `test-dt-template.R`, `test-dt-e2e.R` | deleted |
| `tests/testthat/test-templates.R`, `test-job-setup.R`, `test-template-provenance.R` | drop `dt` from comments and exclusions |
| `inst/templates/00_datasets/dt.qmd` | deleted |
| `inst/extdata/templates.json` | `dt` row removed; `bd` row's description and note mention the checks |
| `inst/templates/README.md` | `dt` row removed; `bd` row mentions the checks |
| `.lintr` | `dt.qmd` key removed |
| `dev/gallery/family-00-datasets.R` | `dt` job removed; `bd` job sets the check choices |
| `news/feat-bd-checks.md` | new fragment |

---

### Task 1: The Checks section in `bd.qmd`, with its chunk-level tests

**Files:**
- Modify: `inst/templates/00_datasets/bd.qmd`
- Modify: `tests/testthat/helper-bd.R`
- Create: `tests/testthat/test-bd-checks.R`

**Interfaces:**
- Produces, in `bd.qmd`: chunk labels `rebuild`, `crosstabs`, `followup`, `tbl-checks` between `write-built` and
  `register`; objects `.rebuild_state` (character), `.comparison` (`compare_built()` result or `NULL`), `.tab`
  (last cross-tab), `.checked` (`data.frame(label, n, n_missing)`); helper `.bd_table(tab, label, cap, ...)`.
- Produces, in `helper-bd.R`: `bd_check_choices(m, register, ...)` returning a choices list, and
  `bd_check_run(root, choices, change = identity, labels = bd_check_labels)` returning the run environment with
  `$.stdout` (captured stdout lines).

- [ ] **Step 1: Raise `bd_skip()` and add the check helpers to `helper-bd.R`**

Replace `bd_skip()`'s body:

```r
bd_skip <- function() {
  # The job stops below 1.5.17, the first hvtiRutilities with proc_print() for its named checks, and below
  # hvtiRdatabuild 0.3.3, the first with compare_built() for the rebuild comparison.
  testthat::skip_if_not_installed("hvtiRutilities", "1.5.17")
  testthat::skip_if_not_installed("hvtiRdatabuild", "0.3.3")
  testthat::skip_if_not_installed("arrow")
  testthat::skip_if_not_installed("haven")
}
```

Append to the end of `helper-bd.R`:

```r
# The build's own choices for the check tests, with the four check sections set to columns the
# synthetic master carries. `...` overrides any of them.
bd_check_choices <- function(m, register = FALSE, ...) {
  utils::modifyList(
    list(MASTER = m$parquet, KEEP = c("age", "sex", "iv_dead", "dead", "dt_surg"),
         EXCLUDE = list(age < 40 ~ "Under 40"), REGISTER = register,
         CROSSTABS = list(c("dead", "sex")), EVENT = "dead", FOLLOWUP = "iv_dead",
         CHECKS = list(iv_dead <= 0 ~ "Follow-up of zero or less"), PRINT_COLS = c("ccfid", "iv_dead")),
    list(...)
  )
}

bd_check_labels <- c("rebuild", "crosstabs", "followup", "tbl-checks")

# Run bd through write-built, apply `change` to the data frame it wrote, as a rebuild with a changed
# derivation would leave it, then run the check chunks in `labels`. Returns the environment, with the
# check chunks' stdout in $.stdout.
bd_check_run <- function(root, choices, change = identity, labels = bd_check_labels) {
  env <- bd_run(root, choices, labels = c("setup", "edit-study-choices", "check-choices", "read-master", "cohort",
                                          "derive", "write-built"))
  env$d <- change(env$d)
  env$.stdout <- withr::with_dir(root, utils::capture.output(
    hazard_run("bd", labels, env), type = "output"  # nolint: object_usage_linter.
  ))
  env
}
```

`modifyList()` merges nested lists, so a test that replaces `EXCLUDE` or `CHECKS` assigns it after the call
(`ch <- bd_check_choices(m); ch$EXCLUDE <- list(...)`), as `test-dt-template.R` did.

- [ ] **Step 2: Write the failing tests in `tests/testthat/test-bd-checks.R`**

```r
# bd's Checks section: what the rebuild changed, cross-tabs, follow-up and named checks, run on the
# data frame write-built has just written. Ported from the dt template's tests (dev/specs/2026-10-29-bd-checks-design.md).

test_that("the Checks section sits between write-built and Register", {
  src <- readLines(hazard_template("bd"), warn = FALSE)  # nolint: object_usage_linter.
  at <- function(label) which(trimws(src) == paste0("#| label: ", label))
  expect_true(at("write-built") < at("rebuild"))
  expect_true(at("rebuild") < at("crosstabs"))
  expect_true(at("crosstabs") < at("followup"))
  expect_true(at("followup") < at("tbl-checks"))
  expect_true(at("tbl-checks") < at("register"))
  expect_false(any(grepl("read-working", src, fixed = TRUE)))
})

test_that("a rebuild of the study dataset is compared against its registered version", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  bd_run(root, bd_check_choices(m, register = TRUE))
  env <- bd_check_run(root, bd_check_choices(m), labels = "rebuild")
  expect_match(env$.rebuild_state, "^A rebuild of the study dataset: study_cohort.rds against its registered version ")
  # Nothing changed since registering, so every column reads identical.
  expect_true(all(env$.comparison$verdict == "identical"))
  rows <- attr(env$.comparison, "rows")
  expect_identical(c(length(rows$only_oracle), length(rows$only_r)), c(0L, 0L))
})

test_that("the rebuild comparison reports values, not shape, against the registered version", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  bd_run(root, bd_check_choices(m, register = TRUE))
  # HVTI_DATA = "working" makes read_built() serve the working file unless told not to;
  # the baseline must still be the registered version, or every column reads identical.
  withr::local_envvar(HVTI_DATA = "working")
  env <- bd_check_run(root, bd_check_choices(m), labels = "rebuild", change = function(d) {
    d$dead <- 1L - d$dead
    d$iv_dead <- d$iv_dead + 1
    d$ccfid[[1L]] <- "PTSWAP001"
    d
  })
  cmp <- as.data.frame(env$.comparison)
  rows <- attr(env$.comparison, "rows")
  expect_identical(rows$n_oracle, rows$n_r)
  changed <- cmp[cmp$variable %in% c("dead", "iv_dead"), ]
  expect_identical(changed$verdict, c("differs", "differs"))
  expect_identical(changed$n_differ, rep(rows$n_common, 2L))
  expect_true(all(cmp$verdict[!cmp$variable %in% c("dead", "iv_dead")] == "identical"))
  expect_length(rows$only_oracle, 1L)
  expect_identical(rows$only_r, "PTSWAP001")
})

test_that("a comparison build is compared against the study dataset and says it is a comparison build", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  bd_run(root, bd_check_choices(m, register = TRUE, DATASET_ID = "legacy"))
  rebuild <- bd_check_choices(m, DATASET_ID = "study_rebuild")
  # Assigned, not merged with modifyList(), which would merge the two lists of rules.
  rebuild$EXCLUDE <- list(age < 50 ~ "Under 50")
  env <- bd_check_run(root, rebuild, labels = "rebuild")
  expect_identical(hvtiRutilities::study_config(root)$built, "legacy.rds")
  expect_match(env$.rebuild_state, "^A comparison build: study_rebuild.rds is not the study dataset\\.")
  expect_match(env$.rebuild_state, "dataset legacy.rds, registered as legacy_[0-9]{8}[.]parquet")
  rows <- attr(env$.comparison, "rows")
  expect_identical(rows$n_r, nrow(env$d))
  expect_identical(length(rows$only_oracle), sum(m$data$age >= 40 & m$data$age < 50, na.rm = TRUE))
  expect_length(rows$only_r, 0L)
})

test_that("with nothing registered there is no comparison, and the report says so", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  env <- bd_check_run(root, bd_check_choices(m), labels = "rebuild")
  expect_null(env$.comparison)
  expect_identical(env$.rebuild_state,
                   "Nothing is registered for this study yet, so there is no version to compare this build against.")
})

test_that("the cross-tab, follow-up and named-check sections report counts", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  env <- bd_check_run(root, bd_check_choices(m), labels = c("crosstabs", "followup", "tbl-checks"),
                      change = function(d) {
                        d$iv_dead[1:3] <- c(0, -1, NA)
                        d
                      })
  out <- paste(env$.stdout, collapse = "\n")
  expect_match(out, "### dead by sex", fixed = TRUE)
  expect_match(out, "row(s) look suspicious, listed in the console", fixed = TRUE)
  expect_identical(env$.checked$label, "Follow-up of zero or less")
  expect_identical(env$.checked$n, 2L)
  expect_identical(env$.checked$n_missing, 1L)
  expect_true(all(c("dead", "sex", "Frequency", "Small") %in% names(env$.tab)))
})

test_that("a KEY of several columns with a missing part is refused, not joined on the text NA", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  bd_run(root, bd_check_choices(m, register = TRUE, KEY = c("ccfid", "dt_surg")))
  expect_error(
    bd_check_run(root, bd_check_choices(m, KEY = c("ccfid", "dt_surg")), labels = "rebuild", change = function(d) {
      d$dt_surg[[2L]] <- NA
      d
    }),
    "bd: rebuild .*missing value", perl = TRUE
  )
})

test_that("the follow-up section counts every suspicious row, not the 25 it lists", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  env <- bd_check_run(root, bd_check_choices(m), labels = "followup", change = function(d) {
    d$iv_dead[1:40] <- 0
    d
  })
  expected <- sum(is.na(env$d$dead) | is.na(env$d$iv_dead) | env$d$iv_dead <= 0)
  expect_gt(expected, 25L)
  expect_match(paste(env$.stdout, collapse = "\n"), paste0("\n", expected, " row(s) look suspicious"), fixed = TRUE)
})

test_that("a logical derivation is compared by value, as read_built() reads it", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  flag <- function(d) {
    d$flag <- d$dead == 1L
    d
  }
  # The registered version carries the logical column: write it, then register the working file.
  env <- bd_check_run(root, bd_check_choices(m), labels = character(), change = flag)
  saveRDS(env$d, file.path(hvtiRutilities::study_dir("datasets", root), "study_cohort.rds"))
  withr::with_dir(root, suppressMessages(hvtiRutilities::update_manifest(dataset = "study")))
  env <- bd_check_run(root, bd_check_choices(m), labels = "rebuild", change = flag)
  cmp <- as.data.frame(env$.comparison)
  expect_identical(cmp$verdict[cmp$variable == "flag"], "identical")
  env <- bd_check_run(root, bd_check_choices(m), labels = "rebuild", change = function(d) {
    d <- flag(d)
    d$flag <- !d$flag
    d
  })
  cmp <- as.data.frame(env$.comparison)
  expect_identical(cmp$verdict[cmp$variable == "flag"], "differs")
  expect_identical(cmp$n_differ[cmp$variable == "flag"], attr(env$.comparison, "rows")$n_common)
  expect_true(is.logical(env$d$flag))
})

test_that("bad check choices stop in check-choices, naming no value", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  expect_error(bd_run(root, bd_check_choices(m, CROSSTABS = list(1L)), labels = c("setup", "edit-study-choices",
                                                                                  "check-choices")),
               "bd: check-choices .*CROSSTABS must be a list of column-name vectors", perl = TRUE)
  bad <- bd_check_choices(m)
  bad$CHECKS <- "not a formula"
  expect_error(bd_run(root, bad, labels = c("setup", "edit-study-choices", "check-choices")),
               "bd: check-choices .*CHECKS must be a list", perl = TRUE)
  expect_error(bd_run(root, bd_check_choices(m, EVENT = c("a", "b")), labels = c("setup", "edit-study-choices",
                                                                                "check-choices")),
               "bd: check-choices .*EVENT must be one column name", perl = TRUE)
})
```

- [ ] **Step 3: Run the new tests to see them fail**

Run: `NOT_CRAN=true Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-bd-checks.R")'`
Expected: FAIL. The layout test fails on `at("rebuild")` being empty, and the rest fail with
`chunk 'rebuild' found 0 times` (or `crosstabs`, `followup`).

- [ ] **Step 4: Raise the setup floors and add `.bd_table()` in `bd.qmd`'s `setup` chunk**

Replace the comment and `if` block that check hvtiRutilities 1.5.12 (currently lines 58-63) with:

```r
# Registering claims the build record only from hvtiRutilities 1.5.3, and declaring the working file
# (declare_data()) needs 1.5.12; an older one would record a bd cut as legacy or cannot declare it. The named
# checks need proc_print(), released in 1.5.17, and the rebuild comparison compare_built(), in hvtiRdatabuild 0.3.3.
if (utils::packageVersion("hvtiRutilities") < "1.5.17") {
  .bd_stop("setup", "this job needs hvtiRutilities >= 1.5.17 for proc_print(); ",
           utils::packageVersion("hvtiRutilities"), " is installed.")
}
if (!requireNamespace("hvtiRdatabuild", quietly = TRUE) || utils::packageVersion("hvtiRdatabuild") < "0.3.3") {
  .bd_stop("setup", "this job needs hvtiRdatabuild >= 0.3.3 for compare_built().")
}
```

Directly after `knitr::opts_chunk$set(warning = NA, message = NA)`, add:

```r
# One numbered table, for a section that shows a table only when it has one or shows several: a
# child chunk with its own label and caption while rendering, and a plain table in the console,
# where a child's label would collide with the same chunk run before.
.bd_table <- function(tab, label, cap, ...) {
  if (!isTRUE(getOption("knitr.in.progress"))) return(print(knitr::kable(tab, ...)))
  child <- new.env(parent = environment())
  fence <- strrep("`", 3)
  cat(knitr::knit_child(text = c(paste0(fence, "{r}"), paste0("#| label: ", label),
                                 paste0("#| tbl-cap: ", encodeString(cap, quote = "\"")),
                                 "knitr::kable(tab, ...)", fence), envir = child, quiet = TRUE), sep = "\n")
}
```

Then run `grep -n "1.5.12" tests/testthat/*.R`. Any test asserting the old setup message is updated to
`hvtiRutilities >= 1.5.17 for proc_print()`.

- [ ] **Step 5: Add the five choices to `edit-study-choices`**

Insert after the `DATASET_ID <- "study_cohort"` line and its blank line, before the `REGISTER` comment:

```r
# EDIT: pairs of columns to cross-tabulate, typically a derived column against its source, such as an event
# indicator against an indicator of its date. A missing value is a level of its own, as PROC FREQ / MISSING shows
# it. A list of character vectors, or list() for none.
CROSSTABS <- list(c("dead", "sex"))

# EDIT: the event indicator and its follow-up interval(s) in years, as the derive chunk makes them. EVENT <- NULL
# checks none.
EVENT    <- "dead"
FOLLOWUP <- "iv_dead"

# EDIT: the rows that look wrong, as condition ~ "Label", the shape of EXCLUDE. The report shows each label and
# how many rows match; the matching rows go to the console. A check may name a patient, for example
#   ccfid == "<id>" ~ "The patient queried by the surgeon"
# and a row for which a condition is missing is counted apart, never as a match. list() for none.
CHECKS <- list(
  dead == 1 & is.na(iv_dead) ~ "Event with no follow-up interval",
  iv_dead <= 0 ~ "Follow-up interval of zero or less"
)

# EDIT: the columns printed in the console for each check's matching rows. NULL prints every column.
PRINT_COLS <- c("dead", "iv_dead")

```

Replace the `REGISTER` comment's last two lines:

```r
# reads. Before registering a rebuild, hvtiRutilities::review_built() shows how
# the working file differs from the version registered now.
```

with:

```r
# reads. Render with FALSE first and read the Checks section, which shows how this
# build differs from the version registered now, then set TRUE and render again.
```

- [ ] **Step 6: Validate the choices in `check-choices`**

Insert before `KEEP <- tolower(KEEP)`:

```r
if (is.character(CROSSTABS)) CROSSTABS <- list(CROSSTABS)
if (!is.list(CROSSTABS) || !all(vapply(CROSSTABS, is.character, logical(1L)))) {
  .bd_stop("check-choices", "CROSSTABS must be a list of column-name vectors, or list().")
}
if (inherits(CHECKS, "formula")) CHECKS <- list(CHECKS)
if (!is.list(CHECKS)) .bd_stop("check-choices", "CHECKS must be a list of condition ~ \"Label\", or list().")
if (!is.null(EVENT) && (!is.character(EVENT) || length(EVENT) != 1L || !is.character(FOLLOWUP) || !length(FOLLOWUP))) {
  .bd_stop("check-choices", "EVENT must be one column name and FOLLOWUP one or more, or EVENT NULL.")
}
```

- [ ] **Step 7: Add the Checks section between `write-built` and `## Register`**

Insert this block after the closing fence of the `write-built` chunk and before `## Register`. It is `dt.qmd`'s four
chunks with `.dt_stop` -> `.bd_stop`, `.dt_table` -> `.bd_table`, `.dt_key` -> `.bd_key`, `.working` -> `.built`,
and the comparison reading `d`, already in memory.

````markdown
## Checks

These checks read the dataset this render has just written. They report counts only: the rows behind a count,
and the patients on one side of the rebuild only, are printed in the console, so run the chunks in an
interactive session to read them. A check changes nothing and blocks nothing. A finding becomes a correction to
the master, a rule in `EXCLUDE`, or a fix to the derive chunk; then render again, and register once the checks
read right.

### What this rebuild changed

```{r}
#| label: rebuild
#| results: asis
# unnumbered: its two tables are child chunks with their own labels and captions
# The baseline is the version registered now for the study's declared dataset, read
# with read_built(working = FALSE) and bound to this build here, never looked up by a
# helper on its own. review_built() resolves its file from _study.yml and not from
# DATASET_ID, so in a comparison build it would review the declared file while every
# check below reads this one. working = FALSE is explicit: with nothing registered,
# or with HVTI_DATA = "working", read_built() serves the working file, and the
# comparison would be this file against itself.
.cfg <- hvtiRutilities::study_config(.root, require_data = FALSE)
.declared <- .cfg$built
.found <- if (!is.null(.declared)) hvtiRtemplates:::.manifest_find(.root, source = .declared)
.comparison <- NULL
if (is.null(.found)) {
  .rebuild_state <- "Nothing is registered for this study yet, so there is no version to compare this build against."
} else {
  # .provenance_read() stops if the registered version changes while it is read. Its record is not shown: it
  # follows HVTI_DATA, and would name the working file under a working read where this read the registered one.
  .baseline_read <- tryCatch(
    hvtiRtemplates:::.provenance_read("study", .cfg, function() hvtiRutilities::read_built(.cfg, working = FALSE),
                                      role = "baseline"),
    error = function(e) .bd_stop("rebuild", conditionMessage(e))
  )
  .baseline <- .baseline_read$value
  .rebuild_state <- if (identical(.declared, basename(.built))) {
    paste0("A rebuild of the study dataset: ", basename(.built), " against its registered version ",
           .found$version_file, ".")
  } else {
    paste0("A comparison build: ", basename(.built), " is not the study dataset. It is compared against the study ",
           "dataset ", .declared, ", registered as ", .found$version_file, ", which this build leaves unchanged.")
  }
  # compare_built() joins on one column. A KEY of several columns is joined on all of them.
  .join <- function(x) {
    if (length(KEY) == 1L) return(x)
    x$.bd_key <- do.call(paste, c(unname(as.list(x[KEY])), sep = "\r"))
    # A missing part leaves the key missing, which compare_built() refuses, rather than the text "NA".
    x$.bd_key[!stats::complete.cases(x[KEY])] <- NA
    x
  }
  .id <- if (length(KEY) == 1L) KEY else ".bd_key"
  # read_built() reads a logical column as integer and drops a labeled column's value labels, so this
  # build is read the same way: otherwise every logical derivation reads "type changed" and its values,
  # the thing a rebuild check is for, are never compared. The checks below read the data as written.
  .as_read <- d
  .as_read[] <- lapply(.as_read, function(x) {
    if (is.logical(x)) return(as.integer(x))
    if (!inherits(x, "haven_labelled")) return(x)
    out <- as.vector(x)
    attr(out, "label") <- attr(x, "label")
    out
  })
  .comparison <- tryCatch(hvtiRdatabuild::compare_built(.join(.baseline), .join(.as_read), id = .id),
                          error = function(e) .bd_stop("rebuild", conditionMessage(e)))
  .rows <- attr(.comparison, "rows")
  # The patients on one side only are identifiers: the console has them, the report their count.
  for (.side in c("only_oracle", "only_r")) {
    .ids <- .rows[[.side]]
    cat("\n", if (.side == "only_oracle") "In the registered version only" else "In this build only", ": ",
        length(.ids), " row(s)\n", sep = "", file = stderr())
    if (length(.ids)) cat(utils::head(.ids, 100L), sep = "\n", file = stderr())
    if (length(.ids) > 100L) cat("... ", length(.ids) - 100L, " more not shown\n", sep = "", file = stderr())
  }
}
cat(.rebuild_state, "\n")
# Per column: identical, within tolerance or differs, with how many rows differ and by
# how much. It is never collapsed into a pass or a fail: a difference is read, not counted.
# The tables are shown only when there is a comparison, so a study with nothing registered shows no empty caption.
if (!is.null(.comparison)) {
  .rows_tab <- data.frame(
    Item = c("Rows in the registered version", "Rows in this build", "Rows in both",
             "In the registered version only", "In this build only"),
    Value = c(.rows$n_oracle, .rows$n_r, .rows$n_common, length(.rows$only_oracle), length(.rows$only_r))
  )
  .verdicts <- c(absent_in_r = "in the registered version only", absent_in_sas = "in this build only",
                 type_mismatch = "type changed")
  .columns_tab <- data.frame(
    Column = .comparison$variable,
    Verdict = ifelse(.comparison$verdict %in% names(.verdicts), .verdicts[.comparison$verdict], .comparison$verdict),
    `Rows differing` = .comparison$n_differ,
    `Largest difference` = signif(.comparison$max_abs_diff, 4),
    check.names = FALSE
  )
  .bd_table(.rows_tab, "tbl-rebuild-rows", "Rows in the registered version and in this build, joined on the dataset's key")
  .bd_table(.columns_tab, "tbl-rebuild-columns", "Each column of the rows in both, compared by value")
}
```

### Cross-tabs

```{r}
#| label: crosstabs
#| results: asis
# unnumbered: each cross-tab is a child chunk with its own label and caption
# Counts the author needs to see: a small cell is flagged, never suppressed.
.small <- 5L
if (!length(CROSSTABS)) cat("No cross-tabs are named in CROSSTABS.\n")
for (.i in seq_along(CROSSTABS)) {
  .pair <- CROSSTABS[[.i]]
  .tab <- tryCatch(hvtiRutilities::proc_freq(d, .pair, missing = TRUE),
                   error = function(e) .bd_stop("crosstabs", conditionMessage(e)))
  .tab <- .tab[, intersect(c(.pair, "Frequency", "Percent"), names(.tab)), drop = FALSE]
  .tab$Small <- ifelse(.tab$Frequency > 0 & .tab$Frequency < .small, paste("under", .small), "")
  .tab[.pair] <- lapply(.tab[.pair], function(x) ifelse(is.na(x), "(missing)", as.character(x)))
  .by <- paste(.pair, collapse = " by ")
  cat("\n\n#### ", .by, "\n\n", sep = "")
  # A label holds letters, digits and hyphens, so an underscore in a name cannot be read as markup. The
  # position keeps two labels apart when two pairs' names reduce to the same letters.
  .slug <- gsub("[^A-Za-z0-9]+", "-", paste(.pair, collapse = "-"))
  .bd_table(.tab, paste0("tbl-crosstab-", .i, "-", .slug), paste0(.by, ", with a missing value as a level of its own"),
            row.names = FALSE)
}
```

### Follow-up

```{r}
#| label: followup
#| results: asis
# unnumbered: its two tables are child chunks with their own labels and captions
# identifier = NULL: the report holds aggregates only. The suspicious rows the check
# finds go to the console, without an identifier, for the author to look at.
if (is.null(EVENT)) {
  cat("No follow-up pair is named in EVENT.\n")
} else {
  .fc <- tryCatch(hvtiRutilities::followup_check(d, event = EVENT, followup = FOLLOWUP, identifier = NULL),
                  error = function(e) .bd_stop("followup", conditionMessage(e)))
  .bd_table(.fc$cohort, "tbl-followup-cohort", "Patients by event status")
  .bd_table(.fc$intervals, "tbl-followup-intervals", "Each follow-up interval", digits = 3)
  # review lists at most 25 rows; n_suspicious counts them all.
  .n_suspicious <- attr(.fc, "n_suspicious")
  cat("\n", .n_suspicious, " row(s) look suspicious, listed in the console.\n", sep = "")
  if (nrow(.fc$review)) cat(utils::capture.output(print(.fc$review, row.names = FALSE)), sep = "\n", file = stderr())
  if (.n_suspicious > nrow(.fc$review)) {
    cat("... ", .n_suspicious - nrow(.fc$review), " more not shown\n", sep = "", file = stderr())
  }
}
```

### Named checks

```{r}
#| label: tbl-checks
#| tbl-cap: "Rows matching each named check; the rows themselves are in the console"
# proc_print() writes the matching rows to stderr(), which a render does not knit, and
# returns one count per check, which is all this report shows.
if (length(CHECKS)) {
  .checked <- tryCatch(hvtiRutilities::proc_print(d, where = CHECKS, var = PRINT_COLS),
                       error = function(e) .bd_stop("checks", conditionMessage(e)))
  knitr::kable(.checked, col.names = c("Check", "Rows matching", "Undecided (missing)"))
} else {
  knitr::kable(data.frame(Check = "No checks are named in CHECKS."))
}
```
````

Cross-tab headings are `####` here, one level below `### Cross-tabs`, where `dt` used `###` under `## Cross-tabs`.
The test in Step 2 matches `"### dead by sex"`, which `"#### dead by sex"` contains, so it still holds.

- [ ] **Step 8: Update the intro prose**

Replace:

```markdown
What does not belong here: corrections to a patient's values (they belong to
the master's corrections, in hvtiRdatabuild, so every study sees them);
imputation, propensity scores and variables for one model (a `vars` job);
printing patient rows to check them (do that in the console, never in a
report).
```

with:

```markdown
Before it registers, the job checks what it built: what the rebuild changed
against the version registered now, cross-tabs, the follow-up columns and the
study's own named checks. The report holds their counts; the rows behind them
go to the console, never into the report.

What does not belong here: corrections to a patient's values (they belong to
the master's corrections, in hvtiRdatabuild, so every study sees them);
imputation, propensity scores and variables for one model (a `vars` job).
```

- [ ] **Step 9: Run the new tests and the existing bd tests**

Run: `NOT_CRAN=true Rscript -e 'devtools::load_all(); for (f in c("test-bd-checks.R", "test-bd-template.R")) testthat::test_file(file.path("tests/testthat", f))'`
Expected: PASS, no skips once hvtiRutilities 1.5.17 and hvtiRdatabuild 0.3.3 are installed.

- [ ] **Step 10: Prove the privacy routing by mutation**

In `bd.qmd`'s `rebuild` chunk, change both `file = stderr()` in the one-side loop to `file = stdout()`. Add a
temporary assertion to the values test: `expect_false(any(grepl("PTSWAP001", env$.stdout, fixed = TRUE)))`. Run
`test-bd-checks.R`: it must FAIL. Revert the mutation with an editor (not `git checkout`, which would discard the
uncommitted work), keep the assertion, and rerun: PASS.

- [ ] **Step 11: Commit**

```bash
git add inst/templates/00_datasets/bd.qmd tests/testthat/helper-bd.R tests/testthat/test-bd-checks.R
git commit -m "bd: check the dataset it built before registering it

Moves dt's four check sections into a Checks section between write-built
and Register. They read the data frame just written and report counts
only; rows go to the console.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: End-to-end renders: counts in the report, no patient row

**Files:**
- Modify: `tests/testthat/test-bd-e2e.R`

**Interfaces:**
- Consumes: `bd_master()`, `bd_study()`, `bd_job()`, `bd_quarto_skip()` from `helper-bd.R`; the Checks section from
  Task 1.
- Produces: nothing new.

- [ ] **Step 1: Read how `test-bd-e2e.R` renders a job**

Run: `sed -n '1,31p' tests/testthat/test-bd-e2e.R`. Use its existing render helper and `bd_job()` edits. If the file
has no helper that renders and returns the HTML, add this at the top of the file:

```r
bd_render <- function(job) {
  quarto::quarto_render(job, execute_dir = dirname(job), quiet = TRUE)
  paste(readLines(sub("[.]qmd$", ".html", job), warn = FALSE), collapse = "\n")
}
```

- [ ] **Step 2: Write the two render tests at the end of `test-bd-e2e.R`**

```r
# The edits that point a scaffolded bd job at the synthetic master and its columns, with the checks set.
bd_check_edits <- function(m, register) {
  list(
    "^MASTER <- " = paste0("MASTER <- \"", m$parquet, "\""),
    "^KEEP <- " = "KEEP <- c(\"age\", \"sex\", \"iv_dead\", \"dead\", \"dt_surg\")",
    "^EXCLUDE <- " = "EXCLUDE <- list(age < 40 ~ \"Under 40\")",
    "^REGISTER <- " = paste0("REGISTER <- ", register)
  )
}

test_that("a bd render shows the checks' counts above Register, and no patient row or identifier", {
  skip_on_cran()
  bd_quarto_skip()
  m <- bd_master()
  root <- bd_study()
  bd_run(root, bd_check_choices(m, register = TRUE))
  # The rebuild: a derivation that adds a column of distinctive strings, which a check prints.
  edits <- bd_check_edits(m, FALSE)
  edits[["^#   d\\$dead    <- "]] <- paste(
    "#   d$dead    <- as.integer(!is.na(d$dt_death))",
    "d$note <- sprintf(\"ZQXNOTE%04d\", seq_len(nrow(d)))", sep = "\n"
  )
  job <- bd_job(root, edits)
  lines <- readLines(job, warn = FALSE)
  queried <- readRDS(file.path(hvtiRutilities::study_dir("datasets", root), "study_cohort.rds"))$ccfid[[5L]]
  from <- grep("^CHECKS <- list\\($", lines)
  to <- from + which(lines[(from + 1L):length(lines)] == ")")[[1L]]
  lines <- c(lines[seq_len(from - 1L)],
             paste0("CHECKS <- list(!is.na(note) ~ \"Every row\", ccfid == \"", queried, "\" ~ \"Queried patient\")"),
             lines[(to + 1L):length(lines)])
  lines[grep("^PRINT_COLS <- ", lines)] <- "PRINT_COLS <- c(\"ccfid\", \"note\")"
  writeLines(lines, job)
  html <- bd_render(job)

  expect_match(html, "A rebuild of the study dataset: study_cohort.rds", fixed = TRUE)
  expect_match(html, "Every row", fixed = TRUE)
  expect_match(html, "Queried patient", fixed = TRUE)
  expect_match(html, "dead by sex", fixed = TRUE)
  # The Checks section comes before Register in the report.
  expect_lt(regexpr("What this rebuild changed", html, fixed = TRUE), regexpr(">Register<", html, fixed = TRUE))
  expect_false(grepl("ZQXNOTE", html, fixed = TRUE))
  leaked <- m$data$ccfid[vapply(m$data$ccfid, grepl, logical(1L), x = html, fixed = TRUE)]
  expect_identical(leaked, character())
})

test_that("a first bd render says nothing is registered, and a cross-tab named twice still renders", {
  skip_on_cran()
  bd_quarto_skip()
  m <- bd_master()
  root <- bd_study()
  edits <- bd_check_edits(m, FALSE)
  edits[["^CROSSTABS <- "]] <- "CROSSTABS <- list(c(\"dead\", \"sex\"), c(\"dead\", \"sex\"))"
  html <- bd_render(bd_job(root, edits))
  expect_match(html, "Nothing is registered for this study yet", fixed = TRUE)
  expect_false(grepl("Rows in the registered version", html, fixed = TRUE))
  expect_identical(lengths(regmatches(html, gregexpr("dead by sex, with a missing value", html, fixed = TRUE))), 2L)
})
```

Before relying on the `^#   d\\$dead    <- ` pattern and the `>Register<` anchor, confirm each against the template
and a rendered report: `grep -n '^#   d\$dead' inst/templates/00_datasets/bd.qmd` must print one line, and the
Register heading's HTML must contain `>Register<`. Adjust the anchor to what the HTML holds, not the reverse.

- [ ] **Step 3: Run the e2e file**

Run: `NOT_CRAN=true Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-bd-e2e.R")'`
Expected: PASS. Quarto renders use the **installed** hvtiRtemplates, so first install this branch into a private
library (Global Constraints, `$LIB`) and run with it: `R CMD INSTALL -l $LIB . && R_LIBS=$LIB NOT_CRAN=true Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-bd-e2e.R")'`.

- [ ] **Step 4: Prove the HTML guard by mutation**

In `bd.qmd`'s `tbl-checks` chunk, replace the `proc_print()` call's result with a version that also prints the
rows to stdout: add `print(d[PRINT_COLS])` on the line before `knitr::kable(.checked, ...)`. Reinstall into `$LIB`
and rerun the first new test: it must FAIL on `ZQXNOTE`. Remove the line, reinstall, rerun: PASS.

- [ ] **Step 5: Commit**

```bash
git add tests/testthat/test-bd-e2e.R
git commit -m "bd: render tests for the Checks section

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Remove `dt`

**Files:**
- Delete: `inst/templates/00_datasets/dt.qmd`, `tests/testthat/helper-dt.R`, `tests/testthat/test-dt-template.R`,
  `tests/testthat/test-dt-e2e.R`
- Modify: `inst/extdata/templates.json`, `inst/templates/README.md`, `.lintr`, `dev/gallery/family-00-datasets.R`,
  `tests/testthat/test-templates.R`, `tests/testthat/test-job-setup.R`, `tests/testthat/test-template-provenance.R`
- Create: `news/feat-bd-checks.md`

**Interfaces:**
- Consumes: Task 1's choices (`CROSSTABS`), so the gallery's `bd` job can set them.

- [ ] **Step 1: Delete the template and its tests**

```bash
git rm inst/templates/00_datasets/dt.qmd tests/testthat/helper-dt.R tests/testthat/test-dt-template.R tests/testthat/test-dt-e2e.R
```

- [ ] **Step 2: Remove the catalog row, and describe the checks in `bd`'s row**

In `inst/extdata/templates.json`, delete the whole object whose `"prefix"` is `"dt"`, including the comma that
separates it from its neighbor, so the file stays valid JSON. In the `bd` object, replace `"description"` with:

```json
"description": "Cuts a study's dataset from a master snapshot: cohort list, exclusions with attrition and derived variables, then the working file and its build record. Before registering, it checks what it built: what the rebuild changed against the registered version, cross-tabs, follow-up and named checks, with counts in the report and rows in the console only. Registered as a dated version of the study dataset.",
```

and append this sentence to the end of `bd`'s `"note"` string: ` Since 2026-10-29 it carries the checks that were
the dt template (dev/specs/2026-10-29-bd-checks-design.md), and the review covers them.`

Run: `python3 -c "import json; json.load(open('inst/extdata/templates.json'))"`. Expected: no output.

- [ ] **Step 3: README, `.lintr`, and the tests that named `dt`**

- `inst/templates/README.md`: delete the `00_datasets/dt.qmd` table row. Change the `bd` row's description cell to
  `study dataset build: master snapshot to a registered dated version, with checks before registering (counts in the report, rows in the console)`.
- `.lintr`: delete the five-line `"inst/templates/00_datasets/dt.qmd" = list(...)` entry.
- `tests/testthat/test-templates.R`: change the comment above `keeps_source_out` to
  `# bd alone keeps a marker's source line out of its report and names no data in its box.`, and the
  `proc_print` line's comment to `# >= 1.5.17 (bd's named checks print rows to the console only)`.
- `tests/testthat/test-job-setup.R`: comment `# bd builds a dataset and does not write through a set.` and
  condition `if (!identical(info, "bd.qmd")) ...`.
- `tests/testthat/test-template-provenance.R`: delete the two comment lines about the dt check job, and change
  the exclusion to `templates[templates$prefix != "bd", ]`.
- Run `grep -rn -E '"dt"|dt\.qmd|dt_skip|helper-dt' R inst tests .lintr dev/gallery`. Expected: no output except
  the taxonomy's `dt` row in `R/`, which stays.

- [ ] **Step 4: The gallery**

In `dev/gallery/family-00-datasets.R`:
- delete the `"dt" = list(...)` job and the two comment lines above it;
- in the `bd` job's choices, add
  `"^CROSSTABS <- list\\(c\\(\"dead\", \"sex\"\\)\\)$" = "CROSSTABS <- list(c(\"dead\", \"female\"))"`, since the
  gallery master has `female`, not `sex`;
- restore line 1-2 of the header to name `bd` only, adding that it checks its cut before registering.

- [ ] **Step 5: The news fragment**

Create `news/feat-bd-checks.md`:

```markdown
* `bd` checks the dataset it built before registering it. A new Checks section, between the working file and
  Register, reports what the rebuild changed against the registered version, cross-tabs, the follow-up columns
  and the study's named checks (`CROSSTABS`, `EVENT`, `FOLLOWUP`, `CHECKS` and `PRINT_COLS`). Counts go in the
  report; the rows behind them go to the console. The checks never block registration. `bd` now needs
  hvtiRutilities 1.5.17 and hvtiRdatabuild 0.3.3. Design: `dev/specs/2026-10-29-bd-checks-design.md`.
* The `dt` template is removed, one release after it arrived as in-flight: its checks are `bd`'s Checks section.
  A job scaffolded from it should move its choices into the study's `bd` job. The taxonomy keeps its `dt` row, so
  `job_census()` still counts the legacy SAS `dt` jobs.
```

- [ ] **Step 6: Run every gate locally**

```bash
python3 dev/specs/artifacts/check-roadmap-counts.py
python3 dev/specs/artifacts/check-spec-counts.py
python3 dev/specs/artifacts/check-flow-counts.py
NOT_CRAN=true Rscript -e 'devtools::document(); devtools::test()'
Rscript -e 'lintr::lint_package()'
```

Expected: the three checks print no failure; `devtools::document()` changes nothing; tests `FAIL 0 | WARN 0`, with
only the known TemporalHazard skips if that package is older than 1.2.17; lint prints nothing.

- [ ] **Step 7: Commit**

```bash
git add inst/extdata/templates.json inst/templates/README.md .lintr dev/gallery/family-00-datasets.R \
  tests/testthat/test-templates.R tests/testthat/test-job-setup.R tests/testthat/test-template-provenance.R \
  news/feat-bd-checks.md
git commit -m "Remove the dt template: its checks are bd's

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Gallery render, review and the pull request

**Files:** none beyond Task 3.

- [ ] **Step 1: Render `bd` in the gallery against this branch**

Install the released family into `$LIB` (`R_LIBS=$LIB Rscript -e 'hvtiR::install(force = TRUE)'`), then this branch
over it (`R CMD INSTALL -l $LIB .`), then:

```bash
R_LIBS=$LIB Rscript -e 'source("dev/gallery/gallery.R"); root <- gallery_study(tempfile()); print(gallery_build(root, only = "bd")[, c("template", "error")]); stopifnot(!length(gallery_missing()))'
```

Expected: `bd` with error `NA`, and no missing job. The gallery itself is rebuilt on the next release day, not here.

- [ ] **Step 2: Local review**

Run `/code-review` on the branch. Fix what it finds, and rerun Task 3 Step 6 after any fix.

- [ ] **Step 3: Push and open the PR**

```bash
git push -u origin feat/bd-checks
gh pr create --title "Fold the dt checks into bd, and remove dt" --body-file pr-body.md
```

`pr-body.md` (in the scratchpad, not the repo) holds: what moved, the test counts from Task 3 Step 6, the two
mutation proofs, and a line saying `/code-review` stood in for the bot if Copilot returns a quota notice. End it
with the Claude Code attribution line.

Then read the R-CMD-check `SKIP n | PASS` line on the ubuntu release leg: `gh run view <id> --log | grep -E "SKIP [0-9]+ \| PASS"`.
Expected `SKIP 0`.
