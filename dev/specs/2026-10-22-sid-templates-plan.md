# `sid` templates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `sid-fit.qmd` (mice or forest imputation over `M`, pooled SID forests, a digest-keyed distance handoff) and `sid-clusters.qmd` (PAM over K, K metrics, stable letters, Sankey, a registered cluster dataset) under the existing `sid` prefix, both at ledger status `in-flight`.

**Architecture:** Two self-contained Quarto templates in `inst/templates/30_analyses/`, built from the two SID studies the spec names. `sid-fit` saves one handoff, `sid.rds` (`list(dist, id_key, vars, dropped, reduced, settings)` with lineage; `dist` is named by study-keyed ID digests, never IDs). `sid-clusters` reads it the way `vp-explain` reads `vp.rds`, defines its helpers in a `sid-helpers` chunk, and writes a CSV of cluster letters that it registers as an ancillary dataset, so later jobs read it through `JOIN`. Everything is in this one repository: `sid` is already in `hvti_taxonomy()`.

**Tech Stack:** R, Quarto, randomForestSRC 3.9.0 (`sidClustering()`), mice 3.19.0, cluster 2.1.8, hvtiPlotR (`hv_sankey()`), hvtiRutilities (`cache_fit()`, `register_data()`), testthat edition 3.

**Spec:** [`2026-10-22-sid-templates-design.md`](2026-10-22-sid-templates-design.md).

## Global Constraints

