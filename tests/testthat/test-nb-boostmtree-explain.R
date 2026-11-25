# nb-boostmtree_explain is run here chunk by chunk, after nb-boostmtree_fit has saved its bundle.

nb_effect_labels <- c("setup", "edit-study-choices", "fit", "tbl-data", "fig-importance", "importance-runs", "effects")

# One fitted study for each set of fit choices, grown on first use and removed when the file ends: most tests here
# explain a fit and never change it, and a fit is the dearest step they share. nb_fit_copy() hands a test its own copy
# of the whole study, key and caches included, so a test that rewrites the bundle or the caches leaves the shared one
# as it was fitted.
nb_fitted <- new.env()
# nolint start: object_usage_linter.
nb_fit_copy <- function(choices = nb_choices(), .local_envir = parent.frame()) {
  key <- paste(deparse(choices), collapse = "")
  if (is.null(nb_fitted[[key]])) {
    root <- nb_study(.local_envir = testthat::teardown_env())
    nb_fit_in(root, choices = choices)
    nb_fitted[[key]] <- root
  }
  dest <- withr::local_tempdir("nb-study-copy-", .local_envir = .local_envir)
  from <- list.files(nb_fitted[[key]], all.files = TRUE, full.names = TRUE, no.. = TRUE)
  stopifnot(all(file.copy(from, dest, recursive = TRUE, copy.date = TRUE)))
  normalizePath(dest)
}
# nolint end

test_that("the mean line averages within time bins, not at single visit times", {
  nb_skip_unless_stack()
  root <- nb_fit_copy()
  env <- nb_env(root)
  utils::capture.output(nb_explain_run(c("setup", "edit-study-choices", "fit", "fig-traces"), env,
                                       nb_explain_choices(N_TRACES = 10)))
  # Every bin stands on more than one patient, and there are fewer bins than distinct times.
  expect_true(all(env$trace_means$n_patients > 1L))
  expect_lt(nrow(env$trace_means), length(unique(env$traces$time)))
})

test_that("the trace sample is reproducible under SEED", {
  nb_skip_unless_stack()
  root <- nb_fit_copy()
  labels <- c("setup", "edit-study-choices", "fit", "fig-traces")
  a <- nb_env(root)
  utils::capture.output(nb_explain_run(labels, a, nb_explain_choices(N_TRACES = 10)))
  b <- nb_env(root)
  utils::capture.output(nb_explain_run(labels, b, nb_explain_choices(N_TRACES = 10)))
  expect_identical(sort(unique(as.character(a$p_traces$data$id))), sort(unique(as.character(b$p_traces$data$id))))
})

test_that("the partial effects are cached beside the fit, and changed EFFECT_VARIABLES stop until REFIT", {
  nb_skip_unless_stack()
  local_child_chunks()
  root <- nb_fit_copy()
  dir <- nb_set_dir(root)
  partial <- file.path(dir, "nb-boostmtree_explain-partial.rds")
  stamp <- function(f) list(md5 = unname(tools::md5sum(f)), mtime = file.mtime(f))
  choices <- nb_explain_choices(EFFECT_VARIABLES = c("age", "grp"))
  env <- nb_env(root)
  utils::capture.output(nb_explain_run(nb_effect_labels, env, choices))
  expect_true(file.exists(partial))
  before <- stamp(partial)
  # The second render loads the effects rather than recomputing them.
  env2 <- nb_env(root)
  utils::capture.output(nb_explain_run(nb_effect_labels, env2, choices))
  expect_identical(stamp(partial), before)
  expect_identical(env2$.partial, env$.partial)
  # Another variable list is a stale cache, named as such, until REFIT; the fit is not refitted with it.
  choices <- nb_explain_choices(EFFECT_VARIABLES = "grp")
  expect_error(utils::capture.output(nb_explain_run(nb_effect_labels, nb_env(root), choices)), "inputs$.effect_vars",
               fixed = TRUE, class = "hvtiRutilities_stale_cache")
  fit_before <- stamp(file.path(dir, "nb-boostmtree_fit-fit0.rds"))
  env3 <- nb_env(root)
  utils::capture.output(nb_explain_run(nb_effect_labels, env3, nb_explain_choices(EFFECT_VARIABLES = "grp", REFIT = TRUE)))
  expect_identical(as.character(unique(env3$p_effects[[1L]]$data$variable)), "grp")
  expect_identical(stamp(file.path(dir, "nb-boostmtree_fit-fit0.rds")), fit_before)
})

