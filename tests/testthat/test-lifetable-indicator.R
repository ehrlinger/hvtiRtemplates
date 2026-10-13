test_that("a 0/1 column with the default level 1 passes through unchanged", {
  x <- c(1L, 0L, 1L, NA)
  out <- hvtiRtemplates:::.lifetable_indicator(x, 1, "male", "MALE_LEVEL")
  expect_identical(as.vector(out), c(1L, 0L, 1L, NA))
})

test_that("a female column and a sex factor give the same male indicator (#183)", {
  female <- c(1L, 0L, 0L, 1L)
  sex <- factor(c("F", "M", "M", "F"))
  from_female <- hvtiRtemplates:::.lifetable_indicator(female, 0, "female", "MALE_LEVEL")
  from_sex <- hvtiRtemplates:::.lifetable_indicator(sex, "M", "sex", "MALE_LEVEL")
  expect_identical(as.vector(from_female), c(0L, 1L, 1L, 0L))
  expect_identical(as.vector(from_sex), as.vector(from_female))
})

test_that("a race factor takes several non-white levels, and the mapping shows every value", {
  race <- c("White", "Black", "Asian", "White", NA, "Other")
  out <- hvtiRtemplates:::.lifetable_indicator(race, c("Black", "Asian", "Other"), "race", "OTHER_LEVELS",
                                               counted = c("white", "non-white"))
  expect_identical(as.vector(out), c(0L, 1L, 1L, 0L, NA, 1L))
  m <- attr(out, "mapping")
  expect_identical(m$value, c("Asian", "Black", "Other", "White", "(missing)"))
  expect_identical(m$n, c(1L, 1L, 1L, 2L, 1L))
  expect_identical(m$counted_as, c("non-white", "non-white", "non-white", "white", "missing"))
})

test_that("a level the column never takes stops, naming the values it does take", {
  sex <- factor(c("F", "M"))
  expect_error(hvtiRtemplates:::.lifetable_indicator(sex, "Male", "sex", "MALE_LEVEL"),
               "^MALE_LEVEL names a value that sex never takes: Male[.] It takes: F, M[.] Change MALE_LEVEL")
  expect_error(hvtiRtemplates:::.lifetable_indicator(sex, character(), "sex", "MALE_LEVEL"),
               "^MALE_LEVEL must name at least one value of sex")
})
