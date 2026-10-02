# The `00_datasets` level: a `bd` build job (master, subset, publish, register)

**Date:** 2026-10-02
**Status:** design. Every decision in section 3 was made by John Ehrlinger on 2026-10-01
and 2026-10-02, in the order listed. Nothing is built yet.
**Issue:** [hvtiRtemplates#223](https://github.com/ehrlinger/hvtiRtemplates/issues/223),
including its 2026-10-01 comment on where the job reads from.
**Reads with:** `2026-09-29-template-data-contract-design.md` (the downstream contract this
job feeds), hvtiRdatabuild's `2026-09-23-cardiac-master-view-design.md` (masters as
warehouse views reached through a parquet snapshot) and `2026-09-02-vars-port-and-attrition-design.md`,
and [hvtiRdatabuild#71](https://github.com/ehrlinger/hvtiRdatabuild/issues/71) (console-only
targeted prints).
**Packages:** `hvtiRtemplates` (the template and one new exported helper). `hvtiRdatabuild`
and `hvtiRutilities` are called, not changed.

This note is self-contained. It assumes no memory of the session that produced it.

⚠️ No study, variable value or patient identifier appears here. `ccfid`, `MRN`, `eMRN` and
`dt_surg` are column names, not values. The exemplars in section 2 are described generically.

## 1. What was asked, and why it blocks

Every analysis template reads a registered dataset through `read_job_data()`, after
`verify_manifest()` accepts it, and no job produces one. The template catalog has
`10_descriptive` through `40_graphs` and no `00_datasets`, although the folder is already in
the taxonomy and `study_setup()` already creates it. At the 2026-10-01 stat programmer
session the walkthrough stopped at "start from a built dataset". The new-study guide
(`vignettes/new-study.qmd`) starts from a delivered dataset for the same reason, and is
reopened once this ships.

The first build job covers the common path: subset a master (the cardiac master, or a child
such as the mitral master), record who was dropped and why, write a draft, publish it as a
dated release, and register that release with the study.

## 2. What was measured before designing

### 2.1 The package surface (installed versions, read 2026-10-01)

| Fact | Consequence |
|---|---|
| `hvti_taxonomy()`: prefix `bd`, "assembles raw sources into the analytic dataset", folder `datasets` | the job is `bd`, unqualified |
| `templates.json` already has a `bd` row: `status: queued`, `blocked_on: hvtiRdatabuild`, `r_exemplars: 15` | the ledger row exists; it changes state, no new row |
| `study_setup()` creates `00_datasets/` (checked on a temporary study) | acceptance item 1's folder half needs a test, not code |
| `add_job()` places through `hvtiRutilities::study_dir(row$folder)`, and `study_dir("datasets")` resolves to `00_datasets/` | `add_job("bd", ...)` should work unchanged; a test proves it |
| `publish_dataset()` (hvtiRdatabuild 0.2.3) accepts `.rds`, `.csv`, `.sas7bdat`, `.xlsx`, `.xls`, **not parquet** | the job reads parquet and writes an `.rds` draft |
| `snapshot_master()` writes one parquet per master build with a `.meta.json` sidecar (SHA-256, rows, parent release). `master.yml` does not record where the parquet went | the job names the parquet directly (decision 4) |
| The cardiac master snapshot is roughly 36 GB | the read must push columns and conditions down to arrow before `collect()` |
| hvtiRdatabuild `main` is 0.2.4; 0.2.3 is installed | the Suggests floor rises to 0.2.3, the first release with `publish_dataset()` |

### 2.2 Publish and register compose, once (synthetic probe, 2026-10-02)

On a `study_setup()` study, with `datasets_dir = study_dir("datasets")`:

1. `publish_dataset(draft.rds, "syn_study", ...)` wrote `syn_study_20261002.rds` and
   `dataset-catalog.yml` in `00_datasets/`, release `syn_study-20261002-r1`.
