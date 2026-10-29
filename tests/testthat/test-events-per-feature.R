# The draft reasons live in the package's run state; each test starts it empty and restores it.
local_draft_reasons <- function(.local_envir = parent.frame()) {
  rs <- hvtiRtemplates:::.run_state
  old <- rs$draft_reasons
  rs$draft_reasons <- character()
  withr::defer(rs$draft_reasons <- old, envir = .local_envir)
}

test_that("events per feature reports each group and stays quiet at or above the floor", {
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "")
  local_draft_reasons()
  out <- expect_silent(hvtiRtemplates:::.check_events_per_feature(c(A = 60, B = 40), 2L, floor = 20))
  expect_equal(out$events_per_feature, c(30, 20))
  expect_length(hvtiRtemplates:::.run_state$draft_reasons, 0L)
})

test_that("below the floor it warns naming the group and marks the report draft", {
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "")
  local_draft_reasons()
  expect_warning(hvtiRtemplates:::.check_events_per_feature(c(A = 60, B = 12), 20L, floor = 20),
                 "B has 12 event\\(s\\) for 20 feature\\(s\\), 0.6 each")
  expect_match(hvtiRtemplates:::.run_state$draft_reasons, "fewer than 20 events per candidate feature")
})

test_that("a final render stops below the floor, and a floor of 0 never warns", {
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "1")
  expect_error(hvtiRtemplates:::.check_events_per_feature(c(cohort = 5), 3L, floor = 20), "HVTI_TEMPLATE_STRICT")
  expect_silent(hvtiRtemplates:::.check_events_per_feature(c(cohort = 5), 3L, floor = 0))
})