- Never push to `main`. All work goes on `feat/sid-templates`, through one PR the maintainer merges.
- Branch from `origin/main` after `git fetch`, never from local `main`: other sessions merge here concurrently. Other sessions share `~/Documents/GitHub/hvtiRtemplates`, so work in a worktree: `git worktree add ../hvtiRtemplates-sid -b feat/sid-templates origin/main`.
- Versions are three digits. No PR touches `Version:` or `NEWS.md`. This PR ships files, so it adds `news/feat-sid-templates.md` holding its bullets and no heading.
- Roxygen is Rd markup (no markdown). Lines are at most 135 characters (`.lintr`).
- A template carries its own `format:` block and opens with ONE `setup` chunk. It has exactly one `^SUBJECT\s+<- ` and one `^TYPE\s+<- ` line. Every `EDIT:` marker sits in a chunk labeled `edit-…`. It carries no study identifiers (no study names, no `/studies/` paths, no built-dataset filenames), and it ends with one `provenance` chunk.
- Each template gets its own **file** key in `.lintr` excluding exactly `object_name_linter`, `commented_code_linter` and `object_usage_linter`.
- `options(rf.cores = 1L, mc.cores = 1L)` in both `setup` chunks.
- Every random call is seeded. Imputation m and its SID forest run inside `cache_fit(seed = SEED + m - 1)`, which evaluates the code under `withr::with_seed()`; `sidClustering()` also gets `seed = -abs(SEED + m - 1)`. The `reduce = TRUE` step draws on R's generator even with `seed =` (spec §1).
- No file under `estimates/` holds a patient ID: patients are named by `hvtiRtemplates:::.id_digest(ids, hvtiRtemplates:::.study_id_key(.root))` (#203).
- Every figure is at most 6.5 in wide and 9 in high, and adds `hvtiPlotR::theme_hv_manuscript(base_size = 12)` (`test-figure-standard.R`).
- The count scripts live in `dev/specs/artifacts/`: `roadmap_render.py`, `check-roadmap-counts.py`, `check-spec-counts.py`, `check-flow-counts.py`.
- `check-roadmap-counts.py` fails a commit that adds a template file no ledger row claims, and a `queued` row claims none: the task that creates a template sets its row to `in-flight` in the same commit.
- PAM is `cluster::pam(stats::as.dist(D), k)` everywhere. Never `pam(D, k)` on the matrix (spec §1).
- No `na.action` argument to `sidClustering()`. A missing value reaching the fit stops with a message.
- Template version floors match `DESCRIPTION`'s `Suggests`.
- Tests that fit SID carry `skip_on_cran()`. Tests run the INSTALLED templates chunk by chunk via `rf_run()`/`rf_env()` (`tests/testthat/helper-rf.R`), so reinstall before each test run: `R CMD INSTALL --no-test-load -l "$SID_LIB" .` and run with `R_LIBS="$SID_LIB"`. Concurrent sessions overwrite the shared library. Set up the private library once:
  `export SID_LIB=$(mktemp -d)/lib && mkdir -p "$SID_LIB"`.
- Never `git add -A` after a test run: a failing testthat run writes `tests/testthat/_problems/`. Add files by name.
- Run `/code-review` locally before opening the PR, and say in the PR body that it stood in for Copilot. Check the Copilot quota first with the reviews command in `AGENTS.md`.

## File map

| File | Responsibility |
|---|---|
| `inst/templates/30_analyses/sid-fit.qmd` | create: cohort, missingness, imputation, SID fit, `sid.rds` |
| `inst/templates/30_analyses/sid-clusters.qmd` | create: helpers, PAM, K metrics, sizes, Sankey, K sections, CSV + registration, `sid-clusters.rds` |
| `inst/extdata/templates.json` | the `sid` row becomes `(sid, fit)` and `(sid, clusters)` |
| `tests/testthat/helper-sid.R` | create: planted-cluster cohort, choices, label vectors, `sid_fit_first()` |
| `tests/testthat/test-sid-templates.R` | create: every test in spec §7 |
| `tests/testthat/test-template-catalog.R` | counts 68 → 69 rows, 45 prefixes |
| `tests/testthat/test-template-figures.R` | the `expected` list gains `sid-clusters` |
| `tests/testthat/helper-rf.R` | `rf_pkg_floors` gains `cluster` and `mice` |
| `.lintr` | two file keys |
| `DESCRIPTION` | `Suggests`: `cluster (>= 2.1.8)`, `mice (>= 3.19.0)` |
| `inst/templates/README.md` | template table rows, figure-name rows |
| `dev/specs/2026-08-29-template-conversion-roadmap.md` | generated block, by `roadmap_render.py` |
| `news/feat-sid-templates.md` | create: the NEWS bullets |

---

### Task 1: Ledger rows, catalog counts and dependencies

**Files:**
- Modify: `inst/extdata/templates.json` (the row with `"prefix": "sid"`)
- Modify: `tests/testthat/test-template-catalog.R:4-5`
- Modify: `DESCRIPTION` (`Suggests`)
- Modify: `tests/testthat/helper-rf.R:104-109`
- Modify: `dev/specs/2026-08-29-template-conversion-roadmap.md` (generated block only, by script)

**Interfaces:**
- Produces: catalog rows keyed `(sid, fit)` and `(sid, clusters)`, `status: "queued"`, `folder: "analyses"`, `family: "machine-learning"`. Task 2 flips `(sid, clusters)` and Task 3 flips `(sid, fit)` to `in-flight`, each with its file.

- [ ] **Step 1: Worktree, branch and private library**

```bash
cd ~/Documents/GitHub/hvtiRtemplates
git fetch -q origin && git worktree add ../hvtiRtemplates-sid -b feat/sid-templates origin/main
cd ../hvtiRtemplates-sid
export SID_LIB=$(mktemp -d)/lib && mkdir -p "$SID_LIB"
```

- [ ] **Step 2: Re-measure the counts**

Run: `Rscript -e 'x <- jsonlite::fromJSON("inst/extdata/templates.json")$templates; cat(nrow(x), length(unique(x$prefix)), "\n")'`
Expected: `68 45` (as of `88cd7cd`). If the `vt` work landed rows first, use the measured numbers below, plus one row and the same prefix count.

- [ ] **Step 3: Move the catalog counts (the failing test)**

In `tests/testthat/test-template-catalog.R`, change

```r
  expect_equal(nrow(catalog), 68L)
  expect_equal(length(unique(catalog$prefix)), 45L)
```

to

```r
  expect_equal(nrow(catalog), 69L)
  expect_equal(length(unique(catalog$prefix)), 45L)
```

Run: `Rscript -e 'devtools::test(filter = "template-catalog$")'`
Expected: FAIL, `nrow(catalog)` is 68 not 69.

- [ ] **Step 4: Replace the `sid` row with two**

In `inst/extdata/templates.json`, replace the whole object whose `"prefix"` is `"sid"` with:

```json
    {
      "prefix": "sid",
      "qualifier": "fit",
      "name": "SID clustering: fit",
      "description": "An unsupervised sidClustering forest on the clustering variables, after one seeded imputation, saving the SID dissimilarity for sid-clusters.",
      "folder": "analyses",
      "family": "machine-learning",
      "kind": "job",
      "status": "queued",
      "batch": null,
      "sas_breadth": null,
      "r_exemplars": null,
      "r_jobs": null,
      "upstream": [],
      "downstream": [],
      "workflows": [],
      "blocked_on": null,
      "spec": "dev/specs/2026-10-22-sid-templates-design.md",
      "note": "Built from the two SID clustering studies in the ML family roadmap. Helpers live in template chunks; hvtiRforests#1 is no longer a blocker.",
      "sas_breadth_jobs": null,
      "disposition": "build",
      "uses": [
        "randomForestSRC::sidClustering",
        "mice::mice",
        "hvtiRutilities::cache_fit"
      ]
    },
    {
      "prefix": "sid",
      "qualifier": "clusters",
      "name": "SID clustering: clusters",
      "description": "PAM on a sid-fit dissimilarity over a range of K: metrics for choosing K, letters stable across K, a Sankey, and the assignments registered for later jobs to join.",
      "folder": "analyses",
      "family": "machine-learning",
      "kind": "job",
      "status": "queued",
      "batch": null,
      "sas_breadth": null,
      "r_exemplars": null,
      "r_jobs": null,
      "upstream": [],
      "downstream": [],
      "workflows": [],
      "blocked_on": null,
      "spec": "dev/specs/2026-10-22-sid-templates-design.md",
      "note": "Never fits SID; reads sid.rds. Per-cluster profiling is a dc-tables job and per-cluster varPro a vp-fit job, both joining the registered clusters dataset.",
      "sas_breadth_jobs": null,
      "disposition": "build",
      "uses": [
        "cluster::pam",
        "cluster::silhouette",
        "hvtiPlotR::hv_sankey",
        "hvtiRutilities::register_data"
      ]
    },
```

Keep the trailing comma only if another object follows (it does: `vt`).

- [ ] **Step 5: Suggests and test floors**

In `DESCRIPTION` `Suggests` (sorted case-insensitively), add `    cluster (>= 2.1.8),` after `    broom,` and `    mice (>= 3.19.0),` after `    MASS,`.

In `tests/testthat/helper-rf.R`, change `rf_pkg_floors` to:

```r
rf_pkg_floors <- c(
  randomForestSRC  = "3.7.0",
  varPro           = "3.2.0",
  ggRandomForests  = "4.0.0",
  hvtiRutilities   = "1.3.0",
  cluster          = "2.1.8",
  mice             = "3.19.0"
)
```

Check the hvtiPlotR floor: `hv_sankey()` must exist at the `Suggests` floor `hvtiPlotR (>= 2.8.9)`. Run:

```bash
gh api repos/ehrlinger/hvtiPlotR/contents/NEWS.md --jq .content | base64 -d | grep -n -i -B3 "hv_sankey" | head
```

If `hv_sankey` first appears under a heading above `2.8.9`, raise the floor in `DESCRIPTION` to that version, and use the same version in Task 4's setup check.

- [ ] **Step 6: Regenerate the roadmap and run the gates**

```bash
python3 dev/specs/artifacts/roadmap_render.py
python3 dev/specs/artifacts/check-roadmap-counts.py
Rscript -e 'devtools::test(filter = "template-catalog$|roadmap")'
```

Expected: the script rewrites the generated block, the count check prints no error, and the tests PASS.

- [ ] **Step 7: Commit**

```bash
git add inst/extdata/templates.json tests/testthat/test-template-catalog.R DESCRIPTION tests/testthat/helper-rf.R \
  dev/specs/2026-08-29-template-conversion-roadmap.md
git commit -m "feat(sid): qualified ledger rows sid-fit and sid-clusters; cluster and mice in Suggests"
```

---

### Task 2: `sid-clusters.qmd` skeleton and its helpers

The helpers come first because they are pure functions with hand-built tests, needing no fit.

**Files:**
- Create: `inst/templates/30_analyses/sid-clusters.qmd` (front matter, `setup`, `edit-study-choices`, `sid-helpers` only; Task 4 adds the rest)
- Create: `tests/testthat/helper-sid.R`
- Create: `tests/testthat/test-sid-templates.R`
- Modify: `.lintr` (a file key)

**Interfaces:**
- Produces, in chunk `sid-helpers`:
  - `sid_align_labels(mat, overrides = list(), pool = LETTERS)`: `mat` is an integer matrix or data frame, one column per K in ascending order, named `pm<k>`. Returns a character matrix of the same shape and names.
  - `sid_collapse(letters, map)`: `letters` is a character vector; `map` is a named list of character vectors. Returns a character vector.
  - `sid_mds_signs(xy)`: `xy` is a numeric matrix. Returns it with each column's sign set.
- Produces, in `helper-sid.R`: `sid_helpers_env()`, an environment holding the three helpers, parsed from the installed template.

- [ ] **Step 1: Write the failing helper tests**

Create `tests/testthat/helper-sid.R`:

```r
# The sid templates are run chunk by chunk through rf_run() (helper-rf.R),
# whose chunk runner is not specific to random forests.

# The helpers in sid-clusters' `sid-helpers` chunk, evaluated alone, so they
# can be tested on hand-built inputs with no fit.
sid_helpers_env <- function() {
  src <- readLines(template_path("sid", "clusters"), warn = FALSE)
  env <- new.env(parent = globalenv())
  eval(parse(text = rf_chunk(src, "sid-helpers")), envir = env)  # nolint: object_usage_linter.
  env
}
```

Create `tests/testthat/test-sid-templates.R`:

```r
# The sid templates, run chunk by chunk from the installed files (helper-rf.R,
# helper-sid.R). Only tests that fit SID skip on CRAN.

test_that("sid_align_labels keeps a parent's letter on its largest child", {
  h <- sid_helpers_env()
  # K = 2: cluster 1 has 6 patients, cluster 2 has 4. K = 3 splits cluster 1
  # into 4 + 2; the 4 keep the parent's letter, the 2 take a fresh one.
  mat <- data.frame(pm2 = c(1, 1, 1, 1, 1, 1, 2, 2, 2, 2), pm3 = c(3, 3, 3, 3, 1, 1, 2, 2, 2, 2))
  out <- h$sid_align_labels(mat)
  expect_identical(colnames(out), c("pm2", "pm3"))
  expect_identical(out[, "pm2"], rep(c("A", "B"), c(6, 4)))
  expect_identical(out[, "pm3"], c(rep("A", 4), "C", "C", rep("B", 4)))
})

test_that("sid_align_labels does not depend on how PAM numbered its clusters", {
  h <- sid_helpers_env()
  mat <- data.frame(pm2 = c(1, 1, 1, 1, 1, 1, 2, 2, 2, 2), pm3 = c(3, 3, 3, 3, 1, 1, 2, 2, 2, 2))
  renumbered <- data.frame(pm2 = 3 - mat$pm2, pm3 = c(`1` = 2, `2` = 3, `3` = 1)[as.character(mat$pm3)])
  expect_identical(unname(h$sid_align_labels(renumbered)), unname(h$sid_align_labels(mat)))
})

test_that("sid_align_labels applies an override and rejects an unknown cluster id", {
  h <- sid_helpers_env()
  mat <- data.frame(pm2 = c(1, 1, 1, 2, 2), pm3 = c(1, 1, 3, 2, 2))
  out <- h$sid_align_labels(mat, overrides = list(pm2 = c("1" = "B", "2" = "A")))
  expect_identical(out[, "pm2"], c("B", "B", "B", "A", "A"))
  expect_error(h$sid_align_labels(mat, overrides = list(pm2 = c("7" = "B"))), "unknown cluster id")
})

test_that("sid_align_labels never gives two clusters one letter when an override takes it", {
  h <- sid_helpers_env()
  # Found in review: an override gives cluster 1 at K = 3 the letter "B", which
  # the lineage rule would otherwise hand to cluster 2, the child of B.
  mat <- data.frame(pm2 = c(1, 1, 1, 1, 2, 2), pm3 = c(1, 1, 3, 3, 2, 2))
  out <- h$sid_align_labels(mat, overrides = list(pm3 = c("1" = "B")))
  pm3 <- tapply(out[, "pm3"], mat$pm3, unique)
  expect_identical(anyDuplicated(unlist(pm3)), 0L)
  expect_error(h$sid_align_labels(mat, overrides = list(pm3 = c("1" = "B", "2" = "B"))), "one letter to two")
})

test_that("sid_align_labels stops when the letter pool runs out", {
  h <- sid_helpers_env()
  mat <- data.frame(pm3 = c(1, 2, 3))
  expect_error(h$sid_align_labels(mat, pool = c("A", "B")), "Letter pool exhausted")
})

test_that("sid_collapse maps letters, keeps unmapped ones and rejects a bad map", {
  h <- sid_helpers_env()
  x <- c("A", "C", "D", "B", "E")
  expect_identical(h$sid_collapse(x, list(Z = c("C", "D", "E"))), c("A", "Z", "Z", "B", "Z"))
  expect_error(h$sid_collapse(x, list(Z = c("C", "Q"))), "not a cluster at K: Q")
  expect_error(h$sid_collapse(x, list(Y = "C", Z = "C")), "mapped more than once: C")
})

test_that("sid_mds_signs gives the same picture under row order and sign flips", {
  h <- sid_helpers_env()
  xy <- cbind(c(1, -3, 2, 0.5), c(-0.2, 0.1, 0.4, -2))
  ref <- h$sid_mds_signs(xy)
  expect_true(ref[2, 1] > 0)  # the largest |x| on axis 1 is row 2, made positive
  expect_true(ref[4, 2] > 0)
  perm <- c(3, 1, 4, 2)
  expect_identical(h$sid_mds_signs(xy[perm, ]), ref[perm, ])
  expect_identical(h$sid_mds_signs(-xy), ref)
})
```

- [ ] **Step 2: Run them to see them fail**

```bash
R CMD INSTALL --no-test-load -l "$SID_LIB" . >/dev/null 2>&1
R_LIBS="$SID_LIB" Rscript -e 'devtools::test(filter = "sid-templates")'
```

Expected: FAIL. `template_path("sid", "clusters")` errors, because there is no such file.

- [ ] **Step 3: Create the skeleton with the helpers**

Create `inst/templates/30_analyses/sid-clusters.qmd`. The front matter is `vp-fit.qmd`'s lines 1-29 verbatim, with `title: "SID clustering: clusters"`. Then:

````markdown
This job turns a `sid-fit` dissimilarity into clusters. It runs PAM
(partitioning around medoids) on the SID distance for each K in a range,
reports what the elbow and the silhouette say about K, and gives every
solution letters that keep their identity as K grows, so cluster A at K = 4
is recognisably cluster A at K = 5. It never fits the forest: it reads
`sid.rds`, so choosing K and pinning letters cost seconds and can be
repeated freely.

The assignments are written to the study's datasets folder and registered,
so a later job reads them with `JOIN`: a `dc-tables` job to describe the
clusters, a `vp-fit` job with the cluster as its outcome to ask which
variables separate them.

This template is **in flight**: no study has yet run it end to end.

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
SUBJECT <- "morphology"
TYPE    <- "sid"
.in <- knitr::current_input(dir = TRUE)
suppressPackageStartupMessages({
  library(cluster)
  library(hvtiPlotR)
  library(hvtiRutilities)
})
# Nothing below is random, but the threads are pinned as in every forest job,
# so a library that does reach for them behaves the same on every machine.
options(rf.cores = 1L, mc.cores = 1L)
# The versions this template was verified against on 2026-10-22.
if (utils::packageVersion("cluster") < "2.1.8") {
  stop("This job needs cluster >= 2.1.8; ", utils::packageVersion("cluster"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
if (utils::packageVersion("hvtiPlotR") < "2.8.9") {
  stop("This job needs hvtiPlotR >= 2.8.9; ", utils::packageVersion("hvtiPlotR"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
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
# The draft banners, if any, and the box under the title, after all the code above.
.job$notice
```

## Study choices

Edit these values for this study before rendering.

```{r}
#| label: edit-study-choices
# EDIT: the solutions to assign letters and draw in the Sankey, smallest K
# first. Letters are carried from each K to the next, so the range must be
# consecutive.
K_RANGE <- 2:9

# EDIT: the solution this study reports, one of K_RANGE. Leave NULL for the
# first render: the metrics and sizes below are how K is chosen, and every
# section that needs K is skipped, saying so. A final render needs K.
K <- NULL

# EDIT: letters pinned by hand, by solution and PAM cluster number, such as
#   OVERRIDES <- list(pm4 = c("1" = "B", "2" = "D", "3" = "C", "4" = "A"))
# PAM numbers its clusters arbitrarily, so an override is a domain decision
# written down (which cluster a paper calls A), not a fix. Read the cluster
# numbers from the sizes table. list() lets the lineage rule choose.
OVERRIDES <- list()

# EDIT: optionally, groups made of clusters at K, such as
#   COLLAPSE <- list(Z = c("C", "D", "E"))
# written as an extra column G<K>. Letters not named keep their own letter.
# NULL writes no group column.
COLLAPSE <- NULL

# EDIT: a cluster smaller than this at K is flagged. Later per-cluster tables
# and a vp-fit with the cluster as outcome need enough patients in each.
MIN_SIZE <- 20

# EDIT: how far the K metrics run. They are drawn beyond K_RANGE on purpose: an
# elbow is only visible with points on both sides of it.
K_METRICS_MAX <- 15

# Each figure is saved to graphs/ as a PNG (for Word), and a PDF and a TIFF (for the publisher).
# SAVE_FIGURES <- FALSE saves none; FIGURES keeps only the figures whose names
# start with one of its entries, e.g. FIGURES <- c("sid-clusters-sankey"). The names are the
# file names, listed for each template in the templates README.
SAVE_FIGURES <- TRUE
FIGURES <- NULL
```

```{r}
#| label: sid-helpers
# Letters that keep their identity across K. The first solution's clusters
# take letters largest first. At each later K, every cluster is the child of
# the previous solution's cluster that contributes most of its patients; the
# largest child of each parent inherits the parent's letter and its siblings
# take fresh ones. An override pins a letter to a PAM cluster number.
sid_align_labels <- function(mat, overrides = list(), pool = LETTERS) {
  mat <- as.matrix(mat)
  out <- matrix(NA_character_, nrow(mat), ncol(mat), dimnames = list(NULL, colnames(mat)))
  pinned <- function(col, ids) {
    res <- stats::setNames(rep(NA_character_, length(ids)), as.character(ids))
    ov <- overrides[[col]]
    if (is.null(ov)) return(res)
    bad <- setdiff(names(ov), as.character(ids))
    if (length(bad)) {
      stop("OVERRIDES$", col, " names unknown cluster id(s): ", toString(bad), call. = FALSE)
    }
    if (anyDuplicated(ov)) stop("OVERRIDES$", col, " gives one letter to two clusters.", call. = FALSE)
    res[names(ov)] <- ov
    res
  }
  fresh <- function(taken) {
    l <- setdiff(pool, taken)[1]
    if (is.na(l)) stop("Letter pool exhausted: more clusters than letters.", call. = FALSE)
    l
  }
  used <- character(0)
  sizes <- table(mat[, 1])
  ids <- names(sort(sizes, decreasing = TRUE))
  got <- pinned(colnames(mat)[1], ids)
  for (id in ids) if (is.na(got[id])) got[id] <- fresh(c(used, got))
  used <- unique(c(used, got))
  out[, 1] <- got[as.character(mat[, 1])]
  for (k in seq_len(ncol(mat))[-1]) {
    tab <- table(out[, k - 1], mat[, k])
    parent <- apply(tab, 2, function(col) rownames(tab)[which.max(col)])
    got <- pinned(colnames(mat)[k], colnames(tab))
    for (p in unique(parent)) {
      kids <- names(parent)[parent == p]
      kids <- kids[order(colSums(tab)[kids], decreasing = TRUE)]
      # Checked against the whole column: an override may already have given
      # the parent's letter to a cluster of another parent.
      if (!p %in% got) {
        free <- kids[is.na(got[kids])]
        if (length(free)) got[free[1]] <- p
      }
      for (ch in kids) if (is.na(got[ch])) got[ch] <- fresh(c(used, got))
    }
    used <- unique(c(used, got))
    out[, k] <- got[as.character(mat[, k])]
  }
  out
}

# Groups made of clusters. A letter not in the map keeps its own letter.
sid_collapse <- function(letters, map) {
  named <- unlist(map, use.names = FALSE)
  twice <- unique(named[duplicated(named)])
  if (length(twice)) stop("COLLAPSE has a letter mapped more than once: ", toString(twice), call. = FALSE)
  absent <- setdiff(named, letters)
  if (length(absent)) stop("COLLAPSE names a letter that is not a cluster at K: ", toString(absent), call. = FALSE)
  out <- letters
  for (g in names(map)) out[letters %in% map[[g]]] <- g
  out
}

# cmdscale() returns each axis with an arbitrary sign, so a map can mirror
# between renders. Each axis is turned so that the patient furthest from the
# origin along it is positive, which depends on neither row order nor render.
sid_mds_signs <- function(xy) {
  for (j in seq_len(ncol(xy))) {
    if (xy[which.max(abs(xy[, j])), j] < 0) xy[, j] <- -xy[, j]
  }
  xy
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
  extra = list(subject = SUBJECT, type = TYPE)
))
```
````

The `provenance` chunk is here from the start because the catalog-wide tests require every shipped template to end with one. Task 4 replaces it.

- [ ] **Step 4: The `.lintr` key**

In `.lintr`, after the `vp-explain.qmd` entry, add:

```r
    "inst/templates/30_analyses/sid-clusters.qmd" = list(
      object_name_linter = Inf,
      commented_code_linter = Inf,
      object_usage_linter = Inf
    ),
```

- [ ] **Step 5: Run the helper tests**

```bash
R CMD INSTALL --no-test-load -l "$SID_LIB" . >/dev/null 2>&1
R_LIBS="$SID_LIB" Rscript -e 'devtools::test(filter = "sid-templates")'
```

Expected: PASS, 7 tests. If the renumbering test fails, the cause is ties in `sort()` order: the test data have no ties, so look for a bug in `parent`.

- [ ] **Step 6: The ledger row and the template count**

Set the `(sid, clusters)` row in `inst/extdata/templates.json` to `"status": "in-flight"`. Start its `note` with "Released for review in a real study. Becomes shipped once a study renders sid-fit and sid-clusters end to end." and keep the existing note after it. In `tests/testthat/test-template-provenance.R`, raise `expect_equal(nrow(templates), 37L)` (line 172 at `88cd7cd`) by one. Then:

```bash
python3 dev/specs/artifacts/roadmap_render.py && python3 dev/specs/artifacts/check-roadmap-counts.py
R CMD INSTALL --no-test-load -l "$SID_LIB" . >/dev/null 2>&1
R_LIBS="$SID_LIB" Rscript -e 'devtools::test(filter = "template-")'
```

Expected: no error, and the catalog-wide `template-` tests PASS with the skeleton in place.

- [ ] **Step 7: Commit**

```bash
git add inst/templates/30_analyses/sid-clusters.qmd tests/testthat/helper-sid.R tests/testthat/test-sid-templates.R .lintr \
  inst/extdata/templates.json tests/testthat/test-template-provenance.R dev/specs/2026-08-29-template-conversion-roadmap.md
git commit -m "feat(sid-clusters): skeleton and the label, collapse and MDS-sign helpers"
```

---

### Task 3: `sid-fit.qmd`

**Files:**
- Create: `inst/templates/30_analyses/sid-fit.qmd`
- Modify: `tests/testthat/helper-sid.R`, `tests/testthat/test-sid-templates.R`, `.lintr`

**Interfaces:**
- Consumes: `cache_fit(name, code, seed, dir, refit)` from hvtiRutilities; `.attach_handoff_lineage()`, `.embed_provenance()` and `read_job_data()` from this package.
- Produces: `estimates/<subject>-<type>/sid.rds`, an object `list(dist, id_key, vars, dropped, reduced, settings)` with handoff lineage in `attr(, "hvti_provenance")`, including the data `selection`. Its parts:
  - `dist` is a numeric n × n matrix, the mean over `M` imputations, with `rownames` and `colnames` set to `hvtiRtemplates:::.id_digest(<ID column>, hvtiRtemplates:::.study_id_key(.root))`;
  - `id_key` is `hvtiRtemplates:::.id_key_fingerprint(key)`;
  - `vars` is a character vector of the variables clustered on;
  - `dropped` is a data frame (`variable`, `reason`);
  - `reduced` is the union of the fits' `outcome.names`;
  - `settings` is `list(ntree, sid_reduce, seed, impute, m, mice_maxit, max_missing)`.
  - It holds **no patient ID and no patient values** (spec §3). `vt-fit` reads `dist` by digest too.
- Produces, in `helper-sid.R`: `sid_data()`, `sid_fit_choices`, `sid_fit_labels`, `sid_fit_first()`.

- [ ] **Step 1: Test helpers**

Append to `tests/testthat/helper-sid.R`:

```r
# Three well-separated groups of 50 on four continuous variables and one
# factor, with a few values missing so the imputation has work to do. Seeded,
# so a test sees the same patients every run. `truth` is the planted group;
# it is not a clustering variable.
sid_data <- function(n_per = 50L, seed = 20261022L) {
  withr::with_seed(seed, {
    truth <- rep(1:3, each = n_per)
    centre <- c(-3, 0, 3)[truth]
    d <- data.frame(
      a = stats::rnorm(3 * n_per, centre), b = stats::rnorm(3 * n_per, -centre),
      c = stats::rnorm(3 * n_per, centre / 2), e = stats::rnorm(3 * n_per),
      f = factor(ifelse(truth == 3, "y", sample(c("x", "y"), 3 * n_per, replace = TRUE, prob = c(0.8, 0.2))))
    )
    d$a[sample(nrow(d), 5)] <- NA
    d$f[sample(nrow(d), 3)] <- NA
  })
  d$truth <- truth
  d
}

# NTREE = 500: at 50 trees the planted groups were not recovered (normalized
# measure 0.92, measured in review); at 200 it was 0.12. Each fit takes well
# under a second on 150 rows.
sid_fit_choices <- list(
  VARS = c("a", "b", "c", "e", "f"), MAX_MISSING = 0.4, NTREE = 500, SID_REDUCE = FALSE,
  IMPUTE = "mice", M = 1, MICE_MAXIT = 5, SEED = 1, REFIT = FALSE
)

# Every chunk of sid-fit, in order.
sid_fit_labels <- c("setup", "edit-study-choices", "tbl-data", "tbl-missing", "impute", "fit", "tbl-used", "save")

# sid-fit run end to end in a throwaway study.
sid_fit_first <- function(data = sid_data(), choices = sid_fit_choices, .local_envir = parent.frame()) {
  env <- rf_env(data, .local_envir)  # nolint: object_usage_linter.
  rf_run("sid", "fit", sid_fit_labels, env, choices)  # nolint: object_usage_linter.
  env
}
```

- [ ] **Step 2: Write the failing tests**

Append to `tests/testthat/test-sid-templates.R`:

```r
test_that("sid-fit imputes, fits and saves the handoff", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("sid", "fit"))
  env <- sid_fit_first()
  h <- readRDS(env$set_path("estimates", "sid.rds"))
  expect_identical(names(h), c("dist", "id_key", "vars", "dropped", "reduced", "settings"))
  expect_identical(dim(h$dist), c(150L, 150L))
  expect_false(anyNA(h$dist))
  key <- hvtiRtemplates:::.study_id_key(env$.root)
  expect_identical(rownames(h$dist), hvtiRtemplates:::.id_digest(seq_len(150L), key))
  expect_identical(h$id_key, hvtiRtemplates:::.id_key_fingerprint(key))
  expect_false(is.null(attr(h, "hvti_provenance")$selection))
})

test_that("sid-fit imputes by forest, and pools M imputations into one mean distance", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("sid", "fit"))
  forest <- readRDS(sid_fit_first(choices = utils::modifyList(sid_fit_choices, list(IMPUTE = "forest")))$set_path(
    "estimates", "sid.rds"
  ))
  expect_false(anyNA(forest$dist))
  env <- sid_fit_first(choices = utils::modifyList(sid_fit_choices, list(M = 2)))
  expect_length(env$sid_fits, 2L)
  pooled <- readRDS(env$set_path("estimates", "sid.rds"))$dist
  expect_equal(unname(pooled), unname((env$sid_fits[[1]]$dist + env$sid_fits[[2]]$dist) / 2))
  expect_identical(nrow(env$sid_agreement), 2L)
  # IMPUTE is checked where it is used, in the impute chunk (the fifth).
  bad <- rf_env(sid_data())
  expect_error(rf_run("sid", "fit", sid_fit_labels[1:5], bad, utils::modifyList(sid_fit_choices, list(IMPUTE = "x"))),
               "IMPUTE")
})

test_that("sid-fit drops a variable over MAX_MISSING and says so", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("sid", "fit"))
  d <- sid_data()
  d$e[1:80] <- NA
  env <- sid_fit_first(d)
  expect_identical(env$sid_dropped$variable, "e")
  expect_false("e" %in% env$sid_vars)
})

