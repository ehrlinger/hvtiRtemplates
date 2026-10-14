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
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.2.0")
  env <- new.env(parent = globalenv())
  env$d <- rm_mi_data()
  env$set_path <- function(kind, file) tempfile(fileext = file)
  env$.root <- withr::local_tempdir("rm-root-")
  choices <- list(OUTCOME = "exposure", PREDICTORS = c("age", "female"), ID = "id",
                  IMPUTATION = "imp", N_STRATA = 5L)
  labels <- c("edit-study-choices", "fit", "model-scale", "tbl-fit-status", "tbl-estimates", "tbl-covariance",
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
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.2.0")
  fit <- hvtiRpropensity::bs_continuous(exposure ~ age + female, rm_data(), id_col = "id")
  prov <- hvtiRtemplates:::.lm_fit_provenance(fit)
  expect_identical(names(prov$analysis)[[1L]], "exposure")
  expect_identical(prov$analysis$exposure$variable, "exposure")
})

test_that("rm-balancing_continuous renders end to end", {
  skip_on_cran()
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.2.0")
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  out <- rm_render_fixture("balancing_continuous")
  expect_true(file.exists(out$output))
  bundle <- file.path(hvtiRutilities::study_dir("estimates", out$root), "exposure-analysis",
                      "rm-balancing_continuous.rds")
  expect_true(file.exists(bundle))
})

rm_linear_labels <- c("setup", "edit-study-choices", "fit", "model-scale", "tbl-fit-status", "tbl-fit-quality", "tbl-estimates",
                      "tbl-covariance", "fig-residuals", "fig-qq", "save")

rm_linear_env <- function(d, imputation, scale = "identity", .local_envir = parent.frame()) {
  # eval_setup_chunk() drops the chunk's library() calls, so the figure chunks need ggplot2 attached here.
  withr::local_package("ggplot2", .local_envir = .local_envir)
  root <- lm_study(.local_envir = .local_envir)  # nolint: object_usage_linter.
  job <- file.path(root, "outcome-linear-rm-linear.qmd")
  writeLines("A job.", job)
  testthat::local_mocked_bindings(current_input = function(...) job, .package = "knitr", .env = .local_envir)
  env <- new.env(parent = globalenv())
  env$d <- d
  env$.root <- root
  rm_run("linear", rm_linear_labels, env, list(  # nolint: object_usage_linter.
    OUTCOME = "outcome", PREDICTORS = c("age", "female"), ID = "id", IMPUTATION = imputation, SAVE_FIGURES = FALSE,
    RESPONSE_SCALE = scale
  ))
  env
}

test_that("rm-linear on one dataset reports R-squared and t inference", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.2.0")
  env <- rm_linear_env(rm_data(), NULL)
  expect_s3_class(env$fit, "rm_fit")
  expect_false(any(env$fit$tables$estimates$pooled))
  expect_false(is.na(env$fit$tables$fit_quality$r_squared))
  expect_true(all(is.finite(env$fit$tables$estimates$df)))
  expect_true(file.exists(env$MODEL_PATH))
})

test_that("rm-linear on imputations pools and withholds R-squared", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.2.0")
  env <- rm_linear_env(rm_mi_data(), "imp")
  expect_identical(env$fit$meta$n_imputations, 2L)
  expect_true(all(env$fit$tables$estimates$pooled))
  expect_true(all(is.na(env$fit$tables$fit_quality$r_squared)))
})

test_that("rm-linear on the log scale fits log(outcome)", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.2.0")
  env <- rm_linear_env(rm_data(), NULL, scale = "log")
  expect_identical(deparse(env$fit$meta$formula), "log(outcome) ~ age + female")
  expect_identical(env$fit$meta$outcome_col, "outcome")
  expect_identical(env$.scale_label, " (log scale)")
})

