# nb-boostmtree: a template for boosted multivariate trees on longitudinal data

**Date:** 2026-10-01
**Status:** design. Every decision here was made by John Ehrlinger on 2026-10-01,
in the order the sections appear. Nothing is built yet.
**Reads with:** the data contract (`2026-09-29-template-data-contract-design.md`),
issue #203 (no patient identifier in saved files), and the catalog row for `nb`
in `inst/extdata/templates.json`.
**Packages:** `hvtiRtemplates` for the template and the catalog; the fitting
package `boostmtree` from the CCF fork; `ggBoostedTrees` for the figures. Neither
package changes.

This note is self-contained. It assumes no memory of the session that produced it.

⚠️ No study, variable or patient identifier appears here. `ccfid`, `mrn`,
`iv_echo` and the like are column names, not values, and the exemplar studies are
named only by tree and topic.

## 1. What was asked

Add a template for boostmtree jobs. The `nb` (Boosting) job type is `queued` in
the catalog, blocked on ggBoostedTrees#9, and covers two methods: boostmtree and
BoostMLR. Only boostmtree has ggBoostedTrees figures today.

**Decision:** a qualified template, `nb-boostmtree`, now. The `nb` row splits into
`nb`/`boostmtree` (shipped) and `nb`/`boostmlr` (queued, still blocked on
ggBoostedTrees#9). A prefix must be wholly qualified or wholly unqualified
(`check-roadmap-counts.py`), so both rows carry a qualifier.

## 2. Exemplars

The two-study gate is met many times over. The census (2026-09-02) records 12
studies with `nb` jobs qualified `Boostmtree`, 49 jobs in all, and a read of 13
jobs across 12 studies on 2026-10-01 (cardiac, thoracic, vascular and general
trees) found one shape:

- **Data.** Already long, one row per visit, built upstream. Columns with two or
  fewer distinct values become factors, rows with a missing response are dropped,
  and a keep or drop list chooses the predictors.
- **Fit.** One call in every job:
  `boostmtree(x, tm, id, y, family, M, nu, mod.grad = TRUE, cv.flag = TRUE)`.
  No job passes `K`, `d` or `ntree`, or runs a selection step first. Missing
  predictors are left to the package.
- **Figures.** Observed against predicted, the `rho` and out-of-bag error paths
  over `M` with the best `M`, variable importance, partial and marginal plots for
  chosen variables, and a spaghetti plot of patient traces with the mean overlaid.
- **Saving.** `save(fit.cv, ...)` to `estimates/`, then the fit is commented out
  and `load()`ed on later runs. The saved fit carries the ID; one study's ID
  column is `mrn`.

**What varies by study** becomes `EDIT:` settings: the ID, time and response
columns; the family (continuous most often, then binary, then ordinal); `M` (100
to 1000) and `nu` (0.01 or 0.05); the predictor list; which variables get effect
plots; and occasionally a row filter.

**Out of scope, seen once or twice:** train/test validation with `predict()` (one
study), and by-group refits (two studies). An analyst runs the job once per group
with `WHERE`.

## 3. The fitting package

**Decision:** fit with `boostmtree` from the CCF fork, version 2.0.2 or later.

Every exemplar fits with `cv.flag = TRUE`. In upstream `boostmtree`, that flag
skips the in-sample refresh inside the boosting loop, so the ridge penalty
collapses and the stored coefficients diverge linearly in `M`. Everything that
reads the non-cross-validated path is wrong: `predict(..., use.cv.flag = FALSE)`,
`partial.plot()`, `marginal.plot()` and `vimp()`. Reported upstream as
kogalur/boostmtree#2, with the fix in kogalur/boostmtree#3, open since
2026-09-03. CRAN carries 2.0.0, with the bug. The fork,
`ehrlinger/boostmtree_src` (package in its `boostmtree/` subdirectory, tag
`v2.0.2-ccf`), carries the fix and keeps the package name `boostmtree`.

The template's setup chunk requires `boostmtree (>= 2.0.2)` and otherwise stops
with the install line:

```r
remotes::install_github("ehrlinger/boostmtree_src", subdir = "boostmtree", ref = "v2.0.2-ccf")
```

and a comment saying why. Today the version floor separates the fork from CRAN.
⚠️ If upstream ever releases a 2.0.2 or later without the fix, the floor would
pass it; revisit the check when upstream moves. `hvtiBoostmtree` is not used.

The fork's `README-ccf-fork.md` still names the tag `v2.0.1-ccf`; it is stale and
should be corrected in that repository.

## 4. Settings and data

In `edit-study-choices`, every study-specific line marked `EDIT:`:

- **The data contract.** The shared block: `DATASET <- "study"`,
  `ANALYSIS_SET <- NULL`, `WHERE <- NULL`, `ID <- "ccfid"`. Then
  **`KEY <- c(ID, TIME)`**: the data hold one row per visit, so the ID alone does
  not make a row unique, and `read_job_data()` then catches duplicated visits.
  This is the first template whose default `KEY` is not `ID`.
- **The model's columns.** `TIME <- "iv_echo"` (the visit time, in years),
  `RESPONSE <- "<response>"` (a placeholder the analyst must replace) and
  `FAMILY <- "continuous"` (or `"binary"`, `"ordinal"`, `"nominal"`).
- **Predictors.** `PREDICTORS <- NULL` takes every column but `ID`, `TIME` and
  `RESPONSE`, as every exemplar does. A vector restricts the fit to those
  columns. The job stops when `PREDICTORS` names the resolved ID or `TIME`, or
  when `RESPONSE` is the resolved ID.
- **The fit.** `M <- 1000` and `NU <- 0.05`, the commonest pair; the comment says
  studies used 0.01 to 0.05, and that a smaller `nu` needs a larger `M`.
  `cv.flag = TRUE` and `mod.grad = TRUE` are fixed, not settings: every exemplar
  uses them, and `cv.flag = TRUE` is how the job finds its best `M`.
  `SEED` seeds the fit and the trace sample.
- **Figures.** `EFFECT_VARIABLES <- NULL` draws partial effects for the top six by
  importance, or a vector names them. `N_TRACES <- 100` sets how many patients the
  trace plot samples; `Inf` draws every one.
- **Refitting.** `REFIT <- FALSE`; `TRUE` forces a refit (section 5).

The `data` chunk reads through `read_job_data()` and prints the record and any
attrition, as every converted template does. It then converts text predictors to
factors with a note naming them, as the random-forest family does, and drops rows
with a missing response, reporting how many: `boostmtree` can impute missing
predictors but not a missing response.

## 5. The fit, the cache and what is saved

**Fit.** `boostmtree(x = d[PREDICTORS], tm = d[[TIME]], id = d[[.id]],
y = d[[RESPONSE]], family = FAMILY, M = M, nu = NU, mod.grad = TRUE,
cv.flag = TRUE)` inside `withr::with_seed(SEED, ...)`, where `.id` is the ID
column `read_job_data()` resolved, possibly the MRN fallback. `boostmtree` takes
vectors, not a formula, so the formula-environment leak found in the hazard and
random-forest families does not arise; the byte test checks it regardless.

**Cache.** The fit is saved to `estimates/` as
`<subject>-<type>-nb-boostmtree.rds` and reused on a later render when both the
selection's `key_hash` (the rows) and the fit settings (`FAMILY`, `M`, `NU`,
`PREDICTORS`, `SEED`) match; anything else refits, and `REFIT <- TRUE` forces it.
This replaces the exemplars' save, comment out, `load()` pattern, which is how a
stale fit gets reported against new data.

