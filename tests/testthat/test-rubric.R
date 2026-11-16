# The hvtiR family's shared conventions: renamed arguments, quiet mode,
# condition classes and the seven-field provenance record. The rubric is
# Projects/hvtiR API rubric in the maintainer's vault. All data are synthetic.

# A fresh once-per-session register, so each test sees the first warning.
local_fresh_renames <- function(.local_envir = parent.frame()) {
  env <- hvtiRtemplates:::.renamed_warned
  old <- as.list(env)
  rm(list = ls(env), envir = env)
  withr::defer({
    rm(list = ls(env), envir = env)
    list2env(old, env)
  }, envir = .local_envir)
}

lt_data <- function() {
  data.frame(t = c(0.5, 1, 1.5, 2, 3, 4), e = c(1, 0, 1, 1, 0, 0), g = c("a", "b", "a", "b", "a", "b"))
}

test_that("an old argument name works, and warns once per session", {
  skip_if_not_installed("TemporalHazard")
  local_fresh_renames()
  d <- lt_data()
  expect_warning(old <- life_table_keep(d, time = "t", event_col = "e"), "`time` is renamed `time_col`",
                 class = "hvtiRtemplates_deprecated")
  expect_identical(old, life_table_keep(d, "t", "e"))
  expect_no_warning(life_table_keep(d, time_col = "t", event_col = "e"))
  # The second use of the same old name is silent.
  expect_silent(life_table_keep(d, time = "t", event_col = "e"))
})

test_that("giving an old name with its new one is an error naming both", {
  local_fresh_renames()
  d <- lt_data()
  expect_error(life_table_keep(d, time_col = "t", event_col = "e", time = "t"),
               "life_table_keep\\(\\): `time` and `time_col` were both given")
  expect_error(build_cohort(data.frame(ccfid = "A"), id_col = "ccfid", id = "ccfid"),
               "`id` and `id_col` were both given")
  expect_error(add_job("ac", "death", "hz", root = tempdir(), dir = tempdir()), "`dir` and `root` were both given")
})

test_that("an old name in the same position still binds positionally", {
  local_fresh_renames()
  out <- build_cohort(data.frame(ccfid = c("A", "B")), NULL, NULL, NULL, "ccfid")
  expect_identical(out$attrition$patients_after, 2L)
})

test_that("an id column left out warns that its default is going, and reads ccfid", {
  local_fresh_renames()
  expect_warning(out <- build_cohort(data.frame(ccfid = c("A", "B"))), "`id_col` will have no default",
                 class = "hvtiRtemplates_deprecated")
  expect_identical(out$attrition$patients_after, 2L)
})

test_that("hvti.quiet silences messages and never warnings or errors", {
  expect_message(hvtiRtemplates:::.hvti_inform("said"), "said")
  withr::local_options(hvti.quiet = TRUE)
  expect_silent(hvtiRtemplates:::.hvti_inform("said"))
  expect_true(hvtiRtemplates:::.hvti_quiet())
  expect_identical(formals(render_job)$quiet, quote(isTRUE(getOption("hvti.quiet"))))
  expect_identical(formals(run_job)$quiet, quote(isTRUE(getOption("hvti.quiet"))))
})

test_that("a refusal a caller may catch carries an hvtiRtemplates_ class", {
  err <- tryCatch(hvtiRtemplates:::.abort("fn(): refused.", class = "run_refused"), error = identity)
  expect_s3_class(err, "hvtiRtemplates_run_refused")
  expect_identical(conditionMessage(err), "fn(): refused.")
  expect_null(conditionCall(err))
})
