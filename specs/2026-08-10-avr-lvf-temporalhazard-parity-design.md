# AVR / LV-function survival — TemporalHazard parity pipeline

> **Migrated 2026-08-18** from `/Volumes/qhsstudies/cardiac/valves/aortic/replacement/pericardial/lv_function/survival/analyses/R_parity/docs/specs/2026-08-10-avr-lvf-temporalhazard-parity-design.md`.
> Cross-references to the other migrated documents have been repointed to their
> paths in this repository; the text is otherwise unchanged. Study folders on the
> share do not host git repositories, so the design record lives with the package
> that owns the migration programme. `specs/artifacts/README.md` records what
> moved and from where.

**Date:** 2026-08-10
**Status:** Approved design; stages 1–3 in scope for the first pass
**Study:** `/studies/cardiac/valves/aortic/replacement/pericardial/lv_function/survival`
**Paper:** Mihaljevic T, Nowicki ER, Rajeswaran J, Blackstone EH, Lagazzi L, Thomas J,
Lytle BW, Cosgrove DM. *Survival after valve replacement for aortic stenosis:
implications for decision making.* J Thorac Cardiovasc Surg. 2008;135(6):1270-9.
doi:10.1016/j.jtcvs.2007.12.042
**Requested by:** Rajeswaran (email, reproduced in `qmd/index.qmd`)

---

## 1. Purpose

Two goals, deliberately coupled:

1. **Parity validation** — reproduce this study's SAS `PROC HAZARD` results in R with
   `TemporalHazard`, and cross-check every estimate against the committed `.lst` files.
2. **Pipeline shakedown** — this is the first production exercise of the R analysis
   pipeline that will replace SAS study programs. The scaffolding built here is the
   template the next study inherits.

The second goal is why the easy stages are in scope at all. A stage that reproduces
trivially still exercises the data contract, the `.lst` parser, the comparison harness,
and the report render.

**Forcing function:** the institutional SAS license expires 2026-09-29. This work is the
first end-to-end demonstration that a Blackstone-lineage hazard analysis can be carried
out without SAS.

---

## 2. Job flow

Rajeswaran's flow, with the reference artefacts that exist on disk today:

| # | Stage | SAS program | Reference | R target |
|---|-------|-------------|-----------|----------|
| 1 | Actuarial | `distributions/ac.dead_JR.sas` | `.lst` ✅ | `hzr_kaplan()` |
| 2 | Temporal hazard fit | `distributions/hz.dead_JR.sas` | `.lst` ✅ | `hazard()` |
| 3 | Hazard figure | `graphs/hp.dead_JR.sas` | `.lst` + 3 PDFs ✅ | `predict.hazard()` |
| 4 | Bagging | `analyses/bh.dead_s3_JR.sas` | **none** | `hzr_bootstrap()` |
| 5 | Multivariable | `analyses/hm.dead_s3_JR.sas` | `.lst` ✅ | `hazard()` + `hzr_stepwise()` |

**Stages 1–3 are in scope for this pass.** Stages 4–5 are deferred pending review of the
stage 1–3 outcome; their design constraints are recorded in §8 so the deferral is
informed rather than open-ended.

### 2.1 Model structure across stages

The stages do **not** share a likelihood. This is the single most important structural
fact in this spec:

| Stage | Time variables | Censoring | Free params | CoE |
|-------|----------------|-----------|-------------|-----|
| 1 `ac` | `iv_dead`, `dead` | right | — (no fit) | — |
| 2 `hz` | `iu_dead`, `il_dead`, `ic_dead`, `idead` | **interval** | **6** | **on** (`conserve`) |
| 3 `hp` | `im_dead` (overlay), time grid | right (overlay only) | — (reuses stage 2 fit) | — |
| 5 `hm` | `iu_dead`, `il_dead`, `ic_dead`, `idead` | interval | 6 + 40 covariates | **off** (`noconserve`) |

A stage-2 parity result therefore does **not** transfer to stage 5, and a stage-1 pass
says nothing about the fitting path at all.

### 2.2 Stage 2 model specification (from `hz.dead_JR.sas`)

```sas
proc hazard data=built conserve p outhaz=outest steepest quasi mi=200 condition=14;
     event idead;
     icensor ic_dead=il_dead;
     time iu_dead;
     parms mue=0.08620027 thalf=0.1573284 nu=0.928347 m=1.116333
           mul=0.01358171 tau=1 fixtau alpha=1 fixalpha gamma=1 fixgamma
           eta=1.687817 weibull;
```

