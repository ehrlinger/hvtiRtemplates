# Mixed-model template: `mm`

**Date:** 2026-11-12
**Status:** Design approved by John Ehrlinger on 2026-11-12; census run on the server 2026-11-12
**Parent:** `2026-08-29-template-conversion-roadmap-design.md`, the `mm` row of the
models family (batch 6). Follows the `rm` design
(`2026-10-13-rm-template-family-design.md`) for the shared template contract and
repeats it only where `mm` differs.

## 1. Objective

Ship one unqualified template, `inst/templates/30_analyses/mm.qmd`, that fits a
linear mixed model to a continuous response measured repeatedly on each patient,
and saves population-average predictions over time for a later `mp` plot.

`mm` stays unqualified. The census in §2 found one model family written three
ways, and the three differ by a covariance choice, not by job. A qualifier per
SAS statement would split one decision across files, and the random-effects-only
form clears the gate at 7 studies, but 30 of its 47 programs come from one study (§2.2).

## 2. Evidence

### 2.1 The census

`dev/specs/artifacts/2026-11-12-mm-shape-census.py`, run on lri over `/studies`
on 2026-11-12. The public result is
`dev/specs/artifacts/2026-11-12-mm-shape-census.json`; the private CSV, which
holds paths, stays in `general/_development/mm-shape-census-20261112/out/`.

| | |
|---|---|
| SAS programs | 263 in 56 studies |
| R jobs | 1 |
| `tp.mm` template copies skipped | 1,091 |
| manual review | 18 programs |
| misfiled (no mixed fit) | 2 programs |
| migrations to `gm` / `nm` | 0 / 0 |

### 2.2 Shapes

| shape | SAS form | programs | studies | MI programs |
|---|---|---|---|---|
| `repeated_covariance` | `REPEATED / type= sub=` | 138 | 38 | 2 |
| `random_and_repeated` | both statements | 59 | 15 | 0 |
| `random_effects` | `RANDOM ... / subject=` | 47 | 7 | 31 |

30 of the 47 `random_effects` programs come from one study, which also carries
24 of its 31 MI programs.

### 2.3 Choices inside the fits

Over the 244 programs that fit a mixed model:

| choice | programs | studies |
|---|---|---|
| `type=cs` | 140 | 37 |
| `type=ar(1)` | 54 | 13 |
| `type=un` | 7 | 4 |
| `type=sp(pow)`, `sp(exp)`, `sp(gau)` | 6 | 5 |
| `method=` stated (`ml` 3, `reml` 5) | 8 | 4 |
| splines in time | 0 | 0 |
| `LSMEANS` | 12 | 5 |
| `ESTIMATE` / `CONTRAST` | 1 | 1 |
| saved predictions | 19 | 5 |
| multiple imputation | 33 | 4 |

The 1,091 template copies show that a SAS template was in wide use, which is
why the corpus is this uniform.

### 2.4 What a typical job does

Read on 2026-11-12, a `repeated_covariance` job with `type=cs` from a congenital
study. Its hash is in the private CSV. It is the shape the counts above describe:

1. A DATA step transforms time, `1/(t+1)` and `log(t+1)`, and logs the response.
2. `PROC MIXED; CLASS id; MODEL ln_y = <time terms> <covariates>; REPEATED / type=cs sub=id;`
   with no repeated effect, so a marginal compound-symmetry model.
3. The fixed effects and their covariance are saved, transposed and multiplied
   back by hand into predictions over a time grid, then back-transformed with
   `exp()` with confidence limits for plotting.

`REPEATED / type=cs` with no repeated effect equals a random-intercept model,
except that it allows a negative within-patient correlation. The template keeps
the marginal form so a ported job reproduces its SAS estimates.

## 3. Engine and ownership

`nlme`, a recommended package that ships with R, so no new dependency. It goes in
`Suggests` beside the other study-side engines. `gls()` reproduces the marginal
forms and `lme()` the random-effects forms. Both use REML by default, as SAS does.

