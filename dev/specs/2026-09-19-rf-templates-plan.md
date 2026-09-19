# Random forest templates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship six job templates, `rfs`, `rfc` and `rfr`, each as a `fit` and an `explain`, with their catalog rows, dependencies, lint keys, tests and docs.

**Architecture:** A fit job grows the forest through `hvtiRutilities::cache_fit()` into the set's estimates folder, then saves the bare forest as `<prefix>.rds`, the handoff. An explain job reads `<prefix>.rds`, rebuilds the training frame and model from the forest itself, and caches VIMP, VarPro and both partial-dependence steps as separate `cache_fit()` entries. Tests run each template's chunks by label in a throwaway study, the way the `hz` theta test does, not through Quarto.

**Tech Stack:** R, Quarto `.qmd` templates, randomForestSRC 3.7.0, varPro 3.2.0, ggRandomForests 4.0.0, hvtiRutilities 1.3.0 (`cache_fit`, `read_built`, `study_root`, `study_dir`, `study_setup`), testthat edition 3, Python 3 for the catalog guards.

**Spec:** `dev/specs/2026-09-19-rf-templates-design.md`. Read its sections 4 and 5 before Task 2.

## Global Constraints

- Branch `spec/rf-templates`, opened as one PR against `main`. Never push to `main`.
- No `Version:` change. `NEWS.md` entries go under `# hvtiRtemplates (unreleased)`.
- Suggests floors, verbatim: `randomForestSRC (>= 3.7.0)`, `varPro (>= 3.2.0)`, `ggRandomForests (>= 4.0.0)`. Each template enforces the same floors with `utils::packageVersion("<pkg>") < "<x.y.z>"`.
- Remotes gains `ehrlinger/randomForestSRC` and `ehrlinger/varPro`.
- Templates carry no study identifiers: no `/studies/` path, no study name, no built-dataset filename.
- Every study-specific line is marked `EDIT:`. `REFIT` is not study-specific and carries no marker.
- `ENDPOINT` and `TYPE` sit in the `set` chunk, one `^ENDPOINT\s+<- ` line and one `^TYPE\s+<- ` line per file, never marked `EDIT:`.
- Each template carries its own `format:` block and its own FILE key in `.lintr`.
- Lines at most 135 characters. Roxygen, if any is touched, is Rd markup, not markdown.
- Prose in templates, README and NEWS follows the house voice, with no em-dashes. R comments use `--` as the existing templates do.
- Definition of done: `devtools::test()` passes, `devtools::check()` is 0/0/0, `lintr::lint_package()` is clean, and the three `dev/specs/artifacts/check-*.py` guards pass.

## File structure

| file | responsibility |
|---|---|
| `inst/extdata/templates.json` | six qualified rows replace three unqualified ones |
| `DESCRIPTION` | Suggests floors and Remotes |
| `inst/templates/30_analyses/rfs-fit.qmd` | grow and check a survival forest, save `rfs.rds` |
| `inst/templates/30_analyses/rfs-explain.qmd` | VIMP, VarPro and dependence for `rfs.rds` |
| `inst/templates/30_analyses/rfc-fit.qmd` | the same for classification, `rfc.rds` |
| `inst/templates/30_analyses/rfc-explain.qmd` | explain `rfc.rds` |
| `inst/templates/30_analyses/rfr-fit.qmd` | the same for regression, `rfr.rds` |
| `inst/templates/30_analyses/rfr-explain.qmd` | explain `rfr.rds` |
| `tests/testthat/helper-rf.R` | run a template's chunks by label in a temp study |
| `tests/testthat/test-rf-templates.R` | smoke, handoff, no-refit and stale-cache tests |
| `tests/testthat/test-templates.R` | declared-helper list and Suggests-bound list gain entries |
| `tests/testthat/test-template-catalog.R` | row count 55 to 58 |
| `.lintr` | six file keys |
| `inst/templates/README.md` | six table rows and the migration mapping |
| `NEWS.md` | one unreleased entry |
| `dev/specs/2026-09-17-ml-family-roadmap-design.md` | re-rendered generated tables, by script only |

---

### Task 1: Catalog rows and dependencies

**Files:**
- Modify: `inst/extdata/templates.json` (the `rfs`, `rfc`, `rfr` rows)
- Modify: `DESCRIPTION` (Remotes, Suggests)
- Modify: `tests/testthat/test-template-catalog.R:5`
- Regenerate: the roadmap document's GENERATED block, via `dev/specs/artifacts/roadmap_render.py`

**Interfaces:**
- Produces: six catalog rows keyed `(rfs, fit)`, `(rfs, explain)`, `(rfc, fit)`, `(rfc, explain)`, `(rfr, fit)`, `(rfr, explain)`, all `status: "queued"`. Tasks 2 to 5 flip each to `"shipped"` when its file lands.

- [ ] **Step 1: Write the failing test**

In `tests/testthat/test-template-catalog.R`, change line 5 from `expect_equal(nrow(catalog), 55L)` to `expect_equal(nrow(catalog), 58L)`, and add after line 11:

```r
  rf <- catalog[catalog$prefix %in% c("rfs", "rfc", "rfr"), ]
  expect_setequal(paste(rf$prefix, rf$qualifier),
                  paste(rep(c("rfs", "rfc", "rfr"), each = 2L), c("fit", "explain")))
  # Explain rows carry no census counts: the counts describe the prefix, and
  # repeating them on both halves would double its breadth in the ledger.
  expect_true(all(is.na(rf$r_exemplars[rf$qualifier == "explain"])))
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript -e 'devtools::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-template-catalog.R")'`
Expected: FAIL, `nrow(catalog)` is 55, not 58.

- [ ] **Step 3: Rewrite the three rows as six**

Run this script from the repo root. It keeps each prefix's census counts on its fit row, nulls them on the explain row, and preserves every other field's position.

```bash
python3 - <<'EOF'
import json
p = "inst/extdata/templates.json"
d = json.load(open(p))
fit_uses = {
    "rfs": ["randomForestSRC::rfsrc", "hvtiRutilities::cache_fit", "ggRandomForests::gg_error",
            "ggRandomForests::gg_rfsrc", "ggRandomForests::gg_brier"],
    "rfc": ["randomForestSRC::rfsrc", "hvtiRutilities::cache_fit", "ggRandomForests::gg_error",
            "ggRandomForests::gg_roc", "ggRandomForests::calc_auc"],
    "rfr": ["randomForestSRC::rfsrc", "hvtiRutilities::cache_fit", "ggRandomForests::gg_error",
            "ggRandomForests::gg_rfsrc"],
}
explain_uses = ["randomForestSRC::vimp", "randomForestSRC::max.subtree", "varPro::varpro",
                "hvtiRutilities::cache_fit", "ggRandomForests::gg_vimp", "ggRandomForests::gg_varpro",
                "ggRandomForests::gg_variable", "ggRandomForests::gg_partial_rfsrc",
                "ggRandomForests::gg_partial_varpro"]
outcome = {"rfs": "survival", "rfc": "classification", "rfr": "regression"}
spec = "dev/specs/2026-09-19-rf-templates-design.md"
out = []
for r in d["templates"]:
    if r["prefix"] not in fit_uses:
        out.append(r)
        continue
    pfx = r["prefix"]
    base_name = r["name"]
    fit = dict(r)
    fit.update(qualifier="fit", name=f"{base_name}: fit", spec=spec, uses=fit_uses[pfx],
               note=(f"Grows the {outcome[pfx]} forest and saves {pfx}.rds for {pfx}-explain in the same set. "
                     "Old rfsrc.* and rf.* jobs map here by the outcome in their fit call."))
    exp = dict(r)
    exp.update(qualifier="explain", name=f"{base_name}: explain", spec=spec, uses=explain_uses,
               sas_breadth=None, sas_breadth_jobs=None, r_exemplars=None, r_jobs=None,
               note=f"Reads {pfx}.rds from {pfx}-fit in the same set and never refits. Census counts are on the fit row.")
    out += [fit, exp]
d["templates"] = out
with open(p, "w") as fh:
    json.dump(d, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
EOF
```

