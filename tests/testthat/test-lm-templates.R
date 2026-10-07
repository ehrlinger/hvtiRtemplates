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
  env$.root <- withr::local_tempdir("lm-root-")
  choices <- list(OUTCOME = "outcome", PREDICTORS = c("age", "female"),
                  OUTCOME_LEVELS = c("none", "event"), EVENT_LEVEL = "event",
                  ID = "id", IMPUTATION = NULL)
  lm_run("binary", c("edit-study-choices", "fit", "save"), env, choices)
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
                  IMPUTATION = NULL)
  utils::capture.output(lm_run("binary", c("edit-study-choices", "tbl-data", "fit"), env, choices))
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
    env$.root <- withr::local_tempdir("lm-root-")
    lm_run(qualifier, c("edit-study-choices", "fit", lm_results(qualifier), "save"), env, cases[[qualifier]])
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
    env$.root <- withr::local_tempdir("lm-root-")
    labels <- c("edit-study-choices", "fit", lm_results(qualifier), "save")
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
  model_provenance <- hvtiRtemplates:::.lm_fit_provenance(model)
  root <- lm_study()
  cfg <- hvtiRutilities::study_config(root)
  model <- hvtiRtemplates:::.attach_handoff_lineage(
    model, data = list(hvtiRutilities::provenance_data(cfg = cfg, role = "training")),
    analysis = model_provenance$analysis, cohort = model_provenance$cohort
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
  lm_run("checkpred", c("edit-study-choices", "model", "validate", lm_results("checkpred"), "save"), env,
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
  model_provenance <- hvtiRtemplates:::.lm_fit_provenance(model)
  root <- lm_study()
  cfg <- hvtiRutilities::study_config(root)
  model <- hvtiRtemplates:::.attach_handoff_lineage(
    model, data = list(hvtiRutilities::provenance_data(cfg = cfg, role = "training")),
    analysis = model_provenance$analysis, cohort = model_provenance$cohort
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
  lm_run("checkpred", c("edit-study-choices", "model", "validate"), env,
         list(MODEL_FILE = "lm-checkpred.rds", OUTCOME = "outcome", GROUPS = 10L))
  expect_error(lm_run("checkpred", "save", env), "overwrite the source model")
  expect_identical(readBin(path, "raw", n = file.info(path)$size), before)
})

test_that("lm-checkpred stops when its validation patients were in the training data", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.7")
  # WHERE may not name the patient identifier, so the cohorts are chosen on an
  # ordinary column, an enrollment sequence that follows ccfid.
  built <- lm_data()
  built$enrolled <- built$ccfid
  root <- lm_study(data = built)
  cfg <- hvtiRutilities::study_config(root)
  bundle_dir <- file.path(hvtiRutilities::study_dir("estimates", root), "outcome-analysis")
  dir.create(bundle_dir, recursive = TRUE)
  # A current lm template saves digested IDs; a model saved before that holds raw ones. Both are checked.
  save_model <- function(train, digest) {
    model <- hvtiRpropensity::fit_logistic(
      outcome ~ age + female, train, family = "binary", outcome_col = "outcome",
      id_col = "ccfid", outcome_levels = c("none", "event"), event_level = "event"
    )
    model_provenance <- hvtiRtemplates:::.lm_fit_provenance(model)
    model <- hvtiRtemplates:::.attach_handoff_lineage(
      model, data = list(hvtiRutilities::provenance_data(cfg = cfg, role = "training")),
      analysis = model_provenance$analysis, cohort = model_provenance$cohort
    )
    if (digest) model <- hvtiRtemplates:::.digest_bundle_ids(model, root)
    saveRDS(model, file.path(bundle_dir, "lm-binary.rds"))
  }
  check <- function(choices = list(), labels = character()) {
    env <- new.env(parent = globalenv())
    env$.root <- root
    env$study_config <- hvtiRutilities::study_config
    env$set_path <- function(kind, file) file.path(bundle_dir, file)
    choices <- utils::modifyList(list(MODEL_FILE = "lm-binary.rds", OUTCOME = "outcome", GROUPS = 5L), choices)
    utils::capture.output(lm_run("checkpred", c("edit-study-choices", "tbl-data", "model", "training-overlap", labels),
                                 env, choices))
    env
  }
  d <- lm_data()
  for (digest in c(FALSE, TRUE)) {
    # The whole training cohort read again.
    save_model(d, digest)
    expect_identical(isTRUE(readRDS(file.path(bundle_dir, "lm-binary.rds"))$meta$id_digest), digest)
    expect_error(check(), "^The validation data are the training data: set DATASET or WHERE to the validation cohort[.]$",
                 info = paste("digest", digest))
    # A validation cohort that shares some patients names how many, never which.
    save_model(d[d$ccfid <= 70, ], digest)
    err <- tryCatch(check(list(WHERE = quote(enrolled > 60))), error = conditionMessage)
    expect_identical(err, "10 validation patients were in the training data: set DATASET or WHERE to the validation cohort.",
                     info = paste("digest", digest))
    # Identifiers from different columns cannot be compared.
    expect_error(check(list(ID = "id", WHERE = quote(enrolled > 70))), "identify patients by `id`.*`ccfid`",
                 info = paste("digest", digest))
    # A disjoint cohort goes on to validation, and its saved copy keeps no raw validation ID.
    env <- check(list(WHERE = quote(enrolled > 70)), c("validate", "save"))
    expect_identical(nrow(env$d), 50L, info = paste("digest", digest))
    saved <- readRDS(env$VALIDATION_PATH)
    key <- hvtiRtemplates:::.study_id_key(root)
    expect_true(isTRUE(saved$meta$id_digest), info = paste("digest", digest))
    expect_identical(saved$data$ccfid, hvtiRtemplates:::.id_digest(env$d$ccfid, key), info = paste("digest", digest))
    # The source model's training IDs are digested once, whichever way it was saved.
    expect_identical(saved$models[[1L]]$data$ccfid, hvtiRtemplates:::.id_digest(d$ccfid[d$ccfid <= 70], key),
                     info = paste("digest", digest))
    # A missing validation ID cannot be compared, so it stops.
    env <- check(list(WHERE = quote(enrolled > 70)))
    env$d$ccfid[1L] <- NA
    expect_error(lm_run("checkpred", "training-overlap", env), "Some patients have no `ccfid`",
                 info = paste("digest", digest))
    # A saved model without its training identifiers stops rather than skipping the check.
    model <- readRDS(file.path(bundle_dir, "lm-binary.rds"))
    model$data$ccfid <- NULL
    saveRDS(model, file.path(bundle_dir, "lm-binary.rds"))
    expect_error(check(list(WHERE = quote(enrolled > 70))), "does not keep its training identifiers",
                 info = paste("digest", digest))
  }
})

