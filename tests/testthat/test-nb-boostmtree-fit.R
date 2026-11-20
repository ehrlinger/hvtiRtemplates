test_that("add_job scaffolds nb-boostmtree_fit with its subject and type", {
  dir <- withr::local_tempdir("nb-job-")
  job <- add_job("nb", subject = "lvef", type = "boost", root = dir, qualifier = "boostmtree_fit")
  expect_match(basename(job), "^nb[.]boostmtree_fit[.]lvef[.]boost[.]qmd$")
  txt <- readLines(job)
  expect_identical(grep("^SUBJECT <- ", txt, value = TRUE), "SUBJECT <- \"lvef\"")
  expect_identical(grep("^TYPE\\s+<- ", txt, value = TRUE), "TYPE    <- \"boost\"")
})

test_that("the data chunk keeps the model's columns and drops rows with no response", {
  nb_skip_unless_stack()
  data <- nb_data()
  data$lvef[c(1, 5)] <- NA
  root <- nb_study(data)
  env <- nb_env(root)
  out <- utils::capture.output(nb_fit_run(c("edit-study-choices", "tbl-data"), env, nb_choices()))
  expect_identical(sort(names(env$d)), sort(c("ccfid", "iv_echo", "lvef", "age", "female", "grp")))
  expect_identical(nrow(env$d), nrow(data) - 2L)
  expect_true(is.factor(env$d$grp))
  expect_true(any(grepl("2 visit(s) have no lvef", out, fixed = TRUE)))
  expect_true(any(grepl("Text predictors converted to factors: grp", out, fixed = TRUE)))
})

test_that("KEY defaults to ID and TIME, so a duplicated visit stops the read", {
  nb_skip_unless_stack()
  data <- nb_data()
  data <- rbind(data, data[1, ])
  root <- nb_study(data)
  env <- nb_env(root)
  expect_error(utils::capture.output(nb_fit_run(c("edit-study-choices", "tbl-data"), env, nb_choices())), "unique")
})

test_that("the ID and TIME cannot be predictors, nor the ID the response", {
  nb_skip_unless_stack()
  root <- nb_study()
  run <- function(...) {
    env <- nb_env(root)
    utils::capture.output(nb_fit_run(c("edit-study-choices", "tbl-data"), env, nb_choices(...)))
  }
  expect_error(run(PREDICTORS = c("age", "ccfid")), "identifier, a KEY column or the visit time")
  expect_error(run(PREDICTORS = c("age", "iv_echo")), "identifier, a KEY column or the visit time")
  expect_error(run(RESPONSE = "ccfid"), "cannot be the response")
})

test_that("the default predictors leave out a ccfid the job is not keyed on, and no saved file holds one", {
  nb_skip_unless_stack()
  data <- nb_randid_data()
  root <- nb_study(data)
  env <- nb_env(root)
  out <- utils::capture.output(nb_fit_run(c("setup", "edit-study-choices", "tbl-data", "fit", "save"), env, nb_randid_choices()))
  expect_identical(env$.id, "randid")
  expect_identical(sort(env$.predictors), sort(c("age", "female", "grp")))
  # read_job_data() drops a ccfid that is neither the ID nor a KEY column, and the data table says so.
  expect_false("ccfid" %in% names(env$d))
  expect_match(env$job_data$record$value[env$job_data$record$step == "Identifiers dropped"], "`ccfid`", fixed = TRUE)
  # By name only: no ccfid value is printed.
  expect_false(any(vapply(unique(data$ccfid), function(v) any(grepl(v, out, fixed = TRUE)), logical(1L))))
  expect_true(file.exists(nb_bundle_path(root)))
  expect_length(nb_files_holding(root, unique(data$ccfid)), 0L)
})

test_that("no identifier column can be the response or the visit time, whatever ID names", {
  nb_skip_unless_stack()
  # A ccfid beside an ID of randid: as the response it would be fitted as y and
  # saved with the fit, so it is refused before anything is fitted or written.
  data <- nb_randid_data()
  root <- nb_study(data)
  run <- function(...) {
    env <- nb_env(root)
    utils::capture.output(nb_fit_run(c("setup", "edit-study-choices", "tbl-data", "fit", "save"), env, nb_randid_choices(...)))
  }
  expect_error(run(RESPONSE = "ccfid"), "A patient identifier (ccfid) cannot be the response.", fixed = TRUE)
  expect_error(run(RESPONSE = "CCFID"), "cannot be the response")
  expect_error(run(TIME = "ccfid", KEY = c("randid", "ccfid")), "A patient identifier (ccfid) cannot be the visit time.",
               fixed = TRUE)
  expect_length(list.files(hvtiRutilities::study_dir("estimates", root), recursive = TRUE), 0L)
  expect_length(nb_files_holding(root, unique(data$ccfid)), 0L)
})