test_that("the response term follows RESPONSE_SCALE and refuses what it cannot fit", {
  d <- data.frame(y = c(1, 2, NA), x = 1:3)
  expect_identical(hvtiRtemplates:::.response_term(d, "y", "identity"), "y")
  expect_identical(hvtiRtemplates:::.response_term(d, "y", "log"), "log(y)")
  expect_error(hvtiRtemplates:::.response_term(d, "y", "sqrt"), "RESPONSE_SCALE must be")
  expect_error(hvtiRtemplates:::.response_term(d, "y", c("log", "identity")), "RESPONSE_SCALE must be")
  expect_error(hvtiRtemplates:::.response_term(data.frame(y = c("12", "3")), "y", "log"), "y is not numeric")
  d$y[[1L]] <- 0
  expect_identical(hvtiRtemplates:::.response_term(d, "y", "identity"), "y")
  expect_error(hvtiRtemplates:::.response_term(d, "y", "log"), "1 value at or below zero")
})

test_that("a named RESPONSE_SCALE reads as its value in the formula and the note alike", {
  # A scale looked up from a named vector keeps its name; c(outcome = "identity") once fitted log().
  d <- data.frame(y = c(1, 2), x = 1:2)
  for (scale in c("identity", "log")) {
    named <- stats::setNames(scale, "y")
    expect_identical(hvtiRtemplates:::.response_scale(named), scale)
    expect_identical(hvtiRtemplates:::.response_term(d, "y", named), hvtiRtemplates:::.response_term(d, "y", scale))
    expect_identical(hvtiRtemplates:::.response_note(y ~ x, named, "outcome"),
                     hvtiRtemplates:::.response_note(y ~ x, scale, "outcome"))
  }
  expect_error(hvtiRtemplates:::.response_scale(NA_character_), "RESPONSE_SCALE must be")
  expect_error(hvtiRtemplates:::.response_scale(factor("log")), "RESPONSE_SCALE must be")
})

test_that("every rm template settles RESPONSE_SCALE before any code reads it", {
  # The figures branch on the setting in the template itself, where no rendered text can show a wrong scale.
  for (qualifier in names(rm_qualifiers)) {
    src <- readLines(template_path("rm", qualifier), warn = FALSE)
    code <- !grepl("^\\s*#", src)
    settle <- which(src == "RESPONSE_SCALE <- hvtiRtemplates:::.response_scale(RESPONSE_SCALE)")
    expect_length(settle, 1L)
    reads <- setdiff(which(code & grepl("RESPONSE_SCALE", src, fixed = TRUE) & !grepl("^RESPONSE_SCALE <- ", src)),
                     settle)
    expect_true(length(reads) > 0L && all(reads > settle), info = qualifier)
  }
})

test_that("the response note states the formula and reads the coefficients on its scale", {
  identity <- hvtiRtemplates:::.response_note(y ~ x, "identity", "outcome")
  expect_match(identity, "`y ~ x`", fixed = TRUE)
  expect_match(identity, "as measured", fixed = TRUE)
  expect_no_match(identity, "geometric", fixed = TRUE)
  logged <- hvtiRtemplates:::.response_note(log(y) ~ x, "log", "outcome")
  expect_match(logged, "`log(y) ~ x`", fixed = TRUE)
  expect_match(logged, "ratio of geometric means", fixed = TRUE)
  expect_no_match(logged, "as measured", fixed = TRUE)
})

test_that("rm set markers must agree with the rendered job filename", {
  root <- lm_study()  # nolint: object_usage_linter.
  job <- file.path(root, "other-eda-rm.qmd")
  writeLines("A finished job.", job)
  testthat::local_mocked_bindings(current_input = function(...) job, .package = "knitr")
  for (qualifier in names(rm_qualifiers)) {
    env <- new.env(parent = globalenv())
    env$.root <- root
    expect_error(rm_run(qualifier, "set", env), "but declares SUBJECT", info = qualifier)
  }
})

test_that("rm-linear renders end to end and saves both figures", {
  skip_on_cran()
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.2.0")
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  out <- rm_render_fixture("linear")
  expect_true(file.exists(out$output))
  prose <- rm_report_prose(out$output)
  expect_match(prose, "outcome ~ age + female", fixed = TRUE)
  expect_match(prose, "as measured", fixed = TRUE)
  expect_no_match(prose, "geometric means", fixed = TRUE)
  graphs <- file.path(hvtiRutilities::study_dir("graphs", out$root), "outcome-analysis")
  expect_true(all(file.exists(file.path(graphs, c("rm-linear-residuals.png", "rm-linear-qq.png")))))
})

