test_that("the mm cohort is longitudinal with the correlation it was built with", {
  d <- mm_data()
  per_patient <- table(d$ccfid)
  expect_true(all(per_patient >= 2L & per_patient <= 6L))
  expect_false(anyDuplicated(d[c("ccfid", "time")]) > 0L)
  expect_true(all(d$y > 0))
  # The between-patient share of the log-scale variance is the CS correlation.
  fit <- nlme::lme(log(y) ~ log(time + 1) + age + female, random = ~ 1 | ccfid, data = d)
  vc <- as.numeric(nlme::VarCorr(fit)[, "Variance"])
  expect_equal(vc[[1L]] / sum(vc), 0.5, tolerance = 0.1)
})

test_that("mm scaffolds with its study choices and EDIT: markers", {
  root <- withr::local_tempdir("mm-scaffold-")
  suppressMessages(hvtiRutilities::study_setup(root, study = "Synthetic mm study", study_tracker_id = 42L, adopt = TRUE, cleanup = FALSE,
                                         renv = FALSE))
  job <- add_job("mm", "outcome", "mixed", dir = root)
  src <- readLines(job, warn = FALSE)
  # tbl-data resolves RESPONSE_SCALE and IMPUTATION again; the study choices are the lines before it.
  src <- src[seq_len(grep("label: tbl-data", src, fixed = TRUE) - 1L)]
  for (field in c("TIME", "KEY", "OUTCOME", "RESPONSE_SCALE", "TIME_TERMS", "PREDICTORS", "STRUCTURE", "METHOD",
                  "PREDICT_AT", "PREDICT_TIMES", "IMPUTATION")) {
    expect_length(grep(paste0("^", field, " <- "), src), 1L)
  }
  expect_true(any(grepl('^STRUCTURE <- "cs"', src)))
  expect_true(any(grepl("^KEY <- c\\(ID, TIME\\)", src)))
  expect_gt(sum(grepl("EDIT:", src, fixed = TRUE)), 5L)
})

test_that("mm reads every measurement, not one row per patient", {
  src <- readLines(template_path("mm"), warn = FALSE)
  expect_true(any(grepl("one_row_per_patient = FALSE", src, fixed = TRUE)))
})
