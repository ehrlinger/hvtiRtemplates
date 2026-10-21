# Background Jobs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a long template render run detached from a Workbench session, and stop a long fit from being started in the console.

**Architecture:** `submit_job()` writes a runner script beside the job and starts it with `setsid nohup <caller's Rscript>` from the study root; the runner records its state in `<job>.run.yml` and calls `render_job()` unchanged. `job_status()` reads that file and checks the recorded process. `guard_long_fit()` is a one-line check a template calls before an expensive `cache_fit()`. Spec: `dev/specs/2026-10-20-background-jobs-design.md`.

**Tech Stack:** R (>= 4.4.0), `ps` and `yaml` (already in Imports), `rlang::is_interactive()`, testthat edition 3.

## Global Constraints

- No new Imports: `ps`, `yaml`, `rlang` are already there; `knitr` is not, so use it only behind `requireNamespace()`.
- Roxygen is Rd markup, not markdown: `\code{}`, `\strong{}`, `\itemize{}`, `\link{}`. Every export has `@return`.
- Lines are at most 135 characters (`.lintr`). `lintr::lint_package()` must stay clean.
- testthat edition 3. Tests that start real processes call `skip_on_os("windows")` and `skip_on_cran()`.
- Windows: `submit_job()` stops with a message. It never silently runs in the foreground.
- A background render is `render_job(path, final = final)` with no other change.
- Status file `<job>.run.yml`, log `<job>.run.log`, runner `<job>.runner` (no `.R` extension, so a project-wide `quarto render` of the study never picks it up), all beside the job.
- States: `none`, `submitted`, `running`, `finished`, `failed`, `vanished`.
- A pull request never edits `NEWS.md` or `Version:`; its entry is `news/<branch>.md`.
- Definition of done (AGENTS.md): `devtools::test()` passes, `devtools::check()` 0/0/0, `devtools::document()` run and `man/`/`NAMESPACE` committed.

## File structure

- Create `R/long-fit.R`: `guard_long_fit()`.
- Create `R/background-job.R`: `submit_job()`, `job_status()`, and internals `.run_files()`, `.pid_alive()`, `.write_status()`, `.runner_lines()`, `.submit_job()`.
- Create `tests/testthat/test-guard-long-fit.R`, `tests/testthat/test-background-job.R`.
- Modify `inst/templates/30_analyses/nb-boostmtree.qmd` (fit chunk), `tests/testthat/test-nb-boostmtree.R`.
- Modify `inst/templates/README.md` (new section), add `news/feat-background-jobs.md`.
- Generated: `NAMESPACE`, `man/guard_long_fit.Rd`, `man/submit_job.Rd`, `man/job_status.Rd`.

---

### Task 1: `guard_long_fit()`

**Files:**
- Create: `R/long-fit.R`
- Test: `tests/testthat/test-guard-long-fit.R`

**Interfaces:**
- Produces: `guard_long_fit(name, dir, why)`; returns `invisible(FALSE)` when it lets the fit proceed; otherwise stops with a message containing `submit_job(`.

- [ ] **Step 1: Write the failing tests**

```r
# tests/testthat/test-guard-long-fit.R
test_that("an interactive session with no cached fit is stopped and told to submit the job", {
  withr::local_options(rlang_interactive = TRUE, hvtiRtemplates.allow_interactive_fit = NULL)
  dir <- withr::local_tempdir()
  expect_error(guard_long_fit("nb-boostmtree-fit", dir = dir, why = "a boostmtree fit takes hours"),
               "submit_job(", fixed = TRUE)
  expect_error(guard_long_fit("nb-boostmtree-fit", dir = dir, why = "a boostmtree fit takes hours"),
               "a boostmtree fit takes hours", fixed = TRUE)
})

test_that("a cached fit, the escape option, or a non-interactive render lets the fit proceed", {
  dir <- withr::local_tempdir()
  withr::local_options(rlang_interactive = FALSE)
  expect_false(guard_long_fit("x", dir = dir, why = "slow"))
  withr::local_options(rlang_interactive = TRUE)
  saveRDS(1, file.path(dir, "x.rds"))
  expect_false(guard_long_fit("x", dir = dir, why = "slow"))
  unlink(file.path(dir, "x.rds"))
  withr::local_options(hvtiRtemplates.allow_interactive_fit = TRUE)
  expect_false(guard_long_fit("x", dir = dir, why = "slow"))
})

test_that("guard_long_fit() checks its arguments", {
  expect_error(guard_long_fit(c("a", "b"), dir = ".", why = "slow"), "`name`")
  expect_error(guard_long_fit("a", dir = NA_character_, why = "slow"), "`dir`")
})
```

