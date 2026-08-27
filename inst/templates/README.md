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

A corpus census (`hvtiRutilities::job_census()`, 2026-08-27) measured, over
`general` and `vascular` alone — 318,951 files across 250 studies:

| prefix | claimed | measured (lower bound) |
|---|---|---|
| `hm` | 1 study | **33 studies** |
| `bh` | 1 study | **30 studies** |
| `hs` | 1 study | **11 studies** |

Lower bounds because `cardiac` and `thoracic` were absent from that run. Only
`gm` and `rg` were genuinely at one study.

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
