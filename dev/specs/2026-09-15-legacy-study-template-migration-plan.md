# Legacy Study Template Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Teach fellows to adopt a legacy study, register its canonical and
named datasets, and migrate four established EDA job types through
template-specific adapters.

**Architecture:** `migrate_job()` provides validation, template selection,
atomic output, and reporting. Four internal adapters interpret only the source
shape for `dc-tables`, `dc-gfup`, `dp-trends`, or `dp-postage`; uncertain source
material remains behind a blocking `EDIT:` marker. A runnable vignette uses a
temporary legacy study, while `bio_aggrecan` is a separately approved live
acceptance run.

**Tech Stack:** R 4.1+, testthat edition 3, Quarto, hvtiRutilities,
hvtiRtables, hvtiPlotR, ggplot2, patchwork, digest, yaml, officer, flextable.

**Spec:**
`dev/specs/2026-09-15-legacy-study-template-migration-design.md`

## Global Constraints

- Work only in `hvtiRtemplates`; do not edit `hvtiRutilities`, `hvtiRtables`,
  `hvtiPlotR`, or `hvtiR`.
- Rebase onto the completed `add_job()` work before implementation and use
  `add_job()` throughout.
- Treat the current `hvtiR` catalog as a verification input. Its four rows are
  already `shipped`.
- Keep lines at or below 135 characters and give each new template its own
  file key in `.lintr`.
- Every template has its own `format:` block, exactly one `ENDPOINT <-` line,
  exactly one `TYPE <-` line, and an edit guard.
- No installed template, fixture, vignette, generated migration report, or
  test may contain a real study path, study name, dataset filename, or patient
  identifier value.
- A migration adapter removes an `EDIT:` marker only for deterministic source
  extraction. Inference remains visibly unresolved.
- Migration never changes the SAS source, listing, log, RTF, or DOCX evidence.
- `migrate_job()` refuses overwrite and leaves neither output file behind when
  either atomic placement fails.
- The tutorial runs only in a temporary directory during package checks.
- Do not write to `bio_aggrecan` until the live-acceptance task presents its
  exact write set and receives separate user approval.
- Do not bump `Version:` in this feature branch. Add shipped behavior beneath
  `# hvtiRtemplates (unreleased)` in `NEWS.md`.

---

### Task 1: Integrate the two prerequisite branches

**Files:**

- Modify only through rebase: files already changed by
  `codex/add-job-numbered-layout`
- Verify: `DESCRIPTION`, `NAMESPACE`, `R/add-job.R`,
  `tests/testthat/test-add-job.R`

**Interfaces:**

- Consumes: `add_job(prefix, endpoint, type, dir = ".", qualifier = NULL)`
- Consumes: `study_setup()`, `register_data()`, `study_dir()`,
  `read_built(..., dataset = "study")` from the completed utilities work
- Produces: a clean implementation baseline with no local reimplementation of
  either dependency

- [ ] **Step 1: Confirm both prerequisite tasks have stopped writing**

Run:

```bash
git -C /Users/ehrlinj/Documents/GitHub/hvtiRtemplates status --short --branch
git -C /Users/ehrlinj/Documents/GitHub/hvtiRutilities status --short --branch
```

Expected: the `add_job()` work and study API work are committed. If either
checkout is still dirty or its Codex task is active, stop this task and wait.

- [ ] **Step 2: Rebase onto the committed `add_job()` branch**

Run:

```bash
git rebase codex/add-job-numbered-layout
```

Expected: clean rebase. Resolve no semantic conflict by guessing; compare the
conflicting file with the design and the prerequisite branch before editing.

- [ ] **Step 3: Verify the required exports exist**

Run:

```bash
Rscript -e '
  pkgload::load_all()
  stopifnot(exists("add_job"))
  ns <- getNamespaceExports("hvtiRutilities")
  stopifnot(all(c("study_setup", "register_data", "study_dir",
                  "read_built") %in% ns))
'
```

Expected: exit 0.

- [ ] **Step 4: Run the clean baseline**

Run:

```bash
Rscript -e 'devtools::test()'
```

Expected: 0 failures and 0 warnings. Catalog tests may skip when `HVTI_JOBS`
is not set.

- [ ] **Step 5: Complete a stopped rebase after resolving observed conflicts**

```bash
git status --short
git add R/add-job.R R/templates.R tests/testthat/test-add-job.R
git rebase --continue
```

Run this step only when Step 2 stopped on one of these three prerequisite-owned
files. Expected: the rebase continues with the prerequisite commit message.

---

### Task 2: Add shared lexical parsers for migration evidence

**Files:**

- Create: `R/migration-parse.R`
- Create: `tests/testthat/test-migration-parse.R`
- Create: `tests/testthat/fixtures-migration/common/example.sas`
- Create: `tests/testthat/fixtures-migration/common/example.log`
- Create: `tests/testthat/fixtures-migration/common/example.lst`

**Interfaces:**

- Consumes: character vectors returned by `readLines()`
- Produces: `.source_lines(path)`, `.sas_mask_comments(lines)`,
  `.sas_calls(lines, name)`, `.sas_arguments(call)`,
  `.sas_grouped_vars(text)`, `.sas_log_findings(lines)`, and
  `.listing_facts(lines)`

- [ ] **Step 1: Write failing tests for comment masking and balanced calls**

```r
test_that("SAS parsing ignores commented calls and keeps source lines", {
  x <- c(
    "/* %desc_tab(vartype=bad, varlist=wrong); */",
    "%desc_tab(",
    "  vartype=category,",
    "  varlist= female race_grp,",
    "  by=repair);"
  )
  calls <- hvtiRtemplates:::.sas_calls(x, "desc_tab")
  expect_length(calls, 1L)
  expect_identical(calls[[1L]]$start, 2L)
  expect_match(calls[[1L]]$text, "female race_grp", fixed = TRUE)
})

test_that("SAS arguments retain empty and populated values", {
  call <- paste("vartype=continuous, by=, byvalue=0 1,",
                "varlist=age bmi")
  out <- hvtiRtemplates:::.sas_arguments(call)
  expect_identical(out$vartype, "continuous")
  expect_identical(out$by, "")
  expect_identical(out$byvalue, "0 1")
  expect_identical(out$varlist, "age bmi")
})
```

