test_that("rhf-fit tunes, grows a hazard forest and saves the handoff", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("rhf", "fit"))
  env <- rhf_fit_first()
  expect_s3_class(env$forest, "rhf")
  expect_s3_class(env$tuned, "tune.treesize.rhf")
  for (nm in c("rhf.rds", "rhf-forest.rds", "rhf-treesize.rds")) {
    expect_true(file.exists(file.path(env$CACHE_DIR, nm)), info = nm)
  }
  saved <- readRDS(file.path(env$CACHE_DIR, "rhf.rds"))
  expect_s3_class(saved, "rhf")
  lineage <- attr(saved, "hvti_provenance")
  expect_identical(lineage$analysis$event$variable, "event")
  expect_length(lineage$analysis$repair, 0L)
  expect_identical(lineage$analysis$lookahead$action, "keep")
  # The saved forest and both caches hold every patient's intervals, so only their owner may read them.
  if (.Platform$OS.type != "windows") {
    for (nm in c("rhf.rds", "rhf-forest.rds", "rhf-treesize.rds")) {
      expect_identical(format(file.mode(file.path(env$CACHE_DIR, nm))), "600", info = nm)
    }
  }
  expect_s3_class(ggplot2::ggplot_build(plot(ggRandomForests::gg_tune_rhf(env$tuned))), "ggplot_built")
})

test_that("rhf-fit skips the search when TREESIZE is a number", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("rhf", "fit"))
  env <- rhf_fit_first(choices = utils::modifyList(rhf_choices, list(TREESIZE = 5L)))
  expect_null(env$tuned)
  expect_false(file.exists(file.path(env$CACHE_DIR, "rhf-treesize.rds")))
})

test_that("a saved rhf forest holds no study id", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("rhf", "fit"))
  d <- rhf_data()
  env <- rhf_fit_first(d)
  bytes <- rf_rds_bytes(file.path(env$CACHE_DIR, "rhf.rds"))
  for (id in unique(d$ccfid)) expect_false(rf_bytes_hold(bytes, id), info = format(id, scientific = FALSE))
  # Every file the fit cached, the tree-size search and the forest alike, not only the saved one.
  expect_identical(rf_files_holding(env$CACHE_DIR, unique(d$ccfid)), character())
  # The scan finds the ids in a file known to hold them, so a clean result above is not an empty search.
  known <- withr::local_tempdir()
  saveRDS(d, file.path(known, "rows.rds"))
  expect_identical(rf_files_holding(known, unique(d$ccfid)), "rows.rds")
})

test_that("rhf-fit stops on an overlap, and REPAIR clips it in a draft only", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("rhf", "fit"))
  d <- rhf_data()
  first <- which(d$ccfid == d$ccfid[[1L]])
  d$start[first[2L]] <- d$start[first[2L]] - 1e-3
  env <- rf_env(d)
  expect_error(rf_run("rhf", "fit", c("setup", "edit-study-choices", "tbl-data", "tbl-cohort"), env, rhf_choices),
               "1 overlapping interval")
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "")
  env <- rf_env(d)
  out <- utils::capture.output(rf_run("rhf", "fit", c("setup", "edit-study-choices", "tbl-data", "tbl-cohort", "repair"),
                                      env, utils::modifyList(rhf_choices, list(REPAIR = "clip"))))
  expect_true(any(grepl("DRAFT -- rows repaired in the job", out, fixed = TRUE)))
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "1")
  env <- rf_env(d)
  expect_error(rf_run("rhf", "fit", c("setup", "edit-study-choices", "tbl-data", "tbl-cohort", "repair"),
                      env, utils::modifyList(rhf_choices, list(REPAIR = "clip"))),
               "HVTI_TEMPLATE_STRICT")
})

test_that("rhf-fit refuses a WHERE on a time-varying column", {
  rf_skip_unless_stack(rf_template_packages("rhf", "fit"))
  env <- rf_env(rhf_data())
  expect_error(rf_run("rhf", "fit", c("setup", "edit-study-choices", "tbl-data"), env,
                      utils::modifyList(rhf_choices, list(WHERE = quote(start > 0)))),
               "lost some of their rows")
})

test_that("rhf-fit refuses a predictor named like the forest's own columns", {
  rf_skip_unless_stack(rf_template_packages("rhf", "fit"))
  d <- rhf_data()
  d$id <- 1
  env <- rf_env(d)
  expect_error(rf_run("rhf", "fit", c("setup", "edit-study-choices", "tbl-data"), env,
                      utils::modifyList(rhf_choices, list(PREDICTORS = c("xtd", "id")))),
               "may not name a column id, start, stop or event")
})

