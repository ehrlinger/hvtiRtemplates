# `dc-general` template: base-procedure descriptive checking

**Date:** 2026-09-16
**Status:** design, approved 2026-09-16.
**Supersedes nothing.** Implements the `dc-general` row that
`2026-09-09-eda-templates-design.md` placed in wave 2 and answered in its
section 8.1, and that `2026-09-14-eda-templates-wave-2-4-plan.md` recorded as
out of scope ("not requested; unblocked").

## 1. Purpose

`dc-general` is the first quality-control look at a built cohort: what the data
contain, how the categorical variables break down, how the continuous variables
are distributed, and which variables move together. It replaces
`descriptive/dc.general`, 759 SAS jobs, the largest row in the descriptive
family.

It is **not** a manuscript table. That is `dc-tables`. The catalog note on this
row reads "Base procs only (contents/means/freq), no package dependency, which
is what separates it from `tables`." Any implementation that gives `dc-general`
a table-package dependency collapses the one distinction the two rows exist to
draw.

## 2. Engine: base R inline

`hvtiRutilities` 1.1.12 exports `proc_contents()` and `proc_means()` and no
other `proc_*` function. Three of the four sections have no helper.

**Decided 2026-09-16: base R, inline in the template.** `table()`,
`quantile()` and `cor()` fill the gap, as `dc-gfup` already reproduces
`proc freq / list missprint` with `table(useNA = "ifany")`. The catalog's
`replaced_by` stays `proc_contents` and `proc_means`, and the job ships as one
hvtiRtemplates pull request.

Rejected: adding `proc_freq()`, `proc_univariate()` and `proc_corr()` to
`hvtiRutilities` first (two repositories, a release and a pin before the
template), and template-local helper functions (more code than the sections
need). Revisit the first if a second job needs the same procedures.

## 3. File

`inst/templates/10_descriptive/dc-general.qmd`. No code registry lists
templates: `template_list()` scans `inst/templates/` for `<prefix>-<qualifier>.qmd`.

The per-template obligations of `2026-09-09-eda-templates-design.md` section 7
apply. Corrected 2026-09-16: the first draft of this section named only the
README row. The full list:

- a row in `inst/templates/README.md`, and `dc-general` added to that file's
  list of qualified templates;
- its own **file key** in `.lintr` (never a directory key) excluding
  `object_name_linter`, `commented_code_linter` and `object_usage_linter`, as
  every sibling has;
- a `NEWS.md` entry under `# hvtiRtemplates (unreleased)`, with no `Version:`
  bump, because `inst/` ships;
- no study identifiers: `test-add-job.R` scans every template for
  `/studies/`, `preserve_root`, `lv_function` and `built.sas7bdat`, and
  `tools/check-no-site-identifiers.sh` scans the repository.

## 4. Boilerplate

Copied verbatim from `inst/templates/10_descriptive/dc-gfup.qmd` as of
`d79bf45`, so the siblings share one setup contract:

- the YAML header (HTML, table of contents, folded code, embedded resources);
- `setup`: project-root resolution, sourcing `R/`, the hvtiRdatabuild >= 0.2.1
  check;
- `edit-guard`: refuses to render while an `EDIT:` marker remains unless
  `HVTI_TEMPLATE_DRAFT` is set;
- `set`: `ENDPOINT <- "cohort"`, `TYPE <- "eda"`, the filename check, and
  `set_path()` through `hvtiRutilities::study_dir()`;
- `data`: `verify_manifest()`, `ANALYSIS_SET <- "eda"`, the attrition table.

## 5. The `spec` chunk

Every setting carries an `EDIT:` marker.

| setting | default | SAS origin |
|---|---|---|
| `CATEGORICAL` | `list(Demography = c("female"))` | the `%macro freq` `tables` list, grouped by `/* Demography */`-style banners |
| `CONTINUOUS` | `list(Demography = c("age"))` | the `%macro cdfs` `var` list, same banners |
| `CORR_VARS` | `unlist(CONTINUOUS, use.names = FALSE)`; `character()` skips the section | the `proc corr` `var` list |
| `ID_COL` | `NULL` | `id ccfid` |

The grouped lists take the `list(heading = vars)` shape of `dc-tables`'
`GROUPS`, because section 8.1 of the 2026-09-09 design found that both jobs use
one comment taxonomy. A variable list therefore moves between the two jobs
unchanged.

`CORR_VARS = character()` is the deliberate form of exemplar B's empty
`%macro corr` `var` list, which was a section copied in and never filled.

⚠️ **`ID_COL` is off by default and its `EDIT:` says why.** `ccfid` is a
patient identifier. Setting it labels the extreme values in section 6.3 with
identifiers, and the rendered report must then not be circulated. The SAS
default suited listings that stayed on the SAS server; a self-contained HTML
report travels.

## 6. Report sections

All computation lives in one `derive` chunk, which produces `freqs`, `cdfs` and
`corrs`. The section chunks only print. This is what makes the template testable
without rendering (section 8).

### 6.0 Other investigations

