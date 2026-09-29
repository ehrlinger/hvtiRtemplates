# read_job_data() steps on plain data frames. No identifier value appears in
# any message: the tests assert counts only.

d0 <- data.frame(
  ccfid = 1:6, MRN = 101:106, eMRN = 201:206, pt_mrn = 1:6,
  age = c(15, 40, 55, NA, 70, 80), hx_chf = c(0L, 1L, 1L, 0L, 1L, NA)
)

test_that("the ID is ccfid when present, else MRN, then eMRN, else a stop", {
  expect_identical(hvtiRtemplates:::.resolve_job_id(d0, "ccfid"),
                   list(id = "ccfid", fallback = FALSE))
  expect_identical(hvtiRtemplates:::.resolve_job_id(d0[-1], "ccfid"),
                   list(id = "MRN", fallback = TRUE))
  expect_identical(hvtiRtemplates:::.resolve_job_id(d0[c("eMRN", "age")], "ccfid"),
                   list(id = "eMRN", fallback = TRUE))
  expect_error(hvtiRtemplates:::.resolve_job_id(d0["age"], "ccfid"),
               "ID in edit-study-choices")
  # A non-default ID never falls back: the analyst named it.
  expect_error(hvtiRtemplates:::.resolve_job_id(d0, "randid"), "randid")
})

test_that("MRN and eMRN are dropped unless one is the ID; no other name is", {
  out <- hvtiRtemplates:::.drop_identifiers(d0, "ccfid")
  expect_setequal(out$dropped, c("MRN", "eMRN"))
  expect_true("pt_mrn" %in% names(out$data))
  expect_false(any(c("MRN", "eMRN") %in% names(out$data)))
  kept <- hvtiRtemplates:::.drop_identifiers(d0[-1], "MRN")
  expect_identical(kept$dropped, "eMRN")
  expect_true("MRN" %in% names(kept$data))
  lower <- d0
  names(lower)[2] <- "mrn"
  expect_true("mrn" %in% hvtiRtemplates:::.drop_identifiers(lower, "ccfid")$dropped)
})

test_that("WHERE follows filter(): NA rows are dropped and counted, conditions apply in order", {
  none <- hvtiRtemplates:::.apply_where(d0, NULL)
  expect_identical(nrow(none$data), 6L)
  expect_identical(nrow(none$steps), 0L)
  one <- hvtiRtemplates:::.apply_where(d0, quote(age >= 18))
  expect_identical(one$data$ccfid, c(2L, 3L, 5L, 6L))
  expect_identical(one$steps$removed, 2L)
  expect_identical(one$steps$missing, 1L)
  two <- hvtiRtemplates:::.apply_where(d0, rlang::exprs(age >= 18, hx_chf == 1))
  expect_identical(two$data$ccfid, c(2L, 3L, 5L))
  expect_identical(two$steps$condition, c("age >= 18", "hx_chf == 1"))
  expect_identical(two$steps$removed, c(2L, 1L))
  expect_identical(two$steps$missing, c(1L, 1L))
  min_age <- 50
  expect_identical(hvtiRtemplates:::.apply_where(d0,
                                                 quote(age >= .env$min_age))$data$ccfid,
                   c(3L, 5L, 6L))
  expect_error(hvtiRtemplates:::.apply_where(d0, "age >= 18"), "WHERE must be NULL")
  expect_error(hvtiRtemplates:::.apply_where(d0, quote(age + 1)), "TRUE or FALSE")
})

test_that("rows must be unique on KEY; patients are counted on ID", {
  expect_identical(hvtiRtemplates:::.check_job_key(d0, "ccfid", "ccfid"),
                   list(rows = 6L, patients = 6L))
  long <- data.frame(ccfid = c(1L, 1L, 2L), iv_echo = c(0.1, 1.2, 0.3))
  expect_identical(hvtiRtemplates:::.check_job_key(long, c("ccfid", "iv_echo"),
                                                   "ccfid"),
                   list(rows = 3L, patients = 2L))
  expect_error(hvtiRtemplates:::.check_job_key(long, "ccfid", "ccfid"),
               "1 value of KEY repeats")
  err <- tryCatch(hvtiRtemplates:::.check_job_key(long, "ccfid", "ccfid"),
                  error = conditionMessage)
  expect_false(grepl("\\b1\\b.*\\b1\\b.*\\b2\\b", err))
  expect_error(hvtiRtemplates:::.check_job_key(long, "visit", "ccfid"),
               "KEY names a column")
})

