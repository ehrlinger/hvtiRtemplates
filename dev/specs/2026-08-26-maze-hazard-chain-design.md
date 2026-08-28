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
`dev/specs/2026-08-21-template-set-layout-design.md` §5 already fixes the scheme:
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
estimates/dead-hz/hz.rds   # list(deterministic =, multistart =, noconserve =,
                           #      male =, female =)
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

## 9b. What of the SAS jobs is NOT ported — stated, not implied

A second exemplar is only useful if its gaps are known. These are the parts of
the four SAS jobs the R chain does **not** reproduce. None is a defect; all are
undone work, and naming them stops a later reader inferring coverage that does
not exist.

| SAS feature | where | status |
|---|---|---|
| `%hazplot(...)` goodness-of-fit suite | `hz.dead.sas:94` | **no R counterpart.** The R chain checks parity against printed estimates; it runs no GOF diagnostics. |
| Fit 2 → `est.hzdead_fem` | `hz.dead.sas:110-122` | fitted in R as the `noconserve` sensitivity, but **not** ported as the covariate model it actually is (`early female; late female;`). Nothing reads it. |
| Nomogram CI columns | `hz.dead.lst` (`_CLLSURV`/`_CLUSURV`, `_CLLHAZ`/`_CLUHAZ`) | **parsed then discarded.** 32 more printed values the parity job reads and does not check. Pinning them would test the variance path, not just Λ and h. |
| Confidence bands on the figures | `hp.dead.female.sas` (`_CLLSURV`/`_CLUSURV`, `_CLLHAZ`/`_CLUHAZ`) | **dropped.** The R figures plot point estimates only. SAS also picks specific rows for band display (`if female=0 and number in (264, 252, ...)`), which is not reproduced. |
| Axis ranges | `hp.dead.female.sas:157-182` | **deliberately different.** SAS uses months 0–24 with survival 80–100% and a linear hazard 0–4 %/month. The R figures run to 36 months and use log-y hazard, because the female fit's trough near month 10 is invisible on a linear 0–4 scale. Units match; scales do not. |
| Grid resolution | same | 1000 points vs SAS's 1001 (`inc=(max-min)/999.9` then an explicit final point). Immaterial for a smooth curve. |

### `ac` parity — added 2026-08-26, and it found a real divergence

`parity/dead-hz-03.01-ac-parity.qmd` compares R's life tables against
`ac.dead.lst`, across all three tables SAS prints (unstratified, and the two
under `Stratify by Female`). The table-to-arm mapping is proven rather than
assumed, as in the `hz` parity job.

**All thirteen compared columns now agree exactly, at the printed precision,
on every row of all three tables:**

| gated | overall | male | female |
|---|---|---|---|
| every SAS life-table column | **650/650** | **351/351** | **325/325** |

⚠️ **Not thirteen independent confirmations.** `cumhaz` is `−log(survival)` in
the macro itself, and `hazard`/`density`/`life`/`mid_int` are deterministic
functions of `survival` and `time`; `n_risk`/`n_censor`/`n_event` are cohort
bookkeeping. The independent agreements are **`survival`, `std_err`, and the
confidence limits** — the rest follow once those hold and the definitions are
known.

### ⭐ Every divergence was a difference of DEFINITION, not of data

Five columns initially disagreed. Reading `%kaplan`
(`/programs/apps/sas/macro.library/kaplan`) identified all five, and each then
reproduced exactly. **None was a disagreement about the data or the estimator's
correctness — every one was R and SAS computing a differently-defined
quantity under the same column name.**

**Confidence limits — a ~68% band, not 95%.** The limits are a logit-scale
interval back-transformed: `SI_EXACT` reduces to `SE/(S(1−S))`, so
`CL = expit(logit(S) ∓ T_ALPHA·SI)`. It *was* a transform, just not one of the
four first tried. And **`T_ALPHA = 1`** — solved from SAS's own printed output
(implied 0.999988, sd 0.0007, the scatter being 5-dp printing alone). So these
columns are **±1 standard error**:

| row 1 | lower | upper |
|---|---|---|
| SAS `CL_LOWER`/`CL_UPPER` | 0.99470 | 0.99928 |
| `hzr_kaplan()` 95% | 0.98627 | 0.99972 |

⚠️ **This reaches beyond maze.** preserve_root runs the same macro. Anyone who
has read a `CL_LOWER`/`CL_UPPER` pair from these listings as a 95% interval —
in a figure, a table or a manuscript — has read a band about half as wide as
they thought.

**`hazard`, `density`, `life` — interval quantities keyed to the previous
EVENT row.** From the macro (lines ~112-128), with `LAG_*` advancing only
inside `IF &EVENT>0`, so censoring-only rows do not move the lag:

```
Δt      = t_i − t_(previous event row)
HAZARD  = log(S_prev / S_i) / Δt        # cumulative-hazard increment, NOT d/(n·w)
DENSITY = (S_prev − S_i) / Δt
LIFE    = Σ Δt·(3·S_i − S_prev)/2
```