- [ ] **Step 2: Run the parser tests and confirm the functions are absent**

Run:

```bash
Rscript -e 'devtools::test(filter = "migration-parse")'
```

Expected: FAIL because `.sas_calls()` and `.sas_arguments()` do not exist.

- [ ] **Step 3: Implement balanced-call and argument parsing**

Create focused helpers with these signatures:

```r
.source_lines <- function(path) {
  lines <- readLines(path, warn = FALSE)
  data.frame(line = seq_along(lines), text = lines,
             stringsAsFactors = FALSE)
}

.sas_calls <- function(lines, name) {
  masked <- .sas_mask_comments(lines)
  # Locate "%name(" case-insensitively, then scan characters until the
  # matching closing parenthesis at nesting depth zero. Return a list of
  # list(start = integer(1), end = integer(1), text = character(1)).
}

.sas_arguments <- function(call) {
  # Split only on commas at parenthesis depth zero. Lower-case argument names,
  # trim values, and retain an empty string for `by=`.
}
```

`.sas_mask_comments()` must replace characters inside `/* ... */` with spaces
while preserving newlines and character positions. It must also mask
whole-line `* comment;` statements without masking multiplication.

- [ ] **Step 4: Add failing tests for grouped variables and evidence facts**

```r
test_that("group headings partition a SAS variable list", {
  x <- "/* Demography */ female race_grp /* Procedure */ repair replace"
  expect_identical(
    hvtiRtemplates:::.sas_grouped_vars(x),
    list(Demography = c("female", "race_grp"),
         Procedure = c("repair", "replace"))
  )
})

test_that("log and listing facts keep evidence line numbers", {
  log <- c("NOTE: There were 40 observations read", "WARNING: Missing values")
  lst <- c("Goodness of Follow-up", "N  Mean  Std Dev", "40  3.2  1.1")
  expect_equal(hvtiRtemplates:::.sas_log_findings(log)$severity,
               c("note", "warning"))
  expect_equal(hvtiRtemplates:::.listing_facts(lst)$line, 1:3)
})
```

- [ ] **Step 5: Implement the evidence helpers and rerun tests**

`.sas_grouped_vars()` returns a named list and errors on duplicate or empty
headings. `.sas_log_findings()` returns `line`, `severity`, and `text` for
`ERROR:`, `WARNING:`, and row-count `NOTE:` lines. `.listing_facts()` returns
nonblank lines with their original line numbers; adapters interpret them.

Run:

```bash
Rscript -e 'devtools::test(filter = "migration-parse")'
```

Expected: PASS.

- [ ] **Step 6: Commit the lexical layer**

```bash
git add R/migration-parse.R tests/testthat/test-migration-parse.R tests/testthat/fixtures-migration/common
git commit -m "feat: parse legacy job evidence"
```

---

### Task 3: Add the migration dispatcher, atomic writer, and report

**Files:**

- Create: `R/migrate-job.R`
- Create: `tests/testthat/helper-migration.R`
- Create: `tests/testthat/test-migrate-job.R`

**Interfaces:**

- Consumes: `add_job()`, `template_list()`, and parser helpers from Task 2
- Produces: exported
  `migrate_job(source, endpoint, type, prefix, qualifier = NULL, lst = NULL,
  log = NULL, reference = NULL, dir = ".")`
- Produces: adapter result with `regions` as a named character vector and
  `translated`, `unresolved`, and `ignored` as data frames
- Produces: `.migration_adapter(prefix, qualifier)`,
  `.replace_regions(lines, regions)`, `.migration_report()`, and
  `.write_migration_pair()`

- [ ] **Step 1: Write failing public-interface tests**

```r
test_that("migrate_job refuses unsupported and out-of-root sources", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "descriptive"))
  src <- withr::local_tempfile(fileext = ".sas")
  writeLines("proc means; run;", src)
  expect_error(
    migrate_job(src, "cohort", "eda", "ac", dir = root),
    "beneath the study root"
  )
  inside <- file.path(root, "descriptive", "job.sas")
  writeLines("proc means; run;", inside)
  expect_error(
    migrate_job(inside, "cohort", "eda", "ac", dir = root),
    "migration is not supported"
  )
})

test_that("optional evidence must exist when supplied", {
  root <- migration_study_fixture()
  source <- file.path(root, "descriptive", "dc.tables.sas")
  writeLines("%desc_tab(vartype=continuous, varlist=age);", source)
  expect_error(
    migrate_job(source,
                "cohort", "eda", "dc", "tables",
                log = file.path(root, "missing.log"), dir = root),
    "missing.log"
  )
})
```

Create `migration_study_fixture(kind = NULL)` in
`tests/testthat/helper-migration.R`. It makes only temporary bare study folders,
registers synthetic canonical and named CSV datasets, and copies fixtures when
`kind` names a fixture directory. It contains no real study metadata. Also
define `render_migrated_fixture(kind, root = NULL)` there; it selects the
fixture's fixed `(prefix, qualifier)` mapping, calls `migrate_job()`, removes
only fixture-declared review markers, renders the output with Quarto, and
returns the output paths.

- [ ] **Step 2: Run the test and confirm the export is absent**

Run:

```bash
Rscript -e 'devtools::test(filter = "migrate-job")'
```

Expected: FAIL because `migrate_job()` does not exist.

- [ ] **Step 3: Implement validation and adapter dispatch**

Use an explicit registry, not method-name construction:

```r
.migration_adapters <- function() {
  c(
    "dc\rtables" = ".migrate_dc_tables",
    "dc\rgfup" = ".migrate_dc_gfup",
    "dp\rtrends" = ".migrate_dp_trends",
    "dp\rpostage" = ".migrate_dp_postage"
  )
}

.migration_key <- function(prefix, qualifier) {
  paste(prefix, if (is.null(qualifier)) "" else qualifier, sep = "\r")
}
```

