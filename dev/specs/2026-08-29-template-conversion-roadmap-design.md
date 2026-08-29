# Template conversion roadmap

**Date:** 2026-08-29
**Status:** implemented 2026-08-29 — the ledger, renderer and both guards are
in place. The roadmap itself is `2026-08-29-template-conversion-roadmap.md`.
**Prompted by:** `bh` reaching implementation with no answer to "and then
what?" — four templates shipped, thirty-eight prefixes unaccounted for, and
no record of which come next or why.

This note is self-contained. It assumes no memory of the session that
produced it.

---

> ⚠️ **This is a design document. §§3–7 describe machinery that does not exist
> yet, and the present tense in them means *will*, not *does*.** The ledger
> (`artifacts/2026-08-29-template-roadmap.json`), the renderer, both CI guards
> and the roadmap document are **planned work**, specified task-by-task with
> their full contents in `2026-08-29-template-conversion-roadmap-plan.md`. The
> only artifact that exists today is
> `artifacts/2026-08-29-job-census-summary.json`, the corpus evidence in §2.
> Nothing in `.github/workflows/` runs a roadmap check yet.

## 1. What this decides

How the remaining taxonomy prefixes become supported R templates: the unit of
work, what orders the queue, where the status lives so it cannot drift, and
how R jobs that never entered the catalogue get folded in.

It decides **no template's contents**. Each family still earns its own design
spec; this note decides only the shape of the queue those specs come out of.

**Scope: 38 prefixes.** Forty-two in `hvti_taxonomy()`, less the four shipped
(`ac`, `hz`, `hp`, `hm`) and `bh` in flight, plus three new prefixes (`rfr`,
`sid`, `vt`), less two demoted to non-template umbrella rows (`rf`, `rfsrc`).

---

## 2. The corpus, measured rather than assumed

Two inventories, both run 2026-08-29, both with their scope stated — the
failure this repository keeps repeating is quoting a count whose scope went
unrecorded.

### 2.1 `~/Documents/template`, by extension

`find ~/Documents/template -name 'tp.*' -type f`, 374 files:

| extension | n | | extension | n |
|---|---|---|---|---|
| `.sas` | 244 | | `.Rnw` | 4 |
| `.R` | 97 | | `.rmd` / `.Rmd` | 4 |
| `.qmd` | 8 | | `.doc` / `.docx` | 6 |
| `.S` | 8 | | other | 3 |

**130 of the 374 are not SAS.** Every prior count in this repository's specs
said "244 templates" and meant `tp.*.sas`. That number was never wrong; its
scope was never written down, and the R corpus went unseen as a result.

Excluding `archive/`, the non-SAS templates land:

| folder | n |
|---|---|
| `graphs/` | 38 |
| `analyses/` | 20 |
| `descriptive/` | 9 |
| `documents/` | 7 |
| **total** | **74** |

⚠️ **The R-native corpus is a plotting corpus.** `dp` alone holds 24 non-SAS
templates. Any intuition that R work concentrated in modelling is wrong.

### 2.2 SAS templates per prefix

Top of the distribution, `tp.*.sas` only: `bd` 24, `hp` 21, `dc` 21, `np` 15,
`lm` 13, `vars` 12, `lp` 12, `ac` 12, `nd` 10, `hs` 10, `bn` 10, `hz` 9.
The tail runs to one: `pm`, `cm`, `cd`, `bq`, `dt`, `mm`, `mp`.

These differ by one or two from `dev/specs/artifacts/2026-08-22-job-flow.json`
(`dc` 19, `lp` 11) because that scan covered 241 jobs to this one's 244. Both
are correct for their own scope; neither is a corpus census of `/studies`.

### 2.3 The gate is not a constraint

`hvtiRutilities::job_census()` over `/studies` (2026-08-27, 2,240,570 files)
found **no taxonomy prefix anywhere at a single study**. The smallest are `bq`
at 2 and `cp`/`pm` at 5. The two-studies gate is open for every prefix, and
nothing in this roadmap waits on a second exemplar.

