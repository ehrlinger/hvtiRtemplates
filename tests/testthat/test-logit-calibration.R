# The numerical core of the lg template: the internals in R/logit-calibration.R.
# The design is dev/specs/2026-10-11-lg-template-design.md; its section 5 lists
# what these tests cover. All data are synthetic.

test_that(".lg_groups() reproduces PROC RANK GROUPS=5 on a 12-row fixture with ties", {
  # PROC RANK GROUPS=G assigns floor(rank * G / (n + 1)), the rank averaged over
  # ties. Worked by hand for n = 12 and G = 5, so n + 1 = 13:
  #
  #   sorted value        1    3    3    4    6    6    6    9   10    12    12   20
  #   rank (ties mean)    1  2.5  2.5    4    6    6    6    8    9  10.5  10.5   12
  #   rank * 5 / 13    0.38 0.96 0.96 1.54 2.31 2.31 2.31 3.08 3.46  4.04  4.04 4.62
  #   group               0    0    0    1    2    2    2    3    3     4     4    4
  #
  # The tied 3s, 6s and 12s each share a group. A rule that ranks ties in order
  # would split them: the second 3 would be rank 3 and fall in group 1.
  x <- c(12, 3, 20, 6, 1, 9, 6, 12, 4, 10, 3, 6)
  got <- hvtiRtemplates:::.lg_groups(x, groups = 5L)
  expect_identical(got$group, c(4L, 0L, 4L, 2L, 0L, 3L, 2L, 4L, 1L, 3L, 0L, 2L))
  expect_identical(got$missing, 0L)
  expect_identical(as.integer(table(got$group)), c(3L, 1L, 3L, 2L, 3L))
})

test_that(".lg_groups() puts a rank that makes the product a whole number in the higher group", {
  # n = 9, G = 5, so n + 1 = 10 and rank 2 gives exactly 2 * 5 / 10 = 1: group 1, not 0.
  got <- hvtiRtemplates:::.lg_groups(1:9, groups = 5L)
  expect_identical(got$group, c(0L, 1L, 1L, 2L, 2L, 3L, 3L, 4L, 4L))
})

test_that(".lg_groups() drops a missing covariate and counts it, without moving the other groups", {
  x <- c(12, 3, 20, 6, 1, 9, 6, 12, 4, 10, 3, 6)
  got <- hvtiRtemplates:::.lg_groups(c(x, NA, NA), groups = 5L)
  expect_identical(got$group, c(4L, 0L, 4L, 2L, 0L, 3L, 2L, 4L, 1L, 3L, 0L, 2L, NA, NA))
  expect_identical(got$missing, 2L)
})

test_that(".lg_groups() takes each observed level of an ordinal covariate as a group", {
  # %logitgr: the covariate is its own grouping, so `groups` has no say.
  x <- c(3, 1, 2, 2, 3, 3, 1, NA)
  got <- hvtiRtemplates:::.lg_groups(x, groups = 5L, kind = "ordinal")
  expect_identical(got$group, c(2L, 0L, 1L, 1L, 2L, 2L, 0L, NA))
  expect_identical(got$missing, 1L)
  # A level that is absent leaves no empty group: levels 1, 2 and 4 are groups 0, 1 and 2.
  expect_identical(hvtiRtemplates:::.lg_groups(c(4, 1, 2), kind = "ordinal")$group, c(2L, 0L, 1L))
})

test_that(".lg_groups() stops on a covariate or group count it cannot use", {
  expect_error(hvtiRtemplates:::.lg_groups(c("a", "b")), "^x must be numeric")
  expect_error(hvtiRtemplates:::.lg_groups(c(NA_real_, NA_real_)), "^x has no value")
  expect_error(hvtiRtemplates:::.lg_groups(1:9, groups = 1L), "^groups must be a whole number of at least 2")
  expect_error(hvtiRtemplates:::.lg_groups(1:9, groups = 2.5), "^groups must be a whole number of at least 2")
  expect_error(hvtiRtemplates:::.lg_groups(1:9, groups = NA_integer_), "^groups must be a whole number of at least 2")
  # The count is not checked for an ordinal covariate, which does not use it.
  expect_identical(hvtiRtemplates:::.lg_groups(1:3, groups = NA, kind = "ordinal")$group, 0:2)
})

# The 12-row fixture of the grouping test, with an event and a follow-up time
# for each patient. Its five groups are, in order:
#
#   group  x values    patients (positions)  events  follow-up
#     1    1, 3, 3     5, 2, 11              1       1 + 1 + 5 = 7
#     2    4           9                     0       6
#     3    6, 6, 6     4, 7, 12              2       3 + 2 + 3 = 8
#     4    9, 10       6, 10                 1       1 + 4 = 5
#     5    12, 12, 20  1, 8, 3                3       2 + 2 + 4 = 8
lg_fixture <- function() {
  list(
    x = c(12, 3, 20, 6, 1, 9, 6, 12, 4, 10, 3, 6),
    event = c(1L, 0L, 1L, 1L, 0L, 0L, 0L, 1L, 0L, 1L, 1L, 1L),
    time = c(2, 1, 4, 3, 5, 1, 2, 2, 6, 4, 1, 3)
  )
}

