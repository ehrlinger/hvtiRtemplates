test_that("add_job() scaffolds bd into the study's 00_datasets folder", {
  root <- bd_study()
  job <- add_job("bd", "study", "build", dir = root)
  expect_identical(basename(dirname(job)), "00_datasets")
  lines <- readLines(job, warn = FALSE)
  expect_true(any(lines == "SUBJECT <- \"study\""))
  expect_true(any(lines == "TYPE    <- \"build\""))
})

test_that("a run without REGISTER writes the working file and its record and registers nothing", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  env <- bd_run(root, list(MASTER = m$parquet, KEEP = c("age", "iv_dead", "dead", "dt_surg"),
                           EXCLUDE = list(age < 40 ~ "Under 40")))
  datasets <- hvtiRutilities::study_dir("datasets", root)
  expect_true(file.exists(file.path(datasets, "study_cohort.rds")))
  expect_true(file.exists(file.path(datasets, "study_cohort.build.yml")))
  expect_length(bd_versions(root), 0L)
  expect_null(hvtiRutilities::study_config(root, require_data = FALSE)$built)
  expect_null(env$.version_after)
  expect_identical(env$.cut$attrition$reason, c("Rows read", "Under 40"))
  # A missing age is not excluded.
  expect_identical(nrow(env$d), nrow(m$data) - sum(m$data$age < 40, na.rm = TRUE))
})

test_that("the dataset carries ID, KEY, JOIN_BY and KEEP columns, and drops MRN", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  env <- bd_run(root, list(MASTER = m$parquet, KEEP = c("age", "mrn"), EXCLUDE = NULL))
  expect_setequal(names(env$d), c("ccfid", "dt_surg", "age"))
  built <- readRDS(file.path(hvtiRutilities::study_dir("datasets", root), "study_cohort.rds"))
  expect_identical(names(built), names(env$d))
})

test_that("the build record describes the working file and the master, and holds no key", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  choices <- list(MASTER = m$parquet, KEEP = "age", EXCLUDE = list(ccfid == "PT00003" ~ "Withdrew consent"))
  env <- bd_run(root, choices)
  rec <- yaml::read_yaml(env$.record_file)
  meta <- jsonlite::read_json(sub("[.]parquet$", ".meta.json", m$parquet))
  expect_identical(rec$schema, 1L)
  expect_identical(rec$built_sha256, digest::digest(env$.built, algo = "sha256", file = TRUE))
  expect_identical(rec$master$sha256, meta$parquet_sha256)
  expect_identical(rec$view, basename(m$parquet))
  expect_true(rec$derived_after_overlay)
  expect_true("overlay_sha256" %in% names(rec))
  expect_identical(rec$attrition$reason, c("Rows read", "Withdrew consent"))
  # A rule naming a patient stays in the job: the record carries its hash, not its text.
  expect_false(any(grepl("PT00003", readLines(env$.record_file), fixed = TRUE)))
  expect_match(rec$cohort_sha256, "^[0-9a-f]{64}$")
  # Replaced whole: modifyList() would merge the two unnamed rule lists and keep the first rule.
  choices$EXCLUDE <- list(ccfid == "PT00004" ~ "Withdrew consent")
  other <- bd_run(root, choices)
  expect_false(identical(yaml::read_yaml(other$.record_file)$cohort_sha256, rec$cohort_sha256))
})

test_that("REGISTER registers the working file as a dated version whose provenance is bd", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  choices <- list(MASTER = m$parquet, KEEP = "age", EXCLUDE = NULL, REGISTER = TRUE)
  env <- bd_run(root, choices)
  expect_identical(hvtiRutilities::study_config(root)$built, "study_cohort.rds")
  expect_null(env$.version_before)
  expect_identical(env$.version_after, bd_current_version(root))
  expect_identical(env$.register_step, "Registered as the study dataset")
  prov <- bd_provenance(root)
  expect_identical(prov$origin, "bd")
  expect_identical(prov$build$view, basename(m$parquet))
  # The record moved beside the version it describes.
  datasets <- hvtiRutilities::study_dir("datasets", root)
  expect_true(file.exists(file.path(datasets, prov$build$record)))
  expect_false(file.exists(file.path(datasets, "study_cohort.build.yml")))
  # The same cut again registers nothing.
  again <- bd_run(root, choices)
  expect_identical(again$.register_step, "Unchanged since the version registered: nothing to do")
  expect_length(bd_versions(root), 1L)
})

