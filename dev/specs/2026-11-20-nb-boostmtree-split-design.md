# nb-boostmtree split: a fit job and an explain job

**Date:** 2026-11-20
**Status:** design. Every decision here was made by John Ehrlinger on 2026-11-20,
in the order the sections appear. Nothing is built yet.
**Reads with:** `2026-10-01-nb-boostmtree-design.md` (the template this splits),
the `rfs-fit` / `rfs-explain` pair (the shape it copies), issues #580 and #493,
and the 2026-11-20 seed-stability study (`/studies/general/_development/boostmtree-seeds-20261119/`).
**Packages:** `hvtiRtemplates` (two templates, the catalog, tests);
`ggBoostedTrees` (one change, released first, section 3); `boostmtree` unchanged.

This note is self-contained. It assumes no memory of the session that produced it.

⚠️ No study, variable or patient identifier appears here. Column names such as
`ccfid` are names, not values.

## 1. What was asked, and why now

The open item from the 2026-11-20 seed-stability session: templates that drive a
boostmtree analysis for biostats users, with shadow covariates, repeated vimp, a
convergence check and version recording, building on `nb-boostmtree`. John's
standing split (2026-11-20): **ggBoostedTrees documents how to use boostmtree
correctly; the templates drive the analysis.**

What the study found, which the templates must act on:

- **A seed reproduces a fit only within one randomForestSRC version.** 0 of 50
  seeds gave identical fits across rfsrc 3.9.0 and 3.10.0; the distributions match.
- **`m.opt` is arbitrary on a flat CV curve**: 156 to 400 across seeds, median
  about 385, at `nu = 0.25`, `M = 400`. The template default is `nu = 0.05`,
  where the plateau is likely wider; not measured.
- **Strong effects are stable** (98 to 100% of runs), true nulls rare (0 to 6%),
  **borderline effects are not** (14 to 46%). Refitting moves verdicts as much
  as rerunning vimp.

What `nb-boostmtree.qmd` does today (806 lines, `origin/main` `b385643`): one
fit, one `vimp.boostmtree()` run, `m.opt` reported as Best M, no shadows (so
ggBoostedTrees 0.10.1 draws no noise band and no verdict), no randomForestSRC
version recorded. Floors: boostmtree 2.0.8, ggBoostedTrees 0.9.0.

## 2. Decisions

| # | Question | Decision |
|---|---|---|
| D1 | Extend `nb-boostmtree` or split it? | **Split into fit and explain**, like `rfs-fit` / `rfs-explain`. |
| D2 | Names | **`nb-boostmtree_fit` and `nb-boostmtree_explain`.** The `nb` qualifier already names the package (`boostmlr` is queued), so the stage goes after it. `qualifier` is `[A-Za-z0-9_]+`, so `_` is legal and `-` is not. |
| D3 | Which iteration | **Predict at `m.opt`; report the plateau beside it.** No selection rule in code until the 156-vs-400 prediction comparison is measured (section 9). |
| D4 | Stability | **Repeat vimp by default (`N_VIMP = 10`); refits opt-in (`N_REFITS = 0`).** |
| D5 | Where pooling lives | **ggBoostedTrees first** (0.10.2), then the templates. Pooling in a template would be copied into every study job. |
| D6 | #580 run-time table | **Retime at the defaults, `M = 500`, `NU = 0.05`, on boostmtree 2.0.13 with `K_SHADOW = 5`**, on lri, recording peak memory too. |
| D7 | What becomes of `nb-boostmtree` | **Deprecated, not renamed** (section 7). Changed from a rename alias during design, because `upgrade_job()` follows renames and would merge old jobs onto `_fit`, offering to delete their importance, effects and trajectory chunks. |

## 3. ggBoostedTrees 0.10.2: pooled importance