**That catalogue has now been retrieved** (2026-08-29). It lives on the share
in `census-20260827-064249/` beside `job-census.R` — 961 MB across six files.
Two are copied to `~/Documents/templates/census-20260827/`, deliberately
outside any git repository: `census-GATE.csv` (3.4 MB, the per-prefix
aggregate) and `census-R-slice.csv` (18 MB, the R-side rows). The other
940 MB of per-file rows stay on the share.

A counts-only derivation is committed here as
`dev/specs/artifacts/2026-08-29-job-census-summary.json` — 42 known prefixes,
7 non-prefixes, the top 40 unknowns. **No path, study name or other identifier
appears in it.** `hvtiRtemplates` is a public repository and
`tests/testthat/test-new-job.R` forbids study identifiers; the raw catalogue is
2.24 M study paths and must not be committed here.

⚠️ **The two counts in that file measure different things and are not
interchangeable.** `distinct_studies` counts every extension and is
SAS-dominated — it answers *how widely used is this job type*. `r_studies`
counts R-side extensions only — it answers *how much R precedent exists*. Batch
value reads the first; extraction risk reads the second.

**The lower bound `inst/templates/README.md` acknowledges is now closed.** Its
published R counts read `.qmd` rows only, and it predicted the error direction
was undercounting. Measured across `.R`, `.Rmd`, `.rmd`, `.S`, `.Rnw` and `.r`
as well:

| prefix | README (`.qmd` only) | measured (all R) |
|---|---|---|
| `ac` | 4 | **16** |
| `hz` | 3 | **5** |
| `hp` | 3 | **16** |
| `bh` | 2 | 2 |
| `hm` | 1 | **2** |
| `hs` | 1 | **7** |

⚠️ **A stem replicated across studies inflates `r_studies`, and one prefix is
badly hit.** `ar` reads 395 distinct R studies, but two stems account for 365
of them; its real figure is **89**. Sweeping every prefix used for batch
ordering, `ar` is the only severe case and `dp` the only other affected one
(398 → 323). **Any prefix whose top stem spans more than ~100 studies must be
deflated before its count is quoted.**

⚠️ **84% of R-side rows for taxonomy prefixes are templates, not jobs** —
32,226 of 38,282. `job_census()` drops them on two flags (`is_template`, and
`naming == "template"`); any recount that omits either filter inflates every
prefix. A first attempt at this table did omit them and produced R-study counts
exceeding the all-extension totals, which is how the error was caught. **Any
future recount must reproduce `job-census.R`'s job definition, not invent one.**

Two by-products of the census bear directly on this roadmap:

- an **unknown-prefix bucket of 103,454 rows**, dominated by recurring non-job
  names (`binder` 1,017 studies, `built` 975, `stat_refs` 957). That bucket is
  where a `sid`- or `vt`-class prefix surfaces, so §6's new-prefix discovery has
  a data source rather than only recollection.

  ⚠️ **A note in the vault records this as 103,461, and that figure is wrong by
  exactly 7.** `census-GATE.csv` classifies every row as `known` (42),
  `non_prefix` (7) or `unknown` (103,454); the larger number counted the
  non-prefixes as unknowns. **103,454 is the unknown bucket.**
- a **misfiled false-positive class, shipped deliberately** — every R job under
  `analyses/R_hazard/` reports misfiled, because the taxonomy files `ac`/`hz`
  under `distributions/` while `hvtiRtemplates` places R jobs under `analyses/`.
  Both are right by their own rules. See §3.4.

---

## 3. Decisions

### 3.1 Unit — one template per prefix

Not one per SAS file. `bd` would otherwise need 24 ordinal slots and 24
reviews for what is one job type with variants. Variants become `EDIT:`
branches inside the single file, which is what the markers are for.

