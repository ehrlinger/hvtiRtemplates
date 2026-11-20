# nb-boostmtree split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the one-job `nb-boostmtree` template with a fit job, `nb-boostmtree_fit`, that grows the SEED fit with shadow covariates (and optional refits) and saves them as one handoff bundle, and an explain job, `nb-boostmtree_explain`, that reads that bundle, runs `vimp.boostmtree()` `N_VIMP` times per fit and pools the runs with ggBoostedTrees 0.10.2; deprecate `nb-boostmtree` through the catalog. Closes #580 and #493.

**Architecture:** Two Quarto jobs in the `rfs-fit` / `rfs-explain` shape. `_fit` writes `set_path("estimates", "nb-boostmtree_fit.rds")`, a list `fit`, `refits`, `versions`, `k_shadow`, `seed` with handoff lineage on the **outer** list. `_explain` reads it with `.read_handoff()` and never fits. The old template stays on disk for one release, marked `deprecated_by: nb-boostmtree_fit`; `migrate_job()` writes `_fit` and its warning carries the deprecation note naming `_explain`. No new exported function; `R/` changes are the `migrate_job()` comment and warning, and (Task 7, conditional) a shadow term in `.boostmtree_need_gib()`.

**Tech Stack:** R, Quarto, testthat 3e, `boostmtree` (>= 2.0.13, CCF fork), `ggBoostedTrees` (>= 0.10.2: `gg_boost_vimp.list()`, `gg_boost_vimp_pool`, `boost_shadow()`), `hvtiRutilities` (`cache_fit()`, `cache_would_fit()`), `hvtiPlotR`, `withr`, `parallel`.

**Spec:** `dev/specs/2026-11-20-nb-boostmtree-split-design.md` (section 9 step 3 only). Steps 1 (ggBoostedTrees 0.10.2, released) and 2 (lri retime, running) are outside this plan; Task 7 consumes step 2's output.

### Three refinements to the spec, made while planning

All three follow from reading the code on 2026-11-20 and keep the spec's intent. **Refinement 1 changed a name the spec fixed; John confirmed it on 2026-11-20 and the spec now says `nb-boostmtree_fit.rds`.**

1. **The handoff is `nb-boostmtree_fit.rds`, not `nb-boostmtree-fit.rds` (spec section 4).** The spec chose `nb-boostmtree-fit.rds` so that the deprecated job could not overwrite `_fit`'s output. It can: the deprecated job's fit **cache** is `cache_fit("nb-boostmtree-fit", ...)` in `dirname(set_path("estimates", ...))`, which is the same folder, so its cache file is `estimates/<subject>-<type>/nb-boostmtree-fit.rds`, byte for byte the spec's handoff path. Rendering the old job after `_fit` in one set would find the bundle where its cache should be and stop as an unkeyed cache, or, with `REFIT <- TRUE`, overwrite the bundle; the gallery, which renders both in set `lvef-boost` (spec section 8), would fail. The underscore name matches the template name and collides with nothing the old job writes (`nb-boostmtree.rds`, `nb-boostmtree-fit`, `-vimp`, `-partial`, `-sensitivity-*`). The same reasoning renames every cache (refinement 3). The spec's test, "rendering the deprecated job in the same set leaves `_explain`'s input intact", is Task 4's, and its mutation is to put the spec's name back.
2. **`boost_shadow()` refuses a predictor that varies within a patient** ("covariates must be constant within subject", ggBoostedTrees 0.10.2 `R/boost_shadow.R`). The spec does not mention this. With `K_SHADOW <- 5` the default, a study whose built data carry a time-varying predictor would stop. `_fit` checks constancy in the `fit` chunk **before** the long-fit and memory guards and stops with a message naming the predictors and the two ways out (leave them out of `PREDICTORS`, or `K_SHADOW <- 0`). Shadows are drawn inside the quoted fit call, so `cache_fit()` seeds them with the fit's seed and `K_SHADOW` is a free variable of the call, hence in the cache key.
3. **Cache names carry the template name**: `_fit` caches `nb-boostmtree_fit-fit0` (the SEED fit), `nb-boostmtree_fit-fit<i>` (refit `i`, seed `SEED + i`), `nb-boostmtree_fit-sensitivity-nu<nu>-k<k>`; `_explain` caches `nb-boostmtree_explain-vimp-fit<i>-run<j>` and `nb-boostmtree_explain-partial`. `_explain` keeps its **own** `SEED` choice, as `rfs-explain` does; vimp run `j` on every fit is seeded `SEED + j`, so raising `N_VIMP` adds runs and never changes an existing run's key.

Two further decisions the spec left open: the #580 run-time table records the **peak memory of the fit and its workers together** (what `memory-Large.csv` measures, and what the session must hold), not per-worker memory; and the plateau width at `nu = 0.05` (spec section 9 step 2 "byproduct") is **not measured** by this retime, whose fits run `M = 10`, so it is recorded as not measured in the PR body and nowhere asserted.

## Global Constraints

