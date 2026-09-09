# EDA templates: descriptive checking, data-checking graphics, goodness of follow-up

**Date:** 2026-09-09
**Status:** design, approved in session; implementation not started
**Supersedes nothing.** Schedules six rows that
`2026-08-29-template-conversion-roadmap.md` placed in batches 3 and 4, both of
which that document marks provisional and expects to be reordered as evidence
arrives. Three of the six move batch; the other three are already where they
need to be.

## Why now

The biostats team's fellows training session (Teams, 2026-09-09) named the
exploratory-data-analysis jobs as the material fellows should be taught first,
before actuarial or hazard work. Ashley Lowry, at 54:12: "cover the templates
that we have for these types of jobs, all the EDA stuff, that's relative
specifically to R. So the postage stamps, some correlation plots, trend..."

None of those templates exists. The engines behind most of them do.

## What was asked for, and what it maps to

Six items were named. They map onto six rows that are **already in the job
catalog**, so this batch needs no new prefix and no `hvti_taxonomy()` intake in
`hvtiRutilities`.

| asked for | row | jobs | engine | missing |
|---|---|---|---|---|
| Postage stamps | `dp-variable` | 237 | `hvtiPlotR::hv_eda()` | template |
| Trend plots | `dp-trends` | 80 | `hvtiPlotR::hv_trends()` | template |
| Goodness of follow-up, graph | `dp-gfup` | 48 | `hvtiPlotR::hv_followup()` | template |
| Dc.General | `dc-general` | 759 | `hvtiRtables::hv_tbl_summary()` | template |
| Tables, and correlation plots | `dc-tables` | 551 | `hv_tbl_summary()` | template, plus two functions |
| Goodness of follow-up, summary | `dc-gfup` | 389 | `hv_followup()` covers the graph only | template, plus one function |

2,064 jobs of corpus coverage behind six templates and three functions.

### Correlation plots are a `dc-tables` job, not a `dp` graph job

This is the finding that kept the batch inside the existing ledger.

"Correlation plots" has no roadmap row, no taxonomy prefix, and no chapter in
`hvtiGraphics`. The temptation is to read that as a gap and open a `new-prefix`
intake. The corpus says otherwise. The exemplar is
`/descriptive/dc.tables.ods_preoplabs_a1c.sas`, preserved in
`~/Documents/macro.library/CorrTable.sas`, whose header reads "to obtain
pairwise correlations between preop lab values and A1c within A1c groups". Its
computation is one call:

```sas
proc corr data=built nosimple spearman pearson fisher(biasadj=no alpha=.32) plots=matrix;
  ods output SpearmanCorr=corrs FisherSpearmanCorr=corrcis
             PearsonCorr=corrp  FisherPearsonCorr=corrcip;
```

Two artifacts come out of it: a **scatter-plot matrix** (`plots=matrix`) and a
**table of pairwise coefficients with Fisher confidence intervals**. The job is
filed under `/descriptive/` and named `dc.tables.*`. So correlation work is a
variant inside `dc-tables`, recorded there as an `EDIT:` path, and not a
seventh row.

⚠️ `~/Documents/macro.library/CorrTable.sas` is two unrelated programs
concatenated in one file. The first is `%STStable`, an STS observed-versus-
expected table; the correlation program is the second, below it. The filename
describes neither well. Read past the first header before concluding what that
file is.

⚠️ **`pool_collinear_pairs()` in `hvtiRutilities` is not this function.** It
prunes bootstrap selection pools at a 0.99 threshold. It answers "which pair is
so collinear that one must go", not "what is the correlation structure here",
and reusing it for the EDA screen would silently discard everything below the
threshold, which is the part an author is looking at.

### The table engine already exists

`hvtiRtables` 1.0.0 ships `hv_tbl_summary()`, and it is not a generic wrapper:
it is written to the `%summarytable` SAS macro interface the biostats team
already knows. `groups` is the macro's `LIST=`, doing double duty as display
order and section headers; `continuous`, `binary` and `categorical` are `CON1=`,
`CAT1=` and `CAT2=`; `compare` adds the trailing comparison column as
`"pvalue"`, `"smd"`, `"both"`. `R/hv-sas-glossary.R` encodes the compute, shape
and save stages of that lineage explicitly.

