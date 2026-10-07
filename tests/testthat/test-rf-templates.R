# Survival data for rfs: randomForestSRC's own veteran set, status 0/1.
rfs_data <- function() {
  e <- new.env()
  utils::data("veteran", package = "randomForestSRC", envir = e)
  e$veteran
}
rfs_choices <- list(TIME = "time", EVENT = "status",
                    PREDICTORS = c("trt", "celltype", "karno", "diagtime", "age", "prior"),
                    NTREE = 50, SEED = 1)

test_that("rfs-fit grows a survival forest and saves the handoff", {
  rf_skip_unless_stack(rf_template_packages("rfs", "fit"))
  env <- rf_env(rfs_data())
  rf_run("rfs", "fit", c("set", "edit-study-choices", "tbl-data", "fit", "fig-diagnostics-error", "fig-diagnostics-survival",
                         "fig-diagnostics-brier", "save"), env, rfs_choices)

  expect_s3_class(env$forest, "rfsrc")
  expect_identical(env$forest$family, "surv")
  handoff <- file.path(env$CACHE_DIR, "rfs.rds")
  expect_true(file.exists(handoff))
  expect_true(file.exists(file.path(env$CACHE_DIR, "rfs-forest.rds")))
  # The handoff is the bare forest, not cache_fit()'s keyed record.
  expect_s3_class(readRDS(handoff), "rfsrc")
  for (p in list(env$err, env$surv, env$brier)) {
    expect_s3_class(ggplot2::ggplot_build(plot(p)), "ggplot_built")
  }
})

test_that("rfs-fit refuses a status that is not 0/1", {
  rf_skip_unless_stack(rf_template_packages("rfs", "fit"))
  d <- rfs_data()
  d$status <- d$status + 1L   # 1/2 coding: randomForestSRC would read 2 as a competing event
  env <- rf_env(d)
  expect_error(rf_run("rfs", "fit", c("set", "edit-study-choices", "tbl-data"), env, rfs_choices),
               "0 and 1")
})

test_that("rfs-fit refuses a patient with no outcome", {
  rf_skip_unless_stack(rf_template_packages("rfs", "fit"))
  d <- rfs_data()
  d$time[3] <- NA
  env <- rf_env(d)
  expect_error(rf_run("rfs", "fit", c("set", "edit-study-choices", "tbl-data"), env, rfs_choices),
               "no time or status")
})

test_that("rfs-fit refuses outcomes and duplicate names among predictors", {
  rf_skip_unless_stack(rf_template_packages("rfs", "fit"))
  for (outcome in c("time", "status")) {
    env <- rf_env(rfs_data())
    expect_error(
      rf_run("rfs", "fit", c("set", "edit-study-choices", "tbl-data"), env,
             utils::modifyList(rfs_choices, list(PREDICTORS = c(outcome, "age")))),
      "outcome.*PREDICTORS",
      info = outcome
    )
  }

  env <- rf_env(rfs_data())
  expect_error(
    rf_run("rfs", "fit", c("set", "edit-study-choices", "tbl-data"), env,
           utils::modifyList(rfs_choices, list(PREDICTORS = c("age", "age")))),
    "PREDICTORS.*more than once"
  )
})

test_that("rf_skip_unless_stack does not error on a package with no floor", {
  # "utils" is always installed and has no row in rf_pkg_floors, so this
  # exercises the no-floor fallback -- the branch a `[[` lookup made
  # unreachable, since it throws "subscript out of bounds" for a missing
  # name instead of the NA that `[` returns.
  expect_no_error(rf_skip_unless_stack("utils"))
  expect_no_condition(rf_skip_unless_stack("utils"), class = "skip")
})

# Each figure and table is a chunk of its own, so the report's outputs are listed one by one.
dependence_labels <- c("fig-dependence-marginal", "fig-dependence-partial", "fig-dependence-varpro")
explain_labels <- c("set", "edit-study-choices", "forest", "fig-importance", "tbl-importance", "select", "fig-varpro",
                    dependence_labels)

rfs_explain_choices <- list(TOP_K = 2, TIMES = c(30, 90), SEED = 1)

