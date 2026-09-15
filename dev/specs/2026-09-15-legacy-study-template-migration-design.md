# Legacy study adoption and template-specific SAS migration

**Date:** 2026-09-15
**Status:** Design approved; implementation plan written 2026-09-15
**Primary repository:** `hvtiRtemplates`
**Upstream dependencies:** the two-stage study API in `hvtiRutilities` and the
`add_job()` numbered-layout change in `hvtiRtemplates`

## 1. Purpose

The first tutorial in `hvtiRtemplates` will begin with a study that already
contains SAS work. It will adopt that legacy directory without replacing its
files, register the built and subsetted datasets, and migrate four EDA jobs to
R:

- descriptive tables (`dc-tables`);
- goodness-of-follow-up summaries (`dc-gfup`);
- trends over operation year (`dp-trends`); and
- whole-dataset EDA postage stamps (`dp-postage`).

The package already ships `dp-trends`. This change adds the other three
templates and a migration entry point that fills each supported template from
the particular legacy job it replaces. Translation is limited to the source
shape registered for that template.

The study at
`/Volumes/qhsstudies/vascular/thoracic-aorta/aneurysm/ascending/biomechanics/bio_aggrecan/`
is the source exemplar and the live acceptance case. Its identifiers, paths,
dataset filenames, and variable choices must not enter the installed
templates or the runnable vignette.

## 2. Why the tutorial adopts a legacy study

Fellows will usually meet the R packages in a study that already has
`datasets/`, `descriptive/`, `graphs/`, `documents/`, SAS programs, listings,
and logs. A tutorial that creates an empty numbered study skips the part they
need: adding the study contract without disturbing the work already there.

The tutorial therefore constructs a disposable legacy-shaped study. It places
synthetic built and subset files in `datasets/`, adds small SAS fixtures in the
job folders, and creates reference output files. It then calls
`study_setup(..., adopt = TRUE)`. The example verifies that existing files and
bare folder names remain in place while the package-owned identity and
environment files are added.

The vignette distinguishes adoption from recovery. Adoption adds package-owned
state to an existing study whose work remains authoritative. Recovery restores
missing package-owned state from known evidence. Recovery is not taught in
this tutorial.

## 3. Tutorial flow

The vignette is one end-to-end article rather than a slide deck or a collection
of short articles. Every evaluated example runs in a temporary directory.

1. Build a small legacy study fixture with one canonical dataset and one
   subsetted dataset.
2. Adopt it with `hvtiRutilities::study_setup(..., adopt = TRUE)`.
3. Register the canonical dataset with
   `hvtiRutilities::register_data(..., role = "study")`.
4. Register the subset as a distinctly named dataset with
   `hvtiRutilities::register_data(..., role = "named")`.
5. Show the resulting study status and the separation between study-wide and
   subset cohort counts.
6. Migrate one legacy job for each of the four EDA templates.
7. Read the migration reports and resolve representative `EDIT:` markers.
8. Render the jobs and inspect their HTML, Word, and PNG outputs.

The tutorial uses the settled upstream function signatures. It must not edit
or duplicate the implementation now in progress in `hvtiRutilities`. The
branch will rebase onto the separate `add_job()` change before implementation
so the tutorial teaches the final scaffolding name rather than the retired
`new_job()` name.

## 4. One migration entry point, one adapter per template

The public interface is:

```r
migrate_job(
  source,
  endpoint,
  type,
  prefix,
  qualifier = NULL,
  lst = NULL,
  log = NULL,
  reference = NULL,
  dir = "."
)
```

`migrate_job()` owns the common mechanics:

- require the source to live beneath the study root;
- validate the source and optional evidence files;
- select exactly one installed template;
- require a registered migration adapter for `(prefix, qualifier)`;
- ask the existing scaffolder to create the correctly named job;
- refuse to overwrite an existing job;
- pass the source text to the selected adapter;
- write the migrated job atomically; and
- write a migration report beside the job.

