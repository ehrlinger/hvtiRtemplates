# New-study guide Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `vignettes/new-study.qmd`, a guide that takes a study from an empty directory and a delivered dataset through a first `ac`/`hz`/`hp` chain.

**Architecture:** One new Quarto vignette whose reader-facing chunks execute for real against a hidden 40-row synthetic dataset in a temporary directory, so the vignette build is the CI gate for every call it shows. Nothing is rendered: the provenance sidecar is a labelled static excerpt, and the chain is an inline SVG figure. A new source-reading test file pins the calls; the existing vignette gets one cross-link.

**Tech Stack:** R, Quarto vignettes (`quarto::html` engine), testthat 3e, pkgdown, hvtiRutilities (>= 1.4.0).

**Spec:** `dev/specs/2026-09-23-new-study-guide-design.md`

## Global Constraints

- Branch `docs/new-study-guide`, worktree `/private/tmp/hvtiRtemplates-new-study`. It depends on #142 and must sit on its head (`43014fe` or later). Never push to `main`.
- `add_job()` and `open_job()` take `subject =`, never `endpoint =`.
- Lines at most 135 characters (`.lintr`). No em dashes in prose (house rule).
- Roxygen is Rd markup, not markdown (not touched by this plan).
- No PHI: the vignette's data are generated in a chunk; no data file ships.
- No `setwd()` anywhere in the vignette; the reader's study root is the RStudio project.
- No version bump. `NEWS.md` gets an entry under the existing `# hvtiRtemplates (unreleased)` heading.
- Definition of done: `devtools::test()` passes; `devtools::check()` is 0/0/0 with the vignette rebuild time read from the log; the pkgdown article builds; CI per-platform summaries read, expected `SKIP 2` (macOS, Ubuntu) and `SKIP 3` (Windows), unchanged.

## File Structure

| file | change | responsibility |
|---|---|---|
| `dev/specs/2026-09-23-new-study-guide-design.md` | modify | correct section 5's CI claim |
| `vignettes/new-study.qmd` | create | the guide |
| `tests/testthat/test-vignette-new-study.R` | create | pins the guide's calls and links |
| `tests/testthat/test-vignette-migration.R` | modify | reverse link; add new guide to tutorials test |
| `vignettes/study-setup.qmd` | modify | one cross-link paragraph |
| `_pkgdown.yml` | modify | list the article |
| `NEWS.md` | modify | unreleased entry |

---

### Task 1: Rebase onto #142 and correct the spec

**Files:**
- Modify: `dev/specs/2026-09-23-new-study-guide-design.md` (section 5)

**Interfaces:**
- Consumes: nothing.
- Produces: a branch whose base carries `subject`, the provenance hooks and the render lock.

- [ ] **Step 1: Rebase the branch onto #142's head**

```bash
cd /private/tmp/hvtiRtemplates-new-study
git fetch origin
git rebase origin/codex/endpoint-neutral-data-contract
git log --oneline -3
```

Expected: the spec commit (`docs(specs): design the new-study guide`) sits on top of `43014fe` or later.

- [ ] **Step 2: Replace the wrong CI claim in spec section 5**

Replace the block that begins `⚠️ **These source-reading tests do not run in CI.**` and ends `raised as a follow-up rather than folded in here.` with:

```markdown
**These tests run in CI.** Like `skip_without_vignette()` in
`test-vignette-migration.R`, the new helper falls back from the source tree to
`system.file("doc", "new-study.qmd")`, which `R CMD check` installs. Only tests
that read `test_path()` alone skip on CI (the SAS-guide and tutorials tests,
the two skips on every leg). Adding `new-study.qmd` to the tutorials test
therefore adds no new skip, and the expected summaries stay SKIP 2 on macOS and
Ubuntu and SKIP 3 on Windows.

The vignette build is the second gate: `R CMD check` re-builds vignette outputs
on every leg, and every reader-facing chunk executes.
```

- [ ] **Step 3: Commit**

```bash
git add dev/specs/2026-09-23-new-study-guide-design.md
git commit -m "docs(specs): the new-study vignette tests run in CI"
```

