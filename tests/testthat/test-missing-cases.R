test_that("the missing-values table names each variable and the cohort the fit will use", {
  d <- data.frame(outcome = c(0, 1, NA, 1), age = c(50, NA, 60, NA), female = c(0, 1, 1, 0))
  tab <- hvtiRtemplates:::.missing_cases(d, OUTCOME = "outcome", PREDICTORS = c("age", "female"))
  expect_identical(names(tab), c("Variable", "Setting", "Missing"))
  # Only variables with a missing value, the most missing first, and then the cohort.
  expect_identical(tab$Variable, c("age", "outcome", "Complete cases"))
  expect_identical(tab$Setting, c("PREDICTORS", "OUTCOME", ""))
  expect_identical(tab$Missing, c("2", "1", "1 of 4 rows analyzed; 3 dropped"))
})

test_that("a model term is counted as the fit evaluates it, and `.` means every column", {
  d <- data.frame(y = c(1, 0, 1), x = c(1, NA, 3), z = c(NA, 1, 1))
  tab <- hvtiRtemplates:::.missing_cases(d, OUTCOME = "y", PREDICTORS = "I(x^2)")
  expect_identical(tab$Variable, c("I(x^2)", "Complete cases"))
  tab <- hvtiRtemplates:::.missing_cases(d, OUTCOME = "y", PREDICTORS = ".")
  expect_setequal(tab$Variable, c("x", "z", "Complete cases"))
  expect_identical(tab$Missing[[3L]], "1 of 3 rows analyzed; 2 dropped")
})

test_that("a cohort with nothing missing says so", {
  d <- data.frame(y = c(1, 0), x = c(1, 2))
  tab <- hvtiRtemplates:::.missing_cases(d, OUTCOME = "y", PREDICTORS = "x")
  expect_identical(tab$Variable, "Complete cases")
  expect_identical(tab$Missing, "2 of 2 rows analyzed; none dropped")
})

test_that("under imputation the rows are kept, and the table says so", {
  d <- data.frame(y = c(1, 0, 1), x = c(1, NA, 3))
  tab <- hvtiRtemplates:::.missing_cases(d, OUTCOME = "y", PREDICTORS = "x", action = "impute")
  expect_identical(tab$Missing[[2L]], "3 of 3 rows analyzed; 1 with a missing value imputed")
})

test_that("action = 'stop' names the columns and their counts instead of fitting", {
  d <- data.frame(time = c(1, 2, 3), event = c(1, 0, 1), age = c(NA, 2, NA), ef = c(1, NA, 3))
  expect_error(hvtiRtemplates:::.missing_cases(d, TIME = "time", COVARIATES = c("age", "ef"), action = "stop"),
               paste0("^3 of 3 rows have a missing value in the model's variables: age \\(2\\), ef \\(1\\)[.] ",
                      "Resolve them in the dataset build, or leave the variable out of COVARIATES[.]$"))
  # Nothing missing: no error, and the table is returned as usual.
  expect_identical(hvtiRtemplates:::.missing_cases(d[2L, c("time", "event")], TIME = "time", action = "stop")$Variable,
                   "Complete cases")
})

test_that("stacked imputations are counted per imputation, not summed across the stack", {
  one <- data.frame(y = c(1, 0, 1, 0), x = c(1, NA, 3, 4))
  d <- rbind(cbind(one, imp = 1L), cbind(one, imp = 2L), cbind(one, imp = 3L))
  tab <- hvtiRtemplates:::.missing_cases(d, OUTCOME = "y", PREDICTORS = "x", imputation = "imp")
  expect_identical(tab$Missing, c("1", "3 of 4 rows analyzed in each of 3 imputations; 1 dropped"))
})

test_that("a term's own missing values count, not only its column's (#318 review)", {
  # log() of a negative value is NaN, which the fit drops though x is complete.
  d <- data.frame(y = c(1, 0, 1, 0), x = c(1, -1, 3, 4))
  tab <- suppressWarnings(hvtiRtemplates:::.missing_cases(d, OUTCOME = "y", PREDICTORS = "log(x)"))
  expect_identical(tab$Variable, c("log(x)", "Complete cases"))
  expect_identical(tab$Missing[[2L]], "3 of 4 rows analyzed; 1 dropped")
  # A term that fills in a missing value leaves the row in the fit.
  d$x[[2L]] <- NA
  tab <- hvtiRtemplates:::.missing_cases(d, OUTCOME = "y", PREDICTORS = "ifelse(is.na(x), 0, x)")
  expect_identical(tab$Missing, "4 of 4 rows analyzed; none dropped")
})

test_that("imputations that analyze different numbers of rows are shown as a labelled range", {
  d <- data.frame(y = 1, x = c(1, 2, 3, 4, 1, NA, NA, 4), imp = rep(1:2, each = 4L))
  tab <- hvtiRtemplates:::.missing_cases(d, OUTCOME = "y", PREDICTORS = "x", imputation = "imp")
  expect_identical(tab$Missing, c("0 to 2", "2 to 4 of 4 rows analyzed per imputation, across 2 imputations; 0 to 2 dropped"))
})