test_that("a rendered rm job reads stacked imputations and saves a bundle of both", {
  skip_on_cran()
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.2.0")
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  # The data table's one-row-per-patient guard counts a patient within an imputation:
  # 240 rows on 120 patients must read, and the model must be fit on both imputations.
  subjects <- c(balancing_continuous = "exposure", linear = "outcome")
  classes <- c(balancing_continuous = "bs_continuous", linear = "rm_fit")
  for (qualifier in names(subjects)) {
    out <- rm_render_fixture(qualifier, data = rm_mi_data(), choices = 'IMPUTATION <- "imp"')
    expect_true(file.exists(out$output), info = qualifier)
    bundle <- file.path(hvtiRutilities::study_dir("estimates", out$root), paste0(subjects[[qualifier]], "-analysis"),
                        paste0("rm-", qualifier, ".rds"))
    expect_true(file.exists(bundle), info = qualifier)
    fit <- readRDS(bundle)
    expect_s3_class(fit, classes[[qualifier]])
    expect_identical(fit$meta$n_imputations, 2L, info = qualifier)
    expect_true(all(fit$tables$estimates$pooled), info = qualifier)
  }
})

test_that("a rendered rm-linear job fits when IMPUTATION is spelled differently from the column", {
  skip_on_cran()
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.2.0")
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  # read_job_data() matches the name ignoring case; the fit needs the data's own spelling.
  out <- rm_render_fixture("linear", data = rm_mi_data(), choices = 'IMPUTATION <- "IMP"')
  expect_true(file.exists(out$output))
  bundle <- file.path(hvtiRutilities::study_dir("estimates", out$root), "outcome-analysis", "rm-linear.rds")
  expect_true(file.exists(bundle))
  expect_identical(readRDS(bundle)$meta$n_imputations, 2L)
})

test_that("a rendered rm job on the log scale fits log() and reads its coefficients that way", {
  skip_on_cran()
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.2.0")
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  subjects <- c(balancing_continuous = "exposure", linear = "outcome")
  for (qualifier in names(subjects)) {
    what <- subjects[[qualifier]]
    out <- rm_render_fixture(qualifier, choices = 'RESPONSE_SCALE <- "log"')
    expect_true(file.exists(out$output), info = qualifier)
    bundle <- file.path(hvtiRutilities::study_dir("estimates", out$root), paste0(what, "-analysis"),
                        paste0("rm-", qualifier, ".rds"))
    expect_identical(deparse(readRDS(bundle)$meta$formula), sprintf("log(%s) ~ age + female", what), info = qualifier)
    # The report's own prose, not its folded code, must read the coefficients on the log scale.
    prose <- rm_report_prose(out$output)
    expect_match(prose, sprintf("log(%s) ~ age + female", what), fixed = TRUE, info = qualifier)
    expect_match(prose, "ratio of geometric means", fixed = TRUE, info = qualifier)
    expect_no_match(prose, "as measured", fixed = TRUE, info = qualifier)
  }
})

test_that("a rendered rm-linear with a named RESPONSE_SCALE fits, says and draws one scale", {
  skip_on_cran()
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.2.0")
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  cases <- list(identity = list(formula = "outcome ~ age + female", says = "as measured", not = "geometric means"),
                log = list(formula = "log(outcome) ~ age + female", says = "ratio of geometric means", not = "as measured"))
  for (scale in names(cases)) {
    case <- cases[[scale]]
    out <- rm_render_fixture("linear", choices = sprintf('RESPONSE_SCALE <- c(outcome = "%s")', scale))
    bundle <- file.path(hvtiRutilities::study_dir("estimates", out$root), "outcome-analysis", "rm-linear.rds")
    expect_identical(deparse(readRDS(bundle)$meta$formula), case$formula, info = scale)
    prose <- rm_report_prose(out$output)
    expect_match(prose, case$says, fixed = TRUE, info = scale)
    expect_no_match(prose, case$not, fixed = TRUE, info = scale)
  }
})