The template-specific adapter owns interpretation. It returns replacements for
known template fields plus a structured report of translated, unresolved, and
ignored source material. An unsupported template is an error. The common layer
never falls back to a generic translator.

The first release registers four adapters, including the already shipped
`dp-trends`. A later template gains migration support only when its own source
shape, fixtures, and tests are added.

## 5. Evidence hierarchy and confidence rule

The legacy source program supplies migration inputs. A SAS adapter may
extract:

- `%let` values used for titles and population text;
- input libraries, datasets, and `set` statements;
- ODS, `OUTRTF=`, and filename destinations;
- variables and their comment-group headings;
- `BY=`, `BYVALUE=`, `VAR`, `TABLE`, `ID`, and filter statements;
- labels, formats, simple assignments, and plotting arguments; and
- `%include` or `%inc` dependencies.

The optional log is evidence about what ran: resolved macro values, opened
datasets, row and variable counts, warnings, errors, and missing variables. The
optional listing is a text output reference: titles, row order, labels, group
levels, displayed precision, and reported statistics. `reference` accepts one
or more existing `.rtf` or `.docx` artifacts. Those files provide table text,
structure, and a visual comparison target. They do not supply analysis choices
that are absent from the source program.

Only deterministic extraction may remove an `EDIT:` marker. Inference may
prefill a candidate value, but the marker remains and the report quotes the SAS
lines that require review. Arbitrary macros, complex DATA-step logic, implicit
formats, and study-specific cleaning are never guessed. A migrated job with an
unresolved marker remains subject to the templates' render-time guard.

The source program, listing, log, and RTF files are read-only evidence. Migration
does not rename, move, edit, or delete them.

## 6. `dc-tables` template and adapter

### Template contract

`dc-tables.qmd` reads either the canonical dataset or one named registered
dataset. Its editable block declares:

- `DATASET`;
- an optional grouping variable;
- named variable groups in display order;
- continuous, binary, and categorical variable buckets;
- the comparison statistic;
- continuous summary and percentile choices;
- document title, footnotes, and abbreviations; and
- the Word output filename.

The compute and output path is:

```text
hv_tbl_summary()
  -> hv_man_table()
  -> hv_man_table_save()
  -> hv_check_docx()
```

The result is the flat CORR internal format saved as an editable `.docx` under
the study's logical `documents/` directory. `hv_check_docx()` runs after the
save and a structural finding stops the job. The Word file is intended to
replace the RTF artifact that the SAS program wrote for later import and
editing in Word.

### Adapter contract

The adapter recognises `%desc_tab(...)` calls. It extracts `VARTYPE`,
`VARLIST`, comment-group headings, `BY`, `BYVALUE`, `COUNTPERSIG`, titles, and
`OUTRTF`. Separate categorical and continuous calls populate the corresponding
R buckets. A SAS type or option without a defined R equivalent remains an
`EDIT:` item.

The `bio_aggrecan/documents/` RTF files are visual and numerical references.
Acceptance compares row order, labels, counts, statistics, displayed precision,
headings, footnotes, and editability in Word. Byte identity and pagination
identity are not goals because RTF and DOCX encode layout differently.

## 7. `dc-gfup` template and adapter

### Template contract

`dc-gfup.qmd` reads a selected registered dataset and requires explicit event
and follow-up-time fields. It reports:

- missing event and follow-up values;
- `proc_means()` summaries for the full cohort;
- summaries split into relevant event and censoring groups;
- counts of negative, zero, missing, or otherwise impossible follow-up; and
- a short sorted review table for suspicious observations.

An identifier may be selected for local review, but no patient identifier is
enabled in the installed template. The template does not print every patient
and does not reproduce legacy date arithmetic whose only purpose was to rebuild
fields now supplied by the registered data.

### Adapter contract

