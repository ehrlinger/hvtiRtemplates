# `hs`: observed against expected with a test, a band for the average curve, and a check

**Date:** 2026-11-10
**Status:** design, for the maintainer's approval. Not implemented. No plan yet.
**Origin:** a call on 2026-11-10 about a study whose ~689 patients were scored
through a SAS `hs` model fitted on ~7,200 other patients. Each patient's
predicted curve was averaged into an expected curve and set against the
study's own Kaplan-Meier. Four things went wrong in the conversation, and this
note answers three of them (section 2).
**Already on `main`, not redone here:** `hs-setup` averages unweighted
survival, not cumulative hazard, following `%usmatchd`, and says so;
`hs-setup` and `hs-concordance` warn that `CLEVEL` is plus or minus one
standard error, about 68%.

This note is self-contained. It assumes no memory of the session that
produced it.

---

## 1. What this decides

Which template each of three additions goes in, what each computes, what
each is called in the report, and how each is tested. It does not build
anything.

| # | addition | home |
|---|---|---|
| 1 | one-sample log-rank test: O/E, its interval and a p-value | **`hs-concordance`**, a new section |
| 2 | a band for the cohort-average curve, as a named choice, and the spaghetti plot | **`hs-concordance`**, a new figure section; the computation in one internal helper in `R/` |
| 3 | a check that the mean of the patients' predictions equals the averaged curve | **both** `hs-setup` and `hs-concordance`, one line each |

Built in `hs` first. The `vt` templates do the same kind of work on forest
curves, so the test and the band are written as model-agnostic helpers they
can call, and `vt-explain` cross-references them now (section 3.2). No new
template, so no two-studies gate and no ledger row.

---

## 2. The problems on the call

1. **The expected band looked far narrower than the Kaplan-Meier's.** Three
   causes stack, and only the first is a mistake:
   - the expected band is about 68% (`CLEVEL`), the Kaplan-Meier's 95%. A 95%
     band is 1.97 times as wide on the same fit (`hs-setup` measures this);
   - the expected curve's uncertainty is the **reference model's**, estimated
     on 7,200 patients, while the Kaplan-Meier's is the 689's. A narrower
     band is correct, not a defect;
   - the SAS job averages each patient's CLL and CLU. That is quantity (a) in
     section 5, which is *wider* than the CI of the mean curve, so it does not
     explain narrowness; it overstates the expected curve's uncertainty.
2. **The sponsor needs a p-value, and no curve gives one.** Two bands that
   overlap or not is not a test. Section 4.
3. **A skewed spread of patient predictions took ten minutes to argue.**
   "Most below 1%, mean 2%" is a mean pulled by a tail. `hs-setup`'s
   prediction table prints the median, min and max, and its obs-vs-exp table
   uses the mean; nothing prints both side by side. Sections 5.4 and 6.
4. Averaging CLL and CLU without saying what it is. Section 5.

---

## 3. Where it goes, and why

### 3.1 `hs-concordance`, not `hs-setup`

The call's shape is **a cohort scored through a model fitted on a different
cohort**. That is exactly what `hs-concordance` does and `hs-setup` refuses:

- `hs-setup` reads `hm.rds` **from its own set** and checks that the rows it
  predicts for are the rows the model was fitted on, stopping otherwise. Its
  obs-vs-exp table compares the model's average against a matched population
  **life table**, and says "a comparison, not a test". Run against its own
  fitted rows, a one-sample log-rank would return O/E = 1 by construction
  (section 4.4), so it has no question to answer there.
- `hs-concordance` reads each model from **another set**, or with
  `CROSS_STUDY <- TRUE` from another study, predicts the job's own cohort
  through it, and already carries that cohort's `TIME` and `EVENT`
  (`assert_cohort()` in the `cohort` chunk). Every input the test needs is
  present.

The call's case is `hs-concordance` with **one model**. `MODELS` of length
one is already accepted; the decision section needs two and is deleted by the
author. One change is needed: `GROUP` is required today, and with one model it
is a column every patient shares. Proposed: **`GROUP` may be `NULL` when
`MODELS` has one entry**, and every patient is then in that model's group. A
`NULL` with two or more models still stops.

With several models, the test is computed per **(model, group received)**
cell, which `hs-concordance` already crosses:

