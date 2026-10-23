# mtry Tuning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let `nb-boostmtree` choose `mtry` by cross-validated pilot fits on a patient subsample, with `MTRY <- "tune"`.

**Architecture:** `tune_mtry()` (new, `R/tune-mtry.R`) draws a seeded subsample of whole patients, fits one cross-validated boostmtree pilot per candidate through a small mockable internal, and returns a table plus the chosen value. The template calls it as `hvtiRtemplates::tune_mtry()` (a job attaches only boostmtree, ggBoostedTrees and hvtiRutilities), guarded and cached on its own, before the full fit's call is built, and writes the chosen value into that call as a literal so an untuned job's cache key does not change. Spec: `dev/specs/2026-10-20-mtry-tuning-design.md`.

**Tech Stack:** R (>= 4.4.0), boostmtree (fork, >= 2.0.4; in Suggests), testthat edition 3.

## Global Constraints

- **Prerequisites:** the implementation branch must start from a `main` that contains hvtiRtemplates#370 (`MTRY`) and #366 (`guard_long_fit()`). Task 0 checks this, and stops if either is missing.
- boostmtree stays in **Suggests**: `tune_mtry()` checks `requireNamespace("boostmtree")` and stops with the install line if it is absent.
- Error measure, the template's own: the standardized `l2` error at each component's best M, `err[m.opt, "l2"]` with `err <- if (is.matrix(fit$err.rate)) list(fit$err.rate) else fit$err.rate`. **A pilot's score is the mean over components** (one for continuous or binary; one per threshold or class otherwise), because one `mtry` serves every component.
- Candidates default: `unique(sort(pmax(1L, as.integer(round(c(p, p / 2, p / 3, sqrt(p))))), decreasing = TRUE))`, where `p = ncol(x)`.
- Subsample: `n_patients = 1000L`, drawn by patient, never by row; every patient when there are fewer. For an ordinal or nominal response, every level present in the data must be present in the sample: a level the draw missed adds one random patient who has it, so the sample can exceed `n_patients` by up to the number of levels less one.
- Pilots: `M = 50L`, `nu = 0.2`, `cv.flag = TRUE`, `mod.grad = TRUE`, `control = boostmtree::boostmtree.control(cv.cores = cores)`.
- Winner: the lowest score; a tie goes to the larger `mtry`. A failing candidate is recorded and excluded; if all fail, stop with the first error.
- Roxygen is Rd markup; every export has `@return`. Lines are at most 135 characters. testthat edition 3.
- `MTRY` accepts `NULL`, a single positive integer, or `"tune"`; anything else stops in the fit chunk with a message naming `MTRY`.
- **An untuned job's cache key must not change.** The text of `.fit_code` stays `mtry = MTRY`. Under `"tune"` the chosen value is substituted into the call as a literal after `.fit_code` is built, so only a tuned job's fit has a new key.
- **The tuning is resolved before the fit's call, its memory check and its `cache_would_fit()`.** Under `"tune"` it has its own `guard_long_fit("nb-boostmtree-mtry", ...)`, its own `guard_memory()` sized for one pilot, and progress reporting through the same `.job$progress()` the fit uses.
- The tuning's `cache_fit()` and `cache_would_fit()` pass `packages = "boostmtree"`: the fit runs inside `tune_mtry()`, so the key cannot see the dependency otherwise, and a boostmtree upgrade must rerun the pilots. hvtiRtemplates is deliberately not keyed, so a patch release does not rerun an hour of pilots.
- News goes in `news/<branch>.md`, never `NEWS.md`. No `Version:` change.

## File structure

- Create `R/tune-mtry.R`: `tune_mtry()` (exported), `.mtry_candidates()`, `.sample_patients()`, `.pilot_fit()`, `.pilot_score()`.
- Create `tests/testthat/test-tune-mtry.R`.
- Modify `inst/templates/30_analyses/nb-boostmtree.qmd`: the `MTRY` comment, the fit chunk, and a new `tbl-mtry` chunk.
- Modify `tests/testthat/test-nb-boostmtree.R`, `inst/templates/README.md`; add `news/feat-mtry-tuning.md`.
- Generated: `NAMESPACE`, `man/tune_mtry.Rd`.