The adapter extracts the event, follow-up, date, and optional identifier fields
from `VAR`, `TABLE`, `ID`, `BY`, sort, and simple filter statements. It
recognises the survivor subset used by the legacy job. Derived date arithmetic,
external `%vars` transformations, and event-specific commented scaffolding are
quoted in the report and left for review.

## 8. `dp-trends` adapter

The existing `dp-trends.qmd` remains the template authority. Its adapter
extracts:

- the operation-year field or simple year construction;
- variables trended together;
- percent versus continuous intent when the source states it;
- labels, grouping or filtering statements;
- axis ranges and breaks; and
- legacy figure titles and destinations.

A fractional interval plus a stated calendar-year origin may be translated to
the existing whole-year expression. An origin inferred only from observed
values remains an `EDIT:` item. Hand-written aggregation, smoothing, or
plotting code is recorded as replaced source rather than copied into the R job,
because `hvtiPlotR::hv_trends()` owns those operations.

## 9. `dp-postage` template and adapter

### Template contract

`dp-postage.qmd` implements the whole-dataset EDA meaning used by the legacy
`tp.dp.DescriptiveSummary.qmd`: one small panel per selected variable. It is
not the subgroup-faceting recipe called a postage stamp elsewhere, and it is
not the per-variable `dp-variable` job.

The editable block declares:

- `DATASET`;
- the x or preferred-time variable;
- variables to include or exclude;
- grid rows and columns; and
- common point and axis settings.

The template removes no columns by name unless the author confirms the
selection. It warns when likely identifiers or date fields are included. For
each selected variable it calls `hvtiPlotR::hv_eda()` and plots the returned
object. `patchwork::wrap_plots()` arranges those plots into numbered pages. The
template writes page-level PNG files under the study's logical `graphs/`
directory and embeds them in the rendered job. This change adds no plotting
package function.

### Adapter contract

The adapter reads the preferred time, color, stratification, inclusion and
exclusion choices, grid dimensions, alpha, and simple scale settings from the
legacy R or SAS source. `hv_eda()` has no color-variable argument, so a legacy
color choice is recorded as unresolved rather than translated. Study-specific
cleaning remains an unresolved block, quoted in the migration report.
Supporting both `.qmd` and `.sas` source here does not create a generic R-to-R
converter; it is the adapter for this one legacy template shape.

## 10. Template identity and placement

The three new files are:

```text
inst/templates/10_descriptive/dc-tables.qmd
inst/templates/10_descriptive/dc-gfup.qmd
inst/templates/10_descriptive/dp-postage.qmd
```

All are qualified because `dc` and `dp` have several job types. Jobs scaffold
into the bare folders retained by an adopted study:

```text
descriptive/cohort-eda-dc-tables.qmd
descriptive/cohort-eda-dc-gfup.qmd
graphs/cohort-eda-dp-trends.qmd
descriptive/cohort-eda-dp-postage.qmd
```

Every template retains the existing obligations: its own format block, exactly
one `ENDPOINT` declaration and one `TYPE` declaration, study-specific lines
marked `EDIT:`, a file-specific `.lintr` entry, no study identifiers, a row in
the installed template README, and a NEWS entry under the unreleased heading.

`dp-postage` exposes the existing folder-authority defect. `hvti_taxonomy()`
maps the prefix `dp` coarsely to `graphs`, while the job catalog maps each
qualified row to its actual folder. Template placement tests will consult the
catalog row first and fall back to the taxonomy only when no catalog row exists.
The taxonomy remains one row per prefix.

## 11. Migration report

For an output job `descriptive/cohort-eda-dc-tables.qmd`, migration writes
`descriptive/cohort-eda-dc-tables-migration.md`. The report contains:

- source, listing, log, and output-reference paths as study-relative paths;
- source checksums;
- selected package template and installed package version;
- values translated with their source line numbers;
- unresolved choices with quoted source lines and the matching `EDIT:` marker;
- ignored sections and the reason each was ignored;
- warnings and errors found in the log;
- output facts found in the listing; and
- a completion checklist.

