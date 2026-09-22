lm_qualifiers <- c(
  binary = "fit_logistic", ordinal = "fit_logistic", nominal = "fit_logistic",
  propensity_binary = "ps_logistic", propensity_ordinal = "ps_ordinal",
  propensity_nominal = "ps_nominal", checkpred = "validate_logistic",
  balancing_count = "bs_count"
)

test_that("the lm family ships eight engine-specific templates", {
  tl <- template_list()
  lm <- tl[tl$prefix == "lm", ]
  expect_setequal(lm$qualifier, names(lm_qualifiers))
  for (qualifier in names(lm_qualifiers)) {
    src <- readLines(template_path("lm", qualifier), warn = FALSE)
    expect_true(any(grepl(paste0(lm_qualifiers[[qualifier]], "\\("), src)), info = qualifier)
    expect_true(any(grepl("hvtiRpropensity >= 0.1.7", src, fixed = TRUE)), info = qualifier)
  }
})

test_that("LM set markers must agree with the rendered job filename", {
  qualifiers <- names(lm_qualifiers)
  expect_length(qualifiers, 8L)
  template_dir <- system.file(
    "templates", "30_analyses", package = "hvtiRtemplates"
  )
  if (!nzchar(template_dir)) {
    template_dir <- testthat::test_path("..", "..", "inst", "templates", "30_analyses")
  }

  testthat::local_mocked_bindings(
    current_input = function(...) file.path(tempdir(), "other-eda-lm.qmd"),
    .package = "knitr"
  )

  for (qualifier in qualifiers) {
    source <- readLines(file.path(template_dir, paste0("lm-", qualifier, ".qmd")),
                        warn = FALSE)
    env <- new.env(parent = globalenv())
    env$.root <- tempdir()

    expect_error(
      eval(parse(text = lm_chunk(source, "set")), envir = env),
      "but declares SUBJECT", info = qualifier
    )
  }
})

test_that("lm-binary fits and saves a model bundle", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.7")
  env <- new.env(parent = globalenv())
  env$d <- lm_data()
  env$set_path <- function(kind, file) tempfile(fileext = file)
  choices <- list(OUTCOME = "outcome", PREDICTORS = c("age", "female"),
                  OUTCOME_LEVELS = c("none", "event"), EVENT_LEVEL = "event",
                  ID = "id", IMPUTATION = NULL)
  lm_run("binary", c("study-choices", "fit", "save"), env, choices)
  expect_s3_class(env$fit, "lm_fit")
  expect_identical(env$fit$meta$model_family, "binary")
  expect_true(file.exists(env$MODEL_PATH))
})

test_that("lm-binary validates variables inside model terms", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.7")
  env <- new.env(parent = globalenv())
  env$.root <- lm_study()
  env$read_built <- hvtiRutilities::read_built
  env$study_config <- hvtiRutilities::study_config
  choices <- list(OUTCOME = "outcome", PREDICTORS = c("age", "I(age^2)"),
                  OUTCOME_LEVELS = c("none", "event"), EVENT_LEVEL = "event",
                  ID = "id", IMPUTATION = NULL)
  lm_run("binary", c("study-choices", "read", "fit"), env, choices)
  expect_s3_class(env$fit, "lm_fit")
  expect_true("I(age^2)" %in% names(stats::coef(env$fit$models[[1L]])))
})

test_that("lm outcome templates fit every declared family", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.7")
  d <- lm_mi_data()
  cases <- list(
    ordinal = list(OUTCOME = "ordinal", PREDICTORS = c("age", "female"),
                   OUTCOME_LEVELS = c("low", "middle", "high"), ID = "id", IMPUTATION = "imp"),
    nominal = list(OUTCOME = "nominal", PREDICTORS = c("age", "female"),
                   OUTCOME_LEVELS = c("reference", "level_b", "level_c"),
                   REFERENCE_LEVEL = "reference", ID = "id", IMPUTATION = "imp")
  )
  for (qualifier in names(cases)) {
    env <- new.env(parent = globalenv())
    env$d <- d
    env$set_path <- function(kind, file) tempfile(fileext = file)
    lm_run(qualifier, c("study-choices", "fit", "results", "save"), env, cases[[qualifier]])
    expect_true(inherits(env$fit, "lm_fit"), info = qualifier)
    expect_identical(env$fit$meta$model_family, qualifier, info = qualifier)
    expect_identical(env$fit$meta$n_imputations, 2L, info = qualifier)
    expect_true(length(env$fit$models) == 2L, info = qualifier)
    expect_true(all(env$fit$tables$estimates$pooled), info = qualifier)
    expect_equal(nrow(env$fit$data), length(unique(d$id)), info = qualifier)
    expect_true(file.exists(env$MODEL_PATH), info = qualifier)
    expect_s3_class(readRDS(env$MODEL_PATH), "lm_fit")
  }
})