2. Re-saving the same object with `saveRDS()` and publishing again returned the **same**
   release. Publication is idempotent across a resave, so a re-render with no change mints
   nothing.
3. `register_data(built = <release file>, catalog_dataset =, release_id =)` succeeded and
   `verify_manifest()` passed.
4. A changed draft published as `-r2`, and a second `register_data()` stopped with
   **"the default dataset is already registered"**. Moving a study to a newer release is
   `adopt_data_update(release_id =)`. Decision 9 follows from this.

### 2.3 Exemplars (the two-study rule)

Five SAS build jobs on the studies share, all `<area>/<subarea>/<study>/datasets/bd.data.sas`,
all reading a master and subsetting it. No R or Quarto build job exists anywhere on the
share. The rule is met several times over. One skeleton recurs: header macro variables, a
`libname` to the study's datasets and one to a master, `set <master>.built[_<date>]`, a
cohort join or predicate filter, derived intervals and labels, `data library.built`, then
`proc contents` and `proc means`.

| Observed | Studies | Design response |
|---|---|---|
| Pinning a dated master snapshot (`built_<date>`) | the newer jobs | `MASTER` names one snapshot file (decision 4) |
| Cohort is an external list (REDCap export or data-request CSV) joined on (patient ID, surgery date), with an `exclude` flag on the list | 3 of 5 | optional `COHORT` (decision 6) |
| Cohort is predicates on the master (`if ... then delete`) | 2 of 5 | `EXCLUDE` rules (decision 2) |
| Derived intervals, mortality, indicators, labels | 5 of 5 | a `derive` chunk (decision 7) |
| One row per patient via `first.ccfid` | 2 of 5 | an `EXCLUDE` example, plus the `KEY` check |
| Column keep lists, in a later `sas2r` step, not in `bd.data` | most | `KEEP` in the build itself |
| Attrition recorded | none (one job saves an `exclude` dataset) | the attrition table is a first-class output |
| No manifest or catalog step | 5 of 5 | publish and register (decisions 1, 9) |

Hazards seen in the exemplars, each designed out:

- **Hardcoded per-patient value corrections** (`if ccfid="..." and dt_surg=... then ...`).
  Corrections belong to the master corrections model in hvtiRdatabuild, not to a study build.
  The template says so and offers no place for them.
- **`proc print` of patient rows**, including `where ccfid='...'`. The template prints no rows.
- **A credential `%include`.** The template reads no credentials; a future warehouse source
  connects through `hvtiRdatabuild::dw_connect()`.
- **Hardcoded paths copied in from other studies.** Every path is relative to the study root
  or is the one `MASTER` setting.

## 3. Decisions

| # | Question | Decision |
|---|---|---|
| 1 | Does rendering publish? | A `PUBLISH <- FALSE` switch. Off: cut, draft and report only. On: publish and register. The report states the mode |
| 2 | How are cohort rules written? | Exclusion rules with reasons, `condition ~ "Reason"`, in order. A missing condition means **not excluded**, as SAS `delete` and analysis sets do, and is counted |
| 3 | Where do named-patient exclusions live? | A study-side `00_datasets/exclude-ids.csv` (`id`, `reason`). Never in the `.qmd`, because `code-fold` puts the source into the HTML |
| 4 | How is the master named? | `MASTER` is a path to the parquet snapshot. Its sidecar is required and its SHA-256 recorded; `VERIFY_MASTER <- FALSE` rehashes when `TRUE` |
| 5 | Must the build also run as a script? | Yes. Every chunk is plain R with no knitr reliance, so `knitr::purl()` gives the script a scheduled `dwpull` refresh runs against a warehouse table. Only `read-master` changes for that source |
| 6 | Cohort by list, predicates, or either? | Either. Optional `COHORT` path, joined on `JOIN_BY`; `EXCLUDE` applies after in both modes |
| 7 | Do derivations belong in `bd`? | Yes, the study-intrinsic ones (intervals, event indicators) in one `EDIT:` chunk. Imputation, propensity and model-specific variables go to `vars` later |
| 8 | Where does the logic live? | The template, plus one exported helper, `build_cohort()`, for the cohort and attrition steps |
| 9 | What does a second publishing render do? | The register step branches: nothing registered, `register_data()`; this release registered, no-op; an older release registered, `adopt_data_update()`. The report shows which ran and the release IDs before and after |

