# Confidence bands for the rf explain templates: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `rfs-explain`, `rfc-explain` and `rfr-explain` can draw 95% subsampling intervals on permutation
importance and pointwise bands on the partial-dependence plots, computed in a submitted job and cached.

**Architecture:** One new internal file, `R/rf-bands.R`, holds the computation (subsample sizes, row draws,
refits, partial values, the jackknife SE, interpolation) and the two plot helpers. Each explain template gains
four study choices and three chunks that call those helpers through `cache_fit()`, behind `guard_long_fit()`,
which learns to take a vector of cache names. Everything is off by default (`BANDS_B <- 0`).

**Tech Stack:** R, randomForestSRC 3.9.0 (`subsample()`, `extract.subsample()`, `partial.rfsrc()`,
`get.partial.plot.data()`), ggplot2, patchwork, hvtiPlotR, hvtiRutilities `cache_fit()`, testthat 3e.

**Design:** [`2026-10-26-rf-confidence-bands-design.md`](2026-10-26-rf-confidence-bands-design.md). Read it
first; this plan does not repeat its reasoning.

## Global Constraints

- Branch `spec/rf-confidence-bands` exists; implementation goes on a new branch `feat/rf-confidence-bands` cut
  from `origin/main` after the spec PR merges, or stacked on the spec branch **opened against `main`**, never
  against another branch (AGENTS.md: a stacked PR draws no Copilot review).
- Lines are at most **135** characters (`.lintr`). Every default linter is on in `R/`.
- Roxygen is **Rd markup**, not markdown: `\code{}`, `\strong{}`, `\link{}`.
- `BANDS_B` defaults to **0**; with it, every explain job renders exactly as on `main`.
- `SUBRATIO`: `NULL` or one number in (0, 0.5]. The default is `exp(-1)` for n <= 1000 and
  `exp(-1) * sqrt(1000 / n)` above. Always pass the resolved value to `subsample()` explicitly, so the
  behavior does not depend on randomForestSRC's own default.
- `BAND_STYLE`: `"ribbon"` or `"bars"`. `BAND_AT`: `NULL` or a named list of numeric vectors.
- SE = `sqrt(subratio * rowMeans((star - hat)^2, na.rm = TRUE))`, deviations about the full forest's value.
- Floor: **100** events per subsample (rfs) or of the smallest class (rfc); none for rfr.
- VIMP for the intervals uses `importance = "anti"` (the `vimp()` default the importance figure uses) and
  `extract.subsample(standardize = FALSE)` (the importance figure is unstandardized).
- No forest on the **full cohort** is grown in an explain job; subsample forests are grown only in
  `.band_refit()`.
- Never `git add -A`: failing testthat runs write `tests/testthat/_problems/`. Add files by name.
- Every R/Rscript run touching `/Volumes/qhsstudies` is forbidden from the Mac. All runs in this plan are on
  the package checkout under `~/Documents/GitHub` and may run locally, except Task 9's timing job.
- A pull request that ships carries a `news/<branch>.md` fragment and **no** `Version:` or `NEWS.md` edit.

---

## File map

| file | change | responsibility |
|---|---|---|
| `R/long-fit.R` | modify | `guard_long_fit()` takes a character vector `name` |
| `R/rf-bands.R` | create | band computation and the two plot helpers, all internal |
| `inst/templates/30_analyses/rfs-explain.qmd` | modify | choices, `bands-plan`, interval and band chunks |
| `inst/templates/30_analyses/rfc-explain.qmd` | modify | the same, for classification |
| `inst/templates/30_analyses/rfr-explain.qmd` | modify | the same, for regression |
| `tests/testthat/test-guard-long-fit.R` | modify | vector `name` |
| `tests/testthat/test-rf-bands.R` | create | unit tests of `R/rf-bands.R` |
| `tests/testthat/test-rf-templates.R` | modify | template-level band tests |
| `tests/testthat/test-template-figures.R` | modify | the new documented figure names |
| `inst/templates/README.md` | modify | figure table row, when-to-submit paragraph |
| `man/guard_long_fit.Rd` | regenerate | `devtools::document()` |
| `news/feat-rf-confidence-bands.md` | create | the NEWS fragment |

---

### Task 1: `guard_long_fit()` accepts several cache names

**Files:**
- Modify: `R/long-fit.R:12-45`
- Test: `tests/testthat/test-guard-long-fit.R`
- Regenerate: `man/guard_long_fit.Rd`

**Interfaces:**
- Produces: `guard_long_fit(name, dir, why, refit = FALSE)`, where `name` is a non-empty character vector with
  no `NA` or empty element. It returns `invisible(FALSE)` when every `<dir>/<name>.rds` exists (and
  `refit` is `FALSE`), and otherwise errors as today.

- [ ] **Step 1: Write the failing tests.** Append to `tests/testthat/test-guard-long-fit.R`:

```r
test_that("several names pass only when every cache exists", {
  dir <- withr::local_tempdir()
  withr::local_options(rlang_interactive = TRUE, hvtiRtemplates.allow_interactive_fit = NULL)
  saveRDS(1, file.path(dir, "a.rds"))
  expect_error(guard_long_fit(c("a", "b"), dir = dir, why = "slow"), "submit_job(", fixed = TRUE)
  saveRDS(1, file.path(dir, "b.rds"))
  expect_false(guard_long_fit(c("a", "b"), dir = dir, why = "slow"))
  expect_error(guard_long_fit(c("a", "b"), dir = dir, why = "slow", refit = TRUE), "REFIT")
})

test_that("a name vector with an empty or NA element is refused", {
  expect_error(guard_long_fit(c("a", ""), dir = ".", why = "slow"), "`name`")
  expect_error(guard_long_fit(c("a", NA), dir = ".", why = "slow"), "`name`")
  expect_error(guard_long_fit(character(), dir = ".", why = "slow"), "`name`")
})
```

and **delete** the now-wrong first line of the existing test "guard_long_fit() checks its arguments":
`expect_error(guard_long_fit(c("a", "b"), dir = ".", why = "slow"), "`name`")`.

- [ ] **Step 2: Run them and see them fail.**

Run: `Rscript -e 'devtools::test(filter = "guard-long-fit")'`
Expected: FAIL in "several names pass only when every cache exists" with "`name` must be a single".

- [ ] **Step 3: Implement.** In `R/long-fit.R` replace the `name` check and the existence test:

```r
  if (!is.character(name) || !length(name) || anyNA(name) || !all(nzchar(name))) {
    stop("guard_long_fit(): `name` must be one or more non-empty strings.", call. = FALSE)
  }
```

```r
  if (!rlang::is_interactive() || isTRUE(getOption("hvtiRtemplates.allow_interactive_fit")) ||
        (!isTRUE(refit) && all(file.exists(file.path(dir, paste0(name, ".rds")))))) {
    return(invisible(FALSE))
  }
```

and the roxygen `@param name`:

```r
#' @param name Character. The \code{cache_fit()} name, or several when one long step writes several caches;
#'   each cache file is \code{<dir>/<name>.rds}, and the call is refused while any of them is missing.
```

- [ ] **Step 4: Run the tests and see them pass.**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "guard-long-fit")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 13 ]` (9 before, 4 added, 1 removed: count what prints, and
confirm FAIL 0).

- [ ] **Step 5: Commit.**

```bash
git add R/long-fit.R man/guard_long_fit.Rd tests/testthat/test-guard-long-fit.R
git commit -m "Let guard_long_fit() guard several caches at once"
```

---

### Task 2: the band arithmetic

Pure functions with no forest: subsample size, SE, interpolation, the floor.

**Files:**
- Create: `R/rf-bands.R`
- Test: `tests/testthat/test-rf-bands.R`

**Interfaces:**
- Produces:
  - `.band_subratio(n, subratio)` -> numeric(1) in (0, 0.5]; errors naming `SUBRATIO`.
  - `.band_size(n, subratio)` -> integer(1), `max(2L, round(subratio * n))`.
  - `.band_se(hat, star, subratio)` -> numeric, length `length(hat)`; `star` is a `length(hat)` x B matrix.
  - `.band_at(x, hat, star, at)` -> `list(x = at, hat = numeric, star = matrix)`, each column of `star`
    linearly interpolated at `at`.
  - `.band_floor_need(rare_total, floor = 100)` -> the smallest subratio giving `floor` rare cases.

- [ ] **Step 1: Write the failing tests.** Create `tests/testthat/test-rf-bands.R`:

```r
test_that("the default subratio follows randomForestSRC's rule, and a chosen one is checked", {
  expect_equal(hvtiRtemplates:::.band_subratio(500, NULL), exp(-1))
  expect_equal(hvtiRtemplates:::.band_subratio(4000, NULL), exp(-1) * sqrt(1000 / 4000))
  expect_equal(hvtiRtemplates:::.band_subratio(500, 0.25), 0.25)
  for (bad in list(0, 0.6, -1, NA_real_, c(0.2, 0.3), "0.2")) {
    expect_error(hvtiRtemplates:::.band_subratio(500, bad), "SUBRATIO")
  }
  expect_identical(hvtiRtemplates:::.band_size(100, 0.37), 37L)
  expect_identical(hvtiRtemplates:::.band_size(3, 0.1), 2L)
})