- a group under **another** group's model is indirect standardization: deaths
  observed in PCI patients against the deaths the CABG model expects for
  patients like them. A valid question, and the table says what it is;
- a group under **its own** model, when that model was fitted on these same
  patients, is in-sample and returns O/E = 1 (section 4.4). Those cells are
  printed as a check, marked in-sample, with no p-value. The marking needs
  the job to know the cell is in-sample; it compares the model's fitted
  row count and selection with the cohort's, as `hs-setup` does. **Open
  question Q4.**

### 3.2 `vt-fit` and `vt-explain`: the same questions on forest curves

Decided by the maintainer on 2026-11-10: the `vt` templates may build these
in, and at least cross-reference them for this kind of work. A virtual twins
job asks the call's question in a second form: a patient's other-arm curve is
that patient scored through a model fitted on a different cohort, the other
arm's forest. Each piece carries over, with differences:

| piece | in `hs-concordance` | in `vt` |
|---|---|---|
| O/E test | `predict(type = "cumulative_hazard")` at each patient's own time | the forest's cumulative hazard (`chf`, `chf.oob` in randomForestSRC) at each patient's own time, read off `time.interest` as a step function. Not `-log(survival)`, which is infinite where a forest's survival reaches 0 |
| own-arm cell | in-sample, O/E = 1 by construction, printed as a check | **out of bag**, so not 1 by construction: an honest calibration of each arm's forest. More useful here than in `hs` |
| other-arm cell | indirect standardization | observed events in arm B against what arm A's forest expects for them: the twins' counterfactual comparison, as a count with a test |
| band (a) | patients' 68% limits averaged | **not available**: a forest gives no per-patient limits |
| band (b) | waits on TemporalHazard (section 5.2) | bootstrap of the forests only; no delta method exists |
| band (c), spaghetti | yes | yes, on the twin curves `vt-fit` already builds |
| Kaplan-Meier beside it | 95% | `vt-fit`'s `fig-km` draws 70% today; the coverage must be named either way |

**What this changes in the design.** The O/E test and the band take plain
inputs, never a model object, so either family can call them (section 3.3):
the test takes each patient's event, own follow-up and expected cumulative
hazard; the band takes a patients-by-times matrix of survival and, where they
exist, of limits.

**What this pull request does in `vt`.** A cross-reference only: one
paragraph in `vt-explain`'s "Reading the result" naming the helpers and this
note, and the same pointer in `inst/templates/README.md`. Building the O/E
section and the spaghetti into `vt-fit` or `vt-explain` is a **second pull
request**, after the `hs` one, so the helpers are exercised once before a
second family depends on them. `vt` is `in-flight` from one study; that does
not block adding a section to it. **Open question Q8.**

### 3.3 Two helpers in `R/`

Both are needed in `hs-concordance` now and in `vt` next (section 3.2), and
the band is a candidate for `hs-setup`'s `fig-expected` later. So both are
internal functions in `R/observed-expected.R`, tested directly, and called as
`hvtiRtemplates:::.one_sample_logrank()` and
`hvtiRtemplates:::.cohort_curve_band()`, the way templates already call
`.lifetable_indicator()`. Code pasted into two families of templates would
drift. Neither takes a model object: they take the numbers a model produced,
so neither knows whether a hazard model or a forest made them.

```r
.one_sample_logrank(event, expected, level = 0.95)
# event: 0/1 per patient. expected: each patient's expected cumulative hazard
# at their own follow-up. Returns O, E, O/E, its exact interval, chi-squared, p.
.cohort_curve_band(surv, lower = NULL, upper = NULL, band)
# surv, lower, upper: patients x times. band: "limits_mean" (needs lower and
# upper) or "spread". Returns the average curve and the band, with a label.
```

---

## 4. Addition 1: the one-sample log-rank

### 4.1 What it computes

For each patient *i* in the scored cohort, with follow-up `t_i` and event
`d_i`, both in the job's own `TIME` and `EVENT`:

```
E_i = H(t_i | x_i)          # predict(fit, newdata, type = "cumulative_hazard"),
                            # newdata$time = t_i, the patient's OWN follow-up
O   = sum(d_i)
E   = sum(E_i)
O/E, chi-squared = (O - E)^2 / E on 1 df, p = pchisq(..., lower.tail = FALSE)
```

This is the one-sample log-rank test (Breslow 1975; Finkelstein, Muzikansky
and Schoenfeld 2003). It treats the expected curve as **fixed**, and says so
in the report (section 4.3).