Two smaller calls were made in the design and not objected to:

- **`KEEP` is required**, with no read-everything default. The read pulls `KEEP`, `JOIN_BY`
  and the columns `EXCLUDE` names. The release carries `KEEP`, `JOIN_BY` and the derived
  columns. `MRN` and `eMRN` are dropped unless serving as the ID, matching `read_job_data()`.
- **One row per patient is not a setting.** It is an `EXCLUDE` example after an ordering
  (`duplicated(ccfid) ~ "Later operation"`), and the final `KEY` uniqueness check catches the
  rest.

## 4. The template: `inst/templates/00_datasets/bd.qmd`

It is the first file in a new `inst/templates/00_datasets/` directory and scaffolds as
`00_datasets/<subject>-<type>-bd.qmd`. It carries its own `format:` block, the single
`SUBJECT` and `TYPE` lines `add_job()` substitutes, and `EDIT:` markers on every
study-specific line. It holds no study data and no identifiers: every patient-level input the
study supplies is a file beside the data.

| Chunk | Does |
|---|---|
| `setup` | finds the study root, as every template does |
| `edit-study-choices` | `SUBJECT`, `TYPE`, `MASTER`, `VERIFY_MASTER <- FALSE`, `COHORT <- NULL`, `JOIN_BY <- c("ccfid", "dt_surg")`, `KEEP`, `EXCLUDE`, `ID <- "ccfid"`, `KEY <- ID`, `DATASET_ID`, `PUBLISH <- FALSE`. Only `MASTER` and `KEEP` must be edited before a first render |
| `read-master` | checks the sidecar exists and records the parquet's SHA-256, rows and parent release (rehashing under `VERIFY_MASTER`). Opens the parquet with `arrow::open_dataset()`, selects `KEEP`, `JOIN_BY` and the columns `EXCLUDE` names, then collects. Lowercases names, as `read_built()` does. **The one chunk that changes** when the source becomes a warehouse table |
| `cohort` | `build_cohort()`: cohort list, then exclusion IDs, then `EXCLUDE`. Returns the rows and the attrition table |
| `derive` | `EDIT:`, with one or two neutral examples (an interval from surgery, an event indicator). Asserts the row count did not change |
| `write-draft` | drops `MRN`/`eMRN` unless one is the ID, checks `KEY` is unique, writes `00_datasets/draft-<DATASET_ID>.rds` and the build record (section 5.4) |
| `publish` | under `PUBLISH`, `publish_dataset()` then the decision 9 branch, as adjacent visible lines, per the issue comment. Otherwise reports "draft only, nothing published" |
| `report` | source and its hash, the attrition table, a column summary (name, type, missing count, range for numerics), the mode, and the release before and after. No rows |

`DATASET_ID` follows `publish_dataset()`'s rule (lower-case letters, digits, underscores) and
the template checks it before any read, so a bad name fails in seconds, not after a 36 GB
read.

