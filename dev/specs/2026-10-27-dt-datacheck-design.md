# The `dt` data check: what it checks, and whether it lives in `bd`

**Date:** 2026-10-27
**Status:** design. Sections 3 to 6 were decided by John Ehrlinger on 2026-10-27, in the order
they appear. Where the checks live (section 7) is decided by a rule applied to a census that is
staged on the share and has not been run; its numbers will be added here when it has.
Implementation waits on the census and on John's go-ahead.
**Reads with:** `2026-10-14-bd-vars-action-items-design.md` (the diagnostics row of section 4
and its open item 3, which this note settles); `2026-08-29-template-conversion-roadmap-design.md`
(the "Datasets last" rule, section 2 here); `inst/templates/00_datasets/bd.qmd`.
**Packages:** hvtiRtemplates (the template or `bd`'s new section), hvtiRutilities (the existing
`proc_*` helpers and one new check helper).

This note is self-contained. It assumes no memory of the session that produced it.

⚠️ No study, variable value or patient identifier appears here.

## 1. The question

The bd-vars note left open "whether `dt` takes over `bd`'s diagnostic output or `bd`'s report
keeps it". `dt` is the catalog's queued "Data check" row in `00_datasets`: 512 SAS uses across
503 jobs, disposition `scaffold`, `blocked_on: "hvtiRdatabuild"`. The SAS habit it replaces is
the checking loop a programmer runs after a build: write the build, cross-tab, spot
discrepancies, print the rows that look wrong (hvtiRdatabuild#71, raised from the 2026-10-01
session).

## 2. The blocker is stale

Measured 2026-10-27 against `origin/main` of both repositories.

- The "Datasets last" rule held datasets templates until hvtiRdatabuild's API settled. `bd`
  shipped against it in hvtiRtemplates 1.2.4, and hvtiRdatabuild 0.3.3 is released.
- `bd.qmd` names one hvtiRdatabuild function, `snapshot_master()`, and only in an `EDIT:`
  comment. Its working calls are to hvtiRtemplates and hvtiRutilities.
- hvtiRdatabuild's 21 exports hold no check or summary helper. The helpers a data check needs
  are in **hvtiRutilities**: `proc_freq()`, `proc_means()`, `proc_contents()`,
  `proc_univariate()`, `review_built()`, `compare_datasets()`, `followup_check()`.
- The one missing piece is #71's targeted-print helper (section 5).

So `blocked_on` should name that helper, not hvtiRdatabuild. The catalog row is changed with
the implementation, not by this note.

## 3. Ownership: `bd` keeps its receipt, the checks only read

`bd`'s report stays as it is: run mode and source, the attrition table, and each column's type,
missing count and range. That is the **receipt** of the cut, what the build did. The checks
are about what the data says, and they **never write**: no dataset, no registration, no
correction. A finding becomes a correction in the overlay, a rule in `bd`'s `EXCLUDE`, or a
derivation fix, never an edit made by the check. This extends the bd-vars note's three rules
with a fourth: **a check never writes.**

The checks do not repeat the receipt's per-column summary.

## 4. Input

The checks read **the working file `bd` writes**, `datasets/<DATASET_ID>.rds`, named by the
same `DATASET_ID` and validated the same way. They do not read the registered `built`: the loop
is build, check, fix, rebuild, and it runs before a version is registered and dated. This is
also the input that survives a merge into `bd` unchanged (section 7).

## 5. Patient rows: console only, counts in the report

A targeted print shows patient rows, and a rendered report gets shared. So each named check
reports **only its label and how many rows match**. The matching rows, with the columns the
author chose, go to the **console**, where an interactive Workbench session shows them and a
render does not knit them.

The helper that does this lives in **hvtiRutilities**, beside `proc_freq()`, which already
answered #71's generic half. #71 closes by pointing there. Its API is hvtiRutilities' design;
this note fixes only its contract: given data, named predicates and columns, it returns a
count per predicate for the report and writes matching rows to the console, never into the
knitted output.

## 6. The checks

Four sections, in this order:

1. **What this rebuild changed.** `hvtiRutilities::review_built()`: the working file against
   the version registered now, or a plain statement that none is registered yet.