test_that("the SE is the jackknife SE extract.subsample() reports", {
  skip_if_not_installed("randomForestSRC", "3.9.0")
  e <- new.env()
  utils::data("veteran", package = "randomForestSRC", envir = e)
  f <- randomForestSRC::rfsrc(survival::Surv(time, status) ~ ., e$veteran, ntree = 30,
                              importance = "none", seed = -1)
  set.seed(2)
  s <- randomForestSRC::subsample(f, B = 4, importance = "anti", verbose = FALSE)
  hat <- s$vmp[[1]][, 1]
  star <- sapply(s$vmpS, function(v) v[[1]][[1]])
  expect_equal(unname(hvtiRtemplates:::.band_se(hat, star, s$subratio)),
               unname(randomForestSRC::extract.subsample(s, standardize = FALSE)$se.jk.Z))
})

test_that("an NA replicate is left out of the SE rather than making it NA", {
  star <- matrix(c(1, 2, NA, 3, 1, 2), nrow = 2)
  expect_equal(hvtiRtemplates:::.band_se(c(2, 2), star, 0.5),
               sqrt(0.5 * c(mean(c(1, 0, 1)), mean(c(0, 0)))))
})

test_that("interpolating at a grid point reproduces that grid point", {
  x <- c(10, 20, 30)
  hat <- c(1, 2, 4)
  star <- cbind(c(1, 3, 5), c(0, 2, 2))
  at <- hvtiRtemplates:::.band_at(x, hat, star, c(20, 25))
  expect_equal(at$hat, c(2, 3))
  expect_equal(at$star, rbind(c(3, 2), c(4, 2)))
  expect_error(hvtiRtemplates:::.band_at(x, hat, star, 40), "observed range")
})

test_that("the floor names the subratio that would give 100 rare cases", {
  expect_equal(hvtiRtemplates:::.band_floor_need(400), 0.25)
  expect_equal(hvtiRtemplates:::.band_floor_need(150), 100 / 150)
})
```

- [ ] **Step 2: Run them and see them fail.**

Run: `Rscript -e 'devtools::test(filter = "rf-bands")'`
Expected: FAIL, `could not find function ".band_subratio"` (or "object not found").

- [ ] **Step 3: Implement.** Create `R/rf-bands.R`:

```r
# Confidence bands for the rf explain templates: VIMP intervals from randomForestSRC's
# subsample(), and pointwise bands on the partial plots from refits of our own on
# subsamples drawn the same way. The design is dev/specs/2026-10-26-rf-confidence-bands-design.md.

# randomForestSRC's default subsample fraction, or the study's, checked. The value is
# always passed to subsample() explicitly, so a change of default there cannot make the
# two kinds of band use different subsamples.
.band_subratio <- function(n, subratio) {
  if (is.null(subratio)) return(if (n <= 1000) exp(-1) else exp(-1) * sqrt(1000 / n))
  if (!is.numeric(subratio) || length(subratio) != 1L || is.na(subratio) || subratio <= 0 || subratio > 0.5) {
    stop("SUBRATIO must be NULL or one number above 0 and at most 0.5: above that every subsample ",
         "forest is nearly the full forest and the bands shrink to its tree-to-tree noise.", call. = FALSE)
  }
  subratio
}

.band_size <- function(n, subratio) max(2L, as.integer(round(subratio * n)))

# The delete-d jackknife standard error extract.subsample() reports as se.jk.Z: the
# mean squared deviation of the subsample estimates about the full forest's, scaled by
# the subsample fraction. `star` has one row per point and one column per subsample;
# a subsample that could not give a value (NA) is left out of that point's mean.
.band_se <- function(hat, star, subratio) {
  sqrt(subratio * rowMeans((star - hat)^2, na.rm = TRUE))
}

# The band read off at the values a study chose for its bars, each subsample's curve
# taken straight between grid points, as the figure draws the line.
.band_at <- function(x, hat, star, at) {
  if (any(at < min(x) | at > max(x))) {
    stop("BAND_AT asks for values outside the observed range, ", signif(min(x), 4), " to ", signif(max(x), 4),
         ".", call. = FALSE)
  }
  lin <- function(y) stats::approx(x, y, xout = at)$y
  list(x = at, hat = lin(hat), star = apply(star, 2L, lin) |> matrix(nrow = length(at)))
}

# The smallest subsample fraction that gives `floor` of the rarest outcome, from the
# cohort's count of it.
.band_floor_need <- function(rare_total, floor = 100) floor / rare_total
```

- [ ] **Step 4: Run the tests and see them pass.**

Run: `Rscript -e 'devtools::test(filter = "rf-bands")'`
Expected: `[ FAIL 0 | ... ]`, all five tests passing.

- [ ] **Step 5: Lint and commit.**

Run: `Rscript -e 'lintr::lint("R/rf-bands.R")'`. Expected: no lints.

```bash
git add R/rf-bands.R tests/testthat/test-rf-bands.R
git commit -m "Add the band arithmetic for the rf explain templates"
```

---

### Task 3: subsample rows, refits and partial values

**Files:**
- Modify: `R/rf-bands.R`
- Test: `tests/testthat/test-rf-bands.R`

**Interfaces:**
- Consumes: `.band_size()` (Task 2).
- Produces:
  - `.band_strata(forest)` -> factor of length `forest$n` (rfs: event status; rfc: class) or `NULL` (rfr).
  - `.band_rows(forest, B, subratio)` -> list of B sorted integer vectors; stratified; errors naming
    `SUBRATIO` when a survival subsample would hold no event.
  - `.band_refit(forest, rows, seed)` -> an `rfsrc` grow object on `rows`, with the forest's settings.
  - `.band_grid(pd, var)` -> `list(type = "continuous"|"categorical", x = <values>)`, read from a
    `gg_partial_rfsrc` result.
  - `.band_times(pd)` -> numeric of snapped horizons, or `NULL` when `pd` has no `time` column.
  - `.partial_values(forest, var, x, times)` -> numeric of length `length(x) * max(1, length(times))`, `x`
    varying fastest.

- [ ] **Step 1: Write the failing tests.** Append to `tests/testthat/test-rf-bands.R`:

```r
band_forest <- function(family = c("surv", "class", "regr")) {
  family <- match.arg(family)
  e <- new.env()
  utils::data("veteran", package = "randomForestSRC", envir = e)
  switch(family,
    surv = randomForestSRC::rfsrc(survival::Surv(time, status) ~ ., e$veteran, ntree = 20, seed = -1),
    class = randomForestSRC::rfsrc(Species ~ ., datasets::iris, ntree = 20, seed = -1),
    regr = randomForestSRC::rfsrc(Ozone ~ ., stats::na.omit(datasets::airquality), ntree = 20, seed = -1)
  )
}

test_that("rows are drawn within event status, at the subsample size, the same under the same seed", {
  skip_if_not_installed("randomForestSRC", "3.9.0")
  f <- band_forest("surv")
  set.seed(1)
  rows <- hvtiRtemplates:::.band_rows(f, 3, 0.3)
  set.seed(1)
  expect_identical(hvtiRtemplates:::.band_rows(f, 3, 0.3), rows)
  expect_length(rows, 3L)
  status <- f$yvar[[2]] > 0
  for (r in rows) {
    expect_false(is.unsorted(r))
    expect_lte(abs(length(r) - hvtiRtemplates:::.band_size(f$n, 0.3)), 1L)
    expect_equal(mean(status[r]), mean(status), tolerance = 0.05)
  }
})

test_that("a survival subsample with no event stops, naming SUBRATIO", {
  skip_if_not_installed("randomForestSRC", "3.9.0")
  f <- band_forest("surv")
  f$yvar[[2]][] <- 0
  f$yvar[[2]][1] <- 1
  expect_error(hvtiRtemplates:::.band_rows(f, 2, 0.05), "SUBRATIO")
})

test_that("a refit keeps the forest's settings and grows on the rows given", {
  skip_if_not_installed("randomForestSRC", "3.9.0")
  for (fam in c("surv", "class", "regr")) {
    f <- band_forest(fam)
    rows <- seq_len(floor(f$n / 2))
    g <- hvtiRtemplates:::.band_refit(f, rows, seed = -7)
    expect_identical(g$n, length(rows), info = fam)
    expect_identical(g$family, f$family, info = fam)
    expect_identical(c(g$ntree, g$mtry, g$nodesize), c(f$ntree, f$mtry, f$nodesize), info = fam)
    expect_identical(g$xvar.names, f$xvar.names, info = fam)
  }
})

