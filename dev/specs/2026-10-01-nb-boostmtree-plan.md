# nb-boostmtree Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `inst/templates/30_analyses/nb-boostmtree.qmd`, a one-job template that fits boosted multivariate trees on longitudinal data with the CCF `boostmtree` fork and reports it with ggBoostedTrees, under the data contract and with no patient identifier in anything it saves.

**Architecture:** One Quarto job in the shape of `rfs-fit.qmd`: `setup`, `guard-edits`, `set`, `edit-study-choices`, `data`, `fit` (through `hvtiRutilities::cache_fit()`), six report chunks, `save`, `provenance`. Patient IDs are replaced by the study-keyed digest (`hvtiRtemplates:::.id_digest()`) **before** the fit, so the fit, its cache and the saved file never hold a raw ID. The catalog row `nb` splits into two qualified rows. No `R/` function is added.

**Tech Stack:** R, Quarto, testthat 3e, `boostmtree` (>= 2.0.2, `ehrlinger/boostmtree_src`), `ggBoostedTrees`, `hvtiRutilities`, `hvtiPlotR`, `withr`.

**Spec:** `dev/specs/2026-10-01-nb-boostmtree-design.md`.

### Two refinements to the spec, made while planning

Both follow from measurement on 2026-10-01 and keep the spec's intent:

1. **Digest before the fit, not after (spec section 5).** A fitted `boostmtree` holds the ID in `$id`, `$id.unique` **and** inside `$base.learner`: each randomForestSRC learner's `$call` and the environment of its `$forest$sampsize` function. Rewriting those after the fit means editing randomForestSRC internals. Passing `id = .id_digest(d[[.id]], key)` to `boostmtree()` instead means no raw ID ever reaches the fit. `boostmtree` groups by `id` only and accepts character IDs. `gg_boost_trajectory()` labels subjects from `$id.unique`, which is then the digest, one per patient.
2. **The cache is `hvtiRutilities::cache_fit()`, as in every fit template (spec section 5).** Its key covers the code's inputs (`d`, `PREDICTORS`, `FAMILY`, `M`, `NU`), the package versions and the seed. A stale cache **stops** and lists what changed; `REFIT <- TRUE` recomputes it. This is stricter than the spec's "anything else refits", and it matches `rfs-fit`, so a study author meets one rule.

## Global Constraints

- `boostmtree (>= 2.0.2)`. Install hint: `remotes::install_github("ehrlinger/boostmtree_src", subdir = "boostmtree", ref = "v2.0.2-ccf")`. CRAN's 2.0.0 is refused.
- Every study-specific line carries an `EDIT:` marker. A template has exactly one `^SUBJECT\s+<- ` and one `^TYPE\s+<- ` line.
- No study identifiers in the template. Identifier values are never printed or saved in plaintext.
- Settings: `DATASET <- "study"`, `ANALYSIS_SET <- NULL`, `WHERE <- NULL`, `ID <- "ccfid"`, `KEY <- c(ID, TIME)`, `TIME <- "iv_echo"`, `RESPONSE <- "<response>"`, `FAMILY <- "continuous"`, `PREDICTORS <- NULL`, `M <- 1000`, `NU <- 0.05`, `SEED <- 2026`, `EFFECT_VARIABLES <- NULL`, `N_TRACES <- 100`, `REFIT <- FALSE`.
- Lines at most 135 characters; no em dashes; US spelling (`bash tools/check-us-spelling.sh`).
- `lintr::lint_package(cache = FALSE)` gives 0 lints. Roxygen is Rd markup.
- `devtools::test()` gives FAIL 0, WARN 0, SKIP 0 locally. CI expects SKIP 0, or 1 on Windows.
  - Any package a test skips on must be in DESCRIPTION Suggests.
  - Muffle a warning only by its exact message, never with a blanket `suppressWarnings()`.
- In tests, use `withr::local_seed()`, never `set.seed()`; qualify testthat helpers as `testthat::`.
- Run R with `R_LIBS=<scratch lib>` when the plan says so. Install the branch (`R CMD INSTALL --no-test-load .`) before render tests. Chain Bash with `&&`.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never push to main.

---

### Task 1: The template's data half, its catalog row and its dependencies

**Files:**
- Create: `inst/templates/30_analyses/nb-boostmtree.qmd`, the chunks through `data`. Later tasks append.
- Modify: `inst/extdata/templates.json` (the `nb` row), then regenerate the roadmap tables with `python3 dev/specs/artifacts/roadmap_render.py`.
- Modify: `DESCRIPTION` (Suggests, Remotes), `.lintr` (a per-file key), `tests/testthat/test-data-contract.R` (the converted list).
- Create: `tests/testthat/helper-nb.R`, `tests/testthat/test-nb-boostmtree.R`.

**Interfaces:**
- Produces:
  - Template chunks `setup`, `guard-edits`, `set`, `edit-study-choices` and `data`. After `data`, the chunk environment holds `d` (the model's columns only: TIME, RESPONSE, PREDICTORS, plus the resolved ID), `.id` (the resolved ID column name), `.predictors` (the predictor names actually used) and `job_data`.
  - Test helpers `nb_template()`, `nb_data(n, id)`, `nb_study(data)`, `nb_env(root)` and `nb_run(labels, env, choices)`.

- [ ] **Step 1: Write the failing tests.**

Create `tests/testthat/helper-nb.R`:

```r
# nb-boostmtree is run here chunk by chunk, as the rf and hazard templates are.

nb_template <- function() {
  templates <- template_list()
  hit <- which(templates$name == "nb-boostmtree")
  if (length(hit) != 1L) stop("template 'nb-boostmtree' found ", length(hit), " times", call. = FALSE)
  templates$file[[hit]]
}

# Evaluate chunks `labels` in `env`; `choices` overwrite edit-study-choices.
nb_run <- function(labels, env, choices = list()) {
  src <- readLines(nb_template(), warn = FALSE)
  for (label in labels) {
    at <- which(trimws(src) == paste0("#| label: ", label))
    if (length(at) != 1L) stop("chunk '", label, "' found ", length(at), " times", call. = FALSE)
    end <- at + which(src[(at + 1L):length(src)] == "```")[1L]
    suppressMessages(eval(parse(text = src[(at + 1L):(end - 1L)]), envir = env))
    if (identical(label, "edit-study-choices")) list2env(choices, envir = env)
  }
  invisible(env)
}

