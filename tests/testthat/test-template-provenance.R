template_by_name <- function(name) {
  templates <- template_list()
  hit <- which(templates$name == name)
  stopifnot(length(hit) == 1L)
  templates$file[[hit]]
}

provenance_chunk_end <- function(source, label) {
  if (length(label) != 1L) return(integer())
  after_label <- (label + 1L):length(source)
  fence <- which(source[after_label] == "```")
  if (!length(fence)) return(integer())
  label + fence[[1L]]
}

provenance_chunk <- function(path) {
  source <- readLines(path, warn = FALSE)
  label <- grep("^#\\| label: provenance$", source)
  if (length(label) != 1L) return(character())
  open <- max(which(seq_along(source) < label & source == "```{r}"))
  close <- provenance_chunk_end(source, label)
  if (!length(close)) return(character())
  final <- tail(which(nzchar(trimws(source))), 1L)
  if (!identical(close, final)) {
    stop("The provenance chunk must end at the final nonblank line.", call. = FALSE)
  }
  source[open:close]
}

provenance_expressions <- function(path) {
  chunk <- provenance_chunk(path)
  parse(text = chunk[-c(1L, length(chunk))])
}

is_embed_provenance_call <- function(expr) {
  if (!is.call(expr)) return(FALSE)
  fun <- expr[[1L]]
  direct <- is.call(fun) &&
    identical(as.character(fun[[1L]]), ":::") &&
    identical(as.character(fun[[2L]]), "hvtiRtemplates") &&
    identical(as.character(fun[[3L]]), ".embed_provenance")
  direct || (identical(expr[[1L]], as.name("cat")) && length(expr) == 2L && is_embed_provenance_call(expr[[2L]]))
}

r_chunk_expressions <- function(path) {
  source <- readLines(path, warn = FALSE)
  starts <- which(source == "```{r}")
  lapply(starts, function(start) {
    end <- start + which(source[(start + 1L):length(source)] == "```")[[1L]]
    parse(text = source[(start + 1L):(end - 1L)])
  })
}

embed_provenance_call_count <- function(expr) {
  direct <- as.integer(is_embed_provenance_call(expr))
  nested <- if (!direct && is.call(expr)) {
    sum(vapply(as.list(expr)[-1L], embed_provenance_call_count, integer(1L)))
  } else {
    0L
  }
  direct + nested
}

template_provenance_call_count <- function(path) {
  chunks <- r_chunk_expressions(path)
  sum(vapply(chunks, function(chunk) {
    sum(vapply(chunk, embed_provenance_call_count, integer(1L)))
  }, integer(1L)))
}

capture_provenance <- function(path, env) {
  captured <- NULL
  if (!exists(".provenance_data", envir = env, inherits = FALSE)) env$.provenance_data <- list()
  if (!exists(".provenance_artifacts", envir = env, inherits = FALSE)) env$.provenance_artifacts <- list()
  testthat::local_mocked_bindings(
    .embed_provenance = function(input, data, artifacts = list(), extra = NULL, ...) {
      captured <<- list(input = input, data = data, artifacts = artifacts, extra = extra)
      ""
    },
    .package = "hvtiRtemplates"
  )
  eval(provenance_expressions(path), envir = env)
  captured
}

test_that("provenance_chunk rejects an unlabeled later chunk", {
  path <- tempfile(fileext = ".qmd")
  writeLines(c(
    "```{r}",
    "#| label: provenance",
    "cat(hvtiRtemplates:::.embed_provenance(.in, data = list()))",
    "```",
    "```{r}",
    "invisible(NULL)",
    "```"
  ), path)

  expect_error(provenance_chunk(path), "final nonblank")
})

test_that("provenance calls outside the final chunk do not satisfy the contract", {
  path <- tempfile(fileext = ".qmd")
  writeLines(c(
    "```{r}",
    "cat(hvtiRtemplates:::.embed_provenance(.in, data = list()))",
    "```",
    "# hvtiRtemplates:::.embed_provenance(.in, data = list())",
    "```{r}",
    "#| label: provenance",
    "invisible(NULL)",
    "```"
  ), path)

  expressions <- provenance_expressions(path)
  expect_false(any(vapply(expressions, is_embed_provenance_call, logical(1L))))
})

test_that("nested provenance calls do not satisfy the contract", {
  cases <- c(
    if_false = "if (FALSE) hvtiRtemplates:::.embed_provenance(.in, data = list())",
    quoted = "quote(hvtiRtemplates:::.embed_provenance(.in, data = list()))",
    braced = "{ hvtiRtemplates:::.embed_provenance(.in, data = list()); invisible(NULL) }"
  )

  for (name in names(cases)) {
    path <- tempfile(fileext = ".qmd")
    writeLines(c(
      "```{r}",
      "#| label: provenance",
      cases[[name]],
      "```"
    ), path)

    expressions <- provenance_expressions(path)
    expect_false(any(vapply(expressions, is_embed_provenance_call, logical(1L))), info = name)
  }
})

