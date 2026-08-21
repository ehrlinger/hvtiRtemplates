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

  # Certifying the paths differ is not enough: new_job() writes endpoint/type
  # into the FILENAME, and a body that still says the template's placeholder
  # values silently resolves set_path() into the OTHER set's directory. Each
  # written file's ENDPOINT/TYPE declarations must match its own name.
  for (path in c(a, b)) {
    fields <- strsplit(sub("[.]qmd$", "", basename(path)), "-", fixed = TRUE)[[1L]]
    txt <- readLines(path, warn = FALSE)
    declared_endpoint <- sub('^ENDPOINT <- "(.*)"$', "\\1", grep("^ENDPOINT <- ", txt, value = TRUE))
    declared_type     <- sub('^TYPE\\s+<- "(.*)"$', "\\1", grep("^TYPE\\s+<- ", txt, value = TRUE))
    expect_equal(declared_endpoint, fields[[1L]], label = paste("declared ENDPOINT in", path))
    expect_equal(declared_type, fields[[2L]], label = paste("declared TYPE in", path))
  }
})

test_that("new_job errors when the template lacks the ENDPOINT/TYPE marker lines", {
  # `.set_markers()` must fail loudly rather than hand back a job that looks
  # scaffolded but silently kept whatever the fake template happened to say.
  fake_template <- tempfile("fake-template-", fileext = ".qmd")
  writeLines(c("---", "title: fake", "---", "no markers here"), fake_template)
  on.exit(unlink(fake_template), add = TRUE)

  fake_tl <- data.frame(
    name = "01.01-zz", prefix = "zz", ordinal = "01.01",
    folder = "distributions", file = fake_template, stringsAsFactors = FALSE
  )
  testthat::local_mocked_bindings(template_list = function() fake_tl, .package = "hvtiRtemplates")

  dir <- tempfile("newjob-")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  expect_error(new_job("zz", "dead_pa", "hz", dir = dir), "ENDPOINT")

  # The failure is after the copy, so the defect Finding 1 exists to prevent
  # -- a job named for one set but declaring the template's placeholder set
  # -- must not survive: the partially-written file must be gone, not just
  # the error raised.
  out <- file.path(dir, "distributions", "dead_pa-hz-01.01-zz.qmd")
  expect_false(file.exists(out))
})

test_that("new_job rejects endpoint/type shapes that would break the filename", {
  # `-` is the field separator and `.` is reserved to the ordinal, so neither
  # may appear in `endpoint` or `type`; both must also be a single non-NA
  # string. Verified misbehaviour this guards against: "" collapses a field,
  # NA writes the string "NA" into the path, character(0) recycles silently,
  # a length-2 vector reaches `if()` and errors opaquely, "dead-pa" adds a
  # fifth field, and "../esc" escapes the taxonomy folder.
  dir <- tempfile("newjob-")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  expect_error(new_job("ac", "", "hz", dir = dir), "endpoint")
  expect_error(new_job("ac", "dead_pa", "", dir = dir), "type")
  expect_error(new_job("ac", NA_character_, "hz", dir = dir), "endpoint")
  expect_error(new_job("ac", character(0), "hz", dir = dir), "endpoint")
  expect_error(new_job("ac", c("a", "b"), "hz", dir = dir), "endpoint")
  expect_error(new_job("ac", "dead-pa", "hz", dir = dir), "endpoint")
  expect_error(new_job("ac", "../esc", "hz", dir = dir), "endpoint")
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

test_that("every template declares ENDPOINT/TYPE markers new_job() can substitute", {
  # The markers are the interface: new_job() hard-stops for any template
  # lacking them (see .set_markers()), so the contract has to hold for every
  # template on disk, not just `ac` -- otherwise the next template to be
  # added could silently fail to scaffold.
  tl <- template_list()
  for (i in seq_len(nrow(tl))) {
    txt <- readLines(tl$file[[i]], warn = FALSE)
    label <- paste("template", tl$name[[i]])
    expect_true(any(grepl("^ENDPOINT\\s+<- ", txt)), label = label)
    expect_true(any(grepl("^TYPE\\s+<- ", txt)), label = label)
  }
})

test_that("the ac template resolves artifact paths from its set markers", {
  # A template that computes artifact paths from anything but ENDPOINT/TYPE
  # would need a path edited by hand -- the mistake the markers exist to
  # prevent.
  txt <- readLines(template_path("ac"), warn = FALSE)
  expect_true(any(grepl("set_path <- function\\(kind, file\\)", txt)))
  expect_true(any(grepl("paste0\\(ENDPOINT, \"-\", TYPE\\)", txt)))
})
