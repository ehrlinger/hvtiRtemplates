vpm_data <- function() {
  d <- data.frame(y = c(1, 2, NA, 4, 5, 6, 7, 8, 9, 10), a = c(NA, 2:10), b = c(1, NA, 3:10), c = 1:10)
  d$a[5] <- NA
  d
}

test_that(".vp_missing drops a missing outcome in either mode and counts it on its own", {
  for (na in c("na.impute", "na.omit")) {
    m <- .vp_missing(vpm_data(), c("a", "b", "c"), outcome = "y", na_action = na)
    expect_false(anyNA(m$d$y))
    expect_identical(m$cohort$n_supplied, 10L)
    expect_identical(m$cohort$n_outcome_missing, 1L)
  }
})

test_that(".vp_missing keeps every row with an outcome under na.impute, and counts what it will impute", {
  m <- .vp_missing(vpm_data(), c("a", "b", "c"), outcome = "y", na_action = "na.impute")
  expect_identical(nrow(m$d), 9L)
  expect_identical(m$cohort$n_imputed, c(a = 2L, b = 1L, c = 0L))
  expect_identical(m$cohort$n_dropped, 0L)
  expect_true(anyNA(m$d$a))
})

test_that(".vp_missing drops incomplete rows under na.omit, exactly as complete.cases() did", {
  d <- vpm_data()
  m <- .vp_missing(d, c("a", "b", "c"), outcome = "y", na_action = "na.omit")
  expect_identical(m$d, d[stats::complete.cases(d), , drop = FALSE])
  expect_identical(m$cohort$n_dropped, 3L)
  expect_identical(m$cohort$n_imputed, c(a = 0L, b = 0L, c = 0L))
})

test_that(".vp_missing refuses to impute a predictor above the ceiling, and names it", {
  d <- vpm_data()
  d$b[1:6] <- NA
  expect_error(.vp_missing(d, c("a", "b", "c"), outcome = "y", max_missing = 0.4), "b \\(56%\\)")
  expect_no_error(.vp_missing(d, c("a", "b", "c"), outcome = "y", na_action = "na.omit", max_missing = 0.4))
})

test_that(".vp_missing's table states n supplied, n used and the rule", {
  m <- .vp_missing(vpm_data(), c("a", "b", "c"), outcome = "y")
  expect_identical(m$table$Row[1], "Supplied")
  expect_identical(m$table$Count[m$table$Row == "Used"], "9")
  expect_identical(m$table$Count[m$table$Row == "Imputed: a"], "2 (22%)")
  expect_match(attr(m$table, "rule"), "imputed once by random forest")
})

test_that(".vp_missing works with no outcome, as vp-dependence calls it", {
  m <- .vp_missing(vpm_data(), c("a", "b"), na_action = "na.impute")
  expect_identical(nrow(m$d), 10L)
  expect_identical(m$cohort$n_outcome_missing, 0L)
})

test_that(".vp_missing builds a valid table when no predictor is missing, in both modes", {
  d <- data.frame(y = 1:5, a = 1:5, b = 5:1)
  for (na in c("na.impute", "na.omit")) {
    m <- .vp_missing(d, c("a", "b"), outcome = "y", na_action = na)
    expect_identical(m$table$Count[m$table$Row == "Used"], "5")
    expect_null(names(m$table$Count))
    expect_type(m$table$Count, "character")
  }
})

test_that(".vp_missing returns a valid table when every row is missing the outcome", {
  d <- data.frame(y = c(NA_real_, NA_real_), a = c(1, NA))
  for (na in c("na.impute", "na.omit")) {
    m <- .vp_missing(d, "a", outcome = "y", na_action = na)
    expect_identical(nrow(m$d), 0L)
    expect_identical(m$table$Count[m$table$Row == "Used"], "0")
  }
})

test_that(".vp_missing gives the na.omit drop count a percentage", {
  m <- .vp_missing(vpm_data(), c("a", "b", "c"), outcome = "y", na_action = "na.omit")
  expect_identical(m$table$Count[m$table$Row == "Missing a predictor, dropped"], "3 (33%)")
})