test_that("lm propensity and count templates expose pooled inference", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.7")
  d <- lm_mi_data()
  cases <- list(
    propensity_binary = list(TREATMENT = "treatment", PREDICTORS = c("age", "female"),
                             TREATMENT_LEVELS = c("control", "treated"), TREATED_LEVEL = "treated",
                             ID = "id", IMPUTATION = "imp"),
    propensity_ordinal = list(TREATMENT = "treatment_ordinal", PREDICTORS = c("age", "female"),
                              TREATMENT_LEVELS = c("low", "middle", "high"),
                              ID = "id", IMPUTATION = "imp"),
    propensity_nominal = list(TREATMENT = "treatment_nominal", PREDICTORS = c("age", "female"),
                              TREATMENT_LEVELS = c("reference", "level_b", "level_c"),
                              REFERENCE_LEVEL = "reference", ID = "id", IMPUTATION = "imp"),
    balancing_count = list(OUTCOME = "count", PREDICTORS = c("age", "female"),
                           ID = "id", IMPUTATION = "imp", DISTRIBUTION = "poisson", N_STRATA = 5L)
  )
  for (qualifier in names(cases)) {
    env <- new.env(parent = globalenv())
    env$d <- d
    env$set_path <- function(kind, file) tempfile(fileext = file)
    labels <- c("study-choices", "fit", "results", "save")
    lm_run(qualifier, labels, env, cases[[qualifier]])
    expect_true(all(c("estimates", "covariance", "fit_status") %in% names(env$fit$tables)), info = qualifier)
    expect_identical(env$fit$meta$n_imputations, 2L, info = qualifier)
    expect_true(length(env$fit$models) == 2L, info = qualifier)
    expect_true(all(env$fit$tables$estimates$pooled), info = qualifier)
    expect_equal(nrow(env$fit$data), length(unique(d$id)), info = qualifier)
    expect_true(file.exists(env$MODEL_PATH), info = qualifier)
    expect_true(length(env$fit$meta$package_versions) > 0L, info = qualifier)
    if (identical(qualifier, "propensity_ordinal")) {
      expect_true(all(c("quintile", "decile") %in% names(env$fit$data)))
    }
  }
})

test_that("lm-checkpred applies the saved bundle without fitting", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.7")
  d <- lm_data()
  model <- hvtiRpropensity::fit_logistic(
    outcome ~ age + female, d, family = "binary", outcome_col = "outcome",
    id_col = "id", outcome_levels = c("none", "event"), event_level = "event"
  )
  root <- lm_study()
  cfg <- hvtiRutilities::study_config(root)
  model <- hvtiRtemplates:::.attach_handoff_lineage(
    model, data = list(hvtiRutilities::provenance_data(cfg = cfg, role = "training"))
  )
  bundle_dir <- file.path(hvtiRutilities::study_dir("estimates", root), "outcome-analysis")
  dir.create(bundle_dir, recursive = TRUE)
  path <- file.path(bundle_dir, "lm-binary.rds")
  validation_path <- file.path(bundle_dir, "lm-checkpred.rds")
  saveRDS(model, path)
  before <- readBin(path, "raw", n = file.info(path)$size)
  env <- new.env(parent = globalenv())
  env$.root <- root
  env$d <- d
  env$.provenance_data <- list(hvtiRutilities::provenance_data(cfg = cfg, role = "validation"))
  env$set_path <- function(kind, file) file.path(bundle_dir, file)
  testthat::local_mocked_bindings(
    fit_logistic = function(...) stop("checkpred refitted a model", call. = FALSE),
    .package = "hvtiRpropensity"
  )
  lm_run("checkpred", c("study-choices", "model", "validate", "results", "save"), env,
         list(MODEL_FILE = "lm-binary.rds", OUTCOME = "outcome", GROUPS = 10L))
  expect_s3_class(env$validation, "lm_validation")
  expect_equal(lapply(env$model$models, stats::coef), lapply(model$models, stats::coef))
  expect_identical(readBin(path, "raw", n = file.info(path)$size), before)
  expect_true(file.exists(validation_path))
})

test_that("lm-checkpred refuses to overwrite its source bundle", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.7")
  d <- lm_data()
  model <- hvtiRpropensity::fit_logistic(
    outcome ~ age + female, d, family = "binary", outcome_col = "outcome",
    id_col = "id", outcome_levels = c("none", "event"), event_level = "event"
  )
  root <- lm_study()
  cfg <- hvtiRutilities::study_config(root)
  model <- hvtiRtemplates:::.attach_handoff_lineage(
    model, data = list(hvtiRutilities::provenance_data(cfg = cfg, role = "training"))
  )
  bundle_dir <- file.path(hvtiRutilities::study_dir("estimates", root), "outcome-analysis")
  dir.create(bundle_dir, recursive = TRUE)
  path <- file.path(bundle_dir, "lm-checkpred.rds")
  saveRDS(model, path)
  before <- readBin(path, "raw", n = file.info(path)$size)
  env <- new.env(parent = globalenv())
  env$.root <- root
  env$d <- d
  env$.provenance_data <- list(hvtiRutilities::provenance_data(cfg = cfg, role = "validation"))
  env$set_path <- function(kind, file) file.path(bundle_dir, file)
  lm_run("checkpred", c("study-choices", "model", "validate"), env,
         list(MODEL_FILE = "lm-checkpred.rds", OUTCOME = "outcome", GROUPS = 10L))
  expect_error(lm_run("checkpred", "save", env), "overwrite the source model")
  expect_identical(readBin(path, "raw", n = file.info(path)$size), before)
})

test_that("every lm template scaffolds and renders", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.7")
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  for (qualifier in names(lm_qualifiers)) {
    out <- lm_render_fixture(qualifier)
    expect_true(file.exists(out$job), info = qualifier)
    expect_true(file.exists(out$output), info = qualifier)
  }
})