Then, only for the `rfr` fit row, set the counts the 2026-09-19 content census measured, replacing whatever the old `rfr` row carried: `"r_exemplars": 6`, and append to its `note`: `" Gate measured 2026-09-19 by reading fit calls: six studies grow a regression forest."` Edit the JSON by hand for this; it is one row.

- [ ] **Step 4: Check the file did not reformat unrelated rows**

Run: `git diff --stat inst/extdata/templates.json`
Expected: only the rf rows change. If the diff touches every line, the original indent differed from 2: re-run step 3 with the indent `git show HEAD:inst/extdata/templates.json | head -3` shows.

- [ ] **Step 5: Add the dependencies**

In `DESCRIPTION`, add to `Remotes:` (keep the existing order, append):

```
    ehrlinger/randomForestSRC,
    ehrlinger/varPro
```

(add a comma to the line above). In `Suggests:`, change `ggRandomForests,` to `ggRandomForests (>= 4.0.0),` and add, in alphabetical position:

```
    randomForestSRC (>= 3.7.0),
    varPro (>= 3.2.0),
```

- [ ] **Step 6: Regenerate the roadmap tables and run the guards**

```bash
python3 dev/specs/artifacts/roadmap_render.py && python3 dev/specs/artifacts/check-roadmap-counts.py && python3 dev/specs/artifacts/check-spec-counts.py && python3 dev/specs/artifacts/check-flow-counts.py
```

Expected: `Catalog agrees with disk: ... template rows routed to hvtiRtemplates, 14 on disk.` and the other two exit 0.

- [ ] **Step 7: Run the catalog tests**

Run: `Rscript -e 'devtools::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-template-catalog.R"); testthat::test_file("tests/testthat/test-template-catalog-rules.R"); testthat::test_file("tests/testthat/test-roadmap.R")'`
Expected: all PASS. `test-template-catalog-rules.R` checks that every `uses` entry is an export of a package in `DESCRIPTION`, which is why step 5 comes before this.

- [ ] **Step 8: Commit**

```bash
git add inst/extdata/templates.json DESCRIPTION tests/testthat/test-template-catalog.R dev/specs/2026-09-17-ml-family-roadmap-design.md
git commit -m "catalog: split rfs/rfc/rfr into fit and explain rows

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Test helper and `rfs-fit`

**Files:**
- Create: `tests/testthat/helper-rf.R`
- Create: `tests/testthat/test-rf-templates.R`
- Create: `inst/templates/30_analyses/rfs-fit.qmd`
- Modify: `tests/testthat/test-templates.R` (declared helpers list near line 250; Suggests-bound package list near line 468)
- Modify: `.lintr` (one file key)
- Modify: `inst/extdata/templates.json` (`rfs`/`fit` status to `"shipped"`)

**Interfaces:**
- Consumes: the `(rfs, fit)` catalog row from Task 1.
- Produces: `rf_chunk(src, label)`, `rf_study(.local_envir)`, `rf_run(prefix, qualifier, labels, env, choices)` in `helper-rf.R`; the file `<study>/90_estimates/<ENDPOINT>-<TYPE>/rfs.rds` holding an `rfsrc` survival forest; chunk labels `setup`, `edit-guard`, `set`, `study-choices`, `read`, `fit`, `diagnostics`, `save`.

- [ ] **Step 1: Write the helper**

Create `tests/testthat/helper-rf.R`:

```r
# The rf templates are run here chunk by chunk, not through Quarto: a render
# needs a study with built data, and CI has neither. Each chunk is parsed out
# of the INSTALLED template by its label and evaluated in one environment, the
# way the hz theta test does, so what runs is the text that ships.

rf_chunk <- function(src, label) {
  at <- grep(paste0("#| label: ", label), src, fixed = TRUE)
  if (length(at) != 1L) stop("chunk '", label, "' found ", length(at), " times", call. = FALSE)
  end <- at + which(src[(at + 1L):length(src)] == "```")[1L]
  src[(at + 1L):(end - 1L)]
}

# A throwaway study, so set_path() and study_dir() resolve as they would in a
# real one. study_setup() prints a checklist, which a test does not want.
rf_study <- function(.local_envir = parent.frame()) {
  root <- withr::local_tempdir("rf-study-", .local_envir = .local_envir)
  utils::capture.output(suppressMessages(
    hvtiRutilities::study_setup(root, study = "RF smoke", study_tracker_id = 1L)
  ))
  normalizePath(root)
}

# Evaluate the chunks `labels` of template (prefix, qualifier) in `env`. After
# `study-choices` runs, `choices` overwrites the template's placeholders, as a
# study author's edits would. `setup` is never run: it resolves the study root
# from the file being rendered, so the caller sets env$.root and attaches the
# packages instead.
rf_run <- function(prefix, qualifier, labels, env, choices = list()) {
  src <- readLines(template_path(prefix, qualifier), warn = FALSE)
  for (label in labels) {
    suppressMessages(eval(parse(text = rf_chunk(src, label)), envir = env))
    if (identical(label, "study-choices")) list2env(choices, envir = env)
  }
  invisible(env)
}

rf_skip_unless_stack <- function() {
  testthat::skip_if_not_installed("randomForestSRC", minimum_version = "3.7.0")
  testthat::skip_if_not_installed("varPro", minimum_version = "3.2.0")
  testthat::skip_if_not_installed("ggRandomForests", minimum_version = "4.0.0")
  testthat::skip_if_not_installed("hvtiRutilities", minimum_version = "1.3.0")
  suppressPackageStartupMessages({
    library(randomForestSRC)
    library(varPro)
    library(ggRandomForests)
    library(hvtiRutilities)
  })
}

# A fresh environment whose read_built() returns `data` instead of reading a
# registered dataset, rooted in a throwaway study.
rf_env <- function(data, .local_envir = parent.frame()) {
  env <- new.env(parent = globalenv())
  env$.root <- rf_study(.local_envir)
  env$read_built <- function(...) data
  env
}
```

- [ ] **Step 2: Write the failing tests**

Create `tests/testthat/test-rf-templates.R`:

```r
# Survival data for rfs: randomForestSRC's own veteran set, status 0/1.
rfs_data <- function() {
  e <- new.env()
  utils::data("veteran", package = "randomForestSRC", envir = e)
  e$veteran
}
rfs_choices <- list(TIME = "time", STATUS = "status",
                    PREDICTORS = c("trt", "celltype", "karno", "diagtime", "age", "prior"),
                    NTREE = 50, SEED = 1)

test_that("rfs-fit grows a survival forest and saves the handoff", {
  rf_skip_unless_stack()
  env <- rf_env(rfs_data())
  rf_run("rfs", "fit", c("set", "study-choices", "read", "fit", "diagnostics", "save"), env, rfs_choices)

  expect_s3_class(env$forest, "rfsrc")
  expect_identical(env$forest$family, "surv")
  handoff <- file.path(env$CACHE_DIR, "rfs.rds")
  expect_true(file.exists(handoff))
  expect_true(file.exists(file.path(env$CACHE_DIR, "rfs-forest.rds")))
  # The handoff is the bare forest, not cache_fit()'s keyed record.
  expect_s3_class(readRDS(handoff), "rfsrc")
  for (p in list(env$err, env$surv, env$brier)) {
    expect_s3_class(ggplot2::ggplot_build(plot(p)), "ggplot_built")
  }
})

