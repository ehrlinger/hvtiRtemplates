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
  expect_identical(f$progress, "/s/analyses/nb.x.run.progress")
  expect_identical(f$lock, "/s/analyses/nb.x.run.lock")
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

test_that("a status file that is a bare scalar fails loud, naming the file", {
  job <- status_job()
  writeLines("foo", .run_files(job)$status)
  expect_error(job_status(job, quiet = TRUE), "nb.boostmtree.x.boost.run.yml", fixed = TRUE)
})

test_that("a submission that never started says so, and a log-less one says that too", {
  job <- status_job()
  old <- format(Sys.time() - 600, "%Y-%m-%dT%H:%M:%S%z")
  .write_status(.run_files(job)$status, state = "submitted", submitted = old)
  out <- utils::capture.output(job_status(job))
  expect_match(out, "never started", fixed = TRUE)
  expect_match(out, "(log missing or empty)", fixed = TRUE)
})

test_that("a log that cannot be written stops the submission before any process or status file", {
  job <- status_job()
  dir.create(.run_files(job)$log)
  expect_error(.submit_job(job, final = FALSE, render_call = "1", root = dirname(job)), "cannot write the log file")
  expect_false(file.exists(.run_files(job)$status))
})

test_that("a running job on another host is not downgraded to vanished", {
  job <- status_job()
  .write_status(.run_files(job)$status, state = "running", pid = 999999L, host = "some-other-host", started = "x")
  out <- utils::capture.output(st <- job_status(job))
  expect_identical(st$state, "running")
  expect_match(out, "some-other-host", fixed = TRUE)
  expect_error(.submit_job(job, final = FALSE, render_call = "1", root = dirname(job)),
               .run_files(job)$status, fixed = TRUE)
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

wait_for <- function(job, states, seconds = 30) {
  for (i in seq_len(seconds * 4)) {
    st <- job_status(job, quiet = TRUE)
    if (st$state %in% states) return(st)
    Sys.sleep(0.25)
  }
  st
}

test_that("a submitted job returns at once, then runs to finished", {
  skip_on_os("windows")
  skip_on_cran()
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
  skip_on_os("windows")
  skip_on_cran()
  job <- status_job()
  .submit_job(job, final = FALSE, render_call = "stop('boom from the job')", root = dirname(job))
  st <- wait_for(job, c("finished", "failed", "vanished"))
  expect_identical(st$state, "failed")
  expect_identical(st$exit_code, 1L)
  expect_match(paste(readLines(.run_files(job)$log), collapse = "\n"), "boom from the job", fixed = TRUE)
})

test_that("a killed job reads vanished, and a running one cannot be submitted twice", {
  skip_on_os("windows")
  skip_on_cran()
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

test_that("submitting removes the last run's progress file", {
  skip_on_os("windows")
  skip_on_cran()
  job <- status_job()
  writeLines("stage: fit", .run_files(job)$progress)
  .submit_job(job, final = FALSE, render_call = "1", root = dirname(job))
  expect_false(file.exists(.run_files(job)$progress))
  wait_for(job, c("finished", "failed", "vanished"))
})

test_that("a submit is refused, launching nothing, while another call holds the claim", {
  job <- status_job()
  f <- .run_files(job)
  expect_true(dir.create(f$lock))
  expect_error(.submit_job(job, final = FALSE, render_call = "1", root = dirname(job)), f$lock, fixed = TRUE)
  expect_error(.submit_job(job, final = FALSE, render_call = "1", root = dirname(job)), "delete that directory", fixed = TRUE)
  expect_error(.submit_job(job, final = FALSE, render_call = "1", root = dirname(job)), "s old", fixed = TRUE)
  expect_false(file.exists(f$log))
  expect_false(file.exists(f$runner))
  expect_false(file.exists(f$status))
  expect_true(dir.exists(f$lock))  # the holder's claim is not ours to release
})

test_that("the claim is released after a submit that fails, and after one that succeeds", {
  skip_on_os("windows")
  skip_on_cran()
  job <- status_job()
  f <- .run_files(job)
  dir.create(f$log)
  expect_error(.submit_job(job, final = FALSE, render_call = "1", root = dirname(job)), "cannot write the log file")
  expect_false(dir.exists(f$lock))
  unlink(f$log, recursive = TRUE)
  .submit_job(job, final = FALSE, render_call = "1", root = dirname(job))
  expect_false(dir.exists(f$lock))
  wait_for(job, c("finished", "failed", "vanished"))
})

test_that("a live pid with a different creation time is a different process, and reads vanished", {
  job <- status_job()
  f <- .run_files(job)$status
  mine <- as.numeric(ps::ps_create_time(ps::ps_handle()))
  .write_status(f, state = "running", pid = Sys.getpid(), created = sprintf("%.6f", mine - 3600))
  expect_identical(job_status(job, quiet = TRUE)$state, "vanished")
  .write_status(f, state = "running", pid = Sys.getpid(), created = sprintf("%.6f", mine))
  expect_identical(job_status(job, quiet = TRUE)$state, "running")
})

test_that("a status written without a creation time is judged by its pid alone", {
  job <- status_job()
  .write_status(.run_files(job)$status, state = "running", pid = Sys.getpid())
  expect_identical(job_status(job, quiet = TRUE)$state, "running")
})

test_that("the runner records its creation time, and the live job reads running by it", {
  skip_on_os("windows")
  skip_on_cran()
  job <- status_job()
  .submit_job(job, final = FALSE, render_call = "Sys.sleep(60)", root = dirname(job))
  st <- wait_for(job, "running")
  expect_identical(st$state, "running")
  expect_type(st$created, "character")
  expect_lt(abs(as.numeric(st$created) - as.numeric(ps::ps_create_time(ps::ps_handle(as.integer(st$pid))))), 60)
  ps::ps_kill(ps::ps_handle(as.integer(st$pid)))
  wait_for(job, "vanished")
})

test_that("an unwritable directory says the claim cannot be created, not that another call holds it", {
  skip_on_os("windows")
  skip_on_cran()
  skip_if(identical(Sys.info()[["user"]], "root"))
  job <- status_job()
  Sys.chmod(dirname(job), "555")
  withr::defer(Sys.chmod(dirname(job), "755"))
  expect_error(.submit_job(job, final = FALSE, render_call = "1", root = dirname(job)), "cannot create", fixed = TRUE)
})

test_that("a creation time 30 s off still reads running, and one 10 minutes off reads vanished", {
  job <- status_job()
  f <- .run_files(job)$status
  mine <- as.numeric(ps::ps_create_time(ps::ps_handle()))
  .write_status(f, state = "running", pid = Sys.getpid(), created = sprintf("%.6f", mine + 30))
  expect_identical(job_status(job, quiet = TRUE)$state, "running")
  .write_status(f, state = "running", pid = Sys.getpid(), created = sprintf("%.6f", mine - 600))
  expect_identical(job_status(job, quiet = TRUE)$state, "vanished")
})
