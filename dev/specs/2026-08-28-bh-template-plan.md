# `04.06-bh` Template Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `inst/templates/analyses/04.06-bh.qmd`, the bootstrap
variable-selection *report* template, scaffoldable by `new_job("bh", ...)`.

**Architecture:** The template is a Quarto report that reads pooled bootstrap
output written by a companion runner it does not ship. It pools chunks with
`hvtiRbootstrap`, groups candidates with `hvtiRutilities`, and refuses to render
green while `EDIT:` markers remain. Design:
[`dev/specs/2026-08-28-bh-template-design.md`](2026-08-28-bh-template-design.md).

**Tech Stack:** Quarto (`.qmd`), R, `testthat` edition 3, `lintr`, `roxygen2`.

## Source material

The exemplars are **not in this repo**. Re-fetch them before Task 1 — the
scratchpad copy from the design session is gone:

```bash
LVF=/Volumes/qhsstudies/cardiac/valves/aortic/replacement/pericardial/lv_function/survival/analyses/R_hazard
PR=/Volumes/qhsstudies/vascular/thoracic-aorta/dissection/ascending/acute/preserve_root/analyses
cp "$LVF/example-jobs/bh.example.qmd" "$PR/bh.dead_summary.sas" "$PR/bh.dead.sas" .
```

`/studies` is the SMB mount `/Volumes/qhsstudies`. **Do not `find` from its
root** — 2.24M files over SMB. Use the paths above directly.

**On "complete code" in this plan:** the load-bearing transformations are given
as real code below. Where a step says *port chunk `<label>` from the exemplar*,
the exemplar is the source of truth and copying it is the intended action — the
581-line report is not reproduced here, and that is deliberate, not a
placeholder. Every such step names the exact chunk label and the exact
substitutions to apply.

## Global Constraints

- **Filename is `04.06-bh.qmd`** in `inst/templates/analyses/`. `MM` is the
  prefix's positional index in its taxonomy folder; `bh` is 6th in `analyses`.
  Never `04.02`.
- **Line length 135**, per `.lintr`. Every other default linter is enforced.
- **Roxygen is Rd markup, not markdown** — no backticks or `**bold**` in `.Rd`.
  (Only relevant if a task touches `R/`; none should.)
- **Templates carry no study identifiers.** `test-new-job.R` asserts no match
  for `/studies/`, a study name, or a built-dataset filename. Scrub
  `lv_function`, `preserve_root`, `bagging.rds`, `built.sas7bdat`, and every
  absolute path out of every ported chunk.
- **Exactly one `^ENDPOINT\s+<- ` line and one `^TYPE\s+<- ` line.**
  `new_job()` hard-stops if either is missing, duplicated, or moved.
- **Every study-specific line is marked `EDIT:`**, and comments say *why* a
  choice matters, not what to type.
- **Template carries its own `format:` block** — never inherits `_quarto.yml`.
- **Version floors:** `hvtiRbootstrap >= 0.1.1`, `hvtiRutilities >= 1.1.5`,
  `TemporalHazard` 1.2.6.
- **Renames from the exemplar's study-local helpers**, applied everywhere:
  | exemplar | template |
  |---|---|
  | `pool_bagging()` | `hvtiRbootstrap::boot_pool_chunks()` |
  | `bagging_chunk_files()` | `hvtiRbootstrap::boot_chunk_files()` |
  | `bagging_shortfall()` | `hvtiRbootstrap::boot_shortfall()` |
- **Definition of done for the package:** `devtools::test()` passes,
  `devtools::check()` is 0/0/0, `devtools::document()` run and `man/` +
  `NAMESPACE` committed with the source change.
- **Never push to `main`.** Branch, PR, let the maintainer merge.

---

### Task 1: Skeleton, front matter, edit guard, lint entry

The smallest thing `new_job()` can scaffold and `lintr` can pass. No analysis
yet — this task exists so the plumbing is proven before any content lands on it.

