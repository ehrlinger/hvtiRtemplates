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

test_that("outside a knit nothing is recorded and the factory returns NULL", {
  file <- file.path(withr::local_tempdir(), "x.run.progress")
  p <- .progress_install(file)
  expect_null(p("iteration"))
  expect_false(file.exists(file))
  expect_null(.progress_install(NULL)("iteration"))
})
