# bd's Checks section: what the rebuild changed, cross-tabs, follow-up and named checks, run on the
# data frame write-built has just written. Ported from the dt template's tests (dev/specs/2026-10-29-bd-checks-design.md).

test_that("the Checks section sits between write-built and Register", {
  src <- readLines(hazard_template("bd"), warn = FALSE)  # nolint: object_usage_linter.
  at <- function(label) which(trimws(src) == paste0("#| label: ", label))
  expect_true(at("write-built") < at("rebuild"))
  expect_true(at("rebuild") < at("crosstabs"))
  expect_true(at("crosstabs") < at("followup"))
  expect_true(at("followup") < at("tbl-checks"))
  expect_true(at("tbl-checks") < at("register"))
  expect_false(any(grepl("read-working", src, fixed = TRUE)))
})

test_that("a rebuild of the study dataset is compared against its registered version", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  bd_draft(root, bd_check_choices(m))
  bd_run(root, bd_check_choices(m, register = TRUE))
  env <- bd_check_run(root, bd_check_choices(m), labels = "rebuild")
  expect_match(env$.rebuild_state, "^A rebuild of the study dataset: study_cohort.rds against its registered version ")
  # Nothing changed since registering, so every column reads identical.
  expect_true(all(env$.comparison$verdict == "identical"))
  rows <- attr(env$.comparison, "rows")
  expect_identical(c(length(rows$only_oracle), length(rows$only_r)), c(0L, 0L))
})

test_that("the rebuild comparison reports values, not shape, against the registered version", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  bd_draft(root, bd_check_choices(m))
  bd_run(root, bd_check_choices(m, register = TRUE))
  # HVTI_DATA = "working" makes read_built() serve the working file unless told not to;
  # the baseline must still be the registered version, or every column reads identical.
  withr::local_envvar(HVTI_DATA = "working")
  env <- bd_check_run(root, bd_check_choices(m), labels = "rebuild", change = function(d) {
    d$dead <- 1L - d$dead
    d$iv_dead <- d$iv_dead + 1
    d$ccfid[[1L]] <- "PTSWAP001"
    d
  })
  cmp <- as.data.frame(env$.comparison)
  rows <- attr(env$.comparison, "rows")
  expect_identical(rows$n_oracle, rows$n_r)
  changed <- cmp[cmp$variable %in% c("dead", "iv_dead"), ]
  expect_identical(changed$verdict, c("differs", "differs"))
  expect_identical(changed$n_differ, rep(rows$n_common, 2L))
  expect_true(all(cmp$verdict[!cmp$variable %in% c("dead", "iv_dead")] == "identical"))
  expect_length(rows$only_oracle, 1L)
  expect_identical(rows$only_r, "PTSWAP001")
  # The identifiers go to the console's stderr, never into the report's output.
  expect_false(any(grepl("PTSWAP001", env$.stdout, fixed = TRUE)))
})

test_that("a comparison build is compared against the study dataset and says it is a comparison build", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  bd_draft(root, bd_check_choices(m, DATASET_ID = "legacy"))
  bd_run(root, bd_check_choices(m, register = TRUE, DATASET_ID = "legacy"))
  rebuild <- bd_check_choices(m, DATASET_ID = "study_rebuild")
  # Assigned, not merged with modifyList(), which would merge the two lists of rules.
  rebuild$EXCLUDE <- list(age < 50 ~ "Under 50")
  env <- bd_check_run(root, rebuild, labels = "rebuild")
  expect_identical(hvtiRutilities::study_config(root)$built, "legacy.rds")
  expect_match(env$.rebuild_state, "^A comparison build: study_rebuild.rds is not the study dataset\\.")
  expect_match(env$.rebuild_state, "dataset legacy.rds, registered as legacy_[0-9]{8}[.]parquet")
  rows <- attr(env$.comparison, "rows")
  expect_identical(rows$n_r, nrow(env$d))
  expect_identical(length(rows$only_oracle), sum(m$data$age >= 40 & m$data$age < 50, na.rm = TRUE))
  expect_length(rows$only_r, 0L)
})

