test_that("every migration log path reports diagnostics without patient-like message text", {
  for (kind in c("dc-tables", "dc-gfup", "dp-trends", "dp-postage-sas", "dp-postage-qmd")) {
    fixture <- sub("-(sas|qmd)$", "", kind)
    root <- migration_study_fixture(fixture)
    folder <- if (kind == "dp-trends") "graphs" else "descriptive"
    source <- file.path(root, folder, paste0(gsub("-", ".", fixture), if (kind == "dp-postage-qmd") ".qmd" else ".sas"))
    if (kind == "dp-postage-sas") {
      writeLines("set built; %let pref_time_var=iv_dead; %let variables=age;", source)
    }
    log <- file.path(root, folder, "review.log")
    writeLines(c(
      "routine output REVIEW_TOKEN_ROUTINE 987654321",
      "WARNING: REVIEW_TOKEN_LOG 987654322",
      "ERROR 180-322: REVIEW_TOKEN_ERROR 987654323",
      "NOTE: There were 40 observations read from REVIEW_TOKEN_NOTE 987654324",
      "NOTE: REVIEW_TOKEN_OTHER 987654325 observations read",
      "NOTE: The data set REVIEW_TOKEN_DATASET has 24 observations and 13 variables."
    ), log)
    before <- tools::md5sum(c(source, log))
    job <- migrate_job(source, "cohort", "eda", substr(fixture, 1L, 2L), sub("^[^-]+-", "", fixture), log = log, dir = root)
    report <- readLines(sub("[.]qmd$", "-migration.md", job))
    text <- paste(report, collapse = "\n")
    expect_false(grepl("REVIEW_TOKEN|98765432", text), info = kind)
    expect_false(grepl(normalizePath(root), text, fixed = TRUE))
    findings <- report[seq.int(match("## Log findings", report) + 1L, match("## Listing facts", report) - 1L)]
    findings <- findings[startsWith(findings, "- ")]
    expect_length(findings, 5L)
    expect_true(all(grepl(paste0("path=", folder, "/review.log"), findings, fixed = TRUE)))
    expect_true(all(grepl("SAS log message content withheld", findings, fixed = TRUE)))
    expect_match(findings[[1L]], "line=2; severity=warning; category=sas_warning", fixed = TRUE)
    expect_match(findings[[2L]], "line=3; severity=error; category=sas_error; error_code=180-322", fixed = TRUE)
    expect_match(findings[[3L]], "observations=40", fixed = TRUE)
    expect_match(findings[[4L]], "observations=NA", fixed = TRUE)
    expect_match(findings[[5L]], "observations=24; variables=13", fixed = TRUE)
    expect_true(any(grepl("EDIT: resolve SAS log errors", readLines(job), fixed = TRUE)))
    expect_identical(tools::md5sum(c(source, log)), before)
  }
})

test_that("log summaries classify ordinary diagnostics and count only recognized aggregate forms", {
  findings <- hvtiRtemplates:::.sas_log_findings(c(
    "WARNING: REVIEW_TOKEN_LOG 52", "error 22-322: REVIEW_TOKEN_ERROR 53",
    "ERROR: REVIEW_TOKEN_PLAIN 54", "NOTE: There were 1,240 observations read.",
    "NOTE: REVIEW_TOKEN_NOTE 55 observations read", "NOTE: The data set WORK.X has 24 observations and 13 variables."
  ))
  expect_identical(findings$severity, c("warning", "error", "error", "note", "note", "note"))
  expect_identical(findings$error_code, c(NA_character_, "22-322", rep(NA_character_, 4L)))
  expect_identical(findings$observations, c(NA_real_, NA_real_, NA_real_, 1240, NA_real_, 24))
  expect_identical(findings$variables, c(rep(NA_real_, 5L), 13))
  expect_false(any(grepl("REVIEW_TOKEN|52|53|54|55", findings$text)))
})
