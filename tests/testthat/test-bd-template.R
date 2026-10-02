test_that("add_job() scaffolds bd into the study's 00_datasets folder", {
  root <- bd_study()
  job <- add_job("bd", "study", "build", dir = root)
  expect_identical(basename(dirname(job)), "00_datasets")
  lines <- readLines(job, warn = FALSE)
  expect_true(any(lines == "SUBJECT <- \"study\""))
  expect_true(any(lines == "TYPE    <- \"build\""))
})

test_that("a draft run writes the draft and its record and publishes nothing", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  env <- bd_run(root, list(MASTER = m$parquet, KEEP = c("age", "iv_dead", "dead", "dt_surg"),
                           EXCLUDE = list(age < 40 ~ "Under 40")))
  datasets <- hvtiRutilities::study_dir("datasets", root)
  expect_true(file.exists(file.path(datasets, "draft-study_cohort.rds")))
  expect_true(file.exists(file.path(datasets, "draft-study_cohort.build.yml")))
  expect_false(file.exists(file.path(datasets, "dataset-catalog.yml")))
  expect_null(env$.release)
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
  draft <- readRDS(file.path(hvtiRutilities::study_dir("datasets", root), "draft-study_cohort.rds"))
  expect_identical(names(draft), names(env$d))
})

test_that("the build record holds the master's hash and the rules in full, beside the data", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  env <- bd_run(root, list(MASTER = m$parquet, KEEP = "age", EXCLUDE = list(ccfid == "PT00003" ~ "Withdrew consent")))
  rec <- yaml::read_yaml(env$.record_file)
  meta <- jsonlite::read_json(sub("[.]parquet$", ".meta.json", m$parquet))
  expect_identical(rec$master$sha256, meta$parquet_sha256)
  expect_match(rec$settings$exclude, "PT00003", fixed = TRUE)
  expect_identical(rec$attrition$reason, c("Rows read", "Withdrew consent"))
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
  bd_expect_stop(root, utils::modifyList(ok, list(KEY = "dead")), "write-draft")
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
  env$d <- env$d[-1L, , drop = FALSE]
  # Simulate a derive chunk that dropped a row: the check compares with the
  # count the cohort step left.
  env$.rows_before_derive <- nrow(env$.cut$data)
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

test_that("a legacy-registered dataset (without release) stops publish before writing to disk", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  datasets <- hvtiRutilities::study_dir("datasets", root)
  # Register a dataset the legacy way: a CSV file, no release.
  utils::write.csv(data.frame(ccfid = "PT00001", age = 50), file.path(datasets, "built.csv"), row.names = FALSE)
  suppressWarnings(suppressMessages(hvtiRutilities::register_data(root, built = "built.csv")))
  # Attempt to publish should fail with the legacy-registration check.
  expect_error(
    bd_run(root, list(MASTER = m$parquet, KEEP = "age", EXCLUDE = NULL, PUBLISH = TRUE)),
    "^bd: publish \\("
  )
  # No dataset-catalog.yml should exist after the failed publish.
  expect_false(file.exists(file.path(datasets, "dataset-catalog.yml")))
})
