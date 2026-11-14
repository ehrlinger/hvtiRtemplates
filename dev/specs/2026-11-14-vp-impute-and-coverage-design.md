# vp family: impute before varPro, and never read "not examined" as "screened out"

Status: decided, 2026-11-14. Every decision in §2, D1 to D9, is John Ehrlinger's of 2026-11-14.
Branch `feat/vp-impute`, cut from `origin/main` `5ee1663`. Lands after 1.6.0.
Source: vault task "vp templates - impute before varPro instead of dropping".

## 1. Problem

Two defects in the `vp` family make the same mistake. Each one reports a variable the screen never looked at
as though the screen had looked at it and found nothing.

**A. Patients are lost.** `varpro()` and `uvarpro()` remove every incomplete row. They accept `na.action` and
ignore it. Every entry point opens with a bare `rfsrc()` that inherits `na.action = "na.omit"` (varPro 3.3.0's own help now says
"Incomplete observations are removed"). The loss compounds as roughly `(1 - m)^p`: 5% MCAR over 10 predictors
kept 235 of 400 rows. On `main`, `vp-fit.qmd` (`tbl-missing`) and `vp-dependence.qmd` both call
`.missing_cases(..., action = "drop")` and then `complete.cases()`. That discloses the loss but cannot avoid it.
This contradicts the 2026-10-22 family decision that missing covariates are a study choice, with forest imputation as
the default. `vt-fit` implements that decision (`NA_ACTION`) and `sid-fit` imputes before clustering. The `vp` family
never got it. A submitted paper's supplementary figure was drawn on 240 of 774 children this way.

**B. Features are counted as screened out when they were never examined.** The full fit runs the exploration
setting (`SPLIT_WEIGHT <- FALSE`, `MTRY` near `sqrt(p)`). It tests about 28 of 30 candidates in the reference
simulation. Three things still let an unexamined variable read as a negative result:

1. `MAX_UNTESTED <- 0.5`. Half the candidates may go untested before the render stops, ten times what the
   exploration setting needs.
2. The refit vote divides by `REPEATS`: "a refit that drops a variable counts against it" (`vp-fit.qmd`, `stability`
   chunk). A variable tested in 3 of 20 refits and selected in all 3 scores `share_selected = 0.15`, which is the
   same number as a variable tested in all 20 and selected in 3. Only the second is evidence against it. The refits
   are not held to `MAX_UNTESTED` at all.
3. The handoff `vp.rds` carries `selected` and the full `coverage` table, but no list of variables that were not
   examined. `vp-explain` drops an untested name from `PARTIAL_VARS` with a note. `vp-individual` marks `tested`. Neither says
   that the screen could not rule the variable in or out.

`vp-dependence` calls `uvarpro(d_noise, ntree = NTREE, ...)` with varPro's defaults for `max.tree` (200) and
`max.rules.tree` (20), and reports no coverage. Whether every variable gets release rules there is unmeasured.

The two defects interact. Dropping rows lowers events, and lower events lower coverage (see `vp-fit`'s note on
60 versus 150 events), so imputation alone will raise the share of candidates tested.

## 2. Decisions

| # | decision | rationale |
|---|---|---|
| D1 | `NA_ACTION <- "na.impute"` is the default in `vp-fit` and `vp-dependence`; `"na.omit"` is today's behavior | matches the 2026-10-22 decision |
| D2 | NEWS line only; `upgrade_job()` does **not** pin `"na.omit"` into jobs that already ran | John, 2026-11-14 |
| D3 | the outcome (`TIME`/`EVENT`/`RESPONSE`) is **excluded** from the imputation model | imputed predictors must carry no endpoint signal, or the screen can rank a predictor on information the imputation put there |
| D4 | spelling `"na.impute"` / `"na.omit"`, validated with `match.arg()` as `vt-fit` does | one setting reads the same across the forest family |
| D5 | a missing outcome is always dropped, never imputed, and counted on its own row | only predictors are imputed |
| D6 | forest imputation only, no `"mice"` option (was O1) | the family is forest-native; `sid-fit` carries MICE for its SAS validation |
| D7 | `MAX_UNTESTED` defaults to `0.1` (was O2) | the exploration setting leaves about 7% untested |
| D8 | the refit vote counts only refits that tested the variable; below `MIN_TESTED_SHARE <- 0.5` it gets no vote and is "not examined in the refits" (was O3) | an unexamined refit is no evidence |
| D9 | measure `uvarpro()` coverage before changing `vp-dependence` (was O4) | change only what a measurement shows |