test_that("the partial effects are guarded only when they are to compute", {
  nb_skip_unless_stack()
  local_child_chunks()
  root <- nb_fit_copy()
  long <- list()
  memory <- list()
  guarded <- function(..., labels = nb_effect_labels) {
    long <<- list()
    memory <<- list()
    env <- nb_env(root)
    testthat::with_mocked_bindings(
      utils::capture.output(nb_explain_run(labels, env, nb_explain_choices(N_VIMP = 2, ...))),
      guard_long_fit = function(name, ...) long[[length(long) + 1L]] <<- name,
      guard_memory = function(need, ...) memory[[length(memory) + 1L]] <<- need
    )
    env
  }
  # Importance alone, so that every run below loads it and only the partial effects are in question.
  guarded(labels = setdiff(nb_effect_labels, "effects"))
  # Not cached: guarded, for the fit's memory at one core, since partial.plot() forks no workers.
  env <- guarded(EFFECT_VARIABLES = "age")
  expect_identical(long, list("nb-boostmtree_explain-partial"))
  expect_identical(memory, list(0, env$.need(1L)))
  # A current cache loads, REFIT or not, so neither guard is asked.
  for (refit in c(FALSE, TRUE)) {
    guarded(EFFECT_VARIABLES = "age", REFIT = refit)
    expect_length(long, 0L)
    expect_identical(memory, list(0))
  }
  # Stale without REFIT stops as stale, not as a long fit.
  expect_error(guarded(EFFECT_VARIABLES = "grp"), class = "hvtiRutilities_stale_cache")
  expect_length(long, 0L)
  # Changed variables under REFIT recompute the effects while importance loads: guarded.
  env <- guarded(EFFECT_VARIABLES = "grp", REFIT = TRUE)
  expect_identical(long, list("nb-boostmtree_explain-partial"))
  expect_identical(memory, list(0, env$.need(1L)))
})

test_that("changed EFFECT_VARIABLES under REFIT are refused outside run_job(), with the cache untouched", {
  nb_skip_unless_stack()
  local_child_chunks()
  root <- nb_fit_copy()
  utils::capture.output(nb_explain_run(nb_effect_labels, nb_env(root), nb_explain_choices(EFFECT_VARIABLES = "age")))
  partial <- file.path(nb_set_dir(root), "nb-boostmtree_explain-partial.rds")
  before <- unname(tools::md5sum(partial))
  withr::local_envvar(HVTI_JOB_MARKER = NA, HVTI_ALLOW_LONG_FIT = NA)
  withr::local_options(hvtiRtemplates.allow_interactive_fit = NULL)
  expect_error(utils::capture.output(nb_explain_run(nb_effect_labels, nb_env(root),
                                                    nb_explain_choices(EFFECT_VARIABLES = "grp", REFIT = TRUE))),
               "partial effects predict")
  expect_identical(unname(tools::md5sum(partial)), before)
})

test_that("EFFECT_VARIABLES may name a factor covariate alone", {
  nb_skip_unless_stack()
  local_child_chunks()
  root <- nb_fit_copy()
  env <- nb_explain_in(root, labels = nb_effect_labels, choices = nb_explain_choices(EFFECT_VARIABLES = "grp"), fit = FALSE)
  expect_length(env$p_effects, 1L)
  expect_identical(as.character(unique(env$p_effects[[1L]]$data$variable)), "grp")
  expect_no_error(ggplot2::ggplot_build(env$p_effects[[1L]]))
})