**The interval for O/E** is the exact Poisson interval on O, divided by E:

```
lower = qchisq(alpha / 2, 2 * O) / 2 / E
upper = qchisq(1 - alpha / 2, 2 * (O + 1)) / 2 / E
```

O = 0 gives a lower limit of 0, which the formula returns as written.

### 4.2 What it does not compute

- **Not at a horizon.** `E_i` is at the patient's own follow-up, not at
  `HORIZON`. Evaluating every patient at one horizon and comparing with the
  deaths before it is the comparison of a curve with a curve, which is the
  thing that gave no p-value.
- **Not the average survival curve.** O/E sums cumulative hazards; the
  average curve averages survivals. They are different summaries of the same
  predictions and the report keeps them in different sections.

### 4.3 Guards and labels

- **Follow-up beyond the reference model's.** `predict()` returns a number
  for any time. A patient followed past the last time in the reference
  model's data is predicted from the parametric form running on. The section
  administratively censors both O and E at `TAU`, which defaults to that last
  time (already computed per model in the `horizon` chunk), counts the
  patients affected, and prints the count. A `TAU` set higher than the
  model's last time stops, as `HORIZON` does.
- **The expected curve treated as fixed** is printed beside the result. With
  a reference cohort ten times the scored one, as on the call, the omitted
  variance is small; with comparable cohorts it is not. **Open question Q2.**
- **Its own coverage.** The interval is labelled with its level wherever it
  appears. The level is a new study choice, `TEST_LEVEL <- 0.95`, kept apart
  from `CLEVEL` and marked `EDIT:` so an author can switch it, to `CLEVEL` for
  one coverage across the report or to any level in (0, 1). Decided by the
  maintainer on 2026-11-10 (Q1).
- **Time units.** `E_i` is only right when `TIME` is in the reference
  model's unit. Inside one study this holds; with `CROSS_STUDY` it rests on
  the author's word, as `hs-concordance` already says.
- **Start/stop models** are already refused by `hs-concordance`.

### 4.4 Proving it on a fixture with a known O/E

Two tests in `test-hs-concordance.R`, through the existing hazard fixtures
(`helper-hazard.R`):

1. **In-sample, O/E = 1.** Conservation of events: when every phase's scale
   is free, the score equation for each `log(mu_j)` makes `sum_i H(t_i | x_i)`
   equal the number of events on the fitted data, to the optimizer's
   tolerance. Running the section on the model's own rows must return O/E
   within 1e-4 of 1 and the template must mark the cell in-sample.
   `hzr_gof()` uses the same identity.
2. **A known multiple.** A scored cohort simulated from the reference model's
   own hazard multiplied by 2: `O/E` near 2, the 95% interval covering 2,
   p below 0.001; and with the multiplier 1, the interval covering 1. Plus an
   exact check that does not depend on simulation: `E` equals the sum of
   `predict(type = "cumulative_hazard")` at each row's own time, computed in
   the test, so a mutant that predicts at `HORIZON` or at `max(TIME)` fails.

---

## 5. Addition 2: a band for the cohort-average curve

### 5.1 Three quantities, kept apart

For each grid time `t`, with `S_i(t)` patient *i*'s predicted survival and
`[L_i(t), U_i(t)]` its limits at `CLEVEL`:

| | name in the report | what it is | what it is NOT, or why it waits |
|---|---|---|---|
| (a) | **average of the patients' limits** | `mean(L_i)`, `mean(U_i)`. Exact for the mean curve only if every patient's error is perfectly correlated, so its half-width is an **upper bound** on (b)'s at the same coverage, on the scale the limits are formed on (the SD of a sum is at most the sum of the SDs) | the CI of the mean |
| (b) | **confidence interval of the mean curve** | the uncertainty of `mean(S_i(t))` from the reference model's parameter uncertainty | available yet: TemporalHazard does not expose what it needs (section 5.2) |
| (c) | **spread of the patients' predictions** | `mean(S_i) +/- SD(S_i)`, or the quartiles | a confidence interval of anything. It measures heterogeneity among patients, and does not narrow as the cohort grows |

The template asks the author to choose, with `BAND <- NULL` stopping the
render, as `OVERLAP` does: `"limits_mean"` for (a), `"spread"` for (c), and
`"mean_ci"` for (b) once it exists. `NULL` stops because the SAS habit is (a)
and an unlabelled default would rebuild it silently.