test_that("rfs-fit refuses a status that is not 0/1", {
  rf_skip_unless_stack()
  d <- rfs_data()
  d$status <- d$status + 1L   # 1/2 coding: randomForestSRC would read 2 as a competing event
  env <- rf_env(d)
  expect_error(rf_run("rfs", "fit", c("set", "study-choices", "read"), env, rfs_choices),
               "0 and 1")
})

test_that("rfs-fit refuses a patient with no outcome", {
  rf_skip_unless_stack()
  d <- rfs_data()
  d$time[3] <- NA
  env <- rf_env(d)
  expect_error(rf_run("rfs", "fit", c("set", "study-choices", "read"), env, rfs_choices),
               "no time or status")
})
```

- [ ] **Step 3: Run them to verify they fail**

Run: `Rscript -e 'devtools::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-rf-templates.R")'`
Expected: FAIL (or ERROR) in all three with `template_path()` reporting no `rfs` template with qualifier `fit`.

- [ ] **Step 4: Write `rfs-fit.qmd`**

Create `inst/templates/30_analyses/rfs-fit.qmd` from these parts, in order.

(a) YAML header: `hm.qmd` lines 1 to 20 verbatim, with line 2 changed to `title: "Random forest survival: fit"`.

(b) Narration, after one blank line:

```markdown
<!-- EDIT: name the job this replaces (an `rfsrc.*` or `rf.*` job with a
     survival outcome), and say which outcome and candidate predictors it
     used. -->

Replaces `analyses/<job>`: describe its outcome and candidate predictors here.

An `rfs-fit` job grows a random survival forest and checks that it learned
something: out-of-bag error by number of trees, predicted survival, and the
Brier score over follow-up. **Importance, VarPro and dependence plots are not
here.** They are the `rfs-explain` job in this same set, which reads the forest
this job saves instead of growing its own, so the explanations always describe
this forest.