`%summarytable` itself descends from Amanda Artis (2020), modifying Rocio
Lopez's `%summtable` (2013), modifying Ryan Lennon's `%summary` (Mayo, 2009).
`dc-general` is therefore a wiring job against a deliberate port, not a new
build.

⚠️ **`corr` in `hvtiRtables` means CORR the group**, Cardiovascular Outcomes,
Registries and Research, and never correlation. `hv-sas-glossary.R` keys every
stage on `corr` versus `jtcvs` as the two manuscript destinations. A grep for
correlation machinery in that package returns nothing but false positives. This
is also why the new functions below are named `hv_correlation_*` in full.

## Ledger changes

The catalog is `inst/extdata/jobs.json` in `ehrlinger/hvtiR`, resolved through
`HVTI_JOBS` or a sibling checkout. Nothing in this repo is the authority, and
editing the copy that used to live here does nothing.

1. `dc-general`, `dc-tables`, `dc-gfup`: `batch` 4 becomes **3**.
2. `dp-variable`, `dp-trends`, `dp-gfup`: unchanged, already `batch` 3.
3. `dc-tables` gains a `note` recording that pairwise correlation is in scope,
   naming the exemplar above.
4. Each row flips `status` to `shipped` as its template lands, not before.

⚠️ **`batch` is an integer, and must stay one.** The obvious spelling of this
change is a new batch `"3a"`, isolating the six rows. It crashes the renderer.
`roadmap_render.py` derives each family's label by sorting the set of batch
values it contains (line 177) and sorts rows on `r["batch"] or 0` (line 196),
so a `plots` family holding both `3` and `"3a"`, which is exactly what moving
three of five `dp` rows produces, raises `TypeError: '<' not supported between
instances of 'str' and 'int'`. Every value in the catalog today is an integer
or `null`, so no string batch has ever been exercised. Batch 5 is a free
integer slot, but it sorts after 4 and would say this work happens later, which
is the opposite of the intent.

Batch 3 therefore carries thirteen rows rather than isolating these six. That
is a real loss of legibility, accepted because a batch is a family-scheduling
unit and the wave table below is what actually orders the work. Three rows
change, and nothing else moves.

Then re-render, from this repo:

```sh
python3 dev/specs/artifacts/roadmap_render.py
```

`check-roadmap-counts.py` enforces agreement in both directions, so a template
on disk with no `shipped` row fails the PR exactly as a `shipped` row with no
template does. Steps 1 to 3 land in one catalog PR before any template work;
step 4 rides with each template's own PR.

Not moved: `dp-procs` and `dp-spaghetti` stay in batch 3 beside their moved
siblings, and `dc-dead`, `lg` and `rg` stay in batch 4. They were not asked
for.

## Sequencing

Three waves. Waves 1 and 2 are template-only work in this repo and depend on
nothing outside it. Wave 3 runs in **parallel** with them rather than after
them, because its blocking work lives in other repositories and its templates
are otherwise identical in shape to wave 2's.

| wave | templates | blocked on |
|---|---|---|
| 1 | `dp-variable`, `dp-trends`, `dp-gfup` | nothing |
| 2 | `dc-general` | nothing |
| 3 | `dc-tables`, `dc-gfup` | the three functions below |

Wave 1 first because it is unblocked and because a facet graph is the thing a
fellow can read on a slide. Wave 2 next because `dc-general` at 759 jobs is the
widest single row in the batch and exercises `hv_tbl_summary()` against a real
template for the first time, which is where interface problems will surface if
there are any.

## The three new functions

Split by artifact type: a plot goes to the plotting package, a table to the
tables package. The correlation job produces one of each, so it costs a
cross-package pair. That is accepted, because the alternative puts a
manuscript-output package in the business of drawing EDA scatter matrices, or
puts confidence-interval statistics in a plotting package.

**These are specced by their owning repositories, not here.** This document
records only the dependency and the shape the templates need.