A patch release, its own PR in `ggBoostedTrees`, merged and tagged before the
templates' PR. **The design is ggBoostedTrees'**: "Pooled variable importance:
box of margins over the shadow band" (`docs/superpowers/specs/2026-11-20-pooled-vimp-box-design.md`
on `feat/pooled-vimp-box`, approved by John 2026-11-20). What follows is what
these templates rely on; where the two differ, that spec governs. It replaced an
earlier design recorded here (nested lists, `summary()` method, stems shaded by
share), dropped the same day.

- **Input.** `gg_boost_vimp(list(v1, v2, ...))`, a new `gg_boost_vimp.list()`
  method. A **flat** list of `vimp.boostmtree` runs: repeated runs on one fit,
  one run on each of several refits, or a mix. Runs are labelled by the list's
  names, or `1..N`. The pool does not know which run came from which fit, so a
  caller that wants that in the report says it itself and encodes it in the names.
  A bare `vimp.boostmtree` object behaves exactly as today.
- **Refusals**, each naming the run: an element that is not a `vimp.boostmtree`
  (BoostMLR included); **a run with no shadow covariates**; a run whose
  covariates, components, responses or metric differ from the first run's; an
  empty list; empty or duplicated names.
- **Each run is judged against its own band**: `band` is the largest shadow
  importance in that run's panel, floored at 0 (the rule
  `.vimp_shadow_thresholds()` already uses); `margin = importance - band`;
  detected when `margin > 0`. Raw importances are never pooled first.
- **Result.** Class `gg_boost_vimp_pool`, one row per variable, component and
  response, shadows excluded: `n_runs`, `n_detected`, `share`,
  `median_importance`, and the 15th, 25th, 50th, 75th and 85th percentiles of the
  margin over runs (`q15` to `q85`). The per-run rows travel as the `runs`
  attribute. **No pooled verdict**: the share is reported and the reader judges.
- **Plot.** `autoplot.gg_boost_vimp_pool()`, the single-run figure's panels and
  facets, with x the margin over each run's own band and a line at zero: a box
  from the 25th to 75th percentile, whiskers 15th to 85th, each run a small point,
  and a `k/N` label giving the share. Rows run by their largest median margin.
- **Docs.** The share is **how stable a verdict is, not a test**. #49 withdrew a
  claimed false-positive rate because shadows within one copy share a shuffle;
  the pool inherits that caveat and states no rate.

## 4. Architecture

```
nb-boostmtree_fit      fit (+ N_REFITS refits)  ->  estimates/nb-boostmtree_fit.rds
nb-boostmtree_explain  reads that file, never fits  ->  importance, effects, trajectories
```

The handoff is `set_path("estimates", "nb-boostmtree_fit.rds")`, within one
`(subject, type)` set, as `rfs.rds` is. **It is not `nb-boostmtree.rds`**, the
file the deprecated job writes: that holds a bare fit, and while the old
template stays on disk (section 7), rendering an old job in the same set would
overwrite a bundle of the same name and break `_explain`. Nor is it
`nb-boostmtree-fit.rds`: the deprecated job caches its fit under the name
`nb-boostmtree-fit` in the same folder, so that path is its cache file. The
underscore name matches the template and collides with nothing the old job writes. Distinct names give
each file one owner and one format. The fit's cache directory follows the new
name for the same reason.

The saved object:

```r
list(fit      = fit,          # the SEED fit, a (boostmtree, grow) object
     refits   = list(),       # N_REFITS fits, grown under SEED + i
     versions = c(boostmtree = , randomForestSRC = , ggBoostedTrees = ),
     k_shadow = K_SHADOW,
     seed     = SEED)
```

**Lineage goes on the outer list.** Today's save chunk attaches handoff lineage
to the fit with `.attach_handoff_lineage()`. `_fit` attaches it to the bundle
instead, with the same `data`, `analysis`, `cohort` and `selection` arguments
(`analysis` gains `k_shadow` and `n_refits`). `.read_handoff()` validates
lineage on the object it reads (`.validate_handoff_lineage()` in
`R/provenance.R`), so lineage left on the inner `fit` would make the bundle fail
validation, and reading it with a plain `readRDS()` instead would skip the
final-render check for unregistered working data.