Absolute share paths do not enter the report. The report is evidence for the
migration and remains beside the editable job rather than under generated
artifacts.

## 12. Failure handling

Migration stops before writing when:

- the source file is missing or unreadable;
- template selection is unknown or ambiguous;
- no adapter is registered for the selected template;
- an optional listing, log, or reference path was supplied but cannot be read;
- the output job or report already exists;
- the adapter finds contradictory deterministic values; or
- the selected template lacks its required substitution markers.

The job and report are prepared before either becomes authoritative. If either
placement fails, neither partial output remains. SAS evidence files are never
changed.

A log containing SAS errors does not silently produce a finished migration.
The report records the errors and the generated job retains a blocking marker.
Warnings are recorded and classified by the adapter when a known warning has a
defined consequence; otherwise they remain unresolved.

## 13. Tests and acceptance

### Package tests

Each adapter has its own small fixtures and tests. Tests cover successful
extraction, ambiguous or duplicated fields, commented code, mixed-case SAS,
missing optional evidence, SAS errors, atomic failure, and overwrite refusal.
The common dispatch tests prove that an unsupported template errors rather than
using another adapter.

Template tests cover marker counts, study-identifier exclusion, folder
placement, dataset selection, output paths, and render-time guards. The
`dc-tables` tests inspect the generated DOCX structurally. Postage-stamp tests
assert deterministic page counts and filenames. Follow-up tests assert the
reported cohorts and impossible-value counts. Trend migration tests compare
the extracted configuration with the existing template contract.

The vignette renders from a temporary legacy fixture during package checks. It
must leave no files outside that fixture.

### Live acceptance on `bio_aggrecan`

Live validation begins only after the study share responds and the upstream
study API is complete. It will:

1. inventory the study without writing;
2. record the exact adoption and registration commands for review;
3. adopt the study without replacing existing files;
4. register the canonical and named subset datasets;
5. migrate one source job for each supported adapter;
6. review and resolve every remaining marker;
7. render all four jobs; and
8. compare the Word tables with the existing RTF references.

The live study is not modified as part of package tests. Before adoption, the
exact write set and recovery path are presented separately because a network
study directory is shared state.

## 14. Repository and release scope

Implementation belongs in `hvtiRtemplates`. The current `hvtiR` catalog already
marks `dc-tables`, `dc-gfup`, `dp-trends`, and `dp-postage` as shipped. The
catalog is a verification input for this change, not an edit target. Strict
catalog-backed tests must confirm that every installed template still agrees
with those rows. `hvtiRutilities`, `hvtiRtables`, and `hvtiPlotR` are
dependencies, not edit targets for this design.

The active `add_job()` branch lands first. This branch then rebases onto it and
uses that public name throughout. The implementation adds `hvtiRtables`,
`hvtiPlotR`, `patchwork`, and the packages required to render the vignette to
`Suggests` with the minimum versions that provide the called interfaces.

The package change is done when:

- `devtools::test()` passes, including catalog-backed tests;
- every new template renders;
- the tutorial vignette renders;
- `devtools::document()` leaves `man/` and `NAMESPACE` current;
- `devtools::check()` reports 0 errors, 0 warnings, and 0 notes;
- the catalog and rendered roadmap agree with the installed templates; and
- the live acceptance record documents the `bio_aggrecan` comparison without
  placing study data or identifiers in the package repository.

## 15. Out of scope

- General SAS-to-R translation.
- Automatic translation of arbitrary macros or DATA-step programs.
- Recovery of a damaged study contract.
- Editing, moving, or deleting legacy SAS evidence.
- Byte-for-byte or page-for-page equivalence between RTF and DOCX.
- New statistical, table, or plotting engines in sibling packages.
- Migration adapters for templates beyond the four taught here.
