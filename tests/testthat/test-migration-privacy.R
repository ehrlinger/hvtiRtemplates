test_that("public migrations retain evidence locations without copying patient rows", {
  for (qualifier in c("gfup", "tables")) {
    root <- migration_study_fixture(paste0("dc-", qualifier))
    stem <- paste0("dc.", qualifier)
    listing <- file.path(root, "descriptive", paste0(stem, ".lst"))
    reference <- file.path(root, "documents", "patient-review.rtf")
    writeLines(c("N Mean", "40 2.5", "Obs study_id iv_dead", "1 SYNTHETIC_SECRET_472 0.123456789"), listing)
    writeLines(c("{\\rtf1", "SYNTHETIC_SECRET_938 0.987654321", "}"), reference)
    before <- tools::md5sum(c(listing, reference))
    job <- migrate_job(
      file.path(root, "descriptive", paste0(stem, ".sas")),
      "cohort", "eda", "dc", qualifier, lst = listing,
      reference = reference, dir = root
    )
    report <- paste(readLines(sub("[.]qmd$", "-migration.md", job)), collapse = "\n")
    expect_false(grepl("SYNTHETIC_SECRET|0[.]123456789|0[.]987654321", report))
    expect_match(report, paste0("descriptive/", stem, ".lst"), fixed = TRUE)
    expect_match(report, "documents/patient-review.rtf", fixed = TRUE)
    expect_match(report, "line=4", fixed = TRUE)
    expect_match(report, "withheld", fixed = TRUE)
    expect_identical(tools::md5sum(c(listing, reference)), before)
  }
})

test_that("public migration blocks jobs whose SAS log has coded errors", {
  root <- migration_study_fixture("dc-tables")
  log <- file.path(root, "descriptive", "dc.tables.log")
  writeLines("ERROR 180-322: Statement is not valid.", log)
  job <- migrate_job(
    file.path(root, "descriptive", "dc.tables.sas"), "cohort", "eda", "dc", "tables", log = log, dir = root
  )
  expect_true(any(grepl("EDIT:.*SAS.*error", readLines(job))))
  report <- paste(readLines(sub("[.]qmd$", "-migration.md", job)), collapse = "\n")
  expect_match(report, "line=1; severity=error; text=ERROR 180-322:", fixed = TRUE)
})
