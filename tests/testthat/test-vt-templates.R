test_that("vt-fit reads the cohort and resolves the predictors", {
  skip_on_cran()
  env <- vt_fit_first()
  expect_setequal(env$.predictors, c("xs", "x1", "g1"))
  expect_equal(sum(env$.no_arm), 10L)
  expect_equal(sum(env$.treated), 290L)
})

test_that("the predictor contract refuses the arm, the outcome and the ID", {
  skip_on_cran()
  for (leak in c("arm", "time", "event", "ccfid")) {
    ch <- utils::modifyList(vt_choices, list(PREDICTORS = c("xs", leak)))
    expect_error(vt_fit_first(choices = ch), "PREDICTORS", info = leak)
  }
})

test_that("patient IDs are digested on read", {
  skip_on_cran()
  env <- vt_fit_first()
  expect_identical(env$d[[env$ID]][1:3],
                   hvtiRtemplates:::.id_digest(1:3, hvtiRtemplates:::.study_id_key(env$.root)))
})

test_that("EXCLUDE drops post-treatment columns", {
  skip_on_cran()
  ch <- utils::modifyList(vt_choices, list(EXCLUDE = "x1"))
  expect_setequal(vt_fit_first(choices = ch)$.predictors, c("xs", "g1"))
})

test_that("na.omit drops and counts patients missing a predictor", {
  skip_on_cran()
  d <- vt_data()
  d$x1[1:3] <- NA
  env <- vt_fit_first(data = d, choices = utils::modifyList(vt_choices, list(NA_ACTION = "na.omit")))
  expect_equal(nrow(env$d), 297L)
})

test_that("with stacked imputations only IMPUTATION_USE reaches the job", {
  skip_on_cran()
  d1 <- vt_data()
  d1$imp <- 1L
  d2 <- vt_data()
  d2$imp <- 2L
  d2$xs <- d2$xs + 100
  ch <- utils::modifyList(vt_choices, list(IMPUTATION = "imp", IMPUTATION_USE = 2L))
  env <- vt_fit_first(data = rbind(d1, d2), choices = ch)
  expect_equal(nrow(env$d), 300L)
  expect_gt(min(env$d$xs), 90)
})