---

### Task 2: Failing test for the guide

**Files:**
- Create: `tests/testthat/test-vignette-new-study.R`

**Interfaces:**
- Consumes: nothing.
- Produces: `new_study_vignette_path()`, `new_study_article()`, `add_job_calls()` (file-local helpers); the contract Tasks 3 to 5 must satisfy. The file holds 15 expectations.

- [ ] **Step 1: Write the test file**

```r
new_study_vignette_path <- function() {
  source <- testthat::test_path("..", "..", "vignettes", "new-study.qmd")
  if (file.exists(source)) return(source)
  system.file("doc", "new-study.qmd", package = "hvtiRtemplates")
}

new_study_article <- function() {
  path <- new_study_vignette_path()
  testthat::skip_if_not(file.exists(path), "vignette source not available")
  paste(readLines(path, warn = FALSE), collapse = "\n")
}

# Calls only: a quoted prefix must follow the parenthesis, so prose such as
# "`add_job()` in a study" is not mistaken for a call that omits `subject =`.
add_job_calls <- function(article) {
  regmatches(article, gregexpr("add_job\\(\"[^)]*\\)", article))[[1L]]
}

test_that("the new-study guide starts from an empty study and a delivered dataset", {
  article <- new_study_article()

  expect_false(grepl("adopt = TRUE", article, fixed = TRUE))
  expect_true(grepl("study_setup(", article, fixed = TRUE))
  expect_true(grepl("register_data(", article, fixed = TRUE))
  expect_true(grepl('role = "study"', article, fixed = TRUE))
  expect_false(grepl("setwd[[:space:]]*[(]", article))
})

test_that("every add_job() call in the guide names a subject, never an endpoint", {
  calls <- add_job_calls(new_study_article())

  expect_gte(length(calls), 4L)
  expect_true(all(grepl("subject = ", calls, fixed = TRUE)))
  expect_false(any(grepl("endpoint", calls, fixed = TRUE)))
  expect_true(any(grepl('add_job("dc", subject = "cohort", type = "eda"', calls, fixed = TRUE) &
                    grepl('qualifier = "general"', calls, fixed = TRUE)))
})

test_that("the worked chain scaffolds ac, hz and hp into one death set", {
  calls <- add_job_calls(new_study_article())

  for (prefix in c("ac", "hz", "hp")) {
    expect_true(
      any(startsWith(calls, sprintf('add_job("%s", subject = "death", type = "hz"', prefix))),
      info = prefix
    )
  }
})

test_that("the guide explains provenance and links its sibling", {
  article <- new_study_article()

  expect_true(grepl(".provenance.json", article, fixed = TRUE))
  expect_true(grepl("study-setup.html", article, fixed = TRUE))
  expect_true(grepl("template_list()", article, fixed = TRUE))
})
```

- [ ] **Step 2: Run it and confirm the red state**

Run: `Rscript -e 'devtools::test(filter = "vignette-new-study")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 4 | PASS 0 ]`, each skip reading "vignette source not available". A skip is this file's red state: the source it reads does not exist yet.

- [ ] **Step 3: Commit**

```bash
git add tests/testthat/test-vignette-new-study.R
git commit -m "test: pin the new-study guide's calls and links"
```

---

### Task 3: The guide, setup through first EDA job and provenance (sections 1 to 5)

**Files:**
- Create: `vignettes/new-study.qmd`

