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

test_that("table migration withholds inline data for every supported SAS alias", {
  for (alias in c("datalines", "cards", "lines", "datalines4", "cards4", "lines4")) {
    root <- migration_study_fixture("dc-tables")
    source <- file.path(root, "descriptive", "dc.tables.sas")
    records <- if (endsWith(alias, "4")) {
      c("PATIENT_SENTINEL_472 ; 43", 'title "PATIENT_SENTINEL_938";', ";;;;")
    } else {
      c("PATIENT_SENTINEL_472 43", "PATIENT_SENTINEL_938 51", ";")
    }
    writeLines(c(
      "data built; input patient $ age;", paste0(toupper(alias), ";"), records,
      "age=age+10; if female=1; run;",
      "%desc_tab(vartype=continuous,input=built,varlist=/* Demography */ age);"
    ), source)
    before <- tools::md5sum(source)
    job <- migrate_job(source, "cohort", "eda", "dc", "tables", dir = root)
    report <- paste(readLines(sub("[.]qmd$", "-migration.md", job)), collapse = "\n")
    expect_false(grepl("PATIENT_SENTINEL", report, fixed = TRUE), info = alias)
    expect_match(report, "line=3; text=Inline SAS data content withheld", fixed = TRUE)
    expect_match(report, "line=6; text=age=age+10;", fixed = TRUE)
    expect_match(report, "line=6; text=if female=1;", fixed = TRUE)
    expect_true(any(grepl("EDIT:.*source.*logic", readLines(job))))
    expect_true("DATASET <- NA_character_" %in% readLines(job))
    expect_identical(tools::md5sum(source), before)
  }
})

test_that("table migration withholds same-line and unterminated inline records", {
  for (records in list(
    c("datalines; PATIENT_SENTINEL_472 43 ;", "age=age+10; run;"),
    c("cards4;", 'PATIENT_SENTINEL_472 " unbalanced quote', "PATIENT_SENTINEL_938 51")
  )) {
    root <- migration_study_fixture("dc-tables")
    source <- file.path(root, "descriptive", "dc.tables.sas")
    writeLines(c(
      "%desc_tab(vartype=continuous,input=built,varlist=/* Demography */ age);",
      "data local; input patient $ age;", records
    ), source)
    job <- migrate_job(source, "cohort", "eda", "dc", "tables", dir = root)
    report <- paste(readLines(sub("[.]qmd$", "-migration.md", job)), collapse = "\n")
    expect_false(grepl("PATIENT_SENTINEL", report, fixed = TRUE))
    expect_match(report, "Inline SAS data content withheld", fixed = TRUE)
    expect_true(any(grepl("EDIT:.*source.*logic", readLines(job))))
  }
})