**Files:**
- Create: `inst/templates/analyses/04.06-bh.qmd`
- Modify: `.lintr` (add a **file** key)
- Test: `tests/testthat/test-new-job.R`, `tests/testthat/test-templates.R`
  (both already generic over `template_list()`; no new test file)

**Interfaces:**
- Produces: a template whose `.template_fields()` parse yields
  `ordinal = "04.06"`, `prefix = "bh"`, `folder = "analyses"`; and the two
  marker lines `ENDPOINT <- "ENDPOINT"` / `TYPE <- "TYPE"` that `new_job()`
  substitutes.

- [ ] **Step 1: Run the suite to confirm a clean baseline**

```bash
Rscript -e 'devtools::test()'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 84 ]`

- [ ] **Step 2: Create the template with front matter and markers**

Create `inst/templates/analyses/04.06-bh.qmd`. Copy the `format:` block and the
`render-stamp` chunk from the exemplar's lines 1–36 verbatim, then add the set
markers. The four lines `new_job()` and `set_path()` depend on:

```r
# EDIT: new_job() rewrites these two lines. They name the (endpoint, analysis
# type) set this job belongs to, and every artifact path below is derived from
# them -- so a hand edit here silently redirects every read and write.
ENDPOINT <- "ENDPOINT"
TYPE     <- "TYPE"

# Artifacts sit under <kind>/<endpoint>-<type>/; authored files sit flat.
# Derived from the two lines above rather than declared, because a declaration
# drifts from the filename and nothing catches it.
set_path <- function(kind, file) {
  d <- file.path(.root, kind, paste0(ENDPOINT, "-", TYPE))
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  file.path(d, file)
}
```

- [ ] **Step 3: Port the edit guard**

Copy the `edit-guard` chunk from `inst/templates/analyses/04.01-hm.qmd`
verbatim, changing only the file-specific danger sentence in its comment. For
`bh` that sentence is:

```r
# Without it an unedited job renders green over a meaningless analysis. In THIS
# file the danger is that EXPECT_CHUNKS and EXPECT_BOOT still hold the template's
# numbers, so the completeness check compares the run against a denominator
# nobody chose -- and passes, reporting frequencies over the wrong base.
```

⚠️ Keep `.tok <- paste0("ED", "IT", ":")` built rather than literal. Quarto
knits through an intermediate and `current_input()` returns *that* file, so a
literal token matches its own source line and the guard fires on every render.

- [ ] **Step 4: Add the `.lintr` file key**

In `.lintr`, inside `exclusions: list(...)`, after the `04.01-hm.qmd` entry:

```r
    "inst/templates/analyses/04.06-bh.qmd" = list(
      object_name_linter = Inf,
      commented_code_linter = Inf,
      object_usage_linter = Inf
    )
```

⚠️ The key is the **file**. A directory key such as `inst/templates` excludes
every linter on that path wholesale and silently.

- [ ] **Step 5: Verify the template is discovered and parses**

```bash
Rscript -e 'devtools::load_all(); print(template_list()[template_list()$prefix == "bh", ])'
```

Expected: one row, `name` = `04.06-bh`, `ordinal` = `04.06`, `folder` = `analyses`.

- [ ] **Step 6: Run tests and lint**

```bash
Rscript -e 'devtools::test()'
```

Expected: PASS, count risen from 84 (the generic template tests now cover a 5th file).