job_study <- function(data, .local_envir = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = .local_envir)
  suppressMessages(hvtiRutilities::study_setup(root, "Job data", 1L, adopt = TRUE))
  utils::write.csv(data, file.path(hvtiRutilities::study_dir("datasets", root), "built.csv"), row.names = FALSE)
  suppressMessages(hvtiRutilities::register_data(root, "built.csv"))
  hvtiRutilities::study_config(start = root)
}

test_that("read_job_data() reads, selects and records what it did", {
  cfg <- job_study(d0)
  out <- read_job_data(cfg, where = rlang::exprs(age >= 18, hx_chf == 1))
  expect_identical(out$data$ccfid, c(2L, 3L, 5L))
  expect_false(any(c("MRN", "eMRN") %in% names(out$data)))
  expect_s3_class(out$record, "data.frame")
  expect_identical(names(out$record), c("step", "value"))
  expect_match(paste(out$record$value, collapse = " "), "3 rows on 3 patients")
  sel <- attr(out$record, "selection")
  expect_identical(sel$id, "ccfid")
  expect_identical(sel$key, "ccfid")
  expect_identical(sel$where, c("age >= 18", "hx_chf == 1"))
  expect_identical(out$provenance$dataset, "study")
  # No identifier value reaches the record.
  expect_false(any(grepl("\\b10[1-6]\\b|\\b20[1-6]\\b", out$record$value)))
})

test_that("KEY follows the ID when the ID falls back", {
  cfg <- job_study(d0[-1])
  out <- read_job_data(cfg)
  # hvtiRutilities::read_built() lowercases every column name, so the resolved
  # fallback identifier is "mrn", not the "MRN" it was written to disk under.
  expect_identical(attr(out$record, "selection")$id, "mrn")
  expect_identical(attr(out$record, "selection")$key, "mrn")
  expect_match(paste(out$record$value, collapse = " "), "fell back to mrn")
})

test_that("an analysis set with another dataset is refused", {
  cfg <- job_study(d0)
  expect_error(read_job_data(cfg, dataset = "other", analysis_set = "eda"), "written from the study dataset")
})

test_that("a job outside a study is told to run study_setup()", {
  expect_error(hvtiRtemplates:::.find_study_root(withr::local_tempdir()), "study_setup")
})

test_that("a hand-off carries the selection, and older four-slot lineage still validates", {
  sel <- list(dataset = "study", analysis_set = NULL, where = "age >= 18", id = "ccfid", key = "ccfid",
              rows = 3L, patients = 3L)
  obj <- hvtiRtemplates:::.attach_handoff_lineage(list(), data = list(list(dataset = "study")), selection = sel)
  expect_identical(attr(obj, "hvti_provenance")$selection, sel)
  old <- hvtiRtemplates:::.attach_handoff_lineage(list(), data = list(list(dataset = "study")))
  expect_identical(names(attr(old, "hvti_provenance")), c("data", "artifacts", "analysis", "cohort"))
  expect_silent(hvtiRtemplates:::.validate_handoff_lineage(old, "x.rds", "hz"))
  expect_silent(hvtiRtemplates:::.validate_handoff_lineage(obj, "x.rds", "hz"))
})

test_that("a downstream job's settings must agree with its upstream selection", {
  up <- list(where = "age >= 18", id = "ccfid", key = "ccfid", time = "iv_dead", event = "dead")
  expect_identical(hvtiRtemplates:::.check_upstream_selection(up, list(where = NULL, id = NULL))$where, "age >= 18")
  expect_error(hvtiRtemplates:::.check_upstream_selection(up, list(where = "age >= 65")),
               "WHERE.*age >= 65.*age >= 18")
  expect_error(hvtiRtemplates:::.check_upstream_selection(up, list(event = "reop")), "EVENT")
  expect_identical(hvtiRtemplates:::.check_upstream_selection(NULL, list(id = "ccfid"))$id, "ccfid")
})

