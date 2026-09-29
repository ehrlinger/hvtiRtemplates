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
  long <- data.frame(ccfid = c(9001L, 9001L, 9002L), iv_echo = c(0.1, 1.2, 0.3))
  expect_identical(hvtiRtemplates:::.check_job_key(long, c("ccfid", "iv_echo"),
                                                   "ccfid"),
                   list(rows = 3L, patients = 2L))
  expect_error(hvtiRtemplates:::.check_job_key(long, "ccfid", "ccfid"),
               "1 value of KEY repeats")
  err <- tryCatch(hvtiRtemplates:::.check_job_key(long, "ccfid", "ccfid"),
                  error = conditionMessage)
  # Neither the repeated ID nor any other ID value reaches the message.
  expect_false(grepl("9001", err, fixed = TRUE))
  expect_false(grepl("9002", err, fixed = TRUE))
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

test_that("a malformed _study.yml is not reported as a missing study", {
  root <- withr::local_tempdir()
  writeLines("a: [", file.path(root, "_study.yml"))
  sub <- file.path(root, "20_distributions")
  dir.create(sub)
  for (start in c(root, sub)) {
    err <- tryCatch(hvtiRtemplates:::.find_study_root(start), error = conditionMessage)
    expect_false(grepl("study_setup", err), info = start)
    expect_identical(err, tryCatch(hvtiRutilities::study_root(start), error = conditionMessage), info = start)
  }
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

test_that(".read_upstream_job_data() stops on a hand-off with no single recorded selection", {
  expect_error(hvtiRtemplates:::.read_upstream_job_data(list(), list(data = list()), list(), source = "hz.rds"),
               "hz.rds.*predates.*disagreed")
  expect_error(hvtiRtemplates:::.read_upstream_job_data(list(), list(data = list()), list(), read = FALSE),
               "predates.*disagreed")
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

test_that(".mask_condition() hides the values of a condition on ID or KEY, and only those", {
  mask <- hvtiRtemplates:::.mask_condition
  expect_identical(mask(quote(ccfid != 9001), "ccfid"), "ccfid != <value>")
  expect_identical(mask(quote(ccfid %in% c(9001, 9002)), "ccfid"), "ccfid %in% c(<value>, <value>)")
  expect_identical(mask("CCFID == \"A9001\"", "ccfid"), "CCFID == <value>")
  expect_identical(mask(quote(age >= 18), "ccfid"), "age >= 18")
  expect_identical(mask(quote(iv_echo > 2.5), c("ccfid", "iv_echo")), "iv_echo > <value>")
  date_shown <- mask(rlang::expr(echo_date != !!as.Date("2020-01-03")), "echo_date")
  expect_identical(date_shown, "echo_date != <value>")
  expect_false(grepl("18264", date_shown, fixed = TRUE))
  expect_false(grepl("2020", date_shown, fixed = TRUE))
})

d_ids <- data.frame(ccfid = 9001:9006, age = c(15, 40, 55, NA, 70, 80))

test_that("a WHERE on the ID never prints its value, but the selection keeps it to rebuild the rows", {
  cfg <- job_study(d_ids)
  out <- read_job_data(cfg, where = rlang::exprs(ccfid != 9001, age >= 18))
  expect_false(any(grepl("9001", c(out$record$step, out$record$value))))
  expect_true(any(grepl("age >= 18", out$record$step, fixed = TRUE)))
  sel <- attr(out$record, "selection")
  expect_identical(sel$where, c("ccfid != 9001", "age >= 18"))
  expect_identical(sel$where_shown, c("ccfid != <value>", "age >= 18"))
  msg <- function(expr) {
    tryCatch({
      force(expr)
      ""
    }, error = conditionMessage)
  }
  bad <- msg(read_job_data(cfg, where = quote(ccfid + 9001)))
  expect_match(bad, "TRUE or FALSE")
  expect_false(grepl("9001", bad))
  missing_col <- msg(read_job_data(cfg, where = quote(ccfid != nosuch + 9001)))
  expect_match(missing_col, "nosuch")
  expect_false(grepl("9001", missing_col))
  differs <- msg(hvtiRtemplates:::.check_upstream_selection(sel, list(where = quote(ccfid != 9002))))
  expect_match(differs, "WHERE")
  expect_false(grepl("900[12]", differs))
  up <- sel
  up$rows <- 99L
  rebuilt <- msg(hvtiRtemplates:::.read_upstream_job_data(cfg, list(selection = up), list()))
  expect_match(rebuilt, "did not rebuild")
  expect_false(grepl("9001", rebuilt))
})

test_that("an explicit ID or KEY matches its column ignoring case, as read_built() lowercases", {
  cfg <- job_study(d0[-1])
  out <- read_job_data(cfg, id = "MRN", key = c("MRN", "AGE"))
  sel <- attr(out$record, "selection")
  expect_identical(sel$id, "mrn")
  expect_identical(sel$key, c("mrn", "age"))
  expect_false(grepl("fell back", paste(out$record$value, collapse = " ")))
})

test_that("a WHERE that fails to evaluate names the condition", {
  cfg <- job_study(d0)
  expect_error(read_job_data(cfg, where = quote(AGE > 1)), "WHERE condition `AGE > 1`: .*AGE")
})

test_that("settings are checked before any data is read", {
  cfg <- job_study(d0)
  # DATASET "absent" is not registered, so every error below must come from the
  # settings check, not the read.
  expect_error(read_job_data(cfg, dataset = "absent", where = "age >= 18"), "WHERE must be NULL")
  expect_error(read_job_data(cfg, dataset = "absent", analysis_set = c("a", "b")), "ANALYSIS_SET")
  expect_error(read_job_data(cfg, dataset = "absent", id = 1), "ID must name one column")
  expect_error(read_job_data(cfg, dataset = "absent", key = 1), "KEY must name")
  expect_error(read_job_data(cfg, dataset = ""), "DATASET")
})

test_that("an analysis set needs hvtiRdatabuild 0.2.1 or later", {
  expect_error(hvtiRtemplates:::.require_databuild(NULL), "hvtiRdatabuild 0.2.1")
  expect_error(hvtiRtemplates:::.require_databuild(package_version("0.2.0")), "0.2.1 or later.*0.2.0")
  expect_silent(hvtiRtemplates:::.require_databuild(package_version("0.2.1")))
})

test_that("read_job_data() reads an analysis set and keeps its attrition", {
  skip_if_not_installed("hvtiRdatabuild", "0.2.1")
  skip_if_not_installed("arrow")
  skip_if_not_installed("hvtiPlotR")
  cfg <- job_study(d0)
  cat("analysis_sets:\n  eda:\n    id: ccfid\n    vars: [ccfid, age, hx_chf]\n",
      "    exclude:\n      - reason: under 18\n        when: age < 18\n",
      sep = "", file = cfg$file, append = TRUE)
  suppressMessages(hvtiRdatabuild::write_analysis_set("eda", cfg))
  out <- read_job_data(cfg, analysis_set = "eda", where = quote(hx_chf == 1))
  expect_identical(as.integer(out$data$ccfid), c(2L, 3L, 5L))
  expect_identical(out$record$value[[1L]], "analysis set `eda` of the study dataset")
  expect_s3_class(out$attrition, "data.frame")
  expect_identical(out$attrition$reason, "under 18")
  expect_identical(as.integer(out$attrition$n_excluded), 1L)
  expect_identical(attr(out$record, "selection")$analysis_set, "eda")
  expect_null(read_job_data(cfg)$attrition)
})

test_that("a WHERE that reaches a column through .data is masked like one on ID or KEY", {
  mask <- hvtiRtemplates:::.mask_condition
  for (cond in list(quote(.data[["ccfid"]] != 9001), quote(.data$ccfid != 9001), quote(.data[["CCFID"]] != 9001))) {
    shown <- mask(cond, "ccfid")
    expect_false(grepl("9001", shown, fixed = TRUE), info = shown)
    expect_match(shown, "<value>", fixed = TRUE)
  }
  cfg <- job_study(d_ids)
  out <- read_job_data(cfg, where = quote(.data[["ccfid"]] != 9001))
  expect_false(any(grepl("9001", c(out$record$step, out$record$value, attr(out$record, "selection")$where_shown))))
  bad <- tryCatch(read_job_data(cfg, where = quote(.data[["ccfid"]] + 9001)), error = conditionMessage)
  expect_match(bad, "TRUE or FALSE")
  expect_false(grepl("9001", bad, fixed = TRUE))
})

test_that("a WHERE value from outside the data is fixed into the recorded condition", {
  cfg <- job_study(d0)
  upstream <- function(where) {
    min_age <- 60
    ids <- c(2L, 3L)
    read_job_data(cfg, where = where)
  }
  bare <- upstream(quote(age >= min_age))
  expect_identical(attr(bare$record, "selection")$where, "age >= 60")
  expect_identical(bare$data$ccfid, c(5L, 6L))
  dollar <- upstream(quote(age >= .env$min_age))
  expect_identical(attr(dollar$record, "selection")$where, "age >= 60")
  brackets <- upstream(quote(age >= .env[["min_age"]]))
  expect_identical(attr(brackets$record, "selection")$where, "age >= 60")
  # A function name in call position is never replaced; its arguments are.
  fn <- upstream(quote(round(age) >= min_age))
  expect_identical(attr(fn$record, "selection")$where, "round(age) >= 60")
  # A downstream job in an environment where min_age means something else, or
  # nothing, still rebuilds the upstream rows.
  for (lineage in list(list(selection = attr(bare$record, "selection")), list(selection = attr(dollar$record, "selection")))) {
    local({
      min_age <- 80
      out <- hvtiRtemplates:::.read_upstream_job_data(cfg, lineage, list())
      expect_identical(out$job_data$data$ccfid, c(5L, 6L))
    })
    expect_identical(hvtiRtemplates:::.read_upstream_job_data(cfg, lineage, list())$job_data$data$ccfid, c(5L, 6L))
  }
})

test_that("an outside value in a WHERE on the ID is recorded but shown masked", {
  cfg <- job_study(d_ids)
  ids <- c(9001L, 9005L)
  out <- read_job_data(cfg, where = quote(!ccfid %in% ids))
  sel <- attr(out$record, "selection")
  expect_identical(sel$where, "!ccfid %in% c(9001L, 9005L)")
  expect_identical(sel$where_shown, "!ccfid %in% <value>")
  expect_false(any(grepl("9001|9005", c(out$record$step, out$record$value))))
  expect_identical(out$data$ccfid, c(9002L, 9003L, 9004L, 9006L))
})

test_that(".read_upstream_job_data() stops when the patients differ though the counts match", {
  cfg <- job_study(d_ids)
  up <- read_job_data(cfg, where = quote(age >= 18))
  sel <- attr(up$record, "selection")
  expect_match(sel$key_hash, "^[0-9a-f]{64}$")
  expect_identical(hvtiRtemplates:::.read_upstream_job_data(cfg, list(selection = sel), list())$job_data$data$ccfid,
                   c(9002L, 9003L, 9005L, 9006L))
  swapped <- d_ids
  swapped$ccfid[[2L]] <- 9999L
  cfg_swapped <- job_study(swapped)
  err <- tryCatch(hvtiRtemplates:::.read_upstream_job_data(cfg_swapped, list(selection = sel), list()),
                  error = conditionMessage)
  expect_match(err, "patients.*differ.*counts may match.*rerun the upstream job")
  expect_false(grepl("9999|900[0-9]", err))
  expect_false(grepl(sel$key_hash, err, fixed = TRUE))
  # An older selection with no key_hash is checked on its counts alone.
  older <- sel
  older$key_hash <- NULL
  expect_identical(nrow(hvtiRtemplates:::.read_upstream_job_data(cfg_swapped, list(selection = older), list())$job_data$data),
                   4L)
})
