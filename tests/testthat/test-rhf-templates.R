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
