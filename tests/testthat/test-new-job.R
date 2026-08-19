test_that("template_list reports the ac job template", {
  tl <- template_list()
  expect_true("ac" %in% tl$prefix)
})

test_that("every template is free of study identifiers", {
  for (nm in template_list()$name) {
    txt <- readLines(template_path(nm), warn = FALSE)
    expect_false(
      any(grepl("/studies/|preserve_root|lv_function|built[.]sas7bdat", txt)),
      label = paste("template", nm, "carries a study identifier")
    )
  }
})

test_that("new_job writes a file and returns its path", {
  dir <- tempfile("newjob-")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  out <- new_job("ac", "dead_pa", dir = dir)
  expect_true(file.exists(out))
  expect_match(out, "ac[.]dead_pa[.]qmd$")
})

test_that("new_job refuses an unknown prefix, naming the valid ones", {
  dir <- tempfile("newjob-")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  expect_error(new_job("zz", "x", dir = dir), "ac")
})

test_that("new_job refuses to overwrite an existing job", {
  dir <- tempfile("newjob-")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  new_job("ac", "dead", dir = dir)
  expect_error(new_job("ac", "dead", dir = dir), "already exists")
})
