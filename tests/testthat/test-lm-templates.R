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
  }
})

test_that("every lm template's hvtiRpropensity guard asks for the version DESCRIPTION suggests", {
  suggests <- utils::packageDescription("hvtiRtemplates")$Suggests
  minimum <- sub(".*hvtiRpropensity \\(>= ([0-9.]+)\\).*", "\\1", gsub("\\s+", " ", suggests))
  # 0.1.10 is the release whose ps_ordinal() and ps_nominal() return the balance
  # table the propensity templates print (#191), and whose count and group
  # tables name rate ratios and treatment levels correctly (#206).
  expect_true(package_version(minimum) >= "0.1.10")
  for (qualifier in names(lm_qualifiers)) {
    src <- readLines(template_path("lm", qualifier), warn = FALSE)
    guard <- regmatches(src, regexpr("packageVersion[(]\"hvtiRpropensity\"[)] < \"[0-9.]+\"", src))
    expect_length(guard, 1L)
    expect_identical(sub('.*< "([0-9.]+)"$', "\\1", guard), minimum, info = qualifier)
    expect_true(any(grepl(paste0("hvtiRpropensity >= ", minimum, "."), src, fixed = TRUE)), info = qualifier)
  }
})

test_that("every lm template stops on a column its study choices name and the data lack, naming the setting", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
  root <- lm_study()
  # The response setting of each template, and a column of lm_data() it can name.
  responses <- list(
    binary = c(OUTCOME = "outcome"), ordinal = c(OUTCOME = "ordinal"), nominal = c(OUTCOME = "nominal"),
    balancing_count = c(OUTCOME = "count"), propensity_binary = c(TREATMENT = "treatment"),
    propensity_ordinal = c(TREATMENT = "treatment_ordinal"),
    propensity_nominal = c(TREATMENT = "treatment_nominal"), checkpred = c(OUTCOME = "outcome")
  )
  read <- function(qualifier, choices) {
    env <- new.env(parent = globalenv())
    env$.root <- root
    env$study_config <- hvtiRutilities::study_config
    utils::capture.output(lm_run(qualifier, c("edit-study-choices", "tbl-data"), env, choices))
    env
  }
  for (qualifier in names(responses)) {
    setting <- names(responses[[qualifier]])
    good <- stats::setNames(list(responses[[qualifier]][[1L]]), setting)
    has_predictors <- !identical(qualifier, "checkpred")
    if (has_predictors) good$PREDICTORS <- c("age", "female")
    # The declared columns all present: the data step goes through.
    expect_s3_class(read(qualifier, good)$d, "data.frame")
    # A response column the data lack names its setting.
    expect_error(read(qualifier, utils::modifyList(good, stats::setNames(list("nope"), setting))),
                 paste0("^", setting, " names a column this dataset does not have: nope[.] Change ", setting,
                        " in edit-study-choices[.]$"), info = qualifier)
    # So does a predictor, including one used inside a model term.
    if (has_predictors) {
      expect_error(read(qualifier, utils::modifyList(good, list(PREDICTORS = c("age", "I(nope^2)", "gone")))),
                   "^PREDICTORS names columns this dataset does not have: nope, gone[.] Change PREDICTORS",
                   info = qualifier)
    }
    # And ID, through read_job_data(), before anything is fitted.
    expect_error(read(qualifier, utils::modifyList(good, list(ID = "nope", KEY = "nope"))),
                 "^ID names a column this dataset does not have: nope[.] Change ID in edit-study-choices[.]$",
                 info = qualifier)
  }
})