- [ ] **Step 2: Run them to see them fail**

Run: `Rscript -e 'devtools::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-guard-long-fit.R")'`
Expected: FAIL, `could not find function "guard_long_fit"`.

- [ ] **Step 3: Implement**

```r
# R/long-fit.R
#' Stop a long fit from starting in an interactive session
#'
#' @description
#' A template calls this just before an expensive \code{cache_fit()}. In an
#' interactive session (the console, or running chunks one by one) with no
#' cached result yet, it stops and says to run the job with
#' \code{\link{submit_job}} instead, because a fit that runs for hours dies
#' with the session. A render, a cached result, or
#' \code{options(hvtiRtemplates.allow_interactive_fit = TRUE)} lets it pass.
#'
#' @param name Character(1). The \code{cache_fit()} name; the cache file is
#'   \code{<dir>/<name>.rds}.
#' @param dir Character(1). The \code{cache_fit()} directory.
#' @param why Character(1). Why the fit is long, shown in the error.
#' @return \code{invisible(FALSE)} when the fit may proceed; otherwise an error.
#' @examples
#' guard_long_fit("example-fit", dir = tempdir(), why = "it takes hours")
#' @export
guard_long_fit <- function(name, dir, why) {
  if (!is.character(name) || length(name) != 1L || is.na(name) || !nzchar(name)) {
    stop("guard_long_fit(): `name` must be a single, non-empty string.", call. = FALSE)
  }
  if (!is.character(dir) || length(dir) != 1L || is.na(dir)) {
    stop("guard_long_fit(): `dir` must be a single directory path.", call. = FALSE)
  }
  if (!rlang::is_interactive() || isTRUE(getOption("hvtiRtemplates.allow_interactive_fit")) ||
      file.exists(file.path(dir, paste0(name, ".rds")))) {
    return(invisible(FALSE))
  }
  job <- if (requireNamespace("knitr", quietly = TRUE)) knitr::current_input(dir = TRUE) else NULL
  call <- sprintf("hvtiRtemplates::submit_job(\"%s\")", if (is.null(job)) "<this job>.qmd" else job)
  stop("This fit is not cached yet, and ", why, ": run interactively it dies with the session. ",
       "Run the job in the background instead:\n  ", call, "\nthen check it with job_status(). ",
       "Once the fit is cached, these chunks run interactively and load it. ",
       "For a deliberate small test, set options(hvtiRtemplates.allow_interactive_fit = TRUE).", call. = FALSE)
}
```

- [ ] **Step 4: Document and run the tests**

Run: `Rscript -e 'devtools::document(); devtools::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-guard-long-fit.R")'`
Expected: PASS (6 expectations).

- [ ] **Step 5: Commit**

```bash
git add R/long-fit.R tests/testthat/test-guard-long-fit.R NAMESPACE man/guard_long_fit.Rd
git commit -m "feat: guard_long_fit() stops a long fit from starting interactively"
```

---

### Task 2: the status file and `job_status()`

**Files:**
- Create: `R/background-job.R` (status part)
- Test: `tests/testthat/test-background-job.R` (status part)

**Interfaces:**
- Produces: `.run_files(path)` returning `list(log, status, runner)`; `.pid_alive(pid)` returning logical(1); `.write_status(file, ...)`; `job_status(path, quiet = FALSE)` returning invisibly a list with `state` among `none`, `submitted`, `running`, `finished`, `failed`, `vanished`, plus whatever fields the file holds (`pid`, `started`, `ended`, `exit_code`, `elapsed_s`, `r_version`, `submitted`) and `log`.