# A survival forest grown and explained once for this file, since an explain
# is the slowest thing it runs: the first test that needs it builds it, and the
# study is removed when the test run ends. A test that changes the study's
# caches works on a copy of it, from rfs_explained_copy(), so the tests stay
# independent of their order. The helpers it calls are defined in helper-rf.R,
# which object_usage_linter cannot see from here.
rfs_explained_cache <- new.env()
# nolint start: object_usage_linter.
rfs_explained <- function() {
  if (is.null(rfs_explained_cache$env)) {
    fit_env <- rf_fit_first("rfs", rfs_data(), rfs_choices, .local_envir = testthat::teardown_env())
    env <- new.env(parent = globalenv())
    env$.root <- fit_env$.root
    rf_run("rfs", "explain", explain_labels, env, rfs_explain_choices)
    rfs_explained_cache$env <- env
  }
  rfs_explained_cache$env
}
# nolint end

# A copy of the shared study, with the caches its explain left, removed when
# `.local_envir` ends.
rfs_explained_copy <- function(.local_envir = parent.frame()) {
  dest <- withr::local_tempdir("rf-study-copy-", .local_envir = .local_envir)
  root <- rfs_explained()$.root
  stopifnot(all(file.copy(list.files(root, all.files = TRUE, full.names = TRUE, no.. = TRUE), dest, recursive = TRUE)))
  normalizePath(dest)
}

test_that("rfs-explain explains the saved forest without refitting", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("rfs", "explain"))
  env <- rfs_explained()

  expect_identical(names(env$frame), c(env$forest$yvar.names, env$forest$xvar.names))
  expect_length(env$sel, 2L)
  expect_identical(env$sel, head(env$ranked, 2L))
  for (nm in c("rfs-vimp", "rfs-varpro", "rfs-partial", "rfs-partial-varpro")) {
    expect_true(file.exists(file.path(env$CACHE_DIR, paste0(nm, ".rds"))), info = nm)
  }
  for (p in list(ggRandomForests::gg_vimp(env$vi), ggRandomForests::gg_varpro(env$vp), env$pd, env$pv)) {
    expect_s3_class(ggplot2::ggplot_build(plot(p)), "ggplot_built")
  }
})

test_that("rfs-explain stops when no fit has run in its set", {
  rf_skip_unless_stack(rf_template_packages("rfs", "explain"))
  env <- new.env(parent = globalenv())
  env$.root <- rf_study()
  expect_error(rf_run("rfs", "explain", c("set", "edit-study-choices", "forest"), env),
               "Render the rfs-fit job in this set first")
})

test_that("a changed TOP_K makes only the partial caches stale", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("rfs", "explain"))
  # The copy carries the caches an explain at TOP_K = 2 left.
  root <- rfs_explained_copy()
  choices <- rfs_explain_choices

  choices$TOP_K <- 3
  again <- new.env(parent = globalenv())
  again$.root <- root
  rf_run("rfs", "explain", c("set", "edit-study-choices", "forest", "fig-importance", "tbl-importance", "select", "fig-varpro"),
         again, choices)
  # "only" is the claim under test: the error must name rfs-partial, the
  # cache the dependence chunk hits first, not merely be A stale-cache error,
  # which any cache going stale for any reason would also satisfy.
  expect_error(rf_run("rfs", "explain", dependence_labels, again),
               regexp = "rfs-partial", class = "hvtiRutilities_stale_cache")

  again$REFIT <- TRUE
  rf_run("rfs", "explain", dependence_labels, again)
  # again$sel is unchanged since the earlier `select` chunk (the `dependence`
  # chunk never touches it), so asserting on it would be tautological. The
  # recomputed partial (a gg_partial_rfsrc list of $continuous/$categorical
  # frames, one row per variable/level) is what REFIT actually produces.
  pd_vars <- unique(c(as.character(again$pd$continuous$name), as.character(again$pd$categorical$name)))
  expect_length(pd_vars, 3L)
})

test_that("PARTIAL_VARS names the dependence variables explicitly", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("rfs", "explain"))
  # The shared study's importance and VarPro caches are reused; its partials,
  # computed for the TOP_K choice, go, so these are computed for PARTIAL_VARS.
  root <- rfs_explained_copy()
  unlink(list.files(root, "^rfs-partial", recursive = TRUE, full.names = TRUE))
  env <- new.env(parent = globalenv())
  env$.root <- root
  # Not the two TOP_K picks (karno, celltype), so the choice is visibly the
  # setting's; one is categorical, whose partial is cheap beside a continuous one.
  chosen <- c("age", "celltype")
  rf_run("rfs", "explain", explain_labels, env,
         list(PARTIAL_VARS = chosen, TIMES = c(30, 90), SEED = 1))

  expect_identical(env$sel, chosen)
  pd_vars <- unique(c(as.character(env$pd$continuous$name), as.character(env$pd$categorical$name)))
  expect_setequal(pd_vars, chosen)
})