Template narration covers why `EXCLUDE` treats a missing value differently from a downstream
`WHERE`, why identifiers live in files and not the job, where corrections belong, and that
interactive spot checks of patient rows belong in the console (hvtiRdatabuild#71), never in
the report.

`.lintr` gets the file key `inst/templates/00_datasets/bd.qmd`, with the per-linter
exclusions the other templates carry. A directory key would exclude everything silently.

## 5. The helper: `build_cohort()`

Exported from hvtiRtemplates, in a new `R/build-cohort.R` beside `R/job-data.R`, documented
in Rd markup.

```r
build_cohort(data, exclude = NULL, cohort = NULL, join_by = NULL,
             exclude_ids = NULL, id = "ccfid")
# returns list(data = <kept rows>, attrition = <data frame>)
```

### 5.1 Steps, in fixed order

1. **Cohort list**, when `cohort` is a path. Read it, check it carries `join_by`, check the
   join columns' types are compatible, and keep the master rows matched on `join_by`. List
   rows that matched no master row are counted, never listed: that count is how a padded-ID
   or shifted-date mismatch shows itself. A list carrying `exclude` and `reason` columns
   contributes `exclude == 1 ~ reason` rules, applied here.
2. **Exclusion IDs**, when `exclude_ids` names an existing file. One step per distinct
   `reason`. IDs are compared through `.id_text()`, so `100000` and `"100000"` match. Listed
   IDs not found are counted, never listed, so a typo cannot silently exclude no one.
3. **`EXCLUDE` rules**, a list of `condition ~ "Reason"` formulas, applied in order to the
   rows still kept. Each condition is evaluated with `rlang::eval_tidy()` against those rows
   and must return a logical vector of their length. `NA` is not excluded, and is counted.

### 5.2 The attrition table

One row per step: `step`, `reason`, `rows_before`, `removed`, `missing_condition`,
`rows_after`, `patients_after`. Patients are counted on `id`. A rule's text is shown with any
value compared against `id` or a `KEY` column replaced by `<value>`, the treatment `WHERE`
gets in `read_job_data()`.

### 5.3 What it never does

Print, message a data value, or put an identifier in its return value's `attrition`.

### 5.4 The build record

The template, not the helper, writes `00_datasets/<release stem>.build.yml` beside the
release, or `draft-<DATASET_ID>.build.yml` in draft mode. It holds the master's path, SHA-256
and parent release; the settings as text, with `EXCLUDE` redacted as above; the attrition
table; and the hvtiRtemplates version. `publish_dataset(source =)` names that file, so the
catalog entry points to how the release was cut.

## 6. Failures and privacy

Every stop names the step (chunk) and the file and the setting to change, and never a data
value. `build_cohort()` errors follow the same form.

| Step | Failure | Points to |
|---|---|---|
| `edit-study-choices` | `DATASET_ID` not a valid catalog ID; `KEEP` empty | the setting |
| `read-master` | parquet or sidecar missing; sidecar hash differs from the file under `VERIFY_MASTER` | `MASTER` |
| `read-master` | a `KEEP` or `JOIN_BY` column absent from the master | the column name |
| `cohort` | cohort file missing a `join_by` column; join columns of incompatible type | `COHORT`, `JOIN_BY` |
| `cohort` | an `EXCLUDE` condition errors, or returns the wrong length or type | rule number and reason |
| `cohort` | every row excluded | the step that emptied it |
| `derive` | the row count changed | the `derive` chunk |
| `write-draft` | `KEY` not unique | how many keys repeat, never which; `KEY` |
| `publish` | `publish_dataset()`, `register_data()` or `adopt_data_update()` stops | rethrown with the step name; the underlying message is kept only when it names no value, the precedent `lift_master()` sets for driver messages |

Privacy holds by construction:

- No identifier in the `.qmd` (decisions 3 and 6), so `code-fold` cannot leak one.
- The HTML carries aggregates only. No `head()`, no row print, no `proc print` analogue.
- `exclude-ids.csv` and the cohort file are never copied into the release, the build record
  or the HTML.
- The build record holds counts, not identifiers, so the study's `.hvti/id_key` digest is
  not needed here.

## 7. Testing, and how each acceptance criterion is met

**Fixture.** A synthetic master made in the test by running `snapshot_master()` on
hvtiRdatabuild's own `oracle_small.sas7bdat`, as that function's example does, so the parquet
and sidecar are real rather than imitations. A synthetic cohort CSV and `exclude-ids.csv` use
`SYN...` IDs. Render tests skip without quarto, arrow or hvtiRdatabuild, all already in
Suggests; `hvtiRdatabuild`'s floor rises to `>= 0.2.3`.

| Acceptance criterion (#223) | Met by | Tested by |
|---|---|---|
| `add_job()` can create it, and `study_setup()` creates the `00_` folder | the template in `inst/templates/00_datasets/`, the `bd` ledger row shipped | `add_job("bd", ...)` into a `study_setup()` study lands in `00_datasets/` with `SUBJECT` and `TYPE` substituted |
| Renders end to end on synthetic data; a downstream job then renders against the registered release | `PUBLISH`, decision 9 | **End to end:** `study_setup()`, `add_job("bd")`, render with `PUBLISH = TRUE`, `verify_manifest()` passes, `add_job("ac")`, render `ac` reading `"study"`. Then a second `bd` render with a changed rule asserts `-r2` and the adopt branch, and a draft render asserts nothing new in `dataset-catalog.yml` |
| Failure messages name the step and file, never a patient value | section 6 | one test per section 6 row, asserting the step and file appear and no fixture ID or value does |
| No patient rows in the rendered HTML by default | the aggregates-only `report` chunk | grep the rendered HTML for every fixture ID: no hit |
| (decision 5) runs as a script | plain-R chunks | `knitr::purl()` the template, `source()` the script against the fixture, and get the same release ID the render made |
| Stat programmers (Moses, Linda, Beth) have reviewed it line by line | not code | a merge gate stated in the implementation PR |

`build_cohort()` unit tests: step order; `NA` counted and not excluded; unmatched list rows
counted; exclusion IDs not found counted; `100000` against `"100000"`; ID rule text redacted;
a malformed rule (wrong length, not logical, an error) names its number and reason.

The end-to-end test needs `ac`'s data columns in the synthetic master (a follow-up interval
and an event indicator); the `derive` example produces them, which also proves the release is
analyzable without a `vars` job.

## 8. Edits that ride along

- `inst/extdata/templates.json`: the `bd` row gets `status: shipped`, `blocked_on: null` and
  `spec` naming this file. `check-roadmap-counts.py` and `spec-counts.yaml` stay green.
- `inst/templates/README.md`: the `00_datasets` level and the `bd` entry.
- `.lintr`: the file key.
- `NEWS.md`: an entry under `# hvtiRtemplates (unreleased)`. No version bump in the PR.
- `DESCRIPTION`: `hvtiRdatabuild (>= 0.2.3)` in Suggests.
- A follow-up issue to reopen the new-study guide so it starts from a `bd` job.

## 9. Risks to check during implementation

- **`adopt_data_update()` on a same-date revision.** It requires a "newer" release. Whether
  `-r2` on the same extract date counts as newer than `-r1` is unverified; the end-to-end
  test's second render proves it or exposes it.
- **`hvtiRutilities (>= 1.4.2)` and release-aware `register_data()`.** Confirm
  `catalog_dataset` and `release_id` exist at the floor, or raise it.
- **Draft and lock files in `00_datasets/`.** `verify_manifest()` passed with
  `draft-*.rds` and `dataset-catalog.yml.lock` present; keep a test on it, since a stricter
  future check could object.
- **Arrow pushdown of `EXCLUDE`.** Only column selection is pushed down. Conditions are
  evaluated in R after `collect()`, because `EXCLUDE` needs R semantics (`NA` not excluded,
  `duplicated()`). If a real master is too large to collect even after column selection, a
  pushed-down pre-filter is a follow-up, not part of this design.

## 10. Out of scope

- The direct warehouse pull, a port of `SP_DW_PULL.sas`. It belongs in hvtiRdatabuild.
- The scheduled `dwpull` refresh script itself. This design makes the job purl-able for it.
- An "adopt an existing legacy dataset" step (`register_data()` with no release).
- `vars`: imputation, propensity and model-specific variables.
- Joining external follow-up, vital-status or echo sources. Left as a commented example.
- A console-only targeted-print helper (hvtiRdatabuild#71).
- Per-patient value corrections, which belong to the master corrections model.