- [ ] **Step 1: Write the failing tests**

```r
# tests/testthat/test-background-job.R
status_job <- function() {
  dir <- withr::local_tempdir(.local_envir = parent.frame())
  job <- file.path(dir, "nb.boostmtree.x.boost.qmd")
  writeLines("---\ntitle: x\n---", job)
  job
}

test_that("a job never submitted reads none", {
  job <- status_job()
  expect_identical(job_status(job, quiet = TRUE)$state, "none")
})

test_that("the run files sit beside the job, and the runner has no .R extension", {
  f <- .run_files("/s/analyses/nb.x.qmd")
  expect_identical(f$log, "/s/analyses/nb.x.run.log")
  expect_identical(f$status, "/s/analyses/nb.x.run.yml")
  expect_identical(f$runner, "/s/analyses/nb.x.runner")
})

test_that("running is reported only while the recorded process is alive", {
  job <- status_job()
  .write_status(.run_files(job)$status, state = "running", pid = Sys.getpid())
  expect_identical(job_status(job, quiet = TRUE)$state, "running")
  .write_status(.run_files(job)$status, state = "running", pid = 999999L)
  expect_identical(job_status(job, quiet = TRUE)$state, "vanished")
})

test_that("finished and failed are read back with their exit code", {
  job <- status_job()
  .write_status(.run_files(job)$status, state = "failed", exit_code = 1L, pid = 999999L)
  st <- job_status(job, quiet = TRUE)
  expect_identical(st$state, "failed")
  expect_identical(st$exit_code, 1L)
})

test_that("a submission that never started reads vanished after two minutes", {
  job <- status_job()
  old <- format(Sys.time() - 600, "%Y-%m-%dT%H:%M:%S%z")
  .write_status(.run_files(job)$status, state = "submitted", submitted = old)
  expect_identical(job_status(job, quiet = TRUE)$state, "vanished")
  .write_status(.run_files(job)$status, state = "submitted", submitted = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
  expect_identical(job_status(job, quiet = TRUE)$state, "submitted")
})

test_that("job_status() prints one line unless quiet", {
  job <- status_job()
  expect_output(job_status(job), "none")
  expect_silent(job_status(job, quiet = TRUE))
})
```

- [ ] **Step 2: Run them to see them fail**

Run: `Rscript -e 'devtools::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-background-job.R")'`
Expected: FAIL, `could not find function "job_status"`.

- [ ] **Step 3: Implement**

