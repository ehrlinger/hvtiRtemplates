# The pilot templates for the ar report record their exhibits and their Methods
# paragraph. dev/specs/2026-11-11-ar-question-report-design.md, section 5.3.

test_that("hz records its estimates, its fit figure and its Methods paragraph", {
  skip_on_cran()
  skip_if_not_installed("TemporalHazard", minimum_version = "1.2.8")
  skip_if_not_installed("numDeriv")
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.7.0")
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  env <- hz_fit_run()
  utils::capture.output(suppressWarnings(hazard_run(
    "hz", c("tbl-conservation-binding", "edit-estimates", "tbl-estimates", "estimates-warning", "fig-fit", "save",
            "methods"),
    env
  )))
  ex <- hvtiRtemplates:::.run_state$exhibits
  expect_setequal(names(ex), c("tbl-estimates", "fig-fit", "methods"))
  expect_identical(ex[["fig-fit"]]$kind, "figure")
  v <- readRDS(file.path(env$.root, ex[["methods"]]$file))
  expect_identical(v$n, nrow(env$resp))
  m <- hvtiRtemplates:::.run_state$methods$text
  expect_match(m, "multiphase hazard")
  expect_match(m, paste0(" ", nrow(env$resp), " patients"))
  expect_false(grepl("EDIT:", m))
})
