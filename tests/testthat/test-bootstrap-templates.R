# The bootstrap reports read a bag their runner saved, not data. The data
# contract reaches them through the bag's lineage: the runner reads its rows
# with read_job_data() and saves the selection, and the report prints it.

# ---- the runner snippet ---------------------------------------------------------

test_that("every runner reads through read_job_data(), keeps the ID out, and saves the selection", {
  for (prefix in boot_all) {
    src <- readLines(template_path(prefix), warn = FALSE)
    chunk <- rf_chunk(src, "runner")
    # A render never runs it: the runner is a study script, days of compute for bh.
    expect_true("#| eval: false" %in% chunk, info = prefix)
    code <- parse(text = chunk, keep.source = FALSE)
    text <- paste(vapply(code, function(e) paste(deparse(e, width.cutoff = 500L), collapse = " "), ""), collapse = "\n")
    expect_match(text, "hvtiRtemplates::read_job_data(cfg", fixed = TRUE, info = prefix)
    expect_match(text, "selection <- attr(job$record, \"selection\")", fixed = TRUE, info = prefix)
    lineage <- paste("attr(bag, \"hvti_provenance\") <- list(data = list(job$provenance), artifacts = list(),",
                     "analysis = NULL, cohort = NULL, selection = selection)")
    expect_match(text, lineage, fixed = TRUE, info = prefix)
    # Only the model's columns reach the screen, never job$data whole.
    expect_match(text, if (prefix == "bh") "d <- job$data[c(\"iv_dead\", \"dead\", pool)]" else "d <- job$data[all.vars(model)]",
                 fixed = TRUE, info = prefix)
    expect_false(grepl("(boot_select|hazard)\\(job\\$data", text), info = prefix)
  }
  # A hazard bag is written by hand: its boot field takes four fields of the
  # result, and not `scope`, whose formulas carry the environment they were
  # written in.
  bh <- paste(rf_chunk(readLines(template_path("bh"), warn = FALSE), "runner"), collapse = "\n")
  expect_match(bh, 'boot = bs[c("replicates", "summary", "n_success", "n_failed")]', fixed = TRUE)
})

test_that("each boot_select() runner saves a bag the report reads, with the selection it prints", {
  data <- rf_mrn_data(id = "ccfid")
  for (prefix in boot_thin) {
    boot_skip_unless_stack(prefix)
    root <- rf_study(data)
    dir <- boot_run_runner(prefix, root, new.env(parent = globalenv()), boot_settings(prefix, where = quote(age >= 40)))
    bag <- readRDS(file.path(dir, "bagging.rds"))
    expect_identical(bag$n_rows, sum(data$age >= 40), info = prefix)
    expect_identical(attr(bag, "hvti_provenance")$selection$where, "age >= 40", info = prefix)

    env <- boot_report(prefix, boot_env(root), c("set", "edit-study-choices", "load", "data"))
    expect_identical(env$.sel$id, "ccfid", info = prefix)
    expect_identical(env$.sel$where, "age >= 40", info = prefix)
    expect_identical(env$.sel$rows, sum(data$age >= 40), info = prefix)
    # Set to the runner's value, a setting only confirms it; a different one stops.
    confirm <- list(WHERE = quote(age >= 40), ID = "ccfid", KEY = "ccfid")
    expect_no_error(boot_report(prefix, boot_env(root), c("set", "edit-study-choices", "load", "data"), confirm))
    expect_error(boot_report(prefix, boot_env(root), c("set", "edit-study-choices", "load", "data"),
                             list(WHERE = quote(age >= 65))),
                 "WHERE here \\(age >= 65\\) differs from the upstream job's \\(age >= 40\\)", info = prefix)
  }
})

test_that("each boot_select() report reads the runner's rows, not the whole dataset, and saves the selection", {
  data <- rf_mrn_data(id = "ccfid")
  for (prefix in boot_thin) {
    boot_skip_unless_stack(prefix)
    root <- rf_study(data)
    dir <- boot_run_runner(prefix, root, new.env(parent = globalenv()), boot_settings(prefix, where = quote(age >= 40)))
    env <- boot_report(prefix, boot_env(root))
    # The correlations describe the rows the screen ran on.
    expect_identical(nrow(env$d), sum(data$age >= 40), info = prefix)
    report <- readRDS(file.path(dir, paste0(prefix, "-report.rds")))
    expect_identical(attr(report, "hvti_provenance")$selection, env$.sel, info = prefix)
  }
})