test_that("embedded provenance calls are unique across all R chunks", {
  path <- tempfile(fileext = ".qmd")
  writeLines(c(
    "```{r}",
    "if (FALSE) hvtiRtemplates:::.embed_provenance(.in, data = list())",
    "```",
    "```{r}",
    "#| label: provenance",
    "cat(hvtiRtemplates:::.embed_provenance(.in, data = list()))",
    "```"
  ), path)
  expect_false(template_provenance_call_count(path) == 1L)
})

test_that("every shipped template ends with one embedded provenance chunk", {
  templates <- template_list()
  expect_equal(nrow(templates), 29L)

  for (path in templates$file) {
    source <- readLines(path, warn = FALSE)
    nonblank <- which(nzchar(trimws(source)))
    labels <- grep("^#\\| label: provenance$", source)
    chunk <- provenance_chunk(path)
    chunk_end <- provenance_chunk_end(source, labels)
    expressions <- provenance_expressions(path)
    info <- basename(path)

    expect_equal(length(labels), 1L, info = info)
    expect_identical(chunk_end, tail(nonblank, 1L), info = info)
    expect_identical(tail(grep("^#\\| label: ", source, value = TRUE), 1L),
                     "#| label: provenance", info = info)
    expect_equal(sum(vapply(expressions, is_embed_provenance_call, logical(1L))), 1L, info = info)
    expect_equal(template_provenance_call_count(path), 1L, info = info)
    expect_true(any(grepl("data = .provenance_data", chunk, fixed = TRUE)), info = info)
    expect_false(any(grepl("record_provenance", source, fixed = TRUE)), info = info)
    expect_true(any(grepl("subject = SUBJECT", chunk, fixed = TRUE)), info = info)
    expect_true(any(grepl("type = TYPE", chunk, fixed = TRUE)), info = info)
  }
})

test_that("provenance payloads take only the recovered render input", {
  for (path in template_list()$file) {
    chunk <- provenance_chunk(path)
    info <- basename(path)
    expect_true(any(grepl(".embed_provenance(", chunk, fixed = TRUE)), info = info)
    expect_true(any(grepl(".in,", chunk, fixed = TRUE)), info = info)
    expect_false(any(grepl("getwd()", chunk, fixed = TRUE)), info = info)
  }
})

test_that("registered data provenance is captured in the chunk that reads it", {
  for (path in template_list()$file) {
    chunks <- r_chunk_expressions(path)
    for (chunk in chunks) {
      text <- paste(vapply(chunk, deparse1, character(1L)), collapse = "\n")
      if (grepl("read_built(", text, fixed = TRUE)) {
        expect_true(grepl(".provenance_read(", text, fixed = TRUE), info = basename(path))
      }
    }
  }
})

test_that("analysis-set branches capture the parquet file they read", {
  for (prefix in c("dc-general", "dc-gfup", "dc-tables", "dp-gfup", "dp-postage")) {
    source <- readLines(template_by_name(prefix), warn = FALSE)
    info <- prefix
    expect_true(any(grepl(".provenance_file_read(", source, fixed = TRUE)), info = info)
    expect_true(any(grepl('paste0(ANALYSIS_SET, ".parquet")', source, fixed = TRUE)), info = info)
  }
})

test_that("only templates with a local dataset choice override the dataset", {
  expected <- c(
    "dc-general", "dc-gfup", "dc-tables", "dp-gfup", "dp-postage", "dp-trends",
    "lm-balancing_count", "lm-binary", "lm-checkpred", "lm-nominal", "lm-ordinal",
    "lm-propensity_binary", "lm-propensity_nominal", "lm-propensity_ordinal"
  )
  templates <- template_list()
  observed <- templates$name[vapply(templates$file, function(path) {
    any(grepl("DATASET, .cfg", readLines(path, warn = FALSE), fixed = TRUE))
  }, logical(1L))]

  expect_setequal(observed, expected)
})

test_that("endpoint-free templates do not invent analysis or cohort blocks", {
  identity_only <- c(
    "dc-general", "dc-tables", "dp-postage", "dp-trends"
  )
  for (prefix in identity_only) {
    chunk <- provenance_chunk(template_by_name(prefix))
    expect_false(any(grepl("analysis =", chunk, fixed = TRUE)), info = prefix)
    expect_false(any(grepl("cohort =", chunk, fixed = TRUE)), info = prefix)
  }
})

test_that("all logistic templates publish runtime analysis and cohort metadata", {
  qualifiers <- c(
    "binary", "ordinal", "nominal", "propensity_binary",
    "propensity_ordinal", "propensity_nominal", "checkpred", "balancing_count"
  )
  for (qualifier in qualifiers) {
    chunk <- provenance_chunk(template_by_name(paste0("lm-", qualifier)))
    expect_true(any(grepl("analysis =", chunk, fixed = TRUE)), info = qualifier)
    expect_true(any(grepl("cohort =", chunk, fixed = TRUE)), info = qualifier)
  }
})