`.migration_adapter()` first rejects a key absent from this registry. For a
supported key, it resolves the stored function name inside the package
namespace and returns that adapter function.

Validate scalar fields through the same field checker used by `add_job()`.
Resolve `dir` and every evidence path with `normalizePath()`, then require the
source and evidence to remain beneath the normalized study root. Select the
template before invoking the adapter.

Call `add_job()` against a temporary staging root, never against `dir`. Read
the staged template, apply adapter regions there, and pass the finished text to
`.write_migration_pair()`. This preserves `add_job()` as the naming authority
without exposing its intermediate copy in the live study.

- [ ] **Step 4: Write failing tests for region replacement and atomic output**

```r
test_that("region replacement requires one complete marker pair", {
  x <- c("# MIGRATE-BEGIN: config", "old", "# MIGRATE-END: config")
  expect_identical(
    hvtiRtemplates:::.replace_regions(x, c(config = "new")),
    c("# MIGRATE-BEGIN: config", "new", "# MIGRATE-END: config")
  )
  expect_error(
    hvtiRtemplates:::.replace_regions(x[-3], c(config = "new")),
    "exactly one"
  )
})

test_that("pair placement rolls back the first file when the second fails", {
  root <- withr::local_tempdir()
  out <- file.path(root, "job.qmd")
  report <- file.path(root, "blocked", "job-migration.md")
  expect_error(
    hvtiRtemplates:::.write_migration_pair(c("job"), c("report"),
                                           out, report),
    "migration report"
  )
  expect_false(file.exists(out))
})
```

- [ ] **Step 5: Implement region replacement, reporting, and pair placement**

`.replace_regions()` requires exactly one begin and end line for every named
region. `.migration_report()` emits study-relative evidence paths, SHA-256
checksums, the package template/version, source line numbers, translated,
unresolved, and ignored sections, log findings, listing facts, and a checklist.
Quote no absolute path.

`.write_migration_pair()` prepares both files in their target directories,
refuses when either target exists, and uses backups plus `on.exit()` rollback
with the same all-or-neither semantics as utilities data registration.

- [ ] **Step 6: Document and export the function**

Add Rd-style roxygen to `R/migrate-job.R`. Use `\code{}`, `\itemize{}`, and
`\link{}`; roxygen markdown is not enabled in this package.

Run:

```bash
Rscript -e 'devtools::document()'
Rscript -e 'devtools::test(filter = "migrate-job|migration-parse")'
```

Expected: `man/migrate_job.Rd` and an updated `NAMESPACE`; tests pass.

- [ ] **Step 7: Commit the common migration API**

```bash
git add R/migrate-job.R R/migration-parse.R \
  tests/testthat/helper-migration.R tests/testthat/test-migrate-job.R \
  man/migrate_job.Rd NAMESPACE
git commit -m "feat: add template migration dispatcher"
```

---

### Task 4: Add `dc-tables` and its `%desc_tab` adapter

**Files:**

- Create: `inst/templates/10_descriptive/dc-tables.qmd`
- Create: `R/migrate-dc-tables.R`
- Create: `tests/testthat/test-migrate-dc-tables.R`
- Create: `tests/testthat/fixtures-migration/dc-tables/dc.tables.sas`
- Create: `tests/testthat/fixtures-migration/dc-tables/dc.tables.lst`
- Create: `tests/testthat/fixtures-migration/dc-tables/dc.tables.log`
- Create: `tests/testthat/fixtures-migration/dc-tables/general.rtf`
- Modify: `.lintr`, `DESCRIPTION`, `tests/testthat/test-templates.R`

**Interfaces:**

- Consumes: `.sas_calls()`, `.sas_arguments()`, `.sas_grouped_vars()`, and the
  adapter-result contract from Task 3
- Produces: `.migrate_dc_tables(evidence, template)`
- Produces: Word pipeline `hv_tbl_summary()` -> `hv_man_table()` ->
  `hv_man_table_save()` -> `hv_check_docx()`

- [ ] **Step 1: Add a synthetic `%desc_tab` fixture**

The fixture must include one categorical and one continuous call:

```sas
title3 "General Descriptive Analyses";
%desc_tab(vartype=category, input=built,
  varlist=/* Demography */ female race_grp /* Procedure */ repair,
  by=treatment, byvalue=0 1, countpersig=2,
  outrtf=&STUDY/documents/general_cate.rtf);
%desc_tab(vartype=continuous, input=built,
  varlist=/* Demography */ age bmi /* Follow-up */ iv_dead,
  by=treatment, byvalue=0 1, countpersig=2,
  outrtf=&STUDY/documents/general_cont.rtf);
```

The `.log` contains a 40-observation note and no error. The `.lst` contains the
title plus stable headings. `general.rtf` is a minimal text RTF with the same
title and headings, not a copied study artifact.

- [ ] **Step 2: Write the failing adapter test**

```r
test_that("dc-tables migrates desc_tab groups and types", {
  root <- migration_study_fixture("dc-tables")
  out <- migrate_job(
    file.path(root, "descriptive", "dc.tables.sas"),
    "cohort", "eda", "dc", "tables",
    lst = file.path(root, "descriptive", "dc.tables.lst"),
    log = file.path(root, "descriptive", "dc.tables.log"),
    reference = file.path(root, "documents", "general.rtf"),
    dir = root
  )
  txt <- readLines(out, warn = FALSE)
  expect_true(any(grepl('BY <- "treatment"', txt, fixed = TRUE)))
  expect_true(any(grepl('Demography = c("female", "race_grp", "age", "bmi")',
                        txt, fixed = TRUE)))
  expect_true(any(grepl('CONTINUOUS <- c("age", "bmi", "iv_dead")',
                        txt, fixed = TRUE)))
  expect_true(any(grepl('CATEGORICAL <- c("race_grp")', txt, fixed = TRUE)))
  expect_true(any(grepl('BINARY <- c("female", "repair")', txt, fixed = TRUE)))
})
```

