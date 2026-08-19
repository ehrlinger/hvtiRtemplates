# R_hazard Job Templates Implementation Plan

> **Migrated 2026-08-18** from `/Volumes/qhsstudies/cardiac/valves/aortic/replacement/pericardial/lv_function/survival/analyses/R_hazard/docs/plans/2026-08-12-r-hazard-job-templates.md`.
> Cross-references to the other migrated documents have been repointed to their
> paths in this repository; the text is otherwise unchanged. Study folders on the
> share do not host git repositories, so the design record lives with the package
> that owns the migration programme. `specs/artifacts/README.md` records what
> moved and from where.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up `analyses/R_hazard/` with five copy-and-edit Quarto templates (`ac`, `hz`, `hp`, `bh`, `hm`) that reproduce the corresponding SAS job types in R, and split the existing parity work into `analyses/R_parity/` so that validation depends on production and not the reverse.

**Architecture:** Two sibling Quarto projects under `analyses/`. `R_hazard` owns the study's data contract (`study_root()`, `sas_path()`, `read_built()`, `assert_cohort()`) and the templates. `R_parity` keeps the tolerance policy and `.lst` access, and sources the data contract from `R_hazard` through one explicit shim file. Templates render as-is against this study; study-specific values are marked `# EDIT:`.

**Tech Stack:** R (>= 4.4), Quarto (`type: default`), `TemporalHazard`, `survival`, `haven`, `testthat`, `knitr`. Optional at runtime: `hvtiRutilities`, `hvtiPlotR`, `numDeriv`.

**Spec:** `specs/2026-08-11-r-hazard-job-templates-design.md` (commit `86e5b81`)

## Global Constraints

- **NO GIT. This overrides every `git` step written anywhere below.** Instructed 2026-08-12. The study tree is a plain working directory: do not init, add, commit, branch, diff, or open a PR in it. Wherever a task ends in a "Commit" step, **append a line to `.superpowers/sdd/progress.md` instead**, naming the files written and the verification output. Wherever the process calls for a review package built from `git diff`, **hand the reviewer the file paths directly** and have it read them.

  Why: the repo in the study tree is not an adopted workflow (its `master` ends at a 2017 cron commit and there is no remote), and the SMB mount makes git unsafe — `core.fileMode` churns 301 files per status, the share unmounted mid-commit during execution, and Quarto renders left undeletable `.smbdelete*` tombstones that only a remount cleared.

  **Consequence to work under:** there is no undo. Before rewriting a file that already renders, copy it aside first. Tasks 7 to 11 each derive a template from a working parity document — read the source, never edit it in place.

- **Quarto rendering happens on the SERVER, not on the Mac. This overrides every `quarto render` step below.** Verification on the Mac is `Rscript -e 'knitr::knit("<file>.qmd", output = tempfile(fileext = ".md"))'`, which executes every chunk against the real data and is the acceptance test here. A document that knits is done as far as this plan is concerned; the rendered HTML is produced on the server.

  Why: Quarto always deletes `<file>_files/execute-results` at the end of a render, and this SMB mount cannot delete a file it just wrote — the client leaves an undeletable `.smbdeleteAAA*` tombstone and the directory never empties. Ruled out by experiment: `freeze: true`, `embed-resources: false`, `--no-clean`, and starting from a clean tree all still fail. It is the write-then-delete pattern itself, not configuration. Short renders occasionally win the race, which is why a one-chunk smoke document succeeded and real ones do not.

  **Do not retry a failed render.** Each attempt leaves another tombstone, and the directory then blocks even `rm -rf` until the share is remounted.

- The tree is at `/Volumes/qhsstudies/cardiac/valves/aortic/replacement/pericardial/lv_function/survival` (server: `/studies/...`).
- **No literal study path in any R or `.qmd` file.** Paths resolve at runtime via `study_root()`. The server and the Mac mount disagree on the absolute prefix.
- **No PHI** in code, notes, commits, or rendered output.
- **`R/` holds side-effect-free helpers only.** Anything with top-level executable code goes in `scripts/`. Every consumer sources `R/` wholesale with `list.files()`; a side effect there runs on every render. Enforced by a test in Task 5.
- **Dependency direction is fixed:** `R_parity` → `R_hazard`. Nothing in `R_hazard` may reference `R_parity`, `parity.R`, `.lst` files, or a tolerance.
- **Quarto project type is `default`, never `book`.** A `book` resolves its whole chapter manifest before rendering and refuses a single-file render while any listed chapter is missing.
- **`df-print: default` and `embed-resources: true`.** `df-print: paged` pulls a `libs/` tree onto a share whose clients disagree about directory contents, and Quarto's cleanup then fails with "Directory not empty (os error 39)".
- **Templates are working documents.** Each renders unedited against this study. Study-specific lines carry a `# EDIT:` comment.
- **No `.lst` parsing, `compare_parity()`, tolerance, or published-value cross-check** anywhere under `R_hazard`.
- Versioning: this is not a package; no version digits are rolled by this plan.

---

## File Structure

**Created:**

| Path | Responsibility |
|---|---|
| `analyses/R_hazard/_quarto.yml` | project config for the analysis project |
| `analyses/R_hazard/.gitignore` | ignore `_output/`, `.quarto/`, `*.rds` |
| `analyses/R_hazard/index.qmd` | overview + environment + dataset manifest |
| `analyses/R_hazard/scripts/clean-freeze.R` | pre-render cleanup (has side effects, so not in `R/`) |
| `analyses/R_hazard/templates/ac.template.qmd` | actuarial life table |
| `analyses/R_hazard/templates/hz.template.qmd` | multiphase parametric fit |
| `analyses/R_hazard/templates/hp.template.qmd` | nomogram + hazard/survival figures |
| `analyses/R_hazard/templates/bh.template.qmd` | bagging report |
| `analyses/R_hazard/scripts/bh.template-run.R` | bagging runner (long job, writes `.rds`) |
| `analyses/R_hazard/templates/hm.template.qmd` | multivariable model report |
| `analyses/R_hazard/scripts/hm.template-run.R` | multivariable runner (long job, writes `.rds`) |
| `analyses/R_parity/R/00-hazard-helpers.R` | the one shim: sources the data contract from `R_hazard` |
| `analyses/R_hazard/tests/testthat/helper-source.R` | sources `R_hazard/R/` for the test suite |
| `analyses/R_hazard/tests/testthat/test-r-dir-is-pure.R` | enforces the `R/` invariant |