- Floors in both templates: `boostmtree >= 2.0.13` (install line `ref = \"v2.0.13-ccf\"`) and `ggBoostedTrees >= 0.10.2` (install line `remotes::install_github(\"ehrlinger/ggBoostedTrees@v0.10.2\")`, never a `ref = ` form: `dev/check-boostmtree-pin.py` reads every `ref = \"...\"` in the file as the boostmtree tag).
- `DESCRIPTION` floors and `Version:` do not move in this PR (release-ordering rule; spec section 4).
- Handoff file: `set_path("estimates", "nb-boostmtree_fit.rds")`. Never `nb-boostmtree.rds`, never `nb-boostmtree-fit.rds` (refinement 1).
- Bundle: `list(fit = <SEED fit>, refits = <list of N_REFITS fits>, versions = c(boostmtree =, randomForestSRC =, ggBoostedTrees =), k_shadow = K_SHADOW, seed = SEED)`.
- Lineage on the **outer** list via `hvtiRtemplates:::.attach_handoff_lineage()`; none on `fit`. `analysis` gains `k_shadow` and `n_refits`.
- `_fit` study choices: `K_SHADOW <- 5`, `N_REFITS <- 0`. `_explain` study choices: `WHERE <- NULL`, `ID <- NULL`, `KEY <- NULL`, `N_VIMP <- 10`, `CORES`, `SEED <- 2026`, `EFFECT_VARIABLES <- NULL`, `N_TRACES <- 100`, `REFIT <- FALSE`, `SAVE_FIGURES <- TRUE`, `FIGURES <- NULL`.
- Refit `i` is grown under `SEED + i`; vimp run `j` under `SEED + j` (explain's SEED). Pooled run names `fit<i>.run<j>`, `fit0` the SEED fit.
- Plateau: iterations whose cross-validated `l2` error is within 1% of the minimum; **display only**. Prediction stays at `m.opt`. No selection rule.
- No detected / not-detected rule anywhere: the pool's `share` is reported, the reader judges.
- `K_SHADOW = 0` in the fit: `_explain` runs vimp once, draws the single-run figure, never calls the pool.
- Effect variables default: the six with the largest `median_importance` (main component, max across responses); the first run's importance when there are no shadows.
- Every study-specific line carries `EDIT:`; exactly one `^SUBJECT\s+<- ` and one `^TYPE\s+<- ` line per template; no study identifiers.
- Lines at most 135 characters; `lintr::lint_package()` gives 0 lints; each new template has its own **file** key in `.lintr`.
- Roxygen is markdown; write `%` bare. After `devtools::document()`, restore `RoxygenNote: 8.1.0` in `DESCRIPTION` (local roxygen2 8.1.1 rewrites it).
- `devtools::test()`: FAIL 0, WARN 0 under `NOT_CRAN=true`. Muffle a warning only by its class or exact message, never `suppressWarnings()`.
- Tests that fork run with `_R_CHECK_LIMIT_CORES_=TRUE`; tests use `nb_cores` (2, or 1 on Windows).
- Every R command runs with `R_LIBS=$LIB` (Task 1). Before any render test, install the branch into `$LIB`: `R CMD INSTALL --no-test-load -l "$LIB" .`.
- Never `git add -A` or `git add .` (failing testthat runs write `tests/testthat/_problems/`); add explicit paths.
- Never run anything against `/Volumes/qhsstudies`. Task 7 only copies two CSVs off it.
- One `news/feat-nb-boostmtree-split.md` fragment; no version bump.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never push to `main`.

Shell variables used throughout (set them in each new shell):

```sh
WT=$HOME/Documents/GitHub/hvtiRtemplates-nb-split
LIB=$HOME/Library/Caches/hvtiRtemplates-nb-split-lib
export R_LIBS="$LIB" NOT_CRAN=true _R_CHECK_LIMIT_CORES_=TRUE
```

`O` below means `git show origin/main:inst/templates/30_analyses/nb-boostmtree.qmd` (806 lines at `a4ab5c6`); line numbers refer to that file. Before Task 2, confirm they still match: `git show origin/main:inst/templates/30_analyses/nb-boostmtree.qmd | sed -n '59p;124p;376p;776p;792p'` must print `#| label: setup`, `#| label: edit-study-choices`, `#| label: fit`, `#| label: save`, `#| label: provenance`. If not, re-read the file and shift every range below by the same offset.

---

### Task 1: Worktree, branch and private library

**Files:** none in the repo.

**Interfaces:**
- Produces: worktree `$WT` on branch `feat/nb-boostmtree-split`; library `$LIB` holding ggBoostedTrees 0.10.2 and (re-installed before each render task) this branch's hvtiRtemplates.

- [ ] **Step 1: Check the spec PR and pick the base.**

```sh
cd $HOME/Documents/GitHub/hvtiRtemplates && git fetch origin && gh pr view 596 --json state,mergedAt --jq '"\(.state) \(.mergedAt)"'
```

`MERGED <date>`: base is `origin/main`. Anything else: base is `origin/docs/nb-boostmtree-split-spec`, and the PR in Task 8 says it is stacked on #596's content but is opened against `main` (a PR opened against another branch gets no Copilot review; AGENTS.md).

- [ ] **Step 2: Create the worktree.** Another session has `docs/sweep-1.6.2` checked out in the main clone, so work in a worktree.

```sh
cd $HOME/Documents/GitHub/hvtiRtemplates && git worktree add "$WT" -b feat/nb-boostmtree-split origin/main
```

(Use `origin/docs/nb-boostmtree-split-spec` in place of `origin/main` if Step 1 said so.) Expected: `Preparing worktree (new branch 'feat/nb-boostmtree-split')`.

- [ ] **Step 3: Install ggBoostedTrees 0.10.2 into the private library.**

```sh
mkdir -p "$LIB" && Rscript -e 'remotes::install_github("ehrlinger/ggBoostedTrees@v0.10.2", lib = Sys.getenv("LIB"), dependencies = FALSE, upgrade = "never")' && \
R_LIBS="$LIB" Rscript -e 'cat(format(packageVersion("ggBoostedTrees")), format(packageVersion("boostmtree")), "\n"); stopifnot(exists("gg_boost_vimp.list", asNamespace("ggBoostedTrees")), "boost_shadow" %in% getNamespaceExports("ggBoostedTrees"))'
```

Expected: `0.10.2 2.0.13`.

- [ ] **Step 4: Read the installed API before writing code against it.**

```sh
R_LIBS="$LIB" Rscript -e 'for (f in c("boost_shadow", "gg_boost_vimp_pool", "plot.gg_boost_vimp_pool")) tools::Rd2txt(utils:::.getHelpFile(help(f, package = "ggBoostedTrees")))' | head -150
R_LIBS="$LIB" Rscript -e 'print(args(hvtiRutilities::cache_fit)); print(args(boostmtree::vimp.boostmtree))'
```

Confirm: `boost_shadow(x, id, k = 5)`; the pool's columns `variable, component, response, n_runs, n_detected, share, median_importance, q15, q25, q50, q75, q85`; `vimp.boostmtree(object, x.names = NULL, joint = FALSE)`. If any differs, stop and report rather than adapt silently.

- [ ] **Step 5: Baseline.** Install the branch and run the nb tests as they stand, so later failures are attributable.

```sh
cd "$WT" && R CMD INSTALL --no-test-load -l "$LIB" . >/dev/null && Rscript -e 'devtools::test(filter = "nb-boostmtree")' 2>&1 | tail -5
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS <n> ]`. Record `<n>`. No commit in this task.

---

### Task 2: `nb-boostmtree_fit` template, its catalog row, lint key and tests

**Files:**
- Create: `inst/templates/30_analyses/nb-boostmtree_fit.qmd`
- Create: `tests/testthat/test-nb-boostmtree-fit.R`
- Modify: `tests/testthat/helper-nb.R` (template-parameterized runners, new floors, `nb_fit_in()`)
- Modify: `inst/extdata/templates.json` (insert the `boostmtree_fit` row after the `nb`/`boostmtree` object, line ~930)
- Modify: `.lintr` (new file key after the `nb-boostmtree.qmd` key, line 211-215)
- Modify: `dev/check-boostmtree-pin.py` (lines 12, 24, 53-67: check every `nb-boostmtree*.qmd`)
- Modify: template-list tests: `tests/testthat/test-data-contract.R` (lines 8-15, 45-46), `tests/testthat/test-template-provenance.R` (lines 243-251), `tests/testthat/test-template-figures.R` (lines 1-3, 34-35), `tests/testthat/test-template-data-routes.R` (lines 268-270 `readers` and `.long_join_templates`, 335-336, 406-410), `tests/testthat/test-job-data.R` (line 1201)

**Interfaces:**
- Consumes: `O` (the old template), `hvtiRtemplates:::.attach_handoff_lineage()`, `hvtiRutilities::cache_fit()` / `cache_would_fit()`, `ggBoostedTrees::boost_shadow()`.
- Produces: template `nb.boostmtree_fit` with chunks `setup`, `edit-study-choices`, `tbl-data`, `data-attrition`, `fit`, `tbl-fit`, `tbl-fit-summary`, `fit-checks`, `fig-error`, `fig-path`, `fig-calibration`, `sensitivity`, `tbl-versions`, `save`, `provenance`. After `fit` the chunk environment holds `fit`, `refits` (list), `.versions` (named chr), `.patient`, `.fit_names`, `.fit_seeds`, `CACHE_DIR`. After `tbl-fit-summary`: `fit_summary` with columns `component, best_m, cv_error, plateau, plateau_error` and, with refits, `best_m_range`. After `save`: file `nb-boostmtree_fit.rds` holding `nb_fit`. Figures `nb-boostmtree_fit-error`, `-path`, `-calibration`.
- Produces (tests): `nb_template(name)`, `nb_run(labels, env, choices, template)`, `nb_fit_run()`, `nb_fit_in(root, parent, choices)`, `nb_bundle_path(root)`.

- [ ] **Step 1: Generalize the helpers.** In `tests/testthat/helper-nb.R`:

Replace lines 3-8 (`nb_template`) and line 11 (`nb_run` signature) and line 12 (`src <- readLines(nb_template(), ...)`):

```r
nb_template <- function(name = "nb.boostmtree") {
  templates <- template_list()
  hit <- which(templates$name == name)
  if (length(hit) != 1L) stop("template '", name, "' found ", length(hit), " times", call. = FALSE)
  templates$file[[hit]]
}

# Evaluate chunks `labels` in `env`; `choices` overwrite edit-study-choices.
nb_run <- function(labels, env, choices = list(), template = "nb.boostmtree") {
  src <- readLines(nb_template(template), warn = FALSE)
```

and after `nb_run` add:

```r
nb_fit_run <- function(labels, env, choices = list()) nb_run(labels, env, choices, "nb.boostmtree_fit")
nb_explain_run <- function(labels, env, choices = list()) nb_run(labels, env, choices, "nb.boostmtree_explain")
nb_bundle_path <- function(root) file.path(hvtiRutilities::study_dir("estimates", root), "lvef-boost", "nb-boostmtree_fit.rds")
nb_set_dir <- function(root) file.path(hvtiRutilities::study_dir("estimates", root), "lvef-boost")
```

In `nb_setup_code()` (line 112) and `nb_mocked_setup()` (line 122) add a `template = "nb.boostmtree"` argument passed to `nb_template()`. In `nb_skip_unless_stack()` (line 135) change the floors to `c(boostmtree = "2.0.13", ggBoostedTrees = "0.10.2")`. In `nb_env()` (lines 101-106) add `"boost_shadow"` to the ggBoostedTrees vector. Replace `nb_fit_in()` (lines 196-200):

```r
nb_fit_in <- function(root, parent = globalenv(), choices = nb_choices(), template = "nb.boostmtree_fit") {
  env <- nb_env(root, parent)
  utils::capture.output(nb_run(c("setup", "edit-study-choices", "tbl-data", "fit", "save"), env, choices, template))
  env
}
```

(The old test file still calls `nb_fit_in()` expecting the old template; in that file change each `nb_fit_in(root` call to pass `template = "nb.boostmtree"`. It is deleted in Task 4.)

- [ ] **Step 2: Write the failing tests.** Create `tests/testthat/test-nb-boostmtree-fit.R`. It holds every fit-side test of the old file, repointed, plus the new ones. Copy these blocks from `git show origin/main:tests/testthat/test-nb-boostmtree.R` and apply the listed edits; every `nb_run(` becomes `nb_fit_run(`, every `"set"` label becomes `"setup"`, every `nb_template()` becomes `nb_template("nb.boostmtree_fit")`:

| old lines | test | edits beyond the three above |
|---|---|---|
| 1-8 | add_job scaffolds | `qualifier = "boostmtree_fit"`; filename regex `^nb[.]boostmtree_fit[.]lvef[.]boost[.]qmd$` |
| 10-116 | data chunk, KEY, structural predictors, case | none |
| 118-131 | setup floors | `nb_mocked_setup(..., template = "nb.boostmtree_fit")`; boostmtree `"2.0.12"`; ggBoostedTrees `"0.10.1"` and expected text `remotes::install_github(\"ehrlinger/ggBoostedTrees@v0.10.2\")`; titles say 2.0.13 / 0.10.2 |
| 133-143 | digest | none |
| 144-174 | no saved file holds an MRN | expected set files `c("nb-boostmtree_fit.rds", "nb-boostmtree_fit-fit0.rds", "nb-boostmtree_fit-fit0.provenance.json")` |
| 175-185 | WHERE on identifier | none |
| 186-210 | lineage selection / MTRY | read `attr(readRDS(nb_bundle_path(root)), "hvti_provenance")` |
| 211-227 | cache reuse | cache file `nb-boostmtree_fit-fit0.rds` |
| 228-278 | MTRY, CORES | none |
| 279-312 | progress | labels `c("tbl-data", "fit", "tbl-fit", "tbl-fit-summary")`; drop the `"prediction"` expectation (it moves to the explain file) |
| 529-592 | interactive guard, memory guard | none |
| 593-602 | lineage = provenance blocks | none (the template keeps both `analysis = list(response = .response` blocks on two lines) |
| 603-660 | K / N_KNOTS, edge warnings | none |
| 661-687 | SENSITIVITY | cache names `nb-boostmtree_fit-sensitivity-` |

Then append the new tests:

```r
test_that("every fit-side report chunk draws for every family, from a fresh fit and from the cache", {
  skip_on_cran()
  nb_skip_unless_stack()
  labels <- c("setup", "edit-study-choices", "tbl-data", "fit", "tbl-fit", "tbl-fit-summary", "fit-checks", "fig-error",
              "fig-path", "fig-calibration", "sensitivity", "tbl-versions", "save")
  components <- list(continuous = "lvef", binary = "lvef_bin = 1 against 0",
                     ordinal = c("lvef_ord threshold 1", "lvef_ord threshold 2"),
                     nominal = c("lvef_nom = low against high", "lvef_nom = mid against high"))
  for (family in names(nb_families)) {
    root <- nb_study(nb_family_data())
    choices <- nb_choices(RESPONSE = nb_families[[family]], FAMILY = family, PREDICTORS = c("age", "female", "grp"))
    for (pass in 1:2) {
      env <- nb_env(root)
      utils::capture.output(nb_fit_run(labels, env, choices))
      for (p in c("p_error", "p_path", "p_calibration")) {
        expect_s3_class(env[[p]], "ggplot")
        expect_no_error(ggplot2::ggplot_build(env[[p]]))
      }
      expect_identical(env$fit_summary$component, components[[family]], info = family)
      expect_identical(env$fit_checks$component, components[[family]], info = family)
      expect_null(env$sensitivity)
      expect_length(nb_files_holding(root, unique(nb_family_data()$ccfid)), 0L)
    }
  }
})

test_that("the fit saves the bundle, with lineage on the outer list only", {
  nb_skip_unless_stack()
  root <- nb_study()
  env <- nb_fit_in(root)
  bundle <- readRDS(nb_bundle_path(root))
  expect_identical(names(bundle), c("fit", "refits", "versions", "k_shadow", "seed"))
  expect_s3_class(bundle$fit, "boostmtree")
  expect_s3_class(bundle$fit, "grow")
  expect_identical(bundle$refits, list())
  expect_identical(bundle$k_shadow, 5)
  expect_identical(bundle$seed, 7)
  lineage <- attr(bundle, "hvti_provenance")
  expect_true(hvtiRtemplates:::.complete_lineage_shape(lineage))
  expect_gt(length(lineage$data), 0L)
  expect_identical(lineage$analysis$k_shadow, 5)
  expect_identical(lineage$analysis$n_refits, 0)
  expect_null(attr(bundle$fit, "hvti_provenance"))
  # The deprecated template's handoff name is never written.
  expect_false(file.exists(file.path(nb_set_dir(root), "nb-boostmtree.rds")))
  expect_false(file.exists(file.path(nb_set_dir(root), "nb-boostmtree-fit.rds")))
})

test_that("the bundle records the versions the fit was grown with", {
  nb_skip_unless_stack()
  root <- nb_study()
  nb_fit_in(root)
  versions <- readRDS(nb_bundle_path(root))$versions
  expect_identical(names(versions), c("boostmtree", "randomForestSRC", "ggBoostedTrees"))
  expect_identical(unname(versions), vapply(names(versions), function(p) format(utils::packageVersion(p)), "",
                                            USE.NAMES = FALSE))
})

test_that("shadows reach the fit, and K_SHADOW is part of the cache key", {
  nb_skip_unless_stack()
  root <- nb_study()
  env <- nb_fit_in(root)
  expect_true(all(c("age", "female", "grp") %in% env$fit$x.var.names))
  expect_length(grep("^shadow[1-5][.]", env$fit$x.var.names), 15L)
  expect_error(nb_fit_in(root, choices = nb_choices(K_SHADOW = 0)), "inputs$K_SHADOW", fixed = TRUE,
               class = "hvtiRutilities_stale_cache")
  env0 <- nb_fit_in(root, choices = nb_choices(K_SHADOW = 0, REFIT = TRUE))
  expect_length(grep("^shadow", env0$fit$x.var.names), 0L)
  expect_identical(readRDS(nb_bundle_path(root))$k_shadow, 0)
})

test_that("a predictor that varies within a patient stops before any guard or fit, unless K_SHADOW is 0", {
  nb_skip_unless_stack()
  data <- nb_data()
  data$hr <- 60 + seq_len(nrow(data)) %% 7
  root <- nb_study(data)
  env <- nb_env(root)
  # Stopped before any guard: nothing cached, nothing saved.
  expect_error(utils::capture.output(nb_fit_run(c("setup", "edit-study-choices", "tbl-data", "fit"), env, nb_choices())),
               "vary between visits.*hr.*K_SHADOW <- 0")
  expect_length(list.files(nb_set_dir(root), "[.]rds$"), 0L)
  expect_no_error(nb_fit_in(root, choices = nb_choices(K_SHADOW = 0)))
})

test_that("N_REFITS grows each refit under SEED + i, caches it, and the summary and error figure use them", {
  nb_skip_unless_stack()
  root <- nb_study()
  labels <- c("setup", "edit-study-choices", "tbl-data", "fit", "tbl-fit-summary", "fig-error", "save")
  env0 <- nb_env(root)
  utils::capture.output(nb_fit_run(labels, env0, nb_choices()))
  env <- nb_env(root)
  utils::capture.output(nb_fit_run(labels, env, nb_choices(N_REFITS = 2)))
  expect_true(all(file.exists(file.path(nb_set_dir(root), sprintf("nb-boostmtree_fit-fit%d.rds", 0:2)))))
  expect_identical(env$.fit_seeds, 7 + 0:2)
  expect_length(env$refits, 2L)
  expect_false(identical(env$refits[[1L]]$mu, env$fit$mu))
  # The SEED fit is the one already cached: adding refits does not refit it.
  expect_identical(env$fit$mu, env0$fit$mu)
  expect_true("best_m_range" %in% names(env$fit_summary))
  expect_length(env$p_error$layers, length(env0$p_error$layers) + 1L)
  expect_length(readRDS(nb_bundle_path(root))$refits, 2L)
  expect_identical(attr(readRDS(nb_bundle_path(root)), "hvti_provenance")$analysis$n_refits, 2)
})

test_that("the plateau is every iteration within 1% of the lowest error, and Best M lies on it", {
  nb_skip_unless_stack()
  root <- nb_study()
  env <- nb_env(root)
  utils::capture.output(nb_fit_run(c("setup", "edit-study-choices", "tbl-data", "fit", "tbl-fit-summary"), env,
                                   nb_choices(M = 20)))
  e <- if (is.matrix(env$fit$err.rate)) env$fit$err.rate else env$fit$err.rate[[1L]]
  p <- which(e[, "l2"] <= 1.01 * min(e[, "l2"]))
  expect_identical(env$fit_summary$plateau, paste0(min(p), " to ", max(p)))
  expect_equal(env$fit_summary$plateau_error, e[min(p), "l2"])
  expect_true(env$fit_summary$best_m >= min(p) && env$fit_summary$best_m <= max(p))
})

test_that("the report provenance carries the versions and the shadow and refit choices", {
  tpl <- readLines(nb_template("nb.boostmtree_fit"), warn = FALSE)
  prov <- grep("label: provenance", tpl, fixed = TRUE)
  expect_true(any(grepl("versions = as.list(.versions)", tpl[prov:length(tpl)], fixed = TRUE)))
  expect_true(any(grepl("k_shadow = K_SHADOW, n_refits = N_REFITS", tpl[prov:length(tpl)], fixed = TRUE)))
})
```

- [ ] **Step 3: Run them; they fail.**

```sh
cd "$WT" && Rscript -e 'devtools::test(filter = "nb-boostmtree-fit")' 2>&1 | tail -15
```

Expected: errors `template 'nb.boostmtree_fit' found 0 times`.

- [ ] **Step 4: Write the template.** Create `inst/templates/30_analyses/nb-boostmtree_fit.qmd`, assembled in this order.

**4a.** `O` lines 1-29 verbatim, except line 2 becomes `title: "Boosted multivariate trees: boostmtree fit"`.

**4b.** In place of `O` 31-40:

````markdown
<!-- EDIT: name the job this replaces (an `nb.<variable>.Boostmtree` job), and
     say which response, visit time and predictors it used.
     Replace this comment with that text. -->

An `nb-boostmtree_fit` job fits boosted multivariate trees to a response measured
repeatedly over follow-up, one row per visit, and reports how well it fits: the
cross-validated error path, the fitted rho, phi and lambda, and observed against
fitted values over time, and, when SENSITIVITY is on, how much the fit moves with
the learning rate and the size of the trees. It saves the fit for the
`nb-boostmtree_explain` job in the same set, which reports importance, partial
effects and patients' trajectories and never fits.
````

**4c.** `O` 41-57 verbatim (the set comment).

**4d.** The `setup` chunk: `O` 58-117 with these replacements. Lines 64-87 become:

```r
# boostmtree must be the CCF fork, 2.0.13 or later. Every study fits with
# cv.flag = TRUE, and in boostmtree 2.0.0 (the CRAN release) that flag leaves the
# in-sample fit frozen, so the stored coefficients diverge with M and every
# non-cross-validated result is wrong (kogalur/boostmtree#2, fixed by #3). 2.0.13
# is the floor because it is the release whose seed reproduces a fit: before it,
# the same SEED could grow a different fit. A seed reproduces a fit only within one
# randomForestSRC version, which is why the saved fit records that version too.
# 2.0.8 added the progress = argument and the lower worker memory this job relies on.
if (!requireNamespace("boostmtree", quietly = TRUE) || utils::packageVersion("boostmtree") < "2.0.13") {
  stop("This job needs boostmtree >= 2.0.13 from the CCF fork. Install it with\n",
       "  remotes::install_github(\"ehrlinger/boostmtree_src\", subdir = \"boostmtree\", ref = \"v2.0.13-ccf\")\n",
       "then re-render.", call. = FALSE)
}
# ggBoostedTrees 0.10.2 adds boost_shadow()'s companion, the pooled importance the
# explain job reads; this job needs boost_shadow() and the error, path and
# calibration figures, and holds the same floor so the pair installs together.
if (!requireNamespace("ggBoostedTrees", quietly = TRUE) || utils::packageVersion("ggBoostedTrees") < "0.10.2") {
  stop("This job needs ggBoostedTrees >= 0.10.2. Install it with\n",
       "  remotes::install_github(\"ehrlinger/ggBoostedTrees@v0.10.2\")\nthen re-render.", call. = FALSE)
}
```

and lines 113-114 become:

```r
# The fits are cached and the bundle saved through set_path(), by set, so a later render
# or the explain job finds this set's results and no other's.
```

The rest of `O` 58-117 (lines 58-63, 88-112, 115-117) verbatim.

**4e.** `O` 119-122 verbatim (heading and sentence), then the `edit-study-choices` chunk: `O` 123-257 verbatim (through `SEED <- 2026`), then this new text, then `O` 264-275 verbatim except line 271, whose example becomes `FIGURES <- c("nb-boostmtree_fit-error")`. (`O` 259-263, `EFFECT_VARIABLES` and `N_TRACES`, move to `_explain`.)

```r

# EDIT: shadow copies of every predictor, fitted beside the real ones. Each copy
# shuffles the predictors' values between patients, so it keeps their
# distribution and carries no signal; the explain job reads the largest shadow
# importance in each run as that run's noise band, and pools runs only when there
# are shadows. 0 turns them off: then no band can be drawn and the explain job
# runs importance once and cannot pool runs. Shadows need every predictor to be
# constant within a patient (a baseline value); the fit stops and names any that
# vary. Cost, measured 2026-11-20 on a laptop at 100 patients, M = 400, NU = 0.25:
# 5 shadows took the fit from 34.5 s to 40.5 s (about 17% more) and one importance
# run from 1.9 s to 6.8 s (about 3.6 times). A fit with shadows is a different
# model, so K_SHADOW is part of the cache key.
K_SHADOW <- 5

# EDIT: extra fits, each grown like the fit above under seed SEED + i and cached
# on its own. Each costs one full fit. Refitting is how the job catches an
# importance verdict that moves between seeds: in a 50-seed simulation a
# borderline effect cleared the noise band in 14 to 46% of runs, and a refit moved
# it as much as a rerun of importance did. 0 fits once.
N_REFITS <- 0
```

**4f.** `O` 276-372 verbatim (`## Cohort`, `tbl-data`, `data-attrition`).

**4g.** `O` 373-374 verbatim (`## Fit` and blank), then the `fit` chunk:

````markdown
```{r}
#| label: fit
#| message: true
# The fit groups visits by patient through `id`. It is given the study-keyed
# digest of each patient's ID, not the ID: a boostmtree fit stores the ID in
# several places, its base learners included, and every one of them is saved
# with it. A digest still groups the visits; it cannot be read back.
CACHE_DIR <- dirname(set_path("estimates", "nb-boostmtree_fit.rds"))
# A spline with as many knots as there are visit times has nothing left for the
# penalty to smooth: stopped here, before hours of fitting, not after.
.n_times <- length(unique(d[[.time]]))
if (N_KNOTS >= .n_times) {
  stop("N_KNOTS (", N_KNOTS, ") must be below the number of distinct visit times (", .n_times, "), ",
       "and well below it for sparse visits.", call. = FALSE)
}
.patient <- hvtiRtemplates:::.id_digest(d[[.id]], hvtiRtemplates:::.study_id_key(.root))
# A shadow shuffles values between patients, so each predictor needs one value per
# patient. boost_shadow() refuses one that varies; asked here, it stops in seconds,
# before the guards below and before any fit, and says what to do.
if (K_SHADOW > 0) {
  .varying <- .predictors[vapply(.predictors, function(v) {
    any(tapply(d[[v]], .patient, function(x) length(unique(x)) > 1L))
  }, logical(1L))]
  if (length(.varying)) {
    stop("Shadows need every predictor constant within a patient, and these vary between visits: ",
         paste(.varying, collapse = ", "), ". Leave them out of PREDICTORS, or set K_SHADOW <- 0 ",
         "(no noise band; nb-boostmtree_explain then runs importance once and cannot pool runs).", call. = FALSE)
  }
}
# The fit, quoted once so the memory check below and cache_fit() read the same call: a
# cache_fit() of a quoted call keys the call. The shadows are drawn inside it, so
# cache_fit() seeds them with the fit's own seed and K_SHADOW is part of the key.
.fit_code <- quote(
  boostmtree(x = if (K_SHADOW > 0) ggBoostedTrees::boost_shadow(d[.predictors], .patient, k = K_SHADOW) else d[.predictors],
             tm = d[[.time]], id = .patient, y = d[[.response]],
             family = FAMILY, M = M, nu = NU, k = K, n.knots = N_KNOTS, mtry = MTRY, mod.grad = TRUE,
             cv.flag = TRUE, verbose = FALSE,
             # get() keeps CORES out of cache_fit()'s key, which sees only the values
             # the call names directly: changing it must not mark an identical fit stale.
             control = boostmtree.control(cv.cores = get("CORES")),
             # Reports each boosting iteration to <job>.run.progress and the render log.
             # get() keeps the job's run record out of the cache key's inputs, as for
             # CORES: it changes what is reported, never what is fitted.
             # The fit keeps the reporter (boostmtree's formula environment holds it), which
             # is safe because the reporter's frame holds only `unit`: no run record is
             # saved with the fit.
             progress = get(".job")$progress("iteration"))
)
# The SEED fit and N_REFITS refits, refit i under SEED + i, each cached on its own,
# so raising N_REFITS fits only the new ones.
.fit_seeds <- SEED + c(0L, seq_len(N_REFITS))
.fit_names <- sprintf("nb-boostmtree_fit-fit%d", seq_along(.fit_seeds) - 1L)
# Refuses here, in the first minutes of the render, a fit this session's memory cannot hold, and
# names the Workbench profile to start; the numbers behind the estimate are in hvtiRtemplates'
# R/fit-memory.R. A cached fit is only loaded, so it needs nothing. Whether cache_fit() will fit
# is its own decision, asked the way it makes it: a file whose key matches loads even with REFIT
# left TRUE, and a stale file stops it before any fit unless REFIT is set. The call itself is
# unconditional, so a cached rerender still records the memory check that run_job() waits for.
# The fits run one after another, so the need is one fit's.
.need <- function(k) hvtiRtemplates:::.boostmtree_need_gib(length(unique(.patient)), nrow(d), FAMILY, k, M)
.fitting <- vapply(seq_along(.fit_seeds), function(i) {
  hvtiRutilities::cache_would_fit(.fit_names[[i]], .fit_code, seed = .fit_seeds[[i]], dir = CACHE_DIR, refit = REFIT)
}, logical(1L))
# The fit runs for hours at study size. Started from the console, the Render button or a terminal,
# it dies with the session, so a fit that will be computed is refused there: run the job with
# hvtiRtemplates::run_job() instead. Once cached, the Render button and these chunks load it.
for (.i in which(.fitting)) {
  hvtiRtemplates::guard_long_fit(.fit_names[[.i]], dir = CACHE_DIR,
                                 why = "a cross-validated boostmtree fit takes hours at study size", refit = REFIT)
}
hvtiRtemplates::guard_memory(if (any(.fitting)) .need(CORES) else 0,
                             sprintf("this boostmtree fit (%s patients, %s visits, %s)",
                                     format(length(unique(.patient)), big.mark = ","), format(nrow(d), big.mark = ","),
                                     FAMILY),
                             cores = CORES, cores_fit = .need)
fit <- cache_fit(.fit_names[[1L]], .fit_code, seed = .fit_seeds[[1L]], dir = CACHE_DIR, refit = REFIT)
refits <- lapply(seq_len(N_REFITS), function(i) {
  cache_fit(.fit_names[[i + 1L]], .fit_code, seed = .fit_seeds[[i + 1L]], dir = CACHE_DIR, refit = REFIT)
})
# The versions these fits were grown with. cache_fit() keys package versions, so a
# cached fit loads only under the versions it was grown with, and these are they.
.versions <- vapply(c("boostmtree", "randomForestSRC", "ggBoostedTrees"),
                    function(p) format(utils::packageVersion(p)), character(1L))
```
````

The memory-guard test (old lines 571-592) reads `tpl[fit:(fit + 3L)]` after the first `guard_memory(`: the three lines after it above hold `patients` and `visits`, so it passes unchanged.

**4h.** `O` 430-435 verbatim (prose and `## Does the fit work?`), then `tbl-fit`:

````markdown
```{r}
#| label: tbl-fit
#| tbl-cap: "The fit"
knitr::kable(data.frame(
  quantity = c("Family", "Iterations (M)", "Learning rate (nu)", "Terminal nodes (K)", "Spline knots",
               "Predictors per split (mtry)", "Shadow copies (K_SHADOW)", "Fits (1 + N_REFITS)", "Patients", "Visits"),
  value = c(FAMILY, M, NU, K, N_KNOTS, if (is.null(MTRY)) "all" else MTRY, K_SHADOW, 1L + N_REFITS,
            length(unique(.patient)), nrow(d))
), col.names = c("", ""))
```
````

**4i.** `tbl-fit-summary`: `O` 446-469 verbatim (chunk header through `.components <- switch(...)`), then:

```r
# The plateau: every iteration whose cross-validated error is within 1% of the
# lowest. Best M is one draw on it: across 50 seeds at nu = 0.25 and M = 400 it
# ran from 156 to 400. Prediction stays at Best M; the 1% is for display and
# changes no fitted value. A rule that picks an iteration on the plateau waits
# until predictions at its two ends are compared and found to differ.
.plateau <- lapply(.err, function(e) which(e[, "l2"] <= 1.01 * min(e[, "l2"])))
fit_summary <- data.frame(
  component = .components,
  best_m = as.integer(fit$m.opt),
  cv_error = mapply(function(e, m) e[m, "l2"], .err, fit$m.opt),
  plateau = vapply(.plateau, function(p) paste0(min(p), " to ", max(p)), character(1L)),
  plateau_error = mapply(function(e, p) e[min(p), "l2"], .err, .plateau)
)
.cols <- c("Response component", "Best M (cross-validated)", "Cross-validated error there (standardized)",
           "Plateau (within 1% of the lowest error)", "Error where the plateau starts")
# With refits, the spread of Best M across fits, one column per component's row.
# Their mean is not reported: Best M piles up at M on a flat curve, so its mean
# depends on M rather than the data, and no fit was grown at it.
if (length(refits)) {
  .m_all <- matrix(vapply(c(list(fit), refits), function(f) as.integer(f$m.opt), integer(length(.components))),
                   nrow = length(.components))
  fit_summary$best_m_range <- apply(.m_all, 1L, function(m) paste0(min(m), " to ", max(m)))
  .cols <- c(.cols, sprintf("Best M across the %d fits", ncol(.m_all)))
}
knitr::kable(fit_summary, col.names = .cols)
```

closing the chunk with ```` ``` ````, then this prose:

```markdown
Best M is the iteration with the lowest cross-validated error, and the fit
predicts there. On a flat error curve it is one draw from the plateau beside it:
another seed can put it anywhere on that plateau without changing the error much.
Read the plateau, not Best M alone, when judging whether M was enough.
```

**4j.** `fit-checks`: `O` 479-513 verbatim.

**4k.** `fig-error`:

````markdown
```{r}
#| label: fig-error
#| fig-cap: "Cross-validated error by boosting iteration. The black solid line is the error after each iteration, and the
#|   black dashed vertical line marks the iteration with the lowest error, Best M. When the job refits, a black dotted
#|   line gives the mean error across fits at each iteration."
# The cross-validated error by iteration; the next figure draws the fitted rho, phi and lambda.
# Best M at the right edge means M was too small. With refits, the mean CURVE across
# fits is drawn, never a mean Best M: see the summary table above.
p_error <- plot(gg_boost_error(fit))
if (length(refits)) {
  .curves <- do.call(rbind, lapply(c(list(fit), refits), gg_boost_error))
  .mean_curve <- stats::aggregate(value ~ iteration + response, data = .curves, FUN = mean)
  p_error <- p_error + ggplot2::geom_line(data = .mean_curve, ggplot2::aes(x = .data[["iteration"]], y = .data[["value"]]),
                                          linetype = "dotted", inherit.aes = FALSE)
}
p_error <- p_error + hvtiPlotR::theme_hv_manuscript(base_size = 12)
save_figure(p_error, "nb-boostmtree_fit-error")
p_error
```
````

**4l.** `fig-path` = `O` 526-535 with line 533's name `"nb-boostmtree_fit-path"`; `fig-calibration` = `O` 537-548 with line 546's name `"nb-boostmtree_fit-calibration"`.

**4m.** `sensitivity` = `O` 700-773 verbatim except line 714: `.grid$name <- sprintf("nb-boostmtree_fit-sensitivity-nu%s-k%s", .grid$nu, .grid$k)`. (Its cells reuse `.fit_code`, so they carry the same shadows; `.at_cell` binds no `K_SHADOW`, so it is read from the chunk.)

**4n.** Versions, save and provenance:

````markdown
## Package versions

A seed reproduces a boostmtree fit only within one randomForestSRC version: in
the 2026-11-20 seed study, none of 50 seeds grew the same fit under
randomForestSRC 3.9.0 and 3.10.0, though the fits agreed in distribution. The
saved fit records the versions it was grown with, and the explain job warns when
it runs under others.

```{r}
#| label: tbl-versions
#| tbl-cap: "Package versions the fit was grown with"
knitr::kable(data.frame(package = names(.versions), version = unname(.versions)), col.names = c("Package", "Version"))
```

```{r}
#| label: save
# The product of this job, and what nb-boostmtree_explain reads. It is separate
# from the caches on purpose: they are this job's internals and this file its
# interface. The lineage goes on the outer list, the object the explain job reads
# and validates; on the inner fit it would fail that check.
nb_fit <- list(fit = fit, refits = refits, versions = .versions, k_shadow = K_SHADOW, seed = SEED)
nb_fit <- hvtiRtemplates:::.attach_handoff_lineage(
  nb_fit,
  data = .provenance_data,
  analysis = list(response = .response, time = .time, family = FAMILY, M = M, nu = NU, k = K, n_knots = N_KNOTS,
                  mtry = if (is.null(MTRY)) "all" else MTRY, k_shadow = K_SHADOW, n_refits = N_REFITS),
  cohort = list(n_patients = length(unique(.patient)), n_visits = nrow(d)),
  selection = attr(job_data$record, "selection")
)
saveRDS(nb_fit, set_path("estimates", "nb-boostmtree_fit.rds"))
```

```{r}
#| label: provenance
#| echo: false
#| results: asis
cat(hvtiRtemplates:::.embed_provenance(
  .in,
  data = .provenance_data,
  run = .job$run,
  extra = list(
    subject = SUBJECT, type = TYPE,
    analysis = list(response = .response, time = .time, family = FAMILY, M = M, nu = NU, k = K, n_knots = N_KNOTS,
                    mtry = if (is.null(MTRY)) "all" else MTRY, k_shadow = K_SHADOW, n_refits = N_REFITS),
    cohort = list(n_patients = length(unique(.patient)), n_visits = nrow(d)),
    versions = as.list(.versions)
  )
))
```
````

- [ ] **Step 5: Catalog row, lint key, pin checker.**

Insert into `inst/extdata/templates.json` after the closing `},` of the `"qualifier": "boostmtree"` object:

```json
    {
      "prefix": "nb",
      "qualifier": "boostmtree_fit",
      "name": "Boosting: boostmtree fit",
      "description": "Fits boosted multivariate trees, with shadow covariates and optional refits, to a response measured repeatedly over follow-up, and reports its error path and plateau, fit over time and package versions.",
      "folder": "analyses",
      "family": "machine-learning",
      "kind": "job",
      "status": "shipped",
      "batch": null,
      "sas_breadth": 21,
      "r_exemplars": 19,
      "r_jobs": 63,
      "upstream": [],
      "downstream": [],
      "workflows": [],
      "blocked_on": null,
      "spec": "dev/specs/2026-11-20-nb-boostmtree-split-design.md",
      "note": "Fits and saves nb-boostmtree_fit.rds for nb-boostmtree_explain in the same set. Old nb.*.Boostmtree jobs map here.",
      "sas_breadth_jobs": 18,
      "disposition": "scaffold",
      "uses": [
        "ggBoostedTrees::boost_shadow",
        "hvtiRutilities::cache_fit",
        "ggBoostedTrees::gg_boost_error",
        "ggBoostedTrees::gg_boost_path",
        "ggBoostedTrees::gg_boost_calibration"
      ]
    },