test_that("the default predictors leave out every KEY column", {
  nb_skip_unless_stack()
  data <- nb_data()
  data$visit <- stats::ave(data$iv_echo, data$ccfid, FUN = seq_along)
  root <- nb_study(data)
  env <- nb_env(root)
  utils::capture.output(nb_fit_run(c("edit-study-choices", "tbl-data"), env, nb_choices(KEY = c("ccfid", "iv_echo", "visit"))))
  expect_identical(sort(env$.predictors), sort(c("age", "female", "grp")))
})

test_that("named PREDICTORS may hold no identifier or KEY column, and no name twice", {
  nb_skip_unless_stack()
  root <- nb_study(nb_randid_data())
  run <- function(...) {
    env <- nb_env(root)
    utils::capture.output(nb_fit_run(c("edit-study-choices", "tbl-data"), env, nb_randid_choices(...)))
  }
  expect_error(run(PREDICTORS = c("age", "ccfid")), "identifier, a KEY column or the visit time: ccfid")
  expect_error(run(PREDICTORS = c("age", "randid")), "identifier, a KEY column or the visit time: randid")
  expect_error(run(PREDICTORS = c("age", "female", "age")), "PREDICTORS names a variable more than once: age")
  expect_error(run(PREDICTORS = c("age", "lvef")), "PREDICTORS names the response (lvef)", fixed = TRUE)
})

test_that("TIME and RESPONSE resolve against the data ignoring case", {
  nb_skip_unless_stack()
  root <- nb_study()
  env <- nb_env(root)
  utils::capture.output(nb_fit_run(c("edit-study-choices", "tbl-data"), env, nb_choices(TIME = "IV_ECHO", RESPONSE = "LVEF")))
  expect_identical(env$.time, "iv_echo")
  expect_identical(env$.response, "lvef")
  expect_identical(sort(names(env$d)), sort(c("ccfid", "iv_echo", "lvef", "age", "female", "grp")))
  expect_identical(sort(env$.predictors), sort(c("age", "female", "grp")))
  env <- nb_env(root)
  expect_error(utils::capture.output(nb_fit_run(c("edit-study-choices", "tbl-data"), env,
                                                nb_choices(TIME = "IV_ECHO", PREDICTORS = c("age", "IV_ECHO")))),
               "identifier, a KEY column or the visit time")
})

test_that("the setup chunk passes when both packages meet their floors", {
  nb_skip_unless_stack()
  expect_no_error(nb_mocked_setup("neither", "0.0.0", template = "nb.boostmtree_fit"))
})

test_that("boostmtree older than 2.0.13 is refused with the fork's install line", {
  nb_skip_unless_stack()
  expect_error(nb_mocked_setup("boostmtree", "2.0.12", template = "nb.boostmtree_fit"), "ref = \"v2.0.13-ccf\"", fixed = TRUE)
})

test_that("ggBoostedTrees older than 0.10.2 is refused with its install line", {
  nb_skip_unless_stack()
  expect_error(nb_mocked_setup("ggBoostedTrees", "0.10.1", template = "nb.boostmtree_fit"),
               "remotes::install_github(\"ehrlinger/ggBoostedTrees@v0.10.2\")", fixed = TRUE)
})

test_that("the fit groups visits by the study-keyed digest, never the ID", {
  nb_skip_unless_stack()
  root <- nb_study()
  env <- nb_fit_in(root)
  expect_s3_class(env$fit, "boostmtree")
  raw_ids <- unique(nb_data()$ccfid)
  expect_false(any(as.character(raw_ids) %in% as.character(env$fit$id.unique)))
  key <- hvtiRtemplates:::.study_id_key(root, create = FALSE)
  expect_setequal(as.character(env$fit$id.unique), hvtiRtemplates:::.id_digest(raw_ids, key))
})

