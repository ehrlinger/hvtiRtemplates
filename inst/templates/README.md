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
templated yet**. Both shapes exist in exactly one study, and a template
extracted from a single example encodes that study's choices as though they
were general. They arrive once a second study has run them.

`bh` and `hm` are likewise pending.

## Editing a scaffolded job

Every line a study must change is marked `EDIT:`. Work through them in order;
the markers are placed so that a job which still contains one has not been
finished. The comments around them record why a choice matters, not merely what
to type — several exist because the alternative fails quietly rather than
loudly.
