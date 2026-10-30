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
  # The working file is declared as the study's dataset, with no version registered.
  expect_identical(hvtiRutilities::study_config(root, require_data = FALSE)$built, "study_cohort.rds")
  expect_null(env$.version_after)
  expect_identical(env$.register_step, "Declared as the study dataset: nothing registered")
  expect_identical(env$.cut$attrition$reason, c("Rows read", "Under 40"))
  # A missing age is not excluded.
  expect_identical(nrow(env$d), nrow(m$data) - sum(m$data$age < 40, na.rm = TRUE))
})

test_that("bd with REGISTER = FALSE declares the working file and registers nothing", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  bd_run(root, list(MASTER = m$parquet, KEEP = "age", EXCLUDE = NULL, REGISTER = FALSE))
  yml <- yaml::read_yaml(file.path(root, "_study.yml"))
  expect_identical(yml$built, "study_cohort.rds")
  expect_false(is.null(yml$key))
  manifest <- file.path(root, "manifest.yaml")
  expect_true(!file.exists(manifest) || !length(yaml::read_yaml(manifest)$datasets))
  expect_length(bd_versions(root), 0L)
})

test_that("a second bd render keeps the contract, and another DATASET_ID is a working file only", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  choices <- list(MASTER = m$parquet, KEEP = "age", EXCLUDE = NULL, REGISTER = FALSE)
  bd_run(root, choices)
  first <- readLines(file.path(root, "_study.yml"))
  bd_run(root, choices)
  expect_identical(readLines(file.path(root, "_study.yml")), first)
  # A comparison build under another DATASET_ID writes its own file and declares nothing.
  env <- bd_run(root, utils::modifyList(choices, list(DATASET_ID = "other_cohort")))
  expect_identical(readLines(file.path(root, "_study.yml")), first)
  expect_match(env$.register_step, "still study_cohort.rds", fixed = TRUE)
  expect_match(env$.register_step, "not declared or registered", fixed = TRUE)
  expect_true(file.exists(file.path(hvtiRutilities::study_dir("datasets", root), "other_cohort.rds")))
  # Registering under it is refused.
  err <- expect_error(bd_run(root, utils::modifyList(choices, list(DATASET_ID = "other_cohort", REGISTER = TRUE))),
                      "^bd: register \\(")
  expect_match(conditionMessage(err), "registered as study_cohort.rds")
  expect_identical(readLines(file.path(root, "_study.yml")), first)
})

test_that("REGISTER = TRUE registers the declared working file as the study's first version", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  choices <- list(MASTER = m$parquet, KEEP = "age", EXCLUDE = NULL, REGISTER = FALSE)
  bd_draft(root, choices)
  env <- bd_run(root, utils::modifyList(choices, list(REGISTER = TRUE)))
  expect_match(env$.register_step, "^Registered as ")
  expect_length(bd_versions(root), 1L)
  expect_true(all(hvtiRutilities::verify_manifest(file.path(root, "manifest.yaml"))$status == "OK"))
})

