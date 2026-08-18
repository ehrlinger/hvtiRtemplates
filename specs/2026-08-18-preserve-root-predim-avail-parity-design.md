# Preserve-root `predim_avail` death chain — TemporalHazard conversion and parity

**Date:** 2026-08-18
**Status:** Approved design
**Study:** `/studies/vascular/thoracic-aorta/dissection/ascending/acute/preserve_root`
**Study title:** Fate of Preserved Aortic Root in Acute Type A Aortic Dissection (2009–2021)
**Spec home:** this repository. The study folders are on a network share that
does not host git repositories, so the design record lives with the package that
owns the migration programme (§3.2).

---

## 1. Purpose

Convert the `predim_avail` death chain from SAS to R with `TemporalHazard`, 1:1, and
check every estimate against the committed SAS reference output.

This is not a one-off. Three studies prototype three packages:

| Study | Order |
|-------|-------|
| `cardiac/valves/aortic/replacement/pericardial/lv_function/survival` | first |
| `cardiac/valves/aortic/replacement/pericardial/resilia` | second wave |
| `vascular/.../acute/preserve_root` (this one) | second wave |

driving `hvtiRtemplates`, `hvtiRutilities` and `hvtiRlifetables`.

What this study contributes that `lv_function` could not:

| Package | Contribution |
|---------|-------------|
| `hvtiRtemplates` | Second consumer of the `ac`/`hz`/`hp` job templates — the one that separates generic scaffolding from study-specific content. You cannot tell which is which with one consumer. |
| `hvtiRutilities` | A **live, mutable** `built.sas7bdat`, rewritten 2026-06-09. `lv_function`'s dataset was archival; `verify_manifest()` has never faced real drift. |
| `hvtiRlifetables` | `graphs/hs.uslife.sas` is the **only `hs` reference in any of the three studies**. Out of scope here (§8), recorded so the deferral is informed. |

### 1.1 Why this is a real second test, not a rerun

| | `lv_function` | preserve_root |
|---|---|---|
| Model | 6 free params, two-phase Weibull | **4 free params, early + constant** |
| Conservation of events | on, iterative | on, **closed-form branch** |
| N | 3049 | **291** |
| Interval-censored events | 3 / 1032 | 5 / 77 |
| CoE on/off pair | deferred to stage 5 | **in scope, same `.lst`** |
| vcov reference | standard errors only | **full 4×4 matrix, full precision** |
| `%vars` required | yes — post-`%vars` dataset | **no** (§4) |
| Numeric reference | `.lst` only | **`outhaz` dataset + `.lst`** (§6.1) |

A parity pass in `lv_function` transfers to none of these. Different likelihood branch,
different conservation path, different sample size regime.

---

## 2. Job flow

| # | Stage | SAS program | Reference on disk | R target |
|---|-------|-------------|-------------------|----------|
| 1 | Actuarial | `distributions/ac.dead_predim_avail.sas` | `.lst` (2026-05-26) | `hzr_kaplan()` |
| 2 | Hazard fit | `distributions/hz.dead_predim_avail.sas` | `.lst` (2026-06-11) + `estimates/hzdead_pa.sas7bdat` | `hazard()` |
| 3 | Nomogram + figures | `graphs/hp.dead_predim_avail.sas` | `.lst` (2026-05-06) + PDFs | `predict.hazard()` |

Stages 1 and 2 **do not share a response**. Stage 1 fits `iv_dead` / `dead`
(right-censored). Stage 2 fits `iu_dead` / `il_dead` / `ic_dead` / `idead`
(interval-censored). A stage-1 pass says nothing about the fitting path.

Stage 3 consumes stage 2: the SAS `%hazpred` call reads `inhaz=est.hzdead_pa`, the
stored estimate dataset. In R, stage 3 consumes the stage-2 fit object.

---

## 3. Layout

