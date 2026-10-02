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
  # The default names the upstream job's template; a caller whose upstream is
  # not a template, such as a bootstrap report, says what to run instead.
  expect_error(hvtiRtemplates:::.read_upstream_job_data(list(), list(data = list()), list(), read = FALSE),
               "Rerun the upstream job with the current template, then rerun this one[.]$")
  expect_error(
    hvtiRtemplates:::.read_upstream_job_data(list(), list(data = list()), list(), read = FALSE,
                                             source = "the bootstrap bag bagging.rds",
                                             rerun = "Rerun the bootstrap runner."),
    "\\(the bootstrap bag bagging[.]rds\\) carries no single recorded data selection.*combined[.] Rerun the bootstrap runner[.]$"
  )
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

# A WHERE on the patient identifier is refused: the selection saves each
# condition's exact text in every hand-off, so a filter on identifier values
# would put them in the job's output.
refusal <- function(expr) {
  tryCatch({
    force(expr)
    ""
  }, error = conditionMessage)
}

test_that("a WHERE on the ID stops before any row is filtered, and never prints its value", {
  cfg <- job_study(d_ids)
  for (where in list(quote(ccfid != 9001), quote(CCFID != 9001), rlang::exprs(age >= 18, ccfid != 9001),
                     quote(ccfid + 9001), quote(ccfid != nosuch + 9001), rlang::exprs(nosuch > 1, ccfid != 9001))) {
    err <- refusal(read_job_data(cfg, where = where))
    info <- paste(deparse(where), collapse = " ")
    expect_match(err, "patient identifier", info = info)
    expect_match(err, "`ccfid`", fixed = TRUE, info = info)
    expect_match(err, "saved.*output", info = info)
    expect_match(err, "dataset build.*analysis set", info = info)
    expect_false(grepl("9001", err, fixed = TRUE), info = info)
    # Checked before any condition runs, so a missing column is never looked up.
    expect_false(grepl("not found", err, fixed = TRUE), info = info)
  }
})

test_that("a WHERE on MRN or eMRN stops even when neither is the ID, and on a fallback ID", {
  cfg <- job_study(d0)
  for (where in list(quote(MRN > 103), quote(emrn == 201), quote(EMRN %in% c(201, 202)))) {
    err <- refusal(read_job_data(cfg, where = where))
    expect_match(err, "patient identifier", info = deparse(where))
    expect_false(grepl("10[0-9]|20[0-9]", err), info = deparse(where))
  }
  fallback <- job_study(d0[-1])
  err <- refusal(read_job_data(fallback, where = quote(mrn != 101)))
  expect_match(err, "patient identifier")
  expect_false(grepl("101", err, fixed = TRUE))
  # pt_mrn is an ordinary column: its name only contains mrn.
  expect_identical(nrow(read_job_data(cfg, where = quote(pt_mrn > 3))$data), 3L)
})

test_that("a WHERE on a KEY column that is not the ID is still allowed, and shown masked", {
  long <- data.frame(ccfid = c(9001L, 9001L, 9002L), iv_echo = c(0.1, 6.2, 0.3))
  cfg <- job_study(long)
  out <- read_job_data(cfg, where = quote(iv_echo < 5), key = c("ccfid", "iv_echo"))
  sel <- attr(out$record, "selection")
  expect_identical(sel$where, "iv_echo < 5")
  expect_identical(sel$where_shown, "iv_echo < <value>")
  expect_identical(sel$rows, 2L)
})

