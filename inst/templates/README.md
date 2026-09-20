# Supported R job templates

Files in this directory are **supported and runnable**: they render, they are
tested, and they are the intended starting point for a new analysis job. Copy
one with `add_job()` rather than by hand, which names the file consistently and
refuses to overwrite an existing job.

## What is here

| template | job type | a job scaffolds into |
|---|---|---|
| `20_distributions/ac.qmd` | actuarial life tables | `20_distributions/` or `distributions/` |
| `20_distributions/hz.qmd` | multiphase parametric hazard fit | `20_distributions/` or `distributions/` |
| `40_graphs/hp.qmd` | nomogram and hazard figures | `40_graphs/` or `graphs/` |
| `40_graphs/hs.qmd` | patient-level predictions and expected survival | `40_graphs/` or `graphs/` |
| `40_graphs/dp-trends.qmd` | trends over operation year (EDA) | `40_graphs/` or `graphs/` |
| `10_descriptive/dc-tables.qmd` | CORR Word tables and optional correlations | `10_descriptive/` or `descriptive/` |
| `10_descriptive/dc-gfup.qmd` | recorded follow-up interval checks | `10_descriptive/` or `descriptive/` |
| `10_descriptive/dc-general.qmd` | general descriptive checks (base procedures) | `10_descriptive/` or `descriptive/` |
| `10_descriptive/dp-postage.qmd` | EDA panels on numbered PNG pages | `10_descriptive/` or `descriptive/` |
| `30_analyses/hm.qmd` | multivariable hazard model | `30_analyses/` or `analyses/` |
| `30_analyses/bl.qmd` | bootstrap variable selection, logistic | `30_analyses/` or `analyses/` |
| `30_analyses/br.qmd` | bootstrap variable selection, linear | `30_analyses/` or `analyses/` |
| `30_analyses/bc.qmd` | bootstrap variable selection, Cox | `30_analyses/` or `analyses/` |
| `30_analyses/bh.qmd` | bootstrap variable selection | `30_analyses/` or `analyses/` |
| `30_analyses/rfs-fit.qmd` | random survival forest, grown and checked | `30_analyses/` or `analyses/` |
| `30_analyses/rfs-explain.qmd` | importance, VarPro and dependence for an `rfs` forest | `30_analyses/` or `analyses/` |
| `30_analyses/rfc-fit.qmd` | classification forest, grown and checked | `30_analyses/` or `analyses/` |
| `30_analyses/rfc-explain.qmd` | importance, VarPro and dependence for an `rfc` forest | `30_analyses/` or `analyses/` |
| `30_analyses/rfr-fit.qmd` | regression forest, grown and checked | `30_analyses/` or `analyses/` |
| `30_analyses/rfr-explain.qmd` | importance, VarPro and dependence for an `rfr` forest | `30_analyses/` or `analyses/` |

A template is named `<prefix>.qmd`, or `<prefix>-<qualifier>.qmd` where one
prefix carries several job types, and lives in a numbered directory named for
the taxonomy folder it scaffolds into:

```
00_datasets   10_descriptive   20_distributions   30_analyses
40_graphs     50_documents                        90_estimates
```

The name is the authority: `template_list()` reads the prefix and qualifier
from it and the folder from the directory, stripping the ordering digits.
The placement test requires the job catalog and skips when it is absent.
Its internal lookup helper uses the catalog's `(prefix, qualifier)` row and
falls back to `hvti_taxonomy()` when the catalog or matching row is absent.
The catalog places `dp-postage` in `descriptive/` and `dp-trends` in `graphs/`;
the prefix-wide taxonomy cannot distinguish those jobs. A separate test checks
that every template directory names a taxonomy folder even without the catalog.

⚠️ **The digits are ASSIGNED, not derived.** `estimates` is 90 though it is
fifth in the taxonomy, because it holds saved output rather than jobs. The
decade gaps are room to insert without renumbering.