test_that("partial values agree with gg_partial_rfsrc on its own grid", {
  skip_if_not_installed("randomForestSRC", "3.9.0")
  skip_if_not_installed("ggRandomForests", "4.0.0")
  f <- band_forest("surv")
  pd <- ggRandomForests::gg_partial_rfsrc(f, xvar.names = c("karno", "celltype"), partial.time = c(30, 90))
  times <- hvtiRtemplates:::.band_times(pd)
  g <- hvtiRtemplates:::.band_grid(pd, "karno")
  expect_identical(g$type, "continuous")
  v <- hvtiRtemplates:::.partial_values(f, "karno", g$x, times)
  ref <- pd$continuous[pd$continuous$name == "karno", ]
  ref <- ref[order(ref$time, ref$x), ]
  expect_equal(v, ref$yhat, tolerance = 1e-8)
  cg <- hvtiRtemplates:::.band_grid(pd, "celltype")
  expect_identical(cg$type, "categorical")
  cv <- hvtiRtemplates:::.partial_values(f, "celltype", cg$x, times)
  expect_length(cv, length(cg$x) * length(times))
  expect_true(all(cv >= 0 & cv <= 1))
})
```

- [ ] **Step 2: Run them and see them fail.**

Run: `Rscript -e 'devtools::test(filter = "rf-bands")'`
Expected: the four new tests FAIL with "could not find function".

- [ ] **Step 3: Implement.** Append to `R/rf-bands.R`:

```r
# The groups a subsample is drawn within, as subsample() draws them: event status for a
# survival forest, the class for a classification forest, none for regression.
.band_strata <- function(forest) {
  switch(forest$family,
    surv = factor(forest$yvar[[forest$yvar.names[2]]] > 0, levels = c(FALSE, TRUE)),
    class = factor(forest$yvar),
    NULL
  )
}

# B subsamples of the forest's rows, each a fraction `subratio` of them, drawn without
# replacement within the strata. R's generator draws them, which cache_fit() seeds.
.band_rows <- function(forest, B, subratio) {
  n <- forest$n
  b <- .band_size(n, subratio)
  strata <- .band_strata(forest)
  draw <- function() {
    if (is.null(strata)) return(sort(sample.int(n, b)))
    sort(unlist(lapply(split(seq_len(n), strata), function(i) {
      k <- min(length(i), as.integer(round(b * length(i) / n)))
      i[sample.int(length(i), k)]
    }), use.names = FALSE))
  }
  rows <- lapply(seq_len(B), function(i) draw())
  if (identical(forest$family, "surv")) {
    event <- forest$yvar[[forest$yvar.names[2]]] > 0
    if (any(vapply(rows, function(r) !any(event[r]), logical(1)))) {
      stop("A subsample of ", b, " patients holds no event. Raise SUBRATIO.", call. = FALSE)
    }
  }
  rows
}

# A forest grown on `rows` with the settings of `forest`, read off the saved forest
# rather than its call: the fit job's call names its own variables (model, NTREE), which
# do not exist here. The seed is handed to rfsrc(), negated as randomForestSRC documents.
.band_refit <- function(forest, rows, seed) {
  y <- forest$yvar.names
  d <- forest$xvar
  if (is.data.frame(forest$yvar)) d <- cbind(forest$yvar, d) else d[[y]] <- forest$yvar
  d <- d[rows, , drop = FALSE]
  tick <- function(v) paste0("`", v, "`")
  formula <- if (identical(forest$family, "surv")) {
    stats::as.formula(sprintf("Surv(%s, %s) ~ .", tick(y[1]), tick(y[2])))
  } else {
    stats::as.formula(paste(tick(y), "~ ."))
  }
  na_action <- if (length(forest$imputed.indv)) "na.impute" else "na.omit"
  randomForestSRC::rfsrc(formula, data = d, ntree = forest$ntree, mtry = forest$mtry,
                         nodesize = forest$nodesize, nsplit = forest$nsplit, splitrule = forest$splitrule,
                         na.action = na_action, importance = "none", seed = -abs(seed))
}

# The values a variable's partial was drawn at, read from the full forest's
# gg_partial_rfsrc result, so every subsample forest is evaluated on the same grid.
.band_grid <- function(pd, var) {
  for (type in c("continuous", "categorical")) {
    frame <- pd[[type]]
    if (is.data.frame(frame) && var %in% frame$name) {
      x <- frame$x[frame$name == var]
      x <- if (is.factor(x)) levels(droplevels(x)) else sort(unique(x))
      return(list(type = type, x = x))
    }
  }
  stop("No partial was drawn for ", var, ".", call. = FALSE)
}

# The horizons the full forest's partial was read at, already snapped to its event times.
.band_times <- function(pd) {
  times <- unlist(lapply(pd[c("continuous", "categorical")], function(f) if (is.data.frame(f)) f$time))
  if (is.null(times)) NULL else sort(unique(as.numeric(times)))
}

# A forest's partial prediction for one variable at the values `x`, and for a survival
# forest at each horizon in `times`, averaged over the patients as gg_partial_rfsrc()
# averages it. A subsample forest snaps `times` to its own nearest event time.
.partial_values <- function(forest, var, x, times = NULL) {
  surv <- identical(forest$family, "surv")
  p <- randomForestSRC::partial.rfsrc(forest, partial.xvar = var, partial.values = x,
                                      partial.type = if (surv) "surv", partial.time = if (surv) times)
  as.numeric(randomForestSRC::get.partial.plot.data(p)$yhat)
}
```

- [ ] **Step 4: Run the tests.**

Run: `Rscript -e 'devtools::test(filter = "rf-bands")'`
Expected: PASS. **If "partial values agree with gg_partial_rfsrc" fails on the categorical half**, read
`ggRandomForests:::make_eval_grid` (`Rscript -e 'print(ggRandomForests:::make_eval_grid)'`) for how it hands
a factor's levels to `partial.rfsrc()`, and make `.band_grid()` return the values in that form; do not loosen
the test. If the refit test fails for the regression forest because `forest$xvar` lacks rows that
`na.omit` dropped, use `forest$xvar` as it is (it holds only the rows the forest was grown on) and assert
`g$n == length(rows)` still.

- [ ] **Step 5: Commit.**

```bash
git add R/rf-bands.R tests/testthat/test-rf-bands.R
git commit -m "Draw subsample rows and regrow forests for the partial bands"
```

---

### Task 4: the refit pool, the per-variable band, and the plan table

**Files:**
- Modify: `R/rf-bands.R`
- Test: `tests/testthat/test-rf-bands.R`

**Interfaces:**
- Consumes: `.band_refit()`, `.partial_values()`, `.band_subratio()`, `.band_size()`, `.band_strata()`,
  `.band_floor_need()`.
- Produces:
  - `.band_pool(vars, grids, progress = NULL)` -> an environment; `vars` are the variables still to compute,
    `grids` a named list of `.band_grid()` results, `progress` a `function(step, steps)` or `NULL`.
  - `.band_partial(pool, forest, rows, var, grid, times, seed)` -> `list(var, type, x, time, hat, star)`,
    `hat` numeric of length m, `star` an m x B matrix, m = `length(x) * max(1, length(times))`. The first call
    grows the B forests once and computes every pooled variable; later calls read the pool.
  - `.band_plan(forest, B, subratio, style, at, sel, pd)` -> `list(subratio, table)`; validates
    `BAND_STYLE` and `BAND_AT`; warns and marks the report a draft (or stops under strict) below the floor.

- [ ] **Step 1: Write the failing tests.** Append:

```r
test_that("the pool grows each subsample forest once for all its variables", {
  skip_if_not_installed("randomForestSRC", "3.9.0")
  skip_if_not_installed("ggRandomForests", "4.0.0")
  f <- band_forest("surv")
  pd <- ggRandomForests::gg_partial_rfsrc(f, xvar.names = c("karno", "age"), partial.time = c(30, 90))
  times <- hvtiRtemplates:::.band_times(pd)
  grids <- lapply(c(karno = "karno", age = "age"), function(v) hvtiRtemplates:::.band_grid(pd, v))
  set.seed(1)
  rows <- hvtiRtemplates:::.band_rows(f, 3, 0.4)
  grown <- 0L
  # The mock counts the refits and hands back the full forest, so the test grows nothing.
  local_mocked_bindings(.band_refit = function(...) {
    grown <<- grown + 1L
    f
  }, .package = "hvtiRtemplates")
  steps <- integer()
  pool <- hvtiRtemplates:::.band_pool(names(grids), grids, progress = function(step, steps_) steps <<- c(steps, step))
  a <- hvtiRtemplates:::.band_partial(pool, f, rows, "karno", grids$karno, times, 1)
  b <- hvtiRtemplates:::.band_partial(pool, f, rows, "age", grids$age, times, 1)
  expect_identical(grown, 3L)
  expect_identical(steps, 1:3)
  expect_identical(dim(a$star), c(length(grids$karno$x) * length(times), 3L))
  expect_length(b$hat, length(grids$age$x) * length(times))
  expect_error(hvtiRtemplates:::.band_partial(pool, f, rows, "trt", grids$karno, times, 1), "not in the pool")
})