test_that("the dataset carries ID, KEY, JOIN_BY and KEEP columns, an MRN among them when the job keeps it", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  env <- bd_run(root, list(MASTER = m$parquet, KEEP = c("age", "mrn"), EXCLUDE = NULL))
  expect_setequal(names(env$d), c("ccfid", "dt_surg", "age", "mrn"))
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
  bd_draft(root, choices)
  env <- bd_run(root, choices)
  expect_identical(hvtiRutilities::study_config(root)$built, "study_cohort.rds")
  expect_null(env$.version_before)
  expect_identical(env$.version_after, bd_current_version(root))
  # The draft declared the working file, so registering it is a first version of a declared dataset.
  expect_identical(env$.register_step, "Registered as a new version of the study dataset")
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
  bd_draft(root, list(MASTER = m$parquet, KEEP = "age", EXCLUDE = NULL))
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
  bd_expect_stop(root, utils::modifyList(ok, list(KEY = "dead", CROSSTABS = list())), "write-built")
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
  bd_draft(root, choices)
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

test_that("a working file never overwrites a published release, even without REGISTER", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  datasets <- hvtiRutilities::study_dir("datasets", root)
  ok <- list(MASTER = m$parquet, KEEP = "age", EXCLUDE = NULL, REGISTER = FALSE)
  # A dated name is a release's or a version's, and is refused before the master is read.
  dated <- file.path(datasets, "study_cohort_20261002.rds")
  saveRDS(data.frame(ccfid = "PT00001", age = 50), dated)
  sha <- digest::digest(dated, algo = "sha256", file = TRUE)
  bd_expect_stop(root, utils::modifyList(ok, list(DATASET_ID = "study_cohort_20261002")), "check-choices")
  bd_expect_stop(root, utils::modifyList(ok, list(DATASET_ID = "study_cohort_20261002_r2")), "check-choices")
  expect_identical(digest::digest(dated, algo = "sha256", file = TRUE), sha)
  # A release the catalog lists under an undated name is refused before it is written.
  release <- file.path(datasets, "legacy_cut.rds")
  saveRDS(data.frame(ccfid = "PT00001", age = 50), release)
  sha <- digest::digest(release, algo = "sha256", file = TRUE)
  catalog <- list(format_version = 1L, datasets = list(legacy_cut = list(releases = list(
    list(release_id = "legacy_cut-20261002-r1", file = "legacy_cut.rds", status = "published")
  ))))
  yaml::write_yaml(catalog, file.path(datasets, "dataset-catalog.yml"))
  bd_expect_stop(root, utils::modifyList(ok, list(DATASET_ID = "legacy_cut")), "write-built")
  expect_identical(digest::digest(release, algo = "sha256", file = TRUE), sha)
  expect_false(file.exists(file.path(datasets, "legacy_cut.build.yml")))
})

# The rest of the registration contract. A registering render registers only a file whose bytes a draft's report
# beside the job names, and the helpers write that report only through the template's own Report table.
bd_reg_labels <- c("setup", "edit-study-choices", "check-choices", "read-master", "cohort", "derive", "write-built",
                   bd_check_labels, "register")

test_that("REGISTER = TRUE with no draft report stops in register and registers nothing", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  choices <- list(MASTER = m$parquet, KEEP = "age", EXCLUDE = NULL, REGISTER = TRUE)
  err <- expect_error(bd_run(root, choices), "^bd: register \\(")
  expect_match(conditionMessage(err), "no draft report was found", fixed = TRUE)
  expect_false(file.exists(bd_sim_html(root)))
  expect_length(bd_versions(root), 0L)
  expect_null(hvtiRutilities::study_config(root, require_data = FALSE)$built)
  # A draft that ran only to its checks wrote no report either.
  bad <- bd_check_choices(m, CHECKS = list(no_such_col > 1 ~ "A column the data lacks"))
  expect_error(bd_draft(root, bad, labels = bd_reg_labels), "^bd: tbl-checks \\(")
  expect_false(file.exists(bd_sim_html(root)))
  expect_error(bd_run(root, bd_check_choices(m, register = TRUE)), "no draft report was found")
  expect_length(bd_versions(root), 0L)
})

test_that("the draft's report prints the hash of the file it wrote, and a registering render prints none", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  choices <- list(MASTER = m$parquet, KEEP = "age", EXCLUDE = NULL, REGISTER = FALSE)
  env <- bd_draft(root, choices)
  report <- paste(readLines(bd_sim_html(root)), collapse = "\n")
  hash <- digest::digest(env$.built, algo = "sha256", file = TRUE)
  expect_match(report, "Build reviewed (sha256)", fixed = TRUE)
  expect_match(report, hash, fixed = TRUE)
  # The registering render's own Report table has no such row.
  reg <- bd_run(root, utils::modifyList(choices, list(REGISTER = TRUE)))
  shown <- utils::capture.output(print(eval(parse(text = bd_chunk_code("tbl-report-source")), envir = reg)))
  expect_false(any(grepl("Build reviewed", shown, fixed = TRUE)))
  expect_false(any(grepl(hash, shown, fixed = TRUE)))
})

