# The second exemplar: an `ac` → `hz` → `hp` chain in maze

**Date:** 2026-08-26
**Status:** design, approved for planning
**Repos touched:** `hvtiRtemplates` (this spec, and the templates it unblocks),
`hvtiRutilities` (`study_init()`, `assert_cohort()`), the maze study tree.

---

## 1. Why this exists

`inst/templates/README.md` states the gate plainly:

> `hz` (parametric temporal-hazard fit) and `hp` (nomogram and figures) are
> **not templated yet**. Both shapes exist in exactly one study, and a template
> extracted from a single example encodes that study's choices as though they
> were general. They arrive once a second study has run them.

That one study is `preserve_root`. This design runs the second, so the gate
opens for `ac`, `hz` and `hp` together.

It is not only a formality. A 2026-08-26 census of the SAS corpus
(3,269 listings, 4,843 fit blocks, 527 studies; see
`PARITY-HANDOFF.md` §14 in the preserve_root tree) shows **preserve_root's
phase shape is a minority one**:

| shape | fit blocks |
|---|---|
| `E+L` | 3,157 |
| `E+C` (preserve_root) | 472 |

Extracting a template from preserve_root alone would encode an
`Early+Constant` habit that six sevenths of the corpus does not share, along
with interval censoring that most jobs do not have. The second exemplar is
what stops that.

## 2. The study

`/studies/cardiac/rhythm/maze/atricure/gender` — *Gender differences in
post-op outcomes of RF ablation for treatment of AFIB*, CCF 2001 to 2004.

Chosen because it differs from preserve_root on the axes that matter, while
remaining checkable:

| | preserve_root | maze/atricure/gender |
|---|---|---|
| phase shape | `E+C` (minority) | **`E+L`** (majority) |
| interval censoring | yes — dominates the job | **none** |
| cohort | job-filtered, 291 of 378 | **whole dataset, 512** |
| cohort gate | Shape B | **Shape A** |
| `noconserve` reference | none usable | ⚠️ **none usable either** — see §6 |
| nomogram on the target fit | yes, 23 points | **yes, 8 points** |

### The §6.1 gate — run 2026-08-26, passes 5/5

`hz.dead.sas` applies no cohort filter (`data built; set library.built;` plus
a column drop), so the job cohort is the whole dataset. Verified against
`hz.dead.lst`'s own printed figures:

| check | R, from `built.sas7bdat` | `.lst` |
|---|---|---|
| N | 512 | 512 |
| events | 53 | 53 |
| right censored | 459 | 459 |
| `IV_DEAD` min | 0.008213721 | 0.008213721 |
| `IV_DEAD` max | 4.175308 | 4.175308 |

No `NA` in either gate variable. **This is the first §6.1 gate in the parity
effort that passed without a fight** — preserve_root's needed a job-defined
`predim_avail` filter that cannot be recovered from the `.lst` at all.

## 3. Layout — the taxonomy, not preserve_root's

preserve_root's R jobs live in `analyses/R_hazard/{R,qmd}`. That is **legacy**:
the 2026-08-13 provenance design records `_study.yml` as the thing that
"subsumes the `_quarto.yml` walk that `R_hazard` ... uses". Building the second
exemplar there would copy a superseded layout and force template extraction to
translate placement as well as content.

So the jobs go where `new_job()` puts them:

| file | origin |
|---|---|
| `distributions/dead-hz-03.01-ac.qmd` | `new_job("ac", "dead", "hz")` |
| `distributions/dead-hz-03.02-hz.qmd` | hand-written |
| `graphs/dead-hz-06.01-hp.qmd` | hand-written |
| `parity/dead-hz-03.02-hz-parity.qmd` | hand-written — see §7 |

Generated artifacts follow the rule already stated in the templates README —
authored files flat, generated artifacts under `<endpoint>-<type>/`:

```
estimates/dead-hz/ac.rds
estimates/dead-hz/hz.rds
graphs/dead-hz/hp-*.png
```

### Ordinals — already settled, not a decision for this design

⚠️ **An earlier draft of this spec assigned `hz` the ordinal `04.01` and
described it as precedent-setting. That was wrong on both counts.**
`specs/2026-08-21-template-set-layout-design.md` §5 already fixes the scheme:
the **major comes from the taxonomy folder**, the minor is the next free
position within it.

| major | folder |
|---|---|
| `01` | `datasets` |
| `02` | `descriptive` |
| `03` | `distributions` |
| `04` | `analyses` |
| `05` | `estimates` |
| `06` | `graphs` |
| `07` | `documents` |