test_that("a subsample forest that cannot give a value leaves NA for that subsample only", {
  skip_if_not_installed("randomForestSRC", "3.9.0")
  f <- band_forest("regr")
  grid <- list(type = "continuous", x = c(60, 80))
  pool <- hvtiRtemplates:::.band_pool("Temp", list(Temp = grid))
  calls <- 0L
  local_mocked_bindings(.partial_values = function(forest, ...) {
    calls <<- calls + 1L
    if (calls == 2L) stop("level absent") else c(1, 2)
  }, .package = "hvtiRtemplates")
  out <- hvtiRtemplates:::.band_partial(pool, f, list(1:50, 1:50), "Temp", grid, NULL, 1)
  expect_true(all(is.na(out$star[, 1])))
  expect_false(anyNA(out$star[, 2]))
})

test_that("the plan refuses a bad style or BAND_AT, and warns below the floor", {
  skip_if_not_installed("randomForestSRC", "3.9.0")
  skip_if_not_installed("ggRandomForests", "4.0.0")
  f <- band_forest("surv")
  pd <- ggRandomForests::gg_partial_rfsrc(f, xvar.names = c("karno", "celltype"), partial.time = 30)
  plan <- function(...) hvtiRtemplates:::.band_plan(f, 3, 0.4, ..., sel = c("karno", "celltype"), pd = pd)
  expect_error(plan("dots", NULL), "BAND_STYLE")
  expect_error(plan("bars", list(trt = 1)), "BAND_AT")
  expect_error(plan("bars", list(celltype = 1)), "categorical")
  expect_error(plan("bars", list(karno = "50")), "BAND_AT")
  expect_message(plan("ribbon", list(karno = 50)), "BAND_AT is ignored")
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "")
  # veteran has 128 deaths, so 40% of them is about 51, under the floor of 100.
  expect_warning(p <- plan("ribbon", NULL), "SUBRATIO")
  expect_identical(p$subratio, 0.4)
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "1")
  expect_error(plan("ribbon", NULL), "HVTI_TEMPLATE_STRICT")
})
```

- [ ] **Step 2: Run them and see them fail.**

Run: `Rscript -e 'devtools::test(filter = "rf-bands")'`
Expected: the three new tests FAIL with "could not find function".

- [ ] **Step 3: Implement.** Append to `R/rf-bands.R`:

```r
# The B subsample forests are grown once for every variable whose band is missing, and
# each forest is dropped as soon as its partials are read: B forests at once would not
# fit in a session. The first .band_partial() call fills the pool; the rest read it.
# The template reaches the pool through get(), so cache_fit() keys each band on its own
# variable's grid and not on the pool, which changes with the set of missing variables.
.band_pool <- function(vars, grids, progress = NULL) {
  pool <- new.env(parent = emptyenv())
  pool$vars <- vars
  pool$grids <- grids
  pool$progress <- progress
  pool
}

.band_fill <- function(pool, forest, rows, times, seed) {
  B <- length(rows)
  m <- function(v) length(pool$grids[[v]]$x) * max(1L, length(times))
  pool$star <- lapply(stats::setNames(pool$vars, pool$vars), function(v) matrix(NA_real_, m(v), B))
  for (b in seq_len(B)) {
    fit <- .band_refit(forest, rows[[b]], seed = abs(seed) + b)
    for (v in pool$vars) {
      # A factor level absent from this subsample, say, leaves its column NA; the SE is read from the rest.
      value <- tryCatch(.partial_values(fit, v, pool$grids[[v]]$x, times), error = function(e) NULL)
      if (length(value) == nrow(pool$star[[v]])) pool$star[[v]][, b] <- value
    }
    rm(fit)
    if (is.function(pool$progress)) pool$progress(b, B)
  }
  invisible(pool)
}

# One variable's band: the full forest's partial and the B subsample forests' at the
# same values, for cache_fit() to save under the variable's own name.
.band_partial <- function(pool, forest, rows, var, grid, times, seed) {
  if (!var %in% pool$vars) stop(var, " is not in the pool of variables still to compute.", call. = FALSE)
  if (is.null(pool$star)) .band_fill(pool, forest, rows, times, seed)
  list(var = var, type = grid$type, x = grid$x, time = times,
       hat = .partial_values(forest, var, grid$x, times), star = pool$star[[var]])
}

# Checks the band choices before anything is grown, and the table the report prints.
.band_plan <- function(forest, B, subratio, style, at, sel, pd) {
  if (!is.character(style) || length(style) != 1L || !style %in% c("ribbon", "bars")) {
    stop("BAND_STYLE must be \"ribbon\" or \"bars\".", call. = FALSE)
  }
  if (!is.null(at)) {
    if (!is.list(at) || is.null(names(at)) || !all(vapply(at, is.numeric, logical(1)))) {
      stop("BAND_AT must be NULL or a named list of numbers, e.g. list(age = c(50, 60, 70)).", call. = FALSE)
    }
    unknown <- setdiff(names(at), sel)
    if (length(unknown)) stop("BAND_AT names predictor(s) with no partial plot: ", toString(unknown), call. = FALSE)
    cat_vars <- names(at)[vapply(names(at), function(v) .band_grid(pd, v)$type == "categorical", logical(1))]
    if (length(cat_vars)) {
      stop("BAND_AT names categorical predictor(s), which get a bar at every level: ", toString(cat_vars),
           call. = FALSE)
    }
    if (identical(style, "ribbon")) message("BAND_AT is ignored under BAND_STYLE = \"ribbon\".")
  }
  n <- forest$n
  subratio <- .band_subratio(n, subratio)
  b <- .band_size(n, subratio)
  strata <- .band_strata(forest)
  rare <- if (is.null(strata)) NA_integer_ else if (identical(forest$family, "surv")) sum(strata == "TRUE") else
    min(table(strata))
  per <- if (is.na(rare)) NA_integer_ else as.integer(round(subratio * rare))
  what <- if (identical(forest$family, "surv")) "events" else "of the smallest class"
  if (!is.na(per) && per < 100L) {
    need <- .band_floor_need(rare)
    msg <- paste0("Each subsample holds about ", per, " ", what, ", under the 100 the bands need. ",
                  if (need <= 0.5) sprintf("SUBRATIO <- %.2f would give 100.", ceiling(need * 100) / 100) else
                    "The cohort is too small to reach 100 at SUBRATIO <= 0.5; read the bands as rough.")
    if (.strict_render()) {
      stop(msg, "\nThis render stops because HVTI_TEMPLATE_STRICT is '", Sys.getenv("HVTI_TEMPLATE_STRICT"),
           "'. Unset it, or set it to 0, false or no, to render a draft instead.", call. = FALSE)
    }
    warning(msg, call. = FALSE)
    .run_mark_draft(paste0("the confidence bands rest on subsamples of about ", per, " ", what))
  }
  table <- data.frame(
    item = c("Subsample forests", "Patients in each", "Fraction of the cohort",
             if (!is.na(per)) paste("Expected", what, "in each")),
    value = c(B, b, sprintf("%.3f", subratio), if (!is.na(per)) per)
  )
  list(subratio = subratio, table = table)
}
```

- [ ] **Step 4: Run the tests.**

Run: `Rscript -e 'devtools::test(filter = "rf-bands")'`
Expected: PASS. The mock in the pool test uses `local_mocked_bindings(.package = "hvtiRtemplates")`, which
needs `devtools::load_all()` semantics; `devtools::test()` provides them.

- [ ] **Step 5: Commit.**

```bash
git add R/rf-bands.R tests/testthat/test-rf-bands.R
git commit -m "Grow each band's subsample forests once and check the band choices"
```

---

### Task 5: the two plot helpers

**Files:**
- Modify: `R/rf-bands.R`
- Test: `tests/testthat/test-rf-bands.R`

**Interfaces:**
- Consumes: `.band_se()`, `.band_at()`, `.group_colors()` (`R/figure-colors.R`).
- Produces:
  - `.plot_vimp_intervals(ci)` -> ggplot; `ci` is `extract.subsample()$var.jk.sel.Z`.
  - `.band_frame(band, subratio, at = NULL, alpha = 0.05)` -> data.frame `x, time, hat, lower, upper`.
  - `.plot_partial_bands(bands, subratio, style, at, ncol)` -> a patchwork of one panel per band.

- [ ] **Step 1: Write the failing tests.** Append:

```r
fake_band <- function(type = "continuous", times = NULL) {
  x <- if (type == "continuous") c(1, 2, 3) else c("a", "b")
  m <- length(x) * max(1L, length(times))
  set.seed(3)
  list(var = "v", type = type, x = x, time = times, hat = seq_len(m) / 10,
       star = matrix(seq_len(m) / 10 + stats::rnorm(m * 4, sd = 0.02), m, 4))
}