```

In `.lintr`, after the `"inst/templates/30_analyses/nb-boostmtree.qmd" = list(...)` entry (lines 211-215), add the same three-linter entry keyed `"inst/templates/30_analyses/nb-boostmtree_fit.qmd"`.

In `dev/check-boostmtree-pin.py`: line 24 becomes `TEMPLATES = sorted((ROOT / "inst" / "templates" / "30_analyses").glob("nb-boostmtree*.qmd"))`; lines 53 and 61-64 check each:

```python
    for template in TEMPLATES:
        hint = re.findall(r'ref = \\"([^"\\]+)\\"', template.read_text(encoding="utf-8"))
        if hint != [ours]:
            problems.append(f"{template.name}'s install line names {hint or 'no tag'}, not the DESCRIPTION pin @{ours}.")
```

and the docstring (line 12) and success message (line 67) say "the nb-boostmtree templates' install lines". Run `python3 dev/check-boostmtree-pin.py` (needs network); expected `... agree.`.

- [ ] **Step 6: Template-list tests.** Edit, each with the new name only:
  - `test-data-contract.R`: add `"nb-boostmtree_fit"` to the converted list (line 14); line 46 becomes `if (name %in% c("nb-boostmtree", "nb-boostmtree_fit")) out[["KEY"]] <- "KEY <- c(ID, TIME)"`.
  - `test-template-provenance.R` line 250: add `"nb-boostmtree_fit"`.
  - `test-template-figures.R`: add `"nb-boostmtree_fit"` to `figure_templates`, and `` `nb-boostmtree_fit` = c("nb-boostmtree_fit-error", "nb-boostmtree_fit-path", "nb-boostmtree_fit-calibration") `` to `expected`.
  - `test-template-data-routes.R`: `readers` 30L to 31L (line 268); the `.long_join_templates` vector gains `"nb-boostmtree_fit"` after `"nb-boostmtree"`; line 335 accepts `c("nb-boostmtree.qmd", "nb-boostmtree_fit.qmd", "dc-trends.qmd")` and `expect_length(accept, 3L)`; the test at 406-410 reads `"nb-boostmtree_fit.qmd"` and its title says `nb-boostmtree_fit`.
  - `test-job-data.R` line 1201: `"such as dc-eda, dc-general, dc-tables, dc-trends, mm, nb-boostmtree, nb-boostmtree_fit or rhf-fit."`

- [ ] **Step 7: Run the fit tests and the list tests; they pass.**

```sh
cd "$WT" && Rscript -e 'devtools::test(filter = "nb-boostmtree|data-contract|template-provenance|template-figures|template-data-routes|job-data|template-catalog")' 2>&1 | tail -8
```

Expected: `FAIL 0 | WARN 0`. If a list test elsewhere fails naming `nb-boostmtree_fit` or `nb.boostmtree_fit`, it is a list of templates: add the name and record the file in the commit message.

- [ ] **Step 8: Mutation-prove the lineage placement.** In the `save` chunk, temporarily attach the lineage to `fit` instead (`nb_fit$fit <- hvtiRtemplates:::.attach_handoff_lineage(nb_fit$fit, ...)` and save without outer lineage). Run `devtools::test(filter = "nb-boostmtree-fit")`: "lineage on the outer list only" must fail. Revert (`git diff` on the template shows nothing from the mutation).

- [ ] **Step 9: Lint and commit.**

```sh
cd "$WT" && Rscript -e 'l <- lintr::lint_package(); print(l); quit(status = length(l) > 0)' && \
git add inst/templates/30_analyses/nb-boostmtree_fit.qmd tests/testthat/test-nb-boostmtree-fit.R tests/testthat/helper-nb.R \
  tests/testthat/test-nb-boostmtree.R inst/extdata/templates.json .lintr dev/check-boostmtree-pin.py \
  tests/testthat/test-data-contract.R tests/testthat/test-template-provenance.R tests/testthat/test-template-figures.R \
  tests/testthat/test-template-data-routes.R tests/testthat/test-job-data.R && \
