rm_qualifiers <- c(balancing_continuous = "bs_continuous", linear = "fit_linear")

test_that("the shipped rm templates each call their hvtiRpropensity engine by namespace", {
  tl <- template_list()
  shipped <- tl$qualifier[tl$prefix == "rm"]
  expect_true(length(shipped) >= 1L)
  expect_true(all(shipped %in% names(rm_qualifiers)))
  for (qualifier in shipped) {
    src <- readLines(template_path("rm", qualifier), warn = FALSE)
    expect_true(any(grepl(paste0("hvtiRpropensity::", rm_qualifiers[[qualifier]], "\\("), src)), info = qualifier)
  }
})

test_that("every rm template's hvtiRpropensity guard asks for the version DESCRIPTION suggests", {
  suggests <- utils::packageDescription("hvtiRtemplates")$Suggests
  minimum <- sub(".*hvtiRpropensity \\(>= ([0-9.]+)\\).*", "\\1", gsub("\\s+", " ", suggests))
  tl <- template_list()
  for (qualifier in tl$qualifier[tl$prefix == "rm"]) {
    src <- readLines(template_path("rm", qualifier), warn = FALSE)
    guard <- regmatches(src, regexpr("packageVersion[(]\"hvtiRpropensity\"[)] < \"[0-9.]+\"", src))
    expect_length(guard, 1L)
    expect_identical(sub('.*< "([0-9.]+)"$', "\\1", guard), minimum, info = qualifier)
  }
})

test_that("rm-balancing_continuous scores, pools and saves a bundle", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.12")
  env <- new.env(parent = globalenv())
  env$d <- rm_mi_data()
  env$set_path <- function(kind, file) tempfile(fileext = file)
  env$.root <- withr::local_tempdir("rm-root-")
  choices <- list(OUTCOME = "exposure", PREDICTORS = c("age", "female"), ID = "id",
                  IMPUTATION = "imp", N_STRATA = 5L)
  labels <- c("edit-study-choices", "fit", "tbl-fit-status", "tbl-estimates", "tbl-covariance",
              "tbl-strata-counts", "save")
  rm_run("balancing_continuous", labels, env, choices)
  expect_s3_class(env$fit, "bs_continuous")
  expect_identical(env$fit$meta$n_imputations, 2L)
  expect_true(all(env$fit$tables$estimates$pooled))
  expect_true(all(c("bs", "cluster") %in% names(env$fit$data)))
  expect_equal(nrow(env$fit$data), 120L)
  expect_true(file.exists(env$MODEL_PATH))
})

test_that("rm-balancing_continuous names the exposure in its provenance", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.12")
  fit <- hvtiRpropensity::bs_continuous(exposure ~ age + female, rm_data(), id_col = "id")
  prov <- hvtiRtemplates:::.lm_fit_provenance(fit)
  expect_identical(names(prov$analysis)[[1L]], "exposure")
  expect_identical(prov$analysis$exposure$variable, "exposure")
})

test_that("rm-balancing_continuous renders end to end", {
  skip_on_cran()
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.12")
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  out <- rm_render_fixture("balancing_continuous")
  expect_true(file.exists(out$output))
  bundle <- file.path(hvtiRutilities::study_dir("estimates", out$root), "exposure-analysis",
                      "rm-balancing_continuous.rds")
  expect_true(file.exists(bundle))
})
