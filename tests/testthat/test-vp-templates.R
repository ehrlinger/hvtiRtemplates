# The vp templates, run chunk by chunk from the installed files (helper-rf.R,
# helper-vp.R). Only tests that fit varPro skip on CRAN.

vp_data_labels <- c("setup", "edit-study-choices", "tbl-data", "tbl-missing")

test_that("vp-fit draws half its noise from each kind of candidate", {
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  env <- rf_env(vp_data())
  rf_run("vp", "fit", c(vp_data_labels, "noise"), env, vp_choices)
  noise <- grep("^noise", names(env$d_noise), value = TRUE)
  src <- sub("^noise[0-9]+_", "", noise)
  expect_length(noise, 20L)
  expect_identical(sum(src %in% c("fs", "g1")), 10L)
  # A permuted copy keeps its source's values and loses their order.
  for (i in seq_along(noise)) {
    expect_identical(sort(as.character(env$d_noise[[noise[i]]])), sort(as.character(env$d[[src[i]]])))
  }
})

test_that("vp-fit refuses an outcome named both ways, or neither", {
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  both <- vp_outcome(vp_choices, TIME = "time", EVENT = "event", RESPONSE = "event")
  neither <- vp_outcome(vp_choices, TIME = NULL, EVENT = NULL, RESPONSE = NULL)
  for (choices in list(both, neither)) {
    env <- rf_env(vp_data())
    expect_error(rf_run("vp", "fit", vp_data_labels, env, choices), "either TIME and EVENT")
  }
})

test_that("vp-fit screens a 0/1 RESPONSE as classification", {
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  choices <- vp_outcome(vp_choices, TIME = NULL, EVENT = NULL, RESPONSE = "event")
  env <- rf_env(vp_data())
  rf_run("vp", "fit", vp_data_labels, env, choices)
  expect_identical(env$.family, "classification")
  expect_true(is.factor(env$d$event))
  expect_identical(env$.analysis$outcome$kind, "classification")
})

test_that("vp-fit drops incomplete patients before the fit, and counts them", {
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  data <- vp_data()
  data$x1[1:7] <- NA
  env <- rf_env(data)
  rf_run("vp", "fit", vp_data_labels, env, vp_choices)
  expect_identical(nrow(env$d), 193L)
  expect_identical(env$.cohort$n, 193L)
  expect_match(utils::tail(env$.missing_values$Missing, 1L), "7 dropped")
})

test_that("vp-fit refuses a candidate whose name could be taken for noise", {
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  data <- vp_data()
  data$noise_x <- data$x1
  choices <- utils::modifyList(vp_choices, list(PREDICTORS = c("xs", "noise_x")))
  env <- rf_env(data)
  expect_error(rf_run("vp", "fit", c(vp_data_labels, "noise"), env, choices), "start with \"noise\"")
})
