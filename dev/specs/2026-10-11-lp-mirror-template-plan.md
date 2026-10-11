# lp-mirror Template Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `inst/templates/40_graphs/lp-mirror.qmd`, the mirrored propensity-score histogram, as designed in `dev/specs/2026-10-11-lp-mirror-template-design.md`: it reads the bundle an `lm-propensity_binary` job saved, never refits, and draws all patients, the matching-weighted cohort, and, when `MATCH` names a flag, the matched patients.

**Architecture:** One new Quarto template whose figure helpers live in its own `helpers` chunk (as `dc-tables` keeps its helpers), so tests evaluate them on synthetic data. Two internals are lifted out of `lm-checkpred` into `R/handoff-path.R` so both templates share them: `.handoff_path()` (the `MODEL_FILE`/`MODEL_SET` check) and `.bundle_ids()` (an ID in the form a bundle holds it). Everything else reuses existing internals: `.read_handoff()`, `.read_upstream_job_data()`, `.save_figure()`, `.check_job_columns()`, `.embed_provenance()`, `.id_digest()` and `.bundle_id_key()`.

**Tech Stack:** R, Quarto, testthat edition 3, hvtiPlotR `hv_mirror_hist()`, hvtiRpropensity `ps_logistic()` bundles, hvtiRutilities study layout and provenance, Python 3 for the catalog scripts.

## Global Constraints

- hvtiPlotR floor stays `>= 2.8.0` in DESCRIPTION; the template's own version check says `2.8.0`.
- hvtiRpropensity floor stays `>= 0.1.10` in DESCRIPTION; the template's check says `0.1.10` and a test ties it to DESCRIPTION, as #287's test does for the `lm` family.
- No refit: the job reads `lm-propensity_binary.rds` and never calls a fitting function.
- No patient identifier, raw or digested, in any output: report, figure, table, provenance or saved file.
- Every figure is saved as PNG and PDF through `.save_figure()`, via the template's `save_figure()` wrapper, under `SAVE_FIGURES` and `FIGURES`.
- `.lintr` gains a key for the file `inst/templates/40_graphs/lp-mirror.qmd`, never for a directory.
- Roxygen is Rd markup (`\code{}`, `\strong{}`), not markdown.
- No em-dashes anywhere: code, comments, docs, commit messages, PR text.
- News fragment `news/feat-lp-mirror.md`; NEWS.md is not edited.
- `Version:` in DESCRIPTION is untouched.
- Tests run with `NOT_CRAN=true`, one file per command.
- Never install into the user's R library. Everything installs into the scratch library `$SCRATCH/lib-lpmirror`, called `LIB` in prose below; every command spells it out in full.
- Lines are at most 135 characters (`.lintr`).
- Branch `feat/lp-mirror` from `origin/main`. Never push to `main`.

---

## File Structure

| file | create / modify | responsibility |
|---|---|---|
| `R/handoff-path.R` | create | `.handoff_path()`: checks `MODEL_FILE` and `MODEL_SET` and returns the bundle path. `.bundle_ids()`: a job's IDs in the form a saved bundle holds them |
| `inst/templates/30_analyses/lm-checkpred.qmd` | modify (`model`, `training-overlap` chunks) | uses the two lifted helpers instead of its inline copies |
| `tests/testthat/test-handoff-path.R` | create | unit tests of the two helpers |
| `inst/templates/40_graphs/lp-mirror.qmd` | create | the template |
| `inst/extdata/templates.json` | modify (the `lp` row) | the `lp` row becomes `lp-mirror`, shipped |
| `dev/specs/2026-08-29-template-conversion-roadmap.md` | regenerate | rendered by `roadmap_render.py`, never hand-edited |
| `.lintr` | modify | the file key for `lp-mirror.qmd` |
| `tests/testthat/helper-lm.R` | modify (append) | `lp_data()`, `lp_helpers()`, `lp_fixture()`; kept in this file so `object_usage_linter` sees the `lm_*` helpers they call |
| `tests/testthat/test-lp-mirror.R` | create | every test in spec section 7 |
| `tests/testthat/test-template-provenance.R` | modify | template count 31 to 32; `lp-mirror` among the templates with a local dataset choice |
| `tests/testthat/test-template-data-routes.R` | modify | `lp-mirror` exempt from the JOIN offer, with the reason; rebuilders 3 to 4 |
| `tests/testthat/test-template-figures.R` | modify | `lp-mirror` among the figure templates, with its figure names |
| `dev/gallery/gallery.R` | modify (`gallery_job()` and header comment) | a job may name its template in `template`, so one template can have two gallery jobs |
| `dev/gallery/family-lm.R` | modify | the simulated `match_pair` column; the `lp-mirror` and `lp-mirror-matched` jobs |
| `dev/gallery/notes.json` | modify | the `lp-mirror` note |
| `inst/templates/README.md` | modify | the template table, the qualified-templates paragraph, the figure-name table |
| `news/feat-lp-mirror.md` | create | the NEWS entry |

---

## Task 0: Branch and scratch library

**Files:** none in the repo.

**Interfaces:** produces the scratch library `LIB` holding hvtiRutilities 1.5.1, hvtiRdatabuild and hvtiRpropensity from their `origin/main`, and this branch's hvtiRtemplates. hvtiPlotR 2.8.5 is read from the user library, which `R_LIBS` still searches after `LIB`.

- [ ] **Step 1: Set the two locations, then branch from origin/main.** `REPOS` is the folder holding the hvtiR clones, and `SCRATCH` a scratch folder outside every repo. Every later command uses both.

```bash
export REPOS=<folder holding the hvtiR clones>
export SCRATCH=<scratch folder outside any repo>
cd $REPOS/hvtiRtemplates
git fetch origin
git checkout -b feat/lp-mirror origin/main
```

- [ ] **Step 2: Export the three dependencies from their local clones and install them into LIB.**

```bash
mkdir -p $SCRATCH/lib-lpmirror
mkdir -p $SCRATCH/src-lpmirror
git -C $REPOS/hvtiRutilities fetch --tags origin
git -C $REPOS/hvtiRutilities archive --prefix=hvtiRutilities/ v1.5.1 | tar -x -C $SCRATCH/src-lpmirror
git -C $REPOS/hvtiRdatabuild fetch origin
git -C $REPOS/hvtiRdatabuild archive --prefix=hvtiRdatabuild/ origin/main | tar -x -C $SCRATCH/src-lpmirror
git -C $REPOS/hvtiRpropensity fetch origin
git -C $REPOS/hvtiRpropensity archive --prefix=hvtiRpropensity/ origin/main | tar -x -C $SCRATCH/src-lpmirror
R_LIBS=$SCRATCH/lib-lpmirror R CMD INSTALL --no-docs -l $SCRATCH/lib-lpmirror $SCRATCH/src-lpmirror/hvtiRutilities $SCRATCH/src-lpmirror/hvtiRdatabuild $SCRATCH/src-lpmirror/hvtiRpropensity
```

- [ ] **Step 3: Install this branch's hvtiRtemplates into LIB.** A Quarto render calls `hvtiRtemplates:::` internals from the installed package, not from `load_all()`, so this same command is rerun before every render below (Tasks 1, 7, 8 and 9 say where).

```bash
cd $REPOS/hvtiRtemplates
R_LIBS=$SCRATCH/lib-lpmirror R CMD INSTALL --no-docs -l $SCRATCH/lib-lpmirror .
```

- [ ] **Step 4: Verify the versions the gates run against.**

```bash
R_LIBS=$SCRATCH/lib-lpmirror Rscript -e 'for (p in c("hvtiRutilities", "hvtiRdatabuild", "hvtiRpropensity", "hvtiPlotR", "hvtiRtemplates")) cat(p, as.character(packageVersion(p)), "\n")'
```

Expected: `hvtiRutilities 1.5.1`, `hvtiRdatabuild` at least `0.2.3` (0.2.4 on 2026-10-11), `hvtiRpropensity` at least `0.1.10` (0.1.11 on 2026-10-11), `hvtiPlotR` at least `2.8.0` (2.8.5 installed), `hvtiRtemplates` the DESCRIPTION version of this branch. If hvtiPlotR is missing or older, stop and ask: do not install it into the user library.

- [ ] **Step 5: Baseline.** Record the suite state before any change, so a later failure can be told from a pre-existing one:

```bash
for f in tests/testthat/test-*.R; do echo "== $f"; R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e "devtools::load_all(quiet=TRUE); testthat::test_file('$f')" 2>&1 | grep -E "FAIL [0-9]+ \| WARN [0-9]+ \| SKIP [0-9]+ \| PASS [0-9]+"; done > $SCRATCH/lp-baseline.txt
```

Expected: FAIL 0 everywhere. One known exception, measured while writing this plan: on `origin/main` with hvtiRdatabuild 0.2.3, `test-job-data.R` errors once (`$ operator is invalid for atomic vectors`), unrelated to this work. Record what it reports with LIB's hvtiRdatabuild, and compare against this file in Task 9. No commit in this task.

---

## Task 1: Lift the bundle-path check and the ID comparison out of lm-checkpred

**Files:**
- Create: `R/handoff-path.R`
- Create: `tests/testthat/test-handoff-path.R`
- Modify: `inst/templates/30_analyses/lm-checkpred.qmd`, chunk `model` (lines 188 to 204 on origin/main, the `MODEL_FILE` check through the `file.exists()` stop) and chunk `training-overlap` (lines 242 to 247, the `.digested` and `.validation_ids` block)

**Interfaces:**
- Produces `.handoff_path(file, set, root, own, upstream, set_example)`: `file` is `MODEL_FILE`, `set` is `MODEL_SET` or `NULL`, `root` the study root, `own` a `function(file)` giving the path in the job's own set (a template passes `function(file) set_path("estimates", file)`), `upstream` the upstream template's name (`"lm-binary"`, `"lm-propensity_binary"`), `set_example` a set name for the message. Returns the path; stops with `MODEL_FILE must name one .rds file, such as "<upstream>.rds", with no folder: ...`, `MODEL_SET must be NULL or one set name, "<subject>-<type>", such as "<set_example>".`, or `Saved model not found: <path>. Render the <upstream> job first, or set MODEL_FILE and MODEL_SET to where it saved its model.`
- Produces `.bundle_ids(bundle, ids, root)`: `.id_digest(ids, .bundle_id_key(bundle, root))` when `bundle$meta$id_digest` is `TRUE`, else `as.character(ids)`.
- Consumed by: `lm-checkpred.qmd` (this task) and `lp-mirror.qmd` (Tasks 3 and 6).

- [ ] **Step 1: Write the failing test.** Create `tests/testthat/test-handoff-path.R`:

```r
# .handoff_path() and .bundle_ids(): the MODEL_FILE/MODEL_SET check and the ID
# comparison lm-checkpred and lp-mirror share. Synthetic studies only.

test_that(".handoff_path() finds a bundle in the job's own set or a named one, and nowhere else", {
  root <- lm_study()
  estimates <- hvtiRutilities::study_dir("estimates", root)
  dir.create(file.path(estimates, "own-set"))
  dir.create(file.path(estimates, "other-set"))
  file.create(file.path(estimates, "own-set", "up.rds"))
  file.create(file.path(estimates, "other-set", "up.rds"))
  own <- function(file) file.path(estimates, "own-set", file)
  path <- function(file = "up.rds", set = NULL) {
    hvtiRtemplates:::.handoff_path(file, set, root, own, upstream = "up", set_example = "other-set")
  }
  expect_identical(path(), file.path(estimates, "own-set", "up.rds"))
  expect_identical(path(set = "other-set"), file.path(estimates, "other-set", "up.rds"))
  for (bad in list("../own-set/up.rds", "up.csv", c("up.rds", "up.rds"), NA_character_, 1)) {
    expect_error(path(file = bad), "^MODEL_FILE must name one [.]rds file, such as \"up[.]rds\", with no folder")
  }
  for (bad in list("../other-set", "other", c("a-b", "c-d"), NA_character_)) {
    expect_error(path(set = bad), "^MODEL_SET must be NULL or one set name, \"<subject>-<type>\", such as \"other-set\"")
  }
  expect_error(path(set = "absent-set"),
               "^Saved model not found: .*absent-set/up[.]rds[.] Render the up job first, or set MODEL_FILE and MODEL_SET")
})

test_that(".bundle_ids() digests IDs for a digested bundle and leaves them as text otherwise", {
  root <- lm_study()
  bundle <- hvtiRtemplates:::.digest_bundle_ids(list(data = data.frame(ccfid = 1:3), meta = list(id_col = "ccfid")),
                                                root)
  key <- hvtiRtemplates:::.study_id_key(root)
  expect_identical(hvtiRtemplates:::.bundle_ids(bundle, c(1L, 3L), root), hvtiRtemplates:::.id_digest(c(1L, 3L), key))
  expect_identical(hvtiRtemplates:::.bundle_ids(bundle, c(1L, 3L), root), bundle$data$ccfid[c(1L, 3L)])
  expect_identical(hvtiRtemplates:::.bundle_ids(list(meta = list()), c(1L, 3L), root), c("1", "3"))
})
```

