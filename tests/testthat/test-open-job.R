new_study <- function(pattern) {
  root <- tempfile(pattern)
  suppressMessages(hvtiRutilities::study_setup(root, study = "Open job test", study_tracker_id = 1L))
  normalizePath(root)
}

test_that("open_job creates a missing job under the study root found from a subdirectory", {
  root <- new_study("openjob-new-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)

  out <- open_job("ac", "dead", "eda", dir = file.path(root, "20_distributions"))

  expect_identical(out, file.path(root, "20_distributions", "dead-eda-ac.qmd"))
  expect_true(file.exists(out))
})

test_that("open_job opens an existing job without changing it", {
  root <- new_study("openjob-existing-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  first <- open_job("ac", "dead", "eda", dir = root)
  writeLines("worked on", first)

  expect_message(again <- open_job("ac", "dead", "eda", dir = root), "already exists")

  expect_identical(again, first)
  expect_identical(readLines(first), "worked on")
})

test_that("open_job refuses an ambiguous prefix", {
  root <- new_study("openjob-ambiguous-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  expect_error(open_job("dc", "dead", "eda", dir = root), "open_job\\(\\):")
})

test_that("open_job outside a study names study_setup", {
  dir <- tempfile("openjob-nostudy-")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  expect_error(open_job("ac", "dead", "eda", dir = dir), "_study.yml")
})