# A small longitudinal cohort: 40 patients, 3 to 6 visits each, a continuous
# response that drifts with time and age. `id` names the ID column: "ccfid",
# or "MRN" to exercise the fallback that keeps MRN as the job's ID. IDs are
# ten digits, so a byte search cannot match one by chance.
nb_data <- function(n = 40L, id = "ccfid") {
  withr::local_seed(20261001)
  visits <- sample(3:6, n, replace = TRUE)
  pid <- rep(4730000000 + seq_len(n), visits)
  age <- rep(round(stats::runif(n, 30, 80)), visits)
  female <- rep(stats::rbinom(n, 1L, 0.4), visits)
  iv_echo <- unlist(lapply(visits, function(k) sort(round(stats::runif(k, 0, 8), 2))))
  d <- data.frame(id = pid, iv_echo = iv_echo, age = age, female = female, grp = rep(sample(c("a", "b"), n, TRUE), visits))
  d$lvef <- 55 - 0.8 * d$iv_echo + 0.1 * (d$age - 55) - 2 * d$female + stats::rnorm(nrow(d), 0, 2)
  names(d)[[1L]] <- id
  d
}

nb_study <- function(data = nb_data(), .local_envir = parent.frame()) {
  root <- withr::local_tempdir("nb-study-", .local_envir = .local_envir)
  suppressMessages(hvtiRutilities::study_setup(root, study = "nb test", study_tracker_id = 9L, adopt = TRUE))
  utils::write.csv(data, file.path(hvtiRutilities::study_dir("datasets", root), "built.csv"), row.names = FALSE)
  suppressWarnings(suppressMessages(hvtiRutilities::register_data(root, built = "built.csv")))
  normalizePath(root)
}

# A chunk environment for `root`, parented on globalenv as a render's is.
nb_env <- function(root, parent = globalenv()) {
  env <- new.env(parent = parent)
  env$.root <- root
  env$.provenance_data <- list()
  env$study_config <- hvtiRutilities::study_config
  env
}

nb_skip_unless_stack <- function() {
  testthat::skip_if_not_installed("boostmtree", minimum_version = "2.0.2")
  testthat::skip_if_not_installed("ggBoostedTrees")
}

nb_choices <- function(...) {
  utils::modifyList(list(RESPONSE = "lvef", M = 20, SEED = 7), list(...))
}
```

Create `tests/testthat/test-nb-boostmtree.R`:

```r
test_that("add_job scaffolds nb-boostmtree with its subject and type", {
  dir <- withr::local_tempdir("nb-job-")
  job <- add_job("nb", subject = "lvef", type = "boost", dir = dir, qualifier = "boostmtree")
  expect_match(basename(job), "^lvef-boost-nb-boostmtree[.]qmd$")
  txt <- readLines(job)
  expect_identical(grep("^SUBJECT <- ", txt, value = TRUE), "SUBJECT <- \"lvef\"")
  expect_identical(grep("^TYPE\\s+<- ", txt, value = TRUE), "TYPE    <- \"boost\"")
})

test_that("the data chunk keeps the model's columns and drops rows with no response", {
  nb_skip_unless_stack()
  data <- nb_data()
  data$lvef[c(1, 5)] <- NA
  root <- nb_study(data)
  env <- nb_env(root)
  out <- utils::capture.output(nb_run(c("edit-study-choices", "data"), env, nb_choices()))
  expect_identical(sort(names(env$d)), sort(c("ccfid", "iv_echo", "lvef", "age", "female", "grp")))
  expect_identical(nrow(env$d), nrow(data) - 2L)
  expect_true(is.factor(env$d$grp))
  expect_true(any(grepl("2 visit(s) have no lvef", out, fixed = TRUE)))
  expect_true(any(grepl("Text predictors converted to factors: grp", out, fixed = TRUE)))
})

test_that("KEY defaults to ID and TIME, so a duplicated visit stops the read", {
  nb_skip_unless_stack()
  data <- nb_data()
  data <- rbind(data, data[1, ])
  root <- nb_study(data)
  env <- nb_env(root)
  expect_error(utils::capture.output(nb_run(c("edit-study-choices", "data"), env, nb_choices())), "unique")
})

test_that("the ID and TIME cannot be predictors, nor the ID the response", {
  nb_skip_unless_stack()
  root <- nb_study()
  run <- function(...) {
    env <- nb_env(root)
    utils::capture.output(nb_run(c("edit-study-choices", "data"), env, nb_choices(...)))
  }
  expect_error(run(PREDICTORS = c("age", "ccfid")), "identifier or the visit time")
  expect_error(run(PREDICTORS = c("age", "iv_echo")), "identifier or the visit time")
  expect_error(run(RESPONSE = "ccfid"), "cannot be the response")
})

test_that("boostmtree older than 2.0.2 is refused with the fork's install line", {
  src <- readLines(nb_template())
  at <- which(trimws(src) == "#| label: setup")
  end <- at + which(src[(at + 1L):length(src)] == "```")[1L]
  setup <- src[(at + 1L):(end - 1L)]
  setup <- setup[!grepl("find_study_root|list.files|library\\(", setup)]
  env <- new.env(parent = globalenv())
  testthat::local_mocked_bindings(
    packageVersion = function(pkg, ...) if (identical(pkg, "boostmtree")) package_version("2.0.0") else package_version("99.0.0"),
    .package = "utils"
  )
  expect_error(eval(parse(text = setup), envir = env), "ehrlinger/boostmtree_src", fixed = TRUE)
})
```

- [ ] **Step 2: Run the tests and confirm they fail.**

Run: `R_LIBS=<scratch lib> Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-nb-boostmtree.R")'`
Expected: FAIL. `add_job()` errors because no `nb` template with qualifier `boostmtree` exists, and `nb_template()` errors "found 0 times".