test_that(".lg_table() gives one row per group with the mean, range, counts and the logit", {
  f <- lg_fixture()
  tab <- hvtiRtemplates:::.lg_table(f$x, f$event, groups = 5L, link = "logit")
  expect_named(tab, c("group", "mean", "min", "max", "n", "events", "rate", "link"))
  expect_identical(tab$group, 1:5)
  expect_equal(tab$mean, c(7 / 3, 4, 6, 9.5, 44 / 3))
  expect_equal(tab$min, c(1, 4, 6, 9, 12))
  expect_equal(tab$max, c(3, 4, 6, 10, 20))
  expect_identical(tab$n, c(3L, 1L, 3L, 2L, 3L))
  expect_identical(tab$events, c(1L, 0L, 2L, 1L, 3L))
  expect_equal(tab$rate, c(1 / 3, 0, 2 / 3, 1 / 2, 1))
  # log(p / (1 - p)): log(1/2), then undefined for a rate of 0, log(2), 0, and undefined for a rate of 1.
  expect_equal(tab$link, c(log(0.5), NA, log(2), 0, NA))
  expect_identical(attr(tab, "dropped"), c(covariate = 0L, follow_up = 0L, event = 0L))
})

test_that(".lg_table() with the hazard link is the log of events over summed follow-up", {
  f <- lg_fixture()
  tab <- hvtiRtemplates:::.lg_table(f$x, f$event, f$time, groups = 5L, link = "hazard")
  expect_identical(tab$events, c(1L, 0L, 2L, 1L, 3L))
  expect_equal(tab$rate, c(1 / 7, 0, 2 / 8, 1 / 5, 3 / 8))
  # log(events / sum(time)); no events in group 2, so no log.
  expect_equal(tab$link, c(log(1 / 7), NA, log(2 / 8), log(1 / 5), log(3 / 8)))
})

test_that("a group whose link cannot be computed keeps its row, blank, and is named in a note", {
  f <- lg_fixture()
  tab <- hvtiRtemplates:::.lg_table(f$x, f$event, groups = 5L, link = "logit")
  expect_identical(nrow(tab), 5L)
  notes <- attr(tab, "notes")
  expect_length(notes, 2L)
  expect_match(notes[[1L]], "^Group 2 [(]n = 1, events = 0[)]: no patient had the event, so the rate is 0 and its logit is undefined")
  expect_match(notes[[2L]], paste0("^Group 5 [(]n = 3, events = 3[)]: every patient had the event, ",
                                   "so the rate is 1 and its logit is undefined"))
  expect_match(notes, "The point is left blank[.]$", all = TRUE)
  haz <- hvtiRtemplates:::.lg_table(f$x, f$event, f$time, groups = 5L, link = "hazard")
  expect_match(attr(haz, "notes"), "^Group 2 [(]n = 1, events = 0[)]: no patient had the event, so the hazard rate is 0")
  expect_length(attr(haz, "notes"), 1L)
  # A fully defined table has no note.
  expect_identical(attr(hvtiRtemplates:::.lg_table(f$x, rep(c(1L, 0L), 6L), groups = 2L), "notes"), character(0))
})

test_that(".lg_table() drops a missing covariate or follow-up and counts it, and leaves an unknown event out of n", {
  f <- lg_fixture()
  # Two more patients: one without the covariate, one without follow-up. A patient without an
  # event value is still ranked (PROC SUMMARY's N counts the event, not the covariate) but is
  # in neither n nor events.
  x <- c(f$x, NA, 5, 7)
  event <- c(f$event, 1L, 1L, NA)
  time <- c(f$time, 3, NA, 2)
  tab <- hvtiRtemplates:::.lg_table(x, event, time, groups = 5L, link = "hazard")
  expect_identical(attr(tab, "dropped"), c(covariate = 1L, follow_up = 1L, event = 1L))
  # 13 patients are ranked, so n + 1 = 14 and the groups move; the patient with x = 7 has no event.
  expect_identical(sum(tab$n), 12L)
  expect_identical(sum(tab$events), 7L)
  # The logit link does not need follow-up, so a missing time is not dropped.
  tab <- hvtiRtemplates:::.lg_table(x, event, time, groups = 5L, link = "logit")
  expect_identical(attr(tab, "dropped"), c(covariate = 1L, follow_up = 0L, event = 1L))
  expect_identical(sum(tab$n), 13L)
  expect_identical(sum(tab$events), 8L)
})

test_that(".lg_table() takes each level of an ordinal covariate as a group", {
  tab <- hvtiRtemplates:::.lg_table(c(1, 1, 2, 2, 2, 3, 3), c(0L, 1L, 0L, 1L, 1L, 1L, 1L), kind = "ordinal")
  expect_equal(tab$mean, 1:3)
  expect_identical(tab$n, c(2L, 3L, 2L))
  expect_equal(tab$link, c(0, log(2), NA))
})

test_that(".lg_table() stops on an event, follow-up or length it cannot use", {
  f <- lg_fixture()
  expect_error(hvtiRtemplates:::.lg_table(f$x, f$event + 1L), "^event must be coded 0 and 1")
  expect_error(hvtiRtemplates:::.lg_table(f$x, rep(c("yes", "no"), 6L)), "^event must be coded 0 and 1")
  expect_error(hvtiRtemplates:::.lg_table(f$x, f$event[-1L]), "^x and event must be the same length")
  expect_error(hvtiRtemplates:::.lg_table(f$x, f$event, link = "hazard"), "^link = \"hazard\" needs time")
  expect_error(hvtiRtemplates:::.lg_table(f$x, f$event, f$time[-1L], link = "hazard"), "^time must be numeric")
  expect_error(hvtiRtemplates:::.lg_table(f$x, f$event, replace(f$time, 2L, -1), link = "hazard"),
               "^time holds 1 negative value")
  # A logical event is 1 and 0.
  expect_identical(hvtiRtemplates:::.lg_table(f$x, f$event == 1L)$events, c(1L, 0L, 2L, 1L, 3L))
})