`lme4` was rejected because it has no marginal covariance structures, so it
cannot reproduce 38 of the 56 studies as written. `glmmTMB` was rejected as a
new compiled dependency.

The fit and prediction code lives in the template, as `vt-fit`'s does, until a
second longitudinal template (`mp` or `gm`) shows what a package function should
be. The macro-allocation design left `mm` without an owner, and this keeps it
so on purpose. Nothing in `R/` is added except what §5 requires.

## 4. Study choices (`EDIT:` fields)

Names follow `rm-linear` wherever the meaning is the same.

| field | default | meaning |
|---|---|---|
| `SUBJECT`, `TYPE` | `"outcome"`, `"mixed"` | as every template |
| `DATASET`, `ANALYSIS_SET`, `WHERE`, `ID`, `JOIN`, `JOIN_VARS`, `JOIN_KEY` | as `rm-linear` | as `rm-linear` |
| `TIME` | `"time"` | the column giving each measurement's time since the reference event |
| `KEY` | `c(ID, TIME)` | one row per patient and time; the first longitudinal default the data-contract spec (§10) anticipated |
| `REDUCE` | `NULL` | kept `NULL`: a joined dataset of echoes keeps a row per record, which is the point of the job |
| `OUTCOME` | `"continuous_outcome"` | the repeated continuous response |
| `RESPONSE_SCALE` | `"identity"` | `"identity"` or `"log"`, through `.response_scale()` and `.response_term()` as in `rm` |
| `TIME_TERMS` | `c("time")` | the time terms as R expressions, e.g. `c("I(1/(time + 1))", "log(time + 1)")`, so a SAS DATA-step transform carries over line for line |
| `PREDICTORS` | `c("age", "female")` | the declared fixed effects other than time; the job selects nothing |
| `STRUCTURE` | `"cs"` | one or more of `"cs"`, `"ar1"`, `"un"`, `"random"`, `"random+cs"`, `"random+ar1"`; the first is the reported model |
| `METHOD` | `"REML"` | `"ML"` when models with different fixed effects are compared by likelihood |
| `PREDICT_AT` | `NULL` | a list of covariate profiles for the prediction grid; `NULL` uses the cohort's medians and reference levels |
| `PREDICT_TIMES` | `NULL` | the time grid; `NULL` takes 50 points over the observed range |

### 4.1 `STRUCTURE` mapping

| value | SAS | R |
|---|---|---|
| `"cs"` | `REPEATED / type=cs sub=id` | `gls(correlation = corCompSymm(form = ~ 1 \| id))` |
| `"ar1"` | `REPEATED visit / type=ar(1) sub=id` | `gls(correlation = corAR1(form = ~ visit_index \| id))` |
| `"un"` | `REPEATED visit / type=un sub=id` | `gls(correlation = corSymm(form = ~ visit_index \| id), weights = varIdent(form = ~ 1 \| visit))` |
| `"random"` | `RANDOM intercept / subject=id` | `lme(random = ~ 1 \| id)` |
| `"random+cs"`, `"random+ar1"` | both statements | `lme(random = ~ 1 \| id, correlation = ...)` |

`visit_index` is the rank of a measurement's `TIME` among the distinct `TIME` values, built by
the job, so a patient who misses visit 2 keeps visit 3 in place 3, as SAS places it. AR(1)
and UN assume shared, ordered visits; the comment beside `STRUCTURE` says so.
`"random+cs"` and `"random+ar1"` report the implied within-patient correlation, because the
split between the random intercept and the residual correlation is not identified.
Spatial-power structures (5 studies) are not offered in the first cut. The
comment points to `corExp(form = ~ time | id)` as the R form for a study that
needs one.

## 5. Guards

Each stops with a message naming the field to change:

- `KEY` is unique, but no patient has more than one row: the data is not longitudinal.
- `TIME` has missing or negative values.
- A `"log"` response has a value at or below zero (`.response_term()` already stops on this).
- `"ar1"` or `"un"` with times that do not fall on a shared visit set (more than 20 distinct times).
- `IMPUTATION` is set: MI is out of scope (§7), and a stacked fit would be silently wrong.

## 6. Report and saved output

The report shows:
- counts of patients and of measurements, and measurements per patient;
- the fixed-effects table, read on the response scale with a note for log;
- the covariance parameters, with the within-patient correlation for CS;
- when `STRUCTURE` lists more than one value, a comparison table by AIC and BIC.
  Comparison under REML is valid only because the fixed effects do not change,
  and the table says so.

The job saves two files:
- `estimates/mm.rds`: the coefficients, their covariance, the report's tables, the
  predictions and the study choices, in a bundle whose `meta$id_col` names the ID
  column. It holds no `nlme` object, because an `nlme` fit carries the patient ID
  as its grouping factor (`$groups`, and inside its correlation structure), where
  `.digest_bundle_ids()` cannot reach it. A study needing the model refits it from
  the job.
- `estimates/mm-predictions.csv`, population-average predictions over
  `PREDICT_TIMES` for each `PREDICT_AT` profile, with 95% limits from the
  fixed-effects covariance (the delta method on the linear predictor). They are
  back-transformed with `exp()` when the response is logged. This replaces the
  hand-built predictions in §2.4 and is what `mp` will read.

## 7. Non-goals for the first cut

| left out | evidence | where it goes |
|---|---|---|
| multiple-imputation pooling | 33 programs, 4 studies | a later `mm` revision; guarded in §5 |
| `LSMEANS` and contrasts | 12 and 1 programs | a later revision if a study asks |
| spatial covariance | 6 programs, 5 studies | a comment pointing at `corExp()` |
| splines in time | 0 | none |
| figures | | `mp` |
| non-normal outcomes | | `gm` |
| the 18 manual-review programs | 13 are fixed-effects repeated-measures fits with LSMEANS | read before the catalog note is written |

## 8. Catalog and documentation

- `templates.json`: `mm` moves from `queued` to `in-flight` now, and to `shipped` after the lri port in §10 step 4. Set `spec` to this
  file, `uses` to `["nlme::gls", "nlme::lme"]`, `downstream` to `["mp"]`, and
  the census counts in `note`.
- The roadmap regenerates, and `check-roadmap-counts.py` passes.
- `inst/templates/README.md`: the template row, and the `mm` line in the
  untemplated list removed.
- `.lintr`: a file key for `inst/templates/30_analyses/mm.qmd`, with the same
  per-linter exclusions as `rm-linear.qmd`.
- A `news/` fragment.

## 9. Verification

- A synthetic longitudinal fixture: 200 patients with 2 to 6 measurements each,
  a known CS correlation of 0.5, a log-normal response and a time effect in
  `log(time + 1)`. No study data.
- Tests run the chunks by label, as the `rm` tests do, and skip on CRAN like
  the other model fits:
  - `"cs"` recovers the correlation to within 0.1 and the time coefficient to
    within its standard error;
  - each `STRUCTURE` value fits and reports;
  - the comparison table appears only when `STRUCTURE` lists more than one value;
  - each §5 guard fires, mutation-checked by disabling it;
  - predictions back-transform: `exp()` of the log-scale limits brackets the
    reported prediction;
  - the template carries no study identifiers (`test-add-job.R`).
- `add_job("mm", ...)` scaffolds and the job renders end to end.
- `devtools::check()` is 0/0/0.

## 10. Build order

1. Fixture, then failing tests for §5 and §9.
2. `mm.qmd`: the setup chunk, study choices, guards, fit, report and saved output.
3. The catalog, roadmap, README, `.lintr` and news changes in §8.
4. Port one corpus job by hand against the template and compare its estimates
   with the SAS `.lst`, on lri. This is the gate before the catalog says `shipped`.
