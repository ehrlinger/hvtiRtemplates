# Batch 2a Phase 3 — `bl`, `br`, `bc` implementation plan

Steps use checkbox (`- [ ]`) syntax so a task can be picked up mid-way. Work
task by task and run each task's verification before moving on.

**Date:** 2026-09-01
**Status:** 2026-09-01. Part A paused after Task A1; see the execution note at
the end of Part A. **Part B complete and pushed** on `feat/batch-2a-phase-3`,
check 0/0/0, PR held until `hvtiRbootstrap` 0.9.2 ships; see the Part B
execution note, which records six defects in this plan.
**Design:** `2026-08-31-batch-2a-bootstrap-family-design.md` §4, §7 Phase 3, §8
**Predecessor:** `2026-09-01-batch-2a-phase-2-plan.md`
**Issue:** [#8](https://github.com/ehrlinger/hvtiRtemplates/issues/8)

**Goal:** Ship `bl`, `br` and `bc` as thin templates over `hvtiRbootstrap`'s
reporting layer, and give that layer a producer it can actually read.

**Architecture:** Phase 1 extracted the reporting layer out of `bh`'s bag.
Nothing checked what the package's own `boot_select()` returns, and it returns
something else: a wide `boot_selection` matrix with no provenance. So Phase 3
opens **upstream** — `boot_select()` records what it knows, and a new
`boot_bag()` converts a `boot_selection` plus the runner's four unknowable
facts into a validated bag. Only then are `bl`, `br` and `bc` thin. This is
the same order Phase 1 used, and for the same reason.

**Tech Stack:** R (>= 4.1), `hvtiRbootstrap` 0.9.1 → 0.9.2, `hvtiRtemplates`
1.0.18 → 1.0.19, `hvtiRutilities` (>= 1.1.4), Quarto, testthat edition 3.

**Three parts, in order.** Part A is `hvtiRbootstrap` 0.9.2 and ships as its
own release. Part B is the three templates and their render gate. Part C is
the SAS parity check for `bl` and `br`, and it lives in the study's own R
project, not here. Part C can begin once Part B's templates render; it does
not block the 1.0.19 release, but its results are carried back into the
README, `NEWS.md` and the design by Task C4.

---

## 0. The gap this plan closes, and how it survived two phases

The design's §4 promised "one code path serves all four templates" and §7
sequenced Phase 3 as templates only. Both are true of the *reading* side. The
*writing* side was never examined.

`boot_validate()` requires a long-form bag:

```
n_boot  seed  slentry  slstay  base_params  requested  usable  n_rows
elapsed_mins  manifest  boot$replicates  boot$summary  boot$n_success
boot$n_failed
```

`boot$replicates` is long: one row per (replicate, term) pair that was
selected, with an unselected term simply absent. That shape is written by
TemporalHazard's hazard runner, which is why `bh` works.

`boot_select()` — the package's own entry point, and the function `bl`, `br`
and `bc` runners call — returns `new_boot_selection(m, n_rep, n_attempts,
call)` (`R/boot-class.R:1`): a **wide** coefficients matrix, two integers and
an unevaluated call. It takes `sle`, `sls` and `seed` as arguments and records
none of them structurally. Nothing in the package pivots wide to long.

So the reporting layer cannot be reached from the screen function that feeds
it. Written as designed, each study would hand-write the pivot plus nine
provenance fields, and `bl`/`br`/`bc` would ship three copies of an
instruction to do so.

**This is the design's own §6 failure shape — a field read out of an artifact
produced by a different package — with one difference that makes it worse:
here the artifact is produced by the same package, at the other end of it.**
The two ends were built against different studies and never met.

⚠️ **Do not "fix" this in the templates.** An `EDIT:`-marked pivot in three
files is the four-files-to-hand-sync problem the extraction exists to remove,
re-entered one layer down.

### What Phase 3 does NOT fix

- ⚠️ **[#21](https://github.com/ehrlinger/hvtiRbootstrap/issues/21) and
  [#22](https://github.com/ehrlinger/hvtiRbootstrap/issues/22) were fixed
  while this plan was being written**, by
  [#23](https://github.com/ehrlinger/hvtiRbootstrap/pull/23) (commit
  `4691713`, 2026-09-01), and more thoroughly than this plan scoped them: every
  optional read is now exact -- `dropped`, `free_sd`, `n_chunks`, `seeds`,
  `th_sha`, `th_version` -- and `boot_validate()` refuses a per-phase
  `free_sd`. Task A3 is **withdrawn** in consequence, and Part A is based on
  that PR rather than on 0.9.0.
- **[#16](https://github.com/ehrlinger/hvtiRbootstrap/issues/16)** (`bq`,
  no quantile fitter) and `bn` stay out of scope per design §9.

---

## Global Constraints

Every task's requirements implicitly include this section.

- ⚠️ **Work in a git worktree, not in the shared clone.** On 2026-09-01 a
  concurrent session switched `hvtiRbootstrap`'s working tree to another branch
  between this plan's `git checkout -b` and its first commit, so Task A1's
  commit landed on **that** session's branch and the working tree later
  reverted under it. A branch cut is a point-in-time guess; only a worktree
  isolates. `hvtiRtemplates` already keeps `.claude/worktrees/`.
- **Never push to `main`.** Branch, open a PR **against `main`**, let the
  maintainer merge. A PR opened against another branch gets no Copilot review
  and still reaches `main` when the parent merges.
- **Versions are straight three digits.** `hvtiRbootstrap` → **0.9.2**
  (0.9.1 is taken by
  [#23](https://github.com/ehrlinger/hvtiRbootstrap/pull/23)),
  `hvtiRtemplates` 1.0.18 → **1.0.19**. Patch digit only; minor and major are
  the maintainer's decision. No `.9000`, no fourth digit.
- **Bump `DESCRIPTION`, refresh its `Date`, and add the matching `NEWS.md`
  entry in the same commit.** `hvtiRtemplates` `NEWS.md` uses plain
  `# hvtiRtemplates X.Y.Z` headings — **no `Version:` line**.
- **`devtools::document()` is run and `man/` + `NAMESPACE` are committed with
  the source change**, in both repositories.
- **Line length:** `hvtiRtemplates` `.lintr` sets 135. `hvtiRbootstrap` has
  **no `.lintr`**, so lintr's default 80 applies there. Do not carry a width
  across.
- **A new template needs its own key in `.lintr`, and the key must be the
  FILE.** `"inst/templates/analyses/04.02-bl.qmd" = list(...)`. A directory
  key silences every linter on the path, wholesale and silently.
- **Templates carry no study identifiers.** `test-new-job.R` asserts no
  template matches `/studies/`, a study name, or a built-dataset filename.
- **Every study-specific line is marked `EDIT:`**, and the comment says *why*
  the choice matters, not only what to type.
- ⚠️ **The two repositories take OPPOSITE roxygen dialects, and this plan got
  it wrong until 2026-09-01.** `hvtiRbootstrap` **does** set
  `Roxygen: list(markdown = TRUE)` (`DESCRIPTION:24`), so Part A is written in
  markdown: backticks, `[fn()]` links, `**bold**`. `hvtiRtemplates` sets no
  such field, so Part B is Rd markup: `\code{}`, `\strong{}`, `\emph{}`,
  `\itemize{}`, `\link{}`. `AGENTS.md`'s "Roxygen here is Rd markup" is a
  statement about **this** repository only. Carrying it across is the same
  mistake `AGENTS.md` warns about for `.lintr` widths and `_pkgdown.yml`
  indexes, made in a plan that quotes those warnings.
- **Every exported object needs `@return`.**
- **No em-dashes in package documentation, template prose, commit messages or
  PR bodies.** Use `--` in code comments, "and" or a comma in prose.
- **Ordinals are keys, assigned once.** This plan assigns `bl` = **04.02**,
  `br` = **04.03**, `bc` = **04.04** — the three lowest free minors in
  `analyses`. `04.01` is `hm`, `04.05` is `bh` (frozen), `04.06` is
  **retired and can never be reissued**. Do not recompute any of these from
  taxonomy row position; that is the mistake that cost `bh` a renumber.

---

## File structure

**`hvtiRbootstrap`** (Part A, ships first, its own release)

| file | responsibility |
|---|---|
| `R/boot-select.R` | modify: record a `$control` list on the returned object |
| `R/boot-bag.R` | **create**: `boot_bag()`, the `boot_selection` to bag adapter |
| `R/boot-frequencies.R` | modify: one line, `bag[["dropped"]]` (issue #21) |
| `tests/testthat/test-boot-bag.R` | **create**: adapter round-trip and refusals |
| `tests/testthat/test-boot-select.R` | modify: `$control` is recorded |
| `tests/testthat/test-boot-frequencies.R` | modify: #21 regression |

**`hvtiRtemplates`** (Part B)

| file | responsibility |
|---|---|
| `dev/specs/2026-08-31-batch-2a-bootstrap-family-design.md` | modify: §4.2 records the gap, §7 and §8 restate Phase 3 |
| `dev/specs/artifacts/2026-09-01-phase-3-render-gate.R` | **create**: the render-gate harness |
| `inst/templates/analyses/04.02-bl.qmd` | **create** |
| `inst/templates/analyses/04.03-br.qmd` | **create** |
| `inst/templates/analyses/04.04-bc.qmd` | **create** |
| `.lintr` | modify: one file key per new template |
| `DESCRIPTION` | modify: version, Date, `hvtiRbootstrap (>= 0.9.2)` |
| `NEWS.md` | modify: 1.0.19 entry |
| `inst/templates/README.md` | modify: three table rows, the untemplated list |
| `dev/specs/artifacts/2026-08-29-template-roadmap.json` | modify: three rows to `shipped` with ordinals |
| `dev/specs/2026-08-29-template-conversion-roadmap.md` | regenerate |
| `tests/testthat/test-templates.R` | modify: the thin-template structural test |

**The study's R project** (Part C, nothing here enters `hvtiRtemplates`)

| file | responsibility |
|---|---|
| `R/read_bootreg_summary.R` | **create**: parse a `%bootreg` summary `.lst` into `boot_summary()`'s columns |
| `R/compare_bootreg.R` | **create**: the distributional comparison and its five criteria |
| a `bl` job and its runner | **create**: scaffolded from `04.02-bl.qmd` |
| a `br` job and its runner | **create**: scaffolded from `04.03-br.qmd` |
| `docs/specs/<date>-bl-br-parity.md` | **create**: criteria stated before the run, measured values after |

---

# Part A — `hvtiRbootstrap` 0.9.2

⚠️ **Base this on [#23](https://github.com/ehrlinger/hvtiRbootstrap/pull/23),
not on `origin/main`.** That PR fixes the optional-field reads `boot_bag()`'s
output is read through, and it has already taken 0.9.1. Cutting from
`origin/main` instead puts the adapter on a base whose `boot_dropped()` still
partial-matches.

⚠️ **Use a worktree.** The shared clone is not safe: see the Global
Constraints.

```bash
cd ~/Documents/GitHub/hvtiRbootstrap && git fetch origin && git worktree add ../hvtiRbootstrap-boot-bag -b feat/boot-bag-adapter origin/fix/optional-field-reads
```

---

### Task A1: `boot_select()` records what it knows

**Why this task exists.** `boot_bag()` must not ask its caller to retype
`sle`, `sls`, `seed` or the row count. A bag whose `slentry` was retyped by
hand can disagree with the run that produced it, and the provenance table
would report the typed value as though the screen had used it. The run is the
only honest source, so the run records them.

`$call` is not that source: `match.call()` omits every argument left at its
default, so a screen run with `sle = 0.10` records nothing about `sle`.

**Files:**
- Modify: `R/boot-select.R` (the `new_boot_selection()` call at the end of
  `boot_select()`, and the `@return` block near line 45)
- Modify: `R/boot-class.R` (`new_boot_selection()` signature)
- Test: `tests/testthat/test-boot-select.R`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `x$control`, a named list carrying
  `method` (character), `sle` (numeric), `sls` (numeric), `max_steps`
  (integer), `fraction` (numeric), `seed` (numeric or `NA_real_`),
  `n_rows` (integer), `n_terms` (integer), `elapsed_mins` (numeric),
  `package` (character, the `hvtiRbootstrap` version string).
  Task A2 reads every one of these.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-boot-select.R`:

```r
test_that("boot_select() records the run's own control settings", {
  set.seed(4)
  n <- 120
  x1 <- stats::rnorm(n)
  df <- data.frame(y = 2 * x1 + stats::rnorm(n), x1 = x1, x2 = stats::rnorm(n))

  fit <- boot_select(df, y ~ x1 + x2, fit_linear, n_rep = 5, sle = 0.08,
                     sls = 0.04, seed = 77)

  # Every field boot_bag() reads. Named individually rather than by
  # setdiff(), so a failure says WHICH one went missing.
  ctl <- fit$control
  expect_type(ctl, "list")
  expect_identical(ctl$method, "stepwise")
  expect_identical(ctl$sle, 0.08)
  expect_identical(ctl$sls, 0.04)
  expect_identical(ctl$seed, 77)
  expect_identical(ctl$n_rows, 120L)
  expect_identical(ctl$n_terms, 2L)
  expect_type(ctl$elapsed_mins, "double")
  expect_gte(ctl$elapsed_mins, 0)
  expect_identical(ctl$package,
                   as.character(utils::packageVersion("hvtiRbootstrap")))
})

test_that("an unseeded run records NA rather than inventing a seed", {
  set.seed(5)
  df <- data.frame(y = stats::rnorm(60), x1 = stats::rnorm(60))
  fit <- boot_select(df, y ~ x1, fit_linear, n_rep = 3)
  expect_true(is.na(fit$control$seed))
})
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd ~/Documents/GitHub/hvtiRbootstrap && Rscript -e 'devtools::test(filter = "boot-select")'
```

Expected: FAIL, `ctl` is `NULL` so `expect_type(ctl, "list")` reports
`"NULL"`.

- [ ] **Step 3: Widen `new_boot_selection()`**

In `R/boot-class.R`, replace the constructor:

```r
new_boot_selection <- function(coefficients, n_rep, n_attempts, call,
                               control = NULL) {
  structure(
    list(coefficients = coefficients, n_rep = n_rep,
         n_attempts = n_attempts, call = call, control = control),
    class = "boot_selection"
  )
}
```

`control = NULL` rather than a required argument: the constructor is
internal, but an object saved before 0.9.2 and reloaded under it has no
`control` either, and `boot_bag()` in Task A2 refuses that case by name
rather than failing on an absent list element.

- [ ] **Step 4: Record the control settings in `boot_select()`**

In `R/boot-select.R`, immediately before the `while (kept < n_rep)` loop, add
the start time. `ctrl` is already built at line 109:

```r
  .t0 <- proc.time()[["elapsed"]]
```

Then replace the closing `new_boot_selection(...)` call with:

```r
  # What the run knows about itself. boot_bag() reads this rather than asking
  # the caller to retype it: a bag whose slentry was typed by hand can
  # disagree with the screen it describes, and the provenance table would
  # report the typed value as though the screen had used it.
  #
  # `call` cannot serve. match.call() omits every argument left at its
  # default, so a run at the default sle = 0.10 records nothing about sle.
  #
  # elapsed is CPU-elapsed seconds for this call only, converted to the
  # minutes boot_validate() expects. A chunked run sums them in
  # boot_pool_chunks(), which is why the unit matters here.
  control <- list(
    method       = ctrl$method,
    sle          = ctrl$sle,
    sls          = ctrl$sls,
    max_steps    = as.integer(ctrl$max_steps),
    fraction     = fraction,
    seed         = if (is.null(seed)) NA_real_ else as.numeric(seed),
    n_rows       = as.integer(n),
    n_terms      = length(terms_all),
    elapsed_mins = (proc.time()[["elapsed"]] - .t0) / 60,
    package      = as.character(utils::packageVersion("hvtiRbootstrap"))
  )

  new_boot_selection(m, n_rep = as.integer(n_rep),
                     n_attempts = attempts, call = match.call(),
                     control = control)
```

⚠️ **Check the local names before pasting.** This block reads `ctrl`,
`fraction`, `seed`, `n` and `terms_all` from `boot_select()`'s frame. `n` is
the row count and `terms_all` the offered non-base terms; both are already
bound where the matrix is built. If any name differs in the file you are
editing, use the file's name, not this one.

- [ ] **Step 5: Document the new field**

In `R/boot-select.R`, extend the `@return` block:

```r
#' @return An object of class \code{boot_selection}. \code{$coefficients} is a
#'   matrix with one row per valid replicate and one column per candidate term,
#'   \code{NA} where the term was not selected. \code{$control} records the
#'   run's own settings -- method, \code{sle}, \code{sls}, \code{max_steps},
#'   \code{fraction}, \code{seed}, row count, term count, elapsed minutes and
#'   the package version -- so that \code{\link{boot_bag}()} can build a
#'   provenance record from the run rather than from what a caller retypes.
```

- [ ] **Step 6: Run tests and document**

```bash
cd ~/Documents/GitHub/hvtiRbootstrap && Rscript -e 'devtools::document(); devtools::test()'
```

Expected: PASS, no failures. `print.boot_selection()` is unchanged and its
existing test still passes — the object gained a field, it did not lose one.

- [ ] **Step 7: Commit**

```bash
cd ~/Documents/GitHub/hvtiRbootstrap && git add R/boot-select.R R/boot-class.R man NAMESPACE tests/testthat/test-boot-select.R && git commit -m "feat(select): record the run's control settings on the returned object"
```

---

### Task A2: `boot_bag()`, the adapter

**Files:**
- Create: `R/boot-bag.R`
- Test: `tests/testthat/test-boot-bag.R`

**Interfaces:**
- Consumes: `x$control` from Task A1; `boot_summary()`, `boot_validate()`.
- Produces: `boot_bag(x, base_params, requested, manifest, dropped = NULL,
  usable = NULL)` returning a list that satisfies `boot_validate()`. Part B's
  three templates and the Task B2 harness call exactly this signature.

**Why these four arguments and no others.** `base_params`, `requested`,
`manifest` and `dropped` are the only facts `boot_select()` cannot know:
which terms are the base model rather than candidates, how many candidates
existed *before* the runner dropped any, what the built dataset was, and what
was dropped. `usable` is derivable and therefore derived — supplied only to be
**checked**, in the spirit of design §6.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-boot-bag.R`:

```r
# A small screen with a known answer, so the round-trip below is checkable by
# hand. Synthetic: no cohort data enters this package.
fx_selection <- function(n_rep = 20) {
  set.seed(11)
  n  <- 150
  x1 <- stats::rnorm(n)
  x2 <- stats::rnorm(n)
  df <- data.frame(y = 2 * x1 + stats::rnorm(n), x1 = x1, x2 = x2,
                   noise = stats::rnorm(n))
  boot_select(df, y ~ x1 + x2 + noise, fit_linear, n_rep = n_rep,
              sle = 0.10, sls = 0.05, seed = 42)
}

test_that("boot_bag() produces a bag the reporting layer accepts", {
  fit <- fx_selection()
  bag <- boot_bag(fit, base_params = "(Intercept)", requested = 5L,
                  manifest = list(sha256 = "abc123"))

  expect_silent(boot_validate(bag))
  expect_identical(bag$n_boot, 20L)
  expect_identical(bag$slentry, 0.10)
  expect_identical(bag$slstay, 0.05)
  expect_identical(bag$seed, 42)
  expect_identical(bag$n_rows, 150L)
  expect_identical(bag$requested, 5L)
  expect_identical(bag$usable, 3L)          # x1, x2, noise
  expect_identical(bag$boot$n_success, 20L)
  expect_identical(bag$boot$n_failed, fit$n_attempts - 20L)
})

test_that("the wide-to-long pivot round-trips exactly", {
  fit <- fx_selection()
  bag <- boot_bag(fit, base_params = "(Intercept)", requested = 5L,
                  manifest = list(sha256 = "abc123"))

  # The invariant that matters: the frequencies the report shows must be the
  # frequencies boot_summary() computes from the matrix. A pivot that lost a
  # replicate, or that wrote an NA as a row, would move them and nothing
  # downstream could see it.
  wide <- boot_summary(fit)
  wide <- wide[wide$variable != "(Intercept)", , drop = FALSE]
  freq <- boot_frequencies(bag)

  expect_setequal(freq$variable, wide$variable)
  expect_equal(freq$pct[order(freq$variable)],
               wide$pct[order(wide$variable)], tolerance = 1e-12)
  expect_equal(freq$n[order(freq$variable)],
               wide$n[order(wide$variable)])
})

test_that("boot_bag() carries no phase dimension", {
  fit <- fx_selection()
  bag <- boot_bag(fit, base_params = "(Intercept)", requested = 5L,
                  manifest = list(sha256 = "abc123"))

  # The whole reason bl, br and bc are thin. phase = NULL is the default and
  # must produce no phase column anywhere.
  expect_false("phase" %in% names(boot_frequencies(bag)))
  cm <- data.frame(variable = c("x1", "x2", "noise"),
                   concept = c("x", "x", "noise"),
                   stringsAsFactors = FALSE)
  expect_false("phase" %in% names(boot_concepts(bag, cm)))
  expect_identical(nrow(boot_dropped(bag)), 0L)
  expect_true(all(c("Distinct candidates ever selected",
                    "SD of the first free base parameter") %in%
                    boot_health(bag)$check))
})

test_that("an unseeded screen is refused, not given a blank seed", {
  set.seed(9)
  df <- data.frame(y = stats::rnorm(80), x1 = stats::rnorm(80))
  fit <- boot_select(df, y ~ x1, fit_linear, n_rep = 4)
  expect_error(
    boot_bag(fit, base_params = "(Intercept)", requested = 1L,
             manifest = list(sha256 = "a")),
    "did not record a seed"
  )
})

test_that("a boot_selection from 0.9.0 is refused by name", {
  fit <- fx_selection()
  fit$control <- NULL
  expect_error(
    boot_bag(fit, base_params = "(Intercept)", requested = 5L,
             manifest = list(sha256 = "a")),
    "predates"
  )
})

test_that("a usable count that disagrees with the screen is refused", {
  fit <- fx_selection()
  expect_error(
    boot_bag(fit, base_params = "(Intercept)", requested = 5L,
             manifest = list(sha256 = "a"), usable = 9L),
    "9 usable candidates"
  )
})

test_that("base_params must name a term the screen actually carries", {
  fit <- fx_selection()
  expect_error(
    boot_bag(fit, base_params = "not_a_term", requested = 5L,
             manifest = list(sha256 = "a")),
    "not among the screen's terms"
  )
})

test_that("dropped is carried through when supplied", {
  fit <- fx_selection()
  drp <- data.frame(variable = "constant_col", reason = "constant",
                    stringsAsFactors = FALSE)
  bag <- boot_bag(fit, base_params = "(Intercept)", requested = 6L,
                  manifest = list(sha256 = "a"), dropped = drp)
  expect_identical(nrow(boot_dropped(bag)), 1L)
})
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/Documents/GitHub/hvtiRbootstrap && Rscript -e 'devtools::test(filter = "boot-bag")'
```

Expected: FAIL, "could not find function \"boot_bag\"".

- [ ] **Step 3: Write `boot_bag()`**

Create `R/boot-bag.R`:

```r
#' A screen the reporting layer can read
#'
#' @description
#' Convert a [boot_select()] result into the bag that
#' [boot_validate()] accepts and every reporting function reads.
#'
#' @details
#' `boot_select()` returns a WIDE object: one row per replicate, one
#' column per term, `NA` where a term was not selected. The reporting
#' layer reads a LONG one, because it was extracted from a hazard runner that
#' writes long. Nothing converted between them, so the package's own screen
#' function could not reach its own report. This is that conversion.
#'
#' **The pivot drops `NA` rather than writing it.** That is not an
#' optimisation: `boot_frequencies()` counts a term's rows against
#' `n_boot`, so a row written for an unselected term would count as a
#' selection. The replicate count travels in `n_boot`, never in the row
#' count.
#'
#' Everything the run knows about itself comes from `x$control` rather
#' than from an argument, so a bag cannot claim an entry level the screen did
#' not use. The four arguments here are the facts `boot_select()` cannot
#' know: which terms are the base model, how many candidates existed before
#' the runner dropped any, what dataset was screened, and what was dropped.
#'
#' @param x A `boot_selection` from [boot_select()], run
#'   under 0.9.2 or later. An object from an earlier version carries no
#'   `$control` and is refused by name.
#' @param base_params Character. The terms that are the base model rather than
#'   candidates. They are excluded from every frequency, and the first of them
#'   is the parameter [boot_health()] watches for a zero standard
#'   deviation. Must name terms the screen carries.
#' @param requested Numeric. How many candidates the runner OFFERED, before it
#'   dropped any. Not derivable here: a candidate dropped before screening
#'   never became a column.
#' @param manifest A named list describing the dataset screened, indexed by
#'   name. `list(sha256 = ...)` at minimum.
#' @param dropped Optional data frame of candidates dropped before screening,
#'   as [boot_dropped()] reports it. Absent means nothing was
#'   dropped.
#' @param usable Optional numeric, checked rather than used. Supply it to
#'   assert the count the runner believed it screened; a disagreement with the
#'   screen's own term count is refused.
#'
#' @return A list carrying the fields [boot_validate()] requires:
#'   `n_boot`, `seed`, `slentry`, `slstay`,
#'   `base_params`, `requested`, `usable`, `n_rows`,
#'   `elapsed_mins`, `manifest`, `dropped` when supplied, and
#'   `boot` holding `replicates`, `summary`, `n_success`
#'   and `n_failed`. Validated before it is returned, so an invalid bag
#'   is never emitted.
#'
#' @seealso [boot_select()] for the screen,
#'   [boot_provenance()] and [boot_frequencies()] for
#'   what reads the result.
#'
#' @examples
#' set.seed(1)
#' n  <- 200
#' x1 <- rnorm(n)
#' df <- data.frame(y = 2 * x1 + rnorm(n), x1 = x1, x2 = rnorm(n))
#' fit <- boot_select(df, y ~ x1 + x2, fit_linear, n_rep = 10, seed = 42)
#' bag <- boot_bag(fit, base_params = "(Intercept)", requested = 2,
#'                 manifest = list(sha256 = "example"))
#' boot_frequencies(bag)
#'
#' @export
boot_bag <- function(x, base_params, requested, manifest, dropped = NULL,
                     usable = NULL) {
  if (!inherits(x, "boot_selection")) {
    stop("`x` must be a boot_selection from boot_select(), found ",
         class(x)[1L], ".", call. = FALSE)
  }
  ctl <- x$control
  if (!is.list(ctl)) {
    stop("This boot_selection predates hvtiRbootstrap 0.9.2 and carries no ",
         "`$control`, so the entry and stay levels, the seed and the row ",
         "count it ran under are not recoverable from it.\nRe-run the screen ",
         "under 0.9.2 or later.", call. = FALSE)
  }
  if (is.na(ctl$seed)) {
    stop("This screen did not record a seed, so the report it feeds could ",
         "not be reproduced and the provenance table would print a blank ",
         "where the seed belongs.\nRe-run boot_select() with `seed =`.",
         call. = FALSE)
  }

  m <- x$coefficients
  terms_seen <- colnames(m)
  if (!all(base_params %in% terms_seen)) {
    stop("`base_params` names ",
         paste(setdiff(base_params, terms_seen), collapse = ", "),
         ", which is not among the screen's terms. Every frequency below ",
         "excludes the base model, so a name that matches nothing excludes ",
         "nothing and reports the base model as a candidate.", call. = FALSE)
  }
  n_usable <- length(setdiff(terms_seen, base_params))
  if (!is.null(usable) && !identical(as.integer(usable), n_usable)) {
    stop("The runner reports ", as.integer(usable), " usable candidates; the ",
         "screen carries ", n_usable, ". One of the two is describing a ",
         "different run.", call. = FALSE)
  }

  # Long form, NA dropped. See @details: a row written for an unselected term
  # would be counted as a selection by boot_frequencies().
  idx <- which(!is.na(m), arr.ind = TRUE)
  reps <- data.frame(
    replicate = as.integer(idx[, "row"]),
    parameter = terms_seen[idx[, "col"]],
    estimate  = as.numeric(m[idx]),
    stringsAsFactors = FALSE
  )
  reps <- reps[order(reps$replicate, reps$parameter), , drop = FALSE]
  rownames(reps) <- NULL

  bag <- list(
    n_boot       = as.integer(x$n_rep),
    seed         = ctl$seed,
    slentry      = ctl$sle,
    slstay       = ctl$sls,
    base_params  = base_params,
    requested    = as.integer(requested),
    usable       = n_usable,
    n_rows       = as.integer(ctl$n_rows),
    elapsed_mins = ctl$elapsed_mins,
    manifest     = manifest,
    engine       = ctl$package,
    boot         = list(
      replicates = reps,
      summary    = boot_summary(x),
      n_success  = as.integer(x$n_rep),
      n_failed   = as.integer(x$n_attempts) - as.integer(x$n_rep)
    )
  )
  if (!is.null(dropped)) {
    bag$dropped <- dropped
  }

  # Validated on the way out, so this function cannot emit a bag that the
  # report will refuse three chunks into a render.
  boot_validate(bag)
  bag
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd ~/Documents/GitHub/hvtiRbootstrap && Rscript -e 'devtools::document(); devtools::test(filter = "boot-bag")'
```

Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/GitHub/hvtiRbootstrap && git add R/boot-bag.R man NAMESPACE tests/testthat/test-boot-bag.R && git commit -m "feat(bag): boot_bag() converts a boot_selection into a bag the report reads"
```

---

### Task A3: WITHDRAWN

⚠️ **Do not implement this task.** It planned to change `bag$dropped` to
`bag[["dropped"]]` in `boot_dropped()`, closing
[#21](https://github.com/ehrlinger/hvtiRbootstrap/issues/21).

[#23](https://github.com/ehrlinger/hvtiRbootstrap/pull/23) did that on
2026-09-01, before this plan's execution began, and did more: **every** optional
read is exact -- `dropped`, `free_sd`, `n_chunks`, `seeds`, `th_sha`,
`th_version` -- and `boot_validate()` now refuses a per-phase `free_sd`, closing
[#22](https://github.com/ehrlinger/hvtiRbootstrap/issues/22) as well. This plan
had argued #22 was out of reach for Phase 3. It was not; it was one commit away.

Part A is based on that PR (see the Part A header), so the fix arrives with the
base rather than being re-applied here. Nothing to do.

---

### Task A4: Release 0.9.2

**Files:**
- Modify: `DESCRIPTION` (Version, Date)
- Modify: `NEWS.md`

- [ ] **Step 1: Bump `DESCRIPTION`**

Set `Version: 0.9.2` and `Date: 2026-09-01`. #23 already moved it to
0.9.1; this is the next patch on top of that.

- [ ] **Step 2: Add the `NEWS.md` entry**

Insert above the `# hvtiRbootstrap 0.9.1` heading that #23 added:

```markdown
# hvtiRbootstrap 0.9.2

* **`boot_bag()` converts a `boot_select()` result into the bag the reporting
  layer reads.** The two ends of this package were built against different
  studies and had never met: `boot_select()` returns a wide coefficients
  matrix with no provenance, while `boot_validate()` and everything after it
  read a long-form bag written by a hazard runner. Nothing converted between
  them, so the package's own screen function could not reach its own report,
  and every study would have hand-written the pivot plus nine provenance
  fields. `boot_bag()` writes it once. The pivot drops `NA` rather than
  recording it, because a row written for an unselected term would be counted
  as a selection.

* **`boot_select()` records the run's own settings** on the returned object as
  `$control`: method, `sle`, `sls`, `max_steps`, `fraction`, seed, row count,
  term count, elapsed minutes and the package version. `boot_bag()` reads
  those rather than asking a caller to retype them, so a bag cannot claim an
  entry level the screen did not use. `$call` could not serve, because
  `match.call()` omits every argument left at its default.

```

- [ ] **Step 3: Full check**

```bash
cd ~/Documents/GitHub/hvtiRbootstrap && Rscript -e 'devtools::document(); devtools::test(); devtools::check()'
```

Expected: `devtools::check()` 0 errors, 0 warnings, 0 notes.

⚠️ **Read the `testthat` summary line inside the output, not the check mark
beside it.** A `skip_if_not()` is not a failure, and a green job can hide a
suite that skipped the tests you care about. The line to find is
`[ FAIL 0 | WARN 0 | SKIP n | PASS n ]`; state the SKIP count when reporting.

- [ ] **Step 4: Commit and open the PR**

```bash
cd ~/Documents/GitHub/hvtiRbootstrap && git add DESCRIPTION NEWS.md man && git commit -m "release: 0.9.2, the boot_bag() adapter" && git push -u origin feat/boot-bag-adapter && gh pr create --base main --title "boot_bag(): give the reporting layer a producer it can read" --body "Phase 3 of hvtiRtemplates batch 2a opens here: bl, br and bc cannot be thin templates until boot_select() output can reach the reporting layer. Builds on #23."
```

⚠️ **`--base main`, always.** A PR opened against another branch never gets
the Copilot review, and retargeting when a parent merges does not trigger it
either.

- [ ] **Step 5: Wait for the merge before starting Part B**

Part B's templates declare `hvtiRbootstrap (>= 0.9.2)`, so the RELEASE waits on
this one.

⚠️ **The render gate does not.** The templates never call `boot_bag()`; only a
runner does. A bag built by hand, or by the Part B harness with the pivot
inlined, renders them completely. Tasks B1 through B7 can therefore all be done
while Part A is blocked, and were. Only Task B8's PR waits, because CI resolves
`Remotes: ehrlinger/hvtiRbootstrap` against that repository's `main` and cannot
satisfy `>= 0.9.2` until it ships.

---

## Part A execution note, 2026-09-01

**Task A1 is written and passing; it is in the wrong place.**

The work itself is done and correct: `$control` recorded on the returned
object, `new_boot_selection()` widened with `control = NULL`, `@return`
documented, two tests. `devtools::test()` reported `FAIL 0 | WARN 0 | SKIP 0 |
PASS 274`.

⚠️ **That PASS count is not a clean measurement.** The working tree held
another session's uncommitted tests at the time, so the run covered files that
are not part of this task. Re-measure after the recovery below.

⚠️ **The commit landed on another branch.** A concurrent session switched the
shared working tree from `feat/boot-bag-adapter` to `fix/required-field-reads`
between the branch cut and the commit, so `a0894e4` sits on top of that
session's work and `feat/boot-bag-adapter` is still empty at `2cde608`. The
tree then reverted `R/boot-select.R` and `R/boot-class.R` under the task.
Nothing was lost; nothing of the other session's was touched.

**Recovery, once that session is finished** and #23 has settled:

1. Create the worktree named in the Part A header, based on #23.
2. `git cherry-pick a0894e4` into it.
3. The owner of `fix/required-field-reads` drops the stray commit.
4. Re-run `devtools::test()` in the worktree and record the real counts.
5. Resume at Task A2.

**The general lesson is in the Global Constraints**: a branch cut is a
point-in-time guess and only a worktree isolates. This plan warned about
concurrent sessions for `hvtiRtemplates` and then shared a working tree in
`hvtiRbootstrap`.

---

# Part B — `hvtiRtemplates` 1.0.19

Work in `~/Documents/GitHub/hvtiRtemplates` on a branch
`feat/batch-2a-phase-3`, cut from `origin/main`.

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git fetch origin && git checkout -b feat/batch-2a-phase-3 origin/main
```

⚠️ **Cut from `origin/main`, not local `main`.** Sessions ship to this
repository concurrently and local `main` is stale by default.

---

### Task B1: Record the gap in the design

The design is the record. A plan that fixes something the design still gets
wrong leaves the next reader working from the wrong document.

**Files:**
- Modify: `dev/specs/2026-08-31-batch-2a-bootstrap-family-design.md`

- [ ] **Step 1: Add §4.2**

After §4.1 ("Phase-awareness is not optional"), insert:

```markdown
### 4.2 The reporting layer had no producer, and this was found in Phase 3

⚠️ **Added 2026-09-01, after Phases 1 and 2 shipped.** §4 above describes the
reading side correctly and says nothing about the writing side, which is where
the gap was.

`boot_validate()` requires a long-form bag: `boot$replicates` carries one row
per selected (replicate, term) pair, with an unselected term absent. That
shape is written by TemporalHazard's hazard runner, which is why `bh` works.

`boot_select()` -- this package's own entry point, and the function a `bl`,
`br` or `bc` runner calls -- returns a WIDE `boot_selection`: a coefficients
matrix, two integers and an unevaluated call. It takes `sle`, `sls` and `seed`
and records none of them structurally. Nothing pivoted wide to long.

So the layer Phase 1 extracted could not be reached from the screen function
that feeds it. Written as designed, each study would hand-write the pivot plus
nine provenance fields, and the three thin templates would ship three copies
of an instruction to do so -- the hand-sync problem the extraction exists to
remove, one layer down.

**This is §6's failure shape with one difference that makes it worse: the
artifact is produced by the SAME package, at the other end of it.** The two
ends were built against different studies and never met. No test in either
repository composed them, because each end had its own fixtures.

**Resolution:** `hvtiRbootstrap` 0.9.2 adds `boot_bag()`, and `boot_select()`
records a `$control` list so the bag's provenance comes from the run rather
than from what a caller retypes. Phase 3 therefore opens upstream, as Phase 1
did.
```

- [ ] **Step 2: Restate §7 Phase 3 and §8**

In §7, replace the Phase 3 paragraph with:

```markdown
**Phase 3** -- `hvtiRbootstrap` gains `boot_bag()` and ships as 0.9.2 (§4.2),
then `bl`, `br` and `bc` ship as thin templates. Ordinals are assigned from
the ledger as free minors in `analyses`, **never recomputed from taxonomy row
position** (`04.06` is retired and cannot be reissued): `bl` 04.02, `br`
04.03, `bc` 04.04.
```

In §8, replace the `bl`/`br`/`bc` bullet with:

```markdown
- `bl`, `br`, `bc` each: renders against a bag built by `boot_bag()`; own
  `.lintr` **file** key; `edit-guard` chunk; exactly one `^ENDPOINT` and one
  `^TYPE` line; no study identifiers; README row; ledger row `shipped` with
  its assigned ordinal.
  ⚠️ **The render gate for this phase is a screen we run, not a screen a
  study ran, and that is a weaker gate than `bh` got.** `bh` rendered against
  a real 25-chunk bag a study had produced (§5). Searched on 2026-09-01
  across 876 `analyses/` directories at two of the share's directory depths:
  **no R job found calls `boot_select()`**, so no `bl`, `br` or `bc` bag was
  available to render against. ⚠️ The share nests deeper than those two
  levels, so read this as "none found", not "none exists". What does exist is
  one study set up as an hvtiR project -- `_study.yml`, a built dataset, a
  cohort with a survival endpoint -- so the gate screens **real data with real
  variable names, a real correlation structure and a real pool size**, and
  `read_built()` and `set_path()` are exercised rather than stubbed. What it
  still does not cover is a pool and a dropped set a study author chose.
  Stated rather than resolved.
```

- [ ] **Step 3: Update the header status**

Change `**Status:** designed, not started` to
`**Status:** Phases 0-2 shipped; Phase 3 in progress, see §4.2`.

- [ ] **Step 4: Verify the spec-count gate still passes**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && python3 dev/specs/artifacts/check-spec-counts.py && python3 dev/specs/artifacts/check-flow-counts.py && python3 dev/specs/artifacts/check-roadmap-counts.py
```

Expected: all three exit 0. This edit changes no anchored count; run them so
that a later failure is attributable to a later task.

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git add dev/specs/2026-08-31-batch-2a-bootstrap-family-design.md && git commit -m "spec: record the reporting layer's missing producer, found in phase 3"
```

---

### Task B2: The render-gate harness

Design §5 made a real render a required step of this batch, not a
preliminary, because `bh` shipped in three releases with a render-blocker in
it. This is that step for Phase 3.

⚠️ **What is available, searched on the share on 2026-09-01, not assumed.**
No R job found calls `boot_select()`, so **there is no `bl`, `br` or `bc` bag
to render against**. The `bl` and `br` "R exemplars" in the census are SAS
runs — a `bl.*_summary.lst` beside a `tp.bl.*.sas` — not R jobs.

⚠️ **The search was not exhaustive and the plan should not read as though it
were.** Studies sit at more than one directory depth; two levels were covered
and deeper ones were not. "None found", not "none exists".

**So the gate runs a screen rather than reading one, and runs it against a
study's real built dataset.** That buys real variable names, a real
correlation structure, a real row count, and a `read_built()` that returns
data instead of erroring. It does not buy a candidate pool a study author
chose — **that is what Part C adds**, for `bl` and `br`, by matching an
existing `%bootreg` job's pool and comparing against its output. Run Part B's
gate first anyway: it is minutes, Part C is a long compute, and a template
that cannot render should not be found out by a 500-replicate screen.

⚠️ **Nothing is written into the study tree.** Copy the built dataset and
`_study.yml` into a scratch project outside it and render there, read-only,
exactly as design §5 describes for `bh`. The share holds live research data
and this repository is public.

**Files:**
- Create: `dev/specs/artifacts/2026-09-01-phase-3-render-gate.R`

**Interfaces:**
- Consumes: `boot_bag()` from Task A2.
- Produces: an `.rds` under `<scratch>/estimates/`, in the layout
  `set_path("estimates", ...)` expects, plus a printed summary. Tasks B3, B4
  and B5 render against it.

⚠️ **No study path, study name or variable name may appear in the committed
script.** The study root arrives as an argument and the candidate pool is
derived from the data at run time. `test-new-job.R` asserts that no shipped
file matches `/studies/`, a study name or a built-dataset filename; this
script lives under `dev/` and is not covered by that test, which is a reason
to be more careful here, not less.

- [ ] **Step 1: Stage a scratch project from a study, without touching it**

```bash
STUDY=<the study root on the share>            # not recorded in this repo
GATE=/tmp/phase3-gate
mkdir -p "$GATE/datasets" "$GATE/estimates" "$GATE/job"
cp "$STUDY/_study.yml" "$GATE/_study.yml"
cp "$STUDY/datasets/$(Rscript -e 'cat(yaml::read_yaml(Sys.getenv("CFG"))$built)' CFG="$STUDY/_study.yml")" "$GATE/datasets/"
printf 'project:\n  type: default\n' > "$GATE/_quarto.yml"
```

⚠️ **Every copy is one-way and the source is never opened for writing.** That
is the property that matters: the share holds live research data.

⚠️ **Do NOT `chmod a-w` the staged `datasets/`, which an earlier version of
this step did.** `read_built()` writes a `built.schema.csv` beside the data on
first read, so a read-only copy fails with a permission error from inside
`read_built()` that names a temp file and not the cause. The staged copy is
scratch; leave it writable. The study is protected by never writing to it, not
by the mode bits on a copy of it.

- [ ] **Step 2: Write the harness**

Create `dev/specs/artifacts/2026-09-01-phase-3-render-gate.R`:

```r
# Produce a bootstrap screen that 04.02-bl, 04.03-br and 04.04-bc can be
# rendered against, before any study has run one.
#
# No R job found on the share calls boot_select(), so there is no bl, br or
# bc bag to read. This runs a screen instead. Given a staged study project it screens
# that study's real built dataset -- real names, real correlations, real row
# count -- which is what makes read_built() and pool_collinear_pairs() render
# rather than error. Given no project it falls back to simulated columns, so
# the gate still runs when the share is not mounted.
#
# What neither mode covers is a candidate pool and a dropped set a study
# author chose. Design section 8 says so; do not let this script's success
# read as more than it is.
#
# NO STUDY PATH, STUDY NAME OR VARIABLE NAME IS RECORDED HERE. The project
# root arrives as an argument and the pool is derived from the data.
#
# Usage:
#   Rscript 2026-09-01-phase-3-render-gate.R <project-dir> <model> [<prefix>]
#     <model> is linear, logistic or cox
#     <prefix> defaults to "bagging"
# Writes <project-dir>/estimates/<prefix>.rds.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2L) {
  stop("Usage: <project-dir> <model:linear|logistic|cox> [<prefix>]",
       call. = FALSE)
}
proj   <- args[[1L]]
model  <- match.arg(args[[2L]], c("linear", "logistic", "cox"))
prefix <- if (length(args) >= 3L) args[[3L]] else "bagging"

suppressPackageStartupMessages({
  library(hvtiRbootstrap)
  library(hvtiRutilities)
})
if (utils::packageVersion("hvtiRbootstrap") < "0.9.2") {
  stop("boot_bag() lands in 0.9.2; ", utils::packageVersion("hvtiRbootstrap"),
       " is installed.", call. = FALSE)
}
dir.create(file.path(proj, "estimates"), recursive = TRUE,
           showWarnings = FALSE)

# Real data when the project carries a study manifest, simulated otherwise.
# Announced either way: a gate that silently degraded to simulation would
# report the weaker run as though it were the stronger one.
have_study <- file.exists(file.path(proj, "_study.yml"))
if (have_study) {
  cfg <- study_config(proj)
  d   <- read_built(cfg)
  cat("mode        : real built dataset\n")
} else {
  set.seed(20260901)
  n   <- 400
  age <- stats::rnorm(n, 60, 10)
  bmi <- stats::rnorm(n, 27, 4)
  d <- data.frame(age = age, ln_age = log(age), age2 = age^2,
                  bmi = bmi, ln_bmi = log(bmi),
                  noise1 = stats::rnorm(n), noise2 = stats::rnorm(n))
  lp <- 0.05 * (d$age - 60) + 0.12 * (d$bmi - 27)
  d$.y_cont <- lp + stats::rnorm(n)
  d$.y_bin  <- stats::rbinom(n, 1, stats::plogis(lp))
  d$.t      <- stats::rexp(n, rate = exp(lp) / 50)
  d$.e      <- stats::rbinom(n, 1, 0.7)
  cfg <- list(cohort = list(event = ".e", time = ".t"))
  cat("mode        : simulated, no study project at ", proj, "\n", sep = "")
}

# The pool is DERIVED, never named: numeric, non-constant, not an outcome.
# Naming columns here would put a study's variable names in a public repo, and
# deriving them also means the pool is whatever the data actually offers.
outcomes <- unlist(cfg$cohort[c("event", "time")], use.names = FALSE)
num <- vapply(d, is.numeric, logical(1))
ok  <- vapply(d, function(x) length(unique(x[!is.na(x)])) > 2L, logical(1))
cand <- setdiff(names(d)[num & ok], outcomes)
cand <- cand[seq_len(min(12L, length(cand)))]   # 12 keeps the gate to minutes
if (length(cand) < 3L) {
  stop("Only ", length(cand), " usable candidate columns; the concept and ",
       "cluster tables need more than that to show anything.", call. = FALSE)
}

# The outcome each fitter needs, taken from the manifest rather than guessed.
rhs <- paste(cand, collapse = " + ")
spec <- switch(
  model,
  linear   = list(f = stats::as.formula(paste(cand[[1L]], "~",
                                              paste(cand[-1L],
                                                    collapse = " + "))),
                  fitter = fit_linear),
  logistic = list(f = stats::as.formula(paste(outcomes[[1L]], "~", rhs)),
                  fitter = fit_logistic),
  cox      = list(f = stats::as.formula(
                    paste0("survival::Surv(", outcomes[[2L]], ", ",
                           outcomes[[1L]], ") ~ ", rhs)),
                  fitter = fit_cox)
)

# n_rep is small on purpose. This proves the templates render; it does not
# claim any frequency is stable. A study's own run is where n_rep matters.
fit <- boot_select(d, spec$f, spec$fitter, n_rep = 60, sle = 0.10,
                   sls = 0.05, seed = 4242)

# A Cox model has no intercept, so base_params cannot be "(Intercept)" there.
# Taken from the screen's own terms rather than written in.
base <- if (model == "cox") colnames(fit$coefficients)[[1L]] else "(Intercept)"

bag <- boot_bag(
  fit,
  base_params = base,
  requested   = length(cand),
  manifest    = list(sha256 = "render-gate, screen run by the gate")
)

out <- file.path(proj, "estimates", paste0(prefix, ".rds"))
saveRDS(bag, out)

freq <- boot_frequencies(bag, threshold = 50)
cat("wrote       : ", out, "\n", sep = "")
cat("model       : ", model, "\n", sep = "")
cat("n_boot      : ", bag$n_boot, "\n", sep = "")
cat("n_rows      : ", bag$n_rows, "\n", sep = "")
cat("candidates  : ", nrow(freq), "\n", sep = "")
cat("base param  : ", base, "\n", sep = "")
cat("phase column: ", "phase" %in% names(freq), "  (must be FALSE)\n", sep = "")
```

- [ ] **Step 3: Run it for each model**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && for m in linear logistic cox; do Rscript dev/specs/artifacts/2026-09-01-phase-3-render-gate.R /tmp/phase3-gate $m; done
```

Expected: three runs, each reporting `mode : real built dataset`,
`phase column: FALSE  (must be FALSE)` and a nonzero candidate count. The Cox
run's `base param` must **not** be `(Intercept)`.

A `phase column: TRUE` means `boot_frequencies()` grew a phase column under
`phase = NULL`; stop and revisit Task A2 before any template is written. A
`mode : simulated` line means the staging in Step 1 did not take.

⚠️ Each model overwrites `estimates/bagging.rds`. Re-run the model whose
template you are about to render, or pass a distinct prefix per model and set
`BOOT_FILE` in the template to match.

- [ ] **Step 4: Commit**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git add dev/specs/artifacts/2026-09-01-phase-3-render-gate.R && git commit -m "dev: a render-gate harness that screens real built data for phase 3"
```

⚠️ **Before committing, read the file for anything that names a study.**
`git diff --cached` and check the copy in Step 1 did not leave a path in a
comment.

---

### Task B3: `04.02-bl.qmd`, the bootstrap logistic template

**Files:**
- Create: `inst/templates/analyses/04.02-bl.qmd`
- Modify: `.lintr` (add the file key)

**Interfaces:**
- Consumes: `boot_bag()` (A2), the harness (B2).
- Produces: the file `04.03-br.qmd` and `04.04-bc.qmd` are derived from in
  Tasks B4 and B5. Get this one right; the other two are its diff.

**How to build it.** Start from `inst/templates/analyses/04.05-bh.qmd` and
apply the changes below. Copying is correct here and duplication is not the
worry it was at design time: the ~700 lines being copied are prose,
`kable()`s and `EDIT:` markers, which is exactly the half the design decided
the templates own (§4). The computation is not being copied; it lives in the
package.

```bash
cd ~/Documents/GitHub/hvtiRtemplates && cp inst/templates/analyses/04.05-bh.qmd inst/templates/analyses/04.02-bl.qmd
```

- [ ] **Step 1: Retitle and re-narrate the header**

Replace the YAML title and the opening narrative (lines 1-40 of the copy) so
it describes a logistic screen. Keep the `format:` block **verbatim** — a
template carries its own and must not inherit from a project `_quarto.yml`.

The lead paragraph, replacing `bh`'s:

```markdown
This job reports a bootstrap variable selection screen over a **logistic**
model: how often each candidate survived stepwise selection across
resamples, how much of that figure is Monte-Carlo noise, and which candidates
the screen never saw. It does not run the screen. A companion runner does
that and writes the bag this file reads.

A selection frequency is an estimate, not a count of something fixed. Every
table below is built to keep that visible, because the decision this job
exists to support is which side of a retention threshold a variable falls on,
and that decision is the part resampling noise moves.
```

- [ ] **Step 2: Change the version floor and the library block**

In the `setup` chunk, drop `library(TemporalHazard)` — a logistic screen does
not touch it — and raise the floor:

```r
suppressPackageStartupMessages({
  library(hvtiRbootstrap)
  library(hvtiRutilities)
  library(ggplot2)
})

# boot_bag() lands in 0.9.2, and without it a boot_select() result cannot be
# read by anything below. A study on 0.9.0 otherwise gets "could not find
# function boot_bag" from inside its runner, one file away from this one, and
# the message names the symbol without naming the release that carries it.
if (utils::packageVersion("hvtiRbootstrap") < "0.9.2") {
  stop("This report needs hvtiRbootstrap >= 0.9.2; ",
       utils::packageVersion("hvtiRbootstrap"), " is installed. boot_bag() ",
       "converts a boot_select() screen into the bag this report reads, and ",
       "nothing below 0.9.2 has such a function.\nUpdate it, then re-render.",
       call. = FALSE)
}
```

- [ ] **Step 3: Set `ENDPOINT` and `TYPE`**

Exactly one `^ENDPOINT <- ` line and one `^TYPE <- ` line, unchanged in form
from `bh`'s. `new_job()` substitutes both after copying and hard-stops if
either is missing, duplicated or moved.

- [ ] **Step 4: Simplify the screen-reading chunks**

`bh` pools chunks because a hazard screen is days of compute. A logistic
screen over a study pool is minutes, so the default is a single file. Replace
the `EXPECT_CHUNKS` / `BOOT_PREFIX` / chunk-pooling chunks with:

```r
# EDIT: what this run was LAUNCHED as, not what happens to be on disk.
#
# A render partway through a run produces a report that is wrong in no visible
# way: every health check passes, every frequency is honestly computed, and
# only the denominator is not the intended one. This number is the only thing
# that can tell the difference.
EXPECT_BOOT <- 1000L

# EDIT: the file your runner wrote its screen to, under this set's estimates
# directory. It must match the runner exactly.
BOOT_FILE <- "bagging.rds"
```

and the read:

```r
# The screen is not run here. It is read.
#
# boot_select() writes nothing until it returns, so a run that dies partway
# leaves nothing at all. Keeping the run in a companion file means a failed
# render costs a re-render, not a re-run.
.single_file <- set_path("estimates", BOOT_FILE)
if (!file.exists(.single_file)) {
  stop("No screen found at ", .single_file, ". This report reads a bag your ",
       "runner wrote with boot_bag(); it does not run the screen.\nRun the ",
       "companion runner first, or correct BOOT_FILE.", call. = FALSE)
}
bag <- readRDS(.single_file)
.chunk_files <- character(0)

# A run split across chunks is still supported: pool with
# hvtiRbootstrap::boot_pool_chunks() in your runner and write the pooled bag
# to BOOT_FILE. Pooling belongs to the runner, because only the runner knows
# how many chunks it launched.
shortfall <- boot_shortfall(bag, expect_chunks = 1L, expect_boot = EXPECT_BOOT)
if (!is.null(shortfall)) {
  cat(shortfall, "\n")
}
```

⚠️ Keep `.single_file` and `.chunk_files` bound under these exact names. The
`save` chunk at the end of the file reads both when it checks that the report
is not about to overwrite the screen it just read.

- [ ] **Step 5: Set `PHASE_OF` to `NULL` and drop every phase column**

Replace `bh`'s `PHASE_OF` block in the `criteria` chunk with:

```r
# A logistic screen has no phases: a candidate is offered once, so one term is
# one screening decision and there is nothing to split a term name on.
#
# boot_frequencies() and boot_concepts() take phase = NULL for exactly this
# case, and it is the same code path bh drives with a splitting rule. Do NOT
# supply a rule here to "be safe": a rule that matches nothing still adds a
# phase column of empty strings, and every table below would then group by a
# column that says nothing.
PHASE_OF <- NULL
```

Then remove `phase` from every column selection and ordering. The exact
sites, by their `bh` line numbers:

| `bh` line | change |
|---|---|
| 369 | `as.data.frame(table(reason = dropped$reason))` |
| 484-485 | `boot_frequencies(bag, phase = PHASE_OF, threshold = RETAIN_PCT)`, then `freq[, c("variable", "n", "pct", "mc_error", "near_threshold")]` |
| 495 | `retained[, c("variable", "n", "pct", "mc_error", "near_threshold")]` |
| 538-541 | order by `by_concept$concept` then `-by_concept$pct`; select `c("concept", "variable", "representative", "pct", "mc_error")` |
| 569-570 | keep `phase = PHASE_OF`; select `c("concept", "n_forms", "pct_any", "best_form_pct", "spread", "retained")` |
| 590 | `cat("No concept had more than one form retained.\n")` |
| 705 | delete the `facet_wrap(~phase, scales = "free_y") +` line |

⚠️ **`dropped$phase` at line 369 is a different question from `PHASE_OF`.**
`boot_dropped()` takes no phase argument and returns whatever columns the
runner wrote. A single-phase runner writes no `phase` column, and
`table(phase = dropped$phase, ...)` on an absent column errors. Removing it
is correct here; a runner that does write one still has it in the detail
table below.

- [ ] **Step 5b: Rewrite the health chunk. Two of `bh`'s warnings are FALSE
      here.**

⚠️ **This plan originally had no such step**, having assumed the health section
transferred unchanged. It does not, and copying it tells a study author
something untrue about the function they are calling.

`bh`'s chunk instructs: *"EDIT: the candidate pool, written LITERALLY in your
runner's formula. Not in a variable, not via as.formula() or reformulate()"*,
because `hzr_bootstrap()` rewrites the stored formula per replicate and a
symbol does not survive that rewrite. **`boot_select()` does not have that
problem.** Its fitters evaluate through `.fit_in_env()`
(`hvtiRbootstrap/R/fitters.R`), which builds a fresh environment and binds
`formula` and `data` into it, which is exactly where `step()`'s `update()`
looks. Verified against 0.9.1 rather than reasoned about:

```r
f <- y ~ x1 + x2 + noise
a <- boot_select(d, f, fit_logistic, n_rep = 20, seed = 1)
b <- boot_select(d, y ~ x1 + x2 + noise, fit_logistic, n_rep = 20, seed = 1)
identical(a$coefficients, b$coefficients)   # TRUE
```

Replace the comment with one saying a variable-held formula is fine here, why,
and that `bh` warns the opposite for a reason that does not apply.

**Both refusals stay, and both diagnoses change.** `boot_health()` still cannot
refuse for itself, so the template's two `stop()` calls remain. But `bh`'s
messages diagnose hazard failures. Rewrite them for what actually produces
these states under `boot_select()`:

- *Selected nothing*: the runner passed `select = "none"` so nothing was ever a
  candidate; `sle` is far too strict for the pool; or `base_params` in the
  `boot_bag()` call names the whole model, subtracting every term from the
  frequencies.
- *SD exactly zero*: a bootstrap that resamples nothing. Check the runner was
  given the cohort rather than a single row, and that `boot_bag()` was handed
  the screen it thinks it was.

⚠️ Keep the `.want` label-drift guard exactly as `bh` has it. The refusals match
`boot_health()`'s checks by NAME, so a rename upstream makes both `%in%` tests
`FALSE` and deletes the guards silently rather than breaking them.

- [ ] **Step 6: Rewrite the clusters chunk's `EDIT:` block**

`bh`'s members are phase-qualified. Replace with:

```r
# EDIT: your clusters, one per concept you want reported. There is no sensible
# default: which concepts are worth clustering is a statement about your
# candidate pool, not about logistic regression.
#
# Members are bare variable names, not phase-qualified: this screen offers
# each candidate once. Naming a term no replicate carries is refused rather
# than reported as 0%, so a typo that grouped nothing cannot read as a concept
# nobody selected.
CLUSTERS <- list(
  Age = c("age", "ln_age")
)
```

- [ ] **Step 7: Rewrite the `save` chunk's filename and comment**

```r
report_file <- set_path("estimates", "bl-report.rds")
```

Keep the overwrite guard verbatim, and replace the comment sentence naming
`hzr_bootstrap()` with:

```r
# NOT BOOT_FILE. The run's INPUT is that name, so writing the report there
# overwrites the screen it just read. Checked rather than assumed, because
# BOOT_FILE is an edit point and the failure destroys the run instead of
# erroring.
```

Drop the `saveRDS()` list's `expect_chunks = EXPECT_CHUNKS` element and keep
`expect_boot = EXPECT_BOOT`.

- [ ] **Step 8: Add the `.lintr` file key**

In `.lintr`, inside `exclusions: list(`, after the `04.05-bh.qmd` entry:

```r
    "inst/templates/analyses/04.02-bl.qmd" = list(
      object_name_linter = Inf,
      commented_code_linter = Inf,
      object_usage_linter = Inf
    ),
```

- [ ] **Step 9: Lint and render**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && Rscript -e 'lintr::lint_package()'
```

Expected: no lints. Then render inside the staged gate project from Task B2:

```bash
cd ~/Documents/GitHub/hvtiRtemplates && Rscript dev/specs/artifacts/2026-09-01-phase-3-render-gate.R /tmp/phase3-gate logistic && cp inst/templates/analyses/04.02-bl.qmd /tmp/phase3-gate/job/ && cd /tmp/phase3-gate && HVTI_TEMPLATE_DRAFT=1 quarto render job/04.02-bl.qmd --to markdown
```

⚠️ **`--to markdown`, not `gfm`.** The two writers differ by hundreds of
lines of pure writer noise, and a gate whose diff is mostly noise gets waved
through.

Expected: the render completes. The DRAFT banner reports the unresolved
`EDIT:` markers, which is correct for an unedited template. Then read the
rendered `.md` and confirm all four:

1. no table carries a `phase` column;
2. the figure has no facet strip;
3. the `collinear` chunk produced a table or the explicit
   "No pair of screened candidates correlates" line — **not** an error.
   `read_built()` resolves here because the gate project carries `_study.yml`
   and the built dataset, which is the whole reason Task B2 stages a project
   rather than a bare `.rds`;
4. the health table's two refusal rows are present and passing.

⚠️ **`CLUSTERS` and the concept map will not match the gate data**, whose
variable names are the study's, not this template's example. A cluster naming
a term no replicate carries is **refused** by `boot_clusters()`, by design.
Set `CLUSTERS` to a pair of names from the gate run's frequency table for the
render, and **restore the template's example before committing**.

- [ ] **Step 10: Commit**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git add inst/templates/analyses/04.02-bl.qmd .lintr && git commit -m "feat(bl): bootstrap logistic template, 04.02, reporting through hvtiRbootstrap"
```

---

### Task B4: `04.03-br.qmd`, the bootstrap regression template

**Files:**
- Create: `inst/templates/analyses/04.03-br.qmd`
- Modify: `.lintr`

**Interfaces:**
- Consumes: `04.02-bl.qmd` from Task B3, which is the base.
- Produces: nothing later tasks read beyond the ledger and README rows.

```bash
cd ~/Documents/GitHub/hvtiRtemplates && cp inst/templates/analyses/04.02-bl.qmd inst/templates/analyses/04.03-br.qmd
```

- [ ] **Step 1: Change what a linear screen changes, and nothing else**

Four edits, and they are the whole diff from `bl`:

1. Title and lead paragraph: "a **linear** model" rather than "a
   **logistic** model".
2. The `criteria` chunk's `EDIT:` comment on `RETAIN_PCT`: keep the text,
   the reliability-cutoff argument is model-independent.
3. The `save` chunk: `set_path("estimates", "br-report.rds")`.
4. Add this paragraph after the frequency-is-an-estimate section, because it
   is the one thing a linear screen makes worse:

```markdown
⚠️ **A linear screen's frequencies move with the outcome's scale.** Stepwise
entry and stay are p-value thresholds, and a p-value on a continuous outcome
responds to residual variance in a way a binary outcome's does not. Two runs
of the same pool against the same cohort, one on a raw outcome and one on a
transformed one, are not comparable screens and their retained sets should not
be read against each other.
```

⚠️ **Do not "improve" anything else while copying.** `bl` and `br` differing
by four edits is what makes a future fix to one applicable to the other by
inspection. A reworded comment costs that.

- [ ] **Step 2: Add the `.lintr` file key**

```r
    "inst/templates/analyses/04.03-br.qmd" = list(
      object_name_linter = Inf,
      commented_code_linter = Inf,
      object_usage_linter = Inf
    ),
```

- [ ] **Step 3: Lint and render**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && Rscript -e 'lintr::lint_package()'
```

Then rebuild the gate bag for a linear screen and render as in Task B3
Step 9, substituting `04.03-br.qmd`:

```bash
cd ~/Documents/GitHub/hvtiRtemplates && Rscript dev/specs/artifacts/2026-09-01-phase-3-render-gate.R /tmp/phase3-gate linear && cp inst/templates/analyses/04.03-br.qmd /tmp/phase3-gate/job/ && cd /tmp/phase3-gate && HVTI_TEMPLATE_DRAFT=1 quarto render job/04.03-br.qmd --to markdown
```

Expected: no lints; the render completes; all four checks from Task B3
Step 9 pass.

- [ ] **Step 4: Verify the diff from `bl` is exactly what you intended**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && diff inst/templates/analyses/04.02-bl.qmd inst/templates/analyses/04.03-br.qmd
```

Expected: **ten** hunks, matching Step 1.

⚠️ **This plan said four, and told you to revert a fifth as an accidental
edit.** That instruction would have reverted correct changes. `bl` does not
merely say "logistic" in its title: it names its companion model job (`lm`,
which becomes `rm`), the fitter its runner calls (`fit_logistic`, which becomes
`fit_linear`), and its own report file (`bl-report.rds`). Each of those is a
real difference between the two templates. Count the hunks against Step 1's
list rather than against a number.

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git add inst/templates/analyses/04.03-br.qmd .lintr && git commit -m "feat(br): bootstrap linear regression template, 04.03"
```

---

### Task B5: `04.04-bc.qmd`, the bootstrap Cox template

**Files:**
- Create: `inst/templates/analyses/04.04-bc.qmd`
- Modify: `.lintr`

**Interfaces:**
- Consumes: `04.02-bl.qmd` from Task B3.
- Produces: nothing later tasks read beyond the ledger and README rows.

⚠️ **`bc` has no exemplar study and no SAS template.** It is in this batch
because `fit_cox()` exists, which inverts the reading the SAS counts gave
(design §2.3). No study has ever run one, so the Task B2 gate render is the
only evidence this file works, and the README and ledger must say so.

```bash
cd ~/Documents/GitHub/hvtiRtemplates && cp inst/templates/analyses/04.02-bl.qmd inst/templates/analyses/04.04-bc.qmd
```

- [ ] **Step 1: Retitle and re-narrate**

"a **Cox proportional hazards** model" in the lead paragraph.

- [ ] **Step 2: Change the base-parameter guidance**

A Cox model has no intercept, so `base_params = "(Intercept)"` — the value
`bl` and `br` runners use — names nothing, and `boot_bag()` refuses it. That
refusal is correct and the template must say so before the author meets it:

```markdown
⚠️ **A Cox model has no intercept, so the base model is whatever terms you
force into every replicate.** `boot_bag()` refuses a `base_params` naming a
term the screen does not carry, which is what `"(Intercept)"` copied from a
logistic runner does here. Name the forced terms instead. If nothing is
forced, `boot_health()`'s standard-deviation check has no parameter to watch
and reports `NA`: the check that catches a bootstrap which refit nothing is
then not running, and a screen where every frequency is 100% would render
green.
```

Place it immediately above the `health` section, where the check it describes
is run.

- [ ] **Step 3: Change the save filename**

```r
report_file <- set_path("estimates", "bc-report.rds")
```

- [ ] **Step 4: Add the `.lintr` file key**

```r
    "inst/templates/analyses/04.04-bc.qmd" = list(
      object_name_linter = Inf,
      commented_code_linter = Inf,
      object_usage_linter = Inf
    ),
```

- [ ] **Step 5: Lint, and render against a Cox screen**

The gate study's manifest declares a survival endpoint, so the harness screens
a real one:

```bash
cd ~/Documents/GitHub/hvtiRtemplates && Rscript -e 'lintr::lint_package()' && Rscript dev/specs/artifacts/2026-09-01-phase-3-render-gate.R /tmp/phase3-gate cox && cp inst/templates/analyses/04.04-bc.qmd /tmp/phase3-gate/job/ && cd /tmp/phase3-gate && HVTI_TEMPLATE_DRAFT=1 quarto render job/04.04-bc.qmd --to markdown
```

Expected: no lints; the harness reports a `base param` that is **not**
`(Intercept)`; the render completes and passes all four checks from Task B3
Step 9.

⚠️ **This is the check `bc` most needs.** It has no exemplar study, so this
render is the only evidence the file works at all — and it is the one place
the no-intercept problem from Step 2 shows up as behaviour rather than as
prose. If the harness's `base param` line reads `(Intercept)`, `fit_cox()`
returned one and Step 2's warning is wrong; fix the warning, not the harness.

- [ ] **Step 6: Commit**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git add inst/templates/analyses/04.04-bc.qmd .lintr && git commit -m "feat(bc): bootstrap Cox template, 04.04, no exemplar study"
```

---

### Task B6: The structural test

The existing `bh` test asserts that template reports through the package
rather than its own copy. Three more templates make that assertion worth
generalising, and adds one the `bh` test cannot make: these three must carry
**no** phase handling at all.

**Files:**
- Modify: `tests/testthat/test-templates.R`

**Interfaces:**
- Consumes: `template_path(prefix)` — a **bare prefix**, not a
  folder-qualified path. `template_path("analyses/04.02-bl.qmd")` errors with
  "unknown template".

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-templates.R`:

```r
test_that("the thin bootstrap templates report through hvtiRbootstrap", {
  for (prefix in c("bl", "br", "bc")) {
    src <- readLines(template_path(prefix), warn = FALSE)
    # Comments stripped first. These templates NARRATE the reporting layer --
    # the setup chunk's version-floor comment names boot_bag() -- so matching
    # raw source would let a hand-edit delete a live call, leave the comment,
    # and keep this green.
    code <- sub("#.*$", "", src)

    for (fn in c("boot_validate", "boot_provenance", "boot_seeds",
                 "boot_dropped", "boot_health", "boot_frequencies",
                 "boot_concepts")) {
      expect_true(any(grepl(paste0(fn, "("), code, fixed = TRUE)),
                  info = paste(fn, "is not called by the", prefix, "template"))
    }

    # The refusals boot_health() cannot make for itself. It reports and never
    # stops, so a screen that selected nothing renders green without these.
    expect_true(any(grepl("The screen selected NOTHING", code, fixed = TRUE)),
                info = paste(prefix, "lost the empty-screen refusal"))
    expect_true(any(grepl("returned the SAME fit", code, fixed = TRUE)),
                info = paste(prefix, "lost the flat-bootstrap refusal"))
  }
})

test_that("the thin bootstrap templates carry no phase dimension", {
  for (prefix in c("bl", "br", "bc")) {
    src <- readLines(template_path(prefix), warn = FALSE)
    fence <- grepl("^```", src)
    in_chunk <- cumsum(fence) %% 2 == 1 & !fence
    code <- sub("#.*$", "", src[in_chunk])

    # PHASE_OF must be NULL and must stay NULL. A splitting rule that matches
    # nothing still adds a phase column of empty strings, and every grouped
    # table would then group by a column that says nothing -- silently, since
    # no count changes and no error is raised.
    ph <- grep("^\\s*PHASE_OF\\s*<-", code, value = TRUE)
    expect_length(ph, 1L)
    expect_match(ph, "NULL", info = paste(prefix, "supplies a phase rule"))

    # No table may select or order by a phase column: with phase = NULL the
    # reporting layer returns none, so a reference is an error at render time
    # in a file nobody has run against a real bag yet.
    expect_false(any(grepl("\\$phase|\"phase\"|~phase", code)),
                 info = paste(prefix, "references a phase column"))
  }
})
```

- [ ] **Step 2: Run the tests**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && Rscript -e 'devtools::test(filter = "templates")'
```

Expected: PASS. If the phase test fails, a Task B3 Step 5 site was missed;
the `info` names which template.

- [ ] **Step 3: Commit**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git add tests/testthat/test-templates.R && git commit -m "test: the thin bootstrap templates report through the package and carry no phase"
```

---

### Task B7: Ledger, README and the regenerated roadmap

`spec-counts.yaml` runs `check-roadmap-counts.py`, which compares the ledger
against `inst/templates/` **in both directions**. Three new template files
with no ledger rows fail the PR, and so would three rows claiming absent
templates. This task is what makes B3-B5 mergeable.

**Files:**
- Modify: `dev/specs/artifacts/2026-08-29-template-roadmap.json`
- Modify: `dev/specs/2026-08-29-template-conversion-roadmap.md` (regenerated)
- Modify: `inst/templates/README.md`

- [ ] **Step 1: Update the three ledger rows**

For `bl`, `br` and `bc`, set `"status": "shipped"`, `"batch": 2`, the
assigned ordinal, and `"spec"`. Leave `sas_breadth`, `r_exemplars` and
`r_jobs` at their measured values — they are census facts, not status.

```json
{ "prefix": "bl", "ordinal": "04.02", "status": "shipped",
  "spec": "dev/specs/2026-08-31-batch-2a-bootstrap-family-design.md",
  "note": null }
{ "prefix": "br", "ordinal": "04.03", "status": "shipped",
  "spec": "dev/specs/2026-08-31-batch-2a-bootstrap-family-design.md",
  "note": null }
{ "prefix": "bc", "ordinal": "04.04", "status": "shipped",
  "spec": "dev/specs/2026-08-31-batch-2a-bootstrap-family-design.md",
  "note": "no exemplar study and no SAS template. Shipped on fit_cox() existing. Gated on a screen the render gate ran against a real built dataset, never on a screen a study ran." }
```

Edit the existing objects in place; do not append new ones. Every field in
`FIELDS` must remain present on each row.

- [ ] **Step 2: Regenerate the roadmap document**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && python3 dev/specs/artifacts/check-roadmap-counts.py
```

Expected on first run: FAIL, and **the failure names the fix**:
`run python3 dev/specs/artifacts/roadmap_render.py`. Run that, then re-run the
checker.

⚠️ **Do not update the counts by hand, which is what this plan first said.**
The roadmap document is generated from the ledger, and `roadmap_render.py` is
the generator. Hand-editing it produces a document that agrees with the checker
and disagrees with its source the next time anything regenerates.

⚠️ **Editing a count without regenerating fails the PR**, and hand-counting
is how the macro-allocation tables drifted three times in one day.

- [ ] **Step 3: Add the README rows**

In `inst/templates/README.md`, after the `04.05-bh.qmd` row:

```markdown
| `analyses/04.02-bl.qmd` | bootstrap variable selection, logistic | `analyses/` |
| `analyses/04.03-br.qmd` | bootstrap variable selection, linear | `analyses/` |
| `analyses/04.04-bc.qmd` | bootstrap variable selection, Cox | `analyses/` |
```

Rows sit in ordinal order, so these go **above** `04.05-bh.qmd`.

- [ ] **Step 4: Update the README's untemplated list and add the runner note**

In the paragraph listing what shipped when, add `bl`, `br` and `bc` at
1.0.19. Then extend the existing "`bh`'s companion runner is not templated"
note:

```markdown
**Nor are `bl`, `br` and `bc`'s.** Their runner calls
`hvtiRbootstrap::boot_select()` with the fitter for its model and converts the
result with `boot_bag()`, which is one call and needs no template. What it
must supply is the four facts the screen cannot know: which terms are the base
model, how many candidates were offered before any were dropped, the dataset
manifest, and what was dropped.

⚠️ **None of the three has been rendered against a screen a study ran.** No R
job in the corpus calls `boot_select()` yet, so all three were gated on a
screen run against a real built dataset for the purpose. That covers real
variable names and a real correlation structure; it does not cover the
candidate pool and the dropped set a study author chooses, which is where
`bh`'s one shipped defect lived. `bc` has the least behind it: it ships
because `fit_cox()` exists, not because a study has run one, and of the 16
studies with a `bc` job none has an R exemplar. Read the first real output of
any of the three against your own expectations, not as a checked path.
```

- [ ] **Step 5: Run all three count gates**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && python3 dev/specs/artifacts/check-spec-counts.py && python3 dev/specs/artifacts/check-flow-counts.py && python3 dev/specs/artifacts/check-roadmap-counts.py
```

Expected: all three exit 0.

- [ ] **Step 6: Commit**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git add dev/specs/artifacts/2026-08-29-template-roadmap.json dev/specs/2026-08-29-template-conversion-roadmap.md inst/templates/README.md && git commit -m "docs: ledger, roadmap and README rows for bl, br and bc"
```

---

### Task B8: Release 1.0.19

**Files:**
- Modify: `DESCRIPTION` (Version, Date, `hvtiRbootstrap` bound)
- Modify: `NEWS.md`

- [ ] **Step 1: Bump `DESCRIPTION` and correct the dependency bound**

Set `Version: 1.0.19` and `Date: 2026-09-01`. In `Suggests:`, raise
`hvtiRbootstrap (>= 0.1.1)` to `hvtiRbootstrap (>= 0.9.2)`.

⚠️ **That bound is currently wrong and was already wrong before this plan.**
1.0.18 shipped a `bh` template that refuses to render below 0.9.0 while
`DESCRIPTION` still declared `>= 0.1.1`. Raising it to 0.9.2 fixes both.

- [ ] **Step 2: Add the `NEWS.md` entry**

Insert above the `# hvtiRtemplates 1.0.18` heading:

```markdown
# hvtiRtemplates 1.0.19

* **Three bootstrap screen templates ship**: `analyses/04.02-bl.qmd`
  (logistic), `analyses/04.03-br.qmd` (linear) and `analyses/04.04-bc.qmd`
  (Cox). All three report through `hvtiRbootstrap`'s reporting layer with
  `PHASE_OF <- NULL`, which is the single-phase path the same functions serve
  for `bh` with a term-splitting rule. One code path, four templates.

* **They require `hvtiRbootstrap (>= 0.9.2)`, and `DESCRIPTION` now says so.**
  0.9.2 adds `boot_bag()`, without which a `boot_select()` screen cannot be
  read by the reporting layer at all: the screen returns a wide coefficients
  matrix and the layer reads a long-form bag written by a hazard runner, and
  nothing converted between them. The declared bound had also drifted -- it
  still read `>= 0.1.1` while 1.0.18's `bh` template refused to render below
  0.9.0.

* **All three were rendered against a screen run for the gate, not against a
  screen a study ran.** No R job found on the share calls `boot_select()`, so
  there was no `bl`, `br` or `bc` bag to read. The gate screens a real built
  dataset instead, which exercises real variable names, a real correlation
  structure and `read_built()`; what it does not exercise is a candidate pool
  a study author chose. `bc` is the weakest of the three: the corpus has 16
  studies with a `bc` job and none has an R exemplar.
  `inst/templates/README.md` and the roadmap ledger both record this.

* **Ordinals 04.02, 04.03 and 04.04** are assigned from the free minors in
  `analyses`. `04.06` remains retired and unissuable.
```

- [ ] **Step 3: Full check**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && Rscript -e 'devtools::document(); devtools::test(); devtools::check()'
```

Expected: `devtools::check()` **0 errors, 0 warnings, 0 notes**, and
`devtools::test()` reporting `FAIL 0 | WARN 0`.

⚠️ **Read the `SKIP` count and state it.** A green conclusion can sit over a
suite that skipped the tests you care about; that cost `hvtiRlifetables` ten
CI runs and two reviews.

- [ ] **Step 4: Build the PDF manual locally**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && Rscript -e 'devtools::check(manual = TRUE)'
```

`check-manual.yaml` has no `pull_request` trigger, so the manual build runs
for the first time **after** merge, on `main`, where there is no PR left to
fix it in. This task adds no Rd markup, but run it anyway: the cost is one
command and the failure mode is a broken `main`.

- [ ] **Step 5: Push and open the PR**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && git add DESCRIPTION NEWS.md man && git commit -m "release: 1.0.19, bl br and bc as thin bootstrap templates" && git push -u origin feat/batch-2a-phase-3 && gh pr create --base main --title "Batch 2a phase 3: bl, br and bc as thin templates" --body "Design 2026-08-31-batch-2a-bootstrap-family-design.md section 7 phase 3. Depends on hvtiRbootstrap 0.9.2, which adds boot_bag(). Section 4.2 of the design records the gap that release closes."
```

- [ ] **Step 6: Verify all eight checks and the Copilot review**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && gh pr checks --watch && gh pr view --json reviewRequests,reviews
```

⚠️ **Copilot reviews the PR as opened and never re-reviews a later push.** If
you push a fix after its review, re-request explicitly and verify with
`gh pr view --json reviewRequests` — never trust the mutation's 200. The
GraphQL form and the bot-node-id lookup are in `AGENTS.md`.

⚠️ **A re-review can re-raise a finding the reviewed commit already fixed**,
because it anchors against the cumulative diff. Check the file before acting
on one.

---

---

# Part C — parity against the SAS runs

**Where this work lives.** In the study's own R project, beside the existing
`R_hazard` project, with its spec under that project's `docs/specs/`. **No
study path, study name, variable name or endpoint name enters
`hvtiRtemplates`.** What comes back here is a pass/fail, counts, and the
sentences in Task B7 and B8 that describe the gate.

**Why this is worth doing at all.** Part B's render gate proves the three
templates run. It does not prove they report the right numbers, and the
residual risk it leaves — a candidate pool and a dropped set a study author
chose — is precisely the risk that produced `bh`'s one shipped defect. One
study on the share has SAS `bl` and `br` runs whose summary output is
structurally the table `boot_summary()` returns. Comparing against it closes
that risk for two of the three prefixes.

### ⚠️ This is NOT the parity gate `hz` passed, and must not be written as one

`hz` reproduced at 1e-12 because a nomogram is deterministic: the C code
transcribes to R exactly. **A bootstrap screen is stochastic.** `%bootreg` and
`boot_select()` draw different resamples from different generators, so their
selection frequencies agree only within Monte-Carlo error — about **3.2**
percentage points per variable at `p = 0.5` over 500 replicates. Over a table
of 150 candidates, **several rows will differ by more than two standard errors
by chance alone**.

⚠️ **3.2, not the 2.2 this plan said until 2026-09-01.** 2.2 is
`100 * sqrt(p * (1 - p) / n)`, the error of ONE run. The comparison is between
two independent runs, whose difference carries
`100 * sqrt(2 * p * (1 - p) / n)`, larger by a factor of `sqrt(2)`. Written with
explicit multiplication because these are expressions to be applied, not
notation to be read: `2p(1-p)` pasted into R is a call to a function `p`. `compare_bootreg()` below had the right formula throughout;
only the prose was wrong. Following the prose instead of the code sets the band
at 2 x 2.2 rather than 2 x 3.2, which turns a nominal 95% band into roughly
84% and flags about 24 spurious disagreements on a 150-row table -- read, of
course, as the port having failed.

A parity test written as equality therefore has two failure modes and both are
bad: it fails spuriously, or it gets tuned until it passes and then certifies
nothing. So the comparison is distributional, and it is split into what is
deterministic and what is not:

| checked exactly | checked distributionally |
|---|---|
| the candidate pool: membership and size | each variable's `pct`, against a 2 SE band |
| which terms are at 100% (the base or forced set) | the retained set at the cutoff |
| the replicate count | rank agreement across the whole table |
| the entry and stay levels | per-term coefficient `mean` and `sd` |

Coefficient means and standard deviations are the better numeric comparison:
they converge faster than a selection frequency, because every replicate that
selected a term contributes to them while the frequency is a proportion over
all replicates.

---

### Task C1: Parse the SAS summary output

**Files (in the study's R project):**
- Create: `R/read_bootreg_summary.R`
- Test: `tests/testthat/test-read-bootreg-summary.R`

**Interfaces:**
- Produces: `read_bootreg_summary(path)` returning a data frame with columns
  `variable`, `n`, `pct`, `min`, `max`, `mean`, `sd` — the same names and
  order `boot_summary()` uses, so the comparison in C2 is a join and not a
  translation.

- [ ] **Step 1: Note the two output shapes before writing the parser**

The logistic and linear summaries do **not** carry the same base row, and a
parser that assumes one will silently mislabel the other:

- `proc=logistic` writes `_LNLIKE_` at 100% as its first row. That is the
  model's log-likelihood, not a candidate, and it is what `base_params`
  corresponds to.
- `proc=reg` writes **no** `_LNLIKE_`. The dependent variable appears at 100%
  with an estimate of exactly `-1` across every replicate, and any forced
  variable also sits at 100%.

So the parser must return every row and let C2 decide which are base, rather
than filtering by a name it recognises.

- [ ] **Step 2: Write the failing test**

Use a fixture of the first 12 lines of each `_summary.lst`, copied into the
test directory. The fixture is the study's own output and stays in the study.

```r
test_that("the logistic summary parses to boot_summary()'s columns", {
  x <- read_bootreg_summary(test_path("fixtures", "bl-summary.lst"))
  expect_identical(names(x),
                   c("variable", "n", "pct", "min", "max", "mean", "sd"))
  expect_identical(x$variable[[1L]], "_LNLIKE_")
  expect_identical(x$n[[1L]], 500L)
  expect_equal(x$pct[[1L]], 100.0)
  # A row further down, so a parser that only reads the header is caught.
  expect_true(all(x$pct <= 100 & x$pct >= 0))
  expect_false(any(is.na(x$n)))
})

test_that("the linear summary parses, and carries no _LNLIKE_ row", {
  x <- read_bootreg_summary(test_path("fixtures", "br-summary.lst"))
  expect_false("_LNLIKE_" %in% x$variable)
  # The dependent variable sits at 100% with estimate -1 in every replicate.
  expect_true(any(x$pct == 100 & x$sd == 0))
})
```

- [ ] **Step 3: Write the parser**

The `.lst` is fixed-width with a page header repeated every 107 lines
(`options pagesize=107`). Read the lines, keep those matching a data row,
and split on whitespace — the columns are `Obs _NAME_ N PCT MIN MAX MEAN STD`
and `_NAME_` never contains a space.

```r
read_bootreg_summary <- function(path) {
  ln <- readLines(path, warn = FALSE)
  # A data row: leading obs number, then a name, then six numeric fields.
  # Matched rather than counted from the header, because the header repeats
  # on every page and a count would drift by one page per 107 lines.
  keep <- grepl("^\\s*\\d+\\s+\\S+(\\s+-?[0-9.]+){6}\\s*$", ln)
  if (!any(keep)) {
    stop("No summary rows found in ", path, ". A %bootreg summary writes ",
         "Obs/_NAME_/N/PCT/MIN/MAX/MEAN/STD; this file does not.",
         call. = FALSE)
  }
  f <- strsplit(trimws(ln[keep]), "\\s+")
  out <- data.frame(
    variable = vapply(f, `[[`, character(1), 2L),
    n        = as.integer(vapply(f, `[[`, character(1), 3L)),
    pct      = as.numeric(vapply(f, `[[`, character(1), 4L)),
    min      = as.numeric(vapply(f, `[[`, character(1), 5L)),
    max      = as.numeric(vapply(f, `[[`, character(1), 6L)),
    mean     = as.numeric(vapply(f, `[[`, character(1), 7L)),
    sd       = as.numeric(vapply(f, `[[`, character(1), 8L)),
    stringsAsFactors = FALSE
  )
  # Obs numbers run 1..n with no gaps. A page header mistaken for a data row
  # would break that, and nothing downstream would notice a missing variable.
  obs <- as.integer(vapply(f, `[[`, character(1), 1L))
  if (!identical(obs, seq_along(obs))) {
    stop("Parsed ", length(obs), " rows but their Obs numbers are not ",
         "1..", length(obs), ", so a line was dropped or a header was read ",
         "as data.", call. = FALSE)
  }
  out
}
```

- [ ] **Step 4: Run the tests**

Expected: PASS, both.

- [ ] **Step 5: Commit in the study project**

---

### Task C2: The `bl` parity run

**Files (in the study's R project):**
- Create: a `bl` job scaffolded from `04.02-bl.qmd`, plus its runner
- Create: `R/compare_bootreg.R` and its test
- Create: the parity spec under the project's `docs/specs/`

**Interfaces:**
- Consumes: `read_bootreg_summary()` from C1, `boot_select()`, `boot_bag()`.
- Produces: `compare_bootreg(r_summary, sas_summary, n_boot, cutoff)`
  returning a data frame with one row per variable and columns `variable`,
  `pct_r`, `pct_sas`, `diff`, `se`, `within_2se`, `retained_r`,
  `retained_sas`, `decision_agrees`. Task C3 calls the same function.

- [ ] **Step 1: Match the SAS call exactly where it is deterministic**

Read the settings off the `%bootreg` call rather than choosing them:
`resampl` is the replicate count, `proc=logistic` selects `fit_logistic`,
`sle` and `sls` are the entry and stay levels, `fraction` is the resample
size, and the `data built; ... where` line is the cohort filter. The MODEL
statement's variable list is the pool, in full, including every `ln_`, `in_`
and trailing-`2` form.

⚠️ **Do not prune the pool to make the run faster.** Design §5 measured what
pruning does: of 57 forms removed, 16 correlated below 0.9 with the form
kept. A pruned pool is a different screen and its frequencies are not
comparable to the SAS ones — a variable's selection frequency is conditional
on the pool it competed in, and the same study moved one variable from 26.6%
to 95.2% by changing the pool alone.

⚠️ **This run is not instant.** 500 stepwise logistic fits over a pool of
roughly 150 candidates on a few thousand rows. Time one replicate first and
multiply before launching, and use `boot_select()`'s `max_attempts` default
rather than `Inf` so a pool that cannot fit stops with a diagnostic instead
of hanging.

- [ ] **Step 2: Write the comparison**

```r
compare_bootreg <- function(r_summary, sas_summary, n_boot, cutoff = 50) {
  m <- merge(r_summary[, c("variable", "pct")],
             sas_summary[, c("variable", "pct")],
             by = "variable", all = TRUE,
             suffixes = c("_r", "_sas"))

  # The band is the Monte-Carlo error of the DIFFERENCE of two independent
  # runs, so it is sqrt(2) times one run's error. Using one run's error would
  # flag about a third of the table as disagreeing when nothing is wrong.
  p  <- m$pct_sas / 100
  m$se <- 100 * sqrt(2 * p * (1 - p) / n_boot)
  m$diff <- m$pct_r - m$pct_sas
  m$within_2se <- !is.na(m$diff) & abs(m$diff) <= 2 * m$se

  m$retained_r   <- !is.na(m$pct_r)   & m$pct_r   >= cutoff
  m$retained_sas <- !is.na(m$pct_sas) & m$pct_sas >= cutoff
  m$decision_agrees <- m$retained_r == m$retained_sas
  m[order(-m$pct_sas), , drop = FALSE]
}
```

- [ ] **Step 3: State the pass criteria before running, not after**

Write these into the parity spec **first**. A criterion chosen after seeing
the output is not a test.

1. **Pool membership is exact.** Every candidate in the SAS MODEL statement
   appears in the R frequency table and no other does, once `_LNLIKE_` and
   the base set are set aside. A mismatch here is a transcription error, not
   noise, and stops everything else.
2. **Rank agreement:** Spearman correlation of `pct_r` against `pct_sas`
   across all candidates **>= 0.95**. This is the headline number. It is
   insensitive to the Monte-Carlo scatter that makes any single row
   unreliable.
3. **Band coverage:** at least **90%** of candidates within 2 SE. Not 100%:
   at a nominal 95% band, roughly 5% of a 150-row table falls outside by
   construction, and demanding 100% is demanding the impossible.
4. **Retention decisions agree on at least 90% of candidates**, and **every**
   disagreement is within 2 SE of the cutoff. A disagreement far from the
   cutoff is a real difference and must be explained, not counted.
5. **No systematic shift:** the median of `diff` within **1 SE of zero**. A
   consistent offset in one direction is the signature of a different
   selection rule, not of resampling noise, and it is the failure this whole
   comparison exists to catch.

⚠️ **Criterion 5 is the one that would catch a wrong fitter.** Criteria 2-4
can all pass while `fit_logistic()`'s AIC-based `step()` enters variables at
a systematically different rate than `%bootreg`'s p-value thresholds. `sle`
and `sls` are p-values and `step()` works on AIC; `R/fitters.R:46` already
records that the two are not the same criterion. If criterion 5 fails, the
finding belongs in `hvtiRbootstrap`, not in the template.

- [ ] **Step 4: Run, and record the numbers in the parity spec**

Record all five criteria's measured values whether they pass or fail, plus
the replicate count, the pool size, the cohort size and both `sle`/`sls`.
A parity spec that records only a verdict cannot be re-checked.

- [ ] **Step 5: Render the `bl` template against the resulting bag**

The bag from this run is a **real** `bl` screen over a real pool. Render
`04.02-bl.qmd` against it and read the concept, crowding and collinearity
tables: this is the first time any of them meets real affix-carrying names
(`ln_avrg`, `in_tvrg`, `avpkg2` and the like are what `concept_map()` was
written for). Any defect found here is a Part B fix, applied to all three
templates.

---

### Task C3: The `br` parity run

Same as Task C2 with three changes, and no others:

1. `proc=reg` selects `fit_linear`, not `fit_logistic`.
2. The outcome is continuous, and the cohort filter is the one on the SAS
   `data built;` line for that job.
3. **There is no `_LNLIKE_` row.** The dependent variable appears at 100%
   with an estimate of exactly `-1` and standard deviation `0` — a SAS REG
   artifact, not a selected term. It must be excluded from the comparison
   explicitly, along with any forced variable also sitting at 100%.

⚠️ **Criterion 5 matters more here.** `R/fitters.R:46` records that `sle`/`sls`
are p-value thresholds while `step()` works on AIC. On a continuous outcome
that difference is largest, because the p-value for a term in a linear model
responds to residual variance in a way a binary outcome's does not — the
same point `04.03-br.qmd` makes in prose in Task B4 Step 1. If any parity run
shows a systematic shift, expect it to be this one.

- [ ] **Step 1: Run C1's parser on the linear summary**
- [ ] **Step 2: Run the R screen matching the SAS call**
- [ ] **Step 3: Compare against the five criteria, recording measured values**
- [ ] **Step 4: Render `04.03-br.qmd` against the resulting bag**
- [ ] **Step 5: Write both runs' results into the study's parity spec**

---

### Task C4: Carry the outcome back

**Files:**
- Modify: `inst/templates/README.md` (the note added in Task B7 Step 4)
- Modify: `NEWS.md` (the bullet added in Task B8 Step 2)
- Modify: `dev/specs/2026-08-31-batch-2a-bootstrap-family-design.md` §8

- [ ] **Step 1: Replace the gate sentences with what was measured**

Counts and verdicts only. **No study name, no variable name, no endpoint
name, no path.** The README note becomes, with the bracketed values filled
from Tasks C2 and C3:

```markdown
**`bl` and `br` were checked against SAS.** Each was run in R over the same
candidate pool, replicate count and entry/stay levels as an existing
`%bootreg` job, and its selection frequencies compared against that job's
summary output: rank correlation [x] and [x], with [n]% and [n]% of
candidates within two Monte-Carlo standard errors and retention decisions
agreeing on [n]% and [n]%. Exact agreement is not available and not expected
-- two bootstrap runs draw different resamples, so their frequencies differ
by about three percentage points per variable at 500 replicates.

⚠️ **`bc` has no such check**, because no `bc` SAS job exists anywhere in the
corpus. It ships on a render against a real dataset and on `fit_cox()`
existing. Read its first real output against your own expectations.
```

- [ ] **Step 2: Update design §8's gate paragraph**

Replace the "screen we run, not a screen a study ran" caveat with the
measured result for `bl` and `br`, and keep it in full for `bc`.

- [ ] **Step 3: Re-run the count gates and commit**

```bash
cd ~/Documents/GitHub/hvtiRtemplates && python3 dev/specs/artifacts/check-spec-counts.py && python3 dev/specs/artifacts/check-flow-counts.py && python3 dev/specs/artifacts/check-roadmap-counts.py
```

⚠️ **The README and design now carry anchored numbers.** If
`check-spec-counts.py` covers the lines you edited, its map must be
regenerated; editing a count without regenerating fails the PR.

---

## Part B execution note, 2026-09-01

**Part B is done and pushed on `feat/batch-2a-phase-3`, nine commits.** Tasks
B1 through B7 complete, B8 complete except the PR. Clean `git archive` export:
`R CMD check` **0 errors, 0 warnings, 0 notes**. Source tree
`testthat` **179 pass, 0 fail, 0 skip**; under check the tarball skips 4, all in
`test-roadmap.R`, because `dev/specs/artifacts/*.json` is `.Rbuildignore`d.
That is pre-existing and was verified for PR #62. `lintr` clean. PDF manual
builds, 4 pages.

**The PR is held, deliberately.** `DESCRIPTION` carries
`Remotes: ehrlinger/hvtiRbootstrap` and `Suggests: hvtiRbootstrap (>= 0.9.2)`.
CI resolves that remote against the other repository's `main`, which is 0.9.1,
so `setup-r-dependencies` cannot satisfy the constraint and the run reddens for
a reason only Part A can fix. Open the PR once 0.9.2 ships.

**Version renumbered to 1.0.20.** 1.0.19 went to
[#65](https://github.com/ehrlinger/hvtiRtemplates/pull/65), a prose fix that was
ready while this branch was blocked. Renumbered rather than left to collide,
which is how #44 and #46 both shipped under 1.0.10.

**The render gate was stronger than planned.** Every template was rendered
against a real built dataset from a study on the share, screened through
`boot_select()`, rather than against the simulated columns the plan settled
for: 12 candidates over 494 real rows. `read_built()` and
`pool_collinear_pairs()` therefore ran for real, which closes the plan's
residual risk 2. `new_job()` scaffolded each template, which exercises the
single-`^ENDPOINT`/single-`^TYPE` contract, since it hard-stops otherwise.

### What this plan got wrong

Six defects, recorded because the next batch will be written from this one.
Four are corrected inline above; two could not be.

**D1. Task B4 said the `br` diff from `bl` is four hunks, and told the executor
to revert a fifth as an accidental edit.** It is **ten**. `bl` names its
companion model job, the fitter its runner calls and its own report file, and
all three change for a linear screen. This is the worst defect in the plan:
following it deletes correct work, and the instruction is phrased with enough
confidence to be obeyed. Corrected at Task B4 Step 4.

**D2. Task B2's staging step made the copied `datasets/` read-only.**
`read_built()` writes a `built.schema.csv` beside the data on first read, so the
gate died inside `read_built()` with a permission error naming a temp file.
The instinct was right and the target was wrong: the study is protected by
never writing to it, not by the mode bits on a scratch copy. Corrected at Task
B2 Step 1.

**D3. Task B7 told the executor to update the roadmap counts by hand from the
checker's output.** There is a generator, `roadmap_render.py`, and the
checker's own failure message names it. Hand-editing a generated document
produces one that satisfies the checker and disagrees with its source at the
next regeneration, which is the drift the ledger exists to prevent. Corrected
at Task B7 Step 2.

**D4. The plan believed Part B's render gate was blocked on `boot_bag()`.** It
was not. The templates never call it; only a runner does. A hand-built bag
renders them completely, and the pivot used to build it was the one this plan
specifies for `boot_bag()`, so its round-trip invariant was verified **before**
Part A writes it: `boot_frequencies()` on the assembled bag matched
`boot_summary()` on the wide matrix to 1e-12. Had the plan been followed
literally, all of Part B would have waited on a blocked Part A for no reason.
Corrected at Task A4 Step 5.

**D5. The plan assumed `bh`'s health chunk transferred unchanged, and gave it
no step at all.** Two of its warnings are false under `boot_select()`. The
"write the formula literally" instruction describes `hzr_bootstrap()`'s
per-replicate rewrite; `boot_select()`'s fitters evaluate through
`.fit_in_env()`, which binds `formula` and `data` where `step()` looks, and a
variable-held formula gives byte-identical results. Copying the warning would
have told study authors something untrue about the function they are calling,
in three files. Added as Task B3 Step 5b.

**D6. A test that passes under `devtools::test()` and errors under
`R CMD check`.** Not a defect in the plan as written, but in work added beyond
it: a new test asserting `DESCRIPTION`'s `hvtiRbootstrap` bound is at least the
highest floor any template enforces read `../../DESCRIPTION`, which resolves
from `tests/testthat` and not from an installed copy. It passed locally and
errored in check. `utils::packageDescription()` is the portable form. This is
the divergence `AGENTS.md` warns about, and only running the real check found
it.

### One thing the plan did not know to ask for

The test in D6 exists because `DESCRIPTION` declared
`hvtiRbootstrap (>= 0.1.1)` from 1.0.13 while `04.05-bh.qmd`'s own guard
demanded 0.1.2 and later 0.9.0. **Nine releases with the two disagreeing**, and
nothing read both: the bound is in `DESCRIPTION`, the floor is a string inside
a `.qmd`. A study could satisfy the declared dependency and still be refused by
the template it had just scaffolded, with the message arriving mid-render.

⚠️ **A repomap would not have caught it**, and it is worth writing that down
because it was proposed as the fix. The generated maps under
`Claude/repomaps/` list `Suggests` with the version bounds **stripped**, and do
not index `inst/templates/` at all, so neither side of the comparison appears
in one. The check that catches this class has to compare the two artifacts
directly.

---

## Self-review

**Spec coverage.** Design §7 Phase 3 requires `bl`, `br`, `bc` as thin
templates with ordinals from the ledger and never from row position: Tasks
B3-B5 and B7. §8's definition of done for this phase — renders against a bag
(B3 Step 9, B4 Step 3, B5 Step 5), own `.lintr` file key (B3 Step 8, B4
Step 2, B5 Step 4), `edit-guard` chunk (inherited by copy from `bh`, asserted
by the existing `test-templates.R` guard at line 112), exactly one `^ENDPOINT`
and one `^TYPE` (B3 Step 3, inherited by B4 and B5), no study identifiers
(asserted by `test-new-job.R`), README row and ledger row (B7),
`devtools::test()` and `check()` 0/0/0 and `document()` (B8 Step 3), patch
bump with matching `NEWS.md` (B8 Steps 1-2). §4.1's "every extracted function
takes `phase = NULL`" is proved by Task A2's phase test and Task B6's
structural test rather than assumed.

**Covered because the design did not:** the missing bag producer, Part A
entire, recorded in the design by Task B1. Part C likewise: the design's §8
asked for a render against a real bag and no such bag exists, so the parity
comparison is what stands in for it, on terms §8 did not anticipate because
it did not distinguish a deterministic reproduction from a stochastic one.

**Part C's boundary.** Its artifacts — the R jobs, the `.lst` parser, the
comparison and the parity spec — live in the study's R project. Only counts
and verdicts return here, through Task C4. No study name, variable name,
endpoint name or path enters this repository at any point.

**Not covered, deliberately.** `bq`
([hvtiRbootstrap#16](https://github.com/ehrlinger/hvtiRbootstrap/issues/16))
and `bn` stay out of scope per design §9.
[hvtiRbootstrap#22](https://github.com/ehrlinger/hvtiRbootstrap/issues/22) is
a per-phase `free_sd`, which a `boot_bag()` bag cannot have; §0 says so.
Running the screens stays out of scope: these templates report over a bag a
companion runner produces.

**Residual risk, stated rather than resolved.**

1. **The gate runs a screen; it does not read one a study ran.** Design §5
   made a real-bag render a required step because `bh` shipped a
   render-blocker through three releases, and this phase cannot fully meet
   that bar: searched on 2026-09-01, no R job found on the share calls
   `boot_select()`, so there is no `bl`, `br` or `bc` bag to read. The gate
   covers the `phase = NULL` path that nothing had ever run — Phase 2's plan
   named that as this phase's first real problem — and it covers real
   variable names, a real correlation structure and a real row count, because
   it screens a study's built dataset. **What it does not cover is the pool
   and the dropped set a study author chose**, and a wrong pool is exactly
   what `bh`'s defect was: `EXPECT_CHUNKS <- 25L` was one study's number
   shipped as though it were general. Part C closes that for `bl` and `br`
   and cannot close it for `bc`.
2. **The gate depends on a mounted share and on one study.** Exactly one
   study on the share is set up as an hvtiR project. If it moves or its
   manifest changes, the harness falls back to simulated columns, and it says
   so on the `mode` line rather than degrading quietly — but a reviewer who
   does not read that line sees a passing gate either way.
3. **`bc` has the least behind it of the three.** No exemplar study, no SAS
   template, no parity run available, and its no-intercept `base_params`
   problem is caught by exactly one render. Read its first real output
   against expectations rather than as a checked path.
4. **Part C's parity is distributional, and a passing run does not mean the
   two implementations agree.** `sle`/`sls` are p-value thresholds and
   `step()` works on AIC (`hvtiRbootstrap` `R/fitters.R:46`), so the two
   selection rules are genuinely different and only criterion 5, the
   systematic-shift check, is aimed at that difference. Criteria 2 to 4 can
   all pass while the rules disagree in a consistent direction.
5. **`boot_bag()`'s `elapsed_mins` is this call's elapsed time only.** A
   runner that chunks its screen and pools with `boot_pool_chunks()` gets the
   sum; a runner that calls `boot_select()` in a loop and stacks the results
   itself does not, and `boot_bag()` cannot tell the difference. The
   provenance table would then understate compute.
6. **`bl`, `br` and `bc` are near-copies by construction.** The design
   accepted that (§10) on the grounds that what is duplicated is prose and
   `EDIT:` markers, not computation. Task B4 Step 1 states the four-edit diff
   explicitly so the claim stays checkable; if a fifth divergence appears in
   a later fix, the premise has changed and the design should be revisited
   rather than the files re-synced by hand.
