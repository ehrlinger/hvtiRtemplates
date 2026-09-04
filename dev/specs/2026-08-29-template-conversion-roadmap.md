# Template conversion roadmap

**Date:** 2026-08-29
**Status:** live — this document tracks work in progress
**Design:** `2026-08-29-template-conversion-roadmap-design.md`, which argues
every decision recorded here. Read it before changing anything.

The taxonomy names 42 analysis prefixes and three more are proposed. Four
templates ship. This is the queue for the rest, and the ledger behind it is
`artifacts/2026-08-29-template-roadmap.json`.

## How to read this

**One template per prefix.** Variants become `EDIT:` markers inside the file,
not separate templates.

**Batched by family.** One design spec per family, then one implementation PR
per prefix off it. Batches 0 to 2 are decided; **3 and later are provisional**
and will be reordered as evidence arrives.

**Two counts, measuring different things.** *Breadth* counts studies using that
job type across every extension and is SAS-dominated — it measures how much a
template is worth. *R exemplars* counts studies with an R job of that type — it
measures how much precedent there is to extract from. A prefix can be wide and
precedent-free; `bd` is 1,134 and 15. Never conflate them.

**An em dash means unmeasured, not zero.** Nine prefixes have a measured zero R
exemplars, which is a finding, not a gap.

## Changing this document

Do not hand-edit the generated tables. Edit
`artifacts/2026-08-29-template-roadmap.json`, then:

```sh
python3 dev/specs/artifacts/roadmap_render.py
```

`check-roadmap-counts.py` fails the PR if the two disagree, or if a `shipped`
row has no template on disk.

<!-- BEGIN GENERATED -->

> Generated from the job catalog in `hvtiR` (`inst/extdata/jobs.json`) by
> `artifacts/roadmap_render.py`. Do not hand-edit these tables —
> edit the catalog and re-render. CI checks the agreement.

**41 templates in scope**, of which 9 exist on disk. 0 demoted to umbrella rows.

## By family

### hazard-chain (batch 1)

| template | status | breadth | jobs | R exemplars | blocked on |
|---|---|---|---|---|---|
| `hs` | shipped | 144 | 140 | 7 | — |
| `hm` | shipped | 383 | 373 | 2 | — |

### bootstrap (batches 0–2)

| template | status | breadth | jobs | R exemplars | blocked on |
|---|---|---|---|---|---|
| `bh` | shipped | 322 | 320 | 2 | — |
| `bc` | shipped | 16 | 16 | 0 | — |
| `bl` | shipped | 352 | 352 | 1 | — |
| `br` | shipped | 103 | 103 | 1 | — |
| `bq` | queued | 2 | 2 | 0 | hvtiRbootstrap#16 |

### bootstrap-ci (unscheduled)

| template | status | breadth | jobs | R exemplars | blocked on |
|---|---|---|---|---|---|
| `bn` | queued | 214 | 108 | 0 | — |

### plots (batch 3)

| template | status | breadth | jobs | R exemplars | blocked on |
|---|---|---|---|---|---|
| `dp-gfup` | queued | — | 48 | — | — |
| `dp-procs` | queued | — | 35 | — | — |
| `dp-spaghetti` | queued | — | 40 | — | — |
| `dp-trends` | queued | — | 80 | — | — |
| `dp-variable` | queued | — | 237 | — | — |
| `hp` | **revisit** | 557 | 541 | 16 | — |
| `lp` | queued | 636 | 310 | 186 | — |
| `mp` | queued | 82 | 41 | 4 | — |
| `np` | queued | 248 | 241 | 45 | — |
| `rp` | queued | 76 | 68 | 5 | — |

### descriptive (batch 4)

| template | status | breadth | jobs | R exemplars | blocked on |
|---|---|---|---|---|---|
| `dc-dead` | queued | — | 171 | — | — |
| `dc-general` | queued | — | 759 | — | — |
| `dc-gfup` | queued | — | 389 | — | — |
| `dc-stddiff` | queued | — | 59 | — | — |
| `dc-tables` | queued | — | 551 | — | — |
| `lg` | queued | 367 | 362 | 0 | — |
| `rg` | queued | 45 | 45 | 0 | — |

### models (batch 6)

| template | status | breadth | jobs | R exemplars | blocked on |
|---|---|---|---|---|---|
| `cm` | queued | 35 | 35 | 2 | — |
| `gm` | queued | 77 | 73 | 0 | — |
| `lm` | queued | 621 | 469 | 10 | — |
| `ls` | queued | 34 | 32 | 0 | — |
| `mm` | queued | 59 | 56 | 1 | — |
| `nm` | queued | 122 | 121 | 1 | — |
| `pm` | queued | 5 | 4 | 0 | — |
| `rm` | queued | 174 | 170 | 8 | — |

### distributions (batch 7)

| template | status | breadth | jobs | R exemplars | blocked on |
|---|---|---|---|---|---|
| `ac` | shipped | 756 | 745 | 16 | — |
| `cd` | queued | 202 | 190 | 6 | — |
| `hz` | shipped | 581 | 574 | 5 | — |
| `nd` | queued | 244 | 244 | 3 | — |

### datasets (batch 8)

| template | status | breadth | jobs | R exemplars | blocked on |
|---|---|---|---|---|---|
| `bd` | queued | 1134 | 1094 | 15 | hvtiRdatabuild |
| `dt` | queued | 512 | 503 | 0 | hvtiRdatabuild |
| `vars` | queued | 959 | 912 | 2 | hvtiRdatabuild |

### documents (batch 9)

| template | status | breadth | jobs | R exemplars | blocked on |
|---|---|---|---|---|---|
| `ar` | queued | 706 | 394 | 89 | — |

## By workflow

A workflow is complete when every prefix in it is on disk.

### hazard-chain — 5/5

Members: `ac`, `hm`, `hp`, `hs`, `hz`

**Complete.**

### propensity-matching — 2/10

Members: `bd`, `bl`, `cm`, `dc-stddiff`, `hp`, `lm`, `lp`, `pm`, `rm`, `rp`

Outstanding: `bd`, `cm`, `dc-stddiff`, `lm`, `lp`, `pm`, `rm`, `rp`.

<!-- END GENERATED -->

## What is not tracked here

The **study-level assembly** — a bookdown report combining the templates a
study ran, for handoff to researchers — has no taxonomy prefix yet and so has
no row. It is a `new-prefix` intake item blocked on an `hvti_taxonomy()` PR in
`hvtiRutilities`, and it is the only genuinely terminal unit in the roadmap.
`ar` is **not** that thing: it writes up one analysis, named
`ar.<method>.<endpoint>`.