The adapter may classify `female` and `repair` as binary only because the
synthetic fixture's registered dataset proves they are 0/1. A source-only run
without readable registered data leaves that split unresolved.

- [ ] **Step 3: Run the focused test and confirm the template is missing**

Run:

```bash
Rscript -e 'devtools::test(filter = "migrate-dc-tables")'
```

Expected: FAIL because `dc-tables` is not installed.

- [ ] **Step 4: Create the runnable template**

The editable region must use these declarations:

```r
# MIGRATE-BEGIN: dc-tables-config
DATASET <- "study"
BY <- NULL
GROUPS <- list(Demography = c("age")) # EDIT: replace with grouped rows
CONTINUOUS <- "age"                   # EDIT: classify every grouped row
BINARY <- character(0)
CATEGORICAL <- character(0)
COMPARE <- "none"
CONTINUOUS_STAT <- "median"
PERCENTILES <- c(15, 85)
ABBREVIATIONS <- character(0)
WORD_FILE <- "dc-tables.docx"
# MIGRATE-END: dc-tables-config
```

Read with:

```r
cfg <- study_config(.root)
d <- read_built(cfg, dataset = DATASET)
tbl <- hvtiRtables::hv_tbl_summary(
  d, by = BY, groups = GROUPS, continuous = CONTINUOUS,
  binary = BINARY, categorical = CATEGORICAL, compare = COMPARE,
  percentiles = PERCENTILES, continuous_stat = CONTINUOUS_STAT
)
ft <- hvtiRtables::hv_man_table(tbl)
word_path <- file.path(study_dir("documents", .root),
                       paste0(ENDPOINT, "-", TYPE), WORD_FILE)
dir.create(dirname(word_path), recursive = TRUE, showWarnings = FALSE)
hvtiRtables::hv_man_table_save(ft, word_path,
                               abbreviations = ABBREVIATIONS)
check <- hvtiRtables::hv_check_docx(word_path)
if (nrow(check)) stop("Word output failed the CORR structural check")
```

Use the established setup, edit-guard, set-marker, and provenance structure
from `dp-trends.qmd`; do not invent a second version.

- [ ] **Step 5: Implement `.migrate_dc_tables()`**

Require at least one `%desc_tab` call. Parse `vartype`, `varlist`, `by`,
`byvalue`, `countpersig`, and `outrtf`. Merge same-named group headings in
source order and reject a variable appearing in two groups. Use registered
data only to distinguish 0/1 variables from multi-level categorical variables.
Generate the exact R declarations consumed by the template region.

- [ ] **Step 6: Add dependency and template-contract tests**

Add to `Suggests`:

```text
hvtiRtables (>= 1.0.1)
```

Add a file-specific `.lintr` entry for `dc-tables.qmd`. Extend template tests
to assert `hv_tbl_summary`, `hv_man_table`, `hv_man_table_save`,
`hv_check_docx`, `study_dir("documents"`, and dataset selection appear in the
code chunks.

- [ ] **Step 7: Run focused tests and render the synthetic migration**

Run:

```bash
Rscript -e 'devtools::test(filter = "migrate-dc-tables|templates")'
Rscript -e 'pkgload::load_all(); source("tests/testthat/helper-migration.R"); render_migrated_fixture("dc-tables")'
```

Expected: tests pass; the rendered job writes a structurally clean DOCX in the
fixture's `documents/cohort-eda/` directory.

- [ ] **Step 8: Commit `dc-tables`**

```bash
git add inst/templates/10_descriptive/dc-tables.qmd \
  R/migrate-dc-tables.R tests/testthat/test-migrate-dc-tables.R \
  tests/testthat/fixtures-migration/dc-tables \
  tests/testthat/test-templates.R .lintr DESCRIPTION
git commit -m "feat: migrate descriptive table jobs"
```

---

### Task 5: Add `dc-gfup` and its follow-up adapter

**Files:**

- Create: `inst/templates/10_descriptive/dc-gfup.qmd`
- Create: `R/migrate-dc-gfup.R`
- Create: `tests/testthat/test-migrate-dc-gfup.R`
- Create: `tests/testthat/fixtures-migration/dc-gfup/dc.gfup.sas`
- Create: `tests/testthat/fixtures-migration/dc-gfup/dc.gfup.lst`
- Create: `tests/testthat/fixtures-migration/dc-gfup/dc.gfup.log`
- Modify: `.lintr`, `tests/testthat/test-templates.R`

**Interfaces:**

- Consumes: shared parser and adapter-result contracts
- Produces: `.migrate_dc_gfup(evidence, template)`
- Produces: follow-up QC through `hvtiRutilities::proc_means()`

- [ ] **Step 1: Add a synthetic follow-up fixture and failing test**

The fixture must contain `var iv_dead`, `var iv_fup`, `by dead`, `id study_id`,
and `if dead=0`. Use `study_id` only in the synthetic fixture.

```r
test_that("dc-gfup extracts event and follow-up fields", {
  root <- migration_study_fixture("dc-gfup")
  out <- migrate_job(
    file.path(root, "descriptive", "dc.gfup.sas"),
    "cohort", "eda", "dc", "gfup", dir = root
  )
  txt <- readLines(out, warn = FALSE)
  expect_true(any(grepl('EVENT <- "dead"', txt, fixed = TRUE)))
  expect_true(any(grepl('FOLLOWUP <- c("iv_dead", "iv_fup")',
                        txt, fixed = TRUE)))
  expect_true(any(grepl("IDENTIFIER <- NULL", txt, fixed = TRUE)))
  report <- readLines(sub("[.]qmd$", "-migration.md", out), warn = FALSE)
  expect_false(any(grepl("study_id", txt, fixed = TRUE)))
  expect_true(any(grepl("study_id", report, fixed = TRUE)))
})
```

The identifier appears only in the migration report's unresolved evidence,
not as an enabled template value.

- [ ] **Step 2: Run the focused test and confirm failure**

```bash
Rscript -e 'devtools::test(filter = "migrate-dc-gfup")'
```

