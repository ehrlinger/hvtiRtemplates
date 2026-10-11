# The numerical core of the lg template: the internals in R/logit-calibration.R.
# The design is dev/specs/2026-10-11-lg-template-design.md; its section 5 lists
# what these tests cover. All data are synthetic.

test_that(".lg_groups() reproduces PROC RANK GROUPS=5 on a 12-row fixture with ties", {
  # PROC RANK GROUPS=G assigns floor(rank * G / (n + 1)), the rank averaged over
  # ties. Worked by hand for n = 12 and G = 5, so n + 1 = 13:
  #
  #   sorted value        1    3    3    4    6    6    6    9   10    12    12   20
  #   rank (ties mean)    1  2.5  2.5    4    6    6    6    8    9  10.5  10.5   12
  #   rank * 5 / 13    0.38 0.96 0.96 1.54 2.31 2.31 2.31 3.08 3.46  4.04  4.04 4.62
  #   group               0    0    0    1    2    2    2    3    3     4     4    4
  #
  # The tied 3s, 6s and 12s each share a group. A rule that ranks ties in order
  # would split them: the second 3 would be rank 3 and fall in group 1.
  x <- c(12, 3, 20, 6, 1, 9, 6, 12, 4, 10, 3, 6)
  got <- hvtiRtemplates:::.lg_groups(x, groups = 5L)
  expect_identical(got$group, c(4L, 0L, 4L, 2L, 0L, 3L, 2L, 4L, 1L, 3L, 0L, 2L))
  expect_identical(got$missing, 0L)
  expect_identical(as.integer(table(got$group)), c(3L, 1L, 3L, 2L, 3L))
})

test_that(".lg_groups() puts a rank that makes the product a whole number in the higher group", {
  # n = 9, G = 5, so n + 1 = 10 and rank 2 gives exactly 2 * 5 / 10 = 1: group 1, not 0.
  got <- hvtiRtemplates:::.lg_groups(1:9, groups = 5L)
  expect_identical(got$group, c(0L, 1L, 1L, 2L, 2L, 3L, 3L, 4L, 4L))
})

test_that(".lg_groups() drops a missing covariate and counts it, without moving the other groups", {
  x <- c(12, 3, 20, 6, 1, 9, 6, 12, 4, 10, 3, 6)
  got <- hvtiRtemplates:::.lg_groups(c(x, NA, NA), groups = 5L)
  expect_identical(got$group, c(4L, 0L, 4L, 2L, 0L, 3L, 2L, 4L, 1L, 3L, 0L, 2L, NA, NA))
  expect_identical(got$missing, 2L)
})

test_that(".lg_groups() takes each observed level of an ordinal covariate as a group", {
  # %logitgr: the covariate is its own grouping, so `groups` has no say.
  x <- c(3, 1, 2, 2, 3, 3, 1, NA)
  got <- hvtiRtemplates:::.lg_groups(x, groups = 5L, kind = "ordinal")
  expect_identical(got$group, c(2L, 0L, 1L, 1L, 2L, 2L, 0L, NA))
  expect_identical(got$missing, 1L)
  # A level that is absent leaves no empty group: levels 1, 2 and 4 are groups 0, 1 and 2.
  expect_identical(hvtiRtemplates:::.lg_groups(c(4, 1, 2), kind = "ordinal")$group, c(2L, 0L, 1L))
})

test_that(".lg_groups() stops on a covariate or group count it cannot use", {
  expect_error(hvtiRtemplates:::.lg_groups(c("a", "b")), "^x must be numeric")
  expect_error(hvtiRtemplates:::.lg_groups(c(NA_real_, NA_real_)), "^x has no value")
  expect_error(hvtiRtemplates:::.lg_groups(1:9, groups = 1L), "^groups must be a whole number of at least 2")
  expect_error(hvtiRtemplates:::.lg_groups(1:9, groups = 2.5), "^groups must be a whole number of at least 2")
  expect_error(hvtiRtemplates:::.lg_groups(1:9, groups = NA_integer_), "^groups must be a whole number of at least 2")
  # The count is not checked for an ordinal covariate, which does not use it.
  expect_identical(hvtiRtemplates:::.lg_groups(1:3, groups = NA, kind = "ordinal")$group, 0:2)
})