- [ ] **Step 2: Run it.**

```bash
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-handoff-path.R")'
```

Expected FAIL: errors `object '.handoff_path' not found` and `object '.bundle_ids' not found`.

- [ ] **Step 3: Implement.** Create `R/handoff-path.R`:

```r
#' Where a job's saved upstream bundle is, checked
#'
#' A downstream job names its upstream bundle by a file name and, when the
#' bundle is in another set, that set's name. Neither may hold a folder, so
#' no setting can reach outside the study's estimates. Shared by
#' \code{lm-checkpred} and \code{lp-mirror}.
#'
#' @param file The bundle's file name, \code{MODEL_FILE}.
#' @param set The set holding it, \code{MODEL_SET}, or \code{NULL} for the
#'   job's own set.
#' @param root The study root.
#' @param own A function of a file name giving its path in the job's own set.
#' @param upstream The upstream template's name, for the messages.
#' @param set_example A set name to show in the message about \code{set}.
#' @return The bundle's path. Stops when either setting is malformed or the
#'   file does not exist.
#' @noRd
.handoff_path <- function(file, set, root, own, upstream, set_example) {
  if (!is.character(file) || length(file) != 1L || is.na(file) || !grepl("^[^/\\\\]+[.]rds$", file)) {
    stop("MODEL_FILE must name one .rds file, such as \"", upstream, ".rds\", with no folder: ",
         "name another set in MODEL_SET.", call. = FALSE)
  }
  if (!is.null(set) &&
        (!is.character(set) || length(set) != 1L || is.na(set) || !grepl("^[A-Za-z0-9_]+-[A-Za-z0-9_]+$", set))) {
    stop("MODEL_SET must be NULL or one set name, \"<subject>-<type>\", such as \"", set_example, "\".",
         call. = FALSE)
  }
  path <- if (is.null(set)) own(file) else file.path(hvtiRutilities::study_dir("estimates", root), set, file)
  if (!file.exists(path)) {
    stop("Saved model not found: ", path, ". Render the ", upstream, " job first, or set MODEL_FILE and ",
         "MODEL_SET to where it saved its model.", call. = FALSE)
  }
  path
}

#' A job's patient IDs, in the form a saved bundle holds them
#'
#' A bundle saved by a current template holds a study-keyed digest of each ID,
#' so a job digests its own IDs with the same key before comparing or joining.
#' One saved before that holds raw identifiers, and is compared as text.
#'
#' @param bundle A saved bundle.
#' @param ids The job's identifiers.
#' @param root The study root.
#' @return A character vector as long as \code{ids}.
#' @noRd
.bundle_ids <- function(bundle, ids, root) {
  if (isTRUE(bundle$meta$id_digest)) .id_digest(ids, .bundle_id_key(bundle, root)) else as.character(ids)
}
```

In `lm-checkpred.qmd`, chunk `model`, replace everything from the line `if (!is.character(MODEL_FILE) || length(MODEL_FILE) != 1L ...` through the closing `}` of the `if (!file.exists(MODEL_PATH))` block with:

```r
MODEL_PATH <- hvtiRtemplates:::.handoff_path(MODEL_FILE, MODEL_SET, .root, function(file) set_path("estimates", file),
                                             upstream = "lm-binary", set_example = "stroke-model")
```

Keep the comment line `# MODEL_FILE is a file name and MODEL_SET a set name, so neither can reach outside the study's estimates.` above it.

In chunk `training-overlap`, replace:

```r
.digested <- isTRUE(model$meta$id_digest)
.validation_ids <- if (.digested) {
  unique(hvtiRtemplates:::.id_digest(d[[.id]], hvtiRtemplates:::.bundle_id_key(model, .root)))
} else {
  unique(as.character(d[[.id]]))
}
```

with:

```r
.validation_ids <- unique(hvtiRtemplates:::.bundle_ids(model, d[[.id]], .root))
```

The three comment lines above it stay. Confirm nothing else reads `.digested`: `grep -n "\.digested" inst/templates/30_analyses/lm-checkpred.qmd` prints nothing.

- [ ] **Step 4: Reinstall (the lm-checkpred render test calls the installed helpers) and run both files.**

```bash
R_LIBS=$SCRATCH/lib-lpmirror R CMD INSTALL --no-docs -l $SCRATCH/lib-lpmirror .
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-handoff-path.R")'
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lm-templates.R")'
```

Expected PASS: `test-handoff-path.R` `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 15 ]`; `test-lm-templates.R` FAIL 0 and SKIP 0, its MODEL_SET and training-overlap tests unchanged and green.

- [ ] **Step 5: Commit.**

```bash
git add R/handoff-path.R tests/testthat/test-handoff-path.R inst/templates/30_analyses/lm-checkpred.qmd
git commit -m "Lift lm-checkpred's bundle-path check and ID comparison into helpers

.handoff_path() checks MODEL_FILE and MODEL_SET and returns the bundle's
path; .bundle_ids() puts a job's IDs in the form a saved bundle holds them.
lm-checkpred uses both, and lp-mirror will. An NA in either setting now stops
with the setting's message rather than an R error.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Mutation check.** Each mutation must turn the new tests red; restore after each.

```bash
sed -i '' 's/ || is.na(file)//' R/handoff-path.R
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-handoff-path.R")'
git checkout -- R/handoff-path.R
sed -i '' 's/if (isTRUE(bundle\$meta\$id_digest)) .id_digest(ids, .bundle_id_key(bundle, root)) else as.character(ids)/as.character(ids)/' R/handoff-path.R
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-handoff-path.R")'
git checkout -- R/handoff-path.R
git status --short
```

Expected: FAIL 1 or more on each run (the NA case errors "missing value where TRUE/FALSE needed"; the digest case compares raw text to a digest). `git status --short` prints nothing.

---

## Task 2: Catalog row, roadmap, lint key and the scaffold

**Files:**
- Create: `inst/templates/40_graphs/lp-mirror.qmd` (skeleton: front matter through `edit-study-choices`, a `helpers` chunk holding only comments, and `provenance`)
- Create: `tests/testthat/test-lp-mirror.R`
- Modify: `inst/extdata/templates.json` (the `"prefix": "lp"` row, near line 796)
- Regenerate: `dev/specs/2026-08-29-template-conversion-roadmap.md`
- Modify: `.lintr` (insert after the `hp.qmd` key, near line 70)
- Modify: `tests/testthat/test-template-provenance.R` line 172

**Interfaces:**
- Produces the template's settings, all set once here and read by later tasks: `SUBJECT`, `TYPE`, `BINWIDTH`, `MODEL_FILE`, `MODEL_SET`, `GROUP_LABELS`, `MATCH`, `DATASET`, `ID`, `SAVE_FIGURES`, `FIGURES`; the closures `set_path(kind, file)` and `save_figure(plot, name, width, height, kind, linked)`; the objects `.in`, `.root`, `.provenance_data`, `.provenance_artifacts`.
- Produces the chunk labels, in order: `setup`, `guard-edits`, `guard-partial`, `set`, `edit-study-choices`, `helpers`, `provenance`. Later tasks insert chunks between `helpers` and `provenance`, and append functions to `helpers`.
- `add_job("lp.mirror", subject, type)` writes `<graphs folder>/lp.mirror.<subject>.<type>.qmd`.

- [ ] **Step 1: Write the failing test.** Create `tests/testthat/test-lp-mirror.R`:

```r
# lp-mirror: the mirrored propensity histogram, read from a saved
# lm-propensity_binary bundle. The design is
# dev/specs/2026-10-11-lp-mirror-template-design.md; its section 7 lists what
# these tests cover. All data are synthetic.

test_that("lp-mirror is a graphs template that add_job() scaffolds by its full name", {
  tl <- template_list()
  row <- tl[tl$name == "lp.mirror", ]
  expect_identical(nrow(row), 1L)
  expect_identical(row$folder, "graphs")
  expect_identical(row$call, "add_job(\"lp.mirror\", subject = \"treatment\", type = \"propensity\")")
  root <- lm_study()
  job <- add_job("lp.mirror", "treatment", "propensity", dir = root)
  expect_identical(basename(job), "lp.mirror.treatment.propensity.qmd")
  expect_identical(normalizePath(dirname(job)), normalizePath(hvtiRutilities::study_dir("graphs", root)))
  src <- readLines(job, warn = FALSE)
  expect_identical(grep("^SUBJECT\\s+<- ", src, value = TRUE), "SUBJECT  <- \"treatment\"")
  expect_identical(grep("^TYPE\\s+<- ", src, value = TRUE), "TYPE     <- \"propensity\"")
})

test_that("the job's package guards ask for the versions DESCRIPTION suggests", {
  src <- readLines(template_path("lp", "mirror"), warn = FALSE)
  suggests <- gsub("\\s+", " ", utils::packageDescription("hvtiRtemplates")$Suggests)
  for (pkg in c("hvtiRpropensity", "hvtiPlotR")) {
    minimum <- sub(paste0(".*", pkg, " \\(>= ([0-9.]+)\\).*"), "\\1", suggests)
    guard <- regmatches(src, regexpr(paste0("packageVersion[(]\"", pkg, "\"[)] < \"[0-9.]+\""), src))
    expect_length(guard, 1L)
    expect_identical(sub('.*< "([0-9.]+)"$', "\\1", guard), minimum, info = pkg)
    expect_true(any(grepl(paste0(pkg, " >= ", minimum), src, fixed = TRUE)), info = pkg)
  }
})
```

- [ ] **Step 2: Run it.**

```bash
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lp-mirror.R")'
```

Expected FAIL: `add_job(): unknown template: lp.mirror. Available: ac, bc, ...`, `nrow(row)` 0, and `unknown template: lp.mirror` from `template_path()`.

- [ ] **Step 3: Implement the catalog row.** In `inst/extdata/templates.json`, replace the `lp` row's fields from `"qualifier": null` through `"note": null,` with the block below; `sas_breadth_jobs`, `disposition` and `uses` stay as they are (`310`, `"thin"`, `["hvtiPlotR::hv_mirror_hist"]`).

```json
      "qualifier": "mirror",
      "name": "Logistic plot: mirrored propensity histogram",
      "description": "The mirrored histogram of the propensity score, treated above the axis and controls below, drawn from a saved lm-propensity_binary bundle without refitting: all patients, under the matching weights, and matched when the study has a match flag.",
      "folder": "graphs",
      "family": "plots",
      "kind": "job",
      "status": "shipped",
      "batch": 3,
      "sas_breadth": 636,
      "r_exemplars": 186,
      "r_jobs": 606,
      "upstream": [
        "lm"
      ],
      "downstream": [],
      "workflows": [
        "propensity-matching"
      ],
      "blocked_on": null,
      "spec": "dev/specs/2026-10-11-lp-mirror-template-design.md",
      "note": "A read-only survey on 2026-10-10 of 23 R lp jobs from 19 studies found about 94% of the 612 R-side lp jobs are propensity plots, about 284 of them mirrored histograms, and none refits. The balance plot ships as dc-stddiff. lp became a qualified prefix on 2026-10-11 so a later lp shape, such as calibration, arrives as its own qualifier. The breadth and exemplar counts above are the whole lp prefix's, measured before the split.",
```

Then regenerate the roadmap:

```bash
python3 dev/specs/artifacts/roadmap_render.py
```

Expected: `rendered 65 template rows into 2026-08-29-template-conversion-roadmap.md`. `git diff dev/specs/2026-08-29-template-conversion-roadmap.md` shows exactly five changed lines: 32 to 33 templates on disk; the `lp` row renamed `lp-mirror`, status `shipped`, its counts unchanged; propensity-matching 8/12 to 9/12; `lp` to `lp-mirror` among that workflow's members; `lp` gone from its outstanding list.

- [ ] **Step 4: Implement the lint key.** In `.lintr`, after the `"inst/templates/40_graphs/hp.qmd" = list(...)` entry, insert:

```r
    "inst/templates/40_graphs/lp-mirror.qmd" = list(
      object_name_linter = Inf,
      commented_code_linter = Inf,
      object_usage_linter = Inf
    ),
