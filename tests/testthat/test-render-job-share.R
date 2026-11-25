# Issue 662: on the lri share Quarto's remove of <stem>_files/execute-results failed on every attempt, and a failed render
# could cost the job its last report. These tests stand in for the share: `share_quarto()` acts as Quarto does in a
# project render, writing execute-results, reading it back and removing it, on a share that refuses to remove a real
# folder there, as lri did ("Directory not empty (os error 39)"), and unlinks a symbolic link as any file system does.

project_job <- function() {
  dir <- withr::local_tempdir(.local_envir = parent.frame())
  writeLines("project: {}", file.path(dir, "_quarto.yml"))
  job <- file.path(dir, "job.qmd")
  writeLines("x", job)
  normalizePath(job, winslash = "/")
}

share_quarto <- function(job, seen = new.env()) {
  force(seen)
  function(...) {
    seen$calls <- (seen$calls %||% 0L) + 1L
    results <- .execute_results_dir(job)
    seen$link <- c(seen$link, if (.is_symlink(results)) Sys.readlink(results) else NA_character_)
    dir.create(results, recursive = TRUE, showWarnings = FALSE)
    writeLines("{}", file.path(results, "html.json"))
    if (!.is_symlink(results)) {
      stop("Error returned by quarto CLI.\nERROR: Directory not empty (os error 39): remove '", results, "'")
    }
    unlink(results)
    writeLines("<html>new</html>", sub("[.]qmd$", ".html", job))
    invisible(NULL)
  }
}

test_that("in a project render, the share that failed every attempt renders the job once", {
  skip_if_not_installed("quarto")
  skip_on_os("windows")
  job <- project_job()
  seen <- new.env()
  local_mocked_bindings(quarto_render = share_quarto(job, seen), .package = "quarto")

  expect_silent(render_job(job))
  expect_identical(seen$calls, 1L)
  # Quarto met a link to a folder on local disk, not the share.
  expect_false(is.na(seen$link))
  expect_false(startsWith(normalizePath(seen$link, mustWork = FALSE), dirname(job)))
  expect_identical(readLines(sub("[.]qmd$", ".html", job)), "<html>new</html>")
  # Nothing is left on the share or on local disk.
  expect_false(file.exists(.execute_results_dir(job)) || .is_symlink(.execute_results_dir(job)))
  expect_false(dir.exists(dirname(.execute_results_dir(job))))
  expect_false(dir.exists(seen$link))
})

test_that("the same share outside a project gets no link, so it still meets the race", {
  # The control for the test above: the freezer step is a project render's, and so is the link.
  skip_if_not_installed("quarto")
  dir <- withr::local_tempdir()
  job <- normalizePath(file.path(dir, "job.qmd"), winslash = "/", mustWork = FALSE)
  writeLines("x", job)
  seen <- new.env()
  local_mocked_bindings(quarto_render = share_quarto(job, seen), .package = "quarto")
  local_mocked_bindings(.race_sleep = function(s) NULL)

  expect_error(suppressMessages(render_job(job)), class = "hvtiRtemplates_execute_results_stuck")
  expect_true(all(is.na(seen$link)))
})

test_that("a link this render placed is removed when Quarto stops before removing it", {
  skip_if_not_installed("quarto")
  skip_on_os("windows")
  job <- project_job()
  seen <- new.env()
  local_mocked_bindings(quarto_render = function(...) {
    seen$link <- Sys.readlink(.execute_results_dir(job))
    stop("chunk failed")
  }, .package = "quarto")

  expect_error(render_job(job), "chunk failed", fixed = TRUE)
  expect_true(nzchar(seen$link))
  expect_false(.is_symlink(.execute_results_dir(job)))
  expect_false(dir.exists(seen$link))
  expect_false(dir.exists(dirname(.execute_results_dir(job))))
})

test_that("a real execute-results folder is left alone, for the race path to settle", {
  skip_if_not_installed("quarto")
  skip_on_os("windows")
  job <- project_job()
  results <- .execute_results_dir(job)
  dir.create(results, recursive = TRUE)
  writeLines("{}", file.path(results, "html.json"))
  seen <- new.env()
  local_mocked_bindings(quarto_render = function(...) {
    seen$link <- .is_symlink(results)
    invisible(NULL)
  }, .package = "quarto")

  render_job(job)
  expect_false(seen$link)
  expect_true(file.exists(file.path(results, "html.json")))
})

test_that("a link that resolves is used as it is and left to its render", {
  skip_if_not_installed("quarto")
  skip_on_os("windows")
  job <- project_job()
  results <- .execute_results_dir(job)
  dir.create(dirname(results))
  other <- withr::local_tempdir()
  file.symlink(other, results)
  seen <- new.env()
  local_mocked_bindings(quarto_render = function(...) {
    seen$link <- Sys.readlink(results)
    invisible(NULL)
  }, .package = "quarto")

  render_job(job)
  expect_identical(seen$link, other)
  expect_identical(Sys.readlink(results), other)
  expect_true(dir.exists(other))
})