- [ ] **Step 3: Split the catalog row.**

In `inst/extdata/templates.json`, replace the single `nb` row (`"prefix": "nb"`, `"qualifier": null`, `"name": "Boosting"`) with these two rows, keeping every other field's value as it was:
- `nb` / `"qualifier": "boostmtree"`: `"name": "Boosting: boostmtree"`, `"status": "shipped"`, `"blocked_on": null`, `"spec": "dev/specs/2026-10-01-nb-boostmtree-design.md"`, `"uses": ["ggBoostedTrees::gg_boost_error", "ggBoostedTrees::gg_boost_path", "ggBoostedTrees::gg_boost_calibration", "ggBoostedTrees::gg_boost_vimp", "ggBoostedTrees::gg_boost_effect", "ggBoostedTrees::gg_boost_trajectory"]`.
- `nb` / `"qualifier": "boostmlr"`: `"name": "Boosting: BoostMLR"`, `"status": "queued"`, `"blocked_on": "ggBoostedTrees#9"`, `"spec": null`, `"uses": []`.

Run `python3 dev/specs/artifacts/roadmap_render.py`, then `python3 dev/specs/artifacts/check-roadmap-counts.py`. The check FAILs until the template file exists (Step 4); that is expected here.

- [ ] **Step 4: Write the template's first chunks.**

Create `inst/templates/30_analyses/nb-boostmtree.qmd`.
- The YAML `format:` block, the `guard-edits` chunk and the `set` chunk with its comments are copied **verbatim** from `inst/templates/30_analyses/rfs-fit.qmd` lines 1-20 and 66-194.
- Change: `title: "Boosted multivariate trees: boostmtree"`, `TYPE    <- "boost"`, and `SUBJECT <- "lvef"` in the `set` chunk.
- In the closing comment of `set`, replace the rfs-specific paragraph with: `# The fit is cached and saved through set_path(), by set, so a later render or job finds this set's fit and no other's.`

Then this preamble, setup chunk, study choices and data chunk:

````markdown
<!-- EDIT: name the job this replaces (an `nb.<variable>.Boostmtree` job), and
     say which response, visit time and predictors it used. -->

Replaces `analyses/<job>`: describe its response, visit time and predictors here.

An `nb-boostmtree` job fits boosted multivariate trees to a response measured
repeatedly over follow-up, one row per visit, and reports how well it fits and
what drives it: the cross-validated error path, observed against fitted values
over time, variable importance, partial effects over time, and a sample of
patients' fitted trajectories.

```{r}
#| label: setup
.in <- knitr::current_input(dir = TRUE)
.root <- hvtiRtemplates:::.find_study_root(if (is.null(.in)) getwd() else dirname(.in))
.provenance_data <- list()
for (f in list.files(file.path(.root, "R"), pattern = "[.]R$", full.names = TRUE)) source(f)
# boostmtree must be the CCF fork, 2.0.2 or later. Every study fits with
# cv.flag = TRUE, and in boostmtree 2.0.0 (the CRAN release) that flag leaves the
# in-sample fit frozen, so the stored coefficients diverge with M and every
# non-cross-validated result is wrong: partial and marginal effects, importance,
# and predict(use.cv.flag = FALSE). Reported upstream as kogalur/boostmtree#2;
# the fix is kogalur/boostmtree#3. The version floor separates the fork from
# CRAN today. Should upstream release a 2.0.2 without the fix, this check would
# pass it; read the installed package's NEWS if in doubt.
if (!requireNamespace("boostmtree", quietly = TRUE) || utils::packageVersion("boostmtree") < "2.0.2") {
  stop("This job needs boostmtree >= 2.0.2 from the CCF fork. Install it with\n",
       "  remotes::install_github(\"ehrlinger/boostmtree_src\", subdir = \"boostmtree\", ref = \"v2.0.2-ccf\")\n",
       "then re-render.", call. = FALSE)
}
if (!requireNamespace("ggBoostedTrees", quietly = TRUE) || utils::packageVersion("ggBoostedTrees") < "0.0.7") {
  stop("This job needs ggBoostedTrees >= 0.0.7. Install it with\n",
       "  remotes::install_github(\"ehrlinger/ggBoostedTrees\")\nthen re-render.", call. = FALSE)
}
suppressPackageStartupMessages({
  library(boostmtree)
  library(ggBoostedTrees)
  library(hvtiRutilities)
})
```

## Study choices

Edit these values for this study before rendering.

```{r}
#| label: edit-study-choices
# EDIT: the registered dataset this job reads ("study" is the built dataset).
DATASET <- "study"

# EDIT: an hvtiRdatabuild analysis set, or NULL to read the whole dataset.
ANALYSIS_SET <- NULL

# EDIT: rows to keep, dplyr::filter() style, or NULL to keep every row:
#   WHERE <- quote(age >= 18)
#   WHERE <- rlang::exprs(age >= 18, hx_chf == 1)
WHERE <- NULL

# EDIT: the patient identifier. Without "ccfid" the job uses MRN, then eMRN;
# name another column, such as "randid", if the study uses one.
ID <- "ccfid"

# EDIT: the visit time, in years. The data hold one row per visit, built
# upstream, so the time is part of what makes a row unique.
TIME <- "iv_echo"

# EDIT: what makes a row unique. The ID alone does not: a patient has a row per
# visit. A duplicated visit then stops the read rather than double-counting.
KEY <- c(ID, TIME)

# EDIT: the response measured at each visit, and its kind: "continuous",
# "binary", "ordinal" or "nominal".
RESPONSE <- "<response>"
FAMILY   <- "continuous"

# EDIT: the predictors, or NULL for every column but the ID, the time and the
# response, which is what the studies this template came from all did. Name
# them when the built dataset carries dates or derived outcomes that should not
# drive the fit.
PREDICTORS <- NULL

# EDIT: boosting iterations and the learning rate. Studies used 0.01 to 0.05; a
# smaller NU needs a larger M. The error path below says whether M was enough:
# the cross-validated best M should sit well inside it, not at its right edge.
M  <- 1000
NU <- 0.05

# EDIT: seeds the fit and the sample of patients the trajectory plot draws, so
# the report reproduces. Part of the cache key.
SEED <- 2026

# EDIT: the variables to draw partial effects for, or NULL for the six most
# important. N_TRACES patients are sampled for the trajectory plot; Inf draws
# every one.
EFFECT_VARIABLES <- NULL
N_TRACES <- 100

# Set TRUE after changing a choice above. A cache whose inputs changed stops the
# render instead of returning the old fit; TRUE recomputes it.
REFIT <- FALSE
```