A prefix may later split if its exemplars genuinely disagree on shape — the
way `hz`'s three exemplars disagreed on `theta` seeding — but a split is a
finding recorded in that family's design spec, never the starting assumption.

### 3.2 Ordering — family batching

One design spec per structural family, then one implementation PR per prefix
off it. The families are structurally parallel by construction: `bl`/`bc`/`bn`/
`bq`/`br` are `bh` with a different model call; `mp`/`lp`/`np`/`gp`/`rp` are
`hp` pointed at a different upstream. The spec is the expensive artifact, and
batching amortises it across four to nine prefixes at a time.

### 3.3 Form — generated from a ledger

`dev/specs/artifacts/2026-08-29-template-roadmap.json` is the map. The roadmap
document's tables are generated from it and CI guards the agreement.

This is the pattern `2026-08-14-macro-allocation.json` plus
`check-spec-counts.py` already established here, adopted for the same reason:
that spec's hand-synced tables drifted three times in one day, caught by a
reviewer rather than by CI. A 38-row status table maintained over months is a
strictly worse drift candidate than the table that already drifted.

### 3.4 The random-forest family splits on outcome

The existing rows cannot be templated as they stand. Three contradictions:

| row | description | problem |
|---|---|---|
| `rf` | "random forest and randomForestSRC models" | same set as `rfsrc` |
| `rfsrc` | "randomForestSRC survival, regression and classification models" | same set as `rf` |
| `rfc` | "random forest classification **reporting**" | taxonomy says `analyses/`; library files it in `graphs/` |
| `rfs` | "random forest survival analysis **reporting**" | taxonomy says `analyses/`; library files it in `documents/` |

Three axes are tangled: package (`rf` vs `rfsrc`), outcome type (`rfc`/`rfs`),
and fit-versus-report. The prefix is the filename and the filename is the
ledger key, so this cannot be deferred past naming the first RF template.

⚠️ **The folder half of that is not an RF problem.** The 2026-08-27 census hit
the same contradiction corpus-wide and recorded it as deferred: the taxonomy
files `ac`/`hz` under `distributions/`, `hvtiRtemplates` places R jobs under
`analyses/`, and every R job under `analyses/R_hazard/` reports misfiled as a
result. `rfc`/`rfs` are one instance of a systemic open question — either the
taxonomy learns where R jobs live, or the placement rule splits. Settling it
belongs in its own spec, not inside a family design, and the ML batch should
not be blocked waiting on it.

**Resolution — outcome axis**, matching how `bh`/`bl`/`bc`/`bn`/`bq`/`br` and
`pm`/`rm`/`cm` already split:

| prefix | | status |
|---|---|---|
| `rfs` | random forest, survival outcome | existing |
| `rfc` | random forest, classification outcome | existing |
| `rfr` | random forest, regression outcome | **new** |
| `sid` | unsupervised RF clustering (sidClustering) | **new** |
| `vt` | virtual twins | **new** |
| `nb` | boosting notebooks (Boostmtree, BoostMLR) | existing; boosting, not forest |
| `rf`, `rfsrc` | umbrella rows | **demoted, not templated** |

⚠️ **This renames a convention 131 studies already use, and that cost is
accepted rather than absent.** The census measures `rfsrc` at 131 studies and
2,295 jobs — more than `rf` (47), `rfs` (25) and `rfc` (19) combined, twice
over — and on the R side at 98 exemplar studies against `rf` 42, `rfc` 12,
`rfs` 10. The corpus is organised on the package axis because `rfsrc` is the
package people use.

The decision stands on two grounds. First, the existing jobs already carry the
outcome in field two — `tp.rfsrc.survival.R`, `tp.rfsrc.regression.R`,
`tp.rfsrc.classification.R` — so the outcome axis is a **rename of a
distinction already being drawn**, not a new one imposed. Second, one axis per
family is what `bh`/`bl`/`bc`/`bn`/`bq`/`br` and `pm`/`rm`/`cm` already do, and
carrying two axes in one family is the defect being fixed.

