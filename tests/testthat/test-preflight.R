test_that("r_version refuses a session R whose major.minor differs from the lock's (failure 1)", {
  root <- lock_study(r = "4.5.3")
  testthat::local_mocked_bindings(.session_r = function() numeric_version("4.6.1"))
  ck <- .check_r_version(root)
  expect_false(ck$ok)
  expect_match(ck$message, "^r_version: .*4[.]5[.]3.*4[.]6[.]1")
  expect_match(ck$fix, "hvti run", fixed = TRUE)
  expect_match(ck$fix, "/opt/R/4.5.3/bin/R", fixed = TRUE)
})

test_that("r_version passes a patch difference with a note", {
  root <- lock_study(r = "4.5.1")
  testthat::local_mocked_bindings(.session_r = function() numeric_version("4.5.3"))
  ck <- .check_r_version(root)
  expect_true(ck$ok)
  expect_match(ck$note, "4.5.1", fixed = TRUE)
})

test_that("r_version passes a study with no lock", {
  root <- withr::local_tempdir()
  expect_true(.check_r_version(root)$ok)
})

test_that("packages refuses a needed package missing from the lock (failure 3)", {
  root <- lock_study(pkgs = list(knitr = "1.48"))
  job <- file.path(root, "analyses", "x.qmd")
  writeLines(c("```{r}", "#| label: setup", "library(knitr)", "```"), job)
  testthat::local_mocked_bindings(.installed_version = function(p) "1.4.4")
  ck <- .check_packages(job, root)
  expect_false(ck$ok)
  expect_match(ck$message, "^packages: .*quarto.*not recorded in renv.lock")
  expect_match(ck$fix, "hvtiR::update()", fixed = TRUE)
})

test_that("packages refuses a locked package missing from the library", {
  root <- lock_study()
  job <- file.path(root, "analyses", "x.qmd")
  writeLines(c("```{r}", "#| label: setup", "library(knitr)", "```"), job)
  testthat::local_mocked_bindings(.installed_version = function(p) if (p == "quarto") NA_character_ else "1.48")
  ck <- .check_packages(job, root)
  expect_false(ck$ok)
  expect_match(ck$fix, 'renv::restore(packages = "quarto")', fixed = TRUE)
})

test_that("packages refuses a version that differs between library and lock", {
  root <- lock_study(pkgs = list(quarto = "1.4.4", knitr = "1.48"))
  job <- file.path(root, "analyses", "x.qmd")
  writeLines(c("```{r}", "#| label: setup", "library(knitr)", "```"), job)
  testthat::local_mocked_bindings(.installed_version = function(p) if (p == "knitr") "1.50" else "1.4.4",
                                  .always_needed = function() c("quarto", "knitr"))
  ck <- .check_packages(job, root)
  expect_false(ck$ok)
  expect_match(ck$message, "knitr 1.50 installed, 1.48 locked", fixed = TRUE)
})

test_that("drift in a package the job does not load is a note, not a refusal", {
  root <- lock_study(pkgs = list(quarto = "1.4.4", knitr = "1.48", sf = "1.0"))
  job <- file.path(root, "analyses", "x.qmd")
  writeLines(c("```{r}", "#| label: setup", "library(knitr)", "```"), job)
  installed <- function(p) if (p == "sf") "1.1" else c(quarto = "1.4.4", knitr = "1.48")[[p]]
  testthat::local_mocked_bindings(.installed_version = installed, .always_needed = function() c("quarto", "knitr"))
  ck <- .check_packages(job, root)
  expect_true(ck$ok)
  expect_match(ck$note, "sf", fixed = TRUE)
})

job_with_setup <- function(root) {
  job <- file.path(root, "analyses", "x.qmd")
  writeLines(c("```{r}", "#| label: setup", "library(knitr)", "```"), job)
  job
}

test_that("a dashed locked version matches the dotted installed one", {
  root <- lock_study(pkgs = list(quarto = "1.4.4", knitr = "1.48", survival = "3.5-8"))
  job <- job_with_setup(root)
  testthat::local_mocked_bindings(
    .installed_version = function(p) c(quarto = "1.4.4", knitr = "1.48", survival = "3.5.8")[[p]],
    .always_needed = function() c("quarto", "knitr", "survival")
  )
  ck <- .check_packages(job, root)
  expect_true(ck$ok)
  expect_null(ck$note)
})