test_that("each effects page is emitted at its own width and height", {
  nb_skip_unless_stack()
  local_child_chunks()
  root <- nb_fit_copy()
  env <- nb_env(root)
  # One vectorized sprintf() over both options once gave every page fig-height equal to its width.
  emitted <- list()
  local_mocked_bindings(knit_child = function(text, ...) {
    emitted[[length(emitted) + 1L]] <<- text
    ""
  }, .package = "knitr")
  utils::capture.output(nb_explain_run(nb_effect_labels, env, nb_explain_choices(EFFECT_VARIABLES = "grp")))
  # The importance table is also emitted as a child chunk; the effect pages are the ones with a figure width.
  pages <- Filter(function(x) any(grepl("^#\\| fig-width:", x)), emitted)
  expect_length(pages, length(env$.effect_page))
  for (i in seq_along(pages)) {
    size <- env$.effect_page[[i]]$size
    expect_true(size$width != size$height)
    expect_identical(grep("^#\\| fig-(width|height):", pages[[i]], value = TRUE),
                     c(sprintf("#| fig-width: %g", .report_size(size$width)),
                       sprintf("#| fig-height: %g", .report_size(size$height))))
  }
})

test_that("visits all at one time draw no mean line, and say so", {
  nb_skip_unless_stack()
  traces <- data.frame(id = factor(rep(c("a", "b"), each = 2L)), time = 1, fitted = c(1, 2, 3, 4),
                       observed = c(1, 2, 3, 4), response = factor("y"))
  class(traces) <- c("gg_boost_trajectory", class(traces))
  env <- nb_env(tempdir())
  env$gg_boost_trajectory <- function(fit) traces
  # The chunk runs alone, without setup's save_figure(); saving is tested elsewhere.
  list2env(list(fit = NULL, SEED = 1, N_TRACES = Inf, .time = "iv_echo", .response = "lvef",
                save_figure = function(...) invisible(NULL)), envir = env)
  out <- utils::capture.output(nb_explain_run("fig-traces", env))
  expect_null(env$trace_means)
  expect_true(any(grepl("no mean line is drawn", out, fixed = TRUE)))
  expect_no_error(ggplot2::ggplot_build(env$p_traces))
})

test_that("explain reads the bundle, never fits, and takes its lineage into provenance", {
  nb_skip_unless_stack()
  root <- nb_fit_copy()
  env <- nb_env(root)
  env$boostmtree <- function(...) stop("explain must never fit")
  utils::capture.output(nb_explain_run(c("setup", "edit-study-choices", "fit", "tbl-data"), env, nb_explain_choices()))
  expect_s3_class(env$fit, "boostmtree")
  expect_identical(env$.provenance_data, env$.fit_read$lineage$data)
  expect_identical(basename(env$.provenance_artifacts[[length(env$.provenance_artifacts)]]$path), "nb-boostmtree_fit.rds")
  expect_identical(env$.predictors, c("age", "female", "grp"))
})

test_that("explain stops, naming the fit job, on a missing file, a non-boostmtree fit, or lineage on the inner fit", {
  nb_skip_unless_stack()
  labels <- c("setup", "edit-study-choices", "fit")
  root <- nb_study()
  expect_error(utils::capture.output(nb_explain_run(labels, nb_env(root), nb_explain_choices())),
               "Render the nb-boostmtree_fit job in this set first", fixed = TRUE)
  nb_fit_in(root)
  path <- nb_bundle_path(root)
  good <- readRDS(path)
  bad <- good
  bad$fit <- list(x = 1)
  saveRDS(bad, path)
  expect_error(utils::capture.output(nb_explain_run(labels, nb_env(root), nb_explain_choices())),
               "does not hold a (boostmtree, grow) fit", fixed = TRUE)
  inner <- good
  attr(inner$fit, "hvti_provenance") <- attr(good, "hvti_provenance")
  attr(inner, "hvti_provenance") <- NULL
  saveRDS(inner, path)
  expect_error(utils::capture.output(nb_explain_run(labels, nb_env(root), nb_explain_choices())),
               "has no complete hvti_provenance lineage", fixed = TRUE)
})

