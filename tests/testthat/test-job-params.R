# Quarto parameters and output names through render_job(), submit_job() and run_job(): one .qmd rendered with
# different params to different reports, each run keeping its own run files under the job's stem and its output name.

variant_wait <- function(job, output_file, states, seconds = 30) {
  for (i in seq_len(seconds * 4)) {
    st <- job_status(job, quiet = TRUE, output_file = output_file)
    if (st$state %in% states) return(st)
    Sys.sleep(0.25)
  }
  st
}

test_that("params and output_file are checked before anything starts", {
  job <- status_job()
  for (fn in list(render_job, submit_job, run_job)) {
    expect_error(fn(job, params = list(1000)), "named list of single values")
    expect_error(fn(job, params = list(fit_m = 1:2)), "named list of single values")
    expect_error(fn(job, params = list(fit_m = NA)), "named list of single values")
    expect_error(fn(job, params = list(a = 1, a = 2)), "named list of single values")
    expect_error(fn(job, params = c(fit_m = 1000)), "named list of single values")
    expect_error(fn(job, output_file = "out/x.html"), "no directory")
    expect_error(fn(job, output_file = "x"), "with an extension")
    expect_error(fn(job, output_file = c("a.html", "b.html")), "one file name")
  }
  expect_error(job_status(job, output_file = "../x.html"), "no directory")
})

test_that("cancel_job() checks output_file before anything starts", {
  skip_on_os("windows")
  expect_error(cancel_job(status_job(), output_file = "x"), "with an extension")
})

test_that("an output_file whose run key names a file beside this job is refused", {
  job <- status_job()
  writeLines("---\ntitle: y\n---", file.path(dirname(job), "nb.boostmtree.x.boost@other.html.qmd"))
  expect_error(submit_job(job, output_file = "other.html"),
               "would share its run files with the job nb.boostmtree.x.boost@other.html.qmd", fixed = TRUE)
  # A job named for the output alone, as the key read before it carried the job, is no longer in the way.
  writeLines("---\ntitle: y\n---", file.path(dirname(job), "plain.html.qmd"))
  expect_silent(.check_output_file("plain.html", job, "submit_job"))
  expect_silent(.check_output_file("other.pdf", job, "submit_job"))
})

test_that("a run with an output_file keeps its run files under the job and the whole output name", {
  f <- .run_files(.run_key("/s/analyses/nb.x.qmd", "nb.x.M1000.html"))
  expect_identical(f$status, "/s/analyses/nb.x@nb.x.M1000.html.run.yml")
  expect_identical(f$log, "/s/analyses/nb.x@nb.x.M1000.html.run.log")
  expect_identical(f$progress, "/s/analyses/nb.x@nb.x.M1000.html.run.progress")
  expect_identical(f$lock, "/s/analyses/nb.x@nb.x.M1000.html.run.lock")
  expect_identical(f$runner, "/s/analyses/nb.x@nb.x.M1000.html.runner")
  # Two jobs given the same output name are two runs, in one folder or in two.
  expect_false(identical(.run_key("/s/analyses/a.qmd", "report.html"), .run_key("/s/analyses/b.qmd", "report.html")))
  expect_false(identical(.run_key("/s/analyses/a.qmd", "report.html"), .run_key("/s/graphs/a.qmd", "report.html")))
  # Two outputs that share a stem are two runs.
  expect_false(identical(.run_key("/s/analyses/nb.x.qmd", "nb.x.M.html"), .run_key("/s/analyses/nb.x.qmd", "nb.x.M.pdf")))
  # No output_file is the job's own run, with the files it has always had.
  expect_identical(.run_key("/s/analyses/nb.x.qmd"), "/s/analyses/nb.x.qmd")
  expect_identical(.run_files(.run_key("/s/analyses/nb.x.qmd"))$status, "/s/analyses/nb.x.run.yml")
})

