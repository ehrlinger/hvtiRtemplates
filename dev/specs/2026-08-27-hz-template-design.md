# `03.02-hz` template — design, 2026-08-27

First template from [#8](https://github.com/ehrlinger/hvtiRtemplates/issues/8).
Replaces a SAS `PROC HAZARD` job: the multiphase parametric fit that `hp` plots
and `hm` builds its covariate model on.

## Exemplars

Three studies have an R `hz` job. This is the whole point of the two-studies
gate, and the count is a **corpus measurement, not a sample**: the 2026-08-27
census recorded `ext` and `study` per file, and filtering its 1,144 `.qmd` rows
gives `hz` in three studies (`ac` 4, `hp` 3, `bh` 2, `hm` 1).

| study | file | shape |
|---|---|---|
| `preserve_root` | `analyses/R_hazard/qmd/02-hz-dead_pa.qmd` | `E+C`, interval-censored |
| `maze/atricure/gender` | `distributions/dead-hz-03.02-hz.qmd` | `E+L`, no interval censoring |
| `lv_function/survival` | `analyses/R_hazard/example-jobs/hz.example.qmd` | no SAS predecessor |

⚠️ Lower bound: the census counts `.qmd` only, so a job written as `.R` or
`.Rmd` is invisible to it. The error direction is undercounting.

## What the three disagree about, and why both answers are kept

**Starting values.** `maze` and `preserve_root` seed `theta` with **SAS's own
converged estimates**, so that "any disagreement is about the likelihood rather
than about where the search began". `lv_function` seeds **neutral shapes**
(`1` = no shape) with the early-phase scale taken from the quarter-point of
observed event times — "a rough neighbourhood, not an estimate".

These are not competing styles. They are two different jobs:

| | seed from | because |
|---|---|---|
| **Shape A** | SAS's converged estimates | replacing an existing SAS job — the seed makes the comparison clean |
| **Shape B** | neutral shapes + a data-derived scale | no SAS predecessor — there are no estimates to seed from |

Extracted from either exemplar alone, the template would have made the other
case silently wrong: seeding neutral where SAS estimates exist discards the only
clean comparison, and seeding from "SAS's estimates" where there are none is
incoherent. So the chunk carries both, as the `03.01-ac` `cohort` chunk already
does for whole-study versus filtered cohorts, and the `EDIT:` marker is the
choice between them.

## Structure

The union of the three, ordered as the analysis runs. Chunks marked ⭐ exist in
only one exemplar and are carried because their absence is silent.

| chunk | from | purpose |
|---|---|---|
| `setup` | all three | root resolution, packages |
| `edit-guard` | (#27) | stop on unresolved markers |
| `set` | maze | `ENDPOINT`/`TYPE`, `set_path()` |
| `cohort` | maze | Shape A / Shape B gate, per `03.01-ac` |
| ⭐ `numderiv-gate` | lv_function | hard stop if `numDeriv` is absent |
| `phases` | all three | phase specification |
| `start` | A: maze, B: lv_function | starting values, both shapes |
| `response` | maze, preserve_root | `Surv()` construction from the SAS censoring statements |
| ⭐ `response-check` | lv_function | event counts, fitted vs cohort |
| `guard` | maze, preserve_root | a positive log-likelihood is impossible |
| `fit` | all three | the reported fit |
| `convergence` | lv_function, preserve_root | converged, iterations, `rcond`, `pd` |
| `multistart` | all three | did the starting point matter |
| `noconserve` | maze, preserve_root | conservation sensitivity |
| ⭐ `conservation-binding` | maze | Σ Λ(tᵢ) under both settings |
| `estimates` | lv_function | coefficients on their natural scale |
| `save` | all three | `saveRDS()` to `set_path("estimates", ...)` |

### Why `numderiv-gate` is a stop and not a warning

`numDeriv` is a `Suggests` of `TemporalHazard`. Without it, an interval- or
left-censored multiphase fit **silently produces no standard errors**: the fit
succeeds, `converged` is `TRUE`, and `vcov()` is simply absent. A model reported
without uncertainty is not a smaller result, it is a different one.

### Why `conservation-binding` is carried from one exemplar

`Σᵢ Λ(tᵢ)` is what `conserve` pins to the event count. Reporting it under both
settings is the only way a reader can distinguish *"the control did nothing"*
from *"the control had almost nothing to do"* — identical in the likelihood
column, opposite in meaning.

### Why `multistart` probes run at `n_starts = 1`

Multi-start is what makes the reported fit robust: it perturbs around its start
until it escapes small basins — which is exactly what would **hide** a second
basin from this check. A single start goes where its starting point leads, so it
is the thing that actually finds another optimum if one is there. Every probe
row must differ from every other; a duplicated start costs time and tests
nothing.

## Two traps carried forward as comments

Both were found the expensive way in the exemplars, and both are invisible on
inspection:

1. **`vcov()` includes fixed parameters as all-`NA` rows**, so `rcond()` on it
   errors. Read `rcond` and `pd` off the fit, which computes them on the free
   parameters — which is also what SAS's condition number refers to.
2. **`else` must not begin a line at top level.** `if (a) x` newline `else y` is
   a parse error, and knitr captures it into the document and carries on, so the
   chunk "runs" and silently emits nothing. Brace it.

## Out of scope

**Parity.** `03.01-ac` has no parity chunk and `maze` carries
`parity/dead-hz-03.01-ac-parity.qmd` as a separate document; the house rule is
already that a parity job borrows the ordinal of the job it checks. `maze`'s
`hz.qmd` carrying an inline parity chunk *and* a parity document is the
exception. A parity template is its own piece of work.

**`hp` and `hm`.** Separate PRs, in that order — `hp` reads what this job
writes, and `hm` fixes its shape parameters at this job's converged values.

## Verification

Per #27, tests over the source are not evidence a template runs:

1. `devtools::test()` — including the two guards added in #27, which apply to
   this template automatically.
2. Scaffold with `new_job("hz", ...)` into a fake study and render **unedited**:
   must stop at `edit-guard`.
3. Render with markers stripped: must get past the guard and fail only for want
   of real data.
4. `lintr::lint_package()` clean.