test_that("a study registered under this job's file without a build record takes the build as a new version", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  datasets <- hvtiRutilities::study_dir("datasets", root)
  # Registered as a legacy study would be: the file bd writes, with no build record beside it.
  saveRDS(data.frame(ccfid = "PT00001", age = 50), file.path(datasets, "study_cohort.rds"))
  suppressMessages(hvtiRutilities::register_data(root, built = "study_cohort.rds"))
  legacy <- bd_current_version(root)
  expect_identical(bd_provenance(root, legacy)$origin, "legacy")
  env <- bd_run(root, list(MASTER = m$parquet, KEEP = "age", EXCLUDE = NULL, REGISTER = TRUE))
  expect_identical(env$.version_before, legacy)
  expect_identical(env$.register_step, "Registered as a new version of the study dataset")
  expect_identical(bd_provenance(root)$origin, "bd")
  expect_length(bd_versions(root), 2L)
})

# Every stop names the step and this file, and no message carries a value.
bd_expect_stop <- function(root, choices, step, labels = NULL) {
  ids <- c(sprintf("PT%05d", 1:200), sprintf("M%07d", 1:200))
  # nolint start: object_usage_linter.
  run <- if (is.null(labels)) function() bd_run(root, choices) else function() bd_run(root, choices, labels)
  # nolint end
  err <- testthat::expect_error(run(), paste0("^bd: ", step, " \\("))
  testthat::expect_false(any(vapply(ids, grepl, logical(1L), x = conditionMessage(err), fixed = TRUE)))
}

test_that("failures name the step and the file, never a value", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  ok <- list(MASTER = m$parquet, KEEP = "age", EXCLUDE = NULL)
  bd_expect_stop(root, utils::modifyList(ok, list(DATASET_ID = "Study-1")), "check-choices")
  bd_expect_stop(root, utils::modifyList(ok, list(KEEP = character())), "check-choices")
  bd_expect_stop(root, utils::modifyList(ok, list(MASTER = file.path(tempdir(), "absent.parquet"))), "read-master")
  bd_expect_stop(root, utils::modifyList(ok, list(KEEP = c("age", "no_such_column"))), "read-master")
  bd_expect_stop(root, utils::modifyList(ok, list(EXCLUDE = list(ccfid == "PT00001" & nope ~ "Broken"))), "cohort")
  bd_expect_stop(root, utils::modifyList(ok, list(EXCLUDE = list(!is.na(ccfid) ~ "Everyone"))), "cohort")
  bd_expect_stop(root, utils::modifyList(ok, list(KEY = "dead")), "write-built")
  # A sidecar that disagrees with its parquet, under VERIFY_MASTER.
  bad <- bd_master()
  meta <- sub("[.]parquet$", ".meta.json", bad$parquet)
  json <- jsonlite::read_json(meta)
  json$parquet_sha256 <- strrep("0", 64L)
  jsonlite::write_json(json, meta, auto_unbox = TRUE, null = "null")
  bd_expect_stop(root, utils::modifyList(ok, list(MASTER = bad$parquet, VERIFY_MASTER = TRUE)), "read-master")
})

test_that("a derivation that changes the row count stops in derive", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  env <- new.env(parent = globalenv())
  choices <- list(MASTER = m$parquet, KEEP = "age", EXCLUDE = NULL)
  withr::with_dir(root, utils::capture.output(hazard_run("bd", c("setup", "set", "edit-study-choices", "check-choices",
                                                                 "read-master", "cohort"), env, choices)))
  # The derive chunk itself records the count the cohort step left.
  withr::with_dir(root, utils::capture.output(hazard_run("bd", "derive", env)))
  expect_identical(env$.rows_before_derive, nrow(env$.cut$data))
  # Simulate a derive chunk that dropped a row.
  env$d <- env$d[-1L, , drop = FALSE]
  src <- readLines(hazard_template("bd"), warn = FALSE)
  at <- which(trimws(src) == "#| label: derive")
  end <- at + which(src[(at + 1L):length(src)] == "```")[1L]
  body <- src[(at + 1L):(end - 1L)]
  start <- grep("^if \\(nrow\\(d\\) != [.]rows_before_derive\\)", body)
  expect_length(start, 1L)
  # The check spans lines: from the `if` to the closing brace.
  check <- body[start:(start - 1L + which(body[start:length(body)] == "}")[1L])]
  expect_error(eval(parse(text = check), envir = env), "^bd: derive \\(")
})

