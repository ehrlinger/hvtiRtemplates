# `06.01-hp` template — design, 2026-08-27

Second template from [#8](https://github.com/ehrlinger/hvtiRtemplates/issues/8),
following `03.02-hz`. Replaces a SAS `HAZPRED` job plus its figure jobs: the
nomogram and the curves that overlay the actuarial estimate with the parametric
fit.

## Exemplars

Three, the same studies as `hz` — `preserve_root`, `maze/atricure/gender`,
`lv_function/survival` (census, 2026-08-27: `hp` in 3 studies).

## `hp` reads; it does not recompute

The defining property. `hp` overlays two upstream artifacts — the `ac` life
table and the `hz` fit — and reads **both by set**:

```r
ac <- readRDS(set_path("estimates", "ac.rds"))
hz <- readRDS(set_path("estimates", "hz.rds"))
```

A job that recomputes its upstream can silently disagree with it. This is also
why `03.02-hz`'s `save` chunk persists `phases` and `theta0` alongside the fits:
`hp` needs the specification, not only the estimates.

## ⚠️ Two settings that are silently wrong if omitted

Both were decoded from the `HAZPRED` source during parity work, not guessed.
Neither errors when wrong; both change every number in the nomogram.

### 1. `CLEVEL` defaults to `0.68268948`, which is ±1 SD — not 95%

`0.68268948` is exactly `pnorm(1) - pnorm(-1)` (verified to 8 digits). The
published papers say so: *"Uncertainty is expressed by 68% confidence limits
equivalent to ±1 standard error."*

**This is the same convention `%kaplan` uses.** That macro's `T_ALPHA` is `1`,
so its printed `CL_LOWER`/`CL_UPPER` are also ±1 SE. The two macros agree, and
that agreement matters *here* more than anywhere else, because `hp` is the job
that draws both bands **on one figure**:

- the figure is internally consistent — both bands are ~68%;
- anyone reading either as a 95% interval is reading a band roughly half as
  wide as they think, and nothing on the plot says which it is.

So the template labels the band with its actual coverage in the caption, and
says the same thing in prose. A default that is right and unlabelled is one
citation away from being wrong.

### 2. Survival limits are formed on the **logit** scale

`predict.hazard()` defaults to `conf.type = "log-log"`, the `survfit` standard.
SAS forms survival limits on the logit scale. Omitting `conf.type = "logit"`
does not error — it silently shifts every confidence limit.

## Two grids, not one

`maze` and `lv_function` use different grids, and both are needed because they
answer different questions:

| grid | shape | for |
|---|---|---|
| **reporting** | sparse and irregular — `30/365.2425, 3/12, 6/12, 1:10` | the nomogram table |
| **plotting** | dense, 1000 points **log-spaced** | the curves |

The plotting grid is log-spaced deliberately: `maze`'s SAS job uses
`max=log(3); min=-8; inc=(max-min)/999.9`. A linear grid to the last event time
under-resolves the early phase, which is where the action is.

A wrong grid does not error. It produces a plausible nomogram.

## ⭐ `followup-gate`

From `lv_function`, and carried because nothing else marks it: **a parametric
model returns a number at any horizon asked of it**, including horizons no
patient reached. That is extrapolation from the fitted shape, not an estimate
supported by data.

The subtlety is in how the bound is computed. It must be taken over the **same
rows the fit used** — `hz` drops rows missing either the time or the event, so
`max()` over all non-missing times includes patients the fit never saw and can
**overstate** follow-up. That weakens the guard in the one direction that
matters: it makes it under-warn.

Warning rather than stop: reporting past follow-up is sometimes the deliberate
point of a figure, and the reader needs to know, not be blocked.

## Phase decomposition

`decompose = TRUE` works on the **cumulative** hazard only. Per-phase survival
is not additive and decomposition is not supported for `type = "hazard"`. The
SAS figure overlays `_earlyh`/`_lateh`, which are *instantaneous*; this is the
nearest supported equivalent, and the template says so rather than papering
over the difference.

`predict()` returns the decomposition **wide** — one column per phase plus
`total` — so it is reshaped rather than assumed to arrive long. The components
are asserted to sum to `total`: otherwise it is not a decomposition. The
component list is derived from the returned columns rather than naming
early/late, so a three-phase model needs no edit.

## What these confidence limits are worth

Carried from `lv_function` as prose, because it governs how every number here
should be quoted:

The `hz` fit runs against a near-singular Hessian. That makes the *marginal*
standard errors on weakly identified shape parameters unstable — in parity work
they differed from SAS by 1.25× to 5.1×. The confidence limits here
nevertheless agreed with SAS to within 0.2%–5% across all thirteen grid points,
from that same covariance matrix.

Both hold at once because `se(S(t))² = gᵀVg`. The diagonal of `V` can differ
substantially while that quadratic form agrees, if the two matrices carry
compensating correlations — which is what a near-singular problem produces.

**The survival band is the trustworthy output of this pipeline; the
per-parameter standard errors in the `hz` report are not.**

## Structure

| chunk | from | purpose |
|---|---|---|
| `setup` / `edit-guard` / `set` | house | shared with `ac` and `hz` |
| `read-upstream` | maze | read `ac.rds` and `hz.rds` by set |
| `grid` | maze + lv_function | reporting grid and plotting grid |
| ⭐ `followup-gate` | lv_function | extrapolation past end of follow-up |
| ⭐ `predict` | lv_function | `CLEVEL`, `conf.type = "logit"` |
| `nomogram` | lv_function | the deliverable table |
| `fig-survival` | maze | actuarial (step) overlaid with parametric |
| `fig-hazard` | maze | hazard curve |
| ⭐ `fig-phases` | lv_function | decomposition, with the sum assertion |
| `save` | all three | nomogram CSV + figure paths, by set |

## Out of scope

Parity, as with `hz` — a parity job borrows the ordinal of the job it checks.
`hm` and `bh` follow.

## Verification

As `hz`: `lintr::lint_package()` clean, `devtools::test()`, and a scaffolded
render both unedited (must halt at `edit-guard`) and with markers stripped
(must pass it).