Two phases, no covariates. Free: `mue`, `thalf`, `nu`, `m` (early); `mul`, `eta` (late,
Weibull). Fixed: `tau`, `alpha`, `gamma` = 1. Output saved as `est.hzdead_jr`
(`type=haz`), consumed by stage 3.

---

## 3. Layout

All R work lives under `analyses/R_parity/`, inside the existing SAS `analyses/`
directory. It is the only R-owned subtree in the study.

```
survival/
├── datasets/                      # SAS datasets — read-only to us
├── distributions/                 # SAS: ac.dead_JR, hz.dead_JR — read-only to us
├── graphs/                        # SAS: hp.dead_JR — read-only to us
├── estimates/                     # SAS .haz estimate datasets — read-only to us
└── analyses/                      # SAS: bh/hm.dead_s3_JR — read-only to us
    └── R_parity/                # <- everything we own
        ├── _quarto.yml
        ├── R/
        │   ├── read_built.R       # haven::read_sas + cohort reconciliation
        │   └── parity.R           # .lst parsing + compare_parity()
        ├── qmd/
        │   ├── index.qmd          # study framing, Rajes's email, stage table
        │   ├── 01-ac-dead.qmd
        │   ├── 02-hz-dead.qmd
        │   └── 03-hp-dead.qmd
        ├── docs/specs/            # design docs; this one now in hvtiRtemplates
        └── _output/               # rendered report (gitignored)
```

**Read-only discipline.** Nothing under `analyses/R_parity/` writes anywhere outside
itself — not to `datasets/`, `distributions/`, `graphs/`, `estimates/`, nor to the SAS
programs and `.lst` files in its own parent `analyses/`. All derived R artefacts stay
within `R_parity/`. This keeps the SAS study reproducible from its own tree and means
a failed R run can never corrupt the reference outputs we are validating against.

Because `R_parity/` now sits *inside* a directory full of SAS sources and outputs,
this discipline is a convention rather than a filesystem boundary, so it is worth
stating plainly: **the R tree reads its parent, never writes to it.**

---

## 4. Data contract

**Source:** `datasets/built080426.sas7bdat`, read with
`hvtiRutilities::read_clinical_data()`.

**Why `hvtiRutilities` rather than bare `haven::read_sas()`:** it carries SAS variable
labels through into the R object. The `.lst` files print labels, not just variable names
(e.g. `SURG_NUM  Total Number Cardiac Operations`), so label-aware reading is what lets
the parity tables and the report name quantities the same way SAS did, without
re-keying 40 labels by hand. Three of its exports do real work in scope:

| Function | Use |
|----------|-----|
| `read_clinical_data()` | labelled read of the `.sas7bdat` |
| `compare_datasets()` | the `built103006` vs `built080426` check below |
| `verify_manifest()` / `update_manifest()` | pin dataset state — see §4.1 |

`hvtiRtables` is **not** a dependency of this pass; it becomes one at stage 5, where
`hv_man_table_jtcvs()` renders Table 1 for a JTCVS manuscript. It has no caller in
stages 1–3.

Rajeswaran's email states this dataset is `built103006` already passed through
`vars.sas`. It was rewritten 2026-08-04 20:29 by the `hm.dead_s3_JR` run
(`data library.built080426; set built;` after `%vars(missing=1, impute=1)`).

**Why not reimplement `vars.sas`:** it is ~48 KB of SAS macro performing derivation,
missing-value flagging, and imputation. Porting it is a project in itself and is not
what this pass is testing. Reading the post-`vars` dataset isolates the question we
actually care about — does `TemporalHazard` reproduce `PROC HAZARD`.

**Caveat that must be checked, not assumed:** stages 1–3's SAS programs read
`library.built103006` *without* calling `%vars`. Using `built080426` for those stages is
only valid if the variables they use (`iv_dead`, `dead`, `iu_dead`, `il_dead`,
`ic_dead`, `idead`, `im_dead`, `female`, `hx_htn`, `z_value`, `plvmassi`) are unmodified
by `vars.sas`. `01-ac-dead.qmd` asserts this via
`hvtiRutilities::compare_datasets()` on **both** datasets, restricted to those columns.
If they differ, stages 1–3 switch to `built103006` and the discrepancy is reported.

### 4.1 Dataset manifest

