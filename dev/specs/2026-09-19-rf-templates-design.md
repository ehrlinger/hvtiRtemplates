# Random forest templates: `rfs`, `rfc` and `rfr`, fit and explain

**Date:** 2026-09-19
**Status:** Draft, designed with John Ehrlinger on 2026-09-19 (sections 1 to 5
approved one at a time). Awaiting review of this written form.
**Parents:** sub-project 2 of `dev/specs/2026-09-17-ml-family-roadmap-design.md`,
built on the catalog model in `dev/specs/2026-09-18-template-catalog-design.md`.

## 1. What this decides

- Which templates the three random forest prefixes become, and where they sit.
- What a fit job does, what an explain job does, and how the second reads the
  first.
- The catalog rows, dependencies, lint keys and documentation the templates
  bring with them.
- How the old `rfsrc` and `rf` job names map onto the new prefixes.
- How the work is tested.

## 2. The model

**Each outcome gets two templates: one that fits the forest and one that
explains it.** Fitting is slow and changes rarely. Explaining (importance,
VarPro, dependence plots) is where a study author iterates. Splitting them lets
the second rerun without the first.

| file | prefix | qualifier | outcome |
|---|---|---|---|
| `inst/templates/30_analyses/rfs-fit.qmd` | `rfs` | `fit` | survival |
| `inst/templates/30_analyses/rfs-explain.qmd` | `rfs` | `explain` | survival |
| `inst/templates/30_analyses/rfc-fit.qmd` | `rfc` | `fit` | classification |
| `inst/templates/30_analyses/rfc-explain.qmd` | `rfc` | `explain` | classification |
| `inst/templates/30_analyses/rfr-fit.qmd` | `rfr` | `fit` | regression |
| `inst/templates/30_analyses/rfr-explain.qmd` | `rfr` | `explain` | regression |

All three prefixes are wholly qualified, as `check-roadmap-counts.py` requires.