git commit -m "feat: nb-boostmtree_fit, the fit half of nb-boostmtree, with shadows, refits and a bundled handoff

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `nb-boostmtree_explain` template, its catalog row, lint key and tests

**Files:**
- Create: `inst/templates/30_analyses/nb-boostmtree_explain.qmd`
- Create: `tests/testthat/test-nb-boostmtree-explain.R`
- Modify: `tests/testthat/helper-nb.R` (add `nb_explain_in()`, `nb_explain_choices()`)
- Modify: `inst/extdata/templates.json` (row after `boostmtree_fit`), `.lintr` (file key), `tests/testthat/test-data-contract.R` (lines 8-15, 28-30), `tests/testthat/test-template-figures.R`

**Interfaces:**
- Consumes: `nb-boostmtree_fit.rds` from Task 2 (bundle names exactly `fit, refits, versions, k_shadow, seed`), `hvtiRtemplates:::.read_handoff()`, `hvtiRtemplates:::.read_upstream_job_data()`, `ggBoostedTrees::gg_boost_vimp()` (list method), `plot.gg_boost_vimp_pool()`.
- Produces: template `nb.boostmtree_explain`, chunks `setup`, `edit-study-choices`, `fit`, `tbl-data`, `fig-importance`, `importance-runs`, `effects`, `fig-traces`, `provenance`. Objects: `.bundle`, `fit`, `refits`, `.fits` (named `fit0`, `fit1`, ...), `.runs_plan`, `.runs` (named `fit<i>.run<j>`), `.n_vimp`, `.pool` (`gg_boost_vimp_pool` or `NULL`), `importance_table` (or `NULL`), `p_vimp`, `.effect_vars`, `p_effects`, `p_traces`, `trace_means`. Figures `nb-boostmtree_explain-importance`, `-effects-<kind>-page-<NN>`, `-traces`. Caches `nb-boostmtree_explain-vimp-fit<i>-run<j>`, `nb-boostmtree_explain-partial`.

- [ ] **Step 1: Helpers.** Append to `tests/testthat/helper-nb.R`:

```r
nb_explain_choices <- function(...) utils::modifyList(list(N_VIMP = 3, SEED = 11, CORES = nb_cores), list(...))

# Fit in `root` with `fit_choices`, then run explain chunks `labels` in a fresh environment.
nb_explain_in <- function(root, labels = c("setup", "edit-study-choices", "fit", "tbl-data", "fig-importance",
                                           "importance-runs"),
                          choices = nb_explain_choices(), fit_choices = nb_choices(), fit = TRUE) {
  if (fit) nb_fit_in(root, choices = fit_choices)
  env <- nb_env(root)
  utils::capture.output(nb_explain_run(labels, env, choices))
  env
}
```

- [ ] **Step 2: Write the failing tests.** Create `tests/testthat/test-nb-boostmtree-explain.R`. Move these blocks from the old file, with `nb_run(` replaced by a fit followed by `nb_explain_run(`, `"set"` by `"setup"`, and the fit-side labels (`"tbl-data", "fit"` of the old template) by the explain labels `"fit", "tbl-data"`: old lines 360-369 (mean line), 370-380 (trace sample), 395-423 (partial cache: cache name `nb-boostmtree_explain-partial.rds`; the "fit is not refitted" stamp reads `nb-boostmtree_fit-fit0.rds`), 424-434 (factor alone), 436-458 (page sizes), 459-473 (one time: `nb_explain_run("fig-traces", env)`). Each moved test first calls `nb_fit_in(root)` and then runs explain chunks starting `c("setup", "edit-study-choices", "fit", ...)` with `nb_explain_choices(...)` carrying the old test's `EFFECT_VARIABLES` / `N_TRACES`. Then add:

```r
test_that("explain reads the bundle, never fits, and takes its lineage into provenance", {
  nb_skip_unless_stack()
  root <- nb_study()
  nb_fit_in(root)
  env <- nb_env(root)
  env$boostmtree <- function(...) stop("explain must never fit")
  utils::capture.output(nb_explain_run(c("setup", "edit-study-choices", "fit", "tbl-data"), env, nb_explain_choices()))
  expect_s3_class(env$fit, "boostmtree")
  expect_identical(env$.provenance_data, env$.fit_read$lineage$data)
  expect_identical(basename(env$.provenance_artifacts[[length(env$.provenance_artifacts)]]$path), "nb-boostmtree_fit.rds")
  expect_identical(env$.predictors, c("age", "female", "grp"))
})

test_that("explain stops, naming the fit job, on a missing file, a non-boostmtree fit, or lineage on the inner fit", {
  nb_skip_unless_stack()
  labels <- c("setup", "edit-study-choices", "fit")
  root <- nb_study()
  expect_error(utils::capture.output(nb_explain_run(labels, nb_env(root), nb_explain_choices())),
               "Render the nb-boostmtree_fit job in this set first", fixed = TRUE)
  nb_fit_in(root)
  path <- nb_bundle_path(root)
  good <- readRDS(path)
  bad <- good
  bad$fit <- list(x = 1)
  saveRDS(bad, path)
  expect_error(utils::capture.output(nb_explain_run(labels, nb_env(root), nb_explain_choices())),
               "does not hold a (boostmtree, grow) fit", fixed = TRUE)
  inner <- good
  attr(inner$fit, "hvti_provenance") <- attr(good, "hvti_provenance")
  attr(inner, "hvti_provenance") <- NULL
  saveRDS(inner, path)
  expect_error(utils::capture.output(nb_explain_run(labels, nb_env(root), nb_explain_choices())),
               "has no complete hvti_provenance lineage", fixed = TRUE)
})

test_that("a final render refuses a fit saved from unregistered working data", {
  nb_skip_unless_stack()
  root <- nb_study()
  nb_fit_in(root)
  path <- nb_bundle_path(root)
  b <- readRDS(path)
  lineage <- attr(b, "hvti_provenance")
  lineage$data[[1L]]$working <- TRUE
  attr(b, "hvti_provenance") <- lineage
  saveRDS(b, path)
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "1")
  expect_error(utils::capture.output(nb_explain_run(c("setup", "edit-study-choices", "fit"), nb_env(root),
                                                    nb_explain_choices())),
               "nb-boostmtree_fit.rds was saved from the working", fixed = TRUE)
})

test_that("explain warns when boostmtree or randomForestSRC differ from the fit's", {
  nb_skip_unless_stack()
  root <- nb_study()
  nb_fit_in(root)
  path <- nb_bundle_path(root)
  b <- readRDS(path)
  b$versions[["randomForestSRC"]] <- "0.0.1"
  saveRDS(b, path)
  env <- nb_env(root)
  expect_warning(out <- utils::capture.output(nb_explain_run(c("setup", "edit-study-choices", "fit"), env,
                                                             nb_explain_choices())),
                 "grown with randomForestSRC 0.0.1", fixed = TRUE)
  expect_true(any(grepl("callout-warning", out, fixed = TRUE)))
})

test_that("importance pools N_VIMP runs per fit, named fit<i>.run<j>, and reports the pool's counts unaltered", {
  nb_skip_unless_stack()
  root <- nb_study()
  env <- nb_explain_in(root, fit_choices = nb_choices(N_REFITS = 1))
  expect_identical(names(env$.runs), c("fit0.run1", "fit0.run2", "fit0.run3", "fit1.run1", "fit1.run2", "fit1.run3"))
  expect_s3_class(env$.pool, "gg_boost_vimp_pool")
  expect_identical(unique(env$importance_table$n_runs), 6L)
  expect_identical(env$importance_table$n_detected, env$.pool$n_detected)
  expect_identical(env$importance_table$share, env$.pool$share)
  runs <- list.files(nb_set_dir(root), "^nb-boostmtree_explain-vimp-fit[01]-run[1-3][.]rds$")
  expect_length(runs, 6L)
  expect_s3_class(env$p_vimp, "ggplot")
  expect_no_error(ggplot2::ggplot_build(env$p_vimp))
})

test_that("raising N_VIMP reuses the cached runs and adds only the new ones", {
  nb_skip_unless_stack()
  root <- nb_study()
  nb_explain_in(root, choices = nb_explain_choices(N_VIMP = 2))
  run <- function(j) file.path(nb_set_dir(root), sprintf("nb-boostmtree_explain-vimp-fit0-run%d.rds", j))
  stamp <- function(f) list(md5 = unname(tools::md5sum(f)), mtime = file.mtime(f))
  before <- lapply(1:2, function(j) stamp(run(j)))
  env <- nb_explain_in(root, choices = nb_explain_choices(N_VIMP = 3), fit = FALSE)
  expect_identical(lapply(1:2, function(j) stamp(run(j))), before)
  expect_true(file.exists(run(3)))
  expect_identical(unique(env$importance_table$n_runs), 3L)
})

test_that("with K_SHADOW = 0 explain runs importance once, draws one run, and never pools", {
  nb_skip_unless_stack()
  root <- nb_study()
  nb_fit_in(root, choices = nb_choices(K_SHADOW = 0))
  env <- nb_env(root)
  pooled <- 0L
  env$gg_boost_vimp <- function(object, ...) {
    if (!inherits(object, "vimp.boostmtree")) pooled <<- pooled + 1L
    ggBoostedTrees::gg_boost_vimp(object, ...)
  }
  out <- utils::capture.output(nb_explain_run(c("setup", "edit-study-choices", "fit", "tbl-data", "fig-importance",
                                                "importance-runs"), env, nb_explain_choices()))
  expect_identical(pooled, 0L)
  expect_identical(env$.n_vimp, 1L)
  expect_identical(names(env$.runs), "fit0.run1")
  expect_null(env$.pool)
  expect_null(env$importance_table)
  expect_true(any(grepl("no noise band and no share could be computed", out, fixed = TRUE)))
  expect_no_error(ggplot2::ggplot_build(env$p_vimp))
})

test_that("the default effect variables are the six with the largest median importance", {
  nb_skip_unless_stack()
  local_child_chunks()
  root <- nb_study()
  env <- nb_explain_in(root, labels = c("setup", "edit-study-choices", "fit", "tbl-data", "fig-importance",
                                        "importance-runs", "effects"))
  main <- env$.pool[env$.pool$component == "main", ]
  top <- sort(tapply(main$median_importance, as.character(main$variable), max), decreasing = TRUE)
  expect_identical(env$.effect_vars, head(names(top), 6L))
})

test_that("every explain chunk draws for every family, from fresh runs and from the cache", {
  skip_on_cran()
  nb_skip_unless_stack()
  local_child_chunks()
  labels <- c("setup", "edit-study-choices", "fit", "tbl-data", "fig-importance", "importance-runs", "effects", "fig-traces")
  components <- list(continuous = "lvef", binary = "lvef_bin = 1 against 0",
                     ordinal = c("lvef_ord threshold 1", "lvef_ord threshold 2"),
                     nominal = c("lvef_nom = low against high", "lvef_nom = mid against high"))
  for (family in names(nb_families)) {
    root <- nb_study(nb_family_data())
    nb_fit_in(root, choices = nb_choices(RESPONSE = nb_families[[family]], FAMILY = family,
                                         PREDICTORS = c("age", "female", "grp")))
    for (pass in 1:2) {
      env <- nb_env(root)
      utils::capture.output(nb_explain_run(labels, env, nb_explain_choices(N_TRACES = 10)))
      for (p in c("p_vimp", "p_traces")) expect_no_error(ggplot2::ggplot_build(env[[p]]))
      drawn <- unlist(lapply(env$p_effects, function(e) as.character(unique(e$data$variable))))
      expect_identical(sort(drawn), sort(env$.effect_vars), info = family)
      for (e in env$p_effects) expect_identical(levels(e$data$response), components[[family]], info = family)
    }
  }
})

test_that("the partial effects report their steps", {
  nb_skip_unless_stack()
  local_child_chunks()
  root <- nb_study()
  nb_fit_in(root)
  env <- nb_env(root)
  nb_explain_run(c("setup", "edit-study-choices"), env, nb_explain_choices())
  seen <- new.env(parent = emptyenv())
  seen$units <- character()
  bare <- list2env(list(seen = seen), parent = baseenv())
  env$.job$progress <- function(unit) {
    force(unit)
    function(step, steps) seen$units <- c(seen$units, unit)
  }
  environment(env$.job$progress) <- bare
  utils::capture.output(nb_explain_run(c("fit", "tbl-data", "fig-importance", "importance-runs", "effects"), env))
  expect_true("prediction" %in% seen$units)
})

test_that("no explain output prints an identifier", {
  nb_skip_unless_stack()
  local_child_chunks()
  data <- nb_data(id = "MRN")
  root <- nb_study(data)
  nb_fit_in(root)
  env <- nb_env(root)
  out <- utils::capture.output(nb_explain_run(c("setup", "edit-study-choices", "fit", "tbl-data", "fig-importance",
                                                "importance-runs", "effects", "fig-traces"), env,
                                              nb_explain_choices(N_TRACES = 10)))
  expect_false(any(vapply(unique(data$MRN), function(v) any(grepl(v, out, fixed = TRUE)), logical(1L))))
  expect_length(nb_files_holding(root, unique(data$MRN)), 0L)
})
```