test_that("the model-column check accepts the `.` all-columns term", {
  d <- data.frame(age = 1, female = 0)
  # `.` stands for every column, so it is never a missing one.
  expect_identical(hvtiRtemplates:::.check_job_columns(d, PREDICTORS = "."), d)
  expect_identical(hvtiRtemplates:::.check_job_columns(d, PREDICTORS = c(".", "age")), d)
  # A real missing column beside it still stops.
  expect_error(hvtiRtemplates:::.check_job_columns(d, PREDICTORS = c(".", "nope")),
               "^PREDICTORS names a column this dataset does not have: nope[.]")
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
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
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
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
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
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
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
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
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
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
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
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
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
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
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

test_that("lm-checkpred reads a model in another set and validates on a registered validation dataset", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
  d <- lm_data()
  root <- lm_study(data = d)
  datasets <- hvtiRutilities::study_dir("datasets", root)
  # Each validation cohort is registered as a dataset of its own, as the template's comment says to.
  register <- function(name, rows) {
    utils::write.csv(rows, file.path(datasets, paste0(name, ".csv")), row.names = FALSE)
    suppressMessages(hvtiRutilities::register_data(root, built = paste0(name, ".csv"), dataset = name,
                                                   role = "named", population = "Later patients"))
  }
  register("validation", d[d$ccfid > 60, ])
  register("overlapping", d[d$ccfid > 50, ])
  cfg <- hvtiRutilities::study_config(root)
  # The training job saved its model in a set of its own, stroke-model.
  model <- hvtiRpropensity::fit_logistic(
    outcome ~ age + female, d[d$ccfid <= 60, ], family = "binary", outcome_col = "outcome",
    id_col = "ccfid", outcome_levels = c("none", "event"), event_level = "event"
  )
  model_provenance <- hvtiRtemplates:::.lm_fit_provenance(model)
  model <- hvtiRtemplates:::.attach_handoff_lineage(
    model, data = list(hvtiRutilities::provenance_data(cfg = cfg, role = "training")),
    analysis = model_provenance$analysis, cohort = model_provenance$cohort
  )
  estimates <- hvtiRutilities::study_dir("estimates", root)
  dir.create(file.path(estimates, "stroke-model"), recursive = TRUE)
  saveRDS(hvtiRtemplates:::.digest_bundle_ids(model, root), file.path(estimates, "stroke-model", "lm-binary.rds"))
  own <- file.path(estimates, "outcome-analysis")
  check <- function(choices = list(), labels = character()) {
    env <- new.env(parent = globalenv())
    env$.root <- root
    env$study_config <- hvtiRutilities::study_config
    env$set_path <- function(kind, file) {
      dir.create(own, recursive = TRUE, showWarnings = FALSE)
      file.path(own, file)
    }
    choices <- utils::modifyList(list(DATASET = "validation", OUTCOME = "outcome", GROUPS = 5L), choices)
    utils::capture.output(lm_run("checkpred", c("edit-study-choices", "tbl-data", "model", "training-overlap", labels),
                                 env, choices))
    env
  }
  # Without MODEL_SET the job looks in its own set, where there is no model.
  expect_error(check(), "^Saved model not found: .*outcome-analysis.*set MODEL_FILE and MODEL_SET")
  env <- check(list(MODEL_SET = "stroke-model"), c("validate", "save"))
  expect_identical(env$MODEL_PATH, file.path(estimates, "stroke-model", "lm-binary.rds"))
  expect_identical(nrow(env$d), 60L)
  expect_s3_class(env$validation, "lm_validation")
  expect_true(file.exists(file.path(own, "lm-checkpred.rds")))
  # A registered validation dataset is checked against the training cohort like any other.
  expect_error(check(list(DATASET = "overlapping", MODEL_SET = "stroke-model")),
               "^10 validation patients were in the training data")
  # Neither setting can reach outside the study's estimates.
  expect_error(check(list(MODEL_SET = "../stroke-model")), "^MODEL_SET must be NULL or one set name")
  expect_error(check(list(MODEL_FILE = "../stroke-model/lm-binary.rds")), "^MODEL_FILE must name one [.]rds file")
})

test_that("each propensity template prints its balance table where the binary job does", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
  cases <- list(
    propensity_binary = list(TREATMENT = "treatment", TREATMENT_LEVELS = c("control", "treated"),
                             TREATED_LEVEL = "treated"),
    propensity_ordinal = list(TREATMENT = "treatment_ordinal", TREATMENT_LEVELS = c("low", "middle", "high")),
    propensity_nominal = list(TREATMENT = "treatment_nominal", TREATMENT_LEVELS = c("reference", "level_b", "level_c"),
                              REFERENCE_LEVEL = "reference")
  )
  for (qualifier in names(cases)) {
    labels <- lm_results(qualifier)
    # Straight after the covariance table, as in lm-propensity_binary.
    expect_identical(match("tbl-smd", labels), match("tbl-covariance", labels) + 1L, info = qualifier)
    env <- new.env(parent = globalenv())
    env$d <- lm_data()
    lm_run(qualifier, c("edit-study-choices", "fit"), env,
           c(cases[[qualifier]], list(PREDICTORS = c("age", "female"), IMPUTATION = NULL)))
    src <- readLines(template_path("lm", qualifier), warn = FALSE)
    shown <- paste(eval(parse(text = lm_chunk(src, "tbl-smd")), envir = env), collapse = "\n")
    expect_match(shown, "female", info = qualifier)
    # The multi-level table names the pair each row compares.
    if (!identical(qualifier, "propensity_binary")) expect_match(shown, "versus", info = qualifier)
  }
  # The ordinal job says which way its proportional-odds model accumulates, as lm-ordinal does.
  expect_true("direction" %in% lm_results("propensity_ordinal"))
  out <- utils::capture.output(lm_run("propensity_ordinal", "direction", env = local({
    env <- new.env(parent = globalenv())
    env$d <- lm_data()
    lm_run("propensity_ordinal", c("edit-study-choices", "fit"), env,
           c(cases$propensity_ordinal, list(PREDICTORS = c("age", "female"), IMPUTATION = NULL)))
  })))
  expect_match(out, "^Cumulative direction: P[(]Y <= level[)]")
})

test_that("every lm template scaffolds and runs end to end, and one renders through Quarto", {
  skip_on_cran()
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
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