```
preserve_root/
├── datasets/ distributions/ graphs/ estimates/   # SAS — read-only to us
└── analyses/
    └── R_hazard/                     # everything we own
        ├── _quarto.yml               # type: default, output-dir: _output
        ├── R/
        │   └── study.R               # cohort gate, g_root3 derivation, comparison
        │                             # manifest. The ONLY study-specific R here;
        │                             # everything else comes from hvtiRtemplates.
        ├── qmd/
        │   ├── 01-ac-dead_pa.qmd
        │   ├── 02-hz-dead_pa.qmd
        │   └── 03-hp-dead_pa.qmd
        ├── parity/
        │   ├── 01-ac-dead_pa-parity.qmd
        │   ├── 02-hz-dead_pa-parity.qmd
        │   └── 03-hp-dead_pa-parity.qmd
        ├── docs/specs/               # this document
        ├── tests/testthat/
        └── _output/                  # gitignored
```

**One Quarto project, paired qmd.** `qmd/` does the analysis; `parity/` does the
comparison. `lv_function` used two separate projects, which was right for an 80-job
whole-study migration and is over-built for three stages. The pairing keeps the same
separation of concerns — a future job with no SAS counterpart simply has no file in
`parity/` — without a second `_quarto.yml`, a second `R/`, and cross-project sourcing.

**Read-only discipline.** Nothing under `R_hazard/` writes outside itself. Not to
`datasets/`, `distributions/`, `graphs/`, `estimates/`, nor to the SAS programs and
`.lst` files in its own parent `analyses/`. `R_hazard/` sits inside a directory full of
SAS sources, so this is a convention rather than a filesystem boundary, and is worth
stating plainly: **the R tree reads its parent, never writes to it.** A failed R run
must not be able to corrupt the reference outputs it is validating against.

### 3.1 preserve_root is the abstraction exercise

This is the **second** study. `lv_function` built the machinery; this study is where it
becomes reusable. So the machinery is generalised into `hvtiRtemplates` **as part of
this work**, and preserve_root consumes it from day one rather than copying it and
hoisting later.

*Two consumers before you abstract* is satisfied, and then some. The rule asks for
examples in hand, not for the second one to be finished. **Three are in hand**, with
more available if the interface needs them — see §3.1.1, which is the evidence base the
components are designed against. Waiting until preserve_root is done would add nothing
except a second copy to reconcile.

#### 3.1.1 The evidence base

A survey of the three studies, because an interface designed against one of them is an
accident:

| | `lv_function` | preserve_root | `resilia` |
|---|---|---|---|
| Late phase | Weibull | constant (`muc`) | **both** — 78 `weibull`, 16 `muc` |
| Fixed/free spread | one combination | one combination | **`fixm` 23×, `fixnu` 34×, `fixeta` 20×** |
| `icensor` | 1 fit, 3/1032 events | 1 fit, 5/77 events | **47 uses** |
| Conservation | `conserve` | `conserve` + one pair | **30 `conserve`, 48 `noconserve`** |
| `outhaz` datasets | present, unused | 1 in scope | **52** |
| Matched cohorts | — | — | `_match`, `_match_per`, `_match_res` |
| `hs` jobs | 0 | **1** | 0 |

Three consequences for the design:

1. **The model-spec interface must take an arbitrary fixed/free combination across both
   late-phase forms.** This spec describes preserve_root's shape (§5.2); the *package*
   component must not hard-code it. Two studies would have suggested a two-case switch;
   `resilia` shows the real space.
2. **The `outhaz` reader is first-class, not a local nicety.** 52 datasets in `resilia`
   alone. §6.1 proposed it from a single file; the corpus settles it.
3. **Interval-censoring evidence comes from `resilia`, not from here.** Its 47 uses give
   the programme real leverage. preserve_root's 5-of-77 caveat in §7.2 stands unchanged
   — a claim earned by one study does not transfer to another.

`resilia`'s matched-cohort analyses are out of scope for all current passes, recorded so
the interface is not designed in a way that excludes them.

It also matches the upstream plan, whose **stage 4 is "adopt in `R_hazard`"** —
`lv_function` is expected to retrofit onto the packaged templates. Deferring the
abstraction would leave both studies on copies with nothing to adopt.

Consumed from `hvtiRtemplates`, not copied:

| Component | Generalised from | What the study supplies |
|-----------|------------------|-------------------------|
| `study_root()` | `lv_function` verbatim — no study content in it | nothing |
| `preflight_report()` | `lv_function` verbatim | optional extra packages |
| `ac` / `hz` / `hp` job templates | `lv_function`'s `example-jobs/` | the edited arguments of one call |
| reference readers | `.lst` parsers + **new `outhaz` reader** (§6.1) | reference file paths |
| `compare_parity()`, tolerance classes, three-state outcome, headline metric | `lv_function`'s `parity.R` | a comparison manifest: which quantities, which class |
| `_quarto.yml` conventions, `.gitignore` | `lv_function` | nothing |

The split is not "generic file versus study file" but **mechanism versus manifest**.
Every reusable component takes the study's specifics as data. What survives in
`R/study.R` is the cohort gate of §4.2, the `g_root3` derivation of §7.1, and the
comparison manifest — declarations, not machinery.

Two lessons already paid for in `lv_function` come along with the code:

- `study_root()` walks up from the working directory until `datasets`,
  `distributions`, `graphs` and `analyses` all appear under one parent. The study
  resolves to `/studies/...` on the RStudio server and to a local mount point on a
  Mac, so **no literal path prefix may appear anywhere in this project.** The analysis
  will be run on the server. This function is what makes success criterion 4 —
  *"no job `.qmd` contains a study path, study title, or dataset name"* — achievable.
- `preflight_report()` checks `numDeriv`, which is only a *Suggests* of
  `TemporalHazard` and so is not pulled by `install_github()`. Its absence silently
  costs standard errors on any interval- or left-censored multiphase fit: the analytic
  multiphase Hessian declines for `status ∈ {-1, 2}` by design, the optimizer falls
  back to `numDeriv`, and with `numDeriv` missing `vcov()` returns a bare logical while
  `rcond` and `pd` come back `NA` with nothing naming the cause. **Stage 2 here is
  interval-censored, so this is a live hazard, not a historical note.**

### 3.2 There is no repository on the share

**No study folder on the share hosts git.** This is universal across the programme, not
a preserve_root quirk. `lv_function/survival` contains a `.git` directory; it is
vestigial, it should not have been created, and it is not a precedent. Nothing in this
design depends on it, and no work here writes to it.

That is a constraint on where code lives, not on reproducibility, because the
templates-and-provenance design already locates reproducibility somewhere else:

> **Criterion 1.** A filed result's sidecar names the exact `hvtiRtemplates` and
> `hvtiRutilities` versions, the R version, every loaded package version, and the
> input dataset checksum.
> **Criterion 2.** `renv::restore()` from a filed sidecar's lock reproduces that
> result's numbers.

A result is therefore reproducible from *package version + dataset checksum + renv lock
+ edited job arguments*, none of which require the study directory to be under version
control. §3.1 is what makes this true rather than aspirational: if the machinery lived
on the share, the share would need a repository.

What remains on the share is generated job `.qmd` files, their rendered output, and
`R/study.R`. **This spec lives in the `hvtiRtemplates` repository**, in `specs/`, beside
the designs that shaped the package.

## 4. Data contract

**Source:** `datasets/built.sas7bdat`, read with
`hvtiRutilities::read_clinical_data()` for SAS variable labels, then filtered to
`pr_avail == 1`.

**`%vars` is not needed, and this is established rather than assumed:**

1. `ac.dead_predim_avail.sas` has its `%vars` call **commented out** in the source.
2. `grep` over `datasets/vars.sas` finds **no definition** of `iu_dead`, `il_dead`,
   `ic_dead`, `idead` or `im_dead`. They already exist in `library.built`.
3. `hz.dead_predim_avail.sas` subsets `where pr_avail=1` *before* calling `%vars`.
   That ordering would matter if `%vars` did anything cohort-dependent. The only such
   operation is `proc standard ... replace` at `datasets/vars.sas:841`, gated behind
   `%if &missing=1`. The analysis calls bare `%vars;`, and the macro signature
   defaults to `missing=0`. So `%vars` is pure per-row transformation here.

This is a materially cleaner contract than `lv_function`'s, which had to read a
post-`%vars` dataset and carry a caveat about it.

**Do not use `datasets/built.xpt`.** Its `keep` list carries `dead deads iv_dead
iv_deads` but none of the interval-censoring variables, and it is dated 2025-05-12
against a 2026-06-09 dataset. It is stale and insufficient.

