# build_cohort() is the cohort step of the bd build job. Every value here is
# simulated; the IDs are made up.

bc_data <- function() {
  data.frame(
    ccfid = c("A0001", "A0002", "A0003", "A0004", "A0005", "A0005"),
    dt_surg = as.Date(c("2010-01-05", "2011-02-06", "2012-03-07", "2013-04-08", "2014-05-09", "2015-06-10")),
    age = c(17, 40, NA, 66, 70, 71),
    stringsAsFactors = FALSE
  )
}

bc_list <- function(rows, .local_envir = parent.frame()) {
  path <- withr::local_tempfile(fileext = ".csv", .local_envir = .local_envir)
  utils::write.csv(rows, path, row.names = FALSE)
  path
}

test_that("with no cohort and no rules every row is kept, and the master row is recorded", {
  out <- build_cohort(bc_data())
  expect_identical(nrow(out$data), 6L)
  expect_identical(names(out$attrition),
                   c("step", "reason", "rows_before", "removed", "missing_condition", "rows_after", "patients_after"))
  expect_identical(out$attrition$step, "master")
  expect_identical(out$attrition$patients_after, 5L)
})

test_that("EXCLUDE rules apply in order; a missing condition is not excluded, and is counted", {
  out <- build_cohort(bc_data(), exclude = list(age < 18 ~ "Under 18", duplicated(ccfid) ~ "Later operation"))
  expect_identical(out$data$ccfid, c("A0002", "A0003", "A0004", "A0005"))
  att <- out$attrition
  expect_identical(att$reason, c("Rows read", "Under 18", "Later operation"))
  expect_identical(att$removed, c(0L, 1L, 1L))
  expect_identical(att$missing_condition, c(0L, 1L, 0L))
  expect_identical(att$rows_after, c(6L, 5L, 4L))
  expect_identical(att$patients_after, c(5L, 4L, 4L))
})

test_that("a rule naming a patient works, and its text never reaches the attrition table", {
  out <- build_cohort(bc_data(), exclude = list(ccfid == "A0004" ~ "Withdrew consent"))
  expect_false("A0004" %in% out$data$ccfid)
  expect_false(any(grepl("A0004", unlist(out$attrition))))
})

test_that("an outside vector of IDs works through the rule's environment", {
  withdrawn <- c("A0001", "A0002")
  out <- build_cohort(bc_data(), exclude = list(ccfid %in% withdrawn ~ "Withdrew consent"))
  expect_identical(nrow(out$data), 4L)
})

test_that("a cohort list keeps matched rows and counts list rows that matched nothing", {
  path <- bc_list(data.frame(ccfid = c("A0002", "A0004", "Z9999"), dt_surg = c("2011-02-06", "2013-04-08", "2013-04-08")))
  out <- build_cohort(bc_data(), cohort = path, join_by = c("ccfid", "dt_surg"))
  expect_identical(out$data$ccfid, c("A0002", "A0004"))
  expect_identical(out$attrition$step, c("master", "cohort"))
  expect_match(out$attrition$reason[[2L]], "1 list row\\(s\\) matched no master row")
  expect_false(any(grepl("Z9999", unlist(out$attrition))))
})

test_that("numbers and text match as identifiers: 100000 and \"100000\"", {
  d <- data.frame(ccfid = c(100000, 100001), dt_surg = as.Date(c("2010-01-01", "2010-01-02")))
  path <- bc_list(data.frame(ccfid = "100000", dt_surg = "2010-01-01"))
  out <- build_cohort(d, cohort = path, join_by = c("ccfid", "dt_surg"))
  expect_identical(nrow(out$data), 1L)
})

test_that("a cohort list's exclude and reason columns become steps, and the helper column is dropped", {
  path <- bc_list(data.frame(ccfid = c("A0002", "A0004", "A0003"), dt_surg = c("2011-02-06", "2013-04-08", "2012-03-07"),
                             exclude = c(0, 1, 1), reason = c("", "Redo", "Redo")))
  out <- build_cohort(bc_data(), cohort = path, join_by = c("ccfid", "dt_surg"))
  expect_identical(out$data$ccfid, "A0002")
  expect_identical(out$attrition$step, c("master", "cohort", "cohort list"))
  expect_identical(out$attrition$reason[[3L]], "Redo")
  expect_identical(out$attrition$removed[[3L]], 2L)
  expect_identical(names(out$data), names(bc_data()))
})

test_that("cohort-list problems stop with the file and the setting, never a value", {
  d <- bc_data()
  no_col <- bc_list(data.frame(ccfid = "A0002"))
  expect_error(build_cohort(d, cohort = no_col, join_by = c("ccfid", "dt_surg")), "has no column\\(s\\) dt_surg")
  bad_date <- bc_list(data.frame(ccfid = "A0002", dt_surg = "02/06/2011"))
  err <- expect_error(build_cohort(d, cohort = bad_date, join_by = c("ccfid", "dt_surg")), "YYYY-MM-DD")
  expect_false(grepl("A0002|02/06/2011", conditionMessage(err)))
  repeated <- bc_list(data.frame(ccfid = c("A0002", "A0002"), dt_surg = c("2011-02-06", "2011-02-06")))
  expect_error(build_cohort(d, cohort = repeated, join_by = c("ccfid", "dt_surg")), "repeats 1 JOIN_BY key")
  expect_error(build_cohort(d, cohort = file.path(tempdir(), "absent.csv"), join_by = "ccfid"), "does not exist")
  no_reason <- bc_list(data.frame(ccfid = "A0002", dt_surg = "2011-02-06", exclude = 1))
  expect_error(build_cohort(d, cohort = no_reason, join_by = c("ccfid", "dt_surg")), "no reason column")
  bad_exclude <- bc_list(data.frame(ccfid = "A0002", dt_surg = "2011-02-06", exclude = "Yes", reason = "Redo"))
  err_exclude <- expect_error(
    build_cohort(d, cohort = bad_exclude, join_by = c("ccfid", "dt_surg")),
    "1 exclude value\\(s\\) that are not 0 or 1"
  )
  expect_false(grepl("Yes", conditionMessage(err_exclude)))
})

test_that("a malformed rule names its number and reason, never its text", {
  d <- bc_data()
  age <- d$age  # Make age available for the list() call
  expect_error(build_cohort(d, exclude = list(age < 18)), "EXCLUDE rule 1 is not written condition ~ \"Reason\"")
  expect_error(build_cohort(d, exclude = list(age ~ 18)), "EXCLUDE rule 1 is not written")
  err <- expect_error(build_cohort(d, exclude = list(age > 1 ~ "Fine", ccfid == "A0001" & nope ~ "Broken")),
                      "EXCLUDE rule 2 \\(\"Broken\"\\) could not be evaluated")
  expect_false(grepl("A0001", conditionMessage(err)))
  expect_error(build_cohort(d, exclude = list(age ~ "Not logical")), "must give TRUE or FALSE for each of the 6 rows")
  expect_error(build_cohort(d, exclude = list(TRUE ~ "Too short")), "must give TRUE or FALSE for each of the 6 rows")
})

test_that("a step that empties the data stops and names it", {
  expect_error(build_cohort(bc_data(), exclude = list(!is.na(ccfid) ~ "Everyone")), "\"Everyone\" excluded every remaining row")
})

test_that("the ID column must exist", {
  expect_error(build_cohort(bc_data(), id = "mrn"), "the ID column mrn is not in the data")
})
