# R_hazard — job templates for the SAS-to-R hazard migration

> **Migrated 2026-08-18** from `/Volumes/qhsstudies/cardiac/valves/aortic/replacement/pericardial/lv_function/survival/analyses/R_hazard/docs/specs/2026-08-11-r-hazard-job-templates-design.md`.
> Cross-references to the other migrated documents have been repointed to their
> paths in this repository; the text is otherwise unchanged. Study folders on the
> share do not host git repositories, so the design record lives with the package
> that owns the migration programme. `specs/artifacts/README.md` records what
> moved and from where.

**Date:** 2026-08-11
**Status:** Approved design
**Study:** `/studies/cardiac/valves/aortic/replacement/pericardial/lv_function/survival`
**Predecessor:** `specs/2026-08-10-avr-lvf-temporalhazard-parity-design.md`

---

## 1. Purpose, and the split it rests on

Two activities have been sharing one directory, and they apply to different
sets of jobs.

**Parity** compares R against the SAS `.lst`. Its purpose is **metering
TemporalHazard**: acceptance testing, and catching the modifications it needs.
Four such documents produced seven merged upstream PRs in two days.

**The analysis** reproduces what a SAS job does, in R, for real. No `.lst`, no
tolerance policy, no comparison. This is what runs when the SAS licence expires
on 2026-09-29.

The distinction is **not lifespan**. Parity is not a phase that ends when the
package is trusted:

- It runs **often** between now and that trust, on every job type as it is
  first ported.
- It is **revisited** whenever a new defect surfaces, or a new TemporalHazard
  release needs re-qualifying against a known-good answer.
- It is **inapplicable** to new analysis, which has no SAS counterpart to
  compare against, and which is most of what this migration exists to enable.

So the real split is **scope**: parity applies only where a SAS answer exists,
the analysis applies always. Every parity document has an analysis underneath
it; not every analysis has a parity document above it.

| Directory | Purpose | Applies to |
|-----------|---------|------------|
| `analyses/R_parity/` | compare R against SAS; meter TemporalHazard | jobs with a stored SAS answer |
| `analyses/R_hazard/` | do the analysis in R | every job, old or new |

`R_analysis/` is renamed to `R_parity/`, which is what it always was.

Two consequences follow, and both are load-bearing later:

1. The dependency direction in §3.1 is **required**, not merely tidy. If
   parity were the temporary layer it would not matter much which way the
   arrow pointed. Because parity is retained and re-run, the analysis must be
   the thing that stands alone.
2. The parity harness is **kept**, so it is worth packaging (§7). A harness
   you return to is a different asset from one you throw away.

## 2. Scale, and why templates

Hazard-family SAS jobs in this study alone:

| Prefix | Location | Jobs | Job type |
|--------|----------|------|----------|
| `hp` | `graphs/` | 25 | hazard prediction / figures |
| `bh` | `analyses/` | 22 | bagging |
| `hz` | `distributions/` | 14 | parametric hazard fit |
| `hm` | `analyses/` | 13 | multivariable model |
| `hs` | `graphs/` | 9 | matched US Life Table reference survival |
| `ac` | `distributions/` | 6 | actuarial life table |

**89 jobs, six shapes.** Roughly fifteen jobs per shape is the argument for
templates over bespoke files.

Approximately fourteen further prefixes exist (`lm`, `lg`, `rm`, `mm`, `bl`,
`dc`, `mp`, `np`, `rp`, `lp`, `nd`, `cd`, `br`, `gm`) covering logistic,
regression, mixed-model and descriptive work. Those are **out of scope here**
and are expected to become sibling `R_<family>` directories later. See §7.

## 3. Layout