---

### Task 0: confirm the prerequisites

- [ ] **Step 1:** `git fetch origin && git merge-base --is-ancestor <#370 merge commit> origin/main && git merge-base --is-ancestor <#366 merge commit> origin/main`. Get each merge commit from `gh pr view 370 --json mergeCommit -q .mergeCommit.oid` (and 366). If either PR is not merged, STOP and report BLOCKED: this plan needs both.
- [ ] **Step 2:** `git merge origin/main` into the branch, and confirm `grep -n "^MTRY <- NULL" inst/templates/30_analyses/nb-boostmtree.qmd` and `grep -n "guard_long_fit" inst/templates/30_analyses/nb-boostmtree.qmd` both find a line.

---

### Task 1: the helpers and `tune_mtry()`

**Files:** Create `R/tune-mtry.R`; Test `tests/testthat/test-tune-mtry.R`.

**Interfaces (produces):**
- `.mtry_candidates(p)`: integer vector, decreasing, unique.
- `.sample_patients(id, n_patients, y = NULL, family = NULL)`: logical vector, the same length as `id`, `TRUE` for every row of each sampled patient; for an ordinal or nominal `family`, topped up so every non-missing level of `y` appears.
- `.pilot_score(fit)`: `list(best_m = <integer vector, one per component>, score = <numeric(1), mean l2 at best M>)`.
- `.pilot_fit(x, tm, id, y, family, mtry, M, nu, cores, ...)`: fits one pilot and returns `.pilot_score(fit)`.
- `tune_mtry(x, tm, id, y, family, candidates = NULL, n_patients = 1000L, M = 50L, nu = 0.2, cores = 1L, ...)`: returns `list(table = data.frame(mtry, best_m, cv_error, chosen, error), mtry = <integer(1)>)`. `best_m` is a character such as `"37"` or `"37/41"` across components; `error` is the condition message for a failed candidate, `NA` otherwise.

- [ ] **Step 1: Write the failing tests**

