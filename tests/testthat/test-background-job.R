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

# A process outside the test session, so a test can watch whether it was signalled.
bystander <- function(cmd = "exec sleep 60") {
  dir <- withr::local_tempdir(.local_envir = parent.frame())
  pidf <- file.path(dir, "pid")
  launch <- sprintf("sh -c %s", shQuote(cmd))
  system(sprintf("cd %s; %s > /dev/null 2>&1 & echo $! > %s", shQuote(dir), launch, shQuote(pidf)), wait = TRUE)
  pid <- as.integer(readLines(pidf))
  h <- ps::ps_handle(pid)
  withr::defer(try(ps::ps_kill(h), silent = TRUE), envir = parent.frame())
  list(pid = pid, h = h, dir = dir, created = sprintf("%.6f", as.numeric(ps::ps_create_time(h))))
}

running_on <- function(job, b, host = Sys.info()[["nodename"]]) {
  .write_status(.run_files(job)$status, state = "running", pid = b$pid, created = b$created, host = host,
                started = .stamp(Sys.time() - 60))
}

alive <- function(h) isTRUE(tryCatch(ps::ps_is_running(h), error = function(e) FALSE))

test_that("cancelling a running job on its own host stops it, records cancelled and clears its progress", {
  skip_on_os("windows")
  skip_on_cran()
  job <- status_job()
  .submit_job(job, final = FALSE, render_call = "Sys.sleep(60)", root = dirname(job))
  st <- wait_for(job, "running")
  expect_identical(st$state, "running")
  h <- ps::ps_handle(as.integer(st$pid))
  writeLines("stage: fit", .run_files(job)$progress)
  out <- cancel_job(job, grace = 5, quiet = TRUE)
  expect_identical(out$state, "cancelled")
  expect_false(alive(h))
  expect_false(file.exists(.run_files(job)$progress))
  expect_false(dir.exists(.run_files(job)$lock))
  rec <- yaml::read_yaml(.run_files(job)$status)
  expect_identical(rec$state, "cancelled")
  expect_identical(rec$started, st$started)
  expect_false(is.null(rec$ended))
  expect_output(job_status(job), "cancelled at", fixed = TRUE)
  .submit_job(job, final = FALSE, render_call = "1", root = dirname(job))  # and it can be submitted again
  expect_identical(wait_for(job, c("finished", "failed", "vanished"))$state, "finished")
})

