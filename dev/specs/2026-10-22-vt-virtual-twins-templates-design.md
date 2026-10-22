# `vt` templates: design, 2026-10-22

**Status** Design, approved with John on 2026-10-22. Not implemented.
**Adds** two templates under the existing `vt` prefix, `vt-fit.qmd` and
`vt-explain.qmd`, both shipped with ledger status `in-flight`.
**Starts from** the Virtual Twins study (ST1267): notebook chapters 03
(feature selection), 04 (case eligibility), 05 (survival modeling), 06
(counterfactuals), 07 (outcomes) and 08 (cluster outcomes), and report
chapters 05 to 08.

## 1. What a virtual twins job does

For each patient, a virtual twins analysis predicts two survival curves: the
curve under the arm the patient received, and the curve under the other arm.
Each curve comes from a forest grown on one arm only, so a patient's
counterfactual curve is what the other arm's forest predicts for someone with
that patient's characteristics. The difference in restricted mean survival time
(RMST) to a horizon tau is the patient's estimated treatment effect.

The method has four steps, and the template keeps them in this order:

1. **Predictors.** A treatment-blind variable screen chooses the covariates
   both forests are grown on. The study screened 101 candidates with varPro on
   all patients, with the arm left out.
2. **Eligibility.** A patient whose characteristics lie outside the other arm's
   data has a counterfactual that is an extrapolation. Such patients are
   flagged and kept out of the summaries.
3. **Arm forests and twin curves.** One survival forest per arm. A patient's
   own-arm curve is out of bag; the other-arm curve is a prediction from the
   other forest.
4. **The contrast.** The RMST difference per patient, summarized by arm, by
   eligibility rule and by any stratifier.

The study's other material (isolation forests, the SID distance as a rule, the
experiments in chapters 09 to 14) stays in the study. Section 8 lists it.

## 2. Taxonomy, ledger and naming