## 3. Design A: impute before varPro

### 3.1 Order of operations in `vp-fit`

```
read -> drop rows missing the outcome (counted) -> refuse sparse predictors (> MAX_MISSING, listed)
     -> impute the remaining predictors ONCE (seeded, cached) -> add noise -> full fit
                                                             \-> subsample -> add noise -> refit (x REPEATS)
```

- **Impute once, before noise and before subsampling.** The refits subsample the imputed data. They do not
  re-impute. Re-imputing per refit would mix imputation noise into the stability vote. Imputing after noise is
  added would let the noise columns into the imputation model. State this in the template comment so a later edit
  does not reinvent it.
- `vp-dependence` follows the same order. Its optional `OUTCOME` is treated as the outcome under D3 and D5: rows
  missing it are dropped, and it stays out of the imputation model, because the graph measures edges into it.
- `"na.omit"` keeps today's path exactly: `.missing_cases(action = "drop")` and then `complete.cases()`. A test
  asserts identical output.

### 3.2 The imputation

- `randomForestSRC::impute(data = d[PREDICTORS], ntree = 250)` under `cache_fit("vp-fit-impute", ..., seed = SEED)`.
  This follows `sid-fit`'s `impute` chunk with `IMPUTE = "forest"`. Only the predictor columns are passed (D3).
  Forest only, no `"mice"` option (D6).
- `MAX_MISSING <- 0.4`, `EDIT:`-marked, same meaning as `sid-fit`'s: a predictor missing in a larger share is
  listed and refused, not filled. The render stops and asks the author to remove it from `PREDICTORS` or raise the
  ceiling. The comment carries the counter-case: in one study, preop labs were missing for most of the events and
  missingness tracked surgical era, so imputation would have handed the model an era proxy. There, complete cases
  were chosen on purpose. That is what `"na.omit"` is for.
- Imputation in `"na.impute"` mode is always followed by a check that no `NA` remains in `PREDICTORS`. varPro would
  otherwise drop rows silently, the defect this spec removes.

### 3.3 Counting

`tbl-missing` reports in either mode:

| row | meaning |
|---|---|
| supplied | rows after the analysis set, before anything here |
| outcome missing (dropped) | D5 |
| predictor missing, by variable | count and share |
| refused (> `MAX_MISSING`) | listed, with share |
| imputed, by variable | `"na.impute"` only |
| dropped for a missing predictor | `"na.omit"` only |
| used | rows the fit sees |

A sentence beneath names the rule that applied: "Missing predictor values were imputed once by random forest
(outcome excluded) before the screen", or "Patients missing any predictor were excluded". `.cohort` gains
`n_supplied`, `n_used`, `n_imputed` (named integer vector by variable) and `na_action`. These reach `vp.rds` through
`.attach_handoff_lineage(cohort = )`. `vp-explain` and `vp-individual` print them in their own "About this run"
block, so a downstream figure cannot quote a different n from the screen it explains.

As a cross-check, varPro 3.3.0 records `model.info$observations` (`input`, `retained`, `omitted`). In `"na.impute"`
mode a test asserts `omitted == 0`. In `"na.omit"` mode `omitted == 0` holds too, because rows are dropped before
the call.

### 3.4 Methods text

