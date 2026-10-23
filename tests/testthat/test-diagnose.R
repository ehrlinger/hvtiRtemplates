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

test_that("after an OOM the recommended cap is larger than the cap that failed, whatever the estimate said", {
  # An underestimate: Medium ran out at its cap, and an estimate of 37.5 GiB alone would name Medium again.
  d <- .diagnose_failure(fx("oom-workers"), list(mem_peak_gib = 76.7, mem_limit_gib = 76.8,
                                                 progress = list(mem_need_gib = 37.5)))
  expect_no_match(d$fix, "Medium", fixed = TRUE)
  expect_match(d$fix, "\"Large\"", fixed = TRUE)
  # An estimate that would name a smaller profile than the one that failed.
  d <- .diagnose_failure(fx("oom-workers"), list(mem_peak_gib = 38.3, mem_limit_gib = 38.4,
                                                 progress = list(mem_need_gib = 10)))
  expect_match(d$fix, "\"Medium\"", fixed = TRUE)
  # Nothing larger than Large: the fallback.
  d <- .diagnose_failure(fx("oom-workers"), list(mem_peak_gib = 153.5, mem_limit_gib = 153.6,
                                                 progress = list(mem_need_gib = 37.5)))
  expect_match(d$fix, "larger than this one (153.6 GiB)", fixed = TRUE)
})

test_that("a recorded need of zero (a cached rerender) counts as no estimate", {
  d <- .diagnose_failure(fx("oom-workers"), list(mem_peak_gib = 19.1, mem_limit_gib = 19.2,
                                                 progress = list(mem_need_gib = 0)))
  expect_match(d$fix, "larger than this one (19.2 GiB)", fixed = TRUE)
  expect_no_match(d$fix, "estimated at 0", fixed = TRUE)
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

test_that("guard_memory()'s refusal through Quarto is passed through, and rlang's Backtrace is not taken as its fix", {
  d <- .diagnose_failure(fx("guard"), list())
  expect_match(d$reason, "^memory: this fit needs about 100 GiB")
  expect_match(d$reason, "Start a \"Large\" session", fixed = TRUE)
  expect_identical(d$fix, "")   # a one-line refusal carries its advice in the reason
  expect_no_match(paste(d$reason, d$fix), "Backtrace", fixed = TRUE)
})

test_that(".job_setup()'s render_r refusal through Quarto keeps its fix line, not the Backtrace", {
  d <- .diagnose_failure(fx("render-r"), list())
  expect_match(d$reason, "^render_r: Quarto ran this render on R [0-9.]+ \\(<tmp>/bin\\), not the R that submitted it, R 4[.]5[.]3")
  expect_match(d$fix, "^A QUARTO_R setting")
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
  expect_match(d$reason, "^memory: this fit needs")
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

test_that("'Killed' alone on a line is a kill; a line that merely starts with it is not", {
  expect_match(.diagnose_failure(c("Killed"), list())$reason, "^probably memory")
  expect_match(.diagnose_failure(c("Killed 3 outliers"), list())$reason, "no known cause", fixed = TRUE)
})

test_that("a recorded exit code is not read as a kill: the runner records only 0 or 1", {
  d <- .diagnose_failure(c("something unrelated"), list(exit_code = 137L, mem_peak_gib = 19.1, mem_limit_gib = 19.2))
  expect_match(d$reason, "no known cause", fixed = TRUE)
  expect_match(.diagnose_failure(c("exit status 137"), list())$reason, "^probably memory")   # the log's own text still counts
})

test_that("the error quoted for a chunk stops before the Backtrace", {
  d <- .diagnose_failure(fx("quitting-backtrace"), list())
  expect_match(d$fix, "inner failure second line", fixed = TRUE)
  expect_false(grepl("Backtrace", d$fix, fixed = TRUE))
})

test_that("a refusal of three lines is not cut", {
  d <- .diagnose_failure(c("Error:", "! memory: this fit needs 40 GiB.", "The session is 19.2 GiB.",
                           "Start a Large session.", "", "Quitting from x.qmd:1-2 [fit]"), list())
  expect_identical(d$reason, "memory: this fit needs 40 GiB. The session is 19.2 GiB.")
  expect_identical(d$fix, "Start a Large session.")
})

test_that("a run that never started gets no diagnosis", {
  job <- status_job()
  file.copy(test_path("fixtures-diagnose", "no-package.log"), .run_files(job)$log, overwrite = TRUE)
  .write_status(.run_files(job)$status, state = "submitted", submitted = "2020-01-01T00:00:00+0000")
  st <- job_status(job, quiet = TRUE)
  expect_identical(st$state, "vanished")
  expect_null(st$diagnosis)
})

test_that("a one-line refusal keeps its reason and prints no empty fix line", {
  job <- status_job()
  writeLines(c("Error:", "! memory: one line only.", "", "Quitting from x.qmd:1-2 [fit]"), .run_files(job)$log)
  .write_status(.run_files(job)$status, state = "failed", exit_code = 1L, pid = 999999L)
  out <- capture.output(job_status(job))
  expect_true(any(grepl("why: memory: one line only.", out, fixed = TRUE)))
  expect_false(any(grepl("fix:", out, fixed = TRUE)))
})
