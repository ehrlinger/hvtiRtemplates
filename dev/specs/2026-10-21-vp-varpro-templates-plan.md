# `vp` templates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `vp-fit.qmd` (a VarPro variable screen with coverage, a per-kind noise bar and stability across subsamples) and `vp-explain.qmd` (VarPro partial dependence for the selected variables) under a new taxonomy prefix `vp`, both at ledger status `in-flight`.

**Architecture:** Two self-contained Quarto templates in `inst/templates/30_analyses/`, built from Virtual Twins notebook chapter 13 and report Appendix C. `vp-fit` saves one handoff, `vp.rds` (`list(fit, coverage, selected, family)` with lineage attached); `vp-explain` reads it the way `rfs-explain` reads `rfs.rds`. The taxonomy row lives in **hvtiRutilities**, so the work spans two repos in a fixed order: ledger rows at `intake` here, the taxonomy row there, then the templates here.

**Tech Stack:** R, Quarto, varPro 3.3.0, ggRandomForests 4.0.0 (`varpro_coverage()`), hvtiRutilities (`cache_fit()`, `hvti_taxonomy()`), testthat edition 3.

**Spec:** [`2026-10-21-vp-varpro-templates-design.md`](2026-10-21-vp-varpro-templates-design.md).

## Global Constraints

- Never push to `main`. Every task's changes go on the branch it names, through a PR the maintainer merges.
- Branch from `origin/main` after `git fetch`, never from local `main`: other sessions merge here concurrently.
- Versions are three digits. No PR touches `Version:` or `NEWS.md`; a PR that ships a file adds `news/<branch with / replaced by ->.md` holding its bullet(s) and no heading. A PR whose every file is excluded by `.Rbuildignore` (`dev/`, `.github/`, `AGENTS.md`, `CLAUDE.md`) adds no fragment.
- Roxygen is Rd markup (no markdown). Lines are at most 135 characters (`.lintr`).
- A template carries its own `format:` block, opens with ONE `setup` chunk, has exactly one `^SUBJECT\s+<- ` and one `^TYPE\s+<- ` line, puts every `EDIT:` marker in a chunk labeled `edit-…`, carries no study identifiers, and ends with one `provenance` chunk.
- Each template gets its own **file** key in `.lintr` excluding exactly `object_name_linter`, `commented_code_linter` and `object_usage_linter`.
- Version floors in the templates match `DESCRIPTION`'s `Suggests`: `varPro (>= 3.2.0)`, `ggRandomForests (>= 4.0.0)`. A ggRandomForests 4.0.0 build without `varpro_coverage()` exists (rc builds before rc9 share the version string), so `vp-fit` also checks the export.
- `options(rf.cores = 1L)` in every `setup` chunk that fits, as the rf templates do.
- Every random call is seeded: `set.seed()` before it, and `varpro()` also gets `seed = -abs(<seed>)`. `varpro()` draws on R's generator even with `seed =`.
- Tests that fit varPro carry `skip_on_cran()`. Tests run the INSTALLED templates chunk by chunk via `rf_run()` (`tests/testthat/helper-rf.R`).
- Local test runs that need the `vp` taxonomy row use a private library holding hvtiRutilities from `main` (Task 2 onward): `R_LIBS="$VP_LIB"`. Concurrent sessions overwrite the shared library.
- Never `git add -A` after a test run: a failing testthat run writes `tests/testthat/_problems/`. Add files by name.
- Run `/code-review` locally before opening each PR and say in the PR body that it stood in for Copilot, whose credits are exhausted.

## File map

| File | Task | Responsibility |
|---|---|---|
| `inst/extdata/templates.json` | 1, 3, 6 | two ledger rows: `intake` (1), fit row `in-flight` (3), explain row `in-flight` (6) |
| `dev/specs/2026-08-29-template-conversion-roadmap.md` | 1, 3, 6 | regenerated tables (`roadmap_render.py`) |
| `tests/testthat/test-template-catalog.R` | 1 | catalog counts 66 → 68 rows, 44 → 45 prefixes |
| `hvtiRutilities: R/taxonomy.R` | 2 | the `vp` row |
| `inst/templates/30_analyses/vp-fit.qmd` | 3, 4, 5 | the screen |
| `inst/templates/30_analyses/vp-explain.qmd` | 6 | the partials |
| `tests/testthat/helper-vp.R` | 3 | `vp_data()`, `vp_choices`, `vp_outcome()`, `vp_fit_labels`, `vp_fit_first()` |
| `tests/testthat/test-vp-templates.R` | 3–6 | the vp tests |
| `.lintr` | 3, 6 | one file key per template |
| `inst/templates/README.md` | 7 | template table, qualified-template sentence, figure-name table |
| `tests/testthat/test-template-figures.R` | 7 | documented figure names for the two templates |
| `inst/templates/30_analyses/rf{s,c,r}-explain.qmd` | 7 | one pointer paragraph each |
| `news/*.md` | 1, 2, 7 | fragments |

---

### Task 1: Ledger rows at `intake` (hvtiRtemplates)

Lands first, so that when Task 2 puts `vp` into the taxonomy this repo's `test-roadmap.R` direction one ("every taxonomy prefix has a roadmap row") already holds.

**Files:**
- Modify: `inst/extdata/templates.json` (insert two rows after the `rfr`/`explain` row)
- Modify: `tests/testthat/test-template-catalog.R:4-5`
- Modify: `dev/specs/2026-08-29-template-conversion-roadmap.md` (generated block only, by script)
- Create: `news/feat-vp-intake.md`

**Interfaces:**
- Produces: catalog rows keyed `(vp, fit)` and `(vp, explain)`, `folder: "analyses"`, `family: "machine-learning"`. Tasks 3 and 6 flip their `status`, `blocked_on` and `note`.

- [ ] **Step 1: Branch**

```bash
cd /Users/ehrlinj/Documents/GitHub/hvtiRtemplates
git fetch -q origin && git checkout -b feat/vp-intake origin/main
```

- [ ] **Step 2: Move the catalog counts (the failing test)**

In `tests/testthat/test-template-catalog.R`, change

```r
  expect_equal(nrow(catalog), 66L)
  expect_equal(length(unique(catalog$prefix)), 44L)
```

to

```r
  expect_equal(nrow(catalog), 68L)
  expect_equal(length(unique(catalog$prefix)), 45L)
```

- [ ] **Step 3: Run it to see it fail**

Run: `Rscript -e 'devtools::test(filter = "template-catalog$")'`
Expected: FAIL, `nrow(catalog)` is 66 not 68.

- [ ] **Step 4: Add the two rows**

In `inst/extdata/templates.json`, find the row with `"prefix": "rfr"` and `"qualifier": "explain"` and insert after it (mind the comma between objects):

```json
    {
      "prefix": "vp",
      "qualifier": "fit",
      "name": "VarPro: fit",
      "description": "A VarPro variable screen that says which variables were tested, judges selection against permuted noise of the same kind, and checks the selection across subsamples.",
      "folder": "analyses",
      "family": "machine-learning",
      "kind": "job",
      "status": "intake",
      "batch": null,
      "sas_breadth": null,
      "r_exemplars": null,
      "r_jobs": null,
      "upstream": [],
      "downstream": [],
      "workflows": [],
      "blocked_on": "hvtiRutilities: the vp row in hvti_taxonomy()",
      "spec": "dev/specs/2026-10-21-vp-varpro-templates-design.md",
      "note": "Built from Virtual Twins notebook ch13 and report Appendix C. Other studies run varPro; Virtual Twins is the first to reach the coverage, noise and stability stage.",
      "sas_breadth_jobs": null,
      "disposition": "scaffold",
      "uses": [
        "varPro::varpro",
        "ggRandomForests::varpro_coverage",
        "ggRandomForests::gg_varpro",
        "hvtiRutilities::cache_fit"
      ]
    },
    {
      "prefix": "vp",
      "qualifier": "explain",
      "name": "VarPro: explain",
      "description": "VarPro partial dependence for the variables a vp-fit screen selected. It never fits varPro.",
      "folder": "analyses",
      "family": "machine-learning",
      "kind": "job",
      "status": "intake",
      "batch": null,
      "sas_breadth": null,
      "r_exemplars": null,
      "r_jobs": null,
      "upstream": [],
      "downstream": [],
      "workflows": [],
      "blocked_on": "hvtiRutilities: the vp row in hvti_taxonomy()",
      "spec": "dev/specs/2026-10-21-vp-varpro-templates-design.md",
      "note": "Reads vp.rds from vp-fit in the same set and never refits.",
      "sas_breadth_jobs": null,
      "disposition": "scaffold",
      "uses": [
        "ggRandomForests::gg_partial_varpro",
        "hvtiRutilities::cache_fit"
      ]
    }
```

- [ ] **Step 5: Regenerate the roadmap tables and run the three count guards**

```bash
python3 dev/specs/artifacts/roadmap_render.py
python3 dev/specs/artifacts/check-roadmap-counts.py && python3 dev/specs/artifacts/check-spec-counts.py && python3 dev/specs/artifacts/check-flow-counts.py
```

Expected: `Catalog agrees with disk: 68 template rows routed to hvtiRtemplates, 36 on disk.` and the other two print their "agree" lines. Then `grep -n "66 templates in scope" dev/specs/2026-08-29-template-conversion-roadmap.md`: if that sentence sits outside the generated block, change it to `**68 templates in scope**, of which 36 exist on disk.`

- [ ] **Step 6: Run the catalog and roadmap tests**

Run: `Rscript -e 'devtools::test(filter = "template-catalog|roadmap|templates$")'`
Expected: PASS, 0 failures. `test-roadmap.R` passes because `intake` rows are exempt from direction two.

- [ ] **Step 7: News fragment**

Create `news/feat-vp-intake.md`:

```markdown
* The template catalog lists `vp-fit` and `vp-explain`, a VarPro variable screen and its partial dependence, at status `intake` until hvtiRutilities adds the `vp` prefix to `hvti_taxonomy()`.
```

- [ ] **Step 8: Commit, review, PR**

```bash
git add inst/extdata/templates.json tests/testthat/test-template-catalog.R dev/specs/2026-08-29-template-conversion-roadmap.md news/feat-vp-intake.md
git commit -m "feat(catalog): list vp-fit and vp-explain at intake

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin feat/vp-intake
gh pr create --title "Catalog: vp-fit and vp-explain at intake" --body "..."
```

The PR body says the rows wait on hvtiRutilities (Task 2) and that `/code-review` stood in for Copilot. **Wait for the maintainer to merge before Task 2's PR is merged.**

---

### Task 2: The `vp` taxonomy row (hvtiRutilities)

**Files (repo `/Users/ehrlinj/Documents/GitHub/hvtiRutilities`):**
- Modify: `R/taxonomy.R` (one row after the `vt` row)
- Create: `news/feat-vp-taxonomy.md`