test_that("PARTIAL_VARS refuses a variable the forest was not grown on", {
  rf_skip_unless_stack(rf_template_packages("rfs", "explain"))
  env <- new.env(parent = globalenv())
  env$.root <- rfs_explained_copy()
  expect_error(
    rf_run("rfs", "explain", c("set", "edit-study-choices", "forest", "fig-importance", "tbl-importance", "select"), env,
           list(PARTIAL_VARS = "not_a_variable", SEED = 1)),
    "not grown on"
  )
})

# Classification data for rfc: two iris species, so the outcome is binary as
# most clinical classification outcomes are.
rfc_data <- function() {
  d <- datasets::iris[datasets::iris$Species != "setosa", ]
  d$Species <- as.character(d$Species)   # the fit must make it a factor itself
  d
}
rfc_choices <- list(RESPONSE = "species",
                    PREDICTORS = c("sepal.length", "sepal.width", "petal.length", "petal.width"),
                    ROC_CLASS = "virginica", NTREE = 50, SEED = 1)

test_that("rfc-fit grows a classification forest from a character outcome", {
  rf_skip_unless_stack(rf_template_packages("rfc", "fit"))
  env <- rf_env(rfc_data())
  rf_run("rfc", "fit", c("set", "edit-study-choices", "tbl-data", "fit", "fig-diagnostics-error", "fig-diagnostics-roc",
                         "diagnostics-auc", "save"), env, rfc_choices)
  expect_identical(env$forest$family, "class")
  expect_true(file.exists(file.path(env$CACHE_DIR, "rfc.rds")))
  expect_true(is.numeric(env$auc) && env$auc > 0.5)
  for (p in list(env$err, env$roc)) expect_s3_class(ggplot2::ggplot_build(plot(p)), "ggplot_built")
})

test_that("rfc-fit selects the named ROC class regardless of factor order", {
  rf_skip_unless_stack(rf_template_packages("rfc", "fit"))
  d <- rfc_data()
  d$Species <- factor(d$Species, levels = c("virginica", "versicolor"))
  choices <- utils::modifyList(rfc_choices, list(ROC_CLASS = "virginica"))
  env <- rf_env(d)
  rf_run("rfc", "fit", c("set", "edit-study-choices", "tbl-data", "fit", "fig-diagnostics-error", "fig-diagnostics-roc",
                         "diagnostics-auc"), env, choices)

  expected <- ggRandomForests::gg_roc(env$forest, which_outcome = 1L)
  expect_equal(as.data.frame(env$roc), as.data.frame(expected))
})

test_that("rfc-fit refuses an unknown ROC class", {
  rf_skip_unless_stack(rf_template_packages("rfc", "fit"))
  env <- rf_env(rfc_data())
  choices <- utils::modifyList(rfc_choices, list(ROC_CLASS = "not-a-species"))
  expect_error(
    rf_run("rfc", "fit", c("set", "edit-study-choices", "tbl-data"), env, choices),
    "ROC_CLASS.*not an observed level"
  )
})

test_that("rfc-fit refuses its untouched ROC class choice for a 0/1 outcome", {
  rf_skip_unless_stack(rf_template_packages("rfc", "fit"))
  d <- rfc_data()
  d$event <- as.integer(d$Species == "virginica")
  choices <- rfc_choices[names(rfc_choices) != "ROC_CLASS"]
  choices$RESPONSE <- "event"
  env <- rf_env(d)
  expect_error(
    rf_run("rfc", "fit", c("set", "edit-study-choices", "tbl-data"), env, choices),
    "ROC_CLASS"
  )
})