test_that("sid-fit refuses an ID or an absent column in VARS", {
  rf_skip_unless_stack(rf_template_packages("sid", "fit"))
  for (vars in list(c("a", "ccfid"), c("a", "nope"))) {
    env <- rf_env(sid_data())
    expect_error(
      rf_run("sid", "fit", sid_fit_labels[1:3], env, utils::modifyList(sid_fit_choices, list(VARS = vars))),
      "VARS"
    )
  }
})

test_that("the seed reproduces a reduce = TRUE fit", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("sid", "fit"))
  choices <- utils::modifyList(sid_fit_choices, list(SID_REDUCE = TRUE))
  one <- readRDS(sid_fit_first(choices = choices)$set_path("estimates", "sid.rds"))$dist
  two <- readRDS(sid_fit_first(choices = choices)$set_path("estimates", "sid.rds"))$dist
  expect_identical(one, two)
})
```

- [ ] **Step 3: Run them to see them fail**

```bash
R CMD INSTALL --no-test-load -l "$SID_LIB" . >/dev/null 2>&1
R_LIBS="$SID_LIB" Rscript -e 'devtools::test(filter = "sid-templates")'
```

Expected: the four new tests FAIL with "no template" for `("sid", "fit")`, and the six helper tests PASS.

- [ ] **Step 4: Write the template**

Create `inst/templates/30_analyses/sid-fit.qmd`. The front matter is `vp-fit.qmd`'s lines 1-29 verbatim, with `title: "SID clustering: fit"`. Then:

````markdown
This job builds the dissimilarity that `sid-clusters` turns into clusters.
SID clustering (Mantero and Ishwaran, 2021) is unsupervised: there is no
outcome. It stretches the clustering variables into staggered copies and
their pairwise interactions, grows a multivariate random forest predicting
the one from the other, and measures how often two patients fall in the same
terminal nodes. Two patients the forest cannot tell apart are close.

The forest needs complete data, so the job first drops variables that are
mostly missing and fills the rest with one imputation. The imputed values
stay inside this job. Whatever describes the clusters later reads the study
data, so it describes what was measured, not what was imputed.

This template is **in flight**: no study has yet run it end to end.

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
SUBJECT <- "morphology"
TYPE    <- "sid"
.in <- knitr::current_input(dir = TRUE)
suppressPackageStartupMessages({
  library(randomForestSRC)
  library(mice)
  library(hvtiRutilities)
})
# One thread, so a fit reproduces from machine to machine. Left unset,
# randomForestSRC runs on every core its OpenMP build can see, and the forest
# changes with the thread count with every seed held fixed.
options(rf.cores = 1L, mc.cores = 1L)
# The versions this template was verified against on 2026-10-22.
if (utils::packageVersion("randomForestSRC") < "3.7.0") {
  stop("This job needs randomForestSRC >= 3.7.0; ", utils::packageVersion("randomForestSRC"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
if (utils::packageVersion("mice") < "3.19.0") {
  stop("This job needs mice >= 3.19.0; ", utils::packageVersion("mice"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
# To render a job you have not finished, leave a chunk out with the chunk
# option skip, giving the reason in quotes, or call hvtiRtemplates::stop_here()
# in a chunk to leave out everything below it. A draft lists each one in a
# callout; a final render refuses them, as it refuses an unresolved marker.
# ?stop_here has more.
.job <- hvtiRtemplates:::.job_setup(SUBJECT, TYPE, envir = environment())
.root <- .job$root
set_path <- .job$set_path
.provenance_data <- list()
# `sid-fit` writes sid.rds and `sid-clusters` reads it, both by set.
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
WHERE <- NULL

# EDIT: the patient identifier. Without "ccfid" the job uses MRN, then eMRN;
# name another column, such as "randid", if the study uses one.
ID <- "ccfid"

# EDIT: what makes a row unique. Clustering is one row per patient.
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
#     record silently would be a hidden choice. This job clusters one row per
#     patient, so a JOIN without REDUCE stops here.
#   JOIN_KEY: overrides the joined dataset's registered key.
JOIN <- NULL
JOIN_VARS <- NULL
REDUCE <- NULL
JOIN_KEY <- NULL

# EDIT: the clustering variables. These DEFINE the clusters: two patients are
# close when they are alike on these. Name measurements of the thing being
# grouped (anatomy, physiology), never an outcome: clustering on survival and
# then comparing survival by cluster answers its own question. Factors are
# allowed, but each adds staggered copies and interactions to the forest.
VARS <- c("age", "female", "hx_chf")

# EDIT: a variable missing in more than this share of patients is dropped and
# listed, not imputed. An imputation that invents most of a column decides the
# clusters it was meant to inform.
MAX_MISSING <- 0.4

# EDIT: the forest. NTREE = 5000 is what the studies behind this template
# used. SID_REDUCE = TRUE runs sidClustering's holdout-VIMP step, which drops
# staggered variables that carry no structure; it is slow, and recommended
# with more than a handful of variables because the interactions grow with the
# square of their number. (It is not the join's REDUCE above.)
NTREE <- 5000
SID_REDUCE <- TRUE

# EDIT: how missing values are filled before the forest, which needs complete
# data. "mice" uses predictive mean matching; "forest" uses randomForestSRC's
# own imputation. M is the number of imputations: with M > 1 one SID forest is
# grown on each and their distances are averaged, so the clusters reflect more
# than one draw of the missing values, at M times the cost. MICE_MAXIT is the
# number of mice iterations, unused by "forest".
IMPUTE <- "mice"
M <- 1
MICE_MAXIT <- 50

# EDIT: the seed. Imputation m and its forest use SEED + m - 1: it is part of
# each cache key, sets R's generator for the call (cache_fit() runs it under
# that seed), and is handed to sidClustering() as `seed =`. Both matter:
# SID_REDUCE = TRUE draws from R's generator as well as from the forest's seed.
SEED <- 1024

# Set TRUE after changing a choice above. A cache whose inputs changed stops the
# render instead of returning the old result; TRUE recomputes only the caches
# that are out of date.
REFIT <- FALSE
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
.id <- attr(job_data$record, "selection")$id
if (tolower(.id) %in% tolower(VARS)) {
  stop("VARS names the patient identifier `", .id, "`. Remove it: an ID is not a measurement.", call. = FALSE)
}
.absent <- setdiff(tolower(VARS), names(d))
if (length(.absent)) {
  stop("VARS names column(s) the data do not have: ", toString(.absent), ".", call. = FALSE)
}
VARS <- tolower(VARS)
.empty <- rowSums(!is.na(d[VARS])) == 0
d <- d[!.empty, , drop = FALSE]
cat("Patients with every clustering variable missing, dropped:", sum(.empty), "\n")
```