### 4.1 Dataset manifest

`built.sas7bdat` is on a mutable network share, is not under version control, and was
rewritten 2026-06-09. Nothing prevents the next SAS run from rewriting it mid-analysis.

Every stage records the manifest entry (`hvtiRutilities::verify_manifest()`) — path,
size, checksum, mtime — in its report header, and **fails loudly if it does not match
the entry recorded at the cohort gate.** A parity result is only meaningful against a
named, pinned dataset state.

This is the point at which `hvtiRutilities` earns its keep in a way `lv_function` could
not test: that study's dataset was archival, so drift detection was never exercised.

### 4.2 Cohort gate — hard stop

From `ac.dead_predim_avail.lst` and `hz.dead_predim_avail.lst`, which agree:

```
There are   291 observations available for analysis with:
                 77 events:
                       72 Uncensored
                        5 Interval Censored
                214 Right Censored Observations
                291 Total Subjects
```

**Target: N = 291, 77 events (72 uncensored + 5 interval-censored), 214 right-censored.**

Stratified by `g_root3` (preoperative root diameter):

| `g_root3` | Definition | Total | Failed | Censored |
|-----------|-----------|-------|--------|----------|
| 1 | `z0axdpr <= 40` | 112 | 27 | 85 |
| 2 | `40 < z0axdpr <= 45` | 89 | 23 | 66 |
| 3 | `z0axdpr > 45` | 90 | 27 | 63 |
| — | Total | 291 | 77 | 214 |

**This is a gate.** If the analysable cohort misses, stages 2–3 do not run. A parity
comparison on the wrong cohort produces a number that looks like an answer.

The `g_root3` cell counts are verified **before** any survival estimate is compared —
the derivation being right is a precondition for the estimates meaning anything.

### 4.3 Reference staleness — stated, not hidden

`.lst` dates against a `built.sas7bdat` last written 2026-06-09:

| Reference | Date | Relative to dataset |
|-----------|------|---------------------|
| `hz.dead_predim_avail.lst` | 2026-06-11 | **after** — contemporaneous |
| `hp.dead_predim_avail.lst` | 2026-05-06 | before |
| `ac.dead_predim_avail.lst` | 2026-05-26 | before |

Stages 1 and 3 compare against output produced from a possibly different dataset state.
The cohort counts agreeing across the May 26 `ac` run and the June 11 `hz` run
(291/77/214 both times) is **evidence** that the relevant columns did not change in
that window — it is not proof. Any stage-1 or stage-3 discrepancy must consider
reference staleness as a candidate cause before it is attributed to `TemporalHazard`.

---

## 5. Model specification — and the trap

### 5.1 The `parms` statement does not describe the fitted model

From `hz.dead_predim_avail.sas`:

```sas
proc hazard data=built conserve p outhaz=outest steepest quasi mi=200 condition=14;
     event idead;
     icensor ic_dead=il_dead;
     time iu_dead;
     parms mue=0.10465 thalf=0.0114 nu=1.6 m=0 fixm
           muc=0.03 tau=1 fixtau alpha=1 fixalpha gamma=1 fixgamma
           eta=1 weibull;
```

This declares **both** a constant late phase (`muc`) and a Weibull one (`eta ...
weibull`). The `.lst` settles which was fitted:

```
Phase      Parameter  Estimate     Std error      Z         Prob>|Z|
Early:     E2         -4.39518     0.5775521     -7.610      <.0001
           E3          0.522231    0.2992917      1.745      0.0810
           E0         -2.28023     0.2302766     -9.902      <.0001
Constant:  C0         -3.48532     0.1526932    -22.826      <.0001
```

**Four free parameters: three early, one constant. No Weibull late phase.** Specifying
`muc` selects the constant phase; the trailing `mul`/`eta`/`weibull` spec is inert.

Porting the `parms` line literally would build a six-parameter two-phase Weibull and
mismatch everything downstream. **This is the highest-value trap in the conversion**,
and the R model specification is derived from the `.lst` output block, not from the
`parms` statement.

### 5.2 Fitted quantities

Fixed: `DELTA = 0`, `M = 0`, `TAU = ALPHA = GAMMA = 1`.