The `.sas7bdat` files live on a mutable network share and are not under version control.
`built080426.sas7bdat` was rewritten 2026-08-04 20:29 by a SAS run; nothing prevents the
next run from rewriting it again mid-analysis.

Every stage therefore records the dataset's manifest entry
(`hvtiRutilities::verify_manifest()`) — path, size, checksum, mtime — in its report
header, and **fails loudly if the manifest does not match the one recorded at the cohort
gate.** A parity result is only meaningful against a named, pinned dataset state.

### 4.2 Cohort — RESOLVED

The apparent conflict between 3049, 3316 and 3687 is resolved. Both
`hz.dead_JR.lst` and `hm.dead_s3_JR.lst` print, identically:

```
There are  3049 observations available for analysis with:
                 1032 events:
                 2017 Right Censored Observations
```

This agrees with Rajeswaran's email and with the paper's Methods ("3049 patients with
aortic stenosis who underwent native AVR with a single type of bioprosthesis").

**`n=3316` is a stale `title2` string** carried in the SAS source; `n=3687` is a stale
header comment. Neither is a cohort definition. They appear on every page of every
`.lst` and should be ignored.

**Target cohort: N = 3049, 1032 events, 2017 right-censored.**

`01-ac-dead.qmd` still asserts this rather than assuming it — it reports total rows,
rows analysable for each time/event pair, and event counts, and checks them against the
counts printed in each `.lst`.

**This remains a gate.** If the analysable cohort does not come to 3049/1032/2017,
stages 2–3 do not run. A parity comparison on the wrong cohort produces a number that
looks like an answer.

### 4.3 Censoring breakdown — RESOLVED, and interval censoring *is* exercised

An earlier draft of this spec read the counts as `3049 = 1032 events + 2017 right
censored` and worried that the `icensor` statement might be declared but inert. The
full block, identical in `hz.dead_JR.lst` and `hm.dead_s3_JR.lst`, settles it:

```
There are  3049 observations available for analysis with:
                     1032 events:
                           1029 Uncensored
                              3 Interval Censored
                     2017 Right Censored Observations
                     3049 Total Subjects
```

**Three of the 1032 events are interval-censored.** So stages 2 and 5 genuinely hit the
interval-censoring likelihood branch — it is not merely declared.

**But calibrate how much that proves.** Three records out of 3049 is very little
leverage: an error confined to the interval branch would move the log-likelihood by an
amount that could hide inside optimizer tolerance. So stage 2 is the *first ever* SAS
cross-check of the interval path (an open gap in `DEVELOPMENT-PLAN.md` §7c), and a pass
is real but weak evidence. Do not report it as "interval censoring verified against
SAS" — report it as what it is: 3 interval-censored events agreed.

If stronger evidence is wanted later, the honest route is a fixture built to have
interval censoring carry real weight, not a re-reading of this one.

---

## 5. Parity harness (`R/parity.R`)

The reusable core. Two responsibilities, kept separate.

### 5.1 Parsing

**Reuse `TemporalHazard`'s existing parsers rather than writing new ones.** The package
ships validated `.lst` parsers in `tests/testthat/helper-sas-parity.R`
(`.hzr_parse_sas_lst()`, `.hzr_parse_sas_lifetable()`, `.hzr_parse_sas_nomogram()`),
built across 10 in-scope fits and hardened through PRs #65–#79.

**Access — resolved upstream 2026-08-10.** Two earlier drafts of this section were wrong,
and the history is worth keeping because it explains the current shape.

*Draft 1* said the parsers are reachable via `TemporalHazard:::`. They were not — the
namespace holds only `.hzr_parse_formula`, `.hzr_parse_hazard_output` and
`.hzr_parse_keyvals`, none of which parse `.lst` files.

*Draft 2* said they exist only in the source repo, so `parse_lst()` must `sys.source()`
them from a checkout located by `TEMPORAL_HAZARD_SRC`. That was true at the time: they
lived in `tests/testthat/helper-sas-parity.R`, and `R CMD INSTALL` skips `tests/` unless
`--install-tests` is passed.

**That is now fixed upstream.** [temporal_hazard#108](https://github.com/ehrlinger/temporal_hazard/pull/108)
(merged into `dev`) moved the parsers to
`inst/sas-parity/helper-sas-parity.R` — installed as `sas-parity/helper-sas-parity.R`,
since `R CMD INSTALL` strips the `inst/` prefix. Everything under `inst/` ships
unconditionally, so they now reach any installed package:

```r
source(system.file("sas-parity", "helper-sas-parity.R", package = "TemporalHazard"))
```

`parse_lst()` therefore resolves in this order:

1. `system.file("sas-parity", "helper-sas-parity.R", package = "TemporalHazard")` —
   the normal route, requires only an installed package
2. `$TEMPORAL_HAZARD_SRC/tests/testthat/helper-sas-parity.R` — fallback for a machine
   running an older install alongside a checkout

and errors with both paths named if neither resolves. It records the `TemporalHazard`
version and which route succeeded in the report header, because "the parsers were
reachable" and "the parsers came from the version we think" are different claims.

**Do not vendor a copy into this study.** A forked parser is how a validated parser
rots — and with two copies, a divergence shows up as both sides passing.

**Capability, not version.** Whether the parsers are reachable is settled by probing
`system.file()`, never by a version floor. Upstream renumbering (2.0.0 → 1.2.0) means
two different packages both claim 1.2.0 — `main`’s without the parsers and `dev`’s with
them — until `dev` merges to `main`. No version number separates them. The preflight
(§9.2) probes directly and reports the version as provenance only.

**Expect parser work — and two gaps are already confirmed.** These `.lst` files date from
2006–2009 and are older than the AVC/KUL captures the parsers were built against. Known
hazards from prior parity work: CRLF line endings, form-feed page breaks, and "Non-ISO
extended-ASCII" classification that silently zeroes `grep -c` without `-a`.

A smoke test of `.hzr_parse_sas_lst()` and `.hzr_parse_sas_nomogram()` against
`hz.dead_JR.lst` (2026-08-10) found the fit block parses correctly — log-likelihood
−3659.01, `n_obs` 3049, matching the cohort gate — but two extractors do not:

| Gap | Symptom | Cause |
|-----|---------|-------|
| `n_events` | returns `NA` | The count block nests `1029 Uncensored` / `3 Interval Censored` under `1032 events:`. The parser's `.hzr_extract_obs_counts()` does not expect the sub-breakdown (see §4.3). |
| nomogram | returns 0 rows | This `.lst` prints `Obs YEARS _SURVIV _CLLSURV _CLUSURV _HAZARD _CLLHAZ _CLUHAZ` — **no `MONTHS` column**. `.hzr_parse_sas_nomogram()` requires the header regex `YEARS\s+MONTHS\s+_SURVIV`. |

Both are genuine findings about parser generality, not obstacles: the AVC fixtures
happen to print a `MONTHS` column and a flat count block, so neither shape was ever
exercised. **Both fixes belong upstream in `temporal_hazard`**, not in this study.

Note the nomogram's first row already cross-checks against the paper: `YEARS 0.0821`
(= 30/365.2425) with `_SURVIV 0.97106` → 97%, matching the published 30-day survival
(§5.3).

A parser failure here is a **finding about the parser's generality**, not an obstacle.
Any fix is contributed back to `TemporalHazard` rather than forked into this study.

### 5.2 Comparison

`compare_parity(r, sas, quantity, tol, ...)` returns a tidy frame:

| column | meaning |
|--------|---------|
| `quantity` | name, e.g. `"log_likelihood"`, `"mue"`, `"surv_5yr"` |
| `r` | value from `TemporalHazard` |
| `sas` | value parsed from `.lst` |
| `abs_diff`, `rel_diff` | differences |
| `tol` | tolerance applied |
| `pass` | logical |

Rendered as a table in each `.qmd`, reduced to one PASS/FAIL badge per stage.

**Fail-loud contract.** `compare_parity()` **errors** — does not warn, does not skip —
when a requested quantity is absent on either side. A comparison that cannot fail is
worse than no comparison. This project has been bitten by exactly this before: the
weighted single-distribution fit tests in `TemporalHazard` passed vacuously for a full
release cycle because an unfitted branch compared `NULL` against `NA`.

### 5.2.1 Tolerance policy — DECIDED

**Framing: the `.lst` does not contain numbers, it contains intervals.** When SAS prints
`Log likelihood = -3363.58`, the value that produced it lies in `[-3363.585, -3363.575)`.
Comparing to more precision than the reference carries is a malformed question. The
comparison asks: *does R's value fall inside the box the printout defines?*

Half a unit in the last printed place is therefore a **floor** that is derived, not
tuned. But a second source of disagreement sits underneath it: R and SAS run different
optimizers on the same likelihood (R: multi-start → Nelder-Mead warmup → BFGS with
analytic gradient; SAS: `steepest quasi`, single-start). Two correct implementations
converge to different points within their own tolerances.

**Tolerance is therefore set by the noisiest step in each quantity's computation chain,
which differs by quantity.** Three classes:

| Class | What limits agreement | Quantities |
|-------|----------------------|------------|
| `deterministic` | print precision only — no optimizer involved | counts, n-at-risk, events, `proc freq` cells, KM/NA life tables, Greenwood SE |
| `optimizer` | convergence tolerance | log-likelihood, MLEs |
| `curvature` | numerical/analytic Hessian, CoE reconciliation | standard errors, confidence limits |

**Rule form:** `abs_diff <= atol + rtol * |sas|` — the `all.equal()` / `numpy.isclose`
shape, so `atol` covers near-zero and `rtol` covers scale.

| Class | Quantity | `rtol` | `atol` | Rationale |
|-------|----------|--------|--------|-----------|
| deterministic | counts, n-at-risk, events | 0 | 0 | exact, or it is a bug |
| deterministic | survival, cumhaz, Greenwood SE | 0 | half-ULP of print | reference is an interval |
| optimizer | log-likelihood | 0 | half-ULP of print (0.005) | LL is well-determined at the optimum |
| optimizer | MLEs | 1e-3 | 1e-6 | different optimizers, flat directions |
| curvature | standard errors | 1e-2 | 1e-6 | Hessian on both sides |
| curvature | confidence limits | 1e-2 | 1e-6 | inherits SE |

**The asymmetry between LL and MLEs is deliberate and diagnostic.** Near an optimum the
log-likelihood is quadratic, so a parameter error of ε costs LL only O(ε²). LL should
therefore agree far more tightly than parameters do, and the two disagreeing in opposite
directions tells you *which* problem you have:

| LL | Parameters | Interpretation |
|----|-----------|----------------|
| agrees | agree | parity |
| agrees tightly | one differs by ~5% | flat direction / weak identifiability — **not an error**; expected here, SAS itself needed `condition=14` |
| differs by ~10 | agree | **structural problem** — different data, likelihood, or censoring handling |
| R higher | differ | **R found a better optimum** |

**Three-state outcome, not boolean.** `PASS` / `DIFFERS` / `R_BETTER`, where `R_BETTER`
fires only when R's log-likelihood exceeds SAS's by more than tolerance. R's multi-start
regularly beats a single-start C optimizer; recording that as `FAIL` would train us to
distrust a real improvement.

### 5.2.2 Headline metric

Each stage reports, above its parity table:

> *"Across N compared quantities, the largest relative discrepancy was X."*

**This, not the PASS badge, is the reviewer-facing claim.** It is falsifiable,
independent of whatever thresholds were chosen, and does not invite "what were your
tolerances and did you tune them?" The thresholds still decide what stops the pipeline;
the max-discrepancy is the evidence.

It also guards the failure mode this project has hit before: a max relative discrepancy
of exactly `0` across hundreds of quantities is not a triumph, it is a signal that
nothing was really compared.

### 5.3 The published paper as a third reference

The `.lst` files are the parity target. The published paper is an independent third
check, and it is unusually well matched to stages 1–3.

**Published non-risk-adjusted survival** (Results, Overall Survival):

| Time | 30 days | 6 months | 1 year | 5 years | 10 years |
|------|---------|----------|--------|---------|----------|
| Survival | 97% | 93% | 91% | 75% | 47% |

These land on the *same grid* as the stage-2 digital nomogram
(`30/365.2425, 3/12, 6/12, 1 to 10 by 1`) — so stages 1–3 can be checked against
published values without any additional work.

**Published methods confirm two settings this spec already assumed:**

- *"Uncertainty is expressed by 68% confidence limits equivalent to ±1 standard error"*
  — confirms `CLEVEL = 0.68268948`, not 95%.
- *"we assumed that sporadic missing values ... were missing at random and used mean
  value imputation; we incorporated missing-value indicator variables"* — confirms
  `%vars(missing=1, impute=1)` and explains the `ms_*` variables in the models.

**Important limit on the paper as a reference.** The published Table 1 coefficients are
close to, but not equal to, the `parms` starting values in `hm.dead_s3_JR.sas` (e.g.
early hypertension: 0.51 published vs 0.5749728 in `parms`; insulin-treated diabetes
0.53 vs 0.4499251). The `parms` values are starting values carried over from an earlier
converged run, and the 2026-08-04 rerun is not necessarily the 2007 published fit.

**The parity target is the `.lst` converged estimates, not the paper.** The paper is a
sanity check on magnitude and sign; a disagreement with it is a provenance question
about which run produced the publication, not a `TemporalHazard` defect.

---

## 6. Stage designs

### 6.1 `01-ac-dead.qmd` — actuarial

Seven `%kaplan` calls in `ac.dead_JR.sas`:

1. overall
2. stratified by `female`
3. stratified by `hx_htn`
4–7. stratified by `z_cat`, separately within each of the four `lvm_cat` strata

`z_cat` and `lvm_cat` are derived inline in the SAS and must be ported explicitly:

```
z_cat   = 4; if z_value  <    0 then 3; if z_value  < -0.6 then 2; if z_value < -1.25 then 1
lvm_cat = 4; if plvmassi < 180 then 3; if plvmassi <  150 then 2; if plvmassi <  100 then 1
```

Note these are cumulative overwrites in SAS order — the R port must reproduce the
ordering, not just the cutpoints. The `proc freq` cell counts in the `.lst` are the
check that the derivation is right, and they are verified **before** any survival
estimate is compared.

**Compared:** n-at-risk, events, survival estimate, Greenwood SE, per stratum and time
point, via `hzr_kaplan()`.

**Expected:** PASS at print precision. PR #68 established `hzr_kaplan()` against
`%KAPLAN` to ~5e-6 on the AVC data.

**What this stage is really testing:** the data contract, the cohort reconciliation, the
life-table parser against a 2006-vintage `.lst`, and the render. The survival numbers
are the least interesting part.

### 6.2 `02-hz-dead.qmd` — temporal hazard fit

The first real test. Two-phase `hazard()` fit, 6 free parameters, `conserve = TRUE`,
interval-censored response, no covariates.

**Two fits, deliberately:**

1. **Deterministic comparison** — initialise from the SAS `parms` values. This is the
   like-for-like number that goes in the parity table.
2. **Independent optimisation** — refit from rough starts with multi-start
   (`n_starts = 5`, seeded locally with `.Random.seed` save/restore). Prior work
   established that R frequently finds a better optimum than the C binary's single-start
   from rough starts. Reported alongside, **not** as the parity number.

Reporting both separates "does R agree with SAS" from "is SAS at the optimum" — two
questions that a single fit conflates.

**Compared:** log-likelihood, the 6 MLEs, their standard errors.

**Known risk — interval censoring has no existing SAS parity fixture.** It is listed as
an open gap (⚪) in `inst/dev/DEVELOPMENT-PLAN.md` §7c; R-only invariants were added in
PR #86 but nothing has ever been checked against SAS. **This stage is the first such
check.** A mismatch is a plausible outcome and a valuable one.

**Second risk — CoE is on.** Standard errors under conservation required two rounds of
reconciliation in prior work (PRs #65, #74): the conserved-μ variance must enter the
full-information vcov, and SAS's survival CLs use a logit transform where R defaults to
cloglog. Both are fixed in the package; this stage confirms the fix holds on a
6-free-parameter interval-censored fit.

### 6.3 `03-hp-dead.qmd` — hazard figure

`predict()` over the SAS digital-nomogram grid from `hz.dead_JR.sas`:

```
years = 30/365.2425, 3/12, 6/12, then 1 to 10 by 1
```

**Compared:** `_surviv`, `_hazard`, and their confidence limits — the `.lst` prints
`_surviv _cllsurv _clusurv _hazard _cllhaz _cluhaz`.

**Two settings that must be right or everything mismatches:**

- SAS `%hazplot` / `%kaplan` default `CLEVEL = 0.68268948` — **one standard deviation,
  not 95%**. `predict(level = )` must be set accordingly.
- Survival CLs must use `conf.type = "logit"` to match HAZPRED. R's default is cloglog
  (the `survfit` standard). This was decoded from `hzp_calc_srv_CL.c` in PR #75.

**Figures:** rebuilt with `hvtiPlotR` — survival, hazard, and hazard-phases —
corresponding to the three existing PDFs in `graphs/`. The existing PDFs are a visual
check, not a numerical one; the numerical check is the nomogram table.

**Dependency:** this stage consumes the stage-2 fit. If stage 2 fails parity, stage 3
still runs but its result is reported as conditional on the stage-2 discrepancy.

---

## 7. Success criteria

| Stage | Criterion |
|-------|-----------|
| Cohort gate | N = 3049, 1032 events, 2017 censored — exact |
| 1 | Life-table quantities match `.lst` to print precision (~1e-5) |
| 2 | Log-likelihood matches `.lst` to printed precision; MLEs within SAS print precision |
| 3 | Nomogram survival/hazard and CLs match `.lst` to ~1e-4 |
| 1–3 (secondary) | Survival at 30 d / 6 mo / 1 y / 5 y / 10 y rounds to 97 / 93 / 91 / 75 / 47 % (§5.3) |
| all | Headline max relative discrepancy reported per stage (§5.2.2) — and non-zero |

Tolerances are per-class and derived, not tuned; see §5.2.1. A stage may also report
`R_BETTER` rather than pass or fail, when R's log-likelihood exceeds SAS's beyond
tolerance.

The secondary criterion is a **published-value** check, not a parity check — it is
coarse (whole percent) but independent of both the `.lst` and the parser, so it catches
a class of error the primary criteria cannot: a systematically wrong cohort or time
scale that both R and the parser agree on.

**Failure handling is part of the deliverable.** Any stage that fails is diagnosed to a
named cause — pipeline bug, parser bug, or package gap — before anything is adjusted. A
gap is documented as a gap; numbers are never forced to match by tuning tolerances or
starting values.

This follows the precedent set by the `hm.death.AVC` stepwise fixture, where R and SAS
were shown to diverge **by construction** (SAS selects on Q-statistics without refitting;
R uses full-refit Wald), and the honest documented gap was worth more than a brittle
forced parity.

---

## 8. Deferred stages — constraints already known

Recorded so the deferral is informed. Neither is in scope for this pass.

### Stage 4 — bagging (`bh.dead_s3_JR.sas`)

```sas
%hazboot(in=built, seed=-1, resampl=500, sle=0.07, sls=0.05, test=0);
```

**This stage produces the published "Reliability (%)" column in Table 1** — the paper
defines it as *"percent of times factor appeared in 500 bootstrap analyses"*, with
*"variables appearing in 50% or more of the models retained as risk factors."* So the
published table gives a full reference for stage 4 even though no `.lst` survives.

**Discrepancy to resolve before running:** the paper states a *"P value criterion for
retention in the model of .05"*, but the SAS call uses `sle=0.07, sls=0.05`. Either the
paper is describing `sls` only, or the rerun differs from the published run. Worth
settling with Rajeswaran rather than guessing.

- **No reference output exists** — no `.lst`, no `.log`. Rajeswaran flags it as needing
  a rerun.
- **`seed = -1` means time-of-day seeding.** Rerunning does not reproduce the paper's
  numbers, and two reruns do not reproduce each other. Element-wise parity is impossible
  by construction; only the distribution of selection frequencies over 500 resamples is
  comparable.
- **Capability gap:** `hzr_bootstrap()` has no bootstrap-with-selection mode equivalent
  to `%HAZBOOT`, and building one would inherit the stepwise gap below. Flagged in
  PR #78 as a possible `scope=` argument.

### Stage 5 — multivariable (`hm.dead_s3_JR.sas`)

Reference: LL = −3363.58, 1032 events, `noconserve`. **This is the paper's Table 1.**

**Covariate count reconciles once `ms_*` variables are accounted for.** The SAS final
model fits 13 early + 27 late covariates; Table 1 lists 12 early + 21 late. The
difference is exactly the six missing-value indicator variables in the late phase
(`ms_mvrg`, `ms_hctp`, `ms_avare`, `ms_cadsy`, `ms_lvfe`, `ms_lvmas`) and one in the
early phase (`ms_cadsy`) — the paper says these were included in the analysis but
*"we reported none."* So:

| Phase | Fitted | `ms_*` | Published |
|-------|--------|--------|-----------|
| Early | 13 | 1 | 12 ✓ |
| Late | 27 | 6 | 21 ✓ |

Both reconcile exactly. This confirms the model in `hm.dead_s3_JR.sas` is the published
model, and gives stage 5 a published cross-check for every non-`ms_` coefficient.

**Stage-5 dependency:** `hvtiRtables::hv_man_table_jtcvs()` renders Table 1 in JTCVS
manuscript form — the journal this paper appeared in. Deferred to stage 5 because
nothing in stages 1–3 produces a manuscript table.

Four known gaps, all pre-existing:

1. **Interval censoring** — no SAS parity fixture (stage 2 addresses this first).
2. **Hessian stability at ~43 parameters** — 13 early + 27 late covariates plus 6 shape
   parameters. The 13-parameter AVC model was already at the identifiability edge
   (`rcond ≈ 8.6e-9`, `pd = FALSE`). Layer 1 inversion hardening will surface this
   safely rather than silently.
3. **Stepwise selection** — `selection forward sle=0.1 sls=0.07 maxsteps=10`. SAS uses
   Q-statistics; R uses full-refit Wald. Established as non-reproducible step-by-step;
   only final-model agreement is assertable.
4. **`robust` standard errors** — the SAS selection statement requests sandwich SEs.
   `TemporalHazard` has no `ROBUST`/`SEMIROBUST` equivalent; it is a Phase 8 candidate.

The `.lst` contains a useful bonus: the penultimate fit runs with *"Conservation of
events: Invoked initially"* and the final with *"Not invoked"* on nearly the same model
— a free CoE-on / CoE-off pair on identical data.

---

## 9. Environment

**Execution target: the CCF server, not a local Mac.** The Mac mount is used for reading
and authoring only. Every runtime assumption below must be verified on the server before
stage 1 runs.

### 9.1 Local (authoring) — verified 2026-08-10

Recorded only as a reference point. These are **not** the versions the analysis runs on.

| Component | Version (Mac) |
|-----------|---------------|
| R | 4.6.0 |
| TemporalHazard | 1.2.0 |
| haven | 2.5.5 |
| survival | 3.8.9 |
| quarto (R pkg / CLI) | 1.5.1 / 1.10.0 |
| ggplot2 | 4.0.3 |
| hvtiPlotR | 2.7.4 |
| hvtiRutilities | 1.0.2 |
| hvtiRtables | 0.9.4 (stage 5 only — not used this pass) |

`hvtiRutilities` and `hvtiRtables` are internal packages, not on CRAN. Their presence
and version on the **server** must be confirmed as part of the §9.2 audit; if
`hvtiRutilities` is absent there, §4 falls back to `haven::read_sas()` and the label /
manifest / dataset-comparison work is done by hand, which is a real cost worth knowing
about before stage 1 rather than during it.

### 9.2 Server (execution) — UNVERIFIED

The same table must be produced on the server as the first implementation task. Specific
risks, in priority order:

1. **`TemporalHazard` availability and version.** 1.2.0 is newer than the 1.1.0 CRAN
   release; if the server has an older version or none, the parity numbers are not
   comparable to anything recorded here. The version actually used is printed in the
   report header of every stage.
2. **`quarto` CLI presence.** If absent, the stages still run as plain R but the report
   deliverable does not build.
3. **R version.** 4.6.0 locally; an older server R constrains package availability.
4. **CRAN mirror.** The lockfile points at `https://<internal-ppm-host>/cran/latest`,
   an internal mirror — reachable from the server, not necessarily from anywhere else.

### 9.3 Path portability — a hard requirement

The study resolves to two different paths:

| Context | Path |
|---------|------|
| Server (and all SAS programs) | `/studies/cardiac/valves/.../lv_function/survival` |
| Mac mount | `/Volumes/qhsstudies/cardiac/valves/.../lv_function/survival` |

**No R file may hardcode either path.** All paths resolve relative to the study root,
discovered at runtime — the `.Rproj`/`renv` root via `here::here()` or an equivalent, not
a literal. The reference `.lst` files are spread across three sibling directories
(`analyses/`, `distributions/`, `graphs/`) two levels above the `.qmd` files, so this
matters for every parity call, not just the data read.

The SAS programs solve the same problem with `%let STUDY=/studies/...`; the R equivalent
must be resolved, not transcribed.

### 9.4 Open setup item

`renv.lock` at the study root currently contains only `renv` itself — the local packages
above resolved from the system library. A real `renv::snapshot()` **on the server** is a
prerequisite for the reproducibility claim, and is the second implementation task after
the version audit. Snapshotting on the Mac would record the wrong library.

**Reference paper:** readable (poppler 26.08.0 installed 2026-08-10). Published values
are incorporated as a third reference — see §5.3. Analyses in the paper were run under
**SAS 9.1**.

---

## 10. Out of scope

- Porting `vars.sas` to R.
- Stages 4 and 5 (see §8).
- Reproducing SAS's plot styling; figures are rebuilt in `hvtiPlotR` house style.
- Any modification to the SAS tree.
- Adding fixtures to the `TemporalHazard` test suite. If a stage produces a fixture
  worth distributing, that is a separate change against that repository, not this one.
