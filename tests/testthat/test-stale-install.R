# The guard in helper-stale-install.R and setup.R: what it fingerprints, where it looks, and which
# tests it may skip.

test_that("the fingerprint changes when a function or a constant in the namespace changes", {
  base <- .fingerprint_here()[[2L]]
  local({
    testthat::local_mocked_bindings(.job_identifier_names = c(.job_identifier_names, "not_a_real_identifier"))
    expect_false(identical(.fingerprint_here()[[2L]], base))
  })
  local({
    testthat::local_mocked_bindings(.is_marker = function(marker) FALSE)
    expect_false(identical(.fingerprint_here()[[2L]], base))
  })
  # And it comes back once both are restored: what changed it was the edit, not a second reading.
  expect_identical(.fingerprint_here()[[2L]], base)
})

test_that("the fingerprint does not depend on the collation, which testthat sets and a child inherits", {
  # Under a locale-aware sort, .packageName sorted differently in C and en_US, and every render skipped.
  in_c <- withr::with_collate("C", .fingerprint_here()[[2L]])
  in_us <- suppressWarnings(withr::with_collate("en_US.UTF-8", {
    skip_if(!identical(Sys.getlocale("LC_COLLATE"), "en_US.UTF-8"), "no en_US.UTF-8 locale here")
    .fingerprint_here()[[2L]]
  }))
  expect_identical(in_c, in_us)
})

test_that("the copy is read where the render starts, so two studies can resolve different installs", {
  skip_on_cran()
  plain <- withr::local_tempdir()
  other <- withr::local_tempdir()
  # A study whose startup file puts its own library first, as a renv activation does, holding a
  # copy of its own. Dropping the user's library instead does not hide a copy in a site or
  # system library, which .libPaths() always keeps: under covr that is where the copy is.
  study_lib <- withr::local_tempdir()
  src <- withr::local_tempdir()
  writeLines(c("Package: hvtiRtemplates", "Version: 0.0.1", "Title: A Study's Own Copy",
               "Description: A study's own copy.", "License: GPL-3"), file.path(src, "DESCRIPTION"))
  writeLines("", file.path(src, "NAMESPACE"))
  dir.create(file.path(src, "R"))
  writeLines("only_in_the_study_copy <- TRUE", file.path(src, "R", "copy.R"))
  r_bin <- file.path(R.home("bin"), "R")
  installed <- system2(r_bin, c("CMD", "INSTALL", "--no-test-load", "-l", shQuote(study_lib), shQuote(src)),
                       stdout = TRUE, stderr = TRUE)
  expect_true(dir.exists(file.path(study_lib, "hvtiRtemplates")), label = paste(installed, collapse = "\n"))
  writeLines(sprintf(".libPaths(c(%s, .libPaths()))", deparse(study_lib)), file.path(other, ".Rprofile"))
  rscript <- file.path(R.home("bin"), "Rscript")
  # R CMD check sets R_PROFILE_USER to "", so no R it starts reads a directory's .Rprofile.
  withr::local_envvar(R_PROFILE_USER = NA)
  a <- .fingerprint_there(plain, rscript)
  skip_if(!length(a), "no installed hvtiRtemplates for the plain directory to find")
  b <- .fingerprint_there(other, rscript)
  # The other study loads its own copy, from its own library, wherever the plain one lives.
  expect_identical(b[[3L]], "0.0.1")
  expect_false(identical(a[[2L]], b[[2L]]))
  expect_identical(normalizePath(paste(b[-(1:3)], collapse = " ")), normalizePath(study_lib))
  # A startup file that fails is an error, not a missing copy: a check that could not run must not
  # skip every render as "not installed".
  broken <- withr::local_tempdir()
  writeLines('stop("a broken startup file")', file.path(broken, ".Rprofile"))
  expect_error(.fingerprint_there(broken, rscript), "a broken startup file")
  # And each is answered for its own directory, not from the other's cached result.
  with_fake_stale({
    .stale_install_reason(plain, rscript)
    .stale_install_reason(other, rscript)
    expect_length(.install_state$reasons, 2L)
  })
})

test_that("a submission refused before any process starts runs, whatever is installed", {
  skip_on_os("windows")
  with_fake_stale({
    job <- status_job()
    dir.create(.run_files(job)$log)
    # A skip here would read as green, so it fails instead.
    tryCatch(
      expect_error(.submit_job(job, final = FALSE, render_call = "1", root = dirname(job)), "cannot write the log file"),
      skip = function(e) testthat::fail(paste("the stale-install guard skipped a refusal test:", conditionMessage(e)))
    )
  })
})

test_that("a submission that reaches the launch skips when the copy it would run is stale", {
  skip_on_os("windows")
  with_fake_stale({
    job <- status_job()
    cond <- tryCatch(.submit_job(job, final = FALSE, render_call = "1", root = dirname(job)),
                     skip = function(e) e)
    expect_s3_class(cond, "skip")
    expect_match(conditionMessage(cond), "is not the code under test|is not installed where")
  })
})

test_that("the R checked for a Quarto render is the one Quarto finds", {
  bin <- withr::local_tempdir()
  file.create(file.path(bin, c("R", "Rscript")))
  withr::with_envvar(c(QUARTO_R = bin), expect_identical(.quarto_rscript(), file.path(bin, "Rscript")))
  withr::with_envvar(c(QUARTO_R = file.path(bin, "R")), expect_identical(.quarto_rscript(), file.path(bin, "Rscript")))
  # Not PATH's Rscript, which R CMD check replaces with a stub that refuses to run.
  withr::with_envvar(c(QUARTO_R = NA, R_HOME = R.home()),
                     expect_identical(.quarto_rscript(), file.path(R.home(), "bin", "Rscript")))
})