The qualifier exists because one prefix can name several jobs. The current
qualified templates are `dc-general`, `dc-tables`, `dc-gfup`, `dp-trends`,
`dp-postage`, `rfs-fit`, `rfs-explain`, `rfc-fit`, `rfc-explain`, `rfr-fit`
and `rfr-explain`; the other prefixes here remain unqualified. A prefix is
wholly qualified or wholly unqualified, never half-decomposed.

### Random forest jobs

The random forest templates come in pairs. The `fit` job grows the forest and
saves it as `<prefix>.rds` in its set's estimates folder; the `explain` job
reads that file and never grows its own, so every explanation describes the
forest that was checked. Scaffold both into the same set, for example
`add_job("rfs", "dead", "rfs", qualifier = "fit")` and
`add_job("rfs", "dead", "rfs", qualifier = "explain")`, and render the fit job
first.

Older studies name these jobs `rfsrc.*` or `rf.*`, whatever the outcome. They
map by the outcome in the job's fit call, not by the name:

| old job | outcome | template |
|---|---|---|
| `rfsrc.*`, `rf.*` | survival | `rfs` |
| `rfsrc.*`, `rf.*` | classification or binary | `rfc` |
| `rfsrc.*`, `rf.*` | continuous | `rfr` |

## Where a scaffolded job lands

`add_job("ac", "dead_pa", "hz")` writes
`20_distributions/dead_pa-hz-ac.qmd` in a new study. Three fields, `-`
separated:
**endpoint, type, prefix**.

The study layout decides the folder. New studies use the numbered taxonomy;
an adopted legacy study with bare folders keeps `distributions/`. A study that
contains both schemes is ambiguous, so job creation stops instead of splitting
the estate across two spellings of one folder.

A job scaffolded from a qualified template carries the qualifier as a fourth
field, so `add_job("dp", "cohort", "eda", qualifier = "trends")` writes
`40_graphs/cohort-eda-dp-trends.qmd` in a new study. A filename that drops the qualifier says
only "some `dp` job", which is what splitting the templates exists to fix.
An EDA job's set key is `(subject, eda)`: the endpoint field names what is
described, and the type is always `eda`.

⭐ **The ordinal was dropped in 1.1.0.** A job named
`dead_pa-hz-03.01-ac.qmd` is from before that change; `03.01` was the taxonomy
folder's position and a per-folder key, and both are gone. See
`dev/specs/2026-09-03-template-identity-design.md`.

The layout rule is one sentence, and it holds in every folder:

> **Authored files sit flat. Generated artifacts sit under `<endpoint>-<type>/`.**

```
<study_root>/
├── distributions/  dead_pa-hz-ac.qmd        dead_pa-rfs-ac.qmd
├── estimates/                                dead_pa-hz/ac.rds
└── graphs/         dead_pa-hz-hp.qmd         dead_pa-hz/hp-fig1.png
```

**A set is keyed on `(endpoint, analysis type)`, not on the endpoint alone.**
One endpoint is analysed by several methods, and those chains share their
upstream — a death-hazard set and a death random-forest-survival set both begin
from the same life table. Keyed on the endpoint alone, both would be written to
`dead_pa-ac.qmd`. The cost of carrying the type on every job is that the
shared upstream runs once per set rather than once per endpoint; the benefit is
that a set is self-contained and uniformly named.

The full design, including what was rejected and why, is in
`dev/specs/2026-08-21-template-set-layout-design.md`.

## What is not here yet, and why

