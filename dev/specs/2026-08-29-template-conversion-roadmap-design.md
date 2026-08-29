# Template conversion roadmap

**Date:** 2026-08-29
**Status:** designed, not started
**Prompted by:** `bh` reaching implementation with no answer to "and then
what?" — four templates shipped, thirty-eight prefixes unaccounted for, and
no record of which come next or why.

This note is self-contained. It assumes no memory of the session that
produced it.

---

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

`sid` is not greenfield: `tp.rf.sidclustering.tuning.R` is already in the
library. The `rfc`/`rfs` folder contradiction is left to the ML family design
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
| `r_exemplars` | studies with an R job, from `job_census()`. **A lower bound** — the census reads `.qmd` only |
| `upstream` / `downstream` | from `2026-08-22-job-flow.json`'s 13 cross-job edges |
| `blocked_on` | a named upstream, e.g. `hvtiRdatabuild` or `hvtiRutilities#taxonomy` |

A second top-level array holds intake records for off-catalogue R jobs (§6).

`dev/specs/artifacts/` is `.Rbuildignore`d, so none of this reaches
`R CMD check`.

---

## 5. Guards

Split by language, each guard placed where what it needs already exists.

**Python — `check-roadmap-counts.py`, run by `spec-counts.yaml`.** Needs no R:

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

Two sources, in this order.

**Source 1, the library, runnable today.** The 74 non-archive non-SAS
templates from §2.1. Local, no mount required. This is the larger and cheaper
source and it was invisible until this note.

**Source 2, `/studies`, a second pass.** Rerun `job_census()` widened beyond
`.qmd` to `.R` and `.Rmd`, for jobs that never returned to the library. Blocked
on server access; does not block source 1.

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

**Batches 3 and later are provisional**, recorded in the ledger's `batch`
field and stated as provisional wherever they are rendered. Current provisional
order: plots (9) → models (8) → machine learning (6) → distributions (2) →
descriptive (3) → datasets (3) → `ar` (1).

Two constraints on that order are firm rather than provisional:

- **Datasets last.** `bd`, `vars` and `dt` scaffold jobs that call
  **`hvtiRdatabuild`**, which is under active development. Their templates
  cannot be designed against an unsettled API. `blocked_on: hvtiRdatabuild`.
- **`ar` is terminal, and is `kind: meta`.** It is intended as a bookdown
  assembly of every template a study used — an aggregator over a set, not a
  job. It cannot be designed before the set it aggregates exists, and it must
  not be scheduled as though it were one more job template.

Descriptive and models are cleared to move earlier if ledger evidence favours
it. Nothing external forces the order: see §8.

---

## 8. Risks, and one that was withdrawn

⚠️ **The "SAS licence expires 2026-09-29" deadline does not apply, and should
not be reinstated from an older note.** Nine places in `dev/specs/` state that
date, twice as a load-bearing forcing function. The maintainer confirmed on
2026-08-29 that the licence runs into **2027**, and that compiled data stays
readable well beyond it. Correcting those nine statements is tracked
separately; this roadmap does not depend on the date either way. Every
template shipped so far was extracted by **reading** SAS source, never by
running it, and this roadmap plans no reference runs.

Remaining risks:

| risk | mitigation |
|---|---|
| The ML batch blocks on a cross-repo taxonomy PR | `blocked_on` names it; raise the PR before batch planning, not during |
| Datasets blocks on `hvtiRdatabuild`'s API | scheduled last; `blocked_on` records why, so "last" is not mistaken for "lowest value" |
| `r_exemplars` is a lower bound | stated in the ledger header and every rendering; intake source 1 narrows it |
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