```bash
Rscript -e 'lintr::lint_package()'
```

Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add inst/templates/analyses/04.06-bh.qmd .lintr
git commit -m "feat(bh): scaffold the 04.06-bh template with its edit guard (#8)"
```

---

### Task 2: Setup, pooling, and the completeness callout

**Files:**
- Modify: `inst/templates/analyses/04.06-bh.qmd`

**Interfaces:**
- Consumes: `.root`, `set_path()`, `ENDPOINT`, `TYPE` from Task 1.
- Produces: `bag` — the pooled bootstrap object every later task reads. Fields
  relied on downstream: `bag$n_boot`, `bag$n_chunks`, `bag$seeds`, `bag$seed`,
  `bag$slentry`, `bag$slstay`, `bag$requested`, `bag$usable`, `bag$n_rows`,
  `bag$elapsed_mins`, `bag$th_version`, `bag$manifest`, `bag$dropped`,
  `bag$boot`.

- [ ] **Step 1: Port the `setup` chunk**

From the exemplar's `setup` chunk (lines 82–136). Apply the three renames from
Global Constraints. Replace the study's `for (f in list.files(.root/R))
source(f)` loop with explicit library calls:

```r
suppressPackageStartupMessages({
  library(TemporalHazard)
  library(hvtiRbootstrap)
  library(hvtiRutilities)
  library(ggplot2)
})
```

- [ ] **Step 2: Add the `EXPECT_*` block with its full comment**

```r
# EDIT: what this run was LAUNCHED as, not what happens to be on disk.
#
# Nothing in a chunk knows how many siblings it was launched alongside, so these
# two numbers are the only thing that can tell a partial pool from a complete
# one. Without them a render at hour eight of a twelve-hour run produces a
# report that is wrong in no visible way: every health check passes, every
# frequency is honestly computed, and only the denominator is not the intended
# one.
#
# For a single unchunked run, set EXPECT_CHUNKS to 1.
EXPECT_CHUNKS <- 25L    # EDIT: how many chunks you launched
EXPECT_BOOT   <- 500L   # EDIT: %hazboot(resampl=) -- total replicates wanted
```

- [ ] **Step 3: Port the load-or-stop logic**

From the exemplar's lines 113–136. The `stop()` message must name a companion
runner **generically** — the exemplar's `scripts/bh.example-run.R` is a study
path and violates the no-study-identifiers rule:

```r
} else {
  stop("No bootstrap output found. This screen is a long job -- days, not ",
       "minutes -- and is run from a companion script rather than inside this ",
       "render, because the run writes nothing until its final replicate.\n",
       "Run your chunks first, then render this report.", call. = FALSE)
}
```

- [ ] **Step 4: Port the `completeness` chunk**

From the exemplar's lines 138–152, with `bagging_shortfall()` → `boot_shortfall()`.
Keep it a callout, not a table cell: a provisional report that cannot say so is
the failure being prevented, including for someone who receives the `.html`
without knowing when it was made.

- [ ] **Step 5: Confirm the file still parses and lints**

```bash
Rscript -e 'devtools::test()' && Rscript -e 'lintr::lint_package()'
```

Expected: tests PASS, lint silent.

- [ ] **Step 6: Commit**

```bash
git add inst/templates/analyses/04.06-bh.qmd
git commit -m "feat(bh): pool chunks and flag an incomplete screen (#8)"
```

---

### Task 3: Provenance, seeds, and unscreened candidates

**Files:**
- Modify: `inst/templates/analyses/04.06-bh.qmd`

**Interfaces:**
- Consumes: `bag` from Task 2.

- [ ] **Step 1: Port `provenance`, `seeds`, `dropped-summary`, `coercion`**

Exemplar chunks at lines 168, 202, 228, 246. Port verbatim except the renames.

- [ ] **Step 2: Keep the two comments that explain non-obvious columns**

Both are load-bearing and must survive the copy:

```r
# CPU cost, NOT wall clock. boot_pool_chunks() SUMS elapsed across chunks, so on
# a chunked run this is total compute; chunks run in parallel finish in a
# fraction of it. Reported in hours because the minutes figure reads as a
# wall-clock number and is off by the chunk count.
```

```r
# Summarised, not listed: at 25 chunks the joined seed string is a single
# 270-character cell that wrecks the table. Every seed is in the table below.
```

- [ ] **Step 3: Keep counts-before-detail ordering**

The dropped-candidate summary table comes **before** the detail table. A reader
who must scroll dozens of rows to discover a whole *class* of variable was never
screened will not discover it.

- [ ] **Step 4: Run tests and lint**

```bash
Rscript -e 'devtools::test()' && Rscript -e 'lintr::lint_package()'
```

- [ ] **Step 5: Commit**

```bash
git add inst/templates/analyses/04.06-bh.qmd
git commit -m "feat(bh): report provenance, seeds and unscreened candidates (#8)"
```

---

### Task 4: The health check — a screen that selected nothing is a failure

This task exists on its own because it is the trap that produces a
publishable-looking artifact. It deserves its own review gate.

**Files:**
- Modify: `inst/templates/analyses/04.06-bh.qmd`

**Interfaces:**
- Consumes: `bag` from Task 2.

- [ ] **Step 1: Port the `health` chunk**

Exemplar line 342. Then add the prose above it, which the template needs and the
exemplar states less directly:

```markdown
⚠️ **A screen that selected nothing is a failure, not a finding.** It is the
signature of a formula that did not survive the per-replicate rewrite: the refit
errors, the error is caught, the step reports nothing accepted, and the screen
halts having selected nothing -- with no warning and `n_failed = 0`. The summary
then reads as a table of perfectly reliable variables.
```

- [ ] **Step 2: Add the formula guard as an `EDIT:` note at the call site**

The runner is not templated, so this is the only place the template can warn:

```r
# EDIT: the candidate pool, written LITERALLY in your runner's formula.
#
# Not in a variable, not via as.formula() or reformulate(). hzr_bootstrap() and
# hzr_stepwise() rewrite the stored formula per replicate, and a symbol standing
# where the formula should be does not survive that rewrite. See the health
# check above for what the failure looks like -- it does not error.
```

- [ ] **Step 3: Add the free-parameter check**

```r
# A free parameter must VARY across resamples. A bootstrap built on the vector
# interface returns the original fit every replicate, with n_success = 500,
# n_failed = 0, and no warning. sd() of a free base parameter is the tell.
```

- [ ] **Step 4: Run tests and lint**

```bash
Rscript -e 'devtools::test()' && Rscript -e 'lintr::lint_package()'
```

- [ ] **Step 5: Commit**

```bash
git add inst/templates/analyses/04.06-bh.qmd
git commit -m "feat(bh): fail loudly when the screen selected nothing (#8)"
```

---

### Task 5: Selection frequencies and Monte-Carlo error

**Files:**
- Modify: `inst/templates/analyses/04.06-bh.qmd`

**Interfaces:**
- Consumes: `bag` from Task 2.
- Produces: `freq` — the per-phase frequency table Task 6 groups.

- [ ] **Step 1: Port `frequencies` and `retained`**

Exemplar lines 370 and 409.

- [ ] **Step 2: Add the interpretation prose**

Place it above the tables, from the exemplar's lines 57–75:

```markdown
## What a selection frequency is, and what it is not

