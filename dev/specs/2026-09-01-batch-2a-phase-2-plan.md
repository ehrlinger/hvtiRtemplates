# Batch 2a Phase 2: rewrite `04.05-bh.qmd` onto the reporting layer

**Date:** 2026-09-01
**Status:** EXECUTED 2026-09-01 on `refactor/batch-2a-phase-2`. See section 11 for
what the plan got wrong; the tasks below are left as written so the corrections
have something to point at.
**Design:** `2026-08-31-batch-2a-bootstrap-family-design.md` §7 Phase 2, §8
**Issue:** [#8](https://github.com/ehrlinger/hvtiRtemplates/issues/8)

> **For agentic workers:** implement this task-by-task. Steps use checkbox
> (`- [ ]`) syntax. Do not batch tasks; each ends at a render that must still
> reproduce the baseline, and a batched failure cannot be attributed.

This note is self-contained. It assumes no memory of the session that produced
it.

**Goal:** replace the six computation chunks of `04.05-bh.qmd` with calls into
the `hvtiRbootstrap` 0.1.2 reporting layer, changing no number in the rendered
report, so that `bl`, `br` and `bc` can be written in Phase 3 as thin templates
over the same calls rather than as hand-synced copies of this file.

**Architecture:** a body-only refactor of one file. The ordinal, the filename,
the chunk labels, the section headings, the prose and every `EDIT:` marker are
unchanged. Six chunk **bodies** become one-line calls; the narration explaining
why each number matters stays, because the templates are the product and a
study author must be able to read the report's reasoning without opening
another repository.

**Tech stack:** R, Quarto, `hvtiRbootstrap` >= 0.1.2, `hvtiRutilities` >= 1.1.5,
`TemporalHazard`, `ggplot2`, `testthat` edition 3, `lintr`.

---

## Phase 1 is done, and the equivalence is measured, not assumed

`hvtiRbootstrap` 0.1.2 shipped the reporting layer on 2026-09-01
([#18](https://github.com/ehrlinger/hvtiRbootstrap/pull/18), released at
`3284b66`, plus [#19](https://github.com/ehrlinger/hvtiRbootstrap/pull/19)).

Every replacement below was run against the **real 25-chunk baseline bag**
before this plan was written, comparing the shipped chunk body to the package
function on the same input. Results:

| shipped chunk | package call | result |
|---|---|---|
| `contract` | `boot_validate()` | passes; now checks shapes too |
| `provenance` | `boot_provenance()` | **identical**, 13 rows |
| `seeds` | `boot_seeds()` | **identical**, 25 rows |
| `dropped-summary` / `dropped-detail` | `boot_dropped()` | identical (0 rows on this bag) |
| `health` | `boot_health()` | `check` and `value` identical, 4 rows; **adds `ok`, `note`** |
| `frequencies` | `boot_frequencies()` | **identical**, 266 rows, max \|Δpct\| = 0 |
| `concept-union` | `boot_concepts()` | same 184 rows **in the same order**, max \|Δ\| = 0 on every shared column; **renames `union_pct` → `pct_any`**, adds `forms`, `n_any`, `n_retained` |

⚠️ **The frequencies result was not a foregone conclusion and is the reason to
keep the gate.** The shipped chunk reads `bag$boot$summary`, whatever the
runner recorded. `boot_frequencies()` discards that and **recomputes** from
`bag$boot$replicates`. They agree on this bag; they are not the same source of
truth, and a runner that pooled its summary differently would move every
percentage in the report with nothing to say so.

The scripts that established this are not committed; they read a study bag.
Re-running them is Task 8.

---

## Global constraints

Every task's requirements implicitly include this section.

- **The ordinal and filename do not change.** `inst/templates/analyses/04.05-bh.qmd`
  stays exactly that. `04.06` is retired and cannot be reissued.
- **Exactly one `^ENDPOINT\s+<- ` line and one `^TYPE\s+<- ` line** must survive.
  `new_job()` hard-stops otherwise and the template cannot be scaffolded at all.
- **No study identifiers.** `test-new-job.R` asserts no template matches
  `/studies/`, a study name, or a built-dataset filename. Nothing measured
  against the baseline bag (no variable name, no frequency, no count) is
  written into this repository. Only pass/fail and row counts.
- **Lines are 135 characters**, not 80. Every other default linter is on.
- **Roxygen is Rd markup, not markdown**, irrelevant to a `.qmd` body, but it
  applies to any `R/` or `man/` change a task makes.
- **Chunk labels are unchanged.** They are how the baseline diff aligns.
- Version is a **straight three digits**, patch digit only: `1.0.17` → `1.0.18`.
  Bump `DESCRIPTION` `Version` *and* `Date`, and add the matching `NEWS.md`
  entry, in the same commit. `NEWS.md` uses plain `# hvtiRtemplates X.Y.Z`
  headings with **no `Version:` line**.
- **Never push to `main`.** Work on `spec/batch-2a-phase-2-plan`, then a
  `refactor/` branch; open the PR **against `main`** so Copilot's review fires.
  A PR opened against another branch never gets reviewed, and retargeting does
  not trigger it either.

---

## The baseline, and what "result-identical" means here

| | |
|---|---|
| reference | `~/Documents/templates/bh-baseline-20260831/` |
| rendered output | `project/analyses/dead-hz-04.05-bh.md` |
| sha256 | `da4e39d54df97ad737f11d3be729141090ee896ce3339d4f521c749354f6a749` |
| bag | 25 chunks in `project/estimates/dead-hz/bagging.chunk*.rds` |
| captured from | `04.05-bh.qmd` at v1.0.17 (`66a4038`), after the #59 fix |

It lives outside git because the render carries a real study's variable names
and selection frequencies, and this repository is public. It stays outside git.

**The gate is: every number identical.** Three diffs are expected and are not
regressions; each is listed in Task 8 with the reason:

1. the `collinear` chunk's error text, which cannot run outside a study tree
   either way;
2. the `health` table gains `ok` and `note` columns;
3. the concept-union table's `union_pct` column is renamed `pct_any` and gains
   `forms`, `n_any` and `n_retained`, **unless Task 6 takes the narrowing
   option**, in which case there is no diff there at all.

Any *other* diff fails the task.

---

## File structure

| file | change |
|---|---|
| `inst/templates/analyses/04.05-bh.qmd` | modified: six chunk bodies replaced, one guard rewritten, setup gains a version floor |
| `tests/testthat/test-templates.R` | modified: one new structural test (Task 7) |
| `.lintr` | **unchanged**: `04.05-bh.qmd` already has its own file key at line 71 |
| `DESCRIPTION` | `Version: 1.0.18`, `Date: 2026-09-01` |
| `NEWS.md` | new `# hvtiRtemplates 1.0.18` entry |
| `inst/templates/README.md` | **unchanged**: the row and ordinal are the same |
| `dev/specs/artifacts/2026-08-29-template-roadmap.json` | **unchanged**: `bh` is already `shipped` at `04.05` |

No new file is created. That is the point of a body-only refactor.

---

## Chunk disposition: all 24, so nothing is decided by omission

| # | label | disposition |
|---|---|---|
| 1 | `setup` | **modify**: add version floor (Task 1) |
| 2 | `edit-guard` | unchanged |
| 3 | `set` | unchanged |
| 4 | `expect` | unchanged (`EDIT:` markers) |
| 5 | `load` | unchanged |
| 6 | `completeness` | unchanged: already calls `boot_shortfall()` |
| 7 | `contract` | **replace** → `boot_validate()` (Task 2) |
| 8 | `provenance` | **replace** → `boot_provenance()` (Task 3) |
| 9 | `seeds` | **replace** → `boot_seeds()` (Task 3) |
| 10 | `dropped-summary` | **replace** → `boot_dropped()` (Task 4) |
| 11 | `dropped-detail` | **replace** → `boot_dropped()` (Task 4) |
| 12 | `health` | **replace table, KEEP the refusals** (Task 5) |
| 13 | `criteria` | unchanged (`EDIT:` marker) |
| 14 | `frequencies` | **replace** → `boot_frequencies()` (Task 6) |
| 15 | `retained` | **simplify** → filter on `freq$retained` (Task 6) |
| 16 | `concept-map` | unchanged |
| 17 | `concept-frequencies` | unchanged: a merge for reading, no package equivalent |
| 18 | `concept-union` | **replace** → `boot_concepts()` (Task 6) |
| 19 | `concept-counts` | unchanged |
| 20 | `cluster-matrix` | unchanged |
| 21 | `clusters` | unchanged |
| 22 | `collinear` | unchanged |
| 23 | `fig-frequencies` | unchanged |
| 24 | `save` | unchanged |

### Cross-chunk bindings that must survive

The chunks are one R session. Replacing a body deletes whatever it bound, and
three bindings are read by chunks that are **not** changing:

| binding | assigned in | read by |
|---|---|---|
| `reps` | `health` (line 440) | `cluster-matrix` (line 697) |
| `provenance` | `provenance` (line 328) | `save` (line 820) |
| `freq`, `retained` | `frequencies`, `retained` | `concept-map`, `concept-frequencies`, `concept-counts`, `collinear`, `fig-frequencies`, `save` |

⚠️ **`reps` is the trap.** It is assigned in the `health` chunk and read 250
lines later by `cluster-matrix`, which is not being touched. Replacing the
health body with a bare `boot_health(bag)` deletes it, and the render fails at
`cluster-matrix` with `object 'reps' not found`, far from the edit that caused
it. Task 5 re-binds it explicitly.

---

## Task 1: version floor in `setup`

**Files:** Modify `inst/templates/analyses/04.05-bh.qmd:42-59`

**Interfaces:**
- Consumes: nothing.
- Produces: the `library()` block every later task's calls resolve against.

**Why this is in scope for a body-only refactor.** Before this change the
template used `boot_chunk_files()`, `boot_pool_chunks()`, `boot_shortfall()`
and `boot_clusters()`, all present since 0.1.1. Afterwards it calls seven
functions that exist only from **0.1.2**. A study with 0.1.1 installed gets
`could not find function "boot_provenance"` from the middle of a report, naming
the symbol but not the cause. Four lines convert that into a sentence saying
which version to install. It is caused by this refactor and it is fixed here.

- [ ] **Step 1: add the floor after the `library()` block**

Insert immediately after the closing `})` of the `suppressPackageStartupMessages`
block, still inside the `setup` chunk:

```r
# The reporting layer below -- boot_validate() and everything after it -- landed
# in 0.1.2. Without this check a study on 0.1.1 gets "could not find function
# boot_provenance" from the middle of a render: the symbol is named, the reason
# is not, and the fix is not guessable from the message.
if (utils::packageVersion("hvtiRbootstrap") < "0.1.2") {
  stop("This report needs hvtiRbootstrap >= 0.1.2 for its reporting layer; ",
       utils::packageVersion("hvtiRbootstrap"), " is installed. Update it, ",
       "then re-render.", call. = FALSE)
}
```

- [ ] **Step 2: confirm the template still parses as a Quarto document**

```bash
grep -c '^```{r}' inst/templates/analyses/04.05-bh.qmd
```

Expected: `24`, unchanged, because this adds lines to an existing chunk rather
than a new one.

- [ ] **Step 3: lint**

```bash
Rscript -e 'lintr::lint("inst/templates/analyses/04.05-bh.qmd")'
```

Expected: no output.

- [ ] **Step 4: commit**

```bash
git add inst/templates/analyses/04.05-bh.qmd
git commit -m "refactor(bh): require hvtiRbootstrap 0.1.2 before the reporting layer runs"
```

---

## Task 2: `contract` → `boot_validate()`

**Files:** Modify `inst/templates/analyses/04.05-bh.qmd`, the `contract` chunk

**Interfaces:**
- Consumes: `bag`, bound by the `load` chunk.
- Produces: nothing bound. Called for the error it raises.

`boot_validate()` is strictly stronger than the chunk it replaces: the chunk
checked that eleven fields were **present**, and passed the real bag happily
while `requested` was a length-2 vector the report could not render: the
defect fixed in 1.0.17. `boot_validate()` checks each field's **shape**.

- [ ] **Step 1: replace the chunk body**

Keep the chunk header, the label and every comment line. Replace the 17 lines
of code, from `.required <- c(` through the closing `}` of the `stop()`, with:

```r
boot_validate(bag)
```

Then revise the chunk's own comment so it describes what now happens. Replace
the paragraph beginning "A pooled run has already had most of these checked"
and the one beginning "The nested fields are checked by name too" with:

```r
# A pooled run has already had most of these checked by boot_pool_chunks(),
# which refuses chunks that disagree. A SINGLE unchunked run has not: nothing
# ran between the runner and here. This is the only check that covers both.

# Shapes, not merely names. Checking presence is what let a length-2 `requested`
# reach a table that cannot recycle it against a length-13 item column -- the
# render-blocker that shipped in three releases and was fixed in 1.0.17. Every
# failure is reported at once, because an author fixing a runner wants the whole
# list rather than one field per re-render.
```

- [ ] **Step 2: verify against the baseline bag**

```bash
Rscript -e 'library(hvtiRbootstrap)
d <- path.expand("~/Documents/templates/bh-baseline-20260831/project/estimates/dead-hz")
bag <- boot_pool_chunks(lapply(boot_chunk_files(d, prefix = "bagging"), readRDS))
print(boot_validate(bag))'
```

Expected: `[1] TRUE`. An error here means the baseline bag does not satisfy the
stricter check, which is a finding about `boot_validate()`, not about this
template. Stop and report it rather than loosening anything.

- [ ] **Step 3: lint, then commit**

```bash
Rscript -e 'lintr::lint("inst/templates/analyses/04.05-bh.qmd")'
git add inst/templates/analyses/04.05-bh.qmd
git commit -m "refactor(bh): contract chunk calls boot_validate()"
```

---

## Task 3: `provenance` and `seeds`

**Files:** Modify `inst/templates/analyses/04.05-bh.qmd`, the `provenance` and
`seeds` chunks

**Interfaces:**
- Consumes: `bag`.
- Produces: `provenance`, a data frame with columns `item` and `value`, both
  character, 13 rows. **The `save` chunk serialises this binding by name**, so
  it must be assigned, not merely printed.

`boot_provenance()` is a verbatim port of the chunk: same `cpu_hours`, same
`sha256`-then-`md5` checksum loop, same per-phase collapse. It was verified
identical, 13 rows, on the baseline bag.

- [ ] **Step 1: replace the `provenance` body**

Delete the code from `cpu_hours <- bag$elapsed_mins / 60` through the final
`provenance` echo, including the local `.per_phase()` helper, which now lives
in the package. Keep every comment. The body becomes:

```r
provenance <- boot_provenance(bag)
provenance
```

⚠️ `provenance <-` is not optional. The `save` chunk at line 820 writes
`provenance = provenance` into the report `.rds`; a bare `boot_provenance(bag)`
prints the table and then fails 490 lines later with `object 'provenance' not
found`.

- [ ] **Step 2: replace the `seeds` body**

```r
boot_seeds(bag)
```

This one binds nothing: the `save` chunk does not read it.

- [ ] **Step 3: verify both against the baseline bag**

```bash
Rscript -e 'library(hvtiRbootstrap)
d <- path.expand("~/Documents/templates/bh-baseline-20260831/project/estimates/dead-hz")
bag <- boot_pool_chunks(lapply(boot_chunk_files(d, prefix = "bagging"), readRDS))
p <- boot_provenance(bag); s <- boot_seeds(bag)
cat("provenance rows:", nrow(p), " cols:", paste(names(p), collapse = ","), "\n")
cat("seeds rows:", nrow(s), " cols:", paste(names(s), collapse = ","), "\n")'
```

Expected exactly:

```
provenance rows: 13  cols: item,value
seeds rows: 25  cols: chunk,seed
```

- [ ] **Step 4: lint, then commit**

```bash
Rscript -e 'lintr::lint("inst/templates/analyses/04.05-bh.qmd")'
git add inst/templates/analyses/04.05-bh.qmd
git commit -m "refactor(bh): provenance and seeds chunks call the reporting layer"
```

---

## Task 4: `dropped-summary` and `dropped-detail`

**Files:** Modify `inst/templates/analyses/04.05-bh.qmd`, both `dropped-*` chunks

**Interfaces:**
- Consumes: `bag`.
- Produces: `dropped`, a data frame with zero rows when nothing was dropped.

`boot_dropped()` returns a zero-row data frame rather than `NULL` when
`bag$dropped` is absent, so the two chunks test `nrow()` instead of
`is.null() || !nrow()`.

⚠️ **The baseline bag drops nothing**, so both chunks take their empty branch
and the diff proves only that the empty path is unchanged. The non-empty path
is covered by Task 7's structural test, not by the render.

- [ ] **Step 1: replace the `dropped-summary` body**

Keep the comments. The body becomes:

```r
dropped <- boot_dropped(bag)
if (!nrow(dropped)) {
  cat("Every candidate offered was screened.\n")
} else {
```

…retaining whatever summary the existing `else` branch prints, with
`bag$dropped` replaced by `dropped` throughout it.

- [ ] **Step 2: replace the `dropped-detail` body**

```r
if (nrow(dropped)) {
  dropped
}
```

The ordering by `phase` then `reason` is done inside `boot_dropped()`, so the
explicit `order()` goes.

- [ ] **Step 3: verify the empty path, then the non-empty path**

```bash
Rscript -e 'library(hvtiRbootstrap)
d <- path.expand("~/Documents/templates/bh-baseline-20260831/project/estimates/dead-hz")
bag <- boot_pool_chunks(lapply(boot_chunk_files(d, prefix = "bagging"), readRDS))
cat("baseline dropped rows:", nrow(boot_dropped(bag)), "\n")
bag$dropped <- data.frame(variable = c("b", "a"), phase = c("late", "early"),
                          reason = c("constant", "all missing"))
print(boot_dropped(bag))'
```

Expected: `baseline dropped rows: 0`, then a two-row frame ordered `early`
before `late`.

- [ ] **Step 4: lint, then commit**

```bash
Rscript -e 'lintr::lint("inst/templates/analyses/04.05-bh.qmd")'
git add inst/templates/analyses/04.05-bh.qmd
git commit -m "refactor(bh): dropped chunks call boot_dropped()"
```

---

## Task 5: `health` takes the table, and keeps the refusal

**Files:** Modify `inst/templates/analyses/04.05-bh.qmd`, the `health` chunk

**Interfaces:**
- Consumes: `bag`.
- Produces: `reps`, which is `bag$boot$replicates`, **read by `cluster-matrix` at line
  697**; and `health`, a data frame with columns `check`, `value`, `ok`, `note`.

⚠️ **This is the task that can silently lose a guard, and it is the one to slow
down on.** `boot_health()` **never calls `stop()`.** It reports `ok = FALSE`
with an explanatory `note` and returns. The shipped chunk's enforcement is two
`stop()` calls of its own:

1. the screen selected nothing: no parameter outside the base model appears in
   any replicate, the signature of a formula that did not survive the
   per-replicate rewrite;
2. the first free base parameter has SD exactly 0: every replicate returned the
   same fit, the signature of a bootstrap built on the vector interface.

Both are failures that **do not error on their own** and whose reports read as
perfectly healthy. Swapping the body for a bare `boot_health(bag)` turns each
into a table cell, and the report renders green over a failed screen. The
package moved the *diagnosis* upstream and deliberately left the *refusal*
here.

- [ ] **Step 1: replace the table construction, keeping `reps` bound**

Replace from `reps <- bag$boot$replicates` through the closing `)` of the
`health <- data.frame(...)` call and its `health` echo with:

```r
# Still bound here, and not only for this chunk: `cluster-matrix` below pivots
# these same replicates into the wide matrix boot_clusters() wants. Dropping the
# binding when this body moved into the package would fail 250 lines away,
# naming `reps` and nothing about the cause.
reps <- bag$boot$replicates

health <- boot_health(bag)
health
```

- [ ] **Step 2: rewrite the two refusals against the `ok` column**

Replace the two `stop()` blocks with the following. The messages are the
shipped ones, unchanged: they say what the failure means and what to do, and
`boot_health()`'s `note` is a shorter statement of the same thing for a reader
of the table.

```r
# boot_health() REPORTS; it does not refuse. Both rows below are failures whose
# reports read as healthy -- a screen that selected nothing has n_failed = 0,
# and a bootstrap that refit nothing has n_success = 500 -- so a table cell is
# not enough. The refusal stays in the template, where the render stops.
.failed <- health$check[!is.na(health$ok) & !health$ok]

if ("Distinct candidates ever selected" %in% .failed) {
  stop("The screen selected NOTHING: no parameter outside the base model ",
       "appears in any replicate. That is a failed screen, not a null result, ",
       "and it is what a formula held in a variable looks like from here -- ",
       "n_failed is ", bag$boot$n_failed, ", because the refit error was ",
       "caught and the step simply accepted nothing.\nWrite the model formula ",
       "literally at the call site in your runner and rerun.", call. = FALSE)
}

if ("SD of the first free base parameter" %in% .failed) {
  stop("The first free base parameter has SD exactly 0 across ", bag$n_boot,
       " replicates, so every replicate returned the SAME fit. A bootstrap ",
       "built on the vector interface does that: it refits nothing and reports ",
       "n_success = ", bag$boot$n_success, " with no warning.\nThe frequencies ",
       "below would all be 100% and mean nothing.", call. = FALSE)
}
```

- [ ] **Step 3: prove both refusals still fire**

This is the step that would have caught the guard going missing. Run it and
read the output. A `stop()` that does not fire is the failure being tested
for, and it does not announce itself.

```bash
Rscript -e 'library(hvtiRbootstrap)
d <- path.expand("~/Documents/templates/bh-baseline-20260831/project/estimates/dead-hz")
bag <- boot_pool_chunks(lapply(boot_chunk_files(d, prefix = "bagging"), readRDS))
h <- boot_health(bag)
cat("healthy bag, failed checks:", sum(!is.na(h$ok) & !h$ok), "\n")

# a screen that selected nothing
b2 <- bag; b2$boot$replicates <- b2$boot$replicates[
  b2$boot$replicates$parameter %in% b2$base_params, ]
f2 <- boot_health(b2)$check[!is.na(boot_health(b2)$ok) & !boot_health(b2)$ok]
cat("empty screen flags:", paste(f2, collapse = " | "), "\n")

# a bootstrap that refit nothing
b3 <- bag; b3$free_sd <- 0
f3 <- boot_health(b3)$check[!is.na(boot_health(b3)$ok) & !boot_health(b3)$ok]
cat("flat screen flags:", paste(f3, collapse = " | "), "\n")'
```

Expected:

```
healthy bag, failed checks: 0
empty screen flags: Distinct candidates ever selected
flat screen flags: SD of the first free base parameter
```

If either middle line is empty, the `%in% .failed` test cannot fire and the
guard is gone. Fix that before continuing; do not proceed to Task 6.

- [ ] **Step 4: lint, then commit**

```bash
Rscript -e 'lintr::lint("inst/templates/analyses/04.05-bh.qmd")'
git add inst/templates/analyses/04.05-bh.qmd
git commit -m "refactor(bh): health table from boot_health(), refusals stay in the template"
```

---

## Task 6: `frequencies`, `retained` and `concept-union`

**Files:** Modify `inst/templates/analyses/04.05-bh.qmd`, the `frequencies`,
`retained` and `concept-union` chunks

**Interfaces:**
- Consumes: `bag`, `RETAIN_PCT` (from `criteria`), `concept` (from
  `concept-map`), `reps` (from `health`).
- Produces:
  - `freq`: columns `phase`, `variable`, `term`, `n`, `pct`, `mc_error`,
    `near_threshold`, `retained`. Read by `concept-map`, `concept-frequencies`,
    `collinear`, `fig-frequencies` and `save`.
  - `retained`: the same columns, filtered. Read by `concept-counts` (which
    uses `retained$term`) and `save`.
  - `concept_union`: one row per phase per concept.

`boot_frequencies()` was verified identical to the shipped chunk on the baseline
bag: 266 rows, `max|Δpct| = 0`. It supplies two columns the chunk did not,
`term` and `retained`, and `term` is what `concept-counts` already wanted.

- [ ] **Step 1: define the phase rule once, in `criteria`**

Add to the `criteria` chunk, after `RETAIN_PCT <- 50`:

```r
# EDIT: how a term's name splits into phase and variable. Terms are named
# `<phase>.<variable>`, so one variable offered to two phases is two independent
# screening decisions and must not be pooled into one row. A single-phase screen
# passes NULL instead, and the reporting layer then reports no phase dimension
# at all -- which is how the same functions serve bl, br and bc.
PHASE_OF <- function(term) sub("[.].*$", "", term)
```

- [ ] **Step 2: replace the `frequencies` body**

Keep every comment. The 18 lines of code become:

```r
freq <- boot_frequencies(bag, phase = PHASE_OF, threshold = RETAIN_PCT)
freq[, c("phase", "variable", "n", "pct", "mc_error", "near_threshold")]
```

The explicit column selection is what holds the printed table identical: the
returned frame also carries `term` and `retained`, and echoing it whole would
add two columns to the report.

- [ ] **Step 3: replace the `retained` body**

```r
retained <- freq[freq$retained, , drop = FALSE]
retained[, c("phase", "variable", "n", "pct", "mc_error", "near_threshold")]
```

`freq$retained` is `pct >= RETAIN_PCT`, computed in the package from the same
`threshold`; the comparison, including its `>=`, was verified to agree.

- [ ] **Step 4: replace the `concept-union` body**

Keep every comment. The 28 lines (`cov_reps`, the `split()`/`lapply()`, the
`do.call(rbind, ...)`) become:

```r
concept_union <- boot_concepts(bag, concept_map = concept[, c("variable", "concept")],
                               phase = PHASE_OF, threshold = RETAIN_PCT)
concept_union[, c("phase", "concept", "n_forms", "pct_any", "best_form_pct",
                  "spread", "retained")]
```

⚠️ **This is the one table whose printed form changes**, and the change is a
column *name*: the shipped chunk called the at-least-one figure `union_pct` and
`boot_concepts()` calls it `pct_any`. Every value is identical: same 184 rows,
same order, `max|Δ| = 0` on all four shared numeric columns, and the package's
name is the better one, because `boot_clusters()` has called it `pct_any` since
0.1.1 and two names for one quantity across two functions in one report is the
drift this extraction exists to remove. The column selection above also drops
`forms`, `n_any` and `n_retained` from the printed table, keeping it the width
it was; they remain available in the object.

**If a byte-identical diff is wanted instead**, add
`names(concept_union)[names(concept_union) == "pct_any"] <- "union_pct"` before
the echo. Decide once, here, and record which in Task 8's diff notes; do not
leave the render to reveal it.

- [ ] **Step 5: verify the three tables against the shipped bodies**

```bash
Rscript -e 'library(hvtiRbootstrap); library(hvtiRutilities)
d <- path.expand("~/Documents/templates/bh-baseline-20260831/project/estimates/dead-hz")
bag <- boot_pool_chunks(lapply(boot_chunk_files(d, prefix = "bagging"), readRDS))
PHASE_OF <- function(term) sub("[.].*$", "", term)
freq <- boot_frequencies(bag, phase = PHASE_OF, threshold = 50)
cat("freq rows:", nrow(freq), " retained:", sum(freq$retained), "\n")
cn <- concept_map(unique(freq$variable), affixes = POOL_AFFIXES,
                  min_stem = POOL_MIN_STEM, plain_suffix = POOL_PLAIN_SUFFIX)
cu <- boot_concepts(bag, cn[, c("variable", "concept")], phase = PHASE_OF, threshold = 50)
cat("concept rows:", nrow(cu), " cols:", paste(names(cu), collapse = ","), "\n")'
```

Expected: `freq rows: 266`, and `concept rows: 184` with columns
`phase,concept,n_forms,forms,n_any,pct_any,best_form_pct,spread,n_retained,retained`.

- [ ] **Step 6: lint, then commit**

```bash
Rscript -e 'lintr::lint("inst/templates/analyses/04.05-bh.qmd")'
git add inst/templates/analyses/04.05-bh.qmd
git commit -m "refactor(bh): frequencies, retained and concepts call the reporting layer"
```

---

## Task 7: a structural test that this file did not drift back

**Files:** Modify `tests/testthat/test-templates.R`

**Interfaces:**
- Consumes: `template_path("analyses/04.05-bh.qmd")`.
- Produces: nothing.

The render gate in Task 8 needs a study bag and cannot run in CI. What CI *can*
assert is that the template calls the reporting layer rather than carrying its
own copy again, which is exactly the regression this batch exists to prevent,
and the one a future hand-edit would reintroduce.

- [ ] **Step 1: write the failing test**

```r
test_that("the bh template reports through hvtiRbootstrap, not its own copy", {
  src <- readLines(template_path("bh"), warn = FALSE)

  # Comments stripped before matching, and not as tidiness. This template
  # NARRATES the reporting layer: the setup chunk's version-floor comment names
  # boot_validate() and the health chunk's comment names boot_health(). Matching
  # raw source would let a hand-edit delete a live call, leave its explanatory
  # comment behind, and keep this test green, which is precisely the drift the
  # test exists to catch. Same guard as the template-token test above.
  code <- sub("#.*$", "", src)

  # The reporting layer is the point of Batch 2a: bl, br and bc are thin only
  # because these calls live in the package. A hand-edit that inlines one of
  # them back into this file makes four reports to hand-sync again.
  for (fn in c("boot_validate", "boot_provenance", "boot_seeds", "boot_dropped",
               "boot_health", "boot_frequencies", "boot_concepts")) {
    expect_true(any(grepl(paste0(fn, "("), code, fixed = TRUE)),
                info = paste(fn, "is not called by the bh template"))
  }

  # boot_health() reports and never stops, so the two refusals are the
  # template's own. A report that renders green over a screen which selected
  # nothing is the failure these prevent.
  expect_true(any(grepl("The screen selected NOTHING", code, fixed = TRUE)))
  expect_true(any(grepl("returned the SAME fit", code, fixed = TRUE)))
})
```

- [ ] **Step 2: run it against the *pre-refactor* file to see it fail**

Tasks 2-6 are already committed by now, so the working tree passes. Extract the
shipped file and assert against that copy instead. **Do not `git stash`**: it
would take the whole working tree with it for a read that needs one file.

```bash
git show 66a4038:inst/templates/analyses/04.05-bh.qmd > /private/tmp/claude-504/-Users-ehrlinj-Documents-GitHub-hvtiRtemplates/c4a63f00-32ca-496c-b1c4-279ecadb293f/scratchpad/bh-old.qmd
Rscript -e 'src <- readLines("/private/tmp/claude-504/-Users-ehrlinj-Documents-GitHub-hvtiRtemplates/c4a63f00-32ca-496c-b1c4-279ecadb293f/scratchpad/bh-old.qmd", warn = FALSE)
cat("calls boot_validate:", any(grepl("boot_validate(", src, fixed = TRUE)), "\n")'
```

Expected: `calls boot_validate: FALSE`, which is the assertion failing on the
pre-refactor file, and therefore the test having teeth.

- [ ] **Step 3: run the suite**

```bash
Rscript -e 'devtools::test()'
```

Expected: PASS, with **`SKIP 0`**. Read the `testthat` summary line itself.
A green conclusion above a skipped test is the failure mode `hvtiRlifetables`
shipped through ten CI runs and two reviews.

- [ ] **Step 4: commit**

```bash
git add tests/testthat/test-templates.R
git commit -m "test(bh): assert the template reports through the package and keeps its refusals"
```

---

## Task 8: the render gate

**Files:** none in this repository. This runs in
`~/Documents/templates/bh-baseline-20260831/`.

**Interfaces:**
- Consumes: the refactored template; the 25-chunk bag.
- Produces: a pass/fail and a diff summary. **No study identifier returns.**

- [ ] **Step 1: scaffold a fresh job from the refactored template**

Work on a copy so the reference render is never overwritten:

```bash
cp -R ~/Documents/templates/bh-baseline-20260831 ~/Documents/templates/bh-phase2-check
```

- [ ] **Step 2: re-apply the baseline's three recorded edits**

They are listed in the baseline's own `README.md` and the comparison is invalid
without all three:

1. `BOOT_PREFIX <- "bagging"`, because the runner wrote `bagging.chunkNN.rds`.
2. `CLUSTERS` set to `early.Ht = c("early.ht", "early.ln_ht")`.
3. `#| error: true` on the `collinear` chunk, which calls `read_built()` and
   needs a study tree, and without this the render aborts there and writes
   nothing at all.

- [ ] **Step 3: render with the draft flag**

```bash
cd ~/Documents/templates/bh-phase2-check/project && HVTI_TEMPLATE_DRAFT=1 quarto render analyses/dead-hz-04.05-bh.qmd --to gfm
```

Expected: completes, with the DRAFT banner. The banner reflects unresolved
`EDIT:` markers, not unreliable values.

- [ ] **Step 4: diff against the reference**

```bash
diff ~/Documents/templates/bh-baseline-20260831/project/analyses/dead-hz-04.05-bh.md ~/Documents/templates/bh-phase2-check/project/analyses/dead-hz-04.05-bh.md
```

Expected: **only** the diffs listed below. Anything else fails the task; do not
accept a numeric diff on the grounds that it looks small. The whole point of a
baseline is that "small" is not a category it has.

| expected diff | why it is not a regression |
|---|---|
| `collinear` chunk error text | that chunk cannot run outside a study tree either way; noted in the baseline README |
| `health` table gains `ok` and `note` columns | `boot_health()` returns them; `check` and `value` are identical |
| `union_pct` → `pct_any` in the concept table | a rename, values identical; **absent if Task 6 Step 4 took the narrowing option** |

- [ ] **Step 5: record the result, without identifiers**

⚠️ **Do not write to `NEWS.md` here.** The 1.0.18 entry does not exist yet;
Task 9 creates it, and this step ran before it. Put the outcome in this task's
report file instead, counts and pass/fail only, and Task 9 carries the sentence
into `NEWS.md`:

```
  Verified against the 25-chunk reference render captured at 1.0.17: the
  provenance, seeds, frequency, retained and concept tables reproduce
  row-for-row and value-for-value.
```

No variable name, no frequency and no study name leaves the render directory.

- [ ] **Step 6: clean up the scratch copy**

```bash
rm -rf ~/Documents/templates/bh-phase2-check
```

---

## Task 9: release

**Files:** `DESCRIPTION`, `NEWS.md`

- [ ] **Step 1: bump `DESCRIPTION`**

```
Version: 1.0.18
Date: 2026-09-01
```

- [ ] **Step 2: add the `NEWS.md` entry**

```markdown
# hvtiRtemplates 1.0.18

## Improvements

* `04.05-bh.qmd` reports through the `hvtiRbootstrap` reporting layer rather
  than carrying its own copy of it. The contract check, provenance and seed
  tables, dropped-candidate tables, health table, selection frequencies and
  concept grouping are now `boot_validate()`, `boot_provenance()`,
  `boot_seeds()`, `boot_dropped()`, `boot_health()`, `boot_frequencies()` and
  `boot_concepts()`. The ordinal, filename, chunk labels, prose and every
  `EDIT:` marker are unchanged.

  This is what makes `bl`, `br` and `bc` thin templates in Batch 2a rather than
  four ~825-line reports to hand-sync on every fix.

  `boot_health()` reports; it does not refuse. The two refusals (a screen that
  selected nothing, and a bootstrap whose free base parameter has SD exactly 0)
  stay in the template, because both are failures whose reports otherwise read
  as healthy.

  Verified against the 25-chunk reference render captured at 1.0.17: the
  provenance, seeds, frequency, retained and concept tables reproduce
  row-for-row and value-for-value.
```

- [ ] **Step 3: document, test, check**

```bash
Rscript -e 'devtools::document(); devtools::test()'
Rscript -e 'devtools::check()'
```

Expected: `document()` leaves `man/` and `NAMESPACE` unchanged (no `R/` change
in this plan); `test()` passes with `SKIP 0`; `check()` is **0 errors, 0
warnings, 0 notes**.

- [ ] **Step 4: build the PDF manual locally**

`check-manual.yaml` has no `pull_request` trigger, so it runs for the first time
*after* merge, where there is no PR left to fix it in. This plan touches no Rd
markup, so this should be uneventful; run it anyway, because "should be" is the
assumption that gate exists to catch.

```bash
R CMD Rd2pdf . --output=/private/tmp/claude-504/-Users-ehrlinj-Documents-GitHub-hvtiRtemplates/c4a63f00-32ca-496c-b1c4-279ecadb293f/scratchpad/hvtiRtemplates.pdf --force --no-preview
```

Expected: completes with no LaTeX error.

- [ ] **Step 5: commit and open the PR against `main`**

```bash
git add DESCRIPTION NEWS.md
git commit -m "release: 1.0.18"
git push -u origin refactor/batch-2a-phase-2
gh pr create --base main \
  --title "refactor(bh): report through the hvtiRbootstrap reporting layer" \
  --body-file /private/tmp/claude-504/-Users-ehrlinj-Documents-GitHub-hvtiRtemplates/c4a63f00-32ca-496c-b1c4-279ecadb293f/scratchpad/pr-body.md
```

Write the body to that file first. `--body-file /dev/stdin` with nothing piped
to it waits on the terminal and never returns.

Open it **against `main`**. A PR opened against another branch never triggers
Copilot's review, and GitHub retargeting the base when a parent merges does not
trigger it either, and the branch then sits one click from `main` having been read
by nobody.

---

## Self-review

**Spec coverage.** Design §7 Phase 2 requires: rewritten onto the new API
(Tasks 2–6), ordinal and filename unchanged (Global constraints; no task
renames the file), verified result-identical against the Phase 0 render
(Task 8). Design §8's definition of done for this phase: `devtools::test()`
passes and `check()` is 0/0/0 (Task 9 Step 3), `document()` run (Task 9 Step 3),
patch bump with matching `NEWS.md` (Task 9 Steps 1–2). `.lintr` needs no new key:
`04.05-bh.qmd` already has its own file key at line 71, and this refactor
adds no file.

**Not covered, deliberately.** Phase 3 (`bl`, `br`, `bc`) is a separate plan;
this one stops at a `bh` that reports through the package. `bq`
([hvtiRbootstrap#16](https://github.com/ehrlinger/hvtiRbootstrap/issues/16))
and `bn` are out of scope per design §9.

**Residual risk, stated rather than resolved.** The render gate exercises one
bag from one study. `boot_dropped()`'s non-empty path, the single-unchunked-run
fallbacks in `boot_seeds()` and `boot_health()`, and the `phase = NULL` path
that Phase 3 depends on are **not** covered by it. The first is covered by
Task 4 Step 3 and Task 7, the last only by `hvtiRbootstrap`'s own tests. Phase 3
is where `phase = NULL` first gets a real render.


---

## 11. Post-execution: what this plan got wrong

Nine tasks, nine per-task reviews and one whole-branch review. The render gate
passed: provenance, seeds, frequency and retained tables byte-identical against
the reference, concept table zero value mismatches across 184 rows, figure PNG
the same sha256. `devtools::check()` 0/0/0, `devtools::test()` `SKIP 0 | PASS 118`.

Six defects in the plan itself, recorded because the next batch will be written
from this one.

**D1. The version floor was wrong, and this is the one that mattered.** The plan
floored `hvtiRbootstrap` at 0.1.2, reasoning that 0.1.2 is where the reporting
layer landed and is therefore the honest minimum. True, and still the wrong
floor: 0.1.2 splits a term into phase and variable by stripping the phase label
whether or not a separator follows it, so a term named `earlyage` reports its
variable as `age`. A real name, matching no concept, quietly absent from every
grouped table. Raised to 0.9.0 in the shipped template. **A frequency that is
merely wrong is worse than a function that is missing**, because a missing
function names itself in an error and a mis-split term produces a report that is
complete, plausible and incorrect.

**D2. Task 6's `PHASE_OF` comment documented a path the template cannot take.**
It told the study author that "a single-phase screen passes `NULL` instead".
The reporting layer does accept `NULL`; this template does not. With
`PHASE_OF <- NULL` the render dies at `freq[, c("phase", ...)]`, again at
`order(by_concept$phase, ...)`, and would die at `facet_wrap(~phase)`. Followed
literally by the author it was written for, the instruction yields four
unattributable errors. Found only by the whole-branch reviewer executing it.

**D3. `template_path()` takes a bare prefix, not a path.** Task 7's interface
block said `template_path("analyses/04.05-bh.qmd")`. `R/templates.R:46` shows
`template_path(prefix)`; the folder-qualified form errors with "unknown
template". Corrected to `template_path("bh")`.

**D3b. The Task 7 test matched raw source, so a comment could satisfy it.** This
template narrates the reporting layer: the setup chunk's version-floor comment
names `boot_validate()` and the health chunk's names `boot_health()`. Matching
uncommented source would let a hand-edit delete a live call, leave the comment,
and keep the test green. Found independently by the task reviewer and by
Copilot on the plan PR. Fixed by stripping comments first, following the guard
an adjacent test in the same file already used; `knitr::purl()` would also work
but would not match the file's existing pattern. Task 7's code block above is
the shipped version.

**D4. Task 8's render command named the wrong pandoc writer.** The plan said
`--to gfm`; the reference was captured with `--to markdown`. `gfm` produces 38
hunks and 804 lines of pure writer noise having nothing to do with the refactor.
The baseline README recorded no writer at all, which is what let the plan guess;
it now records `--to markdown`.

**D5. Task 8's expected-diff list omitted the largest diff category.** The
rendered `.md` echoes each chunk's R source, so rewriting six chunk bodies
necessarily rewrites 208 lines of echoed source. The plan named three expected
diffs when the honest number was five: echoed source, and the DRAFT banner's
unresolved-marker count moving 10 to 11 as `PHASE_OF` is added. A gate that
enumerates fewer diffs than it will see invites the operator to either fail a
clean run or wave through a dirty one.

**D6. Task 2 Step 1's first "replacement" comment paragraph was byte-identical
to the text already in the file.** A no-op that reads as an edit.

### One defect the plan did not have, and the reason it did not

`boot_health()` reports and never refuses, so the template keeps its own two
`stop()` calls. The plan said so and Task 5 implemented it. What neither caught
is that matching a check by its LABEL STRING **fails open**: rename a check
upstream and `%in%` is simply `FALSE`, both refusals silently vanish, and a
screen that selected nothing renders green. The structural test greps the
template's own source and never compares those strings to what `boot_health()`
returns, so the coupling was untested in both repositories. The shipped template
now asserts both labels are present before the guards run, so drift stops the
render instead of deleting the guards. The label-matching design is unchanged;
it is the maintainer's, and this makes it fail loud rather than replacing it.

### For Phase 3

`bl`, `br` and `bc` are the templates that actually take `phase = NULL`. D2 is
their first real problem, not a footnote: whatever they share with this file has
to work without a phase column, and this file has never been run that way.