An empty region marked `EDIT:` for study-specific work. Section 8.1 of the
2026-09-09 design found roughly two thirds of exemplar A to be ad-hoc work above
the skeleton, none of it general, so the template reserves the space rather than
anticipating the content.

### 6.1 Overall statistics

```r
proc_contents(d)
proc_means(d, stats = c("n", "nmiss", "mean", "std", "min", "max", "sum"))
```

The SAS statistics list is `n nmiss mean std min max sum`. `proc_means()` in
hvtiRutilities 1.1.12 accepts every one of them, `"sum"` included (verified
2026-09-16).

### 6.2 Contingency tables

One sub-heading per `CATEGORICAL` group, in list order. For each variable,
`table(x, useNA = "ifany")` with counts and percentages, missing values shown as
their own level (SAS `missprint`).

### 6.3 Cumulative distributions

For each `CONTINUOUS` variable:

- `n` and `nmiss`;
- the `proc univariate` default quantiles, 0, 1, 5, 10, 25, 50, 75, 90, 95, 99
  and 100 percent, computed with `quantile(type = 2)`, which is SAS
  `QNTLDEF=5` and matches `proc_means()` and `dc-gfup`;
- the five lowest and five highest non-missing values (SAS "extreme
  observations"), labelled with `ID_COL` only when it is set.

### 6.4 Pairwise correlations

Pearson coefficients, the `proc corr` default, over `CORR_VARS`, with
pairwise-complete observations. Output is one long table of distinct pairs,
`var1`, `var2`, `r`, `n`, sorted by descending absolute `r`, which is what the
`rank` option orders. No self-pairs, no duplicate pairs.

This is `proc corr nosimple rank`, the bare sweep. Spearman, Fisher intervals
and the scatter-plot matrix belong to `dc-tables`' correlation variant.

## 7. Error handling

`derive` validates before computing anything:

- every name in `CATEGORICAL`, `CONTINUOUS`, `CORR_VARS` and `ID_COL` must be a
  column of `d`; otherwise stop, naming **every** unknown column in one message;
- every `CONTINUOUS` and `CORR_VARS` column must be numeric; otherwise stop,
  naming the offending columns.

No silent coercion and no dropped variables.

## 8. Tests

New `tests/testthat/test-dc-general-derive.R`, following
`test-dc-gfup-derive.R`: extract the `derive` chunk from the installed (or
source) `.qmd`, `parse()` it, and evaluate it in an environment built on
`baseenv()` holding synthetic `d` and the `spec` settings.

1. With `ID_COL = NULL`, no output object contains an identifier column.
2. An unknown variable stops, and the message names it.
3. A non-numeric `CONTINUOUS` variable stops.
4. `corrs` has no self-pairs and no duplicate pairs, and is sorted by
   descending `abs(r)`.
5. A reported quantile equals `quantile(x, p, type = 2)`.
6. `CORR_VARS = character()` yields an empty `corrs` without error.

`test-template-data-routes.R` names its templates explicitly (line 29:
`"dc-tables.qmd", "dc-gfup.qmd", "dp-postage.qmd"`), so add `"dc-general.qmd"`
to that vector; without it the new template's data route goes untested.

## 9. Definition of done

- `devtools::test()` passes.
- `lintr::lint_package()` is clean.
- `devtools::check()` is 0 errors, 0 warnings, 0 notes.
- A standalone render on synthetic data passes with every `EDIT:` marker
  resolved.

## 10. Companion change in hvtiR

On an hvtiR branch, following hvtiR#77:

- `inst/extdata/jobs.json`: `dc-general` status `queued` to `shipped`;
- `NEWS.md`: an entry under `# hvtiR (unreleased)`;
- `tests/testthat/test-jobs.R`: pin the new status.

## 11. Sequencing

| when | step |
|---|---|
| 2026-09-16 | This spec and the template on an hvtiRtemplates branch, pull request opened. The hvtiR flip pull request opened. Both reviewable. |
| after the hvtiR PR merges, **2026-09-17 at the earliest** | Name hvtiR `1.1.13` and tag it. `1.1.12` was named 2026-09-16, and hvtiR names at most one version a day. |
| after the tag | Move both hvtiRtemplates catalog pins (`.github/workflows/R-CMD-check.yaml`, `.github/workflows/spec-counts.yaml`) from `v1.1.11` to `v1.1.13`, re-render the roadmap and re-measure the on-disk count, then merge. |

⚠️ Do not carry a template count forward from an earlier plan. hvtiR#81
refreshed catalog data on 2026-09-16; measure the count after re-rendering.

## 12. Out of scope

- **The SAS "confidence intervals for categories" section** of
  `tp.dc.general.sas` (binomial intervals at `alpha=0.32`, 2 x k risk
  differences, observed versus expected mortality). Decided 2026-09-16: left
  out. Neither study exemplar used it, and the observed-versus-expected test is
  a risk-model check, not descriptive QC.
- **Any `.xlsx` or identified export.** Exemplar A exported two identified
  files to the study root; the template ships no export step.
- **`proc_freq()`, `proc_univariate()`, `proc_corr()` in `hvtiRutilities`**
  (section 2).
- **`dp-gfup`**, still unblocked and still not requested.
