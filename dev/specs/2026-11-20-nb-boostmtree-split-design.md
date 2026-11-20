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
templates' PR.

- `gg_boost_vimp()` accepts a **list** of `vimp.boostmtree()` results as well as
  one. One result behaves exactly as today.
- Given a list, each run is compared with **its own** shadow band (the largest
  shadow importance in that run's panel). Pooling the raw importances first would
  compare against a band made of a different run's noise.
- Per covariate and panel (main effect, interaction with time) it returns the
  **share of runs above the band**, and the **median and range** of importance.
- The plot keeps today's two panels and stems; the mark shows the share. The
  caption says how many runs and how many fits the pool spans. A vimp result does
  not record which fit it came from, so the fit count comes from the nesting: a
  list of runs is one fit, and a list of such lists is one list per fit.
- Help page and vignette: the share is **how stable a verdict is, not a test**.
  #49 withdrew a claimed false-positive rate because shadows within one copy share
  a shuffle; the pooled share inherits that caveat and must not reintroduce a rate.
- No shadows in a run, no band: the share is `NA` and the plot draws importances
  only, as a single run does today.

## 4. Architecture

```
nb-boostmtree_fit      fit (+ N_REFITS refits)  ->  estimates/nb-boostmtree.rds
nb-boostmtree_explain  reads that file, never fits  ->  importance, effects, trajectories
```

The handoff is `set_path("estimates", "nb-boostmtree.rds")`, within one
`(subject, type)` set, as `rfs.rds` is. The saved object:

```r
list(fit      = fit,          # the SEED fit, a (boostmtree, grow) object
     refits   = list(),       # N_REFITS fits, grown under SEED + i
     versions = c(boostmtree = , randomForestSRC = , ggBoostedTrees = ),
     k_shadow = K_SHADOW,
     seed     = SEED)
```

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
  before the fit. 0 turns them off, and the `EDIT:` says that then no band and no
  verdict can be drawn. Part of the cache key: a fit with shadows is a different
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

**Reading the fit.** Reads `estimates/nb-boostmtree.rds` in its own set. Stops,
naming `nb-boostmtree_fit`, when the file is missing or `fit` is not a
`(boostmtree, grow)` object. Never fits.

**Version check.** Compares the recorded boostmtree and randomForestSRC versions
with the installed ones and warns on a difference: vimp pushes permuted data down
the saved trees, and that path runs through randomForestSRC.

**Study choices**

- `N_VIMP <- 10`. Runs are seeded `SEED + i`, cached one by one through
  `cache_fit()`, so raising `N_VIMP` pays only for the new runs. They run in
  parallel over `CORES`; `cache_fit()` seeds each call, so results do not depend
  on the core count. The `EDIT:` gives the cost (about 0.17 fits per run at
  `K_SHADOW = 5`, n = 100) and says the share is stability, not significance.
- With refits in the file, every fit gets `N_VIMP` runs: `N_VIMP * (1 + N_REFITS)`.
- Kept from today: `EFFECT_VARIABLES`, `N_TRACES`, `REFIT`, `SAVE_FIGURES`, `FIGURES`.

**Sections**

1. **Importance.** `gg_boost_vimp(<list of runs>)`, and a table of every
   covariate's share above the band, median and range, per panel. No detected /
   not-detected rule. The prose explains a borderline share by the 14 to 46% the
   study measured. With `K_SHADOW = 0`, importances only, and the prose says no
   band could be drawn.
2. **Partial effects.** Today's `gg_boost_effect` machinery, on the SEED fit.
   With `EFFECT_VARIABLES = NULL`, the six covariates with the highest **median**
   importance across runs, so the pages stop reshuffling from render to render.
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
- `K_SHADOW` is in the cache key (changing it refits); `K_SHADOW = 0` renders with
  no band.
- Pooling: the importance table's shares come from several runs, and raising
  `N_VIMP` reuses the cached runs. **Proved by mutation**: break the per-run band
  and the tests go red.
- Deprecation: `add_job` warns, `upgrade_job` on an old `nb-boostmtree` job drops
  no chunk, `migrate_job` writes `_fit` and its warning names `_explain`.
- **#493**: both end-to-end renders capture Quarto's raw stderr and print it on
  failure, render in their own temporary directories, and keep `skip_on_cran()`.

**Gallery.** `dev/gallery/family-nb.R` gets `_fit` and `_explain` entries in place
of `nb-boostmtree`; `_explain` reads the gallery fit's `.rds`. Rebuilt on release
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