The "no warning on matching versions" case is covered by every other explain test running at WARN 0.

- [ ] **Step 3: Run them; they fail.**

```sh
cd "$WT" && Rscript -e 'devtools::test(filter = "nb-boostmtree-explain")' 2>&1 | tail -8
```

Expected: `template 'nb.boostmtree_explain' found 0 times`.

- [ ] **Step 4: Write the template.** Create `inst/templates/30_analyses/nb-boostmtree_explain.qmd`:

**4a.** `O` lines 1-29, line 2 `title: "Boosted multivariate trees: boostmtree explain"`.

**4b.**

````markdown
<!-- EDIT: say which nb-boostmtree_fit job in this set this explains, and what
     question the importance and effect plots are meant to answer. -->

Explains the fit the `nb-boostmtree_fit` job in this set saved.

An `nb-boostmtree_explain` job never fits. It reads `nb-boostmtree_fit.rds`,
which the fit job writes, and reports variable importance over repeated runs,
partial effects over time and a sample of patients' fitted trajectories, all of
that saved fit and no other. Each importance run is cached on its own, so
raising N_VIMP pays only for the new runs.
````

**4c.** `O` 41-57 verbatim.

**4d.** `setup`: Task 2's `_fit` setup chunk verbatim (same floors and install lines), except its two-line cache comment becomes:

```r
# The importance runs and partial effects are cached through set_path(), by set,
# beside the fit this job reads, and no other set's.
```

**4e.**

````markdown
## Study choices

Edit these values for this study before rendering. The response, visit time,
predictors, iterations, shadows and refits are not here: they come from the fit.

```{r}
#| label: edit-study-choices
# EDIT: the fit's selection is used; set any of these only to confirm it.
# NULL takes the value the fit job used.
WHERE <- NULL
ID <- NULL
KEY <- NULL

# EDIT: importance runs on each fit the fit job saved (the SEED fit and its
# N_REFITS refits), so N_VIMP * (1 + N_REFITS) in all. Each run permutes every
# predictor once at random; repeated runs show how stable a verdict is. A share of
# runs is stability, not significance: there is no error rate behind it. Each run
# costs about 0.17 of a fit at K_SHADOW = 5 (measured at 100 patients). Each is
# cached on its own, so raising N_VIMP pays only for the new runs. With no shadows
# in the fit there is no band to judge runs against, and importance runs once.
N_VIMP <- 10

# EDIT: cores for the importance runs, one run per core. Each core is a forked copy
# of R holding the fit, so memory limits CORES on a large study. Not part of any
# cache key: cache_fit() seeds every run, so results do not depend on it.
CORES <- if (.Platform$OS.type == "windows") 1L else 4L

# EDIT: seeds the importance runs, run j on every fit under SEED + j, and the
# sample of patients the trajectory plot draws. Part of every cache key.
SEED <- 2026

# EDIT: the variables to draw partial effects for, or NULL for the six with the
# largest median importance across runs. N_TRACES patients are sampled for the
# trajectory plot; Inf draws every one.
EFFECT_VARIABLES <- NULL
N_TRACES <- 100
```
````

then `O` 264-275 verbatim inside the same chunk (REFIT, SAVE_FIGURES, FIGURES), with line 271's example `FIGURES <- c("nb-boostmtree_explain-importance")`, and the chunk's closing fence.

**4f.**

````markdown
## The fit

```{r}
#| label: fit
#| results: asis
.handoff <- set_path("estimates", "nb-boostmtree_fit.rds")
if (!file.exists(.handoff)) {
  stop("No fit at ", .handoff, ". Render the nb-boostmtree_fit job in this set first; ",
       "this job explains that fit and never fits its own.", call. = FALSE)
}
.cfg <- study_config(start = .root)
# Read through .read_handoff(), never readRDS(): it validates the lineage the fit
# job attached, and a final render refuses a fit saved from unregistered data.
.fit_read <- hvtiRtemplates:::.read_handoff(.handoff, "fit", .cfg, "the nb-boostmtree_fit job")
.bundle <- .fit_read$value
.provenance_data <- .fit_read$lineage$data
.provenance_artifacts <- c(.fit_read$lineage$artifacts, list(.fit_read$record))
fit <- .bundle$fit
if (!(inherits(fit, "boostmtree") && inherits(fit, "grow"))) {
  stop("nb-boostmtree_fit.rds does not hold a (boostmtree, grow) fit. Render the nb-boostmtree_fit job in this set ",
       "again.", call. = FALSE)
}
refits <- .bundle$refits
CACHE_DIR <- dirname(.handoff)
.response <- .fit_read$lineage$analysis$response
.time <- .fit_read$lineage$analysis$time
# The fit's real predictors; its shadow copies are named shadow<j>.<predictor>.
.predictors <- fit$x.var.names[!grepl("^shadow[0-9]+[.]", fit$x.var.names)]
# Importance pushes permuted data down the saved trees, and that path runs
# through randomForestSRC, so a run under other versions may not match one under
# the fit's. Said in the report and as a warning, not refused.
.recorded <- .bundle$versions[c("boostmtree", "randomForestSRC")]
.installed <- vapply(names(.recorded), function(p) format(utils::packageVersion(p)), character(1L))
.moved <- names(.recorded)[.recorded != .installed]
if (length(.moved)) {
  .msg <- paste0("The fit was grown with ", paste(.moved, .recorded[.moved], collapse = " and "),
                 "; this session has ", paste(.moved, .installed[.moved], collapse = " and "),
                 ". Importance runs through randomForestSRC on the saved trees, so these runs may not match ",
                 "one on the fit's versions. Render nb-boostmtree_fit again to grow the fit on these.")
  cat("::: {.callout-warning}\n", .msg, "\n:::\n\n", sep = "")
  warning(.msg, call. = FALSE)
}
```
````

then, inside the same chunk before its closing fence, `O` 454-469 verbatim (the component labels: `.labels`, `.reference`, `.components`; the `.err` line 453 is not needed).

**4g.**

````markdown
```{r}
#| label: tbl-data
#| tbl-cap: "The data the fit job read"
# This job reads no data: the fit carries its training rows. The fit job
# recorded how it chose them, and a setting above that differs from the fit's
# stops here rather than describe rows the fit was not grown on.
.sel <- hvtiRtemplates:::.read_upstream_job_data(
  .cfg, .fit_read$lineage, list(where = WHERE, id = ID, key = KEY), read = FALSE, source = "nb-boostmtree_fit.rds"
)$selection
knitr::kable(data.frame(step = c("ID", "KEY", "WHERE", "Rows"),
                        value = c(.sel$id, paste(.sel$key, collapse = ", "),
                                  if (length(.sel$where_shown)) paste(.sel$where_shown, collapse = "; ") else "none",
                                  .sel$rows)),
             col.names = c("Data", ""))
```
````

**4h.**

````markdown
## Importance

```{r}
#| label: fig-importance
#| fig-cap: "Importance of each predictor's main effect and of its interaction with time, one panel for each. With shadow
#|   covariates, each box spans the 25th to 75th percentile of a predictor's margin over its own run's noise band
#|   across runs, the whiskers the 15th to 85th, each point is one run, the label k/N counts the runs in which it
#|   cleared the band, and the vertical line marks zero. Without shadows, horizontal dark gray bars give one run's
#|   importance."
#| fig-width: 9.75
#| fig-height: 10.5
# vimp.boostmtree() permutes each predictor at random, so one run's verdict on a
# predictor near the noise band can land on either side of it. Each fit gets
# N_VIMP runs, run j seeded SEED + j and cached on its own, and the runs are
# pooled: each is judged against its own band, never a pooled one.
.fits <- c(list(fit0 = fit), stats::setNames(refits, sprintf("fit%d", seq_along(refits))))
.n_vimp <- if (.bundle$k_shadow > 0) as.integer(N_VIMP) else 1L
.runs_plan <- data.frame(fit = rep(names(.fits), each = .n_vimp), run = rep(seq_len(.n_vimp), times = length(.fits)),
                         stringsAsFactors = FALSE)
.runs_plan$name <- paste0(.runs_plan$fit, ".run", .runs_plan$run)
.vimp_code <- quote(vimp.boostmtree(f))
.vimp_run <- function(i) {
  f <- .fits[[.runs_plan$fit[[i]]]]
  # One randomForestSRC thread per forked worker, so CORES runs use CORES threads.
  if (CORES > 1L) withr::local_options(rf.cores = 1L)
  cache_fit(sprintf("nb-boostmtree_explain-vimp-%s-run%d", .runs_plan$fit[[i]], .runs_plan$run[[i]]), .vimp_code,
            seed = SEED + .runs_plan$run[[i]], dir = CACHE_DIR, refit = REFIT)
}
.runs <- if (CORES > 1L) {
  parallel::mclapply(seq_len(nrow(.runs_plan)), .vimp_run, mc.cores = CORES)
} else {
  lapply(seq_len(nrow(.runs_plan)), .vimp_run)
}
# mclapply() returns an error as a value; raise the first one as it was, its class
# included, so a stale cache still names what changed.
.failed <- which(vapply(.runs, inherits, logical(1L), "try-error"))
if (length(.failed)) stop(attr(.runs[[.failed[[1L]]]], "condition"))
names(.runs) <- .runs_plan$name
.pool <- if (.bundle$k_shadow > 0) gg_boost_vimp(.runs) else NULL
p_vimp <- plot(if (is.null(.pool)) gg_boost_vimp(.runs[[1L]]) else .pool) + hvtiPlotR::theme_hv_manuscript(base_size = 12)
save_figure(p_vimp, "nb-boostmtree_explain-importance", width = 6.5, height = 7)
p_vimp
```

```{r}
#| label: importance-runs
#| results: asis
# unnumbered: its child chunk carries its own label and caption
importance_table <- NULL
if (is.null(.pool)) {
  cat("The fit has no shadow covariates (K_SHADOW was 0 in nb-boostmtree_fit), so no noise band and no share could ",
      "be computed, and importance ran once. The figure shows that one run; a predictor's place in it is not a ",
      "verdict.\n\n", sep = "")
} else {
  importance_table <- .pool[, c("variable", "component", "response", "n_detected", "n_runs", "share",
                                "median_importance", "q25", "q75")]
  class(importance_table) <- "data.frame"
  cat(sprintf(paste("Importance pools %d runs on %s, %d in all. For each predictor and panel the table gives the",
                    "runs in which it cleared that run's noise band, their share, the median importance and the",
                    "25th and 75th percentiles of the margin over the band. The share says how stable a single",
                    "run's verdict is, not whether the effect is real: in a 50-seed simulation, strong effects",
                    "cleared the band in 98 to 100%% of runs, true nulls in 0 to 6%% and borderline effects in",
                    "14 to 46%%. A share in that last range is a borderline effect, and more runs or refits will",
                    "not settle it.\n\n"),
              .n_vimp, if (length(.fits) == 1L) "1 fit" else sprintf("each of %d fits", length(.fits)),
              nrow(.runs_plan)))
  .fence <- strrep("`", 3)
  cat(knitr::knit_child(text = c(
    paste0(.fence, "{r}"), "#| label: tbl-importance",
    "#| tbl-cap: \"How often each predictor cleared its run's noise band, by panel\"",
    paste("knitr::kable(importance_table, digits = 3, col.names = c('Predictor', 'Effect', 'Response', 'Runs cleared',",
          "'Runs', 'Share', 'Median importance', 'Margin, 25th percentile', 'Margin, 75th percentile'))"),
    .fence
  ), envir = environment(), quiet = TRUE), sep = "\n")
}
```
````

**4i.** `## Partial effects` heading, then the `effects` chunk: `O` 568-571 verbatim (header and the "unnumbered" comment), then in place of `O` 572-577:

