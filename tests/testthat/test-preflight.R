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
  testthat::local_mocked_bindings(.installed_version = function(p) if (p == "sf") "1.1" else
                                    c(quarto = "1.4.4", knitr = "1.48")[[p]],
                                  .always_needed = function() c("quarto", "knitr"))
  ck <- .check_packages(job, root)
  expect_true(ck$ok)
  expect_match(ck$note, "sf", fixed = TRUE)
})
