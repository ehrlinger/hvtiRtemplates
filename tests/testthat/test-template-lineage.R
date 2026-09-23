lineage_sha256 <- function(path) {
  digest::digest(path, algo = "sha256", file = TRUE)
}

lineage_rfs_data <- function() {
  data_env <- new.env()
  utils::data("veteran", package = "randomForestSRC", envir = data_env)
  data_env$veteran
}

lineage_rfs_choices <- list(
  TIME = "time", STATUS = "status",
  PREDICTORS = c("trt", "celltype", "karno", "diagtime", "age", "prior"),
  NTREE = 50, SEED = 1
)

test_that("RF explain retains fitted data lineage after the registry changes", {
  rf_skip_unless_stack(rf_template_packages("rfs", "fit"))
  root <- rf_study()
  data_a <- lineage_rfs_data()
  registered <- file.path(hvtiRutilities::study_dir("datasets", root), "cohort.rds")
  saveRDS(data_a, registered)

  fit <- new.env(parent = globalenv())
  fit$.root <- root
  fit$.provenance_data <- list(hvtiRutilities::provenance_data(cfg = hvtiRutilities::study_config(root), role = "training"))
  fit$d <- data_a
  rf_run("rfs", "fit", c("set", "study-choices", "fit", "save"), fit, lineage_rfs_choices)
  fitted_hash <- fit$.provenance_data[[1L]]$sha256
  handoff <- file.path(fit$CACHE_DIR, "rfs.rds")
  handoff_hash <- lineage_sha256(handoff)

  saveRDS(transform(data_a, age = age + 100), registered)
  expect_false(identical(fitted_hash, hvtiRutilities::provenance_data(cfg = hvtiRutilities::study_config(root))$sha256))

  explain <- new.env(parent = globalenv())
  explain$.root <- root
  rf_run("rfs", "explain", c("set", "study-choices", "forest"), explain)

  expect_identical(explain$.provenance_data[[1L]]$sha256, fitted_hash)
  expect_identical(explain$.provenance_artifacts[[1L]]$sha256, handoff_hash)
  expect_identical(explain$.provenance_artifacts[[1L]]$role, "forest")
})

test_that("RF explain rejects a lineage-free package handoff", {
  rf_skip_unless_stack(rf_template_packages("rfs", "fit"))
  fit <- suppressWarnings(rf_fit_first("rfs", lineage_rfs_data(), lineage_rfs_choices))
  handoff <- file.path(fit$CACHE_DIR, "rfs.rds")
  forest <- readRDS(handoff)
  attr(forest, "hvti_provenance") <- NULL
  suppressWarnings(saveRDS(forest, handoff))

  explain <- new.env(parent = globalenv())
  explain$.root <- fit$.root
  expect_error(
    rf_run("rfs", "explain", c("set", "study-choices", "forest"), explain),
    "rebuild.*rfs-fit",
    ignore.case = TRUE
  )
})