test_that("logistic fit provenance is derived from runtime metadata and status tables", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.7")
  d <- lm_mi_data()
  cases <- list(
    binary = list(
      choices = list(
        OUTCOME = "outcome", PREDICTORS = c("age", "female"),
        OUTCOME_LEVELS = c("none", "event"), EVENT_LEVEL = "event",
        ID = "id", IMPUTATION = "imp"
      ),
      target = "outcome", variable = "outcome", levels = c("none", "event"),
      coding = list(event_level = "event"), method = "glm.fit:binomial(logit)"
    ),
    ordinal = list(
      choices = list(
        OUTCOME = "ordinal", PREDICTORS = c("age", "female"),
        OUTCOME_LEVELS = c("low", "middle", "high"), ID = "id", IMPUTATION = "imp"
      ),
      target = "outcome", variable = "ordinal", levels = c("low", "middle", "high"),
      coding = list(cumulative_direction = "P(Y <= level) = logistic(threshold - linear predictor)"),
      method = "polr:logistic"
    ),
    nominal = list(
      choices = list(
        OUTCOME = "nominal", PREDICTORS = c("age", "female"),
        OUTCOME_LEVELS = c("reference", "level_b", "level_c"),
        REFERENCE_LEVEL = "reference", ID = "id", IMPUTATION = "imp"
      ),
      target = "outcome", variable = "nominal", levels = c("reference", "level_b", "level_c"),
      coding = list(reference_level = "reference"), method = "multinom"
    ),
    propensity_binary = list(
      choices = list(
        TREATMENT = "treatment", PREDICTORS = c("age", "female"),
        TREATMENT_LEVELS = c("control", "treated"), TREATED_LEVEL = "treated",
        ID = "id", IMPUTATION = "imp"
      ),
      target = "treatment", variable = "treatment", levels = c("control", "treated"),
      coding = list(treated_level = "treated"), method = "logistic-MI"
    ),
    propensity_ordinal = list(
      choices = list(
        TREATMENT = "treatment_ordinal", PREDICTORS = c("age", "female"),
        TREATMENT_LEVELS = c("low", "middle", "high"), ID = "id", IMPUTATION = "imp"
      ),
      target = "treatment", variable = "treatment_ordinal", levels = c("low", "middle", "high"),
      coding = list(cumulative_direction = "P(Y <= level) = logistic(threshold - linear predictor)"),
      method = "ordinal-logistic-MI"
    ),
    propensity_nominal = list(
      choices = list(
        TREATMENT = "treatment_nominal", PREDICTORS = c("age", "female"),
        TREATMENT_LEVELS = c("reference", "level_b", "level_c"),
        REFERENCE_LEVEL = "reference", ID = "id", IMPUTATION = "imp"
      ),
      target = "treatment", variable = "treatment_nominal", levels = c("reference", "level_b", "level_c"),
      coding = list(reference_level = "reference"), method = "nominal-logistic-MI"
    ),
    balancing_count = list(
      choices = list(
        OUTCOME = "count", PREDICTORS = c("age", "female"), ID = "id", IMPUTATION = "imp",
        DISTRIBUTION = "poisson", N_STRATA = 5L
      ),
      target = "exposure", variable = "count", levels = NULL, coding = list(),
      method = "balancing-poisson-MI"
    )
  )

  for (qualifier in names(cases)) {
    case <- cases[[qualifier]]
    env <- new.env(parent = globalenv())
    env$d <- d
    env$SUBJECT <- "runtime"
    env$TYPE <- "metadata"
    env$.in <- file.path(tempdir(), paste0("lm-", qualifier, ".rmarkdown"))
    env$.provenance_data <- list()
    env$set_path <- function(kind, file) tempfile(fileext = ".rds")
    lm_run(qualifier, c("study-choices", "fit", "save"), env, case$choices)
    record <- capture_provenance(template_by_name(paste0("lm-", qualifier)), env)
    meta <- env$fit$meta
    status <- env$fit$tables$fit_status

    target <- record$extra$analysis[[case$target]]
    expect_identical(target$variable, case$variable, info = qualifier)
    if (!is.null(case$levels)) {
      expect_identical(target$accepted_levels, case$levels, info = qualifier)
      expect_identical(target$observed_levels, case$levels, info = qualifier)
    }
    for (field in names(case$coding)) {
      expect_identical(target[[field]], case$coding[[field]], info = qualifier)
    }
    expect_identical(record$extra$analysis$model$formula, paste(deparse(meta$formula), collapse = " "), info = qualifier)
    expect_identical(record$extra$analysis$model$family, meta$model_family, info = qualifier)
    expect_identical(record$extra$analysis$model$predictors, attr(stats::terms(meta$formula), "term.labels"), info = qualifier)
    expect_identical(record$extra$analysis$model$imputation,
                     list(variable = "imp", n = 2L, stacked = TRUE), info = qualifier)
    if (!is.null(case$method)) {
      expect_identical(record$extra$analysis$model$method, case$method, info = qualifier)
    } else {
      expect_null(record$extra$analysis$model$method, info = qualifier)
    }

    expect_identical(record$extra$cohort$count_unit, "stacked_imputation_rows", info = qualifier)
    expect_identical(record$extra$cohort$n_input, as.integer(sum(status$n_input)), info = qualifier)
    expect_identical(record$extra$cohort$n_analyzed, as.integer(sum(status$n_analyzed)), info = qualifier)
    expect_identical(record$extra$cohort$n_excluded, as.integer(sum(status$n_excluded)), info = qualifier)
    expect_identical(record$extra$cohort$n_unique_people_input, status$n_input[[1L]], info = qualifier)
    expect_identical(record$extra$cohort$by_imputation,
                     unname(lapply(seq_len(nrow(status)), function(i) {
                       as.list(status[i, c("imputation", "n_input", "n_analyzed", "n_excluded")])
                     })), info = qualifier)
    lineage <- attr(env$fit, "hvti_provenance", exact = TRUE)
    expect_identical(lineage$analysis, record$extra$analysis, info = qualifier)
    expect_identical(lineage$cohort, record$extra$cohort, info = qualifier)
  }
})