test_that("a dangling link is replaced, unless a live render holds the study's lock", {
  skip_if_not_installed("quarto")
  skip_on_os("windows")
  job <- project_job()
  results <- .execute_results_dir(job)
  dir.create(dirname(results))
  gone <- file.path(withr::local_tempdir(), "gone")
  file.symlink(gone, results)
  seen <- new.env()
  local_mocked_bindings(quarto_render = function(...) {
    seen$link <- c(seen$link, Sys.readlink(results))
    invisible(NULL)
  }, .package = "quarto")

  local_mocked_bindings(.study_render_running = function(project) TRUE)
  render_job(job)
  expect_identical(seen$link, gone)
  expect_identical(Sys.readlink(results), gone)

  local_mocked_bindings(.study_render_running = function(project) FALSE)
  render_job(job)
  expect_false(identical(seen$link[2L], gone))
  expect_false(.is_symlink(results))
})

test_that("Quarto writes the results through the link and removes only the link", {
  # The premise of the fix, against the Quarto installed here: a recursive remove of a symbolic link unlinks it and
  # leaves the folder it points to, and the freezer still gets its copy.
  skip_on_cran()
  skip_on_os("windows")
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  skip_if_not_installed("rmarkdown")
  job <- project_job()
  writeLines(c("---", "title: t", "format:", "  html:", "    embed-resources: true", "---", "",
               "```{r}", "1 + 1", "```"), job)
  # What render_job() placed, read just before it cleans up.
  seen <- new.env()
  real_drop <- .drop_local_execute_results
  local_mocked_bindings(.drop_local_execute_results = function(local) {
    seen$local <- local
    seen$link_left <- .is_symlink(local$link)
    seen$results <- list.files(local$target)
    real_drop(local)
  })

  render_job(job, quiet = TRUE)
  expect_true(file.exists(sub("[.]qmd$", ".html", job)))
  expect_false(is.null(seen$local))
  expect_false(seen$link_left)
  expect_identical(seen$results, "html.json")
  expect_length(Sys.glob(file.path(dirname(job), ".quarto", "_freeze", "job", "execute-results", "html.json")), 1L)
  expect_false(dir.exists(seen$local$target))
})

test_that("a failed render that removed the report puts the previous one back, with its time, and says so", {
  skip_if_not_installed("quarto")
  dir <- withr::local_tempdir()
  job <- file.path(dir, "job.qmd")
  writeLines("x", job)
  report <- file.path(dir, "job.html")
  writeLines("<html>old</html>", report)
  Sys.setFileTime(report, as.POSIXct("2026-01-02 03:04:05"))
  local_mocked_bindings(quarto_render = function(...) {
    unlink(report)
    stop("chunk failed")
  }, .package = "quarto")

  msgs <- testthat::capture_messages(expect_error(render_job(job), "chunk failed", fixed = TRUE))
  expect_identical(readLines(report), "<html>old</html>")
  expect_identical(format(file.mtime(report), "%Y-%m-%d %H:%M"), "2026-01-02 03:04")
  expect_match(paste(msgs, collapse = ""), "previous report was put back", fixed = TRUE)
  expect_match(paste(msgs, collapse = ""), "2026-01-02 03:04", fixed = TRUE)
})

test_that("the previous report is put back after the race gives up too, and under an output_file's name", {
  skip_if_not_installed("quarto")
  dir <- withr::local_tempdir()
  job <- file.path(dir, "job.qmd")
  writeLines("x", job)
  report <- file.path(dir, "job.M1.html")
  writeLines("<html>old</html>", report)
  local_mocked_bindings(quarto_render = function(...) {
    unlink(report)
    stop("ERROR: Directory not empty (os error 39): remove '", .execute_results_dir(normalizePath(job)), "'")
  }, .package = "quarto")
  local_mocked_bindings(.race_sleep = function(s) NULL)

  expect_error(suppressMessages(render_job(job, output_file = "job.M1.html")),
               class = "hvtiRtemplates_execute_results_stuck")
  expect_identical(readLines(report), "<html>old</html>")
})

test_that("a new report, or one the failed render left in place, is never touched", {
  skip_if_not_installed("quarto")
  dir <- withr::local_tempdir()
  job <- file.path(dir, "job.qmd")
  writeLines("x", job)
  report <- file.path(dir, "job.html")
  writeLines("<html>old</html>", report)

  local_mocked_bindings(quarto_render = function(...) writeLines("<html>new</html>", report), .package = "quarto")
  expect_silent(render_job(job))
  expect_identical(readLines(report), "<html>new</html>")

  local_mocked_bindings(quarto_render = function(...) stop("chunk failed"), .package = "quarto")
  msgs <- testthat::capture_messages(expect_error(render_job(job), "chunk failed", fixed = TRUE))
  expect_identical(readLines(report), "<html>new</html>")
  expect_length(msgs, 0L)

  # A render that succeeds and leaves no report gets no stale one put in its place.
  local_mocked_bindings(quarto_render = function(...) unlink(report), .package = "quarto")
  render_job(job)
  expect_false(file.exists(report))
})

test_that("no copy of the report is left on local disk", {
  skip_if_not_installed("quarto")
  dir <- withr::local_tempdir()
  job <- file.path(dir, "job.qmd")
  writeLines("x", job)
  writeLines("<html>old</html>", file.path(dir, "job.html"))
  before <- Sys.glob(file.path(tempdir(), "report-*"))
  local_mocked_bindings(quarto_render = function(...) stop("chunk failed"), .package = "quarto")
  expect_error(render_job(job), "chunk failed", fixed = TRUE)
  expect_setequal(Sys.glob(file.path(tempdir(), "report-*")), before)
})