test_that("a job that ignores SIGTERM is killed after the grace period", {
  skip_on_os("windows")
  skip_on_cran()
  job <- status_job()
  b <- bystander("trap '' TERM; while :; do sleep 1; done")
  running_on(job, b)
  t0 <- Sys.time()
  expect_identical(cancel_job(job, grace = 1, quiet = TRUE)$state, "cancelled")
  expect_false(alive(b$h))
  expect_gte(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
})

# A render call that starts a stand-in for Quarto the way processx does, in a session of its own, then orphans it,
# so it is neither the runner's descendant nor in its process group. Its pid lands in render.pid.
detached_render <- function(job) {
  script <- file.path(dirname(job), "render.R")
  # An Rscript, as knitr's process is: macOS will not show another process the environment of a system binary such as
  # sleep, so a stand-in like that could not be found by its marker there.
  rscript <- file.path(R.home("bin"), "Rscript")
  cmd <- paste("perl -MPOSIX -e 'POSIX::setsid(); open(F, q(>render.pid)); print F $$; close(F); exec @ARGV'",
               shQuote(rscript), "-e 'Sys.sleep(61)' > /dev/null 2>&1 &")
  writeLines(c(sprintf("system(%s)", deparse(cmd)), "Sys.sleep(60)"), script)
  sprintf("source(%s)", deparse(script))
}

render_handle <- function(job) {
  f <- file.path(dirname(job), "render.pid")
  for (i in 1:40) if (file.exists(f) && length(readLines(f, warn = FALSE))) break else Sys.sleep(0.25)
  h <- ps::ps_handle(as.integer(readLines(f, warn = FALSE)))
  withr::defer(try(ps::ps_kill(h), silent = TRUE), envir = parent.frame())
  h
}

test_that("the render is stopped even in a session of its own, found by the run's marker", {
  skip_on_os("windows")
  skip_on_cran()
  skip_if(!nzchar(Sys.which("perl")))
  job <- status_job()
  .submit_job(job, final = FALSE, render_call = detached_render(job), root = dirname(job))
  expect_identical(wait_for(job, "running")$state, "running")
  render <- render_handle(job)
  expect_true(alive(render))
  expect_identical(cancel_job(job, grace = 5, quiet = TRUE)$state, "cancelled")
  expect_false(alive(render))
})

test_that("a runner killed by hand is recorded failed, and the render it left running is stopped", {
  skip_on_os("windows")
  skip_on_cran()
  skip_if(!nzchar(Sys.which("perl")))
  job <- status_job()
  .submit_job(job, final = FALSE, render_call = detached_render(job), root = dirname(job))
  st <- wait_for(job, "running")
  render <- render_handle(job)
  ps::ps_kill(ps::ps_handle(as.integer(st$pid)))
  expect_identical(wait_for(job, "vanished")$state, "vanished")
  expect_true(alive(render))
  out <- cancel_job(job, grace = 5, quiet = TRUE)
  expect_identical(out$state, "failed")
  expect_false(alive(render))
})

test_that("a run recorded with no creation time is refused, not signalled by its pid alone", {
  skip_on_os("windows")
  skip_on_cran()
  job <- status_job()
  b <- bystander()
  .write_status(.run_files(job)$status, state = "running", pid = b$pid, host = Sys.info()[["nodename"]],
                started = .stamp(Sys.time() - 60))
  expect_error(cancel_job(job, grace = 1, quiet = TRUE), "no creation time", fixed = TRUE)
  expect_true(alive(b$h))
  expect_identical(yaml::read_yaml(.run_files(job)$status)$state, "running")
})

test_that("a process the job starts while shutting down is found by a fresh scan and stopped", {
  skip_on_os("windows")
  skip_on_cran()
  skip_if(!nzchar(Sys.which("perl")))
  job <- status_job()
  d <- dirname(job)
  # A render whose SIGTERM handler starts a marked process in a session of its own, after the first scan has run.
  writeLines("writeLines(as.character(Sys.getpid()), 'late.pid'); Sys.sleep(61)", file.path(d, "late.R"))
  writeLines(c(sprintf("trap 'perl -MPOSIX -e \"POSIX::setsid(); exec @ARGV\" %s late.R > /dev/null 2>&1 &' TERM",
                       shQuote(file.path(R.home("bin"), "Rscript"))),
               "while :; do sleep 1; done"), file.path(d, "render.sh"))
  .submit_job(job, final = FALSE, render_call = "system('sh render.sh')", root = d)
  expect_identical(wait_for(job, "running")$state, "running")
  Sys.sleep(1)
  expect_identical(cancel_job(job, grace = 3, quiet = TRUE)$state, "cancelled")
  expect_true(file.exists(file.path(d, "late.pid")))
  late <- as.integer(readLines(file.path(d, "late.pid")))
  withr::defer(try(ps::ps_kill(ps::ps_handle(late)), silent = TRUE))
  expect_false(.pid_alive(late))
})

test_that("a live pid whose creation time is seconds off is refused, not signalled", {
  skip_on_os("windows")
  skip_on_cran()
  job <- status_job()
  b <- bystander()
  b$created <- sprintf("%.6f", as.numeric(b$created) - 30)  # within job_status()'s minute, so it reads running
  running_on(job, b)
  expect_identical(job_status(job, quiet = TRUE)$state, "running")
  expect_error(cancel_job(job, grace = 1, quiet = TRUE), "may not be the job's", fixed = TRUE)
  expect_true(alive(b$h))
  expect_identical(yaml::read_yaml(.run_files(job)$status)$state, "running")
})

test_that("a live pid without the run's marker is not the job's, and is not signalled", {
  skip_on_os("windows")
  skip_on_cran()
  job <- status_job()
  b <- bystander(sprintf("exec %s -e 'Sys.sleep(60)'", shQuote(file.path(R.home("bin"), "Rscript"))))
  .write_status(.run_files(job)$status, state = "running", pid = b$pid, created = b$created,
                marker = "PSHVTINOTHERE_1", host = Sys.info()[["nodename"]], started = .stamp(Sys.time() - 60))
  expect_identical(cancel_job(job, grace = 1, quiet = TRUE)$state, "cancelled")
  expect_true(alive(b$h))
})

test_that("a job recorded on another host is refused, naming the host, and nothing changes", {
  local_mocked_bindings(.is_windows = function() FALSE)  # no process is signalled: only the records are read
  job <- status_job()
  f <- .run_files(job)
  .write_status(f$status, state = "running", pid = 999999L, host = "lri-r99", started = "x")
  writeLines("stage: fit", f$progress)
  before <- readLines(f$status)
  expect_error(cancel_job(job, quiet = TRUE), "run cancel_job() in an R session on lri-r99", fixed = TRUE)
  expect_identical(readLines(f$status), before)
  expect_true(file.exists(f$progress))
  expect_false(dir.exists(f$lock))
})

test_that("a job on another host can be abandoned, signalling nothing, recording why and clearing its progress", {
  local_mocked_bindings(.is_windows = function() FALSE)  # no process is signalled: only the records are read
  job <- status_job()
  f <- .run_files(job)
  .write_status(f$status, state = "running", pid = 999999L, host = "lri-r99", started = "x")
  writeLines("stage: fit", f$progress)
  expect_error(cancel_job(job, quiet = TRUE), "other_host = \"abandon\"", fixed = TRUE)
  st <- cancel_job(job, other_host = "abandon", quiet = TRUE)
  expect_identical(st$state, "cancelled")
  expect_match(st$reason, "abandoned from", fixed = TRUE)
  expect_match(st$reason, "lri-r99", fixed = TRUE)
  expect_identical(st$host, "lri-r99")
  expect_false(file.exists(f$progress))
  expect_output(job_status(job), "nothing signalled", fixed = TRUE)
  expect_error(cancel_job(job, other_host = "maybe"), "should be one of")
})

test_that("abandon changes nothing for a job on this host", {
  local_mocked_bindings(.is_windows = function() FALSE)  # no process is signalled: only the records are read
  job <- status_job()
  f <- .run_files(job)$status
  .write_status(f, state = "finished", exit_code = 0L, pid = 999999L, elapsed_s = 3)
  expect_identical(cancel_job(job, other_host = "abandon", quiet = TRUE)$state, "finished")
  .write_status(f, state = "running", pid = Sys.getpid(), host = Sys.info()[["nodename"]], started = "x")
  expect_error(cancel_job(job, other_host = "abandon", quiet = TRUE), "no creation time", fixed = TRUE)
})

test_that("a progress file left with no status file, from another host, is refused the same way", {
  local_mocked_bindings(.is_windows = function() FALSE)  # no process is signalled: only the records are read
  job <- status_job()
  .write_status(.run_files(job)$progress, pid = 999999L, host = "lri-r98", started = .stamp(Sys.time() - 3600),
                updated = .stamp(Sys.time() - 60), stage = "fit", stage_index = 2L, stage_count = 3L,
                stages = c("tbl-data", "fit", "effects"), done = list())
  expect_identical(job_status(job, quiet = TRUE)$state, "running")
  expect_error(cancel_job(job, quiet = TRUE), "lri-r98", fixed = TRUE)
})

test_that("a finished job is left as it is", {
  local_mocked_bindings(.is_windows = function() FALSE)  # no process is signalled: only the records are read
  job <- status_job()
  f <- .run_files(job)$status
  .write_status(f, state = "finished", exit_code = 0L, pid = 999999L, elapsed_s = 3)
  before <- readLines(f)
  expect_identical(cancel_job(job, quiet = TRUE)$state, "finished")
  expect_identical(readLines(f), before)
  expect_identical(cancel_job(status_job(), quiet = TRUE)$state, "none")
})

test_that("a pid reused by another process is not signalled, and the run is recorded failed", {
  skip_on_os("windows")
  skip_on_cran()
  job <- status_job()
  b <- bystander()
  b$created <- sprintf("%.6f", as.numeric(b$created) - 3600)  # the recorded job began an hour before this process
  running_on(job, b)
  writeLines("stage: fit", .run_files(job)$progress)
  st <- cancel_job(job, grace = 1, quiet = TRUE)
  expect_true(alive(b$h))
  expect_identical(st$state, "failed")
  expect_match(st$reason, "ended without recording an end", fixed = TRUE)
  expect_false(file.exists(.run_files(job)$progress))
  expect_output(job_status(job), "ended without recording an end", fixed = TRUE)
})

test_that("a submission that never started is recorded failed, saying so", {
  local_mocked_bindings(.is_windows = function() FALSE)  # no process is signalled: only the records are read
  job <- status_job()
  .write_status(.run_files(job)$status, state = "submitted", submitted = .stamp(Sys.time() - 600))
  st <- cancel_job(job, quiet = TRUE)
  expect_identical(st$state, "failed")
  expect_identical(st$reason, "it never started")
})

test_that("a cancel is refused, signalling nothing, while another call holds the claim", {
  skip_on_os("windows")
  skip_on_cran()
  job <- status_job()
  b <- bystander()
  running_on(job, b)
  f <- .run_files(job)
  dir.create(f$lock)
  expect_error(cancel_job(job, quiet = TRUE), "run.lock exists", fixed = TRUE)
  expect_true(alive(b$h))
  expect_true(dir.exists(f$lock))
})

test_that("cancel_job() refuses Windows, a path that is not a job and a bad grace", {
  expect_error(cancel_job(file.path(tempdir(), "no-such-job.qmd")), "existing job file")
  job <- status_job()
  expect_error(cancel_job(job, grace = -1), "`grace`")
  local_mocked_bindings(.is_windows = function() TRUE)
  expect_error(cancel_job(job), "Windows")
})

test_that("the already-running refusal names both run files for another host, and cancel_job() for this one", {
  skip_on_os("windows")
  skip_on_cran()
  job <- status_job()
  f <- .run_files(job)
  .write_status(f$status, state = "running", pid = 999999L, host = "lri-r97", started = "x")
  err <- tryCatch(.submit_job(job, final = FALSE, render_call = "1", root = dirname(job)), error = conditionMessage)
  expect_match(err, f$status, fixed = TRUE)
  expect_match(err, f$progress, fixed = TRUE)
  expect_match(err, "cancel_job() in a session there", fixed = TRUE)
  b <- bystander()
  running_on(job, b)
  expect_error(.submit_job(job, final = FALSE, render_call = "1", root = dirname(job)), "Stop it with cancel_job()",
               fixed = TRUE)
})

test_that("job_status prints the recorded peak against the limit", {
  job <- status_job()
  .write_status(.run_files(job)$status, state = "failed", exit_code = 1L, pid = 999999L,
                mem_peak_gib = 76.7, mem_limit_gib = 76.8)
  expect_output(job_status(job), "memory: 76.7 of 76.8 GiB (peak)", fixed = TRUE)
})

test_that("the runner records the cgroup peak at its end", {
  lines <- .runner_lines("/s/a.qmd", "/s/a.run.yml", FALSE, "TRUE")
  expect_true(any(grepl("hvtiRtemplates:::.run_memory_fields()", lines, fixed = TRUE)))
})

# Runs the generated runner in-process, with quit() stubbed, so the terminal write is observed.
run_runner <- function(status) {
  env <- new.env()
  env$quit <- function(...) invisible(NULL)
  eval(parse(text = .runner_lines("/s/a.qmd", status, FALSE, "TRUE")), envir = env)
  yaml::read_yaml(status)
}

test_that("a memory reader that errors still lets the runner record finished", {
  status <- file.path(withr::local_tempdir(), "a.run.yml")
  testthat::local_mocked_bindings(.cgroup_memory = function(...) stop("no cgroup"))
  st <- run_runner(status)
  expect_identical(st$state, "finished")
  expect_null(st$mem_peak_gib)
})

test_that("NA memory readings are dropped, not written or fatal", {
  status <- file.path(withr::local_tempdir(), "a.run.yml")
  testthat::local_mocked_bindings(.cgroup_memory = function(...) list(limit_gib = NA_real_, peak_gib = NA_real_))
  st <- run_runner(status)
  expect_identical(st$state, "finished")
  expect_null(st$mem_limit_gib)
})

test_that("submit_job exports HVTI_RUN_R to the runner", {
  captured <- NULL
  testthat::local_mocked_bindings(.launch = function(cmd) captured <<- cmd)
  job <- status_job()
  .submit_job(job, FALSE, "TRUE", dirname(job))
  expect_match(captured, "HVTI_RUN_R=", fixed = TRUE)
  expect_match(captured, "export [A-Za-z0-9_]+ HVTI_JOB_MARKER HVTI_RUN_R ")
  expect_match(captured, R.home("bin"), fixed = TRUE)
})
