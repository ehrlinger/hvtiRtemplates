# The one-sample log-rank test and the cohort-average band the hs templates draw
# (dev/specs/2026-11-10-hs-oe-test-and-bands-design.md).

test_that("the one-sample log-rank recovers a known multiple of the expected hazard", {
  withr::local_seed(20261110)
  n <- 4000L
  rate <- 0.2
  follow <- stats::runif(n, 1, 5)
  # Events from twice the reference hazard: H(t) = rate * t, so O/E should be near 2.
  death <- stats::rexp(n, 2 * rate)
  event <- as.integer(death <= follow)
  time <- pmin(death, follow)
  res <- hvtiRtemplates:::.one_sample_logrank(event, rate * time)
  expect_equal(res$observed, sum(event))
  expect_equal(res$expected, sum(rate * time))
  expect_equal(res$ratio, 2, tolerance = 0.1)
  expect_true(res$lower < 2 && res$upper > 2)
  expect_lt(res$p, 0.001)
  expect_identical(res$level, 0.95)

  # From the reference hazard itself, the interval covers 1.
  death <- stats::rexp(n, rate)
  event <- as.integer(death <= follow)
  res <- hvtiRtemplates:::.one_sample_logrank(event, rate * pmin(death, follow))
  expect_true(res$lower < 1 && res$upper > 1)
})

test_that("the O/E interval is the exact Poisson interval, at the level asked for", {
  res <- hvtiRtemplates:::.one_sample_logrank(c(1, 1, 0, 1), c(0.5, 0.5, 0.5, 0.5))
  expect_equal(res$ratio, 3 / 2)
  expect_equal(res$chisq, (3 - 2)^2 / 2)
  expect_equal(res$lower, stats::qchisq(0.025, 6) / 2 / 2)
  expect_equal(res$upper, stats::qchisq(0.975, 8) / 2 / 2)
  wide <- hvtiRtemplates:::.one_sample_logrank(c(1, 1, 0, 1), rep(0.5, 4), level = 0.68268948)
  expect_lt(wide$upper - wide$lower, res$upper - res$lower)
  # No events: a lower limit of 0, not NaN.
  none <- hvtiRtemplates:::.one_sample_logrank(c(0, 0), c(0.3, 0.4))
  expect_identical(none$lower, 0)
  expect_gt(none$upper, 0)
})

test_that("the one-sample log-rank refuses inputs that would understate E", {
  f <- hvtiRtemplates:::.one_sample_logrank
  expect_error(f(c(1, 0), c(0.1, NA)), "missing, infinite or negative")
  expect_error(f(c(1, 0), c(0.1, Inf)), "missing, infinite or negative")
  expect_error(f(c(1, 0), c(0.1, -0.1)), "missing, infinite or negative")
  expect_error(f(c(1, 2), c(0.1, 0.1)), "0 or 1")
  expect_error(f(1, c(0.1, 0.1)), "one value per patient")
  expect_error(f(c(1, 0), c(0.1, 0.1), level = 95), "between 0 and 1")
  expect_error(f(c(0, 0), c(0, 0)), "expected count is 0")
})

test_that("the average-of-limits band is the patients' limits averaged, labeled an upper bound", {
  surv <- rbind(c(0.9, 0.8), c(0.7, 0.4))
  lower <- surv - 0.05
  upper <- surv + c(0.02, 0.04)
  b <- hvtiRtemplates:::.cohort_curve_band(surv, lower, upper, "limits_mean", clevel = 0.68268948)
  expect_equal(b$mean, c(0.8, 0.6))
  expect_equal(b$lower, colMeans(lower))
  expect_equal(b$upper, colMeans(upper))
  expect_match(attr(b, "label"), "68% limits")
  expect_match(attr(b, "label"), "upper bound")
  expect_error(hvtiRtemplates:::.cohort_curve_band(surv, band = "limits_mean", clevel = 0.68),
               "needs the patients' limits")
  expect_error(hvtiRtemplates:::.cohort_curve_band(surv, lower[, 1, drop = FALSE], upper, "limits_mean", clevel = 0.68),
               "one value per patient and time")
})

test_that("the spread band is the 15th to 85th percentiles, and never called a confidence interval", {
  withr::local_seed(1)
  surv <- matrix(stats::runif(300), ncol = 3)
  b <- hvtiRtemplates:::.cohort_curve_band(surv, band = "spread")
  expect_equal(b$lower, unname(apply(surv, 2, stats::quantile, 0.15)))
  expect_equal(b$upper, unname(apply(surv, 2, stats::quantile, 0.85)))
  expect_match(attr(b, "label"), "not a confidence interval")
})

test_that("a band must be chosen by name", {
  expect_error(hvtiRtemplates:::.cohort_curve_band(matrix(0.5), band = NULL), "BAND must be one of")
  expect_error(hvtiRtemplates:::.cohort_curve_band(matrix(0.5), band = "ci"), "BAND must be one of")
  expect_error(hvtiRtemplates:::.cohort_curve_band(matrix(NA_real_), band = "spread"), "missing")
})

test_that("averaging the limits gives an interval no narrower than the mean curve's, by the delta method", {
  # Two patients on one exponential model, S_i = exp(-exp(b0 + b1 x_i) t). The mean curve's
  # standard error from the gradient of the mean is at most the mean of the patients' standard
  # errors: the SD of a sum is at most the sum of the SDs. On the natural scale, where both are exact.
  b <- c(-1, 0.5)
  v <- matrix(c(0.04, 0.01, 0.01, 0.09), 2)
  x <- c(-1, 2)
  t <- 2
  grad <- function(xi) {
    s <- exp(-exp(b[1] + b[2] * xi) * t)
    -s * exp(b[1] + b[2] * xi) * t * c(1, xi)
  }
  se_i <- vapply(x, function(xi) sqrt(drop(t(grad(xi)) %*% v %*% grad(xi))), numeric(1))
  g_mean <- (grad(x[1]) + grad(x[2])) / 2
  se_mean <- sqrt(drop(t(g_mean) %*% v %*% g_mean))
  expect_lte(se_mean, mean(se_i))
})
