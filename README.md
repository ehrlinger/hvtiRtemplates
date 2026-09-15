# hvtiRtemplates

<!-- badges: start -->
[![R-CMD-check](https://github.com/ehrlinger/hvtiRtemplates/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/ehrlinger/hvtiRtemplates/actions/workflows/R-CMD-check.yaml)
[![Codecov test coverage](https://codecov.io/gh/ehrlinger/hvtiRtemplates/graph/badge.svg)](https://app.codecov.io/gh/ehrlinger/hvtiRtemplates)
[![active](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/badges/latest/active.svg)
[![pkgdown](https://github.com/ehrlinger/hvtiRtemplates/actions/workflows/pkgdown.yaml/badge.svg)](https://github.com/ehrlinger/hvtiRtemplates/actions/workflows/pkgdown.yaml)

[![R package version](https://img.shields.io/github/r-package/v/ehrlinger/hvtiRtemplates)](https://github.com/ehrlinger/hvtiRtemplates)

[![lint](https://github.com/ehrlinger/hvtiRtemplates/actions/workflows/lint.yaml/badge.svg)](https://github.com/ehrlinger/hvtiRtemplates/actions/workflows/lint.yaml)
<!-- badges: end -->

Versioned analysis job templates for the HVTI CORR group at the Cleveland
Clinic.

## Install

```r
renv::install("ehrlinger/hvtiRtemplates")
```

## What is here

| Directory | Status | Contents |
|---|---|---|
| `inst/templates/` | **supported** | R job templates. See `inst/templates/README.md` for coverage. |

Everything the package installs is supported: tested, maintained, and intended
to be run. There is no reference-only material.

## There is no SAS corpus here

During development this repository also carried the legacy SAS template corpus
(240 files) and the SAS macro library (495 files, with history imported from
2014) as a reference specification. Both were removed before release, and every
path was purged from every commit with `git filter-repo` — they are not
recoverable from this repository's history by design.

Two consequences worth stating plainly. Parity work against the SAS originals
needs a source outside this repository; the institutional SAS licence runs into
2027, so plan accordingly (`2027-09-29` is the working date, not yet confirmed).
And a result filed before the migration still cannot say what produced it — that
was already true, because `%inc` bound late to a mutable directory with no
version, and removing the corpus neither creates nor worsens that gap.

## Why this package exists

Study analyses were created by copying template files into a new study folder
and editing them. Two things followed: improvements stayed in the study where
they were made, and — the problem that actually hurts — a filed result could
not say what produced it. SAS bound its analysis logic with
`%inc kaplan`, resolving at run time against a mutable directory with no
version, so the `.lst` filed in 2006 was produced by a `kaplan` nobody can now
identify.

The design rule is **bind late, to something versioned**. Late binding is right;
SAS could not make it safe because there was no version to pin. `renv.lock`
supplies that, so a study can use the latest while working and pin it on filing.

In practice a study declares `hvtiRtemplates` in its `renv.lock`, resolves a
template through `template_path("ac")` instead of copying one into the study
folder, and pins the version when results are filed. The lock file is then the
answer to "what produced this?" — the question the SAS arrangement could not
answer, because `%inc` had nothing to pin.

## API

| Function | Returns |
|---|---|
| `hvti_taxonomy()` | the analysis prefix table: prefix, name, folder, description |
| `template_list()` | supported templates: name, prefix, qualifier, folder, file |
| `template_path(prefix, qualifier = NULL)` | path to one supported template |
| `hvti_non_prefixes()` | leading name fields that are utilities, not analysis prefixes |
| `add_job(prefix, endpoint, type, dir = ".", qualifier = NULL)` | the scaffolded job's path, invisibly |
| `migrate_job(source, endpoint, type, prefix, ...)` | the migrated job's path, invisibly; writes an evidence report beside it |

Templates are `<prefix>[-<qualifier>].qmd` in a numbered directory
(`20_distributions/ac.qmd`); a job is
`<endpoint>-<type>-<prefix>[-<qualifier>].qmd` in the study's matching taxonomy
folder. New studies use numbered folders and existing bare-folder studies keep
their layout. The ordinal that once prefixed filenames was dropped in 1.1.0.

`qualifier` names a job type within a prefix. The current qualified templates
are `dc-tables`, `dc-gfup`, `dp-trends`, and `dp-postage`; other prefixes remain
unqualified. It is `NULL` and the column is `NA` for a prefix with a single
template. Naming no qualifier where a prefix carries several is an error
listing the choices, never a silent pick of the first.

## Migrate a legacy job

For a study with SAS programs already in `descriptive/` and `graphs/`, first
adopt its directory with `hvtiRutilities::study_setup(..., adopt = TRUE)` and
register its built datasets with `register_data()`. The tutorial
[Migrate a legacy study to R jobs](articles/legacy-study-migration.html)
walks through adoption, study and named-subset registration, migration, and
output review using synthetic data.

From that study's root, migrate a descriptive-table job with:

```r
job <- hvtiRtemplates::migrate_job(
  source = "descriptive/dc.tables.sas",
  endpoint = "cohort", type = "eda", prefix = "dc", qualifier = "tables",
  lst = "descriptive/dc.tables.lst", log = "descriptive/dc.tables.log",
  reference = "documents/general.rtf", dir = "."
)
```

Use your study's source and evidence filenames. `lst`, `log`, and `reference`
are optional; supplied files must exist beneath `dir`. The call writes
`descriptive/cohort-eda-dc-tables.qmd` and
`descriptive/cohort-eda-dc-tables-migration.md` in a study with bare folders.
It preserves the evidence files and refuses to overwrite either output.

Migration supports `dc-tables`, `dc-gfup`, `dp-trends`, and `dp-postage`.
Each adapter reads a defined source shape. Only deterministic extraction can
remove an `EDIT:` marker; uncertain choices remain in the job and report for
you to resolve before rendering. Logs, listings, and RTF/DOCX references help
you check the translation but do not supply missing analysis choices.

The table job replaces the SAS RTF output with an editable CORR DOCX through
`hv_tbl_summary()`, `hv_man_table()`, `hv_man_table_save()`, and
`hv_check_docx()`. It writes beneath `documents/<endpoint>-<type>/` and stops
on a structural finding. Compare the rows, summaries, precision, and footnotes
with the legacy reference before accepting the document; the structural check
does not establish numerical agreement.