Each template's narration gains a paragraph a study's Methods can copy. It names the rule, the ceiling, that the
outcome was excluded from the imputation model and why, and that imputation was done once before the stability
refits.

## 4. Design B: examined versus screened out

Every candidate ends in exactly one of three states, and every table, handoff and downstream report keeps them
apart:

| state | full fit | meaning |
|---|---|---|
| **selected** | tested and z above the bar | the screen kept it |
| **examined, not selected** | tested and z at or below the bar | evidence, weak, that it adds nothing beyond the others |
| **not examined** | not eligible, or tested in fewer than `TRIM` of trees | no evidence either way |

### 4.1 Full fit

- **`MAX_UNTESTED` defaults to `0.1` (D7).** The exploration setting leaves about 2 of 30
  untested (7%), so 0.1 passes it and stops anything materially worse. The stop message names the untested
  variables and the levers (`MTRY`, `MAX_TREE`/`MAX_RULES_TREE`, `TRIM`). `NULL` still means report only.
- The parsimonious-screen comment keeps its warning that it will trip the ceiling on wide data.

### 4.2 Refit vote

- `share_selected` is computed over the refits **that tested the variable**, not over `REPEATS`. `share_tested` stays
  beside it.
- **Minimum examination (D8).** A variable tested in fewer than `MIN_TESTED_SHARE` of refits (`0.5`, `EDIT:`-marked)
  gets no vote. Its state is "not examined in the refits", and it is neither handed on nor counted as rejected.
  Such variables are listed under the stability table.
- This reverses the current comment ("a refit that drops a variable counts against it"). That rule was deliberate. It
  penalized variables whose testing depended on the subsample. Under this design that dependence is shown in
  `share_tested` and the third state, not folded into a "no" vote.

### 4.3 Handoff and downstream

- `vp.rds` gains `not_examined` (character, full fit) and, with refits, `not_examined_refits`.
- `vp-explain`: a `PARTIAL_VARS` name in `not_examined` gets "not examined by the screen (no evidence either way)"
  instead of today's "did not test them".
- `vp-individual` labels the same variables "not examined", not a bare `tested = FALSE`.

### 4.4 `vp-dependence`

- **Measure first (D9):** measure coverage for `uvarpro()` before changing it. Count the variables with no release rule at
  `ntree = NTREE`, `max.tree = 200`, `max.rules.tree = 20` on the template's fixture and on a 30-variable
  simulation. If any go unexamined, expose `MAX_TREE`/`MAX_RULES_TREE` as `vp-fit` does and report the same
  three states. If none do, record the measurement in a comment and change nothing.
- **Measured (2026-11-14, `dev/vp/uvarpro-coverage.R`, varPro 3.3.0, one thread):** at varPro's defaults
  (`max.tree = 200`, `max.rules.tree = 20`) real variables went unexamined in most configurations. Sweeping
  `max.tree` in (200, `NTREE` = 500) and `max.rules.tree` in (20, 50, 100, 150): in the four configurations Task 6
  measured, every pair at 500 trees covers every real variable and none at 200 does. The rule count follows
  `max.tree` (about 10 a tree) and barely moves with `max.rules.tree` from 20 up. `uvarpro()` took 0.2 to 4.4 s; the
  table is in the script's header.
- **But no pair covers the template's own shape.** Three of those four configurations carry no noise columns, which
  the template always adds. A fifth, the 30-variable configuration with the template's 20 noise columns, left 15 to 19
  of 31 real variables without a rule at 500 trees: its one factor is the only categorical source, so half the noise
  columns are binary copies of it, and they took nearly half the rules. 2,000 trees still left 7 to 10. On the
  fixture shape, 500 trees left a real variable without a rule at 7 of SEED = 1 to 30 (200 trees at 23).
  The rule limits are not the lever for this; the noise draw is (next bullets).