**The legend and caption name the quantity and its coverage**, always: for
(a), "average of the patients' 68% limits (an upper bound on the 68%
interval of the mean)"; for (c), "mean plus or minus one SD across patients;
not a confidence interval". The word "confidence" is never used for (c).

### 5.2 Quantity (b): what TemporalHazard 1.3.0 exposes

Read from the installed package (1.3.0), not from memory:

- `predict.hazard(se.fit = TRUE)` builds a Jacobian of each row's cumulative
  hazard with respect to the parameters, in the internal
  `.hzr_predict_with_se()`, and returns only the per-row `fit`, `se.fit`,
  `lower`, `upper`. **The Jacobian is not returned.**
- `vcov()` and `coef()` are exported methods for a `hazard` object.
- The delta method for the mean curve needs `g = mean_i(dS_i/dtheta)` and then
  `se = sqrt(g' V g)`. Without the per-row Jacobian, the only route is to
  perturb the parameters and predict, which means writing to
  `object$fit$theta`, an internal slot, and repeating the package's own
  handling of fixed parameters and the Weibull log-scale reparameterization.
  **Not proposed:** a template that reaches into a model object's internals
  breaks silently on the next TemporalHazard release.
- `hzr_evaluate()` takes supplied parameters but returns only the baseline
  curve for a multiphase model, so it cannot predict a patient.
- `hzr_bootstrap()` refits on resampled data and returns the coefficient
  draws, not predictions. A bootstrap refit also needs the reference
  cohort's data, which with `CROSS_STUDY` lives in another study, and a
  multiphase refit on 7,200 patients repeated 200 times is a server job.