test_that("lm-checkpred distinguishes training, validation, and model lineage", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.7")
  root <- lm_study()
  cfg <- hvtiRutilities::study_config(root)
  d <- lm_data()
  model <- hvtiRpropensity::fit_logistic(
    outcome ~ age + female, d, family = "binary", outcome_col = "outcome",
    id_col = "id", outcome_levels = c("none", "event"), event_level = "event"
  )
  model_provenance <- hvtiRtemplates:::.lm_fit_provenance(model)
  model <- hvtiRtemplates:::.attach_handoff_lineage(
    model,
    data = list(hvtiRutilities::provenance_data(cfg = cfg, role = "training")),
    analysis = model_provenance$analysis,
    cohort = model_provenance$cohort
  )
  model_dir <- file.path(hvtiRutilities::study_dir("estimates", root), "outcome-analysis")
  dir.create(model_dir, recursive = TRUE)
  model_path <- file.path(model_dir, "lm-binary.rds")
  saveRDS(model, model_path)

  env <- new.env(parent = globalenv())
  env$.root <- root
  env$d <- d
  env$.provenance_data <- list(hvtiRutilities::provenance_data(cfg = cfg, role = "validation"))
  env$set_path <- function(kind, file) file.path(model_dir, file)
  lm_run("checkpred", c("study-choices", "model", "validate", "save"), env,
         list(MODEL_FILE = "lm-binary.rds", OUTCOME = "outcome", GROUPS = 10L))

  expect_identical(vapply(env$.provenance_data, `[[`, character(1L), "role"), c("training", "validation"))
  expect_identical(env$.provenance_artifacts[[1L]]$sha256, lineage_sha256(model_path))
  validation_lineage <- attr(readRDS(env$VALIDATION_PATH), "hvti_provenance", exact = TRUE)
  expect_identical(vapply(validation_lineage$data, `[[`, character(1L), "role"), c("training", "validation"))
  expect_identical(validation_lineage$artifacts[[1L]]$role, "source-model")
  expect_identical(validation_lineage$analysis$training, model_provenance$analysis)
  expect_identical(validation_lineage$cohort$training, model_provenance$cohort)
  expect_identical(validation_lineage$analysis$validation$outcome$variable, "outcome")
  expect_identical(validation_lineage$cohort$validation$n_input, nrow(d))
})

test_that("lm-checkpred rejects a lineage-free source model", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.7")
  root <- lm_study()
  model_dir <- file.path(hvtiRutilities::study_dir("estimates", root), "outcome-analysis")
  dir.create(model_dir, recursive = TRUE)
  saveRDS(list(), file.path(model_dir, "lm-binary.rds"))
  env <- new.env(parent = globalenv())
  env$.root <- root
  env$.provenance_data <- list()
  env$set_path <- function(kind, file) file.path(model_dir, file)

  expect_error(
    lm_run("checkpred", c("study-choices", "model"), env,
           list(MODEL_FILE = "lm-binary.rds", OUTCOME = "outcome", GROUPS = 10L)),
    "rebuild.*lm",
    ignore.case = TRUE
  )
})

test_that("lm-checkpred rejects source lineage without runtime model metadata", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.7")
  root <- lm_study()
  cfg <- hvtiRutilities::study_config(root)
  raw_model <- hvtiRpropensity::fit_logistic(
    outcome ~ age + female, lm_data(), family = "binary", outcome_col = "outcome",
    id_col = "id", outcome_levels = c("none", "event"), event_level = "event"
  )
  data_record <- hvtiRutilities::provenance_data(cfg = cfg, role = "training")
  model_dir <- file.path(hvtiRutilities::study_dir("estimates", root), "outcome-analysis")
  dir.create(model_dir, recursive = TRUE)
  cases <- list(
    missing_analysis = list(analysis = NULL, cohort = list(n_input = 120L)),
    missing_cohort = list(analysis = list(outcome = list(variable = "outcome")), cohort = NULL)
  )

  for (name in names(cases)) {
    case <- cases[[name]]
    model <- hvtiRtemplates:::.attach_handoff_lineage(
      raw_model, data = list(data_record), analysis = case$analysis, cohort = case$cohort
    )
    saveRDS(model, file.path(model_dir, "lm-binary.rds"))
    env <- new.env(parent = globalenv())
    env$.root <- root
    env$.provenance_data <- list()
    env$set_path <- function(kind, file) file.path(model_dir, file)

    expect_error(
      lm_run("checkpred", c("study-choices", "model"), env,
             list(MODEL_FILE = "lm-binary.rds", OUTCOME = "outcome", GROUPS = 10L)),
      "runtime analysis and cohort metadata.*rebuild",
      ignore.case = TRUE,
      info = name
    )
  }
})

