# hm's guard-variance chunk: a degenerate fit with no usable variance matrix
# stops the job before hm.rds is saved, naming the phases and covariates (#228).

test_that("hm stops on a reported fit without a usable variance matrix, naming phase and covariates", {
  skip_concordance()
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  e <- concordance_estate()
  fit <- readRDS(file.path(hvtiRutilities::study_dir("estimates", e$root), "dead-a", "hm.rds"))$reported
  # A fit whose free parameters all have a standard error passes; its FIXED
  # parameters' all-NA rows do not count against it.
  expect_true(any(as.logical(fit$fit$fixed_mask)))
  expect_no_error(hm_guard(e$root, fit))

  # No variance matrix at all: vcov() returns a scalar NA.
  none <- fit
  none$fit$vcov <- NULL
  expect_identical(vcov(none), NA)
  err <- tryCatch(hm_guard(e$root, none), error = conditionMessage)
  expect_match(err, "has no variance matrix", fixed = TRUE)
  n_free <- sum(!as.logical(fit$fit$fixed_mask))
  expect_match(err, paste0("for ", n_free, " of its ", n_free, " free parameters"), fixed = TRUE)
  expect_match(err, "By phase: early (", fixed = TRUE)
  expect_match(err, "x1, age); late (", fixed = TRUE)
  expect_match(err, "Covariates among them: early.x1, early.age, late.x1, late.age", fixed = TRUE)

  # A matrix, but one free covariate's variance is missing and another's is negative.
  partial <- fit
  v <- partial$fit$vcov
  at <- match(c("late.age", "early.x1"), names(coef(fit)))
  v[at[1L], at[1L]] <- NA_real_
  v[at[2L], at[2L]] <- -1
  partial$fit$vcov <- v
  err <- tryCatch(hm_guard(e$root, partial), error = conditionMessage)
  expect_match(err, "no finite standard error for 2 of", fixed = TRUE)
  expect_match(err, "early (x1); late (age)", fixed = TRUE)
  expect_match(err, "Covariates among them: early.x1, late.age.", fixed = TRUE)
})