test_that("no saved file holds an MRN, run in globalenv or outside it", {
  nb_skip_unless_stack()
  data <- nb_data(id = "MRN")
  mrns <- unique(data$MRN)
  for (parent in list(globalenv(), new.env(parent = globalenv()))) {
    root <- nb_study(data)
    env <- nb_fit_in(root, parent)
    expect_identical(tolower(attr(env$job_data$record, "selection")$id), "mrn")
    set_dir <- file.path(hvtiRutilities::study_dir("estimates", root), "lvef-boost")
    expect_setequal(list.files(set_dir),
                    c("nb-boostmtree_fit.rds", "nb-boostmtree_fit-fit0.rds", "nb-boostmtree_fit-fit0.provenance.json"))
    # Every file in the study, so a write anywhere else, .hvti/ included, is
    # searched too. Only the input dataset, its registered copy and the key are
    # left out: the first two hold the IDs by design, and the key is random bytes.
    datasets <- basename(hvtiRutilities::study_dir("datasets", root))
    inputs <- c(file.path(datasets, c("built.csv", "built.parquet")), file.path(".hvti", "id_key"))
    files <- setdiff(list.files(root, recursive = TRUE, all.files = TRUE), inputs)
    estimates <- basename(hvtiRutilities::study_dir("estimates", root))
    expect_true(all(file.path(estimates, "lvef-boost", list.files(set_dir)) %in% files))
    for (f in files) {
      bytes <- nb_file_bytes(file.path(root, f))
      expect_false(any(vapply(mrns, function(v) nb_bytes_hold(bytes, v), logical(1L))), info = f)
    }
    # Positive control, through the same gz read: the search finds them in the
    # data the job read, saved as the fit is.
    control <- withr::local_tempfile(fileext = ".rds")
    saveRDS(env$job_data$data, control)
    expect_true(nb_bytes_hold(nb_file_bytes(control), mrns[[1L]]))
  }
})

test_that("a WHERE on the patient identifier stops before anything is fitted or saved", {
  nb_skip_unless_stack()
  # The data contract refuses it (#219):
  # a WHERE is saved verbatim in the lineage, so an identifier filter would be too.
  data <- nb_data(id = "MRN")
  root <- nb_study(data)
  expect_error(nb_fit_in(root, choices = nb_choices(WHERE = quote(MRN != 4730000001))),
               class = "hvti_where_identifier")
  expect_length(list.files(hvtiRutilities::study_dir("estimates", root), recursive = TRUE), 0L)
})

test_that("the saved fit carries the selection in its lineage", {
  nb_skip_unless_stack()
  root <- nb_study()
  env <- nb_fit_in(root)
  saved <- readRDS(nb_bundle_path(root))
  sel <- attr(saved, "hvti_provenance")$selection
  expect_identical(sel$id, "ccfid")
  expect_identical(sel$key, c("ccfid", "iv_echo"))
})

test_that("the saved fit's lineage records MTRY, as \"all\" for NULL and as given otherwise", {
  nb_skip_unless_stack()
  saved_analysis <- function(choices) {
    root <- nb_study()
    nb_fit_in(root, choices = choices)
    attr(readRDS(nb_bundle_path(root)), "hvti_provenance")$analysis
  }
  default <- saved_analysis(nb_choices())
  expect_identical(default$mtry, "all")
  expect_identical(default$k, 5)
  expect_identical(default$n_knots, 10)
  expect_identical(saved_analysis(nb_choices(MTRY = 2L))$mtry, 2L)
})

test_that("the cache is reused unchanged, and a changed setting stops until REFIT", {
  nb_skip_unless_stack()
  root <- nb_study()
  env <- nb_fit_in(root)
  cache <- file.path(hvtiRutilities::study_dir("estimates", root), "lvef-boost", "nb-boostmtree_fit-fit0.rds")
  before <- list(md5 = unname(tools::md5sum(cache)), mtime = file.mtime(cache))
  env2 <- nb_fit_in(root)
  # Reused, not refitted to an equal result: the cache file is untouched.
  expect_identical(list(md5 = unname(tools::md5sum(cache)), mtime = file.mtime(cache)), before)
  expect_identical(env2$fit$id.unique, env$fit$id.unique)
  # The stale cache stops and names what changed.
  expect_error(nb_fit_in(root, choices = nb_choices(NU = 0.01)), "inputs$NU", fixed = TRUE,
               class = "hvtiRutilities_stale_cache")
  env3 <- nb_fit_in(root, choices = nb_choices(NU = 0.01, REFIT = TRUE))
  expect_s3_class(env3$fit, "boostmtree")
})