test_that("a report warns when the rows it reads are not the patients the screen ran on", {
  data <- rf_mrn_data(id = "ccfid")
  boot_skip_unless_stack("bl")
  root <- rf_study(data)
  dir <- boot_run_runner("bl", root, new.env(parent = globalenv()))
  bag <- readRDS(file.path(dir, "bagging.rds"))
  # Same count, other patients: only the key hash can tell.
  attr(bag, "hvti_provenance")$selection$key_hash <- "0000"
  saveRDS(bag, file.path(dir, "bagging.rds"))
  expect_warning(boot_report("bl", boot_env(root)),
                 "^The rows read now are not the rows this screen ran against: 120 rows now, 120 then[.]")
})

# ---- a bag without one selection stops the report ------------------------------

test_that("a bag saved before the data contract stops each report, naming the bag and the runner", {
  data <- rf_mrn_data(id = "ccfid")
  for (prefix in boot_thin) {
    boot_skip_unless_stack(prefix)
    root <- rf_study(data)
    dir <- boot_run_runner(prefix, root, new.env(parent = globalenv()))
    bag <- readRDS(file.path(dir, "bagging.rds"))
    attr(bag, "hvti_provenance")$selection <- NULL
    saveRDS(bag, file.path(dir, "bagging.rds"))
    env <- boot_report(prefix, boot_env(root), c("set", "edit-study-choices", "load"))
    # The bag itself is still read: it is the data chunk that stops.
    expect_error(boot_report(prefix, env, "data"),
                 paste0("\\(the bootstrap bag bagging[.]rds\\) carries no single recorded data selection: it predates ",
                        "the data contract.*Rerun the bootstrap runner with the `runner` chunk of the current template"),
                 info = prefix)
  }
})

test_that("bh reads its chunks' shared selection, and stops when a chunk has none or they disagree", {
  boot_skip_unless_stack("bh")
  root <- rf_study(rf_mrn_data(id = "ccfid"))
  job <- hvtiRtemplates::read_job_data(hvtiRutilities::study_config(root))
  run <- function() {
    boot_report("bh", boot_env(root), c("set", "edit-study-choices", "load", "data"), list(EXPECT_BOOT = 4L, EXPECT_CHUNKS = 2L))
  }

  boot_save_chunks(root, list(boot_hazard_chunk(1L, job), boot_hazard_chunk(2L, job)))
  expect_identical(run()$.sel, attr(job$record, "selection"))

  boot_save_chunks(root, list(boot_hazard_chunk(1L, job), boot_hazard_chunk(2L, job, selection = NULL)))
  pooled <- paste0("\\(the bootstrap bag pooled from 2 chunks, bh[.]chunk01[.]rds to bh[.]chunk02[.]rds\\) carries no ",
                   "single recorded data selection.*Rerun the bootstrap runner")
  expect_error(run(), pooled)

  other <- utils::modifyList(attr(job$record, "selection"), list(where = "age >= 40", rows = 80L))
  boot_save_chunks(root, list(boot_hazard_chunk(1L, job), boot_hazard_chunk(2L, job, selection = other)))
  expect_error(run(), pooled)
})

# ---- #203: no bag or report carries a patient identifier ------------------------

test_that(".check_bag_identifiers() passes a bag of replicates and settings", {
  job <- list(provenance = list(sha256 = "abc"), data = data.frame(age = 1:3))
  bag <- boot_hazard_chunk(1L, job, selection = list(id = "id", key = "id"))
  expect_true(hvtiRtemplates:::.check_bag_identifiers(bag, "id"))
  expect_true(hvtiRtemplates:::.check_bag_identifiers(bag, "ccfid"))
  # A formula written in the global environment is saved by reference only.
  bag$scope <- list(early = stats::as.formula("~ age", env = globalenv()))
  expect_true(hvtiRtemplates:::.check_bag_identifiers(bag, "ccfid"))
})

test_that(".check_bag_identifiers() stops on rows saved in a bag, wherever they sit", {
  job <- list(provenance = list(sha256 = "abc"), data = data.frame(age = 1:3))
  bag <- boot_hazard_chunk(1L, job)
  rows <- data.frame(MRN = 7350000001 + 0:2, age = 1:3)
  holds <- "^The bootstrap bag holds patient-level data: "
  # A field, under the job's ID or under MRN and eMRN whatever the ID.
  expect_error(hvtiRtemplates:::.check_bag_identifiers(c(bag, list(rows = rows)), "ccfid"), paste0(holds, "bag\\$rows\\$MRN"))
  expect_error(hvtiRtemplates:::.check_bag_identifiers(c(bag, list(rows = data.frame(randid = 1:3))), "randid"),
               "bag\\$rows\\$randid")
  expect_error(hvtiRtemplates:::.check_bag_identifiers(c(bag, list(ids = list(emrn = 1:3))), "ccfid"), "bag\\$ids\\$emrn")
  # A formula or a function whose environment holds the runner's data, as a
  # hazard result's `scope` does when a runner written as a function saves it.
  scoped <- local({
    d <- rows
    ~ age
  })
  expect_error(hvtiRtemplates:::.check_bag_identifiers(c(bag, list(scope = list(early = scoped))), "ccfid"),
               "bag\\$scope\\$early, attribute [.]Environment: d\\$MRN")
  fun <- local({
    d <- rows
    function() d
  })
  expect_error(hvtiRtemplates:::.check_bag_identifiers(c(bag, list(f = fun)), "ccfid"),
               "bag\\$f, a function's environment: d\\$MRN")
  expect_error(hvtiRtemplates:::.check_bag_identifiers(c(bag, list(m = as.matrix(rows))), "ccfid"), "bag\\$m\\$MRN")
})