```

- [ ] **Step 5: Implement the skeleton.** Create `inst/templates/40_graphs/lp-mirror.qmd` with exactly this content:

````markdown
---
title: "Mirrored histogram of the propensity score"
format:
  html:
    theme: cosmo
    toc: true
    toc-location: left
    page-layout: full
    grid:
      body-width: 2000px
      sidebar-width: 250px
    code-fold: true
    df-print: default
    embed-resources: true
---

Draws the propensity score of the treated patients above the axis and of the
controls below it, from the bundle an `lm-propensity_binary` job saved. This
job reads that bundle and never refits the model.

```{r}
#| label: setup
# unnumbered: loads packages and checks versions only
# The study root is the nearest directory above this file holding _study.yml,
# so the job renders the same from the Render button, quarto render, or
# render_job(), at any depth, with no path in this document to edit.
.in <- knitr::current_input(dir = TRUE)
.root <- hvtiRtemplates:::.find_study_root(if (is.null(.in)) getwd() else dirname(.in))
.provenance_data <- list()
.provenance_artifacts <- list()
for (f in list.files(file.path(.root, "R"), pattern = "[.]R$", full.names = TRUE)) source(f)
suppressPackageStartupMessages({
  library(hvtiRutilities)
  library(hvtiPlotR)
  library(ggplot2)
})
# The bundle records its declared treatment levels from hvtiRpropensity 0.1.10.
if (utils::packageVersion("hvtiRpropensity") < "0.1.10") {
  stop("This job needs hvtiRpropensity >= 0.1.10, whose bundles record their treatment levels; ",
       utils::packageVersion("hvtiRpropensity"), " is installed.", call. = FALSE)
}
if (utils::packageVersion("hvtiPlotR") < "2.8.0") {
  stop("This job needs hvtiPlotR >= 2.8.0 for hv_mirror_hist(); ",
       utils::packageVersion("hvtiPlotR"), " is installed.", call. = FALSE)
}
```

```{r}
#| label: guard-edits
#| results: asis
# The token is built, not written, so this chunk does not find itself.
.tok <- paste0("ED", "IT", ":")
.cur <- knitr::current_input()
if (!is.null(.cur)) {
  .src <- readLines(.cur, warn = FALSE)
  .hits <- grep(.tok, .src, fixed = TRUE)
  if (length(.hits)) {
    .msg <- paste0(length(.hits), " unresolved ", .tok, " marker(s) remain in this job:\n",
                   paste0("  - ", trimws(substr(.src[.hits], 1L, 96L)), collapse = "\n"))
    if (tolower(Sys.getenv("HVTI_TEMPLATE_STRICT")) %in% c("", "0", "false", "no")) {
      warning(.msg, "\nRendering as a draft; remove every marker for a final result.", call. = FALSE)
      cat("\n::: {.callout-important title=\"DRAFT -- this job is unfinished\"}\n", .msg, "\n:::\n", sep = "")
    } else {
      stop(.msg, "\nThis render stops because HVTI_TEMPLATE_STRICT is '",
           Sys.getenv("HVTI_TEMPLATE_STRICT"), "'.", call. = FALSE)
    }
  }
}
```

```{r}
#| label: guard-partial
#| results: asis
# unnumbered: a callout, printed only when part of the job is left out
# To render a job you have not finished, leave a chunk out with the chunk
# option skip, giving the reason in quotes, or call hvtiRtemplates::stop_here()
# in a chunk to leave out everything below it. A draft lists each one here; a
# final render refuses them, as it refuses an EDIT marker. ?stop_here has more.
hvtiRtemplates:::.guard_partial(knitr::current_input())
```

<!-- EDIT: scaffold this job with the subject and type of the
     lm-propensity_binary job it plots, add_job("lp.mirror", subject, type),
     so it shares that job's set and finds the saved bundle with no path to
     type. The two lines below are written by add_job() and checked against
     this file's name; to plot from a set of its own, set MODEL_SET instead. -->

```{r}
#| label: set
SUBJECT  <- "treatment"
TYPE     <- "propensity"
.current <- knitr::current_input()
if (!is.null(.current)) {
  .fields <- hvtiRtemplates:::.job_name_fields(.current)
  .name_subject <- if (length(.fields) >= 1L) .fields[[1L]] else NA_character_
  .name_type <- if (length(.fields) >= 2L) .fields[[2L]] else NA_character_
  if (!identical(.name_subject, SUBJECT) || !identical(.name_type, TYPE)) {
    stop("This file is named '", .current, "' (subject '", .name_subject,
         "', type '", .name_type, "'), but declares SUBJECT = \"", SUBJECT,
         "\", TYPE = \"", TYPE, "\". Fix the declaration or the filename before rendering.", call. = FALSE)
  }
}
set_path <- function(kind, file) {
  d <- file.path(hvtiRutilities::study_dir(kind, .root), paste0(SUBJECT, "-", TYPE))
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  file.path(d, file)
}
# Saves a figure as <name>.png and <name>.pdf in this set's graphs/ folder,
# under the SAVE_FIGURES and FIGURES study choices.
save_figure <- function(plot, name, width = 6, height = 4, kind = "graphs", linked = FALSE) {
  hvtiRtemplates:::.save_figure(plot, set_path(kind, paste0(name, ".png")), width, height,
                                SAVE_FIGURES, FIGURES, linked)
}
```

## Study choices

```{r}
#| label: edit-study-choices
# EDIT: the bar width on the 0 to 100 score scale. 5 suits most cohorts; use 10
# for a small one, and 1 for a rare treatment whose scores sit near zero.
BINWIDTH <- 5

# Optional, and needs no edit: the saved bundle. NULL in MODEL_SET is this
# job's own set, where the bundle is when SUBJECT and TYPE match the
# lm-propensity_binary job's. A mirror job in a set of its own names that job's
# set, "<subject>-<type>", for example MODEL_SET <- "treatment-propensity".
MODEL_FILE <- "lm-propensity_binary.rds"
MODEL_SET <- NULL

# Optional, and needs no edit: the group labels. NULL labels each group by its
# treatment level, as the propensity job declared it. To relabel, name both
# levels: GROUP_LABELS <- c(control = "Surgical", treated = "Transcatheter").
GROUP_LABELS <- NULL

# Optional, and needs no edit: a pair-match flag, 1 for a matched patient. NULL
# draws no matched figure. A study whose dataset carries a flag, from a SAS
# match for example, names that column, and DATASET and ID say where to read
# it. The flag is joined onto the bundle's patients by a study-keyed digest of
# ID, so no identifier is kept or printed.
MATCH <- NULL
DATASET <- "built"
ID <- "ccfid"

# Each figure is saved to graphs/ as a PNG (for Word) and a PDF (for the publisher).
# SAVE_FIGURES <- FALSE saves neither; FIGURES keeps only the figures whose names
# start with one of its entries, e.g. FIGURES <- c("lp-mirror-weighted"). The names are the
# file names, listed for each template in the templates README.
SAVE_FIGURES <- TRUE
FIGURES <- NULL
```

```{r}
#| label: helpers
# unnumbered: defines the figure helpers and shows nothing
# The figure helpers. Each takes what it draws as an argument, so the tests
# call them on synthetic data.
```

```{r}
#| label: provenance
#| echo: false
#| results: asis
cat(hvtiRtemplates:::.embed_provenance(
  .in,
  data = .provenance_data,
  artifacts = .provenance_artifacts,
  extra = list(subject = SUBJECT, type = TYPE)
))
```
````

The `SUBJECT` and `TYPE` instruction is an HTML comment, as in `hp.qmd`, not an `EDIT:` line in the `set` chunk: `test-templates.R` requires that a chunk holds a marker exactly when its label starts with `edit-`.

- [ ] **Step 6: Update the shipped-template count.** In `tests/testthat/test-template-provenance.R` line 172, change `expect_equal(nrow(templates), 31L)` to `expect_equal(nrow(templates), 32L)`.

- [ ] **Step 7: Run.**

```bash
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lp-mirror.R")'
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-template-provenance.R")'
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-templates.R")'
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-template-catalog.R")'
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-template-catalog-rules.R")'
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-roadmap.R")'
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-add-job.R")'
python3 dev/specs/artifacts/check-roadmap-counts.py
```

Expected PASS: FAIL 0 in every file; the roadmap check prints `Catalog agrees with disk: 65 template rows routed to hvtiRtemplates, 33 on disk.`

- [ ] **Step 8: Commit.**

```bash
git add inst/templates/40_graphs/lp-mirror.qmd inst/extdata/templates.json dev/specs/2026-08-29-template-conversion-roadmap.md .lintr tests/testthat/test-lp-mirror.R tests/testthat/test-template-provenance.R
git commit -m "Scaffold the lp-mirror template and make lp a qualified prefix

The lp ledger row becomes lp-mirror, shipped, with the roadmap re-rendered
from it. The template file carries its settings, guards and provenance chunk;
the reading and figures follow. .lintr gains its file key.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 9: Mutation check.** Set the guard to another version and confirm the guard test goes red, then restore.

```bash
sed -i '' 's/packageVersion("hvtiPlotR") < "2.8.0"/packageVersion("hvtiPlotR") < "2.7.0"/' inst/templates/40_graphs/lp-mirror.qmd
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lp-mirror.R")'
git checkout -- inst/templates/40_graphs/lp-mirror.qmd
```

Expected: FAIL 1 (`hvtiPlotR`). `git status --short` is clean afterwards.

---

## Task 3: Read the bundle by set, check its lineage, build the scores

**Files:**
- Modify: `inst/templates/40_graphs/lp-mirror.qmd` (insert three chunks between `helpers` and `provenance`)
- Modify: `tests/testthat/helper-lm.R` (append `lp_data()` and `lp_fixture()`)
- Modify: `tests/testthat/test-lp-mirror.R` (append two tests)
- Modify: `tests/testthat/test-template-data-routes.R` lines 398 to 399

**Interfaces:**
- Consumes `.handoff_path()` (Task 1), `hvtiRtemplates:::.read_handoff(path, role, cfg, rebuild)`, `hvtiRtemplates:::.read_upstream_job_data(cfg, lineage, settings, read = TRUE, source, rerun)`.
- Produces in the job's environment: `MODEL_PATH`; `.cfg`; `.model_read` (`$value`, `$record`, `$lineage`); `bundle`; `.meta` (`bundle$meta`); `job_data` (the rebuilt upstream read); `.provenance_data` (the bundle's data lineage, then the rebuild's record); `.provenance_artifacts` (the bundle's carried artifacts, then the bundle's own record); `scores`, a data frame with one row per patient and columns `id` (the bundle's ID digest), `score` (0 to 1), `group` (character treatment level), `weight` (the matching weight), `matched` (0L until Task 6).
- Produces test helpers `lp_data(n = 120L)` and `lp_fixture(lines = character(), data = lp_data(), .local_envir = parent.frame())`, returning `list(root, job, bundle)`; `lp_fixture()` scaffolds the job in the `outcome-analysis` set beside a saved `lm-propensity_binary.rds`.

- [ ] **Step 1: Write the test helpers.** Append to `tests/testthat/helper-lm.R` (at the end of the file, after `lm_eval_job()`):

```r

# lp-mirror: a study whose lm-propensity_binary job has run, and the mirror
# job's own helpers. Kept in this file because they call the lm_* helpers above.

# The lm cohort with a pair-match flag, as a SAS match would leave it: two
# patients in three are matched. The identifiers are seven digits that occur
# nowhere else, so a report that printed one would be caught.
lp_data <- function(n = 120L) {
  d <- lm_data(n)
  d$ccfid <- 9100000L + d$ccfid
  d$match <- as.integer(d$ccfid %% 3L != 0L)
  d
}

# A study whose lm-propensity_binary job ran in the outcome-analysis set, with
# an lp-mirror job scaffolded beside it and its markers worked. Each element of
# `lines` replaces the study-choice line that starts with its setting's name,
# as lm_render_fixture() does. Returns the root, the job and the bundle path.
lp_fixture <- function(lines = character(), data = lp_data(), .local_envir = parent.frame()) {
  fit <- lm_render_fixture("propensity_binary", data = data, render = FALSE, .local_envir = .local_envir)
  job <- add_job("lp.mirror", "outcome", "analysis", dir = fit$root)
  src <- gsub("EDIT:", "REVIEWED:", readLines(job, warn = FALSE), fixed = TRUE)
  for (line in lines) {
    key <- sub(" .*", "", line)
    src[grepl(paste0("^", key, " <- "), src)] <- line
  }
  writeLines(src, job)
  list(root = fit$root, job = job, bundle = fit$env$MODEL_PATH)
}
```