test_that("MTRY reaches boostmtree(), and NULL leaves boostmtree's default", {
  nb_skip_unless_stack()
  seen <- list()
  fit_with <- function(choices) {
    env <- nb_env(nb_study())
    env$boostmtree <- function(...) {
      seen[[length(seen) + 1L]] <<- list(...)["mtry"]
      boostmtree::boostmtree(...)
    }
    utils::capture.output(nb_fit_run(c("setup", "edit-study-choices", "tbl-data", "fit"), env, choices))
  }
  fit_with(nb_choices(MTRY = 2L))
  expect_identical(seen[[1L]]$mtry, 2L)
  fit_with(nb_choices())
  expect_true("mtry" %in% names(seen[[2L]]))
  expect_null(seen[[2L]]$mtry)
})

test_that("CORES reaches boostmtree.control()", {
  nb_skip_unless_stack()
  seen <- NULL
  env <- nb_env(nb_study())
  # Records what the template asked for, then fits on one core: boostmtree warns
  # on Windows for more than one, and the fit is the same either way.
  env$boostmtree.control <- function(...) {
    seen <<- list(...)$cv.cores
    boostmtree::boostmtree.control(cv.cores = 1L)
  }
  utils::capture.output(nb_fit_run(c("setup", "edit-study-choices", "tbl-data", "fit"), env, nb_choices(CORES = 2L)))
  expect_identical(seen, 2L)
})

test_that("changing CORES reuses the cached fit rather than stopping", {
  nb_skip_unless_stack()
  root <- nb_study()
  # Unmocked, as a study runs it. Windows cannot fork and says so when asked
  # for two cores; that notice, and nothing else, is muffled.
  fit_with <- function(cores) {
    withCallingHandlers(nb_fit_in(root, choices = nb_choices(CORES = cores)), warning = function(w) {
      if (grepl("which Windows does not support", conditionMessage(w), fixed = TRUE)) invokeRestart("muffleWarning")
    })
  }
  env <- fit_with(2L)
  cache <- file.path(hvtiRutilities::study_dir("estimates", root), "lvef-boost", "nb-boostmtree_fit-fit0.rds")
  before <- list(md5 = unname(tools::md5sum(cache)), mtime = file.mtime(cache))
  # The fit is identical on any number of cores, so CORES is left out of the cache key.
  env2 <- fit_with(1L)
  expect_identical(list(md5 = unname(tools::md5sum(cache)), mtime = file.mtime(cache)), before)
  expect_identical(env2$fit$id.unique, env$fit$id.unique)
})

test_that("the fit reports its steps, and progress is not in the cache key", {
  nb_skip_unless_stack()
  local_child_chunks()
  root <- nb_study()
  labels <- c("tbl-data", "fit", "tbl-fit", "tbl-fit-summary")
  env <- nb_env(root)
  nb_fit_run(c("setup", "edit-study-choices"), env, nb_choices())
  seen <- new.env(parent = emptyenv())
  seen$units <- character()
  # The closures live in a bare environment: the fit keeps the reporter, and the cache saves it.
  bare <- list2env(list(seen = seen), parent = baseenv())
  env$.job$progress <- function(unit) {
    force(unit)
    function(step, steps) seen$units <- c(seen$units, unit)
  }
  environment(env$.job$progress) <- bare
  utils::capture.output(nb_fit_run(labels, env))
  expect_true("iteration" %in% seen$units)
  # A fit may keep the reporter through boostmtree's formula environment, and the cache then saves it; randomForestSRC
  # 3.10.0 strips that environment, so it may not. Either is safe while a frame holding it holds only `unit`: no run
  # record, and nothing else of the job, rides along in the saved fit.
  envs <- nb_reachable_envs(env$fit)
  holders <- Filter(function(e) "unit" %in% ls(e, all.names = TRUE), envs)
  expect_true(all(vapply(holders, function(e) identical(ls(e, all.names = TRUE), "unit"), logical(1L))))
  expect_false(any(vapply(envs, function(e) any(c(".job", ".root") %in% ls(e, all.names = TRUE)), logical(1L))))
  # The reporter above is this test's own; the package's real one must hold no more than `unit` either.
  expect_identical(ls(environment(hvtiRtemplates:::.progress_step("iteration")), all.names = TRUE), "unit")
  # A second run loads both from the cache: the reporter, and the run record behind it, are not key inputs.
  env2 <- nb_env(root)
  nb_fit_run(c("setup", "edit-study-choices"), env2, nb_choices())
  env2$.job$progress <- function(unit) NULL
  expect_no_error(utils::capture.output(nb_fit_run(labels, env2)))
})
test_that("the fit chunk refuses to start an uncached fit interactively, and names run_job()", {
  nb_skip_unless_stack()
  withr::local_options(rlang_interactive = TRUE, hvtiRtemplates.allow_interactive_fit = NULL)
  withr::local_envvar(HVTI_ALLOW_LONG_FIT = NA)
  env <- nb_env(nb_study())
  env$guard_long_fit <- hvtiRtemplates::guard_long_fit
  expect_error(utils::capture.output(nb_fit_run(c("setup", "edit-study-choices", "tbl-data", "fit"), env, nb_choices())),
               "run_job(", fixed = TRUE)
})

