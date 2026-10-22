fx <- function(name) readLines(testthat::test_path("fixtures-diagnose", paste0(name, ".log")))

test_that("killed workers with the peak at the cap read as memory, and the fix uses the recorded need (failures 4-5)", {
  d <- .diagnose_failure(fx("oom-workers"), list(mem_peak_gib = 19.1, mem_limit_gib = 19.2,
                                                 progress = list(mem_need_gib = 40)))
  expect_match(d$reason, "ran out of memory: peak 19.1 of a 19.2 GiB cap", fixed = TRUE)
  expect_match(d$fix, "Medium", fixed = TRUE)   # 40 GiB needs the Medium profile
})

test_that("with no recorded need, the fix asks for a larger session than this one", {
  d <- .diagnose_failure(fx("oom-workers"), list(mem_peak_gib = 19.1, mem_limit_gib = 19.2))
  expect_match(d$fix, "larger than this one (19.2 GiB)", fixed = TRUE)
})

test_that("the same signature without a recorded peak is hedged", {
  d <- .diagnose_failure(fx("oom-workers"), list())
  expect_match(d$reason, "^probably memory", ignore.case = TRUE)
})

test_that("a missing package reads as the wrong R or library", {
  d <- .diagnose_failure(fx("no-package"), list())
  expect_match(d$reason, "notapkg", fixed = TRUE)
  expect_match(d$fix, "hvti run", fixed = TRUE)
})

test_that("Quitting from names the chunk and quotes the error printed above it", {
  d <- .diagnose_failure(fx("quitting"), list())
  expect_match(d$reason, "chunk `fit`", fixed = TRUE)
  expect_match(d$fix, "^Error.*boom")
  expect_false(grepl("See the log", d$fix, fixed = TRUE))
})

test_that("a check's refusal through Quarto (Error:, then '! memory: ...', then Quitting) is passed through", {
  d <- .diagnose_failure(fx("guard"), list())
  expect_match(d$reason, "^memory: probe refusal")
  expect_match(d$fix, "Large", fixed = TRUE)
})

test_that("every check name passes through, study_render included", {
  for (nm in c("r_version", "packages", "run_state", "quarto", "render_r", "memory", "study_render")) {
    d <- .diagnose_failure(c("Error:", paste0("! ", nm, ": refused."), "Fix it.", "Quitting from x.qmd:1-2 [fit]"), list())
    expect_identical(d$reason, paste0(nm, ": refused."))
    expect_identical(d$fix, "Fix it.")
  }
})

test_that("an unknown failure shows the last 20 log lines", {
  d <- .diagnose_failure(fx("unknown"), list())
  expect_match(d$reason, "no known cause", fixed = TRUE)
  expect_lte(length(strsplit(d$fix, "\n")[[1]]), 20L)
})

test_that("a log carrying a refusal and a missing package is explained by the refusal", {
  d <- .diagnose_failure(fx("guard-and-package"), list())
  expect_match(d$reason, "^memory: probe refusal")
})

test_that("a log carrying killed workers and a missing package is explained by memory", {
  d <- .diagnose_failure(fx("memory-and-package"), list(mem_peak_gib = 19.1, mem_limit_gib = 19.2))
  expect_match(d$reason, "ran out of memory", fixed = TRUE)
  d <- .diagnose_failure(fx("memory-and-package"), list())
  expect_match(d$reason, "^probably memory", ignore.case = TRUE)
})

test_that("job_status prints why and fix for a failed run", {
  job <- status_job()
  file.copy(test_path("fixtures-diagnose", "no-package.log"), .run_files(job)$log, overwrite = TRUE)
  .write_status(.run_files(job)$status, state = "failed", exit_code = 1L, pid = 999999L)
  expect_output(job_status(job), "why: .*notapkg")
  expect_output(job_status(job), "fix: .*hvti run")
})

test_that("the diagnosis is returned even when quiet, and a failing diagnosis never breaks job_status", {
  job <- status_job()
  file.copy(test_path("fixtures-diagnose", "quitting.log"), .run_files(job)$log, overwrite = TRUE)
  .write_status(.run_files(job)$status, state = "failed", exit_code = 1L, pid = 999999L)
  st <- job_status(job, quiet = TRUE)
  expect_match(st$diagnosis$reason, "chunk `fit`", fixed = TRUE)
  local_mocked_bindings(.diagnose_failure = function(...) stop("boom"))
  expect_output(st <- job_status(job), "failed")
  expect_null(st$diagnosis)
})