**Interfaces:**
- Produces: `hvti_taxonomy()` row `prefix = "vp"`, `name = "VarPro"`, `folder = "analyses"`, `umbrella = FALSE`.

- [ ] **Step 1: Branch**

```bash
cd /Users/ehrlinj/Documents/GitHub/hvtiRutilities
git fetch -q origin && git checkout -b feat/vp-taxonomy origin/main
```

- [ ] **Step 2: Write the failing test**

Append to `tests/testthat/test-taxonomy.R` (create the `test_that` at the file's end; if the file is named differently, `grep -ln "hvti_taxonomy()" tests/testthat` finds it):

```r
test_that("vp names the VarPro screen, filed under analyses", {
  tx <- hvti_taxonomy()
  row <- tx[tx$prefix %in% "vp", ]
  expect_identical(nrow(row), 1L)
  expect_identical(row$folder, "analyses")
  expect_false(row$umbrella)
})
```

- [ ] **Step 3: Run it to see it fail**

Run: `Rscript -e 'devtools::test(filter = "taxonomy")'`
Expected: FAIL, `nrow(row)` is 0.

- [ ] **Step 4: Add the row**

In `R/taxonomy.R`, after the line beginning `    c("vt",`, insert, column-aligned with the rows around it (name field padded to 29 characters, folder field to 17):

```r
    c("vp",    "VarPro",                    "analyses",      "rule-based variable screen: coverage, noise and stability checks"),
```

Then find any other list that names the rows one by one: `git grep -n '"vt"\|`vt`' -- R tests vignettes README.md inst man`. Add `vp` beside `vt` wherever one does (the roxygen above the table, a vignette table). Run `Rscript -e 'devtools::document()'` if roxygen changed.

- [ ] **Step 5: Run the tests and lint**

Run: `Rscript -e 'devtools::test(); lintr::lint("R/taxonomy.R")'`
Expected: 0 failures; no lints (`commas_linter` catches misalignment).

- [ ] **Step 6: News fragment**

Create `news/feat-vp-taxonomy.md`:

```markdown
* `hvti_taxonomy()` gains `vp`, a VarPro variable screen with coverage, noise and stability checks, for the `vp-fit` and `vp-explain` templates in hvtiRtemplates.
```

- [ ] **Step 7: Commit, review, PR**

```bash
git add R/taxonomy.R tests/testthat/test-taxonomy.R news/feat-vp-taxonomy.md   # plus man/ or vignettes/ if Step 4 touched them
git commit -m "feat(taxonomy): add vp, the VarPro screen

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin feat/vp-taxonomy
gh pr create --title "Taxonomy: add vp (VarPro screen)" --body "..."
```

The body links the hvtiRtemplates intake PR and the spec. Before it merges, run hvtiRtemplates' tests against this branch (release-ordering rule): `R CMD INSTALL -l "$VP_LIB" .` then `R_LIBS="$VP_LIB" Rscript -e 'devtools::test()'` in hvtiRtemplates' `main` checkout, expecting 0 failures. **Tasks 3–7 start once this PR is on hvtiRutilities `main`.**

---

### Task 3: `vp-fit.qmd`, data and noise

**Files:**
- Create: `inst/templates/30_analyses/vp-fit.qmd`
- Create: `tests/testthat/helper-vp.R`
- Create: `tests/testthat/test-vp-templates.R`
- Modify: `.lintr` (file key after the `rfr-explain.qmd` key)
- Modify: `inst/extdata/templates.json` (`vp`/`fit` row → `in-flight`), roadmap doc (script)

**Interfaces:**
- Consumes: `rf_env(data)`, `rf_run(prefix, qualifier, labels, env, choices)`, `rf_chunk(src, label)`, `rf_skip_unless_stack(pkgs)`, `rf_template_packages(prefix, qualifier)` from `helper-rf.R`.
- Produces, in the chunk environment: `d` (outcome plus candidates, complete cases), `d_noise` (`d` plus `NOISE_N` columns `noise<i>_<source>`), `model` (formula), `.family` (`"survival"`, `"classification"` or `"regression"`), `.analysis`, `.cohort`, `vp_kind(x)` → `"categorical"`/`"continuous"`, `vp_add_noise(d, predictors, n, seed)` → data frame. Test helpers `vp_data()`, `vp_choices`, `vp_outcome(choices, ...)`, `vp_fit_labels`, `vp_fit_first()`.

- [ ] **Step 1: Branch and private library**

```bash
cd /Users/ehrlinj/Documents/GitHub/hvtiRtemplates
git fetch -q origin && git checkout -b feat/vp-templates origin/main
export VP_LIB=/private/tmp/claude-504/-Users-ehrlinj-Documents-GitHub-hvtiRtemplates/vp-lib
mkdir -p "$VP_LIB" && git -C ../hvtiRutilities fetch -q origin && git -C ../hvtiRutilities checkout -q origin/main && R CMD INSTALL -l "$VP_LIB" ../hvtiRutilities
R_LIBS="$VP_LIB" Rscript -e 'stopifnot("vp" %in% hvtiRutilities::hvti_taxonomy()$prefix)'
```

- [ ] **Step 2: Test helpers**

Create `tests/testthat/helper-vp.R`:

```r
# The vp templates are run chunk by chunk through rf_run() (helper-rf.R), whose
# chunk runner is not specific to random forests.

# A survival cohort with a planted signal: the hazard rises with `xs` and with
# level "b" of `fs`; `x1`, `x2` and `g1` are null. Seeded, so a test sees the
# same patients every run.
vp_data <- function(n = 200L, seed = 20261021L) {
  withr::with_seed(seed, {
    d <- data.frame(
      xs = stats::rnorm(n), fs = factor(sample(c("a", "b"), n, replace = TRUE)),
      x1 = stats::rnorm(n), x2 = stats::rnorm(n), g1 = factor(sample(c("u", "v", "w"), n, replace = TRUE))
    )
    event_time <- stats::rexp(n, exp(1.2 * d$xs + 1.2 * (d$fs == "b")))
    censor <- stats::rexp(n, 0.3)
  })
  d$time <- pmin(event_time, censor)
  d$event <- as.integer(event_time <= censor)
  d
}

# Every choice a vp-fit test sets. RESPONSE = NULL is kept as an element: the
# chunks read it, and list2env() assigns a NULL element.
vp_choices <- list(
  TIME = "time", EVENT = "event", RESPONSE = NULL,
  PREDICTORS = c("xs", "fs", "x1", "x2", "g1"),
  NTREE = 50, REPEATS = 2, SEED = 1, SAVE_FIGURES = FALSE
)

# vp_choices with the three outcome choices replaced. utils::modifyList() would
# DROP an element set to NULL, so the outcome is rebuilt with c(), which keeps it.
vp_outcome <- function(choices, TIME, EVENT, RESPONSE) {  # nolint: object_name_linter.
  c(choices[setdiff(names(choices), c("TIME", "EVENT", "RESPONSE"))],
    list(TIME = TIME, EVENT = EVENT, RESPONSE = RESPONSE))
}

# Every chunk of vp-fit, in order. Tasks 4 and 5 extend it.
vp_fit_labels <- c("setup", "edit-study-choices", "tbl-data", "tbl-missing", "noise")

# vp-fit run end to end in a throwaway study.
vp_fit_first <- function(data = vp_data(), choices = vp_choices, .local_envir = parent.frame()) {
  env <- rf_env(data, .local_envir)  # nolint: object_usage_linter.
  rf_run("vp", "fit", vp_fit_labels, env, choices)  # nolint: object_usage_linter.
  env
}
```

- [ ] **Step 3: Write the failing tests**

Create `tests/testthat/test-vp-templates.R`:

```r
# The vp templates, run chunk by chunk from the installed files (helper-rf.R,
# helper-vp.R). Only tests that fit varPro skip on CRAN.

vp_data_labels <- c("setup", "edit-study-choices", "tbl-data", "tbl-missing")

test_that("vp-fit draws half its noise from each kind of candidate", {
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  env <- rf_env(vp_data())
  rf_run("vp", "fit", c(vp_data_labels, "noise"), env, vp_choices)
  noise <- grep("^noise", names(env$d_noise), value = TRUE)
  src <- sub("^noise[0-9]+_", "", noise)
  expect_length(noise, 20L)
  expect_identical(sum(src %in% c("fs", "g1")), 10L)
  # A permuted copy keeps its source's values and loses their order.
  for (i in seq_along(noise)) {
    expect_identical(sort(as.character(env$d_noise[[noise[i]]])), sort(as.character(env$d[[src[i]]])))
  }
})

test_that("vp-fit refuses an outcome named both ways, or neither", {
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  both <- vp_outcome(vp_choices, TIME = "time", EVENT = "event", RESPONSE = "event")
  neither <- vp_outcome(vp_choices, TIME = NULL, EVENT = NULL, RESPONSE = NULL)
  for (choices in list(both, neither)) {
    env <- rf_env(vp_data())
    expect_error(rf_run("vp", "fit", vp_data_labels, env, choices), "either TIME and EVENT")
  }
})

test_that("vp-fit screens a 0/1 RESPONSE as classification", {
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  choices <- vp_outcome(vp_choices, TIME = NULL, EVENT = NULL, RESPONSE = "event")
  env <- rf_env(vp_data())
  rf_run("vp", "fit", vp_data_labels, env, choices)
  expect_identical(env$.family, "classification")
  expect_true(is.factor(env$d$event))
  expect_identical(env$.analysis$outcome$kind, "classification")
})

test_that("vp-fit drops incomplete patients before the fit, and counts them", {
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  data <- vp_data()
  data$x1[1:7] <- NA
  env <- rf_env(data)
  rf_run("vp", "fit", vp_data_labels, env, vp_choices)
  expect_identical(nrow(env$d), 193L)
  expect_identical(env$.cohort$n, 193L)
  expect_match(utils::tail(env$.missing_values$Missing, 1L), "7 dropped")
})

test_that("vp-fit refuses a candidate whose name could be taken for noise", {
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  data <- vp_data()
  data$noisy <- data$x1
  choices <- utils::modifyList(vp_choices, list(PREDICTORS = c("xs", "noisy")))
  env <- rf_env(data)
  expect_error(rf_run("vp", "fit", c(vp_data_labels, "noise"), env, choices), "start with \"noise\"")
})
```

- [ ] **Step 4: Run them to see them fail**

Run: `R_LIBS="$VP_LIB" Rscript -e 'devtools::test(filter = "vp-templates")'`
Expected: FAIL, `template_path("vp", "fit")` finds no file.

- [ ] **Step 5: Create the template**

Create `inst/templates/30_analyses/vp-fit.qmd`:

````markdown
---
title: "VarPro: fit"
date: now
date-format: "YYYY-MM-DD HH:mm"
# Carried in the file rather than inherited from _quarto.yml. A file meant to be
# COPIED should not depend on settings from the directory it happens to sit in:
# rendered as a standalone document the project's format block never applies,
# which is how server-rendered reports end up with sibling _files/ trees instead
# of being self-contained.
#
# NOTE: output-dir is a PROJECT setting and cannot be set here, so the .html
# lands next to its source. With embed-resources that is a single standalone
# file, which is the property that actually matters when a report is sent on.
format:
  html:
    fig-width: 6
    fig-height: 4
    theme: cosmo
    toc: true
    toc-location: left
    page-layout: full
    grid:
      body-width: 2000px
      sidebar-width: 250px
    toc-depth: 3
    code-fold: true
    df-print: default
    embed-resources: true
---

<!-- EDIT: say what this screen is for: which outcome, which candidates, and
     whether its selected set feeds a later model job or stands alone. Replace
     this comment with that text. -->

A `vp-fit` job runs VarPro, a rule-based variable screen, and reports what it
could and could not tell. It needs only the data and an outcome: VarPro grows
its own forests, and no other job in the set has to run first.

The report answers three questions VarPro's own importance plot cannot.
**Was each variable tested?** VarPro's importance z is zero for a variable
tested in fewer than about one tree in ten, so z = 0 means *untested*, not
unimportant. **Does it beat noise?** Permuted copies of real candidates are
added before the fit, and a variable is selected only when it beats every
tested copy of its own kind. **Does the selection hold?** The screen is
refitted on subsamples of the patients and the share of refits selecting each
variable is reported.

The selected set is saved for a later model job. `vp-explain` in this set
draws VarPro's partial dependence for it.

This template is **in flight**: it is built from one study's screen, and a
second study running it through to its stability section is what moves it to
shipped.

<!-- The two values below are written by add_job() from the subject/type it
     was called with, which are also the filename's first two fields. They
     name the SET this job belongs to, and every artifact path in the
     document is computed from them, so no output path below needs editing.

     Do NOT hand-edit these declarations: the render-time guard below checks
     them against this file's own name and stops if they disagree. To put
     this job in a different set, call add_job() again with the new
     subject/type rather than editing this copy in place. -->

```{r}
#| label: setup
#| results: asis
SUBJECT <- "dead"
TYPE    <- "vp"
.in <- knitr::current_input(dir = TRUE)
suppressPackageStartupMessages({
  library(varPro)
  library(ggRandomForests)
  library(hvtiRutilities)
})
# One thread, so a fit reproduces from machine to machine. Left unset,
# randomForestSRC, which varPro grows its forests with, runs on every core its
# OpenMP build can see, and on a multi-core server a varPro result changed with
# the thread count with every seed held fixed.
options(rf.cores = 1L)
# The versions this template was verified against on 2026-10-21. Below them a
# call here can fail or change meaning, and the message would arrive mid-render
# rather than here.
if (utils::packageVersion("varPro") < "3.2.0") {
  stop("This job needs varPro >= 3.2.0; ", utils::packageVersion("varPro"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
if (utils::packageVersion("ggRandomForests") < "4.0.0") {
  stop("This job needs ggRandomForests >= 4.0.0; ", utils::packageVersion("ggRandomForests"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
# Early 4.0.0 builds carry the same version string and lack varpro_coverage(),
# so the floor above cannot tell them apart. Check the function itself.
if (!"varpro_coverage" %in% getNamespaceExports("ggRandomForests")) {
  stop("This job needs a ggRandomForests that exports varpro_coverage() (4.0.0-rc9 or later).\n",
       "Update it, then re-render.", call. = FALSE)
}
# The study root is the nearest directory above this file holding _study.yml,
# so the job renders the same from the Render button, quarto render, or
# render_job(), at any depth, with no path in this document to edit.
# Without the guard in .job_setup(), an unedited job renders green over a
# meaningless analysis. Here that is a screen of the template's placeholder
# outcome and candidates, whose tables look exactly like a result.
# To render a job you have not finished, leave a chunk out with the chunk
# option skip, giving the reason in quotes, or call hvtiRtemplates::stop_here()
# in a chunk to leave out everything below it. A draft lists each one in a
# callout; a final render refuses them, as it refuses an unresolved marker.
# ?stop_here has more.
.job <- hvtiRtemplates:::.job_setup(SUBJECT, TYPE, envir = environment())
.root <- .job$root
set_path <- .job$set_path
.provenance_data <- list()
# Saves a figure as <name>.png, .pdf and .tiff in this set's graphs/ folder (or `kind`'s),
# under the SAVE_FIGURES and FIGURES study choices.
save_figure <- function(plot, name, width = 6, height = 4, kind = "graphs", linked = FALSE) {
  hvtiRtemplates:::.save_figure(plot, set_path(kind, paste0(name, ".png")), width, height,
                                SAVE_FIGURES, FIGURES, linked)
}

# `vp-fit` writes vp.rds and `vp-explain` reads it back, both by set. The write
# is the `save` chunk near the foot of this file.
# The draft banners, if any, and the box under the title, after all the code above.
.job$notice
```

## Study choices

Edit these values for this study before rendering.

```{r}
#| label: edit-study-choices
# EDIT: the registered dataset this job reads ("built" is the study dataset).
DATASET <- "built"

# EDIT: an hvtiRdatabuild analysis set, or NULL to read the whole dataset.
ANALYSIS_SET <- NULL

# EDIT: rows to keep, dplyr::filter() style, or NULL to keep every row:
#   WHERE <- quote(age >= 18)
#   WHERE <- rlang::exprs(age >= 18, hx_chf == 1)
WHERE <- NULL

# EDIT: the patient identifier. Without "ccfid" the job uses MRN, then eMRN;
# name another column, such as "randid", if the study uses one.
ID <- "ccfid"

# EDIT: what makes a row unique; one row per patient unless repeated measures
# add their visit time or date, for example KEY <- c(ID, "iv_echo").
KEY <- ID

# Optional, and needs no edit: NULL reads the cohort alone. To join one
# registered ancillary dataset (echoes, labs), name it in JOIN. The cohort
# above decides the patients, one row each; the joined records of other
# patients are dropped and counted in the data table.
#   JOIN_VARS: the cohort columns each joined row carries; NULL carries all,
#     and a column both datasets have stops, so list only those the job needs.
#   REDUCE: NULL keeps a row per joined record, keyed on that dataset's key;
#     list(rule = "first", by = "echo_date") keeps one row per patient ("last",
#     or "nearest" with to = a cohort date column). A tie stops: picking one
#     record silently would be a hidden choice. This job screens one row per
#     patient, so a JOIN without REDUCE stops here.
#   JOIN_KEY: overrides the joined dataset's registered key.
JOIN <- NULL
JOIN_VARS <- NULL
REDUCE <- NULL
JOIN_KEY <- NULL

# EDIT: the outcome, named one of two ways.
#   A survival screen names TIME and EVENT (coded 1 = event, 0 = censored)
#   and leaves RESPONSE NULL.
#   A classification or regression screen sets TIME and EVENT to NULL and
#   names RESPONSE. A factor, text or 0/1 column screens as classification;
#   any other number as regression.
TIME     <- "iv_dead"
EVENT    <- "dead"
RESPONSE <- NULL

# EDIT: the candidate predictors. Name them rather than taking every column: a
# built dataset carries identifiers, dates and derived outcomes, and a screen
# will select a date that quietly encodes follow-up.
PREDICTORS <- c("age", "female", "hx_chf")

# EDIT: how many permuted noise columns to add, split evenly between
# categorical and continuous candidates. A variable is selected only when it
# beats every TESTED noise column of its kind, so too few columns make a
# lenient bar. 20 is what the Virtual Twins screen used.
NOISE_N <- 20

# EDIT: the share of trees a variable must be scored in to count as tested.
# 0.1 matches varPro's own trimming: below it, z is 0 by construction.
TRIM <- 0.1

# EDIT: varPro's forest. NVAR caps how many variables get release rules, and
# counts the noise columns too; with SPLIT_WEIGHT = TRUE a guided first forest
# picks them, and the rest are cut before any rule is built (104 of 154 terms
# in the Virtual Twins screen). Those cut variables show as not eligible below,
# which is not evidence of no effect. To give every candidate rules, set NVAR
# to at least length(PREDICTORS) + NOISE_N and SPLIT_WEIGHT to FALSE.
NTREE <- 500
NVAR <- 30
SPLIT_WEIGHT <- TRUE

# EDIT: the stability check. REPEATS refits, each on SUBSAMPLE of the patients
# drawn without replacement and with a fresh noise draw. 0 skips it; it costs
# REPEATS times one fit.
REPEATS <- 20
SUBSAMPLE <- 0.632

# EDIT: the seed. It is part of every cache key, seeds R's generator before
# each random step, and is handed to varpro() as `seed =`, negated as
# randomForestSRC documents. Both halves matter: varpro() draws from R's
# generator as well as from its own seed.
SEED <- 2026

# Set TRUE after changing a choice above. A cache whose inputs changed stops the
# render instead of returning the old result; TRUE recomputes only the caches
# that are out of date.
REFIT <- FALSE

# Each figure is saved to graphs/ as a PNG (for Word), and a PDF and a TIFF (for the publisher).
# SAVE_FIGURES <- FALSE saves none; FIGURES keeps only the figures whose names
# start with one of its entries, e.g. FIGURES <- c("vp-fit-coverage"). The names are the
# file names, listed for each template in the templates README.
SAVE_FIGURES <- TRUE
FIGURES <- NULL
```

## Cohort

```{r}
#| label: tbl-data
#| tbl-cap: "The data this job read"
# The checksum of every dataset in manifest.yaml is checked before anything is
# read, so a result can name the data that produced it. It stops on a mismatch.
hvtiRutilities::verify_manifest(file.path(.root, "manifest.yaml"))
.cfg <- study_config(start = .root)
job_data <- hvtiRtemplates::read_job_data(.cfg, dataset = DATASET, analysis_set = ANALYSIS_SET,
                                          where = WHERE, id = ID, key = KEY, join = JOIN, join_vars = JOIN_VARS,
                                          reduce = REDUCE, join_key = JOIN_KEY, one_row_per_patient = TRUE)
d <- job_data$data
.provenance_data <- c(if (exists(".provenance_data")) .provenance_data else list(), list(job_data$provenance),
                      if (!is.null(job_data$provenance_join)) list(job_data$provenance_join))
knitr::kable(job_data$record, col.names = c("Data", ""))
# One outcome, named one way. A screen given both would have to guess which
# question it was asked.
.survival <- !is.null(TIME) && !is.null(EVENT) && is.null(RESPONSE)
if (!.survival && !(is.null(TIME) && is.null(EVENT) && !is.null(RESPONSE))) {
  stop("Name either TIME and EVENT (a survival screen) or RESPONSE (classification or regression), ",
       "not both and not neither.", call. = FALSE)
}
.outcome <- c(TIME, EVENT, RESPONSE)
.outcomes <- intersect(.outcome, PREDICTORS)
if (length(.outcomes)) {
  stop("Do not include outcome variable(s) in PREDICTORS: ", paste(.outcomes, collapse = ", "), ".", call. = FALSE)
}
.duplicated <- unique(PREDICTORS[duplicated(PREDICTORS)])
if (length(.duplicated)) {
  stop("PREDICTORS names a variable more than once: ", paste(.duplicated, collapse = ", "), ".", call. = FALSE)
}
# A screen must not be handed an identifier. It would select who a patient is,
# not what is true of them, and the saved fit keeps its data, so the
# identifier would be written into vp.rds.
.selection <- attr(job_data$record, "selection")
.identifiers <- PREDICTORS[tolower(PREDICTORS) %in% tolower(c(.selection$id, .selection$key))]
if (length(.identifiers)) {
  stop("Do not include the patient identifier or a KEY column in PREDICTORS: ",
       paste(.identifiers, collapse = ", "), ".", call. = FALSE)
}
if (any(tolower(.outcome) == tolower(.selection$id))) {
  stop("The patient identifier (", .selection$id, ") cannot be an outcome of this job.", call. = FALSE)
}
.missing <- setdiff(c(.outcome, PREDICTORS), names(d))
if (length(.missing)) {
  stop("Not in the data this job read: ", paste(.missing, collapse = ", "), call. = FALSE)
}
d <- d[, c(.outcome, PREDICTORS), drop = FALSE]

# A screen cannot learn from a patient with no outcome.
.no_outcome <- Reduce(`|`, lapply(d[.outcome], is.na))
if (any(.no_outcome)) {
  stop(sum(.no_outcome), " patient(s) have no outcome. Resolve them in the dataset build; the screen will not.",
       call. = FALSE)
}
if (.survival) {
  # randomForestSRC reads a status above 1 as a competing event, so a 1/2
  # coding, which survival::Surv() accepts, would screen a competing-risks
  # outcome without a word. Refuse it here instead.
  if (!all(d[[EVENT]] %in% c(0, 1))) {
    stop(EVENT, " must be coded 0 and 1 (1 = event); found ",
         paste(sort(unique(d[[EVENT]])), collapse = ", "), ".", call. = FALSE)
  }
  .family <- "survival"
} else {
  .y <- d[[RESPONSE]]
  if (is.character(.y) || is.logical(.y) || is.factor(.y) || (is.numeric(.y) && all(.y %in% c(0, 1)))) {
    # varPro screens a factor outcome as classification and a number as
    # regression, so a 0/1 outcome left numeric would be screened as a
    # continuous one. It is converted here, and the report says so.
    if (!is.factor(.y)) {
      d[[RESPONSE]] <- factor(.y)
      cat(RESPONSE, "converted to a factor: screened as classification.\n")
    }
    .family <- "classification"
  } else if (is.numeric(.y)) {
    .family <- "regression"
  } else {
    stop(RESPONSE, " is neither a number, text nor a factor, so it cannot be screened.", call. = FALSE)
  }
}
.analysis <- if (.survival) {
  list(time = list(variable = TIME), event = list(variable = EVENT, event = 1L, censored = 0L))
} else {
  list(outcome = list(variable = RESPONSE, kind = if (.family == "classification") "classification" else "continuous"))
}

# A forest splits a text column only as a factor, so text predictors are
# converted here, and named, rather than left for the fit to refuse or coerce.
.chr <- PREDICTORS[vapply(d[PREDICTORS], is.character, logical(1L))]
if (length(.chr)) {
  d[.chr] <- lapply(d[.chr], factor)
  cat("Text predictors converted to factors: ", paste(.chr, collapse = ", "), "\n", sep = "")
}
```

```{r}
#| label: data-attrition
#| results: asis
# unnumbered: its child chunk carries its own label and caption
if (!is.null(job_data$attrition)) {
  .fence <- strrep("`", 3)
  cat(knitr::knit_child(text = c(
    paste0(.fence, "{r}"), "#| label: tbl-data-attrition",
    paste0("#| tbl-cap: ", encodeString(paste0("Analysis set `", ANALYSIS_SET, "`: exclusions, in order"), quote = "\"")),
    "knitr::kable(job_data$attrition)", .fence
  ), envir = environment(), quiet = TRUE), sep = "\n")
}
```

```{r}
#| label: tbl-missing
#| tbl-cap: "Missing values in the screen's variables"
# varpro() drops every patient with a missing value, so the screen would
# describe fewer patients than this report claims. They are dropped here
# instead, and counted, before the fit sees the data.
.empty <- PREDICTORS[vapply(d[PREDICTORS], function(x) all(is.na(x)), logical(1L))]
if (length(.empty)) {
  stop("PREDICTORS names a column with no values: ", paste(.empty, collapse = ", "),
       ". Remove it from PREDICTORS.", call. = FALSE)
}
.missing_values <- hvtiRtemplates:::.missing_cases(d, TIME = TIME, EVENT = EVENT, RESPONSE = RESPONSE,
                                                   PREDICTORS = PREDICTORS, action = "drop")