test_that("the fit chunk runs interactively once the fit is cached, REFIT left TRUE included", {
  nb_skip_unless_stack()
  root <- nb_study()
  nb_fit_in(root)
  withr::local_options(rlang_interactive = TRUE, hvtiRtemplates.allow_interactive_fit = NULL)
  withr::local_envvar(HVTI_ALLOW_LONG_FIT = NA)
  env <- nb_env(root)
  expect_no_error(utils::capture.output(nb_fit_run(c("setup", "edit-study-choices", "tbl-data", "fit"), env, nb_choices())))
  # A key that matches loads under REFIT, as cache_fit() does, so the Render button rerenders after run_job().
  env2 <- nb_env(root)
  expect_no_error(utils::capture.output(nb_fit_run(c("setup", "edit-study-choices", "tbl-data", "fit"), env2,
                                                   nb_choices(REFIT = TRUE))))
})

test_that("a cached fit with REFIT left TRUE guards no memory; a stale one with REFIT guards the fit", {
  nb_skip_unless_stack()
  root <- nb_study()
  nb_fit_in(root)
  needs <- numeric()
  testthat::local_mocked_bindings(guard_memory = function(need_gib, ...) {
    needs <<- c(needs, need_gib)
    invisible(TRUE)
  })
  # The key matches, so cache_fit() loads the fit although REFIT is TRUE: nothing is allocated for fitting.
  utils::capture.output(nb_fit_run(c("setup", "edit-study-choices", "tbl-data", "fit"), nb_env(root), nb_choices(REFIT = TRUE)))
  expect_identical(needs, 0)
  # A changed setting with REFIT recomputes, so the estimate is guarded.
  utils::capture.output(nb_fit_run(c("setup", "edit-study-choices", "tbl-data", "fit"), nb_env(root),
                                   nb_choices(NU = 0.01, REFIT = TRUE)))
  expect_gt(needs[[2L]], 0)
})

test_that("the nb-boostmtree_fit fit chunk guards memory before cache_fit()", {
  tpl <- readLines(nb_template("nb.boostmtree_fit"), warn = FALSE)
  guards <- grep("guard_memory(", tpl, fixed = TRUE)
  cache <- grep("cache_fit(", tpl, fixed = TRUE)
  # One for the fit, one for the sensitivity grid, each ahead of the fits it guards.
  expect_length(guards, 2L)
  fit <- guards[[1L]]
  expect_lt(fit, min(cache[cache > fit]))
  # Not inside an if (): a cached rerender must still record the check run_job() waits for.
  expect_match(tpl[fit], "^hvtiRtemplates::guard_memory\\(")
  # The refusal names the counts the estimate was made from (spec section 5.2).
  expect_match(paste(tpl[fit:(fit + 3L)], collapse = " "), "patients.*visits", perl = TRUE)
  # The grid fits through .at_cell(i, fit = TRUE), not a literal cache_fit( call; require that call to be found,
  # so a guard moved after it fails here rather than comparing against min(integer(0)) = Inf.
  sens <- grep("label: sensitivity", tpl, fixed = TRUE)
  expect_length(sens, 1L)
  grid_fit <- grep(".at_cell(i, fit = TRUE)", tpl, fixed = TRUE)
  expect_length(grid_fit, 1L)
  expect_gt(guards[[2L]], sens)
  expect_lt(guards[[2L]], grid_fit)
})