**Moved (`git mv`, preserving history):**

| From | To |
|---|---|
| `analyses/R_analysis/` | `analyses/R_parity/` |
| `analyses/R_parity/R/paths.R` | `analyses/R_hazard/R/paths.R` |
| `analyses/R_parity/R/read_built.R` | `analyses/R_hazard/R/read_built.R` |
| `analyses/R_parity/R/clean-freeze.R` | `analyses/R_hazard/scripts/clean-freeze.R` |
| `analyses/R_parity/R/run-bagging.R` | `analyses/R_parity/scripts/run-bagging.R` |
| `analyses/R_parity/tests/testthat/test-paths.R` | `analyses/R_hazard/tests/testthat/test-paths.R` |
| `analyses/R_parity/tests/testthat/test-read-built.R` | `analyses/R_hazard/tests/testthat/test-read-built.R` |

**Modified:**

| Path | Change |
|---|---|
| `analyses/R_parity/R/parity.R` | gains `lst_path()`, moved out of `paths.R` |
| `analyses/R_parity/_quarto.yml` | `pre-render` path follows `clean-freeze.R` |
| `analyses/R_parity/tests/testthat/helper-source.R` | sources both projects' `R/` |
| `analyses/R_parity/scripts/run-bagging.R` | explicit sourcing; no wholesale `R/` source |

**Split rationale.** `paths.R` currently holds three functions with two different owners. `study_root()` and `sas_path()` describe where the study is, which the analysis needs. `lst_path()` maps a stage to its SAS listing, which only parity needs. Task 4 moves `lst_path()` into `parity.R` so that no `.lst` string exists anywhere under `R_hazard`.

---

## Two working-tree conditions found before planning

Both are live and both would corrupt this plan's commits if not handled first.

**1. File-mode churn.** `git status` reports 323 entries; 301 are `mode change 100644 => 100755` with zero content change, produced by the share's permission handling. Any `git add -A` in a later task sweeps 301 unrelated files into a commit. Task 1 neutralises it.

**2. `R/run-bagging.R` executes on source.** Every `.qmd` sources the helper directory wholesale:

```r
for (f in list.files("../R", pattern = "[.]R$", full.names = TRUE)) source(f)
```

`R/run-bagging.R` is not a function library. Its top level calls `read_built()`, fits a base model, and runs a 500-replicate bootstrap. So rendering *any* stage runs the bagging job. This is why the Global Constraints make `R/` helpers-only and why Task 5 adds a test for it.

---

### Task 1: Stop the file-mode churn

**Files:**
- Modify: `.git/config` (via `git config`, not by hand)

**Interfaces:**
- Consumes: nothing
- Produces: a working tree where `git status --porcelain` lists only real changes, which every later task's commit steps rely on

- [ ] **Step 1: Record the current noise level**

```bash
git -C . status --porcelain | wc -l
```

Expected: `323` (or another number in the hundreds).

- [ ] **Step 2: Confirm the entries are mode-only, not content**

```bash
git -C . diff --summary | grep -c 'mode change'
```

Expected: `301`. Now find the content changes hiding among them. Use
`--numstat`, **not** `--summary`: `--summary` reports only mode changes,
creations and deletions, so it prints nothing for a content-only edit and
reads as all-clear when it is not.

```bash
git -C . diff --numstat | awk '$1 != 0 || $2 != 0'
```

Expected on this checkout, as of 2026-08-12: **three files**, which are
pre-existing uncommitted edits by a human and are **not** this plan's work.

```
2  2  datasets/vars.sas
3  3  distributions/hz.dead.sas
2  2  graphs/hp.dead_s3.avarea_lvmass_3d.sas
```

They correct the study path (the tree gained a `replacement/` level at some
point), and `hz.dead.sas` additionally switches `set library.built` to
`set library.built_n`, which is a different input dataset.

**Leave all three alone.** Modifying the SAS tree is out of scope (design spec
section 8), and these belong to whoever made them. Every commit in this plan
names explicit paths under `analyses/`, so no `git add` here can sweep them in.
Never use `git add -A` or `git add .` in this plan.

**If the list differs from those three, stop and report** before proceeding.

- [ ] **Step 3: Disable file-mode tracking for this checkout**

```bash
git -C . config core.fileMode false
```

- [ ] **Step 4: Verify the noise is gone**

```bash
git -C . status --porcelain | grep -v '^??' | wc -l
```

Expected: `0`. Untracked entries (`??`) remain and are correct: they are the SAS jobs, `renv/`, `renv.lock`, `.Rprofile`, `.renvignore`, `survival.Rproj`.

- [ ] **Step 5: Create the working branch**

```bash
git -C . checkout -b feat/r-hazard-templates
```

No commit in this task. `core.fileMode` is local repository configuration and is not tracked.

---

### Task 2: Rename `R_analysis` to `R_parity`

**Files:**
- Move: `analyses/R_analysis/` → `analyses/R_parity/`
- Modify: `analyses/R_parity/tests/testthat/helper-source.R:12,20`
- Modify: `analyses/R_parity/R/run-bagging.R:5,20,153,160`

**Interfaces:**
- Consumes: clean working tree from Task 1
- Produces: `analyses/R_parity/` renders and tests green; no path string in the tree still says `R_analysis`

- [ ] **Step 1: Establish the baseline before touching anything**

```bash
cd analyses/R_analysis && Rscript -e 'testthat::test_dir("tests/testthat")'
```

Expected: `FAIL 0`. Record the PASS count. If it is not `FAIL 0`, stop and report — this plan must not begin on a red suite.

- [ ] **Step 2: Rename the directory**