## Missing values

```{r}
#| label: tbl-missing
#| tbl-cap: "Share of patients missing each clustering variable"
.miss <- vapply(d[VARS], function(x) mean(is.na(x)), numeric(1))
sid_dropped <- data.frame(variable = character(0), reason = character(0))
.sparse <- names(.miss)[.miss > MAX_MISSING]
if (length(.sparse)) {
  sid_dropped <- rbind(sid_dropped, data.frame(variable = .sparse, reason = paste0("missing in more than ",
                                                                                  100 * MAX_MISSING, "%")))
}
.flat <- VARS[vapply(d[VARS], function(x) length(unique(stats::na.omit(x))) < 2L, logical(1))]
.flat <- setdiff(.flat, .sparse)
if (length(.flat)) sid_dropped <- rbind(sid_dropped, data.frame(variable = .flat, reason = "one value only"))
sid_vars <- setdiff(VARS, sid_dropped$variable)
if (length(sid_vars) < 2L) stop("Fewer than two clustering variables are left to cluster on.", call. = FALSE)
knitr::kable(data.frame(variable = names(.miss), missing = sprintf("%.1f%%", 100 * .miss),
                        kept = names(.miss) %in% sid_vars))
```

## Imputation

The forest needs complete data. Each imputation fills the missing values
once, by predictive mean matching (`"mice"`) or by randomForestSRC's forest
imputation (`"forest"`). With one imputation the filled values are treated as
known, so the cluster boundaries are conditional on one draw; with several,
the forests' distances are averaged below. Either way, nothing later describes
the clusters with imputed values.