| function | package | shape |
|---|---|---|
| `hv_correlation_matrix()` | `hvtiPlotR` | scatter-plot matrix, mirroring `plots=matrix`. Returns an `hv_data`-classed object with a `sample_*_data()` companion, per that package's convention and beside `hv_eda()`. |
| `hv_correlation_table()` | `hvtiRtables` | Spearman and Pearson coefficients with Fisher confidence intervals, mirroring `ods output SpearmanCorr` / `FisherSpearmanCorr` / `PearsonCorr` / `FisherPearsonCorr`. Must support stratification: the exemplar computes both overall and within `a1c_grp`. |
| `hv_followup_table()` | `hvtiRtables` | the `dc-gfup` summary companion to `hv_followup()`'s graph. |

Names are spelled out rather than abbreviated to `hv_corr_*` because of the
CORR collision noted above.

## Per-template obligations in this repo

Each of the six templates carries, without exception:

- Its own **file key** in `.lintr`, never a directory key. A directory key
  excludes every linter on that path wholesale and silently.
- Exactly one `^ENDPOINT\s+<- ` line and one `^TYPE\s+<- ` line. `new_job()`
  substitutes both and hard-stops if either is missing, duplicated or moved.
- Its own `format:` block, not inherited from a project `_quarto.yml`.
- `EDIT:` markers on every study-specific line, with comments saying why a
  choice matters rather than only what to type.
- No study identifiers. `test-new-job.R` asserts no template matches
  `/studies/`, a study name, or a built-dataset filename.
- A row in `inst/templates/README.md`.
- A `NEWS.md` entry under `# hvtiRtemplates (unreleased)`, added if absent. No
  `Version:` bump in the template PR itself.
- The catalog row flipped to `shipped`, re-rendered.

Filenames, all qualified, because `dp` and `dc` are wholly-qualified prefixes:

```
inst/templates/40_graphs/dp-variable.qmd
inst/templates/40_graphs/dp-trends.qmd
inst/templates/40_graphs/dp-gfup.qmd
inst/templates/10_descriptive/dc-general.qmd
inst/templates/10_descriptive/dc-tables.qmd
inst/templates/10_descriptive/dc-gfup.qmd
```

⚠️ `10_descriptive/` does not exist yet; this batch creates it. The digits are
assigned, not derived, and 10 is already the assigned decade for `descriptive`.

Jobs scaffold into the **bare** taxonomy folder, `graphs/` and `descriptive/`,
carrying the qualifier as a fourth field: `new_job("dp", "dead_pa", "hz",
qualifier = "trends")` writes `graphs/dead_pa-hz-dp-trends.qmd`.

## The second-exemplar gate

`AGENTS.md` requires two studies to have exercised a shape before a template is
added. Every row here clears it by a wide margin, the smallest being `dp-gfup`
at 48 jobs. Nothing in this batch is gated, and no per-study count needs to be
quoted to establish that.

## Definition of done

Per template, and per `AGENTS.md`:

- `devtools::test()` passes.
- `devtools::check()` is 0 errors, 0 warnings, 0 notes.
- `devtools::document()` run, with `man/` and `NAMESPACE` committed alongside.
- The template renders.
- `check-roadmap-counts.py` passes, which it will not until the catalog row is
  flipped and re-rendered. It is the only one of the three `spec-counts.yaml`
  checks that reads the catalog: `check-spec-counts.py` is hard-scoped to the
  macro-allocation spec and its map, and `check-flow-counts.py` checks the job
  flow diagrams against the taxonomy. Neither is affected by this batch, so a
  failure in either is not a symptom of a missing catalog flip.

⚠️ `/code-review` is run locally before each PR opens, and the PR body says so.
Copilot's review quota is exhausted until October, confirmed 2026-09-03, so
nothing else reads the diff: the ruleset's `copilot_code_review` rule does not
block a merge, and the approval rule cannot be satisfied by its own author.

⚠️ `check-manual.yaml` does not run on `pull_request`. It is push-to-`main`,
release and dispatch only. No template here is expected to touch Rd markup, but
if one does, build the PDF manual locally before merging rather than trusting a
green PR.

## Out of scope

- `dp-procs`, `dp-spaghetti`, `dc-dead`, `lg`, `rg`. Not asked for; batches
  unchanged.
- The `dc-stddiff` standardized-difference member, which the roadmap already
  assigns to `hvtiRutilities`, not here.
- Multi-file templates. `dc-general` and `dc-tables` are single-file jobs, so
  the runner-template gap that blocks `bh` and `hm` does not apply.
- Any `hvti_taxonomy()` change. This batch deliberately needs none.