test_that("single-dataset logistic provenance reports rows without claiming unique people", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.7")
  env <- new.env(parent = globalenv())
  env$d <- lm_data()
  env$SUBJECT <- "runtime"
  env$TYPE <- "metadata"
  env$.in <- file.path(tempdir(), "lm-binary.rmarkdown")
  lm_run("binary", c("study-choices", "fit"), env, list(
    OUTCOME = "outcome", PREDICTORS = c("age", "female"),
    OUTCOME_LEVELS = c("none", "event"), EVENT_LEVEL = "event",
    ID = "id", IMPUTATION = NULL
  ))
  record <- capture_provenance(template_by_name("lm-binary"), env)
  status <- env$fit$tables$fit_status

  expect_identical(record$extra$cohort$count_unit, "rows")
  expect_identical(record$extra$cohort$n_input, status$n_input[[1L]])
  expect_identical(record$extra$cohort$n_analyzed, status$n_analyzed[[1L]])
  expect_identical(record$extra$cohort$n_excluded, status$n_excluded[[1L]])
  expect_identical(record$extra$cohort$by_imputation, list(as.list(status[1L, c(
    "imputation", "n_input", "n_analyzed", "n_excluded"
  )])))
  expect_null(record$extra$cohort$n_unique_people_input)
})

test_that("lm-checkpred separates carried training metadata from runtime validation metadata", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.7")
  root <- lm_study()
  cfg <- hvtiRutilities::study_config(root)
  d <- lm_data()
  model <- hvtiRpropensity::fit_logistic(
    outcome ~ age + female, d, family = "binary", outcome_col = "outcome",
    id_col = "id", outcome_levels = c("none", "event"), event_level = "event"
  )
  training_analysis <- list(outcome = list(variable = "outcome", event_level = "event"))
  training_cohort <- list(n_input = nrow(d), n_analyzed = nrow(d), n_excluded = 0L)
  model <- hvtiRtemplates:::.attach_handoff_lineage(
    model,
    data = list(hvtiRutilities::provenance_data(cfg = cfg, role = "training")),
    analysis = training_analysis,
    cohort = training_cohort
  )
  bundle_dir <- file.path(hvtiRutilities::study_dir("estimates", root), "outcome-analysis")
  dir.create(bundle_dir, recursive = TRUE)
  saveRDS(model, file.path(bundle_dir, "lm-binary.rds"))

  d$age[c(1L, 3L)] <- NA_real_
  env <- new.env(parent = globalenv())
  env$.root <- root
  env$d <- d
  env$.provenance_data <- list(hvtiRutilities::provenance_data(cfg = cfg, role = "validation"))
  env$set_path <- function(kind, file) file.path(bundle_dir, file)
  env$SUBJECT <- "runtime"
  env$TYPE <- "validation"
  env$.in <- file.path(root, "lm-checkpred.rmarkdown")
  lm_run("checkpred", c("study-choices", "model", "validate"), env,
         list(MODEL_FILE = "lm-binary.rds", OUTCOME = "outcome", GROUPS = 10L))
  record <- capture_provenance(template_by_name("lm-checkpred"), env)
  meta <- env$validation$meta

  expect_identical(record$extra$analysis$training, training_analysis)
  expect_identical(record$extra$analysis$validation$outcome, list(
    variable = meta$outcome_col,
    accepted_levels = meta$outcome_levels,
    observed_levels = meta$outcome_levels,
    event_level = meta$event_level
  ))
  expect_identical(record$extra$analysis$validation$model$formula,
                   paste(deparse(meta$formula), collapse = " "))
  expect_identical(record$extra$analysis$validation$model$family, meta$model_family)
  expect_identical(record$extra$analysis$validation$model$method, "glm.fit:binomial(logit)")
  expect_identical(record$extra$analysis$validation$model$predictors,
                   attr(stats::terms(meta$formula), "term.labels"))
  expect_identical(record$extra$cohort$training, training_cohort)
  expect_identical(record$extra$cohort$validation, list(
    count_unit = "validation_rows",
    n_input = meta$n_input,
    n_analyzed = meta$n_analyzed,
    n_excluded = meta$n_excluded
  ))
  expect_identical(vapply(record$data, `[[`, character(1L), "role"), c("training", "validation"))
  expect_identical(record$artifacts[[1L]]$role, "source-model")
})

