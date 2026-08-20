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

test_that("new_job errors when the copy fails rather than returning a dead path", {
  # `file.copy()` reports failure by returning FALSE, not by erroring, so an
  # unchecked call hands back a path to a file that was never written. Provoke
  # a real failure by making the target directory read-only.
  skip_on_os("windows")            # POSIX mode bits do not govern writability
  skip_if(unname(Sys.info()["user"]) == "root")  # root ignores the mode bits

  dir <- tempfile("newjob-")
  dir.create(dir, recursive = TRUE)
  on.exit({
    Sys.chmod(dir, "700")
    unlink(dir, recursive = TRUE)
  }, add = TRUE)

  Sys.chmod(dir, "500")
  skip_if(file.access(dir, mode = 2) == 0, "directory is still writable")

  # `file.copy()` also warns ("cannot create file ... Permission denied") on its
  # way to returning FALSE. That warning is useful in real use; here it would
  # just leave the suite with a WARN, so only the error is under test.
  expect_error(suppressWarnings(new_job("ac", "dead_ro", dir = dir)),
               "failed to write")
})
