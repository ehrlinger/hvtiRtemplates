# lg: the logit calibration job. The design is
# dev/specs/2026-10-11-lg-template-design.md; its section 5 lists what these
# tests cover. The numerical core has its own tests in test-logit-calibration.R.
# All data are synthetic.

test_that("lg is a descriptive template that add_job() scaffolds, and its catalog row is shipped as Logit calibration", {
  tl <- template_list()
  row <- tl[tl$name == "lg", ]
  expect_identical(nrow(row), 1L)
  expect_identical(row$folder, "descriptive")
  expect_identical(row$call, "add_job(\"lg\", subject = \"dead\", type = \"calibration\")")
  root <- lm_study()
  job <- add_job("lg", "dead", "calibration", dir = root)
  expect_identical(basename(job), "lg.dead.calibration.qmd")
  expect_identical(normalizePath(dirname(job)), normalizePath(hvtiRutilities::study_dir("descriptive", root)))
  src <- readLines(job, warn = FALSE)
  expect_identical(grep("^SUBJECT\\s+<- ", src, value = TRUE), "SUBJECT <- \"dead\"")
  expect_identical(grep("^TYPE\\s+<- ", src, value = TRUE), "TYPE    <- \"calibration\"")
  catalog <- template_catalog()
  entry <- catalog[catalog$prefix == "lg", ]
  expect_identical(nrow(entry), 1L)
  expect_identical(entry$name, "Logit calibration")
  expect_identical(entry$status, "shipped")
  expect_true(is.na(entry$qualifier))
  expect_identical(entry$spec, "dev/specs/2026-10-11-lg-template-design.md")
  expect_identical(entry$downstream[[1L]], "lm")
})

test_that("the job checks its choices against the data before any calibration, naming the setting", {
  local_child_chunks()
  run <- function(...) lm_eval_job(lg_fixture(...)$job)
  expect_error(run("LINK <- \"cox\""), "^LINK must be \"logit\" or \"hazard\"")
  expect_error(run("EVENT <- \"died\""), "^EVENT names a column this dataset does not have: died")
  expect_error(run("EVENT <- c(\"dead\", \"hdead\")"), "^EVENT must be one column name")
  expect_error(run("TIME <- \"later\""), "^TIME names a column this dataset does not have: later")
  expect_error(run("EVENT <- \"ccfid\""), "^EVENT and TIME cannot be the patient identifier")
  expect_error(run(variables = c("VARIABLES <- data.frame(", "  name = c(\"age\", \"bmi\")", ")")),
               "^VARIABLES names a column this dataset does not have: bmi. Change VARIABLES in edit-study-choices")
  expect_error(run(variables = c("VARIABLES <- data.frame(", "  name = \"ccfid\"", ")")),
               "^VARIABLES names the patient identifier")
  # TIME is read by the hazard link and by INTERVAL only: a logit job with no INTERVAL need not have it.
  expect_no_error(run(c("LINK <- \"logit\"", "EVENT <- \"hdead\"", "TIME <- \"later\"")))
  expect_error(run(c("LINK <- \"logit\"", "EVENT <- \"hdead\"", "TIME <- \"later\"", "INTERVAL <- c(0, 5)")),
               "^TIME names a column this dataset does not have: later")
})

test_that("INTERVAL keeps the patients whose follow-up is in the window and reports how many it kept", {
  local_child_chunks()
  d <- lg_data()
  inside <- d$iv_dead >= 0.25 & d$iv_dead <= 5
  s <- lg_fixture("INTERVAL <- c(0.25, 5)")
  env <- lm_eval_job(s$job)
  expect_identical(nrow(env$d), sum(inside))
  expect_identical(env$.interval$counts$patients,
                   c(nrow(d), sum(d$iv_dead < 0.25), sum(d$iv_dead > 5), 0L, sum(inside)))
  # The covariates' defaults are those of the patients kept.
  expect_identical(env$variables$constant, signif(stats::median(d$age[inside]), 1L))
  # Without an interval, every patient is calibrated and there is nothing to report.
  env <- lm_eval_job(lg_fixture()$job)
  expect_identical(nrow(env$d), nrow(d))
  expect_null(env$.interval$counts)
  expect_identical(env$variables$constant, signif(stats::median(d$age), 1L))
})