Free, on the internal log scale (what the optimizer and Hessian actually see):
`E2`, `E3`, `E0`, `C0`.

Free, on the natural scale (reported separately by SAS):

| Parameter | `.lst` (7 s.f.) | `outhaz` (full precision) |
|-----------|-----------------|---------------------------|
| `THALF` | 0.01233664 | 0.012336635510161828 |
| `NU` | 1.685784 | 1.6857843769467957 |
| `MUE` | 0.1022604 | — (derived) |
| `MUC` | 0.0306439 | — (derived) |
| `E0` | −2.28023 | −2.28023296061588 |
| `C0` | −3.48532 | −3.4853216662142557 |

### 5.3 Convergence and conservation

```
Log likelihood = -239.194
Optimization terminated after 5 iterations and 53 function evaluations
Normal exit: Convergence attained
Log base 10 of condition code = 1.225803
Number of events conserved = 77
Conservation of events: Invoked at each iteration
If only one scaling parameter, estimation is in closed form.
```

That last line matters: with a single scaling parameter, CoE takes its **closed-form
branch**. `lv_function`'s six-parameter fit never exercised it.

---

## 6. Parity harness — built in `hvtiRtemplates`

Three responsibilities, kept separate: read the reference, compare, report.
All three are package mechanism (§3.1); the study supplies a manifest naming
which quantities to compare and in which tolerance class.

### 6.1 The reference is not only the `.lst`

`estimates/hzdead_pa.sas7bdat` is the `outhaz` dataset SAS wrote alongside the printed
output. It carries, at full double precision:

- `_EST_` — converged parameter estimates
- `_STATUS_` — free (`1`) vs fixed (`0`) per parameter
- the **complete variance-covariance matrix**, indexed by parameter name
  (`THALF × THALF = 0.33356641372425322`, matching the `.lst`'s printed
  `E2 × E2 = 0.3335664`)
- model-structure flags (`G1FLAG`, `FIXDEL0`, `FIXMNU1`, `G3FLAG`, `FIXGE2`, `FIXGAE2`)

**`lv_function`'s harness reads `.lst` only.** Using `outhaz` is new here, and it
changes the tolerance argument rather than merely tightening a number (§6.3).

Reference precedence:

1. `estimates/*.sas7bdat` where the quantity exists there — full precision
2. `.lst` otherwise — notably the **log-likelihood**, which `outhaz` does not store,
   and every life-table and nomogram quantity

Both are read for quantities present in both, and **a disagreement between the two SAS
references is itself a reportable finding** — it means the `.lst` and the estimate
dataset came from different runs, which is exactly the staleness risk of §4.3.

### 6.2 Parsing the `.lst`

Parsers come from the installed package, never vendored:

```r
source(system.file("sas-parity", "helper-sas-parity.R", package = "TemporalHazard"))
```

with `$TEMPORAL_HAZARD_SRC/tests/testthat/helper-sas-parity.R` as a fallback for a
machine running an older install beside a checkout, erroring with **both paths named**
if neither resolves.

**Capability is probed, never inferred from a version number.** Upstream renumbering
means `main` and `dev` both report 1.2.0 — one with the parsers, one without. The
preflight probes `system.file()` directly and records the version as provenance only.

**Do not vendor a copy into this study.** A forked parser is how a validated parser
rots, and with two copies a divergence shows up as *both sides passing*.

**Expect parser work.** Two gaps were already found and fixed upstream during
`lv_function` (nested event-count breakdown; nomogram header lacking a `MONTHS`
column). These `.lst` files are 2026-vintage and differently shaped again. A parser
failure here is a **finding about parser generality**, not an obstacle, and any fix is
contributed back to `TemporalHazard` rather than forked into this study.

### 6.3 Tolerance policy

**For `.lst`-sourced quantities, the reference is an interval, not a number.** When SAS
prints `Log likelihood = -239.194`, the value that produced it lies in
`[-239.1945, -239.1935)`. Comparing more precisely than the reference carries is a
malformed question, so half a unit in the last printed place is a floor that is
*derived*, not tuned.

