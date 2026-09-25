# EDA report as a composite: `dp-postage` sections and `dp-eda`

**Date:** 2026-09-25
**Status:** design. Sections 3 and 4 decided by John Ehrlinger on 2026-09-25.
Section 4.1 is proposed. Section 7 is open. Nothing is built.
**Reads with:** `2026-09-09-eda-templates-design.md`, which scheduled the EDA
rows this note reshapes, and `2026-09-02-dp-dc-decomposition-design.md`, which
named the `dp` qualifiers.
**Packages:** `hvtiRtemplates` for the templates, `hvtiPlotR` for the one
function they need (section 5).

This note is self-contained. It assumes no memory of the session that produced
it.

⚠️ No study, variable or patient identifier appears here.

## 1. What was asked

From the template review with Lauren on 2026-09-24, and a follow-up the next
morning: an EDA report is **goodness of follow-up, then continuous variables,
then categorical variables as percentages, then categorical variables as
counts**, over every variable in the dataset. Each section should also be
available on its own, and the combined report must not be a second copy of
the plotting code.

The audience is the biostatistician choosing variables for an analysis set,
not the researcher. A researcher gets the report only on request.

## 2. What exists

| piece | where | does |
|---|---|---|
| `hv_followup()` | `hvtiPlotR` | the follow-up figure |
| `hv_eda()` | `hvtiPlotR` | one variable's panel against an x variable; `show_percent` switches a categorical panel between counts and percent |
| `eda_classify_var()`, `eda_select_vars()` | `hvtiPlotR` | continuous or categorical, with `unique_limit` and overrides |
| `dp-gfup` | template, `40_graphs/` | the follow-up figure as a job (shipped 2026-09-25, #145) |
| `dp-postage` | template, `10_descriptive/` | one panel per variable, paginated **inside the template**, with one `SHOW_PERCENT` for the whole run |

Two gaps. Pagination is template code, so a second template that wants the
same pages has to copy it. And `SHOW_PERCENT` is one switch for the whole run,
so percent and count for the same categorical variables need two renders.

## 3. Decided: one `dp-postage`, with sections

`SHOW_PERCENT` is replaced by

```r
SECTIONS <- c("continuous", "percent", "count")  # EDIT: any subset, in order
```

Three templates that differ in one argument would be three copies of the same
setup, data and validation code to keep in step, for no difference a study
author could not get by editing one line. Rejected on that ground: separate
`dp-postage_cont`, `dp-postage_pct` and `dp-postage_n` templates.

`VARIABLES <- NULL` (the default) means every column except the x variable,
the identifier and `EXCLUDE`. Named variables are checked all at once, and the
error lists every name not in the data. Both decided in the 2026-09-24 review.

**No migration mapping,** decided 2026-09-25. These templates are in their
first round of use, so no job depends on `SHOW_PERCENT` yet. `migrate_job()`
stops reading it, and a migrated `dp-postage` job starts from the default
`SECTIONS`.

## 4. Decided: `dp-eda` shares code through functions, not text

`dp-eda` is a complete template in `10_descriptive/`, with the usual `EDIT:`
study choices. It calls `hv_followup()` once and the section function of
section 5 once for each of `continuous`, `percent` and `count`. It does not
include other files.

**Quarto includes were considered and rejected.** `add_job()` copies one file
into a study. A `{{< include _setup.qmd >}}` would name a file that was never
copied, and the job would fail on its first render. The repository rule is the
same: a file meant to be copied must not depend on the directory it sits in.

**A generator was considered and rejected for now.** Section pieces in `dev/`
assembled into self-contained templates at build time would give one source
for the text, but add a script and a CI gate. What `dp-eda` shares with
`dp-postage` and `dp-gfup` is the setup, data and study-choices code every
template already repeats, and `test-eda-configuration.R` and
`test-template-provenance.R` already hold those in step. Revisit if a third
composite appears.

Because `dp-eda` and the section templates call the same functions with the
same arguments, **a section in `dp-eda` is the same figure as the standalone
job.** That is the guarantee the include design was after, reached through
the functions instead.

## 4.1 Proposed: a table beside each figure section

The figures show shape; a reader checking data quality also wants the numbers.
Each section of `dp-eda` carries the table that goes with it, over **exactly
the variables on that section's pages**, so a figure and its table can never
describe different variables.

| section | table | from |
|---|---|---|
| overview, first | every variable: type, label, missing count | `hvtiRutilities::proc_contents()` |
| follow-up | cohort, event and censored counts; missing, negative and zero intervals | `dc-gfup`'s tables, see below |
| continuous | n, missing, mean, SD, quartiles, range | `hvtiRutilities::proc_means()` |
| categorical | each level's n and percent, missing shown | `hvtiRutilities::proc_freq()` |

One categorical table serves both the percent and count sections, because a
table can carry both columns where a figure needs two.

**`dc-gfup`'s tables are template code today.** Sharing them through functions
means moving the cohort-count and interval checks into a function that
`dc-gfup` and `dp-eda` both call. Its home and name are open (section 7).

A standalone `dp-postage` prints its sections' tables too, so the guarantee of
section 4 holds for tables as well as figures.

**Not included:** `dc-tables`. That is the formatted manuscript table, written
to Word for researchers, and a different job from checking the data.

## 5. Needed in `hvtiPlotR`: one paginated section function

```r
hv_eda_pages(data, x_col, section = c("continuous", "percent", "count"),
             vars = NULL, labels = NULL, ncol = 4L, nrow = 4L,
             unique_limit = 6L, type_overrides = NULL, alpha = 0.5)
```

- **Returns a list of pages**, each a `patchwork` grid, with the variables on
  it as an attribute, so a template can print a heading and a caption naming
  them. It prints nothing.
- **`section` selects by class.** `continuous` keeps the variables
  `eda_classify_var()` calls continuous; `percent` and `count` keep the
  categorical ones and differ only in `show_percent`.
- **One binning of `x_col`,** computed inside the function the same way for
  every section, so a percent panel and a count panel for the same variable
  put their bars in the same places.
- **`labels`** is a named vector of display labels. Templates pass
  `hvtiRutilities::label_map()` output, and pick up smart truncation
  (`hvtiRutilities` spec section 4.2) when it lands.
- **`alpha = 0.5`**, and the shared palette once the palette helper exists.
- Tested there with `vdiffr` snapshots. `hvtiRtemplates` keeps its render
  tests.

This moves pagination out of `dp-postage` and into the package. It is the only
new code the design needs outside the templates.

## 6. Chunk labels and pages

`dp-eda` prefixes every chunk label by section (`gfup-`, `cont-`, `pct-`,
`cnt-`), so a label cannot collide however the sections grow. Each page is
emitted under its own heading, with a caption listing the variables on it, so a
report over hundreds of variables can be navigated from the table of contents.

## 7. Open

1. **Longitudinal variables.** The 2026-09-24 review raised spaghetti panels
   for repeated measures as part of an EDA. That is `dp-spaghetti`, queued. Add
   it to `dp-eda` as a fifth section when it ships, or leave it separate?
2. **Derived variables.** Year and month of operation should be built in the
   data build, not derived in a job. That is a question for the SAS
   programmers and blocks nothing here: `X_VAR` names whatever column exists.
3. **The follow-up table function.** Where `dc-gfup`'s cohort and interval
   checks live once they leave the template: `hvtiRutilities`, beside
   `proc_means()`, is the likely home.
4. **Acceptance.** Lauren's current EDA report is the reference output for
   the R sections, and the SAS EDA output is the acceptance test. Which study
   and which SAS output are not yet named.

## 8. Order of work

1. `hv_eda_pages()` in `hvtiPlotR`, with snapshot tests.
2. The follow-up table function, and `dc-gfup` calling it.
3. `dp-postage` moves to `hv_eda_pages()` and `SECTIONS`, with the
   `VARIABLES <- NULL` default, the all-missing-names error and its section
   tables. `migrate_job()` stops reading `SHOW_PERCENT`.
4. `dp-eda`, and its catalog row, `.lintr` key and render test.