A selection frequency is an estimate, not a count of something fixed, and it
carries Monte-Carlo error of roughly `sqrt(p(1-p)/n_boot)`. At `p = 0.5` over
500 replicates that is about **2.2 percentage points**, so a variable sitting
within a few points of the retention threshold can fall on either side of it on
resampling noise alone.

- **Agreement on the retention decision matters more than agreement on the
  frequency.** Which side of the threshold a variable falls on is the decision
  this job exists to support.
- **A near-threshold variable is not a weak risk factor.** It is a variable
  whose selection is unstable, which is a different claim.
```

- [ ] **Step 3: Add the criteria as EDIT: knobs**

The two exemplars disagree (500/0.07/0.05 vs 1000/0.12/0.1), which is what
proves these are knobs:

```r
# EDIT: from YOUR .sas %hazboot call. The two studies this template was
# extracted from disagree -- 500/0.07/0.05 and 1000/0.12/0.1 -- so there is no
# default here to fall back on. Read them off the call and paste it above.
```

- [ ] **Step 4: Run tests and lint**

```bash
Rscript -e 'devtools::test()' && Rscript -e 'lintr::lint_package()'
```

- [ ] **Step 5: Commit**

```bash
git add inst/templates/analyses/04.06-bh.qmd
git commit -m "feat(bh): report selection frequencies with Monte-Carlo error (#8)"
```

---

### Task 6: Concept grouping at read time, and the no-pruning warning

**Files:**
- Modify: `inst/templates/analyses/04.06-bh.qmd`

**Interfaces:**
- Consumes: `bag`, `freq`.
- Uses: `hvtiRutilities::concept_map()`, `concept_of()`, `selection_crowding()`,
  `pool_collinear_pairs()`, and the affix vocabulary `POOL_AFFIXES`,
  `POOL_MIN_STEM`, `POOL_PLAIN_SUFFIX`.

- [ ] **Step 1: Port `concept-map`, `concept-frequencies`, `concept-counts`**

Exemplar lines 290, 438, 469.

- [ ] **Step 2: Add the no-pruning warning above them — verbatim**

This is the single most important prose in the file. `prune_to_one_form()` is
exported and one call away, and reaching for it looks like tidying:

```markdown
⚠️ **Do not prune competing transformations from the pool before screening.**
Screen every form; group only when reading, which is what this section does.

