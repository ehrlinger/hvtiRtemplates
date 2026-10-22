ok_checks <- function(env = parent.frame()) {
  ok <- function(n) function(...) .check(n, TRUE)
  testthat::local_mocked_bindings(.check_r_version = ok("r_version"), .check_packages = ok("packages"),
                                  .check_quarto = ok("quarto"), .check_run_state = ok("run_state"),
                                  .check_study_render = ok("study_render"), .env = env)
}

test_that("run_job refuses before submitting when any check fails, and lists every failure", {
  root <- lock_study(r = "4.5.3")
  job <- file.path(root, "analyses", "x.qmd")
  writeLines("---\ntitle: x\n---", job)
  submitted <- FALSE
  testthat::local_mocked_bindings(.session_r = function() numeric_version("4.6.1"),
                                  .check_packages = function(...) .check("packages", FALSE, "quarto missing.", "hvtiR::update()"),
                                  .check_quarto = function() .check("quarto", TRUE),
                                  .check_run_state = function(...) .check("run_state", TRUE),
                                  .check_study_render = function(...) .check("study_render", TRUE),
                                  submit_job = function(...) submitted <<- TRUE)
  expect_error(expect_output(run_job(job), "r_version.*\n.*packages"), "refused")
  expect_false(submitted)
})

test_that("run_job refuses a bad path and a bad wait", {
  expect_error(run_job("no-such.qmd"), "existing job file")
  job <- status_job()
  expect_error(run_job(job, wait = -1), "`wait`")
  expect_error(run_job(job, wait = "5"), "`wait`")
  expect_error(run_job(job, wait = c(1, 2)), "`wait`")
  expect_error(run_job(job, wait = NA_real_), "`wait`")
})

test_that("run_job returns the status job_status() returns, invisibly, with and without a wait", {
  root <- lock_study()
  job <- file.path(root, "analyses", "x.qmd")
  writeLines(".job <- hvtiRtemplates:::.job_setup(SUBJECT, TYPE)", job)
  ok_checks()
  want <- list(state = "running", pid = 1L, host = "h", progress = list(checks = "render_r"))
  testthat::local_mocked_bindings(submit_job = function(...) invisible(NULL),
                                  job_status = function(path, quiet = FALSE) want)
  capture.output(res <- withVisible(run_job(job, wait = 0)))
  expect_false(res$visible)
  expect_identical(res$value, want)
  capture.output(res <- withVisible(run_job(job, wait = 1)))
  expect_false(res$visible)
  expect_identical(res$value, want)
})

test_that("run_job reports a study render in progress alongside the other checks", {
  root <- lock_study()
  job <- file.path(root, "analyses", "x.qmd")
  writeLines("---\ntitle: x\n---", job)
  ok_checks()
  testthat::local_mocked_bindings(.check_study_render = function(...) .check("study_render", FALSE, "busy.", "wait."))
  expect_error(expect_output(run_job(job), "study_render"), "refused")
})

test_that("render_r is expected where the job calls .job_setup(), memory where it calls guard_memory()", {
  root <- withr::local_tempdir()
  j <- file.path(root, "a.qmd")
  writeLines(".job <- hvtiRtemplates:::.job_setup(SUBJECT, TYPE)", j)
  expect_identical(.expected_checks(j), "render_r")
  writeLines(c(".job <- hvtiRtemplates:::.job_setup(SUBJECT, TYPE)", "guard_memory(need, 'fit')"), j)
  expect_identical(.expected_checks(j), c("render_r", "memory"))
})

test_that("a legacy job (four old setup chunks, no .job_setup()) expects no in-render checks", {
  # The pre-consolidation shape, as rfs-fit.qmd had it at 384234f^: guard-edits, guard-partial, set.
  root <- withr::local_tempdir()
  j <- file.path(root, "legacy.qmd")
  writeLines(c("```{r}", "#| label: guard-edits", "hvtiRtemplates:::.guard_edits()", "```",
               "```{r}", "#| label: set", ".root <- hvtiRtemplates:::.find_study_root(getwd())", "```"), j)
  expect_identical(.expected_checks(j), character(0))
})

test_that("run_job notes that a legacy job runs without in-render checks, naming upgrade_job()", {
  root <- lock_study()
  job <- file.path(root, "analyses", "legacy.qmd")
  writeLines(c("```{r}", "#| label: set", "x <- 1", "```"), job)
  ok_checks()
  testthat::local_mocked_bindings(submit_job = function(...) invisible(NULL),
                                  job_status = function(path, quiet = FALSE) list(state = "running", pid = 1L, host = "h"))
  out <- paste(capture.output(run_job(job, wait = 1)), collapse = "\n")
  expect_match(out, "predates the in-render checks", fixed = TRUE)
  expect_match(out, 'upgrade_job("legacy.qmd")', fixed = TRUE)
})

test_that("the wait returns once every expected check is recorded", {
  testthat::local_mocked_bindings(job_status = function(path, quiet = FALSE) {
    list(state = "running", pid = 1L, host = "h", progress = list(checks = c("render_r", "memory")))
  })
  out <- capture.output(st <- .wait_for_checks("x.qmd", c("render_r", "memory"), wait = 1, poll = 0))
  expect_identical(st$state, "running")
  expect_match(out, "checks passed", all = FALSE)
})

test_that("the wait returns on failure, printing the diagnosis", {
  want <- list(state = "failed")
  testthat::local_mocked_bindings(job_status = function(path, quiet = FALSE) {
    if (!quiet) cat("x.qmd: failed\n  why: memory: ...\n")
    want
  })
  expect_output(st <- .wait_for_checks("x.qmd", "render_r", wait = 1, poll = 0), "why: memory")
  expect_identical(st, want)
})

test_that("a render that finishes between polls is reported finished, not running or starting", {
  testthat::local_mocked_bindings(job_status = function(path, quiet = FALSE) {
    if (!quiet) cat("x.qmd: finished in 40 s\n")
    list(state = "finished", progress = list(checks = "render_r"))
  })
  out <- capture.output(st <- .wait_for_checks("x.qmd", c("render_r", "memory"), wait = 60, poll = 0))
  expect_identical(st$state, "finished")
  expect_match(out, "finished", all = FALSE)
  expect_false(any(grepl("still starting|checks passed", out)))
})

test_that("the wait times out with a pointer to hvti status", {
  want <- list(state = "running", progress = list())
  testthat::local_mocked_bindings(job_status = function(path, quiet = FALSE) want)
  expect_output(st <- .wait_for_checks("x.qmd", "render_r", wait = 0, poll = 0), "still starting", fixed = TRUE)
  expect_identical(st, want)
})