test_that("with nothing registered there is no comparison, and the report says so", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  env <- bd_check_run(root, bd_check_choices(m), labels = "rebuild")
  expect_null(env$.comparison)
  expect_identical(env$.rebuild_state,
                   "Nothing is registered for this study yet, so there is no version to compare this build against.")
})

test_that("the cross-tab, follow-up and named-check sections report counts", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  env <- bd_check_run(root, bd_check_choices(m), labels = c("crosstabs", "followup", "tbl-checks"),
                      change = function(d) {
                        d$iv_dead[1:3] <- c(0, -1, NA)
                        d
                      })
  out <- paste(env$.stdout, collapse = "\n")
  expect_match(out, "### dead by sex", fixed = TRUE)
  expect_match(out, "row(s) look suspicious, listed in the console", fixed = TRUE)
  expect_identical(env$.checked$label, "Follow-up of zero or less")
  expect_identical(env$.checked$n, 2L)
  expect_identical(env$.checked$n_missing, 1L)
  expect_true(all(c("dead", "sex", "Frequency", "Small") %in% names(env$.tab)))
})

test_that("a KEY of several columns with a missing part is refused, not joined on the text NA", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  bd_draft(root, bd_check_choices(m, KEY = c("ccfid", "dt_surg")))
  bd_run(root, bd_check_choices(m, register = TRUE, KEY = c("ccfid", "dt_surg")))
  expect_error(
    bd_check_run(root, bd_check_choices(m, KEY = c("ccfid", "dt_surg")), labels = "rebuild", change = function(d) {
      d$dt_surg[[2L]] <- NA
      d
    }),
    "bd: rebuild .*missing value", perl = TRUE
  )
})

test_that("the follow-up section counts every suspicious row, not the 25 it lists", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  env <- bd_check_run(root, bd_check_choices(m), labels = "followup", change = function(d) {
    d$iv_dead[1:40] <- 0
    d
  })
  expected <- sum(is.na(env$d$dead) | is.na(env$d$iv_dead) | env$d$iv_dead <= 0)
  expect_gt(expected, 25L)
  expect_match(paste(env$.stdout, collapse = "\n"), paste0("\n", expected, " row(s) look suspicious"), fixed = TRUE)
})

test_that("a logical derivation is compared by value, as read_built() reads it", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  flag <- function(d) {
    d$flag <- d$dead == 1L
    d
  }
  # The registered version carries the logical column: declare the working file (a first, unregistered
  # build does), write it with the column, then register it.
  bd_run(root, bd_check_choices(m))
  env <- bd_check_run(root, bd_check_choices(m), labels = character(), change = flag)
  saveRDS(env$d, file.path(hvtiRutilities::study_dir("datasets", root), "study_cohort.rds"))
  withr::with_dir(root, suppressMessages(hvtiRutilities::update_manifest(dataset = "study")))
  env <- bd_check_run(root, bd_check_choices(m), labels = "rebuild", change = flag)
  cmp <- as.data.frame(env$.comparison)
  expect_identical(cmp$verdict[cmp$variable == "flag"], "identical")
  env <- bd_check_run(root, bd_check_choices(m), labels = "rebuild", change = function(d) {
    d <- flag(d)
    d$flag <- !d$flag
    d
  })
  cmp <- as.data.frame(env$.comparison)
  expect_identical(cmp$verdict[cmp$variable == "flag"], "differs")
  expect_identical(cmp$n_differ[cmp$variable == "flag"], attr(env$.comparison, "rows")$n_common)
  expect_true(is.logical(env$d$flag))
})

