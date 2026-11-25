# hvtiRtemplates

[![R package
version](https://img.shields.io/github/r-package/v/ehrlinger/hvtiRtemplates)](https://github.com/ehrlinger/hvtiRtemplates)

[![lint](https://github.com/ehrlinger/hvtiRtemplates/actions/workflows/lint.yaml/badge.svg)](https://github.com/ehrlinger/hvtiRtemplates/actions/workflows/lint.yaml)

Versioned analysis job templates for the HVTI CORR group at the
Cleveland Clinic.

**New to the family, or to a study? Read [Start
here](https://ehrlinger.github.io/hvtiR/articles/start-here.html)
first.** It sets the study up with `hvtiR::setup()` and sends you on to
the tutorials on this site.

**Start at the [template
gallery](https://ehrlinger.github.io/hvtiRtemplates/gallery/):** every
template, what it is for, the
[`add_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md)
call that adds it to your study, and the report it produces on a
synthetic study. The full reference is at
<https://ehrlinger.github.io/hvtiRtemplates/>.

## Installation

hvtiRtemplates is part of the HVTI R family. Install it with the rest of
the family through [hvtiR](https://github.com/ehrlinger/hvtiR):

``` r

# install.packages("pak")
pak::pak("ehrlinger/hvtiR")
hvtiR::install()
```

`hvtiR::install()` installs every member in one call, so the versions
the members require of one another resolve together. Update later with
`hvtiR::update()`. On Linux and macOS it installs over a package that is
already loaded and then tells you to restart R; on Windows, run it from
a fresh R session.

To install hvtiRtemplates on its own:

``` r

pak::pak("ehrlinger/hvtiRtemplates")
```

In a project that uses renv, install with
`renv::install("ehrlinger/hvtiRtemplates")` instead, so the package
lands in the project library.

## What is here

| Directory | Status | Contents |
|----|----|----|
| `inst/templates/` | **supported** | R job templates. See `inst/templates/README.md` for coverage. |

Everything the package installs is supported: tested, maintained, and
intended to be run. There is no reference-only material.

## There is no SAS corpus here

During development this repository also carried the legacy SAS template
corpus (240 files) and the SAS macro library (495 files, with history
imported from 2014) as a reference specification. Both were removed
before release, and every path was purged from every commit with
`git filter-repo` — they are not recoverable from this repository’s
history by design.

Two consequences worth stating plainly. Parity work against the SAS
originals needs a source outside this repository; the institutional SAS
license runs to September 2027, so plan accordingly. And a result filed
before the migration still cannot say what produced it — that was
already true, because `%inc` bound late to a mutable directory with no
version, and removing the corpus neither creates nor worsens that gap.

## Why this package exists

Study analyses were created by copying template files into a new study
folder and editing them. Two things followed: improvements stayed in the
study where they were made, and — the problem that actually hurts — a
filed result could not say what produced it. SAS bound its analysis
logic with `%inc kaplan`, resolving at run time against a mutable
directory with no version, so the `.lst` filed in 2006 was produced by a
`kaplan` nobody can now identify.

The design rule is **bind late, to something versioned**. Late binding
is right; SAS could not make it safe because there was no version to
pin. `renv.lock` supplies that, so a study can use the latest while
working and pin it on filing.

In practice a study declares `hvtiRtemplates` in its `renv.lock`, and
[`add_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md)
copies a template into the study as an editable job; the job’s setup,
guards and provenance run from the installed package rather than from
the copy. The study pins the version when results are filed. The lock
file is then one part of the answer to “what produced this?”: it fixes
the package code, and each render’s provenance records the rest, a
checksum of the job’s own source and the registered data it read. That
is the question the SAS arrangement could not answer, because `%inc` had
nothing to pin.

## API

### The taxonomy and the catalog

| Function | Returns |
|----|----|
| [`template_catalog()`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_catalog.md) | every template job, including queued work and dependencies |
| [`hvti_taxonomy()`](https://ehrlinger.github.io/hvtiRutilities/reference/hvti_taxonomy.html) | the analysis prefix table: prefix, name, folder, description |
| [`template_list()`](https://ehrlinger.github.io/hvtiRtemplates/reference/template_list.md) | supported templates: name, folder and title printed; prefix, qualifier, description, call and file in the data |
| `template_path(prefix, qualifier = NULL)` | path to one supported template |
| [`hvti_non_prefixes()`](https://ehrlinger.github.io/hvtiRutilities/reference/hvti_non_prefixes.html) | leading name fields that are utilities, not analysis prefixes |

### Scaffolding and upgrading jobs

| Function | Returns |
|----|----|
| `add_job(prefix, subject, type, root = NULL, qualifier = NULL, open = TRUE)` | the scaffolded job’s path, invisibly |
| `open_job(prefix, subject, type, root = NULL, qualifier = NULL)` | job path; creates a missing job or opens an existing one |
| `upgrade_job(path, root = NULL, open = TRUE)` | the upgraded job’s path, invisibly; rewrites a job from its template’s current version, keeping its edits, with a report in `_archive/` |
| `import_job(path, subject = NULL, type = NULL, root = NULL)` | the imported job’s path, invisibly; copies a job from another study, keeping its edits |
| `migrate_job(path, subject, type, prefix = NULL, ...)` | the migrated job’s path, invisibly; writes an evidence report beside it |
| `read_job_data(cfg, dataset = "study", ...)` | inside a job: a list holding the selected rows and the record of what was read, joined and kept |
| `build_cohort(data, exclude = NULL, path = NULL, ...)` | a list holding the kept rows and who was dropped and why |
| [`stop_here()`](https://ehrlinger.github.io/hvtiRtemplates/reference/stop_here.md) | inside a render, the job’s provenance block, so a draft can stop partway |

### Running jobs

| Function | Returns |
|----|----|
| `run_job(path, final = FALSE, wait = 300, ...)` | the job’s status, invisibly; checks, submits and waits for a background render |
| `render_job(path, final = FALSE, quiet = ..., params = NULL, output_file = NULL)` | `path`, invisibly; renders a draft, or with `final = TRUE` a render that stops on an unfinished job |
| `submit_job(path, final = FALSE, params = NULL, output_file = NULL)` | the job’s status, invisibly; starts a render detached from the session |
| `job_status(path, quiet = FALSE, output_file = NULL)` | a background render’s state, invisibly |
| `cancel_job(path, grace = 30, ...)` | the job’s status afterwards, invisibly |
| `install_hvti(dir)` | the installed `hvti` command’s path, invisibly |
| `install_provenance_hooks(root = NULL)` | the study’s `_quarto.yml` or `_quarto.yaml` path, invisibly; adds the hooks a job that records its provenance needs, for a study whose jobs came from elsewhere |
| `guard_long_fit(name, dir, why, refit = FALSE)` | `FALSE`, invisibly, when a long fit may start; an error outside a background run |
| `guard_memory(need_gib, why, ...)` | the session’s memory limit in GiB, invisibly, when the fit fits; an error otherwise |

### The `ar` analysis report

| Function | Returns |
|----|----|
| `ar_item(id)`, `ar_value(id, field)` | inside an `ar` analysis report: one saved figure, table or value from a finished job, checked against the bytes that job recorded |
| `ar_paste_methods(path)`, `ar_review(path)` | for an `ar` report: fill each empty Methods slot from its source job, leaving existing text for the analyst to compare and update; mark items as reviewed after their source job was rendered again |

### Life tables, for the `ac` job

| Function | Returns |
|----|----|
| `life_table(data, time_col, event_col, strata_col = NULL, ...)` | a Kaplan-Meier life table, by stratum when one is named |
| `life_table_at(data, time_col, event_col, times, ...)` | survival and its limits at stated horizons, by stratum |
| `life_table_keep(data, time_col, event_col, strata_col = NULL)` | a logical vector, `TRUE` for each row the life table analyzes |
| `life_table_tests(data, time_col, event_col, strata_col)` | the log-rank, Wilcoxon and likelihood-ratio tests comparing strata |

[`add_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/add_job.md)
also installs idempotent Quarto pre-render and post-render hooks in the
study without replacing existing project settings or user hooks. Every
managed render captures the registered data actually read, embeds its
runtime payload in the completed HTML, and publishes a same-stem
`.provenance.json` beside Quarto’s actual output. A failed render leaves
the prior completed HTML and sidecar together when the output stays
untouched. If publication fails after an output changes, the hooks
expose a prior sidecar only when its recorded output hash still matches.
Otherwise they withhold the sidecar and retain its recovery backup with
a warning.

Templates are `<prefix>[-<qualifier>].qmd` in a numbered directory
(`20_distributions/ac.qmd`); a job is
`<prefix>[.<qualifier>].<subject>.<type>.qmd` in the study’s matching
taxonomy folder, so a study’s jobs sort by template. Jobs scaffolded
before 2026-10 keep their `<subject>-<type>-<prefix>[-<qualifier>].qmd`
names and keep rendering. New studies use numbered folders and existing
bare-folder studies keep their layout. The ordinal that once prefixed
filenames was dropped in 1.1.0.

The subject groups a job set. It is a statistical endpoint when the job
analyses one, such as `death`; it can instead be an endpoint-free topic
such as `cohort`, `treatment`, or `labs`. Each job owns its outcome
variables, coding, filters, and any cohort definition. Dataset
registration records the data, not a study-wide endpoint or cohort.

`qualifier` names a job type within a prefix. The current qualified
families are `dc`, `hs`, `lm`, `lp`, `nb`, `rfc`, `rfr`, `rfs`, `rhf`,
`rm`, `sid`, `vp`, and `vt`. The `lm` choices are `binary`, `ordinal`,
`nominal`, `propensity_binary`, `propensity_ordinal`,
`propensity_nominal`, `checkpred`, and `balancing_count`. It is `NULL`
and the column is `NA` for an unqualified prefix. A prefix is qualified
or not as a whole, so a qualified prefix keeps its qualifier even with
one template shipped, as `nb.boostmtree` does. Naming no qualifier where
a prefix carries several is an error listing the choices, never a silent
pick of the first.

## Migrate a legacy job

For a study with SAS programs already in `descriptive/` and `graphs/`,
first adopt its directory with `hvtiR::setup(..., adopt = TRUE)` and
register its built datasets with `register_data()`. The tutorial [Adopt
an existing study for descriptive and EDA
work](https://ehrlinger.github.io/hvtiRtemplates/articles/study-setup.md)
walks through new-study creation, recoverable legacy cleanup and
adoption, data registration, the EDA analysis set, all five pre-analysis
jobs, and output review using synthetic data.

From that study’s root, migrate a descriptive-table job with:

``` r

job <- hvtiRtemplates::migrate_job(
  path = "descriptive/dc.tables.sas",
  subject = "cohort", type = "eda", prefix = "dc", qualifier = "tables",
  lst_path = "descriptive/dc.tables.lst", log_path = "descriptive/dc.tables.log",
  reference_path = "documents/general.rtf", root = "."
)
```

Use your study’s source and evidence filenames. `lst_path`, `log_path`,
and `reference_path` are optional; supplied files must exist beneath
`root`. The call writes `descriptive/dc.tables.cohort.eda.qmd` and
`descriptive/dc.tables.cohort.eda-migration.md` in a study with bare
folders. It preserves the evidence files and refuses to overwrite either
output.

Migration supports `dc-tables`, `dc-gfup`, `dc-trends`, and `dc-eda`.
Each adapter reads a defined source shape. Only deterministic extraction
can remove an `EDIT:` marker; uncertain choices remain in the job and
report for you to resolve before rendering. Logs, listings, and RTF/DOCX
references help you check the translation but do not supply missing
analysis choices.

The table job replaces the SAS RTF output with an editable CORR DOCX
through `hv_tbl_summary()`, `hv_man_table()`, `hv_man_table_save()`, and
`hv_check_docx()`. It writes beneath `documents/<subject>-<type>/` and
stops on a structural finding. Compare the rows, summaries, precision,
and footnotes with the legacy reference before accepting the document;
the structural check does not establish numerical agreement.

## Documentation

The articles are on the [package
site](https://ehrlinger.github.io/hvtiRtemplates/).

| Article | For |
|----|----|
| [Work a job, from template to final report](https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html) | the whole cycle of one job: scaffold, edit, draft, final |
| [Running a job that takes hours](https://ehrlinger.github.io/hvtiRtemplates/articles/long-running-jobs.html) | background renders, their status and their guards |
| [Start a new study from a delivered dataset](https://ehrlinger.github.io/hvtiRtemplates/articles/new-study.html) | a study that has no SAS history |
| [Adopt an existing study for descriptive and EDA work](https://ehrlinger.github.io/hvtiRtemplates/articles/study-setup.html) | a study with legacy folders and built datasets |
| [From SAS descriptive jobs to R](https://ehrlinger.github.io/hvtiRtemplates/articles/sas-to-r-descriptive.html) | each descriptive SAS job beside the template that replaces it |
| [Migrate a legacy SAS study](https://ehrlinger.github.io/hvtiRtemplates/articles/legacy-study-migration.html) | [`migrate_job()`](https://ehrlinger.github.io/hvtiRtemplates/reference/migrate_job.md) and its evidence report |
| [The template catalog](https://ehrlinger.github.io/hvtiRtemplates/articles/template-catalog.html) | every template, supported and queued |

`inst/templates/README.md` is the contract for the templates themselves:
what each one does, its figures, and the rules every job follows.

## Related packages

The templates call the rest of the hvtiR family: `hvtiRutilities` (study
layout and registered data, imported), and `hvtiPlotR`, `hvtiRtables`,
`hvtiRdatabuild`, `hvtiRbootstrap`, `hvtiRlifetables` and
`hvtiRpropensity`, which the jobs attach as they need them.
[`hvtiR`](https://github.com/ehrlinger/hvtiR) installs them together.