test_that("a draft whose checks did not all run prints no review hash, and a registering run stops naming the check", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  choices <- bd_check_choices(m)
  without <- bd_reg_labels[bd_reg_labels != "tbl-checks"]
  env <- bd_draft(root, choices, labels = without)
  report <- paste(readLines(bd_sim_html(root)), collapse = "\n")
  expect_false(grepl("Build reviewed", report, fixed = TRUE))
  expect_match(report, "Checks did not all run (tbl-checks)", fixed = TRUE)
  expect_null(hvtiRutilities::study_config(root, require_data = FALSE)$built)
  err <- expect_error(bd_run(root, bd_check_choices(m, register = TRUE), labels = without), "^bd: register \\(")
  expect_match(conditionMessage(err), "did not run: tbl-checks", fixed = TRUE)
  expect_length(bd_versions(root), 0L)
})

test_that("chunks run by hand stop in register, even after a draft, and register nothing", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  choices <- list(MASTER = m$parquet, KEEP = "age", EXCLUDE = NULL, REGISTER = TRUE)
  bd_draft(root, choices)
  err <- expect_error(bd_run(root, choices, render = FALSE), "^bd: register \\(")
  expect_match(conditionMessage(err), "not a Quarto render", fixed = TRUE)
  expect_length(bd_versions(root), 0L)
})

test_that("a valid replacement of the working file after it was hashed is not registered", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  choices <- bd_check_choices(m)
  bd_draft(root, choices)
  # The registering render's chunks run through the checks, so the build record holds the draft's hash.
  env <- bd_run(root, bd_check_choices(m, register = TRUE), labels = bd_reg_labels[bd_reg_labels != "register"])
  expect_identical(env$.record$built_sha256, digest::digest(env$.built, algo = "sha256", file = TRUE))
  # Another writer replaces the file with a valid RDS carrying a value the draft's report never showed.
  changed <- readRDS(env$.built)
  changed$age[[1L]] <- -123
  saveRDS(changed, env$.built)
  err <- expect_error(withr::with_dir(root, utils::capture.output(hazard_run("bd", "register", env))), # nolint: object_usage_linter.
                      "^bd: register \\(")
  expect_match(conditionMessage(err), "changed after this render wrote it", fixed = TRUE)
  expect_length(bd_versions(root), 0L)
  expect_false(grepl("-123", conditionMessage(err), fixed = TRUE))
})

test_that("a draft report that names other bytes than the build is not registered", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  choices <- list(MASTER = m$parquet, KEEP = "age", EXCLUDE = list(age < 40 ~ "Under 40"), REGISTER = FALSE)
  bd_draft(root, choices)
  datasets <- hvtiRutilities::study_dir("datasets", root)
  # A different cut of the same master: the bytes written are not the bytes the draft's report names.
  changed <- choices
  changed$EXCLUDE <- list(age < 50 ~ "Under 50")
  changed$REGISTER <- TRUE
  err <- expect_error(bd_run(root, changed), "^bd: register \\(")
  expect_match(conditionMessage(err), "draft report names other bytes", fixed = TRUE)
  expect_length(bd_versions(root), 0L)
  # A report that is a registering render's own, which prints no hash, approves nothing either.
  writeLines("<html>a registering render's report</html>", bd_sim_html(root))
  expect_error(bd_run(root, utils::modifyList(choices, list(REGISTER = TRUE))), "draft report names other bytes")
  expect_length(bd_versions(root), 0L)
  expect_true(file.exists(file.path(datasets, "study_cohort.build.yml")))
})

test_that("a finding does not block registration: a CHECKS entry that matches rows still registers", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  with_checks <- c("setup", "set", "edit-study-choices", "check-choices", "read-master", "cohort", "derive",
                   "write-built", bd_check_labels, "register")
  choices <- bd_check_choices(m, CHECKS = list(!is.na(age) ~ "Every row"))
  bd_draft(root, choices, labels = with_checks)
  env <- bd_run(root, utils::modifyList(choices, list(REGISTER = TRUE)), labels = with_checks)
  expect_gt(env$.checked$n, 0L)
  expect_identical(env$.register_step, "Registered as a new version of the study dataset")
  expect_length(bd_versions(root), 1L)
})