test_that("explain stops, naming the fit job, when the bundle lacks a field", {
  nb_skip_unless_stack()
  root <- nb_fit_copy()
  path <- nb_bundle_path(root)
  b <- readRDS(path)
  b$k_shadow <- NULL
  saveRDS(b, path)
  expect_error(utils::capture.output(nb_explain_run(c("setup", "edit-study-choices", "fit"), nb_env(root),
                                                    nb_explain_choices())),
               "lacks k_shadow. Render the nb-boostmtree_fit job in this set again", fixed = TRUE)
})

test_that("a final render refuses a fit saved from unregistered working data", {
  nb_skip_unless_stack()
  root <- nb_fit_copy()
  path <- nb_bundle_path(root)
  b <- readRDS(path)
  lineage <- attr(b, "hvti_provenance")
  lineage$data[[1L]]$working <- TRUE
  attr(b, "hvti_provenance") <- lineage
  saveRDS(b, path)
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "1")
  expect_error(utils::capture.output(nb_explain_run(c("setup", "edit-study-choices", "fit"), nb_env(root),
                                                    nb_explain_choices())),
               "nb-boostmtree_fit.rds was saved from the working", fixed = TRUE)
})

test_that("explain warns when boostmtree or randomForestSRC differ from the fit's", {
  nb_skip_unless_stack()
  root <- nb_fit_copy()
  path <- nb_bundle_path(root)
  b <- readRDS(path)
  b$versions[["randomForestSRC"]] <- "0.0.1"
  saveRDS(b, path)
  env <- nb_env(root)
  expect_warning(out <- utils::capture.output(nb_explain_run(c("setup", "edit-study-choices", "fit"), env,
                                                             nb_explain_choices())),
                 "grown with randomForestSRC 0.0.1", fixed = TRUE)
  expect_true(any(grepl("callout-warning", out, fixed = TRUE)))
})

test_that("importance pools N_VIMP runs per fit, named fit<i>.run<j>, and reports the pool's counts unaltered", {
  nb_skip_unless_stack()
  # importance-runs emits its table as a child chunk.
  local_child_chunks()
  root <- nb_fit_copy(nb_choices(N_REFITS = 1))
  env <- nb_explain_in(root, fit = FALSE)
  expect_identical(names(env$.runs), c("fit0.run1", "fit0.run2", "fit0.run3", "fit1.run1", "fit1.run2", "fit1.run3"))
  expect_s3_class(env$.pool, "gg_boost_vimp_pool")
  expect_identical(unique(env$importance_table$n_runs), 6L)
  expect_identical(env$importance_table$n_detected, env$.pool$n_detected)
  expect_identical(env$importance_table$share, env$.pool$share)
  runs <- list.files(nb_set_dir(root), "^nb-boostmtree_explain-vimp-fit[01]-run[1-3][.]rds$")
  expect_length(runs, 6L)
  expect_s3_class(env$p_vimp, "ggplot")
  expect_no_error(ggplot2::ggplot_build(env$p_vimp))
})

test_that("raising N_VIMP reuses the cached runs and adds only the new ones", {
  nb_skip_unless_stack()
  # importance-runs emits its table as a child chunk.
  local_child_chunks()
  root <- nb_fit_copy()
  nb_explain_in(root, choices = nb_explain_choices(N_VIMP = 2), fit = FALSE)
  run <- function(j) file.path(nb_set_dir(root), sprintf("nb-boostmtree_explain-vimp-fit0-run%d.rds", j))
  stamp <- function(f) list(md5 = unname(tools::md5sum(f)), mtime = file.mtime(f))
  before <- lapply(1:2, function(j) stamp(run(j)))
  env <- nb_explain_in(root, choices = nb_explain_choices(N_VIMP = 3), fit = FALSE)
  expect_identical(lapply(1:2, function(j) stamp(run(j))), before)
  expect_true(file.exists(run(3)))
  expect_identical(unique(env$importance_table$n_runs), 3L)
})