test_that("a band frame is the full forest's value plus and minus 1.96 SE", {
  band <- fake_band(times = c(30, 90))
  fr <- hvtiRtemplates:::.band_frame(band, subratio = 0.3)
  se <- hvtiRtemplates:::.band_se(band$hat, band$star, 0.3)
  expect_equal(fr$upper - fr$hat, stats::qnorm(0.975) * se)
  expect_identical(nrow(fr), 6L)
  expect_identical(sort(unique(fr$time)), c(30, 90))
  at <- hvtiRtemplates:::.band_frame(band, subratio = 0.3, at = 2.5)
  expect_identical(nrow(at), 2L)
  expect_true(all(at$x == 2.5))
})

test_that("the band figures build, with ribbons or bars as chosen", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("patchwork")
  skip_if_not_installed("hvtiPlotR")
  layers <- function(p) vapply(p[[1]]$layers, function(l) class(l$geom)[1], "")
  bands <- list(v = fake_band(times = c(30, 90)), w = fake_band("categorical"))
  bands$w$var <- "w"
  ribbon <- hvtiRtemplates:::.plot_partial_bands(bands, 0.3, "ribbon", NULL, ncol = 2)
  bars <- hvtiRtemplates:::.plot_partial_bands(bands, 0.3, "bars", list(v = c(1.5, 2.5)), ncol = 2)
  expect_true("GeomRibbon" %in% layers(ribbon))
  expect_false("GeomRibbon" %in% layers(bars))
  expect_true("GeomErrorbar" %in% layers(bars))
  for (p in list(ribbon, bars)) expect_s3_class(patchwork::patchworkGrob(p), "gtable")
  ci <- data.frame(lower = c(-0.1, 0.2), mean = c(0, 0.3), upper = c(0.1, 0.4), row.names = c("a", "b"))
  expect_s3_class(ggplot2::ggplot_build(hvtiRtemplates:::.plot_vimp_intervals(ci)), "ggplot_built")
})
```

- [ ] **Step 2: Run them and see them fail.**

Run: `Rscript -e 'devtools::test(filter = "rf-bands")'`
Expected: FAIL, "could not find function".

- [ ] **Step 3: Implement.** Append to `R/rf-bands.R`:

```r
# Each predictor's importance with its 95% subsampling interval, ranked as the
# importance figure ranks them, an interval clear of zero in one color and one that
# reaches it in another.
.plot_vimp_intervals <- function(ci) {
  d <- data.frame(vars = rownames(ci), vimp = ci$mean, lower = ci$lower, upper = ci$upper)
  d$vars <- factor(d$vars, levels = d$vars[order(d$vimp)])
  d$clear <- factor(ifelse(d$lower > 0, "Interval above zero", "Interval reaches zero"),
                    levels = c("Interval above zero", "Interval reaches zero"))
  sym <- rlang::sym
  ggplot2::ggplot(d, ggplot2::aes(x = !!sym("vimp"), y = !!sym("vars"), color = !!sym("clear"))) +
    ggplot2::geom_vline(xintercept = 0, linetype = "dashed", color = "gray50") +
    ggplot2::geom_errorbar(ggplot2::aes(xmin = !!sym("lower"), xmax = !!sym("upper")), width = 0.3,
                           orientation = "y") +
    ggplot2::geom_point(size = 2) +
    ggplot2::scale_color_manual(values = c(`Interval above zero` = "black", `Interval reaches zero` = "gray55"),
                                drop = FALSE, name = NULL) +
    ggplot2::labs(x = "Permutation importance", y = NULL)
}

# A band as plotting rows: the full forest's value and its pointwise interval, at the
# grid or, for a continuous predictor, at the values in `at`.
.band_frame <- function(band, subratio, at = NULL, alpha = 0.05) {
  nx <- length(band$x)
  nt <- max(1L, length(band$time))
  hat <- matrix(band$hat, nx, nt)
  star <- band$star
  x <- band$x
  if (!is.null(at) && identical(band$type, "continuous")) {
    parts <- lapply(seq_len(nt), function(t) {
      rows <- (t - 1L) * nx + seq_len(nx)
      .band_at(band$x, hat[, t], star[rows, , drop = FALSE], at)
    })
    hat <- do.call(cbind, lapply(parts, `[[`, "hat"))
    star <- do.call(rbind, lapply(parts, `[[`, "star"))
    x <- at
    nx <- length(at)
  }
  se <- .band_se(as.numeric(hat), star, subratio)
  z <- stats::qnorm(1 - alpha / 2)
  data.frame(x = rep(x, times = nt), time = if (length(band$time)) rep(band$time, each = nx) else NA_real_,
             hat = as.numeric(hat), lower = as.numeric(hat) - z * se, upper = as.numeric(hat) + z * se)
}

# One panel per predictor: the full forest's partial with a ribbon, or error bars, for
# a continuous predictor, and a point with error bars at each level of a categorical
# one. A survival forest's horizons share a color in line, band and bar.
.plot_partial_bands <- function(bands, subratio, style, at, ncol) {
  sym <- rlang::sym
  panels <- lapply(bands, function(band) {
    fr <- .band_frame(band, subratio, at = if (identical(style, "bars")) at[[band$var]])
    line <- .band_frame(band, subratio)
    timed <- !all(is.na(fr$time))
    fr$time <- factor(fr$time)
    line$time <- factor(line$time)
    colour <- if (timed) ggplot2::aes(color = !!sym("time"), fill = !!sym("time"), group = !!sym("time"))
    dodge <- ggplot2::position_dodge(width = if (identical(band$type, "continuous")) diff(range(line$x)) / 40 else 0.4)
    p <- ggplot2::ggplot(fr, ggplot2::aes(x = !!sym("x"), y = !!sym("hat"))) + colour
    if (identical(band$type, "categorical")) {
      p <- p + ggplot2::geom_errorbar(ggplot2::aes(ymin = !!sym("lower"), ymax = !!sym("upper")), width = 0.2,
                                      position = dodge) +
        ggplot2::geom_point(size = 2, position = dodge)
    } else if (identical(style, "ribbon")) {
      p <- p + ggplot2::geom_ribbon(ggplot2::aes(ymin = !!sym("lower"), ymax = !!sym("upper")), alpha = 0.2,
                                    color = NA) +
        ggplot2::geom_line()
    } else {
      p <- p + ggplot2::geom_line(data = line) +
        ggplot2::geom_errorbar(ggplot2::aes(ymin = !!sym("lower"), ymax = !!sym("upper")),
                               width = diff(range(line$x)) / 30, position = dodge)
    }
    if (timed) {
      cols <- .group_colors(levels(fr$time))
      p <- p + ggplot2::scale_color_manual(values = cols, name = "Time") +
        ggplot2::scale_fill_manual(values = cols, name = "Time")
    }
    p + ggplot2::labs(x = band$var, y = NULL)
  })
  patchwork::wrap_plots(panels, ncol = ncol, guides = "collect")
}
```

- [ ] **Step 4: Run the tests.**

Run: `Rscript -e 'devtools::test(filter = "rf-bands")'`
Expected: PASS. If `.group_colors()` warns for two levels, read its header in `R/figure-colors.R`; it should
not for fewer than its palette size.

- [ ] **Step 5: Lint and commit.**

Run: `Rscript -e 'lintr::lint("R/rf-bands.R")'`. Expected: no lints.

```bash
git add R/rf-bands.R tests/testthat/test-rf-bands.R
git commit -m "Draw the importance intervals and the partial bands"
```

---

### Task 6: `rfs-explain` draws the bands

**Files:**
- Modify: `inst/templates/30_analyses/rfs-explain.qmd` (choices after `SEED`, ~line 147; new chunks after
  `dependence-partial`, ~line 331; the intro paragraph ~line 37)
- Test: `tests/testthat/test-rf-templates.R`

**Interfaces:**
- Consumes: everything in `R/rf-bands.R`; `guard_long_fit()` (Task 1); `hvtiRutilities::cache_would_fit()` (in the 1.5.13 floor); `.job$progress()`; `.page_child()`,
  `save_figure()`, `sel`, `pd`, `forest`, `CACHE_DIR`, `SEED`, `REFIT`, `TIMES` from the template.
- Produces, in the job's environment when `BANDS_B > 0`: `.bands` (from `.band_plan()`), `vi_ci`
  (`extract.subsample()` result), `.rows`, `bands` (named list of `.band_partial()` results); caches
  `rfs-vimp-subsample.rds`, `rfs-band-rows.rds`, `rfs-partial-band-<var>.rds`; figures
  `rfs-explain-importance-intervals` and `rfs-explain-dependence-partial-bands-page-NN`.

- [ ] **Step 1: Write the failing tests.** In `tests/testthat/test-rf-templates.R`, after the
"PARTIAL_VARS refuses..." test, add:

```r
band_labels <- c("bands-plan", "importance-intervals", "dependence-partial-bands")