test_that("a lock entry with no Version is unrecorded, not a crash", {
  root <- lock_study(pkgs = list(quarto = "1.4.4", knitr = "1.48"))
  lock <- jsonlite::read_json(file.path(root, "renv.lock"))
  lock$Packages$gh <- list(Package = "gh", Source = "GitHub")
  jsonlite::write_json(lock, file.path(root, "renv.lock"), auto_unbox = TRUE)
  job <- job_with_setup(root)
  testthat::local_mocked_bindings(
    .installed_version = function(p) c(quarto = "1.4.4", knitr = "1.48", gh = "1.0")[[p]],
    .always_needed = function() c("quarto", "knitr", "gh")
  )
  ck <- .check_packages(job, root)
  expect_false(ck$ok)
  expect_match(ck$message, "gh 1.0 is installed but not recorded", fixed = TRUE)
})

test_that("r_version treats an unparseable lock version as absent, with a note", {
  for (bad in c("", "devel", "4")) {
    root <- lock_study(r = bad)
    testthat::local_mocked_bindings(.session_r = function() numeric_version("4.5.3"))
    ck <- .check_r_version(root)
    expect_true(ck$ok)
    expect_match(ck$note, "could not be read", fixed = TRUE)
  }
})

test_that("packages notes when the job's own packages could not be read", {
  root <- lock_study()
  job <- file.path(root, "analyses", "x.qmd")
  writeLines("no setup chunk here", job)
  testthat::local_mocked_bindings(.installed_version = function(p) c(quarto = "1.4.4", knitr = "1.48")[[p]],
                                  .always_needed = function() c("quarto", "knitr"))
  ck <- .check_packages(job, root)
  expect_true(ck$ok)
  expect_match(ck$note, "could not be read", fixed = TRUE)
})

test_that("packages: neither installed nor recorded", {
  root <- lock_study(pkgs = list(knitr = "1.48"))
  job <- job_with_setup(root)
  testthat::local_mocked_bindings(.installed_version = function(p) if (p == "quarto") NA_character_ else "1.48",
                                  .always_needed = function() c("quarto", "knitr"))
  ck <- .check_packages(job, root)
  expect_false(ck$ok)
  expect_match(ck$message, "quarto is neither installed nor recorded", fixed = TRUE)
  expect_match(ck$fix, "hvtiR::update()", fixed = TRUE)
})

test_that("packages: installed newer than locked updates, older restores", {
  root <- lock_study(pkgs = list(quarto = "1.4.4", knitr = "1.48"))
  job <- job_with_setup(root)
  testthat::local_mocked_bindings(.installed_version = function(p) if (p == "knitr") "1.50" else "1.4.4",
                                  .always_needed = function() c("quarto", "knitr"))
  expect_match(.check_packages(job, root)$fix, "hvtiR::update()", fixed = TRUE)
  testthat::local_mocked_bindings(.installed_version = function(p) if (p == "knitr") "1.40" else "1.4.4")
  expect_match(.check_packages(job, root)$fix, 'renv::restore(packages = "knitr")', fixed = TRUE)
})

test_that("render_r refuses a render on an R other than the submitter's (failure 2)", {
  testthat::local_mocked_bindings(.r_home = function() "/usr/lib/R/bin")
  ck <- .check_render_r(expected = "/opt/R/4.5.3/lib/R/bin")
  expect_false(ck$ok)
  expect_match(ck$message, "^render_r: .*/usr/lib/R/bin.*/opt/R/4.5.3")
  expect_match(ck$fix, "QUARTO_R", fixed = TRUE)
})

test_that("render_r is skipped when nothing was submitted", {
  expect_true(.check_render_r(expected = "")$ok)
})

test_that(".job_setup() stops a render whose R is not the submitter's, and passes the same R", {
  setup_fixture()
  withr::local_envvar(HVTI_RUN_R = "/no/such/R/bin")
  expect_error(run_setup(), "render_r: .*/no/such/R/bin.*QUARTO_R")
  withr::local_envvar(HVTI_RUN_R = R.home("bin"))
  expect_no_error(run_setup())
})