Measured, on the study this template came from: of the 57 forms pruning removed,
**16 correlated at |r| < 0.9** with the form kept and five below 0.5. `in_zexp`
**is** `1/zexp` -- r = 0.9997 against the reciprocal -- yet correlates with
`zexp` at only **-0.195**, because `zexp` spans 0.038 to 151.9. Over a 4000-fold
range a value and its reciprocal are different information. That study's
published model uses `zexp` and `in_zexp` in the same phase, **both
significant**, a two-parameter flexible form pruning forbids.

The naming convention tells you two variables are RELATED. Only the data tells
you whether they are REDUNDANT.
```

- [ ] **Step 3: Add the affix-vocabulary EDIT: marker**

```r
# EDIT: the affix vocabulary, if your study's variable names do not follow
# vars.sas conventions. POOL_AFFIXES carries ln_, in_, in2, _pr and a trailing
# 2, the order in which they strip, and the deliberate refusal to reduce agee
# to age. Those are facts about this institution's names, not about statistics,
# which is why they are data you can replace rather than logic you cannot.
concept <- concept_map(names(freq), affixes = POOL_AFFIXES,
                       min_stem = POOL_MIN_STEM,
                       plain_suffix = POOL_PLAIN_SUFFIX)
```

- [ ] **Step 4: Run tests and lint**

```bash
Rscript -e 'devtools::test()' && Rscript -e 'lintr::lint_package()'
```

- [ ] **Step 5: Commit**

```bash
git add inst/templates/analyses/04.06-bh.qmd
git commit -m "feat(bh): group concepts at read time, never by pruning (#8)"
```

---

### Task 7: Correlation clusters — what the SAS exemplar contributed

The R exemplar has **no equivalent** of this section. It is the reason the second
exemplar was read, and it is new code rather than a port.

**Files:**
- Modify: `inst/templates/analyses/04.06-bh.qmd`
- Test: `tests/testthat/test-bh-helpers.R` (create)

**Interfaces:**
- Consumes: `bag`, `freq`.
- Uses: `hvtiRbootstrap::boot_clusters()`.

- [ ] **Step 1: Write the failing test**

The template is this repo's first caller of `boot_clusters()`, so the render
must not be the only thing standing behind it. Create
`tests/testthat/test-bh-helpers.R`:

```r
test_that("boot_clusters() groups a synthetic pool by correlation", {
  skip_if_not_installed("hvtiRbootstrap")
  set.seed(1)
  n <- 200L
  x <- rnorm(n)
  d <- data.frame(a = x, a2 = x + rnorm(n, sd = 0.01), b = rnorm(n))
  cl <- hvtiRbootstrap::boot_clusters(d, cluster = "a", clname = "A")
  expect_true(is.data.frame(cl))
  expect_true(nrow(cl) > 0L)
})