test_that("event-time templates record local coding and observed counts", {
  event_names <- c(ac = "STATUS", hz = "STATUS", hm = "EVENT", hp = "EVENT", hs = "EVENT")
  for (prefix in names(event_names)) {
    chunk <- provenance_chunk(template_by_name(prefix))
    event <- event_names[[prefix]]
    expect_true(any(grepl("variable = TIME", chunk, fixed = TRUE)), info = prefix)
    expect_true(any(grepl(paste0("variable = ", event), chunk, fixed = TRUE)), info = prefix)
    expect_true(any(grepl("event = 1L", chunk, fixed = TRUE)), info = prefix)
    expect_true(any(grepl("censored = 0L", chunk, fixed = TRUE)), info = prefix)
    expect_true(any(grepl("cohort = cc", chunk, fixed = TRUE)), info = prefix)
  }
})

test_that("forest templates take analysis identity and counts from runtime objects", {
  for (prefix in c("rfs-fit", "rfs-explain", "rfc-fit", "rfc-explain", "rfr-fit", "rfr-explain")) {
    chunk <- provenance_chunk(template_by_name(prefix))
    expect_true(any(grepl("forest$yvar", chunk, fixed = TRUE)), info = prefix)
    expect_true(any(grepl("cohort =", chunk, fixed = TRUE)), info = prefix)
    expect_false(any(grepl("variable = SUBJECT", chunk, fixed = TRUE)), info = prefix)
  }
})

test_that("RF provenance chunks record the fitted objects they consume", {
  rf_cases <- list(
    rfs = list(
      data = function() {
        data_env <- new.env()
        utils::data("veteran", package = "randomForestSRC", envir = data_env)
        data_env$veteran
      },
      choices = list(
        TIME = "time", STATUS = "status",
        PREDICTORS = c("trt", "celltype", "karno", "diagtime", "age", "prior"), NTREE = 50, SEED = 1
      )
    ),
    rfc = list(
      data = function() {
        data <- datasets::iris[datasets::iris$Species != "setosa", ]
        data$Species <- as.character(data$Species)
        data
      },
      choices = list(
        RESPONSE = "Species",
        PREDICTORS = c("Sepal.Length", "Sepal.Width", "Petal.Length", "Petal.Width"),
        ROC_CLASS = "virginica", NTREE = 50, SEED = 1
      )
    ),
    rfr = list(
      data = function() datasets::airquality[!is.na(datasets::airquality$Ozone), ],
      choices = list(
        RESPONSE = "Ozone", PREDICTORS = c("Solar.R", "Wind", "Temp", "Month", "Day"),
        NTREE = 50, SEED = 1, NA_ACTION = "na.impute"
      )
    )
  )

  for (prefix in names(rf_cases)) {
    rf_skip_unless_stack(rf_template_packages(prefix, "fit"))
    case <- rf_cases[[prefix]]
    fit <- rf_env(case$data())
    suppressWarnings(rf_run(prefix, "fit", c("set", "study-choices", "read", "fit", "save"), fit, case$choices))
    fit$SUBJECT <- "provenance"
    fit$TYPE <- "fit"
    fit$.in <- file.path(fit$.root, paste0(prefix, "-fit.rmarkdown"))

    fit_record <- capture_provenance(template_by_name(paste0(prefix, "-fit")), fit)
    expect_identical(fit_record$input, fit$.in, info = prefix)

    explain <- new.env(parent = globalenv())
    explain$.root <- fit$.root
    rf_run(prefix, "explain", c("set", "study-choices", "forest"), explain)
    explain$SUBJECT <- "provenance"
    explain$TYPE <- "explain"
    explain$.in <- file.path(explain$.root, paste0(prefix, "-explain.rmarkdown"))

    explain_record <- capture_provenance(template_by_name(paste0(prefix, "-explain")), explain)
    expect_identical(explain_record$input, explain$.in,
                     info = prefix)

    records <- list(fit = list(record = fit_record, env = fit), explain = list(record = explain_record, env = explain))
    for (qualifier in names(records)) {
      record <- records[[qualifier]]$record
      env <- records[[qualifier]]$env
      expect_identical(record$extra$subject, "provenance", info = paste(prefix, qualifier))
      expect_identical(record$extra$type, qualifier, info = paste(prefix, qualifier))

      if (identical(prefix, "rfs")) {
        time <- if (identical(qualifier, "fit")) env$TIME else env$forest$yvar.names[[1L]]
        status <- if (identical(qualifier, "fit")) env$STATUS else env$forest$yvar.names[[2L]]
        event <- env$forest$yvar[[status]]
        expect_identical(record$extra$analysis$time$variable, time, info = qualifier)
        expect_identical(record$extra$analysis$event$variable, status, info = qualifier)
        expect_identical(record$extra$analysis$event$event, 1L, info = qualifier)
        expect_identical(record$extra$analysis$event$censored, 0L, info = qualifier)
        expect_identical(record$extra$cohort, list(
          n = as.integer(nrow(env$forest$yvar)),
          n_events = as.integer(sum(event == 1)),
          n_censored = as.integer(sum(event == 0))
        ), info = qualifier)
      } else {
        variable <- if (identical(qualifier, "fit")) env$RESPONSE else env$forest$yvar.names[[1L]]
        kind <- if (identical(prefix, "rfc")) "classification" else "continuous"
        expect_identical(record$extra$analysis$outcome$variable, variable, info = qualifier)
        expect_identical(record$extra$analysis$outcome$kind, kind, info = qualifier)
        expect_identical(record$extra$cohort, list(n = as.integer(length(env$forest$yvar))), info = qualifier)
        if (identical(prefix, "rfc")) {
          expect_identical(record$extra$analysis$outcome$observed_levels, levels(env$forest$yvar), info = qualifier)
          if (identical(qualifier, "fit")) {
            expect_identical(record$extra$analysis$outcome$target_level, env$ROC_CLASS)
          } else {
            expect_null(record$extra$analysis$outcome$target_level)
          }
        }
      }
    }
  }
})