test_that("the saved lineage and the report provenance record the same tuning choices", {
  tpl <- readLines(nb_template("nb.boostmtree_fit"), warn = FALSE)
  # Each analysis = list(...) block, joined with its continuation line.
  at <- grep("analysis = list(response = .response", tpl, fixed = TRUE)
  expect_length(at, 2L)
  blocks <- vapply(at, function(i) paste(trimws(tpl[i:(i + 1L)]), collapse = " "), "")
  expect_identical(blocks[[1L]], blocks[[2L]])
  expect_match(blocks[[1L]], 'mtry = if (is.null(MTRY)) "all" else MTRY', fixed = TRUE)
})

test_that("K and N_KNOTS reach boostmtree() as k and n.knots", {
  nb_skip_unless_stack()
  seen <- NULL
  env <- nb_env(nb_study())
  env$boostmtree <- function(...) {
    seen <<- list(...)[c("k", "n.knots")]
    boostmtree::boostmtree(...)
  }
  utils::capture.output(nb_fit_run(c("setup", "edit-study-choices", "tbl-data", "fit"), env, nb_choices(K = 3, N_KNOTS = 4)))
  expect_identical(seen, list(k = 3, n.knots = 4))
})

test_that("N_KNOTS at or above the number of visit times stops before anything is fitted", {
  nb_skip_unless_stack()
  d <- nb_data()
  # Scheduled visits: each patient's k-th visit at time k - 1, so six distinct times in all.
  d$iv_echo <- stats::ave(d$iv_echo, d$ccfid, FUN = seq_along) - 1
  env <- nb_env(nb_study(d))
  env$boostmtree <- function(...) stop("fitted")
  expect_error(utils::capture.output(nb_fit_run(c("setup", "edit-study-choices", "tbl-data", "fit"), env,
                                                nb_choices(N_KNOTS = 6))),
               "N_KNOTS (6) must be below the number of distinct visit times (6)", fixed = TRUE)
})

test_that("the report warns when Best M is at the edge of M, and when lambda reached its ceiling", {
  nb_skip_unless_stack()
  env <- nb_env(nb_study())
  utils::capture.output(nb_fit_run(c("setup", "edit-study-choices", "tbl-data", "fit", "tbl-fit-summary"), env,
                                   nb_choices(M = 10)))
  # Best M well inside M, lambda below its ceiling: no warning.
  env$fit$m.opt <- 3L
  env$fit_summary$best_m <- 3L
  env$fit$lambda[] <- 1
  out <- utils::capture.output(nb_fit_run("fit-checks", env))
  expect_false(any(grepl("callout-warning", out, fixed = TRUE)))
  expect_false(env$fit_checks$m_at_edge)
  expect_false(env$fit_checks$lambda_at_max)
  # Best M at M but the error flat over the last tenth (0.05%, as a study's M = 500 fit was): no warning.
  # The error path is read from .err, which tbl-fit-summary leaves; iteration 9 opens the last tenth of 10.
  env$fit$m.opt <- 10L
  env$fit_summary$best_m <- 10L
  env$.err[[1L]][, "l2"] <- 1
  env$.err[[1L]][9L, "l2"] <- 1.0005
  out <- utils::capture.output(nb_fit_run("fit-checks", env))
  expect_false(any(grepl("callout-warning", out, fixed = TRUE)))
  expect_false(env$fit_checks$m_at_edge)
  expect_equal(env$fit_checks$last_tenth_drop, 0.0005)
  # Best M at M with the error still falling (0.5% over the last tenth), lambda at boostmtree's lambda.max:
  # one warning for each.
  env$.err[[1L]][9L, "l2"] <- 1.005
  env$fit$lambda[] <- formals(boostmtree::boostmtree)$lambda.max
  out <- paste(utils::capture.output(nb_fit_run("fit-checks", env)), collapse = "\n")
  expect_match(out, "last tenth of the 10 iterations fitted, and the cross-validated error fell 0.50%", fixed = TRUE)
  expect_match(out, "reached boostmtree's ceiling", fixed = TRUE)
  expect_true(env$fit_checks$m_at_edge)
  expect_true(env$fit_checks$lambda_at_max)
})