rhf_cleanup_labels <- c("setup", "edit-study-choices", "tbl-data", "cap", "tbl-cohort", "repair", "tbl-lookahead")

test_that("rhf-fit caps a predictor's tail and refuses a cap on a column it does not use", {
  rf_skip_unless_stack(rf_template_packages("rhf", "fit"))
  d <- rhf_data()
  cap <- stats::median(d$x_1)
  env <- rf_env(d)
  out <- utils::capture.output(rf_run("rhf", "fit", rhf_cleanup_labels, env,
                                      utils::modifyList(rhf_choices, list(CAPS = c(x_1 = cap)))))
  expect_lte(max(env$d$x_1), cap)
  expect_true(any(grepl(paste0("x_1: ", sum(d$x_1 > cap), " intervals capped"), out, fixed = TRUE)))
  env <- rf_env(d)
  expect_error(rf_run("rhf", "fit", rhf_cleanup_labels, env, utils::modifyList(rhf_choices, list(CAPS = c(age = 90)))),
               "CAPS names a column that is not in PREDICTORS: age")
})

test_that("rhf-fit refuses a CAPS it cannot read rather than capping nothing", {
  rf_skip_unless_stack(rf_template_packages("rhf", "fit"))
  d <- rhf_data()
  bad <- list(unnamed = 2, partly_named = c(x_1 = 2, 3), duplicated = c(x_1 = 2, x_1 = 3), missing = c(x_1 = NA_real_),
              infinite = c(x_1 = Inf), text = c(x_1 = "2"), empty = numeric())
  for (nm in names(bad)) {
    env <- rf_env(d)
    expect_error(rf_run("rhf", "fit", rhf_cleanup_labels, env, utils::modifyList(rhf_choices, list(CAPS = bad[[nm]]))),
                 "CAPS must be NULL or a numeric vector", info = nm)
  }
  d$x_1 <- factor(d$x_1 > 0)
  env <- rf_env(d)
  expect_error(rf_run("rhf", "fit", rhf_cleanup_labels, env, utils::modifyList(rhf_choices, list(CAPS = c(x_1 = 1)))),
               "CAPS names a predictor that is not numeric: x_1")
})

test_that("a cap keeps an integer predictor integer", {
  rf_skip_unless_stack(rf_template_packages("rhf", "fit"))
  d <- rhf_data()
  d$x_1 <- as.integer(round(d$x_1 * 10))
  env <- rf_env(d)
  utils::capture.output(rf_run("rhf", "fit", rhf_cleanup_labels, env,
                               utils::modifyList(rhf_choices, list(CAPS = c(x_1 = 2.5)))))
  expect_type(env$d$x_1, "integer")
  expect_identical(max(env$d$x_1), 2L)
})

test_that("rhf-fit counts predictor changes on final intervals, and LOOKAHEAD = \"reset\" undoes them", {
  rf_skip_unless_stack(rf_template_packages("rhf", "fit"))
  d <- rhf_data()
  env <- rf_env(d)
  utils::capture.output(rf_run("rhf", "fit", rhf_cleanup_labels, env, rhf_choices))
  # Every patient with more than one interval has a final interval to check.
  expect_identical(sum(env$.lookahead$checked), sum(table(d$ccfid) > 1L))
  # hazard.simulation() redraws xtd on every interval, so the check finds changes.
  expect_gt(sum(env$.lookahead$changed), 0L)
  env <- rf_env(d)
  utils::capture.output(rf_run("rhf", "fit", rhf_cleanup_labels, env,
                               utils::modifyList(rhf_choices, list(LOOKAHEAD = "reset"))))
  expect_equal(env$d[env$.final, rhf_choices$PREDICTORS], env$d[env$.final - 1L, rhf_choices$PREDICTORS],
               ignore_attr = TRUE)
  # An interval length no final interval has checks none, and resets none.
  env <- rf_env(d)
  utils::capture.output(rf_run("rhf", "fit", rhf_cleanup_labels, env,
                               utils::modifyList(rhf_choices, list(LOOKAHEAD_INTERVAL = 1e6, LOOKAHEAD = "reset"))))
  expect_identical(sum(env$.lookahead$checked), 0L)
})

rhf_explain_labels <- c("setup", "edit-study-choices", "forest", "tbl-data", "fig-auc-cumulative", "fig-auc-incident",
                        "tbl-auc", "curves", "fig-hazard", "fig-chf", "fig-importance", "tbl-importance")