test_that("rfc-fit refuses its outcome and duplicate names among predictors", {
  rf_skip_unless_stack(rf_template_packages("rfc", "fit"))
  env <- rf_env(rfc_data())
  expect_error(
    rf_run("rfc", "fit", c("set", "edit-study-choices", "tbl-data"), env,
           utils::modifyList(rfc_choices, list(PREDICTORS = c("species", "sepal.length")))),
    "outcome.*PREDICTORS"
  )

  env <- rf_env(rfc_data())
  expect_error(
    rf_run("rfc", "fit", c("set", "edit-study-choices", "tbl-data"), env,
           utils::modifyList(rfc_choices, list(PREDICTORS = c("sepal.length", "sepal.length")))),
    "PREDICTORS.*more than once"
  )
})

test_that("rfc-explain ranks by overall importance, not per class", {
  rf_skip_unless_stack(rf_template_packages("rfc", "explain"))
  fit_env <- rf_fit_first("rfc", rfc_data(), rfc_choices)
  env <- new.env(parent = globalenv())
  env$.root <- fit_env$.root
  rf_run("rfc", "explain", explain_labels, env, list(TOP_K = 2, SEED = 1))
  expect_false(anyDuplicated(env$ranked) > 0)
  expect_length(env$sel, 2L)
  for (p in list(env$pd, env$pv)) expect_s3_class(ggplot2::ggplot_build(plot(p)), "ggplot_built")
})

test_that("no explain template grows a forest", {
  # The design's central promise: an explanation describes the forest the fit
  # job saved. A refit here, however helpful it looks when the handoff is
  # missing, would explain a different forest in a report that says otherwise.
  #
  # A plain \brfsrc\( misses several forest-growing entry points a study
  # author could reach for just as easily: rfsrc.fast() (the one someone
  # would use on a slow study), imbalanced(), sidClustering() and
  # tune.rfsrc(), which all grow forests internally, plus a call written as
  # `rfsrc (x, y)` with a stray space or wrapped in do.call("rfsrc", ...).
  # \\s* before the paren covers the spaced form; the do.call alternative
  # covers the string-dispatched one.
  grow_fns <- c("rfsrc", "rfsrc\\.fast", "imbalanced", "sidClustering", "tune\\.rfsrc")
  direct <- paste0("\\b(", paste(grow_fns, collapse = "|"), ")\\s*\\(")
  via_do_call <- paste0("do\\.call\\(\\s*[\"'](", paste(grow_fns, collapse = "|"), ")[\"']")
  grows_forest <- paste0(direct, "|", via_do_call)

  templates <- grep("-explain[.]qmd$", template_list()$file, value = TRUE)
  # A found-nothing loop makes zero assertions, which testthat reports as an
  # empty test (a silent SKIP) rather than a failure. This keeps the test
  # from going vacuous if the explain templates are ever renamed or moved.
  expect_true(length(templates) > 0)
  for (f in templates) {
    code <- sub("#.*$", "", readLines(f, warn = FALSE))
    expect_false(any(grepl(grows_forest, code)), info = basename(f))
  }
})

# Regression data for rfr: airquality's Ozone against the other columns, with
# the rows missing an outcome dropped -- na.impute below covers the predictors.
rfr_data <- function() datasets::airquality[!is.na(datasets::airquality$Ozone), ]
rfr_choices <- list(RESPONSE = "ozone", PREDICTORS = c("solar.r", "wind", "temp", "month", "day"),
                    NTREE = 50, SEED = 1, NA_ACTION = "na.impute")

test_that("rfr-fit grows a regression forest, imputing missing predictors", {
  rf_skip_unless_stack(rf_template_packages("rfr", "fit"))
  env <- rf_env(rfr_data())
  rf_run("rfr", "fit", c("set", "edit-study-choices", "tbl-data", "fit", "fig-diagnostics-error", "fig-diagnostics-predicted",
                         "save"), env, rfr_choices)
  expect_identical(env$forest$family, "regr")
  expect_identical(env$forest$n, nrow(rfr_data()))   # na.impute kept every patient
  expect_true(file.exists(file.path(env$CACHE_DIR, "rfr.rds")))
  for (p in list(env$err, env$pred)) expect_s3_class(ggplot2::ggplot_build(plot(p)), "ggplot_built")
})

test_that("rfr-fit refuses a non-numeric outcome", {
  rf_skip_unless_stack(rf_template_packages("rfr", "fit"))
  d <- rfr_data()
  d$Ozone <- factor(d$Ozone)
  env <- rf_env(d)
  expect_error(rf_run("rfr", "fit", c("set", "edit-study-choices", "tbl-data"), env, rfr_choices), "must be numeric")
})