d <- d[stats::complete.cases(d), , drop = FALSE]
.cohort <- list(n = as.integer(nrow(d)))
if (.survival) {
  .cohort$n_events <- as.integer(sum(d[[EVENT]] == 1))
  .cohort$n_censored <- as.integer(sum(d[[EVENT]] == 0))
}
knitr::kable(.missing_values)
```

## Noise

```{r}
#| label: noise
# Each noise column is a permuted copy of a real candidate: it keeps that
# candidate's values and loses any link to the outcome, so whatever importance
# it earns is what chance alone earns. Half the copies come from categorical
# candidates and half from continuous ones, as far as each kind allows,
# because a variable is judged against noise of its own kind.
#
# The kind rule is varpro_coverage()'s: a factor, text or logical column, or a
# number with at most 5 distinct values, is categorical.
vp_kind <- function(x) {
  if (is.factor(x) || is.character(x) || is.logical(x) || length(unique(stats::na.omit(x))) <= 5L) {
    "categorical"
  } else {
    "continuous"
  }
}
vp_add_noise <- function(d, predictors, n, seed) {
  kinds <- vapply(d[predictors], vp_kind, "")
  pools <- split(predictors, kinds)
  n_cat <- if (length(pools$categorical) && length(pools$continuous)) {
    n %/% 2L
  } else if (length(pools$categorical)) {
    n
  } else {
    0L
  }
  draw <- function(pool, k) if (k == 0L) character() else pool[sample.int(length(pool), k, replace = k > length(pool))]
  set.seed(abs(seed))
  src <- c(draw(pools$categorical, n_cat), draw(pools$continuous, n - n_cat))
  for (i in seq_along(src)) {
    set.seed(abs(seed) + i)
    d[[paste0("noise", i, "_", src[i])]] <- sample(d[[src[i]]])
  }
  d
}
if (NOISE_N < 1) {
  stop("NOISE_N must be at least 1: the selection rule needs noise to beat.", call. = FALSE)
}
# The coverage table finds noise by the "noise" prefix, so a real candidate
# named that way would be judged as noise.
.noisy <- grep("^noise", PREDICTORS, value = TRUE)
if (length(.noisy)) {
  stop("Candidate(s) whose names start with \"noise\", which this job reserves for its noise columns: ",
       paste(.noisy, collapse = ", "), ". Rename them in the dataset build.", call. = FALSE)
}
d_noise <- vp_add_noise(d, PREDICTORS, NOISE_N, SEED)
model <- if (.survival) {
  stats::as.formula(paste0("Surv(", TIME, ", ", EVENT, ") ~ ."))
} else {
  stats::as.formula(paste0(RESPONSE, " ~ ."))
}
# The saved fit keeps this formula, and a formula keeps the environment it was
# made in; set it, so a job run anywhere else does not write every object
# beside the formula, `job_data` and its patient IDs included, into vp.rds.
environment(model) <- globalenv()
```

```{r}
#| label: provenance
#| echo: false
#| results: asis
cat(hvtiRtemplates:::.embed_provenance(
  .in,
  data = .provenance_data,
  run = .job$run,
  extra = list(subject = SUBJECT, type = TYPE, analysis = .analysis, cohort = .cohort)
))
```
````

- [ ] **Step 6: `.lintr` key and catalog flip**

In `.lintr`, after the `"inst/templates/30_analyses/rfr-explain.qmd" = list(...)` entry, add:

```r
    "inst/templates/30_analyses/vp-fit.qmd" = list(
      object_name_linter = Inf,
      commented_code_linter = Inf,
      object_usage_linter = Inf
    ),