test_that(".check_upstream_selection() ignores fields outside its known five", {
  out <- hvtiRtemplates:::.check_upstream_selection(list(rows = 10L, id = "ccfid"), list(rows = 5L))
  expect_identical(out$id, "ccfid")
  # A field the check does not compare is never overwritten: upstream wins.
  expect_identical(out$rows, 10L)
})

test_that(".check_upstream_selection() compares DATASET and ANALYSIS_SET too", {
  up <- list(dataset = "study", analysis_set = "eda", id = "ccfid", rows = 3L, patients = 3L)
  expect_error(hvtiRtemplates:::.check_upstream_selection(up, list(dataset = "other")), "DATASET")
  expect_error(hvtiRtemplates:::.check_upstream_selection(up, list(analysis_set = "late")), "ANALYSIS_SET")
  out <- hvtiRtemplates:::.check_upstream_selection(up, list(dataset = "study", analysis_set = NULL,
                                                             rows = 1L, patients = 1L))
  expect_identical(out$analysis_set, "eda")
  expect_identical(c(out$rows, out$patients), c(3L, 3L))
})

test_that(".check_upstream_selection() treats NULL settings as an empty list", {
  out <- hvtiRtemplates:::.check_upstream_selection(list(id = "ccfid"), NULL)
  expect_identical(out$id, "ccfid")
})

test_that(".check_upstream_selection() compares a real quote() or exprs() WHERE against the upstream string", {
  up <- list(where = "age >= 18")
  expect_identical(
    hvtiRtemplates:::.check_upstream_selection(up, list(where = quote(age >= 18)))$where,
    "age >= 18"
  )
  expect_error(
    hvtiRtemplates:::.check_upstream_selection(up, list(where = quote(age >= 65))),
    "WHERE.*age >= 65.*age >= 18"
  )
  up_two <- list(where = c("age >= 18", "hx_chf == 1"))
  expect_identical(
    hvtiRtemplates:::.check_upstream_selection(
      up_two, list(where = rlang::exprs(age >= 18, hx_chf == 1))
    )$where,
    c("age >= 18", "hx_chf == 1")
  )
  expect_error(
    hvtiRtemplates:::.check_upstream_selection(up_two, list(where = rlang::exprs(age >= 65, hx_chf == 1))),
    "WHERE"
  )
})

test_that(".read_upstream_job_data() stops on a hand-off that predates the data contract", {
  expect_error(hvtiRtemplates:::.read_upstream_job_data(list(), list(data = list()), list(), source = "hz.rds"),
               "hz.rds.*predates")
  expect_error(hvtiRtemplates:::.read_upstream_job_data(list(), list(data = list()), list(), read = FALSE),
               "predates")
})

test_that(".read_upstream_job_data() rebuilds the upstream rows and returns the selection", {
  cfg <- job_study(d0)
  up <- read_job_data(cfg, where = rlang::exprs(age >= 18, hx_chf == 1))
  lineage <- list(selection = attr(up$record, "selection"))
  out <- hvtiRtemplates:::.read_upstream_job_data(cfg, lineage, list(where = NULL, id = NULL, key = NULL))
  expect_identical(names(out), c("job_data", "selection"))
  expect_identical(out$job_data$data$ccfid, c(2L, 3L, 5L))
  expect_identical(out$selection$where, c("age >= 18", "hx_chf == 1"))
  bare <- hvtiRtemplates:::.read_upstream_job_data(cfg, lineage, list(), read = FALSE)
  expect_identical(names(bare), "selection")
  expect_identical(bare$selection$rows, 3L)
  expect_error(hvtiRtemplates:::.read_upstream_job_data(cfg, lineage, list(dataset = "other")), "DATASET")
})

test_that(".read_upstream_job_data() stops when the rows it rebuilds are not the upstream cohort", {
  cfg <- job_study(d0)
  up <- read_job_data(cfg, where = quote(age >= 18))
  sel <- attr(up$record, "selection")
  sel$rows <- 99L
  expect_error(hvtiRtemplates:::.read_upstream_job_data(cfg, list(selection = sel), list()),
               "99 rows.*4 rows.*did not rebuild")
})
