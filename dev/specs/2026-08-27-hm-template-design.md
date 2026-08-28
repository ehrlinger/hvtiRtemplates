# `04.01-hm` template — design, 2026-08-27

Third template from [#8](https://github.com/ehrlinger/hvtiRtemplates/issues/8).
Replaces a SAS `PROC HAZARD` job with a `selection` statement: the
multivariable risk-factor model built on the shape parameters `hz` fitted.

Depends on **hvtiRutilities ≥ 1.1.4**
([#47](https://github.com/ehrlinger/hvtiRutilities/issues/47)), which ships the
candidate-pool helpers this template calls. Before that release they existed
only in one study's local `R/`, and templating against them would have produced
a job that stops on arrival anywhere else.

## Exemplars — one R, one SAS, and that is the point

| exemplar | kind | what it contributes |
|---|---|---|
| `lv_function/survival/.../hm.example.qmd` | R, 635 lines | the whole R chain: covariate audit, two-stage fit, selection diagnostics |
| `dm_nodm/analyses/hm.dead.sas` | SAS | two stages the R exemplar has **no equivalent for** |

The corpus census counts `hm` in **one** study as an R job and **384** as a SAS
job. So unlike `hz` and `hp`, the second exemplar here is a SAS job rather than
a second R port — which is enough for the purpose, because the gate exists to
stop one study's choices being encoded as general, and a SAS job states those
choices as plainly as an R one does.

### What the second exemplar added

Reading `hm.dead.sas` against `hm.example.qmd` found two stages present in SAS
and absent from R:

- **`%check`** — refit with `selection forward … maxsteps=0`, forcing the final
  model, to compute Q-statistics for factors the screen may have overlooked.
- **`%deciles`** — a deciles-of-risk calibration table,
  `%deciles(in=built, event=dead, interval=im_dead, time=10, groups=10, …)`.

`TemporalHazard` already exports `hzr_deciles(object, time, groups, status,
event_time)` and `hzr_gof()`, so the second of these maps directly and the
first has a partial equivalent. From the R exemplar alone the template would
have shipped a model-selection job that never asks whether the model
**calibrates** — and nothing in its output would have looked missing.

Conversely the R exemplar carries checks SAS has no equivalent for, kept for
the same reason: `selection-monotone`, `multistart`, `numderiv-gate`.

⚠️ **`hm.dead.sas` also defines `%macro final` and never invokes it**, and that
macro's variable list (`prev_avr`, `ao_prg`, `ms_valv`) is aortic-valve
leftovers pasted into a CABG-diabetes study. The `.lst` shows only `%model`.
Reading the `.lst` alone would have shown neither the dead macro nor the wrong
variables — which is why the template's `covariates` chunk reads the `.sas`.

## ⚠️ Two silent traps specific to this job

### 1. `hzr_stepwise()`'s defaults are not SAS's

| | `hzr_stepwise()` default | typical SAS `selection` |
|---|---|---|
| entry | `slentry = 0.3` | `sle = 0.1` |
| stay | `slstay = 0.2` | `sls = 0.07` |

Accepting the R defaults runs a **different screen** from the job being
reproduced, admits more variables, and does not error. The template sets them
from the `.sas` and marks them `EDIT:`.

### 2. The default `criterion = "score"` has a known defect

[temporal_hazard#130](https://github.com/ehrlinger/temporal_hazard/issues/130):
the score criterion *declines the strongest candidates*, because the observed
information goes indefinite at `beta = 0`. The template says so at the call
site rather than leaving a reader to discover it from a screen that quietly
passed over the best variable.

## Covariates are read out of the SAS job, never transcribed

`sas_variable_block()` takes only the names; a `name=value` block carries the
*other* study's converged answers and must not be inherited. A transcribed list
drifts from the job it claims to reproduce and nothing catches it.

## The covariate audit is not optional

`%vars(missing=1, impute=1)` mean-imputes and adds a paired `ms_*` indicator,
so a 0/1 clinical variable arrives carrying **three** values — 0, 1, and the
cohort mean. In SAS these are numeric and enter **linearly**. Read into R they
arrive as **factors** and are dummy-coded, which is a different model with a
different parameter count, and nothing in the output says so.

`covariate_audit()` reports the decision per variable and the template
**stops** on any `ERROR` action rather than fitting a model whose covariates are
not what the job specifies.

## Two stages, and why it is not one

Fitting shapes and 40 covariates together from a neutral start **lands in the
wrong basin and reports `converged = TRUE` while doing it**. The SAS job itself
fixes the shapes for selection (`fixthalf fixm fixnu fixeta`) and frees them
only for the final fit.

- **Stage 1** holds the shapes at the `hz` fit and fits the covariates.
- **Stage 2** frees the shapes, starting from stage 1.

The comparison is **reported, not assumed**, and which stage is reported is an
`EDIT:` decision with the evidence table beside it. On the R exemplar's study,
freeing the shapes gained 0.014 in objective, moved no covariate by more than
3e-4, turned `pd` from `TRUE` to `FALSE`, and left two shape parameters with no
standard error — so stage 1 was reported, a deliberate divergence from SAS
`%final`.

## Structure

| chunk | from | purpose |
|---|---|---|
| `setup` / `edit-guard` / `set` | house | shared |
| `numderiv-gate` | lv_function | no `numDeriv` means no standard errors, silently |
| `vars` | lv_function | time, event, interval flag, and which `.sas` to read |
| `covariates` | lv_function | `sas_variable_block()` per phase |
| `audit` | lv_function | `covariate_audit()`, stop on ERROR |
| `collinear` | lv_function | `pool_collinear_pairs()` — `male`/`female` are exact complements |
| `cohort` | house | Shape A / Shape B gate |
| `phases` | lv_function | shapes from the companion `hz` job |
| `fit` | lv_function | two stages |
| `stages` / `reported` | lv_function | evidence, then the choice |
| `estimates` | lv_function | coefficients, IQR-scaled |
| `selection` | lv_function | read the companion runner's result |
| `selection-monotone` | lv_function | a forward step cannot lower the log-likelihood |
| `selection-crowding` | lv_function | `selection_crowding()` |
| ⭐ `calibration` | **dm_nodm** | `hzr_deciles()` — observed vs expected by decile of risk |
| ⭐ `gof` | **dm_nodm** | `hzr_gof()`, the nearest equivalent to `%check` |
| `save` | all | persist for `hs`/`bh` |

## The ordinal: `04.01`, and a correction to §5 of the layout spec

`analyses` is major `04`, and `hm` is the first `analyses` row in
`hvti_taxonomy()`, so `04.01`.

⚠️ §5 of `2026-08-21-template-set-layout-design.md` says the minor is *"the next
free position within it"*. The rule that actually reproduces every shipped
ordinal is **positional by taxonomy row** — `ac` and `hz` are the 1st and 2nd
`distributions` rows, giving `03.01` and `03.02`.

The two agree for everything templated so far, so nothing has caught it. They
diverge on the **third** `analyses` template: next-free gives `hm`=04.01,
`bh`=04.02, `hs`=04.03, and `order(ordinal)` then disagrees with
`order(taxonomy row)` because `hs` precedes `bh` in the taxonomy — a red test
in `test-taxonomy.R` whose only fix is renumbering a shipped template, which §5
promises never happens.

Positional avoids it: `hm`=04.01, `hs`=04.02, `bh`=**04.06**. This PR corrects
the spec wording.

## Out of scope

- **Running the selection.** It is a long job; the exemplar runs it from a
  companion script and this template reads the saved result, reporting
  "not run" when absent rather than silently reporting nothing.
- **Parity**, as with `hz` and `hp`.
- `bh` follows.

## Verification

As `hz` and `hp`: `lintr::lint_package()` clean, `devtools::test()`, and a
scaffolded render both unedited (must halt at `edit-guard`) and with markers
stripped (must pass it). Plus: `hzr_deciles()` and `hzr_gof()` exercised
against a synthetic fit, since the template is the first caller of either.