test_that("a selection saved before the refusal is still shown masked, and rebuilding it names the file", {
  cfg <- job_study(d_ids)
  sel <- attr(read_job_data(cfg, where = quote(age >= 18))$record, "selection")
  # As an upstream job saved it before WHERE on the ID was refused.
  sel$where <- c("ccfid != 9001", "age >= 18")
  differs <- refusal(hvtiRtemplates:::.check_upstream_selection(sel, list(where = quote(ccfid != 9002))))
  expect_match(differs, "WHERE")
  expect_match(differs, "ccfid != <value>", fixed = TRUE)
  expect_false(grepl("900[12]", differs))
  rebuilt <- refusal(hvtiRtemplates:::.read_upstream_job_data(cfg, list(selection = sel), list(), source = "hz.rds"))
  expect_match(rebuilt, "hz.rds", fixed = TRUE)
  expect_match(rebuilt, "patient identifier")
  expect_match(rebuilt, "remove it from the upstream job's WHERE, then rerun the upstream job", fixed = TRUE)
  # The advice is given once, and not as though the condition were this job's.
  expect_false(grepl("remove the condition from WHERE", rebuilt, fixed = TRUE))
  expect_identical(lengths(regmatches(rebuilt, gregexpr("rerun the upstream job", rebuilt, ignore.case = TRUE))), 1L)
  expect_false(grepl("9001", rebuilt, fixed = TRUE))
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

test_that("a WHERE that reaches a column through .data is masked, and stops", {
  mask <- hvtiRtemplates:::.mask_condition
  for (cond in list(quote(.data[["ccfid"]] != 9001), quote(.data$ccfid != 9001), quote(.data[["CCFID"]] != 9001))) {
    shown <- mask(cond, "ccfid")
    expect_false(grepl("9001", shown, fixed = TRUE), info = shown)
    expect_match(shown, "<value>", fixed = TRUE)
  }
  # .data naming the ID, MRN or eMRN as a literal stops, ignoring case.
  cfg <- job_study(d_ids)
  for (where in list(quote(.data[["ccfid"]] != 9001), quote(.data$ccfid != 9001), quote(.data[["CCFID"]] + 9001))) {
    err <- refusal(read_job_data(cfg, where = where))
    expect_match(err, "patient identifier", info = deparse(where))
    expect_match(err, "`ccfid`", fixed = TRUE, info = deparse(where))
    expect_false(grepl("9001", err, fixed = TRUE), info = deparse(where))
  }
  err <- refusal(read_job_data(job_study(d0), where = quote(.data[["mrn"]] > 103)))
  expect_match(err, "patient identifier")
  expect_false(grepl("103", err, fixed = TRUE))
})

test_that("a WHERE that names an ordinary column through .data is allowed, and shown masked", {
  cfg <- job_study(d_ids)
  for (where in list(quote(.data$age >= 18), quote(.data[["age"]] >= 18))) {
    out <- read_job_data(cfg, where = where)
    expect_identical(out$data$ccfid, c(9002L, 9003L, 9005L, 9006L), info = deparse(where))
    # The masking still hides the values of any condition that uses .data.
    expect_match(attr(out$record, "selection")$where_shown, ">= <value>", fixed = TRUE, info = deparse(where))
  }
})

test_that("a WHERE whose .data column is not written literally stops, and asks for the name", {
  cfg <- job_study(d_ids)
  for (where in list(quote(.data[[paste0("cc", "fid")]] == 9001), quote(nrow(.data) > 9001))) {
    err <- refusal(read_job_data(cfg, where = where))
    expect_match(err, "name the column", info = deparse(where))
    expect_match(err, "patient identifier", info = deparse(where))
    expect_false(grepl("9001", err, fixed = TRUE), info = deparse(where))
  }
  # An index from outside the data is fixed in first, so it is judged by the column it names.
  nm <- "age"
  expect_identical(nrow(read_job_data(cfg, where = quote(.data[[nm]] >= 18))$data), 4L)
  nm <- "ccfid"
  err <- refusal(read_job_data(cfg, where = quote(.data[[nm]] == 9001)))
  expect_match(err, "patient identifier (`ccfid`)", fixed = TRUE)
  expect_false(grepl("9001", err, fixed = TRUE))
})

test_that("a WHERE that reaches the ID through an outside symbol or condition stops", {
  cfg <- job_study(d_ids)
  col <- quote(ccfid)
  filt <- quote(ccfid != 9001)
  for (where in list(quote(col != 9001), quote(filt), rlang::exprs(age >= 18, filt))) {
    err <- refusal(read_job_data(cfg, where = where))
    expect_match(err, "patient identifier (`ccfid`)", fixed = TRUE, info = deparse(where))
    expect_false(grepl("9001", err, fixed = TRUE), info = deparse(where))
  }
})

test_that("a WHERE that looks a column up by a string stops, and is masked", {
  cfg <- job_study(d_ids)
  lookups <- list(quote(get("ccfid") != 9001), quote(get0("ccfid") != 9001), quote(base::get("ccfid") != 9001),
                  quote(mget("ccfid")[[1]] != 9001), quote(eval(as.name("ccfid")) != 9001),
                  quote(eval(as.symbol("ccfid")) != 9001), quote(evalq(get("ccfid")) != 9001),
                  quote(eval(str2lang("ccfid")) != 9001), quote(eval(parse(text = "ccfid")[[1]]) != 9001),
                  quote(eval(str2expression("ccfid")[[1]]) != 9001), quote(eval(rlang::sym("ccfid")) != 9001),
                  quote(eval(sym("ccfid")) != 9001))
  for (where in lookups) {
    info <- paste(deparse(where), collapse = " ")
    err <- refusal(read_job_data(cfg, where = where))
    expect_match(err, "name the column", info = info)
    expect_false(grepl("9001", err, fixed = TRUE), info = info)
    shown <- hvtiRtemplates:::.mask_condition(where, "ccfid")
    expect_false(grepl("9001", shown, fixed = TRUE), info = info)
  }
  # A lookup that names the ID literally is refused for the ID itself.
  expect_match(refusal(read_job_data(cfg, where = quote(evalq(ccfid) != 9001))), "patient identifier (`ccfid`)",
               fixed = TRUE)
  # The masking change is for string lookups only: an ordinary condition stays readable.
  expect_identical(hvtiRtemplates:::.mask_condition(quote(age >= 18), "ccfid"), "age >= 18")
})

test_that("a WHERE that takes a data frame, list, environment or S4 object from outside stops, naming it", {
  cfg <- job_study(d_ids)
  lookup <- data.frame(ccfid = 9001:9003, age = c(10, 30, 50))
  for (where in list(quote(with(lookup, ccfid) != 9001), quote(with(lookup, age) > 20))) {
    info <- paste(deparse(where), collapse = " ")
    err <- refusal(read_job_data(cfg, where = where))
    expect_match(err, "`lookup`", fixed = TRUE, info = info)
    expect_match(err, "filter on a column of the data", info = info)
    # Nothing from the frame reaches the message, and nothing is saved.
    expect_false(grepl("9001|9002|9003|10, 30, 50|structure", err), info = info)
  }
  holder <- list(cut = 18)
  box <- new.env()
  fn <- function(x) x
  setClass("WhereBox", representation(x = "numeric"), where = environment())
  s4 <- methods::new("WhereBox", x = 18)
  for (where in list(quote(age > holder[["cut"]]), quote(age > get("cut", box)), quote(age > s4))) {
    err <- refusal(read_job_data(cfg, where = where))
    expect_match(err, "filter on a column of the data", info = paste(deparse(where), collapse = " "))
  }
  # A function name carries no data, so it is left as the name, not refused.
  allowed <- list(list(quote(sapply(age, fn) > 18), 4L, "sapply(age, fn) > 18"),
                  list(quote(sapply(age, round) > 1), 5L, "sapply(age, round) > 1"),
                  list(quote(mapply(max, age, age) > 50), 3L, "mapply(max, age, age) > 50"),
                  list(quote(Reduce(`|`, list(age > 50, age < 20))), 4L, "Reduce(`|`, list(age > 50, age < 20))"))
  for (case in allowed) {
    out <- read_job_data(cfg, where = case[[1L]])
    expect_identical(nrow(out$data), case[[2L]], info = case[[3L]])
    expect_identical(attr(out$record, "selection")$where, case[[3L]])
  }
})

test_that("an outside atomic value or language object still resolves as before", {
  d <- data.frame(dt = as.Date(c("2020-01-01", "2020-01-03")), g = factor(c("a", "b")), x = c(1, 2))
  cut <- as.Date("2020-01-02")
  level <- factor("b", levels = c("a", "b"))
  at <- as.POSIXct("2020-01-02", tz = "UTC")
  vals <- c(2, 3)
  cond <- quote(x > 1)
  expect_identical(nrow(.apply_where(d, quote(dt >= cut), environment())$data), 1L)
  expect_identical(nrow(.apply_where(d, quote(g == level), environment())$data), 1L)
  expect_identical(nrow(.apply_where(d, quote(as.POSIXct(dt) >= at), environment())$data), 1L)
  expect_identical(nrow(.apply_where(d, quote(x %in% vals), environment())$data), 1L)
  expect_identical(.apply_where(d, quote(cond), environment())$steps$condition, "x > 1")
  nothing <- NULL
  expect_identical(nrow(.apply_where(d, quote(is.null(nothing) & x > 1), environment())$data), 1L)
})

test_that("a function named by a string, or called from a call, is a lookup", {
  cfg <- job_study(d_ids)
  for (where in list(quote(do.call("get", list("ccfid")) != 9001), quote(match.fun("get")("ccfid") != 9001),
                     quote((function(x) x)(ccfid2) != 9001))) {
    info <- paste(deparse(where), collapse = " ")
    err <- refusal(read_job_data(cfg, where = where))
    expect_match(err, "name the column", info = info)
    expect_false(grepl("9001", err, fixed = TRUE), info = info)
    expect_false(grepl("9001", hvtiRtemplates:::.mask_condition(where, "ccfid"), fixed = TRUE), info = info)
  }
  # pkg::fn is a name, not a call computed at run time.
  expect_identical(hvtiRtemplates:::.mask_condition(quote(base::round(age) >= 18), "ccfid"), "base::round(age) >= 18")
  expect_identical(nrow(read_job_data(cfg, where = quote(base::round(age) >= 18))$data), 4L)
})

test_that("an alias of a lookup function is refused as that lookup, before anything is filtered", {
  alias <- get
  err <- refusal(.apply_where(data.frame(ccfid = 9001:9003), quote(alias("ccfid") != 9001), env = environment(),
                              cols = "ccfid", identifiers = c("ccfid", "mrn", "emrn")))
  expect_match(err, "name the column")
  expect_false(grepl("9001", err, fixed = TRUE))
})

d_long_ids <- data.frame(ccfid = 4730000001 + 0:5, age = c(15, 40, 55, NA, 70, 80))

test_that("a WHERE value that is also a patient identifier in the data is refused, however it is reached", {
  d <- d_long_ids
  d$id2 <- d$ccfid
  cfg <- job_study(d)
  f <- function(x) get(x)
  ids <- c(4730000001, 4730000002)
  for (where in list(quote(f("ccfid") != 4730000001), quote(id2 != 4730000001), quote(id2 %in% ids),
                     quote(age > 18 & id2 %in% c(5, 4730000002)))) {
    info <- paste(deparse(where), collapse = " ")
    err <- refusal(read_job_data(cfg, where = where))
    expect_match(err, "also a patient identifier in the data", info = info)
    expect_match(err, "`ccfid`", fixed = TRUE, info = info)
    expect_false(grepl("47300000", err, fixed = TRUE), info = info)
  }
  # A threshold that equals no identifier is allowed; NA never matches.
  expect_identical(nrow(read_job_data(cfg, where = quote(age > 60))$data), 2L)
  expect_identical(nrow(read_job_data(cfg, where = quote(!id2 %in% c(NA, 1)))$data), 6L)
})

test_that("a WHERE constant expression that evaluates to an identifier is refused before any row is filtered", {
  d <- data.frame(ccfid = 4730000001 + 0:2, id2 = 4730000001 + 0:2, age = c(50, 70, 80))
  cfg <- job_study(d)
  for (where in list(quote(id2 != 4730000000 + 1), quote(id2 != as.numeric("4730000001")),
                     quote(id2 %in% c(4730000000 + 1, 4730000000 + 2)))) {
    info <- paste(deparse(where), collapse = " ")
    err <- refusal(read_job_data(cfg, where = where))
    expect_match(err, "also a patient identifier in the data", info = info)
    expect_match(err, "`ccfid`", fixed = TRUE, info = info)
    expect_false(grepl("4730000001|4.73e", err), info = info)
  }
  # Nothing is filtered: the refusal comes from the check, before evaluation.
  expect_error(.apply_where(d, quote(id2 != 4730000000 + 1), environment(), cols = "ccfid",
                            identifiers = "ccfid", id_values = list(ccfid = .id_text(d$ccfid))),
               class = "hvti_where_identifier")
  chr <- data.frame(ccfid = paste0("A", 4730000001 + 0:2), id2 = paste0("A", 4730000001 + 0:2), age = c(50, 70, 80))
  err <- refusal(read_job_data(job_study(chr), where = quote(id2 != paste0("A47300", "00001"))))
  expect_match(err, "also a patient identifier in the data")
  expect_false(grepl("A4730000001", err, fixed = TRUE))
  # Thresholds computed from constants are allowed when they equal no identifier, or are short.
  expect_identical(nrow(read_job_data(cfg, where = quote(age > 60 + 5))$data), 2L)
  expect_identical(nrow(read_job_data(cfg, where = quote(age > 2000 + 26 - 1960))$data), 2L)
  expect_identical(nrow(read_job_data(cfg, where = quote(age < 2000 + 26))$data), 3L)
})

test_that("a refused WHERE executes nothing: the name checks run before any value is computed", {
  cfg <- job_study(d_ids)
  calls <- new.env()
  calls$n <- 0L
  f <- function() {
    calls$n <- calls$n + 1L
    1
  }
  expect_match(refusal(read_job_data(cfg, where = quote(ccfid != f()))), "patient identifier")
  expect_identical(calls$n, 0L)
  path <- withr::local_tempfile()
  file.create(path)
  expect_match(refusal(read_job_data(cfg, where = quote(ccfid != unlink(path)))), "patient identifier")
  expect_true(file.exists(path))
  # Across conditions too: a later refused condition stops before an earlier one is computed.
  expect_match(refusal(read_job_data(cfg, where = rlang::exprs(age > f(), ccfid != 9001))), "patient identifier")
  expect_identical(calls$n, 0L)
})

test_that("an allowed stateful WHERE call runs exactly once", {
  cfg <- job_study(d_ids)
  calls <- new.env()
  calls$n <- 0L
  cutoff <- function() {
    calls$n <- calls$n + 1L
    if (calls$n == 1L) 75 else 55
  }
  out <- read_job_data(cfg, where = quote(age > cutoff()))
  expect_identical(calls$n, 1L)
  expect_equal(out$data$age, 80)
})

test_that("the value check folds only base arithmetic, c(), paste and coercion, never a shadowed function", {
  flag <- new.env()
  flag$hit <- FALSE
  paste0 <- function(...) {
    flag$hit <- TRUE
    base::paste0(...)
  }
  found <- .where_constants(quote(id2 != paste0("47300", "00001")), data_cols = "id2", env = environment())
  expect_false(flag$hit)
  expect_false("4730000001" %in% found)
  # Unshadowed, the allowlisted functions fold.
  expect_true("4730000001" %in% .where_constants(quote(id2 != paste0("47300", "00001")), "id2", baseenv()))
  expect_true("4730000001" %in% .where_constants(quote(id2 != as.numeric("4730000001")), "id2", baseenv()))
  expect_true("4730000002" %in% .where_constants(quote(id2 %in% c(4730000000 + 1, (4730000000 + 2))), "id2",
                                                 baseenv()))
  # A call outside the allowlist is not folded, so its value is not seen.
  expect_false("4730000001" %in% .where_constants(quote(id2 != sum(4730000000, 1)), "id2", baseenv()))
})

test_that("a value transformed through a data column is allowed: the documented limit of the value check", {
  d <- data.frame(ccfid = 4730000001 + 0:2, id2 = 4730000001 + 0:2)
  out <- read_job_data(job_study(d), where = quote(id2 / 2 != 2365000000.5))
  expect_identical(nrow(out$data), 2L)
})

test_that("short identifiers do not collide with thresholds: hx_chf == 1 and age >= 18 are allowed with IDs 1..n", {
  cfg <- job_study(d0)
  expect_identical(read_job_data(cfg, where = rlang::exprs(age >= 18, hx_chf == 1))$data$ccfid, c(2L, 3L, 5L))
})

test_that("a copy column filtered on a 4-character ID value is allowed: the documented limit of the value check", {
  d <- d_ids
  d$id2 <- d$ccfid
  out <- read_job_data(job_study(d), where = quote(id2 != 9001))
  expect_identical(nrow(out$data), 5L)
})

test_that("an MRN or eMRN value is refused against any column, though those columns are dropped", {
  d <- data.frame(ccfid = 9001:9004, MRN = 7000001:7000004, eMRN = 8000001:8000004, score = c(7000001, 2, 3, 8000002))
  cfg <- job_study(d)
  # read_built() lowercases column names, so the columns are named mrn and emrn.
  for (case in list(list(quote(score != 7000001), "`mrn`"), list(quote(score != 8000002), "`emrn`"))) {
    err <- refusal(read_job_data(cfg, where = case[[1L]]))
    expect_match(err, "also a patient identifier in the data", info = case[[2L]])
    expect_match(err, case[[2L]], fixed = TRUE)
    expect_false(grepl("700000|800000", err), info = case[[2L]])
  }
})

test_that("a name that is not a column is not taken for the ID", {
  cfg <- job_study(d_ids)
  ccfid <- 18
  mrn <- c(1, 18)
  lst <- list(mrn = 18)
  # .env$ccfid and an outside mrn are fixed in as constants, so nothing names the ID.
  out <- read_job_data(cfg, where = quote(age > .env$ccfid))
  expect_identical(attr(out$record, "selection")$where, "age > 18")
  expect_identical(nrow(read_job_data(cfg, where = quote(age > .env[["ccfid"]]))$data), 4L)
  # Its value is still checked: an outside ccfid that is a patient's identifier is refused.
  ccfid <- 4730000001
  expect_match(refusal(read_job_data(job_study(d_long_ids), where = quote(age > .env$ccfid - 4730000000))),
               "also a patient identifier")
  expect_identical(nrow(read_job_data(cfg, where = quote(age > max(mrn)))$data), 4L)
  # An .env lookup that resolves to nothing is still not the ID column: it fails as an
  # unknown name, not as a refusal.
  for (where in list(quote(age > .env$emrn), quote(age > .env[["emrn"]]))) {
    err <- refusal(read_job_data(cfg, where = where))
    expect_match(err, "emrn", info = deparse(where))
    expect_false(grepl("patient identifier", err, fixed = TRUE), info = deparse(where))
  }
  # The right side of $ names a field, not a column.
  expect_identical(nrow(read_job_data(cfg, where = quote(age >= lst$mrn))$data), 4L)
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

test_that("an outside value in a WHERE on the ID stops, and is never printed", {
  cfg <- job_study(d_ids)
  ids <- c(9001L, 9005L)
  err <- refusal(read_job_data(cfg, where = quote(!ccfid %in% ids)))
  expect_match(err, "patient identifier")
  expect_false(grepl("9001|9005", err))
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

test_that("a value fixed into WHERE from outside the data rebuilds exactly", {
  cut <- 1 / 3
  d <- data.frame(x = c(cut, 0.3333333333333333, 0.34))
  steps <- .apply_where(d, quote(x >= cut), environment())
  expect_identical(eval(str2lang(steps$steps$condition)[[3L]]), cut)
})

test_that("a typed WHERE value keeps its short text", {
  steps <- .apply_where(data.frame(x = c(0.05, 0.2)), quote(x >= 0.1), environment())
  expect_identical(steps$steps$condition, "x >= 0.1")
})
