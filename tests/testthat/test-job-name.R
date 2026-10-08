test_that("the stem is template first, with periods", {
  expect_identical(hvtiRtemplates:::.job_stem("ac", NA_character_, "death", "hz"), "ac.death.hz")
  expect_identical(hvtiRtemplates:::.job_stem("dp", "trends", "cohort", "eda"), "dp.trends.cohort.eda")
  expect_identical(hvtiRtemplates:::.job_stem("ac", NULL, "death", "hz"), "ac.death.hz")
})

test_that("subject and type are read from either spelling", {
  f <- hvtiRtemplates:::.job_name_fields
  expect_identical(f("x/20_distributions/ac.death.hz.qmd"), c("death", "hz"))
  expect_identical(f("dp.trends.cohort.eda.qmd"), c("cohort", "eda"))
  expect_identical(f("bl.death.boot.runner.R"), c("death", "boot"))
  expect_identical(f("dead_pa-hz-ac.qmd"), c("dead_pa", "hz"))
  expect_identical(f("cohort-eda-dp-trends.qmd"), c("cohort", "eda"))
  expect_identical(f("dead_pa-boot-bl-runner.R"), c("dead_pa", "boot"))
})

test_that("Quarto's intermediate file reads the same as the job", {
  f <- hvtiRtemplates:::.job_name_fields
  expect_identical(f("ac.death.hz.rmarkdown"), c("death", "hz"))
  expect_identical(f("dead_pa-hz-ac.rmarkdown"), c("dead_pa", "hz"))
})

test_that("a report whose type is 'runner' keeps it; only an R script drops it", {
  f <- hvtiRtemplates:::.job_name_fields
  expect_identical(f("ac.death.runner.rmarkdown"), c("death", "runner"))
  expect_identical(f("ac.death.runner.qmd"), c("death", "runner"))
})

test_that("a name in neither form gives no fields", {
  f <- hvtiRtemplates:::.job_name_fields
  expect_identical(f("analysis.qmd"), character(0))
  expect_identical(f("a.b.qmd"), character(0))
  expect_identical(f("a.b.c.d.e.qmd"), character(0))
})

test_that("the old spelling of a job is the dash form in the same folder", {
  d <- file.path(withr::local_tempdir(), "study")
  invisible(hvtiRutilities::study_setup(d, study = "Old spelling", study_tracker_id = 1L))
  tl <- template_list()
  row <- hvtiRtemplates:::.select_template(tl, "dp", "trends")
  legacy <- hvtiRtemplates:::.job_path_legacy(row, "cohort", "eda", d)
  expect_identical(basename(legacy), "cohort-eda-dp-trends.qmd")
  expect_identical(dirname(legacy), dirname(hvtiRtemplates:::.job_path(row, "cohort", "eda", d)))
})
