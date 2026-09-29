# read_job_data() steps on plain data frames. No identifier value appears in
# any message: the tests assert counts only.

d0 <- data.frame(
  ccfid = 1:6, MRN = 101:106, eMRN = 201:206, pt_mrn = 1:6,
  age = c(15, 40, 55, NA, 70, 80), hx_chf = c(0L, 1L, 1L, 0L, 1L, NA)
)

test_that("the ID is ccfid when present, else MRN, then eMRN, else a stop", {
  expect_identical(hvtiRtemplates:::.resolve_job_id(d0, "ccfid"),
                   list(id = "ccfid", fallback = FALSE))
  expect_identical(hvtiRtemplates:::.resolve_job_id(d0[-1], "ccfid"),
                   list(id = "MRN", fallback = TRUE))
  expect_identical(hvtiRtemplates:::.resolve_job_id(d0[c("eMRN", "age")], "ccfid"),
                   list(id = "eMRN", fallback = TRUE))
  expect_error(hvtiRtemplates:::.resolve_job_id(d0["age"], "ccfid"),
               "ID in edit-study-choices")
  # A non-default ID never falls back: the analyst named it.
  expect_error(hvtiRtemplates:::.resolve_job_id(d0, "randid"), "randid")
})

test_that("MRN and eMRN are dropped unless one is the ID; no other name is", {
  out <- hvtiRtemplates:::.drop_identifiers(d0, "ccfid")
  expect_setequal(out$dropped, c("MRN", "eMRN"))
  expect_true("pt_mrn" %in% names(out$data))
  expect_false(any(c("MRN", "eMRN") %in% names(out$data)))
  kept <- hvtiRtemplates:::.drop_identifiers(d0[-1], "MRN")
  expect_identical(kept$dropped, "eMRN")
  expect_true("MRN" %in% names(kept$data))
  lower <- d0
  names(lower)[2] <- "mrn"
  expect_true("mrn" %in% hvtiRtemplates:::.drop_identifiers(lower, "ccfid")$dropped)
})

test_that("WHERE follows filter(): NA rows are dropped and counted, conditions apply in order", {
  none <- hvtiRtemplates:::.apply_where(d0, NULL)
  expect_identical(nrow(none$data), 6L)
  expect_identical(nrow(none$steps), 0L)
  one <- hvtiRtemplates:::.apply_where(d0, quote(age >= 18))
  expect_identical(one$data$ccfid, c(2L, 3L, 5L, 6L))
  expect_identical(one$steps$removed, 2L)
  expect_identical(one$steps$missing, 1L)
  two <- hvtiRtemplates:::.apply_where(d0, rlang::exprs(age >= 18, hx_chf == 1))
  expect_identical(two$data$ccfid, c(2L, 3L, 5L))
  expect_identical(two$steps$condition, c("age >= 18", "hx_chf == 1"))
  expect_identical(two$steps$removed, c(2L, 1L))
  expect_identical(two$steps$missing, c(1L, 1L))
  min_age <- 50
  expect_identical(hvtiRtemplates:::.apply_where(d0,
                                                 quote(age >= .env$min_age))$data$ccfid,
                   c(3L, 5L, 6L))
  expect_error(hvtiRtemplates:::.apply_where(d0, "age >= 18"), "WHERE must be NULL")
  expect_error(hvtiRtemplates:::.apply_where(d0, quote(age + 1)), "TRUE or FALSE")
})

test_that("rows must be unique on KEY; patients are counted on ID", {
  expect_identical(hvtiRtemplates:::.check_job_key(d0, "ccfid", "ccfid"),
                   list(rows = 6L, patients = 6L))
  long <- data.frame(ccfid = c(1L, 1L, 2L), iv_echo = c(0.1, 1.2, 0.3))
  expect_identical(hvtiRtemplates:::.check_job_key(long, c("ccfid", "iv_echo"),
                                                   "ccfid"),
                   list(rows = 3L, patients = 2L))
  expect_error(hvtiRtemplates:::.check_job_key(long, "ccfid", "ccfid"),
               "1 value of KEY repeats")
  err <- tryCatch(hvtiRtemplates:::.check_job_key(long, "ccfid", "ccfid"),
                  error = conditionMessage)
  expect_false(grepl("\\b1\\b.*\\b1\\b.*\\b2\\b", err))
  expect_error(hvtiRtemplates:::.check_job_key(long, "visit", "ccfid"),
               "KEY names a column")
})