test_that("SENSITIVITY refits over NU and K, reuses this fit for its own cell, and a re-render loads the grid", {
  skip_on_cran()
  nb_skip_unless_stack()
  local_child_chunks()
  root <- nb_study()
  labels <- c("setup", "edit-study-choices", "tbl-data", "fit", "tbl-fit-summary", "sensitivity")
  choices <- nb_choices(M = 4, SENSITIVITY = TRUE)
  env <- nb_env(root)
  out <- paste(utils::capture.output(nb_fit_run(labels, env, choices)), collapse = "\n")
  s <- env$sensitivity
  expect_identical(nrow(s), 6L)
  expect_setequal(paste(s$nu, s$k), paste(rep(c(0.01, 0.05), 3L), rep(c(3, 5, 8), each = 2L)))
  # M scaled to hold M * NU: 4 * 0.05 / 0.01 is 20, not the 21 floating point would give.
  expect_identical(s$m[s$nu == 0.01], rep(20L, 3L))
  expect_identical(s$m[s$nu == 0.05], rep(4L, 3L))
  # This job's own cell is the fit above, not a refit, so its change is exactly zero.
  expect_identical(s$change[s$nu == 0.05 & s$k == 5], 0)
  expect_identical(s$best_m[s$nu == 0.05 & s$k == 5], as.integer(env$fit$m.opt))
  set_dir <- file.path(hvtiRutilities::study_dir("estimates", root), "lvef-boost")
  expect_length(list.files(set_dir, "^nb-boostmtree_fit-sensitivity-.*\\.rds$"), 5L)
  expect_match(out, "Sensitivity to NU and K", fixed = TRUE)
  expect_match(out, "moves by at most", fixed = TRUE)
  # A re-render loads every cell from its cache, unchanged.
  env2 <- nb_env(root)
  utils::capture.output(nb_fit_run(labels, env2, choices))
  expect_identical(env2$sensitivity, s)
})

test_that("every fit-side report chunk draws for every family, from a fresh fit and from the cache", {
  skip_on_cran()
  nb_skip_unless_stack()
  labels <- c("setup", "edit-study-choices", "tbl-data", "fit", "tbl-fit", "tbl-fit-summary", "fit-checks", "fig-error",
              "fig-path", "fig-calibration", "sensitivity", "tbl-versions", "save")
  components <- list(continuous = "lvef", binary = "lvef_bin = 1 against 0",
                     ordinal = c("lvef_ord threshold 1", "lvef_ord threshold 2"),
                     nominal = c("lvef_nom = low against high", "lvef_nom = mid against high"))
  for (family in names(nb_families)) {
    root <- nb_study(nb_family_data())
    choices <- nb_choices(RESPONSE = nb_families[[family]], FAMILY = family, PREDICTORS = c("age", "female", "grp"))
    for (pass in 1:2) {
      env <- nb_env(root)
      utils::capture.output(nb_fit_run(labels, env, choices))
      for (p in c("p_error", "p_path", "p_calibration")) {
        expect_s3_class(env[[p]], "ggplot")
        expect_no_error(ggplot2::ggplot_build(env[[p]]))
      }
      expect_identical(env$fit_summary$component, components[[family]], info = family)
      expect_identical(env$fit_checks$component, components[[family]], info = family)
      expect_null(env$sensitivity)
      expect_length(nb_files_holding(root, unique(nb_family_data()$ccfid)), 0L)
    }
  }
})

test_that("the fit saves the bundle, with lineage on the outer list only", {
  nb_skip_unless_stack()
  root <- nb_study()
  env <- nb_fit_in(root)
  bundle <- readRDS(nb_bundle_path(root))
  expect_identical(names(bundle), c("fit", "refits", "versions", "k_shadow", "seed"))
  expect_s3_class(bundle$fit, "boostmtree")
  expect_s3_class(bundle$fit, "grow")
  expect_identical(bundle$refits, list())
  expect_identical(bundle$k_shadow, 5)
  expect_identical(bundle$seed, 7)
  lineage <- attr(bundle, "hvti_provenance")
  expect_true(hvtiRtemplates:::.complete_lineage_shape(lineage))
  expect_gt(length(lineage$data), 0L)
  expect_identical(lineage$analysis$k_shadow, 5)
  expect_identical(lineage$analysis$n_refits, 0)
  expect_null(attr(bundle$fit, "hvti_provenance"))
  # The deprecated template's handoff name is never written.
  expect_false(file.exists(file.path(nb_set_dir(root), "nb-boostmtree.rds")))
  expect_false(file.exists(file.path(nb_set_dir(root), "nb-boostmtree-fit.rds")))
})

test_that("the bundle records the versions the fit was grown with", {
  nb_skip_unless_stack()
  root <- nb_study()
  nb_fit_in(root)
  versions <- readRDS(nb_bundle_path(root))$versions
  expect_identical(names(versions), c("boostmtree", "randomForestSRC", "ggBoostedTrees"))
  expect_identical(unname(versions), vapply(names(versions), function(p) format(utils::packageVersion(p)), "",
                                            USE.NAMES = FALSE))
})