test_that("event-time provenance chunks retain observed STATUS and EVENT cohorts", {
  cases <- list(
    ac = list(event = "STATUS", time = "TIME", data = data.frame(time = c(1, 2, NA), status = c(1, 0, 1))),
    hm = list(event = "EVENT", time = "TIME", data = data.frame(time = c(1, 2, 3), event = c(1, 0, 1)))
  )

  for (prefix in names(cases)) {
    case <- cases[[prefix]]
    cc <- hvtiRutilities::cohort_counts(case$data, event = tolower(case$event), time = tolower(case$time))
    env <- new.env(parent = globalenv())
    env$.in <- file.path(tempdir(), paste0(prefix, "-provenance.rmarkdown"))
    env$SUBJECT <- "provenance"
    env$TYPE <- "event-time"
    env$TIME <- tolower(case$time)
    env[[case$event]] <- tolower(case$event)
    env$cc <- cc

    record <- capture_provenance(template_by_name(prefix), env)
    expect_identical(record$input, env$.in, info = prefix)
    expect_identical(record$extra$analysis$time$variable, env$TIME, info = prefix)
    expect_identical(record$extra$analysis$event$variable, env[[case$event]], info = prefix)
    expect_identical(record$extra$cohort, cc, info = prefix)
  }
})

make_provenance_study <- function(root) {
  suppressMessages(hvtiRutilities::study_setup(
    root, "Provenance render", 42L, adopt = TRUE
  ))
  data <- data.frame(id = 1:3, dead = c(1L, 0L, 0L), iv_dead = 1:3)
  utils::write.csv(
    data,
    file.path(hvtiRutilities::study_dir("datasets", root), "cohort.csv"),
    row.names = FALSE
  )
  suppressMessages(hvtiRutilities::register_data(root, "cohort.csv"))
  .install_provenance_hooks(root)
  invisible(root)
}

write_provenance_job <- function(root, stem, prefix, definitions, output_file = NULL) {
  path <- file.path(root, paste0(stem, ".qmd"))
  chunk <- provenance_chunk(template_by_name(prefix))
  frontmatter <- c("---", "format: html")
  if (!is.null(output_file)) frontmatter <- c(frontmatter, paste0("output-file: ", output_file))
  writeLines(c(
    frontmatter, "---", "",
    "```{r}",
    ".in <- knitr::current_input(dir = TRUE)",
    ".cfg <- hvtiRutilities::study_config(start = Sys.getenv(\"QUARTO_PROJECT_DIR\"))",
    ".data_read <- hvtiRtemplates:::.provenance_read(",
    "  \"study\", .cfg, function() hvtiRutilities::read_built(cfg = .cfg)",
    ")",
    ".provenance_data <- list(.data_read$record)",
    definitions,
    "```", "",
    chunk
  ), path)
  path
}

render_provenance_job <- function(job, root, quiet = TRUE) {
  quarto::quarto_render(job, execute_dir = root, quiet = quiet)
}

test_that("an endpoint-free render writes a stem-matched sidecar without invented blocks", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available(), "Quarto CLI is required for rendering")
  root <- make_provenance_study(withr::local_tempdir())
  job <- write_provenance_job(
    root, "cohort-eda-dc-general", "dc-general",
    c('SUBJECT <- "cohort"', 'TYPE <- "eda"', 'DATASET <- "study"')
  )

  render_provenance_job(job, root)

  sidecar <- file.path(root, "cohort-eda-dc-general.provenance.json")
  record <- jsonlite::fromJSON(sidecar, simplifyVector = FALSE)
  expect_true(file.exists(file.path(root, "cohort-eda-dc-general.html")))
  expect_true(file.exists(sidecar))
  expect_identical(record$job, "cohort-eda-dc-general")
  expect_true(all(names(hvtiRutilities:::.provenance_required()) %in% names(record)))
  expect_identical(record$subject, "cohort")
  expect_identical(record$type, "eda")
  expect_false(any(c("analysis", "cohort") %in% names(record)))
})