```

In `inst/extdata/templates.json`, on the `vp`/`fit` row set `"status": "in-flight"`, `"blocked_on": null`, and `"note"` to:

```
"Released for review in a real study. Built from Virtual Twins notebook ch13 and report Appendix C; other studies run varPro, and Virtual Twins is the first to reach the coverage, noise and stability stage. Becomes shipped once a second study runs vp-fit through its stability section."
```

Then `python3 dev/specs/artifacts/roadmap_render.py`.

- [ ] **Step 7: Run the vp tests and the catalog-wide template tests**

Run: `R_LIBS="$VP_LIB" Rscript -e 'devtools::test(filter = "vp-templates|templates$|template-|taxonomy|roadmap|add-job")'`
Expected: the five vp tests PASS; 0 failures elsewhere. The catalog-wide tests this file must satisfy include "every template declares SUBJECT and TYPE markers", "a chunk is labeled edit- exactly when it holds an EDIT marker", "every shipped template ends with one embedded provenance chunk", "every template that reads its own data offers the join and records the joined data", "DESCRIPTION's Suggests bounds match what the templates enforce" and "every template is free of study identifiers". A failure there names the rule; fix the template, not the test.

- [ ] **Step 8: Count guards and lint**

```bash
python3 dev/specs/artifacts/check-roadmap-counts.py && python3 dev/specs/artifacts/check-spec-counts.py
Rscript -e 'lintr::lint("tests/testthat/helper-vp.R"); lintr::lint("tests/testthat/test-vp-templates.R"); lintr::lint("inst/templates/30_analyses/vp-fit.qmd")'
```

Expected: `... 37 on disk.`; no lints.

- [ ] **Step 9: Commit**

```bash
git add inst/templates/30_analyses/vp-fit.qmd tests/testthat/helper-vp.R tests/testthat/test-vp-templates.R .lintr inst/extdata/templates.json dev/specs/2026-08-29-template-conversion-roadmap.md
git commit -m "feat(vp-fit): read the cohort and add noise of each kind

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `vp-fit.qmd`, fit, judge and coverage