test_that("submit_job() writes params and output_file into the runner, and a plain submit's runner is unchanged", {
  skip_on_os("windows")
  job <- status_job()
  launched <- character()
  local_mocked_bindings(.launch = function(cmd) launched <<- c(launched, cmd), .find_study_root = function(dir) dir)
  submit_job(job, params = list(fit_m = 1000, label = "M1000", boot = TRUE), output_file = "nb.boostmtree.x.boost.M1000.html")
  f <- .run_files(.run_key(job, "nb.boostmtree.x.boost.M1000.html"))
  runner <- readLines(f$runner)
  expect_true(any(grepl(paste0("render_job(path, final = FALSE, params = list(fit_m = 1000, label = \"M1000\", ",
                               "boot = TRUE), output_file = \"nb.boostmtree.x.boost.M1000.html\")"), runner, fixed = TRUE)))
  # The runner's own record names the job and the output, so printed calls can name both.
  expect_true(any(grepl("base <- c(base, list(job = \"nb.boostmtree.x.boost.qmd\"", runner, fixed = TRUE)))
  st <- yaml::read_yaml(f$status)
  expect_identical(st$state, "submitted")
  expect_identical(st$job, "nb.boostmtree.x.boost.qmd")
  expect_identical(st$output_file, "nb.boostmtree.x.boost.M1000.html")
  expect_match(launched, basename(f$runner), fixed = TRUE)
  # The job's own run is untouched.
  expect_false(file.exists(.run_files(job)$status))
  submit_job(job)
  plain <- readLines(.run_files(job)$runner)
  expect_true(any(grepl("render_job(path, final = FALSE)", plain, fixed = TRUE)))
  expect_false(any(grepl("base <- c(base,", plain, fixed = TRUE)))
  expect_null(yaml::read_yaml(.run_files(job)$status)$output_file)
})

test_that("two output names of one job run side by side, and each is read and refused by its own name", {
  skip_on_os("windows")
  job <- status_job()
  m500 <- "nb.boostmtree.x.boost.M500.html"
  m1000 <- "nb.boostmtree.x.boost.M1000.html"
  local_mocked_bindings(.launch = function(cmd) invisible(0L), .find_study_root = function(dir) dir)
  submit_job(job, output_file = m500)
  .write_status(.run_files(.run_key(job, m500))$status, state = "running", pid = Sys.getpid(),
                host = Sys.info()[["nodename"]], job = basename(job), output_file = m500)
  expect_identical(job_status(job, quiet = TRUE, output_file = m500)$state, "running")
  expect_identical(job_status(job, quiet = TRUE, output_file = m1000)$state, "none")
  expect_identical(job_status(job, quiet = TRUE)$state, "none")
  # The same output name twice is the same run.
  expect_error(submit_job(job, output_file = m500), "nb.boostmtree.x.boost@nb.boostmtree.x.boost.M500.html.qmd is already running")
  # Another output name is another run: its own files take it.
  expect_no_error(submit_job(job, output_file = m1000))
  expect_identical(job_status(job, quiet = TRUE, output_file = m1000)$state, "submitted")
})

test_that("run_job()'s checks name the running output, and Quarto's one render per study still counts it", {
  job <- status_job()
  root <- dirname(job)
  m500 <- "nb.boostmtree.x.boost.M500.html"
  m1000 <- "nb.boostmtree.x.boost.M1000.html"
  .write_status(.run_files(.run_key(job, m500))$status, state = "running", pid = Sys.getpid(),
                host = Sys.info()[["nodename"]], job = basename(job), output_file = m500)
  # The same output again: this run is already running, and the fix names the job and its output_file.
  ck <- .check_run_state(.run_key(job, m500), root)
  expect_false(ck$ok)
  expect_match(ck$fix, 'job_status("nb.boostmtree.x.boost.qmd", output_file = "nb.boostmtree.x.boost.M500.html")',
               fixed = TRUE)
  expect_match(ck$fix, 'cancel_job("nb.boostmtree.x.boost.qmd", output_file = "nb.boostmtree.x.boost.M500.html")',
               fixed = TRUE)
  # Another output of the same job, and the job's own run, are each another render in the study.
  expect_true(.check_run_state(.run_key(job, m1000), root)$ok)
  for (key in list(.run_key(job, m1000), job)) {
    ck <- .check_study_render(key, root)
    expect_false(ck$ok)
    expect_match(ck$fix, 'job_status("nb.boostmtree.x.boost.qmd", output_file = "nb.boostmtree.x.boost.M500.html")',
                 fixed = TRUE)
  }
})

