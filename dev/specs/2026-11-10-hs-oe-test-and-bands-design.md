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

Not `vt-fit` or `vt-explain` (section 3.2). No new template, so no
two-studies gate and no ledger row.

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

### 3.2 Not `vt-fit` or `vt-explain`

The `vt` templates are random survival forests per arm, compared by RMST
difference (`2026-10-22-vt-virtual-twins-templates-design.md`). The test
needs each patient's expected **cumulative hazard** at their own follow-up
from a parametric `hm` model, which `TemporalHazard::predict(type =
"cumulative_hazard")` gives and a forest's ensemble curve does not in the same
sense. The call's model is a SAS `hs`/`hm` model. Nothing here belongs in
`vt`.

### 3.3 The helper in `R/`

The band computation (section 5) is needed in `hs-concordance` now and is a
candidate for `hs-setup`'s `fig-expected` later. One internal function,
`.cohort_curve_band()` in `R/hs-band.R`, tested directly, called as
`hvtiRtemplates:::.cohort_curve_band()` the way templates already call
`.lifetable_indicator()`. Thirty lines pasted into two templates would drift.
The one-sample log-rank is short enough to stay in the chunk, as `hs-score`'s
scoring does. **Open question Q5** asks whether it should also be a helper.

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
  appears. The level is a new constant, `TEST_LEVEL <- 0.95`, kept apart from
  `CLEVEL`. **Open question Q1.**
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

**Proposed:** ask TemporalHazard for the mean-curve standard error directly,
for example `predict(..., se.fit = TRUE, average = TRUE)` returning the
delta-method SE of the row mean at each time, or the per-row Jacobian as an
attribute. Filed as a TemporalHazard issue once this note is approved. (b)
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
| `R/hs-band.R` | `.cohort_curve_band()`, internal |
| `tests/testthat/test-hs-concordance.R` | the two O/E tests of section 4.4; band labels; `GROUP = NULL` with one model, and its refusal with two |
| `tests/testthat/test-hs-band.R` | (a) against hand-computed means; (c) never labelled a confidence interval; (a)'s standard error at least (b)'s, computed numerically in the test, on a two-patient fixture |
| `inst/templates/README.md` | one line each for the new sections |
| `news/<branch>.md` | the fragment |

Every new study choice carries an `EDIT:` marker with the reasoning, as the
template's existing ones do. No version bump in the pull request.

---

## 8. Open questions for the maintainer

- **Q1. The O/E interval's level.** Proposed 95% (`TEST_LEVEL`), because a
  p-value is reported against 0.05 and a sponsor reads an interval beside it
  as 95%. The alternative is `CLEVEL`'s 68%, consistent with every other
  interval in the `hs` templates. Either way the level is printed beside it.
- **Q2. The reference model's uncertainty in the test.** The one-sample
  log-rank treats E as fixed, which makes it slightly anti-conservative. With
  7,200 against 689 that is small. Including it needs `Var(E)`, which is the
  same delta method as section 5.2 and so waits on the same TemporalHazard
  change. Proposed: ship the fixed-E test, say so in the report, and add
  `Var(E)` when TemporalHazard exposes it.
- **Q3. Quantity (b).** Proposed: a TemporalHazard issue for the mean-curve
  SE, and (b) ships when that lands. The alternative, perturbing
  `object$fit$theta` in the template, is rejected in section 5.2 but is the
  maintainer's call if (b) is needed before TemporalHazard's next release.
- **Q4. Detecting an in-sample cell.** Proposed: a cell is in-sample when the
  model's set is this study's and its recorded selection and row count match
  the cohort's. A partial overlap (some of the scored patients were in the
  fit) is reported as a count, not resolved.
- **Q5. The test as a helper.** Ten lines; kept in the chunk unless a second
  template needs it.
- **Q6. Mean and quartiles in the existing tables.** Small, and squarely the
  call's problem 3, but it changes a table every existing `hs-setup` report
  prints.
- **Q7. The `hs-setup` column named `observed`.** In `obs_vs_exp`,
  `observed` is the model's average prediction, not anything observed; the
  life table is `expected`. Next to a section that compares *observed
  events* with *model-expected*, the name invites exactly the confusion of
  the call. Renaming it changes the saved artifact, which plotting jobs read.
  Raised here, not proposed for this change.

---

## 9. References

- Breslow NE (1975). Analysis of survival data under the proportional
  hazards model. *International Statistical Review* 43:45-57.
- Finkelstein DM, Muzikansky A, Schoenfeld DA (2003). Comparing survival of
  a sample to that of a standard population. *Journal of the National Cancer
  Institute* 95:1434-1439.
