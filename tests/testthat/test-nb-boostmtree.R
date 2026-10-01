test_that("add_job scaffolds nb-boostmtree with its subject and type", {
  dir <- withr::local_tempdir("nb-job-")
  job <- add_job("nb", subject = "lvef", type = "boost", dir = dir, qualifier = "boostmtree")
  expect_match(basename(job), "^lvef-boost-nb-boostmtree[.]qmd$")
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
  out <- utils::capture.output(nb_run(c("edit-study-choices", "data"), env, nb_choices()))
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
  expect_error(utils::capture.output(nb_run(c("edit-study-choices", "data"), env, nb_choices())), "unique")
})

test_that("the ID and TIME cannot be predictors, nor the ID the response", {
  nb_skip_unless_stack()
  root <- nb_study()
  run <- function(...) {
    env <- nb_env(root)
    utils::capture.output(nb_run(c("edit-study-choices", "data"), env, nb_choices(...)))
  }
  expect_error(run(PREDICTORS = c("age", "ccfid")), "identifier or the visit time")
  expect_error(run(PREDICTORS = c("age", "iv_echo")), "identifier or the visit time")
  expect_error(run(RESPONSE = "ccfid"), "cannot be the response")
})

test_that("TIME and RESPONSE resolve against the data ignoring case", {
  nb_skip_unless_stack()
  root <- nb_study()
  env <- nb_env(root)
  utils::capture.output(nb_run(c("edit-study-choices", "data"), env, nb_choices(TIME = "IV_ECHO", RESPONSE = "LVEF")))
  expect_identical(env$.time, "iv_echo")
  expect_identical(env$.response, "lvef")
  expect_identical(sort(names(env$d)), sort(c("ccfid", "iv_echo", "lvef", "age", "female", "grp")))
  expect_identical(sort(env$.predictors), sort(c("age", "female", "grp")))
  env <- nb_env(root)
  expect_error(utils::capture.output(nb_run(c("edit-study-choices", "data"), env,
                                            nb_choices(TIME = "IV_ECHO", PREDICTORS = c("age", "IV_ECHO")))),
               "identifier or the visit time")
})

test_that("the setup chunk passes when both packages meet their floors", {
  nb_skip_unless_stack()
  expect_no_error(nb_mocked_setup("neither", "0.0.0"))
})

test_that("boostmtree older than 2.0.2 is refused with the fork's install line", {
  nb_skip_unless_stack()
  expect_error(nb_mocked_setup("boostmtree", "2.0.0"), "ehrlinger/boostmtree_src", fixed = TRUE)
})

test_that("ggBoostedTrees older than 0.0.7 is refused with its install line", {
  nb_skip_unless_stack()
  expect_error(nb_mocked_setup("ggBoostedTrees", "0.0.6"), "remotes::install_github(\"ehrlinger/ggBoostedTrees\")", fixed = TRUE)
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
  testthat::skip_if_not(exists(".refuse_identifier_where", envir = asNamespace("hvtiRtemplates"), inherits = FALSE),
                        "needs the WHERE refusal from fix/where-refuses-id")
  # The data contract refuses it (fix/where-refuses-id, merged before this PR):
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