test_that("bootstrap artifact reads hash every chunk and preserve explicit lineage", {
  root <- rf_study()
  cfg <- hvtiRutilities::study_config(root)
  data_record <- hvtiRutilities::provenance_data(cfg = cfg, role = "bootstrap-training")
  paths <- file.path(hvtiRutilities::study_dir("estimates", root), paste0("bag-", 1:2, ".rds"))
  saveRDS(list(chunk = 1L), paths[[1L]])
  bootstrap_analysis <- list(outcome = list(variable = "event", event = 1L))
  bootstrap_cohort <- list(n = 2L, n_events = 1L, n_censored = 1L)
  bag <- hvtiRtemplates:::.attach_handoff_lineage(
    list(chunk = 2L), data = list(data_record),
    analysis = bootstrap_analysis, cohort = bootstrap_cohort
  )
  saveRDS(bag, paths[[2L]])

  first <- hvtiRtemplates:::.read_bootstrap_artifact(paths[[1L]], "bootstrap-chunk", cfg, list(data_record))
  second <- hvtiRtemplates:::.read_bootstrap_artifact(paths[[2L]], "bootstrap-chunk", cfg, list())

  expect_identical(first$record$sha256, lineage_sha256(paths[[1L]]))
  expect_identical(second$record$sha256, lineage_sha256(paths[[2L]]))
  expect_identical(first$lineage$data, list(data_record))
  expect_identical(second$lineage$data, list(data_record))
  combined <- hvtiRtemplates:::.combine_handoff_lineage(list(first$lineage, second$lineage))
  expect_identical(combined$analysis, bootstrap_analysis)
  expect_identical(combined$cohort, bootstrap_cohort)
})

test_that("bootstrap artifact without carried or explicit lineage is rejected", {
  root <- rf_study()
  cfg <- hvtiRutilities::study_config(root)
  path <- file.path(hvtiRutilities::study_dir("estimates", root), "bag.rds")
  saveRDS(list(), path)
  expect_error(
    hvtiRtemplates:::.read_bootstrap_artifact(path, "bootstrap-bag", cfg, list()),
    "explicit.*BOOTSTRAP_DATA|re-run.*lineage",
    ignore.case = TRUE
  )
})

test_that("bootstrap explicit data preserves the remaining carried lineage", {
  root <- rf_study()
  cfg <- hvtiRutilities::study_config(root)
  path <- file.path(hvtiRutilities::study_dir("estimates", root), "partial-lineage.rds")
  data_record <- hvtiRutilities::provenance_data(cfg = cfg, role = "bootstrap-training")
  artifact_record <- list(path = "upstream.rds", role = "upstream", bytes = 1, sha256 = "abc")
  bootstrap_analysis <- list(outcome = list(variable = "event", event = 1L))
  bootstrap_cohort <- list(n = 2L, n_events = 1L, n_censored = 1L)
  partial <- hvtiRtemplates:::.attach_handoff_lineage(
    list(chunk = 1L), data = list(), artifacts = list(artifact_record),
    analysis = bootstrap_analysis, cohort = bootstrap_cohort
  )
  saveRDS(partial, path)

  result <- hvtiRtemplates:::.read_bootstrap_artifact(
    path, "bootstrap-bag", cfg, list(data_record)
  )

  expect_identical(result$lineage$data, list(data_record))
  expect_identical(result$lineage$artifacts, list(artifact_record))
  expect_identical(result$lineage$analysis, bootstrap_analysis)
  expect_identical(result$lineage$cohort, bootstrap_cohort)
})

test_that("bootstrap explicit data does not adapt malformed carried lineage", {
  root <- rf_study()
  cfg <- hvtiRutilities::study_config(root)
  path <- file.path(hvtiRutilities::study_dir("estimates", root), "malformed-lineage.rds")
  data_record <- hvtiRutilities::provenance_data(cfg = cfg, role = "bootstrap-training")
  malformed <- list(chunk = 1L)
  attr(malformed, "hvti_provenance") <- list(
    data = list(), artifacts = list(), analysis = list(outcome = "event")
  )
  saveRDS(malformed, path)

  expect_error(
    hvtiRtemplates:::.read_bootstrap_artifact(
      path, "bootstrap-bag", cfg, list(data_record)
    ),
    "complete hvti_provenance|Rebuild",
    ignore.case = TRUE
  )
})