test_that("every lm template scaffolds and runs end to end, and one renders through Quarto", {
  skip_on_cran()
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.7")
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  # One job goes through Quarto end to end, hooks, provenance and all: checkpred,
  # which reads the saved model and so exercises the most of the family's code.
  # The other seven run every chunk but `provenance` in this session, which
  # catches what a render of their own code would, in a tenth of the time;
  # test-template-provenance.R evaluates each one's provenance chunk.
  out <- lm_render_fixture("checkpred")
  expect_true(file.exists(out$job))
  expect_true(file.exists(out$output))
  for (qualifier in setdiff(names(lm_qualifiers), "checkpred")) {
    out <- lm_render_fixture(qualifier, render = FALSE)
    expect_true(file.exists(out$job), info = qualifier)
    # The job's product, saved by its last chunk before provenance.
    expect_true(file.exists(out$env$MODEL_PATH), info = qualifier)
  }
})

test_that("an imputation column adds to KEY rather than replacing it", {
  # A study keyed on visits keeps its visit column when it also stacks imputations.
  for (qualifier in setdiff(names(lm_qualifiers), "checkpred")) {
    src <- readLines(template_path("lm", qualifier), warn = FALSE)
    src <- sub("^KEY <- ID$", 'KEY <- c(ID, "visit")', src)
    src <- sub("^IMPUTATION <- NULL", 'IMPUTATION <- "imp"', src)
    env <- new.env(parent = globalenv())
    eval(parse(text = lm_chunk(src, "edit-study-choices")), envir = env)
    expect_identical(env$KEY, c("ccfid", "visit", "imp"), info = qualifier)
  }
})