```r
# tests/testthat/test-tune-mtry.R
test_that("the default candidates span every predictor down to the square root", {
  expect_identical(.mtry_candidates(30L), c(30L, 15L, 10L, 5L))
  expect_identical(.mtry_candidates(4L), c(4L, 2L, 1L))
  expect_identical(.mtry_candidates(1L), 1L)
})

test_that("the subsample keeps each patient's rows together, and is reproducible", {
  id <- rep(sprintf("p%03d", 1:50), times = rep(1:5, 10))
  set.seed(1); a <- .sample_patients(id, 10L)
  set.seed(1); b <- .sample_patients(id, 10L)
  expect_identical(a, b)
  expect_length(unique(id[a]), 10L)
  for (p in unique(id[a])) expect_true(all(a[id == p]))
  expect_true(all(.sample_patients(id, 1000L)))
})

test_that("an ordinal or nominal sample holds every response level, however rare", {
  id <- rep(sprintf("p%03d", 1:200), each = 3)
  y <- rep(c(rep(0L, 199 * 3), 2L, 2L, 2L), 1)  # level 2 belongs to one patient only
  y[1:3] <- 1L
  for (family in c("ordinal", "nominal")) {
    for (s in 1:20) {
      set.seed(s)
      keep <- .sample_patients(id, 5L, y, family)
      expect_setequal(unique(y[keep]), c(0L, 1L, 2L))
      expect_lte(length(unique(id[keep])), 5L + 2L)
    }
  }
  set.seed(1)
  expect_length(unique(id[.sample_patients(id, 5L, y, "continuous")]), 5L)
})

test_that("the lowest score wins, a tie goes to the larger mtry, and a failure is recorded", {
  scores <- c(`8` = 0.50, `4` = 0.40, `2` = 0.40, `1` = NA)
  local_mocked_bindings(.pilot_fit = function(..., mtry) {
    if (is.na(scores[[as.character(mtry)]])) stop("pilot failed for ", mtry)
    list(best_m = 7L, score = scores[[as.character(mtry)]])
  })
  x <- data.frame(a = 1:4, b = 1:4)
  set.seed(1)
  out <- tune_mtry(x, tm = 1:4, id = c(1, 1, 2, 2), y = 1:4, family = "continuous", candidates = c(8L, 4L, 2L, 1L))
  expect_identical(out$mtry, 4L)
  expect_identical(out$table$chosen, c(FALSE, TRUE, FALSE, FALSE))
  expect_match(out$table$error[4], "pilot failed for 1")
  expect_true(all(is.na(out$table$error[1:3])))
})

test_that("every pilot failing stops with the first error", {
  local_mocked_bindings(.pilot_fit = function(..., mtry) stop("boom ", mtry))
  x <- data.frame(a = 1:4)
  expect_error(tune_mtry(x, 1:4, c(1, 1, 2, 2), 1:4, "continuous", candidates = c(2L, 1L)), "boom 2")
})

test_that("tune_mtry() checks its arguments", {
  x <- data.frame(a = 1:4)
  expect_error(tune_mtry(x, 1:4, c(1, 1, 2, 2), 1:4, "continuous", candidates = c(0L, 1L)), "candidates")
  expect_error(tune_mtry(x, 1:4, c(1, 1, 2, 2), 1:4, "continuous", n_patients = 0L), "n_patients")
})

test_that("a real pilot on simulated data returns a score and best M per component", {
  skip_if_not_installed("boostmtree", minimum_version = "2.0.4")
  skip_on_cran()
  set.seed(7)
  s <- boostmtree::simLong(n = 40, N = 5, model = 2, family = "continuous")$data.list
  out <- tune_mtry(s$features, s$time, s$id, s$y, "continuous", candidates = c(4L, 2L), M = 5L, nu = 0.5)
  expect_true(out$mtry %in% c(4L, 2L))
  expect_true(all(is.finite(out$table$cv_error)))
  expect_identical(sum(out$table$chosen), 1L)
})
```

- [ ] **Step 2: Run them to see them fail**

Run: `NOT_CRAN=true Rscript -e 'devtools::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-tune-mtry.R")'`
Expected: FAIL, `could not find function ".mtry_candidates"`.

- [ ] **Step 3: Implement**