That spec spells out this exact chain: *"`ac`, `hz`, `hp` produce `03.01`,
`03.02`, `06.01`"*. So **`hz` is `03.02`** — `04` is `analyses`, and a
`04.01-hz.qmd` sitting in `distributions/` would fail the ordinal-vs-folder
test §5 requires. The ordinal is global and fixed per prefix, identical in
every study; scaffolded sets therefore have deliberate **gaps**, and a gap
positively says "no job of that type here".

The error came from reading `hp = 06.01` as evidence of a global run-order
sequence. Both readings explain `ac = 03.01` and `hp = 06.01`; the folder rule
is the documented one, and it was documented in a file the templates README
points at directly.

## 4. Study scaffold

maze has no `_study.yml`. One call, using the gate-verified figures:

```r
study_init(root       = "/studies/cardiac/rhythm/maze/atricure/gender",
           study      = "Gender differences in post-op outcomes of RF ablation for AFIB",
           population = "CCF 2001 to 2004",
           built      = "built.sas7bdat",
           event      = "dead",
           time       = "IV_DEAD")
```

Because the job cohort equals the study cohort, `assert_cohort()` is a genuine
gate here rather than a restatement of itself.

## 5. The `hz` job

preserve_root's `02-hz-dead_pa.qmd` is the skeleton. Everything specific to
interval censoring drops out: no `Surv(type = "interval2")`, no `icensor`
mapping, no `objective = "sas"`. The response is simply `Surv(IV_DEAD, dead)`.

SAS's fit 1, read from `hz.dead.lst`:

```r
phases <- list(
  early = hzr_phase("cdf", t_half = 0.9996401, nu = 2.550286, m = -0.337948),
  late  = hzr_phase("g3", tau = 1, gamma = 1, alpha = 1, eta = 2.574888,
                    fixed = c("tau", "gamma", "alpha"))
)
```

`DELTA = 0`. With `TAU = GAMMA = ALPHA = 1` the late phase is the pure Weibull
`G3 = t^eta`. Branch is **Case 2** (`m < 0`, `nu > 0`).

**Targets — and which question each answers.** Corrected 2026-08-26 after
running it; an earlier draft promised the deterministic *fit* would reproduce
SAS's log-likelihood. It does not, and cannot: `hazard(fit = TRUE)`
re-optimises and moves off SAS's point.

⭐ **The objective agrees; the optimiser improves on SAS.** Evaluated **at
SAS's own converged estimates, with no refitting**, R reproduces every printed
log-likelihood:

| fit | R at SAS's θ | SAS | diff |
|---|---|---|---|
| overall | −176.933714 | −176.934 | **2.9e-04** |
| male | −92.915820 | −92.9158 | **2.0e-05** |
| female | −81.721712 | −81.7217 | **1.2e-05** |

Refit from those same starting values, R instead finds a **higher** likelihood
than SAS reports (overall −176.842, male −92.545, female −80.385). That is not
an R defect — it is a statement about where each optimiser stops.

The two must be reported separately, and only the first is a parity number.
§12 of the parity handoff draws exactly this line: *pinning Λ and h at SAS's
estimates does not show R's optimiser finds them.* The job reflects this
split — a blocking `parity-at-sas-estimates` chunk gated at 1e-3, and an
`optimiser-comparison` chunk that is explicitly not parity.

