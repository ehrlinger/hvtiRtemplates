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

test_that("open_job reports an invalid field under its own name, not add_job()'s", {
  # .check_field() hardcoded "add_job():" in its message; open_job() calls it
  # too, so a bad endpoint blamed the wrong function. The .select_template()
  # error two lines above IS relabelled "open_job():" -- this closes the gap.
  root <- new_study("openjob-badfield-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)

  expect_error(open_job("ac", "a-b", "eda", dir = root), "^open_job\\(\\): `endpoint`")
  expect_false(file.exists(file.path(root, "20_distributions", "a-b-eda-ac.qmd")))
})

test_that("open_job returns exactly the path add_job would write, qualified and not", {
  for (spec in list(
    list(prefix = "ac", qualifier = NULL, pattern = "-ac.qmd"),
    list(prefix = "dc", qualifier = "tables", pattern = "-dc-tables.qmd")
  )) {
    root <- tempfile("openjob-samepath-")
    on.exit(unlink(root, recursive = TRUE), add = TRUE)
    suppressMessages(hvtiRutilities::study_setup(
      root, study = "Same path test", study_tracker_id = 1L
    ))
    root <- normalizePath(root)

    out <- open_job(spec$prefix, "dead", "eda", qualifier = spec$qualifier, dir = root)
    expect_true(file.exists(out), label = spec$prefix)
    expect_true(grepl(spec$pattern, basename(out), fixed = TRUE), label = spec$prefix)

    expect_error(
      add_job(spec$prefix, "dead", "eda", qualifier = spec$qualifier, dir = root),
      "already exists",
      label = spec$prefix
    )
  }
})