test_that("the importance guards are reached only when runs are still to compute", {
  nb_skip_unless_stack()
  local_child_chunks()
  root <- nb_fit_copy()
  labels <- c("setup", "edit-study-choices", "fit", "tbl-data", "fig-importance")
  long <- list()
  memory <- list()
  guarded <- function(env, choices) {
    long <<- list()
    memory <<- list()
    testthat::with_mocked_bindings(
      utils::capture.output(nb_explain_run(labels, env, choices)),
      guard_long_fit = function(name, ...) long[[length(long) + 1L]] <<- name,
      guard_memory = function(need, ...) memory[[length(memory) + 1L]] <<- need
    )
  }
  choices <- nb_explain_choices(N_VIMP = 2)
  guarded(nb_env(root), choices)
  # Nothing is cached yet, so every run is to compute and the guard is asked about all of them.
  expect_identical(long, list(sprintf("nb-boostmtree_explain-vimp-fit0-run%d", 1:2)))
  expect_length(memory, 1L)
  expect_gt(memory[[1L]], 0)
  # Cached now: the long-fit guard is not called, and the memory guard is asked for nothing.
  guarded(nb_env(root), choices)
  expect_length(long, 0L)
  expect_identical(memory, list(0))
  # Raising N_VIMP guards only the new run.
  guarded(nb_env(root), nb_explain_choices(N_VIMP = 3))
  expect_identical(long, list("nb-boostmtree_explain-vimp-fit0-run3"))
})

test_that("under REFIT the importance guards see each run's own fit, so a current cache is not refused", {
  nb_skip_unless_stack()
  local_child_chunks()
  root <- nb_fit_copy(nb_choices(N_REFITS = 1))
  labels <- c("setup", "edit-study-choices", "fit", "tbl-data", "fig-importance")
  long <- list()
  memory <- list()
  guarded <- function(...) {
    long <<- list()
    memory <<- list()
    testthat::with_mocked_bindings(
      utils::capture.output(nb_explain_run(labels, nb_env(root), nb_explain_choices(N_VIMP = 2, ...))),
      guard_long_fit = function(name, ...) long[[length(long) + 1L]] <<- name,
      guard_memory = function(need, ...) memory[[length(memory) + 1L]] <<- need
    )
  }
  guarded()
  # cache_fit() loads a current cache with REFIT left TRUE, so the preflight must not call it a fit. The quoted
  # call names `f`: a preflight that does not bind it, or binds fit0's for every run, keys these runs differently.
  guarded(REFIT = TRUE)
  expect_length(long, 0L)
  expect_identical(memory, list(0))
  # A changed seed is stale, so under REFIT every run is still guarded.
  guarded(REFIT = TRUE, SEED = 99)
  expect_length(long[[1L]], 4L)
  expect_gt(memory[[1L]], 0)
})

test_that("a worker that returns nothing stops the render, naming the run and CORES", {
  nb_skip_unless_stack()
  local_child_chunks()
  root <- nb_fit_copy()
  env <- nb_env(root)
  env$cache_fit <- function(...) NULL
  expect_error(utils::capture.output(nb_explain_run(c("setup", "edit-study-choices", "fit", "tbl-data", "fig-importance"), env,
                                                    nb_explain_choices(N_VIMP = 1))),
               "fit0.run1 returned nothing.*Lower CORES")
})

test_that("vimp runs are seeded SEED + j + 1000 * i, so no two fits share a permutation", {
  nb_skip_unless_stack()
  local_child_chunks()
  root <- nb_fit_copy(nb_choices(N_REFITS = 1))
  env <- nb_explain_in(root, choices = nb_explain_choices(N_VIMP = 2, SEED = 11), fit = FALSE)
  plan <- env$.runs_plan
  seed <- function(name) plan$seed[plan$name == name]
  expect_identical(seed("fit0.run1"), 12)
  expect_identical(seed("fit0.run2"), 13)
  expect_false(seed("fit0.run1") == seed("fit1.run1"))
  expect_identical(seed("fit1.run1"), 1012)
  expect_length(unique(plan$seed), nrow(plan))
})