Two mechanics this cost time to establish: `hazard(fit = FALSE)` leaves
`$fit$objective` as `NA` ([#144](https://github.com/ehrlinger/temporal_hazard/issues/144)),
so the objective must be evaluated through the internal
`.hzr_logl_multiphase()`; and that function returns the **log-likelihood
directly** (negative for these fits), which must not be negated.

**Conservation:** 53 events, `Conservation of events: Invoked at each
iteration`. Note the constraint is nearly non-binding on this cohort —
`Σ Λ(tᵢ)` is 53.00000 with `conserve` on and 53.00073 with it off, so the
three overall refits report an identical likelihood to six decimals. The job
prints both sums, because "the control did nothing" and "the control had
almost nothing to do" are indistinguishable in the likelihood column and mean
opposite things.

Retained from the exemplar, deliberately:

- the **blocking** cohort gate — the job does not run on a wrong cohort;
- the `check_fit()` guard asserting the objective is a finite, negative
  log-likelihood, so a plateau is never reported as a fit;
- deterministic fit (from SAS's own estimates) reported separately from the
  multi-start fit. *Does R agree with SAS* and *is SAS at the optimum* are
  different questions and must not be conflated;
- the conditioning report against SAS's printed condition number.

### What `hz` writes

```
estimates/dead-hz/hz.rds   # list(deterministic =, multistart =, noconserve =)
```

⚠️ **This shape is provisional.** `hm` ("risk factor analysis; builds on the
HZ fit") and `hs` ("patient-level survival predictions from the HM model")
will consume it, and neither has been ported. The shape mirrors what
preserve_root's job already saves; it is recorded as a contract so the first
`hm` port either confirms it or changes it deliberately, rather than
inheriting an accident. See §8.

## 6. ⚠️ RETRACTED — maze does NOT provide a clean `noconserve` reference

**This section claimed the opposite and was wrong. Retracted 2026-08-26.**

It read: *"`hz.dead.lst` carries two fits, and fit 2 is `Conservation of events:
Not invoked` — the same model with conservation off, LL −176.746 ... maze
closes that gap."*

Reading `hz.dead.sas` — which I had not done — shows fit 2 is **not** the same
model:

```sas
  proc hazard data=built noconserve p outhaz=outest steepest quasi mi=200
       condition=14;
       ...
       early female;
       late  female;
```

It turns conservation off **and adds a `female` covariate to both phases**. Its
LL therefore confounds two changes at once — which is *exactly* the defect that
makes preserve_root's fit 2 (which adds `G_ROOT` to both phases) unusable as a
conservation target. maze has the identical problem, so **−176.746 is not a
`noconserve` target and must not be quoted as one.**

The claim came from reading the `.lst`'s `Conservation of events: Not invoked`
line and inferring the rest. §6.3 of the parity handoff already warns against
exactly this move in a narrower form — *do not trust the `libname`/`set`
statement to name the dataset* — and the general rule it implies is: **the
`.lst` tells you what SAS printed, the `.sas` tells you what SAS was asked.
Read both before characterising a fit.**

**Consequence for the plan:** Task 3 keeps its deterministic and multi-start
fits and drops the `noconserve` comparison. A genuine `noconserve` reference
remains unfound in any study examined so far.

**What maze still provides**, unaffected by this retraction: the majority `E+L`
phase shape, no interval censoring, a Shape A cohort, a clean §6.1 gate, and a
printed nomogram on the target fit. It remains the right second exemplar; it
simply does not close the conservation gap as well.

## 7. Verification — a `parity/` job, not folded into `hp`

⚠️ **Also corrected.** An earlier draft put the SAS comparison inside the `hp`
job. `2026-08-21-template-set-layout-design.md` §5.1 places parity in a
**top-level `parity/` folder**, borrowing the ordinal of the job it checks with
a `-parity` suffix: `parity/dead-hz-03.02-hz-parity.qmd`. Parity is a *modality
of a job, not a job* — 1:1 with what it checks, optional, hand-written per
study, and transient, since it exists to retire SAS. Keeping it in one folder
makes the eventual cleanup one delete instead of a sweep.

`hp` therefore produces the nomogram figures; the parity job does the
comparison.

Fit 1 prints a nomogram of **8 points** — `YEARS` = 0.04107, 0.08214, 0.25,
0.50, 1.00, 1.50, 2.00, 3.00. (An earlier draft said 23; that was carried over
from the `dm_nodm` and `hz.reop.biop` oracles without checking maze's own
listing.) Note the leading two are 15 and 30 days: `15/365.25 = 0.04106776`
and `30/365.25 = 0.08213552`.

⚠️ **This file prints `YEARS` to 5 dp, where the g3 oracles print 4.** That is
precisely why print precision must be **inferred per column per file** and
never assumed — the same reason the sweep infers `SURVIV`/`HAZARD` width.

The parity job overlays R's `S(t)` and
`h(t)` on SAS's printed values using the same rule as
`shape-parity-sweep.R`: a point passes if SAS's printed value is reachable
from **any** `t` within the printed `YEARS` rounding interval, to that
column's own print half-ulp, with the precision **inferred per column** rather
than assumed.

Both halves of that rule exist because ignoring either fabricates failures:
SAS's print width varies between files, and the 30-day row's printed `0.0821`
is really `30/365.25`.

The job therefore carries its own parity evidence. A rendered page is itself
evidence the gate passed.

## 8. `hm`, `hs` and `bh` are NOT mocked in

Deliberate, and load-bearing. Job counts:

| prefix | maze | preserve_root |
|---|---|---|
| `ac` | 30 | 40 |
| `hz` | 24 | 35 |
| `hp` | 28 | 67 |
| `hm` | **0** | 1 |
| `hs` | **0** | 3 |
| `bh` | **0** | 6 |

`hm`, `hs` and `bh` exist **only in preserve_root**. Stubbing them into maze
would:

1. **Create jobs with nothing to gate against.** Every job in this design
   earns its place by having a `.lst` to check — cohort counts, printed
   estimates, a nomogram. A mocked `hm` in maze has none, so it would emit
   numbers no one can check. That is the failure mode this whole effort
   exists to catch.
2. **Invert the template gate.** For `hm`/`hs`/`bh`, preserve_root is the
   *first* study and maze cannot be the second, because it has no such jobs.
   A mock would make the roster look like two exemplars exist when it is
   still one — manufacturing exactly the false confidence the gate prevents.
   A template from one example encodes that study's choices as general; a
   template from zero encodes a guess.
3. **Rot.** A stub nobody runs drifts from the interface it stubs.

The roles therefore split:

- **maze** — second exemplar for `ac` / `hz` / `hp`.
- **preserve_root** — sole source of truth for `hm` / `hs` / `bh`, and the
  study to port them from when those templates are wanted.

`bh.dead.sas` and `bh.dead_summary.sas` appeared as untracked files in
preserve_root on 2026-08-26, so bootstrap-hazard work may already be in
flight. `bh` is the natural next port — not a mock.

## 9. Constraint carried for a project not being done

maze is **Shape A** (job cohort = study cohort); preserve_root is **Shape B**
(291 of 378, the filter living in the `.sas`, not the `.lst`). The cohort gate
must therefore be an **explicit, named section** of the `hz` job rather than
hardcoded to Shape A.

This is the one place the design accepts cost for future work: aligning
preserve_root to the templates is a separate project, and hardcoding Shape A
here would mean rewriting the gate then.

## 10. Out of scope

- Aligning preserve_root to the taxonomy layout (its own project, sequenced
  **after** this one so the conventions settled here are migrated onto rather
  than invented twice). While there, its `hz` job's `callout-important` is
  stale — it documents the −268.65 vs −239.194 discrepancy as unresolved and
  pins TemporalHazard 1.2.1, but that was solved and shipped as
  `objective = "sas"` in 1.2.4. The parity documents were repointed on
  2026-08-25; the production job was not.
- Repeated-events jobs (`hz.ce_cardioversion_repeated`, grade 4 and the
  largest remaining `hzr_decompos_g3` widening — a **parity** target, a poor
  template exemplar).
- Longitudinal (`mm`, `gm`, `mp`, `gp`).
- A job-type inventory sweep across `/studies` (cheap, filename-only, and the
  thing that would have answered §8's table in one lookup instead of by hand).

## 11. Both open items — RESOLVED 2026-08-26

**`theta` order for `E+L`.** Read from the package
(`.hzr_phase_theta_names()`), not guessed:

```
early.log_mu, early.log_t_half, early.nu, early.m,
late.log_mu,  late.log_tau,     late.gamma, late.alpha, late.eta
```

Nine positional values. Note the asymmetry: the late phase logs `mu` and `tau`
but carries `gamma`, `alpha`, `eta` on the natural scale.

**The `ac` template needs no change.** It already ships the cohort gate as an
EDIT block offering **Shape A** (`read_built()` + `assert_cohort()`) and
**Shape B** (job filter + counts from the SAS reference, explicitly *not*
`assert_cohort()`, because `_study.yml` describes the study rather than the
job). §9's constraint is therefore already met in `ac`, and the `hz` job should
follow the same pattern rather than inventing one.

## 12. Success criteria

1. `_study.yml` exists in maze and `assert_cohort()` passes on the real data.
2. All three jobs render from a clean session.
3. The `hz` job reproduces SAS's log-likelihoods **at SAS's own estimates** —
   overall −176.934, male −92.9158, female −81.7217, each within 1e-3 — and
   conserves **53** events. The *refits* are reported separately and are not
   expected to match; on this study they find a higher likelihood.
4. ~~The `noconserve` fit reproduces −176.746.~~ **Struck** — see §6; that
   fit adds a `female` covariate and is not a conservation reference.
5. `parity/dead-hz-03.02-hz-parity.qmd` reproduces SAS's nomogram at **8/8**
   points for both `S(t)` and `h(t)`, under the per-column print-precision rule.
6. Every scaffolded filename satisfies the §5 ordinal-vs-folder rule.
7. `template_list()` in `hvtiRtemplates` is unchanged — this design produces
   *jobs*, not templates. Extraction is the next project, and it now has two
   exemplars to intersect.
