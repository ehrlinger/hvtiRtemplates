# Confidence bands for the rf explain templates

**Date:** 2026-10-26
**Status:** designed, not built. Approved in conversation 2026-10-26 (approach 1, subsampling).
**Reads with:** `2026-09-19-rf-templates-design.md` (the templates this extends),
`2026-10-20-background-jobs-design.md` (`submit_job()` and `guard_long_fit()`).
**Packages:** hvtiRtemplates only. ggRandomForests is not changed; see section 7.

## 1. The problem

`rfs-explain`, `rfc-explain` and `rfr-explain` report VIMP (randomForestSRC's
anti-split importance, `importance = "anti"`) and
partial dependence as point estimates. A reader cannot tell a predictor whose
importance is clearly above zero from one that is noise, or a partial curve that
bends from one whose bend is within its own uncertainty.

randomForestSRC answers the first with `subsample()`, which regrows the forest on
subsamples and gives VIMP a standard error. Nothing answers the second: neither
randomForestSRC 3.9.0 nor ggRandomForests 4.0.0 computes bands on a partial plot, and
`subsample()` discards the forests it grows, so they cannot be reused for one.

Both need many refits of the forest. At study size that is hours, longer than a
console session should hold, so the bands are computed in a job started with
`submit_job()`.

## 2. Approach

Bands are optional, cached steps inside the three existing explain templates. No new
template, ledger row or `.lintr` entry.

- **VIMP intervals**: one cached `subsample()` call, of which only the per-subsample VIMP matrix
  is kept; the SE is taken about the importance figure's own estimate (section 3a).
- **Partial-dependence bands**: a refit loop of our own, using the same subsampling and
  the same variance rescaling as `subsample()` (Ishwaran and Lu, 2019), so the two kinds
  of interval rest on one method.

Approaches not taken are in section 8.

## 3. What gets computed

### 3a. VIMP intervals

```r
cache_fit("rfs-vimp-subsample",
          hvtiRtemplates:::.band_vimp_star(
            subsample(forest, B = BANDS_B, subratio = SUBRATIO, importance = "anti", verbose = FALSE)),
          seed = SEED, dir = CACHE_DIR, refit = REFIT, packages = "randomForestSRC")
```

The existing `rf?-vimp` cache and figure stay as they are. The cache holds the matrix of
subsample VIMPs (one row per predictor, one column per subsample; for rfc the `"all"` column),
not the `subsample()` object, which carries a forest.

The `importance` method must match the method the existing `vimp()` call uses, so the
standard error is that quantity's. The fit grows the forest with `importance = "none"`, so
`subsample()` computes VIMP itself with what it is handed. The figure does not plot
`subsample()`'s own re-estimate of the importance, which differs from `vimp()`'s by
Monte Carlo noise: it draws the importance figure's estimate, `vi$importance`, plus and minus
1.96 times the delete-d jackknife SE taken about that estimate (`.band_vimp_se()`), ranked as the
importance figure ranks it, so the two figures cannot disagree in sign or order. `se.jk.Z` is
not used: it is centred on `subsample()`'s own full-forest VIMP, a different draw, so it would
measure the spread about a point the figure does not show. With that VIMP as the centre the
helper reproduces `se.jk.Z` exactly, which a test pins. The interval is labelled "above zero" by its
lower bound.

The fit jobs grow with rfsrc's defaults `forest = TRUE` and `bootstrap = "by.root"`, which
`subsample()` requires (checked 2026-10-26 in `rf?-fit.qmd`: neither is overridden). A
test pins this, so a later edit to a fit job cannot break the bands without notice.

### 3b. Partial-dependence bands

1. **The grid is fixed once**, from the full forest's partial (`pd`, already cached),
   so every refit is evaluated at the same predictor values and, for rfs, the same
   `TIMES`. Curves on different grids cannot be summarized pointwise.
2. **B row sets are drawn once** from `SEED`, without replacement, at size
   b = `SUBRATIO` × n, using `subsample()`'s rule for the default (section 4).
   **Stratified as `subsample()` stratifies**: within event status for rfs, within class
   for rfc, unstratified for rfr. A survival subsample with no event stops the job,
   naming `SUBRATIO`, as `subsample()` does. The row sets are cached on their own, so
   every per-variable cache below describes the same B subsamples.