```r
# R/background-job.R
.run_files <- function(path) {
  stem <- sub("[.]qmd$", "", path)
  list(log = paste0(stem, ".run.log"), status = paste0(stem, ".run.yml"), runner = paste0(stem, ".runner"))
}

.pid_alive <- function(pid) {
  if (is.null(pid) || is.na(suppressWarnings(as.integer(pid)))) return(FALSE)
  isTRUE(tryCatch(ps::ps_is_running(ps::ps_handle(as.integer(pid))), error = function(e) FALSE))
}

.write_status <- function(file, ...) {
  yaml::write_yaml(list(...), file)
  invisible(file)
}

.stamp <- function(time = Sys.time()) format(time, "%Y-%m-%dT%H:%M:%S%z")

#' Report a background job's state
#'
#' @description
#' Reads the status \code{\link{submit_job}} keeps beside a job,
#' \code{<job>.run.yml}. A job whose process was killed never records its
#' end, so a recorded \code{running} is checked against the process itself.
#'
#' @param path Character(1). The job's \code{.qmd} file.
#' @param quiet Logical(1). \code{FALSE} prints a one-line summary.
#' @return Invisibly, a list: \code{state} is one of \code{"none"},
#'   \code{"submitted"}, \code{"running"}, \code{"finished"}, \code{"failed"}
#'   or \code{"vanished"}; the other elements are what the status file
#'   recorded (\code{pid}, \code{started}, \code{ended}, \code{exit_code},
#'   \code{elapsed_s}, \code{r_version}), and \code{log}, the log file's path.
#' @examples
#' job <- file.path(tempdir(), "example.qmd")
#' writeLines("---\ntitle: example\n---", job)
#' job_status(job)
#' @export
job_status <- function(path, quiet = FALSE) {
  files <- .run_files(path)
  st <- if (file.exists(files$status)) yaml::read_yaml(files$status) else list(state = "none")
  if (identical(st$state, "running") && !.pid_alive(st$pid)) st$state <- "vanished"
  if (identical(st$state, "submitted")) {
    at <- as.POSIXct(st$submitted, format = "%Y-%m-%dT%H:%M:%S%z")
    if (is.na(at) || difftime(Sys.time(), at, units = "secs") > 120) st$state <- "vanished"
  }
  st$log <- files$log
  if (!isTRUE(quiet)) {
    detail <- switch(st$state,
      running = sprintf(" (process %s, since %s)", st$pid, st$started),
      finished = sprintf(" in %s s", st$elapsed_s),
      failed = sprintf(" with exit code %s; see %s", st$exit_code, files$log),
      vanished = sprintf(": the process is gone without recording an end; see %s", files$log),
      "")
    cat(basename(path), ": ", st$state, detail, "\n", sep = "")
  }
  invisible(st)
}
```

- [ ] **Step 4: Document and run the tests**

Run: `Rscript -e 'devtools::document(); devtools::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-background-job.R")'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/background-job.R tests/testthat/test-background-job.R NAMESPACE man/job_status.Rd
git commit -m "feat: job_status() reads a background job's status file"
```

---

### Task 3: `submit_job()`

**Files:**
- Modify: `R/background-job.R` (append)
- Test: `tests/testthat/test-background-job.R` (append)

**Interfaces:**
- Consumes: `.run_files()`, `.write_status()`, `.stamp()`, `.pid_alive()`, `job_status()` from Task 2; `.find_study_root(start)` from `R/study-root.R`; `render_job()`.
- Produces: `submit_job(path, final = FALSE)`, returning `invisible(job_status(path, quiet = TRUE))`; internal `.submit_job(path, final, render_call, root)` where `render_call` is R source text evaluated in the runner (tests pass a stand-in; the export passes `render_job`).

- [ ] **Step 1: Write the failing tests**

```r
# appended to tests/testthat/test-background-job.R
wait_for <- function(job, states, seconds = 30) {
  for (i in seq_len(seconds * 4)) {
    st <- job_status(job, quiet = TRUE)
    if (st$state %in% states) return(st)
    Sys.sleep(0.25)
  }
  st
}

test_that("a submitted job returns at once, then runs to finished", {
  skip_on_os("windows"); skip_on_cran()
  job <- status_job()
  out <- file.path(dirname(job), "done.txt")
  t0 <- Sys.time()
  .submit_job(job, final = FALSE, render_call = sprintf("Sys.sleep(2); writeLines('ok', %s)", deparse(out)),
              root = dirname(job))
  expect_lt(as.numeric(difftime(Sys.time(), t0, units = "secs")), 2)
  st <- wait_for(job, c("finished", "failed", "vanished"))
  expect_identical(st$state, "finished")
  expect_identical(st$exit_code, 0L)
  expect_true(file.exists(out))
  expect_true(file.exists(.run_files(job)$log))
})

test_that("a job that errors reads failed with a non-zero exit code, and the log holds the error", {
  skip_on_os("windows"); skip_on_cran()
  job <- status_job()
  .submit_job(job, final = FALSE, render_call = "stop('boom from the job')", root = dirname(job))
  st <- wait_for(job, c("finished", "failed", "vanished"))
  expect_identical(st$state, "failed")
  expect_identical(st$exit_code, 1L)
  expect_match(paste(readLines(.run_files(job)$log), collapse = "\n"), "boom from the job", fixed = TRUE)
})

test_that("a killed job reads vanished, and a running one cannot be submitted twice", {
  skip_on_os("windows"); skip_on_cran()
  job <- status_job()
  .submit_job(job, final = FALSE, render_call = "Sys.sleep(60)", root = dirname(job))
  st <- wait_for(job, "running")
  expect_identical(st$state, "running")
  expect_error(.submit_job(job, final = FALSE, render_call = "1", root = dirname(job)), "already running")
  ps::ps_kill(ps::ps_handle(as.integer(st$pid)))
  expect_identical(wait_for(job, "vanished")$state, "vanished")
})

test_that("submit_job() refuses Windows and a path that is not a job", {
  expect_error(submit_job(file.path(tempdir(), "no-such-job.qmd")), "existing job file")
  local_mocked_bindings(.is_windows = function() TRUE)
  job <- status_job()
  expect_error(submit_job(job), "Windows")
})
```