The five job types
[#8](https://github.com/ehrlinger/hvtiRtemplates/issues/8) offered as candidate
content all ship now, `bh` last: `hz` in 1.0.6, `hp` in 1.0.7, `hm` in 1.0.8,
`hs` in 1.0.12 and `bh` in 1.0.13. The bootstrap family joined it in 1.0.20:
`bl`, `br` and `bc`. What is still untemplated is the rest of the taxonomy, and the roadmap ledger — not this file — is the authority on which
prefix is scheduled when:
[`dev/specs/2026-08-29-template-conversion-roadmap.md`](../../dev/specs/2026-08-29-template-conversion-roadmap.md).

**`bh`'s companion runner is not templated.** The screen is days of compute and
`hzr_bootstrap()` writes nothing until its final replicate, so the run is
chunked from a separate script and this template reports over what that script
wrote. Templating the runner needs multi-file templates in `add_job()`, which
is a package change. `hm` has the same gap.

**Nor are `bl`, `br` and `bc`'s.** Their runner calls
`hvtiRbootstrap::boot_select()` with the fitter for its model and converts the
result with `boot_bag()`, which is one call and needs no template. What it must
supply is the four facts the screen cannot know: which terms are the base
model, how many candidates were offered before any were dropped, the dataset
manifest, and what was dropped.

⚠️ **None of the three has been rendered against a screen a study ran.** No R
job in the corpus calls `boot_select()` yet, so all three were gated on a
screen run against a real built dataset for the purpose. That covers real
variable names and a real correlation structure; it does not cover the
candidate pool and the dropped set a study author chooses, which is where
`bh`'s one shipped defect lived. `bc` has the least behind it: it ships because
`fit_cox()` exists, not because a study has run one, and of the 16 studies with
a `bc` job none has an R exemplar. Read the first real output of any of the
three against your own expectations, not as a checked path.

`hz` and `hp` were each extracted from three R exemplars — `preserve_root`,
`maze/atricure/gender` and `lv_function/survival`. **`hm` had only one R
exemplar**, so its second was the SAS job at
`cardiac/ischemic/cabg/diabetes/surg_factors/dm_nodm`, which is enough for the
purpose: the gate exists to stop one study's choices being encoded as general,
and a SAS job states those choices as plainly as an R one. It earned its place
immediately — it carries a `%deciles` calibration step the R exemplar has no
equivalent for, and without it the template would have shipped a
model-selection job that never asks whether the model calibrates.

⚠️ **Two different questions get called "the gate", and they have different
answers.** The corpus census below counts **SAS** jobs, which answers *will a
template serve more than one study* — yes, everywhere. The gate's stated reason
is the other one: *are there two R implementations to generalise from*, since a
template extracted from a single example encodes that study's choices as though
they were general. Filtering the same census to its 1,144 `.qmd` rows answers
that one:

| prefix | studies with an R job |
|---|---|
| `ac` | 4 |
| `hz` | 3 |
| `hp` | 3 |
| `bh` | 2 |
| `hm` | **1** |
| `hs` | 1 |

That count is a lower bound — the census sees `.qmd` only, so a job written as
`.R` or `.Rmd` is invisible to it, and the error direction is undercounting.

`hz` was worth extracting on those three because they **disagree**, and the
disagreements are the template: two seed `theta` from SAS's converged estimates
while the third seeds neutral shapes with a data-derived time scale, and each is
correct for its own case. Extracted from either alone, the template would have
made the other case silently wrong.

`hm`, `hs` and `bh` are **not** blocked by the two-studies gate. An earlier
version of this paragraph said each existed in only one study. That was read
off a comparison of two directories — `preserve_root` and
`maze/atricure/gender` — and stated as though it held for the corpus.

A corpus census (`hvtiRutilities::job_census()`, 2026-08-27) over the whole of
`/studies` — **2,240,570 files** across all four top-level trees:

| prefix | claimed | measured |
|---|---|---|
| `hm` | 1 study | **383 studies** |
| `bh` | 1 study | **322 studies** |
| `hs` | 1 study | **144 studies** |

**No taxonomy prefix anywhere in the corpus sits at one study.** The whole
"BLOCKED" list is empty. The smallest are `bq` at 2 studies and `cp`/`pm` at 5
— still past the gate. The two-studies gate is open for every prefix the
taxonomy documents, and nothing is waiting on a second exemplar.

The two-directory counts were accurate about those two directories; the
inference from them was not. **Do not quote a per-study count as a gate
answer** — run `job-census.R /studies` server-side, which is what the gate
question is for. `hs` was missing from this list before it was corrected, and
its absence read as "templated".

## Editing a scaffolded job

`migrate_job()` can prefill `dc-tables`, `dc-gfup`, `dp-trends`, and
`dp-postage` from their supported legacy source shapes. It writes a report
beside the job with evidence checksums, source lines, translated values, and
unresolved choices. The existing source and evidence files remain in place.
Only deterministic extraction can remove a marker. Review inferred values,
unsupported cleaning, and presentation choices against the source and study
protocol before removing their `EDIT:` markers.

The table job writes an editable CORR DOCX under
`documents/<endpoint>-<type>/`, replacing the SAS RTF output. Its
`hv_tbl_summary()` -> `hv_man_table()` -> `hv_man_table_save()` ->
`hv_check_docx()` path stops on document-format findings. Compare its numerical
and presentation choices with the RTF reference yourself. Follow-up checks use
registered intervals; they do not establish completeness against a close date.
Trend figures and numbered postage PNG pages go under
`graphs/<endpoint>-<type>/`, including when the postage job itself lives in
`descriptive/`.

`vignette("legacy-study-migration", package = "hvtiRtemplates")` shows
adoption, separate study and named-dataset registration, all four migrations,
marker review, and rendering in a disposable synthetic study.

Every line a study must change is marked `EDIT:`. Work through them in order;
the markers are placed so that a job which still contains one has not been
finished. The comments around them record why a choice matters, not merely what
to type — several exist because the alternative fails quietly rather than
loudly.

**That property is enforced, not merely stated.** Each template carries an
`edit-guard` chunk that scans the rendering file for markers and lists the ones
it found. Until 1.0.5 it was a convention only, and an unedited `ac` template
rendered green over a meaningless stratification: the `derive` chunk indexed a
placeholder column, and when a column is absent `!is.na(d$<col>)` is
`logical(0)`, which makes the assignment a **silent no-op** rather than an
error ([#27](https://github.com/ehrlinger/hvtiRtemplates/issues/27)).

**A job with markers left renders as a draft.** The guard warns, and the
report opens with a DRAFT banner naming the unresolved markers, so the author
renders as they work and the banner goes when the last marker does. The guard
only stops blocking: a section still holding a template placeholder, such as a
column the study does not have, stops with its own error, so a fresh job
renders as far as the markers already worked. It is deliberate: a draft render that
looks like a finished one is the same defect with an extra step, and the
`.html` is what gets sent to someone.

`open_job()` and `render_job()` are the intended way to scaffold and render a
job from R, from anywhere inside the study:

```r
job <- open_job("ac", "dead_pa", "hz")   # creates the job with add_job(), or
                                          # opens it unchanged if it exists
render_job(job)                          # draft, as far as the markers worked
render_job(job, final = TRUE)            # the accepted result: stops instead
                                          # of drafting if a marker remains
```

Rendering outside R with a bare `quarto render` also works, and drafts by
default; to make it stop on an unfinished job instead, set the same variable
`render_job()` sets for you:

```sh
HVTI_TEMPLATE_STRICT=1 quarto render <endpoint>-<type>-ac.qmd
```

Unset, `0`, `false` and `no` leave the job rendering as a draft, case-insensitively.
**Any other value stops**, `1`, `true` and `yes` included, so a mistyped value
fails toward the stop and the author sees it rather than getting a quiet draft.

The guard does not catch a marker that was worked *wrongly* — a placeholder
replaced with a mistyped column name leaves nothing to scan for. That case is
covered separately, by assertions in `derive_cats()` and against `DERIVED`,
which fail when a named column is not in the data.