Old `rfsrc.*` and `rf.*` jobs map onto three prefixes by outcome, read from the
job's fit call and not from its name: a survival outcome is `rfs`, a
classification or binary outcome `rfc`, a continuous outcome `rfr`.
```

(c) The `setup` chunk:

````markdown
```{r}
#| label: setup
# The study root is the nearest directory above this file holding _study.yml,
# so the job renders the same from the Render button, quarto render, or
# render_job(), at any depth, with no path in this document to edit.
.in <- knitr::current_input(dir = TRUE)
.root <- hvtiRutilities::study_root(if (is.null(.in)) getwd() else dirname(.in))
for (f in list.files(file.path(.root, "R"), pattern = "[.]R$", full.names = TRUE)) source(f)
suppressPackageStartupMessages({
  library(randomForestSRC)
  library(ggRandomForests)
  library(hvtiRutilities)
})
# The versions this template was verified against, end to end, on 2026-09-19.
# Below them a call here can fail or change meaning, and the message would
# arrive mid-render rather than here.
if (utils::packageVersion("randomForestSRC") < "3.7.0") {
  stop("This job needs randomForestSRC >= 3.7.0; ", utils::packageVersion("randomForestSRC"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
if (utils::packageVersion("ggRandomForests") < "4.0.0") {
  stop("This job needs ggRandomForests >= 4.0.0; ", utils::packageVersion("ggRandomForests"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
```
````

(d) The `edit-guard` chunk: `hm.qmd` lines 50 to 113 verbatim, except lines 57 to 62 (the hm-specific paragraph), which become:

```r
# Without it an unedited job renders green over a meaningless analysis. Here
# that is a forest grown on the template's placeholder outcome, predictors and
# tree count, whose error curve and survival plots look exactly like a result.
```

(e) The set block: `hm.qmd` lines 115 to 175 verbatim (the comment block, the `set` chunk and `set_path()`), with lines 133 and 134 changed to:

```r
ENDPOINT <- "dead"
TYPE     <- "rfs"
```

and then, before the chunk's closing fence, in place of `hm.qmd` lines 177 to 179:

```r

# `rfs-fit` writes the forest through this and `rfs-explain` reads it back,
# both by set, so an explanation can never be filed against a different set
# than the forest it explains. The write is the `save` chunk at the foot of
# this file.
```

(f) Study choices:

````markdown
## Study choices

Edit these values for this study before rendering.

```{r}
#| label: study-choices
# EDIT: follow-up time and the event indicator, coded 1 = event, 0 = censored.
TIME   <- "iv_dead"
STATUS <- "dead"

# EDIT: the candidate predictors. Name them rather than taking every column: a
# built dataset carries identifiers, dates and derived outcomes, and a forest
# will split on a date that quietly encodes follow-up.
PREDICTORS <- c("age", "female", "hx_chf")

# EDIT: forest size and seed. The error-by-trees plot below says whether NTREE
# was enough: a curve still falling at its right edge was not. SEED makes the
# forest reproducible and is part of its cache key.
NTREE <- 1000
SEED  <- 2026

# EDIT: "na.omit" drops a patient missing any predictor; "na.impute" keeps them
# and imputes inside the forest. The classification and regression exemplars
# imputed. Dropping is simpler to report and can shrink the cohort a great deal.
NA_ACTION <- "na.omit"

# Set TRUE after changing a choice above. A cache whose inputs changed stops the
# render instead of returning the old forest; TRUE recomputes only the caches
# that are out of date, so it is safe to leave on while iterating.
REFIT <- FALSE
```
````

(g) Read, fit, diagnostics and save:

````markdown
## Cohort

```{r}
#| label: read
d <- read_built()
.missing <- setdiff(c(TIME, STATUS, PREDICTORS), names(d))
if (length(.missing)) {
  stop("Not in the built dataset: ", paste(.missing, collapse = ", "), call. = FALSE)
}
d <- d[, c(TIME, STATUS, PREDICTORS), drop = FALSE]

# A forest cannot learn from a patient with no outcome, and na.impute would
# impute one, inventing follow-up. So the outcome is required whatever
# NA_ACTION says.
.no_outcome <- is.na(d[[TIME]]) | is.na(d[[STATUS]])
if (any(.no_outcome)) {
  stop(sum(.no_outcome), " patient(s) have no time or status. Resolve them in the ",
       "dataset build; the forest will not.", call. = FALSE)
}

# randomForestSRC reads a status above 1 as a competing event, so a 1/2 coding,
# which survival::Surv() accepts, would grow a competing-risks forest without
# a word. Refuse it here instead.
if (!all(d[[STATUS]] %in% c(0, 1))) {
  stop(STATUS, " must be coded 0 and 1 (1 = event); found ",
       paste(sort(unique(d[[STATUS]])), collapse = ", "), ".", call. = FALSE)
}
```

## Forest

```{r}
#| label: fit
#| message: true
# cache_fit() writes <dir>/<name>.rds and its default dir is the study's
# estimates folder, not this set's, so every call here names the set's.
CACHE_DIR <- dirname(set_path("estimates", "rfs.rds"))
model <- stats::as.formula(paste0("Surv(", TIME, ", ", STATUS, ") ~ ."))
forest <- cache_fit(
  "rfs-forest",
  rfsrc(model, data = d, ntree = NTREE, na.action = NA_ACTION, importance = "none"),
  seed = SEED, dir = CACHE_DIR, refit = REFIT
)
forest
```

`importance = "none"` is deliberate. Importance is the explain job's work, and
cached there on its own, so it can be recomputed without regrowing the forest.

## Does the forest work?

```{r}
#| label: diagnostics
# Out-of-bag error by number of trees.
err <- gg_error(forest)
plot(err)

# Out-of-bag predicted survival, one curve per patient.
surv <- gg_rfsrc(forest)
plot(surv)

# Brier score over follow-up. Lower is better, and 0.25 is what a coin flip
# scores.
brier <- gg_brier(forest)
plot(brier)
```

```{r}
#| label: save
# The product of this job, and what rfs-explain reads. It is separate from the
# cache on purpose: cache_fit() stores a keyed record rather than the bare
# forest, so the cache is this job's internals and this file is its interface.
# The price is the forest on disk twice.
saveRDS(forest, set_path("estimates", "rfs.rds"))
```
````

- [ ] **Step 5: Add the lint key**

In `.lintr`, add to the `exclusions: list(` block, after the last existing `inst/templates/30_analyses/` entry, keeping the comma pattern of its neighbours:

```r
    "inst/templates/30_analyses/rfs-fit.qmd" = list(
      object_name_linter = Inf,
      commented_code_linter = Inf,
      object_usage_linter = Inf
    ),
```

- [ ] **Step 6: Mark the row shipped, and extend the two list tests**

In `inst/extdata/templates.json`, set the `(rfs, fit)` row's `"status"` to `"shipped"`.

In `tests/testthat/test-templates.R`, in the `declared <- c(` vector of the helpers test, change the last line `"label_map", "get_label"` to:

```r
    "label_map", "get_label",
    "cache_fit"  # >= 1.3.0, the floor DESCRIPTION declares
```

In the Suggests-bounds test, change the package vector to:

```r
  for (pkg in c(
    "hvtiRbootstrap", "hvtiRdatabuild", "hvtiRlifetables", "hvtiPlotR",
    "hvtiRtables", "randomForestSRC", "ggRandomForests"
  )) {
```

(`varPro` joins in Task 3, when the first template to call it lands. Adding it now fails the test's "no floor" expectation, which is the test working.)

- [ ] **Step 7: Run the new and affected tests**

Run: `Rscript -e 'devtools::install(quiet = TRUE, upgrade = "never"); devtools::load_all(quiet = TRUE); for (f in c("test-rf-templates.R", "test-templates.R", "test-add-job.R", "test-template-catalog.R")) testthat::test_file(file.path("tests/testthat", f))'`
Expected: all PASS. `devtools::install()` first because `rf_run()` reads the INSTALLED template through `template_path()`.

- [ ] **Step 8: Prove the handoff test by mutation**

Comment out the `saveRDS(` line in `rfs-fit.qmd`, reinstall, and re-run `test-rf-templates.R`.
Expected: `rfs-fit grows a survival forest and saves the handoff` FAILS on `file.exists(handoff)`. Restore the line and confirm it passes again.

- [ ] **Step 9: Lint and guards**

```bash
Rscript -e 'l <- lintr::lint_package(); print(l); quit(status = length(l) > 0)' && python3 dev/specs/artifacts/check-roadmap-counts.py
```

Expected: no lints; `... 15 on disk.`

- [ ] **Step 10: Commit**

```bash
git add tests/testthat/helper-rf.R tests/testthat/test-rf-templates.R tests/testthat/test-templates.R \
  inst/templates/30_analyses/rfs-fit.qmd .lintr inst/extdata/templates.json
git commit -m "feat: rfs-fit template

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: `rfs-explain`

**Files:**
- Create: `inst/templates/30_analyses/rfs-explain.qmd`
- Modify: `tests/testthat/test-rf-templates.R` (append)
- Modify: `tests/testthat/test-templates.R` (Suggests-bound list gains `varPro`)
- Modify: `.lintr`, `inst/extdata/templates.json`

**Interfaces:**
- Consumes: `rf_run()`, `rf_env()`, `rf_skip_unless_stack()` from Task 2; `rfs.rds` in the set's estimates folder.
- Produces: chunk labels `setup`, `edit-guard`, `set`, `study-choices`, `forest`, `importance`, `select`, `varpro`, `dependence`; objects `forest`, `frame`, `model`, `vi`, `ranked`, `sel`, `vp`, `pd`, `pv`; caches `rfs-vimp`, `rfs-varpro`, `rfs-partial`, `rfs-partial-varpro`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-rf-templates.R`:

```r
explain_labels <- c("set", "study-choices", "forest", "importance", "select", "varpro", "dependence")

# Explain needs a fit in the same set first; this runs one.
rf_fit_first <- function(prefix, data, choices, .local_envir = parent.frame()) {
  env <- rf_env(data, .local_envir)
  rf_run(prefix, "fit", c("set", "study-choices", "read", "fit", "save"), env, choices)
  env
}

test_that("rfs-explain explains the saved forest without refitting", {
  rf_skip_unless_stack()
  fit_env <- rf_fit_first("rfs", rfs_data(), rfs_choices)
  env <- new.env(parent = globalenv())
  env$.root <- fit_env$.root
  rf_run("rfs", "explain", explain_labels, env, list(TOP_K = 2, TIMES = c(30, 90), SEED = 1))

  expect_identical(names(env$frame), c(env$forest$yvar.names, env$forest$xvar.names))
  expect_length(env$sel, 2L)
  expect_identical(env$sel, head(env$ranked, 2L))
  for (nm in c("rfs-vimp", "rfs-varpro", "rfs-partial", "rfs-partial-varpro")) {
    expect_true(file.exists(file.path(env$CACHE_DIR, paste0(nm, ".rds"))), info = nm)
  }
  for (p in list(ggRandomForests::gg_vimp(env$vi), ggRandomForests::gg_varpro(env$vp), env$pd, env$pv)) {
    expect_s3_class(ggplot2::ggplot_build(plot(p)), "ggplot_built")
  }
})

test_that("rfs-explain stops when no fit has run in its set", {
  rf_skip_unless_stack()
  env <- new.env(parent = globalenv())
  env$.root <- rf_study()
  expect_error(rf_run("rfs", "explain", c("set", "study-choices", "forest"), env),
               "Render the rfs-fit job in this set first")
})

test_that("a changed TOP_K makes only the partial caches stale", {
  rf_skip_unless_stack()
  fit_env <- rf_fit_first("rfs", rfs_data(), rfs_choices)
  env <- new.env(parent = globalenv())
  env$.root <- fit_env$.root
  choices <- list(TOP_K = 2, TIMES = c(30, 90), SEED = 1)
  rf_run("rfs", "explain", explain_labels, env, choices)

  choices$TOP_K <- 3
  again <- new.env(parent = globalenv())
  again$.root <- fit_env$.root
  rf_run("rfs", "explain", c("set", "study-choices", "forest", "importance", "select", "varpro"), again, choices)
  expect_error(rf_run("rfs", "explain", "dependence", again), class = "hvtiRutilities_stale_cache")

  again$REFIT <- TRUE
  rf_run("rfs", "explain", "dependence", again)
  expect_length(again$sel, 3L)
})

test_that("no explain template grows a forest", {
  # The design's central promise: an explanation describes the forest the fit
  # job saved. A refit here, however helpful it looks when the handoff is
  # missing, would explain a different forest in a report that says otherwise.
  for (f in grep("-explain[.]qmd$", template_list()$file, value = TRUE)) {
    code <- sub("#.*$", "", readLines(f, warn = FALSE))
    expect_false(any(grepl("\\brfsrc\\(", code)), info = basename(f))
  }
})
```

- [ ] **Step 2: Run them to verify they fail**

Run: `Rscript -e 'devtools::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-rf-templates.R")'`
Expected: the three rfs-explain tests FAIL on `template_path()` finding no `explain`; the static test PASSES vacuously, since no explain file exists yet. Step 7 proves it by mutation.

- [ ] **Step 3: Write `rfs-explain.qmd`**

Parts, in order.

(a) YAML: `hm.qmd` lines 1 to 20 verbatim, with `title: "Random forest survival: explain"`.

(b) Narration:

```markdown
<!-- EDIT: say which rfs-fit job in this set this explains, and what question
     the importance and dependence plots are meant to answer. -->

Explains the forest the `rfs-fit` job in this set saved. Describe the question
here.

An `rfs-explain` job never grows a forest. It reads `rfs.rds`, which the fit
job writes, and rebuilds the training data and the model from the forest
itself, so every number below describes that forest and no other. Each
expensive step is cached on its own: changing how many variables get
dependence plots recomputes the partials and nothing else.
```

(c) `setup`: as `rfs-fit.qmd`'s, with `library(varPro)` added after `library(randomForestSRC)`, and this third floor after the other two:

```r
if (utils::packageVersion("varPro") < "3.2.0") {
  stop("This job needs varPro >= 3.2.0; ", utils::packageVersion("varPro"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
```

(d) `edit-guard`: `hm.qmd` lines 50 to 113, with lines 57 to 62 replaced by:

```r
# Without it an unedited job renders green over a meaningless analysis. Here
# that is dependence plots at placeholder survival horizons, drawn in units the
# study's follow-up may not even use, which look exactly like a result.
```

(e) The set block: as in `rfs-fit.qmd` step 4(e), `ENDPOINT <- "dead"` and `TYPE     <- "rfs"`, with the trailing comment:

```r

# `rfs-explain` reads the forest `rfs-fit` wrote in this same set, and caches
# its own work beside it.
```

(f) Study choices:

````markdown
## Study choices

Edit these values for this study before rendering. The outcome and predictors
are not here: they come from the forest.

```{r}
#| label: study-choices
# EDIT: how many variables get dependence plots, ranked by VIMP. The partials
# are the expensive step, so keep this small.
TOP_K <- 8

# EDIT: or name the variables yourself. NULL takes the top TOP_K by VIMP.
PARTIAL_VARS <- NULL

# EDIT: survival horizons for the partial plots, in the units of the fit job's
# time variable. The VarPro partial uses the last one.
TIMES <- c(1, 5, 10)

# EDIT: seed for VIMP, VarPro and the partials. It is part of every cache key.
SEED <- 2026

# Set TRUE after changing a choice above. A cache whose inputs changed stops the
# render instead of returning the old result; TRUE recomputes only the caches
# that are out of date.
REFIT <- FALSE
```
````

(g) The analysis chunks:

````markdown
## The forest

```{r}
#| label: forest
.handoff <- set_path("estimates", "rfs.rds")
if (!file.exists(.handoff)) {
  stop("No forest at ", .handoff, ". Render the rfs-fit job in this set first; ",
       "this job explains that forest and never grows its own.", call. = FALSE)
}
forest <- readRDS(.handoff)
if (!identical(forest$family, "surv")) {
  stop("rfs.rds holds a '", forest$family, "' forest, not a survival forest.", call. = FALSE)
}
CACHE_DIR <- dirname(.handoff)

# The training data and the model, from the forest rather than re-read. A
# VarPro or partial call on a frame that differs from the fitted one explains a
# model nobody fit. The forest keeps no usable formula (`$formula` is NULL and
# `$call` holds whatever expression the fit job wrote), so the model is rebuilt
# from the outcome names. `xvar` keeps any missing values under na.impute, and
# varpro() handles them; the forest's `imputed.data` makes varpro() fail.
frame <- cbind(forest$yvar, forest$xvar)
model <- stats::as.formula(paste0("Surv(", forest$yvar.names[1], ", ",
                                  forest$yvar.names[2], ") ~ ."))
```

## Importance

```{r}
#| label: importance
#| message: true
vi <- cache_fit("rfs-vimp", vimp(forest), seed = SEED, dir = CACHE_DIR, refit = REFIT)
plot(gg_vimp(vi))

# Minimal depth ranks by how near the root a variable first splits, a second
# opinion that needs no permutation. Cheap, so not cached.
ranked <- names(sort(vi$importance, decreasing = TRUE))
depth <- max.subtree(forest)$order[, 1]
data.frame(variable = ranked,
           vimp = round(vi$importance[ranked], 4),
           min_depth = round(depth[ranked], 2),
           row.names = NULL)
```

```{r}
#| label: select
if (is.null(PARTIAL_VARS)) {
  sel <- head(ranked, TOP_K)
} else {
  # A misspelt name would otherwise fail deep inside the partial call, or be
  # dropped from a plot without a word.
  .unknown <- setdiff(PARTIAL_VARS, forest$xvar.names)
  if (length(.unknown)) {
    stop("PARTIAL_VARS names variable(s) the forest was not grown on: ",
         paste(.unknown, collapse = ", "), call. = FALSE)
  }
  sel <- PARTIAL_VARS
}
```

## VarPro

```{r}
#| label: varpro
#| message: true
vp <- cache_fit("rfs-varpro", varpro(model, frame, verbose = FALSE),
                seed = SEED, dir = CACHE_DIR, refit = REFIT)
plot(gg_varpro(vp))
```

## Dependence

```{r}
#| label: dependence
#| message: true
# Marginal: predicted survival against each variable, as observed. Cheap.
plot(gg_variable(forest, time = TIMES), xvar = sel)

# Partial: the forest's prediction with every other variable held at its
# observed values.
pd <- cache_fit("rfs-partial", gg_partial_rfsrc(forest, xvar.names = sel, partial.time = TIMES),
                seed = SEED, dir = CACHE_DIR, refit = REFIT)
plot(pd)

# The VarPro partial, computed from the varpro fit at the last horizon. Not
# partialpro() then gg_partialpro(): the latter is deprecated, and for a
# survival forest a precomputed partialpro() result carries a survival label
# but not a survival curve.
pv <- cache_fit("rfs-partial-varpro", gg_partial_varpro(object = vp, xvar.names = sel, time = max(TIMES)),
                seed = SEED, dir = CACHE_DIR, refit = REFIT)
plot(pv)
```
````

- [ ] **Step 4: Lint key, catalog status, Suggests list**

Add the `.lintr` key for `"inst/templates/30_analyses/rfs-explain.qmd"` with the same three exclusions as Task 2 step 5. Set the `(rfs, explain)` row's `"status"` to `"shipped"`. In the Suggests-bounds test, add `"varPro"` to the package vector after `"ggRandomForests"`.

- [ ] **Step 5: Run the tests**

Run: `Rscript -e 'devtools::install(quiet = TRUE, upgrade = "never"); devtools::load_all(quiet = TRUE); for (f in c("test-rf-templates.R", "test-templates.R", "test-add-job.R")) testthat::test_file(file.path("tests/testthat", f))'`
Expected: all PASS.

- [ ] **Step 6: Prove the missing-forest stop by mutation**

Delete the `if (!file.exists(.handoff)) { ... }` block, reinstall, and run `test-rf-templates.R`.
Expected: `rfs-explain stops when no fit has run in its set` FAILS (readRDS's own error does not match the message). Restore it.

- [ ] **Step 7: Prove the no-refit test by mutation**

Add the line `forest <- rfsrc(model, frame)` at the end of the `forest` chunk, reinstall, and run `test-rf-templates.R`.
Expected: `no explain template grows a forest` FAILS naming `rfs-explain.qmd`. Remove the line.

- [ ] **Step 8: Lint and guards**

```bash
Rscript -e 'l <- lintr::lint_package(); print(l); quit(status = length(l) > 0)' && python3 dev/specs/artifacts/check-roadmap-counts.py
```

Expected: no lints; `... 16 on disk.`

- [ ] **Step 9: Commit**

```bash
git add inst/templates/30_analyses/rfs-explain.qmd tests/testthat/test-rf-templates.R tests/testthat/test-templates.R \
  .lintr inst/extdata/templates.json
git commit -m "feat: rfs-explain template

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: `rfc-fit` and `rfc-explain`

**Files:**
- Create: `inst/templates/30_analyses/rfc-fit.qmd`, `inst/templates/30_analyses/rfc-explain.qmd`
- Modify: `tests/testthat/test-rf-templates.R` (append), `.lintr`, `inst/extdata/templates.json`

**Interfaces:**
- Consumes: the helpers from Task 2 and `explain_labels`, `rf_fit_first()` from Task 3.
- Produces: `rfc.rds`; caches `rfc-forest`, `rfc-vimp`, `rfc-varpro`, `rfc-partial`, `rfc-partial-varpro`; fit objects `err`, `roc`, `auc`.

- [ ] **Step 1: Write the failing tests**

Append:

```r
# Classification data for rfc: two iris species, so the outcome is binary as
# most clinical classification outcomes are.
rfc_data <- function() {
  d <- datasets::iris[datasets::iris$Species != "setosa", ]
  d$Species <- as.character(d$Species)   # the fit must make it a factor itself
  d
}
rfc_choices <- list(RESPONSE = "Species",
                    PREDICTORS = c("Sepal.Length", "Sepal.Width", "Petal.Length", "Petal.Width"),
                    NTREE = 50, SEED = 1)

test_that("rfc-fit grows a classification forest from a character outcome", {
  rf_skip_unless_stack()
  env <- rf_env(rfc_data())
  rf_run("rfc", "fit", c("set", "study-choices", "read", "fit", "diagnostics", "save"), env, rfc_choices)
  expect_identical(env$forest$family, "class")
  expect_true(file.exists(file.path(env$CACHE_DIR, "rfc.rds")))
  expect_true(is.numeric(env$auc) && env$auc > 0.5)
  for (p in list(env$err, env$roc)) expect_s3_class(ggplot2::ggplot_build(plot(p)), "ggplot_built")
})

test_that("rfc-explain ranks by overall importance, not per class", {
  rf_skip_unless_stack()
  fit_env <- rf_fit_first("rfc", rfc_data(), rfc_choices)
  env <- new.env(parent = globalenv())
  env$.root <- fit_env$.root
  rf_run("rfc", "explain", explain_labels, env, list(TOP_K = 2, SEED = 1))
  expect_false(anyDuplicated(env$ranked) > 0)
  expect_length(env$sel, 2L)
  for (p in list(env$pd, env$pv)) expect_s3_class(ggplot2::ggplot_build(plot(p)), "ggplot_built")
})
```

- [ ] **Step 2: Run them to verify they fail**

Run: `Rscript -e 'devtools::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-rf-templates.R")'`
Expected: the two new tests FAIL on `template_path()`.

- [ ] **Step 3: Write `rfc-fit.qmd`**

Copy `rfs-fit.qmd` to `rfc-fit.qmd`, then make exactly these changes.

1. `title: "Random forest classification: fit"`.
2. In the narration, the HTML comment reads `(an \`rfsrc.*\` or \`rf.*\` job with a classification or binary outcome)`, and the second paragraph becomes:

   ```markdown
   An `rfc-fit` job grows a classification forest and checks that it learned
   something: out-of-bag error by number of trees, and the ROC curve with its
   AUC. **Importance, VarPro and dependence plots are not here.** They are the
   `rfc-explain` job in this same set, which reads the forest this job saves
   instead of growing its own, so the explanations always describe this forest.
   ```
3. The edit-guard paragraph ends `whose error curve and ROC curve look exactly like a result.`
4. `TYPE     <- "rfc"`, and every `rfs-fit`, `rfs-explain` and `rfs.rds` in comments becomes `rfc-fit`, `rfc-explain` and `rfc.rds`.
5. The `study-choices` outcome block becomes:

   ```r
   # EDIT: the outcome to classify. Any coding works: 0/1, "yes"/"no" or a label.
   # The read step makes it a factor, which is what makes this a classification
   # forest rather than a regression on the codes.
   RESPONSE <- "dead"
   ```

   and every other line of the chunk stays as in `rfs-fit.qmd`.
6. The `read` chunk becomes:

   ````markdown
   ```{r}
   #| label: read
   d <- read_built()
   .missing <- setdiff(c(RESPONSE, PREDICTORS), names(d))
   if (length(.missing)) {
     stop("Not in the built dataset: ", paste(.missing, collapse = ", "), call. = FALSE)
   }
   d <- d[, c(RESPONSE, PREDICTORS), drop = FALSE]

   # A forest cannot learn from a patient with no outcome, and na.impute would
   # impute one. So the outcome is required whatever NA_ACTION says.
   .no_outcome <- is.na(d[[RESPONSE]])
   if (any(.no_outcome)) {
     stop(sum(.no_outcome), " patient(s) have no ", RESPONSE, ". Resolve them in the ",
          "dataset build; the forest will not.", call. = FALSE)
   }

   # A numeric 0/1 outcome grows a REGRESSION forest, whose "probabilities" can
   # fall outside 0 and 1 and whose error is a mean squared error. Nothing warns.
   d[[RESPONSE]] <- factor(d[[RESPONSE]])
   ```
   ````
7. In the `fit` chunk: `"rfc.rds"`, `model <- stats::reformulate(".", response = RESPONSE)`, and `"rfc-forest"`.
8. The `diagnostics` chunk becomes:

   ````markdown
   ```{r}
   #| label: diagnostics
   # Out-of-bag error by number of trees, overall and per class.
   err <- gg_error(forest)
   plot(err)

   # Out-of-bag ROC curve, and the area under it.
   roc <- gg_roc(forest)
   plot(roc)
   auc <- calc_auc(roc)
   auc
   ```
   ````

   `gg_brier()` is not here: it supports survival forests only.
9. The `save` chunk writes `set_path("estimates", "rfc.rds")`, and its comment names `rfc-explain`.

- [ ] **Step 4: Write `rfc-explain.qmd`**

Copy `rfs-explain.qmd` to `rfc-explain.qmd`, then make exactly these changes.

1. `title: "Random forest classification: explain"`, and every `rfs` in narration, comments, `TYPE` and cache names becomes `rfc`.
2. The edit-guard paragraph becomes:

   ```r
   # Without it an unedited job renders green over a meaningless analysis. Here
   # that is dependence plots for a placeholder number of variables, which look
   # exactly like a result.
   ```
3. Delete the `TIMES` lines (its comment and assignment) from `study-choices`.
4. In the `forest` chunk, the family check tests `"class"` and says `not a classification forest`, and the frame and model lines become:

   ```r
   frame <- cbind(stats::setNames(data.frame(forest$yvar), forest$yvar.names), forest$xvar)
   model <- stats::reformulate(".", response = forest$yvar.names)
   ```
5. In the `importance` chunk, `ranked` and the table use the overall column:

   ```r
   # A classification forest reports importance per class as well as overall;
   # the ranking uses the overall column, so no variable is counted twice.
   imp <- vi$importance[, "all"]
   ranked <- names(sort(imp, decreasing = TRUE))
   depth <- max.subtree(forest)$order[, 1]
   data.frame(variable = ranked,
              vimp = round(imp[ranked], 4),
              min_depth = round(depth[ranked], 2),
              row.names = NULL)
   ```
6. The `dependence` chunk becomes:

   ````markdown
   ```{r}
   #| label: dependence
   #| message: true
   # Marginal: predicted class probability against each variable, as observed.
   plot(gg_variable(forest), xvar = sel)

   # Partial: the forest's prediction with every other variable held at its
   # observed values.
   pd <- cache_fit("rfc-partial", gg_partial_rfsrc(forest, xvar.names = sel),
                   seed = SEED, dir = CACHE_DIR, refit = REFIT)
   plot(pd)

   # The VarPro partial, computed from the varpro fit.
   pv <- cache_fit("rfc-partial-varpro", gg_partial_varpro(object = vp, xvar.names = sel),
                   seed = SEED, dir = CACHE_DIR, refit = REFIT)
   plot(pv)
   ```
   ````

- [ ] **Step 5: Lint keys and catalog status**

Add `.lintr` keys for `rfc-fit.qmd` and `rfc-explain.qmd` with the Task 2 exclusions. Set both `rfc` rows to `"shipped"`.

- [ ] **Step 6: Run the tests**

Run: `Rscript -e 'devtools::install(quiet = TRUE, upgrade = "never"); devtools::load_all(quiet = TRUE); for (f in c("test-rf-templates.R", "test-templates.R", "test-add-job.R")) testthat::test_file(file.path("tests/testthat", f))'`
Expected: all PASS.

- [ ] **Step 7: Prove the factor step by mutation**

Delete the `d[[RESPONSE]] <- factor(d[[RESPONSE]])` line, reinstall, and run `test-rf-templates.R`.
Expected: `rfc-fit grows a classification forest from a character outcome` FAILS: a character outcome errors in `rfsrc()`, or the family is not `"class"`. Restore it.

- [ ] **Step 8: Lint, guards, commit**

```bash
Rscript -e 'l <- lintr::lint_package(); print(l); quit(status = length(l) > 0)' && python3 dev/specs/artifacts/check-roadmap-counts.py
git add inst/templates/30_analyses/rfc-fit.qmd inst/templates/30_analyses/rfc-explain.qmd \
  tests/testthat/test-rf-templates.R .lintr inst/extdata/templates.json
git commit -m "feat: rfc-fit and rfc-explain templates

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Expected before the commit: no lints; `... 18 on disk.`

---

### Task 5: `rfr-fit` and `rfr-explain`

**Files:**
- Create: `inst/templates/30_analyses/rfr-fit.qmd`, `inst/templates/30_analyses/rfr-explain.qmd`
- Modify: `tests/testthat/test-rf-templates.R` (append), `.lintr`, `inst/extdata/templates.json`

**Interfaces:**
- Consumes: as Task 4.
- Produces: `rfr.rds`; caches `rfr-forest`, `rfr-vimp`, `rfr-varpro`, `rfr-partial`, `rfr-partial-varpro`; fit objects `err`, `pred`.

- [ ] **Step 1: Write the failing tests**

Append:

```r
rfr_data <- function() datasets::airquality[!is.na(datasets::airquality$Ozone), ]
rfr_choices <- list(RESPONSE = "Ozone", PREDICTORS = c("Solar.R", "Wind", "Temp", "Month", "Day"),
                    NTREE = 50, SEED = 1, NA_ACTION = "na.impute")

test_that("rfr-fit grows a regression forest, imputing missing predictors", {
  rf_skip_unless_stack()
  env <- rf_env(rfr_data())
  rf_run("rfr", "fit", c("set", "study-choices", "read", "fit", "diagnostics", "save"), env, rfr_choices)
  expect_identical(env$forest$family, "regr")
  expect_identical(env$forest$n, nrow(rfr_data()))   # na.impute kept every patient
  expect_true(file.exists(file.path(env$CACHE_DIR, "rfr.rds")))
  for (p in list(env$err, env$pred)) expect_s3_class(ggplot2::ggplot_build(plot(p)), "ggplot_built")
})

test_that("rfr-fit refuses a non-numeric outcome", {
  rf_skip_unless_stack()
  d <- rfr_data()
  d$Ozone <- factor(d$Ozone)
  env <- rf_env(d)
  expect_error(rf_run("rfr", "fit", c("set", "study-choices", "read"), env, rfr_choices), "must be numeric")
})

test_that("rfr-explain runs VarPro on a forest grown with missing predictors", {
  rf_skip_unless_stack()
  fit_env <- rf_fit_first("rfr", rfr_data(), rfr_choices)
  env <- new.env(parent = globalenv())
  env$.root <- fit_env$.root
  rf_run("rfr", "explain", explain_labels, env, list(TOP_K = 2, SEED = 1))
  expect_true(anyNA(env$frame))   # the raw training data, not imputed.data
  expect_s3_class(env$vp, "varpro")
  for (p in list(env$pd, env$pv)) expect_s3_class(ggplot2::ggplot_build(plot(p)), "ggplot_built")
})
```

- [ ] **Step 2: Run them to verify they fail**

Run: `Rscript -e 'devtools::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-rf-templates.R")'`
Expected: the three new tests FAIL on `template_path()`.

- [ ] **Step 3: Write `rfr-fit.qmd`**

Copy `rfc-fit.qmd` to `rfr-fit.qmd`, then make exactly these changes.

1. `title: "Random forest regression: fit"`; every `rfc` in narration, comments, `TYPE`, cache and file names becomes `rfr`; the HTML comment reads `(an \`rfsrc.*\` or \`rf.*\` job with a continuous outcome)`.
2. The narration's second paragraph becomes:

   ```markdown
   An `rfr-fit` job grows a regression forest and checks that it learned
   something: out-of-bag error by number of trees, and predicted against
   observed. **Importance, VarPro and dependence plots are not here.** They are
   the `rfr-explain` job in this same set, which reads the forest this job saves
   instead of growing its own, so the explanations always describe this forest.

   Every regression exemplar tuned the forest (`tune.rfsrc()`) before fitting.
   This template does not: tuning is a study's choice, added above the `fit`
   chunk when the error curve says the defaults are not enough.
   ```
3. The edit-guard paragraph ends `whose error curve and predicted-against-observed plot look exactly like a result.`
4. The outcome block of `study-choices`:

   ```r
   # EDIT: the continuous outcome. Transform it first if its distribution calls
   # for it (a length of stay is usually logged); the forest predicts on the
   # scale given here.
   RESPONSE <- "los"
   ```
5. In the `read` chunk, replace the factor comment and line with:

   ```r
   # A factor or character outcome grows a CLASSIFICATION forest, one class per
   # distinct value. Nothing warns.
   if (!is.numeric(d[[RESPONSE]])) {
     stop(RESPONSE, " must be numeric for a regression forest; it is ",
          class(d[[RESPONSE]])[1L], ".", call. = FALSE)
   }
   ```
6. The `diagnostics` chunk becomes:

   ````markdown
   ```{r}
   #| label: diagnostics
   # Out-of-bag error by number of trees.
   err <- gg_error(forest)
   plot(err)

   # Out-of-bag predicted against observed.
   pred <- gg_rfsrc(forest)
   plot(pred)
   ```
   ````

- [ ] **Step 4: Write `rfr-explain.qmd`**

Copy `rfc-explain.qmd` to `rfr-explain.qmd`, then make exactly these changes.

1. `title: "Random forest regression: explain"`; every `rfc` becomes `rfr`.
2. The family check tests `"regr"` and says `not a regression forest`.
3. The `importance` chunk's ranking uses the vector directly, as in `rfs-explain.qmd`:

   ```r
   ranked <- names(sort(vi$importance, decreasing = TRUE))
   depth <- max.subtree(forest)$order[, 1]
   data.frame(variable = ranked,
              vimp = round(vi$importance[ranked], 4),
              min_depth = round(depth[ranked], 2),
              row.names = NULL)
   ```

   with the per-class comment removed.
4. The marginal comment in `dependence` reads `# Marginal: predicted outcome against each variable, as observed.`

- [ ] **Step 5: Lint keys and catalog status**

Add `.lintr` keys for `rfr-fit.qmd` and `rfr-explain.qmd`. Set both `rfr` rows to `"shipped"`.

- [ ] **Step 6: Run the tests**

Run: `Rscript -e 'devtools::install(quiet = TRUE, upgrade = "never"); devtools::load_all(quiet = TRUE); for (f in c("test-rf-templates.R", "test-templates.R", "test-add-job.R")) testthat::test_file(file.path("tests/testthat", f))'`
Expected: all PASS.

- [ ] **Step 7: Prove the numeric check by mutation**

Delete the `if (!is.numeric(...)) { ... }` block, reinstall, and run `test-rf-templates.R`.
Expected: `rfr-fit refuses a non-numeric outcome` FAILS. Restore it.

- [ ] **Step 8: Lint, guards, commit**

```bash
Rscript -e 'l <- lintr::lint_package(); print(l); quit(status = length(l) > 0)' && python3 dev/specs/artifacts/check-roadmap-counts.py
git add inst/templates/30_analyses/rfr-fit.qmd inst/templates/30_analyses/rfr-explain.qmd \
  tests/testthat/test-rf-templates.R .lintr inst/extdata/templates.json
git commit -m "feat: rfr-fit and rfr-explain templates

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Expected before the commit: no lints; `... 20 on disk.`

---

### Task 6: Docs, full gates, review and PR

**Files:**
- Modify: `inst/templates/README.md` (the "What is here" table, a new mapping subsection)
- Modify: `NEWS.md` (under `# hvtiRtemplates (unreleased)`)

- [ ] **Step 1: README rows**

In `inst/templates/README.md`, append to the table under `## What is here`, after the `bh.qmd` row:

```markdown
| `30_analyses/rfs-fit.qmd` | random survival forest, grown and checked | `30_analyses/` or `analyses/` |
| `30_analyses/rfs-explain.qmd` | importance, VarPro and dependence for an `rfs` forest | `30_analyses/` or `analyses/` |
| `30_analyses/rfc-fit.qmd` | classification forest, grown and checked | `30_analyses/` or `analyses/` |
| `30_analyses/rfc-explain.qmd` | importance, VarPro and dependence for an `rfc` forest | `30_analyses/` or `analyses/` |
| `30_analyses/rfr-fit.qmd` | regression forest, grown and checked | `30_analyses/` or `analyses/` |
| `30_analyses/rfr-explain.qmd` | importance, VarPro and dependence for an `rfr` forest | `30_analyses/` or `analyses/` |
```

- [ ] **Step 2: README migration mapping**

Insert before `## Where a scaffolded job lands`:

```markdown
### Random forest jobs

The random forest templates come in pairs. The `fit` job grows the forest and
saves it as `<prefix>.rds` in its set's estimates folder; the `explain` job
reads that file and never grows its own, so every explanation describes the
forest that was checked. Scaffold both into the same set, for example
`add_job("rfs", "dead", "rfs", qualifier = "fit")` and
`add_job("rfs", "dead", "rfs", qualifier = "explain")`, and render the fit job
first.

Older studies name these jobs `rfsrc.*` or `rf.*`, whatever the outcome. They
map by the outcome in the job's fit call, not by the name:

| old job | outcome | template |
|---|---|---|
| `rfsrc.*`, `rf.*` | survival | `rfs` |
| `rfsrc.*`, `rf.*` | classification or binary | `rfc` |
| `rfsrc.*`, `rf.*` | continuous | `rfr` |

```

- [ ] **Step 3: NEWS entry**

Under `# hvtiRtemplates (unreleased)` in `NEWS.md`, add as the first bullet:

```markdown
* Six random forest templates: `rfs`, `rfc` and `rfr`, for survival,
  classification and continuous outcomes, each as a `fit` job and an `explain`
  job. The fit job grows the forest through `hvtiRutilities::cache_fit()` and
  saves it for the explain job, which reads it back for VIMP, VarPro and
  dependence plots and never refits. Old `rfsrc.*` and `rf.*` jobs map onto
  the three by outcome; `inst/templates/README.md` has the table.
  `randomForestSRC (>= 3.7.0)` and `varPro (>= 3.2.0)` join Suggests, and
  `ggRandomForests` rises to `>= 4.0.0`.
```

- [ ] **Step 4: Render one pair through Quarto**

The chunk tests do not exercise Quarto, chunk options or the edit-guard banner. Render once by hand in a throwaway study:

```bash
Rscript -e '
d <- file.path(tempdir(), "rf-render"); utils::capture.output(hvtiRutilities::study_setup(d, study = "RF render", study_tracker_id = 1L))
e <- new.env(); utils::data("veteran", package = "randomForestSRC", envir = e)
saveRDS(e$veteran, file.path(hvtiRutilities::study_dir("datasets", d), "veteran.rds"))
hvtiRutilities::register_data(d, built = "veteran.rds", event = "status", time = "time")
f <- hvtiRtemplates::add_job("rfs", "dead", "rfs", dir = d, qualifier = "fit")
x <- readLines(f); x <- sub("\"iv_dead\"", "\"time\"", x); x <- sub("STATUS <- \"dead\"", "STATUS <- \"status\"", x)
x <- sub("c\\(\"age\", \"female\", \"hx_chf\"\\)", "c(\"karno\", \"age\", \"celltype\")", x); x <- sub("NTREE <- 1000", "NTREE <- 50", x)
writeLines(x, f); hvtiRtemplates::render_job(f); cat("rendered:", sub("[.]qmd$", ".html", f), "\n")'
```

Expected: an `.html` that shows the DRAFT banner (the `EDIT:` markers remain) and the three diagnostic plots. If `register_data()` or `read_built()` refuses the `.rds` source, read their help pages and adapt this step; do not skip it. Open the `.html` and look at it.

- [ ] **Step 5: Full gates**

```bash
Rscript -e 'devtools::document(); devtools::test()' && Rscript -e 'devtools::check()' && Rscript -e 'l <- lintr::lint_package(); print(l); quit(status = length(l) > 0)' && python3 dev/specs/artifacts/check-roadmap-counts.py && python3 dev/specs/artifacts/check-spec-counts.py && python3 dev/specs/artifacts/check-flow-counts.py
```

Expected: tests PASS with no new SKIP beyond what the machine lacks; check 0 errors, 0 warnings, 0 notes; no lints; guards pass (`... 20 on disk.`).

- [ ] **Step 6: Commit docs**

```bash
git add inst/templates/README.md NEWS.md
git commit -m "docs: rf templates in the README table and NEWS

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Local code review**

Run `/code-review` against the branch. Fix confirmed findings in new commits, re-running step 5 after each.

- [ ] **Step 8: Push and open the PR**

```bash
git push -u origin spec/rf-templates
gh pr create --base main --title "rfs/rfc/rfr fit and explain templates" --body "..."
```

The body names the spec and plan, lists the six templates, says that a local `/code-review` stood in for the Copilot bot (quota exhausted), and ends with the attribution line.

- [ ] **Step 9: Read the CI summaries, not the check marks**

```bash
gh run list --branch spec/rf-templates --limit 3
gh run view <run-id> --log | grep -E "SKIP [0-9]+ \| PASS"
```

Expected: `SKIP 0` on macOS and Ubuntu, `SKIP 1` on Windows. Any higher SKIP means an rf smoke test skipped for a missing package on that leg, and the templates went untested there.