- [ ] **Step 2: Run them to see them fail**

Run: `Rscript -e 'devtools::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-background-job.R")'`
Expected: the new tests FAIL, `could not find function ".submit_job"`.

- [ ] **Step 3: Implement (append to `R/background-job.R`)**

```r
.is_windows <- function() .Platform$OS.type == "windows"

.runner_lines <- function(path, status, final, render_call) {
  c(sprintf("path <- %s", deparse(path)),
    sprintf("status <- %s", deparse(status)),
    sprintf("final <- %s", deparse(final)),
    "started <- Sys.time()",
    "stamp <- function(t) format(t, '%Y-%m-%dT%H:%M:%S%z')",
    "base <- list(pid = Sys.getpid(), r_version = as.character(getRversion()), started = stamp(started))",
    "yaml::write_yaml(c(list(state = 'running'), base), status)",
    sprintf("ok <- tryCatch({ %s; TRUE }, error = function(e) { message('Error: ', conditionMessage(e)); FALSE })",
            render_call),
    "ended <- Sys.time()",
    paste0("yaml::write_yaml(c(list(state = if (ok) 'finished' else 'failed', exit_code = if (ok) 0L else 1L), base, ",
           "list(ended = stamp(ended), elapsed_s = round(as.numeric(difftime(ended, started, units = 'secs'))))), status)"),
    "quit(save = 'no', status = if (ok) 0L else 1L)")
}

.submit_job <- function(path, final, render_call, root) {
  files <- .run_files(path)
  # "submitted" too: the gap before the runner records "running" must not let a second copy start.
  if (job_status(path, quiet = TRUE)$state %in% c("submitted", "running")) {
    stop("submit_job(): ", basename(path), " is already running; see job_status().", call. = FALSE)
  }
  writeLines(.runner_lines(path, files$status, final, render_call), files$runner)
  .write_status(files$status, state = "submitted", submitted = .stamp())
  rscript <- file.path(R.home("bin"), "Rscript")
  setsid <- if (nzchar(Sys.which("setsid"))) "setsid " else ""
  cmd <- sprintf("cd %s && %snohup %s %s > %s 2>&1 < /dev/null &",
                 shQuote(root), setsid, shQuote(rscript), shQuote(files$runner), shQuote(files$log))
  system(cmd, wait = FALSE)
  invisible(job_status(path, quiet = TRUE))
}

#' Render a job in the background, detached from the session
#'
#' @description
#' Starts \code{\link{render_job}} on the job in a separate process that
#' outlives the R session, the way \code{nohup} from a terminal does, and
#' returns at once. Use it for a job whose fit runs for hours: a Workbench
#' session that times out takes a console run with it.
#'
#' @details
#' The process runs the \code{Rscript} of the R that called
#' \code{submit_job()}, from the study root, so the study's \code{renv} and
#' \code{.Renviron} apply. It writes \code{<job>.run.log} (everything the render
#' prints) and \code{<job>.run.yml} (its state) beside the job; read the state
#' with \code{\link{job_status}}. A job already running is not started twice.
#' Not available on Windows, which cannot detach a process this way.
#'
#' @param path Character(1). The job's \code{.qmd} file.
#' @param final Logical(1). Passed to \code{\link{render_job}}.
#' @return Invisibly, the job's status, as \code{\link{job_status}} returns it.
#' @examples
#' \dontshow{if (FALSE)}
#' submit_job("analyses/nb.boostmtree.lvef.boost.qmd")
#' @export
submit_job <- function(path, final = FALSE) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !file.exists(path) || dir.exists(path)) {
    stop("submit_job(): `path` must be an existing job file.", call. = FALSE)
  }
  if (!is.logical(final) || length(final) != 1L || is.na(final)) {
    stop("submit_job(): `final` must be TRUE or FALSE.", call. = FALSE)
  }
  if (.is_windows()) {
    stop("submit_job(): Windows cannot detach a process from the session; render from a terminal instead.",
         call. = FALSE)
  }
  path <- normalizePath(path, winslash = "/")
  root <- .find_study_root(dirname(path))
  .submit_job(path, final, sprintf("hvtiRtemplates::render_job(path, final = %s)", deparse(final)), root)
}
```

