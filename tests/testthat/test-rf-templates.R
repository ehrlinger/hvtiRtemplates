# Survival data for rfs: randomForestSRC's own veteran set, status 0/1.
rfs_data <- function() {
  e <- new.env()
  utils::data("veteran", package = "randomForestSRC", envir = e)
  e$veteran
}
rfs_choices <- list(TIME = "time", STATUS = "status",
                    PREDICTORS = c("trt", "celltype", "karno", "diagtime", "age", "prior"),
                    NTREE = 50, SEED = 1)

test_that("rfs-fit grows a survival forest and saves the handoff", {
  rf_skip_unless_stack(rf_template_packages("rfs", "fit"))
  env <- rf_env(rfs_data())
  rf_run("rfs", "fit", c("set", "study-choices", "read", "fit", "diagnostics", "save"), env, rfs_choices)

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
  expect_error(rf_run("rfs", "fit", c("set", "study-choices", "read"), env, rfs_choices),
               "0 and 1")
})

test_that("rfs-fit refuses a patient with no outcome", {
  rf_skip_unless_stack(rf_template_packages("rfs", "fit"))
  d <- rfs_data()
  d$time[3] <- NA
  env <- rf_env(d)
  expect_error(rf_run("rfs", "fit", c("set", "study-choices", "read"), env, rfs_choices),
               "no time or status")
})

test_that("rf_skip_unless_stack does not error on a package with no floor", {
  # "utils" is always installed and has no row in rf_pkg_floors, so this
  # exercises the no-floor fallback -- the branch a `[[` lookup made
  # unreachable, since it throws "subscript out of bounds" for a missing
  # name instead of the NA that `[` returns.
  expect_no_error(rf_skip_unless_stack("utils"))
  expect_no_condition(rf_skip_unless_stack("utils"), class = "skip")
})

explain_labels <- c("set", "study-choices", "forest", "importance", "select", "varpro", "dependence")

test_that("rfs-explain explains the saved forest without refitting", {
  rf_skip_unless_stack(rf_template_packages("rfs", "explain"))
  fit_env <- rf_fit_first("rfs", rfs_data(), rfs_choices)
  env <- new.env(parent = globalenv())
  env$.root <- fit_env$.root
  rf_run("rfs", "explain", explain_labels, env, list(TOP_K = 2, TIMES = c(30, 90), SEED = 1))

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
  expect_error(rf_run("rfs", "explain", c("set", "study-choices", "forest"), env),
               "Render the rfs-fit job in this set first")
})

test_that("a changed TOP_K makes only the partial caches stale", {
  rf_skip_unless_stack(rf_template_packages("rfs", "explain"))
  fit_env <- rf_fit_first("rfs", rfs_data(), rfs_choices)
  env <- new.env(parent = globalenv())
  env$.root <- fit_env$.root
  choices <- list(TOP_K = 2, TIMES = c(30, 90), SEED = 1)
  rf_run("rfs", "explain", explain_labels, env, choices)

  choices$TOP_K <- 3
  again <- new.env(parent = globalenv())
  again$.root <- fit_env$.root
  rf_run("rfs", "explain", c("set", "study-choices", "forest", "importance", "select", "varpro"), again, choices)
  # "only" is the claim under test: the error must name rfs-partial, the
  # cache the dependence chunk hits first, not merely be A stale-cache error,
  # which any cache going stale for any reason would also satisfy.
  expect_error(rf_run("rfs", "explain", "dependence", again),
               regexp = "rfs-partial", class = "hvtiRutilities_stale_cache")

  again$REFIT <- TRUE
  rf_run("rfs", "explain", "dependence", again)
  # again$sel is unchanged since the earlier `select` chunk (the `dependence`
  # chunk never touches it), so asserting on it would be tautological. The
  # recomputed partial (a gg_partial_rfsrc list of $continuous/$categorical
  # frames, one row per variable/level) is what REFIT actually produces.
  pd_vars <- unique(c(as.character(again$pd$continuous$name), as.character(again$pd$categorical$name)))
  expect_length(pd_vars, 3L)
})

test_that("PARTIAL_VARS names the dependence variables explicitly", {
  rf_skip_unless_stack(rf_template_packages("rfs", "explain"))
  fit_env <- rf_fit_first("rfs", rfs_data(), rfs_choices)
  env <- new.env(parent = globalenv())
  env$.root <- fit_env$.root
  chosen <- c("age", "karno")
  rf_run("rfs", "explain", explain_labels, env,
         list(PARTIAL_VARS = chosen, TIMES = c(30, 90), SEED = 1))

  expect_identical(env$sel, chosen)
  pd_vars <- unique(c(as.character(env$pd$continuous$name), as.character(env$pd$categorical$name)))
  expect_setequal(pd_vars, chosen)
})

test_that("PARTIAL_VARS refuses a variable the forest was not grown on", {
  rf_skip_unless_stack(rf_template_packages("rfs", "explain"))
  fit_env <- rf_fit_first("rfs", rfs_data(), rfs_choices)
  env <- new.env(parent = globalenv())
  env$.root <- fit_env$.root
  expect_error(
    rf_run("rfs", "explain", c("set", "study-choices", "forest", "importance", "select"), env,
           list(PARTIAL_VARS = "not_a_variable", SEED = 1)),
    "not grown on"
  )
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