test_that("bad check choices stop in check-choices, naming no value", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  # Assigned, not merged with modifyList(), which would leave the unnamed list of pairs as it was.
  worse <- bd_check_choices(m)
  worse$CROSSTABS <- list(1L)
  expect_error(bd_run(root, worse, labels = c("setup", "edit-study-choices", "check-choices")),
               "bd: check-choices .*CROSSTABS must be a list of column-name vectors", perl = TRUE)
  bad <- bd_check_choices(m)
  bad$CHECKS <- "not a formula"
  expect_error(bd_run(root, bad, labels = c("setup", "edit-study-choices", "check-choices")),
               "bd: check-choices .*CHECKS must be a list", perl = TRUE)
  ev <- bd_check_choices(m, EVENT = c("a", "b"))
  expect_error(bd_run(root, ev, labels = c("setup", "edit-study-choices", "check-choices")),
               "bd: check-choices .*EVENT must be one column name", perl = TRUE)
})

test_that("a cross-tab refuses the patient identifier and a column of KEY, naming it", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  err <- expect_error(bd_run(root, bd_check_choices(m, CROSSTABS = list(c("ccfid", "sex")))), "^bd: check-choices \\(")
  expect_match(conditionMessage(err), "ccfid", fixed = TRUE)
  # A column of a composite KEY, spelled in upper case: the screen reads the lower-cased names.
  err <- expect_error(
    bd_run(root, bd_check_choices(m, KEY = c("ccfid", "dt_surg"), CROSSTABS = list(c("DT_SURG", "sex")))),
    "^bd: check-choices \\("
  )
  expect_match(conditionMessage(err), "dt_surg", fixed = TRUE)
  expect_false(grepl("PT00", conditionMessage(err), fixed = TRUE))
})

test_that("a cross-tab of a column with more than 20 distinct values stops, naming the column and the count", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  err <- expect_error(
    bd_check_run(root, bd_check_choices(m, CROSSTABS = list(c("grp", "sex"))), labels = "crosstabs", change = function(d) {
      d$grp <- sprintf("ZQXG%02d", rep_len(1:21, nrow(d)))
      d
    }),
    "^bd: crosstabs \\("
  )
  msg <- conditionMessage(err)
  expect_match(msg, "grp has 21 distinct values", fixed = TRUE)
  expect_false(any(grepl("ZQXG01", msg, fixed = TRUE), grepl("ZQXG21", msg, fixed = TRUE)))
})

test_that("a cross-tab of a column the data lacks stops in crosstabs and names it", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  err <- expect_error(
    bd_check_run(root, bd_check_choices(m, CROSSTABS = list(c("no_such_col", "sex"))), labels = "crosstabs"),
    "^bd: crosstabs \\("
  )
  expect_match(conditionMessage(err), "no_such_col", fixed = TRUE)
})

test_that("a CHECKS condition naming a missing column stops tbl-checks, and nothing is registered", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  with_checks <- c("setup", "set", "edit-study-choices", "check-choices", "read-master", "cohort", "derive",
                   "write-built", bd_check_labels, "register")
  bd_draft(root, bd_check_choices(m), labels = with_checks)
  bad <- bd_check_choices(m, register = TRUE)
  bad$CHECKS <- list(no_such_col > 1 ~ "A column the data lacks")
  expect_error(bd_run(root, bad, labels = with_checks), "^bd: tbl-checks \\(")
  expect_length(bd_versions(root), 0L)
})

test_that("a draft whose checks stop has reviewed nothing", {
  bd_skip()
  m <- bd_master()
  root <- bd_study()
  with_checks <- c("setup", "set", "edit-study-choices", "check-choices", "read-master", "cohort", "derive",
                   "write-built", bd_check_labels, "register")
  bad <- bd_check_choices(m)
  bad$CHECKS <- list(no_such_col > 1 ~ "A column the data lacks")
  expect_error(bd_draft(root, bad, labels = with_checks), "^bd: tbl-checks \\(")
  expect_false(file.exists(file.path(hvtiRutilities::study_dir("datasets", root), "study_cohort.reviewed.yml")))
})