Note: `@examples` must not start a real render under `R CMD check`; the `\dontshow{if (FALSE)}` line keeps the example parseable and documented but unrun. If roxygen rejects that form, use `\dontrun{}` and say why in a comment: an unrunnable example is the one case `\dontrun` is meant for.

- [ ] **Step 4: Document and run the tests**

Run: `Rscript -e 'devtools::document(); devtools::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-background-job.R")'`
Expected: PASS. Note the child `Rscript` must find `yaml`; it does through the inherited library paths.

- [ ] **Step 5: Mutation check**

Delete the line in `.runner_lines()` that writes the final state, rerun: "a submitted job ... runs to finished" must fail (state stays `running`, then `vanished`). Restore it.

- [ ] **Step 6: Commit**

```bash
git add R/background-job.R tests/testthat/test-background-job.R NAMESPACE man/submit_job.Rd
git commit -m "feat: submit_job() renders a job detached from the session"
```

---

### Task 4: `nb-boostmtree` adopts the guard

**Files:**
- Modify: `inst/templates/30_analyses/nb-boostmtree.qmd` (fit chunk, after `CACHE_DIR <- ...`, line 329)
- Test: `tests/testthat/test-nb-boostmtree.R` (append)

**Interfaces:**
- Consumes: `guard_long_fit(name, dir, why)` from Task 1.

- [ ] **Step 1: Write the failing test**

```r
test_that("the fit chunk refuses to start an uncached fit interactively, and names submit_job()", {
  nb_skip_unless_stack()
  withr::local_options(rlang_interactive = TRUE, hvtiRtemplates.allow_interactive_fit = NULL)
  env <- nb_env(nb_study())
  env$guard_long_fit <- hvtiRtemplates::guard_long_fit
  expect_error(utils::capture.output(nb_run(c("set", "edit-study-choices", "tbl-data", "fit"), env, nb_choices())),
               "submit_job(", fixed = TRUE)
})
```

- [ ] **Step 2: Run it to see it fail**

Run: `NOT_CRAN=true Rscript -e 'devtools::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-nb-boostmtree.R", desc = "the fit chunk refuses to start an uncached fit interactively, and names submit_job()")'`
Expected: FAIL (the chunk fits instead of stopping).

- [ ] **Step 3: Add the guard to the template**

In `inst/templates/30_analyses/nb-boostmtree.qmd`, immediately after the line `CACHE_DIR <- dirname(set_path("estimates", "nb-boostmtree.rds"))`, insert:

```r
# The fit runs for hours at study size. Started from the console it dies with
# the session, so an uncached fit is refused there: run the job with
# hvtiRtemplates::submit_job() instead. Once cached, these chunks load it.
hvtiRtemplates::guard_long_fit("nb-boostmtree-fit", dir = CACHE_DIR,
                               why = "a cross-validated boostmtree fit takes hours at study size")
```