test_that("rfr-fit refuses its outcome and duplicate names among predictors", {
  rf_skip_unless_stack(rf_template_packages("rfr", "fit"))
  env <- rf_env(rfr_data())
  expect_error(
    rf_run("rfr", "fit", c("set", "edit-study-choices", "tbl-data"), env,
           utils::modifyList(rfr_choices, list(PREDICTORS = c("ozone", "wind")))),
    "outcome.*PREDICTORS"
  )

  env <- rf_env(rfr_data())
  expect_error(
    rf_run("rfr", "fit", c("set", "edit-study-choices", "tbl-data"), env,
           utils::modifyList(rfr_choices, list(PREDICTORS = c("wind", "wind")))),
    "PREDICTORS.*more than once"
  )
})

test_that("rfr-explain runs VarPro on a forest grown with missing predictors", {
  rf_skip_unless_stack(rf_template_packages("rfr", "explain"))
  fit_env <- rf_fit_first("rfr", rfr_data(), rfr_choices)
  env <- new.env(parent = globalenv())
  env$.root <- fit_env$.root
  # varPro 3.3.0 warns that it drops the rows with missing values; 3.2.0, the
  # floor, drops them silently. Muffle that one message so the test holds on
  # both and any other warning still reaches the summary.
  withCallingHandlers(
    rf_run("rfr", "explain", explain_labels, env, list(TOP_K = 2, SEED = 1)),
    warning = function(w) {
      if (grepl("^varpro\\(\\): omitted [0-9]+ of [0-9]+ observations with missing values",
                conditionMessage(w))) invokeRestart("muffleWarning")
    }
  )
  expect_true(anyNA(env$frame))   # the raw training data, not imputed.data
  expect_s3_class(env$vp, "varpro")
  for (p in list(env$pd, env$pv)) expect_s3_class(ggplot2::ggplot_build(plot(p)), "ggplot_built")
})

# ---- The data contract: read_job_data(), WHERE, ID and KEY ---------------------

rf_prefixes <- c("rfs", "rfc", "rfr")

test_that("every fit reads the rows WHERE keeps and leaves the ID out of the forest", {
  data <- rf_mrn_data(id = "ccfid")
  for (prefix in rf_prefixes) {
    rf_skip_unless_stack(rf_template_packages(prefix, "fit"))
    fit <- rf_fit_in(prefix, data, new.env(parent = globalenv()),
                     rf_mrn_choices(prefix, WHERE = quote(age >= 40)))
    expect_identical(fit$forest$n, sum(data$age >= 40), info = prefix)
    expect_true("ccfid" %in% names(fit$job_data$data), info = prefix)
    expect_identical(fit$forest$xvar.names, c("age", "x1", "grp"), info = prefix)
    selection <- attr(readRDS(file.path(fit$dir, paste0(prefix, ".rds"))), "hvti_provenance")$selection
    expect_identical(selection$where, "age >= 40", info = prefix)
    expect_identical(selection$id, "ccfid", info = prefix)
    expect_identical(selection$rows, sum(data$age >= 40), info = prefix)
  }
})

test_that("every fit refuses the patient identifier or a KEY column among its predictors", {
  data <- rf_mrn_data()
  for (prefix in rf_prefixes) {
    rf_skip_unless_stack(rf_template_packages(prefix, "fit"))
    # The ID fell back to MRN, which the data read names in lower case; the
    # predictor is refused however it is spelled.
    for (spelling in c("mrn", "MRN")) {
      env <- rf_env(data)
      expect_error(
        rf_run(prefix, "fit", c("set", "edit-study-choices", "tbl-data"), env,
               rf_mrn_choices(prefix, PREDICTORS = c("age", spelling))),
        paste0("patient identifier or a KEY column in PREDICTORS: ", spelling),
        info = paste(prefix, spelling)
      )
    }
    env <- rf_env(data)
    expect_error(
      rf_run(prefix, "fit", c("set", "edit-study-choices", "tbl-data"), env,
             rf_mrn_choices(prefix, KEY = c("mrn", "x1"))),
      "patient identifier or a KEY column in PREDICTORS: x1",
      info = prefix
    )
  }
})