3. **For each row set**, grow a forest on those rows with the fit's settings, read from
   the saved forest (ntree, mtry, nodesize, nodedepth, nsplit, splitrule, bootstrap, samptype, sampsize
   rescaled to the subsample's share, the case and variable weights, na.action, the formula), and
   compute `partial.rfsrc()` for each selected variable whose band cache is missing.
   The forest is then **discarded**.
4. **Cache per variable**: `rf?-partial-band-<var>` holds a B × grid matrix (× `TIMES`
   for rfs).
5. **Summarize** pointwise: the full forest's value θ̂ ± z × SE, with z from
   `alpha = 0.05` and the delete-d jackknife SE that `extract.subsample()` reports as
   `se.jk.Z`:

   SE = √( (b / n) × mean over the B subsamples of (θ*ᵦ − θ̂)² )

   The deviations are about the full forest's θ̂, not about the mean of the B curves.
   This is randomForestSRC's own formula, read from `extract.subsample()` in 3.9.0 and
   reproduced exactly from a `subsample()` object's `vmp` and `vmpS` on 2026-10-26.
   (This section first said b / (n − b); that was wrong, and is corrected here.)

What the per-variable cache saves: raising `TOP_K` skips the partials of variables
already cached, **but still regrows all B forests**, because they are not kept. Keeping
them would make a new variable cheap, at the cost of B forests, possibly gigabytes, in
`estimates/`. Rejected; the `TOP_K` `EDIT:` comment says so.

The loop is one internal helper shared by the three templates:
`hvtiRtemplates:::.partial_bands(forest, rows, vars, grid, times)`. Each template adds a
chunk of about 15 lines.

## 4. Study choices

In `edit-study-choices`, after `SEED`, with the guidance as it will read:

```r
# EDIT: subsample forests for the confidence intervals on importance and the
# bands on the partial plots. 0 draws neither.
#   25-50 for a first look at a draft; the bands are rough but show their shape.
#   100 for a report. It is randomForestSRC's default, and enough because the
#   intervals are estimate +/- 1.96 SE: they need a stable SE, not stable tail
#   percentiles, which would take several hundred.
#   200 or more only for 99% intervals, or when a rerun with another SEED moves
#   the band edges by more than you would accept in a figure.
# Cost is about BANDS_B x SUBRATIO fits of the full forest. Submit the job to
# compute them; job_status() shows how many forests are grown and the time left.
BANDS_B <- 0

# EDIT: fraction of patients in each subsample. NULL takes randomForestSRC's
# default, exp(-1) (0.37) up to 1000 patients and exp(-1) * sqrt(1000 / n) above,
# so a larger cohort gets a smaller fraction. Leave it NULL unless the check
# below warns.
#   Raise it when a subsample would hold too few events (rfs) or too few of the
#   smallest class (rfc): the job warns below 100. Small subsamples grow shallow
#   forests whose curves are flatter than the full forest's.
#   Keep it at or below 0.5. Subsampling estimates the spread only while each
#   subsample is a small part of the cohort; near 1 every subsample forest is
#   nearly the full forest, and the bands shrink to the forest's own tree-to-tree
#   noise, far narrower than the real uncertainty.
SUBRATIO <- NULL

# EDIT: how the partial plots draw their bands. "ribbon" shades a band around
# each continuous curve; "bars" draws an error bar at each grid point instead,
# which reads better in black and white and where curves for several follow-up
# times overlap. Categorical predictors always get error bars.
BAND_STYLE <- "ribbon"

# EDIT: with BAND_STYLE <- "bars", where to draw the bars, as a named list of
# values per continuous predictor, e.g. list(age = c(50, 60, 70, 80), lvef = c(30, 50)).
# NULL, or a predictor left out, draws a bar at every grid point. The values
# must lie inside the predictor's observed range. Changing them only redraws:
# each subsample curve is read off at these values the way the plotted line is
# drawn, straight between grid points, so no forest is regrown.
BAND_AT <- NULL
```

- `BANDS_B` defaults to **0**, so a job scaffolded without edits, or an existing job
  brought forward by `upgrade_job()`, renders exactly as before. The bands never start
  costing hours without someone choosing them.
- `SUBRATIO` above 0.5, at or below 0, or not a single number stops the job. `BAND_STYLE` must be `"ribbon"`
  or `"bars"`; anything else stops the job. Both are checked where `TOP_K` is checked.
- `BAND_STYLE` changes only the drawing, so it is not in any cache key: switching it
  redraws from the caches.
- `BAND_AT` is a drawing choice too, and not in any cache key. Each of the B cached
  curves, and the full forest's, is linearly interpolated at the requested values, and
  the rescaled SE is computed from the interpolated values. That is exactly a band on the
  piecewise-linear curve the figure draws, so the bar and the line agree. It stops the
  job when it names a predictor that is not selected for the partials, a categorical
  predictor (those always get a bar at every level), or a value outside the observed
  range; it is ignored, with a message, under `BAND_STYLE = "ribbon"`.
  Rejected: adding the `BAND_AT` values to the partial grid so they are evaluated
  exactly. That puts a drawing choice in the band cache key, so moving one bar would
  regrow all B forests, and the gain over interpolation is small at the default grid of
  25 points.
- **The 100 floor** (events per subsample for rfs, smallest class per subsample for rfc;
  rfr has none) is a working heuristic agreed 2026-10-26, not a published rule: a
  survival or classification forest needs cases of the rare outcome to split on.

## 5. The plan chunk, caches and guards

### 5a. `bands-plan`

Runs when `BANDS_B > 0`, before any guard, and prints:

| row | from |
|---|---|
| subsample size b, and the fraction used | the subratio rule |
| events (rfs) or smallest class (rfc) per subsample | the forest's own data |
| subsample forests to grow | `BANDS_B`, and how many variables still lack a band cache |

Below the floor it warns and marks the report a draft (`.run_mark_draft()`), naming the
`SUBRATIO` that would restore 100; under `HVTI_TEMPLATE_STRICT` it stops instead. This is
the pattern `lg.qmd` uses for a covariate with no scale chosen.

**No run-time estimate in the table.** Checked 2026-10-26: neither the handoff nor the
run record carries the fit's elapsed time in a form the explain job can read, so the
estimate is not printed rather than guessed. The refit loop instead reports through the
job's progress callback, `.job$progress("subsample forest")`, as `nb-boostmtree` reports
its iterations: `job_status()` and the render log then show `subsample forest k/B` and a
time left measured from the forests already grown. The `BANDS_B` comment drops "the job
prints its estimate before it starts" accordingly.

### 5b. Caches

All in `CACHE_DIR`, beside the forest, seeded by `SEED`.

| cache | holds | stale when |
|---|---|---|
| `rf?-vimp-subsample` | the subsample VIMP matrix | forest, `BANDS_B`, `SUBRATIO`, `SEED` |
| `rf?-band-rows` | B integer row-index vectors | n, `BANDS_B`, `SUBRATIO`, `SEED` |
| `rf?-partial-band-<var>` | B × grid partial values for one variable | the rows, the grid, `TIMES` |

The caches hold row indices and predicted values, never identifiers.

### 5c. Guards

`guard_long_fit()` before each step whose cache is missing, its `why` naming B and,
once measured, the time:

```r
if (BANDS_B > 0) hvtiRtemplates::guard_long_fit("rfs-vimp-subsample", dir = CACHE_DIR,
  why = sprintf("the importance intervals regrow the forest %d times", BANDS_B))
```

Each guard is called only when `hvtiRutilities::cache_would_fit()` says the step will compute,
which is no cache, or a stale one under `REFIT`. A current cache loads even under `REFIT`, and
a bigger `TOP_K` needs `REFIT` for the full forest's partial, so a guard on file existence alone
would refuse, or a pool built from it would recompute, bands that are already current. The same
check decides which variables the refit pool computes.

The partial-band step guards on **every** selected variable that will compute, so
`guard_long_fit()`'s `name` accepts a character vector and refuses when any is missing.
It is exported, so this change carries its own test and its own `news/` fragment.

**Before the guards are written in**, a timing run on lri measures one subsample refit at
study size, as the background-jobs spec requires ("each when a measured run time
justifies it"). The job is staged under `/studies/general/_development/` for John to run.

## 6. Figures, captions, tests, docs

### 6a. Figures

Drawn only when `BANDS_B > 0`; with the bands off the job's figure list is unchanged.

| figure | shows |
|---|---|
| `rf?-explain-importance-intervals` | each predictor's VIMP with its 95% subsampling interval, ranked as in the importance figure, a reference line at zero. Free height, one row per predictor |
| `rf?-explain-dependence-partial-bands-page-NN` | the `dependence-partial` pages and panels, with a ribbon or, under `BAND_STYLE = "bars"`, error bars at the grid points, or at the `BAND_AT` values, along each continuous curve, and error bars on each categorical bar. For rfs, one band per horizon in that horizon's color; under `"bars"` the bars for the horizons are dodged so they do not overprint |

Captions state the method exactly, with B and the fraction filled in from the run, and
say the band is pointwise: it bounds the curve at each value, not the whole curve. The
caption names the drawing that `BAND_STYLE` chose ("shaded bands" or "error bars").

Drawn by new internal helpers beside `.partial_subset()` in `R/figure-pages.R`:
`.plot_vimp_intervals()` and `.plot_partial_bands(x, style)`.

### 6b. Tests

In `test-rf-templates.R`, on the synthetic cohorts with `BANDS_B = 3`:

1. `BANDS_B = 0`, the default, writes no band cache and no band figure.
2. With `BANDS_B > 0`, each of the three explain templates writes the caches and both
   figure families.
3. Raising `TOP_K` adds caches only for the new variables; the existing band caches are
   byte-identical afterwards.
4. The SE helper the partial bands use, given a `subsample()` object's `vmp` as θ̂ and
   its `vmpS` replicates as θ*, reproduces `extract.subsample(standardize = FALSE)$se.jk.Z`
   exactly, pinning the two band types to one formula. A randomForestSRC release that
   changes its formula turns this red.
5. With `interactive()` mocked, a missing band cache stops with the `submit_job()`
   message; `guard_long_fit()` accepts a vector of names and refuses when any is missing.
6. "no explain template grows a forest" becomes "no explain template grows a forest on the
   full cohort": every `rfsrc()` call in an explain job is inside `.partial_bands()`.
7. Each `rf?-fit` grows with `forest = TRUE` and `bootstrap = "by.root"` (section 3a).
8. `BAND_STYLE = "bars"` draws error bars and no ribbon, and changing it alone recomputes
   no cache. With `BAND_AT`, the bars sit at exactly the requested values, a value equal
   to a grid point reproduces that grid point's band, changing `BAND_AT` recomputes no
   cache, and each refusal in section 4 stops with a message naming `BAND_AT`.
9. `SUBRATIO` out of range and an unknown `BAND_STYLE` each stop with a message naming
   the choice.
10. The existing MRN scans cover the new caches unchanged.

### 6c. Docs and gates

- `inst/templates/README.md`: the new figure names for the three explain templates, and
  a paragraph on when to submit the job.
- A `news/` fragment.
- If `check-flow-counts.py` or `check-spec-counts.py` count these templates' figures or
  chunks, regenerate them in the same pull request. To be checked in the plan.

## 7. Not in this change

- **ALE and SHAP.** ggRandomForests 4.0.0 exports `gg_ale_rfsrc()` and `gg_shap()` for
  regression and classification forests; no rf explain template uses them. Survival is
  "not yet implemented" in both, by their own help pages. Adding them to `rfr-explain`
  and `rfc-explain` is template work of its own; survival ALE needs ggRandomForests to
  evaluate it at fixed horizons first.
- **Band helpers in ggRandomForests.** `.plot_vimp_intervals()` and
  `.plot_partial_bands()` are candidates to move there after 4.0.0 is released.
- **Simultaneous bands.** The bands are pointwise, and the captions say so.

## 8. Approaches not taken

- **A separate `rf?-bands` job per family.** Keeps explain fast, but adds three templates
  and splits one question, how sure are we of this effect, across two reports.
- **Bands computed in the fit job.** The partial bands depend on the variables explain
  selects, so fit would have to guess them or take over the selection.
- **Bootstrap percentile bands.** Each refit costs a full fit, the tails need several
  hundred replicates, and the method would differ from the VIMP intervals.
- **Keeping the B subsample forests** to make a new variable cheap: gigabytes in
  `estimates/` for a saving that applies only when `TOP_K` changes.