**The ML family design spec owns the migration story** — what a study that
writes `rfsrc.survival` today is told to write, and whether `rfsrc` survives as
an alias. It is not resolved here, and it must not be discovered at naming time.

`sid` is not greenfield: `tp.rf.sidclustering.tuning.R` is already in the
library, and the census counts `rf` at 42 R exemplar studies. The `rfc`/`rfs` folder contradiction is left to the ML family design
spec, which is where the evidence for it belongs.

⚠️ The taxonomy lives in **`hvtiRutilities`**, so adding `rfr`/`sid`/`vt` and
demoting `rf`/`rfsrc` is a cross-repo PR, and it blocks the ML batch.

### 3.5 Cross-cutting workflows get an overlay, not a batch

Some capability spans families. Propensity score matching is the clearest
case — it is not a prefix and never was:

| step | prefix | folder | evidence |
|---|---|---|---|
| develop the score | `lm` | `analyses/` | `tp.lm.logistic_propensity_score.sas` + 4 variants |
| **perform the matching** | `bd` | `datasets/` | `tp.bd.opt_match.sas`, `tp.bd.gmatch_greedy_mayo.sas` |
| check covariate balance | `lp`, `rp` | `graphs/` | `tp.lp.propen.cov_balance.R`, `tp.rp.blnc_scr.cov_balance.R` |
| matched descriptives | `dc` | `descriptive/` | `tp.dc.match.outcomes_paired.sas` |
| outcome, count | `pm` | `analyses/` | `tp.pm.count.balncing_score.sas` |
| outcome, continuous | `rm` | `analyses/` | `tp.rm.continuous.balncing_score.sas` |
| outcome, time-to-event | `cm` | `analyses/` | `tp.cm.CoxPH-evnts-propensity-IPTW-mtch-CoxPH.sas` |
| bootstrap on matched | `bl` | `analyses/` | `tp.bl.median.cost.matched.boot_ci_anes.sas` |
| matched survival plots | `hp` | `graphs/` | `tp.hp.dead.matching_weight.sas` |

Eight prefixes, four folders, five different family batches. Under family
batching alone, a study could not run propensity matching end to end until
nearly the last batch, and nobody would notice until then.

**So the ledger carries a `workflows` array per prefix, and the roadmap
renders a second view by workflow.** Batching stays by family — the design
amortisation is real and worth keeping — but a workflow sitting one prefix
short of complete becomes visible rather than discovered late.

Workflow batching was rejected as the default: it would drag `bd` forward past
its `hvtiRdatabuild` blocker (§7) and abandon the amortisation for a capability
no study has asked for on a date.

⚠️ **`06.01-hp.qmd` is already shipped and may not cover the matched case.**
It was extracted from three unmatched exemplars; the library holds two matched
`hp` jobs. This is why the ledger needs a `revisit` status: shipped is not the
same as complete, and there is currently no way to say so.

---

## 4. The ledger

`dev/specs/artifacts/2026-08-29-template-roadmap.json`. One record per prefix:

```json
{ "prefix": "hs", "name": "Hazard setup", "folder": "analyses",
  "family": "hazard-chain", "kind": "job", "status": "queued",
  "ordinal": null, "batch": 1,
  "sas_templates": 10, "r_templates": 0, "r_exemplars": 1,
  "upstream": ["hm"], "downstream": ["hp"],
  "workflows": ["hazard-chain"],
  "blocked_on": null, "spec": null,
  "note": "closes the hazard chain end to end" }
```