Every other test that runs the fit chunk runs non-interactively (`rlang_interactive` unset under testthat), so they are unaffected.

- [ ] **Step 4: Run the test, then the whole nb file under the check's core limit**

Run: `_R_CHECK_LIMIT_CORES_=TRUE NOT_CRAN=true Rscript -e 'devtools::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-nb-boostmtree.R")'`
Expected: all PASS.

- [ ] **Step 5: Mutation check**

Delete the inserted `guard_long_fit(...)` call, rerun the new test: it must fail. Restore it.

- [ ] **Step 6: Commit**

```bash
git add inst/templates/30_analyses/nb-boostmtree.qmd tests/testthat/test-nb-boostmtree.R
git commit -m "feat(nb-boostmtree): refuse an uncached fit in the console; point to submit_job()"
```

---

### Task 5: documentation, news, and the full gate

**Files:**
- Modify: `inst/templates/README.md`
- Create: `news/feat-background-jobs.md`

- [ ] **Step 1: README section.** Add to `inst/templates/README.md`, after the section on rendering jobs:

```markdown
## Long-running jobs

A fit that runs for hours does not survive a Workbench session that times out,
and a chunk run in the console dies with the session. Run such a job in the
background instead:

    hvtiRtemplates::submit_job("analyses/nb.boostmtree.lvef.boost.qmd")
    hvtiRtemplates::job_status("analyses/nb.boostmtree.lvef.boost.qmd")

`submit_job()` renders the job detached from the session and returns at once;
`<job>.run.log` holds the output and `<job>.run.yml` the state. A template whose
fit is long calls `guard_long_fit()`, which refuses an uncached fit in an
interactive session and names the `submit_job()` call to use. `nb-boostmtree`
does so today. Once the fit is cached, its chunks run interactively and load it.
```

- [ ] **Step 2: News fragment** `news/feat-background-jobs.md`:

```markdown
* New `submit_job()` and `job_status()` render a job in the background,
  detached from the session, so a long fit survives a Workbench session that
  times out. The render is `render_job()` unchanged; it writes `<job>.run.log`
  and `<job>.run.yml` beside the job. Not available on Windows.
* New `guard_long_fit()` stops a long fit from starting in an interactive
  session when it is not cached yet, and names the `submit_job()` call to use.
  `nb-boostmtree` calls it before its cross-validated fit.
```

- [ ] **Step 3: Lint and the full gate**

Run, in order:
- `Rscript -e 'devtools::document()'` and confirm `git status` shows no unexpected `man/` changes.
- `Rscript -e 'print(lintr::lint_package())'`: expect no lints.
- `_R_CHECK_LIMIT_CORES_=TRUE NOT_CRAN=true Rscript -e 'devtools::test()'`: expect `FAIL 0`, and the skip count unchanged except for the new process-starting tests on Windows.
- `Rscript -e 'devtools::check()'`: expect 0 errors, 0 warnings, 0 notes.

- [ ] **Step 4: Commit**

```bash
git add inst/templates/README.md news/feat-background-jobs.md
git commit -m "docs: long-running jobs: submit_job(), job_status(), guard_long_fit()"
```

---

### Task 6: server proof (outside the repository)

Not a repository change; staged for John to run, per the spec's server-proof requirement.

- [ ] **Step 1:** Write `/studies/general/_development/background-job-proof-20261020/proof.qmd`, a job whose one chunk loops for 3 hours writing `Sys.time()` to `heartbeat.txt` every minute, plus `RUN-INSTRUCTIONS.md`: open an ordinary Workbench session, install this branch into a private library, then in the console run `hvtiRtemplates::submit_job("proof.qmd")`, then log out.
- [ ] **Step 2:** The next day, read `heartbeat.txt` and `proof.run.yml`. Pass: the heartbeat runs a full 3 hours and the state is `finished`. Fail: the heartbeat stops near 2 hours (state `vanished`); then the Workbench Launcher fallback (spec section 5, approach B) is needed before anyone relies on `submit_job()`.