test_that("every fit converts a text predictor to a factor and names it (#181)", {
  data <- rf_mrn_data(id = "ccfid")
  expect_type(data$grp, "character")
  for (prefix in rf_prefixes) {
    rf_skip_unless_stack(rf_template_packages(prefix, "fit"))
    env <- rf_env(data)
    printed <- utils::capture.output(
      rf_run(prefix, "fit", c("set", "edit-study-choices", "tbl-data"), env, rf_mrn_choices(prefix))
    )
    expect_identical(printed, "Text predictors converted to factors: grp", info = prefix)
    expect_s3_class(env$d$grp, "factor")
    expect_identical(levels(env$d$grp), c("a", "b", "c"), info = prefix)
    # Nothing is said when there is nothing to convert.
    env <- rf_env(data)
    printed <- utils::capture.output(
      rf_run(prefix, "fit", c("set", "edit-study-choices", "tbl-data"), env,
             rf_mrn_choices(prefix, PREDICTORS = c("age", "x1")))
    )
    expect_identical(printed, character(), info = prefix)
  }
})

test_that("every explain takes the fit's selection and stops on a setting that differs", {
  data <- rf_mrn_data(id = "ccfid")
  labels <- c("set", "edit-study-choices", "forest", "tbl-data")
  for (prefix in rf_prefixes) {
    rf_skip_unless_stack(rf_template_packages(prefix, "explain"))
    fit <- rf_fit_in(prefix, data, new.env(parent = globalenv()),
                     rf_mrn_choices(prefix, WHERE = quote(age >= 40)))
    explain <- function(choices = list()) {
      env <- new.env(parent = globalenv())
      env$.root <- fit$root
      rf_run(prefix, "explain", labels, env, choices)
    }
    env <- explain()
    expect_identical(env$.sel$id, "ccfid", info = prefix)
    expect_identical(env$.sel$key, "ccfid", info = prefix)
    expect_identical(env$.sel$where, "age >= 40", info = prefix)
    expect_identical(env$.sel$rows, sum(data$age >= 40), info = prefix)
    # Set to the fit's value, a setting only confirms it.
    expect_no_error(explain(list(WHERE = quote(age >= 40), ID = "ccfid", KEY = "ccfid")))
    expect_error(explain(list(WHERE = quote(age >= 65))),
                 "WHERE here \\(age >= 65\\) differs from the upstream job's \\(age >= 40\\)", info = prefix)
    expect_error(explain(list(ID = "randid")),
                 "ID here \\(randid\\) differs from the upstream job's \\(ccfid\\)", info = prefix)
    expect_error(explain(list(KEY = c("ccfid", "age"))), "KEY here .* differs from the upstream job's", info = prefix)
  }
})

test_that("every explain stops on a forest saved before the data contract, naming the file", {
  data <- rf_mrn_data(id = "ccfid")
  for (prefix in rf_prefixes) {
    rf_skip_unless_stack(rf_template_packages(prefix, "explain"))
    fit <- rf_fit_in(prefix, data, new.env(parent = globalenv()))
    handoff <- file.path(fit$dir, paste0(prefix, ".rds"))
    forest <- readRDS(handoff)
    attr(forest, "hvti_provenance")$selection <- NULL
    saveRDS(forest, handoff)
    env <- new.env(parent = globalenv())
    env$.root <- fit$root
    # The forest itself is still read: it is the data chunk that stops.
    rf_run(prefix, "explain", c("set", "edit-study-choices", "forest"), env)
    expect_error(rf_run(prefix, "explain", "tbl-data", env),
                 paste0("\\(", prefix, "[.]rds\\) carries no single recorded data selection: it predates the data contract"),
                 info = prefix)
  }
})

# ---- #203: no saved forest carries a patient identifier ------------------------

