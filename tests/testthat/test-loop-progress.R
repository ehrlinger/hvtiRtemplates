# Issue 631: the long template loops report done/total to job_status() and the render log, as
# sid-stability's refits do (#622). A step read from the cache is not counted.

test_that("the looped fits key on the same code as before, so fits cached by earlier copies still load (#631)", {
  skip_on_cran()
  expect_snapshot({
    cat(cached_code("vp", "fit", "tbl-stability", "vp-repeat-"), sep = "\n")
    cat(cached_code("vp", "dependence", "tbl-stability", "\"vp-dependence-repeat-%02d\""), sep = "\n")
    cat(cached_code("vp", "dependence", "tbl-stability", "\"vp-dependence-repeat-%02d-beta\""), sep = "\n")
    cat(cached_code("sid", "fit", "impute", "\"sid-fit-impute-\""), sep = "\n")
    cat(cached_code("sid", "fit", "fit", "\"sid-fit-\""), sep = "\n")
  })
})

# The steps as one string each, unit/step/total, for a readable expectation.
steps_of <- function(steps) vapply(steps, paste, "", collapse = "/")

test_that("vp-fit's stability refits report done/total, counting only refits that fit (#631)", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "fit"))
  env <- rf_env(vp_data())
  labels <- vp_fit_labels
  rf_run("vp", "fit", labels[seq_len(match("tbl-stability", labels) - 1L)], env, vp_choices)
  steps <- progress_recorder(env)
  rf_run("vp", "fit", "tbl-stability", env)
  expect_identical(steps_of(steps()), c("refit/1/2", "refit/2/2"))
  # Raising REPEATS reuses the two cached refits: only the new one counts.
  env$REPEATS <- 3
  rf_run("vp", "fit", "tbl-stability", env)
  expect_identical(steps_of(steps()), "refit/1/1")
  expect_identical(length(unique(env$.stab$r)), 3L)
})

test_that("vp-dependence's stability refits report done/total, counting only refits that fit (#631)", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("vp", "dependence"))
  env <- rf_env(vpd_data())
  labels <- vpd_labels
  choices <- utils::modifyList(vpd_choices, list(REPEATS = 2))
  rf_run("vp", "dependence", labels[seq_len(match("tbl-stability", labels) - 1L)], env, choices)
  steps <- progress_recorder(env)
  rf_run("vp", "dependence", "tbl-stability", env)
  expect_identical(steps_of(steps()), c("refit/1/2", "refit/2/2"))
  env$REPEATS <- 3
  rf_run("vp", "dependence", "tbl-stability", env)
  expect_identical(steps_of(steps()), "refit/1/1")
  expect_length(env$.runs, 3L)
  # A refit whose forest is cached but whose entropy betas are not still counts.
  beta <- function(r) file.path(env$CACHE_DIR, sprintf("vp-dependence-repeat-%02d-beta.rds", r))
  unlink(beta(1L))
  rf_run("vp", "dependence", "tbl-stability", env)
  expect_identical(steps_of(steps()), "refit/1/1")
  # Under REFIT a file whose key still matches loads, so nothing counts; betas made stale while their forest
  # is not, as a glmnet upgrade would leave them, are refitted and counted.
  env$REFIT <- TRUE
  rf_run("vp", "dependence", "tbl-stability", env)
  expect_identical(steps_of(steps()), character())
  rec <- readRDS(beta(2L))
  rec$key$packages$glmnet <- "0.0.1"
  saveRDS(rec, beta(2L))
  rf_run("vp", "dependence", "tbl-stability", env)
  expect_identical(steps_of(steps()), "refit/1/1")
  expect_identical(readRDS(beta(2L))$key$packages$glmnet, format(utils::packageVersion("glmnet")))
})

test_that("sid-fit's imputations and SID forests report done/total, counting only those that fit (#631)", {
  skip_on_cran()
  rf_skip_unless_stack(rf_template_packages("sid", "fit"))
  env <- rf_env(sid_data())
  labels <- sid_fit_labels
  rf_run("sid", "fit", labels[seq_len(match("impute", labels) - 1L)], env,
         utils::modifyList(sid_fit_choices, list(M = 2)))
  steps <- progress_recorder(env)
  rf_run("sid", "fit", c("impute", "fit"), env)
  expect_identical(steps_of(steps()), c("imputation/1/2", "imputation/2/2", "SID forest/1/2", "SID forest/2/2"))
  # Raising M reuses the two cached imputations: only the third counts. The forests are left out here: their
  # cached code reads d_complete whole, so raising M changes every forest's key.
  env$M <- 3
  rf_run("sid", "fit", "impute", env)
  expect_identical(steps_of(steps()), "imputation/1/1")
  expect_length(env$d_complete, 3L)
  # A rerun with nothing new to fit reports nothing.
  env$M <- 2
  rf_run("sid", "fit", c("impute", "fit"), env)
  expect_identical(steps_of(steps()), character())
})