## Cohort

```{r}
#| label: data
hvtiRutilities::verify_manifest(file.path(.root, "manifest.yaml"))
.cfg <- study_config(start = .root)
job_data <- hvtiRtemplates::read_job_data(.cfg, dataset = DATASET, analysis_set = ANALYSIS_SET,
                                          where = WHERE, id = ID, key = KEY)
d <- job_data$data
.provenance_data <- c(if (exists(".provenance_data")) .provenance_data else list(), list(job_data$provenance))
knitr::kable(job_data$record, col.names = c("Data", ""), caption = "The data this job read")
if (!is.null(job_data$attrition)) {
  knitr::kable(job_data$attrition, caption = paste0("Analysis set `", ANALYSIS_SET, "`: exclusions, in order"))
}
.selection <- attr(job_data$record, "selection")
.id <- .selection$id
.predictors <- if (is.null(PREDICTORS)) setdiff(names(d), c(.id, TIME, RESPONSE)) else PREDICTORS
# The fit groups visits by patient, so the ID and the visit time are its
# structure, not its predictors; a predictor named for either would let the
# model learn who a patient is or when they were seen.
.structural <- .predictors[tolower(.predictors) %in% tolower(c(.id, TIME))]
if (length(.structural)) {
  stop("PREDICTORS names the patient identifier or the visit time: ", paste(.structural, collapse = ", "),
       ".", call. = FALSE)
}
if (tolower(RESPONSE) == tolower(.id)) {
  stop("The patient identifier (", .id, ") cannot be the response.", call. = FALSE)
}
.missing <- setdiff(c(TIME, RESPONSE, .predictors), names(d))
if (length(.missing)) {
  stop("Not in the data this job read: ", paste(.missing, collapse = ", "), call. = FALSE)
}
d <- d[, c(.id, TIME, RESPONSE, .predictors), drop = FALSE]
# boostmtree imputes a missing predictor but cannot learn from a visit with no
# response, so those visits are dropped here, and counted.
.no_response <- is.na(d[[RESPONSE]])
if (any(.no_response)) {
  cat(sum(.no_response), " visit(s) have no ", RESPONSE, " and are left out.\n", sep = "")
  d <- d[!.no_response, , drop = FALSE]
}
.chr <- .predictors[vapply(d[.predictors], is.character, logical(1L))]
if (length(.chr)) {
  d[.chr] <- lapply(d[.chr], factor)
  cat("Text predictors converted to factors: ", paste(.chr, collapse = ", "), "\n", sep = "")
}
```
````

- [ ] **Step 5: Register the template.**
  - **`.lintr`:** add a key `"inst/templates/30_analyses/nb-boostmtree.qmd" = list(object_name_linter = Inf, commented_code_linter = Inf, object_usage_linter = Inf)`, placed beside the `rfs-fit.qmd` key in the same style.
  - **`tests/testthat/test-data-contract.R`:** add `"nb-boostmtree"` to the converted list (the `setdiff(template_list()$name, c(...))` vector).
  - **`DESCRIPTION`:**
    - In `Remotes:`, add `ehrlinger/boostmtree_src/boostmtree@v2.0.2-ccf` and `ehrlinger/ggBoostedTrees`.
    - In `Suggests:`, add `boostmtree (>= 2.0.2)` and `ggBoostedTrees (>= 0.0.7)`, alphabetically.

- [ ] **Step 6: Run the tests and confirm they pass.**

Run: `R_LIBS=<scratch lib> Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-nb-boostmtree.R"); testthat::test_file("tests/testthat/test-data-contract.R")'`, then the three `python3 dev/specs/artifacts/check-*-counts.py` scripts.
Expected: every test passes, and all three checks exit 0.
- If the contract test expects chunks this task has not written yet (for example `save`), mark exactly those expectations for Task 2.
- Do not weaken the contract test.

- [ ] **Step 7: Commit.**

```bash
git add inst/templates/30_analyses/nb-boostmtree.qmd inst/extdata/templates.json dev/specs/2026-08-29-template-conversion-roadmap.md DESCRIPTION .lintr tests/testthat/helper-nb.R tests/testthat/test-nb-boostmtree.R tests/testthat/test-data-contract.R
git commit -m "feat(templates): nb-boostmtree, its data half and catalog row"
```

(Add whatever file `roadmap_render.py` regenerated if its name differs; check `git status`.)

---

### Task 2: The fit, the cache and the saved file, with no raw ID anywhere

**Files:**
- Modify: `inst/templates/30_analyses/nb-boostmtree.qmd` (append `fit`, `save`, `provenance`).
- Test: `tests/testthat/test-nb-boostmtree.R`.

**Interfaces:**
- Consumes: from Task 1, `d`, `.id`, `.predictors`, `job_data`, `set_path()`, and the helpers in `helper-nb.R`. `hvtiRtemplates:::.study_id_key(root, create = TRUE)` and `hvtiRtemplates:::.id_digest(x, key)` (R/id-digest.R).
- Produces:
  - `fit`, a grown `boostmtree` object whose `$id` and `$id.unique` are digests.
  - The file `set_path("estimates", "nb-boostmtree.rds")`, carrying `hvti_provenance` lineage with `selection`.