**Files:**
- Modify: `inst/templates/30_analyses/vp-fit.qmd` (insert after the `noise` chunk, before `provenance`)
- Modify: `tests/testthat/helper-vp.R` (`vp_fit_labels`)
- Modify: `tests/testthat/test-vp-templates.R`

**Interfaces:**
- Consumes: `d_noise`, `model`, `NTREE`, `NVAR`, `SPLIT_WEIGHT`, `TRIM`, `SEED`, `REFIT` from Task 3.
- Produces: `CACHE_DIR`; `fit` (a `varpro` object); `vp_judge(cov)`, taking a data frame with columns `variable`, `kind`, `noise`, `tested`, `z` and returning it with `bar` (numeric), `bar_from` (`"categorical"`, `"continuous"`, `"continuous (fallback)"` or `"no noise tested"`) and `selected` (logical, never `NA`); `cov` (the judged `varpro_coverage(by = "variable")` table); `.real` (`cov` without noise rows).

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-vp-templates.R`:

```r
# vp_judge() on hand-built tables: no fit, so these run on CRAN too.
vp_judge_fn <- function() {
  env <- new.env(parent = globalenv())
  eval(parse(text = rf_chunk(readLines(template_path("vp", "fit"), warn = FALSE), "judge")), envir = env)
  env$vp_judge
}
vp_cov <- function(variable, kind, noise, tested, z) {
  data.frame(variable = variable, kind = kind, noise = noise, tested = tested, z = z)
}

test_that("vp_judge falls back to the continuous bar when tested categorical noise all scores zero", {
  cov <- vp_cov(
    variable = c("x_real", "f_null", "noise1_x", "noise2_f", "noise3_f"),
    kind = c("continuous", "categorical", "continuous", "categorical", "categorical"),
    noise = c(FALSE, FALSE, TRUE, TRUE, TRUE),
    tested = c(TRUE, TRUE, TRUE, TRUE, FALSE),
    z = c(0.9, 0.2, 0.3, 0, NA)
  )
  out <- vp_judge_fn()(cov)
  expect_identical(out$selected, c(TRUE, FALSE, FALSE, FALSE, FALSE))
  expect_identical(out$bar[out$variable == "f_null"], 0.3)
  expect_identical(out$bar_from[out$variable == "f_null"], "continuous (fallback)")
})

test_that("vp_judge keeps a categorical bar that tested noise set above zero", {
  cov <- vp_cov(
    variable = c("f_real", "f_null", "noise1_x", "noise2_f"),
    kind = c("categorical", "categorical", "continuous", "categorical"),
    noise = c(FALSE, FALSE, TRUE, TRUE),
    tested = c(TRUE, TRUE, TRUE, TRUE),
    z = c(0.5, 0.2, 0.9, 0.25)
  )
  out <- vp_judge_fn()(cov)
  expect_identical(out$selected, c(TRUE, FALSE, FALSE, FALSE))
  expect_identical(unique(out$bar[out$kind == "categorical"]), 0.25)
  expect_identical(unique(out$bar_from[out$kind == "categorical"]), "categorical")
})

test_that("vp_judge selects nothing when no noise was tested, and says so", {
  cov <- vp_cov(
    variable = c("x_real", "noise1_x"), kind = c("continuous", "continuous"),
    noise = c(FALSE, TRUE), tested = c(TRUE, FALSE), z = c(2, NA)
  )
  out <- vp_judge_fn()(cov)
  expect_identical(out$selected, c(FALSE, FALSE))
  expect_identical(out$bar_from, c("no noise tested", "no noise tested"))
})

test_that("vp-fit selects a planted signal", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  env <- vp_fit_first()
  real <- env$.real[env$.real$tested, ]
  expect_true(all(c("xs", "fs") %in% env$.real$variable[env$.real$selected]))
  expect_setequal(utils::head(real$variable[order(-real$z)], 2L), c("xs", "fs"))
  # Every noise column reached the coverage table, so the bars rest on all of them.
  expect_identical(sum(env$cov$noise), 20L)
})
```

In `tests/testthat/helper-vp.R`, extend `vp_fit_labels`:

```r
vp_fit_labels <- c("setup", "edit-study-choices", "tbl-data", "tbl-missing", "noise", "judge", "fit",
                   "tbl-coverage", "tbl-funnel", "fig-coverage", "fig-varpro")
```

- [ ] **Step 2: Run them to see them fail**

Run: `R_LIBS="$VP_LIB" Rscript -e 'devtools::test(filter = "vp-templates")'`
Expected: FAIL, `chunk 'judge' found 0 times`.

- [ ] **Step 3: Insert the chunks**

In `vp-fit.qmd`, between the `noise` chunk and the `provenance` chunk, insert:

````markdown
## Fit

```{r}
#| label: judge
# The selection rule. A real variable is selected when it is tested and its z
# beats every TESTED noise column of its kind. varPro's own cutoff (z > 0.79)
# does not carry from one fit to another, because z shrinks as more variables
# share each tree; noise in the same fit shrinks with it.
#
# The categorical bar needs care. Categorical noise is rarely tested, and when
# it is it almost always scores z = 0 (in the Virtual Twins repeats: none
# tested in 20 of 40, all zero in 18). A bar of 0 lets any tested categorical
# variable through, so a categorical bar of 0, or one with no categorical
# noise tested, is replaced by the continuous bar. The continuous bar is the
# stricter one, since continuous noise picks up split-point bias, so the rule
# errs toward missing a real categorical effect rather than admitting a false
# one. The table names the bar each variable was judged against.
vp_judge <- function(cov) {
  noise <- cov$noise & cov$tested
  bar_of <- function(k) {
    z <- cov$z[noise & cov$kind == k]
    if (length(z)) max(z) else NA_real_
  }
  bar_cont <- bar_of("continuous")
  bar_cat <- bar_of("categorical")
  if (is.na(bar_cont) && any(noise)) bar_cont <- max(cov$z[noise])
  fallback <- is.na(bar_cat) || bar_cat <= 0
  if (fallback) bar_cat <- bar_cont
  cov$bar <- ifelse(cov$kind == "categorical", bar_cat, bar_cont)
  cov$bar_from <- ifelse(cov$kind == "categorical", if (fallback) "continuous (fallback)" else "categorical", "continuous")
  cov$bar_from[is.na(cov$bar)] <- "no noise tested"
  cov$selected <- !cov$noise & cov$tested & (cov$z > cov$bar) %in% TRUE
  cov
}
```

```{r}
#| label: fit
#| message: true
# cache_fit() writes <dir>/<name>.rds and its default dir is the study's
# estimates folder, not this set's, so every call here names the set's.
CACHE_DIR <- dirname(set_path("estimates", "vp.rds"))
fit <- cache_fit(
  "vp-fit",
  varpro(model, d_noise, ntree = NTREE, nvar = NVAR, split.weight = SPLIT_WEIGHT, verbose = FALSE, seed = -abs(SEED)),
  seed = SEED, dir = CACHE_DIR, refit = REFIT
)
```

## Coverage

Every candidate, and whether VarPro could test it. A variable is **eligible**
when VarPro built release rules for it; one that is not was cut by the split
weights or `NVAR` before any rule was built. It is **tested** when it was
scored in at least `TRIM` of the trees; below that its z is 0 by construction,
which is no evidence of no effect. It is **selected** when it is tested and its
z beats the bar named in the last columns.

```{r}
#| label: tbl-coverage
#| tbl-cap: "Coverage, importance and selection of each candidate, most covered first"
# varpro_coverage() samples release rules, so it is seeded too.
set.seed(abs(SEED))
cov <- vp_judge(ggRandomForests::varpro_coverage(fit, by = "variable", trim = TRIM, noise = "^noise"))
.real <- cov[!cov$noise, ]
knitr::kable(data.frame(
  variable = .real$variable, kind = .real$kind, eligible = .real$eligible, trees = .real$n_trees,
  coverage = round(.real$coverage, 3), z = round(.real$z, 3), tested = .real$tested,
  bar = round(.real$bar, 3), judged_against = .real$bar_from, selected = .real$selected
))
```

```{r}
#| label: tbl-funnel
#| tbl-cap: "How the candidates become the selected set"
# A candidate varPro dropped from its data altogether, a constant column say,
# is counted as a candidate and nothing more.
knitr::kable(data.frame(
  step = c("Candidates", "Eligible", "Tested", "Selected"),
  variables = c(length(PREDICTORS), sum(.real$eligible), sum(.real$tested), sum(.real$selected))
))
```

```{r}
#| label: fig-coverage
#| fig-cap: "Importance against coverage for every eligible variable, one panel per kind. Black points are real
#|   candidates and gray points permuted noise; the dashed horizontal line is the bar a real variable must beat and the
#|   dotted vertical line the coverage below which a variable is untested."
#| fig-width: 8
.plot_cov <- cov[cov$eligible & !is.na(cov$z), ]
.plot_cov$source <- ifelse(.plot_cov$noise, "noise", "real")
.bars <- unique(.plot_cov[!is.na(.plot_cov$bar), c("kind", "bar")])
.fig <- ggplot2::ggplot(.plot_cov, ggplot2::aes(x = coverage, y = z, colour = source)) +
  ggplot2::geom_point() +
  ggplot2::geom_hline(data = .bars, ggplot2::aes(yintercept = bar), linetype = "dashed") +
  ggplot2::geom_vline(xintercept = TRIM, linetype = "dotted") +
  ggplot2::facet_wrap(~kind) +
  ggplot2::scale_colour_manual(values = c(noise = "gray60", real = "black")) +
  ggplot2::labs(x = "Coverage (share of trees scored)", y = "Importance (z)") +
  hvtiPlotR::theme_hv_manuscript(base_size = 12)
save_figure(.fig, "vp-fit-coverage", width = 8)
.fig
```

```{r}
#| label: fig-varpro
#| fig-cap: "VarPro's own importance plot, noise columns included. Each box spans the 15th to the 85th percentile of a
#|   variable's per-tree importance, with a line at the median and whiskers to the 5th and 95th percentiles; the dashed
#|   red line is varPro's default cutoff, which is not the selection rule in this report."
#| fig-height: 7
# Free size: one row per variable, so the height grows with the list.
.fig <- plot(gg_varpro(fit)) + hvtiPlotR::theme_hv_manuscript(base_size = 12)
save_figure(.fig, "vp-fit-varpro", height = 7)
.fig
```
````

- [ ] **Step 4: Run the tests**

Run: `R_LIBS="$VP_LIB" NOT_CRAN=true Rscript -e 'devtools::test(filter = "vp-templates")'`
Expected: all PASS. If "vp-fit selects a planted signal" fails because `fs` or `xs` is untested at `NTREE = 50`, raise `vp_choices$NTREE` to 100 and record the reason in a comment beside it. Do not weaken the assertion.

- [ ] **Step 5: Prove the fallback test by mutation**

In the `judge` chunk, change `fallback <- is.na(bar_cat) || bar_cat <= 0` to `fallback <- is.na(bar_cat)`, run `R_LIBS="$VP_LIB" Rscript -e 'devtools::test(filter = "vp-templates")'` and confirm "vp_judge falls back to the continuous bar…" FAILS. Restore the line and confirm it passes again.

- [ ] **Step 6: Commit**

```bash
git add inst/templates/30_analyses/vp-fit.qmd tests/testthat/helper-vp.R tests/testthat/test-vp-templates.R
git commit -m "feat(vp-fit): judge coverage against noise of each kind

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: `vp-fit.qmd`, stability, reading and the handoff