Expected: FAIL because the template and adapter do not exist.

- [ ] **Step 3: Create the follow-up template**

Use this migration region:

```r
# MIGRATE-BEGIN: dc-gfup-config
DATASET <- "study"
EVENT <- "dead"                    # EDIT: event indicator
FOLLOWUP <- "iv_dead"              # EDIT: follow-up interval(s), in years
IDENTIFIER <- NULL                  # EDIT: opt in only for local review
MAX_REVIEW_ROWS <- 25L
# MIGRATE-END: dc-gfup-config
```

Validate that all selected fields exist, event is binary, follow-up is numeric,
and `MAX_REVIEW_ROWS` is one positive integer. For each interval, report
missing, negative, zero, minimum, quartiles, mean, SD, and maximum. Use
`proc_means()` on the full data and on event/censored subsets. Print no more
than `MAX_REVIEW_ROWS` suspicious rows and omit identifiers unless explicitly
enabled.

- [ ] **Step 4: Implement `.migrate_dc_gfup()`**

Extract `VAR`, `BY`, `ID`, sort statements, and simple `if <event>=0` survivor
filters outside comments. Deterministically populate event and interval fields
when the source agrees across sections. Record derived date arithmetic,
`%inc vars`, and commented event scaffolding as unresolved evidence.

- [ ] **Step 5: Add failure and privacy tests**

```r
test_that("dc-gfup keeps identifiers disabled", {
  result <- hvtiRtemplates:::.migrate_dc_gfup(gfup_evidence(),
                                               gfup_template())
  expect_match(result$regions[["dc-gfup-config"]], "IDENTIFIER <- NULL")
  expect_true(any(grepl("study_id", result$unresolved$text, fixed = TRUE)))
})

test_that("dc-gfup rejects contradictory event fields", {
  evidence <- gfup_evidence(extra = "proc sort; by stroke; run;")
  expect_error(hvtiRtemplates:::.migrate_dc_gfup(evidence,
                                                  gfup_template()),
               "contradictory event")
})
```

- [ ] **Step 6: Add `.lintr`, run tests, and render**

```bash
Rscript -e 'devtools::test(filter = "migrate-dc-gfup|templates")'
Rscript -e 'pkgload::load_all(); source("tests/testthat/helper-migration.R"); render_migrated_fixture("dc-gfup")'
```

Expected: pass; the rendered report contains the expected 40-row full cohort
and the fixture's event/censored counts.

- [ ] **Step 7: Commit `dc-gfup`**

```bash
git add inst/templates/10_descriptive/dc-gfup.qmd \
  R/migrate-dc-gfup.R tests/testthat/test-migrate-dc-gfup.R \
  tests/testthat/fixtures-migration/dc-gfup \
  tests/testthat/test-templates.R .lintr
git commit -m "feat: migrate follow-up summary jobs"
```

---

### Task 6: Add the `dp-trends` migration adapter

**Files:**

- Modify: `inst/templates/40_graphs/dp-trends.qmd`
- Create: `R/migrate-dp-trends.R`
- Create: `tests/testthat/test-migrate-dp-trends.R`
- Create: `tests/testthat/fixtures-migration/dp-trends/dp.trends.sas`
- Create: `tests/testthat/fixtures-migration/dp-trends/dp.trends.lst`
- Create: `tests/testthat/fixtures-migration/dp-trends/dp.trends.log`

**Interfaces:**

- Consumes: the existing `dp-trends` template and shared adapter contract
- Produces: `.migrate_dp_trends(evidence, template)`
- Preserves: `hvtiPlotR::hv_trends()` as the compute engine

- [ ] **Step 1: Write a failing adapter test**

The fixture constructs `year=floor(iv_opyrs)+1985`, trends one 0/1 variable
and one continuous variable, labels both, and gives five-year x breaks.

```r
test_that("dp-trends extracts year origin and trend definitions", {
  root <- migration_study_fixture("dp-trends")
  out <- migrate_job(file.path(root, "graphs", "dp.trends.sas"),
                     "cohort", "eda", "dp", "trends", dir = root)
  txt <- readLines(out, warn = FALSE)
  expect_true(any(grepl("floor(d$iv_opyrs) + 1985", txt, fixed = TRUE)))
  expect_true(any(grepl("hx_chf", txt, fixed = TRUE)))
  expect_true(any(grepl("lvmassi", txt, fixed = TRUE)))
  expect_true(any(grepl("seq(1985, 2025, 5)", txt, fixed = TRUE)))
})
```

- [ ] **Step 2: Run and confirm failure**

```bash
Rscript -e 'devtools::test(filter = "migrate-dp-trends")'
```

Expected: FAIL because no adapter is registered.

- [ ] **Step 3: Add stable migration regions to `dp-trends.qmd`**

Wrap the existing year, `TRENDS`, `XBREAKS`, and stratum declarations in named
`MIGRATE-BEGIN`/`MIGRATE-END` pairs. Add `DATASET <- "study"` and change the
reader to:

```r
d <- read_built(study_config(.root), dataset = DATASET)
```

Do not change plot computation, file naming, edit guard, or prose outside the
minimum needed migration regions.

- [ ] **Step 4: Implement `.migrate_dp_trends()`**

Recognise simple whole-year assignments, source variable lists, binary versus
continuous plot intent, labels, x limits, and breaks. Translate an explicit
`floor(interval) + origin`. If the origin is inferred only from data or prose,
prefill it behind the original `EDIT:` marker and quote the source line in the
report. Record hand-written summarisation and smooths as replaced by
`hv_trends()`.

- [ ] **Step 5: Prove existing template behavior did not regress**

```bash
Rscript -e 'devtools::test(filter = "migrate-dp-trends|templates|add-job")'
Rscript -e 'pkgload::load_all(); source("tests/testthat/helper-migration.R"); render_migrated_fixture("dp-trends")'
```

Expected: all prior `dp-trends` and `add_job()` tests pass; migrated fixture
renders and writes its PNG files under `graphs/cohort-eda/`.

- [ ] **Step 6: Commit the trends adapter**

