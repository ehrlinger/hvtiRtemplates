test_that("template_list reports the ac job template", {
  tl <- template_list()
  expect_true("ac" %in% tl$prefix)
})

test_that("add_job replaces new_job in the public API", {
  exports <- getNamespaceExports("hvtiRtemplates")
  expect_true("add_job" %in% exports)
  expect_false("new_job" %in% exports)
})

test_that("job APIs name the grouping field subject", {
  expect_true("subject" %in% names(formals(add_job)))
  expect_true("subject" %in% names(formals(open_job)))
  expect_true("subject" %in% names(formals(migrate_job)))
  expect_false("endpoint" %in% names(formals(add_job)))
  expect_false("endpoint" %in% names(formals(open_job)))
  expect_false("endpoint" %in% names(formals(migrate_job)))
})

test_that("subjects remain safe filename fields", {
  dir <- tempfile("subject-field-")
  dir.create(file.path(dir, "distributions"), recursive = TRUE)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  expect_error(add_job(prefix = "ac", subject = "../death", type = "hz", dir = dir), "subject")
  expect_error(add_job(prefix = "ac", subject = "death-event", type = "hz", dir = dir), "subject")
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

test_that("every template names the current job scaffolder", {
  tl <- template_list()
  for (i in seq_len(nrow(tl))) {
    txt <- readLines(tl$file[[i]], warn = FALSE)
    expect_false(
      any(grepl("new_job", txt, fixed = TRUE)),
      label = paste("template", tl$name[[i]], "mentions removed new_job()")
    )
  }
})

test_that("add_job preserves a legacy study layout", {
  dir <- tempfile("newjob-")
  dir.create(file.path(dir, "distributions"), recursive = TRUE)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  out <- add_job(prefix = "ac", subject = "dead_pa", type = "hz", dir = dir)
  expect_true(file.exists(out))
  expect_equal(out, file.path(dir, "distributions", "dead_pa-hz-ac.qmd"))
})

test_that("add_job follows a numbered study layout", {
  dir <- tempfile("addjob-numbered-")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  suppressMessages(hvtiRutilities::study_setup(
    dir, study = "Numbered layout test", study_tracker_id = 1L
  ))

  out <- add_job(prefix = "ac", subject = "dead_pa", type = "hz", dir = dir)

  expect_equal(
    out,
    file.path(dir, "20_distributions", "dead_pa-hz-ac.qmd")
  )
})

test_that("add_job refuses a mixed study layout", {
  dir <- tempfile("addjob-mixed-")
  dir.create(file.path(dir, "distributions"), recursive = TRUE)
  dir.create(file.path(dir, "30_analyses"), recursive = TRUE)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  expect_error(add_job(prefix = "ac", subject = "dead_pa", type = "hz", dir = dir), "mixed")
  expect_false(file.exists(file.path(
    dir,
    "distributions",
    "dead_pa-hz-ac.qmd"
  )))
})

test_that("add_job distinguishes two analysis types over one subject", {
  # This is the collision the type field exists to prevent. A death-hazard set
  # and a death-RFS set share the same Kaplan-Meier upstream, so keyed on
  # subject alone both would be `dead_pa-ac.qmd` -- two sets, one file.
  dir <- tempfile("newjob-")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  a <- add_job(prefix = "ac", subject = "dead_pa", type = "hz", dir = dir)
  b <- add_job(prefix = "ac", subject = "dead_pa", type = "rfs", dir = dir)
  expect_false(a == b)
  expect_true(all(file.exists(c(a, b))))

  # Certifying the paths differ is not enough: add_job() writes subject/type
  # into the FILENAME, and a body that still says the template's placeholder
  # values silently resolves set_path() into the OTHER set's directory. Each
  # written file's SUBJECT/TYPE declarations must match its own name.
  for (path in c(a, b)) {
    fields <- strsplit(sub("[.]qmd$", "", basename(path)), "-", fixed = TRUE)[[1L]]
    txt <- readLines(path, warn = FALSE)
    declared_subject <- sub('^SUBJECT <- "(.*)"$', "\\1", grep("^SUBJECT <- ", txt, value = TRUE))
    declared_type     <- sub('^TYPE\\s+<- "(.*)"$', "\\1", grep("^TYPE\\s+<- ", txt, value = TRUE))
    expect_equal(declared_subject, fields[[1L]], label = paste("declared SUBJECT in", path))
    expect_equal(declared_type, fields[[2L]], label = paste("declared TYPE in", path))
  }
})

test_that("add_job errors when the template lacks the SUBJECT/TYPE marker lines", {
  # `.set_markers()` must fail loudly rather than hand back a job that looks
  # scaffolded but silently kept whatever the fake template happened to say.
  fake_template <- tempfile("fake-template-", fileext = ".qmd")
  writeLines(c("---", "title: fake", "---", "no markers here"), fake_template)
  on.exit(unlink(fake_template), add = TRUE)

  # Mirrors template_list()'s real columns, `qualifier` included. A mock that
  # is narrower than the function it stands in for passes while the real code
  # path breaks.
  fake_tl <- data.frame(
    name = "zz", prefix = "zz", qualifier = NA_character_,
    folder = "distributions", file = fake_template,
    stringsAsFactors = FALSE
  )
  testthat::local_mocked_bindings(template_list = function() fake_tl, .package = "hvtiRtemplates")

  dir <- tempfile("newjob-")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  expect_error(add_job(prefix = "zz", subject = "dead_pa", type = "hz", dir = dir), "SUBJECT")

  # The failure is after the copy, so the defect Finding 1 exists to prevent
  # -- a job named for one set but declaring the template's placeholder set
  # -- must not survive: the partially-written file must be gone, not just
  # the error raised.
  out <- file.path(dir, "distributions", "dead_pa-hz-zz.qmd")
  expect_false(file.exists(out))
})

test_that("add_job rejects subject/type shapes that would break the filename", {
  # `-` is the field separator and `.` separates the extension, so neither
  # may appear in `subject` or `type`; both must also be a single non-NA
  # string. Verified misbehaviour this guards against: "" collapses a field,
  # NA writes the string "NA" into the path, character(0) recycles silently,
  # a length-2 vector reaches `if()` and errors opaquely, "dead-pa" adds a
  # fifth field, and "../esc" escapes the taxonomy folder.
  dir <- tempfile("newjob-")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  expect_error(add_job(prefix = "ac", subject = "", type = "hz", dir = dir), "subject")
  expect_error(add_job(prefix = "ac", subject = "dead_pa", type = "", dir = dir), "type")
  expect_error(add_job(prefix = "ac", subject = NA_character_, type = "hz", dir = dir), "subject")
  expect_error(add_job(prefix = "ac", subject = character(0), type = "hz", dir = dir), "subject")
  expect_error(add_job(prefix = "ac", subject = c("a", "b"), type = "hz", dir = dir), "subject")
  expect_error(add_job(prefix = "ac", subject = "dead-pa", type = "hz", dir = dir), "subject")
  expect_error(add_job(prefix = "ac", subject = "../esc", type = "hz", dir = dir), "subject")
})

test_that("add_job refuses an unknown prefix, naming the valid ones", {
  dir <- tempfile("newjob-")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  expect_error(add_job(prefix = "zz", subject = "dead_pa", type = "hz", dir = dir), "ac")
})

test_that("add_job refuses to overwrite an existing job", {
  # A job file accumulates a study's edits; silently replacing one discards them.
  dir <- tempfile("newjob-")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  add_job(prefix = "ac", subject = "dead_pa", type = "hz", dir = dir)
  expect_error(add_job(prefix = "ac", subject = "dead_pa", type = "hz", dir = dir), "already exists")
})

test_that("add_job errors when the copy fails rather than returning a dead path", {
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
  expect_error(suppressWarnings(add_job(prefix = "ac", subject = "dead_pa", type = "hz", dir = dir)),
               "failed to write")
})

test_that("every template declares SUBJECT and TYPE markers", {
  # The markers are the interface: add_job() hard-stops for any template
  # lacking them (see .set_markers()), so the contract has to hold for every
  # template on disk, not just `ac` -- otherwise the next template to be
  # added could silently fail to scaffold.
  tl <- template_list()
  for (i in seq_len(nrow(tl))) {
    txt <- readLines(tl$file[[i]], warn = FALSE)
    info <- basename(tl$file[[i]])
    expect_equal(length(grep("^SUBJECT\\s+<- ", txt)), 1L, info = info)
    expect_equal(length(grep("^TYPE\\s+<- ", txt)), 1L, info = info)
    expect_equal(length(grep("^ENDPOINT\\s+<- ", txt)), 0L, info = info)
  }
})

test_that("the ac template resolves artifact paths from its set markers", {
  # A template that computes artifact paths from anything but SUBJECT/TYPE
  # would need a path edited by hand -- the mistake the markers exist to
  # prevent.
  txt <- readLines(template_path("ac"), warn = FALSE)
  expect_true(any(grepl("set_path <- function\\(kind, file\\)", txt)))
  expect_true(any(grepl("paste0\\(SUBJECT, \"-\", TYPE\\)", txt)))
})

test_that("template artifact paths follow a numbered study layout", {
  root <- tempfile("template-paths-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  suppressMessages(hvtiRutilities::study_setup(
    root, study = "Template paths", study_tracker_id = 1L
  ))

  for (template in template_list()$file) {
    lines <- readLines(template, warn = FALSE)
    label <- grep("^#\\| label: set$", lines)
    end <- label + which(lines[-seq_len(label)] == "```")[[1L]]
    code <- parse(text = lines[(label + 1L):(end - 1L)])
    env <- new.env(parent = globalenv())
    env$.root <- root
    eval(code, envir = env)

    path <- env$set_path("estimates", "result.rds")

    expect_equal(
      path,
      file.path(root, "90_estimates",
                paste0(env$SUBJECT, "-", env$TYPE), "result.rds"),
      info = basename(template)
    )
  }
})