- [ ] **Step 2: Write the failing tests.** Append to `tests/testthat/test-lp-mirror.R`:

```r

test_that("the job reads the bundle from its own set, or another through MODEL_SET, and never refits", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  s <- lp_fixture()
  testthat::local_mocked_bindings(
    ps_logistic = function(...) stop("lp-mirror refitted the model", call. = FALSE),
    .package = "hvtiRpropensity"
  )
  env <- lm_eval_job(s$job)
  expect_identical(env$MODEL_PATH, s$bundle)
  expect_identical(nrow(env$scores), 120L)
  expect_named(env$scores, c("id", "score", "group", "weight", "matched"))
  # The bundle moved to a set of its own is found through MODEL_SET.
  other <- file.path(hvtiRutilities::study_dir("estimates", s$root), "treatment-propensity")
  dir.create(other)
  file.rename(s$bundle, file.path(other, "lm-propensity_binary.rds"))
  expect_error(lm_eval_job(s$job), "^Saved model not found: .*outcome-analysis.*set MODEL_FILE and MODEL_SET")
  src <- readLines(s$job, warn = FALSE)
  writeLines(sub("^MODEL_SET <- NULL$", "MODEL_SET <- \"treatment-propensity\"", src), s$job)
  env <- lm_eval_job(s$job)
  expect_identical(normalizePath(env$MODEL_PATH), normalizePath(file.path(other, "lm-propensity_binary.rds")))
  # Neither setting can reach outside the study's estimates.
  writeLines(sub("^MODEL_SET <- NULL$", "MODEL_SET <- \"../treatment-propensity\"", src), s$job)
  expect_error(lm_eval_job(s$job), "^MODEL_SET must be NULL or one set name")
  writeLines(sub("^MODEL_FILE <- .*$", "MODEL_FILE <- \"../x/lm-propensity_binary.rds\"", src), s$job)
  expect_error(lm_eval_job(s$job), "^MODEL_FILE must name one [.]rds file")
  # A bundle without its matching weight is not one this job can draw.
  writeLines(sub("^MODEL_SET <- NULL$", "MODEL_SET <- \"treatment-propensity\"", src), s$job)
  bundle <- readRDS(file.path(other, "lm-propensity_binary.rds"))
  bundle$data$mt_wt <- NULL
  saveRDS(bundle, file.path(other, "lm-propensity_binary.rds"))
  expect_error(lm_eval_job(s$job), "is not a binary propensity model with its patients, treatment, score and matching weight")
})

test_that("a bundle without lineage, or built from data that changed since, stops with the job to rerun", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  s <- lp_fixture()
  bundle <- readRDS(s$bundle)
  lineage <- attr(bundle, "hvti_provenance")
  resave <- function(value) {
    attr(bundle, "hvti_provenance") <- value
    saveRDS(bundle, s$bundle)
  }
  resave(NULL)
  expect_error(lm_eval_job(s$job), "no complete hvti_provenance lineage. Rebuild it by rendering the lm-propensity_binary job")
  no_data <- lineage
  no_data$data <- list()
  resave(no_data)
  expect_error(lm_eval_job(s$job), "no source data lineage. Rebuild it by rendering the lm-propensity_binary job")
  resave(lineage[setdiff(names(lineage), "selection")])
  expect_error(lm_eval_job(s$job), "Render the lm-propensity_binary job again with the current template")
  # The same counts on other patients: the data changed since the bundle was saved.
  changed <- lineage
  changed$selection$key_hash <- strrep("0", 64L)
  resave(changed)
  expect_error(lm_eval_job(s$job), "The data changed since the upstream job ran")
})
```

- [ ] **Step 3: Run them.**

```bash
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lp-mirror.R")'
```

Expected FAIL: `env$MODEL_PATH` is `NULL`, `env$scores` is `NULL`, and every `expect_error()` reports that no error was thrown.

- [ ] **Step 4: Implement.** In `lp-mirror.qmd`, insert between the `helpers` chunk and the `provenance` chunk:

````markdown
## The saved bundle

```{r}
#| label: model
# MODEL_FILE is a file name and MODEL_SET a set name, so neither can reach
# outside the study's estimates.
MODEL_PATH <- hvtiRtemplates:::.handoff_path(MODEL_FILE, MODEL_SET, .root, function(file) set_path("estimates", file),
                                             upstream = "lm-propensity_binary", set_example = "treatment-propensity")
.cfg <- study_config(start = .root)
# A bundle without its lineage stops here with the job to render again.
.model_read <- hvtiRtemplates:::.read_handoff(MODEL_PATH, "propensity-model", .cfg, "the lm-propensity_binary job")
bundle <- .model_read$value
.meta <- bundle$meta
.cols <- c(.meta$id_col, .meta$treatment_col, .meta$score_col, .meta$weight_col)
if (!inherits(bundle, "ps_logistic") || length(.cols) != 4L || !all(.cols %in% names(bundle$data))) {
  stop("The saved bundle is not a binary propensity model with its patients, treatment, score and matching ",
       "weight: rebuild it by rendering the lm-propensity_binary job with the current template.", call. = FALSE)
}
.provenance_data <- .model_read$lineage$data
.provenance_artifacts <- c(.model_read$lineage$artifacts, list(.model_read$record))
```

```{r}
#| label: tbl-data
#| tbl-cap: "The data the propensity job read, read again"
# The bundle's rows are rebuilt from the data, as the propensity job read them,
# so a bundle built from data that has changed since stops here.
hvtiRutilities::verify_manifest(file.path(.root, "manifest.yaml"))
.up <- hvtiRtemplates:::.read_upstream_job_data(
  .cfg, .model_read$lineage, list(), source = MODEL_FILE,
  rerun = "Render the lm-propensity_binary job again with the current template, then this one."
)
job_data <- .up$job_data
.provenance_data <- c(.provenance_data, list(job_data$provenance),
                      if (!is.null(job_data$provenance_join)) list(job_data$provenance_join))
knitr::kable(job_data$record, col.names = c("Data", ""))
```

```{r}
#| label: scores
# One row per patient: the score, the treatment, the matching weight and the
# patient's ID digest, which only the MATCH join reads.
scores <- data.frame(
  id = bundle$data[[.meta$id_col]],
  score = bundle$data[[.meta$score_col]],
  group = as.character(bundle$data[[.meta$treatment_col]]),
  weight = bundle$data[[.meta$weight_col]],
  matched = 0L
)
if (anyDuplicated(scores$id)) {
  stop("The saved bundle holds a patient more than once; a mirrored histogram counts each patient once. ",
       "Rebuild it by rendering the lm-propensity_binary job with the current template.", call. = FALSE)
}
```
````

`.read_upstream_job_data()` takes `list()` for its settings: this job's `DATASET` and `ID` belong to the `MATCH` read (Task 6), never to the rebuild, which takes every choice from the bundle's recorded selection.

In `tests/testthat/test-template-data-routes.R`, the test "a downstream job that rebuilds its upstream rows records the joined dataset it re-read" (lines 398 to 399), change:

```r
  # hm, hp and hs-setup.
  expect_identical(rebuilders, 3L)
```

to:

```r
  # hm, hp, hs-setup and lp-mirror.
  expect_identical(rebuilders, 4L)
```

- [ ] **Step 5: Run.**

```bash
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lp-mirror.R")'
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-template-data-routes.R")'
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-template-numbering.R")'
```

Expected PASS: FAIL 0 in each.

- [ ] **Step 6: Commit.**

```bash
git add inst/templates/40_graphs/lp-mirror.qmd tests/testthat/helper-lm.R tests/testthat/test-lp-mirror.R tests/testthat/test-template-data-routes.R
git commit -m "lp-mirror: read the propensity bundle by set and check its lineage

The job reads lm-propensity_binary.rds from its own set or from MODEL_SET,
stops on a bundle without lineage, and rebuilds the propensity job's rows so a
bundle built from data that changed since stops with the job to rerun. It
never refits.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Mutation check.** Skip the rebuild and confirm the staleness test goes red, then restore.

```bash
sed -i '' 's/list(), source = MODEL_FILE,/list(), read = FALSE, source = MODEL_FILE,/' inst/templates/40_graphs/lp-mirror.qmd
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lp-mirror.R")'
git checkout -- inst/templates/40_graphs/lp-mirror.qmd
```

Expected: the lineage test fails on "The data changed since the upstream job ran". `git status --short` is clean afterwards.

---

## Task 4: Group labels and the derived symmetric axis

**Files:**
- Modify: `inst/templates/40_graphs/lp-mirror.qmd` (append four functions to the `helpers` chunk; add one line to the `scores` chunk)
- Modify: `tests/testthat/helper-lm.R` (append `lp_helpers()`)
- Modify: `tests/testthat/test-lp-mirror.R` (append two tests and the file-level `lp_scores()`)

**Interfaces:**
- Produces, in the `helpers` chunk:
  - `mirror_groups(meta, labels = NULL)` returning `list(levels, labels)`, treated level first; `labels` is `NULL` or a character vector of two labels named by the declared treatment levels.
  - `mirror_limit(y)` returning one number: `top <- max(abs(y), 0)` plus `max(1, ceiling(0.1 * top))`.
  - `mirror_hist(scores, kind = c("unmatched", "weighted", "matched"), groups, binwidth)` returning an `hv_mirror_hist` object; the unmatched kind keeps only the `"Before"` layer.
  - `mirror_figure(mh, kind = c("unmatched", "weighted", "matched"))` returning a ggplot with y-limits `c(-mirror_limit(mh$data$y), mirror_limit(mh$data$y))`.
- Produces `groups` in the job's environment (`mirror_groups(.meta, GROUP_LABELS)`), consumed by Tasks 5 and 6.
- Produces test helper `lp_helpers()`: a new environment holding the evaluated `helpers` chunk of `template_path("lp", "mirror")`; and `lp_scores()`, 40 synthetic patients, in `test-lp-mirror.R`.
- Relies on hvtiPlotR 2.8.5's `hv_mirror_hist()` behaviour, checked 2026-10-11: `group_levels[1]` is drawn ABOVE the axis (its help text says the reverse); without `weight_col` it requires `match_col`; `$data` has columns `x`, `y`, `group` (the label), `layer` (`"Before"`, `"Matched"` or `"Weighted"`) and `fill_key` (`before_g0`, `matched_g0`, `weighted_g0` and the `_g1` forms); `$meta` has `group_levels`, `group_labels`, `lower`, `upper`, `y_breaks`; `$tables$working` has `score`, `group` and `matched` or `weight`; bins are closed on the right with `include.lowest = TRUE`.

- [ ] **Step 1: Write the test helper.** Append to `tests/testthat/helper-lm.R`:

```r

# The lp-mirror template's helper functions, in an environment of their own.
lp_helpers <- function() {
  env <- new.env(parent = globalenv())
  src <- readLines(template_path("lp", "mirror"), warn = FALSE)
  # The package's own template chunk, as lm_run() evaluates the lm templates.
  eval(parse(text = lm_chunk(src, "helpers")), envir = env)
  env
}
```

- [ ] **Step 2: Write the failing tests.** Append to `tests/testthat/test-lp-mirror.R`:

```r

test_that("the groups are labelled by the bundle's declared levels, treated first, unless GROUP_LABELS says", {
  h <- lp_helpers()
  meta <- list(treatment_levels = c("control", "treated"), treated_level = "treated")
  expect_identical(h$mirror_groups(meta), list(levels = c("treated", "control"), labels = c("treated", "control")))
  # Named by level, in either order.
  expect_identical(h$mirror_groups(meta, c(control = "Surgical", treated = "Transcatheter"))$labels,
                   c("Transcatheter", "Surgical"))
  expect_identical(h$mirror_groups(meta, c(treated = "Transcatheter", control = "Surgical"))$labels,
                   c("Transcatheter", "Surgical"))
  expect_error(h$mirror_groups(meta, c("Surgical", "Transcatheter")),
               "^GROUP_LABELS must be NULL or two labels named by the treatment levels, such as c[(]control")
  expect_error(h$mirror_groups(meta, c(control = "a", other = "b")), "^GROUP_LABELS must be NULL")
  # A bundle saved before hvtiRpropensity 0.1.10 declares no levels.
  expect_error(h$mirror_groups(list(treatment_levels = NULL, treated_level = NULL)),
               "does not declare two treatment levels")
  # The job reads them from the saved bundle.
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  s <- lp_fixture("GROUP_LABELS <- c(control = \"Surgical\", treated = \"Transcatheter\")")
  env <- lm_eval_job(s$job)
  expect_identical(env$groups, list(levels = c("treated", "control"), labels = c("Transcatheter", "Surgical")))
})