test_that("N_VIMP must be a whole number from 1 to 999, so seeds never coincide across fits", {
  nb_skip_unless_stack()
  local_child_chunks()
  root <- nb_fit_copy()
  for (bad in list(0, 1000, 2.5, NA_real_, c(2, 3), "3")) {
    env <- nb_env(root)
    expect_error(utils::capture.output(nb_explain_run(c("setup", "edit-study-choices", "fit", "tbl-data", "fig-importance"), env,
                                                      nb_explain_choices(N_VIMP = bad))),
                 "N_VIMP must be a whole number from 1 to 999", info = format(bad))
  }
})

test_that("with K_SHADOW = 0 explain runs importance once, draws one run, and never pools", {
  nb_skip_unless_stack()
  local_child_chunks()
  root <- nb_fit_copy(nb_choices(K_SHADOW = 0, N_REFITS = 1))
  env <- nb_env(root)
  pooled <- 0L
  env$gg_boost_vimp <- function(object, ...) {
    if (!inherits(object, "vimp.boostmtree")) pooled <<- pooled + 1L
    ggBoostedTrees::gg_boost_vimp(object, ...)
  }
  out <- utils::capture.output(nb_explain_run(c("setup", "edit-study-choices", "fit", "tbl-data", "fig-importance",
                                                "importance-runs", "effects"), env, nb_explain_choices()))
  expect_identical(pooled, 0L)
  expect_identical(env$.n_vimp, 1L)
  expect_identical(names(env$.runs), "fit0.run1")
  expect_length(list.files(nb_set_dir(root), "^nb-boostmtree_explain-vimp-.*[.]rds$"), 1L)
  expect_identical(env$.runs_plan$name, "fit0.run1")
  expect_gt(length(env$.effect_vars), 0L)
  expect_false(any(grepl("shadow", env$.effect_vars)))
  expect_true(all(env$.effect_vars %in% c("age", "female", "grp")))
  expect_null(env$.pool)
  expect_null(env$importance_table)
  expect_true(any(grepl("no noise band and no share could be computed", out, fixed = TRUE)))
  expect_no_error(ggplot2::ggplot_build(env$p_vimp))
})

test_that("the default effect variables are the six with the largest median importance", {
  nb_skip_unless_stack()
  local_child_chunks()
  root <- nb_fit_copy()
  env <- nb_explain_in(root, labels = nb_effect_labels, fit = FALSE)
  main <- env$.pool[env$.pool$component == "main", ]
  top <- sort(tapply(main$median_importance, as.character(main$variable), max), decreasing = TRUE)
  expect_identical(env$.effect_vars, head(names(top), 6L))
})

test_that("every explain chunk draws for every family, from fresh runs and from the cache", {
  skip_on_cran()
  nb_skip_unless_stack()
  local_child_chunks()
  labels <- c(nb_effect_labels, "fig-traces")
  components <- list(continuous = "lvef", binary = "lvef_bin = 1 against 0",
                     ordinal = c("lvef_ord threshold 1", "lvef_ord threshold 2"),
                     nominal = c("lvef_nom = low against high", "lvef_nom = mid against high"))
  for (family in names(nb_families)) {
    root <- nb_study(nb_family_data())
    nb_fit_in(root, choices = nb_choices(RESPONSE = nb_families[[family]], FAMILY = family,
                                         PREDICTORS = c("age", "female", "grp")))
    for (pass in 1:2) {
      env <- nb_env(root)
      utils::capture.output(nb_explain_run(labels, env, nb_explain_choices(N_TRACES = 10)))
      for (p in c("p_vimp", "p_traces")) expect_no_error(ggplot2::ggplot_build(env[[p]]))
      drawn <- unlist(lapply(env$p_effects, function(e) as.character(unique(e$data$variable))))
      expect_identical(sort(drawn), sort(env$.effect_vars), info = family)
      for (e in env$p_effects) expect_identical(levels(e$data$response), components[[family]], info = family)
    }
  }
})