```r
# Partial effects over time, on the SEED fit, for EFFECT_VARIABLES or the six
# with the largest median importance across runs (the first run's importance
# when the fit has no shadows), so the pages do not reshuffle between renders.
# An ordinal or nominal fit reports importance once per response component, so a
# variable is ranked by its largest importance across them.
if (is.null(.pool)) {
  .vimp_main <- gg_boost_vimp(.runs[[1L]], components = "main")
  .top <- sort(tapply(.vimp_main$importance, as.character(.vimp_main$variable), max), decreasing = TRUE)
} else {
  .vimp_main <- .pool[.pool$component == "main", ]
  .top <- sort(tapply(.vimp_main$median_importance, as.character(.vimp_main$variable), max), decreasing = TRUE)
}
.effect_vars <- if (is.null(EFFECT_VARIABLES)) head(names(.top), 6L) else EFFECT_VARIABLES
```

then `O` 578-660 verbatim except line 598 `.partial <- cache_fit("nb-boostmtree_explain-partial",` and line 651 `save_figure(.p, sprintf("nb-boostmtree_explain-effects-%s-page-%02d", .pg$kind, .pg$page),`. (`.vimp_main` from a single run is a `gg_boost_vimp` frame that includes shadow rows when the fit has shadows; with no shadows there are none, so no filter is needed. The pool excludes shadows itself.)

**4j.** `## Trajectories` heading, then `fig-traces` = `O` 662-698 verbatim except line 696 `save_figure(p_traces, "nb-boostmtree_explain-traces")`.

**4k.**

````markdown
```{r}
#| label: provenance
#| echo: false
#| results: asis
cat(hvtiRtemplates:::.embed_provenance(
  .in,
  data = .provenance_data,
  run = .job$run,
  artifacts = .provenance_artifacts,
  extra = list(
    subject = SUBJECT, type = TYPE,
    analysis = c(.fit_read$lineage$analysis, list(n_vimp = .n_vimp, n_runs = nrow(.runs_plan))),
    cohort = .fit_read$lineage$cohort
  )
))
```
````

- [ ] **Step 5: Catalog row, lint key, list tests.** Insert after the `boostmtree_fit` row:

```json
    {
      "prefix": "nb",
      "qualifier": "boostmtree_explain",
      "name": "Boosting: boostmtree explain",
      "description": "Explains a saved boostmtree fit: importance pooled over repeated runs against shadow covariates, partial effects over time and patient trajectories. It never fits.",
      "folder": "analyses",
      "family": "machine-learning",
      "kind": "job",
      "status": "shipped",
      "batch": null,
      "sas_breadth": null,
      "r_exemplars": null,
      "r_jobs": null,
      "upstream": [],
      "downstream": [],
      "workflows": [],
      "blocked_on": null,
      "spec": "dev/specs/2026-11-20-nb-boostmtree-split-design.md",
      "note": "Reads nb-boostmtree_fit.rds from nb-boostmtree_fit in the same set and never fits. Census counts are on the fit row, which it shares.",
      "sas_breadth_jobs": null,
      "disposition": "scaffold",
      "uses": [
        "hvtiRutilities::cache_fit",
        "ggBoostedTrees::gg_boost_vimp",
        "ggBoostedTrees::gg_boost_effect",
        "ggBoostedTrees::gg_boost_trajectory"
      ]
    },
```

`.lintr`: the three-linter key for `"inst/templates/30_analyses/nb-boostmtree_explain.qmd"`. `test-data-contract.R`: add `"nb-boostmtree_explain"` to the converted list, to `downstream_templates` (line 28) and to the `reads_data()` exclusion (line 30). `test-template-figures.R`: add `"nb-boostmtree_explain"` to `figure_templates` and `` `nb-boostmtree_explain` = c("nb-boostmtree_explain-importance", "nb-boostmtree_explain-effects-", "nb-boostmtree_explain-traces") ``.

- [ ] **Step 6: Run; they pass.**

```sh
cd "$WT" && Rscript -e 'devtools::test(filter = "nb-boostmtree|data-contract|template-figures|template-catalog|template-provenance")' 2>&1 | tail -8
```

Expected: `FAIL 0 | WARN 0`.

- [ ] **Step 7: Mutation-prove the pooling test (spec section 8).** In `fig-importance`, change `names(.runs) <- .runs_plan$name` to `.runs <- head(.runs, -1L); names(.runs) <- head(.runs_plan$name, -1L)`. Run `devtools::test(filter = "nb-boostmtree-explain")`: "importance pools N_VIMP runs per fit" and "raising N_VIMP" must fail. Revert. Then mutate `.read_handoff(...)` to `list(value = readRDS(.handoff), lineage = attr(readRDS(.handoff), "hvti_provenance"), record = list(path = .handoff))`: "lineage on the inner fit" and "unregistered working data" must fail. Revert; `git diff` shows no mutation left.

- [ ] **Step 8: Lint and commit.**

```sh
cd "$WT" && Rscript -e 'l <- lintr::lint_package(); print(l); quit(status = length(l) > 0)' && \
git add inst/templates/30_analyses/nb-boostmtree_explain.qmd tests/testthat/test-nb-boostmtree-explain.R \
  tests/testthat/helper-nb.R tests/testthat/test-nb-boostmtree.R inst/extdata/templates.json .lintr \
  tests/testthat/test-data-contract.R tests/testthat/test-template-figures.R && \
git commit -m "feat: nb-boostmtree_explain reads the fit bundle and pools N_VIMP importance runs per fit

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(`test-nb-boostmtree.R` is staged because Step 2 moved its explain-side tests out.)

---

### Task 4: Deprecate `nb-boostmtree`, and `migrate_job()` for a split

Why this follows Tasks 2-3 rather than leading: `check-roadmap-counts.py` requires `deprecated_by` to name a **shipped row on disk**, so the deprecation cannot land before `_fit` exists.

**Files:**
- Modify: `inst/extdata/templates.json` (the `"qualifier": "boostmtree"` row: add two fields)
- Modify: `R/migrate-job.R` (roxygen line 14; lines 182-188)
- Modify: `man/migrate_job.Rd` (regenerated)
- Modify: `tests/testthat/test-deprecation.R` (lines 20-28; new tests)
- Modify: `tests/testthat/test-upgrade-job.R` (lines 612-614)
- Delete: `tests/testthat/test-nb-boostmtree.R` (every remaining test there is now in the fit or explain file; the deprecated template is frozen and keeps catalog-wide coverage plus the tests below)

**Interfaces:**
- Consumes: `.template_deprecation()`, `.warn_if_deprecated()`, `.warn_deprecated()` (`R/templates.R` 272-302), `migration_study_fixture()`, `caught_warnings()` (test helpers).
- Produces: catalog fields `deprecated_by = "nb-boostmtree_fit"`, `deprecation_note` (text below); `migrate_job()` warning `"migrate_job(): nb.boostmtree is deprecated in favor of nb.boostmtree_fit, so this job is written from nb.boostmtree_fit instead. <note>"`.

- [ ] **Step 1: Failing tests.** In `test-deprecation.R` replace the test at lines 20-29 with:

```r
test_that("the catalog lists the two renames, and marks only nb-boostmtree deprecated", {
  renames <- hvtiRtemplates:::.template_renames()
  expect_identical(renames$from, c("dp-eda", "dp-trends"))
  expect_identical(renames$to, c("dc-eda", "dc-trends"))
  expect_identical(renames$from_folder, c("descriptive", "graphs"))
  shipped <- sub(".", "-", template_list()$name, fixed = TRUE)
  expect_true(all(renames$to %in% shipped))
  expect_false(any(renames$from %in% shipped))
  catalog <- template_catalog()
  marked <- catalog[!is.na(catalog$deprecated_by), ]
  expect_identical(paste(marked$prefix, marked$qualifier, sep = "-"), "nb-boostmtree")
  expect_identical(marked$deprecated_by, "nb-boostmtree_fit")
  expect_match(marked$deprecation_note, "nb-boostmtree_explain", fixed = TRUE)
})
```

and append:

```r
test_that("nb-boostmtree warns from add_job() and still scaffolds", {
  root <- migration_study_fixture(NULL)
  expect_warning(job <- add_job("nb", "lvef", "boost", root = root, qualifier = "boostmtree"),
                 "nb.boostmtree is deprecated in favor of nb.boostmtree_fit", class = "hvtiRtemplates_deprecated")
  expect_true(file.exists(job))
})

test_that("upgrade_job() on an old nb-boostmtree job warns and keeps every chunk", {
  root <- migration_study_fixture(NULL)
  job <- withCallingHandlers(add_job("nb", "lvef", "boost", root = root, qualifier = "boostmtree"),
                             hvtiRtemplates_deprecated = function(w) invokeRestart("muffleWarning"))
  labels <- grep("^#\\| label: ", readLines(job), value = TRUE)
  expect_warning(upgrade_job(job), "nb.boostmtree is deprecated", class = "hvtiRtemplates_deprecated")
  expect_identical(grep("^#\\| label: ", readLines(job), value = TRUE), labels)
  expect_true(all(c("#| label: fig-importance", "#| label: effects", "#| label: fig-traces") %in% labels))
})

test_that("migrate_job() writes an nb-boostmtree source as nb-boostmtree_fit and names the explain job", {
  root <- migration_study_fixture(NULL)
  dir.create(file.path(root, "analyses"), showWarnings = FALSE)
  source <- file.path(root, "analyses", "nb.boostmtree.lvef.sas")
  writeLines(c("* nb boostmtree job;", "data a; set b; run;"), source)
  got <- caught_warnings(migrate_job(source, "lvef", "boost", prefix = "nb", qualifier = "boostmtree", root = root))
  dep <- Filter(function(w) inherits(w, "hvtiRtemplates_deprecated"), got$warnings)
  expect_length(dep, 1L)
  expect_match(conditionMessage(dep[[1L]]), "written from nb.boostmtree_fit instead", fixed = TRUE)
  expect_match(conditionMessage(dep[[1L]]), "nb-boostmtree_explain", fixed = TRUE)
  expect_match(basename(got$value), "^nb[.]boostmtree_fit[.]lvef[.]boost[.]qmd$")
})
```

If `migration_study_fixture(NULL)` already lays out `30_analyses/` rather than `analyses/`, put the source in the folder it created (`hvtiRutilities::study_dir("analyses", root)`).

Append to `tests/testthat/test-nb-boostmtree-fit.R` (the spec's path test):

```r
test_that("rendering the deprecated job in the same set leaves the explain job's input intact", {
  nb_skip_unless_stack()
  root <- nb_study()
  nb_fit_in(root)
  bundle <- nb_bundle_path(root)
  before <- list(md5 = unname(tools::md5sum(bundle)), mtime = file.mtime(bundle))
  nb_fit_in(root, template = "nb.boostmtree")
  expect_identical(list(md5 = unname(tools::md5sum(bundle)), mtime = file.mtime(bundle)), before)
  expect_true(file.exists(file.path(nb_set_dir(root), "nb-boostmtree.rds")))
  env <- nb_env(root)
  expect_no_error(utils::capture.output(nb_explain_run(c("setup", "edit-study-choices", "fit"), env, nb_explain_choices())))
})
```

Run: `devtools::test(filter = "deprecation|nb-boostmtree-fit")`. Expected failures: the catalog test (nothing marked), the three new deprecation tests. The same-set test passes already; prove it by mutation in Step 4.

- [ ] **Step 2: Mark the row.** In the `"qualifier": "boostmtree"` object of `inst/extdata/templates.json`, after `"uses": [...]`, add:

```json
      ,
      "deprecated_by": "nb-boostmtree_fit",
      "deprecation_note": "Its fit moved to nb-boostmtree_fit, and its importance, partial effects and trajectories to nb-boostmtree_explain, which reads the fit nb-boostmtree_fit saves; scaffold both with add_job()."