test_that("with BANDS_B at its default the explain writes no band cache and draws no band", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("rfs", "explain"))
  env <- rfs_explained()
  expect_identical(env$BANDS_B, 0)
  rf_run("rfs", "explain", band_labels, env)
  expect_length(list.files(env$CACHE_DIR, "band|subsample"), 0L)
  expect_length(list.files(env$.root, "partial-bands|importance-intervals", recursive = TRUE), 0L)
})

test_that("rfs-explain draws the importance intervals and the partial bands from cached subsamples", {
  skip_on_cran()
  rf_skip_unless_stack(c(rf_template_packages("rfs", "explain"), "patchwork"))
  withr::local_options(hvtiRtemplates.allow_interactive_fit = TRUE)
  env <- new.env(parent = globalenv())
  env$.root <- rfs_explained_copy()
  rf_run("rfs", "explain", c(explain_labels, band_labels), env,
         c(rfs_explain_choices, list(BANDS_B = 3, SUBRATIO = 0.5)))
  for (nm in c("rfs-vimp-subsample", "rfs-band-rows", paste0("rfs-partial-band-", env$sel))) {
    expect_true(file.exists(file.path(env$CACHE_DIR, paste0(nm, ".rds"))), info = nm)
  }
  expect_identical(dim(env$bands[[1]]$star)[2], 3L)
  expect_gt(length(list.files(env$.root, "rfs-explain-importance-intervals", recursive = TRUE)), 0L)
  expect_gt(length(list.files(env$.root, "rfs-explain-dependence-partial-bands-page-01", recursive = TRUE)), 0L)
})

test_that("a bigger TOP_K computes bands only for the new variables", {
  skip_on_cran()
  rf_skip_unless_stack(c(rf_template_packages("rfs", "explain"), "patchwork"))
  withr::local_options(hvtiRtemplates.allow_interactive_fit = TRUE)
  root <- rfs_explained_copy()
  env <- new.env(parent = globalenv())
  env$.root <- root
  choices <- c(rfs_explain_choices, list(BANDS_B = 3, SUBRATIO = 0.5))
  rf_run("rfs", "explain", c(explain_labels, band_labels), env, choices)
  first <- file.path(env$CACHE_DIR, paste0("rfs-partial-band-", env$sel, ".rds"))
  before <- tools::md5sum(first)
  # A bigger TOP_K makes the full forest's partial stale, so REFIT is set, as a study
  # author would set it. REFIT recomputes only stale caches: the two bands already cached
  # are current, and must be left byte for byte as they were.
  again <- new.env(parent = globalenv())
  again$.root <- root
  pooled <- NULL
  trace_pool <- function(vars, grids, progress = NULL) {
    pooled <<- vars
    hvtiRtemplates:::.band_pool(vars, grids, progress)
  }
  local_mocked_bindings(.band_pool = trace_pool, .package = "hvtiRtemplates")
  rf_run("rfs", "explain", c(explain_labels, band_labels), again, modifyList(choices, list(TOP_K = 3, REFIT = TRUE)))
  expect_identical(pooled, again$sel[3])
  expect_identical(tools::md5sum(first), before)
  expect_true(file.exists(file.path(again$CACHE_DIR, paste0("rfs-partial-band-", again$sel[3], ".rds"))))
})

test_that("BAND_STYLE and BAND_AT only redraw", {
  skip_on_cran()
  rf_skip_unless_stack(c(rf_template_packages("rfs", "explain"), "patchwork"))
  withr::local_options(hvtiRtemplates.allow_interactive_fit = TRUE)
  root <- rfs_explained_copy()
  choices <- c(rfs_explain_choices, list(BANDS_B = 3, SUBRATIO = 0.5))
  env <- new.env(parent = globalenv())
  env$.root <- root
  rf_run("rfs", "explain", c(explain_labels, band_labels), env, choices)
  caches <- list.files(env$CACHE_DIR, "band|subsample", full.names = TRUE)
  before <- tools::md5sum(caches)
  cont <- env$sel[vapply(env$sel, function(v) hvtiRtemplates:::.band_grid(env$pd, v)$type == "continuous", TRUE)][1]
  at <- stats::setNames(list(stats::median(env$bands[[cont]]$x)), cont)
  again <- new.env(parent = globalenv())
  again$.root <- root
  rf_run("rfs", "explain", c(explain_labels, band_labels), again,
         c(choices, list(BAND_STYLE = "bars", BAND_AT = at)))
  expect_identical(tools::md5sum(caches), before)
})

