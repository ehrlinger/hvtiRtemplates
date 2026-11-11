# vt-fit's observed-against-expected section: the one-sample log-rank on each arm
# forest's cumulative hazard, and the spread band around the average curve.

vt_oe_labels <- c(vt_fit_labels, "fit", "curves-helper", "curves", "rmst-helper", "rmst", "oe", "oe-curves")

test_that("the other arm's forest is tested, and the own arm is tested out of bag", {
  skip_on_cran()
  env <- vt_fit_first(labels = vt_oe_labels)
  oe <- env$oe
  expect_identical(paste(oe$model, oe$group), c("A A", "A B", "B A", "B B"))
  own <- oe$model == oe$group
  expect_identical(oe$inference[own], rep("tested, out of bag", 2L))
  expect_equal(oe$in_fit[own], oe$n[own] + oe$no_prediction[own])
  expect_identical(oe$inference[!own], rep("tested", 2L))
  expect_true(all(oe$in_fit[!own] == 0L))
  expect_true(all(is.finite(oe$p) & oe$lower < oe$ratio & oe$ratio < oe$upper))
  # Out of bag, a forest is roughly calibrated on its own arm: not 1 by construction, but near it.
  expect_true(all(oe$ratio[own] > 0.7 & oe$ratio[own] < 1.4))
  # The panel titles say which test is out of bag.
  expect_true(all(grepl("out of bag", unique(env$oe_curves$panel[env$oe_curves$model == env$oe_curves$group]))))
  expect_false(any(grepl("out of bag", unique(env$oe_curves$panel[env$oe_curves$model != env$oe_curves$group]))))
})

test_that("E is the other forest's cumulative hazard at each patient's own follow-up", {
  skip_on_cran()
  env <- vt_fit_first(labels = vt_oe_labels)
  d <- env$d
  pat <- d[d[[env$ARM]] %in% "B" & env$.treated & d[[env$ID]] %in% env$.rmst$ID[env$.rmst$elig], , drop = FALSE]
  f <- env$.forests[["A"]]
  # Computed here by predict(), not read from .curves, so a change in how the job
  # finds the hazard (at HORIZON, at max(TIME), off by one step) turns this red.
  p <- predict(f, newdata = pat[, f$xvar.names, drop = FALSE], na.action = "na.impute", seed = -abs(env$SEED))
  t_own <- pmin(pat[[env$TIME]], env$TAU)
  k <- findInterval(t_own, f$time.interest)
  e <- sum(ifelse(k == 0L, 0, p$chf[cbind(seq_along(k), pmax(k, 1L))]))
  cell <- env$oe[env$oe$model == "A" & env$oe$group == "B", ]
  expect_equal(cell$expected, e)
  expect_identical(cell$observed, sum(pat[[env$STATUS]] == 1 & pat[[env$TIME]] <= env$TAU))
})

test_that("TAU defaults to the shorter arm's follow-up and refuses one beyond it", {
  skip_on_cran()
  env <- vt_fit_first(labels = vt_oe_labels)
  expect_identical(env$TAU, min(env$.followup))
  env$TAU <- min(env$.followup) + 1
  expect_error(rf_run("vt", "fit", "oe", env), "beyond the follow-up")  # nolint: object_usage_linter.
})

test_that("the average curve is the mean of the predictions the RMST reads, banded by their spread", {
  skip_on_cran()
  env <- vt_fit_first(labels = vt_oe_labels)
  cv <- env$oe_curves
  expect_true(all(cv$time <= env$TAU))
  expect_true(all(cv$lower <= cv$mean + 1e-12 & cv$mean <= cv$upper + 1e-12))
  # The band's label never calls the spread a confidence interval.
  expect_match(env$.cap_oe_km, "not a confidence interval", fixed = TRUE)
  # At the horizon, the curve drawn equals 1 - the mean RMST risk under that forest.
  cell <- env$.oe_cells[[2L]]
  at <- findInterval(env$HORIZON, cell$times)
  risk <- env$.rmst$risk_A[match(cell$ids, env$.rmst$ID)]
  expect_equal(colMeans(cell$surv)[at], mean(1 - risk))
})

test_that("the spaghetti thins to SPAGHETTI_N patients per panel", {
  skip_on_cran()
  env <- vt_fit_first(labels = vt_oe_labels, choices = utils::modifyList(vt_choices, list(SPAGHETTI_N = 7)))
  per <- tapply(env$.lines$patient, env$.lines$panel, function(x) length(unique(x)))
  expect_true(all(per <= 7))
})