- **Taxonomy:** `vt` is already in `hvti_taxonomy()` (hvtiRutilities PR #127):
  "Virtual twins: per-arm forests, swapped-arm prediction, RMST difference",
  folder `analyses`. No hvtiRutilities change is needed.
- **Files:** `inst/templates/30_analyses/vt-fit.qmd` and
  `inst/templates/30_analyses/vt-explain.qmd`. The pair mirrors
  `rfs-fit`/`rfs-explain` and `vp-fit`/`vp-explain`, and `template_list()`
  shows them as `vt.fit` and `vt.explain`.
- **The prefix is wholly qualified.** `add_job("vt", ...)` with no qualifier
  errors and lists both.
- **Ledger rows.** The single unqualified row `(vt, NA)`, today `queued` with
  `blocked_on: hvtiRforests#1`, is replaced by `(vt, fit)` and
  `(vt, explain)`. Both are `in-flight`, with `blocked_on` cleared. The
  catalog grows from 68 rows to 69; the prefix count stays at 45.
- **Why `blocked_on` clears.** The ML family roadmap
  (`2026-09-17-ml-family-roadmap-design.md`) puts the method code (swapped-arm
  prediction, RMST difference) in `hvtiRforests`, which does not exist yet.
  John decided on 2026-10-22 that `vt` is needed now. The helpers therefore live
  in chunks of their own inside `vt-fit`, as `vp_judge()` does in `vp-fit`, and
  are tested chunk by chunk. Moving them to `hvtiRforests` is a later pull
  request, and each ledger row's note says so.
- **The two-study gate.** Virtual Twins is the only study to have run this
  analysis. `in-flight` records that, and both rows become `shipped` once a
  second study runs `vt-fit` through to `vt-explain`. This is the route `bd`
  and `vp` took.

## 3. Inputs from upstream jobs

- **The data, and missing covariates.** A built dataset read with
  `job_data()`, the way every template reads one. John, 2026-10-22: a study may
  use MICE or forest imputation, so the handling is a study choice, built on
  what the package already has rather than a new path:
  - **`NA_ACTION`** (an `EDIT:` choice, as in `rfs-fit`): `"na.impute"`, the
    default, keeps a patient with missing predictors and imputes inside each
    forest; `"na.omit"` drops them, counted with `.missing_cases()`. The outcome
    is required either way, as in `rfs-fit`, because imputing it would invent
    follow-up. Gower distance handles missing values, and the `"sid"` method
    reads a distance computed upstream, so eligibility needs no imputation of
    its own.
  - **MICE**, run upstream (an imputation job), arrives as stacked data with
    one row per patient per imputation. `IMPUTATION` (an `EDIT:` choice, `NULL`
    by default) names the column numbering the imputations and is passed to
    `job_data(imputation = )`, as the `lm` templates do. **The first release
    uses one completed dataset**: `IMPUTATION_USE` (default 1) names which, and
    the report says that one of m was used. This is what the exemplar did
    (MICE with m = 1). Pooling across imputations is out of scope (section 8).
- **The predictors, from a `vp-fit` screen or a list.**
  - `VP_SET <- "dead-vp"` (an `EDIT:` choice) names the `vp-fit` set whose
    `vp.rds` this job reads. It takes `vp.rds$selected`, read with
    `.read_handoff()` so its lineage is checked and recorded.
  - `VP_SET <- NULL` uses `PREDICTORS`, a list in the study choices.
  - Either way, `EXCLUDE` (an `EDIT:` list) then drops columns measured after
    the treatment decision. In the study these were the later procedure flags;
    a screen does not know when a variable was measured.
  - The **predictor contract** stops the render when the arm, time, status or
    ID is among the predictors. The study found such a leak on 2026-09-23,
    after its forests had been circulated.
  - The `vp-fit` screen must have been run without the arm, which is what makes
    it treatment-blind. `vt-fit` checks that the arm is not among the screen's
    candidates (`vp.rds$coverage$variable`) and stops if it is.
- **A `sid` clustering**, read by `vt-fit` for its distance when
  `ELIGIBILITY` includes `"sid"` (section 4.1), and by `vt-explain` for its
  clusters (section 6). Clusters
  join the per-patient table on the ID as a stratifier and never enter a forest
  as a covariate, because they are built from the same characteristics the
  forests already use. This is the interface the ML roadmap set between `sid`
  and `vt`.

## 4. `vt-fit.qmd`

Chunks, in order:

1. **`setup`**, the standard opening: `SUBJECT`, `TYPE <- "vt"`, `.in`,
   `library()` calls with version floors for `randomForestSRC (>= 3.7.0)`,
   `cluster` and `hvtiRpropensity (>= 0.2.0)`, the floors `DESCRIPTION`'s
   `Suggests` carries. `cluster` is not in `Suggests` today and is added,
   because the tests run `vt_ood()`. Then
   `options(rf.cores = 1L, mc.cores = 1L)` and
   `hvtiRtemplates:::.job_setup()`.
2. **`edit-study-choices`**, each marked `EDIT:`:
   - `TIME`, `STATUS` and `ID`;
   - `ARM`, and `ARMS`, the two levels in the order the difference is taken:
     `diff = RMST(ARMS[1]) - RMST(ARMS[2])`;
   - `NO_ARM`, the rows predicted under both arms and fit by neither (the
     study's "Future" patients, who received neither treatment). The default
     is the rows whose `ARM` is `NA`. A study with none has zero such rows and
     every section still renders;
   - `VP_SET`, `PREDICTORS` and `EXCLUDE` (section 3);
   - `ELIGIBILITY`, `COMBINE` and `SID_SET` (section 4.1);
   - `NA_ACTION`, `IMPUTATION` and `IMPUTATION_USE` (section 3);
   - `HORIZON`, tau, in the time variable's own units. The comment says the
     study used 4 years because events ran out by 5;
   - `NTREE` (default 1000; the study used 5000), `NSPLIT` (default 8);
   - `SEED`, part of every cache key, used as `set.seed(SEED)` before each
     random call and passed to `rfsrc()` as `seed = -abs(SEED)`. Both are
     needed: the study's forests were irreproducible until 2026-10-07 because
     random calls were unseeded;
   - `REFIT`, `SAVE_FIGURES` and `FIGURES`, as in every template.
3. **`tbl-data`.** Rows with a missing `TIME` or `STATUS` among the treated
   are dropped, with the count stated. Counts and events by arm, and the count
   of no-arm rows.
4. **`predictors`.** Resolves the predictor set (section 3), applies the
   contract and prints the final list.
5. **`ood`.** Defines the eligibility machinery (section 4.1): `vt_ood()`, the
   nearest-neighbour rule on any distance, and one `vt_elig_<method>()` per
   method, each returning a distance.
6. **`eligibility`.** Runs every method named in `ELIGIBILITY`, combines them
   by `COMBINE`, and adds the sensitivity rows:
   - **Propensity common support**, from `hvtiRpropensity::ps_forest()` on the
     treated patients and `ps_support()`. It is a sensitivity row only, never
     part of the combined rule.
   - **Unrestricted**, everyone.
   - A table of the out-of-distribution patients with, for each method, the
     arm each failed against and the reason, and a figure per method of each
     patient's distance against the arm's reference.
   - A cross-tab of the methods' flags against each other, because the study
     found Gower and SID barely agree (chapter 09).
   - Patients are flagged, never dropped. Listings show everyone; the summaries
     in `vt-explain` use the combined rule.
7. **`fit`.** One `rfsrc()` survival forest per arm, each a separate
   `cache_fit()`: `ntree = NTREE`, `nsplit = NSPLIT`,
   `na.action = NA_ACTION`, `importance = FALSE`, `seed = -abs(SEED)`, with
   `set.seed(SEED)` before each.
8. **`tbl-performance`.** Each arm's OOB C-index with a 95% interval, its
   patient and event counts. An interval that includes 0.5 gets a note that the
   arm's side of every contrast is exploratory. The study's smaller arm had 50
   patients and 12 events and an interval of 0.44 to 0.74.
9. **`curves`.** Defines and runs `vt_curves()`:
   - the own-arm curve is the forest's **out-of-bag** prediction, so no patient
     is predicted by a forest grown on them (the study's in-bag bias, fixed
     2026-09-23);
   - the other-arm curve is `predict()` from the other forest;
   - no-arm rows get both curves from `predict()`;
   - every curve is keyed by `ID`, never by row position. The study carried a
     row-order pairing bug until 2026-09-23.
10. **`rmst`.** Defines and runs `vt_rmst()`:
    - the step-function integral of each curve to `HORIZON`;
    - `diff = rmst_<ARMS[1]> - rmst_<ARMS[2]>`, in the time variable's units;
    - the risk of the event by `HORIZON` under each arm, and the log relative
      risk, which `vt-explain`'s standardized betas use;
    - it **stops** when `HORIZON` is beyond the largest follow-up time in
      either arm. That is the study's units bug (2026-06-22: day horizons on a
      fit in years, which truncated every curve to the same value) caught where
      it happens.
11. **`fig-curves`.** Mean twin curves per arm (`hvtiPlotR::hv_rmst_curves()`),
    in-distribution patients only.
12. **`save`.** One handoff, `estimates/<subject>-<type>/vt.rds` (section 5),
    with handoff lineage attached.
13. **`provenance`.**

### 4.1 Eligibility is a choice of methods

John, 2026-10-22: eligibility will gain methods as studies use them, so no
method is hard-wired.

- **`ELIGIBILITY`** (an `EDIT:` choice) names one or more methods. The first
  release carries two, the ones the exemplars use:
  - **`"gower"`**: Gower distance (`cluster::daisy(metric = "gower")`) over the
    model predictors only. Gower handles mixed types, is model-free and is
    bounded, which is why the Virtual Twins study chose it over Euclidean,
    Mahalanobis, matching, Jaccard and forest proximity (2026-10-01).
  - **`"sid"`**: the SID distance from a `sid` clustering set, named by
    `SID_SET` (an `EDIT:` choice). John chose the morphology study's SID
    (ST1264) as the measure on 2026-10-22, in preference to Virtual Twins'
    own reversion to Gower alone on 2026-10-05: the morphology work is later
    and is the more careful SID analysis. `vt-fit` reads the distance from the
    set's handoff and never fits SID itself, and stops when the set is missing
    or lacks the ID of any patient in this job.
  - The default is `ELIGIBILITY <- "gower"`, which needs no upstream job.
- **One rule, many distances.** Every method supplies a patient-by-patient
  distance, and `vt_ood()` applies the same rule to each:
  - for each arm, every patient's nearest neighbour in that arm, excluding the
    patient themself;
  - a patient is **out of distribution** for an arm when that distance is
    **strictly greater** than the largest nearest-neighbour distance among the
    arm's own patients. The reference is the arm's own spread, not a
    percentile;
  - a treated patient is judged against the other arm; a no-arm patient must
    pass against both.
- **The same shape from every method.** `vt_ood()` returns one row per
  patient and arm judged: `ID`, `method`, `arm`, `nn_id`, `distance`,
  `reference`, `ratio` (distance over the arm's median nearest-neighbour
  distance), `in_distribution` and `reason`. Methods are bound by row, so a
  table or figure written for one method serves any.
- **`COMBINE`** (an `EDIT:` choice) is `"any"` (the default: a patient is out
  of distribution when any method flags them, the stricter rule and the one
  the study used for Gower or SID) or `"all"`.
- **Adding a method later** is a new `vt_elig_<method>()` returning a
  distance with the IDs as labels, and a new name accepted by `ELIGIBILITY`.
  A method that is not a distance (an isolation-forest score, say) supplies a
  flag and reason in the same row shape instead, and bypasses `vt_ood()`. Each
  method gets its own column in the handoff and its own row in the
  sensitivity table without further change.

## 5. The handoff

`vt.rds` is a list:

| element | contents |
|---|---|
| `rmst` | one row per patient: `ID`, arm (with no-arm rows marked), `rmst_<arm>` for each arm, `diff`, `risk_<arm>`, `log_rr`, one logical column per eligibility method (`elig_gower`, `elig_sid`, ...), `elig` (the methods combined by `COMBINE`), and the sensitivity columns `elig_propensity` and `elig_none` |
| `curves` | the per-patient survival curves on the forests' shared time grid, keyed by `ID` and arm |
| `forests` | the two `rfsrc` fits, named by arm |
| `eligibility` | `vt_ood()`'s rows for every method, `ELIGIBILITY`, `COMBINE`, the `SID_SET` read if any, and the propensity scores |
| `predictors` | the final predictor list, and the `VP_SET` it came from or `NULL` |
| `settings` | `ARMS`, `HORIZON`, `NTREE`, `SEED`, the time units label |

One file rather than several, because the handoff reader validates the lineage
of one object, and separate files could drift apart. The forests are saved so
that `vt-explain`'s standardized betas can refit nothing.

## 6. `vt-explain.qmd`

It reads `vt.rds` from its own set with `.read_handoff()`, never calls
`rfsrc()`, and stops naming the missing file when no `vt-fit` has run in the
set. Its study choices are `STRATIFY`, `BOOT`, `GAIN_MIN` and the figure
choices.

1. **Core contrast**, in-distribution patients under the primary rule:
   - the RMST difference by arm as percentile boxes (15th to 85th box, 5th to
     95th whiskers), the study's `geom_pct_box()` made general;
   - a ranking plot of every patient's difference;
   - mean twin curves by arm, with the horizon marked;
   - **received best versus alternative best** at `HORIZON`: in each arm, the
     share whose own-arm RMST is the larger, a stacked bar per arm. A footnote
     gives each arm's event count where its C-index interval includes 0.5;
   - **the sensitivity table**: for each eligibility rule (the combined rule,
     each method alone, propensity support, unrestricted), the count kept, the median difference
     with its 15th and 85th percentiles, and the share favouring `ARMS[1]`, by
     arm.
2. **Stratifier**, when `STRATIFY` is not `NULL`:
   - `STRATIFY` is either the name of a column in the data, or
     `list(set = "<subject>-sid")`, naming a `sid` set whose handoff this job
     reads;
   - the stratum joins the per-patient table on `ID`, coerced to character on
     both sides. The study's IDs were a factor in one cache and character in
     another;
   - a cross-tab of arm by stratum, and the difference by stratum and arm.
     Strata with fewer than 5 in-distribution patients in an arm are shown but
     their medians are not.
   - **The `sid` handoff shape is not settled.** The `sid` template is being
     designed alongside this one. The `vt` templates read two elements of
     `sid.rds`: `dist`, the patient-by-patient SID distance with IDs as labels
     (for `vt-fit`'s `"sid"` method), and `clusters`, a data frame of the ID
     and one `cluster` column for the chosen K (for this stratifier). If the
     `sid` design lands with other names, the plan's tasks follow it, and this
     paragraph is amended.
3. **Standardized betas**, the study's chapter 07 method (Ishwaran and
   Blackstone, CSBJ 2025): each patient's log relative risk at `HORIZON`,
   divided by its standard deviation, regressed on one characteristic at a
   time with overlap (ATO) weights from the propensity scores in `vt.rds`.
   Confidence intervals come from `BOOT` patient bootstraps with the forests
   held fixed (default 1000, about a minute in the study); `BOOT <- 0` skips
   the intervals. Seeded with `SEED` from the handoff.
4. **Who might benefit**, the report's chapter 08: in-distribution patients
   whose twin favours the arm they did not receive by more than `GAIN_MIN`
   (default 0, in the time variable's units), and no-arm patients by which arm
   their twin favours. A table of their characteristics beside those of the
   rest of their arm.
5. **Reading the result.** The study's prose made general: what out of
   distribution means and why such patients are not summarized; that an arm
   whose C-index interval includes 0.5 makes its half of every contrast
   exploratory; that the difference is a model estimate per patient, not an
   observed outcome; and that a design-based contrast (the propensity RMST in
   `hvtiRpropensity::ps_rmst()`) is the check on it.

## 7. Testing

A new `tests/testthat/test-vt-templates.R` runs the installed templates chunk
by chunk with `rf_run()`, in the throwaway `rf_study()` fixture, with a
`helper-vt.R` beside `helper-vp.R`.

The synthetic cohort, `vt_data()`: about 300 patients in two arms of unequal
size, a continuous `xs` that interacts with the arm (it favours arm A when high
and arm B when low), two null covariates, a categorical covariate, five planted
outliers far from arm B in `xs`, and ten no-arm rows.

1. **The sign recovers the planted effect.** The median difference among
   high-`xs` patients favours arm A and among low-`xs` patients arm B.
2. **`vt_ood()` flags the planted outliers** and no others in arm A. **By
   mutation:** change the strict `>` to `>=` and confirm a patient on the
   reference is flagged and the test fails.
3. **No-arm rows must pass against both arms.** A no-arm row near arm A alone
   is out of distribution.
3a. **Methods combine as stated.** With two hand-built distances that flag
    different patients, `COMBINE = "any"` flags the union and `"all"` the
    intersection, and every method's rows have the same columns.
3b. **The `"sid"` method reads a set and refuses a gap.** A fixture `sid.rds`
    with a `dist` is used as given; one missing a patient's ID stops the render
    naming the count missing.
4. **Keying by ID.** `vt_curves()` on a predict frame whose rows are shuffled
   returns the same per-patient curves. Revert to row pairing and confirm the
   test fails.
5. **Own-arm curves are out of bag.** For an arm-A patient, the own-arm curve
   equals the forest's OOB curve, not `predict()` on the training data.
6. **`HORIZON` beyond follow-up stops** with a message naming both.
7. **The predictor contract stops** when `ARM` is in `PREDICTORS`, and when a
   `VP_SET` screen had the arm among its candidates.
8. **The `vp.rds` route.** A `vp-fit` run in the fixture, then `vt-fit` with
   `VP_SET` set, uses the screen's selected set minus `EXCLUDE`.
9. **The handoff.** `vt-explain` reads `vt.rds` with no `rfsrc(` call in its
   source, and stops naming the file when no fit has run.
10. **The stratifier joins on ID**, with a factor ID on one side and character
    on the other.
11. **`BOOT <- 0` skips the intervals** and the betas still render.
11a. **Missing covariates.** `NA_ACTION = "na.omit"` drops and counts the
     patients missing a predictor; with stacked data and `IMPUTATION` set,
     only the rows of imputation `IMPUTATION_USE` reach the forests, and the
     report names one of m.
12. **No MRN in any saved file**, with the existing `rf_mrn_data()` scan.

`vt_ood()`, `vt_rmst()` and the keying test need no forest: they run on
hand-built inputs, so they run on CRAN too. Tests that grow forests carry
`skip_on_cran()`, at `NTREE = 50`.

The catalog-wide tests cover the format block, the `SUBJECT`/`TYPE` lines, the
single `setup` chunk, no study identifiers, `EDIT:` markers only in `edit-`
chunks, package floors, provenance and lineage for both files with no new code.

**Gates outside `testthat`:** a `.lintr` **file** key for each template; the
ledger rows, with the roadmap tables regenerated by
`python3 dev/specs/artifacts/roadmap_render.py`; `test-template-catalog.R`'s
row count from 68 to 69.

**CI cost.** About ten small forests at `NTREE = 50` and one small `vp-fit`.
Under `NOT_CRAN=true` the expected `SKIP 0` on macOS and Ubuntu and `SKIP 3`
on Windows do not change.

**Not tested:** whether the Gower rule is the right eligibility rule, or
whether per-arm forests beat a pooled forest with a treatment term. Those are
statistical claims; the study's chapter 10 (calibration error of 2.7 against
16.8 points for the smaller arm, and a pooled forest that lost the treatment
difference) is the evidence, and `in-flight` records that a second study has
yet to confirm it.

## 8. Out of scope

- **Isolation-forest support scores** and the cross-arm distance rule. The
  study tried both as sensitivity rules. Section 4.1's structure takes either
  as a later method without a redesign.
- **Fitting SID inside `vt-fit`.** The `"sid"` method reads a `sid` set's
  distance; a study without one runs the `sid` job first.
- **Running an imputation**, which belongs to an upstream job.
- **Pooling across multiple imputations.** Decided 2026-10-22: the first
  release uses one completed dataset. Pooling would grow both forests and run
  eligibility per imputation, average each patient's difference, report the
  between-imputation spread, and need a rule for a patient in distribution in
  some imputations only. That is a later design.
- **The study's experiments** (chapters 09 to 14) and its design-check
  appendix.
- **Moving `vt_ood()`, `vt_curves()` and `vt_rmst()` to `hvtiRforests`**
  once that package exists (`hvtiRforests#1`).
- **The design-based propensity RMST contrast**, which
  `hvtiRpropensity::ps_rmst()` already provides; `vt-explain` points to it.
