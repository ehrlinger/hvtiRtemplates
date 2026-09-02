# Batch 2a — the bootstrap screen family

**Date:** 2026-08-31
**Status:** Phases 0-3 shipped. Phase 3 opened upstream with `boot_bag()` in
`hvtiRbootstrap` 0.9.2 (§4.2), then shipped `bl`, `br` and `bc` in 1.0.20.
**Not done:** the SAS parity comparison for `bl` and `br` (§8), which lives in a
study's own R project, and which `bc` cannot have.
**Roadmap:** `2026-08-29-template-conversion-roadmap.md` is the live batch
assignment, generated from the ledger; the reasoning behind family batching is
in `2026-08-29-template-conversion-roadmap-design.md`. Both put `bl`, `bc`,
`bn`, `bq` and `br` in one family riding on `bh`'s design. The corpus does not
support that grouping; see §2.

**This spec changed the ledger, not only the prose.** `bn` moves to a new
`bootstrap-ci` family and `bq` to `blocked_on: hvtiRbootstrap#16`, both
unscheduled, and the roadmap document is regenerated. Rescoping in prose alone
would have left the generated roadmap still showing them in batch 2 —
the drift the ledger exists to prevent.
**Issue:** [#8](https://github.com/ehrlinger/hvtiRtemplates/issues/8)

This note is self-contained. It assumes no memory of the session that produced
it.

---

## 1. What this decides

That `bl`, `br` and `bc` ship as thin templates over a reporting layer extracted
into `hvtiRbootstrap`, and that `bq` and `bn` leave this batch for stated
reasons.

It decides nothing about `bn`'s eventual design, and nothing about the other
prefixes in the roadmap.

---

## 2. The roadmap's family was wrong, measured three ways

The roadmap grouped six prefixes on the premise that each is "`bh` with a
different model call". Three measurements say otherwise.

### 2.1 What exists to port

| prefix | SAS templates (live) | R exemplar studies | corpus studies |
|---|---|---|---|
| `bh` | 5 | 2 | 322 |
| `bn` | **10** | 0 | 214 |
| `bl` | 4 | 1 | 352 |
| `br` | 2 | 1 | 103 |
| `bq` | 1 | 0 | 2 |
| `bc` | **0** | **0** | 16 |

### 2.2 `bn` is a different job

Its macros do not overlap `bh`'s beyond `%vars`:

```
bh: %hazboot  %hazbtcp  %sumboot  %cluster  %hazpred
bn: %bnmnr    %bnmnr_gr %bnprev   %decompos
```

Its filenames — `binary.avregurg.ci`, `continuous-avmngrad`,
`ordinal-avregurg` — match its taxonomy description: *bootstrap confidence
intervals for nonparametric estimates*. That is not bootstrap variable
selection. **Grouping it would encode a similarity that is not there**, which
is the failure family batching exists to avoid.

### 2.3 The fitters decide the rest, not the SAS corpus

`hvtiRbootstrap` 0.1.1 exports `boot_select(data, formula, fitter, ...)` —
model-agnostic with a pluggable fitter — plus `fit_cox`, `fit_linear` and
`fit_logistic`, all sharing `(data, formula, select)`.

⚠️ **This inverts the reading taken from the SAS counts.** `bc` has no SAS
template and no R exemplar, yet `fit_cox` already exists; `bq` has a SAS
template but **no quantile fitter**, so its template cannot be written at all.
An earlier draft of this scoping had them the other way round, on the SAS
counts alone.

### 2.4 Resulting scope

| prefix | disposition |
|---|---|
| `bl` `br` `bc` | **in this batch** — fitter exists, shape matches `bh` |
| `bq` | **deferred, blocked**: no quantile fitter — [hvtiRbootstrap#16](https://github.com/ehrlinger/hvtiRbootstrap/issues/16). A demand signal on that package, not a template problem |
| `bn` | **deferred, own design**: different job entirely (§2.2) |

---

## 3. The duplication problem, and why the fix goes upstream

`04.05-bh.qmd` is **825 lines, of which the model-specific surface is about ten
code lines** — all deriving or ordering by `phase`, which exists only because
multiphase hazard terms are named `early.age` / `late.bmi`. Logistic, linear and
Cox have no phases.

Everything else is a report over a **model-agnostic bag**: its contract names
`n_boot`, `seed`, `slentry`, `slstay`, `base_params`, `usable`, `requested`,
`n_rows`, `elapsed_mins`, `manifest`, `boot` — nothing about hazards.

So writing `bl`, `br` and `bc` as siblings means **four ~825-line files that
must be hand-synced on every fix**. This repository has a documented history of
what hand-synced copies do; the macro-allocation spec's tables drifted three
times in a single day, which is why `check-spec-counts.py` exists.

**Therefore: extract first, then template.** The computation moves into
`hvtiRbootstrap`; the templates keep what a study author edits and reads.

---

## 4. The boundary

| stays in the template | moves to `hvtiRbootstrap` |
|---|---|
| every `kable()`, all prose, the figure, `saveRDS` | the bag contract check |
| every `EDIT:` marker — `EXPECT_CHUNKS`, `EXPECT_BOOT`, `BOOT_PREFIX`, the concept map, thresholds, clusters | completeness / shortfall |
| `ENDPOINT` / `TYPE` and `set_path()` | frequencies, retained, dropped |
| the narration explaining *why* each number matters | concepts, clusters, collinearity |

This is the split `us_cohort_curve()` established for `hs`: the package owns the
computation, the template owns the narration and the study's decisions. A study
author must still be able to read and adjust what the report says **without
editing another repository** — templates are the product.

### 4.1 Phase-awareness is not optional

Every extracted function takes **`phase = NULL`**. With `NULL` there is no phase
dimension; `bh` passes its term-splitting rule. One code path serves all four
templates.

The alternative — the package serving `bl`/`br`/`bc` while `bh` keeps its own
copy — reintroduces exactly the two-implementations problem the extraction
exists to remove.

### 4.2 The reporting layer had no producer, and this was found in Phase 3

⚠️ **Added 2026-09-01, after Phases 1 and 2 shipped.** §4 above describes the
reading side correctly and says nothing about the writing side, which is where
the gap was.

`boot_validate()` requires a **long-form** bag: `boot$replicates` carries one
row per selected (replicate, term) pair, with an unselected term simply absent.
That shape is written by TemporalHazard's hazard runner, which is why `bh`
works.

`boot_select()` — this package's own entry point, and the function a `bl`, `br`
or `bc` runner calls — returns a **wide** `boot_selection`: a coefficients
matrix, two integers and an unevaluated call. It takes `sle`, `sls` and `seed`
as arguments and records none of them structurally. Nothing pivoted wide to
long.

So the layer Phase 1 extracted could not be reached from the screen function
that feeds it. Written as designed, each study would hand-write the pivot plus
nine provenance fields, and the three thin templates would ship three copies of
an instruction to do so — the hand-sync problem the extraction exists to
remove, re-entered one layer down.

**This is §6's failure shape with one difference that makes it worse: the
artifact is produced by the SAME package, at the other end of it.** The two
ends were built against different studies and never met. No test in either
repository composed them, because each end had its own fixtures.

**Resolution.** Phase 3 opens upstream, as Phase 1 did. `hvtiRbootstrap` gains
`boot_bag()`, which converts a `boot_selection` plus the four facts a screen
cannot know — which terms are the base model, how many candidates were offered
before any were dropped, the dataset manifest, and what was dropped — into a
validated bag. `boot_select()` records a `$control` list so that the bag's
entry level, stay level, seed and row count come from the run rather than from
what a caller retypes; `$call` cannot serve, because `match.call()` omits every
argument left at its default.

---

## 5. What Phase 0 established, and what it cost

Before any of the above, the shipped `bh` was rendered against a real 25-chunk
bag from a study on the share. **This had never been done.**

It found a **render-blocker in the shipped template**: the `provenance` chunk
passed `bag$requested` and `bag$usable` to `data.frame()` as scalars when they
are per-phase vectors, so the table could not build on any multiphase bag —
which is every hazard bag. Fixed in 1.0.17
([#59](https://github.com/ehrlinger/hvtiRtemplates/pull/59)).

⚠️ **The template was authored against that exact bag.** `EXPECT_CHUNKS <- 25L`
and `EXPECT_BOOT <- 500L` are that study's own values. It shipped in 1.0.13 and
was renumbered in 1.0.15 with the defect intact, because nobody ran it.

**So Phase 0 is a required step of this batch, not a preliminary.** Each new
template renders against a real bag before it ships. The capability now exists:
a scratch project outside the study, chunks copied read-only, `HVTI_TEMPLATE_DRAFT=1`,
reaching 43 of 49 chunks. The remaining six need `read_built()` and therefore a
study tree.

⚠️ **No study identifier crosses back into this repository.** The render happens
in scratch or in the study; only counts and a pass/fail return.

---

## 6. `boot_validate()` must check shapes, not just presence

The existing `contract` chunk checks that eleven fields are **present**. It
passed the real bag happily while `requested` was a length-2 vector the template
could not handle.

**This is the fourth instance of one failure shape in this template family**,
and every one was invisible to `R CMD check`, the test suite, `lintr` and code
review:

| template | field | assumed | actually |
|---|---|---|---|
| `hs` | `hm.rds$covariates` | character vector | `list(early=, late=)` |
| `hs` | `fit$data` | the model frame | a container; columns in `$frame` |
| `bh` | `bag$requested` / `$usable` | scalar | per-phase vector |
| `bh` | zero-length field | one value | `character(0)`, dropping a row |

Every one is **a field read out of an artifact produced by a different
package**. That is a narrow, checkable category rather than a general lesson.

**So `boot_validate()` asserts the shape of each field it names — type, and
scalar-versus-vector — not merely that the name exists.** It is the one piece of
this extraction that would have prevented the defect that motivated it.

---

## 7. Sequencing

**Phase 0** — render the fixed `bh` against the real bag; keep the output as the
reference. Already possible; §5.

**Phase 1** — `hvtiRbootstrap` gains the reporting layer and `boot_validate()`.
Ships as its own release. **This batch's first visible output is in another
repository**, which is the correct order and worth stating plainly.

**Phase 2** — `04.05-bh.qmd` is rewritten onto the new API. **Its ordinal and
filename do not change**; this is a body-only refactor, and it must be verified
**result-identical** against the Phase 0 render, the same gate
`us_cohort_curve()` passed at 1e-12.

**Phase 3** — `hvtiRbootstrap` gains `boot_bag()` and ships it (§4.2), then
`bl`, `br` and `bc` ship as thin templates. Ordinals are assigned from the
ledger as free minors in `analyses`, **never recomputed from taxonomy row
position** (`04.06` is retired and cannot be reissued): `bl` 04.02, `br` 04.03,
`bc` 04.04.

---

## 8. Definition of done

- `hvtiRbootstrap` released with the reporting layer and shape-checking
  `boot_validate()`.
- `04.05-bh.qmd` rewritten, verified result-identical, ordinal unchanged.
- `bl`, `br`, `bc` each: renders against a bag built by `boot_bag()`; own
  `.lintr` **file** key; `edit-guard` chunk; exactly one `^ENDPOINT` and one
  `^TYPE` line; no study identifiers; README row; ledger row `shipped` with its
  assigned ordinal.
  ⚠️ **The render gate for this phase is a screen the gate runs, not a screen a
  study ran, and that is weaker than what `bh` got.** `bh` rendered against a
  real 25-chunk bag a study had produced (§5). Searched on 2026-09-01: no R job
  found on the share calls `boot_select()`, so there is no `bl`, `br` or `bc`
  bag to read. The gate therefore screens a study's real built dataset, which
  exercises real variable names, a real correlation structure, a real row count
  and `read_built()`. It does not exercise a candidate pool a study author
  chose. For `bl` and `br` that last gap is closed separately, by comparing an
  R screen against the SAS `%bootreg` job it replaces over the same pool and
  criteria — **distributionally, not exactly**: two bootstrap runs draw
  different resamples, so their frequencies differ by roughly **three**
  percentage points per variable at 500 replicates and no 1e-12 comparison is
  available. Three, not two: 2.2 points is the error of ONE run, and the
  difference of two independent runs is larger by a factor of root 2.
  `bc` has no SAS counterpart anywhere in the corpus and gets no such check.
- `devtools::test()` passes; `devtools::check()` 0/0/0; `document()` run.
- Patch bumps with matching `NEWS.md` entries. **One tag per release**, not one
  per template: packages are moving under the `hvtiR` meta-package, where each
  tag is a member re-resolution and another `update()` downstream.

---

## 9. Out of scope

- **`bq`** — no quantile fitter in `hvtiRbootstrap`:
  [#16](https://github.com/ehrlinger/hvtiRbootstrap/issues/16). Not a template
  problem and not fixable here. The SAS side pairs `%bootreg` with `fit_linear`
  and `%bootqr` with nothing; `%bootqr` is not in `~/Documents/macro.library`
  either, so `tp.bq.quantile_regression_bagging.sas` is the specification that
  exists. ⚠️ `bq` is the **smallest prefix in the taxonomy** — 2 studies, 18
  jobs — so this may sit unbuilt for a while; it is filed so the blocker lives
  where the fix would.
- **`bn`** — a different job (§2.2). Needs its own design spec against its own
  macros and its 10 SAS templates.
- **Running the screens.** These templates report over a bag; the bag is
  produced by a companion runner, and that boundary is a durability boundary —
  a full screen is days of compute and writes nothing until its last replicate.

---

## 10. Rejected

**Three near-copies of `bh` now, extract later.** Fastest to a shipped batch,
and creates four ~825-line files to hand-sync. The repo's own history says how
that ends.

**One template with the model as an `EDIT:`.** No duplication, but `new_job()`
scaffolds by prefix and the taxonomy gives `bh`/`bl`/`bc`/`br` separate rows and
ordinals. It would break the naming scheme to save a file.

**Absorbing presentation into a `boot_report()` that emits.** Least duplication
of all, and a study author could no longer read or adjust what the report says
without editing another repository. Against the premise that the templates are
the product.

**Keeping `bq` in the batch on its SAS template.** A template that cannot call a
fitter is not a template. The SAS file is evidence the job exists, not a way to
run it in R.