**Files:**
- Modify: `inst/templates/30_analyses/vp-fit.qmd` (insert after `fig-varpro`, before `provenance`)
- Modify: `tests/testthat/helper-vp.R` (`vp_fit_labels`)
- Modify: `tests/testthat/test-vp-templates.R`

**Interfaces:**
- Consumes: `d`, `PREDICTORS`, `NOISE_N`, `vp_add_noise()`, `vp_judge()`, `model`, `CACHE_DIR`, `cov`, `.real`, `.family`, `.analysis`, `.cohort`, `job_data` from Tasks 3–4.
- Produces: `.stab` (data frame `r`, `variable`, `selected`, `tested`; zero rows when `REPEATS` is 0); cache files `vp-repeat-<NN>.rds`; `estimates/<subject>-<type>/vp.rds` holding `list(fit, coverage, selected, family)` with attribute `hvti_provenance`. Task 6 reads `vp.rds` by those names.

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-vp-templates.R`:

```r
test_that("vp-fit saves one handoff: the fit, its judged coverage, the selection and the family", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  env <- vp_fit_first()
  h <- readRDS(env$set_path("estimates", "vp.rds"))
  expect_named(h, c("fit", "coverage", "selected", "family"))
  expect_identical(h$selected, env$.real$variable[env$.real$selected])
  expect_identical(h$family, "survival")
  expect_s3_class(h$fit, "varpro")
  expect_false(is.null(attr(h, "hvti_provenance")))
  expect_setequal(unique(env$.stab$r), 1:2)
})

test_that("raising REPEATS computes only the new repeat", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  env <- vp_fit_first()
  first <- file.path(env$CACHE_DIR, "vp-repeat-01.rds")
  stamp <- file.mtime(first)
  expect_false(file.exists(file.path(env$CACHE_DIR, "vp-repeat-03.rds")))
  Sys.sleep(1.1)  # so a rewrite would show in the modification time
  again <- new.env(parent = globalenv())
  again$.root <- env$.root
  again$.provenance_data <- list()
  rf_run("vp", "fit", vp_fit_labels, again, utils::modifyList(vp_choices, list(REPEATS = 3)))
  expect_identical(file.mtime(first), stamp)
  expect_true(file.exists(file.path(env$CACHE_DIR, "vp-repeat-03.rds")))
  expect_setequal(unique(again$.stab$r), 1:3)
})

test_that("REPEATS = 0 skips the stability check", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  env <- vp_fit_first(choices = utils::modifyList(vp_choices, list(REPEATS = 0)))
  expect_identical(nrow(env$.stab), 0L)
  expect_false(any(grepl("^vp-repeat-", list.files(env$CACHE_DIR))))
})
```

In `tests/testthat/helper-vp.R`, extend `vp_fit_labels`:

```r
vp_fit_labels <- c("setup", "edit-study-choices", "tbl-data", "tbl-missing", "noise", "judge", "fit",
                   "tbl-coverage", "tbl-funnel", "fig-coverage", "fig-varpro", "tbl-stability", "save")
```

- [ ] **Step 2: Run them to see them fail**

Run: `R_LIBS="$VP_LIB" NOT_CRAN=true Rscript -e 'devtools::test(filter = "vp-templates")'`
Expected: FAIL, `chunk 'tbl-stability' found 0 times`.

- [ ] **Step 3: Insert the chunks**

In `vp-fit.qmd`, between `fig-varpro` and `provenance`, insert:

````markdown
## Stability

The screen refitted `REPEATS` times, each on a subsample of the patients drawn
without replacement and with a fresh noise draw. A variable selected in most
refits holds up; one selected once in a while is the screen's own noise.

```{r}
#| label: tbl-stability
#| tbl-cap: "How often each candidate was tested and selected across the refits"
#| message: true
# Each refit is cached on its own, so raising REPEATS computes only the new
# ones. Redrawing the noise alone would hold the patients fixed and understate
# how much the selection moves, so each refit also draws its patients.
.stab <- data.frame(r = integer(), variable = character(), selected = logical(), tested = logical())
if (REPEATS > 0) {
  .stab <- do.call(rbind, lapply(seq_len(REPEATS), function(r) {
    set.seed(abs(SEED) + r)
    rows <- sort(sample.int(nrow(d), floor(SUBSAMPLE * nrow(d))))
    dr <- vp_add_noise(d[rows, , drop = FALSE], PREDICTORS, NOISE_N, SEED + r)
    fr <- cache_fit(
      sprintf("vp-repeat-%02d", r),
      varpro(model, dr, ntree = NTREE, nvar = NVAR, split.weight = SPLIT_WEIGHT, verbose = FALSE, seed = -abs(SEED + r)),
      seed = SEED + r, dir = CACHE_DIR, refit = REFIT
    )
    set.seed(abs(SEED) + r)
    cr <- vp_judge(ggRandomForests::varpro_coverage(fr, by = "variable", trim = TRIM, noise = "^noise"))
    cr <- cr[!cr$noise, ]
    data.frame(r = r, variable = cr$variable, selected = cr$selected, tested = cr$tested)
  }))
  .per <- tapply(.stab$selected, .stab$r, sum)
  cat("Selected per refit: ", min(.per), " to ", max(.per), " variables.\n", sep = "")
  .freq <- stats::aggregate(cbind(share_tested = tested, share_selected = selected) ~ variable, data = .stab, FUN = mean)
  .freq <- .freq[order(-.freq$share_selected, -.freq$share_tested), ]
  knitr::kable(.freq, digits = 2, row.names = FALSE)
} else {
  cat("Skipped: REPEATS is 0.\n")
}
```

## Reading the result

**Untested is not unimportant.** VarPro scores a variable by a trimmed mean of
its importance in each tree, and a tree with no usable rule for the variable
counts as zero. A variable tested in fewer than `TRIM` of the trees therefore
scores exactly 0. A variable that is not eligible was never tested at all.
Neither is evidence of no effect; the variable simply was not examined.

**Selected means it beat chance in this fit.** The bar is the best score any
tested noise column of the same kind reached. A categorical variable is held
to the continuous bar whenever categorical noise sets no bar of its own, which
makes the rule strict for categorical variables.

**This is a screen, not a selection.** It keeps everything it could not rule
out, and its settings matter: guided split weights and `NVAR` decide which
variables are examined at all. A selection would also need the unguided screen
(`SPLIT_WEIGHT <- FALSE`), the stability above, and ideally cross-validation
to agree. Read the stability table before the coverage table: a variable
selected in the full fit but rarely in the refits is a weak candidate.

```{r}
#| label: save
# The product of this job, and what vp-explain reads: the fit, its judged
# coverage and the selected set, in one file, so they cannot drift apart. It is
# separate from the cache on purpose: cache_fit() stores a keyed record, so the
# cache is this job's internals and this file is its interface.
vp_handoff <- hvtiRtemplates:::.attach_handoff_lineage(
  list(fit = fit, coverage = cov, selected = .real$variable[.real$selected], family = .family),
  data = .provenance_data,
  analysis = .analysis,
  cohort = .cohort,
  # vp-explain takes the rows, ID and KEY of this screen from this record.
  selection = attr(job_data$record, "selection")
)
saveRDS(vp_handoff, set_path("estimates", "vp.rds"))
```
````

- [ ] **Step 4: Run the tests**

Run: `R_LIBS="$VP_LIB" NOT_CRAN=true Rscript -e 'devtools::test(filter = "vp-templates")'`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add inst/templates/30_analyses/vp-fit.qmd tests/testthat/helper-vp.R tests/testthat/test-vp-templates.R
git commit -m "feat(vp-fit): check the selection across subsamples and save vp.rds

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `vp-explain.qmd`

**Files:**
- Create: `inst/templates/30_analyses/vp-explain.qmd`
- Modify: `.lintr` (file key after `vp-fit.qmd`'s)
- Modify: `inst/extdata/templates.json` (`vp`/`explain` row → `in-flight`), roadmap doc (script)
- Modify: `tests/testthat/test-vp-templates.R`

**Interfaces:**
- Consumes: `estimates/<subject>-<type>/vp.rds` from Task 5 (`$fit`, `$coverage`, `$selected`, `$family`); `rf_gg_partial_varpro`, which `rf_run()` swaps in before a chunk labeled `dependence-varpro`.
- Produces: `sel` (variables drawn), `pv` (the `gg_partial_varpro` result), cache `vp-partial.rds`, figures `vp-explain-dependence-varpro-page-<NN>`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/testthat/test-vp-templates.R`:

```r
vp_explain_labels <- c("setup", "edit-study-choices", "screen", "tbl-data", "select", "dependence-varpro")

test_that("no vp-explain line calls varpro()", {
  src <- readLines(template_path("vp", "explain"), warn = FALSE)
  # gg_partial_varpro( is allowed; a bare varpro( fit is not.
  expect_false(any(grepl("(^|[^_[:alnum:]])varpro\\(", src)))
})

test_that("vp-explain stops when no vp-fit has run in its set", {
  rf_skip_unless_stack(rf_template_packages("vp", "explain"))
  env <- rf_env(vp_data())
  expect_error(rf_run("vp", "explain", c("setup", "edit-study-choices", "screen"), env), "Render the vp-fit job")
})

test_that("vp-explain draws the saved selection, tested variables only", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "explain"))
  fit <- vp_fit_first()
  env <- new.env(parent = globalenv())
  env$.root <- fit$.root
  rf_run("vp", "explain", vp_explain_labels, env, list(HORIZON = 1, SEED = 1, SAVE_FIGURES = FALSE))
  h <- readRDS(fit$set_path("estimates", "vp.rds"))
  expect_setequal(env$sel, h$selected)
  expect_true(all(env$sel %in% h$coverage$variable[h$coverage$tested]))
  expect_true(file.exists(file.path(env$CACHE_DIR, "vp-partial.rds")))
})

test_that("vp-explain refuses a horizon past the longest follow-up", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "explain"))
  fit <- vp_fit_first()
  env <- new.env(parent = globalenv())
  env$.root <- fit$.root
  expect_error(rf_run("vp", "explain", vp_explain_labels, env, list(HORIZON = 1e6, SEED = 1, SAVE_FIGURES = FALSE)),
               "longest follow-up")
})
```