- [ ] **Step 1: Write the failing tests.** Append to `tests/testthat/test-nb-boostmtree.R`:

```r
# TRUE when `bytes` hold `value` as text or as R's big-endian double.
nb_bytes_hold <- function(bytes, value) {
  patterns <- list(charToRaw(format(value, scientific = FALSE)), writeBin(as.double(value), raw(), endian = "big"))
  any(vapply(patterns, function(p) length(grepRaw(p, bytes, fixed = TRUE)) > 0L, logical(1L)))
}
nb_file_bytes <- function(path) {
  con <- gzfile(path, "rb")
  on.exit(close(con))
  pieces <- list()
  repeat {
    piece <- readBin(con, "raw", n = 1e7)
    if (!length(piece)) break
    pieces[[length(pieces) + 1L]] <- piece
  }
  do.call(c, pieces)
}
nb_fit_in <- function(root, parent = globalenv(), choices = nb_choices()) {
  env <- nb_env(root, parent)
  utils::capture.output(nb_run(c("set", "edit-study-choices", "data", "fit", "save"), env, choices))
  env
}

test_that("the fit groups visits by the study-keyed digest, never the ID", {
  nb_skip_unless_stack()
  root <- nb_study()
  env <- nb_fit_in(root)
  expect_s3_class(env$fit, "boostmtree")
  raw_ids <- unique(nb_data()$ccfid)
  expect_false(any(as.character(raw_ids) %in% as.character(env$fit$id.unique)))
  key <- hvtiRtemplates:::.study_id_key(root, create = FALSE)
  expect_setequal(as.character(env$fit$id.unique), hvtiRtemplates:::.id_digest(raw_ids, key))
})

test_that("no saved file holds an MRN, run in globalenv or outside it", {
  nb_skip_unless_stack()
  data <- nb_data(id = "MRN")
  mrns <- unique(data$MRN)
  for (parent in list(globalenv(), new.env(parent = globalenv()))) {
    root <- nb_study(data)
    env <- nb_fit_in(root, parent)
    expect_identical(tolower(attr(env$job_data$record, "selection")$id), "mrn")
    files <- list.files(hvtiRutilities::study_dir("estimates", root), recursive = TRUE, full.names = TRUE)
    expect_true(length(files) >= 2L)
    for (f in files) {
      bytes <- nb_file_bytes(f)
      expect_false(any(vapply(mrns, function(v) nb_bytes_hold(bytes, v), logical(1L))), info = basename(f))
    }
    # Positive control: the same search finds them in the data the job read.
    expect_true(nb_bytes_hold(serialize(env$job_data$data, NULL), mrns[[1L]]))
  }
})

test_that("a WHERE on the patient identifier stops before anything is fitted or saved", {
  nb_skip_unless_stack()
  # The data contract refuses it (fix/where-refuses-id, merged before this PR):
  # a WHERE is saved verbatim in the lineage, so an identifier filter would be too.
  data <- nb_data(id = "MRN")
  root <- nb_study(data)
  expect_error(nb_fit_in(root, choices = nb_choices(WHERE = quote(MRN != 4730000001))), "identifier")
  expect_length(list.files(hvtiRutilities::study_dir("estimates", root), recursive = TRUE), 0L)
})

test_that("the saved fit carries the selection in its lineage", {
  nb_skip_unless_stack()
  root <- nb_study()
  env <- nb_fit_in(root)
  saved <- readRDS(file.path(hvtiRutilities::study_dir("estimates", root), "lvef-boost", "nb-boostmtree.rds"))
  sel <- attr(saved, "hvti_provenance")$selection
  expect_identical(sel$id, "ccfid")
  expect_identical(sel$key, c("ccfid", "iv_echo"))
})

test_that("the cache is reused unchanged, and a changed setting stops until REFIT", {
  nb_skip_unless_stack()
  root <- nb_study()
  env <- nb_fit_in(root)
  first <- env$fit
  env2 <- nb_fit_in(root)
  expect_identical(env2$fit$id.unique, first$id.unique)
  expect_error(nb_fit_in(root, choices = nb_choices(NU = 0.01)), "changed")
  env3 <- nb_fit_in(root, choices = nb_choices(NU = 0.01, REFIT = TRUE))
  expect_s3_class(env3$fit, "boostmtree")
})
```

The `set` chunk computes the set from its file name. Outside a render `knitr::current_input()` is NULL, so `set` is a no-op apart from defining `SUBJECT`, `TYPE` and `set_path()`. That is why the tests run it.

- [ ] **Step 2: Run them and confirm they fail.**

Run: `R_LIBS=<scratch lib> Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-nb-boostmtree.R")'`
Expected: the four new tests FAIL with "chunk 'fit' found 0 times".

- [ ] **Step 3: Append the fit, save and provenance chunks.**

````markdown
## Fit

```{r}
#| label: fit
#| message: true
# The fit groups visits by patient through `id`. It is given the study-keyed
# digest of each patient's ID, not the ID: a boostmtree fit stores the ID in
# several places, its base learners included, and every one of them is saved
# with it. A digest still groups the visits; it cannot be read back.
CACHE_DIR <- dirname(set_path("estimates", "nb-boostmtree.rds"))
.patient <- hvtiRtemplates:::.id_digest(d[[.id]], hvtiRtemplates:::.study_id_key(.root))
fit <- cache_fit(
  "nb-boostmtree-fit",
  boostmtree(x = d[.predictors], tm = d[[TIME]], id = .patient, y = d[[RESPONSE]],
             family = FAMILY, M = M, nu = NU, mod.grad = TRUE, cv.flag = TRUE, verbose = FALSE),
  seed = SEED, dir = CACHE_DIR, refit = REFIT
)
```

`cv.flag = TRUE` and `mod.grad = TRUE` are not settings. Every study fitted with
both, and cross-validation is how the job chooses its best number of iterations.
````

and, after the report chunks (Task 3 inserts the report before these):