lp_scores <- function() {
  i <- seq_len(40L)
  data.frame(id = paste0("p", i), score = (i - 0.5) / 40, group = rep(c("treated", "control"), 20L),
             weight = 0.25 + (i %% 4L) / 4, matched = as.integer(i %% 3L != 0L))
}

test_that("the treated bars are above the axis and the y-limits are symmetric, from the tallest bar", {
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  h <- lp_helpers()
  groups <- list(levels = c("treated", "control"), labels = c("Treated", "Control"))
  mh <- h$mirror_hist(lp_scores(), "unmatched", groups, 5)
  expect_true(all(mh$data$y[mh$data$group == "Treated"] >= 0))
  expect_true(all(mh$data$y[mh$data$group == "Control"] <= 0))
  # Only the all-patient bars: an unmatched figure has no matched layer.
  expect_setequal(unique(mh$data$layer), "Before")
  top <- max(abs(mh$data$y))
  expect_identical(h$mirror_limit(mh$data$y), top + max(1, ceiling(0.1 * top)))
  expect_identical(h$mirror_limit(c(3, -12)), 14)
  expect_identical(h$mirror_limit(numeric()), 1)
  p <- h$mirror_figure(mh, "unmatched")
  limits <- ggplot2::layer_scales(p)$y$get_limits()
  expect_identical(limits, c(-h$mirror_limit(mh$data$y), h$mirror_limit(mh$data$y)))
})
```

- [ ] **Step 3: Run them.**

```bash
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lp-mirror.R")'
```

Expected FAIL: `attempt to apply non-function` for `h$mirror_groups` and `h$mirror_hist`.

- [ ] **Step 4: Implement.** Append to the `helpers` chunk of `lp-mirror.qmd`, before its closing fence:

```r

# The two groups, treated first: hv_mirror_hist() draws its first level above
# the axis. Labelled by the levels the propensity job declared, or by
# GROUP_LABELS, named by those levels.
mirror_groups <- function(meta, labels = NULL) {
  declared <- as.character(meta$treatment_levels)
  treated <- as.character(meta$treated_level)
  if (length(declared) != 2L || anyNA(declared) || length(treated) != 1L || !treated %in% declared) {
    stop("The saved bundle does not declare two treatment levels and the treated one: rebuild it by ",
         "rendering the lm-propensity_binary job with the current template.", call. = FALSE)
  }
  levels <- c(treated, setdiff(declared, treated))
  if (is.null(labels)) return(list(levels = levels, labels = levels))
  if (!is.character(labels) || length(labels) != 2L || anyNA(labels) || is.null(names(labels)) ||
        !setequal(names(labels), declared)) {
    stop("GROUP_LABELS must be NULL or two labels named by the treatment levels, such as c(",
         paste0(declared, " = \"", declared, "\"", collapse = ", "), ").", call. = FALSE)
  }
  list(levels = levels, labels = unname(labels[levels]))
}

# The y-axis limit: the tallest bar on either side, plus a tenth of it and at
# least 1, as hv_mirror_hist() pads. The same limit above and below, so both
# groups are read on one scale.
mirror_limit <- function(y) {
  top <- max(abs(y), 0)
  top + max(1, ceiling(0.1 * top))
}

# One hv_mirror_hist() object. `scores` has one row per patient: score, group,
# weight and matched. The unmatched figure keeps only the all-patient bars.
mirror_hist <- function(scores, kind = c("unmatched", "weighted", "matched"), groups, binwidth) {
  kind <- match.arg(kind)
  args <- list(scores, score_col = "score", group_col = "group", group_levels = groups$levels,
               group_labels = groups$labels, binwidth = binwidth)
  if (identical(kind, "weighted")) {
    args$weight_col <- "weight"
  } else {
    args$match_col <- "matched"
    args$matched_value <- 1L
  }
  mh <- suppressMessages(do.call(hvtiPlotR::hv_mirror_hist, args))
  if (identical(kind, "unmatched")) mh$data <- mh$data[mh$data$layer == "Before", , drop = FALSE]
  mh
}

# The figure: the derived symmetric axis, and a fill that names each layer.
mirror_figure <- function(mh, kind = c("unmatched", "weighted", "matched")) {
  kind <- match.arg(kind)
  limit <- mirror_limit(mh$data$y)
  breaks <- pretty(c(-limit, limit), n = 8)
  mh$meta$lower <- -limit
  mh$meta$upper <- limit
  mh$meta$y_breaks <- breaks[abs(breaks) <= limit]
  labels <- mh$meta$group_labels
  colors <- hvtiPlotR::hv_palette(2L)
  fill <- switch(kind,
    unmatched = c(before_g0 = colors[[1L]], before_g1 = colors[[2L]]),
    weighted = c(before_g0 = "grey85", before_g1 = "grey85", weighted_g0 = colors[[1L]], weighted_g1 = colors[[2L]]),
    matched = c(before_g0 = "grey85", before_g1 = "grey85", matched_g0 = colors[[1L]], matched_g1 = colors[[2L]])
  )
  # The grey all-patient bars are one legend entry, not one a group.
  shown <- if (identical(kind, "unmatched")) names(fill) else names(fill)[-2L]
  names_shown <- switch(kind,
    unmatched = labels,
    weighted = c("All patients", paste(labels, "(weighted)")),
    matched = c("All patients", paste(labels, "(matched)"))
  )
  plot(mh) +
    ggplot2::scale_fill_manual(values = fill, breaks = shown, labels = names_shown, name = NULL) +
    ggplot2::labs(x = "Propensity score (%)",
                  y = if (identical(kind, "weighted")) "Patients, or sum of matching weights" else "Patients") +
    ggplot2::theme(legend.position = "top")
}
```

In the `scores` chunk, add as its first code line, after the two comment lines:

```r
groups <- mirror_groups(.meta, GROUP_LABELS)
```

- [ ] **Step 5: Run.**

```bash
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lp-mirror.R")'
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-template-numbering.R")'
```

Expected PASS: FAIL 0 in each (the `helpers` chunk calls `plot(` and stays unnumbered because its first comment is `# unnumbered: ...`).

- [ ] **Step 6: Commit.**

```bash
git add inst/templates/40_graphs/lp-mirror.qmd tests/testthat/helper-lm.R tests/testthat/test-lp-mirror.R
git commit -m "lp-mirror: label the groups from the bundle and derive a symmetric axis

The groups are the bundle's declared treatment levels, treated first so its
bars sit above the axis, or GROUP_LABELS named by level. The y-limit is the
tallest bar plus a tenth, the same above and below.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Mutation check.** Two mutations, each restored.

```bash
sed -i '' 's/levels <- c(treated, setdiff(declared, treated))/levels <- c(setdiff(declared, treated), treated)/' inst/templates/40_graphs/lp-mirror.qmd
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lp-mirror.R")'
git checkout -- inst/templates/40_graphs/lp-mirror.qmd
sed -i '' 's/mh\$meta\$lower <- -limit/mh$meta$lower <- min(mh$data$y) - 1/' inst/templates/40_graphs/lp-mirror.qmd
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lp-mirror.R")'
git checkout -- inst/templates/40_graphs/lp-mirror.qmd
```

Expected: the first run fails the labels test; the second fails the symmetric-limits expectation. `git status --short` is clean afterwards.

---

## Task 5: The unmatched and weighted figures, with a count table under each

**Files:**
- Modify: `inst/templates/40_graphs/lp-mirror.qmd` (append `mirror_counts()` to `helpers`; insert four chunks after `scores`)
- Modify: `tests/testthat/test-lp-mirror.R` (append two tests)
- Modify: `tests/testthat/test-template-figures.R` lines 1 and 31

**Interfaces:**
- Consumes `scores`, `groups`, `BINWIDTH`, `save_figure()`, `mirror_hist()`, `mirror_figure()`, `lp_scores()`.
- Produces `mirror_counts(mh, kind = c("unmatched", "weighted", "matched"))`: a data frame with `group` (label) and `patients` (integer), plus `weighted` (sum of matching weights) for the weighted kind or `matched` (integer) for the matched kind. Counts only.
- Produces `mh_unmatched` and `mh_weighted` in the job's environment, and the files `graphs/<set>/lp-mirror-unmatched.{png,pdf}` and `lp-mirror-weighted.{png,pdf}`.

- [ ] **Step 1: Write the failing tests.** Append to `tests/testthat/test-lp-mirror.R`:

```r

test_that("the weighted bars are the sum of the matching weights in each group and bin", {
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  h <- lp_helpers()
  s <- lp_scores()
  groups <- list(levels = c("treated", "control"), labels = c("Treated", "Control"))
  mh <- h$mirror_hist(s, "weighted", groups, 10)
  bins <- cut(100 * s$score, seq(0, 100, 10), right = TRUE, include.lowest = TRUE)
  for (g in groups$levels) {
    label <- groups$labels[groups$levels == g]
    want <- tapply(s$weight[s$group == g], bins[s$group == g], sum)
    want[is.na(want)] <- 0
    got <- mh$data$y[mh$data$layer == "Weighted" & mh$data$group == label]
    expect_equal(abs(got), as.numeric(want), info = g)
  }
  counts <- h$mirror_counts(mh, "weighted")
  expect_identical(counts$patients, c(20L, 20L))
  expect_equal(counts$weighted, c(sum(s$weight[s$group == "treated"]), sum(s$weight[s$group == "control"])))
})

test_that("the job saves the unmatched and weighted figures, with a count table under each", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  s <- lp_fixture()
  env <- lm_eval_job(s$job)
  graphs <- file.path(hvtiRutilities::study_dir("graphs", s$root), "outcome-analysis")
  expect_setequal(list.files(graphs), c("lp-mirror-unmatched.png", "lp-mirror-unmatched.pdf",
                                        "lp-mirror-weighted.png", "lp-mirror-weighted.pdf"))
  d <- lp_data()
  n <- c(sum(d$treatment == "treated"), sum(d$treatment == "control"))
  expect_identical(env$mirror_counts(env$mh_unmatched, "unmatched")$patients, n)
  expect_identical(env$mirror_counts(env$mh_weighted, "weighted")$patients, n)
  expect_named(env$mirror_counts(env$mh_unmatched, "unmatched"), c("group", "patients"))
})
```

- [ ] **Step 2: Run them.**

```bash
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lp-mirror.R")'
```

Expected FAIL: `attempt to apply non-function` for `h$mirror_counts`, and no files in `graphs`.

- [ ] **Step 3: Implement.** Append to the `helpers` chunk, before its closing fence:

```r

# Patients in each group; the sum of the matching weights for the weighted
# figure, and the matched patients for the matched one. Counts only.
mirror_counts <- function(mh, kind = c("unmatched", "weighted", "matched")) {
  kind <- match.arg(kind)
  w <- mh$tables$working
  levels <- mh$meta$group_levels
  out <- data.frame(group = mh$meta$group_labels,
                    patients = vapply(levels, function(g) sum(w$group == g), integer(1L), USE.NAMES = FALSE))
  if (identical(kind, "weighted")) {
    out$weighted <- vapply(levels, function(g) sum(w$weight[w$group == g]), numeric(1L), USE.NAMES = FALSE)
  }
  if (identical(kind, "matched")) {
    out$matched <- vapply(levels, function(g) sum(w$group == g & w$matched == 1L), integer(1L), USE.NAMES = FALSE)
  }
  out
}
```

Insert after the `scores` chunk (and before `provenance`):

````markdown
## Figures

```{r}
#| label: fig-mirror-unmatched
#| fig-cap: "Propensity score of each group: treated above the axis, controls below"
mh_unmatched <- mirror_hist(scores, "unmatched", groups, BINWIDTH)
file <- save_figure(mirror_figure(mh_unmatched, "unmatched"), "lp-mirror-unmatched", width = 7, height = 5,
                    linked = TRUE)
knitr::include_graphics(xfun::relative_path(file, if (!is.null(.in)) dirname(.in) else getwd(), error = FALSE),
                        error = FALSE)