```r
# R/tune-mtry.R
.mtry_candidates <- function(p) {
  unique(sort(pmax(1L, as.integer(round(c(p, p / 2, p / 3, sqrt(p))))), decreasing = TRUE))
}

.sample_patients <- function(id, n_patients, y = NULL, family = NULL) {
  patients <- unique(id)
  if (length(patients) <= n_patients) return(rep(TRUE, length(id)))
  keep <- id %in% sample(patients, n_patients)
  # A pilot that never sees a level cannot fit it, so an ordinal or nominal sample is topped up with
  # one patient for each level the draw missed. sample.int() because sample() of one value counts from 1.
  if (!is.null(y) && isTRUE(family %in% c("ordinal", "nominal"))) {
    for (lev in setdiff(unique(y[!is.na(y)]), unique(y[keep]))) {
      has <- setdiff(unique(id[!is.na(y) & y == lev]), unique(id[keep]))
      keep <- keep | id == has[sample.int(length(has), 1L)]
    }
  }
  keep
}

.pilot_score <- function(fit) {
  err <- if (is.matrix(fit$err.rate)) list(fit$err.rate) else fit$err.rate
  best_m <- as.integer(fit$m.opt)
  list(best_m = best_m, score = mean(mapply(function(e, m) e[m, "l2"], err, best_m)))
}

.pilot_fit <- function(x, tm, id, y, family, mtry, M, nu, cores, ...) {
  fit <- boostmtree::boostmtree(x = x, tm = tm, id = id, y = y, family = family, M = M, nu = nu, mtry = mtry,
                                mod.grad = TRUE, cv.flag = TRUE, verbose = FALSE,
                                control = boostmtree::boostmtree.control(cv.cores = cores), ...)
  .pilot_score(fit)
}

#' Choose boostmtree's mtry by cross-validated pilots on a patient subsample
#'
#' @description
#' Fits one cross-validated boostmtree pilot for each candidate \code{mtry} on
#' a random subsample of whole patients, and chooses the candidate with the
#' lowest cross-validated error. The pilots are short and the subsample small,
#' because cross-validation costs about the square of the number of patients:
#' 1,000 of 5,500 patients costs about 3\% of a full fit per pilot.
#'
#' @details
#' The error is the standardized \code{l2} error at each response component's
#' cross-validated best M, averaged over components (an ordinal or nominal fit
#' has several). A tie goes to the larger \code{mtry}. A candidate whose pilot
#' fails is recorded in the table and left out; if every pilot fails, the
#' first error is raised. For an ordinal or nominal response the subsample
#' holds every level: a level the draw missed adds one patient who has it.
#' The subsample draws from R's random number
#' generator, so seed it first (\code{nb-boostmtree} does, through
#' \code{cache_fit(seed = )}).
#'
#' @param x,tm,id,y,family As for \code{boostmtree::boostmtree()}.
#' @param candidates Integer vector of \code{mtry} values, or \code{NULL} for
#'   every predictor, half, a third and the square root.
#' @param n_patients Integer(1). Patients in the subsample; every patient
#'   when there are fewer.
#' @param M,nu The pilots' boosting steps and learning rate.
#' @param cores Integer(1). Passed to \code{boostmtree.control(cv.cores = )}.
#' @param ... Passed to \code{boostmtree::boostmtree()} for every pilot, for
#'   example \code{progress} or \code{na.action}.
#' @return A list: \code{table}, a data frame with one row per candidate
#'   (\code{mtry}, \code{best_m}, \code{cv_error}, \code{chosen},
#'   \code{error}), and \code{mtry}, the chosen value.
#' @examples
#' \donttest{
#' if (requireNamespace("boostmtree", quietly = TRUE)) {
#'   set.seed(7)
#'   s <- boostmtree::simLong(n = 40, N = 5, model = 2, family = "continuous")$data.list
#'   tune_mtry(s$features, s$time, s$id, s$y, "continuous", candidates = c(4L, 2L), M = 5L, nu = 0.5)$table
#' }
#' }
#' @export
tune_mtry <- function(x, tm, id, y, family, candidates = NULL, n_patients = 1000L, M = 50L, nu = 0.2,
                      cores = 1L, ...) {
  if (is.null(candidates)) candidates <- .mtry_candidates(ncol(x))
  if (!is.numeric(candidates) || !length(candidates) || anyNA(candidates) || any(candidates < 1) ||
        any(candidates != round(candidates))) {
    stop("tune_mtry(): `candidates` must be positive whole numbers.", call. = FALSE)
  }
  if (!is.numeric(n_patients) || length(n_patients) != 1L || is.na(n_patients) || n_patients < 1) {
    stop("tune_mtry(): `n_patients` must be a single positive number.", call. = FALSE)
  }
  candidates <- as.integer(candidates)
  keep <- .sample_patients(id, n_patients, y, family)
  results <- lapply(candidates, function(m) {
    tryCatch(.pilot_fit(x = x[keep, , drop = FALSE], tm = tm[keep], id = id[keep], y = y[keep], family = family,
                        mtry = m, M = M, nu = nu, cores = cores, ...),
             error = function(e) list(best_m = NA_integer_, score = NA_real_, error = conditionMessage(e)))
  })
  scores <- vapply(results, function(r) r$score, numeric(1))
  if (all(is.na(scores))) {
    stop("tune_mtry(): every pilot failed. The first error: ", results[[1L]]$error, call. = FALSE)
  }
  best <- min(scores, na.rm = TRUE)
  chosen_mtry <- max(candidates[!is.na(scores) & scores == best])
  table <- data.frame(
    mtry = candidates,
    best_m = vapply(results, function(r) paste(r$best_m, collapse = "/"), character(1)),
    cv_error = scores,
    chosen = candidates == chosen_mtry & !is.na(scores) & scores == best,
    error = vapply(results, function(r) if (is.null(r$error)) NA_character_ else r$error, character(1)),
    stringsAsFactors = FALSE
  )
  list(table = table, mtry = chosen_mtry)
}
```