test_that("boot_shortfall() reports a partial pool and stays silent on a full one", {
  skip_if_not_installed("hvtiRbootstrap")
  full    <- list(n_boot = 500L, n_chunks = 25L)
  partial <- list(n_boot = 200L, n_chunks = 10L)
  expect_null(hvtiRbootstrap::boot_shortfall(full, 25L, 500L))
  msg <- hvtiRbootstrap::boot_shortfall(partial, 25L, 500L)
  expect_true(is.character(msg) && nzchar(msg))
})
```

Both are exercised here because the template is this repo's first caller of
either, and a render is not a test: the render stops before it reaches them
whenever no bootstrap output exists, which is every CI run.

- [ ] **Step 2: Run it to confirm it fails or skips honestly**

```bash
Rscript -e 'devtools::test(filter = "bh-helpers")'
```

Expected: PASS if `hvtiRbootstrap` is installed; SKIP otherwise. A SKIP here is
acceptable and is why `skip_if_not_installed()` is present — `hvtiRbootstrap` is
a study dependency, not a `DESCRIPTION` one.

⚠️ If the call signature differs from the guess above, **read
`?hvtiRbootstrap::boot_clusters` and correct the test and the template
together.** Do not adjust the test alone to make it pass.

- [ ] **Step 3: Add the clusters section to the template**

```markdown
## Correlation clusters

Concept grouping above is by NAME. This section groups by DATA: variables that
move together, whatever they are called. The SAS job this replaces ran
`%cluster` once per named cluster per phase, and the two views answer different
questions -- a name tells you two variables are related, a correlation tells you
they are redundant.
```

```r
# EDIT: your clusters, one per concept you want reported, and the phase each
# runs against. The SAS job named eight -- Age, Size, BMI, race, GFR, iv_opyrs,
# Renal, blrbn_pr -- and ran each against both the early and constant phases.
# There is no sensible default: which concepts are worth clustering is a
# statement about your candidate pool.
```

- [ ] **Step 4: Run tests and lint**

```bash
Rscript -e 'devtools::test()' && Rscript -e 'lintr::lint_package()'
```

- [ ] **Step 5: Commit**

```bash
git add inst/templates/analyses/04.06-bh.qmd tests/testthat/test-bh-helpers.R
git commit -m "feat(bh): add correlation clusters from the SAS exemplar (#8)"
```

---

### Task 8: Figure, save, and the parallel-not-a-pipeline statement

**Files:**
- Modify: `inst/templates/analyses/04.06-bh.qmd`

- [ ] **Step 1: Port `fig-frequencies` and `save`**

Exemplar lines 523 and 575. The `save` chunk must write through `set_path()`, so
artifacts land in `<kind>/<endpoint>-<type>/`.

- [ ] **Step 2: Add the relationship statement**

Place it near the top, after the SAS provenance block:

```markdown
This job **does not fit the final model**. It screens. The companion `hm` job
fits the multivariable model.