```

```{r}
#| label: tbl-mirror-unmatched
#| tbl-cap: "Patients in each group"
knitr::kable(mirror_counts(mh_unmatched, "unmatched"), col.names = c("Group", "Patients"))
```

```{r}
#| label: fig-mirror-weighted
#| fig-cap: "Propensity score of each group under the matching weights, over all patients in grey"
mh_weighted <- mirror_hist(scores, "weighted", groups, BINWIDTH)
file <- save_figure(mirror_figure(mh_weighted, "weighted"), "lp-mirror-weighted", width = 7, height = 5,
                    linked = TRUE)
knitr::include_graphics(xfun::relative_path(file, if (!is.null(.in)) dirname(.in) else getwd(), error = FALSE),
                        error = FALSE)
```

```{r}
#| label: tbl-mirror-weighted
#| tbl-cap: "Patients in each group, and the sum of their matching weights"
knitr::kable(mirror_counts(mh_weighted, "weighted"), col.names = c("Group", "Patients", "Sum of matching weights"),
             digits = 1)
```
````

The job sits in the graphs folder and its figures one level below, in the set folder, so the link is the figure's path relative to the job, as `dc-stddiff` links its figure.

In `tests/testthat/test-template-figures.R`, line 1, add `"lp-mirror"` after `"hp"`:

```r
figure_templates <- c("dc-gfup", "dc-stddiff", "dc-tables", "dc-eda", "dc-trends", "hp", "lp-mirror",
```

and in the `expected` list of "every printed figure is also saved, under its documented name", after the line `bc = "bc-frequencies", bh = "bh-frequencies", bl = "bl-frequencies", br = "br-frequencies",` (line 31), add:

```r
    `lp-mirror` = c("lp-mirror-unmatched", "lp-mirror-weighted"),
```

- [ ] **Step 4: Run.**

```bash
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lp-mirror.R")'
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-template-figures.R")'
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-template-numbering.R")'
```

Expected PASS: FAIL 0 in each.

- [ ] **Step 5: Commit.**

```bash
git add inst/templates/40_graphs/lp-mirror.qmd tests/testthat/test-lp-mirror.R tests/testthat/test-template-figures.R
git commit -m "lp-mirror: draw the unmatched and weighted figures with their counts

Both figures are saved as PNG and PDF through save_figure(). The weighted
bars are the sum of mt_wt in each group and bin, over all patients in grey.
A table under each gives the patients in each group, and for the weighted
figure the sum of their weights.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Mutation check.** Weight by the score instead of the matching weight; restore.

```bash
sed -i '' 's/args\$weight_col <- "weight"/args$weight_col <- "score"/' inst/templates/40_graphs/lp-mirror.qmd
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lp-mirror.R")'
git checkout -- inst/templates/40_graphs/lp-mirror.qmd
```

Expected: the weighted-bars test fails for both groups. `git status --short` is clean afterwards.

---

## Task 6: The optional MATCH flag, joined by ID digest

**Files:**
- Modify: `inst/templates/40_graphs/lp-mirror.qmd` (append `mirror_join()` to `helpers`; insert a `match` chunk after `scores`; insert a `mirror-matched` chunk after `tbl-mirror-weighted`)
- Modify: `tests/testthat/test-lp-mirror.R` (append two tests)
- Modify: `tests/testthat/test-template-provenance.R` (the `expected` list near line 244)
- Modify: `tests/testthat/test-template-data-routes.R` (the `next` condition, line 240)
- Modify: `tests/testthat/test-template-figures.R` (the `lp-mirror` entry Task 5 added)

**Interfaces:**
- Consumes `.bundle_ids()` (Task 1), `hvtiRtemplates::read_job_data()`, `hvtiRtemplates:::.check_job_columns()`, `scores`, `bundle`, `.meta`, `.cfg`, `MATCH`, `DATASET`, `ID`, `mirror_hist()`, `mirror_figure()`, `mirror_counts()`.
- Produces `mirror_join(bundle_ids, ids, flag)` returning `list(matched, counts)`: `matched` an integer 0/1 vector as long as `bundle_ids`; `counts` a data frame with `count` (two descriptions) and `patients`, in the order "Patients with a score and no match flag", "Patients with a match flag and no score". Stops when fewer than half of `bundle_ids` are in `ids`, or `ids` repeat a patient.
- Produces `.join` (`NULL` without `MATCH`), `match_data`, `mh_matched`, the files `lp-mirror-matched.{png,pdf}`, and the labels `tbl-match-join`, `fig-mirror-matched`, `tbl-mirror-matched` (only with `MATCH`). `.join` is read by the provenance chunk in Task 7.

- [ ] **Step 1: Write the failing tests.** Append to `tests/testthat/test-lp-mirror.R`:

```r

test_that("the match flag joins by ID digest, counts both kinds of miss, and stops on another cohort", {
  h <- lp_helpers()
  bundle_ids <- paste0("d", 1:10)
  # Patients 9 and 10 have no flag; the dataset has two patients with no score.
  out <- h$mirror_join(bundle_ids, c(paste0("d", 1:8), "x1", "x2"), c(1, 0, 1, 1, 0, 1, 1, 1, 1, 1))
  expect_identical(out$matched, c(1L, 0L, 1L, 1L, 0L, 1L, 1L, 1L, 0L, 0L))
  expect_identical(out$counts$patients, c(2L, 2L))
  # Fewer than half the scored patients in the dataset: another cohort, or another identifier.
  expect_error(h$mirror_join(bundle_ids, c("d1", "d2", paste0("x", 1:8)), rep(1, 10)),
               "^Only 2 of the 10 patients the scores were computed for are in the dataset read for MATCH")
  expect_error(h$mirror_join(bundle_ids, c("d1", "d1"), c(1, 1)), "holds a patient more than once")
})

test_that("with MATCH the job joins the flag through the study key and keeps no identifier", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  s <- lp_fixture("MATCH <- \"match\"")
  env <- lm_eval_job(s$job)
  d <- lp_data()
  expect_identical(env$scores$matched, d$match)
  expect_identical(env$.join$counts$patients, c(0L, 0L))
  expect_identical(env$mirror_counts(env$mh_matched, "matched")$matched,
                   c(sum(d$match[d$treatment == "treated"]), sum(d$match[d$treatment == "control"])))
  graphs <- file.path(hvtiRutilities::study_dir("graphs", s$root), "outcome-analysis")
  expect_true(all(file.exists(file.path(graphs, c("lp-mirror-matched.png", "lp-mirror-matched.pdf")))))
  # The scores hold the study-keyed digest, never the identifier.
  expect_false(any(as.character(d$ccfid) %in% env$scores$id))
  # A dataset keyed on another identifier stops by name.
  src <- readLines(s$job, warn = FALSE)
  writeLines(sub("^ID <- .*$", "ID <- \"id\"", src), s$job)
  expect_error(lm_eval_job(s$job), "identifies patients by `id`, the bundle by `ccfid`")
})
```

- [ ] **Step 2: Run them.**

```bash
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lp-mirror.R")'
```

Expected FAIL: `attempt to apply non-function` for `h$mirror_join`; `env$scores$matched` all 0; `env$.join` and `env$mh_matched` `NULL`.

- [ ] **Step 3: Implement.** Append to the `helpers` chunk, before its closing fence:

```r

# The match flag of each bundle patient, joined by ID digest. `ids` are the
# dataset's identifiers made comparable with the bundle's by .bundle_ids(),
# and `flag` the MATCH column. Returns the 0/1 flag for each bundle patient
# and the two counts the job reports; stops when fewer than half of the
# bundle's patients are in the dataset.
mirror_join <- function(bundle_ids, ids, flag) {
  if (anyDuplicated(ids[!is.na(ids)])) {
    stop("The dataset holds a patient more than once, so the match flag cannot be joined one to one: set ",
         "DATASET to a dataset with one row per patient.", call. = FALSE)
  }
  at <- match(bundle_ids, ids)
  joined <- !is.na(at)
  if (sum(joined) < length(bundle_ids) / 2) {
    stop("Only ", sum(joined), " of the ", length(bundle_ids), " patients the scores were computed for are in ",
         "the dataset read for MATCH. The dataset is not the cohort the scores came from, or its ID does not ",
         "identify patients as the propensity job's did: check DATASET and ID.", call. = FALSE)
  }
  value <- flag[at]
  list(
    matched = as.integer(!is.na(value) & value == 1),
    counts = data.frame(
      count = c("Patients with a score and no match flag", "Patients with a match flag and no score"),
      patients = c(sum(is.na(value)), sum(!ids[!is.na(ids)] %in% bundle_ids))
    )
  )
}
```

Insert after the `scores` chunk, before `## Figures`:

````markdown
```{r}
#| label: match
#| results: asis
# unnumbered: its child chunk carries its own label and caption
# The flag is joined by a digest of ID under the study key, the digest the
# bundle holds, so this job keeps and prints no identifier. A scored patient
# with no flag is drawn as unmatched and counted, never dropped.
.join <- NULL
if (!is.null(MATCH)) {
  if (!is.character(MATCH) || length(MATCH) != 1L || is.na(MATCH)) {
    stop("MATCH must be NULL or one column name.", call. = FALSE)
  }
  match_data <- hvtiRtemplates::read_job_data(.cfg, dataset = DATASET, id = ID, one_row_per_patient = TRUE)
  match_data$provenance$role <- "match"
  .provenance_data <- c(.provenance_data, list(match_data$provenance))
  .id <- attr(match_data$record, "selection")$id
  hvtiRtemplates:::.check_job_columns(match_data$data, MATCH = MATCH)
  if (!identical(tolower(.id), tolower(.meta$id_col))) {
    stop("The dataset read for MATCH identifies patients by `", .id, "`, the bundle by `", .meta$id_col,
         "`: set ID so both use the same identifier.", call. = FALSE)
  }
  .join <- mirror_join(scores$id, hvtiRtemplates:::.bundle_ids(bundle, match_data$data[[.id]], .root),
                       match_data$data[[MATCH]])
  scores$matched <- .join$matched
  .fence <- strrep("`", 3)
  cat(knitr::knit_child(text = c(
    paste0(.fence, "{r}"), "#| label: tbl-match-join",
    "#| tbl-cap: \"The match flag joined onto the scored patients\"",
    "knitr::kable(.join$counts, col.names = c(\"\", \"Patients\"))", .fence
  ), envir = environment(), quiet = TRUE), sep = "\n")
}
```
````

Insert after the `tbl-mirror-weighted` chunk, before `provenance`:

````markdown
```{r}
#| label: mirror-matched
#| results: asis
# unnumbered: its child chunks carry their own labels and captions
if (!is.null(MATCH)) {
  mh_matched <- mirror_hist(scores, "matched", groups, BINWIDTH)
  file <- save_figure(mirror_figure(mh_matched, "matched"), "lp-mirror-matched", width = 7, height = 5,
                      linked = TRUE)
  .link <- xfun::relative_path(file, if (!is.null(.in)) dirname(.in) else getwd(), error = FALSE)
  .fence <- strrep("`", 3)
  cat(knitr::knit_child(text = c(
    paste0(.fence, "{r}"), "#| label: fig-mirror-matched",
    "#| fig-cap: \"Propensity score of the matched patients in each group, over all patients in grey\"",
    "knitr::include_graphics(.link, error = FALSE)", .fence, "",
    paste0(.fence, "{r}"), "#| label: tbl-mirror-matched",
    "#| tbl-cap: \"Patients in each group, and those matched\"",
    "knitr::kable(mirror_counts(mh_matched, \"matched\"), col.names = c(\"Group\", \"Patients\", \"Matched\"))",
    .fence
  ), envir = environment(), quiet = TRUE), sep = "\n")
}
```
````

Cross-cutting tests:

1. `tests/testthat/test-template-provenance.R`, test "only templates with a local dataset choice override the dataset": in `expected`, change the line `"lm-propensity_binary", "lm-propensity_nominal", "lm-propensity_ordinal",` to `"lm-propensity_binary", "lm-propensity_nominal", "lm-propensity_ordinal", "lp-mirror",`.
2. `tests/testthat/test-template-data-routes.R`, test "every template that reads its own data offers the join and records the joined data": replace

```r
    # A job that reads with its own DATASET; downstream and bootstrap reports
    # rebuild the selection their upstream job recorded instead.
    if (!grepl("read_job_data(.cfg, dataset = DATASET", text, fixed = TRUE)) next
```

with

```r
    # A job that reads with its own DATASET; downstream and bootstrap reports
    # rebuild the selection their upstream job recorded instead. lp-mirror
    # reads DATASET only for its MATCH column, joined onto the bundle's
    # patients by ID digest, so it offers no JOIN.
    if (!grepl("read_job_data(.cfg, dataset = DATASET", text, fixed = TRUE) || basename(f) == "lp-mirror.qmd") next