The templates fit with randomForestSRC, run VarPro with `varPro`, and plot with
`ggRandomForests`. None of that code moves into those packages; the templates
only call it (the catalog design's §2).

## 3. The gate

The two-study rule is met for all three prefixes.

- `rfs` and `rfc`: the 2026-09-02 census summary records 9 and 11 studies.
- `rfr`: measured on 2026-09-19. Job names cannot answer this question, because
  an `rfsrc` job's first qualifier is the outcome *variable*, not the outcome
  *type*. The measure was a content read of every `rf`/`rfsrc` program file
  (`.R`, `.Rmd`, `.qmd`) in the `analyses` folders of the studies share: 540
  files across 78 studies. Six studies fit a regression forest on a continuous
  outcome. A seventh copies the old regression template but fits a death
  outcome, and is not counted.

⚠️ **The six regression studies share one lineage.** Each carries the same
copied script, which tunes (`tune.rfsrc()`) and imputes before fitting. The
outcomes differ, so the rule is met, but the shape they exercise is largely one
author's. Section 8 leaves tuning out of the base templates; a study that needs
it adds it, and `rfr-fit` says so where the fit call is.

A naive keyword census would have overcounted badly: "regression" appears in 455
of the 540 files, mostly as "logistic regression" in classification jobs.

## 4. The fit template

The same anatomy for all three prefixes, with outcome-specific chunks where
marked.

1. **Header and `format:` block.** The header carries the migration mapping
   (§7). The `format:` block keeps the report self-contained.
2. **`study-choices` chunk**, every line marked `EDIT:`:
   - `ENDPOINT` and `TYPE`, exactly one line each.
   - The outcome: `TIME` and `STATUS` for `rfs`, `RESPONSE` for `rfc` and `rfr`.
   - The predictor list, `NTREE`, `SEED`, `DERIVED` and `REFIT = FALSE` (§5).
   - `rfc` adds an `IMPUTE` switch, because the classification exemplars impute.
3. **Setup.** The `set_path(kind, file)` helper that `hs` and `hp` use, and
   `library()` calls for `randomForestSRC`, `ggRandomForests` and
   `hvtiRutilities`. No `install_github()` lines. A version floor check stops
   with a readable message below the `DESCRIPTION` floors (§6).
4. **Read.** Read the built dataset, keep the predictors and the outcome, and
   stop if the outcome has missing values.
5. **Fit.**
   `forest <- cache_fit("<prefix>", rfsrc(<formula>, data, ntree = NTREE, importance = "none"), seed = SEED)`.
   The chunk sets `message: true`, so the report shows whether the forest was
   reused or recomputed. `importance = "none"` is deliberate: importance is the
   explain job's work, cached separately.
6. **Diagnostics.** `gg_error()` for OOB error against the number of trees, then
   the outcome's performance plot:
   - `rfs`: `gg_rfsrc()`, predicted survival curves.
   - `rfc`: `gg_roc()` with `calc_auc()`, and `gg_brier()`.
   - `rfr`: `gg_rfsrc()`, predicted against observed.
7. **Handoff.** A closing line naming `<prefix>.rds` in the set's estimates
   folder as what the matching explain job reads.

Left out of fit: importance, VarPro and dependence (explain's work),
hyperparameter tuning, uVarPro, and the descriptive tables and EDA the
reference templates carry, which belong to `10_descriptive` jobs.

## 5. The explain template

1. **Header and `format:` block**, as in fit.
2. **`study-choices` chunk**, every line marked `EDIT:`:
   - `ENDPOINT` and `TYPE`. They must match the fit job's, because together they
     name the set whose estimates folder holds the forest.
   - `SEED`, and `REFIT = FALSE`, passed to every `cache_fit()` call.
   - `TOP_K = 8`: how many variables get dependence plots.
   - `PARTIAL_VARS = NULL`: `NULL` means the top `TOP_K` by VIMP; naming
     variables overrides it.
   - `rfs` adds `TIMES`, the horizons for the survival partials.
3. **Load the forest.**
   `forest <- readRDS(set_path("estimates", "<prefix>.rds"))`. A missing file
   stops with "run `<prefix>-fit` first". Explain never refits.
4. **Training frame from the forest.** Rebuilt from `forest$yvar` and
   `forest$xvar`, with `forest$formula` as the model. This is the one departure
   from `hs` and `hp`, where the downstream job re-reads the built dataset. A
   VarPro or partial call on a frame that differs from the fitted one explains a
   model nobody fit; reading the frame from the forest rules that out, and
   removes any need to repeat the outcome and predictor choices.
5. **Importance.** `vimp(forest)`, cached as `<prefix>-vimp`, then a `gg_vimp()`
   plot and table. `max.subtree()` minimal depth as a second ranking; it is
   cheap and not cached.
6. **VarPro.** `varpro(forest$formula, data)`, cached as `<prefix>-varpro`, then
   `gg_varpro()`.
7. **Dependence, for the selected variables:**
   - `gg_variable()` marginal plots, not cached.
   - `gg_partial_rfsrc()` partials, cached as `<prefix>-partial`. Continuous
     and categorical variables are plotted separately.
   - `partialpro()` then `gg_partialpro()`, cached as `<prefix>-partialpro`.

Each expensive step is its own `cache_fit()` entry. `cache_fit()` keys a cache
on its code and free variables, and a stale cache stops with an error of class
`hvtiRutilities_stale_cache` rather than returning the old result. So after
`TOP_K` changes, only the two partial caches are stale; the forest, VIMP and
VarPro caches still load. The study author sets `REFIT <- TRUE`, which
recomputes stale entries only, so one template-wide switch is safe. The
reference templates wrapped one `file.exists()` guard around everything and
returned stale results silently.

Every function named in §4 and §5 is an export of the installed versions,
checked on 2026-09-19: ggRandomForests 4.0.0, varPro 3.2.0, randomForestSRC
3.7.0. Catalog rule 3 requires that.

## 6. Catalog, dependencies, lint and documentation

- **Catalog (`inst/extdata/templates.json`).** The unqualified `rfs`, `rfc` and
  `rfr` rows become six qualified rows, `fit` and `explain` per prefix, each
  with disposition `scaffold`.
  - Each explain row names its fit row in `upstream`; each fit row names its
    explain row in `downstream`.
  - `uses` lists each row's direct calls. Fit: `randomForestSRC::rfsrc`,
    `hvtiRutilities::cache_fit`, `ggRandomForests::gg_error` and the outcome's
    performance functions. Explain: `randomForestSRC::vimp`,
    `randomForestSRC::max.subtree`, `varPro::varpro`, `varPro::partialpro`,
    `hvtiRutilities::cache_fit` and the `ggRandomForests` functions of §5.
  - The census counts (`sas_breadth`, `r_exemplars`, `r_jobs`) describe the
    prefix, not a job type. They go on the fit row and are `null` on the explain
    row. **The plan's first step confirms `check-roadmap-counts.py` accepts
    that** before anything is built on it; duplicating the counts on both rows
    could double a prefix's breadth in the rendered ledger.
  - The `rfr` row records the 2026-09-19 census (§3).
- **`DESCRIPTION`.** Suggests gains `randomForestSRC (>= 3.7.0)` and
  `varPro (>= 3.2.0)`, and `ggRandomForests` rises to `(>= 4.0.0)`. Remotes gains
  `ehrlinger/randomForestSRC` and `ehrlinger/varPro`, because varPro needs a
  matched randomForestSRC. The existing test that Suggests bounds match what the
  templates enforce keeps the floors and the templates' checks in step.
- **`.lintr`.** Six file keys, each carrying the exclusion set the existing
  templates use. No directory key.
- **Documentation.** `inst/templates/README.md` gains the six rows and the
  migration mapping (§7). `NEWS.md` gains an entry under
  `# hvtiRtemplates (unreleased)`. No version bump in the pull request.

## 7. Migration from `rfsrc` and `rf`

A documented mapping only; no `migrate_job()` converter.

| old job | outcome | new prefix |
|---|---|---|
| `rfsrc.*`, `rf.*` | survival | `rfs` |
| `rfsrc.*`, `rf.*` | classification or binary | `rfc` |
| `rfsrc.*`, `rf.*` | regression | `rfr` |

The outcome is read from the job's fit call, not its name (§3). The mapping is
recorded in the README, in `NEWS.md` and in each fit template's header.

## 8. Out of scope

- Hyperparameter tuning (`tune.rfsrc()`) and uVarPro. A study adds them.
- `rhf`, which waits for two exemplar studies.
- `sid` and `vt`, which compose on these templates in a later sub-project.
- A `migrate_job()` converter for old `rfsrc` and `rf` jobs.

## 9. Testing

- **Covered already.** The existing suite picks up the six files without
  change: name parsing, the qualified-prefix rules, the edit-guard, root
  resolution, declared `hvtiRutilities` helpers, and the catalog rules,
  including that every `uses` entry is a real export.
- **Smoke test per outcome.** Scaffold a temporary study with `add_job()`, run
  fit then explain on a small built-in dataset (`veteran` for `rfs`, a binary
  subset of `iris` for `rfc`, `airquality` for `rfr`) with `ntree = 50`. Assert
  that each cache `.rds` appears and each plot object builds. Run the chunks the
  way the TemporalHazard template tests do (#125), not through Quarto. Guard
  with `skip_if_not_installed()` per package.
- **Contract tests.**
  - Explain stops with "run `<prefix>-fit` first" when the forest is missing.
  - After a change to `TOP_K` with `REFIT = FALSE`, the partial step raises
    `hvtiRutilities_stale_cache` and the VIMP step does not.
  - No explain template calls `rfsrc(`: a static check on the files, so the
    no-refit promise is enforced and not only documented.
- **Proved by mutation.** Remove the missing-forest stop, or add an `rfsrc(`
  call to an explain template, and confirm the matching test goes red.
- **Read the CI summaries.** Every leg should report `SKIP 0` on macOS and
  Ubuntu and `SKIP 1` on Windows. A new skip means a smoke test's package was
  missing on that leg, which is the silent-coverage failure `AGENTS.md` warns
  about.