test_that("each report stops on a bag that holds the runner's rows", {
  data <- rf_mrn_data()
  for (prefix in boot_thin) {
    boot_skip_unless_stack(prefix)
    root <- rf_study(data)
    dir <- boot_run_runner(prefix, root, new.env(parent = globalenv()))
    bag <- readRDS(file.path(dir, "bagging.rds"))
    bag$rows <- data
    saveRDS(bag, file.path(dir, "bagging.rds"))
    expect_error(boot_report(prefix, boot_env(root), c("set", "edit-study-choices", "load", "data")),
                 "^The bootstrap bag bagging[.]rds holds patient-level data: bag\\$rows\\$MRN", info = prefix)
  }
  # bh searches every chunk, not only the first, whose fields the pooled bag keeps.
  boot_skip_unless_stack("bh")
  root <- rf_study(data)
  job <- hvtiRtemplates::read_job_data(hvtiRutilities::study_config(root))
  scope <- local({
    d <- job$data
    ~ age
  })
  boot_save_chunks(root, list(boot_hazard_chunk(1L, job), boot_hazard_chunk(2L, job, extra = list(scope = scope))))
  expect_error(boot_report("bh", boot_env(root), c("set", "edit-study-choices", "load", "data"),
                           list(EXPECT_BOOT = 4L, EXPECT_CHUNKS = 2L)),
               "^The bootstrap bag bh[.]chunk02[.]rds holds patient-level data: bag\\$scope, attribute [.]Environment: d\\$mrn")
})

test_that("a runner and report keyed on MRN save no MRN in any file", {
  for (prefix in boot_thin) {
    boot_skip_unless_stack(prefix)
    run <- boot_mrn_run(prefix, globalenv(), globalenv())
    # The ID fell back to MRN, and the runner and the report both read it.
    expect_identical(run$env$.sel$id, "mrn", info = prefix)
    expect_true("mrn" %in% names(run$env$d), info = prefix)
    expect_setequal(list.files(run$dir), c("bagging.rds", paste0(prefix, "-report.rds")))
    expect_identical(rf_files_holding(run$dir, run$data$MRN), character(), info = prefix)
    # The search finds what is there: every MRN in the data the report read.
    read <- serialize(run$env$d, NULL)
    expect_true(all(vapply(run$data$MRN, function(v) rf_bytes_hold(read, v), logical(1L))), info = prefix)
  }
})

test_that("a runner and report keyed on MRN save no MRN when run outside the global environment", {
  for (prefix in boot_thin) {
    boot_skip_unless_stack(prefix)
    # A formula made here carries this environment, and with it `job` and its
    # MRN column, into anything saved that keeps the formula.
    run <- boot_mrn_run(prefix, new.env(parent = globalenv()), new.env(parent = globalenv()))
    expect_true("mrn" %in% names(run$env$d), info = prefix)
    expect_identical(rf_files_holding(run$dir, run$data$MRN), character(), info = prefix)
  }
})

test_that("bh saves no MRN in its report, in or outside the global environment", {
  boot_skip_unless_stack("bh")
  for (env in list(globalenv(), new.env(parent = globalenv()))) {
    data <- rf_mrn_data()
    root <- rf_study(data)
    job <- hvtiRtemplates::read_job_data(hvtiRutilities::study_config(root))
    dir <- boot_save_chunks(root, list(boot_hazard_chunk(1L, job), boot_hazard_chunk(2L, job)))
    rf_restore_later(env, environment())
    env$.root <- root
    env$.provenance_data <- list()
    env$.provenance_artifacts <- list()
    boot_report("bh", env, replace(boot_report_labels, boot_report_labels == "health", "edit-health"),
                list(EXPECT_BOOT = 4L, EXPECT_CHUNKS = 2L, CLUSTERS = list(early.Age = "early.age")))
    expect_true("mrn" %in% names(env$d))
    expect_identical(rf_files_holding(dir, data$MRN), character())
  }
})