test_that("an endpoint-driven render writes its local coding and observed cohort", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available(), "Quarto CLI is required for rendering")
  root <- make_provenance_study(withr::local_tempdir())
  job <- write_provenance_job(
    root, "death-hz-hz", "hz",
    c(
      'SUBJECT <- "death"', 'TYPE <- "hz"',
      'TIME <- "iv_dead"', 'STATUS <- "dead"',
      "cc <- list(n = 3L, n_events = 1L, n_censored = 2L)"
    )
  )

  render_provenance_job(job, root)

  record <- jsonlite::fromJSON(
    file.path(root, "death-hz-hz.provenance.json"),
    simplifyVector = FALSE
  )
  expect_identical(record$analysis$time$variable, "iv_dead")
  expect_identical(record$analysis$event$variable, "dead")
  expect_identical(record$analysis$event$event, 1L)
  expect_identical(record$analysis$event$censored, 0L)
  expect_identical(record$cohort, list(n = 3L, n_events = 1L, n_censored = 2L))
})

test_that("a sidecar write failure fails the render", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available(), "Quarto CLI is required for rendering")
  root <- make_provenance_study(withr::local_tempdir())
  job <- write_provenance_job(
    root, "cohort-eda-dc-general", "dc-general",
    c('SUBJECT <- "cohort"', 'TYPE <- "eda"', 'DATASET <- "study"')
  )
  dir.create(file.path(root, "cohort-eda-dc-general.provenance.json"))

  output <- capture.output(
    failure <- tryCatch(
      render_provenance_job(job, root, quiet = FALSE),
      error = identity
    )
  )
  expect_s3_class(failure, "error")
  expect_match(
    paste(output, collapse = "\n"),
    "publish_provenance\\(\\): could not (write|publish) the provenance sidecar"
  )
})

test_that("render_job publishes provenance through the same project hooks", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available(), "Quarto CLI is required for rendering")
  root <- make_provenance_study(withr::local_tempdir())
  job <- write_provenance_job(
    root, "cohort-wrapper-dc-general", "dc-general",
    c('SUBJECT <- "cohort"', 'TYPE <- "wrapper"', 'DATASET <- "study"')
  )

  render_job(job, quiet = TRUE)

  expect_true(file.exists(file.path(root, "cohort-wrapper-dc-general.provenance.json")))
})

test_that("direct Quarto supports its file-backed input and output lists", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available(), "Quarto CLI is required for rendering")
  root <- make_provenance_study(withr::local_tempdir())
  job <- write_provenance_job(
    root, "cohort-file-backed-dc-general", "dc-general",
    c('SUBJECT <- "cohort"', 'TYPE <- "file-backed"', 'DATASET <- "study"')
  )
  input_list <- tempfile("quarto-inputs-")
  output_list <- tempfile("quarto-outputs-")
  withr::local_envvar(
    QUARTO_USE_FILE_FOR_PROJECT_INPUT_FILES = input_list,
    QUARTO_USE_FILE_FOR_PROJECT_OUTPUT_FILES = output_list
  )

  render_provenance_job(job, root)

  expect_identical(readLines(input_list, warn = FALSE), basename(job))
  expect_identical(readLines(output_list, warn = FALSE), "cohort-file-backed-dc-general.html")
  expect_true(file.exists(file.path(root, "cohort-file-backed-dc-general.provenance.json")))
})

test_that("project renders publish renamed outputs and ignore unmanaged documents", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available(), "Quarto CLI is required for rendering")
  root <- make_provenance_study(withr::local_tempdir())
  first <- write_provenance_job(
    root, "cohort-first-dc-general", "dc-general",
    c('SUBJECT <- "cohort"', 'TYPE <- "first"', 'DATASET <- "study"'),
    output_file = "renamed-first.html"
  )
  second <- write_provenance_job(
    root, "cohort-second-dc-general", "dc-general",
    c('SUBJECT <- "cohort"', 'TYPE <- "second"', 'DATASET <- "study"')
  )
  unmanaged <- file.path(root, "notes.md")
  writeLines(c("---", "format: html", "---", "", "Ordinary project notes."), unmanaged)
  config <- yaml::read_yaml(file.path(root, "_quarto.yml"))
  config$project$`output-dir` <- "rendered"
  config$project$render <- list(basename(first), basename(second), basename(unmanaged))
  yaml::write_yaml(config, file.path(root, "_quarto.yml"))

  quarto::quarto_render(root, execute_dir = root, quiet = TRUE)

  expect_true(file.exists(file.path(root, "rendered", "renamed-first.html")))
  expect_true(file.exists(file.path(root, "rendered", "renamed-first.provenance.json")))
  expect_true(file.exists(file.path(root, "rendered", "cohort-second-dc-general.provenance.json")))
  expect_true(file.exists(file.path(root, "rendered", "notes.html")))
  expect_false(file.exists(file.path(root, "rendered", "notes.provenance.json")))
})