test_that("a study registered under another file stops register before registering anything", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  datasets <- hvtiRutilities::study_dir("datasets", root)
  # A study registered as a file this job does not write, as a SAS-built study is.
  utils::write.csv(data.frame(ccfid = "PT00001", age = 50), file.path(datasets, "built.csv"), row.names = FALSE)
  suppressWarnings(suppressMessages(hvtiRutilities::register_data(root, built = "built.csv")))
  before <- bd_current_version(root)
  bd_expect_stop(root, list(MASTER = m$parquet, KEEP = "age", EXCLUDE = NULL, REGISTER = TRUE), "register")
  # A file this job could not have written: no DATASET_ID to suggest.
  err <- expect_error(bd_run(root, list(MASTER = m$parquet, KEEP = "age", EXCLUDE = NULL, REGISTER = TRUE)))
  expect_false(grepl("DATASET_ID", conditionMessage(err), fixed = TRUE))
  expect_identical(hvtiRutilities::study_config(root)$built, "built.csv")
  expect_identical(bd_current_version(root), before)
  expect_length(bd_versions(root), 0L)
})

test_that("a DATASET_ID other than the registered one stops register before registering anything", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  choices <- list(MASTER = m$parquet, KEEP = "age", EXCLUDE = NULL, REGISTER = TRUE)
  bd_run(root, choices)
  expect_length(bd_versions(root), 1L)
  bd_expect_stop(root, utils::modifyList(choices, list(DATASET_ID = "other_cohort")), "register")
  expect_error(bd_run(root, utils::modifyList(choices, list(DATASET_ID = "other_cohort"))),
               "Set DATASET_ID to \"study_cohort\"", fixed = TRUE)
  expect_identical(hvtiRutilities::study_config(root)$built, "study_cohort.rds")
  expect_length(bd_versions(root), 1L)
  expect_length(bd_versions(root, "other_cohort"), 0L)
})

test_that("a cohort list in the study's datasets folder cuts the dataset to the patients it names", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  pick <- m$data[c(3L, 10L, 25L), ]
  list_file <- file.path(hvtiRutilities::study_dir("datasets", root), "cohort.csv")
  utils::write.csv(data.frame(ccfid = pick$ccfid, dt_surg = format(pick$dt_surg, "%Y-%m-%d")), list_file, row.names = FALSE)
  env <- bd_run(root, list(MASTER = m$parquet, KEEP = "age", EXCLUDE = NULL, COHORT = list_file,
                           JOIN_BY = c("ccfid", "dt_surg")))
  expect_identical(nrow(env$d), 3L)
  expect_setequal(env$d$ccfid, pick$ccfid)
})

test_that("a master snapshot without its sidecar stops in read-master", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  unlink(sub("[.]parquet$", ".meta.json", m$parquet))
  bd_expect_stop(root, list(MASTER = m$parquet, KEEP = "age", EXCLUDE = NULL), "read-master")
})

test_that("a study registered under a dated release file is never told to name it in DATASET_ID", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  datasets <- hvtiRutilities::study_dir("datasets", root)
  # A release file's name: following a DATASET_ID suggestion would overwrite its bytes.
  saveRDS(data.frame(ccfid = "PT00001", age = 50), file.path(datasets, "study_cohort_20261002.rds"))
  suppressMessages(hvtiRutilities::register_data(root, built = "study_cohort_20261002.rds"))
  err <- expect_error(bd_run(root, list(MASTER = m$parquet, KEEP = "age", EXCLUDE = NULL, REGISTER = TRUE)),
                      "^bd: register \\(")
  expect_false(grepl("DATASET_ID", conditionMessage(err), fixed = TRUE))
})