```bash
git add inst/templates/40_graphs/dp-trends.qmd R/migrate-dp-trends.R \
  tests/testthat/test-migrate-dp-trends.R \
  tests/testthat/fixtures-migration/dp-trends
git commit -m "feat: migrate trend plot jobs"
```

---

### Task 7: Add `dp-postage` and its `hv_eda()` adapter

**Files:**

- Create: `inst/templates/10_descriptive/dp-postage.qmd`
- Create: `R/migrate-dp-postage.R`
- Create: `tests/testthat/test-migrate-dp-postage.R`
- Create: `tests/testthat/fixtures-migration/dp-postage/dp.postage.qmd`
- Modify: `R/templates.R`, `.lintr`, `DESCRIPTION`,
  `tests/testthat/test-taxonomy.R`, `tests/testthat/test-templates.R`

**Interfaces:**

- Consumes: `hvtiPlotR::hv_eda()`, `patchwork::wrap_plots()`, and shared
  migration contracts
- Produces: `.migrate_dp_postage(evidence, template)`
- Produces: `.template_folder_authority(prefix, qualifier, catalog)`
- Produces: deterministic PNG pages under `graphs/<endpoint>-<type>/`

- [ ] **Step 1: Write failing template and adapter tests**

```r
test_that("postage migration extracts explicit EDA controls", {
  root <- migration_study_fixture("dp-postage")
  out <- migrate_job(file.path(root, "descriptive", "dp.postage.qmd"),
                     "cohort", "eda", "dp", "postage", dir = root)
  txt <- readLines(out, warn = FALSE)
  expect_true(any(grepl('X_VAR <- "iv_dead"', txt, fixed = TRUE)))
  report <- readLines(sub("[.]qmd$", "-migration.md", out), warn = FALSE)
  expect_true(any(grepl("color choice remains unresolved", report,
                        fixed = TRUE)))
  expect_true(any(grepl("GRID_NCOL <- 4L", txt, fixed = TRUE)))
  expect_true(any(grepl("GRID_NROW <- 4L", txt, fixed = TRUE)))
})

test_that("postage pages are deterministic", {
  expect_identical(hvtiRtemplates:::.postage_pages(letters[1:18], 4L, 4L),
                   list(letters[1:16], letters[17:18]))
})
```

- [ ] **Step 2: Run and confirm the template is absent**

```bash
Rscript -e 'devtools::test(filter = "migrate-dp-postage")'
```

Expected: FAIL because `dp-postage` is not installed.

- [ ] **Step 3: Create the postage template**

Use this migration region:

```r
# MIGRATE-BEGIN: dp-postage-config
DATASET <- "study"
X_VAR <- "iv_dead"                 # EDIT: reference time or year
VARIABLES <- c("age")              # EDIT: variables shown as panels
EXCLUDE <- character(0)
GRID_NCOL <- 4L
GRID_NROW <- 4L
UNIQUE_LIMIT <- 6L
SHOW_PERCENT <- FALSE
# MIGRATE-END: dp-postage-config
```

Validate every field and warn when `VARIABLES` includes likely identifiers or
date/datetime names. Build plots exactly as:

```r
plots <- lapply(VARIABLES, function(variable) {
  plot(hvtiPlotR::hv_eda(
    d, x_col = X_VAR, y_col = variable,
    y_label = get_label(label_map(d), variable),
    unique_limit = UNIQUE_LIMIT, show_percent = SHOW_PERCENT
  ))
})
pages <- split(plots, ceiling(seq_along(plots) / (GRID_NCOL * GRID_NROW)))
page_plots <- lapply(pages, patchwork::wrap_plots,
                     ncol = GRID_NCOL, nrow = GRID_NROW)
```

Save `dp-postage-page-01.png`, `dp-postage-page-02.png`, and so on under the
set's logical graphs directory. Embed those exact files in the job.

- [ ] **Step 4: Implement `.migrate_dp_postage()`**

Recognise `dta_filename`, `pref_time_var`, `pref_color_var`, `stratify_by`,
explicit variable lists, exclusion lists, `ncol`, `nrow`, `alpha`, and simple
scale declarations in the legacy QMD or SAS source. Record `pref_color_var` as
unresolved because `hv_eda()` has no color-variable argument. Put every
study-specific cleaning assignment into `unresolved`; never copy it into the
executable template region.

- [ ] **Step 5: Fix folder authority without changing taxonomy**

Change the template placement test so each template first joins the live job
catalog on `(prefix, qualifier)` and uses that row's `folder`. When the catalog
is unavailable or has no row, fall back to `hvti_taxonomy()`.

The divergent assertion must use a temporary catalog:

```r
test_that("catalog folder overrides coarse taxonomy for a qualified template", {
  catalog <- data.frame(prefix = "dp", qualifier = "postage",
                        folder = "descriptive")
  expect_identical(
    hvtiRtemplates:::.template_folder_authority(
      "dp", "postage", catalog
    ),
    "descriptive"
  )
})
```

Implement `.template_folder_authority()` in `R/templates.R`. Match both prefix
and qualifier, require at most one catalog row, and use coarse taxonomy only
when the catalog is absent or contains no matching row.

- [ ] **Step 6: Add dependencies and render tests**

Require `hvtiPlotR (>= 2.7.13)` and `patchwork (>= 1.1.0)` in `Suggests`. Add
the file-specific `.lintr` entry.

Run:

```bash
Rscript -e 'devtools::test(filter = "migrate-dp-postage|taxonomy|templates")'
Rscript -e 'pkgload::load_all(); source("tests/testthat/helper-migration.R"); render_migrated_fixture("dp-postage")'
```

Expected: pass; an 18-variable fixture writes two PNGs named with two-digit
page numbers.

- [ ] **Step 7: Commit `dp-postage`**

```bash
git add inst/templates/10_descriptive/dp-postage.qmd \
  R/migrate-dp-postage.R tests/testthat/test-migrate-dp-postage.R \
  tests/testthat/fixtures-migration/dp-postage \
  tests/testthat/test-taxonomy.R tests/testthat/test-templates.R \
  .lintr DESCRIPTION
git commit -m "feat: migrate EDA postage stamp jobs"
```