rhf_explain_choices <- list(N_CURVES = 5, MAX_RULES_TREE = 10, MAX_TREE = 10, N_TIMES = 3, SEED = 1)

test_that("rhf-explain explains the saved forest without refitting", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("rhf", "explain"))
  fit <- rhf_fit_first()
  forest_cache <- file.path(fit$CACHE_DIR, "rhf-forest.rds")
  grown_at <- file.mtime(forest_cache)
  env <- new.env(parent = globalenv())
  env$.root <- fit$.root
  utils::capture.output(rf_run("rhf", "explain", rhf_explain_labels, env, rhf_explain_choices))
  for (nm in c("rhf-auc-cumulative", "rhf-auc-incident", "rhf-varpro-cache", "rhf-importance")) {
    expect_true(file.exists(file.path(env$CACHE_DIR, paste0(nm, ".rds"))), info = nm)
  }
  expect_length(env$.curve_ids, 5L)
  expect_true(all(is.finite(c(env$auc_cum$iAUC.uno, env$auc_inc$iAUC.uno))))
  for (p in list(ggRandomForests::gg_auct(env$forest, auct_fit = env$auc_cum), env$haz,
                 ggRandomForests::gg_rhf_importance(env$forest, importance_fit = env$imp))) {
    expect_s3_class(ggplot2::ggplot_build(plot(p)), "ggplot_built")
  }
  if (.Platform$OS.type != "windows") {
    for (nm in c("rhf-auc-cumulative", "rhf-auc-incident", "rhf-varpro-cache", "rhf-importance")) {
      expect_identical(format(file.mode(file.path(env$CACHE_DIR, paste0(nm, ".rds")))), "600", info = nm)
    }
  }
  # It never regrows: the fit's forest cache is untouched by the explain run.
  expect_identical(file.mtime(forest_cache), grown_at)
})

test_that("rhf-explain's partial dependence is off by default and its choices parse", {
  src <- readLines(template_path("rhf", "explain"), warn = FALSE)
  env <- new.env()
  eval(parse(text = rf_chunk(src, "edit-study-choices")), envir = env)
  expect_null(env$PD_VARS)
  expect_identical(c(env$PD_N, env$PD_GRID, env$PD_MIN_RISK), c(300, 9, 20))
  # With PD_VARS NULL neither chunk computes anything, so nothing else they read is needed.
  for (label in c("tbl-pd-exposure", "fig-partial")) {
    expect_null(eval(parse(text = rf_chunk(src, label)), envir = env), info = label)
  }
  expect_false(exists("pd", envir = env, inherits = FALSE))
  # The lessons of the first real run travel with the template.
  text <- paste(src, collapse = " ")
  expect_match(text, "These paths are not calibrated probabilities", fixed = TRUE)
  expect_match(text, "should come from a pooled model", fixed = TRUE)
})