- **Decided (John Ehrlinger, 2026-11-14): report now, fix the noise next.** `MAX_TREE <- 500` (passed as
  `min(MAX_TREE, NTREE)`, so every tree) and `MAX_RULES_TREE <- 20`, `EDIT:`-marked beside `NTREE`, and
  **`MAX_UNTESTED <- NULL`**: the coverage table reports every unexamined variable and the handoff carries them,
  but the render does not stop unless a study sets a share. The measured reason: `vp_add_noise()` draws half the
  `NOISE_N` columns from the categorical candidates whenever any exist, and on 30 variables those permuted copies
  take enough of the rules (about 2,100 of 4,800 with one binary factor) that 15 to 19 of 31 real variables went
  unexamined at 500 trees and 7 to 10 at 2,000, past any affordable `NTREE`. A numeric default would stop most such
  renders. **The cost is the lasso, not the forest:** `get.beta.entropy()` fits one per rule, and on the fixture
  shape took 51 s at 500 trees against 20 s at 200, paid for the full fit and for each refit.
- **Follow-up:** redesign `vp_add_noise()` in `vp-dependence` so the noise kinds are drawn in proportion to the
  candidates, not half and half. That is what lets the gate default on (a share such as 0.1).
- **Report:** a `tbl-coverage` table after the fit names each variable's rule count and whether it was examined;
  the handoff carries `not_examined`. An unexamined variable has no rule, so no edge leaves it; it is still a
  predictor in every other variable's lasso, so edges into it can still appear. In the stability table an edge's
  share is over the refits that examined the variable it leaves (its tail: the graph is directed, and a variable
  with no rule is still a column in every lasso), with that count beside it, and NA when none did; a variable's
  signal-set share is over the refits that examined it. Both follow `vp-fit`'s vote (§4.2).

## 5. Tests (testthat edition 3)

1. Fixture with 5% MCAR over the predictors, plus outcome `NA` in a few rows.
   - `"na.impute"`: `n_used == n_supplied - n_outcome_missing`. No `NA` reaches `varpro()`. `model.info$observations$omitted == 0`.
   - `"na.omit"`: output identical to `main`'s (snapshot of the counts table and the selected set under a fixed seed).
   - A predictor above `MAX_MISSING` stops the render with its name in the message.
   - The outcome column is not passed to `impute()` (assert on the cached call's data columns).
2. Refit vote: a synthetic `.stab` where variable `a` is tested 3/20 and selected 3/3, and `b` is tested 20/20 and
   selected 3/20. They must land in different states (`a` not examined, `b` examined and not selected). Mutation check:
   revert to the `/ REPEATS` denominator and confirm the test fails.
3. `MAX_UNTESTED`: a fit with 3 of 10 untested stops at 0.1 and passes at `NULL`.
4. Handoff: `not_examined` is present, and `vp-explain` prints the new wording for a not-examined `PARTIAL_VARS` name.
5. End-to-end renders of all four `vp` templates with `NOT_CRAN=true`, from a private library (`R CMD INSTALL -l`).
   Expect `SKIP 0` on macOS.

## 6. Out of scope

- The supplementary-figure refit for the paper above. That decision belongs to that paper's revision task.
- Filing "`varpro()` accepts `na.action` and ignores it" upstream at kogalur/varPro. That is a separate one-line
  task, next to varPro#5.
- `vt-fit` and `sid-fit` are unchanged.

## 7. Release notes

`news/feat-vp-impute.md`, roughly:

- `vp-fit` and `vp-dependence` now impute missing predictor values once, by random forest and without the outcome,
  before the screen (`NA_ACTION <- "na.impute"`), instead of dropping every patient with a missing value.
  **Existing jobs will use more patients and may select differently on their next render.** Set
  `NA_ACTION <- "na.omit"` to keep complete cases.
- The `vp` reports now separate *not examined* from *examined and not selected*. The refit vote counts only the
  refits that tested a variable, and `MAX_UNTESTED` defaults to 0.1 (was 0.5).