```bash
git -C . mv analyses/R_analysis analyses/R_parity
```

- [ ] **Step 3: Run the suite to verify it fails**

```bash
cd analyses/R_parity && Rscript -e 'testthat::test_dir("tests/testthat")'
```

Expected: PASS. The helper walks up for `_quarto.yml` and does not hard-code the directory name, so the suite survives the rename. What is now stale is the *error message* it prints on failure, fixed next. If the suite instead fails, read the message before changing anything.

- [ ] **Step 4: Update the stale references**

In `analyses/R_parity/tests/testthat/helper-source.R`, replace lines 11-12 and the error text:

```r
# Walk up from wherever testthat set the working directory until _quarto.yml
# appears -- that marks the R_parity project root.

.r_parity_root <- local({
  d <- normalizePath(getwd(), mustWork = TRUE)
  while (!file.exists(file.path(d, "_quarto.yml"))) {
    p <- dirname(d)
    if (identical(p, d)) {
      stop("helper-source.R: walked to the filesystem root without finding ",
           "_quarto.yml. Run the suite from inside analyses/R_parity/.",
           call. = FALSE)
    }
    d <- p
  }
  d
})

for (.f in list.files(file.path(.r_parity_root, "R"),
                      pattern = "[.]R$", full.names = TRUE)) {
  source(.f)
}
```

In `analyses/R_parity/R/run-bagging.R`, change every `R_analysis` to `R_parity`: the usage comment on line 5, the fallback path on line 20, and the two `sas_path()` calls on lines 153 and 160.

- [ ] **Step 5: Verify nothing still says `R_analysis`**

```bash
grep -rn 'R_analysis' analyses/ --include='*.R' --include='*.qmd' --include='*.yml' --include='*.md'
```

