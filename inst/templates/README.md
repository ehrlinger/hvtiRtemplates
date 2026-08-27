# Supported R job templates

Files in this directory are **supported and runnable**: they render, they are
tested, and they are the intended starting point for a new analysis job. Copy
one with `new_job()` rather than by hand, which names the file consistently and
refuses to overwrite an existing job.

## What is here

| template | job type | scaffolds into |
|---|---|---|
| `distributions/03.01-ac.qmd` | actuarial life tables | `distributions/` |

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
`specs/2026-08-21-template-set-layout-design.md`.

## What is not here yet, and why

`hz` (parametric temporal-hazard fit) and `hp` (nomogram and figures) are **not
templated yet**, even though the two-studies gate is now open. `ac`, `hz` and
`hp` each exist in two studies (`preserve_root` and `maze/atricure/gender`),
and `maze/atricure/gender`'s run reproduced **its own study's** SAS results
(not `preserve_root`'s — no cross-study reproduction is claimed or possible):
log-likelihoods evaluated at SAS's converged estimates matched within 1e-3
(overall -176.934, male -92.9158, female -81.7217), and SAS's printed
nomograms matched at **22/22** points — 8 survival and 8 hazard on the overall
fit, plus 7 survival on each per-sex fit. Template extraction for `hz`/`hp` is
the next piece of work, not blocked on a study count anymore.

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

The guard then warns instead of stopping, **and the report carries a DRAFT
banner naming the unresolved markers**. The banner is deliberate: a draft render
that looks like a finished one is the same defect with an extra step, and the
`.html` is what gets sent to someone.

The guard does not catch a marker that was worked *wrongly* — a placeholder
replaced with a mistyped column name leaves nothing to scan for. That case is
covered separately, by assertions in `derive_cats()` and against `DERIVED`,
which fail when a named column is not in the data.