| field | meaning |
|---|---|
| `kind` | `job` for a template that scaffolds one job; `meta` for one that aggregates a set. `ar` is the only `meta` today |
| `status` | `shipped` · `revisit` · `in-flight` · `queued` · `intake` · `out-of-scope` |
| `batch` | integer; **provisional past batch 2** and stated as such |
| `sas_templates` / `r_templates` | counts from §2, scope recorded in the file header |
| `r_exemplars` | studies with an **R** job. **Measured for all 42 prefixes** (§2.3), seeded from `2026-08-29-job-census-summary.json`'s `r_studies`. A genuine `0` (nine prefixes have one) must be distinguishable from "not measured", so an unmeasured prefix serialises as `null`, never `0` |
| `sas_breadth` | `distinct_studies` from the same file — all extensions, SAS-dominated. Measures batch **value**, where `r_exemplars` measures extraction **risk**. Never conflate them |
| `upstream` / `downstream` | from `2026-08-22-job-flow.json`'s 13 cross-job edges |
| `blocked_on` | a named upstream, e.g. `hvtiRdatabuild` or `hvtiRutilities#taxonomy` |

A second top-level array holds intake records for off-catalogue R jobs (§6).

`dev/specs/artifacts/` is `.Rbuildignore`d, so none of this reaches
`R CMD check`.

---

## 5. Guards

Split by language, each guard placed where what it needs already exists.

⚠️ **Neither guard exists yet, and `spec-counts.yaml` does not call one.**
Both are specified in the plan, Tasks 1–3.

**Python — `check-roadmap-counts.py`, to be run by `spec-counts.yaml`.** Needs
no R:

1. `status == "shipped"` **iff** `inst/templates/<folder>/<ordinal>-<prefix>.qmd`
   exists. Both directions — a ledger claiming a template that is absent fails,
   and so does a template no ledger row claims.
2. Every `ordinal` unique, zero-padded to `NN.MM`, with `NN` matching its
   folder's number.
3. The roadmap document's generated tables byte-match a fresh render.

**testthat — `tests/testthat/test-roadmap.R`.** Needs the taxonomy, which
needs R:

4. Ledger prefixes ≡ `hvti_taxonomy()` prefixes, both directions. Adding a
   prefix upstream fails here until the roadmap accounts for it.

⚠️ Guard 4 must `skip_if_not(file.exists(...))`: `dev/specs/` is
`.Rbuildignore`d, so the ledger is absent from a built package and an
unguarded test would fail every `R CMD check` on the tarball.

---

## 6. Intake — the off-catalogue R jobs

Three sources, in this order.

**Source 0, the existing census catalogue — ✅ done 2026-08-29.** Retrieved,
derived and committed as `2026-08-29-job-census-summary.json`; `r_exemplars`
and `sas_breadth` are measured for all 42 prefixes (§2.3). The 103,454-row
unknown-prefix bucket is carried in the same file, top 40 by study count, as
the discovery surface for new prefixes.

**Source 1, the library, runnable today.** The 74 non-archive non-SAS
templates from §2.1. Local, no mount required. This is the larger and cheaper
source and it was invisible until this note.

**Source 2, a widened `/studies` sweep, last.** Re-run `job_census()` extended
beyond `.qmd` to `.R` and `.Rmd`, for R jobs that never returned to the library.
This is the only source that closes the acknowledged lower bound on
`r_exemplars`, but it is also the most expensive and the least urgent — sources
0 and 1 between them cover every prefix well enough to order batches. Blocked on
server access; blocks neither source 0 nor source 1.

Each intake record gets one of four verdicts:

| verdict | consequence |
|---|---|
| `exemplar` | attaches to an existing prefix; raises its `r_exemplars` |
| `new-prefix` | blocks on an `hvti_taxonomy()` PR in `hvtiRutilities` before it can be named |
| `supersedes-sas` | that prefix converts by lift-and-generalise; the SAS template is reference, not source |
| `not-template` | recorded with its reason and closed. **Not silently dropped** — an absent row reads as "never considered" |

Non-conforming names in the library are the `new-prefix` candidates:
`tp.CONSORTdiagram`, `tp.complexUpset`, `tp.BRIER_multiphasehazard.R`,
`tp.ggpair_plots_histograms.R`, `tp.report_metadata.yml`.

---