---

### Task 8: Add the runnable legacy-adoption tutorial

**Files:**

- Create: `vignettes/legacy-study-migration.qmd`
- Modify: `tests/testthat/helper-migration.R`
- Create: `tests/testthat/test-vignette-migration.R`
- Modify: `DESCRIPTION`

**Interfaces:**

- Consumes: `study_setup()`, `register_data()`, `migrate_job()`, and all four
  adapters
- Produces: an installed vignette titled "Migrate a legacy study to R jobs"
- Extends: `render_migrated_fixture(kind, root = NULL)` for package tests only
- Produces: `render_all_migration_fixtures()` for the final verification task

- [ ] **Step 1: Write the failing vignette test**

```r
test_that("legacy migration vignette declares the complete workflow", {
  path <- test_path("..", "..", "vignettes",
                    "legacy-study-migration.qmd")
  expect_true(file.exists(path))
  txt <- readLines(path, warn = FALSE)
  expect_true(any(grepl("adopt = TRUE", txt, fixed = TRUE)))
  expect_true(any(grepl("role = \"study\"", txt, fixed = TRUE)))
  expect_true(any(grepl("role = \"named\"", txt, fixed = TRUE)))
  for (q in c("tables", "gfup", "trends", "postage")) {
    expect_true(any(grepl(paste0('qualifier = "', q, '"'), txt,
                          fixed = TRUE)))
  }
})
```

- [ ] **Step 2: Run and confirm failure**

```bash
Rscript -e 'devtools::test(filter = "vignette-migration")'
```

Expected: FAIL because the QMD is absent.

- [ ] **Step 3: Complete the disposable legacy rendering helpers**

Confirm `migration_study_fixture()` creates these bare folders beneath
`withr::local_tempdir()` when no root is supplied:

```text
datasets/ descriptive/ distributions/ analyses/ graphs/ documents/ estimates/
```

Write a 40-row canonical CSV and a deterministic 24-row named subset CSV. Both
contain `dead`, `iv_dead`, `iv_fup`, `year`, `female`, `race_grp`, `repair`,
`age`, `bmi`, `hx_chf`, and `lvmassi`. Copy only the synthetic migration
fixtures requested by `kind`.

Repeat the small synthetic fixture setup in a hidden vignette chunk. The
installed vignette must not source a helper under `tests/`.

Add the final verifier:

```r
render_all_migration_fixtures <- function() {
  kinds <- c("dc-tables", "dc-gfup", "dp-trends", "dp-postage")
  stats::setNames(lapply(kinds, render_migrated_fixture), kinds)
}
```

- [ ] **Step 4: Write the vignette**

Start from the familiar legacy tree and show its files before adoption. Use:

```r
study_setup(root, study = "Synthetic legacy study",
            study_tracker_id = 42L, adopt = TRUE)
register_data(root, built = "built.csv", event = "dead", time = "iv_dead",
              role = "study", population = "Synthetic full cohort")
register_data(root, built = "complete_cases.csv", event = "dead",
              time = "iv_dead", dataset = "complete_cases",
              role = "named", population = "Synthetic complete cases")
```

Then call `migrate_job()` once per qualifier. Use the named subset for one job
and the canonical dataset for the others. Show the migration report, resolve
the synthetic fixture's remaining markers, render, and inspect the resulting
DOCX and PNG paths. Explain why study-wide and named-dataset cohort counts stay
separate.

- [ ] **Step 5: Configure Quarto vignette dependencies**

Add:

```text
VignetteBuilder: quarto
```

and add `knitr`, `quarto`, and `withr` to `Suggests` if absent. Keep the QMD's
own `format:` and vignette metadata block. Do not add a `reference:` section to
`_pkgdown.yml`.

- [ ] **Step 6: Render and test**

Run:

```bash
quarto render vignettes/legacy-study-migration.qmd --to html
Rscript -e 'devtools::test(filter = "vignette-migration|migrate")'
```

Expected: the vignette renders without accessing `/Volumes`; all migration
tests pass.

- [ ] **Step 7: Commit the tutorial**

```bash
git add vignettes/legacy-study-migration.qmd \
  tests/testthat/helper-migration.R \
  tests/testthat/test-vignette-migration.R DESCRIPTION
git commit -m "docs: teach legacy study job migration"
```

---

### Task 9: Update shipped documentation and run strict catalog checks

**Files:**

- Modify: `README.md`
- Modify: `inst/templates/README.md`
- Modify: `NEWS.md`
- Modify: `R/templates.R` roxygen if template-count prose is stale
- Regenerate: `man/*.Rd`, `NAMESPACE`, `DESCRIPTION`

**Interfaces:**

- Consumes: the completed templates, migration API, and existing catalog rows
- Produces: current installed documentation and release notes

- [ ] **Step 1: Update the template inventory and API examples**

Add the three new templates to `inst/templates/README.md`, including their bare
destination folders. Add `migrate_job()` to the root API table and show one
`dc-tables` migration call. Replace stale `new_job()` prose with `add_job()` if
the prerequisite branch did not already do so.

- [ ] **Step 2: Add the unreleased NEWS entry**

Under `# hvtiRtemplates (unreleased)`, state that the package now ships the
three EDA templates, template-specific migration for four EDA job types, and a
legacy-adoption tutorial. Name the RTF-to-CORR-DOCX path and the rule that
uncertain translation remains an `EDIT:` marker.

- [ ] **Step 3: Run the no-AI-slop pass and repository style checks**

```bash
rg -n 'delve|foster|leverage|utilize|facilitate|empower|streamline|robust' \
  README.md NEWS.md inst/templates/README.md \
  vignettes/legacy-study-migration.qmd
rg -n 'cutting-edge|paradigm shift|game changer|tapestry|realm|beacon' \
  README.md NEWS.md inst/templates/README.md \
  vignettes/legacy-study-migration.qmd
awk 'length($0) > 135 { print FILENAME ":" FNR ":" length($0) }' \
  README.md NEWS.md inst/templates/README.md \
  vignettes/legacy-study-migration.qmd R/*.R tests/testthat/*.R
```