test_that("cancel_job() with an output_file records that run's end, and leaves the job's own run alone", {
  skip_on_os("windows")
  job <- status_job()
  m500 <- "nb.boostmtree.x.boost.M500.html"
  .write_status(.run_files(.run_key(job, m500))$status, state = "running", pid = 999999L,
                host = Sys.info()[["nodename"]], job = basename(job), output_file = m500)
  .write_status(.run_files(job)$status, state = "finished", exit_code = 0L, pid = 999999L)
  st <- cancel_job(job, grace = 0, quiet = TRUE, output_file = m500)
  expect_identical(st$state, "failed")
  rec <- yaml::read_yaml(.run_files(.run_key(job, m500))$status)
  expect_identical(rec$output_file, m500)
  expect_identical(job_status(job, quiet = TRUE)$state, "finished")
})

test_that("render_job() hands params and output_file to Quarto, and the render learns its output for its progress", {
  job <- status_job()
  seen <- NULL
  local_mocked_bindings(quarto_render = function(input, ..., execute_params = NULL, output_file = NULL) {
    seen <<- list(params = execute_params, output_file = output_file, env = Sys.getenv("HVTI_OUTPUT_FILE"))
    invisible(NULL)
  }, .package = "quarto")
  withr::local_envvar(HVTI_OUTPUT_FILE = "inherited.html")
  render_job(job, quiet = TRUE, params = list(fit_m = 1000), output_file = "nb.boostmtree.x.boost.M1000.html")
  expect_identical(seen$params, list(fit_m = 1000))
  expect_identical(seen$output_file, "nb.boostmtree.x.boost.M1000.html")
  expect_identical(seen$env, "nb.boostmtree.x.boost.M1000.html")
  expect_identical(Sys.getenv("HVTI_OUTPUT_FILE"), "inherited.html")
  # With no output_file the render is the job's own, whatever the caller's environment held.
  render_job(job, quiet = TRUE)
  expect_null(seen$params)
  expect_null(seen$output_file)
  expect_identical(seen$env, "")
})

test_that("a render given an output_file writes its progress under that output's name", {
  job <- file.path("studies", "analyses", "nb.boostmtree.x.boost.qmd")
  withr::local_envvar(HVTI_OUTPUT_FILE = "nb.boostmtree.x.boost.M1000.html")
  expect_identical(.progress_path(file.path("studies", "analyses", "nb.boostmtree.x.boost.rmarkdown")),
                   file.path("studies", "analyses", "nb.boostmtree.x.boost@nb.boostmtree.x.boost.M1000.html.run.progress"))
  withr::local_envvar(HVTI_OUTPUT_FILE = NA)
  expect_identical(.progress_path(job), .run_files(job)$progress)
})

test_that("a real submit with an output_file runs, and its runner records the run under the output's name", {
  skip_on_os("windows")
  skip_on_cran()
  job <- status_job()
  out <- "nb.boostmtree.x.boost.M1000.html"
  skip_if_stale_install(dirname(job))
  .submit_job(job, final = FALSE, render_call = "1", root = dirname(job), output_file = out)
  st <- variant_wait(job, out, c("finished", "failed", "vanished"))
  expect_identical(st$state, "finished")
  rec <- yaml::read_yaml(.run_files(.run_key(job, out))$status)
  expect_identical(rec$job, basename(job))
  expect_identical(rec$output_file, out)
  expect_identical(job_status(job, quiet = TRUE)$state, "none")
})