test_that("rhf-explain counts exposure in aggregate only, then draws partial dependence", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("rhf", "explain"))
  d <- rhf_data()
  d$xb <- as.integer(d$x_1 > stats::median(d$x_1))
  # Text predictors, which rhf-fit makes factors: one ordinary, one labeled 0 and 1, whose codes are 1 and 2.
  d$xf <- c("a", "b", "c")[1L + d$ccfid %% 3L]
  d$xg <- as.character(as.integer(d$x_2 > stats::median(d$x_2)))
  # Days, not years: the exposure is in the units of the interval columns, whatever they are.
  d$start <- d$start * 365.25
  d$stop <- d$stop * 365.25
  fit <- rhf_fit_first(d, utils::modifyList(rhf_choices, list(PREDICTORS = c("xtd", "x_1", "xb", "xf", "xg"),
                                                              TREESIZE = 5L)))
  env <- new.env(parent = globalenv())
  env$.root <- fit$.root
  # Records what each prediction is handed, then predicts as the template would.
  handed <- new.env()
  handed$xg <- list()
  env$predict <- function(object, newdata, ...) {
    handed$xg[[length(handed$xg) + 1L]] <- newdata$xg
    stats::predict(object, newdata, ...)
  }
  utils::capture.output(rf_run("rhf", "explain", c(rhf_explain_labels, "tbl-pd-exposure", "fig-partial"), env,
                               c(rhf_explain_choices, list(PD_VARS = c("xtd", "xb", "xf", "xg"), PD_N = 60,
                                                           PD_GRID = 3, PD_MIN_RISK = 1))))
  ex <- env$pd_exposure
  expect_identical(names(ex), c("variable", "value", "time.index", "start", "stop", "patients", "patient_time", "deaths"))
  # One block for everyone and one for each value of a 0/1 or factor predictor; the continuous one gets none.
  n_win <- nrow(env$imp$window.info)
  expect_identical(nrow(ex), (1L + 2L + 3L + 2L) * n_win)
  expect_setequal(unique(ex$variable), c("(all)", "xb", "xf", "xg"))
  everyone <- ex[ex$variable == "(all)", ]
  for (v in c("xb", "xf", "xg")) {
    by_value <- ex[ex$variable == v, ]
    expect_equal(everyone$deaths, as.numeric(tapply(by_value$deaths, by_value$time.index, sum)), info = v)
    expect_equal(everyone$patient_time, as.numeric(tapply(by_value$patient_time, by_value$time.index, sum)), info = v)
  }
  expect_setequal(ex$value[ex$variable == "xf"], c("a", "b", "c"))
  # In the interval columns' own units: no window holds more patient-time than its patients could spend in it.
  expect_true(all(everyone$patient_time <= everyone$patients * (everyone$stop - everyone$start) + 1e-8))
  expect_gt(max(everyone$stop), 100)
  expect_true(all(everyone$patients <= length(unique(d$ccfid))))
  # Aggregate only: no study id.
  expect_false(any(unlist(lapply(ex, as.character)) %in% as.character(unique(d$ccfid))))
  # The partial dependence: 3 values for xtd, 0 and 1 for xb, and each level of the factors.
  expect_setequal(unique(env$pd$variable), c("xtd", "xb", "xf", "xg"))
  expect_setequal(env$pd$level[env$pd$variable == "xb"], c("0", "1"))
  expect_setequal(env$pd$level[env$pd$variable == "xf"], c("a", "b", "c"))
  expect_true(all(env$pd$n.risk >= 1L & env$pd$n.risk <= 60L))
  # The factor labeled 0 and 1 is set by level and stays a factor: each of its two predictions holds one level.
  set_xg <- Filter(function(x) is.factor(x) && length(unique(x)) == 1L, handed$xg)
  expect_length(set_xg, 2L)
  expect_identical(vapply(set_xg, function(x) as.character(x[[1L]]), ""), c("0", "1"))
  expect_identical(levels(set_xg[[1L]]), c("0", "1"))
  expect_s3_class(ggplot2::ggplot_build(env$.fig), "ggplot_built")
  # predict() dispatches to randomForestRHF, so its version is part of the cache key.
  cache <- file.path(env$CACHE_DIR, "rhf-partial.rds")
  rec <- readRDS(cache)
  expect_identical(rec$key$packages$randomForestRHF, format(utils::packageVersion("randomForestRHF")))
  # A cache written by another randomForestRHF is stale, and the render stops rather than reuse it.
  rec$key$packages$randomForestRHF <- "0.0.1"
  saveRDS(rec, cache)
  expect_error(utils::capture.output(rf_run("rhf", "explain", "fig-partial", env)), "randomForestRHF")
  if (.Platform$OS.type != "windows") {
    expect_identical(format(file.mode(file.path(env$CACHE_DIR, "rhf-partial.rds"))), "600")
  }
})

test_that("rhf-explain stops when no fit has run in its set", {
  rf_skip_unless_stack(rf_template_packages("rhf", "explain"))
  env <- new.env(parent = globalenv())
  env$.root <- rf_study()
  expect_error(rf_run("rhf", "explain", c("setup", "edit-study-choices", "forest"), env),
               "Render the rhf-fit job in this set first")
})

test_that("a forest grown on repaired rows makes the explain report a draft, and stops a final one", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("rhf", "explain"))
  d <- rhf_data()
  first <- which(d$ccfid == d$ccfid[[1L]])
  d$start[first[2L]] <- d$start[first[2L]] - 1e-3
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "")
  fit <- rhf_fit_first(d, utils::modifyList(rhf_choices, list(REPAIR = "clip", TREESIZE = 5L)))
  env <- new.env(parent = globalenv())
  env$.root <- fit$.root
  out <- utils::capture.output(rf_run("rhf", "explain", c("setup", "edit-study-choices", "forest"), env))
  expect_true(any(grepl("DRAFT -- rows repaired in the job", out, fixed = TRUE)))
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "1")
  env <- new.env(parent = globalenv())
  env$.root <- fit$.root
  expect_error(rf_run("rhf", "explain", c("setup", "edit-study-choices", "forest"), env), "HVTI_TEMPLATE_STRICT")
})