```

   `expect_identical(readers, 21L)` stays 21.
3. `tests/testthat/test-template-figures.R`: change the entry Task 5 added to `` `lp-mirror` = c("lp-mirror-unmatched", "lp-mirror-weighted", "lp-mirror-matched"), ``.

- [ ] **Step 4: Run.**

```bash
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lp-mirror.R")'
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-template-provenance.R")'
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-template-data-routes.R")'
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-template-figures.R")'
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-template-numbering.R")'
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-templates.R")'
```

Expected PASS: FAIL 0 in each.

- [ ] **Step 5: Commit.**

```bash
git add inst/templates/40_graphs/lp-mirror.qmd tests/testthat/test-lp-mirror.R tests/testthat/test-template-provenance.R tests/testthat/test-template-data-routes.R tests/testthat/test-template-figures.R
git commit -m "lp-mirror: join an optional match flag by ID digest and draw the matched figure

MATCH names a pair-match column in DATASET. It is joined onto the bundle's
patients by a study-keyed digest of ID, so no identifier is kept or printed.
The job reports the scored patients with no flag and the flags with no score,
and stops when fewer than half the scored patients are in the dataset.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Mutation check.** Three mutations, each restored.

```bash
sed -i '' 's/matched = as.integer(!is.na(value) \& value == 1),/matched = as.integer(value == 1),/' inst/templates/40_graphs/lp-mirror.qmd
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lp-mirror.R")'
git checkout -- inst/templates/40_graphs/lp-mirror.qmd
sed -i '' 's|if (sum(joined) < length(bundle_ids) / 2) {|if (sum(joined) < 0) {|' inst/templates/40_graphs/lp-mirror.qmd
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lp-mirror.R")'
git checkout -- inst/templates/40_graphs/lp-mirror.qmd
sed -i '' 's/hvtiRtemplates:::.bundle_ids(bundle, match_data\$data\[\[.id\]\], .root)/as.character(match_data$data[[.id]])/' inst/templates/40_graphs/lp-mirror.qmd
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lp-mirror.R")'
git checkout -- inst/templates/40_graphs/lp-mirror.qmd
```

Expected: run 1 fails the unit join test (NA flags); run 2 fails the "Only 2 of the 10" expectation; run 3 fails the job-level MATCH test with "Only 0 of the 120 patients", since raw IDs never meet the digests. `git status --short` is clean afterwards.

---

## Task 7: Provenance, and the rendered report

**Files:**
- Modify: `inst/templates/40_graphs/lp-mirror.qmd` (the `provenance` chunk)
- Modify: `tests/testthat/test-lp-mirror.R` (append one test)

**Interfaces:**
- Consumes `.provenance_data`, `.provenance_artifacts`, `.model_read`, `MODEL_SET`, `MODEL_FILE`, `BINWIDTH`, `MATCH`, `.join`.
- Produces in the embedded payload, beside `subject` and `type`: `analysis` and `cohort` from the bundle's lineage (the model the figures plot), and `mirror`, a list with `model_set` (the set read, the job's own when `MODEL_SET` is `NULL`), `model_file`, `binwidth`, and with `MATCH` also `match` and `join` (`no_flag`, `no_score`). `data` carries the bundle's lineage, the rebuild's dataset record and, with `MATCH`, the match dataset's record with role `"match"`; `artifacts` carries the bundle's record.

- [ ] **Step 1: Write the failing test.** Append to `tests/testthat/test-lp-mirror.R`:

```r

test_that("the job renders two figures without MATCH and three with it, naming no patient", {
  skip_on_cran()
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  for (match in c(FALSE, TRUE)) {
    s <- lp_fixture(if (match) "MATCH <- \"match\"" else character())
    quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = TRUE)
    html <- paste(readLines(sub("[.]qmd$", ".html", s$job), warn = FALSE), collapse = "\n")
    figures <- c("lp-mirror-unmatched", "lp-mirror-weighted", if (match) "lp-mirror-matched")
    graphs <- file.path(hvtiRutilities::study_dir("graphs", s$root), "outcome-analysis")
    expect_setequal(sub("[.]png$", "", list.files(graphs, "[.]png$")), figures)
    expect_setequal(sub("[.]pdf$", "", list.files(graphs, "[.]pdf$")), figures)
    shown <- unique(regmatches(html, gregexpr("id=\"fig-mirror-[a-z]+\"", html))[[1L]])
    expect_setequal(shown, paste0("id=\"fig-", sub("^lp-", "", figures), "\""))
    # No patient identifier, raw or digested, appears in the report.
    d <- lp_data()
    key <- hvtiRtemplates:::.study_id_key(s$root)
    for (id in c(as.character(d$ccfid), hvtiRtemplates:::.id_digest(d$ccfid, key))) {
      expect_false(grepl(id, html, fixed = TRUE), info = id)
    }
    payload <- hvtiRtemplates:::.extract_provenance(html, managed = TRUE)
    expect_identical(payload$mirror$model_file, "lm-propensity_binary.rds")
    expect_identical(payload$mirror$model_set, "outcome-analysis")
    expect_false(is.null(payload$analysis))
    if (match) {
      expect_identical(payload$mirror$match, "match")
      expect_identical(unlist(payload$mirror$join), c(no_flag = 0L, no_score = 0L))
      expect_true("match" %in% vapply(payload$data, function(r) r$role, character(1L)))
    }
  }
})
```

- [ ] **Step 2: Reinstall and run.**

```bash
R_LIBS=$SCRATCH/lib-lpmirror R CMD INSTALL --no-docs -l $SCRATCH/lib-lpmirror .
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lp-mirror.R")'
```

Expected FAIL: the figure and identifier expectations pass already, and the payload ones fail: `payload$mirror$model_file` is `NULL`, `payload$analysis` is `NULL`.

- [ ] **Step 3: Implement.** Replace the `provenance` chunk's `cat(...)` call with:

```r
cat(hvtiRtemplates:::.embed_provenance(
  .in,
  data = .provenance_data,
  artifacts = .provenance_artifacts,
  extra = list(
    subject = SUBJECT, type = TYPE,
    analysis = .model_read$lineage$analysis, cohort = .model_read$lineage$cohort,
    mirror = Filter(Negate(is.null), list(
      model_set = if (is.null(MODEL_SET)) paste0(SUBJECT, "-", TYPE) else MODEL_SET,
      model_file = MODEL_FILE, binwidth = BINWIDTH, match = MATCH,
      join = if (!is.null(.join)) stats::setNames(as.list(.join$counts$patients), c("no_flag", "no_score"))
    ))
  )
))
```

- [ ] **Step 4: Reinstall and run.**

```bash
R_LIBS=$SCRATCH/lib-lpmirror R CMD INSTALL --no-docs -l $SCRATCH/lib-lpmirror .
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lp-mirror.R")'
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-template-provenance.R")'
```

Expected PASS: `test-lp-mirror.R` FAIL 0, SKIP 0; `test-template-provenance.R` FAIL 0.

- [ ] **Step 5: Commit.**

```bash
git add inst/templates/40_graphs/lp-mirror.qmd tests/testthat/test-lp-mirror.R
git commit -m "lp-mirror: record the bundle it read and the match join in its provenance

The payload names the set and file read, the bundle's analysis and cohort,
the bin width, and with MATCH the column, the match dataset's version and
the two join counts. A rendered report names no patient, raw or digested.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Mutation check.** Print one identifier from the match read and confirm the render test catches it; restore.

```bash
sed -i '' 's/^  scores\$matched <- .join\$matched$/  scores$matched <- .join$matched\n  cat(match_data$data[[.id]][1L], "\\n")/' inst/templates/40_graphs/lp-mirror.qmd
grep -n 'match_data\$data\[\[.id\]\]\[1L\]' inst/templates/40_graphs/lp-mirror.qmd
R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lp-mirror.R")'
git checkout -- inst/templates/40_graphs/lp-mirror.qmd
```

Expected: `grep` prints the inserted line, and the render test fails on `9100001` in the `MATCH` pass. If BSD `sed` wrote a literal `n` instead of a newline, `grep` prints nothing: insert the line with an editor instead and rerun. `git status --short` is clean afterwards. No reinstall is needed after the restore: the render reads the template through `add_job()` under `load_all()`, and the installed internals did not change.

---

## Task 8: The gallery jobs

**Files:**
- Modify: `dev/gallery/gallery.R` (header comment near line 11; `gallery_job()` near line 90)
- Modify: `dev/gallery/family-lm.R` (header comment; `columns`; `jobs`)
- Modify: `dev/gallery/notes.json`

**Interfaces:**
- Produces a gallery job field `template`: a job whose name is not its template's (`lp-mirror-matched`) names it there. `gallery_job()` splits `spec$template %||% name` into prefix and qualifier.
- Produces the column `match_pair` (0/1, simulated) in the gallery cohort, owned by the `lm` family.
- Produces gallery jobs `lp-mirror` (set `approach-propensity`, beside `lm-propensity_binary`) and `lp-mirror-matched` (set `approach-matched`, `MODEL_SET <- "approach-propensity"`, `MATCH <- "match_pair"`, `ID <- "patient_id"`). Two jobs of one template cannot share a set, because `add_job()` refuses to overwrite a job file, so the matched job reads the bundle through `MODEL_SET`.

The gallery is dev tooling with no test file; its verification is the render in Step 4.

- [ ] **Step 1: Let a gallery job name its template.** In `dev/gallery/gallery.R`, extend the `jobs:` paragraph of the header comment to read:

```r
#   - jobs: one entry per template, in render order, each naming the set it
#     belongs to (subject and type) and the study choices typed under its
#     EDIT: markers, as demo-study.R's set_choices() takes them. A second job
#     of one template takes a name of its own and names its template in
#     `template`, as lp-mirror-matched does.
```

and in `gallery_job()` change

```r
  parts <- strsplit(name, "-", fixed = TRUE)[[1L]]
```

to

```r
  parts <- strsplit(spec$template %||% name, "-", fixed = TRUE)[[1L]]
```

- [ ] **Step 2: Add the match column and the two jobs.** In `dev/gallery/family-lm.R`:

Header: change `# covariates, so every model has something to find.` to:

```r
# covariates, so every model has something to find. lp-mirror draws the
# lm-propensity_binary bundle, once in its approach-propensity set and once,
# as lp-mirror-matched, from a set of its own with a simulated match flag.
```

In `columns`, inside the `with_seed()` block, after the line `prior <- stats::rpois(n, exp(-1.2 + 0.25 * a + 0.5 * d$hx_chf))`:

```r
      # A pair-match flag, as a SAS match would leave it: most transcatheter
      # patients find a surgical partner, and fewer surgical ones are used.
      # Drawn last, so no draw above moves.
      paired <- stats::rbinom(n, 1L, ifelse(tavr == 1L, 0.85, 0.45))
```

After `d$prior_ops <- prior`:

```r
    d$match_pair <- paired
```

In `labels`, change `prior_ops = "Number of prior cardiac operations"` to `prior_ops = "Number of prior cardiac operations", match_pair = "In a matched pair (simulated)"`.

In `jobs`, after the `"lm-propensity_binary"` entry and before `"lm-propensity_ordinal"`:

```r
    # The mirrored histogram of that bundle, in its set, with no match flag.
    "lp-mirror" = list(subject = "approach", type = "propensity", choices = list(
      "^GROUP_LABELS <- " = "GROUP_LABELS <- c(surgical = \"Surgical\", transcatheter = \"Transcatheter\")"
    )),
    # The same bundle from a set of its own, with the simulated match flag, so
    # the matched figure is drawn too.
    "lp-mirror-matched" = list(template = "lp-mirror", subject = "approach", type = "matched", choices = list(
      "^MODEL_SET <- " = "MODEL_SET <- \"approach-propensity\"",
      "^GROUP_LABELS <- " = "GROUP_LABELS <- c(surgical = \"Surgical\", transcatheter = \"Transcatheter\")",
      "^MATCH <- " = "MATCH <- \"match_pair\"",
      "^ID <- " = "ID <- \"patient_id\""
    )),
```

- [ ] **Step 3: Add the gallery note.** In `dev/gallery/notes.json`, after the `"lm-propensity_binary"` entry, add:

```json
  "lp-mirror": {
    "issues": [],
    "note": "Two figures, all patients and under the matching weights. A second gallery job, lp-mirror-matched, sets MATCH to a simulated flag and adds the matched figure."
  },
```

Check the file still parses: `python3 -c 'import json; json.load(open("dev/gallery/notes.json"))'` prints nothing.