test_that("a Quarto render with params writes the named report, and its progress beside the job under that name", {
  skip_on_cran()
  skip_if_not_installed("quarto")
  skip_if(!nzchar(Sys.which("quarto")))
  dir <- withr::local_tempdir()
  job <- file.path(dir, "nb.boostmtree.x.boost.qmd")
  writeLines(c("---", "title: x", "format: html", "params:", "  fit_m: 1", "---", "",
               "```{r}", "#| label: setup",
               "hvtiRtemplates:::.progress_install(hvtiRtemplates:::.progress_path(knitr::current_input(dir = TRUE)))",
               "```", "",
               "```{r}", "#| label: show", "cat('fit_m is', params$fit_m)", "```"), job)
  for (m in c(500, 1000)) {
    render_job(job, quiet = TRUE, params = list(fit_m = m), output_file = sprintf("nb.boostmtree.x.boost.M%d.html", m))
  }
  for (m in c(500, 1000)) {
    html <- file.path(dir, sprintf("nb.boostmtree.x.boost.M%d.html", m))
    expect_true(file.exists(html))
    expect_match(paste(readLines(html, warn = FALSE), collapse = "\n"), paste("fit_m is", m), fixed = TRUE)
    st <- job_status(job, quiet = TRUE, output_file = basename(html))
    expect_identical(st$state, "finished")
    expect_identical(st$progress$stages, "show")
  }
  expect_false(file.exists(file.path(dir, "nb.boostmtree.x.boost.run.progress")))
})

test_that("two outputs sharing a stem with different extensions are separate runs", {
  skip_on_os("windows")
  job <- status_job()
  html <- "nb.boostmtree.x.boost.M.html"
  pdf <- "nb.boostmtree.x.boost.M.pdf"
  local_mocked_bindings(.launch = function(cmd) invisible(0L), .find_study_root = function(dir) dir)
  submit_job(job, output_file = html)
  .write_status(.run_files(.run_key(job, html))$status, state = "running", pid = Sys.getpid(),
                host = Sys.info()[["nodename"]], job = basename(job), output_file = html)
  expect_identical(job_status(job, quiet = TRUE, output_file = html)$state, "running")
  expect_identical(job_status(job, quiet = TRUE, output_file = pdf)$state, "none")
  expect_no_error(submit_job(job, output_file = pdf))
  expect_identical(yaml::read_yaml(.run_files(.run_key(job, pdf))$status)$output_file, pdf)
  expect_identical(yaml::read_yaml(.run_files(.run_key(job, html))$status)$state, "running")
})

test_that("a run whose record names another output is neither reported nor cancelled under the wrong name", {
  skip_on_os("windows")
  job <- status_job()
  html <- "nb.boostmtree.x.boost.M.html"
  # A record under the .pdf run's files that names the .html output, as an older stem-keyed run would leave.
  key <- .run_key(job, "nb.boostmtree.x.boost.M.pdf")
  .write_status(.run_files(key)$status, state = "running", pid = Sys.getpid(), created = "1",
                host = Sys.info()[["nodename"]], job = basename(job), output_file = html)
  expect_error(job_status(job, quiet = TRUE, output_file = "nb.boostmtree.x.boost.M.pdf"),
               "record output_file \"nb.boostmtree.x.boost.M.html\"", fixed = TRUE)
  signalled <- FALSE
  local_mocked_bindings(.stop_procs = function(...) {
    signalled <<- TRUE
    character()
  })
  expect_error(cancel_job(job, grace = 0, quiet = TRUE, output_file = "nb.boostmtree.x.boost.M.pdf"),
               "nothing was signalled")
  expect_false(signalled)
  expect_identical(yaml::read_yaml(.run_files(key)$status)$state, "running")
})

# Two jobs with the same output name, beside each other (`a`, `b`) or in another folder (`c`), each with a recorded run.
two_jobs_one_output <- function(env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)
  dir.create(file.path(root, "analyses"))
  dir.create(file.path(root, "graphs"))
  jobs <- c(a = file.path(root, "analyses", "a.qmd"), b = file.path(root, "analyses", "b.qmd"),
            c = file.path(root, "graphs", "a.qmd"))
  for (j in jobs) writeLines("---\ntitle: x\n---", j)
  jobs
}