Note: `tune_mtry()` itself does not call `requireNamespace()`; `.pilot_fit()` uses `boostmtree::`, and its error is caught per candidate, so a missing boostmtree surfaces as "every pilot failed" naming the missing package. That keeps the mocked tests independent of boostmtree.

- [ ] **Step 4: Document and run the tests**

Run: `NOT_CRAN=true Rscript -e 'devtools::document(); devtools::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-tune-mtry.R")'` (with `R_LIBS` naming a library that has boostmtree >= 2.0.4, so the real-pilot test runs). Expected: all PASS, SKIP 0.

- [ ] **Step 5: Mutation checks**

(a) Change `max(` to `min(` in `chosen_mtry <-`: the tie test must fail. (b) Change `.sample_patients()` to `sample(c(TRUE, FALSE), length(id), replace = TRUE)`: the subsample test must fail. (c) Delete the top-up loop: the rare-level test must fail. Restore all three.

- [ ] **Step 6: Commit**

```bash
git add R/tune-mtry.R tests/testthat/test-tune-mtry.R NAMESPACE man/tune_mtry.Rd
git commit -m "feat: tune_mtry() chooses mtry by cross-validated pilots on a patient subsample"
```

---

### Task 2: `MTRY = "tune"` in `nb-boostmtree`

**Files:** Modify `inst/templates/30_analyses/nb-boostmtree.qmd`; Test `tests/testthat/test-nb-boostmtree.R`.

**Interfaces (consumes):** `hvtiRtemplates::tune_mtry(x, tm, id, y, family, ..., cores)` returning `list(table, mtry)`, from Task 1; `guard_long_fit()` and `guard_memory()`; `hvtiRutilities::cache_fit()` and `cache_would_fit()` (>= 1.5.11), both taking `packages =`; the fit chunk's `CACHE_DIR`, `.patient`, `.predictors`, `.time`, `.response`, `d`, `.job`.

⚠️ The template calls `hvtiRtemplates::tune_mtry()`, never a bare `tune_mtry()`: a job attaches only boostmtree, ggBoostedTrees and hvtiRutilities, so a bare call fails in every real render. Do **not** bind `tune_mtry` in `nb_env()`; that binding would hide exactly this failure. The chunk tests mock it in the package namespace with `local_mocked_bindings(.package = "hvtiRtemplates")`, and one render test runs the real function end to end.

- [ ] **Step 1: Write the failing tests** (append to `tests/testthat/test-nb-boostmtree.R`)