**Interfaces:**
- Consumes: Task 2's tests (only the first test goes fully green here).
- Produces: `new_root` (the executable example's study root) and `delivered` (the synthetic data frame), both created in the `synthetic-setup` chunk and used by Task 4's chunks.

- [ ] **Step 1: Create the vignette with front matter and sections 1 to 5**

````markdown
---
title: "Start a new study from a delivered dataset"
author: "John Ehrlinger"
vignette: >
  %\VignetteIndexEntry{Start a new study}
  %\VignetteEngine{quarto::html}
  %\VignetteEncoding{UTF-8}
format:
  html:
    toc: true
    embed-resources: true
---

This tutorial starts with an empty directory and an analysis dataset that has
just been delivered. It takes the study through setup, data registration and a
first descriptive job, then through one analysis chain, so you can see how the
templates hand work to one another.

If the study directory already exists and holds jobs and data, start with
[Adopt an existing study](study-setup.html) instead. That guide keeps the
existing layout and files.

The executable example uses a 40-row synthetic dataset generated below. Its
files stay in a temporary directory and disappear after the article renders.

## Before you start

A delivered dataset here means one analysis-ready file, CSV or SAS transport,
already built from the source extract. Building that file is a separate step;
this guide begins once it exists. Keep it on the study share: patient data
never enter a git repository.

Create the study directory, open it in RStudio as a Project
(**File > New Project > Existing Directory**) and work from its `.Rproj` from
then on. Select the R version and load the hvtiR packages as described in
[Adopt an existing study](study-setup.html#open-the-study-as-an-rstudio-project).
Those steps are the same for a new study, so they are kept in one place.

```r
library(hvtiRutilities)
library(hvtiRtemplates)
```

```{r}
#| label: synthetic-setup
#| include: false
knitr::opts_chunk$set(collapse = TRUE, comment = "#>")
library(hvtiRutilities)
library(hvtiRtemplates)
workspace <- withr::local_tempdir(.local_envir = environment())
new_root <- file.path(workspace, "new-study")
i <- seq_len(40L)
delivered <- data.frame(
  ccfid = i,
  dead = i %% 2L,
  iv_dead = i / 10,
  age = 40 + i,
  female = i %% 2L
)
```

## Create the study

`study_setup()` turns an empty directory into a study. It writes `_study.yml`,
which names the study and its Study Tracker ID, an RStudio project file,
environment defaults, and the numbered folders every job is placed in:

| folder | holds |
|---|---|
| `00_datasets` | the registered data |
| `10_descriptive` | descriptive tables and checks |
| `20_distributions` | life tables and hazard models |
| `30_analyses` | multivariable and machine-learning models |
| `40_graphs` | figures |
| `50_documents` | Word tables and manuscript material |
| `90_estimates` | saved output that other jobs read |

`90_estimates` is numbered last on purpose. It holds results, not jobs, and a
job that needs another job's result reads it from there.

```r
study_setup(
  root = ".",
  study = "Study title from Study Tracker",
  study_tracker_id = 42L
)
```

The executable example uses its temporary directory:

```{r}
#| label: create-study
study_setup(new_root, study = "Synthetic new study", study_tracker_id = 42L)
sort(list.files(new_root))
```

## Register the dataset

Copy the delivered file into `00_datasets`, then register it. Registration
records the file's size, checksum and the population it describes in
`manifest.yaml`:

```r
register_data(
  built = "built.csv",
  role = "study",
  population = "Patients meeting the study inclusion criteria"
)
```

Every job reads data through this registration rather than through a file
path. That is what lets a rendered job record exactly which bytes it read: a
job that opens a path directly cannot tell you, a year later, which version of
the file it saw.

```{r}
#| label: register-data
utils::write.csv(
  delivered, file.path(study_dir("datasets", new_root), "built.csv"), row.names = FALSE
)
register_data(
  new_root,
  built = "built.csv",
  role = "study",
  population = "Synthetic full cohort"
)
```

Registration names no endpoint and no cohort. Those belong to the jobs that
analyse them, so one registered dataset can serve every job in the study.

## Scaffold the first EDA job

Start with the general descriptive checks:

```r
general <- open_job("dc", subject = "cohort", type = "eda", qualifier = "general")
```

`open_job()` creates the job and opens it in RStudio. The file is named
`<subject>-<type>-<prefix>-<qualifier>.qmd`, here
`10_descriptive/cohort-eda-dc-general.qmd`. The subject names what the job is
about and need not be a statistical endpoint: `cohort` describes the whole
registered population. The type names the stage, and the pair keeps a set of
related jobs and their outputs together.

The executable example scaffolds without opening an editor:

```{r}
#| label: scaffold-eda
general <- add_job("dc", subject = "cohort", type = "eda", dir = new_root, qualifier = "general")
sub(paste0(new_root, "/"), "", general, fixed = TRUE)
```

Each job carries `EDIT:` markers where the template cannot know the study's
answer: variables, labels, groups. Work through them from the top. A job that
still contains one is unfinished.

The first `add_job()` in a study also installs its provenance hooks. It adds
pre-render and post-render entries to `_quarto.yml`, keeping any settings
already there, and copies the hook scripts into `.hvtiR/hooks/`:

```{r}
#| label: hooks
cat(readLines(file.path(new_root, "_quarto.yml")), sep = "\n")
list.files(file.path(new_root, ".hvtiR"), recursive = TRUE)
```

## Render and read the provenance

Render the job with the **Render** button, or from the Console:

```r
render_job(general, final = TRUE)
```

Both run the same hooks. While the job executes it records what it read; once
Quarto has written the HTML, the post-render hook publishes a sidecar beside
it, `cohort-eda-dc-general.provenance.json`. An abridged example from a
synthetic study:

```json
{
  "job": "cohort-eda-dc-general",
  "rendered": "2026-09-23T14:42:04Z",
  "study": { "name": "Synthetic new study", "file": "_study.yml", "sha256": "35f29fb1..." },
  "r": { "version": "4.6.1", "platform": "aarch64-apple-darwin23" },
  "data": [
    {
      "dataset": "study",
      "path": "00_datasets/built.csv",
      "role": "study",
      "bytes": 1051,
      "sha256": "3d6f6b0c..."
    }
  ],
  "artifacts": [],
  "source": "10_descriptive/cohort-eda-dc-general.qmd",
  "subject": "cohort",
  "type": "eda",
  "output": { "file": "cohort-eda-dc-general.html", "sha256": "95455dd3..." }
}
```

Read it as a receipt. `data` names the registered file and the checksum of the
bytes the job read. `packages`, omitted here, lists every package version.
`output` carries the checksum of the HTML it describes, so a sidecar can be
matched to its report and to nothing else.

If a render fails, the report and sidecar already on disk are left as they
were. A new sidecar is only ever published beside the HTML it describes. One
job renders at a time in a study; a second render started while one is running
stops and asks you to wait.
````

- [ ] **Step 2: Run the tests**

Run: `Rscript -e 'devtools::test(filter = "vignette-new-study")'`
Expected: `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 10 ]`. The first test passes. The subject test fails once, on `expect_gte(length(calls), 4L)`, because only the `dc` call exists yet. The chain test fails three times (no `ac`, `hz` or `hp` call) and the link test fails once, on `template_list()`.

- [ ] **Step 3: Render the vignette to confirm every chunk executes**

```bash
Rscript -e 'devtools::install(upgrade = "never", quiet = TRUE)'
quarto render vignettes/new-study.qmd --output-dir "$(mktemp -d)"
```

Expected: `Output created: new-study.html` with no chunk error. The `create-study` chunk lists the seven numbered folders; the `hooks` chunk prints the two hook entries.

- [ ] **Step 4: Commit**

```bash
git add vignettes/new-study.qmd
git commit -m "docs: new-study guide, setup through provenance"
```

---

### Task 4: The death chain and the closing section (sections 6 and 7)

**Files:**
- Modify: `vignettes/new-study.qmd` (append after section 5)

**Interfaces:**
- Consumes: `new_root` from Task 3's `synthetic-setup` chunk.
- Produces: the `ac`/`hz`/`hp` calls and the `template_list()` call that Task 2's tests assert.

- [ ] **Step 1: Append sections 6 and 7**

````markdown
## A first analysis chain: death

Most analyses are chains: one job saves a result that the next reads. The
hazard chain has three jobs. `ac` computes the actuarial life table, `hz`
fits the parametric hazard model, and `hp` plots the two together.

```r
open_job("ac", subject = "death", type = "hz")
open_job("hz", subject = "death", type = "hz")
open_job("hp", subject = "death", type = "hz")
```

All three share one subject and one type, and that is what connects them. The
pair `("death", "hz")` names a set, and each job writes and reads its saved
results in the set's own folder, `90_estimates/death-hz/`. `hp` finds `ac.rds`
and `hz.rds` there without a path to edit. A second analysis of the same
endpoint, a random survival forest say, takes a different type and so a
different folder; the two chains cannot overwrite each other's life table.

```{r}
#| label: scaffold-chain
chain <- c(
  ac = add_job("ac", subject = "death", type = "hz", dir = new_root),
  hz = add_job("hz", subject = "death", type = "hz", dir = new_root),
  hp = add_job("hp", subject = "death", type = "hz", dir = new_root)
)
sub(paste0(new_root, "/"), "", chain, fixed = TRUE)
```

The filenames read `death-hz-ac.qmd`, `death-hz-hz.qmd` and `death-hz-hp.qmd`:
subject, type, then the template. `hz` appears twice in the second because the
set is named for its method and the job is that method's template.

```{=html}
<figure style="margin: 1.5rem 0;">
<svg viewBox="0 0 640 210" role="img" aria-labelledby="chain-title" style="width: 100%; height: auto; color: inherit;"
     xmlns="http://www.w3.org/2000/svg" font-family="system-ui, sans-serif" font-size="13">
  <title id="chain-title">The death hazard chain: ac and hz save handoffs that hp reads</title>
  <defs>
    <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto">
      <path d="M0,0 L10,5 L0,10 z" fill="currentColor"/>
    </marker>
  </defs>
  <g fill="none" stroke="currentColor" stroke-width="1.5">
    <rect x="10" y="20" width="150" height="46" rx="6"/>
    <rect x="10" y="130" width="150" height="46" rx="6"/>
    <rect x="245" y="20" width="150" height="46" rx="6" stroke-dasharray="4 3"/>
    <rect x="245" y="130" width="150" height="46" rx="6" stroke-dasharray="4 3"/>
    <rect x="480" y="75" width="150" height="46" rx="6"/>
    <path d="M160,43 L243,43" marker-end="url(#arrow)"/>
    <path d="M160,153 L243,153" marker-end="url(#arrow)"/>
    <path d="M395,43 C440,43 440,90 478,95" marker-end="url(#arrow)"/>
    <path d="M395,153 C440,153 440,106 478,101" marker-end="url(#arrow)"/>
  </g>
  <g fill="currentColor" text-anchor="middle">
    <text x="85" y="41">death-hz-ac.qmd</text>
    <text x="85" y="58" font-size="11">actuarial life table</text>
    <text x="85" y="151">death-hz-hz.qmd</text>
    <text x="85" y="168" font-size="11">parametric hazard</text>
    <text x="320" y="41">ac.rds</text>
    <text x="320" y="58" font-size="11">90_estimates/death-hz/</text>
    <text x="320" y="151">hz.rds</text>
    <text x="320" y="168" font-size="11">90_estimates/death-hz/</text>
    <text x="555" y="96">death-hz-hp.qmd</text>
    <text x="555" y="113" font-size="11">overlay plot</text>
    <text x="320" y="200" font-size="11">each job also publishes a .provenance.json beside its HTML</text>
  </g>
</svg>
<figcaption>Solid boxes are jobs; dashed boxes are the saved handoffs they share through the set's folder.</figcaption>
</figure>
```

Render in chain order: `ac`, then `hz`, then `hp`. Each saved handoff carries
its own lineage, the registered data it was built from, so `hp` can check its
inputs before it plots them. It stops, with a message saying which job to
rerun, when a handoff has no lineage or when `ac` and `hz` were built from
different data. Rerender both upstream jobs after the registered data change.
`hp`'s sidecar then lists the data both handoffs were built from and each
handoff's checksum.

## Where to go next

`template_list()` lists every template with its prefix, qualifier and folder:

```{r}
#| label: templates
head(template_list()[, c("name", "prefix", "qualifier", "folder")], 10)
```

The other chains follow the same pattern: a fitting job saves a handoff that
later jobs read. The random forest jobs (`rfc`, `rfr`, `rfs`) pair a `-fit`
job with an `-explain` job; the logistic family (`lm`) fits and validates
outcome and propensity models; `bh` reports bootstrap variable selection.
````

- [ ] **Step 2: Run the tests**

Run: `Rscript -e 'devtools::test(filter = "vignette-new-study")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 15 ]`.

- [ ] **Step 3: Mutation check**

Change `type = "hz"` to `type = "hazard"` in the `hp` line of the `scaffold-chain` chunk and rerun Step 2.
Expected: the chain test fails with `info = hp`. Revert the change and rerun: `PASS 15`.

- [ ] **Step 4: Render, and check the figure in both themes**

```bash
Rscript -e 'devtools::install(upgrade = "never", quiet = TRUE)'
out="$(mktemp -d)"; quarto render vignettes/new-study.qmd --output-dir "$out"; open "$out/new-study.html"
```

Expected: no chunk error; `scaffold-chain` prints the three paths under `20_distributions/` and `40_graphs/`. The figure draws in the text colour. Switch the operating system to dark mode and confirm it is still legible.

- [ ] **Step 5: Commit**

```bash
git add vignettes/new-study.qmd
git commit -m "docs: new-study guide, the death chain"
```

---

### Task 5: Cross-links, site index, tutorials test and NEWS

**Files:**
- Modify: `vignettes/study-setup.qmd` (after the paragraph that ends "without renaming the legacy working directories or deleting old files.")
- Modify: `tests/testthat/test-vignette-migration.R` (the "study setup vignette declares the complete workflow" and "tutorials use the RStudio project as the study root" tests)
- Modify: `_pkgdown.yml` (`articles:`)
- Modify: `NEWS.md`

**Interfaces:**
- Consumes: `vignettes/new-study.qmd` from Tasks 3 and 4.
- Produces: nothing later tasks call.

- [ ] **Step 1: Write the failing reverse-link assertion**

In `test-vignette-migration.R`, inside `test_that("study setup vignette declares the complete workflow", {`, after `expect_false(any(grepl("cleanup_targets", txt, fixed = TRUE)))` add:

```r
  expect_true(any(grepl("new-study.html", txt, fixed = TRUE)))
```

In `test_that("tutorials use the RStudio project as the study root", {`, extend the `tutorials` vector:

```r
  tutorials <- c(
    testthat::test_path("..", "..", "vignettes", "study-setup.qmd"),
    testthat::test_path(
      "..", "..", "vignettes", "sas-to-r-descriptive.qmd"
    ),
    testthat::test_path("..", "..", "vignettes", "new-study.qmd")
  )
```

- [ ] **Step 2: Run to confirm it fails**

Run: `Rscript -e 'devtools::test(filter = "vignette-migration")'`
Expected: one failure, `any(grepl("new-study.html", txt, fixed = TRUE))` is not TRUE. The tutorials test passes, because Task 3 wrote `RStudio` and `.Rproj` into the new guide and no `setwd()`.

- [ ] **Step 3: Add the cross-link to `study-setup.qmd`**

After the paragraph ending "without renaming the legacy working directories or deleting old files.", insert:

```markdown
If the study does not exist yet and you are starting from a newly delivered
dataset, follow [Start a new study](new-study.html) instead.
```

- [ ] **Step 4: List the article in `_pkgdown.yml`**

```yaml
articles:
  - title: Tutorials
    contents:
      - new-study
      - study-setup
      - sas-to-r-descriptive
      - legacy-study-migration
```

- [ ] **Step 5: Add the NEWS entry**

Under `# hvtiRtemplates (unreleased)` in `NEWS.md`, after the last existing bullet of that section, add:

```markdown
* New vignette, "Start a new study from a delivered dataset", takes a study
  from an empty directory through registration, a first descriptive job and
  its provenance sidecar, to a first `ac`, `hz` and `hp` chain. It complements
  "Adopt an existing study".
```

- [ ] **Step 6: Run the vignette tests**

Run: `Rscript -e 'devtools::test(filter = "vignette")'`
Expected: `FAIL 0`, `SKIP 0` from the source tree.

- [ ] **Step 7: Commit**

```bash
git add vignettes/study-setup.qmd tests/testthat/test-vignette-migration.R _pkgdown.yml NEWS.md
git commit -m "docs: link the new-study guide from setup, the site and NEWS"
```

---

### Task 6: Prose pass, full verification and the pull request

**Files:**
- Modify: `vignettes/new-study.qmd` (prose only)

**Interfaces:**
- Consumes: everything above.
- Produces: the pull request.

- [ ] **Step 1: House-voice pass**

Apply the `ehrlinger-writing` skill to `vignettes/new-study.qmd`, prose only. Do not change a chunk, a call or a filename. Then check the house rules mechanically (the `printf` builds the em dash so this plan does not contain one):

```bash
grep -n "$(printf '\342\200\224')" vignettes/new-study.qmd; grep -n "setwd" vignettes/new-study.qmd
```

Expected: both print nothing.

- [ ] **Step 2: Full test suite**

Run: `Rscript -e 'devtools::test()'`
Expected: `FAIL 0`, `SKIP 0` from the source tree.

- [ ] **Step 3: Full check with the manual**

```bash
Rscript -e 'devtools::document()'
git status --short man NAMESPACE
Rscript -e 'devtools::check(error_on = "note")'
```

Expected: `git status` prints nothing (this plan changes no Rd); the check reports `0 errors | 0 warnings | 0 notes`. Read the `checking re-building of vignette outputs` time from the log and record it for the PR body.

- [ ] **Step 4: Lint and site**

```bash
Rscript -e 'lintr::lint_package()'
Rscript -e 'pkgdown::build_article("new-study")'
```

Expected: no lints; the article builds and appears under Tutorials.

- [ ] **Step 5: Local review stands in for the bot**

Run `/code-review` on the branch against `origin/codex/endpoint-neutral-data-contract` and fix what it confirms.

- [ ] **Step 6: Push and open the PR against `main`**

Write the body to a file first, replacing `VIGNETTE_TIME` with the time recorded in Step 3:

```bash
cat > /tmp/new-study-pr.md <<'EOF'
## Summary

- New vignette `new-study.qmd`: empty directory to registration, first EDA job, its provenance sidecar, and a first `ac`/`hz`/`hp` chain.
- Every reader-facing call executes against synthetic data during the vignette build; nothing is rendered.
- `test-vignette-new-study.R` pins the calls (`subject =`, never `endpoint =`), the chain's shared set and the cross-links.
- Cross-linked from `study-setup.qmd`, listed in `_pkgdown.yml`, NEWS entry under unreleased.

Design: `dev/specs/2026-09-23-new-study-guide-design.md`. Plan: `dev/specs/2026-09-23-new-study-guide-plan.md`.

## Dependency

Built on #142 (`subject`, provenance hooks, hvtiRutilities 1.4.0). Merge after it; this PR's diff shrinks to its own commits once #142 lands.

## Verification

- `devtools::test()`: FAIL 0, SKIP 0 from source.
- `devtools::check(error_on = "note")`: 0/0/0; vignette rebuild VIGNETTE_TIME.
- Expected CI summaries: SKIP 2 on macOS and Ubuntu, SKIP 3 on Windows (unchanged).
- `/code-review` run locally in place of the Copilot bot.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
git push -u origin docs/new-study-guide
gh pr create --base main --title "docs: start a new study from a delivered dataset" --body-file /tmp/new-study-pr.md
```

Opened against `main`, not the #142 branch, so the ruleset's Copilot review fires.

- [ ] **Step 7: Read the CI summaries, not the check marks**

```bash
run=$(gh run list --branch docs/new-study-guide --workflow R-CMD-check.yaml --limit 1 --json databaseId --jq '.[0].databaseId')
gh run view "$run" --log | grep -E "SKIP [0-9]+ \| PASS"
```

Expected: SKIP 2 on macOS and Ubuntu, SKIP 3 on Windows, FAIL 0 everywhere.
