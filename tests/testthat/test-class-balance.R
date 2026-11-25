# The class-imbalance switch for rfc-fit.
y <- function(...) factor(rep(names(c(...)), c(...)))

test_that("two classes past the ratio grow RFQ and say so", {
  b <- hvtiRtemplates:::.class_balance(y(no = 90, yes = 10), ratio = 3)
  expect_true(b$rfq)
  expect_equal(b$ratio, 9)
  expect_identical(b$metric, "normalized Brier score")
  expect_match(b$text, ".callout-note", fixed = TRUE)
  expect_match(b$text, "no 90, yes 10, a ratio of 9.0 to 1", fixed = TRUE)
})

test_that("the ratio is inclusive, and balanced classes print nothing", {
  expect_true(hvtiRtemplates:::.class_balance(y(no = 30, yes = 10), ratio = 3)$rfq)
  b <- hvtiRtemplates:::.class_balance(y(no = 29, yes = 10), ratio = 3)
  expect_false(b$rfq)
  expect_identical(b$metric, "error rate")
  expect_identical(b$text, "")
})

test_that("more than two classes warn rather than switch", {
  b <- hvtiRtemplates:::.class_balance(y(a = 90, b = 30, c = 5), ratio = 3)
  expect_false(b$rfq)
  expect_match(b$text, ".callout-warning", fixed = TRUE)
  expect_match(b$text, "two classes only", fixed = TRUE)
})

test_that("Inf never switches, and a bad ratio stops", {
  expect_false(hvtiRtemplates:::.class_balance(y(no = 99, yes = 1), ratio = Inf)$rfq)
  expect_error(hvtiRtemplates:::.class_balance(y(no = 9, yes = 1), ratio = 0.5), "IMBALANCE_RATIO")
  expect_error(hvtiRtemplates:::.class_balance(y(no = 9, yes = 1), ratio = NA), "IMBALANCE_RATIO")
})

test_that("unused factor levels are not counted as empty classes", {
  f <- factor(c(rep("no", 30), rep("yes", 10)), levels = c("no", "yes", "maybe"))
  expect_true(hvtiRtemplates:::.class_balance(f, ratio = 3)$rfq)
})

test_that("fewer than two classes stop, without warnings, rather than say the forest is standard", {
  expect_error(expect_no_warning(hvtiRtemplates:::.class_balance(y(no = 40), ratio = 1)),
               "two or more classes .* all no [(]40[)]")
  expect_error(expect_no_warning(hvtiRtemplates:::.class_balance(factor(character()), ratio = 3)), "there are none")
})
