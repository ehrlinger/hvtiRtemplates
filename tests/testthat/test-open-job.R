new_study <- function(pattern) {
  root <- tempfile(pattern)
  suppressMessages(hvtiRutilities::study_setup(root, study = "Open job test", study_tracker_id = 1L))
  normalizePath(root, winslash = "/", mustWork = FALSE)
}

test_that("open_job creates a missing job under the study root found from a subdirectory", {
  root <- new_study("openjob-new-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)

  out <- open_job(prefix = "ac", subject = "dead", type = "eda", dir = file.path(root, "20_distributions"))

  expect_identical(
    normalizePath(out, winslash = "/", mustWork = FALSE),
    normalizePath(file.path(root, "20_distributions", "dead-eda-ac.qmd"), winslash = "/", mustWork = FALSE)
  )
  expect_true(file.exists(out))
})

test_that("open_job opens an existing job without changing it", {
  root <- new_study("openjob-existing-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  first <- open_job(prefix = "ac", subject = "dead", type = "eda", dir = root)
  writeLines("worked on", first)

  expect_message(again <- open_job(prefix = "ac", subject = "dead", type = "eda", dir = root), "already exists")

  expect_identical(
    normalizePath(again, winslash = "/", mustWork = FALSE),
    normalizePath(first, winslash = "/", mustWork = FALSE)
  )
  expect_identical(readLines(first), "worked on")
})

test_that("open_job refuses an ambiguous prefix", {
  root <- new_study("openjob-ambiguous-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  expect_error(open_job(prefix = "dc", subject = "dead", type = "eda", dir = root), "open_job\\(\\):")
})

test_that("open_job outside a study names study_setup", {
  dir <- tempfile("openjob-nostudy-")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  expect_error(open_job(prefix = "ac", subject = "dead", type = "eda", dir = dir), "_study.yml")
})

test_that("open_job reports an invalid field under its own name, not add_job()'s", {
  # .check_field() hardcoded "add_job():" in its message; open_job() calls it
  # too, so a bad subject blamed the wrong function. The .select_template()
  # error two lines above IS relabelled "open_job():" -- this closes the gap.
  root <- new_study("openjob-badfield-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)

  expect_error(open_job(prefix = "ac", subject = "a-b", type = "eda", dir = root), "^open_job\\(\\): `subject`")
  expect_false(file.exists(file.path(root, "20_distributions", "a-b-eda-ac.qmd")))
})

test_that("open_job's positional argument order matches add_job's", {
  # add_job()'s fourth positional argument is dir, with qualifier fifth and
  # named-only in practice; open_job() must accept dir in that same slot, or
  # a caller moving from an add_job() call to open_job() with the same
  # positional arguments gets an error that misreads dir as qualifier.
  root <- new_study("openjob-positional-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)

  out <- open_job("ac", "demo", "eda", root)

  expect_identical(
    normalizePath(out, winslash = "/", mustWork = FALSE),
    normalizePath(file.path(root, "20_distributions", "demo-eda-ac.qmd"), winslash = "/", mustWork = FALSE)
  )
  expect_true(file.exists(out))
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

    out <- open_job(prefix = spec$prefix, subject = "dead", type = "eda", qualifier = spec$qualifier, dir = root)
    expect_true(file.exists(out), label = spec$prefix)
    expect_true(grepl(spec$pattern, basename(out), fixed = TRUE), label = spec$prefix)

    expect_error(
      add_job(prefix = spec$prefix, subject = "dead", type = "eda", qualifier = spec$qualifier, dir = root),
      "already exists",
      label = spec$prefix
    )
  }
})