2. **Cross-tabs.** `CROSSTABS`, an `EDIT:` list of column pairs, each through
   `proc_freq(missing = TRUE)`, so a missing value is its own level, as `PROC FREQ / MISSING`
   shows it. The typical pair is a derived column against its source, such as an event
   indicator against its date. Small cells are flagged, not suppressed: these are counts the
   author needs to see.
3. **Follow-up.** `followup_check()` on an `EDIT:` interval and event pair, with
   `identifier = NULL` so the report holds aggregates only. `bd` derives these columns and
   every time-related job relies on them.
4. **Named checks.** `CHECKS`, written as `condition ~ "Label"`, the shape of `bd`'s
   `EXCLUDE`, with `PRINT_COLS` naming the columns to print. Report and console as in
   section 5.

Each section is one self-contained chunk that reads `d` and the study choices and nothing
another section made, so a section moves between files without edits.

## 7. Where the checks live: decided by the census

John's view is that `dt` may merge into `bd`. The two homes:

- **In `bd`.** The checks become a Checks section after `bd`'s Report, and *What this rebuild
  changed* moves above Register, where `bd`'s comments already tell the author to run
  `review_built()`. One render builds and checks, which is the SAS loop: the bd-vars note's
  diagnostics row records `proc print` and `proc means` inside SAS `bd` jobs. The `dt` row
  leaves `templates.json`, and the taxonomy keeps its `dt` row, as it kept `dp`'s, because
  `job_census()` still counts the legacy `dt` jobs. Costs: every change to a check re-reads the
  master and re-cuts, and `skip` and `stop_here()` skip chunks below a point, not above it; and
  `bd` is under line-by-line review by the stat programmers, so the section lands after that
  review closes.
- **Separate `dt`.** `inst/templates/00_datasets/dt.qmd`, scaffolded as
  `dt.<subject>.<type>.qmd`, with the standard `setup` chunk. A check re-reads only the `.rds`.
  It stops with a plain message when `bd` has not written the working file. Merging later means
  moving its chunks below `bd`'s Report and dropping its read chunk.

**The rule.** The census (`/studies/general/_development/dt-census-20261027/`, run on lri)
classifies each legacy `dt` job by what it reads: `bd_only`, `bd_and_other`, `other_only`,
`work_only` or `none`. **If `bd_only` is at least 80% of `dt` jobs, the checks go into `bd`.
Below that they ship as a separate `dt`**, because a fifth or more of the corpus checks
something `bd` does not hold, such as a `vars` output or an analysis set. The census matches
datasets by member name, so members named through macro variables fall into `other_only`.
Skim a sample of that class in the private CSV before applying the rule.

Census results: *not yet run.*

## 8. Report conventions

Either home inherits `bd`'s: no code shown, because a `CHECKS` condition can name a patient
and a folded chunk's source is in the HTML; `show_markers = FALSE`; warnings and messages to
the console. The study-specific lines are `EDIT:` markers: `DATASET_ID` (separate `dt` only),
`CROSSTABS`, the follow-up pair, `CHECKS` and `PRINT_COLS`.

## 9. Testing, at implementation

- A render against a synthetic study after a `bd` render, in a private library (concurrent
  sessions overwrite the installed package).
- **The PHI guard, proved by mutation:** a fixture whose `PRINT_COLS` values are distinctive
  strings, and a test that none appears in the HTML. Reverting the console routing must turn it
  red.
- For a separate `dt`: its own `.lintr` file key, the `SUBJECT`/`TYPE` lines, the
  no-study-identifier test, and the roadmap ledger row.
- For a merge into `bd`: the existing `bd` tests stay green and the new section is covered by
  the same PHI test.

## 10. Open

1. The census numbers, and the home the rule then picks.
2. The hvtiRutilities helper's name and API, in that package's own design.
3. Whether a merged `bd` later wants a way to re-run only its checks against an existing
   working file. Not designed here: wait until the iteration cost is measured on the cardiac
   master.

## 11. Out of scope

Any edit to `bd.qmd` or the catalog row before implementation; the SAS workflow, which is being
retired and is left as it is.
