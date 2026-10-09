test_that("add_job scaffolds nb-boostmtree with its subject and type", {
  dir <- withr::local_tempdir("nb-job-")
  job <- add_job("nb", subject = "lvef", type = "boost", dir = dir, qualifier = "boostmtree")
  expect_match(basename(job), "^nb[.]boostmtree[.]lvef[.]boost[.]qmd$")
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
  out <- utils::capture.output(nb_run(c("edit-study-choices", "tbl-data"), env, nb_choices()))
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
  expect_error(utils::capture.output(nb_run(c("edit-study-choices", "tbl-data"), env, nb_choices())), "unique")
})

test_that("the ID and TIME cannot be predictors, nor the ID the response", {
  nb_skip_unless_stack()
  root <- nb_study()
  run <- function(...) {
    env <- nb_env(root)
    utils::capture.output(nb_run(c("edit-study-choices", "tbl-data"), env, nb_choices(...)))
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
  out <- utils::capture.output(nb_run(c("set", "edit-study-choices", "tbl-data", "fit", "save"), env, nb_randid_choices()))
  expect_identical(env$.id, "randid")
  expect_identical(sort(env$.predictors), sort(c("age", "female", "grp")))
  expect_true(any(grepl("Identifier columns left out of the predictors: ccfid", out, fixed = TRUE)))
  # By name only: no ccfid value is printed.
  expect_false(any(vapply(unique(data$ccfid), function(v) any(grepl(v, out, fixed = TRUE)), logical(1L))))
  expect_true(file.exists(file.path(hvtiRutilities::study_dir("estimates", root), "lvef-boost", "nb-boostmtree.rds")))
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
    utils::capture.output(nb_run(c("set", "edit-study-choices", "tbl-data", "fit", "save"), env, nb_randid_choices(...)))
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
  utils::capture.output(nb_run(c("edit-study-choices", "tbl-data"), env, nb_choices(KEY = c("ccfid", "iv_echo", "visit"))))
  expect_identical(sort(env$.predictors), sort(c("age", "female", "grp")))
})

test_that("named PREDICTORS may hold no identifier or KEY column, and no name twice", {
  nb_skip_unless_stack()
  root <- nb_study(nb_randid_data())
  run <- function(...) {
    env <- nb_env(root)
    utils::capture.output(nb_run(c("edit-study-choices", "tbl-data"), env, nb_randid_choices(...)))
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
  utils::capture.output(nb_run(c("edit-study-choices", "tbl-data"), env, nb_choices(TIME = "IV_ECHO", RESPONSE = "LVEF")))
  expect_identical(env$.time, "iv_echo")
  expect_identical(env$.response, "lvef")
  expect_identical(sort(names(env$d)), sort(c("ccfid", "iv_echo", "lvef", "age", "female", "grp")))
  expect_identical(sort(env$.predictors), sort(c("age", "female", "grp")))
  env <- nb_env(root)
  expect_error(utils::capture.output(nb_run(c("edit-study-choices", "tbl-data"), env,
                                            nb_choices(TIME = "IV_ECHO", PREDICTORS = c("age", "IV_ECHO")))),
               "identifier, a KEY column or the visit time")
})

test_that("the setup chunk passes when both packages meet their floors", {
  nb_skip_unless_stack()
  expect_no_error(nb_mocked_setup("neither", "0.0.0"))
})

test_that("boostmtree older than 2.0.2 is refused with the fork's install line", {
  nb_skip_unless_stack()
  expect_error(nb_mocked_setup("boostmtree", "2.0.0"), "ehrlinger/boostmtree_src", fixed = TRUE)
})

test_that("ggBoostedTrees older than 0.9.0 is refused with its install line", {
  nb_skip_unless_stack()
  expect_error(nb_mocked_setup("ggBoostedTrees", "0.0.9"), "remotes::install_github(\"ehrlinger/ggBoostedTrees\")", fixed = TRUE)
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
                    c("nb-boostmtree.rds", "nb-boostmtree-fit.rds", "nb-boostmtree-fit.provenance.json"))
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
  saved <- readRDS(file.path(hvtiRutilities::study_dir("estimates", root), "lvef-boost", "nb-boostmtree.rds"))
  sel <- attr(saved, "hvti_provenance")$selection
  expect_identical(sel$id, "ccfid")
  expect_identical(sel$key, c("ccfid", "iv_echo"))
})

test_that("the cache is reused unchanged, and a changed setting stops until REFIT", {
  nb_skip_unless_stack()
  root <- nb_study()
  env <- nb_fit_in(root)
  cache <- file.path(hvtiRutilities::study_dir("estimates", root), "lvef-boost", "nb-boostmtree-fit.rds")
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

test_that("every report chunk draws for every family, from a fresh fit and from the cache", {
  skip_on_cran()
  nb_skip_unless_stack()
  # The effects chunk emits each figure as a child chunk.
  local_child_chunks()
  labels <- c("set", "edit-study-choices", "tbl-data", "fit", "tbl-fit", "tbl-fit-summary", "fig-error", "fig-path",
              "fig-calibration", "fig-importance", "effects", "fig-traces", "save")
  components <- list(continuous = "lvef", binary = "lvef_bin = 1 against 0",
                     ordinal = c("lvef_ord threshold 1", "lvef_ord threshold 2"),
                     nominal = c("lvef_nom = low against high", "lvef_nom = mid against high"))
  for (family in names(nb_families)) {
    # A study per family: one set holds one cached fit, and another family's would be stale there.
    root <- nb_study(nb_family_data())
    choices <- nb_choices(RESPONSE = nb_families[[family]], FAMILY = family,
                          PREDICTORS = c("age", "female", "grp"), N_TRACES = 10)
    for (pass in 1:2) {
      env <- nb_env(root)
      utils::capture.output(nb_run(labels, env, choices))
      for (p in c("p_error", "p_path", "p_calibration", "p_vimp", "p_traces")) {
        expect_s3_class(env[[p]], "ggplot")
        expect_no_error(ggplot2::ggplot_build(env[[p]]))
      }
      expect_true(is.list(env$p_effects))
      effects <- env$p_effects
      expect_gte(length(effects), 1L)
      for (e in effects) expect_no_error(ggplot2::ggplot_build(e))
      # One figure per covariate kind draws every effect variable once, continuous and factor alike,
      # each for every response component, named as the summary names it.
      drawn <- unlist(lapply(effects, function(e) as.character(unique(e$data$variable))))
      expect_identical(sort(drawn), sort(env$.effect_vars), info = family)
      for (e in effects) expect_identical(levels(e$data$response), components[[family]], info = family)
      # One summary row per response component, each with its own best M and error there.
      expect_identical(nrow(env$fit_summary), length(env$fit$m.opt), info = family)
      expect_true(all(is.finite(env$fit_summary$cv_error)), info = family)
      expect_false(anyDuplicated(env$.effect_vars) > 0L, info = family)
      # Each component is named by its level, in the summary and on its effect figures.
      expect_identical(env$fit_summary$component, components[[family]], info = family)
      # The save made on each pass, the cache-hit pass included, holds no ccfid.
      expect_length(nb_files_holding(root, unique(nb_family_data()$ccfid)), 0L)
    }
  }
})

test_that("the mean line averages within time bins, not at single visit times", {
  nb_skip_unless_stack()
  root <- nb_study()
  env <- nb_env(root)
  utils::capture.output(nb_run(c("set", "edit-study-choices", "tbl-data", "fit", "fig-traces"), env, nb_choices(N_TRACES = 10)))
  # Every bin stands on more than one patient, and there are fewer bins than distinct times.
  expect_true(all(env$trace_means$n_patients > 1L))
  expect_lt(nrow(env$trace_means), length(unique(env$traces$time)))
})

test_that("the trace sample is reproducible under SEED", {
  nb_skip_unless_stack()
  root <- nb_study()
  labels <- c("set", "edit-study-choices", "tbl-data", "fit", "fig-traces")
  a <- nb_env(root)
  utils::capture.output(nb_run(labels, a, nb_choices(N_TRACES = 10)))
  b <- nb_env(root)
  utils::capture.output(nb_run(labels, b, nb_choices(N_TRACES = 10)))
  expect_identical(sort(unique(as.character(a$p_traces$data$id))), sort(unique(as.character(b$p_traces$data$id))))
})

test_that("no report output prints an identifier", {
  nb_skip_unless_stack()
  # The effects chunk emits each figure as a child chunk.
  local_child_chunks()
  data <- nb_data(id = "MRN")
  root <- nb_study(data)
  env <- nb_env(root)
  out <- utils::capture.output(nb_run(c("set", "edit-study-choices", "tbl-data", "fit", "tbl-fit", "tbl-fit-summary",
                                        "fig-error", "fig-path", "fig-calibration", "fig-importance", "effects", "fig-traces"),
                                      env, nb_choices(N_TRACES = 10)))
  expect_false(any(vapply(unique(data$MRN), function(v) any(grepl(v, out, fixed = TRUE)), logical(1L))))
})


test_that("EFFECT_VARIABLES may name a factor covariate alone", {
  nb_skip_unless_stack()
  local_child_chunks()
  root <- nb_study()
  env <- nb_env(root)
  utils::capture.output(nb_run(c("set", "edit-study-choices", "tbl-data", "fit", "tbl-fit", "tbl-fit-summary", "fig-importance",
                                 "effects"), env, nb_choices(EFFECT_VARIABLES = "grp")))
  expect_length(env$p_effects, 1L)
  expect_identical(as.character(unique(env$p_effects[[1L]]$data$variable)), "grp")
  expect_no_error(ggplot2::ggplot_build(env$p_effects[[1L]]))
})

test_that("visits all at one time draw no mean line, and say so", {
  nb_skip_unless_stack()
  traces <- data.frame(id = factor(rep(c("a", "b"), each = 2L)), time = 1, fitted = c(1, 2, 3, 4),
                       observed = c(1, 2, 3, 4), response = factor("y"))
  class(traces) <- c("gg_boost_trajectory", class(traces))
  env <- nb_env(tempdir())
  env$gg_boost_trajectory <- function(fit) traces
  # The chunk runs alone, without set's save_figure(); saving is tested elsewhere.
  list2env(list(fit = NULL, SEED = 1, N_TRACES = Inf, .time = "iv_echo", .response = "lvef",
                save_figure = function(...) invisible(NULL)), envir = env)
  out <- utils::capture.output(nb_run("fig-traces", env))
  expect_null(env$trace_means)
  expect_true(any(grepl("no mean line is drawn", out, fixed = TRUE)))
  expect_no_error(ggplot2::ggplot_build(env$p_traces))
})

test_that("nb-boostmtree scaffolds and renders end to end, and the page holds no MRN", {
  skip_on_cran()
  nb_skip_unless_stack()
  testthat::skip_if_not_installed("quarto")
  testthat::skip_if_not(quarto::quarto_available(), "Quarto CLI is required for rendering")
  # Keyed on MRN, so the rendered page is searched for the identifier most likely to leak.
  data <- nb_data(id = "MRN")
  root <- nb_study(data)
  job <- add_job("nb", subject = "lvef", type = "boost", dir = root, qualifier = "boostmtree")
  set_choice <- function(from, to) {
    txt <- readLines(job)
    hit <- grep(from, txt)
    stopifnot(length(hit) == 1L)
    txt[hit] <- to
    writeLines(txt, job)
  }
  set_choice("^RESPONSE <- ", "RESPONSE <- \"lvef\"")
  set_choice("^M  <- ", "M  <- 5")
  set_choice("^N_TRACES <- ", "N_TRACES <- 10")
  # EDIT: markers remain, so this renders as a draft, with its warning and banner.
  render_job(job, quiet = TRUE)
  html <- sub("[.]qmd$", ".html", job)
  expect_true(file.exists(html))
  expect_true(file.exists(file.path(hvtiRutilities::study_dir("estimates", root), "lvef-boost", "nb-boostmtree.rds")))
  bytes <- nb_file_bytes(html)
  expect_false(any(vapply(unique(data$MRN), function(v) nb_bytes_hold(bytes, v), logical(1L))))
  page <- rawToChar(bytes)
  expect_match(page, "DRAFT -- this job is unfinished", fixed = TRUE)
  # The provenance chunk runs only in a render: its payload is in the page and its sidecar beside the job.
  payload <- hvtiRtemplates:::.extract_provenance(page)
  expect_identical(payload$subject, "lvef")
  expect_identical(payload$type, "boost")
  expect_identical(payload$analysis$response, "lvef")
  expect_identical(payload$analysis$family, "continuous")
  expect_identical(payload$cohort$n_patients, length(unique(data$MRN)))
  expect_true(file.exists(sub("[.]qmd$", ".provenance.json", job)))
})
