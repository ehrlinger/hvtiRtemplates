hvti <- function() system.file("bin", "hvti", package = "hvtiRtemplates")

fake_r <- function(ver) {
  top <- withr::local_tempdir(.local_envir = parent.frame())
  bin <- file.path(top, ver, "bin")
  dir.create(bin, recursive = TRUE)
  log <- file.path(top, "args.txt")
  # printf, not echo: sh's echo interprets backslashes, which would corrupt the path being checked.
  writeLines(c("#!/bin/sh", sprintf('printf "%%s\\n" "$PWD" > %s; for a in "$@"; do printf "%%s\\n" "$a" >> %s; done', log, log)),
             file.path(bin, "Rscript"))
  Sys.chmod(file.path(bin, "Rscript"), "755")
  list(top = top, log = log)
}

test_that("hvti run starts the lock's R from the study root, passing the path as data (failures 1 and 8)", {
  skip_on_os("windows")
  root <- lock_study(r = "4.5.3")
  odd <- file.path(root, "analyses", "we\"ird\\dir")   # a quote and a backslash in a directory name
  dir.create(odd)
  job <- file.path(odd, "x.qmd")
  writeLines("x", job)
  r <- fake_r("4.5.3")
  out <- system2(hvti(), c("run", shQuote(job), "--final"), env = paste0("HVTI_R_ROOT=", r$top), stdout = TRUE, stderr = TRUE)
  got <- readLines(r$log)
  expect_identical(normalizePath(got[1]), normalizePath(root))
  expect_identical(got[2], "-e")
  expect_identical(got[3], "quit(status = hvtiRtemplates:::.hvti_main(commandArgs(TRUE)))")
  expect_identical(got[c(4, 6)], c("run", "TRUE"))
  expect_identical(normalizePath(got[5]), normalizePath(job))   # pwd may keep a symlinked tempdir logical
})

test_that("the hvti script keeps its executable bit in the installed package", {
  skip_on_os("windows")
  expect_true(nzchar(hvti()))
  expect_true(file.access(hvti(), 1L) == 0L)
})

test_that(".hvti_main exits nonzero when the launch fails or is refused, zero when it runs (C11)", {
  testthat::local_mocked_bindings(run_job = function(path, final) invisible(list(state = "failed")))
  expect_identical(.hvti_main(c("run", "x.qmd", "FALSE")), 1L)
  testthat::local_mocked_bindings(run_job = function(path, final) stop("run_job(): refused; fix the checks"))
  expect_identical(suppressMessages(.hvti_main(c("run", "x.qmd", "FALSE"))), 1L)
  testthat::local_mocked_bindings(run_job = function(path, final) invisible(list(state = "running")))
  expect_identical(.hvti_main(c("run", "x.qmd", "FALSE")), 0L)
})

test_that(".hvti_main passes the path through unchanged, quotes and backslashes included", {
  seen <- NULL
  testthat::local_mocked_bindings(run_job = function(path, final) {
    seen <<- list(path, final)
    list(state = "running")
  })
  .hvti_main(c("run", "/s/we\"ird\\dir/x.qmd", "TRUE"))
  expect_identical(seen, list("/s/we\"ird\\dir/x.qmd", TRUE))
})

test_that(".hvti_main routes status and cancel with the path, and exits 1 on their errors", {
  seen <- NULL
  fake_status <- function(path, quiet = FALSE) {
    seen <<- c("status", path)
    list(state = "running")
  }
  fake_cancel <- function(path, ...) {
    seen <<- c("cancel", path)
    list(state = "cancelled")
  }
  testthat::local_mocked_bindings(job_status = fake_status, cancel_job = fake_cancel)
  expect_identical(.hvti_main(c("status", "a.qmd", "FALSE")), 0L)
  expect_identical(seen, c("status", "a.qmd"))
  expect_identical(.hvti_main(c("cancel", "b.qmd", "FALSE")), 0L)
  expect_identical(seen, c("cancel", "b.qmd"))
  testthat::local_mocked_bindings(cancel_job = function(path, ...) stop("cancel_job(): refused"))
  expect_identical(suppressMessages(.hvti_main(c("cancel", "b.qmd", "FALSE"))), 1L)
})

test_that("hvti refuses, naming the version, when the lock's R is not installed", {
  skip_on_os("windows")
  root <- lock_study(r = "9.9.9")   # a version no /opt/R on any host holds
  job <- file.path(root, "analyses", "x.qmd")
  writeLines("x", job)
  r <- fake_r("4.6.1")
  out <- suppressWarnings(system2(hvti(), c("run", job), env = paste0("HVTI_R_ROOT=", r$top), stdout = TRUE, stderr = TRUE))
  expect_match(paste(out, collapse = "\n"), "R 9.9.9")
  expect_false(is.null(attr(out, "status")))
})