Expected: no output. (The spec's `Predecessor:` line references the parity design, which is already correct.)

- [ ] **Step 6: Run the suite and render one stage**

```bash
cd analyses/R_parity && Rscript -e 'testthat::test_dir("tests/testthat")'
```

Expected: `FAIL 0`, same PASS count as Step 1.

```bash
cd analyses/R_parity && quarto render qmd/01-ac-dead.qmd
```

Expected: `Output created: _output/qmd/01-ac-dead.html`.

- [ ] **Step 7: Commit**

```bash
git add analyses/R_parity && git commit -m "refactor: rename R_analysis to R_parity

The directory held two activities with different scopes: comparing R against
stored SAS output, and doing the analysis in R. Only the first is parity work,
and that is what this directory has always contained. Renaming it frees the
name R_hazard for the analysis, which the next commits add.

Updates the two files that named the old directory in a string: the test
helper's failure message and run-bagging.R's fallback path and output paths."
```

---

### Task 3: Create the `R_hazard` project skeleton

**Files:**
- Create: `analyses/R_hazard/_quarto.yml`
- Create: `analyses/R_hazard/.gitignore`
- Move: `analyses/R_parity/R/clean-freeze.R` → `analyses/R_hazard/scripts/clean-freeze.R`
- Modify: `analyses/R_parity/_quarto.yml:21`

**Interfaces:**
- Consumes: `analyses/R_parity/` from Task 2
- Produces: `analyses/R_hazard/_quarto.yml` with `pre-render: scripts/clean-freeze.R`; `analyses/R_hazard/scripts/clean-freeze.R` as the single copy both projects use

- [ ] **Step 1: Create the directories**

```bash
mkdir -p analyses/R_hazard/R analyses/R_hazard/scripts analyses/R_hazard/templates analyses/R_hazard/tests/testthat
```

- [ ] **Step 2: Move `clean-freeze.R` out of `R/` and into `scripts/`**

```bash
git -C . mv analyses/R_parity/R/clean-freeze.R analyses/R_hazard/scripts/clean-freeze.R
```

It is a pre-render script whose top level deletes directories. Under the Global Constraints it may not live in any `R/`, and the spec's success criterion 4 forbids duplicating it, so both projects point at this one copy.

- [ ] **Step 3: Write `analyses/R_hazard/_quarto.yml`**

```yaml
# A `default` project, not a `book`. The book format resolves its whole chapter
# manifest before rendering anything, so it refuses a single-file render while
# any listed chapter is missing. That is hostile to authoring one job at a time.
#
# `render:` lists only index.qmd. Templates under templates/ are rendered
# individually while being authored, and instantiated jobs are added here as
# they are created. A whole-project render must not sweep in every template.

project:
  type: default
  output-dir: _output
  # Quarto's own removal of <file>_files/execute-results fails on this network
  # share ("Directory not empty", os error 39) because two clients disagree
  # about directory contents: the render succeeds and the cleanup kills the
  # command. Remove the tree before Quarto looks at it.
  pre-render: scripts/clean-freeze.R

  render:
    - index.qmd

format:
  html:
    theme: cosmo
    toc: true
    toc-depth: 3
    code-fold: true
    # NOT df-print: paged -- it pulls a pagedtable JS/CSS tree into
    # <file>_files/libs/, which is what trips the share's cleanup race above.
    # Every table here goes through knitr::kable() anyway.
    df-print: default
    # Standalone HTML: reports get sent to collaborators, and a file that
    # depends on a sibling _files/ directory does not survive that.
    embed-resources: true

execute:
  echo: true
  warning: true
  error: false
  freeze: false
```

- [ ] **Step 4: Write `analyses/R_hazard/.gitignore`**

```gitignore
_output/
.quarto/
*_files/
*.knit.md
*.rds

/.quarto/
```

- [ ] **Step 5: Point `R_parity` at the moved script**

In `analyses/R_parity/_quarto.yml`, change line 21:

```yaml
  pre-render: ../R_hazard/scripts/clean-freeze.R
```

- [ ] **Step 6: Verify both projects still render**

```bash
cd analyses/R_parity && quarto render qmd/01-ac-dead.qmd
```

Expected: `Output created: _output/qmd/01-ac-dead.html`. **If Quarto rejects the `../` pre-render path**, stop and report: the fallback is a two-line `analyses/R_parity/scripts/clean-freeze.R` that does `source("../R_hazard/scripts/clean-freeze.R")`, which keeps one implementation but needs the success-criterion-4 wording checked.

- [ ] **Step 7: Commit**

```bash
git add analyses/R_hazard analyses/R_parity/_quarto.yml && git commit -m "feat: add R_hazard project skeleton

R_hazard is the permanent side of the split: it does the analysis in R, with
no .lst, no tolerance policy and no comparison. Its render list holds index.qmd
only, so a whole-project render never sweeps in the templates.

clean-freeze.R moves from R_parity/R/ to R_hazard/scripts/ and both projects
point at that one copy. It belongs in scripts/ rather than R/ because its top
level deletes directories, and every consumer sources R/ wholesale."
```

---

### Task 4: Move the data contract into `R_hazard`

**Files:**
- Move: `analyses/R_parity/R/paths.R` → `analyses/R_hazard/R/paths.R`
- Move: `analyses/R_parity/R/read_built.R` → `analyses/R_hazard/R/read_built.R`
- Move: `analyses/R_parity/tests/testthat/test-paths.R` → `analyses/R_hazard/tests/testthat/test-paths.R`
- Move: `analyses/R_parity/tests/testthat/test-read-built.R` → `analyses/R_hazard/tests/testthat/test-read-built.R`
- Create: `analyses/R_hazard/tests/testthat/helper-source.R`
- Create: `analyses/R_parity/R/00-hazard-helpers.R`
- Modify: `analyses/R_hazard/R/paths.R` (remove `lst_path()`)
- Modify: `analyses/R_parity/R/parity.R` (gain `lst_path()`)

**Interfaces:**
- Consumes: `analyses/R_hazard/_quarto.yml` from Task 3 (the shim locates the project by walking up to it)
- Produces:
  - `study_root(start = getwd()) -> character(1)`
  - `sas_path(...) -> character(1)`
  - `built_path() -> character(1)`, `built_manifest() -> data.frame`
  - `read_built() -> data.frame`
  - `cohort_counts(d) -> list(n, n_events, n_censored)`
  - `assert_cohort(d) -> invisible(TRUE)`, errors otherwise
  - all of the above available in `R_parity` unchanged, via the shim
  - `lst_path(stage) -> character(1)` now defined in `R_parity/R/parity.R`

- [ ] **Step 1: Move the four files**

```bash
git -C . mv analyses/R_parity/R/paths.R analyses/R_hazard/R/paths.R
git -C . mv analyses/R_parity/R/read_built.R analyses/R_hazard/R/read_built.R
git -C . mv analyses/R_parity/tests/testthat/test-paths.R analyses/R_hazard/tests/testthat/test-paths.R
git -C . mv analyses/R_parity/tests/testthat/test-read-built.R analyses/R_hazard/tests/testthat/test-read-built.R
```

- [ ] **Step 2: Run the `R_parity` suite to verify it fails**

```bash
cd analyses/R_parity && Rscript -e 'testthat::test_dir("tests/testthat")'
```

Expected: FAIL, with errors of the form `could not find function "sas_path"` or `could not find function "read_built"` from `test-parity.R` and `test-parse-lst.R`. This is the point of the step: it proves the parity suite really did depend on those helpers, so the shim in Step 4 is load-bearing rather than decorative.

- [ ] **Step 3: Remove `lst_path()` from `paths.R` and add it to `parity.R`**

Delete lines 24-38 of `analyses/R_hazard/R/paths.R` (the `lst_path()` definition and its two comment lines), leaving the file ending after `sas_path()`.

Append to `analyses/R_parity/R/parity.R`:

```r
# Stage -> reference .lst. Lives here, not in R_hazard/R/paths.R, because a
# path to a SAS listing is a parity concern: R_hazard must contain no .lst
# string at all (design spec, section 5). The three stages live in three
# different SAS directories, which is why this is a lookup and not a template.
lst_path <- function(stage) {
  map <- c(
    ac = file.path("distributions", "ac.dead_JR.lst"),
    hz = file.path("distributions", "hz.dead_JR.lst"),
    hp = file.path("graphs",        "hp.dead_JR.lst"),
    hm = file.path("analyses",      "hm.dead_s3_JR.lst")
  )
  if (!stage %in% names(map)) {
    stop("unknown stage: ", stage, ". Expected one of: ",
         paste(names(map), collapse = ", "), call. = FALSE)
  }
  sas_path(map[[stage]])
}
```

- [ ] **Step 4: Write the shim `analyses/R_parity/R/00-hazard-helpers.R`**

```r
# R_parity sources the study's data contract FROM R_hazard, never the reverse
# (design spec, section 3.1). Validation depends on production, the way tests
# depend on a package. Because parity is re-run whenever a defect surfaces or a
# TemporalHazard release needs re-qualifying, the analysis has to be the layer
# that stands alone.
#
# Named 00- so it sorts first. Every consumer in this project sources R/
# wholesale with list.files(), which returns names in sorted order, so this
# runs before parity.R and lst_path() can rely on sas_path().
#
# Dependency-free by design, matching tests/testthat/helper-source.R: the
# server has two R installations whose libraries differ, so a helper that needs
# a package works under one and not the other.
#
# Files are listed explicitly rather than sourced wholesale. R_hazard/R/ holds
# only side-effect-free helpers, but naming them means a new file over there
# cannot silently change what R_parity executes.

# Assigned rather than a bare local() call, because Task 5 adds a test that
# every top-level expression in R/ is an assignment. The value records where
# the contract came from, which is worth having when two checkouts disagree.

.hazard_helpers <- local({
  d <- normalizePath(getwd(), mustWork = TRUE)
  while (!file.exists(file.path(d, "_quarto.yml"))) {
    p <- dirname(d)
    if (identical(p, d)) {
      stop("00-hazard-helpers.R: walked to the filesystem root without ",
           "finding _quarto.yml, so the R_parity project root is unknown. ",
           "Run from inside analyses/R_parity/.", call. = FALSE)
    }
    d <- p
  }

  hazard_r <- file.path(dirname(d), "R_hazard", "R")
  if (!dir.exists(hazard_r)) {
    stop("00-hazard-helpers.R: expected the sibling project at ", hazard_r,
         ", which does not exist. R_parity cannot run without R_hazard's ",
         "data contract.", call. = FALSE)
  }

  for (f in c("paths.R", "read_built.R")) {
    p <- file.path(hazard_r, f)
    if (!file.exists(p)) {
      stop("00-hazard-helpers.R: ", p, " is missing. R_hazard's data ",
           "contract is incomplete.", call. = FALSE)
    }
    sys.source(p, envir = globalenv())
  }
  hazard_r
})
```

- [ ] **Step 5: Write `analyses/R_hazard/tests/testthat/helper-source.R`**

```r
# This project is not an R package, so testthat does not load R/ for us --
# source it by hand. Dependency-free for the same reason as R_parity's copy:
# the server has two R installations whose libraries differ, so a helper that
# needs a package passes under one and fails under the other.
#
# Walk up from wherever testthat set the working directory until _quarto.yml
# appears -- that marks the R_hazard project root.

.r_hazard_root <- local({
  d <- normalizePath(getwd(), mustWork = TRUE)
  while (!file.exists(file.path(d, "_quarto.yml"))) {
    p <- dirname(d)
    if (identical(p, d)) {
      stop("helper-source.R: walked to the filesystem root without finding ",
           "_quarto.yml. Run the suite from inside analyses/R_hazard/.",
           call. = FALSE)
    }
    d <- p
  }
  d
})

for (.f in list.files(file.path(.r_hazard_root, "R"),
                      pattern = "[.]R$", full.names = TRUE)) {
  source(.f)
}
```

- [ ] **Step 6: Move the `lst_path()` test to `R_parity`**

`test-paths.R` moved to `R_hazard` in Step 1, but its `lst_path()` tests now belong with `parity.R`. Open `analyses/R_hazard/tests/testthat/test-paths.R`, cut every `test_that()` block that calls `lst_path()`, and paste them into `analyses/R_parity/tests/testthat/test-parity.R`.

If no such block exists, add one to `analyses/R_parity/tests/testthat/test-parity.R`:

```r
test_that("lst_path() maps known stages and rejects unknown ones", {
  expect_true(grepl("distributions/ac[.]dead_JR[.]lst$", lst_path("ac")))
  expect_true(grepl("graphs/hp[.]dead_JR[.]lst$", lst_path("hp")))
  expect_error(lst_path("zz"), "unknown stage: zz")
})
```

- [ ] **Step 7: Run both suites to verify they pass**

```bash
cd analyses/R_hazard && Rscript -e 'testthat::test_dir("tests/testthat")'
```

Expected: `FAIL 0`, covering `test-paths.R` and `test-read-built.R`.

```bash
cd analyses/R_parity && Rscript -e 'testthat::test_dir("tests/testthat")'
```

Expected: `FAIL 0`, and the total PASS count across both suites equals the Task 2 Step 1 baseline plus any test added in Step 6.

- [ ] **Step 8: Verify no `.lst` reference leaked into `R_hazard`**

```bash
grep -rn 'lst\|parity\|tolerance' analyses/R_hazard/R/
```

Expected: no output.

- [ ] **Step 9: Render a parity stage end to end**

```bash
cd analyses/R_parity && quarto render qmd/01-ac-dead.qmd
```

Expected: `Output created: _output/qmd/01-ac-dead.html`. This is the real proof that the shim works under knitr's working directory, which differs from testthat's.

- [ ] **Step 10: Commit**

```bash
git add analyses/R_hazard analyses/R_parity && git commit -m "refactor: move the study data contract into R_hazard

paths.R and read_built.R describe this study's data and are needed by both
projects, so they live with the permanent one. R_parity reaches them through a
single explicit shim, 00-hazard-helpers.R, named to sort first so parity.R can
rely on sas_path() at source time.

lst_path() goes the other way, into parity.R: a path to a SAS listing is a
parity concern, and R_hazard must contain no .lst string at all.

The shim names the two files rather than sourcing R_hazard/R/ wholesale, so a
new helper over there cannot silently change what R_parity executes."
```

---

### Task 5: Move side-effect scripts out of `R/` and enforce the invariant

**Files:**
- Move: `analyses/R_parity/R/run-bagging.R` → `analyses/R_parity/scripts/run-bagging.R`
- Modify: `analyses/R_parity/scripts/run-bagging.R:17-24`
- Create: `analyses/R_hazard/tests/testthat/test-r-dir-is-pure.R`
- Create: `analyses/R_parity/tests/testthat/test-r-dir-is-pure.R`

**Interfaces:**
- Consumes: `sas_path()` from Task 4
- Produces: a test in both projects that fails if any `R/*.R` file gains top-level executable code

This task fixes a live defect. `R/run-bagging.R` is sourced by every `.qmd` in the project and its top level runs a 500-replicate bootstrap, so rendering any stage runs the bagging job.

- [ ] **Step 1: Write the shared checker**

The check runs in both projects, so it is a function in `R_hazard/R/` rather
than two copies of a test body. Success criterion 4 forbids duplicating a file
between the projects, and a near-identical test in each is exactly that.

Create `analyses/R_hazard/R/purity.R`:

```r
# R/ is sourced wholesale by every .qmd and by both test helpers:
#
#   for (f in list.files("../R", pattern = "[.]R$", full.names = TRUE)) source(f)
#
# So a file in R/ with top-level executable code runs on every render. This was
# not hypothetical: R_parity/R/run-bagging.R called read_built() and ran a
# 500-replicate bootstrap at its top level, meaning every stage render fired a
# ten-minute job nobody asked for. Scripts belong in scripts/.
#
# The check is syntactic, not behavioural: parse each file and require every
# top-level expression to be an assignment. That admits function definitions
# and constants, and rejects calls.
#
# Returns a character vector of complaints, empty when the directory is clean,
# so the caller decides whether to warn or to fail.

r_dir_impurities <- function(dir) {
  files <- list.files(dir, pattern = "[.]R$", full.names = TRUE)
  out <- character(0)
  for (f in files) {
    for (e in parse(f)) {
      if (!(is.call(e) &&
            as.character(e[[1]])[1] %in% c("<-", "=", "<<-", "assign"))) {
        out <- c(out, paste0(
          basename(f), ": top-level expression is not an assignment: ",
          paste(deparse(e), collapse = " ")))
      }
    }
  }
  out
}
```

Add `"purity.R"` to the file list in `analyses/R_parity/R/00-hazard-helpers.R`
so `R_parity`'s suite can reach it:

```r
  for (f in c("paths.R", "read_built.R", "purity.R")) {
```

- [ ] **Step 2: Write the failing test in each project**

Create `analyses/R_hazard/tests/testthat/test-r-dir-is-pure.R`:

```r
test_that("every file in R/ is free of top-level side effects", {
  bad <- r_dir_impurities(file.path(.r_hazard_root, "R"))
  expect_equal(bad, character(0),
               info = paste("R/ is sourced wholesale on every render, so these",
                            "would execute every time. Move to scripts/."))
})
```

Create `analyses/R_parity/tests/testthat/test-r-dir-is-pure.R`:

```r
test_that("every file in R/ is free of top-level side effects", {
  bad <- r_dir_impurities(file.path(.r_parity_root, "R"))
  expect_equal(bad, character(0),
               info = paste("R/ is sourced wholesale on every render, so these",
                            "would execute every time. Move to scripts/."))
})
```

Two files, three lines each, calling one implementation. Not a duplicate.

- [ ] **Step 3: Run the tests to verify one fails**

```bash
cd analyses/R_parity && Rscript -e 'testthat::test_dir("tests/testthat", filter = "r-dir-is-pure")'
```

Expected: FAIL, naming `run-bagging.R` and a top-level expression such as `suppressPackageStartupMessages(...)`.

**If it also names `parity.R`, `preflight.R` or `read_built.R`, do not silence the test.** Those files were believed to be pure and were never checked; a complaint there is a second instance of the same defect and should be moved to `scripts/` on the same terms. Report what it named before changing anything.

```bash
cd analyses/R_hazard && Rscript -e 'testthat::test_dir("tests/testthat", filter = "r-dir-is-pure")'
```

Expected: PASS. `R_hazard/R/` holds only `paths.R` and `read_built.R`, which are function definitions and constants.

- [ ] **Step 4: Move the script**

```bash
mkdir -p analyses/R_parity/scripts
git -C . mv analyses/R_parity/R/run-bagging.R analyses/R_parity/scripts/run-bagging.R
```

- [ ] **Step 5: Replace its sourcing preamble**

In `analyses/R_parity/scripts/run-bagging.R`, replace lines 17-24 (the `.self` resolution and the `list.files()` loop) with:

```r
# Source the helpers explicitly. The old version resolved its own path with
# sys.frame(1)$ofile and then sourced its sibling directory wholesale, which
# only worked because it lived in R/ -- and living in R/ is precisely the bug
# this file was moved to fix.
#
# Walk up for _quarto.yml, the same dependency-free idiom the test helpers use.
.root <- local({
  d <- normalizePath(getwd(), mustWork = TRUE)
  while (!file.exists(file.path(d, "_quarto.yml"))) {
    p <- dirname(d)
    if (identical(p, d)) {
      stop("run-bagging.R: run this from inside analyses/R_parity/.",
           call. = FALSE)
    }
    d <- p
  }
  d
})
for (.f in list.files(file.path(.root, "R"), pattern = "[.]R$",
                      full.names = TRUE)) {
  source(.f)
}
```

Update the usage comment on line 5 to the new location:

```r
#   cd analyses/R_parity && Rscript scripts/run-bagging.R
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
cd analyses/R_parity && Rscript -e 'testthat::test_dir("tests/testthat")'
```

Expected: `FAIL 0`.

- [ ] **Step 7: Verify the script still starts**

```bash
cd analyses/R_parity && timeout 90 Rscript scripts/run-bagging.R 2>&1 | head -5
```

Expected: `candidates: early 158, late 158` then `base model converged: TRUE`, then the timeout kills it mid-bootstrap. The point is that the helpers resolved and the job began, not that it finished.

- [ ] **Step 8: Commit**

```bash
git add analyses/R_parity analyses/R_hazard && git commit -m "fix: R/ is sourced on every render, so scripts must not live there

run-bagging.R sat in R/ with a 500-replicate bootstrap at its top level. Every
.qmd sources R/ wholesale, so rendering any stage fired a ten-minute job. Moved
to scripts/ and given explicit helper sourcing.

Adds test-r-dir-is-pure.R to both projects: parse each R/*.R file and require
every top-level expression to be an assignment. Function definitions and
constants pass; calls do not. This is the invariant the templates rely on."
```

---

### Task 6: `R_hazard/index.qmd`

**Files:**
- Create: `analyses/R_hazard/index.qmd`

**Interfaces:**
- Consumes: `built_manifest()`, `read_built()`, `assert_cohort()`, `cohort_counts()` from Task 4
- Produces: a rendered overview establishing environment and dataset provenance for every job in the project

- [ ] **Step 1: Write the file**

````markdown
# Overview

Hazard-family analysis of the AVR / LV-function survival study in R, using the
`TemporalHazard` package.

**Study:** *Survival after valve replacement for aortic stenosis: implications
for decision making.* Mihaljevic T, Nowicki ER, Rajeswaran J, Blackstone EH,
Lagazzi L, Thomas J, Lytle BW, Cosgrove DM. J Thorac Cardiovasc Surg.
2008;135(6):1270-9. doi:10.1016/j.jtcvs.2007.12.042

This project **does the analysis**. It reads the built dataset, fits, predicts
and reports. It does not compare anything against SAS: that is `R_parity`'s
job, and it applies only where a stored SAS answer exists. New analysis has no
SAS counterpart at all, which is most of what this migration exists to enable.

The institutional SAS licence expires 2026-09-29.

## Job types

Each SAS job type has a template under `templates/`. Copy it, rename it to
`NN.<prefix>.<sas-basename>.qmd`, and edit the lines marked `# EDIT:`.

| Prefix | SAS location | Jobs here | What it does | Template |
|--------|--------------|-----------|--------------|----------|
| `ac` | `distributions/` | 6 | actuarial life table | `ac.template.qmd` |
| `hz` | `distributions/` | 14 | multiphase parametric fit | `hz.template.qmd` |
| `hp` | `graphs/` | 25 | nomogram and figures | `hp.template.qmd` |
| `bh` | `analyses/` | 22 | bagging | `bh.template.qmd` |
| `hm` | `analyses/` | 13 | multivariable model | `hm.template.qmd` |
| `hs` | `graphs/` | 9 | matched US Life Table survival | not authored |

`hs` needs age, race and sex-matched US Life Table survival, which `%usmatchd`
supplies in SAS and no R equivalent supplies here. It is scoped to a proposed
`hvtiRlifetables` package in section 4.3 of the design spec.

The number prefix encodes pipeline dependency order: `ac` then `hz` then `hp`
then `bh` then `hm`. A job's number says what must already have run.

## Environment

```{r}
#| label: env
#| code-fold: true
for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)

pkg <- function(name) {
  tryCatch(as.character(packageVersion(name)), error = function(e) "absent")
}

knitr::kable(data.frame(
  component = c("R", "TemporalHazard", "survival", "haven",
                "numDeriv", "hvtiRutilities", "hvtiPlotR"),
  version = c(paste(R.version$major, R.version$minor, sep = "."),
              pkg("TemporalHazard"), pkg("survival"), pkg("haven"),
              pkg("numDeriv"), pkg("hvtiRutilities"), pkg("hvtiPlotR")),
  stringsAsFactors = FALSE
))
```

Two of those move numbers rather than merely recording provenance.
`survival` backs `hzr_kaplan()`, so its version can change an `ac` result.
`numDeriv` is a `Suggests` of `TemporalHazard`: without it, interval- or
left-censored multiphase fits produce **no standard errors, silently**. If it
reads `absent` above, install it before running any `hz` or `hm` job.

## Dataset

The `.sas7bdat` files live on a mutable share and are not under version
control. Every job records this manifest; a mid-analysis rewrite changes the
checksum and must invalidate the run rather than be averaged into it.

```{r}
#| label: manifest
knitr::kable(built_manifest())
```

```{r}
#| label: gate
d <- read_built()
assert_cohort(d)
knitr::kable(as.data.frame(cohort_counts(d)))
```

`assert_cohort()` errors if the cohort does not match, so a rendered page is
itself evidence the gate passed.
````

- [ ] **Step 2: Render it**

```bash
cd analyses/R_hazard && quarto render index.qmd
```

Expected: `Output created: _output/index.html`. Open it and confirm the environment table lists a `TemporalHazard` version and the cohort table reads `n = 3049`, `n_events = 1032`, `n_censored = 2017`.

- [ ] **Step 3: Commit**

```bash
git add analyses/R_hazard/index.qmd && git commit -m "feat: add R_hazard index

States what the project is for and what each template covers, then renders the
environment and the dataset manifest. Flags numDeriv explicitly: it is a
Suggests, and without it interval-censored multiphase fits produce no standard
errors without saying so."
```

---

### Tasks 7 to 11: the five templates

**Method.** Each template derives from the corresponding `R_parity/qmd/` document, which already renders correctly against this study. Do not write these from scratch: the parity documents encode findings that cost real debugging, listed per template in section 4 of the design spec. The work is subtraction and parameterisation.

For every template:

1. `cp analyses/R_parity/qmd/<source>.qmd analyses/R_hazard/templates/<prefix>.template.qmd`
2. **Delete** every parity element: `compare_parity()` calls, `parse_lst()` calls, `lst_path()` calls, `parity_headline()`, `parity_badge()`, the tolerance table, all `.lst` prose, and every published-value cross-check.
3. **Keep** every comment that records a finding. These are the reason the template exists.
4. **Leave** the setup chunk's `list.files("../R", ...)` path alone. `templates/` sits one level below the project root exactly as `qmd/` did, so the relative path is already correct. Confirm this rather than assume it: an instantiated job lands at the project *root* (`01.ac.dead_JR.qmd`, per spec section 3.2), where the path must become `"R"`. Add a `# EDIT:` marker on that line saying so.
5. **Mark** each study-specific value with `# EDIT:` and a note saying what to change it to.
6. **Replace** any value that came from a `.lst` with either a literal marked `# EDIT:` or a computed value. This is the one place where subtraction is not enough: `hz`, `hp` and `bh` currently read starting values out of the SAS listing, which `R_hazard` may not do.
7. Render the template unedited. It must succeed against this study.
8. Commit.

| Task | Template | Derives from | Companion script |
|---|---|---|---|
| 7 | `ac.template.qmd` | `R_parity/qmd/01-ac-dead.qmd` | none |
| 8 | `hz.template.qmd` | `R_parity/qmd/02-hz-dead.qmd` | none |
| 9 | `hp.template.qmd` | `R_parity/qmd/03-hp-dead.qmd` | none |
| 10 | `bh.template.qmd` | `R_parity/qmd/04-bh-dead.qmd` | `scripts/bh.template-run.R` from `R_parity/scripts/run-bagging.R` |
| 11 | `hm.template.qmd` | not yet written | `scripts/hm.template-run.R` |

**Task 11 has no parity source.** Stage 5 was never authored. Its template is written fresh from `analyses/hm.dead_s3_JR.sas`, reusing `hz.template.qmd`'s fitting block and adding the covariate blocks. Expect it to take longer than the other four combined.

Each task expands to the standard cycle: write, render to verify it fails or succeeds, fix, render again, commit. The subagent executing a template task must read both the source `.qmd` and the corresponding `.sas` before editing.

**Starting values (step 6 above): decided.** In `R_parity`, `hz` reads its `theta0` from the SAS listing via `parse_lst(lst_path("hz"), "fit")`. `R_hazard` may not do that, and will not substitute literals: hard-coding one study's converged parameters into a template meant for fourteen `hz` jobs defeats the point of a template, and the next person to instantiate it would have no way to know the numbers were wrong for their data.

`hz.template.qmd` and `hm.template.qmd` therefore **compute the start from the data**, using `TemporalHazard`'s own initialisation with `n_starts > 1`.

This carries a known risk and the template must make it visible rather than manage it silently. The stage-2 likelihood **is multimodal**: during parity work a different start reached -3678.83 against the SAS optimum. So both templates must:

- pass `control = list(n_starts = 5, maxit = 2000, conserve = TRUE)`, not `n_starts = 1`;
- print the objective at convergence, and `fit$converged`, in a table near the top of the report rather than buried in a `str()` dump;
- state in prose that a multiphase hazard likelihood can have several optima, so a converged fit is not by itself evidence of the best one, and that comparing the objective across `n_starts` is how that gets checked.

A worse optimum is then visible in the rendered report. That is the whole requirement: not that it cannot happen, but that it cannot happen quietly.

---

## Task 12: Verify against the spec's success criteria

**Files:**
- Modify: `analyses/R_hazard/_quarto.yml` (add rendered templates to `render:` if desired)

**Interfaces:**
- Consumes: everything above
- Produces: a PR

- [ ] **Step 1: Criterion 1 — five templates render unedited**

```bash
cd analyses/R_hazard && for t in ac hz hp bh hm; do quarto render templates/$t.template.qmd || echo "FAILED: $t"; done
```

Expected: five `Output created:` lines, no `FAILED:`.

- [ ] **Step 2: Criterion 2 — `R_parity` still renders**

```bash
cd analyses/R_parity && Rscript -e 'testthat::test_dir("tests/testthat")' && quarto render
```

Expected: `FAIL 0`, then four `Output created:` lines.

- [ ] **Step 3: Criterion 3 — a new job is a copy, a rename, and `# EDIT:` lines only**

This is the criterion that decides whether the templates are worth having, and
the only way to check it is to instantiate one.

```bash
cd analyses/R_hazard && cp templates/ac.template.qmd 01.ac.dead_JR.qmd
```

Edit **only** lines carrying a `# EDIT:` marker. For `ac` against this study
that is the source path (`"../R"` becomes `"R"` at the project root) and the
title. Then:

```bash
cd analyses/R_hazard && quarto render 01.ac.dead_JR.qmd
```

Expected: `Output created: _output/01.ac.dead_JR.html`, and its life table
matches the one in `templates/ac.template.qmd`'s own render.

```bash
cd analyses/R_hazard && diff <(grep -v '# EDIT:' templates/ac.template.qmd) <(grep -v '# EDIT:' 01.ac.dead_JR.qmd)
```

Expected: no output. Any difference outside an `# EDIT:` line means the
template did not carry its own weight, and the offending value needs a marker.

Add the instantiated job to `_quarto.yml`'s `render:` list and commit it: it is
the first real job in the project, not a test artifact.

- [ ] **Step 4: Criterion 4 — no file duplicated between the projects**

Compare content, not names. Two files may legitimately share a basename and
differ (each project's `helper-source.R` names a different project root);
duplication means the same bytes maintained in two places.

```bash
cd analyses && for f in $(cd R_hazard && find . -name '*.R' -o -name '*.qmd' | sed 's|^\./||'); do
  [ -f "R_parity/$f" ] && cmp -s "R_hazard/$f" "R_parity/$f" && echo "DUPLICATE: $f"
done; echo checked
```

Expected: `checked` with no `DUPLICATE:` lines.

- [ ] **Step 5: Confirm the dependency direction holds**

```bash
grep -rn 'R_parity\|parity\|\.lst\|compare_parity\|tolerance' analyses/R_hazard/R/ analyses/R_hazard/templates/ analyses/R_hazard/index.qmd
```

Expected: only the `index.qmd` sentence naming `R_parity` as the other project's job, and the `hs` prose. No code reference.

- [ ] **Step 6: Open the PR**

```bash
git push -u origin feat/r-hazard-templates
gh pr create --title "R_hazard: job templates and the R_parity split" --body "$(cat <<'EOF'
Implements the approved design at `specs/2026-08-11-r-hazard-job-templates-design.md`.

Splits `analyses/R_analysis/` into two sibling projects. `R_hazard` does the analysis in R and owns the study's data contract; `R_parity` compares R against stored SAS output and sources that contract from `R_hazard`. The arrow points that way because parity is re-run whenever a defect surfaces or a release needs re-qualifying, so the analysis has to be the layer that stands alone.

Five templates authored: `ac`, `hz`, `hp`, `bh`, `hm`. `hs` is specified but not authored: it needs age, race and sex-matched US Life Table survival, scoped to a proposed `hvtiRlifetables` package.

Also fixes a live defect. `R/run-bagging.R` had a 500-replicate bootstrap at its top level, and every `.qmd` sources `R/` wholesale, so rendering any stage fired a ten-minute job. Moved to `scripts/`, with a test in both projects that parses every `R/*.R` file and requires top-level expressions to be assignments.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Deferred, with triggers

Recorded so they are not rediscovered. Neither is built by this plan.

| Deferred | Trigger |
|---|---|
| `hs` template | `hvtiRlifetables` exists |
| `hvtiRlifetables` | its own design cycle, gated on a spike measuring `survexp.usr` against the 31 stored `uslife*.sas7bdat` fixtures |
| Templates into `hvtiRutilities/inst/rmarkdown/templates/` (not a separate `hvtiRtemplates`) | the first time a template is copied to another study and edited there |
| Sibling `R_<family>` directories for the other fourteen prefixes | the first one is needed; `read_built.R` then moves up a level |
| `paths.R` and `parity.R` into `hvtiRutilities` | a second study needs them |