An earlier hypothesis in this spec called it "an interval-width convention"
and guessed an actuarial `d/(n·w)` rate. That was close but wrong on both
counts: the gap skips censoring-only rows, and `HAZARD` is a log-ratio, not a
rate. Implemented as written, all four reproduce **50/50 exact**.

⚠️ **One trap worth carrying.** These must be computed from **full-precision**
`survival` and `time`, never from SAS's printed 5-dp columns. Fed the printed
values, `HAZARD` scores 2/50 — `log(S_prev/S_i)` for two nearly-equal rounded
numbers amplifies the rounding enormously. The job comments this.

**`hzr_kaplan()`'s own `hazard`/`density`/`life` and 95% limits are retained in
the report as non-gated columns**, precisely to keep visible that they are
*different estimators*, not wrong ones.

⚠️ **Consequence worth carrying:** `hzr_kaplan()` and `%kaplan` agree exactly
on survival and its standard error. Every other column is **reconcilable but
not interchangeable** — the definitions are now known and reproduce to the last
printed digit, but the two packages' same-named columns are different
quantities. Anything that consumes `hazard`, `density`, `life` or the
confidence limits from one side while comparing against the other is comparing
different things, and the confidence-limit case additionally differs in
coverage (±1 SE against 95%).

### RESOLVED 2026-08-26 — SAS stopped short on a shallow ridge, and it does not matter

The question was whether R's refit gaining likelihood from SAS's own start
means SAS stopped early, or means the two objectives merely coincide at that
θ. **It is the former, and the gap is statistically meaningless.**

**1. The objectives are the same.** At SAS's θ, five of the six free gradient
components vanish to ~1e-5; only `early.log_t_half` is materially non-zero
(−0.133). Five coordinates independently agreeing that SAS is stationary is
not what two different functions look like.

**2. Conservation is not what holds SAS there.** `Σ Λ(tᵢ) = 53.00000` exactly
at SAS's θ, so the constraint is satisfied — but decomposing ∇L against ∇g
shows only **6.4%** of the gradient lies along the constraint direction. SAS's
point is **not a KKT point**: a likelihood-increasing direction is available
that conservation does not block.

**3. It is one mode, not two.** Profiling the likelihood along the straight
line from SAS's θ to R's refit rises **monotonically** with no dip
(−176.9337 → −176.8420 over nine steps). There is no barrier between them, so
this is not multimodality — it is one long, gently ascending ridge.

**4. The ridge is nearly flat, and the parameters on it are unidentified.**
R's standard error for `log_t_half` at SAS's θ is **6.5** — `t_half` is
essentially undetermined by these data. The whole excursion moves `t_half`
from 0.9996 to 0.353 and `nu` from 2.55 to 1.54 to buy 0.09 log-likelihood.

**5. So the disagreement is not material.** Every SAS estimate lies well
inside R's 95% confidence region:

| fit | Δ log-likelihood | 2ΔLL | inside 95% (χ²₆ = 12.59) |
|---|---|---|---|
| overall | 0.0920 | 0.18 | ✅ p = 1.00 |
| male | 0.3705 | 0.74 | ✅ p = 0.99 |
| female | 1.3364 | 2.67 | ✅ p = 0.85 |

⚠️ **What did NOT settle it, and why.** The obvious test — comparing R's
Hessian at SAS's θ against the variance-covariance matrix the `.lst` prints —
**does not discriminate**. SAS's fit runs with `condition=14`, which
regularises an ill-conditioned Hessian, so its variance path differs from R's
whether or not the objectives match. R's unconstrained SE for `log_t_half` is
6.5 against SAS's printed 0.0053, a ratio of 1230 — and projecting out the
conservation constraint changes it by less than 1e-5, so conservation does not
explain it either. The conclusion above rests on the gradient, the path
profile and the confidence region, not on that comparison.

**Consequence for §5.** "The optimiser improves on SAS" is accurate but should
not be read as a defect on either side. SAS's convergence criterion was met on
a ridge flat enough that the remaining gain is inside the noise; R's optimiser
kept walking it. Both land in the same confidence region, and the parity that
matters — the objective evaluated at SAS's estimates — is exact.

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
5. `parity/dead-hz-03.02-hz-parity.qmd` reproduces SAS's nomograms at **22/22**
   rows / 30 checks, all exact at the printed precision and needing no
   tolerance rule: overall `S(t)` 8/8 and `h(t)` 8/8 from `hz.dead.lst`, plus
   male 7/7 and female 7/7 `S(t)` from `hp.dead.female.lst`.
6. Every scaffolded filename satisfies the §5 ordinal-vs-folder rule.
7. `template_list()` in `hvtiRtemplates` is unchanged — this design produces
   *jobs*, not templates. Extraction is the next project, and it now has two
   exemplars to intersect.