**For `outhaz`-sourced quantities that floor does not apply** — the value is stored at
machine precision. What remains is that R and SAS run different optimizers on the same
likelihood (R: multi-start → Nelder-Mead warmup → BFGS with analytic gradient; SAS:
`steepest quasi`, single-start). Two correct implementations converge to different
points within their own tolerances. So the binding constraint moves from *printing* to
*convergence*, and the tolerance is set by the noisiest step in each quantity's chain.

Rule form: `abs_diff <= atol + rtol * |sas|`.

| Class | Quantity | Source | `rtol` | `atol` |
|-------|----------|--------|--------|--------|
| deterministic | counts, n-at-risk, events, `proc freq` cells | `.lst` | 0 | 0 |
| deterministic | survival, cumhaz, Greenwood SE | `.lst` | 0 | half-ULP of print |
| optimizer | log-likelihood | `.lst` | 0 | 0.0005 |
| optimizer | MLEs (`E2 E3 E0 C0`, `THALF NU`) | `outhaz` | 1e-6 | 1e-9 |
| optimizer | MLEs (`MUE MUC`, derived) | `.lst` | 1e-3 | 1e-6 |
| curvature | variance-covariance matrix | `outhaz` | 1e-4 | 1e-9 |
| curvature | standard errors, confidence limits | `.lst` | 1e-2 | 1e-6 |

The `outhaz` rows are three to six orders tighter than the `.lst` rows for the same
quantities. **If the tight tolerances prove unachievable, that is a result, not a
provocation to loosen them** — it localises the disagreement to the optimizer, and the
`.lst`-precision comparison still runs alongside as the headline claim.

**The LL / MLE asymmetry is deliberate and diagnostic.** Near an optimum the
log-likelihood is quadratic, so a parameter error of ε costs LL only O(ε²). The two
disagreeing in opposite directions tells you which problem you have:

| LL | Parameters | Interpretation |
|----|-----------|----------------|
| agrees | agree | parity |
| agrees tightly | one differs | flat direction / weak identifiability — not an error |
| differs materially | agree | **structural** — different data, likelihood, or censoring |
| R higher | differ | **R found a better optimum** |

With `E3` at `Prob>|Z| = 0.0810`, a flat direction in `NU` is a plausible and
non-alarming outcome.

### 6.4 Comparison and reporting

`compare_parity(r, sas, quantity, tol, ...)` returns a tidy frame with columns
`quantity`, `r`, `sas`, `source`, `abs_diff`, `rel_diff`, `tol`, `outcome`.

**Fail-loud contract.** `compare_parity()` **errors** — does not warn, does not skip —
when a requested quantity is absent on either side. A comparison that cannot fail is
worse than no comparison. This project has been bitten by exactly this: weighted
single-distribution fit tests in `TemporalHazard` passed vacuously for a full release
cycle because an unfitted branch compared `NULL` against `NA`.

**Three-state outcome:** `PASS` / `DIFFERS` / `R_BETTER`, where `R_BETTER` fires only
when R's log-likelihood exceeds SAS's beyond tolerance. R's multi-start regularly beats
a single-start C optimizer; recording that as `FAIL` would train us to distrust a real
improvement.

**Headline metric**, above each stage's table:

> *Across N compared quantities, the largest relative discrepancy was X.*

This, not the badge, is the reviewer-facing claim. It is falsifiable, independent of
whatever thresholds were chosen, and does not invite "what were your tolerances and did
you tune them?" A max relative discrepancy of exactly `0` across hundreds of quantities
is **not a triumph — it is a signal that nothing was really compared**, and the report
flags it as such.

---

## 7. Stage designs

### 7.1 `01-ac-dead_pa` — actuarial

Two `%kaplan` calls on `iv_dead` / `dead` (right-censored):

1. overall
2. stratified by `g_root3`

`g_root3` is derived inline in the SAS and ported explicitly:

```
g_root3 = .
if z0axdpr <= 40            then 1
if z0axdpr >  40 and <= 45  then 2
if z0axdpr >  45            then 3
```

Note this initialises to missing and assigns in ascending order — unlike the
`g_root1`/`g_root2` dummy pair in `hz.dead_predim_avail.sas`, which uses the same
cutpoints in a different shape. Port the form the stage actually uses.

