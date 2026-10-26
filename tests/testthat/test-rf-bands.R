test_that("the default subratio follows randomForestSRC's rule, and a chosen one is checked", {
  expect_equal(hvtiRtemplates:::.band_subratio(500, NULL), exp(-1))
  expect_equal(hvtiRtemplates:::.band_subratio(4000, NULL), exp(-1) * sqrt(1000 / 4000))
  expect_equal(hvtiRtemplates:::.band_subratio(500, 0.25), 0.25)
  for (bad in list(0, 0.6, -1, NA_real_, c(0.2, 0.3), "0.2")) {
    expect_error(hvtiRtemplates:::.band_subratio(500, bad), "SUBRATIO")
  }
  expect_identical(hvtiRtemplates:::.band_size(100, 0.37), 37L)
  expect_identical(hvtiRtemplates:::.band_size(3, 0.1), 2L)
})

test_that("the SE is the jackknife SE extract.subsample() reports", {
  skip_if_not_installed("randomForestSRC", "3.9.0")
  e <- new.env()
  utils::data("veteran", package = "randomForestSRC", envir = e)
  Surv <- survival::Surv # rfsrc() parses the formula text and does not accept survival::Surv  # nolint: object_name_linter
  f <- randomForestSRC::rfsrc(Surv(time, status) ~ ., e$veteran, ntree = 30,
                              importance = "none", seed = -1)
  set.seed(2)
  s <- randomForestSRC::subsample(f, B = 4, importance = "anti", verbose = FALSE)
  hat <- s$vmp[[1]][, 1]
  star <- sapply(s$vmpS, function(v) v[[1]][[1]])
  expect_equal(unname(hvtiRtemplates:::.band_se(hat, star, s$subratio)),
               unname(randomForestSRC::extract.subsample(s, standardize = FALSE)$se.jk.Z))
})

test_that("an NA replicate is left out of the SE rather than making it NA", {
  star <- matrix(c(1, 2, NA, 3, 1, 2), nrow = 2)
  expect_equal(hvtiRtemplates:::.band_se(c(2, 2), star, 0.5),
               sqrt(0.5 * c(mean(c(1, 1)), mean(c(0, 1, 0)))))
})

test_that("interpolating at a grid point reproduces that grid point", {
  x <- c(10, 20, 30)
  hat <- c(1, 2, 4)
  star <- cbind(c(1, 3, 5), c(0, 2, 2))
  at <- hvtiRtemplates:::.band_at(x, hat, star, c(20, 25))
  expect_equal(at$hat, c(2, 3))
  expect_equal(at$star, rbind(c(3, 2), c(4, 2)))
  expect_error(hvtiRtemplates:::.band_at(x, hat, star, 40), "observed range")
})

test_that("a failed subsample interpolates to NA, and the others are read as before", {
  x <- c(10, 20, 30)
  hat <- c(1, 2, 4)
  star <- cbind(c(1, 3, 5), NA_real_)
  at <- hvtiRtemplates:::.band_at(x, hat, star, 25)
  expect_equal(at$star[1, 1], 4)
  expect_true(is.na(at$star[1, 2]))
  expect_equal(dim(at$star), c(1L, 2L))
})

test_that("the floor names the subratio that would give 100 rare cases", {
  expect_equal(hvtiRtemplates:::.band_floor_need(400), 0.25)
  expect_equal(hvtiRtemplates:::.band_floor_need(150), 100 / 150)
})