⚠️ `bh` and `hm` are **parallel analyses, not a pipeline.** `%hazboot` and
`%model` were parallel in SAS and these jobs reproduce that. Do not describe
this job's retained set as what `hm` fits, and do not write a handoff file for
it -- an earlier study report did both, and nothing read the file. A reader who
believes the claim will assume the `hm` model was screened for reliability
first. It was not.
```

- [ ] **Step 3: Verify no study identifiers survived**

```bash
grep -nEi 'lv_function|preserve_root|/studies/|sas7bdat|bagging\.rds|example-run' inst/templates/analyses/04.06-bh.qmd
```

Expected: **no output.** Any hit is a test failure waiting to happen.

- [ ] **Step 4: Run tests and lint**

```bash
Rscript -e 'devtools::test()' && Rscript -e 'lintr::lint_package()'
```

- [ ] **Step 5: Commit**

```bash
git add inst/templates/analyses/04.06-bh.qmd
git commit -m "feat(bh): add the frequency figure, artifact save and hm relationship (#8)"
```

---

### Task 9: Render verification, docs, and the version bump

**Files:**
- Modify: `inst/templates/README.md`, `NEWS.md`, `DESCRIPTION`

- [ ] **Step 1: Scaffold a job and render it UNEDITED**

```bash
Rscript -e 'devtools::load_all(); new_job("bh", "dead_pa", "hz", dir = tempdir()); cat(list.files(tempdir(), recursive = TRUE, pattern = "bh"), sep = "\n")'
```

Expected: `analyses/dead_pa-hz-04.06-bh.qmd`

Render it. Expected: **halts at `edit-guard`**, listing the unresolved markers.
A green render here is a task failure.

- [ ] **Step 2: Render with markers stripped**

Strip the `EDIT:` lines and render again. Expected: it passes `edit-guard` and
proceeds to the `setup` stop about missing bootstrap output — which is correct,
since no runner has run.

- [ ] **Step 3: Update `inst/templates/README.md`**

Add to the "What is here" table:

```markdown
| `analyses/04.06-bh.qmd` | bootstrap variable selection | `analyses/` |
```

Then rewrite the "What is not here yet" section: `bh` is no longer listed as
untemplated. State what remains untemplated — the **runner** — and why:

```markdown
`bh`'s companion runner is not templated. The screen is days of compute and
`hzr_bootstrap()` writes nothing until its final replicate, so the run is
chunked from a separate script and this template reports over what that script
wrote. Templating the runner needs multi-file templates in `new_job()`, which
is a package change. `hm` has the same gap.
```

- [ ] **Step 4: Bump `DESCRIPTION` and `NEWS.md`**

`DESCRIPTION`: `Version: 1.0.10`, and refresh `Date:`. **Patch digit only** —
minor and major are the maintainer's decision.

`NEWS.md`, a new top section using a plain heading (**no `Version:` line** —
that is ggRandomForests' convention, not this repo's):

```markdown
# hvtiRtemplates 1.0.10

## New features

- **`analyses/04.06-bh.qmd`** — the bootstrap variable-selection screen,
  replacing a SAS `%hazboot` / `%sumboot` / `%cluster` chain (#8). Scaffold with
  `new_job("bh", <endpoint>, <type>)`. Design:
  `dev/specs/2026-08-28-bh-template-design.md`. **Requires hvtiRbootstrap >=
  0.1.1 and hvtiRutilities >= 1.1.5.**

  The template is the **report**, not the runner...
```

- [ ] **Step 5: Document, check, and commit**

```bash
Rscript -e 'devtools::document()'
Rscript -e 'devtools::check()'
```

Expected: **0 errors, 0 warnings, 0 notes.**

```bash
git add inst/templates/README.md NEWS.md DESCRIPTION man NAMESPACE
git commit -m "docs(bh): document the template and bump to 1.0.10 (#8)"
```

- [ ] **Step 6: Open the PR**

```bash
git push -u origin feat/8-bh-template
gh pr create --title "Add the 04.06-bh bootstrap screen template (#8)"
```

⚠️ The local branch `feat/8-bh-template` currently exists as an **empty pointer
at `main`**. Delete it before branching, or branch under a fresh name:

```bash
git branch -D feat/8-bh-template
```

## Out of scope

- **The runner and the progress watcher.** Design doc, "Scope".
- **Multi-file templates in `new_job()`.** Its own spec.
- **`hs`.** Its prefix collides — the taxonomy's "Hazard setup" is not #8's US
  life-table job. Resolve before templating.