```{r}
#| label: impute
if (!IMPUTE %in% c("mice", "forest")) stop("IMPUTE must be \"mice\" or \"forest\".", call. = FALSE)
if (!is.numeric(M) || length(M) != 1L || M < 1 || M != trunc(M)) stop("M must be a whole number, 1 or more.", call. = FALSE)
CACHE_DIR <- dirname(set_path("estimates", "sid.rds"))
.to_impute <- d[sid_vars]
.n_missing <- sum(is.na(.to_impute))
# Imputation m is cached under its own name and seeded SEED + m - 1, so raising
# M later reuses the imputations already made.
d_complete <- lapply(seq_len(M), function(m) {
  if (.n_missing == 0L) return(.to_impute)
  s <- SEED + m - 1L
  if (identical(IMPUTE, "mice")) {
    imp <- cache_fit(paste0("sid-fit-impute-", m),
                     mice::mice(.to_impute, m = 1, maxit = MICE_MAXIT, method = "pmm", printFlag = FALSE),
                     seed = s, dir = CACHE_DIR, refit = REFIT)
    mice::complete(imp, 1)
  } else {
    cache_fit(paste0("sid-fit-impute-", m),
              randomForestSRC::impute(data = .to_impute, ntree = 250, verbose = FALSE),
              seed = s, dir = CACHE_DIR, refit = REFIT)
  }
})
cat("Values imputed in each of", M, "imputation(s):", .n_missing, "\n")
```

## The SID forest