````markdown
```{r}
#| label: save
# The product of this job. It is separate from the cache on purpose: the cache
# is this job's internals and this file its interface, which carries the
# selection a later job would rebuild the rows from.
fit <- hvtiRtemplates:::.attach_handoff_lineage(
  fit,
  data = .provenance_data,
  analysis = list(response = RESPONSE, time = TIME, family = FAMILY, M = M, nu = NU),
  cohort = list(n_patients = length(unique(.patient)), n_visits = nrow(d)),
  selection = attr(job_data$record, "selection")
)
saveRDS(fit, set_path("estimates", "nb-boostmtree.rds"))
```

```{r}
#| label: provenance
#| echo: false
#| results: asis
cat(hvtiRtemplates:::.embed_provenance(
  .in,
  data = .provenance_data,
  extra = list(
    subject = SUBJECT, type = TYPE,
    analysis = list(response = RESPONSE, time = TIME, family = FAMILY, M = M, nu = NU),
    cohort = list(n_patients = length(unique(.patient)), n_visits = nrow(d))
  )
))
```
````

- [ ] **Step 4: Run the tests and confirm they pass.** Use the same command. Expected: all PASS.
  - If the byte test fails, find what holds the MRN by walking the saved object with `serialize()` on each element, as the spec's section 5 asks.
  - Fix that at the source. Never fix it by narrowing the test.

- [ ] **Step 5: Mutation-prove the byte test.**
  - In the `fit` chunk, replace `id = .patient` with `id = d[[.id]]`.
  - Rerun. Expected: "no saved file holds an MRN" FAILs.
  - Restore the line.

- [ ] **Step 6: Commit.**

```bash
git add inst/templates/30_analyses/nb-boostmtree.qmd tests/testthat/test-nb-boostmtree.R
git commit -m "feat(templates): nb-boostmtree fits on the study-keyed digest, caches and saves with lineage"
```

---

### Task 3: The report

**Files:**
- Modify: `inst/templates/30_analyses/nb-boostmtree.qmd`. Insert the report between `fit` and `save`.
- Create: `R/nb-boostmtree.R` (`.nb_single_response()`).
- Test: `tests/testthat/test-nb-boostmtree.R`.

**Interfaces:**
- Consumes: `fit` (Task 2), `.predictors`, `EFFECT_VARIABLES`, `N_TRACES`, `SEED`, `RESPONSE`, `TIME`.
- Produces: the chunks `fit-summary`, `error-path`, `calibration`, `importance`, `effects` and `traces`. `fit-summary` leaves `fit_summary`, a data frame with one row per response component. The others leave a ggplot object in `env` (`p_error`, `p_path`, `p_calibration`, `p_vimp`, `p_traces`), except `effects`: it leaves `p_effects`, a ggplot for a single-component fit, or a list of ggplots, one per component, for an ordinal or nominal fit.

**Amended 2026-10-01 after review of #217.** Four changes, each verified against a real fit:
1. Ordinal and nominal fits carry one `m.opt` and one error matrix per response component (`fit$err.rate` is then a list). The summary therefore has one row per component.
2. `gg_boost_vimp()` returns one row per variable per component, so "the top six" ranks variables by their largest importance across components, without duplicates.
3. `gg_boost_effect()` refuses a multi-component `partial.plot` ("nested by response") in ggBoostedTrees 0.0.7. For those fits the effects chunk splits the `partial.plot` data by component and draws each one. This is checked against the installed object and recorded as a ggBoostedTrees issue. That issue, ggBoostedTrees#19, merged in 0.0.8, and the chunk now passes one `partial.plot` whole.
4. The mean line over the traces averages fitted values within equal-count time bins, not at exact visit times, which are mostly one patient each.

Every family the template offers is tested.

- [ ] **Step 1: Write the failing test.**

```r
# One response per family the template offers, beside the continuous lvef.
nb_family_data <- function() {
  d <- nb_data()
  d$lvef_bin <- as.integer(d$lvef > stats::median(d$lvef))
  d$lvef_ord <- cut(d$lvef, stats::quantile(d$lvef, c(0, 1 / 3, 2 / 3, 1)), include.lowest = TRUE, labels = FALSE)
  d$lvef_nom <- c("low", "mid", "high")[d$lvef_ord]
  d
}
nb_families <- list(continuous = "lvef", binary = "lvef_bin", ordinal = "lvef_ord", nominal = "lvef_nom")

test_that("every report chunk draws for every family, from a fresh fit and from the cache", {
  nb_skip_unless_stack()
  root <- nb_study(nb_family_data())
  labels <- c("set", "edit-study-choices", "data", "fit", "fit-summary", "error-path", "calibration",
              "importance", "effects", "traces", "save")
  for (family in names(nb_families)) {
    choices <- nb_choices(RESPONSE = nb_families[[family]], FAMILY = family,
                          PREDICTORS = c("age", "female", "grp"), N_TRACES = 10)
    for (pass in 1:2) {
      env <- nb_env(root)
      utils::capture.output(nb_run(labels, env, choices))
      for (p in c("p_error", "p_path", "p_calibration", "p_vimp", "p_traces")) {
        expect_s3_class(env[[p]], "ggplot")
        expect_no_error(ggplot2::ggplot_build(env[[p]]))
      }
      effects <- if (inherits(env$p_effects, "ggplot")) list(env$p_effects) else env$p_effects
      expect_gte(length(effects), 1L)
      for (e in effects) expect_no_error(ggplot2::ggplot_build(e))
      # One summary row per response component, each with its own best M and error there.
      expect_identical(nrow(env$fit_summary), length(env$fit$m.opt), info = family)
      expect_true(all(is.finite(env$fit_summary$cv_error)), info = family)
      expect_false(anyDuplicated(env$.effect_vars) > 0L, info = family)
    }
  }
})

test_that("the mean line averages within time bins, not at single visit times", {
  nb_skip_unless_stack()
  root <- nb_study()
  env <- nb_env(root)
  utils::capture.output(nb_run(c("set", "edit-study-choices", "data", "fit", "traces"), env, nb_choices(N_TRACES = 10)))
  # Every bin stands on more than one patient, and there are fewer bins than distinct times.
  expect_true(all(env$trace_means$n_patients > 1L))
  expect_lt(nrow(env$trace_means), length(unique(env$traces$time)))
})

test_that("the trace sample is reproducible under SEED", {
  nb_skip_unless_stack()
  root <- nb_study()
  labels <- c("set", "edit-study-choices", "data", "fit", "traces")
  a <- nb_env(root); utils::capture.output(nb_run(labels, a, nb_choices(N_TRACES = 10)))
  b <- nb_env(root); utils::capture.output(nb_run(labels, b, nb_choices(N_TRACES = 10)))
  expect_identical(sort(unique(as.character(a$p_traces$data$id))), sort(unique(as.character(b$p_traces$data$id))))
})

test_that("no report output prints an identifier", {
  nb_skip_unless_stack()
  data <- nb_data(id = "MRN")
  root <- nb_study(data)
  env <- nb_env(root)
  out <- utils::capture.output(nb_run(c("set", "edit-study-choices", "data", "fit", "fit-summary", "error-path",
                                        "calibration", "importance", "effects", "traces"), env, nb_choices(N_TRACES = 10)))
  expect_false(any(vapply(unique(data$MRN), function(v) any(grepl(v, out, fixed = TRUE)), logical(1L))))
})
```