```r
nb_fake_tuning <- function(mtry = 3L) {
  function(...) list(table = data.frame(mtry = c(mtry, 1L), best_m = c("4", "5"), cv_error = c(0.2, 0.3),
                                        chosen = c(TRUE, FALSE), error = NA_character_), mtry = mtry)
}

test_that("MTRY = \"tune\" writes the tuned mtry into the fit's call and shows the choice", {
  nb_skip_unless_stack()
  local_child_chunks()
  local_mocked_bindings(tune_mtry = nb_fake_tuning(3L), .package = "hvtiRtemplates")
  seen <- NULL
  env <- nb_env(nb_study())
  env$boostmtree <- function(...) {
    seen <<- list(...)$mtry
    boostmtree::boostmtree(...)
  }
  out <- utils::capture.output(nb_run(c("set", "edit-study-choices", "tbl-data", "fit", "tbl-mtry"), env,
                                      nb_choices(MTRY = "tune")))
  expect_identical(seen, 3L)
  expect_identical(env$.fit_code$mtry, 3L)  # a literal, so the key reads the value used
  expect_true(any(grepl("Chosen", out, fixed = TRUE)))
})

test_that("an untuned job's fit call, and so its cache key, is unchanged", {
  nb_skip_unless_stack()
  env <- nb_env(nb_study())
  utils::capture.output(nb_run(c("set", "edit-study-choices", "tbl-data", "fit"), env, nb_choices(MTRY = NULL)))
  expect_identical(env$.fit_code$mtry, quote(MTRY))
  expect_false(exists(".tune_code", envir = env, inherits = FALSE))
})

test_that("the tuning is keyed on boostmtree's version, and a cached rerender asks no memory", {
  nb_skip_unless_stack()
  local_mocked_bindings(tune_mtry = nb_fake_tuning(3L), .package = "hvtiRtemplates")
  root <- nb_study()
  env <- nb_env(root)
  utils::capture.output(nb_run(c("set", "edit-study-choices", "tbl-data", "fit"), env, nb_choices(MTRY = "tune")))
  # refit = TRUE answers by the key alone: FALSE when the stored key matches, TRUE when it does not.
  would <- function(packages) hvtiRutilities::cache_would_fit("nb-boostmtree-mtry", env$.tune_code, seed = env$SEED,
                                                               dir = env$CACHE_DIR, refit = TRUE, packages = packages)
  expect_false(would("boostmtree"))
  expect_true(would(NULL))
  needs <- numeric()
  local_mocked_bindings(guard_memory = function(need_gib, ...) needs <<- c(needs, need_gib), .package = "hvtiRtemplates")
  env2 <- nb_env(root)
  utils::capture.output(nb_run(c("set", "edit-study-choices", "tbl-data", "fit"), env2,
                               nb_choices(MTRY = "tune", REFIT = FALSE)))
  expect_identical(needs, c(0, 0))  # the pilots' check, then the fit's
})

test_that("an MTRY that is not NULL, a positive integer or \"tune\" stops naming MTRY", {
  nb_skip_unless_stack()
  env <- nb_env(nb_study())
  expect_error(utils::capture.output(nb_run(c("set", "edit-study-choices", "tbl-data", "fit"), env,
                                            nb_choices(MTRY = "auto"))), "MTRY", fixed = TRUE)
})
```

And, beside the existing end-to-end render test, one that renders with the real `tune_mtry()` (no mock), so a bare or unattached call fails here rather than in a study:

```r
test_that("nb-boostmtree renders end to end with MTRY = \"tune\"", {
  # the same skips and setup as "nb-boostmtree scaffolds and renders end to end", with MTRY <- "tune"
  # substituted into the scaffolded job before render_job()
  ...
  expect_true(any(grepl("Choosing mtry", page, fixed = TRUE)))
})
```

Fill in the `...` from the existing render test; do not weaken its MRN scan. If the pilots make this test slower than the existing render test by more than a minute, lower `M` through the template's own pilot setting rather than skipping the test.

- [ ] **Step 2: Run them to see them fail**

Run: `R_LIBS=<library with boostmtree 2.0.8 and this branch installed> _R_CHECK_LIMIT_CORES_=TRUE NOT_CRAN=true Rscript -e 'devtools::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-nb-boostmtree.R")'`
Expected: the new tests FAIL, except "an untuned job's fit call" which already passes on `main`: it is the guard that the change keeps it passing.

- [ ] **Step 3: Change the template.**

(a) Extend the `MTRY` comment, ending it with: `"tune" chooses it by cross-validated pilots on a subsample of 1,000 patients (hvtiRtemplates::tune_mtry()), at about 3% of a full fit per candidate, and shows the choice in the report.`

(b) In the fit chunk, after `.patient <- ...` and **before** `.fit_code <- quote(`, insert:

```r
# MTRY is NULL (every predictor), a positive whole number, or "tune": cross-validated pilots on a
# patient subsample choose it. The pilots are settled here, before the fit's call is built, because
# the fit's cache key and its memory check both depend on the mtry chosen. They are guarded and
# cached apart from the fit, so a change to M or NU alone does not rerun them.
if (!(is.null(MTRY) || identical(MTRY, "tune") ||
        (is.numeric(MTRY) && length(MTRY) == 1L && !is.na(MTRY) && MTRY >= 1 && MTRY == round(MTRY)))) {
  stop("MTRY must be NULL, a positive whole number, or \"tune\".", call. = FALSE)
}
mtry_choice <- NULL
if (identical(MTRY, "tune")) {
  hvtiRtemplates::guard_long_fit("nb-boostmtree-mtry", dir = CACHE_DIR,
                                 why = "cross-validated mtry pilots take an hour or more at study size",
                                 refit = REFIT)
  .tune_code <- quote(
    hvtiRtemplates::tune_mtry(x = d[.predictors], tm = d[[.time]], id = .patient, y = d[[.response]], family = FAMILY,
                              cores = get("CORES"), progress = get(".job")$progress("pilot iteration"))
  )
  # One pilot at a time, so the need is one pilot's: tune_mtry()'s 1,000 patients and M = 50.
  .n_pilot <- min(1000L, length(unique(.patient)))
  .need_pilot <- function(k) {
    hvtiRtemplates:::.boostmtree_need_gib(.n_pilot, round(nrow(d) * .n_pilot / length(unique(.patient))), FAMILY, k, 50L)
  }
  # packages = "boostmtree": the fit runs inside tune_mtry(), where the key cannot see it.
  .tuning <- hvtiRutilities::cache_would_fit("nb-boostmtree-mtry", .tune_code, seed = SEED, dir = CACHE_DIR,
                                             refit = REFIT, packages = "boostmtree")
  hvtiRtemplates::guard_memory(if (.tuning) .need_pilot(CORES) else 0,
                               sprintf("the mtry pilots (%s patients)", format(.n_pilot, big.mark = ",")),
                               cores = CORES, cores_fit = .need_pilot)
  mtry_choice <- cache_fit("nb-boostmtree-mtry", .tune_code, seed = SEED, dir = CACHE_DIR, refit = REFIT,
                           packages = "boostmtree")
}
```

(c) Leave `.fit_code <- quote(...)` exactly as it is, `mtry = MTRY` included, and immediately after it add:

```r
# The tuned value goes into the call as a literal, so the fit's key reads the mtry used. An untuned
# job's call is untouched, and so is the key of a fit it has already cached.
if (!is.null(mtry_choice)) .fit_code <- do.call(substitute, list(.fit_code, list(MTRY = mtry_choice$mtry)))
```

The fit's own `.need`, `cache_would_fit()`, `guard_memory()` and `cache_fit()` lines are unchanged and now follow the tuning.

(d) After the `tbl-fit-summary` chunk, add:

````
```{r}
#| label: tbl-mtry
#| tbl-cap: "Choosing mtry: cross-validated pilots on a patient subsample"
#| eval: !expr identical(MTRY, "tune")
# Each candidate's pilot error (standardized l2 at its best M, averaged over response
# components); the lowest is used for the full fit, and a tie goes to the larger mtry.
knitr::kable(mtry_choice$table[c("mtry", "best_m", "cv_error", "chosen")],
             col.names = c("mtry", "Best M (pilot)", "Cross-validated error", "Chosen"))
```
````

and add one row to the `tbl-fit` table: `quantity = "mtry"`, `value = if (is.null(mtry_choice)) { if (is.null(MTRY)) "every predictor" else MTRY } else mtry_choice$mtry`.

⚠️ Read `.job$progress()` (`R/job-setup.R`) before relying on it for four pilots in a row. If a reporter cannot be reused across fits, or counts past its unit's expected total, report NEEDS_CONTEXT rather than dropping the progress argument.

- [ ] **Step 4: Run the whole nb test file** (command as in Step 2). Expected: FAIL 0, SKIP 0. The existing test that a cached rerender still records the memory check must still pass unchanged. The `tbl-mtry` table's column header "Chosen" must appear in the captured output; if `nb_run()` does not honour the chunk's `eval: !expr` option, report NEEDS_CONTEXT rather than weakening the assertion.

