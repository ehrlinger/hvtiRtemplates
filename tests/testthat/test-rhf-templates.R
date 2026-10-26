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
  # It never regrows: the fit's forest cache is untouched by the explain run.
  expect_identical(file.mtime(forest_cache), grown_at)
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