The `.lst` also carries `proc univariate` on `iv_dead` overall and among survivors, and
a `proc freq` on `dead`. These are free additional deterministic checks.

**Compared:** `g_root3` cell counts first, then n-at-risk, events, survival estimate,
Greenwood SE, per stratum and time point, via `hzr_kaplan()`.

**Expected:** PASS at print precision. What this stage really tests is the data
contract, the cohort reconciliation, the parser against a 2026-vintage `.lst`, and the
render. The survival numbers are the least interesting part.

### 7.2 `02-hz-dead_pa` — hazard fit

The substance. Four free parameters, early + constant, CoE on, interval-censored.

**Three fits, deliberately:**

1. **Deterministic** — initialised from the SAS `parms` values. This is the number that
   goes in the parity table.
2. **Independent** — multi-start from rough starts (`n_starts = 5`, seeded with
   `.Random.seed` save/restore). Answers *"is SAS at the optimum"*, which is a different
   question from *"does R agree with SAS"*. Reported alongside, never as the parity
   number.
3. **`noconserve`** — same data, same model, one flag changed, compared against the
   second fit block in the same `.lst` (LL = −239.019).

Fit 3 is nearly free and is the most controlled test of the conservation path available
anywhere in the three studies: identical data, identical model, one flag. `lv_function`
only got such a pair as an incidental bonus in a deferred stage.

**Compared:** log-likelihood (−239.194 conserve, −239.019 noconserve); `E2 E3 E0 C0`
and their standard errors; natural-scale `THALF NU MUE MUC`; the full 4×4
variance-covariance matrix; `Number of events conserved = 77`.

**Risk — interval censoring has thin leverage.** 5 of 77 events are interval-censored.
The branch is genuinely hit, so this is a real check, but an error confined to it would
move the log-likelihood by an amount that could hide inside optimizer tolerance. Report
it as *"5 interval-censored events agreed"*, **not** as *"interval censoring verified
against SAS"*. Stronger evidence needs a fixture built so interval censoring carries
real weight, not a re-reading of this one.

**Risk — N = 291 with 4 parameters.** Small-sample Hessian conditioning is untested
territory for this package; `lv_function` had 3049. `Log base 10 of condition code =
1.225803` says SAS found it well conditioned, which is a useful reference point.
`rcond` and `pd` are reported whatever they come out as.

### 7.3 `03-hp-dead_pa` — nomogram and figures

`predict()` over the two grids the SAS builds:

- **curve grid** — 1000 points log-spaced, `exp(seq(-5, log(10), length.out = 1000))`
- **digital nomogram** — `30/365.2425, 0.25, 0.5, 1:10`

**Two settings that must be right or everything mismatches:**

- `%hazplot` / `%kaplan` default `CLEVEL = 0.68268948` — **one standard deviation, not
  95%.** `predict(level = )` must be set accordingly.
- Survival confidence limits use a **logit** transform to match `HAZPRED`. R's default
  is cloglog, the `survfit` standard. Decoded from `hzp_calc_srv_CL.c` upstream.

**Compared:** `_surviv`, `_hazard`, and `_cllsurv _clusurv _cllhaz _cluhaz`, on the
digital grid; plus the overlaid `%kaplan` n-at-risk values (243, 220, 158, 52) that the
SAS uses to place confidence bars.

**Figures:** rebuilt with `hvtiPlotR` against the existing PDFs in `graphs/`. These are
a **visual** check; the numerical check is the nomogram table.

**Dependency:** consumes the stage-2 fit. If stage 2 fails parity, stage 3 still runs
and its result is reported as conditional on the stage-2 discrepancy.

---

## 8. Out of scope — recorded so the deferral is informed

### 8.1 `hs.uslife` → `hvtiRlifetables`

`graphs/hs.uslife.sas` calls:

```sas
%usmatchd(in=built, out=usmatchd, table='SEXRACE', id=ccfid, max=10,
          ninc=149.9, individl=1);
```

over `age`, `male`, and `other` (non-white), writing `est.uslife` — 6 MB of per-patient
matched predictions, a far richer reference than its 8 KB `.lst`.