Expected: no banned prose and no newly introduced overlong lines.

- [ ] **Step 4: Regenerate package documentation**

```bash
Rscript -e 'devtools::document()'
git diff --check
```

Expected: generated files match roxygen and no whitespace errors appear.

- [ ] **Step 5: Run catalog-backed tests against the real catalog**

Run:

```bash
HVTI_JOBS=/Users/ehrlinj/Documents/GitHub/hvtiR/inst/extdata/jobs.json \
  Rscript -e 'devtools::test(filter = "roadmap|taxonomy|templates")'
python3 dev/specs/artifacts/check-roadmap-counts.py
python3 dev/specs/artifacts/check-spec-counts.py
python3 dev/specs/artifacts/check-flow-counts.py
```

Expected: no skips in catalog-reading tests; the catalog's four shipped rows
match templates on disk; all three count checks pass. Do not edit the catalog
to make the test green.

- [ ] **Step 6: Commit documentation**

```bash
git add README.md inst/templates/README.md NEWS.md R/templates.R man NAMESPACE DESCRIPTION
git commit -m "docs: document legacy job migration"
```

---

### Task 10: Run full package verification

**Files:**

- Verify only; modify the owning task's files when a failure is found

**Interfaces:**

- Consumes: all implementation tasks
- Produces: evidence for the repository definition of done

- [ ] **Step 1: Render all four migration targets**

Use the synthetic study helper to create completed jobs for the three new
templates and the migrated `dp-trends` template. Confirm every output exists
and no render uses draft mode.

Run:

```bash
Rscript -e 'pkgload::load_all(); source("tests/testthat/helper-migration.R"); render_all_migration_fixtures()'
```

Expected: four HTML jobs, one DOCX, and deterministic PNG pages.

- [ ] **Step 2: Run lint and documentation-current checks**

```bash
Rscript -e 'lintr::lint_package()'
Rscript -e 'devtools::document()'
git diff --exit-code man NAMESPACE DESCRIPTION
```

Expected: no new lints and no generated-file drift.

- [ ] **Step 3: Run the complete test suite with the catalog present**

```bash
HVTI_JOBS=/Users/ehrlinj/Documents/GitHub/hvtiR/inst/extdata/jobs.json Rscript -e 'devtools::test()'
```

Expected: 0 failures, 0 warnings, and no catalog skips.

- [ ] **Step 4: Run the package check**

```bash
Rscript -e 'devtools::check(error_on = "note")'
```

Expected: 0 errors, 0 warnings, 0 notes.

- [ ] **Step 5: Review the complete branch diff**

```bash
git diff --check main...HEAD
git status --short --branch
git log --oneline --decorate main..HEAD
```

Expected: only `hvtiRtemplates` changes, a clean worktree, and the task-sized
commits listed above.

- [ ] **Step 6: Commit any verification-only correction in its owning task**

Do not create a miscellaneous cleanup commit. Amend or add a focused commit
whose message names the failed contract, then rerun Steps 1 through 5.

---

### Task 11: Validate against `bio_aggrecan` after a write-set review

**Files:**

- Read:
  `/Volumes/qhsstudies/vascular/thoracic-aorta/aneurysm/ascending/biomechanics/bio_aggrecan/`
- Create after approval: package-owned study state and four migrated jobs in
  that study
- Create in this branch:
  `dev/specs/artifacts/2026-09-15-bio-aggrecan-migration-acceptance.md`

**Interfaces:**

- Consumes: the verified package and the real legacy study
- Produces: a redacted acceptance record; produces no study data in this repo

- [ ] **Step 1: Wait for the share and inventory read-only**

List the study root, logical folders, candidate built/subset datasets, matching
SAS/LST/log files, and RTF files in `documents/`. Record file sizes, dates, and
SHA-256 checksums. Read `_study.yml` and `manifest.yaml` if present. Do not
write, adopt, register, or scaffold in this step.

- [ ] **Step 2: Resolve the exact migration mapping**

Prepare a table with these columns:

```text
role | registered name | dataset file | event | time | SAS source | LST | log | RTF/DOCX reference | output job
```

Every field must name an observed file or value. Do not infer the canonical
dataset, subset role, event, or time from a filename alone.

- [ ] **Step 3: Present the write set and recovery path for approval**

Show every file that `study_setup(adopt = TRUE)`, both `register_data()` calls,
and four `migrate_job()` calls would create or modify. State which files can be
restored from the pre-write checksums. Stop and wait for explicit approval.

- [ ] **Step 4: Adopt and register only the approved datasets**

Run the exact reviewed calls. After each call, compare every pre-existing file
checksum with the inventory. Expected: only the approved package-owned files
change; every legacy SAS, listing, log, RTF, dataset, and authored file remains
byte-identical.

- [ ] **Step 5: Migrate all four jobs**

Call `migrate_job()` with the observed source and evidence paths. Review the
four migration reports. Resolve `EDIT:` markers from the source and protocol;
do not infer missing scientific choices.

- [ ] **Step 6: Render and compare outputs**

Render all four jobs without draft mode. For `dc-tables`, compare the DOCX with
the SAS RTF references for row order, labels, counts, statistics, displayed
precision, headings, and footnotes. Run `hv_check_docx()` and open the DOCX in
Word to confirm it remains editable.

- [ ] **Step 7: Write the redacted acceptance record**

Record package versions, source checksums, created relative paths, unresolved
items, render results, DOCX structural results, and parity findings. Exclude
study data, patient identifiers, absolute share paths, and study-specific
variable values not needed to explain a mismatch.

- [ ] **Step 8: Commit only the redacted record**

```bash
git add dev/specs/artifacts/2026-09-15-bio-aggrecan-migration-acceptance.md
git commit -m "test: validate legacy study migration"
```

Expected: the package branch contains the acceptance record, not the live
study files.