```

(As JSON: append the two keys to the object; keep the file's indentation.) Run `python3 dev/specs/artifacts/check-roadmap-counts.py`: expected `Catalog agrees with disk: 77 template rows routed to hvtiRtemplates, 52 on disk.`

- [ ] **Step 3: `migrate_job()`.** In `R/migrate-job.R` replace lines 182-188:

```r
  # A deprecated template's replacement may draw only part of its output:
  # nb-boostmtree split into a fit job and an explain job, and the catalog's
  # replacement is the fit. The job is written from that replacement, and the
  # warning carries the catalog's deprecation note, which names the rest.
  deprecated <- .template_deprecation(prefix, qualifier)
  if (!is.null(deprecated)) {
    .warn_deprecated(paste0("migrate_job(): ", deprecated$name, " is deprecated in favor of ",
                            deprecated$deprecated_by, ", so this job is written from ",
                            deprecated$deprecated_by, " instead. ", deprecated$note))
```

Roxygen line 14-15: `#' drew. Naming a deprecated template warns and writes the job from its` / `#' replacement; the warning carries the catalog's note, which names any other` / `#' template the old one's output moved to. Naming a template by its name before a rename, such as` (rewrap to the existing width). Then:

```sh
cd "$WT" && Rscript -e 'devtools::document()' && sed -i '' 's/^RoxygenNote: 8\.1\.1$/RoxygenNote: 8.1.0/' DESCRIPTION && git diff --stat DESCRIPTION man/
```

Expected: `man/migrate_job.Rd` changed, `DESCRIPTION` unchanged.

- [ ] **Step 4: Repoint and muffle.** `test-upgrade-job.R` lines 612-614: `template_path("nb", "boostmtree_fit")` and `grep("^An \`nb-boostmtree_fit\` job fits", new)`. Delete `tests/testthat/test-nb-boostmtree.R` (`git rm`). Run the whole suite and find every new deprecation warning:

```sh
cd "$WT" && Rscript -e 'devtools::test()' 2>&1 | grep -E "deprecated in favor|FAIL [0-9]+ \| WARN" 
```

Each `nb.boostmtree is deprecated` warning comes from a loop over every template through `template_path()` or `add_job()` (for example the `uses` test in `test-template-catalog.R` once #598 has merged). Wrap that call with `withCallingHandlers(..., hvtiRtemplates_deprecated = function(w) invokeRestart("muffleWarning"))`, as `test-templates.R` lines 731, 995 and 1054 already do. Expected after: `FAIL 0 | WARN 0`.

Mutation for the same-set test: in `_fit`'s `save` chunk and `fit` chunk's `CACHE_DIR` line, temporarily use the spec's name `nb-boostmtree-fit.rds` (and `nb_bundle_path()` likewise). Run `devtools::test(filter = "nb-boostmtree-fit")`: "rendering the deprecated job in the same set" must fail (the old job's cache_fit finds the bundle where its cache belongs). Revert.

- [ ] **Step 5: Commit.**

```sh
cd "$WT" && git add inst/extdata/templates.json R/migrate-job.R man/migrate_job.Rd tests/testthat/test-deprecation.R \
  tests/testthat/test-upgrade-job.R tests/testthat/test-nb-boostmtree-fit.R <each file muffled in Step 4> && \
git rm -q tests/testthat/test-nb-boostmtree.R && \
git commit -m "feat: deprecate nb-boostmtree in favor of nb-boostmtree_fit; migrate_job names the explain half

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: End-to-end renders of both jobs, with Quarto's stderr kept (#493)

**Files:**
- Modify: `tests/testthat/helper-nb.R` (add `nb_render()`, `nb_set_choice()`)
- Modify: `tests/testthat/test-nb-boostmtree-fit.R`, `tests/testthat/test-nb-boostmtree-explain.R` (one render test each)

**Interfaces:**
- Consumes: `render_job(job, quiet = FALSE)`; `hvtiRtemplates:::.extract_provenance()`.
- Produces: `nb_render(job)` returning the render's stdout and stderr lines, and on failure calling `testthat::fail()` with Quarto's stderr from the console streams and from every `$stderr` on the condition chain.

- [ ] **Step 1: Helper.** Append to `helper-nb.R`:

```r
# Rewrite the one line of `job` matching `from`.
nb_set_choice <- function(job, from, to) {
  txt <- readLines(job)
  hit <- grep(from, txt)
  stopifnot(length(hit) == 1L)
  txt[hit] <- to
  writeLines(txt, job)
}

# Render `job` and return what it printed. On failure, fail with Quarto's own
# stderr (#493): the quarto package once lost it while formatting its error with
# cli, so the console streams are captured here and the condition chain is read
# too. Each render gets its own TMPDIR, so renders run in parallel share no
# Quarto temporary files.
nb_render <- function(job) {
  withr::local_envvar(TMPDIR = withr::local_tempdir("nb-render-tmp-"))
  out <- withr::local_tempfile(fileext = ".out")
  err <- withr::local_tempfile(fileext = ".err")
  con_out <- file(out, "w")
  con_err <- file(err, "w")
  sink(con_out)
  sink(con_err, type = "message")
  result <- tryCatch({
    render_job(job, quiet = FALSE)
    NULL
  }, error = function(e) e, finally = {
    sink(type = "message")
    sink()
    close(con_out)
    close(con_err)
  })
  printed <- c(readLines(out, warn = FALSE), readLines(err, warn = FALSE))
  if (!is.null(result)) {
    chain <- character()
    e <- result
    while (!is.null(e)) {
      if (is.character(e$stderr)) chain <- c(chain, e$stderr)
      e <- e$parent
    }
    message <- tryCatch(conditionMessage(result), error = function(x) "<the error message could not be formatted>")
    testthat::fail(paste(c(paste("render_job() failed:", message), "--- stderr on the condition chain ---", chain,
                           "--- console, last 80 lines ---", utils::tail(printed, 80L)), collapse = "\n"))
  }
  printed
}
```

- [ ] **Step 2: Failing render tests.** Append to `test-nb-boostmtree-fit.R` (adapted from old lines 475-527):

```r
test_that("nb-boostmtree_fit scaffolds and renders end to end, and the page holds no MRN", {
  skip_on_cran()
  nb_skip_unless_stack()
  testthat::skip_if_not_installed("quarto")
  testthat::skip_if_not(quarto::quarto_available(), "Quarto CLI is required for rendering")
  data <- nb_data(id = "MRN")
  root <- nb_study(data)
  job <- add_job("nb", subject = "lvef", type = "boost", root = root, qualifier = "boostmtree_fit")
  nb_set_choice(job, "^RESPONSE <- ", "RESPONSE <- \"lvef\"")
  nb_set_choice(job, "^M  <- ", "M  <- 5")
  nb_set_choice(job, "^MTRY <- ", "MTRY <- 2L")
  nb_set_choice(job, "^CORES <- ", paste0("CORES <- ", nb_cores, "L"))
  log <- nb_render(job)
  html <- sub("[.]qmd$", ".html", job)
  expect_true(file.exists(html))
  expect_true(file.exists(nb_bundle_path(root)))
  bytes <- nb_file_bytes(html)
  expect_false(any(vapply(unique(data$MRN), function(v) nb_bytes_hold(bytes, v), logical(1L))))
  page <- rawToChar(bytes)
  banner <- "callout-title-container[^>]*>\\s*(<span[^>]*>[^<]*</span>)?\\s*DRAFT (--|–|&ndash;) this job is unfinished\\s*<"
  expect_match(page, banner, useBytes = TRUE)
  payload <- hvtiRtemplates:::.extract_provenance(page)
  expect_identical(payload$analysis$response, "lvef")
  expect_equal(payload$analysis$mtry, 2)
  expect_equal(payload$analysis$k_shadow, 5)
  expect_equal(payload$analysis$n_refits, 0)
  expect_identical(payload$versions$boostmtree, format(utils::packageVersion("boostmtree")))
  expect_identical(payload$cohort$n_patients, length(unique(data$MRN)))
  prog <- yaml::read_yaml(sub("[.]qmd$", ".run.progress", job))
  expect_true("fit" %in% vapply(prog$done, `[[`, "", "stage"))
  expect_true(any(grepl("iteration 5/5", log, fixed = TRUE)))
  expect_false(grepl("iteration [0-9]+/[0-9]+", page))
})
```

and to `test-nb-boostmtree-explain.R`:

```r
test_that("nb-boostmtree_explain renders end to end after the fit job, and the page holds no MRN", {
  skip_on_cran()
  nb_skip_unless_stack()
  testthat::skip_if_not_installed("quarto")
  testthat::skip_if_not(quarto::quarto_available(), "Quarto CLI is required for rendering")
  data <- nb_data(id = "MRN")
  root <- nb_study(data)
  fit_job <- add_job("nb", subject = "lvef", type = "boost", root = root, qualifier = "boostmtree_fit")
  nb_set_choice(fit_job, "^RESPONSE <- ", "RESPONSE <- \"lvef\"")
  nb_set_choice(fit_job, "^M  <- ", "M  <- 5")
  nb_set_choice(fit_job, "^CORES <- ", paste0("CORES <- ", nb_cores, "L"))
  nb_render(fit_job)
  job <- add_job("nb", subject = "lvef", type = "boost", root = root, qualifier = "boostmtree_explain")
  nb_set_choice(job, "^N_VIMP <- ", "N_VIMP <- 2")
  nb_set_choice(job, "^N_TRACES <- ", "N_TRACES <- 10")
  nb_set_choice(job, "^CORES <- ", paste0("CORES <- ", nb_cores, "L"))
  log <- nb_render(job)
  html <- sub("[.]qmd$", ".html", job)
  expect_true(file.exists(html))
  bytes <- nb_file_bytes(html)
  expect_false(any(vapply(unique(data$MRN), function(v) nb_bytes_hold(bytes, v), logical(1L))))
  page <- rawToChar(bytes)
  expect_match(page, "Importance pools 2 runs on 1 fit, 2 in all.", fixed = TRUE)
  payload <- hvtiRtemplates:::.extract_provenance(page)
  expect_identical(payload$analysis$response, "lvef")
  expect_equal(payload$analysis$n_vimp, 2)
  expect_true(any(grepl("nb-boostmtree_fit.rds", unlist(payload$artifacts), fixed = TRUE)))
  expect_gt(length(payload$data), 0L)
  expect_true(any(grepl("prediction [0-9]+/[0-9]+", log)))
  expect_true(all(file.exists(file.path(nb_set_dir(root), sprintf("nb-boostmtree_explain-vimp-fit0-run%d.rds", 1:2)))))
})
```

- [ ] **Step 3: Install the branch and run.**

```sh
cd "$WT" && R CMD INSTALL --no-test-load -l "$LIB" . >/dev/null && Rscript -e 'devtools::test(filter = "nb-boostmtree")' 2>&1 | tail -8
```

Expected: `FAIL 0 | WARN 0 | SKIP 0`. If a render fails, the failure message now carries Quarto's stderr; fix the template, re-install, rerun.

- [ ] **Step 4: Prove the capture.** Temporarily make the explain test's job unrenderable (`nb_set_choice(job, "^N_VIMP <- ", "N_VIMP <- stop('boom 493')")`) and run its file: the failure must read `render_job() failed:` and contain `boom 493` from the console section. Revert.

- [ ] **Step 5: Commit.**

```sh
cd "$WT" && git add tests/testthat/helper-nb.R tests/testthat/test-nb-boostmtree-fit.R tests/testthat/test-nb-boostmtree-explain.R && \
git commit -m "test: end-to-end renders of both nb jobs keep Quarto's stderr on failure (#493)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Gallery, README and AGENTS, roadmap tables, news, full gates

**Files:**
- Modify: `dev/gallery/family-nb.R` (lines 1-5 comment, 56-72 jobs)
- Modify: `inst/templates/README.md` (line 50 table, 110 qualifier paragraph, 419 figure-name table, 606-607 guard paragraph)
- Modify: `AGENTS.md` (`boostmtree-pin.yaml` row: "the tag in `nb-boostmtree`'s install line" becomes "the tag in each `nb-boostmtree*` template's install line")
- Modify: `dev/specs/2026-08-29-template-conversion-roadmap.md` (generated section, by script)
- Create: `news/feat-nb-boostmtree-split.md`

**Interfaces:**
- Consumes: `gallery_family()`, `gallery_missing()` in `dev/gallery/gallery.R`; `dev/specs/artifacts/roadmap_render.py`.
- Produces: gallery jobs `nb-boostmtree`, `nb-boostmtree_fit`, `nb-boostmtree_explain`, all set `lvef`/`boost`, rendered in that order.

- [ ] **Step 1: Gallery.** Line 1 comment: `# Boosted multivariate trees family: nb-boostmtree_fit and nb-boostmtree_explain, for a response measured`, and add after line 5: `# nb-boostmtree stays beside them while it is deprecated: its row still ships and gallery_missing() wants a job for every shipped row. It goes when its file does.` In the `jobs` list, keep the `"nb-boostmtree"` entry and append:

```r
    "nb-boostmtree_fit" = list(subject = "lvef", type = "boost", prepare = nb_register_echo, choices = list(
      "^<!-- EDIT: name the job this replaces" = paste0(
        "Gallery job on the synthetic echo series: LV ejection fraction over follow-up (iv_echo), six baseline predictors,",
        " with five shadow copies of each.\n\n<!--"
      ),
      "^DATASET <- \"built\"$" = "DATASET <- \"echo\"",
      "^ID <- \"ccfid\"$" = "ID <- \"patient_id\"",
      "^RESPONSE <- " = "RESPONSE <- \"lvef\"",
      # The template's M is 500; 200 keeps the gallery fast, and the error
      # path and plateau say whether it was enough.
      "^M  <- 500$" = "M  <- 200"
    )),
    # Rendered after the fit, whose nb-boostmtree_fit.rds it reads in the same set.
    "nb-boostmtree_explain" = list(subject = "lvef", type = "boost", choices = list(
      "^<!-- EDIT: say which nb-boostmtree_fit job" = paste0(
        "Gallery job: explains the nb-boostmtree_fit gallery job's fit of LV ejection fraction.\n\n<!--"
      )
    ))
```

Check `gallery_missing()` sees all three: `cd "$WT" && Rscript -e 'source("dev/gallery/gallery.R"); print(gallery_missing())'` (expected `character(0)`). Do not build the gallery here: AGENTS.md has it rebuilt on release day.

- [ ] **Step 2: README.** Line 50 becomes three rows:

```markdown
| `30_analyses/nb-boostmtree_fit.qmd` | boosted multivariate trees for a response measured at each visit: the fit, with shadow covariates and optional refits, its error path and plateau, saved for the explain job | `30_analyses/` or `analyses/` |
| `30_analyses/nb-boostmtree_explain.qmd` | importance pooled over repeated runs against shadow covariates, partial effects and trajectories for an `nb-boostmtree_fit` fit; never fits | `30_analyses/` or `analyses/` |
| `30_analyses/nb-boostmtree.qmd` | deprecated in favor of `nb-boostmtree_fit` and `nb-boostmtree_explain`; removed in the release after | `30_analyses/` or `analyses/` |
```

Line 110: after "`nb-boostmtree` is qualified from the start, because `nb` will also hold a BoostMLR job, `nb-boostmlr`, which is still to come." add: "The stage goes after the package, `nb-boostmtree_fit` and `nb-boostmtree_explain`, because the qualifier already names the package; `-` cannot appear in a qualifier, so the stage is joined by `_`." Line 419 becomes:

```markdown
| nb-boostmtree_fit | `nb-boostmtree_fit-error`, `-path`, `-calibration` |
| nb-boostmtree_explain | `nb-boostmtree_explain-importance`, `-effects-<kind>-page-<NN>`, `-traces` |
| nb-boostmtree (deprecated) | `nb-boostmtree-error`, `-path`, `-calibration`, `-importance`, `-effects-<kind>-page-<NN>`, `-traces` |
```

Line 607: "`nb-boostmtree`" becomes "`nb-boostmtree_fit` (and the deprecated `nb-boostmtree`)".

- [ ] **Step 3: Roadmap tables and counts.**

```sh
cd "$WT" && python3 dev/specs/artifacts/roadmap_render.py && python3 dev/specs/artifacts/check-roadmap-counts.py && \
python3 dev/specs/artifacts/check-spec-counts.py && python3 dev/specs/artifacts/check-flow-counts.py && \
grep -n "templates in scope" dev/specs/2026-08-29-template-conversion-roadmap.md
```

Expected: `**77 templates in scope**, of which 52 exist on disk.`; the machine-learning table gains `nb-boostmtree_explain` and `nb-boostmtree_fit` rows. If `check-spec-counts.py` or `check-flow-counts.py` fails, the failing prose quotes a count from the map; update that number to the one the script names. Then search the prose docs for stale counts: `grep -rn "50 exist on disk\|75 templates\|50 templates" inst/templates/README.md AGENTS.md README.md vignettes/ dev/specs/*.md | grep -v "^dev/specs/2026-0[89]\|^dev/specs/2026-10"`; update current-state claims only, never dated history.

- [ ] **Step 4: News fragment.** Create `news/feat-nb-boostmtree-split.md`:

```markdown
* `nb-boostmtree` is split into two jobs, as `rfs-fit` and `rfs-explain` are. `nb-boostmtree_fit` fits with five
  shadow copies of every predictor (`K_SHADOW`), optionally refits under other seeds (`N_REFITS`), reports the
  plateau of iterations within 1% of the lowest cross-validated error beside Best M, records the boostmtree,
  randomForestSRC and ggBoostedTrees versions, and saves `nb-boostmtree_fit.rds`. `nb-boostmtree_explain` reads
  it, never fits, runs importance `N_VIMP` times on each fit and pools the runs with ggBoostedTrees 0.10.2, reporting
  how often each predictor cleared its run's noise band; it warns when boostmtree or randomForestSRC differ from the
  fit's. Both need boostmtree 2.0.13 and ggBoostedTrees 0.10.2. `nb-boostmtree` is deprecated and goes in the
  release after; `migrate_job()` writes `nb-boostmtree_fit` and its warning names `nb-boostmtree_explain`, and
  `upgrade_job()` keeps an existing job on its own template (#580).
* The nb end-to-end render tests print Quarto's own error output when a render fails (#493).
```

- [ ] **Step 5: Full gates.**

```sh
cd "$WT" && R CMD INSTALL --no-test-load -l "$LIB" . >/dev/null && \
Rscript -e 'devtools::test()' 2>&1 | grep -E "FAIL [0-9]+ \| WARN [0-9]+ \| SKIP [0-9]+ \| PASS" && \
Rscript -e 'l <- lintr::lint_package(); print(length(l)); quit(status = length(l) > 0)' && \
Rscript -e 'devtools::document()' && sed -i '' 's/^RoxygenNote: 8\.1\.1$/RoxygenNote: 8.1.0/' DESCRIPTION && git status --short man NAMESPACE DESCRIPTION && \
Rscript -e 'r <- devtools::check(document = FALSE, args = "--as-cran", error_on = "never"); print(r); quit(status = length(c(r$errors, r$warnings, r$notes)) > 0)' && \
python3 dev/check-boostmtree-pin.py && bash tools/check-us-spelling.sh
```

Expected: `FAIL 0 | WARN 0 | SKIP 0`; `0` lints; no `man/`/`NAMESPACE`/`DESCRIPTION` change; check `0 errors | 0 warnings | 0 notes`; pin check `agree`; spelling clean. (`devtools::check()` here includes the manual; the Rd change is one `migrate_job` sentence with no math, so the post-merge `check-manual.yaml` risk is nil, but the local check builds it anyway.) If `tools/check-us-spelling.sh` does not exist in the worktree, skip it and say so in the PR body.

- [ ] **Step 6: Commit.**

```sh
cd "$WT" && git add dev/gallery/family-nb.R inst/templates/README.md AGENTS.md dev/specs/2026-08-29-template-conversion-roadmap.md \
  news/feat-nb-boostmtree-split.md <any prose file Step 3 updated> && \
git commit -m "docs: nb-boostmtree split in the gallery, the templates README, the roadmap and news

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: The #580 run-time table, the study-number sentence and the memory-guard decision

**Blocked until the retime finishes.** Start only when this prints `BOOSTMTREE_RETIME_COMPLETE label=Large ...`:

```sh
tail -1 /Volumes/qhsstudies/general/_development/boostmtree-retime-20261120/out/run-Large.log
```

Read only: copy the outputs off the share, compute on the Mac. Never run R, `find` or any program against `/Volumes`.

**Files:**
- Modify: `inst/templates/30_analyses/nb-boostmtree_fit.qmd` (study choices: the M comment's study sentence, copied from `O` 203-208; the CORES run-time table, copied from `O` 247-250; the `fit-checks` comment's back-reference, copied from `O` 485-488)
- Modify, only if Step 3 says so: `R/fit-memory.R` (`.boostmtree_need_gib()` lines 71-81 and the calibration comment lines 55-69), `tests/testthat/test-fit-memory.R`, `inst/templates/README.md` line 606-611
- Modify: `news/feat-nb-boostmtree-split.md`

**Interfaces:**
- Consumes: `out/scaling-Large.csv` columns `n_patients, n_visits, n_predictors, k_shadow, M, cores, seed, elapsed_s, user_s, sys_s, parent_heap_max_mb, m_opt, fit_mb, mu_md5, boostmtree, randomForestSRC, ggBoostedTrees, r_version, blas, threads_env`; `out/memory-Large.csv` columns `n_patients, cores, M, k_shadow, peak_rss_mb, samples`; `out/run-Large.log` (`FAILED:` lines); `out/environment-Large.csv`.
- Produces: the numbers below; possibly `.boostmtree_need_gib(patients, visits, family, cores, m, k_shadow = 0)`.

- [ ] **Step 1: Copy and compute.**

```sh
R=/Volumes/qhsstudies/general/_development/boostmtree-retime-20261120/out; T=$(mktemp -d) && \
cp "$R/scaling-Large.csv" "$R/memory-Large.csv" "$R/run-Large.log" "$R/environment-Large.csv" "$T/" && grep FAILED "$T/run-Large.log"; \
Rscript -e '
t <- commandArgs(TRUE)[1]
s <- read.csv(file.path(t, "scaling-Large.csv")); m <- read.csv(file.path(t, "memory-Large.csv"))
cells <- data.frame(n = c(1000, 1000, 2000, 4000), cores = c(4, 8, 8, 4))
one <- function(d, n, c, M, k, col) { v <- d[d$n_patients == n & d$cores == c & d$M == M & d$k_shadow == k, col]; if (length(v)) v[[1]] else NA }
cells$hours_m500 <- mapply(function(n, c) one(s, n, c, 10, 5, "elapsed_s") * 50 / 3600, cells$n, cells$cores)
cells$gib_k5 <- mapply(function(n, c) one(m, n, c, 10, 5, "peak_rss_mb") / 1024, cells$n, cells$cores)
cells$gib_k0 <- mapply(function(n, c) one(m, n, c, 10, 0, "peak_rss_mb") / 1024, cells$n, cells$cores)
cells$mem_ratio <- cells$gib_k5 / cells$gib_k0
cells$time_ratio <- mapply(function(n, c) one(s, n, c, 10, 5, "elapsed_s") / one(s, n, c, 10, 0, "elapsed_s"), cells$n, cells$cores)
print(cells, digits = 3)
cat("M=20/M=10 time ratio at 1000 on 4, k=5:", one(s, 1000, 4, 20, 5, "elapsed_s") / one(s, 1000, 4, 10, 5, "elapsed_s"), "\n")
cat("versions:", unique(s$boostmtree), unique(s$randomForestSRC), unique(s$ggBoostedTrees), "\n")
same <- tapply(s$mu_md5, paste(s$n_patients, s$M, s$k_shadow), function(x) length(unique(x)) == 1L)
cat("fit identical across cores within each (n, M, k):", all(same), "\n"); print(same[!same])
' "$T"
```

Record: per cell `hours_m500` (round to 0.5 h below 10 h, to 1 h above), `gib_k5` (round to 1 GiB), `mem_ratio`, `time_ratio`; the M ratio; the versions; whether every `mu_md5` group agrees. A cell that is `NA` is a fit that did not finish: read its `FAILED:` line.

- [ ] **Step 2: Decide what the numbers say before editing.**
  - **M ratio** outside 1.8 to 2.2: time is not proportional to M, so "times 50" is not honest. Stop and report to John with the numbers; do not write the table.
  - **`mu_md5` disagrees within a group**: the fit is not identical across core counts, which falsifies the template's "Not part of the cache key: the fit is identical on any number of cores" (`O` 252). Stop and report; that is a separate decision.
  - Otherwise continue.

- [ ] **Step 3: Memory-guard decision (spec section 5).** Let `r_max` be the largest `mem_ratio` over the cells that finished.
  - **`r_max <= 1.10`**: no code change. Add to the calibration comment in `R/fit-memory.R` (after line 67): `#  - Shadows: 5 shadow copies (4 predictors to 24) raised peak memory by at most <round(100 * (r_max - 1))>% in the 2026-11-20 retime (boostmtree <version>, Large session, simulated data), so the estimate has no predictor term. Unmeasured with many more real predictors.`
  - **`r_max > 1.10`**: add the term. Write the failing test first in `tests/testthat/test-fit-memory.R`:

    ```r
    test_that("shadow copies raise the boostmtree estimate by the measured factor, and 0 changes nothing", {
      base <- hvtiRtemplates:::.boostmtree_need_gib(1000, 9000, "continuous", 4, 500)
      expect_identical(hvtiRtemplates:::.boostmtree_need_gib(1000, 9000, "continuous", 4, 500, k_shadow = 0), base)
      with5 <- hvtiRtemplates:::.boostmtree_need_gib(1000, 9000, "continuous", 4, 500, k_shadow = 5)
      expect_equal(with5 - 1, (base - 1) * (1 + 5 * <b>))
    })
    ```

    with `<b>` the number computed next. Run `devtools::test(filter = "fit-memory")`: fails (unused argument). Then change `R/fit-memory.R` line 71 to `.boostmtree_need_gib <- function(patients, visits, family, cores, m, k_shadow = 0) {`, add `k_shadow` to the validation list at line 72, and line 80 to `1 + cores * a * (patients / 1000)^1.7 * (1 + b_shadow * k_shadow) + growth` with `b_shadow <- <b>` defined above it, where `<b> = ceiling(100 * (r_max - 1) / 5) / 100` (conservative: the largest cell, rounded up). Add the calibration line: `#  - b_shadow = <b>: 5 shadow copies (4 predictors to 24) raised peak memory by up to <round(100 * (r_max - 1))>% in the 2026-11-20 retime (boostmtree <version>, Large session); per copy, the largest cell's rise / 5, rounded up. Measured with 4 real predictors only.` In `_fit`'s `fit` chunk pass `k_shadow = K_SHADOW` in `.need`, and in `sensitivity`'s `.need_grid` likewise. README line 606-611 gains one sentence: "The `nb-boostmtree_fit` estimate grows with `K_SHADOW`, measured on 2026-11-20." Run the test: passes.

- [ ] **Step 4: Rewrite the CORES run-time table.** In `nb-boostmtree_fit.qmd`, replace the three table lines copied from `O` 247-250 (from `# Run time at M = 1000` through `# 8 cores) the fit took about 1 h. Hours scale with M.`) with, values from Step 1:

```r
# Run time at M = 500, NU = 0.05, K_SHADOW = 5, continuous, with the peak memory of the fit and its workers
# together, by patients and cores (2026-11-20 retime, boostmtree <boostmtree>, randomForestSRC <randomForestSRC>,
# simulated data with 4 predictors and their 20 shadows): about <h1> h and <g1> GiB at 1,000 patients on 4 cores,
# <h2> h and <g2> GiB at 1,000 on 8, <h3> h and <g3> GiB at 2,000 on 8, and <h4> h and <g4> GiB at 4,000 on 4.
# Timed at M = 10 and multiplied by 50; hours scale with M (M = 20 took <ratio> times as long).
```

A cell that did not finish reads `did not finish in a Large session` in place of its numbers. Each `<...>` is the Step 1 value; nothing else is estimated.

- [ ] **Step 5: The study-number sentence (#580, spec section 5).** No dated, versioned source for "One study of 1,391 patients (4,771 visits) at NU = 0.05 fitted M = 1000 and chose Best M = 751; its cross-validated error at 500 was 0.3% above that best and at 250 1.1%, so 500 was enough at half the time." can be read from this side: the fit's saved output is on lri and this plan runs nothing there. Unless John has supplied, in the conversation or the PR, the output's date and boostmtree version, remove that sentence from the M comment (the lines copied from `O` 204-207), leaving:

```r
# EDIT: the learning rate and the most boosting iterations. NU is the main
# lever: fix it, and let cross-validation choose how many of the M iterations to
# use (Best M, reported below). 0.05 is the reference; 0.01 suits small or
# noisy data, and needs about five times the M. M is a ceiling: the fit stops
# using iterations at Best M, but every one up to M is paid for. boostmtree's own
# default of 200 is too low for clinical longitudinal data. The report says when
# the error was still falling at M by enough to matter.
```

If John supplied it, keep the sentence and append ` (saved <date>, boostmtree <version>)` after `chose Best M = 751`. In `fit-checks` (copied from `O` 485-488), "in the study the M comment above describes, M = 500 put Best M at 498" becomes "in one study fit at NU = 0.05, M = 500 put Best M at 498" when the sentence was removed.

- [ ] **Step 6: Run and commit.**

```sh
cd "$WT" && Rscript -e 'devtools::test(filter = "nb-boostmtree|fit-memory")' 2>&1 | tail -4 && \
Rscript -e 'l <- lintr::lint_package(); quit(status = length(l) > 0)' && \
git add inst/templates/30_analyses/nb-boostmtree_fit.qmd news/feat-nb-boostmtree-split.md <R/fit-memory.R tests/testthat/test-fit-memory.R inst/templates/README.md if changed> && \
git commit -m "docs: nb-boostmtree_fit times M = 500 with shadows on boostmtree <version> (#580)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Add to the news fragment's first bullet: "Its run-time comment now times `M = 500` with five shadows on boostmtree <version>." and, if Step 3 added the term, "and the memory guard counts `K_SHADOW`".

The plateau width at `nu = 0.05` is **not measured** by this retime (its fits run `M = 10`); say so in the PR body under "Not measured", beside the two the spec lists (predictions at `m.opt` 156 against 400; vimp and refit cost at clinical size).

---

### Task 8: Local review, push, PR

**Files:** none.

- [ ] **Step 1: Review.** Run `/code-review` on the branch diff against its base (Copilot review credits are exhausted; AGENTS.md). Fix what it finds with its own test cycle and commit each fix by explicit path.
- [ ] **Step 2: Gates once more** (Task 6 Step 5 commands). Then confirm the head commit is the one reviewed: `git log --oneline -1`.
- [ ] **Step 3: Push and open the PR against `main`.**

```sh
cd "$WT" && git push -u origin feat/nb-boostmtree-split && gh pr create --base main --title "feat: split nb-boostmtree into nb-boostmtree_fit and nb-boostmtree_explain" --body-file <body.md>
```

The body says: what ships (two templates, deprecation, `migrate_job()`); **the handoff name `nb-boostmtree_fit.rds` departs from the spec's `nb-boostmtree-fit.rds`, why (refinement 1), and that John confirms it**; refinements 2 and 3; the time-varying-predictor refusal; the Task 7 numbers and the memory decision with `r_max`; "Not measured" (plateau width at `nu = 0.05`, predictions at the plateau's two ends, vimp and refit cost at clinical size); that `/code-review` stood in for Copilot; `Closes #580`, `Closes #493`; and ends with

```
🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

- [ ] **Step 4: Read the per-platform summaries** of the PR's `R-CMD-check` run, not the check mark: `gh run view <run-id> --log | grep -E "SKIP [0-9]+ \| PASS"` must read `SKIP 0` on ubuntu. Dispatch the weekly sweep (`gh workflow run R-CMD-check.yaml --ref feat/nb-boostmtree-split`) for Windows: the new tests fork through `mclapply` only when `CORES > 1`, and `nb_cores` is 1 there, so no new `skip_on_os("windows")` is expected; if one becomes needed, update the count in AGENTS.md.

---

## Spec coverage

| spec | task |
|---|---|
| 4 architecture, handoff, bundle, outer lineage, floors | 2 (save, setup), 3 (fit chunk), refinement 1 |
| 5 `_fit`: K_SHADOW, N_REFITS, plateau, refit spread and mean curve, versions | 2 |
| 5 #580 study numbers and run-time table, memory term | 7 |
| 6 `_explain`: read_handoff, version warning, N_VIMP, pooling, names, K_SHADOW = 0, effects ranking, traces | 3 |
| 7 deprecation, `migrate_job()` comment and warning, add_job / upgrade_job warnings | 4 |
| 8 ledger rows, `.lintr` keys, maps and counts, news | 2, 3, 6 |
| 8 tests: handoff, lineage, working-data regression, paths, K_SHADOW key and zero path, pooling with mutation, deprecation | 2, 3, 4 |
| 8 #493 stderr capture in end-to-end renders | 5 |
| 8 gallery | 6 |
| 9 not measured (plus plateau width) | 7, 8 |
