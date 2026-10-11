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