test_that("the fit and explain jobs keyed on MRN save no MRN in any file", {
  skip_on_cran()
  data <- rf_mrn_data(n = 60L)   # 60 patients search as surely as 120, in half the time
  for (prefix in rf_prefixes) {
    rf_skip_unless_stack(rf_template_packages(prefix, "explain"))
    fit <- rf_fit_in(prefix, data, globalenv())
    # The ID fell back to MRN, and the job read it.
    expect_identical(attr(fit$job_data$record, "selection")$id, "mrn", info = prefix)
    expect_true("mrn" %in% names(fit$job_data$data), info = prefix)
    expect_setequal(list.files(fit$dir), paste0(prefix, c(".rds", "-forest.rds", "-forest.provenance.json")))
    expect_identical(rf_files_holding(fit$dir, data$MRN), character(), info = prefix)
    # The explain job's caches sit beside the forest and are searched with it.
    caches <- rf_explain_in(prefix, fit$root, globalenv())
    expect_true(all(paste0(prefix, c("-vimp.rds", "-varpro.rds", "-partial.rds", "-partial-varpro.rds")) %in% caches),
                info = prefix)
    expect_identical(rf_files_holding(fit$dir, data$MRN), character(), info = prefix)
    # The search finds what is there: every MRN in the data as the job read it.
    read <- serialize(fit$job_data$data, NULL)
    expect_true(all(vapply(data$MRN, function(v) rf_bytes_hold(read, v), logical(1L))), info = prefix)
    # And the one-scan search the file checks use finds them too.
    expect_true(rf_bytes_hold_any(read, data$MRN), info = prefix)
  }
})

test_that("the fit and explain jobs save no MRN when their chunks run outside the global environment", {
  skip_on_cran()
  data <- rf_mrn_data(n = 60L)
  for (prefix in rf_prefixes) {
    rf_skip_unless_stack(rf_template_packages(prefix, "explain"))
    # A chunk environment that is not the global one is serialized in full,
    # `job_data` and its MRN column included, by anything saved that refers to
    # it: a formula, a function, a captured call.
    fit <- rf_fit_in(prefix, data, new.env(parent = globalenv()))
    expect_true("mrn" %in% names(fit$job_data$data), info = prefix)
    expect_identical(rf_files_holding(fit$dir, data$MRN), character(), info = prefix)
    caches <- rf_explain_in(prefix, fit$root, new.env(parent = globalenv()))
    expect_length(grep("[.]rds$", caches), 4L)
    expect_identical(rf_files_holding(fit$dir, data$MRN), character(), info = prefix)
  }
})

test_that("a run in the global environment puts back what it replaced there", {
  rf_skip_unless_stack(rf_template_packages("rfr", "fit"))
  env <- globalenv()
  withr::defer(rm(list = intersect(c("d", "forest"), ls(env)), envir = env))
  assign("d", "mine", envir = env)
  names_before <- ls(env, all.names = TRUE)
  local(rf_fit_in("rfr", rf_mrn_data(), env))
  expect_identical(get("d", envir = env), "mine")
  expect_setequal(setdiff(ls(env, all.names = TRUE), ".Random.seed"), setdiff(names_before, ".Random.seed"))
})

test_that("every fit refuses the patient identifier as its outcome", {
  data <- rf_mrn_data()
  outcomes <- list(rfs = c("TIME", "EVENT"), rfc = "RESPONSE", rfr = "RESPONSE")
  for (prefix in rf_prefixes) {
    rf_skip_unless_stack(rf_template_packages(prefix, "fit"))
    for (setting in outcomes[[prefix]]) {
      for (spelling in c("mrn", "MRN")) {
        env <- rf_env(data)
        choices <- rf_mrn_choices(prefix)
        choices[[setting]] <- spelling
        expect_error(rf_run(prefix, "fit", c("set", "edit-study-choices", "tbl-data"), env, choices),
                     paste0("patient identifier \\(mrn\\) cannot be an outcome"),
                     info = paste(prefix, setting, spelling))
      }
    }
    # A KEY column that is not the ID, a visit time say, may be the outcome.
    env <- rf_env(data)
    outcome <- if (identical(prefix, "rfs")) "iv_dead" else "los"
    choices <- rf_mrn_choices(prefix, KEY = c("mrn", outcome))
    if (identical(prefix, "rfc")) choices <- utils::modifyList(choices, list(RESPONSE = "los", ROC_CLASS = NA_character_))
    if (identical(prefix, "rfc")) {
      # los is not a class, so rfc stops later, at ROC_CLASS, not at the KEY column.
      expect_error(rf_run(prefix, "fit", c("set", "edit-study-choices", "tbl-data"), env, choices), "ROC_CLASS", info = prefix)
    } else {
      expect_no_error(utils::capture.output(rf_run(prefix, "fit", c("set", "edit-study-choices", "tbl-data"), env, choices)))
    }
  }
})
