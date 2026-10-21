# Job Progress Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A long hvtiRtemplates render reports its stage, its step within the stage, the time
elapsed and an estimate of the time left, both on request (`job_status()`) and as throttled
lines in its log; boostmtree 2.0.8 reports fit iterations and partial-effect predictions.

**Architecture:** A knitr chunk hook, installed by `.job_setup()`, records stages in
`<job>.run.progress`, a YAML file written atomically by the render process alone. A step
callback from `.job$progress(unit)` updates the same file and writes throttled lines to
`stderr()`, which reaches the render log and not the report. boostmtree gains a
`progress = NULL` argument on `boostmtree()` and `partial.plot()` that calls such a callback.
`job_status()` reads the file and prints a progress block.

**Tech Stack:** R, knitr chunk hooks, yaml, testthat 3, `testthat::local_mocked_bindings()`.

**Spec:** `dev/specs/2026-10-21-job-progress-design.md`.

## Global Constraints

- hvtiRtemplates work is on `spec/job-progress`, stacked on `spec/background-jobs` (#366). Do
  not touch #366's branch or its server proof. Open this PR against `main` only after #366 has
  merged: a stacked PR draws no Copilot review and reaches `main` unread.
- boostmtree work is on a new branch `feat/progress-callback`, cut from
  `origin/fix/predict-extrapolate-memory` (tip `22be929`, PR 26), in a worktree
  `~/Documents/GitHub/boostmtree_src-progress`. Never force-push. Do not edit PR 26's branch.
- boostmtree: **no version bump** (DESCRIPTION stays `2.0.8`), a NEWS bullet under the
  existing `# boostmtree 2.0.8` heading, no tag. John cuts 2.0.8.
- hvtiRtemplates: no version bump in these PRs; a `news/<branch>.md` fragment
  (`news/spec-job-progress.md`). Versions are straight three digits, patch digit only.
- Roxygen in hvtiRtemplates is **Rd markup**, not markdown. boostmtree's `man/*.Rd` are
  hand-written (no roxygen): edit the `.Rd` files directly and keep `\usage` in step with the
  code, or codoc fails.
- Lines up to 135 characters in hvtiRtemplates (`.lintr`).
- Progress is advisory: nothing in it may stop a render, a fit or `job_status()`.
- Log lines go to `stderr()` via `cat(..., file = stderr())`, never `message()` (knitr
  captures messages into the report).
- Run tests with `NOT_CRAN=true _R_CHECK_LIMIT_CORES_=TRUE`. Never `git add -A` after a test
  run: failing testthat runs leave `tests/testthat/_problems/`.
- Done for hvtiRtemplates: `devtools::test()` passes, `devtools::check()` 0/0/0,
  `devtools::document()` run with `man/` and `NAMESPACE` committed. Done for boostmtree:
  `R CMD check --as-cran` (with manual) 0 errors / 0 warnings, notes unchanged from PR 26.
- Run a local `/code-review` before each PR (Copilot's quota is exhausted) and say so in the
  PR body.

## Order

Part A (boostmtree) and Part B (hvtiRtemplates) are independent and may run in parallel.
Part C waits for both, and for John to tag boostmtree 2.0.8.

---

## Part A: boostmtree 2.0.8

### Task A1: `progress` on `boostmtree()`

**Files:**
- Create: `boostmtree/R/boostmtree_progress.R`
- Modify: `boostmtree/R/boostmtree.R` (signature, line ~27; `boostmtree.fit.tree(list(...))`, line ~123)
- Modify: `boostmtree/R/boostmtree_fit_tree.R` (end of the `for (m in seq_len(model.info$M))` body, line ~868)
- Modify: `boostmtree/man/boostmtree.Rd`
- Test: `boostmtree/tests/testthat/test-progress.R`

**Interfaces:**
- Produces: `boostmtree.progress.caller(progress)`: returns `NULL` for `NULL`, else a
  `function(step, steps)` that calls `progress(step, steps)`, turns an error into one
  warning and stops calling. Stops if `progress` is neither `NULL` nor a function.
- Produces: `boostmtree(..., progress = NULL)`; the callback is called as `progress(m, M)`
  after each boosting iteration, in the parent process only.

- [ ] **Step 1: Make the worktree**

```bash
cd ~/Documents/GitHub/boostmtree_src && git fetch origin && \
  git worktree add ../boostmtree_src-progress -b feat/progress-callback origin/fix/predict-extrapolate-memory && \
  git -C ../boostmtree_src-progress log --oneline -1
```
Expected: `22be929 ...` (or a later tip of PR 26 if it moved; use whatever PR 26's head is).

- [ ] **Step 2: Write the failing tests**

`boostmtree/tests/testthat/test-progress.R`:

```r
# progress = reports how far a fit or a partial.plot() has got, for callers that
# cannot see verbose's progress bar (knitr captures it into the report).

progress.data <- function() {
  set.seed(2)
  simLong(n = 30, n.time = 4, rho = 0.8, model = 2, family = "continuous", q = 0)$data.list
}

test_that("progress is called once per boosting iteration, in order, with and without cv.flag", {
  d <- progress.data()
  for (cv in c(FALSE, TRUE)) {
    seen <- list()
    set.seed(7)
    boostmtree(d$features, d$time, d$id, d$y, family = "continuous", M = 10, cv.flag = cv, verbose = FALSE,
               progress = function(step, steps) seen[[length(seen) + 1L]] <<- c(step, steps))
    expect_equal(seen, lapply(1:10, function(m) c(m, 10)))
  }
})

test_that("a failing progress callback warns once and leaves the fit unchanged", {
  d <- progress.data()
  set.seed(7)
  a <- boostmtree(d$features, d$time, d$id, d$y, family = "continuous", M = 10, verbose = FALSE)
  calls <- 0L
  set.seed(7)
  expect_warning(
    b <- boostmtree(d$features, d$time, d$id, d$y, family = "continuous", M = 10, verbose = FALSE,
                    progress = function(step, steps) {
                      calls <<- calls + 1L
                      stop("boom")
                    }),
    "boom"
  )
  expect_identical(calls, 1L)
  keep <- setdiff(names(a), "call")
  expect_equal(unclass(b)[keep], unclass(a)[keep])
})

test_that("progress must be NULL or a function", {
  d <- progress.data()
  expect_error(boostmtree(d$features, d$time, d$id, d$y, family = "continuous", M = 2, verbose = FALSE, progress = 1),
               "`progress` must be NULL or a function")
})
```

- [ ] **Step 3: Run them to see them fail**

Run: `cd ~/Documents/GitHub/boostmtree_src-progress/boostmtree && Rscript -e 'devtools::test(filter = "progress")'`
Expected: FAIL, `unused argument (progress = ...)`.

- [ ] **Step 4: Implement**

`boostmtree/R/boostmtree_progress.R`:

```r
# A caller's progress callback, called as progress(step, steps). A callback that
# fails warns once and is not called again, so reporting can never stop a fit.
boostmtree.progress.caller <- function(progress) {
  if (is.null(progress)) return(NULL)
  if (!is.function(progress)) stop("`progress` must be NULL or a function(step, steps).")
  state <- new.env(parent = emptyenv())
  state$live <- TRUE
  function(step, steps) {
    if (!state$live) return(invisible(NULL))
    tryCatch(progress(step, steps), error = function(e) {
      state$live <- FALSE
      warning("`progress` failed and will not be called again: ", conditionMessage(e), call. = FALSE)
    })
    invisible(NULL)
  }
}
```

In `boostmtree/R/boostmtree.R`, add the argument after `control`:

```r
  control = boostmtree.control(),
  progress = NULL
) {
  family <- boostmtree.match.family(family)
  progress <- boostmtree.progress.caller(progress)
```

and in the `boostmtree.fit.tree(list(...))` call, after `univariate = preprocessed$univariate`:

```r
    univariate = preprocessed$univariate,
    progress = progress
  ))
```

Do NOT add `progress` to the `boostmtree.build.object(model.info = list(...))` call: a
callback must never be saved inside the fit.

In `boostmtree/R/boostmtree_fit_tree.R`, as the last statement of the
`for (m in seq_len(model.info$M))` body (after the `for (q ...)` loop closes, before the
`}` that closes the `m` loop, line ~868):

```r
    if (!is.null(model.info$progress)) {
      model.info$progress(m, model.info$M)
    }
```

In `boostmtree/man/boostmtree.Rd`, add `progress = NULL` after `control = boostmtree.control()`
in `\usage`, and after `\item{verbose}`:

```
  \item{progress}{\code{NULL} (the default), or a function \code{function(step, steps)}
    called after each boosting iteration with the iteration done and \code{M}. It is called
    in the main process only, never from a cross-validation worker. Use it to report
    progress where \code{verbose} cannot be seen, such as a document being knitted, which
    captures the progress bar into its output. An error in it becomes one warning and the
    fit carries on.}
```

- [ ] **Step 5: Run the tests**

Run: `Rscript -e 'devtools::test(filter = "progress")'` then `Rscript -e 'devtools::test()'`
Expected: all PASS; the full suite unchanged from PR 26.

- [ ] **Step 6: Commit**

```bash
git add boostmtree/R/boostmtree_progress.R boostmtree/R/boostmtree.R boostmtree/R/boostmtree_fit_tree.R \
  boostmtree/man/boostmtree.Rd boostmtree/tests/testthat/test-progress.R
git commit -m "feat: progress callback on boostmtree(), one call per boosting iteration"
```

### Task A2: `progress` on `partial.plot()`, and NEWS

**Files:**
- Modify: `boostmtree/R/partial_plot.boostmtree.R` (signature ~line 325; the `for (nm in x.var.names)` loop ~366-400)
- Modify: `boostmtree/man/partial.plot.boostmtree.Rd`
- Modify: `boostmtree/NEWS.md`
- Test: `boostmtree/tests/testthat/test-progress.R`

**Interfaces:**
- Consumes: `boostmtree.progress.caller()` from A1.
- Produces: `partial.plot(..., progress = NULL)`, called as `progress(step, steps)` after each
  per-grid-point prediction; `steps` is the total over all variables, fixed from the first call.

- [ ] **Step 1: Write the failing test** (append to `test-progress.R`)

```r
test_that("partial.plot reports one step per (variable, grid point), with steps fixed from the start", {
  d <- progress.data()
  set.seed(7)
  fit <- boostmtree(d$features, d$time, d$id, d$y, family = "continuous", M = 5, cv.flag = TRUE, verbose = FALSE)
  seen <- list()
  partial.plot(fit, x.var.names = names(d$features)[1:2], n.points = 3, output = "data", verbose = FALSE,
               progress = function(step, steps) seen[[length(seen) + 1L]] <<- c(step, steps))
  steps <- vapply(seen, `[[`, 0, 2)
  expect_true(length(seen) >= 2L && length(seen) <= 6L)
  expect_true(all(steps == length(seen)))
  expect_equal(vapply(seen, `[[`, 0, 1), seq_along(seen))
})

test_that("partial.plot's result does not depend on progress", {
  d <- progress.data()
  set.seed(7)
  fit <- boostmtree(d$features, d$time, d$id, d$y, family = "continuous", M = 5, verbose = FALSE)
  a <- partial.plot(fit, n.points = 3, output = "data", verbose = FALSE)
  b <- partial.plot(fit, n.points = 3, output = "data", verbose = FALSE, progress = function(step, steps) NULL)
  expect_equal(b[setdiff(names(b), "call")], a[setdiff(names(a), "call")])
})
```

- [ ] **Step 2: Run to see it fail**

Run: `Rscript -e 'devtools::test(filter = "progress")'`
Expected: the two new tests FAIL. `progress` falls into `...` and reaches
`generic.predict.boostmtree()`, which errors or ignores it, and `seen` stays empty.

- [ ] **Step 3: Implement**

Signature: add `progress = NULL` after `use.cv.flag = NULL,` and before `...`.

After the `use.cv.flag` checks and before `curves <- lapply(...)`:

```r
  progress <- boostmtree.progress.caller(progress)
  # Every grid is resolved first, so the total number of predictions is known
  # from the first progress call.
  x.infos <- lapply(x.var.names, function(nm) {
    boostmtree.effect.resolve.x.values(
      x.column = work.x[[nm]],
      x.var.values = x.var.values,
      x.var.name = nm,
      n.points = n.points
    )
  })
  names(x.infos) <- x.var.names
  steps <- sum(vapply(x.infos, function(info) length(info$values), 0L))
  step <- 0L
```

In the loop, replace the `x.info <- boostmtree.effect.resolve.x.values(...)` block with
`x.info <- x.infos[[nm]]`, and after `rm(pred.object)`:

```r
      rm(pred.object)
      step <- step + 1L
      if (!is.null(progress)) {
        progress(step, steps)
      }
```

`partial.plot.boostmtree.Rd`: add `progress = NULL` to the `\method{partial.plot}{boostmtree}`
usage, after `use.cv.flag = NULL`, and:

```
  \item{progress}{\code{NULL} (the default), or a function \code{function(step, steps)}
    called after each prediction, one per variable and grid point. \code{steps} is the
    total over all variables and is the same on every call. An error in it becomes one
    warning and the computation carries on.}
```

`NEWS.md`, under `# boostmtree 2.0.8`, a new `## New features` section above `## Bug fixes`:

```markdown
## New features

* `boostmtree()` and `partial.plot()` take `progress`, a function called as
  `progress(step, steps)` after each boosting iteration and after each partial-effect
  prediction. It reports progress where `verbose` cannot be seen: a knitted document
  captures the progress bar into its output, so a long render showed only which chunk
  it was in. An error in the callback becomes one warning and the fit carries on.
```

- [ ] **Step 4: Run the tests, then the check**

Run: `Rscript -e 'devtools::test()'`, then from the repo root
`R CMD build boostmtree && R CMD check --as-cran boostmtree_2.0.8.tar.gz`
Expected: tests PASS; check 0 errors, 0 warnings, no codoc mismatch, notes as on PR 26.

- [ ] **Step 5: Commit, push, PR**

```bash
git add boostmtree/R/partial_plot.boostmtree.R boostmtree/man/partial.plot.boostmtree.Rd boostmtree/NEWS.md \
  boostmtree/tests/testthat/test-progress.R
git commit -m "feat: progress callback on partial.plot(), one call per prediction"
git push -u origin feat/progress-callback
```
Open the PR against `main` after PR 26 merges; if PR 26 is still open, ask John before
opening it against `fix/predict-extrapolate-memory`.

---

## Part B: hvtiRtemplates

All paths relative to `~/Documents/GitHub/hvtiRtemplates-progress` (branch `spec/job-progress`).

### Task B1: the progress record and the step callback

**Files:**
- Create: `R/job-progress.R`
- Modify: `R/background-job.R` (`.run_files()`, line 1-4)
- Test: `tests/testthat/test-job-progress.R`, `tests/testthat/test-background-job.R`

**Interfaces:**
- Consumes: `.write_status(file, ...)` and `.stamp(time)` from `R/background-job.R`.
- Produces:
  - `.run_files(path)$progress`: `<stem>.run.progress`.
  - `.now()`: `Sys.time()`, the one clock, mocked in tests.
  - `.progress_every()`: minutes, from `getOption("hvtiRtemplates.progress_every", 10)`.
  - `.fmt_dur(secs)`: `"45s"`, `"12m"`, `"1h03m"`.
  - `.parse_stamp(x)`: the inverse of `.stamp()`.
  - `.progress_eta(elapsed, step, steps)`: seconds left, `NA` at step 0.
  - `.progress_state`: environment holding `file`, `stages`, `started`, `stage`,
    `stage_index`, `stage_started`, `step`, `steps`, `unit`, `done`, `last_log`.
  - `.progress_begin(file, stages)`, `.progress_stage(label, before)`,
    `.progress_step(unit)` returning `function(step, steps)`.

- [ ] **Step 1: Write the failing tests**

In `test-background-job.R`, the "run files sit beside the job" test gains:

```r
  expect_identical(f$progress, "/s/analyses/nb.x.run.progress")
```

`tests/testthat/test-job-progress.R`:

```r
progress_file <- function() {
  file.path(withr::local_tempdir(.local_envir = parent.frame()), "nb.x.y.boost.run.progress")
}

# A clock the test moves by hand.
local_clock <- function(start = as.POSIXct("2026-10-21 07:00:00"), .env = parent.frame()) {
  clock <- new.env()
  clock$now <- start
  testthat::local_mocked_bindings(.now = function() clock$now, .env = .env)
  clock
}

quietly <- function(code) utils::capture.output(code, type = "message")

test_that("durations read as seconds, minutes, or hours and minutes", {
  expect_identical(.fmt_dur(45), "45s")
  expect_identical(.fmt_dur(12 * 60 + 5), "12m")
  expect_identical(.fmt_dur(3780), "1h03m")
  expect_identical(.fmt_dur(-3), "0s")
})

test_that("the estimate is time per step times steps left, and unknown at step 0", {
  expect_equal(.progress_eta(100, 10, 50), 400)
  expect_true(is.na(.progress_eta(100, 0, 50)))
})

test_that("stages and steps are recorded, and a finished stage joins done", {
  clock <- local_clock()
  file <- progress_file()
  quietly(.progress_begin(file, c("tbl-data", "fit")))
  quietly(.progress_stage("tbl-data", TRUE))
  clock$now <- clock$now + 41
  quietly(.progress_stage("tbl-data", FALSE))
  quietly(.progress_stage("fit", TRUE))
  f <- .progress_step("iteration")
  clock$now <- clock$now + 60
  quietly(f(10L, 1000L))
  p <- yaml::read_yaml(file)
  expect_identical(p$stage, "fit")
  expect_identical(p$stage_index, 2L)
  expect_identical(p$stage_count, 2L)
  expect_identical(c(p$step, p$steps), c(10L, 1000L))
  expect_identical(p$unit, "iteration")
  expect_identical(p$done, list(list(stage = "tbl-data", elapsed_s = 41L)))
})

test_that("a label not among the stages is ignored", {
  local_clock()
  file <- progress_file()
  quietly(.progress_begin(file, "fit"))
  quietly(.progress_stage("fig-effect-age", TRUE))
  expect_null(yaml::read_yaml(file)$stage)
})

test_that("step lines are throttled to one per `every` minutes; stage lines always print", {
  withr::local_options(hvtiRtemplates.progress_every = 10)
  clock <- local_clock()
  file <- progress_file()
  quietly(.progress_begin(file, "fit"))
  stage_line <- quietly(.progress_stage("fit", TRUE))
  expect_match(stage_line, "fit  started \\(1 of 1\\)")
  f <- .progress_step("iteration")
  clock$now <- clock$now + 5 * 60
  expect_length(quietly(f(1L, 100L)), 0L)
  clock$now <- clock$now + 5 * 60
  line <- quietly(f(2L, 100L))
  expect_match(line, "fit  iteration 2/100  10m in stage  ~8h10m left in stage", fixed = TRUE)
  expect_identical(yaml::read_yaml(file)$step, 2L)
})

test_that("the last step always prints", {
  clock <- local_clock()
  file <- progress_file()
  quietly(.progress_begin(file, "fit"))
  quietly(.progress_stage("fit", TRUE))
  f <- .progress_step("iteration")
  clock$now <- clock$now + 1
  expect_match(quietly(f(3L, 3L)), "iteration 3/3", fixed = TRUE)
})

test_that("a progress file that cannot be written stops reporting, not the render", {
  local_clock()
  file <- file.path(withr::local_tempdir(), "missing-dir", "x.run.progress")
  out <- quietly(expect_no_error(.progress_begin(file, "fit")))
  expect_match(paste(out, collapse = "\n"), "progress reporting stopped")
  expect_no_error(quietly(.progress_stage("fit", TRUE)))
  expect_false(file.exists(file))
})

test_that("a bad progress_every stops with a message naming the option", {
  withr::local_options(hvtiRtemplates.progress_every = 0)
  expect_error(.progress_every(), "hvtiRtemplates.progress_every")
})
```

The throttle test's estimate: 600 s for 2 steps is 300 s a step, times 98 steps left,
which is 29,400 s, printed as `8h10m`.

- [ ] **Step 2: Run them to see them fail**

Run: `NOT_CRAN=true Rscript -e 'devtools::test(filter = "job-progress|background-job")'`
Expected: FAIL, `could not find function ".fmt_dur"` and a missing `progress` element.

- [ ] **Step 3: Implement**

`R/background-job.R`, `.run_files()`:

```r
.run_files <- function(path) {
  stem <- sub("[.]qmd$", "", path)
  list(log = paste0(stem, ".run.log"), status = paste0(stem, ".run.yml"), runner = paste0(stem, ".runner"),
       progress = paste0(stem, ".run.progress"))
}
```

`R/job-progress.R`:

```r
# How far a long render has got: which chunk is running, how far into it, and how
# long is left. The design is dev/specs/2026-10-21-job-progress-design.md.
#
# The render's own process writes <job>.run.progress. It is a file of its own,
# not part of <job>.run.yml, because submit_job()'s runner writes that one from
# another process, and two processes renaming over one file overwrite each other.
# Log lines go to stderr(), which reaches the render log; knitr would put a
# message() or a cat() to stdout into the report instead. Progress is advisory:
# nothing here may stop a render.

.progress_state <- new.env(parent = emptyenv())

# The one clock, so tests can move it.
.now <- function() Sys.time()

.progress_every <- function() {
  every <- getOption("hvtiRtemplates.progress_every", 10)
  if (!is.numeric(every) || length(every) != 1L || is.na(every) || every <= 0) {
    stop("options(hvtiRtemplates.progress_every = ) must be a positive number of minutes.", call. = FALSE)
  }
  every
}

.fmt_dur <- function(secs) {
  secs <- max(0, round(secs))
  if (secs < 60) return(paste0(secs, "s"))
  mins <- secs %/% 60
  if (mins < 60) return(paste0(mins, "m"))
  sprintf("%dh%02dm", as.integer(mins %/% 60), as.integer(mins %% 60))
}

.parse_stamp <- function(x) as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%S%z")

.progress_eta <- function(elapsed, step, steps) if (step > 0) elapsed / step * (steps - step) else NA_real_

.progress_log <- function(text) {
  cat(format(.now(), "%Y-%m-%d %H:%M"), "  ", text, "\n", sep = "", file = stderr())
  .progress_state$last_log <- .now()
  invisible(NULL)
}

.progress_write <- function() {
  s <- .progress_state
  if (is.null(s$file)) return(invisible(NULL))
  rec <- list(pid = Sys.getpid(), host = Sys.info()[["nodename"]], started = .stamp(s$started), updated = .stamp(.now()),
              stage = s$stage, stage_index = s$stage_index, stage_count = length(s$stages),
              stage_started = if (!is.null(s$stage_started)) .stamp(s$stage_started),
              step = s$step, steps = s$steps, unit = s$unit, stages = s$stages, done = s$done)
  tryCatch(do.call(.write_status, c(list(s$file), Filter(Negate(is.null), rec))), error = function(e) {
    cat("progress reporting stopped: ", conditionMessage(e), "\n", sep = "", file = stderr())
    s$file <- NULL
  })
  invisible(NULL)
}

.progress_begin <- function(file, stages) {
  s <- .progress_state
  rm(list = ls(s, all.names = TRUE), envir = s)
  s$file <- file
  s$stages <- as.character(stages)
  s$started <- .now()
  s$last_log <- s$started
  s$done <- list()
  .progress_write()
}

.progress_stage <- function(label, before) {
  s <- .progress_state
  if (is.null(s$file) || !isTRUE(label %in% s$stages)) return(invisible(NULL))
  if (isTRUE(before)) {
    s$stage <- label
    s$stage_index <- match(label, s$stages)
    s$stage_started <- .now()
    s$step <- s$steps <- s$unit <- NULL
    .progress_log(sprintf("%s  started (%d of %d)", label, s$stage_index, length(s$stages)))
  } else if (identical(label, s$stage)) {
    elapsed <- as.numeric(difftime(.now(), s$stage_started, units = "secs"))
    s$done[[length(s$done) + 1L]] <- list(stage = label, elapsed_s = as.integer(round(elapsed)))
    .progress_log(sprintf("%s  done in %s", label, .fmt_dur(elapsed)))
  }
  .progress_write()
}

# The callback a long computation calls once per step. It writes the file every
# step and a log line only once `every` minutes have passed, or at the last step:
# R runs one thing at a time, so no timer can fire inside a fit, but a step can
# look at the clock.
.progress_step <- function(unit) {
  force(unit)
  function(step, steps) {
    s <- .progress_state
    if (is.null(s$file)) return(invisible(NULL))
    s$step <- as.integer(step)
    s$steps <- as.integer(steps)
    s$unit <- unit
    now <- .now()
    if (step >= steps || as.numeric(difftime(now, s$last_log, units = "mins")) >= .progress_every()) {
      elapsed <- as.numeric(difftime(now, if (is.null(s$stage_started)) s$started else s$stage_started, units = "secs"))
      left <- if (step < steps) paste0("  ~", .fmt_dur(.progress_eta(elapsed, step, steps)), " left in stage") else ""
      .progress_log(sprintf("%s  %s %d/%d  %s in stage%s", if (is.null(s$stage)) "-" else s$stage, unit,
                            as.integer(step), as.integer(steps), .fmt_dur(elapsed), left))
    }
    .progress_write()
  }
}
```

- [ ] **Step 4: Run the tests**

Run: `NOT_CRAN=true Rscript -e 'devtools::test(filter = "job-progress|background-job")'`
Expected: PASS. If the `8h10m` expectation is off by a minute, check the arithmetic in the
note above before changing the code.

- [ ] **Step 5: Lint and commit**

Run: `Rscript -e 'lintr::lint("R/job-progress.R"); lintr::lint("tests/testthat/test-job-progress.R")'`. Expected: no lints.

```bash
git add R/job-progress.R R/background-job.R tests/testthat/test-job-progress.R tests/testthat/test-background-job.R
git commit -m "feat: a progress record and a throttled step callback for long renders"
```

### Task B2: the chunk hook, through `.job_setup()`

**Files:**
- Modify: `R/job-progress.R` (append)
- Modify: `R/job-setup.R` (`.job_setup()`, the returned list, line ~59)
- Test: `tests/testthat/test-job-progress.R`, `tests/testthat/test-job-setup.R` (line ~9)

**Interfaces:**
- Consumes: `.progress_begin()`, `.progress_stage()`, `.progress_step()` from B1.
- Produces: `.progress_install(file)`: during a knit, starts the record at `file` with the
  document's chunk labels (less the calling chunk) as stages, sets the hook, and returns
  `.progress_step`; otherwise returns `function(unit) NULL` and writes nothing.
  `.job_setup()`'s list gains `progress`, that factory.

- [ ] **Step 1: Write the failing tests**

Append to `test-job-progress.R`:

```r
test_that("a knitted document records its chunks as stages, less the one that installs the hook", {
  dir <- withr::local_tempdir()
  rmd <- file.path(dir, "x.Rmd")
  file <- file.path(dir, "x.run.progress")
  writeLines(c("```{r setup}",
               sprintf("p <- hvtiRtemplates:::.progress_install(%s)", deparse(file)),
               "```",
               "```{r first}",
               "f <- p('step'); for (i in 1:3) f(i, 3)",
               "```",
               "```{r second}",
               "1",
               "```"), rmd)
  withr::defer(knitr::knit_hooks$delete("hvti_progress"))
  log <- quietly(knitr::knit(rmd, file.path(dir, "x.md"), quiet = TRUE))
  p <- yaml::read_yaml(file)
  expect_identical(p$stages, c("first", "second"))
  expect_identical(vapply(p$done, `[[`, "", "stage"), c("first", "second"))
  expect_true(any(grepl("first  step 3/3", log, fixed = TRUE)))
  expect_false(any(grepl("step 3/3", readLines(file.path(dir, "x.md")), fixed = TRUE)))
})

test_that("outside a knit nothing is recorded and the factory returns NULL", {
  file <- file.path(withr::local_tempdir(), "x.run.progress")
  p <- .progress_install(file)
  expect_null(p("iteration"))
  expect_false(file.exists(file))
  expect_null(.progress_install(NULL)("iteration"))
})
```

In `test-job-setup.R`, the first test's `expect_named()` becomes:

```r
  expect_named(r$job, c("root", "set_path", "run", "notice", "progress"))
  expect_null(r$job$progress("iteration"))
```

- [ ] **Step 2: Run to see them fail**

Run: `NOT_CRAN=true Rscript -e 'devtools::test(filter = "job-progress|job-setup")'`
Expected: FAIL, `could not find function ".progress_install"`, and the names mismatch.

- [ ] **Step 3: Implement**

Append to `R/job-progress.R`:

```r
# knitr calls this before and after every chunk that has the hvti_progress option,
# which .progress_install() sets for all of them. It returns NULL so nothing
# reaches the report.
.progress_hook <- function(before, options, ...) {
  .progress_stage(options$label, before)
  invisible(NULL)
}

# Called from .job_setup(), in the setup chunk. The stages are the document's chunk
# labels less the setup chunk itself, which installs the hook and so never sees its
# own end. Chunks made by knitr::knit_child() have labels outside the list and are
# ignored: they run inside a parent chunk, whose stage covers them.
.progress_install <- function(file) {
  if (is.null(file) || !isTRUE(getOption("knitr.in.progress"))) return(function(unit) NULL)
  stages <- setdiff(unique(knitr::all_labels()), knitr::opts_current$get("label"))
  .progress_begin(file, stages)
  knitr::knit_hooks$set(hvti_progress = .progress_hook)
  knitr::opts_chunk$set(hvti_progress = TRUE)
  .progress_step
}
```

In `R/job-setup.R`, `.job_setup()`, before building `notice`:

```r
  # A render records its stages and steps in <job>.run.progress; the
  # design is dev/specs/2026-10-21-job-progress-design.md.
  progress <- .progress_install(if (is.null(input)) NULL else .run_files(input)$progress)
```

and the return becomes:

```r
  list(root = root, set_path = set_path, run = run, notice = knitr::asis_output(notice), progress = progress)
```

Update the comment block above `.job_setup()` ("Returns the study root, ...") to name the
progress factory.

- [ ] **Step 4: Run the tests**

Run: `NOT_CRAN=true _R_CHECK_LIMIT_CORES_=TRUE Rscript -e 'devtools::test(filter = "job-progress|job-setup|background-job")'`
Expected: PASS.

- [ ] **Step 5: Mutation check, then commit**

Comment out `knitr::opts_chunk$set(hvti_progress = TRUE)` and rerun: the knit test must fail
(`done` empty). Restore it.

```bash
git add R/job-progress.R R/job-setup.R tests/testthat/test-job-progress.R tests/testthat/test-job-setup.R
git commit -m "feat: a render records each chunk as a stage, through .job_setup()"
```

### Task B3: `job_status()` prints progress

**Files:**
- Modify: `R/job-progress.R` (append)
- Modify: `R/background-job.R` (`job_status()`, its roxygen block)
- Test: `tests/testthat/test-job-progress.R`

**Interfaces:**
- Consumes: B1's helpers; `.run_files()$progress`.
- Produces: `.progress_read(file)` (`NULL`, the parsed list, or `list(error = )`);
  `.progress_view(prog, now)` (adds `age_s`, `stale`, `stage_s`, `eta_s`);
  `.state_from_progress(prog)`; `.progress_lines(prog, state)`. `job_status()` returns
  `progress` in its list and prints the block.

- [ ] **Step 1: Write the failing tests**

Append to `test-job-progress.R`:

```r
# A progress file as a render in its fit stage would leave it, `age` minutes ago.
write_progress <- function(job, age = 2, done_all = FALSE, pid = Sys.getpid()) {
  now <- .now()
  stages <- c("tbl-data", "fit", "effects")
  .write_status(.run_files(job)$progress, pid = pid, host = Sys.info()[["nodename"]],
                started = .stamp(now - 3600), updated = .stamp(now - age * 60),
                stage = if (done_all) "effects" else "fit", stage_index = if (done_all) 3L else 2L, stage_count = 3L,
                stage_started = .stamp(now - 3000), step = 412L, steps = 1000L, unit = "iteration", stages = stages,
                done = if (done_all) lapply(stages, function(s) list(stage = s, elapsed_s = 600L))
                       else list(list(stage = "tbl-data", elapsed_s = 41L)))
}

status_job_progress <- function() {
  job <- file.path(withr::local_tempdir(.local_envir = parent.frame()), "nb.boostmtree.x.boost.qmd")
  writeLines("---\ntitle: x\n---", job)
  job
}

test_that("a running job prints its stage, step, estimate, what is next and when it last moved", {
  local_clock(Sys.time())
  job <- status_job_progress()
  .write_status(.run_files(job)$status, state = "running", pid = Sys.getpid(), host = Sys.info()[["nodename"]],
                started = .stamp(.now() - 3600))
  write_progress(job)
  out <- utils::capture.output(st <- job_status(job))
  expect_identical(st$state, "running")
  expect_match(out[2], "stage   fit (2 of 3)", fixed = TRUE)
  expect_match(out[3], "step    iteration 412/1000, ~", fixed = TRUE)
  expect_match(paste(out, collapse = "\n"), "next    effects", fixed = TRUE)
  expect_match(paste(out, collapse = "\n"), "updated 2m ago$")
  expect_false(st$progress$stale)
  expect_true(st$progress$eta_s > 0)
})

test_that("progress older than three intervals, and at least 30 minutes, reads possibly stalled", {
  local_clock(Sys.time())
  job <- status_job_progress()
  write_progress(job, age = 47)
  out <- utils::capture.output(st <- job_status(job))
  expect_true(st$progress$stale)
  expect_match(paste(out, collapse = "\n"), "updated 47m ago, no progress since; possibly stalled", fixed = TRUE)
})

test_that("without a run.yml the state comes from the progress file", {
  local_clock(Sys.time())
  job <- status_job_progress()
  write_progress(job)
  expect_identical(job_status(job, quiet = TRUE)$state, "running")
  write_progress(job, pid = 999999L)
  expect_identical(job_status(job, quiet = TRUE)$state, "vanished")
  write_progress(job, done_all = TRUE, pid = 999999L)
  st <- job_status(job, quiet = TRUE)
  expect_identical(st$state, "finished")
  out <- utils::capture.output(job_status(job))
  expect_match(paste(out, collapse = "\n"), "stage times:", fixed = TRUE)
})

test_that("an unreadable progress file is noted, and the state still comes from run.yml", {
  job <- status_job_progress()
  .write_status(.run_files(job)$status, state = "failed", exit_code = 1L, pid = 999999L)
  writeLines("{{{ not yaml", .run_files(job)$progress)
  out <- utils::capture.output(st <- job_status(job))
  expect_identical(st$state, "failed")
  expect_match(paste(out, collapse = "\n"), "cannot read", fixed = TRUE)
})
```

- [ ] **Step 2: Run to see them fail**

Run: `NOT_CRAN=true Rscript -e 'devtools::test(filter = "job-progress")'`
Expected: the four new tests FAIL (state `none`; no progress lines).

- [ ] **Step 3: Implement**

Append to `R/job-progress.R`:

```r
.progress_read <- function(file) {
  if (!file.exists(file)) return(NULL)
  p <- tryCatch(yaml::read_yaml(file), error = function(e) NULL)
  if (!is.list(p) || !is.character(p$updated) || !is.character(p$started)) {
    return(list(error = paste0("cannot read ", file, "; progress not shown")))
  }
  p
}

# What job_status() adds to the file: how old it is, whether that is old enough
# to look stuck, and the estimate counted from now rather than from the last write.
.progress_view <- function(prog, now = .now()) {
  if (is.null(prog) || !is.null(prog$error)) return(prog)
  updated <- .parse_stamp(prog$updated)
  prog$age_s <- max(0, as.numeric(difftime(now, updated, units = "secs")))
  prog$stale <- prog$age_s > max(3 * .progress_every() * 60, 30 * 60)
  started <- if (is.null(prog$stage_started)) NA else .parse_stamp(prog$stage_started)
  prog$stage_s <- as.numeric(difftime(now, started, units = "secs"))
  prog$eta_s <- if (is.null(prog$step) || is.na(started)) {
    NA_real_
  } else {
    max(0, .progress_eta(as.numeric(difftime(updated, started, units = "secs")), prog$step, prog$steps) - prog$age_s)
  }
  prog
}

# A render started without submit_job() has no run.yml: its progress file says
# whether it finished, and its process whether it is still running.
.state_from_progress <- function(prog) {
  done <- vapply(prog$done, function(d) d$stage, "")
  if (length(prog$stages) && all(prog$stages %in% done)) {
    return(list(state = "finished", pid = prog$pid, host = prog$host, started = prog$started, ended = prog$updated,
                elapsed_s = round(as.numeric(difftime(.parse_stamp(prog$updated), .parse_stamp(prog$started),
                                                      units = "secs")))))
  }
  list(state = "running", pid = prog$pid, host = prog$host, started = prog$started)
}

.progress_lines <- function(prog, state) {
  if (is.null(prog)) return(character())
  if (!is.null(prog$error)) return(paste0("  progress: ", prog$error))
  stages_done <- vapply(prog$done, function(d) d$stage, "")
  secs_done <- vapply(prog$done, function(d) as.numeric(d$elapsed_s), 0)
  if (!identical(state, "running")) {
    if (!length(stages_done)) return(character())
    return(c("  stage times:", sprintf("    %-28s %s", stages_done, vapply(secs_done, .fmt_dur, ""))))
  }
  out <- character()
  if (!is.null(prog$stage)) {
    out <- c(out, sprintf("  stage   %s (%s of %s), %s in stage", prog$stage, prog$stage_index, prog$stage_count,
                          .fmt_dur(prog$stage_s)))
  }
  if (!is.null(prog$step)) {
    out <- c(out, sprintf("  step    %s %s/%s%s", prog$unit, prog$step, prog$steps,
                          if (is.na(prog$eta_s)) "" else paste0(", ~", .fmt_dur(prog$eta_s), " left in stage")))
  }
  out <- c(out, sprintf("  done    %d stages, %s in all", length(stages_done), .fmt_dur(sum(secs_done))))
  upcoming <- setdiff(prog$stages, c(stages_done, prog$stage))
  if (length(upcoming)) out <- c(out, paste0("  next    ", paste(upcoming, collapse = ", ")))
  c(out, paste0("  updated ", .fmt_dur(prog$age_s), " ago",
                if (isTRUE(prog$stale)) ", no progress since; possibly stalled" else ""))
}
```

In `job_status()` (`R/background-job.R`), after the `known` check:

```r
  prog <- .progress_read(files$progress)
  if (identical(st$state, "none") && is.list(prog) && is.null(prog$error)) st <- .state_from_progress(prog)
```

After `st$log <- files$log`:

```r
  st$progress <- .progress_view(prog)
```

And after the existing `cat(basename(path), ...)` line, inside the `if (!isTRUE(quiet))` block:

```r
    lines <- .progress_lines(st$progress, st$state)
    if (length(lines)) cat(lines, sep = "\n")
```

Roxygen for `job_status()`, in Rd markup: in `@description`, add a sentence saying that a
render also keeps \code{<job>.run.progress}, read here, and that a render started without
\code{\link{submit_job}} is reported from it alone. In `@return`, add:
`\code{progress}, the render's progress record when there is one, with \code{eta_s}, the
estimated seconds left in the current stage, and \code{stale}, \code{TRUE} when it has not
changed for three reporting intervals and at least 30 minutes.` Add `@details`:
`A long step writes a line to the render log at most every
\code{getOption("hvtiRtemplates.progress_every", 10)} minutes.`

- [ ] **Step 4: Run tests, document, check**

```bash
NOT_CRAN=true _R_CHECK_LIMIT_CORES_=TRUE Rscript -e 'devtools::test(filter = "job-progress|background-job|job-setup")'
Rscript -e 'devtools::document()'
```
Expected: PASS; `man/job_status.Rd` changes.

- [ ] **Step 5: Commit**

```bash
git add R/job-progress.R R/background-job.R man/job_status.Rd tests/testthat/test-job-progress.R
git commit -m "feat: job_status() prints stage, step, estimate and staleness"
```

### Task B4: documentation, news, gates

**Files:**
- Modify: `inst/templates/README.md` ("Long-running jobs", line ~487)
- Create: `news/spec-job-progress.md`

- [ ] **Step 1: README paragraph**, appended to "Long-running jobs":

```markdown
A render records how far it has got in `<job>.run.progress`, beside the job: the chunk
running, the step within it where the template reports steps (boostmtree iterations and
partial-effect predictions), and how long each finished chunk took. `job_status()` prints
it, with an estimate of the time left in the current chunk, and says when nothing has moved
for half an hour or more. The render log gets a line as each chunk starts and ends, and,
within a long chunk, a line at most every ten minutes:
`options(hvtiRtemplates.progress_every = 5)` makes that five. A render started from a
terminal without `submit_job()` records progress too.
```

- [ ] **Step 2: News fragment** `news/spec-job-progress.md`:

```markdown
* A render records its progress in `<job>.run.progress`: the chunk running, the step within
  it, and how long each finished chunk took. `job_status()` prints it, with an estimate of
  the time left in the chunk, flags a render that has not moved for half an hour, and reads
  a render started without `submit_job()` from that file alone. Long chunks write a line to
  the render log at most every `hvtiRtemplates.progress_every` minutes (default 10).
```

- [ ] **Step 3: Full gates**

```bash
NOT_CRAN=true _R_CHECK_LIMIT_CORES_=TRUE Rscript -e 'devtools::test()' 2>&1 | grep -E "FAIL|SKIP [0-9]+ \| PASS|\[ FAIL"
Rscript -e 'lintr::lint_package()'
Rscript -e 'devtools::check()'
```
Expected: no failures; skip count unchanged from #366's branch; no lints; check 0/0/0.

- [ ] **Step 4: Commit**

```bash
git add inst/templates/README.md news/spec-job-progress.md
git commit -m "docs: job progress in the long-running jobs guide, and its news"
```

---

## Part C: `nb-boostmtree` uses it (after boostmtree 2.0.8 is tagged)

Do not start until John has tagged boostmtree `v2.0.8-ccf` and it is installed. This is
hvtiRtemplates' own floor move, in a PR of its own after B merges.

⚠️ Coordination (2026-10-21): hvtiRtemplates PR #375 (`chore/boostmtree-2.0.8-install`)
already changes the template's install message to `ref = "v2.0.8-ccf"` and its assertion in
`test-nb-boostmtree.R`, and leaves the floor at 2.0.4. Branch Part C from `main` after #375
merges; keep the install line as #375 leaves it; Part C raises only the floor (template
check, its message's `>=`, and `DESCRIPTION` Suggests) and adapts the floor test.

### Task C1: wire progress and raise the floor

**Files:**
- Modify: `inst/templates/30_analyses/nb-boostmtree.qmd` (version check, lines ~63-77; fit call ~341; `partial.plot()` ~481)
- Modify: `DESCRIPTION` (`Suggests: boostmtree (>= 2.0.4)`, line ~50)
- Modify: `tests/testthat/test-nb-boostmtree.R` (floor test ~123; new tests)
- Create: `news/<branch>.md`

**Interfaces:**
- Consumes: `.job$progress(unit)` from B2; `boostmtree(progress = )` and
  `partial.plot(progress = )` from A.

- [ ] **Step 1: Write the failing tests** (in `test-nb-boostmtree.R`)

Change the floor test to:

```r
test_that("boostmtree older than 2.0.8 is refused with the fork's install line", {
  nb_skip_unless_stack()
  expect_error(nb_mocked_setup("boostmtree", "2.0.7"), "ref = \"v2.0.8-ccf\"", fixed = TRUE)
})
```

Add:

```r
test_that("the fit and the partial effects report their steps, and progress is not in the cache key", {
  nb_skip_unless_stack()
  root <- nb_study()
  env <- nb_env(root)
  nb_run(c("set", "edit-study-choices"), env, nb_choices())
  seen <- new.env()
  seen$units <- character()
  env$.job$progress <- function(unit) {
    force(unit)
    function(step, steps) seen$units <- c(seen$units, unit)
  }
  utils::capture.output(nb_run(c("tbl-data", "fit", "fig-importance", "effects"), env))
  expect_true("iteration" %in% seen$units)
  expect_true("prediction" %in% seen$units)
  env2 <- nb_env(root)
  nb_run(c("set", "edit-study-choices"), env2, nb_choices())
  expect_no_error(utils::capture.output(nb_run(c("tbl-data", "fit", "fig-importance", "effects"), env2)))
})
```

Read `nb_env()`, `nb_choices()` and the "changing CORES reuses the cached fit" test (~line
227) first, and follow their exact call pattern if it differs from the above. The second
run must load from cache without a REFIT stop: that is the proof that `progress` stays out
of the key.

In the end-to-end render test (~line 403), after the render, add:

```r
  prog <- yaml::read_yaml(sub("[.]qmd$", ".run.progress", job))
  expect_true(all(c("fit", "effects") %in% vapply(prog$done, `[[`, "", "stage")))
```

(using the variable that test already holds for the job's path).

- [ ] **Step 2: Run to see them fail**

Run: `NOT_CRAN=true _R_CHECK_LIMIT_CORES_=TRUE Rscript -e 'devtools::test(filter = "nb-boostmtree")'`
Expected: the floor test and the progress test FAIL.

- [ ] **Step 3: Implement**

Version check: `< "2.0.4"` becomes `< "2.0.8"`, the message `>= 2.0.8`, the install line
`ref = "v2.0.8-ccf"`. Add to the comment above it: 2.0.8 adds `progress =`, which the fit
and the partial effects use to report how far they have got.

Fit call, after `control = boostmtree.control(cv.cores = get("CORES"))`:

```r
             control = boostmtree.control(cv.cores = get("CORES")),
             # Reports each boosting iteration to <job>.run.progress and the render log.
             # get() keeps the job's run record out of the cache key's inputs, as for
             # CORES: it changes what is reported, never what is fitted.
             progress = get(".job")$progress("iteration")),
```

`partial.plot()`:

```r
                      partial.plot(fit, x.var.names = .effect_vars, output = "data", verbose = FALSE,
                                   progress = get(".job")$progress("prediction")),
```

`DESCRIPTION`: `boostmtree (>= 2.0.8)`.

News fragment `news/<branch>.md` (branch name with `/` replaced by `-`):

```markdown
* `nb-boostmtree` reports each boosting iteration and each partial-effect prediction to
  `<job>.run.progress` and the render log, so `job_status()` can say how far a fit has got
  and how long its stage has left. It needs boostmtree 2.0.8. Existing jobs need not
  change: they still report stages, and adding these lines to one means refitting it.
```

- [ ] **Step 4: Run tests and gates**

```bash
NOT_CRAN=true _R_CHECK_LIMIT_CORES_=TRUE Rscript -e 'devtools::test(filter = "nb-boostmtree")'
Rscript -e 'devtools::check()'
```
Expected: PASS; 0/0/0. Two mutations, each restored after:
- remove `progress = ...` from the fit call: the progress test fails;
- write `.job$progress("iteration")` instead of `get(".job")$progress("iteration")`: the
  second, cached run in the progress test stops, because `.job` (whose run record carries
  this render's start time) becomes a cache input.

⚠️ `cache_fit()`'s key also holds the call's code text, so this edit changes the key for
a job already in a study. Do NOT copy the `progress =` lines into an existing study job that
holds a cached fit unless it is refitting anyway (`REFIT = TRUE`): its cache would stop as
stale. New jobs scaffolded from the template are unaffected. Say this in the PR body; the
news fragment above already does.

- [ ] **Step 5: Commit**

```bash
git add inst/templates/30_analyses/nb-boostmtree.qmd DESCRIPTION tests/testthat/test-nb-boostmtree.R news/<branch>.md
git commit -m "feat(nb-boostmtree): report fit iterations and partial-effect predictions; boostmtree >= 2.0.8"
```

---

## After the M = 1000 COMMENCE run

Replace the extrapolated cost paragraph in the spec's §7 with the stage table that run
records. This is a note for whoever reads the run's `.run.progress`; it is not a code task.