test_that("an uncached band is refused at the console and names submit_job()", {
  skip_on_cran()
  rf_skip_unless_stack(c(rf_template_packages("rfs", "explain"), "patchwork"))
  withr::local_options(rlang_interactive = TRUE, hvtiRtemplates.allow_interactive_fit = NULL)
  env <- new.env(parent = globalenv())
  env$.root <- rfs_explained_copy()
  expect_error(rf_run("rfs", "explain", c(explain_labels, band_labels), env,
                      c(rfs_explain_choices, list(BANDS_B = 3, SUBRATIO = 0.5))),
               "submit_job(", fixed = TRUE)
})
```

- [ ] **Step 2: Run them and see them fail.**

Run: `Rscript -e 'devtools::test(filter = "rf-templates")'`
Expected: the five new tests FAIL with "no chunk labelled bands-plan" (or `rf_chunk()`'s equivalent).

- [ ] **Step 3: Add the study choices.** In `rfs-explain.qmd`, after the `SEED <- 2026` line and before the
`REFIT` comment, insert the four choices exactly as the design's section 4 gives them (`BANDS_B <- 0`,
`SUBRATIO <- NULL`, `BAND_STYLE <- "ribbon"`, `BAND_AT <- NULL`, each with its full `EDIT:` comment). Append
to the `TOP_K` comment:

```r
# With BANDS_B above 0, a bigger TOP_K computes bands only for the new variables, but
# still regrows all BANDS_B subsample forests to do it.
```

- [ ] **Step 4: Add the three chunks** after the `dependence-partial` chunk and before `provenance`:

````markdown
## Confidence bands

Drawn only when `BANDS_B` is above 0. Each subsample forest is grown on a fraction of the patients, within
event status, and the intervals are the full forest's value plus and minus 1.96 jackknife standard errors
(Ishwaran and Lu, 2019). They are pointwise: each bounds the curve at one value, not the whole curve.

```{r}
#| label: bands-plan
# Checks the band choices before anything is grown, and says what will be.
if (BANDS_B > 0) {
  .bands <- hvtiRtemplates:::.band_plan(forest, BANDS_B, SUBRATIO, BAND_STYLE, BAND_AT, sel, pd)
  .subratio <- .bands$subratio
  knitr::kable(.bands$table, col.names = c("Confidence bands", ""))
}
```

```{r}
#| label: importance-intervals
#| results: asis
#| message: true
# unnumbered: the figure below is a child chunk with its own label and caption
if (BANDS_B > 0) {
  # "anti" is the importance vimp() computed for the figure above, and that figure is
  # unstandardized, so the intervals bracket the same quantity. Quoted once, so the
  # check below and cache_fit() read the same call.
  .ci_code <- quote(extract.subsample(subsample(forest, B = BANDS_B, subratio = .subratio, importance = "anti",
                                                verbose = FALSE), standardize = FALSE))
  # Refused at the console only when the intervals will actually be computed: a current
  # cache loads, even under REFIT.
  if (hvtiRutilities::cache_would_fit("rfs-vimp-subsample", .ci_code, seed = SEED, dir = CACHE_DIR, refit = REFIT,
                                      packages = "randomForestSRC")) {
    hvtiRtemplates::guard_long_fit("rfs-vimp-subsample", dir = CACHE_DIR, refit = REFIT,
                                   why = sprintf("the importance intervals regrow the forest %d times", BANDS_B))
  }
  vi_ci <- cache_fit("rfs-vimp-subsample", .ci_code, seed = SEED, dir = CACHE_DIR, refit = REFIT,
                     packages = "randomForestSRC")
  .fig <- hvtiRtemplates:::.plot_vimp_intervals(vi_ci$var.jk.sel.Z) +
    hvtiPlotR::theme_hv_manuscript(base_size = 12, legend.position = "top")
  save_figure(.fig, "rfs-explain-importance-intervals", height = 7)
  .cap <- sprintf(paste("Permutation importance of each predictor with its pointwise 95%% interval from %d",
                        "subsample forests, each grown on %.0f%% of patients. Points give the importance and",
                        "bars the interval, black where the interval lies above zero and gray where it reaches",
                        "it, as in the legend; the dashed line marks zero."), BANDS_B, 100 * .subratio)
  .page_child("importance-intervals", 1L, list(list(index = 1L, width = 6, height = 7)), "", .cap)
}
```

```{r}
#| label: dependence-partial-bands
#| results: asis
#| message: true
# unnumbered: each page below is a child chunk with its own label and caption
if (BANDS_B > 0) {
  .rows <- cache_fit("rfs-band-rows", hvtiRtemplates:::.band_rows(forest, BANDS_B, .subratio),
                     seed = SEED, dir = CACHE_DIR, refit = REFIT)
  .grids <- lapply(stats::setNames(sel, sel), function(v) hvtiRtemplates:::.band_grid(pd, v))
  .times <- hvtiRtemplates:::.band_times(pd)
  # One band per variable, keyed on that variable's grid alone (.g), so a bigger TOP_K
  # leaves the bands already cached current. get() keeps the pool out of the key: it
  # changes with which variables still need a band.
  .band_code <- quote(hvtiRtemplates:::.band_partial(get(".pool"), forest, .rows, .v, .g, .times, SEED))
  # The variables whose band will be computed: no cache, or a stale one under REFIT. A
  # current cache loads even under REFIT, which a bigger TOP_K needs for the partials above.
  .todo <- character()
  for (.v in sel) {
    .g <- .grids[[.v]]
    if (hvtiRutilities::cache_would_fit(paste0("rfs-partial-band-", .v), .band_code, seed = SEED, dir = CACHE_DIR,
                                        refit = REFIT, packages = "randomForestSRC")) .todo <- c(.todo, .v)
  }
  if (length(.todo)) {
    hvtiRtemplates::guard_long_fit(paste0("rfs-partial-band-", .todo), dir = CACHE_DIR, refit = REFIT,
                                   why = sprintf("the partial-dependence bands regrow the forest %d times", BANDS_B))
  }
  # Reports each subsample forest to <job>.run.progress and the render log.
  .pool <- hvtiRtemplates:::.band_pool(.todo, .grids[.todo], progress = .job$progress("subsample forest"))
  bands <- list()
  for (.v in sel) {
    .g <- .grids[[.v]]
    bands[[.v]] <- cache_fit(paste0("rfs-partial-band-", .v), .band_code, seed = SEED, dir = CACHE_DIR,
                             refit = REFIT, packages = "randomForestSRC")
  }
  .drawn <- if (identical(BAND_STYLE, "bars")) "error bars" else "shaded bands"
  .cap <- sprintf(paste("Partial dependence of the forest's prediction on each selected predictor, one panel",
                        "per predictor, with pointwise 95%% intervals from %d subsample forests, each grown on",
                        "%.0f%% of patients. Lines trace the predicted survival across a continuous predictor",
                        "with %s around it, and points with error bars give it at each level of a categorical",
                        "one, one color per follow-up time as in the legend."), BANDS_B, 100 * .subratio, .drawn)
  .pages <- hvtiRtemplates:::.figure_pages(length(sel), panel_width = 3.25, panel_height = 3, page_height = 6)
  for (.i in seq_along(.pages)) {
    .vars <- sel[.pages[[.i]]$index]
    .fig <- hvtiRtemplates:::.plot_partial_bands(bands[.vars], .subratio, BAND_STYLE, BAND_AT,
                                                ncol = .pages[[.i]]$ncol) &
      hvtiPlotR::theme_hv_manuscript(base_size = 12, legend.position = "top",
                                     legend.title = ggplot2::element_text())
    save_figure(.fig, sprintf("rfs-explain-dependence-partial-bands-page-%02d", .i),
                width = .pages[[.i]]$width, height = .pages[[.i]]$height)
    .page_child("dependence-partial-bands", .i, .pages, sel, .cap)
  }
}
```
````

`subsample` and `extract.subsample` are called bare because the setup chunk attaches randomForestSRC, as
`vimp` already is in `fig-importance`.

- [ ] **Step 5: Run the tests.**

Run: `NOT_CRAN=true Rscript -e 'devtools::test(filter = "rf-templates")'`
Expected: FAIL 0. Read the WARN count: **WARN must not rise** over `main`'s for this file (the known drawing
notices are muffled in `fig-` chunks; these chunks are not `fig-`-labelled, so a new loess or off-scale notice
here will show: if one does, add the chunk label to `rf_drawing_notice()`'s list in `helper-rf.R` only if the
notice is one of the two it already accepts, and otherwise fix its cause). If `cache_fit()` warns that the
band rows or a band are "not reproducible", the generator was touched outside its seed: find the call and
seed it, do not muffle the warning.

- [ ] **Step 6: Commit.**

```bash
git add inst/templates/30_analyses/rfs-explain.qmd tests/testthat/test-rf-templates.R
git commit -m "Draw confidence bands in rfs-explain"
```

---

### Task 7: `rfc-explain` and `rfr-explain` draw the bands

**Files:**
- Modify: `inst/templates/30_analyses/rfc-explain.qmd`, `inst/templates/30_analyses/rfr-explain.qmd`
- Test: `tests/testthat/test-rf-templates.R`

**Interfaces:** as Task 6, with the prefix `rfc` or `rfr` in every cache and figure name.

- [ ] **Step 1: Write the failing test.** Append to `test-rf-templates.R`:

```r
test_that("rfc-explain and rfr-explain draw the bands too", {
  skip_on_cran()
  withr::local_options(hvtiRtemplates.allow_interactive_fit = TRUE)
  cases <- list(rfc = list(data = rfc_data(), choices = rfc_choices),
                rfr = list(data = rfr_data(), choices = rfr_choices))
  for (prefix in names(cases)) {
    rf_skip_unless_stack(c(rf_template_packages(prefix, "explain"), "patchwork"))
    fit_env <- rf_fit_first(prefix, cases[[prefix]]$data, cases[[prefix]]$choices)
    env <- new.env(parent = globalenv())
    env$.root <- fit_env$.root
    rf_run(prefix, "explain", c(explain_labels, band_labels), env,
           list(TOP_K = 2, SEED = 1, BANDS_B = 3, SUBRATIO = 0.5))
    for (nm in c(paste0(prefix, "-vimp-subsample"), paste0(prefix, "-partial-band-", env$sel))) {
      expect_true(file.exists(file.path(env$CACHE_DIR, paste0(nm, ".rds"))), info = nm)
    }
    expect_gt(length(list.files(env$.root, paste0(prefix, "-explain-dependence-partial-bands-page-01"),
                                recursive = TRUE)), 0L)
  }
})
```

Before writing it, read the file for the names of the classification and regression data and choices helpers
(`grep -n "_data <- function\|_choices <- list" tests/testthat/test-rf-templates.R`) and use the real names
in place of `rfc_data`, `rfc_choices`, `rfr_data`, `rfr_choices` if they differ.

- [ ] **Step 2: Run it and see it fail.**

Run: `NOT_CRAN=true Rscript -e 'devtools::test(filter = "rf-templates")'`
Expected: the new test FAILs with "no chunk labelled bands-plan".

- [ ] **Step 3: Implement.** Make the Task 6 edits in both templates, replacing `rfs` with the template's
prefix in every cache name, figure name and `guard_long_fit()` name, and with these differences:

- No `TIMES` exists; `.band_times(pd)` returns `NULL` and the bands have no time dimension. Leave the call in.
- Captions: drop "one color per follow-up time as in the legend". `rfc`: "Lines trace the predicted
  probability of the first outcome level ..."; take the wording "the partial effect" from that template's
  existing `dependence-partial` caption so the two figures describe the same quantity in the same words. `rfr`:
  "Lines trace the predicted outcome ...".
- The intro paragraph of the new section says "within class" for `rfc` and drops the stratification clause for
  `rfr`.
- `rfc`: the interval figure ranks by the `all` row; `extract.subsample()`'s default `target = 0` is the
  overall importance, matching "rfc-explain ranks by overall importance, not per class". Keep the default.

- [ ] **Step 4: Run the tests.**

Run: `NOT_CRAN=true Rscript -e 'devtools::test(filter = "rf-templates")'`
Expected: FAIL 0, WARN not above `main`'s for this file.

- [ ] **Step 5: Commit.**

```bash
git add inst/templates/30_analyses/rfc-explain.qmd inst/templates/30_analyses/rfr-explain.qmd \
  tests/testthat/test-rf-templates.R