```{r}
#| label: fit
#| message: true
# No na.action: the data are complete by now, and sidClustering() fails with
# na.action = "na.impute" when a value IS missing, so a gap here is a bug.
# cache_fit(seed = ) runs each fit under withr::with_seed(), which sets R's
# generator for the holdout-VIMP step; `seed =` is the forest's own.
sid_fits <- lapply(seq_len(M), function(m) {
  if (anyNA(d_complete[[m]])) stop("Missing values reached the SID fit after imputation ", m, ".", call. = FALSE)
  s <- SEED + m - 1L
  cache_fit(paste0("sid-fit-", m),
            sidClustering(d_complete[[m]], method = "sid", ntree = NTREE, reduce = SID_REDUCE, seed = -abs(s)),
            seed = s, dir = CACHE_DIR, refit = REFIT)
})
sid_dist <- Reduce(`+`, lapply(sid_fits, `[[`, "dist")) / M
# How closely each imputation's distances follow the mean. Near 1, the
# imputations agree; well below, the missing values are shaping the distance.
.lower <- function(x) x[lower.tri(x)]
sid_agreement <- data.frame(
  imputation = seq_len(M),
  correlation_with_mean = vapply(sid_fits, function(f) stats::cor(.lower(f$dist), .lower(sid_dist)), numeric(1))
)
```

```{r}
#| label: tbl-used
#| tbl-cap: "What the forests were grown on"
knitr::kable(data.frame(
  step = c("Clustering variables", "Dropped before the fit", "Kept by the reduce step", "Imputation", "Patients"),
  value = c(toString(sid_vars), if (nrow(sid_dropped)) toString(sid_dropped$variable) else "none",
            toString(unique(unlist(lapply(sid_fits, `[[`, "outcome.names")))),
            if (.n_missing == 0L) "none needed" else paste0(IMPUTE, ", ", M, " imputation(s)"),
            nrow(sid_dist))
), col.names = c("", ""))
if (M > 1L) knitr::kable(sid_agreement, digits = 3, caption = "Agreement of each imputation's distances with their mean")
```

## Save

```{r}
#| label: save
# The product of this job, and what sid-clusters and vt-fit read. It is
# separate from the cache on purpose: cache_fit() stores a keyed record, so the
# cache is this job's internals and this file is its interface. The forests
# are not saved: nothing downstream reads them, and they are the large part.
# Patients are named by a study-keyed digest of their ID, never the ID itself
# (#203), so the file can be matched on without holding an MRN.
.key <- hvtiRtemplates:::.study_id_key(.root)
dimnames(sid_dist) <- rep(list(hvtiRtemplates:::.id_digest(d[[.id]], .key)), 2L)
.cohort <- list(n = as.integer(nrow(d)))
sid_handoff <- hvtiRtemplates:::.attach_handoff_lineage(
  list(dist = sid_dist, id_key = hvtiRtemplates:::.id_key_fingerprint(.key), vars = sid_vars, dropped = sid_dropped,
       reduced = unique(unlist(lapply(sid_fits, `[[`, "outcome.names"))),
       settings = list(ntree = NTREE, sid_reduce = SID_REDUCE, seed = SEED, impute = IMPUTE, m = M,
                       mice_maxit = MICE_MAXIT, max_missing = MAX_MISSING)),
  data = .provenance_data,
  cohort = .cohort,
  selection = attr(job_data$record, "selection")
)
saveRDS(sid_handoff, set_path("estimates", "sid.rds"))
```

```{r}
#| label: provenance
#| echo: false
#| results: asis
cat(hvtiRtemplates:::.embed_provenance(
  .in,
  data = .provenance_data,
  run = .job$run,
  extra = list(subject = SUBJECT, type = TYPE, cohort = .cohort)
))
```
````

`attr(job_data$record, "selection")$id` is the ID column as resolved (after any fallback to MRN), set at `R/job-data.R:842`.

- [ ] **Step 5: The `.lintr` key**

In `.lintr`, before the `sid-clusters.qmd` entry, add:

```r
    "inst/templates/30_analyses/sid-fit.qmd" = list(
      object_name_linter = Inf,
      commented_code_linter = Inf,
      object_usage_linter = Inf
    ),
```

- [ ] **Step 6: Run the tests, time the reduce test**

```bash
R CMD INSTALL --no-test-load -l "$SID_LIB" . >/dev/null 2>&1
NOT_CRAN=true R_LIBS="$SID_LIB" Rscript -e 'system.time(devtools::test(filter = "sid-templates"))'
```

Expected: PASS, 11 tests. Record the elapsed time in the commit message. If it exceeds 60 seconds, set the seed test's `NTREE` to 200, which still recovered the groups in review.

- [ ] **Step 7: Prove the seed test by mutation**

In the `fit` chunk, change `seed = s, dir = CACHE_DIR` to `dir = CACHE_DIR` in the `sidClustering` call's `cache_fit()`, so no seed is set for R's generator. Reinstall, and rerun with `filter = "sid-templates"`.
Expected: "the seed reproduces a reduce = TRUE fit" FAILS. Restore it, reinstall, and rerun to confirm it passes. Do not commit the mutation.

If the test still passes under the mutation, `cache_fit()` without `seed` has fallen back to some fixed seed. Read `hvtiRutilities:::.cache_run` and mutate whatever sets the generator instead. A mutation test that cannot go red proves nothing.

- [ ] **Step 8: The catalog-wide counts, and the ledger row**

`sid-fit` is the first new template here that reads its own data. In `tests/testthat/test-template-data-routes.R`, add `"sid-fit.qmd"` to `patient_level_templates` after `"vp-fit.qmd"`, and add one to the `readers` total that test expects. Run it to read the current number:

```bash
R CMD INSTALL --no-test-load -l "$SID_LIB" . >/dev/null 2>&1
R_LIBS="$SID_LIB" Rscript -e 'devtools::test(filter = "template-data-routes|template-provenance")'
```

In `tests/testthat/test-template-provenance.R`, add `"sid-fit"` after `"vp-fit"` in the list of templates that read data (line 249 at `88cd7cd`), and raise `expect_equal(nrow(templates), …)` (line 172) by one more; Task 2 already raised it once, for `sid-clusters`. Rerun the command above; expect PASS.

`check-roadmap-counts.py` fails a commit that adds a template no ledger row claims, and a `queued` row does not claim one. Set the `(sid, fit)` row in `inst/extdata/templates.json` to `"status": "in-flight"`. Start its `note` with "Released for review in a real study. Becomes shipped once a study renders sid-fit and sid-clusters end to end." and keep the existing note after it. Then:

```bash
python3 dev/specs/artifacts/roadmap_render.py && python3 dev/specs/artifacts/check-roadmap-counts.py
```

Expected: no error.

- [ ] **Step 9: Commit**

```bash
git add inst/templates/30_analyses/sid-fit.qmd tests/testthat/helper-sid.R tests/testthat/test-sid-templates.R .lintr \
  tests/testthat/test-template-data-routes.R tests/testthat/test-template-provenance.R inst/extdata/templates.json \
  dev/specs/2026-08-29-template-conversion-roadmap.md
git commit -m "feat(sid-fit): mice or forest imputation over M, seeded SID forests pooled, digest-keyed sid.rds"
```

---

### Task 4: `sid-clusters.qmd`, from the handoff to the save

**Files:**
- Modify: `inst/templates/30_analyses/sid-clusters.qmd` (append after `sid-helpers`)
- Modify: `tests/testthat/helper-sid.R`, `tests/testthat/test-sid-templates.R`

**Interfaces:**
- Consumes: `sid.rds` (Task 3); `sid_align_labels`, `sid_collapse`, `sid_mds_signs` (Task 2).
- Produces:
  - `datasets/<subject>-<type>-clusters.csv` with columns `<id>`, `C<k>` for each k in `K_RANGE`, and `G<K>` when `COLLAPSE` is set;
  - the registered dataset `clusters_<subject>_<type>`, `kind = "ancillary"`, `key = <id>`: registered on the first render, a new dated version via `update_manifest()` on each later one;
  - `estimates/<subject>-<type>/sid-clusters.rds`, `list(clusters, id_key, pam, metrics, letters, k, overrides, collapse)` with lineage. Its parts:
    - `clusters` is `data.frame(id = <ID digest, character>, cluster = <letter at K, character>)`, plus `group` when `COLLAPSE` is set, or `NULL` while `K` is `NULL`. **This is the element `vt-explain` reads** (agreed with the vt design session, 2026-10-22);
    - `id_key` is the key fingerprint copied from `sid.rds`;
    - `pam` is the list of `pam` fits by k;
    - `metrics` is a data frame (`k`, `objective`, `silhouette`);
    - `letters` is a list by `pm<k>` of PAM number → letter maps.
  - Chunk objects used by tests: `sid_letters` (the data frame written to the CSV), `sid_metrics`, `sid_mds`.

- [ ] **Step 1: Test helpers**

Append to `tests/testthat/helper-sid.R`:

```r
sid_clusters_choices <- list(K_RANGE = 2:5, K = 3L, OVERRIDES = list(), COLLAPSE = NULL, MIN_SIZE = 20,
                             K_METRICS_MAX = 8, SAVE_FIGURES = FALSE, FIGURES = NULL)

# Every chunk of sid-clusters, in order.
sid_clusters_labels <- c("setup", "edit-study-choices", "sid-helpers", "handoff", "pam", "fig-metrics", "tbl-metrics",
                         "tbl-sizes", "fig-sankey", "fig-silhouette", "tbl-silhouette", "fig-mds", "tbl-collapse",
                         "save")

# sid-clusters run in the set a sid-fit just wrote, in the same study.
sid_clusters_after <- function(env, choices = sid_clusters_choices) {
  rf_run("sid", "clusters", sid_clusters_labels, env, choices)  # nolint: object_usage_linter.
}
```

`rf_run()` reruns `setup` in the same environment; `SUBJECT` and `TYPE` are identical in both templates, so `set_path` points at the same set.

- [ ] **Step 2: Write the failing tests**

Append to `tests/testthat/test-sid-templates.R`:

```r
test_that("sid-clusters recovers planted clusters at K = 3", {
  skip_on_cran()
  rf_skip_unless_stack(unique(c(rf_template_packages("sid", "fit"), rf_template_packages("sid", "clusters"))))
  env <- sid_fit_first()
  sid_clusters_after(env)
  truth <- sid_data()$truth
  score <- randomForestSRC::sid.perf.metric(factor(truth), factor(env$sid_letters$C3))$normalized_measure
  expect_lt(score, 0.2)
  expect_identical(env$sid_metrics$k, 1:8)
})

test_that("sid-clusters reads sid.rds and never fits", {
  rf_skip_unless_stack(rf_template_packages("sid", "clusters"))
  src <- readLines(template_path("sid", "clusters"), warn = FALSE)
  expect_false(any(grepl("sidClustering(", src, fixed = TRUE)))
  env <- rf_env(sid_data())
  expect_error(rf_run("sid", "clusters", sid_clusters_labels[1:4], env, sid_clusters_choices),
               "Render the sid-fit job in this set first")
})

test_that("sid-clusters writes and registers the cluster letters, and nothing else", {
  skip_on_cran()
  rf_skip_unless_stack(unique(c(rf_template_packages("sid", "fit"), rf_template_packages("sid", "clusters"))))
  env <- sid_fit_first()
  sid_clusters_after(env, utils::modifyList(sid_clusters_choices, list(COLLAPSE = list(Z = c("B", "C")))))
  csv <- file.path(hvtiRutilities::study_dir("datasets", env$.root), "morphology-sid-clusters.csv")
  out <- utils::read.csv(csv)
  expect_identical(names(out), c("ccfid", "C2", "C3", "C4", "C5", "G3"))
  expect_identical(nrow(out), 150L)
  cfg <- hvtiRutilities::study_config(start = env$.root)
  expect_true("clusters_morphology_sid" %in% names(cfg$additional_datasets))
  # A second render with letters pinned differently re-registers, and a read
  # returns the new letters.
  # The K = 2 map the first render chose, PAM number -> letter, reversed.
  map <- readRDS(env$set_path("estimates", "sid-clusters.rds"))$letters$pm2
  flip <- stats::setNames(rev(unname(map)), names(map))
  sid_clusters_after(env, utils::modifyList(sid_clusters_choices, list(OVERRIDES = list(pm2 = flip))))
  again <- read_job_data(hvtiRutilities::study_config(start = env$.root), join = "clusters_morphology_sid")$data
  expect_false(identical(again$c2[again$ccfid == out$ccfid[1]], out$C2[1]))
})

test_that("K = NULL renders the metrics and skips what needs K; a final render or a K outside K_RANGE stops", {
  skip_on_cran()
  rf_skip_unless_stack(unique(c(rf_template_packages("sid", "fit"), rf_template_packages("sid", "clusters"))))
  env <- sid_fit_first()
  # modifyList() would drop an element set to NULL, so K = NULL is rebuilt with c().
  no_k <- c(sid_clusters_choices[setdiff(names(sid_clusters_choices), "K")], list(K = NULL))
  sid_clusters_after(env, no_k)
  expect_false(is.null(env$sid_metrics))
  expect_null(env$sid_mds)
  expect_null(readRDS(env$set_path("estimates", "sid-clusters.rds"))$clusters)
  withr::with_envvar(c(HVTI_TEMPLATE_STRICT = "true"),
                     expect_error(rf_run("sid", "clusters", sid_clusters_labels[c(2:4)], env, no_k), "set K"))
  expect_error(sid_clusters_after(env, utils::modifyList(sid_clusters_choices, list(K = 9L))), "K_RANGE")
})

test_that("the clusters element vt reads holds one digest-keyed letter per patient, and no raw ID", {
  skip_on_cran()
  rf_skip_unless_stack(unique(c(rf_template_packages("sid", "fit"), rf_template_packages("sid", "clusters"))))
  env <- sid_fit_first()
  sid_clusters_after(env)
  h <- readRDS(env$set_path("estimates", "sid-clusters.rds"))
  key <- hvtiRtemplates:::.study_id_key(env$.root)
  expect_identical(names(h$clusters), c("id", "cluster"))
  expect_setequal(h$clusters$id, hvtiRtemplates:::.id_digest(seq_len(150L), key))
  expect_identical(h$clusters$cluster, as.character(env$sid_letters$C3[match(h$clusters$id, rownames(env$sid$dist))]))
  expect_identical(h$id_key, hvtiRtemplates:::.id_key_fingerprint(key))
})
```

The strict check runs `edit-study-choices`, `sid-helpers` and `handoff` only, after a full run has already set up `env`. If `.strict_render()` reads a different variable than `HVTI_TEMPLATE_STRICT`, read `R/job-setup.R:90-118` and use that one.

- [ ] **Step 3: Run them to see them fail**

```bash
R CMD INSTALL --no-test-load -l "$SID_LIB" . >/dev/null 2>&1
NOT_CRAN=true R_LIBS="$SID_LIB" Rscript -e 'devtools::test(filter = "sid-templates")'
```

Expected: the four new tests FAIL with "chunk not found: handoff" (or `rf_chunk`'s equivalent message).

- [ ] **Step 4: Add the chunks**

In `inst/templates/30_analyses/sid-clusters.qmd`, replace the stub `provenance` chunk from Task 2 with the following. It ends with the full `provenance` chunk.

````markdown
## The dissimilarity

```{r}
#| label: handoff
.handoff <- set_path("estimates", "sid.rds")
if (!file.exists(.handoff)) {
  stop("No SID fit at ", .handoff, ". Render the sid-fit job in this set first; ",
       "this job clusters that fit and never grows its own.", call. = FALSE)
}
.cfg <- study_config(start = .root)
.sid_read <- hvtiRtemplates:::.read_handoff(.handoff, "SID fit", .cfg, "the sid-fit job")
sid <- .sid_read$value
.provenance_data <- .sid_read$lineage$data
.provenance_artifacts <- c(.sid_read$lineage$artifacts, list(.sid_read$record))
D <- stats::as.dist(sid$dist)
# sid.rds names patients by a study-keyed digest of their ID, never the ID. The
# fit's rows are rebuilt from its recorded selection, which checks the rows and
# their key hash, and each rebuilt ID is digested and matched to the distance.
.key <- hvtiRtemplates:::.study_id_key(.root)
if (!identical(hvtiRtemplates:::.id_key_fingerprint(.key), sid$id_key)) {
  stop("This study's ID key has changed since sid-fit ran, so its patients cannot be matched. Rerun sid-fit.",
       call. = FALSE)
}
.up <- hvtiRtemplates:::.read_upstream_job_data(.cfg, .sid_read$lineage, list(), source = "sid.rds")
.id <- .up$selection$id
.rebuilt <- .up$job_data$data[[.id]]
.at_fit <- match(rownames(sid$dist), hvtiRtemplates:::.id_digest(.rebuilt, .key))
if (anyNA(.at_fit)) stop("The rebuilt cohort lacks patients the SID fit clustered; rerun sid-fit.", call. = FALSE)
sid_ids <- .rebuilt[.at_fit]
if (any(diff(K_RANGE) != 1) || min(K_RANGE) < 2L) {
  stop("K_RANGE must be consecutive and start at 2 or more, such as 2:9.", call. = FALSE)
}
if (!is.null(K) && !K %in% K_RANGE) stop("K = ", K, " is not in K_RANGE (", toString(K_RANGE), ").", call. = FALSE)
# A draft may leave K unset to choose it from the metrics below; a final report
# must name the solution it reports.
if (is.null(K) && hvtiRtemplates:::.strict_render()) {
  stop("K is NULL. Choose it from the metrics in a draft render, then set K in the study choices.", call. = FALSE)
}
cat("Patients:", attr(D, "Size"), " Clustering variables:", toString(sid$vars), "\n")
```

## PAM over K

PAM (partitioning around medoids) chooses K patients as centres and assigns
everyone to the nearest one, here by the SID distance itself. It is
deterministic given the distance, so this job needs no seed.

```{r}
#| label: pam
.ks <- seq_len(max(K_RANGE, K_METRICS_MAX))
sid_pam <- lapply(.ks, function(k) cluster::pam(D, k))
names(sid_pam) <- paste0("pm", .ks)
sid_metrics <- data.frame(
  k = .ks,
  objective = vapply(sid_pam, function(p) unname(p$objective[["swap"]]), numeric(1)),
  silhouette = vapply(.ks, function(k) if (k == 1L) NA_real_ else sid_pam[[k]]$silinfo$avg.width, numeric(1))
)
sid_metrics$objective <- sid_metrics$objective / sid_metrics$objective[1]
```

## Choosing K

The elbow is the PAM objective, each patient's distance to its medoid,
relative to one cluster. It always falls as K grows; K is chosen where the
fall levels off, which is read by eye and stated as a judgment. The average
silhouette compares each patient's distance to its own cluster with its
distance to the nearest other one: near 1 is well separated, near 0 is on a
boundary. Its maximum is one suggestion, not a rule. Neither says whether
the clusters mean anything clinically.

```{r}
#| label: fig-metrics
#| fig-cap: "PAM objective (normalized to K = 1) and average silhouette by K"
.long <- rbind(data.frame(k = sid_metrics$k, value = sid_metrics$objective, metric = "PAM objective"),
               data.frame(k = sid_metrics$k, value = sid_metrics$silhouette, metric = "Average silhouette"))
.long <- .long[!is.na(.long$value), ]
.plt_metrics <- ggplot2::ggplot(.long, ggplot2::aes(k, value)) +
  ggplot2::geom_line() + ggplot2::geom_point() +
  ggplot2::facet_wrap(~metric, ncol = 1, scales = "free_y") +
  ggplot2::scale_x_continuous("Clusters (K)", breaks = sid_metrics$k) +
  ggplot2::labs(y = NULL) +
  hvtiPlotR::theme_hv_manuscript(base_size = 12)
save_figure(.plt_metrics, "sid-clusters-metrics", height = 5)
.plt_metrics
```

```{r}
#| label: tbl-metrics
#| tbl-cap: "K metrics; the silhouette maximum is marked"
.best <- sid_metrics$k[which.max(sid_metrics$silhouette)]
knitr::kable(transform(sid_metrics, objective = round(objective, 3), silhouette = round(silhouette, 3),
                       note = ifelse(k == .best, "silhouette maximum", "")))
```

## Letters across K

```{r}
#| label: tbl-sizes
#| tbl-cap: "Patients per cluster at each K, by letter (PAM number in brackets)"
.pm <- as.data.frame(lapply(sid_pam[paste0("pm", K_RANGE)], function(p) p$clustering))
.letters <- sid_align_labels(.pm, OVERRIDES)
sid_letters <- data.frame(sid_ids, .letters, check.names = FALSE)
names(sid_letters) <- c(.id, paste0("C", K_RANGE))
.sizes <- do.call(rbind, lapply(K_RANGE, function(k) {
  tab <- table(.letters[, paste0("pm", k)], .pm[[paste0("pm", k)]])
  data.frame(K = k, letter = rownames(tab), pam = colnames(tab)[apply(tab, 1, which.max)],
             n = as.integer(rowSums(tab)))
}))
knitr::kable(.sizes)
.small <- if (!is.null(K)) .sizes[.sizes$K == K & .sizes$n < MIN_SIZE, ] else .sizes[0, ]
if (nrow(.small)) {
  warning("At K = ", K, ", cluster(s) ", toString(.small$letter), " hold fewer than ", MIN_SIZE, " patients.",
          call. = FALSE)
  cat("\n::: {.callout-warning}\nAt K = ", K, ", cluster(s) ", toString(.small$letter), " hold fewer than ",
      MIN_SIZE, " patients, too few for per-cluster tables or a vp-fit to say much.\n:::\n", sep = "")
}
```

```{r}
#| label: fig-sankey
#| fig-cap: "How patients move between clusters as K grows"
.sk <- hvtiPlotR::hv_sankey(sid_letters, cluster_cols = paste0("C", K_RANGE))
.plt_sankey <- plot(.sk) + hvtiPlotR::theme_hv_manuscript(base_size = 12)
# The page is 6.5 in wide; the Sankey's columns need its full width.
save_figure(.plt_sankey, "sid-clusters-sankey", width = 6.5, height = 6)
.plt_sankey
```

A cluster that keeps its letter and most of its patients across several K
is stable; one that forms and dissolves between neighbouring K is not.

## The solution at K

```{r}
#| label: fig-silhouette
#| fig-cap: "Silhouette width of every patient at K, by cluster"
sid_mds <- NULL
if (is.null(K)) {
  cat("K is NULL: the sections that describe one solution are skipped. Set K in the study choices.\n")
} else {
  .at <- sid_letters[[paste0("C", K)]]
  .sil <- cluster::silhouette(sid_pam[[K]]$clustering, D)
  .sil_d <- data.frame(letter = .at, width = .sil[, "sil_width"])
  .sil_d <- .sil_d[order(.sil_d$letter, -.sil_d$width), ]
  .sil_d$rank <- seq_len(nrow(.sil_d))
  .plt_sil <- ggplot2::ggplot(.sil_d, ggplot2::aes(rank, width, fill = letter)) +
    ggplot2::geom_col(width = 1) + ggplot2::coord_flip() +
    ggplot2::labs(x = NULL, y = "Silhouette width", fill = "Cluster") +
    hvtiPlotR::theme_hv_manuscript(base_size = 12) +
    ggplot2::theme(axis.text.y = ggplot2::element_blank(), axis.ticks.y = ggplot2::element_blank())
  save_figure(.plt_sil, "sid-clusters-silhouette")
  print(.plt_sil)
}
```

```{r}
#| label: tbl-silhouette
#| tbl-cap: "Average silhouette width and share of negative widths, by cluster at K"
if (!is.null(K)) {
  knitr::kable(do.call(rbind, lapply(split(.sil_d$width, .sil_d$letter), function(w) {
    data.frame(n = length(w), average = round(mean(w), 3), negative = sprintf("%.0f%%", 100 * mean(w < 0)))
  })))
}
```

A negative width means a patient is closer to another cluster than to its
own. A cluster with many is poorly separated even when the average looks
acceptable.

```{r}
#| label: fig-mds
#| fig-cap: "Patients placed in two dimensions by classical MDS of the SID distance, coloured by cluster at K"
if (!is.null(K)) {
  sid_mds <- sid_mds_signs(stats::cmdscale(D, k = 2))
  .plt_mds <- ggplot2::ggplot(data.frame(x = sid_mds[, 1], y = sid_mds[, 2], letter = .at),
                              ggplot2::aes(x, y, colour = letter)) +
    ggplot2::geom_point(alpha = 0.7) +
    ggplot2::labs(x = "Dimension 1", y = "Dimension 2", colour = "Cluster") +
    hvtiPlotR::theme_hv_manuscript(base_size = 12)
  save_figure(.plt_mds, "sid-clusters-mds")
  print(.plt_mds)
}
```

Two dimensions keep only part of the distance, so clusters that overlap
here may still be separate; the silhouette above is the better guide.

```{r}
#| label: tbl-collapse
#| tbl-cap: "Clusters at K and the groups COLLAPSE makes of them"
if (!is.null(K) && !is.null(COLLAPSE)) {
  sid_letters[[paste0("G", K)]] <- sid_collapse(.at, COLLAPSE)
  knitr::kable(as.data.frame.matrix(table(cluster = .at, group = sid_letters[[paste0("G", K)]])))
}
```

## Reading the result

A SID cluster is a region of the clustering variables where patients are
alike, found without any outcome. It is a description, not a diagnosis, and
the letters carry no order. Read the Sankey for stability, the silhouette
for separation, and the sizes for whether a cluster is large enough to say
anything about. To describe the clusters, a `dc-tables` job joins the
registered dataset below; to ask which variables separate them, a `vp-fit`
job takes the cluster at K as a classification outcome.

## Save

```{r}
#| label: save
# The letters, for any later job to JOIN by the patient ID. Only the ID and
# letters are written: no clustering variable leaves this job.
.csv_name <- paste0(SUBJECT, "-", TYPE, "-clusters.csv")
.dataset <- tolower(paste0("clusters_", SUBJECT, "_", TYPE))
utils::write.csv(sid_letters, file.path(hvtiRutilities::study_dir("datasets", .root), .csv_name), row.names = FALSE)
# register_data() registers a dataset once and stops on a second call. A later
# render records the rewritten file as a new dated version instead, so later
# jobs read the current letters and their manifest check passes.
if (.dataset %in% names(.cfg$additional_datasets)) {
  utils::capture.output(suppressMessages(
    withr::with_dir(.root, hvtiRutilities::update_manifest(dataset = .dataset))
  ))
} else {
  utils::capture.output(suppressMessages(
    hvtiRutilities::register_data(.root, built = .csv_name, dataset = .dataset, role = "named",
                                  population = "SID cluster assignments", kind = "ancillary", key = .id)
  ))
}
cat("Registered `", .dataset, "`: set JOIN <- \"", .dataset, "\" in a later job to use these clusters.\n",
    "A job that models one row per patient also sets REDUCE <- list(rule = \"first\", by = \"", .id, "\").\n",
    sep = "")
# The solution at K for jobs that read this file rather than the dataset, such
# as vt-explain's stratifier: patients by ID digest, as in sid.rds, never by ID.
sid_clusters <- if (!is.null(K)) {
  out <- data.frame(id = rownames(sid$dist), cluster = as.character(sid_letters[[paste0("C", K)]]))
  if (!is.null(COLLAPSE)) out$group <- as.character(sid_letters[[paste0("G", K)]])
  out
}
.cohort <- list(n = as.integer(attr(D, "Size")))
sid_clusters_handoff <- hvtiRtemplates:::.attach_handoff_lineage(
  list(clusters = sid_clusters, id_key = sid$id_key, pam = sid_pam, metrics = sid_metrics,
       letters = lapply(stats::setNames(paste0("pm", K_RANGE), paste0("pm", K_RANGE)), function(col) {
         tab <- table(.pm[[col]], .letters[, col])
         stats::setNames(colnames(tab)[apply(tab, 1, which.max)], rownames(tab))
       }),
       k = K, overrides = OVERRIDES, collapse = COLLAPSE),
  data = .provenance_data,
  artifacts = .provenance_artifacts,
  cohort = .cohort
)
saveRDS(sid_clusters_handoff, set_path("estimates", "sid-clusters.rds"))
```

```{r}
#| label: provenance
#| echo: false
#| results: asis
cat(hvtiRtemplates:::.embed_provenance(
  .in,
  data = .provenance_data,
  artifacts = .provenance_artifacts,
  run = .job$run,
  extra = list(subject = SUBJECT, type = TYPE, cohort = .cohort)
))
```
````

`artifacts =` is how `vp-explain`'s provenance chunk records the handoff it read; check its exact form there and match it.

Checked against the code while writing this plan:

- `.read_handoff(path, role, cfg, rebuild)` is `vp-explain`'s call shape (`R/provenance.R:637`).
- `.attach_handoff_lineage()` accepts `artifacts =` (`R/provenance.R:603`).
- `.read_upstream_job_data(cfg, lineage, settings, read = TRUE, source)` returns `list(job_data, selection)`, and `settings = list()` takes every field from upstream (`R/job-data.R:1185`, `1231`).
- `register_data()` stops with "already registered" on a second call. The no-argument form of `update_manifest()` finds the study from the working directory, hence `withr::with_dir()`. `withr` is in `Suggests`; check that a template may use it by searching `inst/templates` for `withr::`. If none does, use `old <- setwd(.root); on.exit(setwd(old), add = TRUE)` inside a `local({ ... })` instead.

- [ ] **Step 5: Run the tests**

```bash
R CMD INSTALL --no-test-load -l "$SID_LIB" . >/dev/null 2>&1
NOT_CRAN=true R_LIBS="$SID_LIB" Rscript -e 'devtools::test(filter = "sid-templates")'
```

Expected: PASS, 16 tests. If the recovery test's score is above 0.2, print `table(truth, env$sid_letters$C3)` before changing anything. The review measured 0.12 at `NTREE = 200` on this cohort, so a high score at 500 points to a bug, most likely `sid_ids` misordered against `rownames(sid$dist)`.

- [ ] **Step 6: The catalog-wide gates**

```bash
R_LIBS="$SID_LIB" Rscript -e 'devtools::test(filter = "template-|figure-standard")'
```

Expected: PASS. The figure standard reads every `save_figure()` width and every theme call in the file.

- [ ] **Step 7: Commit**

```bash
git add inst/templates/30_analyses/sid-clusters.qmd tests/testthat/helper-sid.R tests/testthat/test-sid-templates.R
git commit -m "feat(sid-clusters): PAM over K, K metrics, stable letters, Sankey, clusters for vt, the registered dataset"
```

---

### Task 5: Later jobs consume the clusters

Spec §5: a long read and a one-row-per-patient read both JOIN the registered dataset. The second needs `REDUCE <- list(rule = "first", by = <ID>)`, which the plan's review confirmed works (a non-ID, non-date `by` such as `"c2"` errors). Task 4's `save` chunk already prints that line.

**Files:**
- Modify: `tests/testthat/test-sid-templates.R`
- Modify: `inst/templates/30_analyses/sid-clusters.qmd` (one sentence at the end of "Reading the result")

**Interfaces:**
- Consumes: the registered dataset `clusters_<subject>_<type>` (Task 4).

- [ ] **Step 1: Write the test**

Append to `tests/testthat/test-sid-templates.R`:

```r
test_that("a later job joins the registered clusters, one per patient", {
  skip_on_cran()
  rf_skip_unless_stack(unique(c(rf_template_packages("sid", "fit"), rf_template_packages("sid", "clusters"))))
  env <- sid_fit_first()
  sid_clusters_after(env)
  cfg <- hvtiRutilities::study_config(start = env$.root)
  long <- read_job_data(cfg, join = "clusters_morphology_sid")
  expect_identical(nrow(long$data), 150L)
  expect_true(all(c("c2", "c3") %in% tolower(names(long$data))))
  expect_error(read_job_data(cfg, join = "clusters_morphology_sid", one_row_per_patient = TRUE), "REDUCE")
  one <- read_job_data(cfg, join = "clusters_morphology_sid", reduce = list(rule = "first", by = "ccfid"),
                       one_row_per_patient = TRUE)
  expect_identical(nrow(one$data), 150L)
  expect_identical(anyDuplicated(one$data$ccfid), 0L)
})
```

- [ ] **Step 2: Run it**

```bash
R CMD INSTALL --no-test-load -l "$SID_LIB" . >/dev/null 2>&1
NOT_CRAN=true R_LIBS="$SID_LIB" Rscript -e 'devtools::test(filter = "sid-templates")'
```

Expected: PASS, 17 tests.

- [ ] **Step 3: Say it in the report**

At the end of "Reading the result" in `sid-clusters.qmd`, add: "A job that models one row per patient, such as `vp-fit`, also sets `REDUCE` to keep the first record by the patient ID; the line to use is printed in the save section below."

- [ ] **Step 4: Run and commit**

Rerun Step 2's command; expect PASS.

```bash
git add inst/templates/30_analyses/sid-clusters.qmd tests/testthat/test-sid-templates.R
git commit -m "test(sid): later jobs join the registered clusters, with the REDUCE a one-row job needs"
```

---

### Task 6: Documentation, MRN scan and the full gate

**Files:**
- Modify: `inst/templates/README.md` (template table, figure-name table)
- Modify: `tests/testthat/test-template-figures.R` (the `expected` list)
- Modify: `tests/testthat/test-sid-templates.R` (MRN test)
- Create: `news/feat-sid-templates.md`

- [ ] **Step 1: The figure names (the failing test)**

In `tests/testthat/test-template-figures.R`, inside the `expected <- list(` call, after the `` `vp-explain` `` entry, add:

```r
    `sid-clusters` = c("sid-clusters-metrics", "sid-clusters-sankey", "sid-clusters-silhouette", "sid-clusters-mds"),
```

Run: `R_LIBS="$SID_LIB" Rscript -e 'devtools::test(filter = "template-figures")'`. If it fails because `sid-fit` saves no figure and the test expects every template to be listed, add `` `sid-fit` = character(0), `` beside it, matching how the file treats any other template with no figures (search it for `character(0)`).

- [ ] **Step 2: The MRN scan**

Append to `tests/testthat/test-sid-templates.R`:

```r
test_that("no file under estimates/ carries an MRN, though the job's ID is the MRN", {
  skip_on_cran()
  rf_skip_unless_stack(unique(c(rf_template_packages("sid", "fit"), rf_template_packages("sid", "clusters"))))
  d <- rf_mrn_data()  # keyed on a ten-digit MRN, no ccfid
  env <- rf_env(d)
  # ID stays "ccfid", which falls back to MRN here, as in the rf MRN tests:
  # KEY <- ID is evaluated before the choices apply, so overriding ID alone
  # would leave KEY on a column this cohort lacks.
  rf_run("sid", "fit", sid_fit_labels, env, utils::modifyList(sid_fit_choices, list(VARS = c("age", "x1", "los"))))
  # This cohort has no cluster structure, so a small cluster is likely; MIN_SIZE = 1
  # keeps its warning out of the suite's WARN 0.
  sid_clusters_after(env, utils::modifyList(sid_clusters_choices, list(MIN_SIZE = 1)))
  dir <- dirname(env$set_path("estimates", "sid.rds"))
  expect_true(all(c("sid.rds", "sid-clusters.rds") %in% list.files(dir)))
  # rf_files_holding() (helper-rf.R) searches every file in `dir`, caches and
  # provenance sidecars included, for each MRN as text and as a big-endian double.
  expect_identical(rf_files_holding(dir, d$MRN), character(0))  # nolint: object_usage_linter.
  # The clusters dataset in datasets/ carries the MRN by design: it is how a
  # later job joins it, as the built dataset beside it does.
})
```

**This test passes by design** once `sid.rds` holds no IDs (Task 3). Prove it by mutation: add `id = d[[.id]],` to the list in `sid-fit`'s `save` chunk, reinstall, confirm the test fails naming `sid.rds`, then revert.

If the mice or SID cache file holds an MRN (`rf_files_holding()` names it), the data passed to `mice()` or `sidClustering()` carried the ID column. `.to_impute <- d[sid_vars]` must exclude it; fix the code, not the test.

- [ ] **Step 3: README rows**

In `inst/templates/README.md`, after the `vp-explain.qmd` row of the template table, add:

```markdown
| `30_analyses/sid-fit.qmd` | SID clustering forest on the clustering variables, after mice or forest imputation pooled over M (in flight) | `30_analyses/` or `analyses/` |
| `30_analyses/sid-clusters.qmd` | PAM over K on a `sid-fit` distance: K metrics, letters stable across K, Sankey, registered assignments (in flight) | `30_analyses/` or `analyses/` |
```

In the figure-name table, after the `vp-explain` row, add:

```markdown
| sid-clusters | `sid-clusters-metrics`, `-sankey`, `-silhouette`, `-mds` |
```

If the paragraph at line 87 ("qualified templates are …") lists every qualified template, add `sid-fit` and `sid-clusters` to it in the same style.

- [ ] **Step 4: NEWS fragment**

Create `news/feat-sid-templates.md`:

```markdown
* New templates `sid-fit` and `sid-clusters` (in flight). `sid-fit` fills
  missing values by mice or forest imputation, `M` times, grows one seeded
  SID clustering forest on each and averages their distances. It saves them
  keyed by a study-keyed digest of the patient ID, never the ID.
  `sid-clusters` runs PAM on that distance over a range of K, reports the
  elbow and silhouette, gives letters that keep their identity across K,
  saves the chosen solution for `vt`, and registers the assignments so a
  later job can `JOIN` them. The `sid` prefix
  is now qualified, so `add_job("sid", ...)` needs `qualifier = "fit"` or
  `"clusters"`.
```

- [ ] **Step 5: The full gate**

```bash
R CMD INSTALL --no-test-load -l "$SID_LIB" . >/dev/null 2>&1
Rscript -e 'devtools::document()'
git status --short man NAMESPACE   # expect nothing: no roxygen changed
NOT_CRAN=true R_LIBS="$SID_LIB" Rscript -e 'devtools::test()' 2>&1 | tail -5
Rscript -e 'lintr::lint_package()'
python3 dev/specs/artifacts/check-spec-counts.py && python3 dev/specs/artifacts/check-flow-counts.py \
  && python3 dev/specs/artifacts/check-roadmap-counts.py
R_LIBS="$SID_LIB" Rscript -e 'devtools::check(error_on = "note")' 2>&1 | tail -15
```

Expected:
- the test summary reads `FAIL 0`, `SKIP 0` and `WARN 0`, apart from warnings an `origin/main` run of the same command also shows (a local run reports `test-rf-templates.R` warnings that CI muffles). Compare the two;
- `lint_package()` prints nothing;
- the three scripts exit 0;
- `check()` is 0 errors, 0 warnings, 0 notes.

- [ ] **Step 6: Commit**

```bash
git add inst/templates/README.md tests/testthat/test-template-figures.R tests/testthat/test-sid-templates.R \
  news/feat-sid-templates.md
git commit -m "docs(sid): README, figure names, MRN scan and NEWS"
```

Add the MRN-fix files from Step 2 by name if that step changed a template.

- [ ] **Step 7: Review and PR**

1. Run `/code-review` on the branch.
2. Check the Copilot quota with the reviews command in `AGENTS.md`.
3. Push `feat/sid-templates` and open the PR against `main`. Its body names:
   - the spec;
   - the `REDUCE` finding from Task 5;
   - the reduce-test timing;
   - that the local review stood in for Copilot.
4. Comment on hvtiRforests#1 that `sid` no longer waits on it, linking the PR.

---

## Out of scope (follow-ups)

- Relaxing `read_job_data()` so a one-row job's JOIN keyed on the ID needs no `REDUCE` (only if Task 5 shows the workaround is awkward).
- Moving `sid_align_labels()`, `sid_collapse()` and `sid_mds_signs()` to hvtiRforests once `vt` needs shared method code.
- Flipping both rows to `shipped` after a study renders the pair.