test_that("mandatory handoff lineage cannot hide missing source data", {
  root <- rf_study()
  cfg <- hvtiRutilities::study_config(root)
  path <- file.path(hvtiRutilities::study_dir("estimates", root), "empty-lineage.rds")
  saveRDS(hvtiRtemplates:::.attach_handoff_lineage(list(), data = list()), path)

  expect_error(
    hvtiRtemplates:::.read_handoff(path, "model", cfg, "the producer job"),
    "source data|data lineage",
    ignore.case = TRUE
  )
  expect_error(
    hvtiRtemplates:::.read_bootstrap_artifact(path, "bootstrap-bag", cfg, list()),
    "BOOTSTRAP_DATA|source data",
    ignore.case = TRUE
  )
})

test_that("bootstrap templates publish and save every input artifact lineage", {
  for (prefix in c("bc", "bh", "bl", "br")) {
    source <- readLines(template_path(prefix), warn = FALSE)
    expect_true(any(grepl(".read_bootstrap_artifact(", source, fixed = TRUE)), info = prefix)
    expect_true(any(grepl("artifacts = .provenance_artifacts", source, fixed = TRUE)), info = prefix)
    expect_true(any(grepl(".attach_handoff_lineage(", source, fixed = TRUE)), info = prefix)
    expect_true(sum(grepl(".bootstrap_lineage$analysis", source, fixed = TRUE)) >= 2L, info = prefix)
    expect_true(sum(grepl(".bootstrap_lineage$cohort", source, fixed = TRUE)) >= 2L, info = prefix)
  }
})

test_that("hp reads the exact ac and hz chain artifacts and carried data", {
  root <- rf_study()
  cfg <- hvtiRutilities::study_config(root)
  record <- hvtiRutilities::provenance_data(cfg = cfg, role = "training")
  artifact_dir <- file.path(hvtiRutilities::study_dir("estimates", root), "death-hz")
  dir.create(artifact_dir, recursive = TRUE)
  ac_path <- file.path(artifact_dir, "ac.rds")
  hz_path <- file.path(artifact_dir, "hz.rds")
  ac <- hvtiRtemplates:::.attach_handoff_lineage(list(overall = data.frame(time = 1)), data = list(record))
  hz <- hvtiRtemplates:::.attach_handoff_lineage(list(deterministic = list(ok = TRUE)), data = list(record))
  saveRDS(ac, ac_path)
  saveRDS(hz, hz_path)

  env <- new.env(parent = globalenv())
  env$.root <- root
  env$FIT_NAME <- "deterministic"
  env$KM_NAME <- "overall"
  env$set_path <- function(kind, file) file.path(artifact_dir, file)
  eval(parse(text = rf_chunk(readLines(template_path("hp"), warn = FALSE), "read-upstream")), envir = env)

  expect_identical(vapply(env$.provenance_artifacts, `[[`, character(1L), "sha256"),
                   c(lineage_sha256(ac_path), lineage_sha256(hz_path)))
  expect_length(env$.provenance_data, 2L)
})

test_that("hazard chain templates attach, require, and publish lineage", {
  sources <- lapply(c("ac", "hz", "hm", "hp", "hs"), function(prefix) {
    readLines(template_path(prefix), warn = FALSE)
  })
  names(sources) <- c("ac", "hz", "hm", "hp", "hs")

  expect_true(any(grepl("overall = km", sources$ac, fixed = TRUE)))
  for (prefix in c("ac", "hz", "hm", "hs")) {
    expect_true(any(grepl(".attach_handoff_lineage(", sources[[prefix]], fixed = TRUE)), info = prefix)
  }
  for (prefix in c("hm", "hp", "hs")) {
    expect_true(any(grepl(".read_handoff(", sources[[prefix]], fixed = TRUE)), info = prefix)
    expect_true(any(grepl("artifacts = .provenance_artifacts", sources[[prefix]], fixed = TRUE)), info = prefix)
  }
  expect_true(any(grepl('"selection"', sources$hm, fixed = TRUE)))
  expect_true(any(grepl(
    ".provenance_artifacts <- c(.provenance_artifacts, .selection_read$lineage$artifacts,",
    sources$hm, fixed = TRUE
  )))
})