Both templates: floors **boostmtree >= 2.0.13** (the seed fix) and
**ggBoostedTrees >= 0.10.2** (section 3). `DESCRIPTION` floors move only in this
package's own bump, per the release-ordering rule.

## 5. `nb-boostmtree_fit`

Starts from today's file and keeps: setup, data, the fit, fit checks, the error,
path and calibration figures, `SENSITIVITY`, `MTRY`, `CORES`, the memory guard,
save and provenance. The importance, effects and trajectory chunks move to
`_explain`.

**New study choices**

- `K_SHADOW <- 5`. Shadows enter through `ggBoostedTrees::boost_shadow(x, id, k)`
  before the fit. 0 turns them off, and the `EDIT:` says that then no band can be
  drawn and the explain job cannot pool runs (the pool refuses runs without
  shadows). Part of the cache key: a fit with shadows is a different
  model. The comment gives the cost, measured 2026-11-20 on the Mac at n = 100,
  `M = 400`, `nu = 0.25`: shadows add about 17% to the fit (34.5 s to 40.5 s) and
  multiply one vimp run by about 3.6 (1.9 s to 6.8 s).
- `N_REFITS <- 0`. Each refit is grown under `SEED + i`, cached one by one through
  `cache_fit()`, and guarded by `guard_long_fit()` like the main fit. The `EDIT:`
  says each costs one full fit and is how the job catches verdicts that move
  between seeds.

**The plateau read**

- The fit-summary table reports `m.opt`, the **plateau** (iterations whose CV
  error is within 1% of the minimum) and the error level there. The prose says
  `m.opt` is one draw on that plateau. Prediction stays at `m.opt`.
- The 1% is a display threshold. It changes no fitted value, and the comment says
  so and says why a selection rule waits (section 9).
- With refits: the table adds the spread of `m.opt` across fits, and the error
  figure overlays the **mean CV curve** across fits. Averaging the argmins is not
  done: they pile up at `M`, so their mean depends on `M` rather than the data, and
  no fit was grown at the averaged iteration.

**Versions**

The saved list records boostmtree, randomForestSRC and ggBoostedTrees versions,
and the provenance chunk prints them, with the reason: a seed reproduces a fit
only within one randomForestSRC version.

**#580**

- Lines 204 to 205 cite one study's 1,391 patients, 4,771 visits and Best M 751.
  Cite them from that fit's saved output on lri, by date and boostmtree version,
  with no study named. If the output cannot be found, remove the sentence and keep
  the point that M is paid for up to its ceiling.
- Lines 247 to 249, the run-time table, time `M = 1000` on boostmtree 2.0.4 and
  2.0.8. Replace them with a retime at `M = 500`, `NU = 0.05`, `K_SHADOW = 5` on
  boostmtree 2.0.13 (section 8). Each cell records hours and peak per-worker
  memory.
- **Memory.** `.boostmtree_need_gib()` in `R/fit-memory.R` estimates from
  patients, visits, family, cores and M, not predictor count, and shadows multiply
  the predictor count by `1 + K_SHADOW`. If the retime shows memory rising with
  shadows, the estimate learns the predictor count in the same PR; otherwise the
  guard under-calls and a fit is killed hours in.

## 6. `nb-boostmtree_explain`

**Reading the fit.** Reads `estimates/nb-boostmtree_fit.rds` in its own set
through `.read_handoff(path, "fit", .cfg, "the nb-boostmtree_fit job")`, as
`rfs-explain` reads `rfs.rds`, never with a bare `readRDS()`. Stops, naming
`nb-boostmtree_fit`, when the file is missing, its lineage is incomplete, or
`fit` is not a `(boostmtree, grow)` object. The lineage records `.read_handoff()`
returns go into this job's provenance, as `rfs-explain` passes
`.forest_read$lineage`, so the report traces back to the data the fit read.
Never fits.

