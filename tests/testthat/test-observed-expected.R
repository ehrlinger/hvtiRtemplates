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

test_that("the average-of-limits band is the patients' limits averaged, and says it is not the mean's interval", {
  surv <- rbind(c(0.9, 0.8), c(0.7, 0.4))
  lower <- surv - 0.05
  upper <- surv + c(0.02, 0.04)
  b <- hvtiRtemplates:::.cohort_curve_band(surv, lower, upper, "limits_mean", clevel = 0.68268948)
  expect_equal(b$mean, c(0.8, 0.6))
  expect_equal(b$lower, colMeans(lower))
  expect_equal(b$upper, colMeans(upper))
  expect_match(attr(b, "label"), "68% limits")
  expect_match(attr(b, "label"), "not an interval for the mean curve")
  expect_no_match(attr(b, "label"), "bound")
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

test_that("averaged logit limits are no bound on the mean curve's interval (review of #509)", {
  # Three patients, independent parameters, the delta method on the logit scale at z = 1. Averaging
  # each patient's interval puts the upper edge INSIDE the mean curve's own upper edge, so the
  # average of limits must not be called an upper bound. Counterexample from the review of #509.
  s <- c(0.9430778, 0.2661929, 0.9389693)
  g <- matrix(c(0.007527468, -0.004440389, 0.07035267, 0.05705287, 0.07481851, 0.04782574), 3, 2)
  v <- diag(2)
  logit_ci <- function(p, se_p) {
    se <- se_p / (p * (1 - p))
    stats::plogis(stats::qlogis(p) + c(-1, 1) * se)
  }
  each <- vapply(1:3, function(i) logit_ci(s[i], sqrt(drop(g[i, ] %*% v %*% g[i, ]))), numeric(2))
  averaged <- rowMeans(each)
  gbar <- colMeans(g)
  of_mean <- logit_ci(mean(s), sqrt(drop(gbar %*% v %*% gbar)))
  expect_equal(averaged, c(0.60847, 0.77089), tolerance = 1e-4)
  expect_equal(of_mean, c(0.64722, 0.77615), tolerance = 1e-4)
  expect_lt(averaged[2], of_mean[2])
})

test_that("the Kaplan-Meier steps leave undefined limits missing, not carried", {
  # Two patients both dying at time 1: survival falls to 0, where survfit() has no log limits.
  k <- hvtiRtemplates:::.km_steps(c(1, 1), c(1, 1))
  expect_identical(k$time, c(0, 1, 1))
  expect_identical(k$surv, c(1, 1, 0))
  expect_true(all(is.na(k$lower[k$surv == 0])) && all(is.na(k$upper[k$surv == 0])))
  # Wherever both limits exist they hold the estimate between them.
  withr::local_seed(3)
  k <- hvtiRtemplates:::.km_steps(stats::rexp(40), stats::rbinom(40, 1, 0.7))
  ok <- !is.na(k$lower) & !is.na(k$upper)
  expect_true(all(k$lower[ok] <= k$surv[ok] & k$surv[ok] <= k$upper[ok]))
  # A step is held until the next time: times never decrease and each change comes in a pair.
  expect_false(is.unsorted(k$time))
})

test_that(".step_frame holds each value to the next time, so a ribbon on it is flat across a gap", {
  k <- data.frame(time = c(0, 1, 3), lower = c(1, 0.8, 0.2), upper = c(1, 0.9, 0.3))
  s <- hvtiRtemplates:::.step_frame(k)
  expect_identical(s$time, c(0, 1, 1, 3, 3))
  expect_identical(s$lower, c(1, 1, 0.8, 0.8, 0.2))
  expect_identical(s$upper, c(1, 1, 0.9, 0.9, 0.3))
  # Across the gap from 1 to 3 the band is 0.8 at both ends: no slope toward 0.2.
  gap <- s[s$time > 1 - 1e-12 & s$time < 3 + 1e-12 & s$lower != 0.2 & s$lower != 1, ]
  expect_identical(unique(gap$lower), 0.8)
  expect_identical(hvtiRtemplates:::.step_frame(k[1, ]), k[1, ])
})
