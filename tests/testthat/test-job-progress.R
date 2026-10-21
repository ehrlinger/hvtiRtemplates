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

test_that("time spent before the first step does not inflate the estimate", {
  withr::local_options(hvtiRtemplates.progress_every = 1)
  clock <- local_clock()
  file <- progress_file()
  quietly(.progress_begin(file, "fit"))
  quietly(.progress_stage("fit", TRUE))
  f <- .progress_step("iteration")
  clock$now <- clock$now + 3600  # a long preamble in the stage, before the loop
  quietly(f(1L, 100L))
  clock$now <- clock$now + 60
  line <- quietly(f(2L, 100L))
  expect_match(line, "iteration 2/100  1h01m in stage  ~1h38m left in stage", fixed = TRUE)
  view <- .progress_view(yaml::read_yaml(file), now = clock$now)
  expect_equal(view$eta_s, 98 * 60)
  # A new loop (the counter goes back) starts the estimate again.
  clock$now <- clock$now + 600
  quietly(f(1L, 50L))
  clock$now <- clock$now + 30
  quietly(f(2L, 50L))
  expect_equal(.progress_view(yaml::read_yaml(file), now = clock$now)$eta_s, 48 * 30)
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

test_that("a bad progress_every falls back to 10 minutes and says so once", {
  withr::local_options(hvtiRtemplates.progress_every = 0)
  rm(list = ls(.progress_state, all.names = TRUE), envir = .progress_state)
  first <- utils::capture.output(val <- .progress_every(), type = "message")
  expect_equal(val, 10)
  expect_match(paste(first, collapse = "\n"), "hvtiRtemplates.progress_every")
  second <- utils::capture.output(val2 <- .progress_every(), type = "message")
  expect_equal(val2, 10)
  expect_length(second, 0)
})

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

test_that("stages are the current document's chunks, not labels a child left in knitr's registry", {
  dir <- withr::local_tempdir()
  # knitr keeps one registry of chunk labels for the session. A child knitted outside any render, as the
  # template tests do, leaves its label there, and the next render's labels are added after it.
  withr::local_options(knitr.duplicate.label = "allow")
  withr::local_dir(dir)
  quietly(knitr::knit_child(text = c("```{r}", "#| label: tbl-stray", "1", "```"), quiet = TRUE))
  rmd <- file.path(dir, "x.Rmd")
  file <- file.path(dir, "x.run.progress")
  writeLines(c("```{r setup}",
               sprintf("p <- hvtiRtemplates:::.progress_install(%s)", deparse(file)),
               "```",
               "```{r first}",
               "1",
               "```",
               "```{r second}",
               "1",
               "```"), rmd)
  withr::defer(knitr::knit_hooks$delete("hvti_progress"))
  quietly(knitr::knit(rmd, file.path(dir, "x.md"), quiet = TRUE))
  expect_identical(yaml::read_yaml(file)$stages, c("first", "second"))
})

test_that("outside a knit nothing is recorded and the factory returns NULL", {
  file <- file.path(withr::local_tempdir(), "x.run.progress")
  p <- .progress_install(file)
  expect_null(p("iteration"))
  expect_false(file.exists(file))
  expect_null(.progress_install(NULL)("iteration"))
})

# A progress file as a render in its fit stage would leave it, `age` minutes ago.
write_progress <- function(job, age = 2, done_all = FALSE, pid = Sys.getpid()) {
  now <- .now()
  stages <- c("tbl-data", "fit", "effects")
  done <- if (done_all) {
    lapply(stages, function(s) list(stage = s, elapsed_s = 600L))
  } else {
    list(list(stage = "tbl-data", elapsed_s = 41L))
  }
  .write_status(.run_files(job)$progress, pid = pid, host = Sys.info()[["nodename"]],
                started = .stamp(now - 3600), updated = .stamp(now - age * 60),
                stage = if (done_all) "effects" else "fit", stage_index = if (done_all) 3L else 2L, stage_count = 3L,
                stage_started = .stamp(now - 3000), step = 412L, steps = 1000L, unit = "iteration",
                step_started = .stamp(now - 2900), step_base = 12L, stages = stages,
                done = done)
}

status_job_progress <- function() {
  job <- file.path(withr::local_tempdir(.local_envir = parent.frame()), "nb.boostmtree.x.boost.qmd")
  writeLines("---\ntitle: x\n---", job)
  job
}

test_that("a failed or vanished job says where it stopped", {
  local_clock(Sys.time())
  job <- status_job_progress()
  write_progress(job)
  .write_status(.run_files(job)$status, state = "failed", exit_code = 1L, pid = 999999L, started = .stamp(.now() - 4000))
  out <- utils::capture.output(job_status(job))
  expect_match(out, "  stopped in fit (2 of 3)", fixed = TRUE, all = FALSE)
  expect_match(out, "stage times:", fixed = TRUE, all = FALSE)
  write_progress(job, done_all = TRUE, pid = 999999L)
  .write_status(.run_files(job)$status, state = "finished", started = .stamp(.now() - 4000), ended = .stamp(.now() - 60))
  expect_false(any(grepl("stopped in", utils::capture.output(job_status(job)), fixed = TRUE)))
})

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

# A progress file that parses, but whose fields are not what the writer would have left.
set_field <- function(field, value) {
  function(p) {
    p[field] <- list(value)
    p
  }
}

malformed_progress <- list(
  "done is a number"       = set_field("done", 5L),
  "done is a vector"       = set_field("done", c("a", "b")),
  "done without a stage"   = set_field("done", list(list(elapsed_s = 3L))),
  "step is text"           = set_field("step", "abc"),
  "step without steps"     = set_field("steps", NULL),
  "elapsed_s is text"      = set_field("done", list(list(stage = "tbl-data", elapsed_s = "foo"))),
  "updated is no stamp"    = set_field("updated", "yesterday"),
  "stage_started no stamp" = set_field("stage_started", "soon"),
  "step_started no stamp"  = set_field("step_started", "soon"),
  "step_base is text"      = set_field("step_base", "abc")
)

test_that("a malformed progress file is noted, never an error, and the state still comes from run.yml", {
  local_clock(Sys.time())
  for (case in names(malformed_progress)) {
    job <- status_job_progress()
    write_progress(job)
    file <- .run_files(job)$progress
    writeLines(yaml::as.yaml(malformed_progress[[case]](yaml::read_yaml(file))), file)
    .write_status(.run_files(job)$status, state = "failed", exit_code = 1L, pid = 999999L)
    out <- NULL
    expect_no_error(out <- utils::capture.output(st <- job_status(job)), message = case)
    expect_identical(st$state, "failed", label = case)
    expect_match(paste(out, collapse = "\n"), "cannot read", fixed = TRUE, label = case)
    unlink(.run_files(job)$status)
    expect_no_error(out <- utils::capture.output(st <- job_status(job)), message = case)
    expect_identical(st$state, "none", label = case)
    expect_match(paste(out, collapse = "\n"), "cannot read", fixed = TRUE, label = case)
  }
})

test_that("the progress path of a Quarto intermediate is the job's, beside it", {
  job <- file.path("studies", "analyses", "nb.boostmtree.x.boost.qmd")
  expect_identical(.progress_path(file.path("studies", "analyses", "nb.boostmtree.x.boost.rmarkdown")),
                   .run_files(job)$progress)
  expect_identical(.progress_path(job), .run_files(job)$progress)
  expect_null(.progress_path(NULL))
})

test_that("a Quarto render leaves <job>.run.progress, which job_status() reads", {
  skip_on_cran()
  skip_if_not_installed("quarto")
  skip_if(!nzchar(Sys.which("quarto")))
  dir <- withr::local_tempdir()
  job <- file.path(dir, "nb.boostmtree.x.boost.qmd")
  writeLines(c("---", "title: x", "format: html", "---", "",
               "```{r}", "#| label: setup",
               "hvtiRtemplates:::.progress_install(hvtiRtemplates:::.progress_path(knitr::current_input(dir = TRUE)))",
               "```", "",
               "```{r}", "#| label: first", "1 + 1", "```", "",
               "```{r}", "#| label: second", "2 + 2", "```"), job)
  quarto::quarto_render(job, execute_dir = dir, quiet = TRUE)
  expect_true(file.exists(file.path(dir, "nb.boostmtree.x.boost.run.progress")))
  expect_length(list.files(dir, pattern = "rmarkdown[.]run[.]progress$"), 0L)
  st <- job_status(job, quiet = TRUE)
  expect_identical(st$progress$stages, c("first", "second"))
  expect_identical(st$state, "finished")
})

test_that("a progress file from before the recorded run is ignored, whatever state that run is in", {
  local_clock(Sys.time())
  for (state in c("submitted", "running", "finished", "failed")) {
    job <- status_job_progress()
    write_progress(job)  # began an hour ago
    .write_status(.run_files(job)$status, state = state, pid = Sys.getpid(), host = Sys.info()[["nodename"]],
                  submitted = .stamp(.now() - 10), started = .stamp(.now() - 10), ended = .stamp(.now() - 5),
                  exit_code = 0L, elapsed_s = 5L)
    st <- job_status(job, quiet = TRUE)
    expect_identical(st$state, state, label = state)
    expect_null(st$progress, label = state)
  }
})

test_that("a progress file from after the recorded run ended gives the state, as with no run.yml", {
  local_clock(Sys.time())
  job <- status_job_progress()
  write_progress(job)
  .write_status(.run_files(job)$status, state = "finished", pid = 999999L, host = Sys.info()[["nodename"]],
                started = .stamp(.now() - 7300), ended = .stamp(.now() - 7200), exit_code = 0L, elapsed_s = 100L)
  st <- job_status(job, quiet = TRUE)
  expect_identical(st$state, "running")
  expect_identical(st$progress$stage, "fit")
})

test_that("a progress file inside the recorded run is kept", {
  local_clock(Sys.time())
  job <- status_job_progress()
  write_progress(job)
  .write_status(.run_files(job)$status, state = "running", pid = Sys.getpid(), host = Sys.info()[["nodename"]],
                started = .stamp(.now() - 3700))
  expect_identical(job_status(job, quiet = TRUE)$progress$stage, "fit")
})