**Version check.** Compares the recorded boostmtree and randomForestSRC versions
with the installed ones and warns on a difference: vimp pushes permuted data down
the saved trees, and that path runs through randomForestSRC.

**Study choices**

- `N_VIMP <- 10`. Run `j` on fit `i` is seeded `SEED + j + 1000 * i` (changed 2026-11-20 after the final review: shared seeds gave every fit the same permutations), cached one by one through
  `cache_fit()`, so raising `N_VIMP` pays only for the new runs. They run in
  parallel over `CORES`; `cache_fit()` seeds each call, so results do not depend
  on the core count. The `EDIT:` gives the cost (about 0.17 fits per run at
  `K_SHADOW = 5`, n = 100) and says the share is stability, not significance.
- With refits in the file, every fit gets `N_VIMP` runs: `N_VIMP * (1 + N_REFITS)`.
  All of them go to `gg_boost_vimp()` as one flat named list, names `fit<i>.run<j>`
  (`fit0` the SEED fit). The pool does not count fits, so the importance prose
  states the pool itself ("10 runs on 1 fit", "10 runs on each of 6 fits").
- Kept from today: `EFFECT_VARIABLES`, `N_TRACES`, `REFIT`, `SAVE_FIGURES`, `FIGURES`.

**Sections**

1. **Importance.** `plot(gg_boost_vimp(<named list of runs>))`, the box of
   margins over each run's band, and a table from the pool of every covariate's
   `n_detected` of `n_runs`, `share`, `median_importance` and the margin's 25th to
   75th percentiles, per panel. No detected / not-detected rule. The prose
   explains a borderline share by the 14 to 46% the study measured.
   **With `K_SHADOW = 0`** the pool refuses runs without shadows, so the job does
   not pool: it draws the single-run figure for the first run (importances, no
   band), says in the prose that no band and no share could be computed, and runs
   vimp once rather than `N_VIMP` times, since the extra runs would feed nothing.
2. **Partial effects.** Today's `gg_boost_effect` machinery, on the SEED fit.
   With `EFFECT_VARIABLES = NULL`, the six covariates with the highest
   `median_importance` across runs (the pool's column; the first run's importance
   when `K_SHADOW = 0`), so the pages stop reshuffling from render to render.
3. **Trajectories.** Today's `fig-traces`, unchanged.

Out of scope: `gg_boost_prediction()` (landmark prediction, ggBoostedTrees
0.10.1). Today's template does not draw it; a later section if wanted.

## 7. Deprecating `nb-boostmtree`

The catalog already supports this (`.template_deprecation()` and
`.warn_if_deprecated()` in `R/templates.R`), so no new mechanism.

- `nb-boostmtree.qmd` stays on disk for one release, its row marked
  `deprecated_by: nb-boostmtree_fit`, with a `deprecation_note` naming **both**
  new templates. `check-roadmap-counts.py` requires a `deprecated_by` row's file on
  disk, which holds.
- `add_job("nb", qualifier = "boostmtree")` and `upgrade_job()` warn through the
  existing path. Existing jobs keep upgrading against the old template, so no
  chunk is ever proposed for deletion.
- ⚠️ **`migrate_job()` assumes a replacement draws the same output** (comment at
  `R/migrate-job.R:182`) and writes the job from `deprecated_by`. A split breaks
  that: a migrated `nb` job would come out fit-only. Decision: `migrate_job()`
  writes `_fit`, as the code does, and its warning, from the `deprecation_note`,
  tells the author to scaffold `_explain` with `add_job()`. The comment at line
  182 is corrected to say a replacement may cover part of the old output.
- The file is removed in the release after.
- The `nb` prefix stays wholly qualified: `boostmtree`, `boostmtree_fit`,
  `boostmtree_explain`, `boostmlr`.

## 8. Ledger, tests, gallery, docs

**Ledger and gates**

