# Supported R job templates

Files in this directory are **supported and runnable**: they render, they are
tested, and they are the intended starting point for a new analysis job. Copy
one with `new_job()` rather than by hand, which names the file consistently and
refuses to overwrite an existing job.

## What is here

| template | job type | scaffolds into |
|---|---|---|
| `distributions/03.01-ac.qmd` | actuarial life tables | `distributions/` |
| `distributions/03.02-hz.qmd` | multiphase parametric hazard fit | `distributions/` |
| `graphs/06.01-hp.qmd` | nomogram and hazard figures | `graphs/` |
| `graphs/06.02-hs.qmd` | patient-level predictions and expected survival | `graphs/` |
| `analyses/04.01-hm.qmd` | multivariable hazard model | `analyses/` |
| `analyses/04.06-bh.qmd` | bootstrap variable-selection screen | `analyses/` |

A template is named `<NN.MM>-<prefix>.qmd` and lives in the taxonomy folder it
scaffolds into. The name is the authority: `template_list()` reads the ordinal
and prefix from it and the folder from the directory, and the test suite checks
both against `hvti_taxonomy()`.

## Where a scaffolded job lands

`new_job("ac", "dead_pa", "hz")` writes
`distributions/dead_pa-hz-03.01-ac.qmd`. Four fields, `-` separated, with `.`
reserved for inside the ordinal: **endpoint, type, ordinal, prefix**.

The layout rule is one sentence, and it holds in every folder:

> **Authored files sit flat. Generated artifacts sit under `<endpoint>-<type>/`.**

```
<study_root>/
├── distributions/  dead_pa-hz-03.01-ac.qmd   dead_pa-rfs-03.01-ac.qmd
├── estimates/                                dead_pa-hz/ac.rds
└── graphs/         dead_pa-hz-06.01-hp.qmd   dead_pa-hz/hp-fig1.png
```

**A set is keyed on `(endpoint, analysis type)`, not on the endpoint alone.**
One endpoint is analysed by several methods, and those chains share their
upstream — a death-hazard set and a death random-forest-survival set both begin
from the same life table. Keyed on the endpoint alone, both would be written to
`dead_pa-03.01-ac.qmd`. The cost of carrying the type on every job is that the
shared upstream runs once per set rather than once per endpoint; the benefit is
that a set is self-contained and uniformly named.

The full design, including what was rejected and why, is in
`dev/specs/2026-08-21-template-set-layout-design.md`.

## What is not here yet, and why

Every job in issue #8 is now templated. `hz` shipped in 1.0.6, `hp` in 1.0.7,
`hm` in 1.0.8, `hs` in 1.0.12 and `bh` in 1.0.13; see the design specs dated
2026-08-27 onward.

What is **not** templated is `bh`'s companion **runner**. The screen is days of
compute and `hzr_bootstrap()` writes nothing until its final replicate, so the
run is chunked from a separate script and `04.06-bh.qmd` reports over whatever
that script wrote. Templating the runner needs multi-file support in
`new_job()`, which is a package change rather than another template. `hm` has
the same gap.

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

Every line a study must change is marked `EDIT:`. Work through them in order;
the markers are placed so that a job which still contains one has not been
finished. The comments around them record why a choice matters, not merely what
to type — several exist because the alternative fails quietly rather than
loudly.

**That property is enforced, not merely stated.** Each template carries an
`edit-guard` chunk that scans the rendering file and stops if any marker
remains, listing the ones it found. Until 1.0.5 it was a convention only, and
an unedited `03.01-ac` rendered green over a meaningless stratification: the
`derive` chunk indexed a placeholder column, and when a column is absent
`!is.na(d$<col>)` is `logical(0)`, which makes the assignment a **silent no-op**
rather than an error ([#27](https://github.com/ehrlinger/hvtiRtemplates/issues/27)).

To render a partly-worked job while drafting, set `HVTI_TEMPLATE_DRAFT=1`:

```sh
HVTI_TEMPLATE_DRAFT=1 quarto render <endpoint>-<type>-03.01-ac.qmd
```

`1`, `true` and `yes` enable it, case-insensitively. **Any other value leaves
the guard strict**, `0` included — a variable set to `0` meaning "off" must not
switch the guard off by being non-empty, and an unrecognised value fails toward
the stop so the author sees it rather than getting a quiet draft.

The guard then warns instead of stopping, **and the report carries a DRAFT
banner naming the unresolved markers**. The banner is deliberate: a draft render
that looks like a finished one is the same defect with an extra step, and the
`.html` is what gets sent to someone.

The guard does not catch a marker that was worked *wrongly* — a placeholder
replaced with a mistyped column name leaves nothing to scan for. That case is
covered separately, by assertions in `derive_cats()` and against `DERIVED`,
which fail when a named column is not in the data.