**What is saved (#203).** The saved fit's identifiers are replaced by the
study-keyed digest through `.digest_bundle_ids()` and read back through
`.bundle_id_key()`, so a lost or replaced key stops the job. That covers `$id`
and **`$id.unique`**, which `gg_boost_trajectory()` reads its subject labels
from, and any other copy the implementation finds: whether `boostmtree` keeps the
ID inside `$x`, row names or its cross-validation structures must be checked, not
assumed. The lineage carries the selection. Figures that group by patient work
on digests unchanged; a figure that must join back to the data digests the data's
own IDs and joins on that, so the raw ID is never saved.

## 6. The report

In this order, each in its own chunk:

1. **Fit summary.** Family, `M`, `nu`, the cross-validated best `M` and the error
   there.
2. **Error path.** `gg_boost_error()` and `gg_boost_path()`.
3. **Observed against predicted.** `gg_boost_calibration()`.
4. **Variable importance.** `gg_boost_vimp()`.
5. **Partial effects.** `gg_boost_effect()` for `EFFECT_VARIABLES`, or the top six.
6. **Patient traces.** `gg_boost_trajectory()` and its `plot()` method: one fitted
   line per patient with that patient's observed values as points, `N_TRACES`
   patients sampled inside `withr::with_seed(SEED, ...)`. The population mean is
   overlaid by the template as one ggplot2 layer. It is not added to
   ggBoostedTrees, which is a CRAN target and cannot depend on the internal
   hvtiPlotR; the template applies the hvtiPlotR theme, as the other families
   do. The plot method's `subset` argument picks patients by ID and is not
   offered, since on a digested fit it would take digests.

No figure or table prints an identifier value.

## 7. Catalog, files and gates

- **Template.** `inst/templates/30_analyses/nb-boostmtree.qmd`, with its own
  per-file `.lintr` key, and on the converted list in `test-data-contract.R`.
- **Ledger.** The `nb` row splits into `nb`/`boostmtree` (`shipped`) and
  `nb`/`boostmlr` (`queued`, `blocked_on` ggBoostedTrees#9). The roadmap is
  regenerated from the ledger, and `check-roadmap-counts.py` passes in both
  directions.
- **Dependencies.** `boostmtree (>= 2.0.2)` and `ggBoostedTrees` in Suggests, so
  the tests run on every CI platform. The fork installs from GitHub; confirm CI
  can install it, through `Remotes:` the way TemporalHazard and hvtiRlifetables
  are.
- **NEWS.** A bullet under `# hvtiRtemplates (unreleased)`.

## 8. Tests

Each must be shown failing with its code reverted, and the suite must stay at
`WARN 0` and `SKIP 0` (one on Windows).

- `add_job("nb", ..., qualifier = "boostmtree")` scaffolds the job and substitutes
  `SUBJECT` and `TYPE`.
- The chunks run end to end on a small synthetic longitudinal study, with `M`
  small enough that CI stays quick.
- The stops fire: `PREDICTORS` naming the ID or `TIME`, `RESPONSE` as the ID,
  `boostmtree` older than 2.0.2, a lost study key.
- The cache is reused on an unchanged rerun and refit when the rows or a fit
  setting change.
- A serialized-bytes test finds no MRN in the saved fit, with the chunks run in
  the global environment and outside it.

## 9. Not in this template

BoostMLR (`nb-boostmlr`, still queued). Train/test validation with `predict()`.
By-group refits, which `WHERE` covers one group at a time. `gg_boost_trajectory()`
already accepts a BoostMLR fit, so ggBoostedTrees#9 may be partly met; that
matters to `nb-boostmlr`, not here.