test_that("the partial effects report their steps", {
  nb_skip_unless_stack()
  local_child_chunks()
  root <- nb_fit_copy()
  env <- nb_env(root)
  utils::capture.output(nb_explain_run(c("setup", "edit-study-choices"), env, nb_explain_choices()))
  seen <- new.env(parent = emptyenv())
  seen$units <- character()
  bare <- list2env(list(seen = seen), parent = baseenv())
  env$.job$progress <- function(unit) {
    force(unit)
    function(step, steps) seen$units <- c(seen$units, unit)
  }
  environment(env$.job$progress) <- bare
  utils::capture.output(nb_explain_run(c("fit", "tbl-data", "fig-importance", "importance-runs", "effects"), env))
  expect_true("prediction" %in% seen$units)
})

test_that("no explain output prints an identifier", {
  nb_skip_unless_stack()
  local_child_chunks()
  data <- nb_data(id = "MRN")
  root <- nb_study(data)
  nb_fit_in(root)
  env <- nb_env(root)
  out <- utils::capture.output(nb_explain_run(c(nb_effect_labels, "fig-traces"), env, nb_explain_choices(N_TRACES = 10)))
  expect_false(any(vapply(unique(data$MRN), function(v) any(grepl(v, out, fixed = TRUE)), logical(1L))))
  expect_length(nb_files_holding(root, unique(data$MRN)), 0L)
})

test_that("nb-boostmtree_explain renders end to end after the fit job, and the page holds no MRN", {
  skip_on_cran()
  nb_skip_unless_stack()
  testthat::skip_if_not_installed("quarto")
  testthat::skip_if_not(quarto::quarto_available(), "Quarto CLI is required for rendering")
  data <- nb_data(id = "MRN")
  root <- nb_study(data)
  fit_job <- add_job("nb", subject = "lvef", type = "boost", root = root, qualifier = "boostmtree_fit")
  nb_set_choice(fit_job, "^RESPONSE <- ", "RESPONSE <- \"lvef\"")
  nb_set_choice(fit_job, "^M  <- ", "M  <- 5")
  nb_set_choice(fit_job, "^CORES <- ", paste0("CORES <- ", nb_cores, "L"))
  nb_render(fit_job)
  job <- add_job("nb", subject = "lvef", type = "boost", root = root, qualifier = "boostmtree_explain")
  nb_set_choice(job, "^N_VIMP <- ", "N_VIMP <- 2")
  nb_set_choice(job, "^N_TRACES <- ", "N_TRACES <- 10")
  nb_set_choice(job, "^CORES <- ", paste0("CORES <- ", nb_cores, "L"))
  log <- nb_render(job)
  html <- sub("[.]qmd$", ".html", job)
  expect_true(file.exists(html))
  bytes <- nb_file_bytes(html)
  expect_false(any(vapply(unique(data$MRN), function(v) nb_bytes_hold(bytes, v), logical(1L))))
  page <- rawToChar(bytes)
  expect_match(page, "Importance pools 2 runs on 1 fit, 2 in all.", fixed = TRUE)
  payload <- hvtiRtemplates:::.extract_provenance(page)
  expect_identical(payload$analysis$response, "lvef")
  expect_equal(payload$analysis$n_vimp, 2)
  expect_true(any(grepl("nb-boostmtree_fit.rds", unlist(payload$artifacts), fixed = TRUE)))
  expect_gt(length(payload$data), 0L)
  expect_true(any(grepl("prediction [0-9]+/[0-9]+", log)))
  expect_true(all(file.exists(file.path(nb_set_dir(root), sprintf("nb-boostmtree_explain-vimp-fit0-run%d.rds", 1:2)))))
})