- [ ] **Step 2: Run them and confirm they fail.** Expected: FAIL, "chunk 'fit-summary' found 0 times".

- [ ] **Step 3: Insert the report.** Read each function's installed help first, e.g. `Rscript -e 'tools::Rd2txt(utils:::.getHelpFile(help("gg_boost_effect", package = "ggBoostedTrees")))'`, and use the arguments the installed version documents. The calls below match `ggBoostedTrees` 0.0.7 and `boostmtree` 2.0.2.

````markdown
## Does the fit work?

```{r}
#| label: fit-summary
knitr::kable(data.frame(
  quantity = c("Family", "Iterations (M)", "Learning rate (nu)", "Patients", "Visits"),
  value = c(FAMILY, M, NU, length(unique(.patient)), nrow(d))
), col.names = c("", ""), caption = "The fit")
# A continuous or binary fit has one response component; an ordinal or nominal
# fit has one per level after the first, each with its own cross-validated best
# M and error path (fit$err.rate is then a list). Read the error at the best M
# from the standardized l2 column, the scale gg_boost_error() plots.
.err <- if (is.matrix(fit$err.rate)) list(fit$err.rate) else fit$err.rate
fit_summary <- data.frame(
  component = seq_along(fit$m.opt),
  best_m = as.integer(fit$m.opt),
  cv_error = mapply(function(e, m) e[m, "l2"], .err, fit$m.opt)
)
knitr::kable(fit_summary, col.names = c("Response component", "Best M (cross-validated)",
                                        "Cross-validated error there (standardized)"),
             caption = "Cross-validated fit, by response component")
```

```{r}
#| label: error-path
# The cross-validated error by iteration, and the fitted rho, phi and lambda.
# Best M at the right edge means M was too small.
p_error <- plot(gg_boost_error(fit))
p_path  <- plot(gg_boost_path(fit))
p_error
p_path
```

```{r}
#| label: calibration
# Observed against fitted values over follow-up, in time bins.
p_calibration <- plot(gg_boost_calibration(fit))
p_calibration
```

```{r}
#| label: importance
# Importance of each predictor's main effect and its interaction with time; the
# interaction is where a predictor whose effect changes over follow-up shows.
vimp <- vimp.boostmtree(fit)
p_vimp <- plot(gg_boost_vimp(vimp))
p_vimp
```

```{r}
#| label: effects
# Partial effects over time, for EFFECT_VARIABLES or the six most important.
# An ordinal or nominal fit reports importance once per response component, so
# a variable is ranked by its largest importance across them.
.vimp_main <- gg_boost_vimp(vimp, components = "main")
.top <- sort(tapply(.vimp_main$importance, as.character(.vimp_main$variable), max), decreasing = TRUE)
.effect_vars <- if (is.null(EFFECT_VARIABLES)) head(names(.top), 6L) else EFFECT_VARIABLES
.unknown <- setdiff(.effect_vars, .predictors)
if (length(.unknown)) stop("EFFECT_VARIABLES names no predictor: ", paste(.unknown, collapse = ", "), call. = FALSE)
pp <- partial.plot(fit, x.var.names = .effect_vars, output = "data", verbose = FALSE)
# gg_boost_effect() takes a single-response partial.plot (ggBoostedTrees 0.0.7).
# An ordinal or nominal fit nests its curves by response component, so each
# component is drawn on its own.
p_effects <- if (length(fit$m.opt) == 1L) {
  plot(gg_boost_effect(pp))
} else {
  lapply(seq_along(fit$m.opt), function(k) plot(gg_boost_effect(.nb_single_response(pp, k))) +
           ggplot2::labs(subtitle = paste("Response component", k)))
}
p_effects
```

```{r}
#| label: traces
# Fitted trajectories for a sample of patients, with their observed values as
# points, and the cohort's mean fitted value over time drawn across them. The
# patients are labelled by digest, so none is identified.
traces <- gg_boost_trajectory(fit)
# Visit times are irregular, so most exact times belong to one patient, and a
# mean taken at each time would join single values. The mean is taken instead
# within ten equal-count time bins, over every patient's fitted values, and
# drawn at each bin's mean time. A bin is per response component when there
# are several.
.edges <- unique(stats::quantile(traces$time, seq(0, 1, length.out = 11L), names = FALSE))
traces$.bin <- cut(traces$time, .edges, include.lowest = TRUE)
.by <- intersect(c("response", ".bin"), names(traces))
trace_means <- do.call(rbind, lapply(split(traces, traces[.by], drop = TRUE), function(b) {
  data.frame(b[1L, setdiff(.by, ".bin"), drop = FALSE], time = mean(b$time), fitted = mean(b$fitted),
             n_patients = length(unique(b$id)))
}))
p_traces <- withr::with_seed(SEED, plot(traces, n_max = N_TRACES)) +
  ggplot2::geom_line(data = trace_means, ggplot2::aes(x = .data[["time"]], y = .data[["fitted"]]),
                     linewidth = 1.2, inherit.aes = FALSE) +
  ggplot2::labs(x = TIME, y = RESPONSE)
p_traces
```
````