test_that("shadows reach the fit, and K_SHADOW is part of the cache key", {
  nb_skip_unless_stack()
  root <- nb_study()
  env <- nb_fit_in(root)
  expect_true(all(c("age", "female", "grp") %in% env$fit$x.var.names))
  expect_length(grep("^shadow[1-5][.]", env$fit$x.var.names), 15L)
  expect_error(nb_fit_in(root, choices = nb_choices(K_SHADOW = 0)), "inputs$K_SHADOW", fixed = TRUE,
               class = "hvtiRutilities_stale_cache")
  env0 <- nb_fit_in(root, choices = nb_choices(K_SHADOW = 0, REFIT = TRUE))
  expect_length(grep("^shadow", env0$fit$x.var.names), 0L)
  expect_identical(readRDS(nb_bundle_path(root))$k_shadow, 0)
})

test_that("a predictor that varies within a patient stops before any guard or fit, unless K_SHADOW is 0", {
  nb_skip_unless_stack()
  data <- nb_data()
  data$hr <- 60 + seq_len(nrow(data)) %% 7
  root <- nb_study(data)
  env <- nb_env(root)
  # Stopped before any guard: nothing cached, nothing saved.
  expect_error(utils::capture.output(nb_fit_run(c("setup", "edit-study-choices", "tbl-data", "fit"), env, nb_choices())),
               "vary between visits.*hr.*K_SHADOW <- 0")
  expect_length(list.files(nb_set_dir(root), "[.]rds$"), 0L)
  expect_no_error(nb_fit_in(root, choices = nb_choices(K_SHADOW = 0)))
})

test_that("N_REFITS grows each refit under SEED + i, caches it, and the summary and error figure use them", {
  nb_skip_unless_stack()
  root <- nb_study()
  labels <- c("setup", "edit-study-choices", "tbl-data", "fit", "tbl-fit-summary", "fig-error", "save")
  env0 <- nb_env(root)
  utils::capture.output(nb_fit_run(labels, env0, nb_choices()))
  env <- nb_env(root)
  utils::capture.output(nb_fit_run(labels, env, nb_choices(N_REFITS = 2)))
  expect_true(all(file.exists(file.path(nb_set_dir(root), sprintf("nb-boostmtree_fit-fit%d.rds", 0:2)))))
  expect_identical(env$.fit_seeds, 7 + 0:2)
  expect_length(env$refits, 2L)
  expect_false(identical(env$refits[[1L]]$mu, env$fit$mu))
  # The SEED fit is the one already cached: adding refits does not refit it.
  expect_identical(env$fit$mu, env0$fit$mu)
  expect_true("best_m_range" %in% names(env$fit_summary))
  expect_length(env$p_error$layers, length(env0$p_error$layers) + 1L)
  expect_length(readRDS(nb_bundle_path(root))$refits, 2L)
  expect_identical(attr(readRDS(nb_bundle_path(root)), "hvti_provenance")$analysis$n_refits, 2)
})

test_that("the plateau is every iteration within 1% of the lowest error, and Best M lies on it", {
  nb_skip_unless_stack()
  root <- nb_study()
  env <- nb_env(root)
  utils::capture.output(nb_fit_run(c("setup", "edit-study-choices", "tbl-data", "fit", "tbl-fit-summary"), env,
                                   nb_choices(M = 20)))
  e <- if (is.matrix(env$fit$err.rate)) env$fit$err.rate else env$fit$err.rate[[1L]]
  p <- which(e[, "l2"] <= 1.01 * min(e[, "l2"]))
  expect_identical(env$fit_summary$plateau, paste0(min(p), " to ", max(p)))
  expect_equal(env$fit_summary$plateau_error, unname(e[min(p), "l2"]))
  expect_true(env$fit_summary$best_m >= min(p) && env$fit_summary$best_m <= max(p))
})

test_that("the report provenance carries the versions and the shadow and refit choices", {
  tpl <- readLines(nb_template("nb.boostmtree_fit"), warn = FALSE)
  prov <- grep("label: provenance", tpl, fixed = TRUE)
  expect_true(any(grepl("versions = as.list(.versions)", tpl[prov:length(tpl)], fixed = TRUE)))
  expect_true(any(grepl("k_shadow = K_SHADOW, n_refits = N_REFITS", tpl[prov:length(tpl)], fixed = TRUE)))
})