test_that("document-level frozen renders retain their original execution payload", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available(), "Quarto CLI is required for rendering")
  root <- make_provenance_study(withr::local_tempdir())
  job <- write_provenance_job(
    root, "cohort-frozen-dc-general", "dc-general",
    c('SUBJECT <- "cohort"', 'TYPE <- "frozen"', 'DATASET <- "study"')
  )
  source <- readLines(job, warn = FALSE)
  source <- append(source, c("execute:", "  freeze: true"), after = 1L)
  writeLines(source, job)
  config <- .read_quarto_config(file.path(root, "_quarto.yml"))
  config$project$render <- list(basename(job))
  .write_quarto_config(config, file.path(root, "_quarto.yml"))

  quarto::quarto_render(root, execute_dir = root, quiet = TRUE)
  sidecar <- file.path(root, "cohort-frozen-dc-general.provenance.json")
  first <- jsonlite::read_json(sidecar, simplifyVector = FALSE)
  quarto::quarto_render(root, execute_dir = root, quiet = TRUE)
  second <- jsonlite::read_json(sidecar, simplifyVector = FALSE)

  expect_identical(second$rendered, first$rendered)
})

test_that("a Pandoc failure after execution keeps the prior HTML-sidecar pair", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available(), "Quarto CLI is required for rendering")
  root <- make_provenance_study(withr::local_tempdir())
  job <- write_provenance_job(
    root, "cohort-pandoc-dc-general", "dc-general",
    c('SUBJECT <- "cohort"', 'TYPE <- "pandoc"', 'DATASET <- "study"')
  )
  render_provenance_job(job, root)
  html <- file.path(root, "cohort-pandoc-dc-general.html")
  sidecar <- file.path(root, "cohort-pandoc-dc-general.provenance.json")
  expect_true(file.exists(sidecar))
  html_before <- readBin(html, "raw", n = file.info(html)$size)
  sidecar_before <- readBin(sidecar, "raw", n = file.info(sidecar)$size)
  source <- readLines(job, warn = FALSE)
  source <- append(source, "filters: [missing-provenance-filter.lua]", after = 2L)
  writeLines(source, job)

  expect_error(render_provenance_job(job, root), "quarto CLI")
  expect_identical(readBin(html, "raw", n = file.info(html)$size), html_before)
  expect_identical(readBin(sidecar, "raw", n = file.info(sidecar)$size), sidecar_before)
})

test_that("existing later hooks run before publication so the checksum covers their changes", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available(), "Quarto CLI is required for rendering")
  root <- make_provenance_study(withr::local_tempdir())
  job <- write_provenance_job(
    root, "cohort-hook-dc-general", "dc-general",
    c('SUBJECT <- "cohort"', 'TYPE <- "hook"', 'DATASET <- "study"')
  )
  writeLines(c(
    'outputs <- strsplit(Sys.getenv("QUARTO_PROJECT_OUTPUT_FILES"), "\\n", fixed = TRUE)[[1L]]',
    'outputs <- outputs[tolower(tools::file_ext(outputs)) == "html"]',
    'for (path in outputs) write("<!-- later-user-hook -->", path, append = TRUE)'
  ), file.path(root, "later-hook.R"))
  config <- yaml::read_yaml(file.path(root, "_quarto.yml"))
  config$project$`post-render` <- c(config$project$`post-render`, "later-hook.R")
  yaml::write_yaml(config, file.path(root, "_quarto.yml"))
  .install_provenance_hooks(root)

  render_provenance_job(job, root)

  html <- file.path(root, "cohort-hook-dc-general.html")
  record <- jsonlite::read_json(hvtiRutilities::provenance_path(html), simplifyVector = FALSE)
  expect_true(any(grepl("later-user-hook", readLines(html, warn = FALSE), fixed = TRUE)))
  expect_identical(record$output$sha256, digest::digest(html, algo = "sha256", file = TRUE))
})

test_that("a managed standalone render without configured hooks fails", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available(), "Quarto CLI is required for rendering")
  root <- withr::local_tempdir()
  make_provenance_study(root)
  unlink(c(file.path(root, "_quarto.yml"), file.path(root, ".hvtiR")), recursive = TRUE)
  job <- write_provenance_job(
    root, "cohort-standalone-dc-general", "dc-general",
    c('SUBJECT <- "cohort"', 'TYPE <- "standalone"', 'DATASET <- "study"')
  )

  expect_error(render_provenance_job(job, root), "quarto CLI")
  expect_false(file.exists(file.path(root, "cohort-standalone-dc-general.provenance.json")))
})