- [ ] **Step 4: Reinstall and render the three jobs.** Run from the repo root, through `Rscript -e`, so `gallery.R` finds `dev/gallery` from the working directory:

```bash
R_LIBS=$SCRATCH/lib-lpmirror R CMD INSTALL --no-docs -l $SCRATCH/lib-lpmirror .
rm -rf $SCRATCH/lp-gallery
R_LIBS=$SCRATCH/lib-lpmirror Rscript -e 'source("dev/gallery/gallery.R"); root <- gallery_study("$SCRATCH/lp-gallery/study"); built <- gallery_build(root, only = c("lm-propensity_binary", "lp-mirror", "lp-mirror-matched")); print(built[, c("template", "seconds", "error")], row.names = FALSE); print(list.files(study_dir("graphs", root), recursive = TRUE, pattern = "[.]png$"))'
```

Expected: three rows with `error` `NA`; PNGs `approach-propensity/lp-mirror-unmatched.png`, `approach-propensity/lp-mirror-weighted.png`, and the three `approach-matched/lp-mirror-*.png`. Open `approach-matched/lp-mirror-matched.png` and confirm by eye: transcatheter above the axis, surgical below, grey "All patients" behind colored matched bars, one legend row, symmetric y-axis.

- [ ] **Step 5: Commit.** `dev/` is build-ignored, so this commit ships nothing.

```bash
git add dev/gallery/gallery.R dev/gallery/family-lm.R dev/gallery/notes.json
git commit -m "Gallery: add the lp-mirror jobs

lp-mirror draws the lm-propensity_binary bundle in its own set; a second job,
lp-mirror-matched, reads it from a set of its own through MODEL_SET with a
simulated match_pair flag, so the matched figure renders too. A gallery job
may now name its template, so one template can have two jobs.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 9: Docs, news fragment, full gates and the pull request

**Files:**
- Modify: `inst/templates/README.md` (template table after line 17; qualified-templates paragraph lines 82 to 92; figure-name table after line 353)
- Create: `news/feat-lp-mirror.md`

**Interfaces:** consumes everything above; produces the pull request.

- [ ] **Step 1: README.** In `inst/templates/README.md`:

After the row for `40_graphs/hs-concordance.qmd` add:

```markdown
| `40_graphs/lp-mirror.qmd` | mirrored histogram of a saved propensity score: all patients, under the matching weights, and matched | `40_graphs/` or `graphs/` |
```

In the qualified-templates paragraph, change `` `dc-eda`, `hs-setup`, `hs-concordance`, the paired `` to `` `dc-eda`, `hs-setup`, `hs-concordance`, `lp-mirror`, the paired ``, and before the sentence `` The other prefixes here remain unqualified. `` insert:

```markdown
`lp` is qualified from its first template, `lp-mirror`, so a later `lp` shape, such as calibration, arrives as a
qualifier of its own.
```

In the figure-name table, after the `hp` row:

```markdown
| lp-mirror | `lp-mirror-unmatched`, `lp-mirror-weighted`, and `lp-mirror-matched` when `MATCH` is set |
```

- [ ] **Step 2: News fragment.** Create `news/feat-lp-mirror.md`:

```markdown
* New template `lp-mirror`, the mirrored histogram of the propensity score:
  `add_job("lp.mirror", subject, type)` with the subject and type of the
  `lm-propensity_binary` job it plots. It reads that job's saved bundle and
  never refits, drawing treated patients above the axis and controls below:
  all patients, then under the matching weights, and, when `MATCH` names a
  pair-match column, the matched patients. The y-axis is derived from the
  counts, the same above and below. The groups are labelled by the declared
  treatment levels, or by `GROUP_LABELS`. A bundle without lineage, or built
  from data that has changed since, stops with the job to render again.
  `MATCH` is joined onto the scored patients by a study-keyed digest of `ID`,
  so the job keeps and prints no identifier; it counts the scored patients
  with no flag and the flags with no score, and stops when fewer than half
  the scored patients are in the dataset. `lp` becomes a qualified prefix.

* `lm-checkpred`'s `MODEL_FILE` and `MODEL_SET` checks are now shared with
  `lp-mirror`. An `NA` in either now stops with the setting's own message
  rather than an R error.
```

- [ ] **Step 3: Commit the docs.**

```bash
git add inst/templates/README.md news/feat-lp-mirror.md
git commit -m "Document lp-mirror and add its news fragment

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 4: Gate: roxygen leaves no diff.**

```bash
R_LIBS=$SCRATCH/lib-lpmirror Rscript -e 'devtools::document()'
git status --short
```

Expected: `git status --short` prints nothing (both new helpers are `@noRd`).

- [ ] **Step 5: Gate: lint.**

```bash
R_LIBS=$SCRATCH/lib-lpmirror Rscript -e 'l <- lintr::lint_package(); print(l); quit(status = length(l) > 0)'
```

Expected: `No lints found.`, exit 0.

- [ ] **Step 6: Gate: the full suite, one file per command.** Reinstall first, then run every test file:

```bash
R_LIBS=$SCRATCH/lib-lpmirror R CMD INSTALL --no-docs -l $SCRATCH/lib-lpmirror .
for f in tests/testthat/test-*.R; do echo "== $f"; R_LIBS=$SCRATCH/lib-lpmirror NOT_CRAN=true Rscript -e "devtools::load_all(quiet=TRUE); testthat::test_file('$f')" 2>&1 | grep -E "FAIL [0-9]+ \| WARN [0-9]+ \| SKIP [0-9]+ \| PASS [0-9]+"; done
```

Expected: every line `FAIL 0`, apart from anything recorded in Task 0's baseline file, which must be unchanged. `SKIP 0` everywhere on macOS. `WARN 0` everywhere except `test-rf-templates.R`, whose known varPro notices are muffled on CI but can show locally; compare its WARN count with the baseline rather than accepting it unread. Any other WARN, SKIP or FAIL is new and is investigated before going on.

- [ ] **Step 7: Gate: the three count scripts.**

```bash
python3 dev/specs/artifacts/check-roadmap-counts.py
python3 dev/specs/artifacts/check-spec-counts.py
python3 dev/specs/artifacts/check-flow-counts.py
```

Expected: `Catalog agrees with disk: 65 template rows routed to hvtiRtemplates, 33 on disk.`, `Spec agrees with the map: ...`, `Diagrams agree with the maps: ...`; each exits 0.

- [ ] **Step 8: Gate: the news check, after committing.**

```bash
git fetch origin
python3 .github/scripts/news.py check --base origin/main
```

Expected: exit 0, the fragment `news/feat-lp-mirror.md` found.

- [ ] **Step 9: Gate: the gallery render of both lp-mirror jobs.** Rerun Task 8 Step 4's three commands verbatim. Expected: three rows, `error` `NA` on each.

- [ ] **Step 10: Gate: no em-dashes in the added lines.**

```bash
git diff origin/main...HEAD -- . ':!dev/specs/2026-08-29-template-conversion-roadmap.md' | python3 -c 'import sys; hits = [l for l in sys.stdin if l.startswith("+") and "\u2014" in l]; print("".join(hits) or "none")'
```

Expected: `none`. The regenerated roadmap is excluded because its renderer marks an empty cell with that character.

- [ ] **Step 11: Gate: local code review.** Run `/code-review` on the branch diff against `origin/main`. Fix every correctness finding with its own commit, rerun the affected test files and Steps 5 to 8, and record in the PR body that the local review stood in for the bot (AGENTS.md: Copilot reviews only the commit a PR is opened with).

- [ ] **Step 12: Push and open the PR.**

```bash
git push -u origin feat/lp-mirror
gh pr create --base main --title "New template: lp-mirror" --body "$(cat <<'EOF'
Implements dev/specs/2026-10-11-lp-mirror-template-design.md, following dev/specs/2026-10-11-lp-mirror-template-plan.md.

- New `inst/templates/40_graphs/lp-mirror.qmd`: the mirrored propensity histogram, read from a saved `lm-propensity_binary` bundle without refitting. Unmatched and weighted figures always; a matched figure when `MATCH` names a pair-match column, joined by a study-keyed ID digest. Derived symmetric y-axis; a count table under each figure; PNG and PDF through `.save_figure()`.
- `lp` becomes a qualified prefix: the ledger row is `lp-mirror`, shipped, and the roadmap is re-rendered.
- `.handoff_path()` and `.bundle_ids()` lifted out of `lm-checkpred` so both templates share them.
- Gallery: `lp-mirror`, and `lp-mirror-matched` with a simulated match flag.

Gates: `devtools::document()` no diff; `lintr::lint_package()` 0; full suite FAIL 0, one file per command, `NOT_CRAN=true`; the three count scripts; `news.py check`; gallery render of both jobs. A local `/code-review` stood in for the Copilot review on every push after the first.

Floors unchanged: hvtiPlotR >= 2.8.0, hvtiRpropensity >= 0.1.10. `Version:` untouched.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Do not merge.

---

## Decisions this plan makes where the spec was silent or the code disagreed

1. **Which group is drawn above the axis.** hvtiPlotR 2.8.5's `hv_mirror_hist()` help says control is `group_levels[1]` and treated bars go above, but its code draws `group_levels[1]` above. The spec wants treated above, so `mirror_groups()` puts the treated level first, and Task 4's test asserts the sign of each group's bars.
2. **The unmatched figure.** Without `weight_col`, `hv_mirror_hist()` requires a `match_col`. The job passes its own all-zero `matched` column and keeps only the `"Before"` layer.
3. **Unflagged patients.** `hv_mirror_hist()` drops incomplete rows, so an NA flag would silently remove a scored patient. The join sets an unflagged patient's flag to 0, draws them as unmatched and counts them.
4. **The y-axis.** `hv_mirror_hist()` pads each side separately, so its limits are not symmetric. `mirror_figure()` overrides `$meta$lower`, `$meta$upper` and `$meta$y_breaks` with one limit from the tallest bar, padded as hvtiPlotR pads.
5. **`SUBJECT`/`TYPE` marked `EDIT:`.** `test-templates.R` allows a marker only in a chunk labelled `edit-`, so the instruction is an HTML comment above the `set` chunk, as in `hp.qmd`.
6. **Too few joined.** The spec gives no threshold; the job stops when fewer than half of the scored patients are in the `MATCH` dataset.
7. **`GROUP_LABELS`.** Named by treatment level, so the order cannot be got wrong.
8. **The weighted table.** It adds the sum of the matching weights, the total the weighted bars show, beside the patient counts.
9. **`MATCH` and the data-route gate.** `test-template-data-routes.R` expects every template that reads its own `DATASET` to offer `JOIN`. `lp-mirror` reads `DATASET` only for one flag column, so it is exempted by name, with the reason in the test. `test-data-contract.R` leaves it among the pending templates, as it does `dc-stddiff` and `bd`.
10. **The second gallery job** lives in its own set (`approach-matched`) and reads the bundle through `MODEL_SET`, because `add_job()` will not write a second job of one template into one set.

## Spec coverage

| spec section | task |
|---|---|
| 1. What `lp` is (qualified prefix, ledger row) | 2 |
| 2. Placement and `add_job("lp.mirror", ...)` | 2 |
| 2. Reading the bundle, `MODEL_FILE`/`MODEL_SET` checks | 1, 3 |
| 2. Lineage and rebuild command; never refits | 3 |
| 2. What the bundle supplies; no column names typed | 3, 4 |
| 2. Optional match flag, digest join, two counts, too-few stop | 6 |
| 3. Unmatched and weighted figures | 5 |
| 3. Matched figure | 6 |
| 3. PNG and PDF via `.save_figure()` | 5, 6 |
| 3. Derived symmetric y-axis | 4 |
| 3. Count tables | 5, 6 |
| 3. Settings table | 2 |
| 3. Out of scope (presentation copies, pptx, axis breaks, `setwd()`, balance plot, refit) | none built; 3 asserts no refit |
| 4. Catalog, roadmap, spec-count scripts | 2, 9 |
| 4. `.lintr` file key | 2 |
| 4. hvtiPlotR and hvtiRpropensity floors, check tied to DESCRIPTION | 2 |
| 5. Provenance | 7 |
| 6. Gallery | 8 |
| 7.1 Reading | 3 |
| 7.2 Labels | 4 |
| 7.3 Axis | 4 |
| 7.4 Weights | 5 |
| 7.5 Match join | 6 |
| 7.6 Lineage | 3 |
| 7.7 No identifiers | 6, 7 |
| 7.8 Render | 7 |