- [ ] **Step 2: Run them to see them fail**

Run: `R_LIBS="$VP_LIB" NOT_CRAN=true Rscript -e 'devtools::test(filter = "vp-templates")'`
Expected: FAIL, `template_path("vp", "explain")` finds no file.

- [ ] **Step 3: Create the template**

Create `inst/templates/30_analyses/vp-explain.qmd`:

````markdown
---
title: "VarPro: explain"
date: now
date-format: "YYYY-MM-DD HH:mm"
# Carried in the file rather than inherited from _quarto.yml. A file meant to be
# COPIED should not depend on settings from the directory it happens to sit in:
# rendered as a standalone document the project's format block never applies,
# which is how server-rendered reports end up with sibling _files/ trees instead
# of being self-contained.
#
# NOTE: output-dir is a PROJECT setting and cannot be set here, so the .html
# lands next to its source. With embed-resources that is a single standalone
# file, which is the property that actually matters when a report is sent on.
format:
  html:
    fig-width: 6
    fig-height: 4
    theme: cosmo
    toc: true
    toc-location: left
    page-layout: full
    grid:
      body-width: 2000px
      sidebar-width: 250px
    toc-depth: 3
    code-fold: true
    df-print: default
    embed-resources: true
---

<!-- EDIT: say which vp-fit screen in this set this explains, and what the
     partial dependence plots are meant to show. -->

Draws VarPro's partial dependence for the variables the `vp-fit` job in this
set selected.

A `vp-explain` job never fits VarPro. It reads `vp.rds`, which the fit job
writes, so the plots describe exactly the screen that report judged. A
variable the screen did not test is never drawn: its partial would rest on
almost no rules. The partials are the expensive step and are cached on their
own.

This template is **in flight**, with `vp-fit`.

<!-- The two values below are written by add_job() from the subject/type it
     was called with, which are also the filename's first two fields. They
     name the SET this job belongs to, and every artifact path in the
     document is computed from them, so no output path below needs editing.

     Do NOT hand-edit these declarations: the render-time guard below checks
     them against this file's own name and stops if they disagree. -->

```{r}
#| label: setup
#| results: asis
SUBJECT <- "dead"
TYPE    <- "vp"
.in <- knitr::current_input(dir = TRUE)
suppressPackageStartupMessages({
  library(varPro)
  library(ggRandomForests)
  library(hvtiRutilities)
})
# One thread, so a partial reproduces from machine to machine: each point is a
# prediction from VarPro's forests.
options(rf.cores = 1L)
# The versions this template was verified against on 2026-10-21.
if (utils::packageVersion("varPro") < "3.2.0") {
  stop("This job needs varPro >= 3.2.0; ", utils::packageVersion("varPro"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
if (utils::packageVersion("ggRandomForests") < "4.0.0") {
  stop("This job needs ggRandomForests >= 4.0.0; ", utils::packageVersion("ggRandomForests"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
# The study root is the nearest directory above this file holding _study.yml,
# so the job renders the same from the Render button, quarto render, or
# render_job(), at any depth, with no path in this document to edit.
# Without the guard in .job_setup(), an unedited job renders green over a
# meaningless analysis. Here that is partials at a placeholder survival
# horizon, in units the study's follow-up may not use, which look exactly like
# a result.
# To render a job you have not finished, leave a chunk out with the chunk
# option skip, giving the reason in quotes, or call hvtiRtemplates::stop_here()
# in a chunk to leave out everything below it. ?stop_here has more.
.job <- hvtiRtemplates:::.job_setup(SUBJECT, TYPE, envir = environment())
.root <- .job$root
set_path <- .job$set_path
.provenance_data <- list()
# Saves a figure as <name>.png, .pdf and .tiff in this set's graphs/ folder (or `kind`'s),
# under the SAVE_FIGURES and FIGURES study choices.
save_figure <- function(plot, name, width = 6, height = 4, kind = "graphs", linked = FALSE) {
  hvtiRtemplates:::.save_figure(plot, set_path(kind, paste0(name, ".png")), width, height,
                                SAVE_FIGURES, FIGURES, linked)
}

# `vp-explain` reads the screen `vp-fit` wrote in this same set, and caches its
# own work beside it.
# The draft banners, if any, and the box under the title, after all the code above.
.job$notice
```

## Study choices

Edit these values for this study before rendering. The outcome and candidates
are not here: they come from the screen.

```{r}
#| label: edit-study-choices
# EDIT: the screen's selection is used; set any of these only to confirm it.
# NULL takes the value the fit job used.
WHERE <- NULL
ID <- NULL
KEY <- NULL

# EDIT: or name the variables yourself. NULL takes the screen's selected set.
# A variable the screen did not test is left out either way, and named below.
PARTIAL_VARS <- NULL

# EDIT: for a survival screen, the scale and the horizon of the partials.
# "surv" draws survival at HORIZON; HORIZON is in the units of the fit job's
# time variable, so a screen fit in years takes HORIZON <- 5 for five years and
# one fit in days takes 1826. A horizon past the longest follow-up stops the
# render rather than draw a flat curve. Both are ignored for classification or
# regression.
SCALE <- "surv"
HORIZON <- 5

# EDIT: the seed for the partials. It is part of their cache key.
SEED <- 2026

# Set TRUE after changing a choice above. A cache whose inputs changed stops the
# render instead of returning the old result; TRUE recomputes only the caches
# that are out of date.
REFIT <- FALSE

# Each figure is saved to graphs/ as a PNG (for Word), and a PDF and a TIFF (for the publisher).
# SAVE_FIGURES <- FALSE saves none; FIGURES keeps only the figures whose names
# start with one of its entries, e.g. FIGURES <- c("vp-explain-dependence"). The names are the
# file names, listed for each template in the templates README.
SAVE_FIGURES <- TRUE
FIGURES <- NULL
```

## The screen

```{r}
#| label: screen
.handoff <- set_path("estimates", "vp.rds")
if (!file.exists(.handoff)) {
  stop("No screen at ", .handoff, ". Render the vp-fit job in this set first; ",
       "this job explains that screen and never fits its own.", call. = FALSE)
}
.cfg <- study_config(start = .root)
.vp_read <- hvtiRtemplates:::.read_handoff(.handoff, "screen", .cfg, "the vp-fit job")
fit <- .vp_read$value$fit
cov <- .vp_read$value$coverage
selected <- .vp_read$value$selected
.provenance_data <- .vp_read$lineage$data
.provenance_artifacts <- c(.vp_read$lineage$artifacts, list(.vp_read$record))
CACHE_DIR <- dirname(.handoff)
```

```{r}
#| label: tbl-data
#| tbl-cap: "The data the fit job read"
# This job reads no data: the screen carries its rows. The fit job recorded how
# it chose them, and a setting above that differs from the fit's stops here.
.sel <- hvtiRtemplates:::.read_upstream_job_data(
  .cfg, .vp_read$lineage, list(where = WHERE, id = ID, key = KEY), read = FALSE, source = "vp.rds"
)$selection
knitr::kable(data.frame(step = c("ID", "KEY", "WHERE", "Rows"),
                        value = c(.sel$id, paste(.sel$key, collapse = ", "),
                                  if (length(.sel$where_shown)) paste(.sel$where_shown, collapse = "; ") else "none",
                                  .sel$rows)),
             col.names = c("Data", ""))
```

```{r}
#| label: select
.real <- cov$variable[!cov$noise]
.tested <- cov$variable[!cov$noise & cov$tested]
if (is.null(PARTIAL_VARS)) {
  sel <- selected
} else {
  # A misspelt name would otherwise fail deep inside the partial call.
  .unknown <- setdiff(PARTIAL_VARS, .real)
  if (length(.unknown)) {
    stop("PARTIAL_VARS names variable(s) the screen was not given: ", paste(.unknown, collapse = ", "), call. = FALSE)
  }
  sel <- PARTIAL_VARS
}
.untested <- setdiff(sel, .tested)
if (length(.untested)) {
  cat("Not drawn, because the screen did not test them: ", paste(.untested, collapse = ", "), "\n", sep = "")
  sel <- setdiff(sel, .untested)
}
if (!length(sel)) {
  stop("No tested variable to draw. The screen selected none; name tested variables in PARTIAL_VARS.", call. = FALSE)
}
# Each figure is drawn a page at a time, panels in a grid no larger than the
# printed page (6.5 by 9 in), and each page is a child chunk of its own so
# Quarto numbers it.
.fence <- strrep("`", 3)
.page_child <- function(kind, i, pages, vars, caption) {
  page <- pages[[i]]
  if (length(pages) > 1L) {
    caption <- paste0(caption, " Page ", i, " of ", length(pages), ": ",
                      paste(vars[page$index], collapse = ", "), ".")
  }
  code <- c(paste0(.fence, "{r}"), paste0("#| label: fig-", kind, "-", i),
            paste0("#| fig-cap: ", encodeString(caption, quote = "\"")),
            sprintf("#| fig-width: %g", page$width), sprintf("#| fig-height: %g", page$height), ".fig", .fence)
  cat(knitr::knit_child(text = code, envir = parent.frame(), quiet = TRUE), sep = "\n")
  cat("\n")
}
```

## Dependence

```{r}
#| label: dependence-varpro
#| results: asis
#| message: true
# unnumbered: each page below is a child chunk with its own label and caption
.survival <- identical(fit$family, "surv")
if (.survival) {
  # y.org holds the time and event as the fit was given them; y is varPro's
  # transformed response and is not in follow-up units.
  .longest <- max(fit$y.org[[1L]])
  if (HORIZON > .longest) {
    stop("HORIZON is ", HORIZON, " but the longest follow-up in the screen is ", signif(.longest, 4),
         ", in the units of the fit job's time variable. Choose a horizon inside follow-up.", call. = FALSE)
  }
}
pv <- cache_fit("vp-partial",
                gg_partial_varpro(object = fit, xvar.names = sel,
                                  scale = if (.survival) SCALE else "auto", time = if (.survival) HORIZON else NULL),
                seed = SEED, dir = CACHE_DIR, refit = REFIT)
# The manuscript theme hides the legend and its title, and the caption reads the line types from the legend.
.cap <- paste("VarPro partial dependence on each selected predictor, one panel per predictor. For a",
              "continuous predictor a black solid line marks the nonparametric partial effect and a black",
              "dashed line the parametric one, as in the legend; for a categorical predictor black box",
              "plots show the spread of the partial effect at each level.")