- Two rows in `inst/extdata/templates.json`, each with `uses` and
  `spec: dev/specs/2026-11-20-nb-boostmtree-split-design.md`. The corpus counts
  (`r_exemplars` 19, `r_jobs` 63, `sas_breadth` 21) stay on `_fit`; `_explain`
  says in `note` that it shares them. The two-study gate is met by the same corpus.
- A `.lintr` **file** key per new template, copied from `nb-boostmtree`'s.
- Regenerate the maps behind `spec-counts.yaml` and update the counts in
  `inst/templates/README.md` and `AGENTS.md`.
- One `news/<branch>.md` fragment. No version bump in the PR.

**Tests** (split `test-nb-boostmtree.R` into a fit file and an explain file,
sharing `helper-nb.R`)

- Handoff: the fit writes the list in section 4; explain reads it; explain stops
  on a missing file and on a non-boostmtree object; explain warns on a version
  mismatch, driven from a temporary `.rds` with faked versions.
- Lineage: the saved bundle carries complete `hvti_provenance` on the outer list,
  and `_explain` refuses a bundle whose lineage is missing or sits only on the
  inner fit. A final render of `_explain` over a fit made from unregistered
  working data is refused, as for `rfs-explain` (the regression test).
- Paths: `_fit` writes `nb-boostmtree_fit.rds`, never `nb-boostmtree.rds` or the old
  job's cache `nb-boostmtree-fit.rds`, and
  rendering the deprecated job in the same set leaves `_explain`'s input intact.
- `K_SHADOW` is in the cache key (changing it refits); `K_SHADOW = 0` renders the
  single-run figure with no band, runs vimp once, and never calls the pool.
- Pooling: the importance table's `n_detected` and `share` come from `N_VIMP`
  runs named `fit<i>.run<j>`, and raising `N_VIMP` reuses the cached runs. The
  per-run band arithmetic is ggBoostedTrees' to test; here, assert the job hands
  the pool every run and reports its counts unaltered. **Proved by mutation**:
  drop a run from the list and the tests go red.
- Deprecation: `add_job` warns, `upgrade_job` on an old `nb-boostmtree` job drops
  no chunk, `migrate_job` writes `_fit` and its warning names `_explain`.
- **#493**: both end-to-end renders capture Quarto's raw stderr and print it on
  failure, render in their own temporary directories, and keep `skip_on_cran()`.

**Gallery.** `dev/gallery/family-nb.R` gets `_fit` and `_explain` entries
**beside** `nb-boostmtree`, rendered in the order `_fit`, then `_explain`;
`_explain` reads the gallery fit's `nb-boostmtree_fit.rds`. The old entry stays
for the deprecation window: its row is still `shipped` and its file is on disk,
so `gallery_missing()` wants a job for it and `gallery_build()` stops without
one (`dev/gallery/gallery.R`). It goes when the file does. The distinct
handoff names (section 4) mean the old job cannot overwrite what `_explain`
reads, whatever the order. Rebuilt on release
day.

## 9. Order of work, and what is not yet measured

1. **ggBoostedTrees 0.10.2** (section 3): PR, release, tag.
2. **Retime on lri** (D6): staged by Claude in `/studies/general/_development/`,
   run by John with `env -u R_HOME /opt/R/4.6.*/bin/Rscript`. The old table's
   cells: 1,000 patients on 4 and on 8 cores, 2,000 on 8, 4,000 on 4 (110 h at
   `M = 1000` on 2.0.4, so expect the longest run here). Records hours, peak
   per-worker memory, and the plateau width at `nu = 0.05` as a byproduct.
3. **hvtiRtemplates PR**: both templates, the deprecation, tests, docs. Closes
   #580 and #493.

Not measured, and not blocking:

- Whether predictions at `m.opt` 156 and 400 differ enough to matter. That decides
  whether a plateau selection rule replaces the argmin (D3).
- vimp and refit cost at clinical size. The n = 100 timings in sections 5 and 6
  are the only measurement; the retime gives the fit, not vimp.
- Seed stability at the size of the 1,391-patient study.