The hvtiPlotR theme: the other fit templates do not add it inside these chunks. Check `rfs-fit.qmd` and the hazard templates, and follow what they do. If they apply none, apply none here. This overrides spec section 6's mention of the theme, because consistency with the shipped templates is the governing rule.

`.nb_single_response(pp, k)` is a small internal helper in `R/` (for example `R/nb-boostmtree.R`, documented `@noRd`). It returns component `k` of a multi-response `partial.plot.boostmtree` object, reshaped as the single-response object `gg_boost_effect()` accepts. Build it by reading:
- `boostmtree:::partial.plot.boostmtree` and its `$curves` / `$smooth` nesting (`[[response]][[variable]]`);
- `ggBoostedTrees:::gg_boost_effect` and its check for a single-response object.

Test it directly in `test-nb-boostmtree.R` on an ordinal fit. If no such reshaping is possible without reaching into ggBoostedTrees internals, stop and report. Do not drop the ordinal effects. The controller files a ggBoostedTrees issue for multi-response effects either way.

- [ ] **Step 4: Run the tests and confirm they pass.** If `gg_boost_effect` or `plot()` signatures differ from the code above, follow the installed docs and say so in the report.

- [ ] **Step 5: Mutation-prove the reproducibility test.** Remove `withr::with_seed(SEED, ...)` around the trace plot, rerun, and confirm the test FAILs. Restore it.

- [ ] **Step 6: Commit.**

```bash
git add inst/templates/30_analyses/nb-boostmtree.qmd tests/testthat/test-nb-boostmtree.R
git commit -m "feat(templates): nb-boostmtree reports error path, calibration, importance, effects and traces"
```

---

### Task 4: Render end to end, NEWS, README and the gates

**Files:**
- Modify: `NEWS.md`, `inst/templates/README.md` (the template list and the untemplated list).
- Test: a render test in `tests/testthat/test-nb-boostmtree.R`.

- [ ] **Step 1: Write the render test.** Follow the existing render tests (`grep -n "quarto_render\|render_job" tests/testthat/*.R`) for the skip conditions and their form:

```r
test_that("nb-boostmtree scaffolds and renders end to end", {
  nb_skip_unless_stack()
  testthat::skip_if_not_installed("quarto")
  testthat::skip_if_not(quarto::quarto_available())
  root <- nb_study()
  job <- add_job("nb", subject = "lvef", type = "boost", dir = root, qualifier = "boostmtree")
  set_choices <- function(path, from, to) {
    txt <- readLines(path)
    hit <- grep(from, txt)
    stopifnot(length(hit) == 1L)
    txt[hit] <- to
    writeLines(txt, path)
  }
  set_choices(job, "^RESPONSE <- ", "RESPONSE <- \"lvef\"")
  set_choices(job, "^M  <- ", "M  <- 20")
  out <- render_job(job, quiet = TRUE)
  expect_true(file.exists(sub("[.]qmd$", ".html", job)))
})
```

If `render_job()`'s signature or return value differs, read its help and adapt the test. It renders a draft, because `EDIT:` markers remain; that is expected.

- [ ] **Step 2: Run it, confirm it passes, and check that it really rendered.**
  - First install the branch into the scratch library: `R_LIBS=<scratch lib> R CMD INSTALL --no-test-load .`
  - Then run the test file.
  - Expected: PASS. A test skipped because Quarto is missing is NOT a pass. Report it.

- [ ] **Step 3: NEWS and README.**
  - Under `# hvtiRtemplates (unreleased)` in `NEWS.md`, add this bullet:

    > `nb-boostmtree` is a new template: boosted multivariate trees for a response measured repeatedly over follow-up, fitted with `boostmtree` 2.0.2 or later from the CCF fork (`ehrlinger/boostmtree_src`), whose fix the CRAN release lacks, and reported with ggBoostedTrees. `KEY` defaults to the ID and the visit time. Patients are grouped by the study-keyed digest, so the fit, its cache and the saved file hold no patient ID. BoostMLR (`nb-boostmlr`) is still to come.

  - In `inst/templates/README.md`, add `nb-boostmtree` to the template list in the same format as its neighbors, and remove `nb` from the untemplated list if it appears there.

- [ ] **Step 4: Run every gate.**
  - `R_LIBS=<scratch lib> Rscript -e 'roxygen2::roxygenise()'`. Expected: no change to `man/` or `NAMESPACE`.
  - The full suite: `R_LIBS=<scratch lib> Rscript -e 'r <- as.data.frame(devtools::test(reporter = "silent")); cat(sum(r$failed), sum(r$error), sum(r$warning), sum(r$skipped), "\n")'`. Expected: `0 0 0 0`.
  - `R_LIBS=<scratch lib> Rscript -e 'cat(length(lintr::lint_package(cache = FALSE)))'`. Expected: `0`.
  - `bash tools/check-us-spelling.sh` and the three `python3 dev/specs/artifacts/check-*-counts.py`. Expected: every one exits 0.

- [ ] **Step 5: Commit.**

```bash
git add NEWS.md inst/templates/README.md tests/testthat/test-nb-boostmtree.R
git commit -m "feat(templates): nb-boostmtree renders end to end; NEWS and README"
```

After the PR opens, read every CI leg's `FAIL | WARN | SKIP | PASS` line.
- Expect `SKIP 0` on macOS and Ubuntu, and 1 on Windows.
- If a leg cannot install `boostmtree` from the fork, the nb tests skip there. Fix `Remotes:` before merging, rather than accepting the skips.