## 7. Sequencing

**Batch 0** — `bh`, in flight on `feat/8-bh-template`.

**Batch 1** — `hs`. One template, and it closes `ac → hz → hm → hs → hp`: the
first `(endpoint, type)` set in the corpus runnable entirely in R with no SAS
fallback. Highest payoff per unit of work in the whole roadmap.

**Batch 2** — bootstrap: `bl`, `bc`, `bn`, `bq`, `br`, off `bh`'s design while
its reasoning is still warm.

⚠️ **Batch 2 has almost no R precedent, and that is a design risk, not a
detail.** Measured R exemplar studies: `bl` 1, `br` 1, and **`bn`, `bc` and
`bq` at zero**. `bh` itself has 2. So five of six bootstrap templates will be
extracted from SAS alone, generalised through one R exemplar's shape. The
bootstrap family design spec must state which choices are `bh`'s and which are
general — that distinction has no second R exemplar to check it against, which
is the exact failure the two-studies gate was written to prevent, arriving by a
different route.

**Batches 3 and later are provisional**, recorded in the ledger's `batch`
field and stated as provisional wherever they are rendered. The census now
gives that order evidence rather than intuition:

| family | breadth (studies) | R exemplars | reading |
|---|---|---|---|
| plots | `lp` 636, `dp` 628, `np` 248 | `dp` 398, `lp` 186, `np` 45 | widest R precedent in the corpus; cheapest to extract |
| descriptive | **`dc` 1010**, `lg` 367, `rg` 45 | `dc` 69, `lg` 0, `rg` 0 | `dc` is the 2nd most used prefix and has **no blocker** |
| models | `lm` 621, `rm` 174, `nm` 122 | `lm` 10, `rm` 8, `nm` 1 | wide use, thin R precedent |
| machine learning | `rfsrc` 131, `rf` 47 | `rfsrc` 98, `rf` 42 | R-native; needs the taxonomy PR first |
| distributions | `nd` 244, `cd` 202 | `cd` 6, `nd` 3 | narrow |
| datasets | **`bd` 1134**, `vars` 959, `dt` 512 | `bd` 15, `vars` 2, `dt` 0 | widest use in the corpus, blocked |

Current provisional order: plots (9) → descriptive (3) → machine learning (6) →
models (8) → distributions (2) → datasets (3) → `ar` (1). Descriptive moves
ahead of models on `dc`'s breadth and its absent blocker; plots leads on having
the only substantial R precedent outside the shipped set.

Two constraints on that order are firm rather than provisional:

- **Datasets last.** `bd`, `vars` and `dt` scaffold jobs that call
  **`hvtiRdatabuild`**, which is under active development. Their templates
  cannot be designed against an unsettled API. `blocked_on: hvtiRdatabuild`.