git commit -m "Draw confidence bands in rfc-explain and rfr-explain"
```

---

### Task 8: invariants, names, docs and the NEWS fragment

**Files:**
- Modify: `tests/testthat/test-rf-templates.R` (the "no explain template grows a forest" test, ~line 279)
- Modify: `tests/testthat/test-template-figures.R:44-46`
- Modify: `inst/templates/README.md:398` and the rf section
- Create: `news/feat-rf-confidence-bands.md`

- [ ] **Step 1: Reword the forest invariant and add the fit-settings test.** Read the existing test at
`test-rf-templates.R` "no explain template grows a forest" and keep its mechanism; change its name to
"no explain template grows a forest on the full cohort" and its assertion so that `rfsrc(` may appear only in
`R/rf-bands.R`'s `.band_refit()` and never in an explain template's source:

```r
test_that("no explain template grows a forest on the full cohort", {
  for (t in c("rfs", "rfc", "rfr")) {
    src <- readLines(template_path(t, "explain"), warn = FALSE)
    expect_false(any(grepl("rfsrc(", src, fixed = TRUE)), info = t)
  }
  # The one place a forest is grown for an explain is a subsample refit.
  expect_match(paste(deparse(body(hvtiRtemplates:::.band_refit)), collapse = "\n"), "rfsrc(", fixed = TRUE)
})
```

If the existing test asserts more than `rfsrc(` (for instance `tune.rfsrc(`), keep every assertion it makes;
only the name and the `.band_refit()` line change.

Then add:

```r
test_that("every fit grows the forest subsample() needs: saved, by.root", {
  for (t in c("rfs", "rfc", "rfr")) {
    src <- paste(readLines(template_path(t, "fit"), warn = FALSE), collapse = "\n")
    expect_false(grepl("forest\\s*=\\s*FALSE", src), info = t)
    expect_false(grepl("bootstrap\\s*=", src), info = t)
  }
})
```

- [ ] **Step 2: Add the documented names.** In `test-template-figures.R`, change the explain loop to:

```r
  for (t in c("rfc-explain", "rfr-explain", "rfs-explain")) {
    expected[[t]] <- paste0(t, c("-importance", "-dependence-marginal", "-dependence-partial",
                                 "-importance-intervals", "-dependence-partial-bands"))
  }
```

and in `inst/templates/README.md` line 398:

```markdown
| rfc-, rfr-, rfs-explain | `<template>-importance`, `-dependence-marginal`, `-dependence-partial`, and with `BANDS_B` above 0 `-importance-intervals` and `-dependence-partial-bands` |
```

- [ ] **Step 3: Add the when-to-submit paragraph** to the rf section of `inst/templates/README.md` (find it
with `grep -n "rfs-explain" inst/templates/README.md`), in the house voice:

```markdown
**Confidence bands.** Set `BANDS_B` in an explain job to draw 95% intervals on the importance and pointwise
bands on the partial plots. Each band regrows the forest on `BANDS_B` subsamples of the patients, so at study
size the job runs for hours: start it with `hvtiRtemplates::submit_job()`, and the console refuses it until
the bands are cached. 100 is right for a report and 25 to 50 for a first look. Leave `SUBRATIO` at `NULL`
unless the job warns that a subsample holds fewer than 100 events or of the smallest class. `BAND_STYLE` and
`BAND_AT` change only the drawing, and redraw from the cache.
```

- [ ] **Step 4: Write the NEWS fragment** `news/feat-rf-confidence-bands.md` (rename to match the branch,
`/` replaced by `-`):

```markdown
* `rfs-explain`, `rfc-explain` and `rfr-explain` can draw 95% subsampling intervals on permutation importance
  and pointwise bands on the partial-dependence plots. Set `BANDS_B` to the number of subsample forests (0, the
  default, draws none); `SUBRATIO`, `BAND_STYLE` (`"ribbon"` or `"bars"`) and `BAND_AT` tune them. The bands are
  cached per variable and run for hours at study size, so submit the job with `submit_job()`.
* `guard_long_fit()` takes several cache names and refuses while any of them is missing.
```

- [ ] **Step 5: Run the whole suite and the gates.**

```bash
Rscript -e 'devtools::document()'
Rscript -e 'lintr::lint_package()'
NOT_CRAN=true Rscript -e 'devtools::test()'
python3 dev/specs/artifacts/check-spec-counts.py
python3 dev/specs/artifacts/check-flow-counts.py
python3 dev/specs/artifacts/check-roadmap-counts.py
```

Expected: no lints; FAIL 0 and WARN equal to `main`'s local count (memory: `test-rf-templates.R`'s known
warnings show locally; CI expects WARN 0); the three count checks print their "agrees" lines. If
`check-flow-counts.py` or `check-spec-counts.py` fails, regenerate what it names in this commit.

- [ ] **Step 6: Commit.**

```bash
git add tests/testthat/test-rf-templates.R tests/testthat/test-template-figures.R inst/templates/README.md \
  news/feat-rf-confidence-bands.md man/
git commit -m "Document the rf confidence bands and keep the explain invariants"
```

---

### Task 9: the release gate, the timing run, and the pull request

- [ ] **Step 1: `R CMD check --as-cran` from a clean export**, manual and vignettes built:

```bash
rm -rf "$TMPDIR/rfb" && mkdir "$TMPDIR/rfb" && git archive HEAD | tar -x -C "$TMPDIR/rfb"
cd "$TMPDIR/rfb" && R CMD build . && NOT_CRAN=true R CMD check --as-cran hvtiRtemplates_*.tar.gz
```

Expected: `Status: OK` (0/0/0). The new roxygen is ASCII, so the PDF manual has nothing new to render; it
is built anyway because `check-manual.yaml` runs only after merge.

- [ ] **Step 2: Stage the timing job for John.** Write the script below to the session scratchpad and
give John the full path; he copies it to `/studies/general/_development/rf-bands-timing/` and runs it on lri
(nothing in it runs from the Mac). It reads one real `rfs.rds` handoff whose path John supplies as its
argument, times one subsample refit at the default fraction, and prints the seconds and the subsample size:

```r
args <- commandArgs(trailingOnly = TRUE)
forest <- hvtiRutilities::read_estimate(args[1])$value
set.seed(1)
rows <- hvtiRtemplates:::.band_rows(forest, 1, hvtiRtemplates:::.band_subratio(forest$n, NULL))[[1]]
t <- system.time(hvtiRtemplates:::.band_refit(forest, rows, 1))[["elapsed"]]
cat(sprintf("n = %d, subsample = %d, one refit = %.0f s, 100 refits = %.1f h\n",
            forest$n, length(rows), t, 100 * t / 3600))
```

Check `read_estimate` exists before handing it over (`Rscript -e 'args(hvtiRutilities::read_estimate)'`); if
the handoff is read differently, use `hvtiRtemplates:::.read_handoff()` as the templates do. The `why` text in
the three guards gains the measured figure ("about N hours for 100 at study size") in a follow-up commit once
John reports it. The guards themselves do not wait on it: they refuse an uncached band whatever its length.

- [ ] **Step 3: Local review.** Run `/code-review` on the branch and fix what it confirms. Copilot's quota is
exhausted (AGENTS.md, measured 2026-10-23); measure it on this PR with the reviews command there, and say in the
PR body that the local review stood in for it.

- [ ] **Step 4: Push and open the PR against `main`.**

```bash
git push -u origin feat/rf-confidence-bands
gh pr create --base main --title "Confidence bands for the rf explain templates" --body-file <body>
```

Body: what changed, the SE formula and its pin test, `BANDS_B = 0` keeps every existing job unchanged, the
timing run outstanding, the local review, and the attribution line.

- [ ] **Step 5: Read the test summaries, not the check marks.**

```bash
gh run view <run-id> --log | grep -E "SKIP [0-9]+ \| PASS"
```

Expected: `SKIP 0` on macOS and Ubuntu, `SKIP 33` on Windows, `WARN 0`.

---

## Self-review against the spec

| spec | task |
|---|---|
| 3a VIMP intervals, `importance = "anti"`, `standardize = FALSE` | 6 (chunk), 7 |
| 3a fit grows `forest = TRUE`, `by.root` | 8 (test) |
| 3b grid fixed from `pd` | 3 (`.band_grid`, `.band_times`) |
| 3b rows drawn once, stratified, no-event stop | 3 (`.band_rows`), 6 (`rf?-band-rows` cache) |
| 3b refit with the fit's settings, forest discarded | 3 (`.band_refit`), 4 (`.band_fill`) |
| 3b per-variable cache | 4 (pool), 6 (loop with `get(".pool")`) |
| 3b SE = jackknife, pinned to `extract.subsample()` | 2 |
| 4 choices and their checks | 6 (choices), 2 and 4 (checks) |
| 4 `BAND_STYLE`, `BAND_AT` drawing only | 5, 6 (test) |
| 4 floor 100, draft or strict stop | 4 (`.band_plan`) |
| 5a plan table, progress callback | 4, 6 |
| 5b caches | 6 |
| 5c guards, vector `name`, timing run | 1, 6, 9 |
| 6a figures and captions | 5, 6, 7 |
| 6b tests 1-10 | 1: 6; 2: 6-7; 3: 6; 4: 2; 5: 1, 6; 6: 8; 7: 8; 8: 6; 9: 2, 4; 10: existing MRN tests, run in 8 |
| 6c docs, NEWS, count gates | 8 |
