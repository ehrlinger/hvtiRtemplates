test_that("template_list reports the ac job template", {
  tl <- template_list()
  expect_true("ac" %in% tl$prefix)
})

test_that("every template is free of study identifiers", {
  tl <- template_list()
  for (i in seq_len(nrow(tl))) {
    txt <- readLines(tl$file[[i]], warn = FALSE)
    expect_false(
      any(grepl("/studies/|preserve_root|lv_function|built[.]sas7bdat", txt)),
      label = paste("template", tl$name[[i]], "carries a study identifier")
    )
  }
})

test_that("new_job writes into the taxonomy folder with all four fields", {
  dir <- tempfile("newjob-")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  out <- new_job("ac", "dead_pa", "hz", dir = dir)
  expect_true(file.exists(out))
  expect_equal(out, file.path(dir, "distributions", "dead_pa-hz-03.01-ac.qmd"))
})

test_that("new_job distinguishes two analysis types over one endpoint", {
  # This is the collision the type field exists to prevent. A death-hazard set
  # and a death-RFS set share the same Kaplan-Meier upstream, so keyed on
  # endpoint alone both would be `dead_pa-03.01-ac.qmd` -- two sets, one file.
  dir <- tempfile("newjob-")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  a <- new_job("ac", "dead_pa", "hz", dir = dir)
  b <- new_job("ac", "dead_pa", "rfs", dir = dir)
  expect_false(a == b)
  expect_true(all(file.exists(c(a, b))))
})

test_that("new_job refuses an unknown prefix, naming the valid ones", {
  dir <- tempfile("newjob-")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  expect_error(new_job("zz", "dead_pa", "hz", dir = dir), "ac")
})

test_that("new_job refuses to overwrite an existing job", {
  # A job file accumulates a study's edits; silently replacing one discards them.
  dir <- tempfile("newjob-")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  new_job("ac", "dead_pa", "hz", dir = dir)
  expect_error(new_job("ac", "dead_pa", "hz", dir = dir), "already exists")
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
  expect_error(suppressWarnings(new_job("ac", "dead_pa", "hz", dir = dir)),
               "failed to write")
})

test_that("the ac template declares its set and resolves artifact paths from it", {
  # The markers are the interface. A job still holding the template's placeholder
  # values has not been finished, and a template that computes artifact paths
  # from anything but them would need a path edited by hand -- the mistake the
  # EDIT markers exist to prevent.
  txt <- readLines(template_path("ac"), warn = FALSE)
  expect_true(any(grepl("^ENDPOINT <- ", txt)))
  expect_true(any(grepl("^TYPE\\s+<- ", txt)))
  expect_true(any(grepl("set_path <- function\\(kind, file\\)", txt)))
  expect_true(any(grepl("paste0\\(ENDPOINT, \"-\", TYPE\\)", txt)))
})