- **`ar` is a `kind: job` template and need not be last.** It was scheduled
  terminal on the assumption that it assembled a whole study; the corpus says
  otherwise (see below). The genuinely terminal unit is the study-level
  assembly, which has no prefix yet.

  ⚠️ **CORRECTED 2026-08-29, and the earlier claim must not be reinstated.**
  An earlier draft of this section read `ar` at "395 R exemplar studies, second
  only to `dp`'s 398 — more R precedent than every shipped template combined",
  and used that to argue its last-place slot was costly. **That number is
  inflated roughly fourfold and the argument built on it was wrong.**

  Two stems, `ar.a1c.hdeath` and `ar.a1c.los_icu`, each appear in **365
  studies**, with 726 of their rows in `graphs/`. That is one analysis
  replicated across the corpus, not 365 studies doing `ar` work. Excluding
  those two stems, `ar` has **89** distinct R studies. A sweep for the same
  signature across every prefix used to order batches found `ar` is the only
  badly affected one — `dp` deflates 398 → 323, and `lp`, `rfsrc`, `dc`, `np`,
  `rf`, `nb`, `ac`, `hp` and `bd` are unchanged — so §7's ordering stands.

  ⚠️ **`ar` is also not what this roadmap first assumed it was.** Its stems are
  `ar.rfsrc.survival`, `ar.rfs.death`, `ar.rfc.tbilirubin_renal`,
  `ar.longitudinal.BoostMTree`, `ar.cluster.training` — named
  `ar.<method>.<endpoint>`. Its library templates are
  `tp.ar.analysis_report.doc`, `tp.ar.markdown_template.docx`,
  `tp.ar.rfs.death.Rnw` and `tp.ar.quarto_template.qmd`. **`ar` is the write-up
  of ONE analysis**, pairing with a single analysis prefix — overwhelmingly an
  ML one, which is where the R-native work is. It is a `kind: job` template,
  not a `kind: meta` one, and it has no dependency on the rest of the roadmap.

  **The study-level assembly is therefore a different artifact that the
  taxonomy does not yet name.** A bookdown report combining the templates a
  study actually ran, for handoff to researchers, aggregates a set the way this
  note originally mis-attributed to `ar`. It is a `new-prefix` intake item
  (§6), it blocks on an `hvti_taxonomy()` PR, and **it is the only genuinely
  terminal unit in the roadmap** — `ar` itself is not.

Descriptive and models are cleared to move earlier if ledger evidence favours
it. Nothing external forces the order: see §8.

---

## 8. Risks, and one that was withdrawn

⚠️ **The "SAS licence expires 2026-09-29" deadline does not apply, and should
not be reinstated from an older note.** That date appears across `dev/specs/`,
`README.md` and `NEWS.md`, twice as a load-bearing forcing function. The
maintainer confirmed on 2026-08-29 that the licence in fact runs to
**2027-09-29**, and that compiled data stays readable well beyond it. The
correction is being applied separately, in
[#44](https://github.com/ehrlinger/hvtiRtemplates/pull/44); this roadmap does
not depend on the date either way. Every template shipped so far was extracted
by **reading** SAS source, never by running it, and this roadmap plans no
reference runs.

Remaining risks:

| risk | mitigation |
|---|---|
| The ML batch blocks on a cross-repo taxonomy PR | `blocked_on` names it; raise the PR before batch planning, not during |
| Datasets blocks on `hvtiRdatabuild`'s API | scheduled last; `blocked_on` records why, so "last" is not mistaken for "lowest value" |
| `r_exemplars` is a lower bound | stated in the ledger header and every rendering; intake sources 0 and 2 narrow it |
| The 2026-08-27 catalogue is unreachable from a workstation | intake source 0 retrieves or re-runs it; until then 36 prefixes carry `null`, and batch order past batch 2 stays provisional |
| A shipped template proves incomplete | `revisit` status exists for exactly this; `hp` is the first candidate |

---

## 9. Out of scope

- 1:1 conversion of 244 SAS files. One template per prefix (§3.1).
- The SAS macro corpus. It lives in `~/Documents/macro.library` and was
  removed from this repository on 2026-08-14.
- Any template's contents. Each family's design spec decides those.
- Fixing the stale licence date in nine other specs. Tracked separately.

---

## 10. Rejected

**One template per SAS file.** 244 units, 24 ordinal slots for `bd` alone, and
a review burden with no matching gain — the variants differ in ways `EDIT:`
markers already express.

**GitHub issues as the roadmap.** Status could not drift, but the reasoning
would leave `dev/specs/`, which is where every template decision so far has
been argued and found again months later.

**A hand-written markdown status table.** The precedent is against it: the
macro-allocation spec's hand-synced tables drifted three times in a single day.

**Workflow batching as the default.** Delivers end-to-end capability sooner,
but drags `bd` past its blocker and discards the family amortisation. Kept as
an overlay instead (§3.5).

**Chain-completion ordering.** It would have caught the propensity gap, which
family batching did not — but at the cost of re-deriving a shared design once
per chain. The workflow overlay recovers what it was good for.