test_that("two jobs with the same output_file keep separate run files and status, in one folder or two", {
  skip_on_os("windows")
  jobs <- two_jobs_one_output()
  out <- "report.html"
  local_mocked_bindings(.launch = function(cmd) invisible(0L), .find_study_root = function(dir) dirname(dir))
  submit_job(jobs[["a"]], output_file = out)
  .write_status(.run_files(.run_key(jobs[["a"]], out))$status, state = "running", pid = Sys.getpid(),
                host = Sys.info()[["nodename"]], job = "a.qmd", output_file = out)
  expect_identical(job_status(jobs[["a"]], quiet = TRUE, output_file = out)$state, "running")
  # Neither the job beside it nor the job of the same name in another folder sees a's run.
  expect_identical(job_status(jobs[["b"]], quiet = TRUE, output_file = out)$state, "none")
  expect_identical(job_status(jobs[["c"]], quiet = TRUE, output_file = out)$state, "none")
  expect_no_error(submit_job(jobs[["b"]], output_file = out))
  expect_no_error(submit_job(jobs[["c"]], output_file = out))
  sb <- yaml::read_yaml(.run_files(.run_key(jobs[["b"]], out))$status)
  expect_identical(c(sb$job, sb$output_file, sb$state), c("b.qmd", out, "submitted"))
  expect_identical(yaml::read_yaml(.run_files(.run_key(jobs[["a"]], out))$status)$state, "running")
  files <- basename(list.files(dirname(jobs[["a"]]), pattern = "[.]run[.]yml$"))
  expect_setequal(files, c("a@report.html.run.yml", "b@report.html.run.yml"))
  expect_identical(basename(list.files(dirname(jobs[["c"]]), pattern = "[.]run[.]yml$")), "a@report.html.run.yml")
})

test_that("cancelling one job's output never signals another job's run of the same output", {
  skip_on_os("windows")
  jobs <- two_jobs_one_output()
  out <- "report.html"
  for (j in jobs[c("a", "c")]) {
    .write_status(.run_files(.run_key(j, out))$status, state = "running", pid = Sys.getpid(), created = "1",
                  host = Sys.info()[["nodename"]], job = basename(j), output_file = out)
  }
  signalled <- FALSE
  local_mocked_bindings(.stop_procs = function(...) {
    signalled <<- TRUE
    character()
  })
  # b has no run of its own: a's, beside it, and c's, in another folder, are not b's to cancel.
  expect_identical(cancel_job(jobs[["b"]], grace = 0, quiet = TRUE, output_file = out)$state, "none")
  expect_false(signalled)
  for (j in jobs[c("a", "c")]) expect_identical(yaml::read_yaml(.run_files(.run_key(j, out))$status)$state, "running")
})

test_that("a run whose record names another job is neither reported nor cancelled", {
  skip_on_os("windows")
  jobs <- two_jobs_one_output()
  out <- "report.html"
  # b's run files holding a record that names a: a stray copy, or a record written before runs were keyed on the job.
  key <- .run_key(jobs[["b"]], out)
  .write_status(.run_files(key)$status, state = "running", pid = Sys.getpid(), created = "1",
                host = Sys.info()[["nodename"]], job = "a.qmd", output_file = out)
  expect_error(job_status(jobs[["b"]], quiet = TRUE, output_file = out), "record job a.qmd, not b.qmd", fixed = TRUE)
  signalled <- FALSE
  local_mocked_bindings(.stop_procs = function(...) {
    signalled <<- TRUE
    character()
  })
  expect_error(cancel_job(jobs[["b"]], grace = 0, quiet = TRUE, output_file = out), "nothing was signalled")
  expect_false(signalled)
  expect_identical(yaml::read_yaml(.run_files(key)$status)$state, "running")
  # The job's own run, with no output_file, never consults the recorded job, and reads as it always has.
  expect_identical(job_status(jobs[["b"]], quiet = TRUE)$state, "none")
})
