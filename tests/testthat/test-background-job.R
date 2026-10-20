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

test_that("an empty status file fails loud, naming the file", {
  job <- status_job()
  file.create(.run_files(job)$status)
  expect_error(job_status(job, quiet = TRUE), "nb.boostmtree.x.boost.run.yml", fixed = TRUE)
})

test_that("an unknown state fails loud, naming it", {
  job <- status_job()
  .write_status(.run_files(job)$status, state = "nonsense")
  expect_error(job_status(job, quiet = TRUE), "nonsense", fixed = TRUE)
})

test_that(".write_status() leaves no temporary file and reads back", {
  job <- status_job()
  f <- .run_files(job)$status
  .write_status(f, state = "finished", elapsed_s = 3)
  expect_false(file.exists(paste0(f, ".tmp")))
  expect_identical(job_status(job, quiet = TRUE)$state, "finished")
})