```
analyses/
├── R_hazard/                    # PERMANENT: the analysis in R
│   ├── _quarto.yml
│   ├── R/
│   │   ├── paths.R              # runtime path resolution
│   │   └── read_built.R         # data contract + cohort gate
│   ├── templates/
│   │   ├── ac.template.qmd
│   │   ├── hz.template.qmd
│   │   ├── hp.template.qmd
│   │   ├── bh.template.qmd
│   │   ├── hm.template.qmd
│   │   └── hs.template.qmd     # see §4.2 -- capability gap
│   ├── docs/specs/              # design docs; this one now in hvtiRtemplates
│   ├── 01.ac.dead_JR.qmd        # instantiated jobs
│   ├── 02.hz.dead_JR.qmd
│   └── _output/
└── R_parity/                    # TEMPORARY: metering TemporalHazard
    ├── R/parity.R               # tolerance policy, .lst access
    └── qmd/01-ac-dead.qmd …     # the existing four, unchanged
```

### 3.1 Dependency direction

**`R_parity` sources from `R_hazard`. Never the reverse.**

Validation depends on production, as tests depend on a package. `paths.R` and
`read_built.R` describe *this study's data* and are needed by both, so they
live with the permanent thing. `parity.R` is a tolerance policy and a `.lst`
parser wrapper; nothing in production needs either, so it stays in `R_parity`.

This is deliberate insurance. When a sibling family directory arrives it will
need the same data contract, and the question becomes "promote `read_built.R`
to a study-level shared location" — a move of one file with known consumers,
not an untangling.

### 3.2 Naming

`NN.<prefix>.<sas-basename>.qmd`, mirroring the SAS file so the correspondence
is mechanical and greppable:

| SAS | R |
|-----|---|
| `distributions/ac.dead_JR.sas` | `01.ac.dead_JR.qmd` |
| `distributions/hz.dead_JR.sas` | `02.hz.dead_JR.qmd` |
| `graphs/hp.dead_JR.sas` | `03.hp.dead_JR.qmd` |
| `analyses/bh.dead_s3_JR.sas` | `04.bh.dead_s3_JR.qmd` |
| `analyses/hm.dead_s3_JR.sas` | `05.hm.dead_s3_JR.qmd` |
| `graphs/hs.uslife_estimates.*.sas` | `06.hs.uslife_estimates.*.qmd` |

Two-digit prefix with a leading zero, matching `R_parity`'s existing scheme and
sorting correctly past nine jobs of one type.

The number encodes **pipeline dependency order**, which is also Rajeswaran's
job flow: `ac` (non-parametric baseline) → `hz` (unadjusted fit) → `hp`
(figures from that fit) → `bh` (which variables are reliable) → `hm` (final
model) → `hs` (matched-population reference survival). A job's number tells you what
must already have run.

## 4. Templates are working documents, not blanks

Each `*.template.qmd` renders as-is against this study, with study-specific
values marked by a `# EDIT:` comment. Copy, rename, edit the marked lines.

A blank skeleton would throw away the expensive part. Everything below was
established by a failure during the parity work, and belongs in the template so
the next study does not re-derive it:

| Knowledge | Template |
|-----------|----------|
| `ic_dead` is the interval-censoring **flag**; `il_dead` is the lower bound and is 0 for every row. `status = idead` marks those records right-censored — the opposite claim. | `hz`, `hm` |
| `status` coding: 1 event, 0 right, 2 interval, −1 left. SAS counts an interval-censored record as an **event**. | `hz`, `hm` |
| `theta` carries **all** parameters including fixed ones, not just the free ones. | `hz`, `hm` |
| SAS logs all six shape parameters; R logs only the scale ones. Compare on the natural scale. | `hz`, `hm` |
| `CLEVEL` default is **0.68268948** (±1 SD), not 0.95. | `hp`, `hs` |
| Survival CLs need `conf.type = "logit"`; `predict.hazard()` defaults to `"log-log"`. | `hp` |
| `hzr_bootstrap()` needs the **formula** interface; the vector interface silently returns identical replicates (fixed upstream in #113, but the constraint is worth knowing). | `bh` |
| `numDeriv` is a `Suggests`; without it, interval- or left-censored multiphase fits silently produce no standard errors. | all |
| Under a near-singular Hessian, marginal parameter SEs are unstable while the fitted curve is not. | `hz`, `hm` |

### 4.1 Long jobs run outside the render

`bh` and `hm` ship a companion runner script that writes an `.rds`; the `.qmd`
reads it. Established by `run-bagging.R`: the bagging job takes ~10 minutes,
and a chunk that blocks that long makes the report unusable to iterate on. It
also keeps a long write off the render path, which matters on a share that has
dropped writes twice.

Runners carry a **did-it-actually-run** assertion. The first bagging run
reported 500 successes, 0 failures, no warning, and 500 identical replicates.
A free parameter must vary across resamples, and the runner now stops if it
does not.

### 4.2 `hs` is a capability gap, not a template

The nine `hs` jobs call `%usmatchd`, a CCF macro that generates **age, race and
sex-matched US Life Table survival** for each patient and averages it overall
and within subgroups. It is the dashed reference line in the paper's Figure 1,
described in its Methods as *"Reference population survival estimates were
generated from equations for the US Life Tables for each patient according to
age, race, and sex."*

This is not a TemporalHazard function with a different name. It belongs to a
different package, proposed as **`hvtiRlifetables`** (§4.3).

The `hs` template is therefore **specified but not authored** in this pass. The
other five templates are unaffected — `hs` is a reference overlay, and nothing
else depends on it.

**What is already known, from the jobs and their stored output.** The macro's
full calling contract is documented in the job source itself, so no access to
`!MACROS/usmatchd.sas` is needed to state the interface:

| Argument | Meaning |
|----------|---------|
| `table` | `'OVERALL'` / `'SEX'` / `'RACE'` / `'SEXRACE'` |
| `id`, `age`, `male`, `other` | per-patient inputs; `other = 1` means non-white |
| `scale`, `max`, `ninc` | output grid: units, horizon, number of increments |
| `individl` | `1` = per-patient curves, `0` = mean curve |
| out: `TIME`, `SMATCHED`, `HMATCHED` | matched survivorship and hazard |

`estimates/uslife.sas7bdat` reads cleanly with `haven`: **460,399 rows =
3,049 patients × 151 grid points**, `TIME` spanning 0 to 10 years. It carries
`AGE` (at entry), `AGE_YR` (advancing with `TIME`, confirming the age-advancing
integration), `AGESURV` (stratum survival up to entry age), `SMATCHED` and
`HMATCHED`. Thirty-one such `uslife*.sas7bdat` files exist in `estimates/`,
covering the overall curve and every subgroup the nine jobs stratify on.

**This makes `hs` parity testable without SAS and without the macro.** The
answers are on disk, per patient, on a known grid. That is a stronger position
than any other stage started from.

### 4.3 `hvtiRlifetables`

Proposed as a separate package rather than a module, because it is primarily
**data**, and data versions on its own cadence: a new NCHS release changes the
tables without changing a line of code, and a reproduction of a 2008 paper must
be able to pin the vintage that paper used.

R already supplies most of the machinery. `survival` ships `survexp.usr`, a
rate table dimensioned age × sex × race × year (1940-2020), and `survexp()`
performs the age-advancing integration. A one-point probe against the stored
SAS output is encouraging and inexact: for the first patient (white male, entry
age 70.04), SAS reports `HMATCHED = 0.037274` at `TIME = 0`, and `survexp.usr`
for that age bin gives 0.037049 in 1988 and 0.037713 in 1987. Same object, late
-1980s vintage, within a percent. One patient at one time point on a coarse age
bin is a smell test, not a validation.

Two structural differences are real and must be settled, not assumed away:

1. **Race levels.** `survexp.usr` offers white/**black**. CCF codes
   white/**other**, where other is any non-white. These are different
   populations, and the difference is not a rounding error.
2. **Calendar year.** `survexp()` advances calendar year along with age.
   `%usmatchd` takes no date argument at all, so it holds the year fixed at its
   table's vintage. Reproducing the macro means fixing the year dimension;
   doing the better thing means not fixing it. The package should support both
   and make the choice explicit at the call site.

Scope, if it is built:

- Rate-table data keyed by **vintage**, so a parity run and a new analysis can
  ask for different tables by name and have that recorded.
- One entry point with the `%usmatchd` contract above, returning a tidy frame
  with `SMATCHED` / `HMATCHED` on the requested grid.
- Validation against the 31 stored `uslife*.sas7bdat` files as fixtures.

Dependency direction: `hvtiRlifetables` may depend on `survival`; nothing in
`TemporalHazard` depends on it. `hs` templates depend on both.

**This design does not authorise building it.** It is scoped here so that the
five authored templates are not blocked, and so the `hs` gap has a named owner
rather than an open question. `hvtiRlifetables` needs its own design cycle.

## 5. What the templates do NOT contain

No `.lst` parsing, no `compare_parity()`, no tolerance policy, no published-value
cross-checks. Those are parity concerns and live in `R_parity`.

A template's job is to produce the analysis result — life table, fit, nomogram,
figures, selection frequencies, calibration — in a form a clinician or
statistician reads. Whether it matches SAS is a separate question asked in a
separate place.

## 6. Success criteria

1. Each of the **five** authored templates renders against this study without
   edits. (`hs` is specified but not authored — see §4.2.)
2. `R_parity` still renders after the rename and the helper move.
3. A new job of any of the six types is a copy, a rename, and edits confined to
   lines marked `# EDIT:`.
4. No file is duplicated between `R_hazard` and `R_parity`.

## 7. Scaling — recorded, not built

Two pressures are known and deliberately deferred (YAGNI), with the decision
points named so they are not rediscovered:

**The other fourteen prefixes.** Expected to become sibling `R_<family>`
directories (`R_logistic`, `R_descriptive`, …). The trigger to act is the first
one being needed. At that point `read_built.R` is wanted by two families in one
study and should move to a study-level shared location. §3.1 is arranged so
that is a file move.

**Templates as a package.** The natural home is
`hvtiRutilities/inst/rmarkdown/templates/`, which is R's standard mechanism and
surfaces in RStudio's New Document dialog and via `rmarkdown::draft()`. A
separate `hvtiRtemplates` is **not** indicated: unlike `hvtiRlifetables` (§4.3),
templates carry no data and version on the same cadence as the helpers they
call, so splitting them buys a second DESCRIPTION, a second CI, and a second
thing in every `renv.lock` for nothing.

Not now, for a reason that will expire: **no template exists yet**. Which
helpers deserve packaging is discovered by writing the five and seeing what
repeats; guessing first builds an API around one study's accidents. Templates
are also working documents under active edit for the duration of the migration,
and a template inside a package adds an install-and-reload to every change.

The trigger is narrower than the one below: **the first time a template is
copied to another study and edited there.** That is the fork moment, and a
forked template fails the same way a forked parity harness does, with both
sides passing while they drift.

**Packaging the helpers.** `paths.R` and `parity.R` know nothing about this study and would
serve every study in the migration. The argument for promoting them to
`hvtiRutilities` is the same one that put the `.lst` parsers in
`TemporalHazard/inst/`: a copied harness forks, and a forked parity harness
shows up as **both sides passing**. `parity.R` has been hardened by four
distinct defects it caught; that hardening should not be re-derived per study.
The trigger is the second study needing it. Dependency direction is fixed:
`hvtiRutilities` may depend on `TemporalHazard` (which is on CRAN), never the
reverse.

## 8. Out of scope

- The fourteen non-hazard prefixes.
- Authoring the `hs` template, which waits on `hvtiRlifetables` (§4.2, §4.3).
- **Building `hvtiRlifetables`.** Scoped in §4.3, designed elsewhere.
- Promoting any helper to a package.
- Changing `R_parity`'s internal file naming (`01-ac-dead.qmd` stays; it works
  and the vault references it).
- Reproducing SAS's plot styling; figures are `hvtiPlotR` house style.
- Any modification to the SAS tree.
