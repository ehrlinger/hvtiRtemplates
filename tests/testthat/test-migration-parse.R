test_that("SAS parsing ignores commented calls and keeps source lines", {
  x <- c(
    "/* %desc_tab(vartype=bad, varlist=wrong); */",
    "%desc_tab(",
    "  vartype=category,",
    "  varlist= female race_grp,",
    "  by=repair);"
  )
  calls <- hvtiRtemplates:::.sas_calls(x, "desc_tab")
  expect_length(calls, 1L)
  expect_identical(calls[[1L]]$start, 2L)
  expect_match(calls[[1L]]$text, "female race_grp", fixed = TRUE)
})

test_that("SAS arguments retain empty and populated values", {
  call <- paste(
    "vartype=continuous, by=, byvalue=0 1,",
    "varlist=age bmi"
  )
  out <- hvtiRtemplates:::.sas_arguments(call)
  expect_identical(out$vartype, "continuous")
  expect_identical(out$by, "")
  expect_identical(out$byvalue, "0 1")
  expect_identical(out$varlist, "age bmi")
})

test_that("SAS arguments keep commas nested in values", {
  out <- hvtiRtemplates:::.sas_arguments(
    "format=put(score, 3.), varlist=age bmi"
  )
  expect_identical(out$format, "put(score, 3.)")
  expect_identical(out$varlist, "age bmi")
})

test_that("group headings partition a SAS variable list", {
  x <- "/* Demography */ female race_grp /* Procedure */ repair replace"
  expect_identical(
    hvtiRtemplates:::.sas_grouped_vars(x),
    list(
      Demography = c("female", "race_grp"),
      Procedure = c("repair", "replace")
    )
  )
})

test_that("group headings cannot be empty or repeated", {
  expect_error(
    hvtiRtemplates:::.sas_grouped_vars("/* */ mock_flag"),
    "must not be empty"
  )
  expect_error(
    hvtiRtemplates:::.sas_grouped_vars("/* Intake */ a /* Intake */ b"),
    "must be unique"
  )
})

test_that("log and listing facts keep evidence line numbers", {
  log <- c("NOTE: There were 40 observations read", "WARNING: Missing values")
  lst <- c("Goodness of Follow-up", "N  Mean  Std Dev", "40  3.2  1.1")
  expect_equal(
    hvtiRtemplates:::.sas_log_findings(log)$severity,
    c("note", "warning")
  )
  expect_equal(hvtiRtemplates:::.listing_facts(lst)$line, 1:3)
})

test_that("fixture evidence retains source text and original line positions", {
  fixture <- testthat::test_path("fixtures-migration", "common")
  sas <- hvtiRtemplates:::.source_lines(file.path(fixture, "example.sas"))
  log <- readLines(file.path(fixture, "example.log"), warn = FALSE)
  listing <- readLines(file.path(fixture, "example.lst"), warn = FALSE)
  calls <- hvtiRtemplates:::.sas_calls(sas$text, "desc_tab")

  expect_identical(sas$line, seq_len(10L))
  expect_identical(calls[[1L]]$start, 6L)
  expect_match(calls[[1L]]$text, "/* Intake */", fixed = TRUE)
  arguments <- hvtiRtemplates:::.sas_arguments(calls[[1L]]$text)
  expect_identical(
    hvtiRtemplates:::.sas_grouped_vars(arguments$varlist),
    list(Intake = "mock_flag", Event = "mock_event")
  )
  expect_identical(hvtiRtemplates:::.sas_log_findings(log)$line, c(1L, 3L, 4L))
  expect_identical(hvtiRtemplates:::.listing_facts(listing)$line, c(1L, 3L, 4L))
})

test_that("comment masking leaves arithmetic visible", {
  masked <- hvtiRtemplates:::.sas_mask_comments(c("* hidden;", "answer = top * bottom;"))
  expect_identical(masked, c("         ", "answer = top * bottom;"))
})