test_that("hvti refuses a job outside any study", {
  skip_on_os("windows")
  d <- withr::local_tempdir()
  job <- file.path(d, "x.qmd")
  writeLines("x", job)
  out <- suppressWarnings(system2(hvti(), c("run", job), stdout = TRUE, stderr = TRUE))
  expect_match(paste(out, collapse = "\n"), "renv.lock")
})

test_that("install_hvti copies the script, not a symlink", {
  skip_on_os("windows")
  d <- withr::local_tempdir()
  p <- suppressMessages(install_hvti(d))
  expect_false(nzchar(Sys.readlink(p)))
  expect_true(file.access(p, 1L) == 0L)
})

test_that("run_job warns once per session when the installed hvti is older than the package's", {
  skip_on_os("windows")
  d <- withr::local_tempdir()
  old <- file.path(d, "hvti")
  writeLines(c("#!/bin/sh", "# hvti: x. hvti-version: 0"), old)
  testthat::local_mocked_bindings(.hvti_on_path = function() old)
  .hvti_state$warned <- FALSE
  expect_warning(.warn_stale_hvti(), "install_hvti")
  expect_no_warning(.warn_stale_hvti())
})

test_that("run_job does not warn when the installed hvti is current or absent", {
  skip_on_os("windows")
  d <- withr::local_tempdir()
  cur <- file.path(d, "hvti")
  file.copy(hvti(), cur)
  .hvti_state$warned <- FALSE
  testthat::local_mocked_bindings(.hvti_on_path = function() cur)
  expect_no_warning(.warn_stale_hvti())
  testthat::local_mocked_bindings(.hvti_on_path = function() "")
  expect_no_warning(.warn_stale_hvti())
})

test_that("hvti rejects an unknown subcommand with the usage, before looking for a study", {
  skip_on_os("windows")
  d <- withr::local_tempdir()
  out <- suppressWarnings(system2(hvti(), c("foo", file.path(d, "x.qmd")), stdout = TRUE, stderr = TRUE))
  expect_match(paste(out, collapse = "\n"), "usage: hvti", fixed = TRUE)
  expect_identical(attr(out, "status"), 2L)
})

test_that("install_hvti has no default directory, so it never writes into the home filespace unasked", {
  expect_identical(formals(install_hvti)$dir, quote(expr = ))
})

test_that("the stale-copy warning names the directory the copy is in", {
  skip_on_os("windows")
  d <- withr::local_tempdir()
  old <- file.path(d, "hvti")
  writeLines(c("#!/bin/sh", "# hvti: x. hvti-version: 0"), old)
  testthat::local_mocked_bindings(.hvti_on_path = function() old)
  .hvti_state$warned <- FALSE
  expect_warning(.warn_stale_hvti(), sprintf('install_hvti("%s")', d), fixed = TRUE)
})

test_that("hvti refuses an unknown third argument and any fourth, so a mistyped --final is not a draft", {
  skip_on_os("windows")
  root <- lock_study(r = "4.5.3")
  job <- file.path(root, "analyses", "x.qmd")
  writeLines("x", job)
  r <- fake_r("4.5.3")
  for (args in list(c("run", job, "--fianl"), c("run", job, "--final", "extra"))) {
    out <- suppressWarnings(system2(hvti(), shQuote(args), env = paste0("HVTI_R_ROOT=", r$top), stdout = TRUE, stderr = TRUE))
    expect_match(paste(out, collapse = "\n"), "usage: hvti", fixed = TRUE)
    expect_identical(attr(out, "status"), 2L)
    expect_false(file.exists(r$log))
  }
})

test_that("hvti finds a study-relative job path from a directory inside the study", {
  skip_on_os("windows")
  root <- lock_study(r = "4.5.3")
  job <- file.path(root, "analyses", "x.qmd")
  writeLines("x", job)
  r <- fake_r("4.5.3")
  withr::local_dir(file.path(root, "analyses"))
  system2(hvti(), c("status", "analyses/x.qmd"), env = paste0("HVTI_R_ROOT=", r$top), stdout = TRUE, stderr = TRUE)
  got <- readLines(r$log)
  expect_identical(got[4], "status")
  expect_identical(normalizePath(got[5]), normalizePath(job))
})