This is the **only `hs` reference across the three prototype studies**, and
`hvtiRlifetables` does not exist as an installed package. Deferred because it is not a
porting job: it requires sourcing US decennial life tables by sex and race and shipping
them as package data, with its own provenance and licensing questions. It gets its own
pass once `ac`/`hz`/`hp` land.

Note `hp.dead_predim_avail.sas` contains an `est.uslife` overlay block, but it sits
inside `%macro skkip` and is never invoked — so stage 3 does not depend on this.

### 8.2 Other chains in this study

`ac`/`hz`/`hp` variants for `_prt45` and `_prt3grp`; the full-cohort `dead` chain
(N=389, `.lst` from 2024-07 against a 2026-06 dataset — stale); the
`root-reint_first_predim_avail` chain and its `_endoexcl` variant; the repeated-events
reintervention chain (likely a `TemporalHazard` capability gap); and the multivariable
and bagging jobs (`hm.dead`, `bh.dead`).

---

## 9. Success criteria

| # | Criterion |
|---|-----------|
| 1 | Cohort gate: 291 / 77 events (72 + 5) / 214 censored — **exact**; `g_root3` cells 112 / 89 / 90 — **exact** |
| 2 | Stage 1 life-table quantities match `.lst` to print precision |
| 3 | Stage 2 LL matches −239.194 to printed precision; `E2 E3 E0 C0` and `THALF NU` match `outhaz` within optimizer tolerance |
| 4 | Stage 2 4×4 vcov matches `outhaz` within curvature tolerance |
| 5 | `noconserve` refit reproduces −239.019 to printed precision |
| 6 | Stage 3 nomogram survival/hazard and confidence limits match to ~1e-4 |
| 7 | Every stage reports its max relative discrepancy — **and it is non-zero** |
| 8 | `.lst` and `outhaz` agree with each other wherever both carry a quantity |

**Failure handling is part of the deliverable.** Any stage that fails is diagnosed to a
named cause — pipeline bug, parser bug, package gap, or reference staleness (§4.3) —
**before anything is adjusted**. A gap is documented as a gap. Numbers are never forced
to match by tuning tolerances or starting values.

This follows the precedent of the `hm.death.AVC` stepwise fixture, where R and SAS were
shown to diverge *by construction* and the honest documented gap was worth more than a
brittle forced parity.

---

## 10. Sequencing

preserve_root is the second study, so the abstraction happens **with** this work, not
after it (§3.1). There is no "study first, package second" phase ordering.

**One track.** Generalise each component out of `lv_function` against this study's
requirements, land it in `hvtiRtemplates`, and have preserve_root consume it
immediately. The study is the proof the abstraction holds: a component that cannot
serve both studies is not finished.

Rough order, driven by dependency rather than by phase:

1. `study_root()`, `preflight_report()`, `_quarto.yml` conventions, `.gitignore` —
   no study content in them, nothing to negotiate.
2. Reference readers, including the **new `outhaz` reader** (§6.1). Designed against
   both studies' reference shapes from the start; this is the component that would
   have been mis-shaped by writing it as study code first.
3. `compare_parity()`, the tolerance classes of §6.3, the three-state outcome and the
   headline metric — mechanism in the package, manifest in the study.
4. The `ac` / `hz` / `hp` job templates, generalised so the study contributes only the
   arguments of one call (criterion 5) and no study path, title or dataset name
   (criterion 4).

Then **upstream stage 4**: retrofit `lv_function` onto the packaged components. Two
studies on one implementation is the actual success condition; two studies on two
copies is the failure this exercise exists to prevent.

Patch bump `1.0.0 → 1.0.1`. `template_list()` already returns a correctly shaped 0-row
frame (`name`, `prefix`, `folder`, `file`); the plumbing exists, the files do not.

**A note on copying versus forking.** Copying a *template* is its intended use — the
`# EDIT:` markers say so. Copying a *parser* or a comparison harness is the fork-rot
failure mode §6.2 forbids, where a divergence shows up as both sides passing. The
distinction is why templates can be instantiated per study while the harness must have
exactly one implementation.

**Branch and PR discipline applies to this repository**, which is a real git repository
— not to the study tree, which is not one. No commits are made on the share.