- [ ] **Step 5: Mutation checks**, each restored before the next: (a) delete the `do.call(substitute, ...)` line: the first new test must fail. (b) Change `hvtiRtemplates::tune_mtry` to `tune_mtry`: the real render test must fail. (c) Drop `packages = "boostmtree"` from both tuning calls: the keyed-on-version test must fail. (d) Move the `do.call(substitute, ...)` line below the fit's `cache_would_fit()`: the zero-memory test must fail, because the fit's memory check then keys a call the cache never stored. That is the test holding the order.

- [ ] **Step 6: Commit**

```bash
git add inst/templates/30_analyses/nb-boostmtree.qmd tests/testthat/test-nb-boostmtree.R
git commit -m "feat(nb-boostmtree): MTRY = \"tune\" chooses mtry by cross-validated pilots"
```

---

### Task 3: documentation, news, and the full gate

- [ ] **Step 1:** In `inst/templates/README.md`, under the `nb-boostmtree` notes (or the "Long-running jobs" section if that is nearer), add:

```markdown
`nb-boostmtree`'s `MTRY` can be `"tune"`: `tune_mtry()` fits a short
cross-validated pilot for each candidate (every predictor, half, a third, the
square root) on 1,000 patients, and the full fit uses the one with the lowest
error. Each pilot costs about 3% of a full fit at 5,500 patients. The defaults
are provisional until the two-study experiment in
`dev/specs/2026-10-20-mtry-tuning-design.md` (section 6) confirms them.
```

- [ ] **Step 2:** `news/feat-mtry-tuning.md`:

```markdown
* New `tune_mtry()` chooses boostmtree's `mtry` by cross-validated pilot fits
  on a random subsample of whole patients, and `nb-boostmtree` runs it when
  `MTRY <- "tune"`, caching the choice apart from the fit and showing each
  candidate's error in the report. The defaults (four candidates, 1,000
  patients, `M = 50`, `nu = 0.2`) are provisional, pending a two-study check.
```

- [ ] **Step 3:** `devtools::document()`; `lintr::lint_package()` (expect none); `_R_CHECK_LIMIT_CORES_=TRUE NOT_CRAN=true devtools::test()` (expect FAIL 0, WARN 0; report SKIP); `devtools::check()` (expect 0/0/0). Run the suite and the check with `R_LIBS` naming a library that holds boostmtree >= 2.0.4 and this branch installed (`R CMD INSTALL -l <lib> .`), because the render tests use the installed package.

- [ ] **Step 4:** Commit `inst/templates/README.md` and `news/feat-mtry-tuning.md`, plus any `man/` or `NAMESPACE` changes.

---

### Task 4: the experiment (server, outside the repository)

Staged for John, per spec section 6. Not a repository change.

- [ ] **Step 1:** Write `/studies/general/_development/mtry-tuning-experiment-<date>/` with:
  - `RUN-INSTRUCTIONS.md`;
  - `program/truth.R`: each candidate fitted on the full data of one study (args: study root, dataset, response, family, the study's WHERE). Writes `out/truth-<study>.csv` with `mtry, best_m, cv_error, elapsed_s`.
  - `program/pilots.R`: `tune_mtry()` at `n_patients` 500, 1000 and 2000, crossed with pilot `M` of 50 and 100, 3 seeds each. Writes `out/pilots-<study>.csv`.

  Read the data through `hvtiRtemplates::read_job_data()`, so the study's registered data, `WHERE` and the same-day rule apply. Print counts only, never identifiers.
- [ ] **Step 2:** The two studies: #1356 (`bdecho_day`, `mv_regn` ordinal, `iv_echo <= 21`) and COMMENCE (`bdamgcc`, `avmngrad` continuous), after COMMENCE is set up (its own task).
- [ ] **Step 3:** After the runs, write the guidance note: the agreement rate between pilot and truth winners, and the spread of `cv_error` across candidates. Then a follow-up PR updating `tune_mtry()`'s defaults if the data overturn them.