# Free size, paged: one facet per predictor, two by two.
.pages <- hvtiRtemplates:::.figure_pages(length(sel), panel_width = 3.25, panel_height = 3, page_height = 6)
for (.i in seq_along(.pages)) {
  .vars <- sel[.pages[[.i]]$index]
  .fig <- plot(hvtiRtemplates:::.partial_subset(pv, .vars)) &
    hvtiPlotR::theme_hv_manuscript(base_size = 12, legend.position = "top", legend.title = ggplot2::element_text())
  save_figure(.fig, sprintf("vp-explain-dependence-varpro-page-%02d", .i),
              width = .pages[[.i]]$width, height = .pages[[.i]]$height)
  .page_child("dependence-varpro", .i, .pages, sel, .cap)
}
```

```{r}
#| label: provenance
#| echo: false
#| results: asis
cat(hvtiRtemplates:::.embed_provenance(
  .in,
  data = .provenance_data,
  run = .job$run,
  artifacts = .provenance_artifacts,
  extra = list(subject = SUBJECT, type = TYPE, analysis = .vp_read$lineage$analysis, cohort = .vp_read$lineage$cohort)
))
```
````

- [ ] **Step 4: `.lintr` key and catalog flip**

In `.lintr`, after the `vp-fit.qmd` key, add:

```r
    "inst/templates/30_analyses/vp-explain.qmd" = list(
      object_name_linter = Inf,
      commented_code_linter = Inf,
      object_usage_linter = Inf
    ),
```

In `inst/extdata/templates.json`, on the `vp`/`explain` row set `"status": "in-flight"`, `"blocked_on": null`, `"note": "Reads vp.rds from vp-fit in the same set and never refits. In flight with vp-fit."`. Then `python3 dev/specs/artifacts/roadmap_render.py`.

- [ ] **Step 5: Run the tests**

Run: `R_LIBS="$VP_LIB" NOT_CRAN=true Rscript -e 'devtools::test(filter = "vp-templates|templates$|template-|roadmap")'`
Expected: all PASS. If `gg_partial_varpro()` warns `partialpro(): skipping xvar.names not found in object$xvar.names`, the `select` chunk passed an original factor name where VarPro holds one-hot terms. Confirm with `fit$xvar.org.names` versus `fit$xvar.names` and pass the names VarPro expects. Do not muffle the warning.

- [ ] **Step 6: Commit**

```bash
python3 dev/specs/artifacts/check-roadmap-counts.py
git add inst/templates/30_analyses/vp-explain.qmd .lintr inst/extdata/templates.json dev/specs/2026-08-29-template-conversion-roadmap.md tests/testthat/test-vp-templates.R
git commit -m "feat(vp-explain): draw VarPro partials for the screen's selection

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Expected check output: `... 38 on disk.`

---

### Task 7: Documentation, pointers, MRN and the full gate

**Files:**
- Modify: `inst/templates/README.md` (template table, qualified-template sentence, figure-name table)
- Modify: `tests/testthat/test-template-figures.R` (the `expected` list)
- Modify: `inst/templates/30_analyses/rfs-explain.qmd`, `rfc-explain.qmd`, `rfr-explain.qmd` (one paragraph each)
- Modify: `tests/testthat/test-vp-templates.R` (MRN test)
- Create: `news/feat-vp-templates.md`

- [ ] **Step 1: Write the failing tests**

In `tests/testthat/test-template-figures.R`, inside "every printed figure is also saved, under its documented name", add to the `expected <- list(` call, after the `` `rfs-fit` `` entry:

```r
    `vp-fit` = c("vp-fit-coverage", "vp-fit-varpro"),
    `vp-explain` = "vp-explain-dependence-varpro",
```

(mind the comma on the line before). Append to `tests/testthat/test-vp-templates.R`:

```r
test_that("vp-fit and vp-explain keyed on MRN save no MRN in any file", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "explain"))
  data <- rf_mrn_data(n = 60L)
  choices <- list(TIME = "iv_dead", EVENT = "dead", RESPONSE = NULL, PREDICTORS = c("age", "x1", "grp"),
                  NTREE = 25, REPEATS = 1, SEED = 1, SAVE_FIGURES = FALSE)
  fit <- vp_fit_first(data, choices)
  # The ID fell back to MRN, and the job read it.
  expect_identical(attr(fit$job_data$record, "selection")$id, "mrn")
  expect_identical(rf_files_holding(fit$CACHE_DIR, data$MRN), character())
  # On 60 patients the screen may select nothing, and vp-explain would then stop
  # before writing its cache; draw the first tested variable instead, so the
  # partial cache exists to be searched.
  h <- readRDS(fit$set_path("estimates", "vp.rds"))
  tested <- h$coverage$variable[!h$coverage$noise & h$coverage$tested]
  expect_gt(length(tested), 0L)
  env <- new.env(parent = globalenv())
  env$.root <- fit$.root
  rf_run("vp", "explain", vp_explain_labels, env,
         list(PARTIAL_VARS = tested[[1L]], HORIZON = 1, SEED = 1, SAVE_FIGURES = FALSE))
  expect_true(file.exists(file.path(fit$CACHE_DIR, "vp-partial.rds")))
  expect_identical(rf_files_holding(fit$CACHE_DIR, data$MRN), character())
  # The search finds what is there: every MRN in the data as the job read it.
  expect_true(rf_bytes_hold_any(serialize(fit$job_data$data, NULL), data$MRN))
})
```

- [ ] **Step 2: Run them**

Run: `R_LIBS="$VP_LIB" NOT_CRAN=true Rscript -e 'devtools::test(filter = "vp-templates|template-figures")'`
Expected: PASS. The figure names already match, so this test pins them rather than failing first. Confirm it bites by renaming `"vp-fit-coverage"` in the template's `save_figure()` call to `"vp-fit-coverag"`, running again (FAIL), and restoring.

- [ ] **Step 3: README**

In `inst/templates/README.md`:

(a) In the template table, after the `30_analyses/rfr-explain.qmd` row, add:

```markdown
| `30_analyses/vp-fit.qmd` | VarPro screen: coverage, a noise bar by kind and stability across subsamples (in flight) | `30_analyses/` or `analyses/` |
| `30_analyses/vp-explain.qmd` | VarPro partial dependence for the variables a `vp-fit` screen selected (in flight) | `30_analyses/` or `analyses/` |
```

(b) In the sentence "The current qualified templates are …", change `the paired `rfs`/`rfc`/`rfr` fit and explain jobs, and the eight` to `the paired `rfs`/`rfc`/`rfr` and `vp` fit and explain jobs, and the eight`.

(c) In the figure-name table, after the `rfs-fit` row, add:

```markdown
| vp-fit | `vp-fit-coverage`, `-varpro` |
| vp-explain | `vp-explain-dependence-varpro-page-<NN>` |
```

- [ ] **Step 4: Pointers in the rf explain templates**

In each of `rfs-explain.qmd`, `rfc-explain.qmd` and `rfr-explain.qmd`, find the paragraph under `## VarPro` that begins "VarPro is given the forest's own data" (`grep -n "VarPro is given the forest's own data" inst/templates/30_analyses/rf*-explain.qmd`). After that paragraph's last line, add a blank line and:

```markdown
The panel and partial here use varPro's default cutoff, and a variable with
z = 0 may simply be untested. For a screen that says which variables were
tested, judges selection against noise and checks it across subsamples, use
the `vp-fit` and `vp-explain` pair.
```

- [ ] **Step 5: News fragment**

Create `news/feat-vp-templates.md`:

```markdown
* New `vp-fit` and `vp-explain` templates, in flight, for a VarPro variable screen. `vp-fit` reports which candidates VarPro tested (z = 0 means untested, not unimportant), selects a variable only when it beats permuted noise of its own kind, checks the selection across subsamples of the patients, and saves the selected set in `vp.rds`. `vp-explain` draws VarPro partial dependence for that set and refuses a survival horizon past the longest follow-up. The `rfs`, `rfc` and `rfr` explain templates point to them.
```

- [ ] **Step 6: The full gate**

```bash
R_LIBS="$VP_LIB" NOT_CRAN=true Rscript -e 'devtools::document(); devtools::test()' 2>&1 | tail -5
R_LIBS="$VP_LIB" Rscript -e 'lintr::lint_package()'
python3 dev/specs/artifacts/check-roadmap-counts.py && python3 dev/specs/artifacts/check-spec-counts.py && python3 dev/specs/artifacts/check-flow-counts.py
R_LIBS="$VP_LIB" NOT_CRAN=true Rscript -e 'devtools::check()' 2>&1 | tail -15
```

Expected: `FAIL 0`, `WARN 0`, `SKIP 0` under `NOT_CRAN=true` (the local test-rf-templates.R warnings recorded in the maintainer's notes excepted, and named if seen); no lints; three "agree" lines; `0 errors ✔ | 0 warnings ✔ | 0 notes ✔`. `devtools::document()` must leave `man/` and `NAMESPACE` unchanged; this work adds no exports.

- [ ] **Step 7: A real render (maintainer, on lri)**

The chunk tests cannot run Quarto. Hand John this command for a scratch study under `/studies/general/_development` with a built dataset and a survival outcome, from that study's directory on lri:

```r
hvtiRtemplates::add_job("vp", "dead", "vp", qualifier = "fit")
hvtiRtemplates::add_job("vp", "dead", "vp", qualifier = "explain")
```

Then render both with `render_job()` after editing their `EDIT:` choices. Record the runtime with `REPEATS = 20` in the PR.

- [ ] **Step 8: Commit, review, PR**

```bash
git add inst/templates/README.md tests/testthat/test-template-figures.R tests/testthat/test-vp-templates.R inst/templates/30_analyses/rfs-explain.qmd inst/templates/30_analyses/rfc-explain.qmd inst/templates/30_analyses/rfr-explain.qmd news/feat-vp-templates.md
git commit -m "docs(vp): list the vp templates, point rf explain jobs at them

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin feat/vp-templates
gh pr create --title "vp-fit and vp-explain: a VarPro screen with coverage, noise and stability" --body "..."
```

The body links the spec, the two earlier PRs, the mutation result from Task 4 Step 5, the lri render runtime, and says `/code-review` stood in for Copilot. After CI, read every leg's summary line, `gh run view <id> --log | grep -E "SKIP [0-9]+ \| PASS"`: expect `SKIP 0` on macOS and Ubuntu and `SKIP 3` on Windows.

## Out of scope (follow-ups)

- Removing the varPro panel and partial from `rf*-explain`, once `vp` ships.
- A `dev/gallery/family-vp.R` entry, so the template gallery shows the pair. Do it on the next family release day, with the gallery rebuild.
- Moving `vp_add_noise()` and the stability loop into ggRandomForests beside `varpro_coverage()`.