**Filed:** [TemporalHazard#731](https://github.com/ehrlinger/TemporalHazard/issues/731)
(2026-11-10) asks for the mean-curve standard error directly,
`predict(..., se.fit = TRUE, average = TRUE)` returning the delta-method SE of
the row mean at each time, or the per-row Jacobian as an attribute. (b)
ships when it lands; (a), (c) and the spaghetti ship now. **Open question
Q3.**

### 5.3 The figure

One figure section in `hs-concordance`, `fig-expected-km`, per (model, group
received) cell:

- the scored cohort's **Kaplan-Meier** with its 95% band, labelled 95%;
- the **average expected curve**, `mean_i(S_i(t))`, on a grid to `TAU`;
- the chosen **band**, labelled by section 5.1;
- the **O/E and p-value** from section 4 in the caption, so the test sits
  beside the picture that cannot give one.

`hs-concordance` predicts at one `HORIZON` today, so the grid predictions are
new. They come from one `predict()` call per model, as `hs-setup`'s
`fig-expected` does, and are not saved in the artifact, which keeps its
current shape. The O/E table **is** saved, under `oe`, with `TAU` and
`TEST_LEVEL`.

### 5.4 The spaghetti plot

`fig-spaghetti`: every patient's predicted survival curve in a thin
translucent line, the average curve over it in a heavy one, per cell. It is
the picture that settles "most below 1%, mean 2%" without argument. For a
large cohort it draws a random sample of lines, `SPAGHETTI_N <- 200`, with a
fixed seed set locally via `withr::with_seed()` so the job sets no global
seed, and the caption states the sample size. The average curve is always
the full cohort's.

---

## 6. Addition 3: the mean equals the averaged curve

One `stopifnot()` per template, where the averaged curve and the patient
predictions are computed by different `predict()` calls:

- **`hs-setup`**: `obs_vs_exp$observed` comes from the per-horizon `pred`;
  `fig-expected`'s `.model` from a separate grid call. The horizons are on
  the grid by construction, so:
  ```r
  stopifnot(isTRUE(all.equal(unname(.model[match(HORIZONS, .grid)]), obs_vs_exp$observed)))
  ```
- **`hs-concordance`**: the new grid curve at `HORIZON` against
  `mean(pred$fit)` for the same model and group, and band (a) at `HORIZON`
  against `mean(pred$lower)` and `mean(pred$upper)`.

`all.equal()`'s default tolerance, because the two calls build their design
matrices separately and need not agree to the last bit.

**Also proposed, for problem 3:** `hs-setup`'s `tbl-predict` gains `mean`,
`q25` and `q75` beside its `median`, `min` and `max`, and `hs-concordance`'s
summary table gains `mean`. A skewed spread is then visible in the table that
everyone reads first. One line each. **Open question Q6.**

---

## 7. What changes, file by file

| file | change |
|---|---|
| `inst/templates/40_graphs/hs-concordance.qmd` | `GROUP` optional with one model; new study choices `TAU`, `TEST_LEVEL`, `BAND`, `SPAGHETTI_N`; sections "Observed against expected" (`tbl-oe`), `fig-expected-km`, `fig-spaghetti`; the `stopifnot` of section 6; `oe` in the saved artifact |
| `inst/templates/40_graphs/hs-setup.qmd` | the `stopifnot` of section 6; `mean`, `q25`, `q75` in `tbl-predict` (if Q6 is yes) |
| `R/observed-expected.R` | `.one_sample_logrank()` and `.cohort_curve_band()`, internal |
| `inst/templates/30_analyses/vt-explain.qmd` | a cross-reference paragraph only (section 3.2) |
| `tests/testthat/test-hs-concordance.R` | the two O/E tests of section 4.4; band labels; `GROUP = NULL` with one model, and its refusal with two |
| `tests/testthat/test-observed-expected.R` | (a) against hand-computed means; (c) never labelled a confidence interval; (a)'s standard error at least (b)'s, computed numerically in the test, on a two-patient fixture |
| `inst/templates/README.md` | one line each for the new sections, and the `vt` pointer |
| `news/<branch>.md` | the fragment |

Every new study choice carries an `EDIT:` marker with the reasoning, as the
template's existing ones do. No version bump in the pull request.

---

## 8. Open questions for the maintainer

- **Q1. The O/E interval's level. Decided 2026-11-10:** 95% by default, with
  `TEST_LEVEL` as an `EDIT:` study choice to switch it (section 4.3). The
  level is printed beside the interval whatever it is.
- **Q2. The reference model's uncertainty in the test.** The one-sample
  log-rank treats E as fixed, which makes it slightly anti-conservative. With
  7,200 against 689 that is small. Including it needs `Var(E)`, which is the
  same delta method as section 5.2 and so waits on
  [TemporalHazard#731](https://github.com/ehrlinger/TemporalHazard/issues/731). Proposed: ship the fixed-E test, say so in the report, and add
  `Var(E)` when TemporalHazard exposes it.
- **Q3. Quantity (b).** Proposed: (b) ships when
  [TemporalHazard#731](https://github.com/ehrlinger/TemporalHazard/issues/731) lands. The alternative, perturbing
  `object$fit$theta` in the template, is rejected in section 5.2 but is the
  maintainer's call if (b) is needed before TemporalHazard's next release.
- **Q4. Detecting an in-sample cell.** Proposed: a cell is in-sample when the
  model's set is this study's and its recorded selection and row count match
  the cohort's. A partial overlap (some of the scored patients were in the
  fit) is reported as a count, not resolved.
- **Q5. The test as a helper.** Settled by the `vt` decision: a second family
  will call it, so it is a helper (section 3.3).
- **Q6. Mean and quartiles in the existing tables.** Small, and squarely the
  call's problem 3, but it changes a table every existing `hs-setup` report
  prints.
- **Q7. The `hs-setup` column named `observed`.** In `obs_vs_exp`,
  `observed` is the model's average prediction, not anything observed; the
  life table is `expected`. Next to a section that compares *observed
  events* with *model-expected*, the name invites exactly the confusion of
  the call. Renaming it changes the saved artifact, which plotting jobs read.
  Raised here, not proposed for this change.

- **Q8. When `vt` gets the sections.** Proposed: a second pull request after
  the `hs` one. Its own-arm O/E is out of bag and needs the forests'
  `chf.oob` kept, which `vt-fit` may not save today; that pull request
  measures it. Whether `vt-fit` or `vt-explain` carries the sections is
  decided then, by where the twin curves and the cohort's events are both in
  hand.

---

## 9. References

- Breslow NE (1975). Analysis of survival data under the proportional
  hazards model. *International Statistical Review* 43:45-57.
- Finkelstein DM, Muzikansky A, Schoenfeld DA (2003). Comparing survival of
  a sample to that of a standard population. *Journal of the National Cancer
  Institute* 95:1434-1439.
