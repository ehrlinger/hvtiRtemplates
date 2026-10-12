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

test_that(".lg_table() under the hazard sums follow-up only over patients whose event is known", {
  # Six patients in two groups of three by rank. The second patient has no event value and a follow-up of 100: if
  # that 100 entered the denominator, the first group's rate would be 1 / 103 and not 1 / 3.
  tab <- hvtiRtemplates:::.lg_table(1:6, c(1, NA, 0, 1, 0, 1), c(1, 100, 2, 3, 4, 5), groups = 2L, link = "hazard")
  expect_identical(tab$n, c(2L, 3L))
  expect_identical(tab$events, c(1L, 2L))
  expect_equal(tab$rate, c(1 / 3, 2 / 12))
  expect_equal(tab$link, log(c(1 / 3, 2 / 12)))
  expect_identical(attr(tab, "dropped")[["event"]], 1L)
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

test_that(".lg_scales() gives the six candidate scales of the group means", {
  m <- c(40, 50, 60, 80)
  s <- hvtiRtemplates:::.lg_scales(m, constant = 50)
  expect_named(s, c("raw", "log", "inverse", "inverse_squared", "squared", "exp"))
  expect_identical(nrow(s), 4L)
  expect_equal(s$raw, m)
  expect_equal(s$log, log(m))
  expect_equal(s$inverse, 50 / m)
  expect_equal(s$inverse_squared, (50 / m)^2)
  expect_equal(s$squared, (m / 50)^2)
  expect_equal(s$exp, exp(m / 50))
  expect_length(attr(s, "notes"), 0L)
  # The constant does not move the raw or log scales; the shift moves only the log.
  s2 <- hvtiRtemplates:::.lg_scales(m, constant = 100, shift = 1)
  expect_equal(s2$raw, m)
  expect_equal(s2$log, log(m + 1))
  expect_equal(s2$inverse, 100 / m)
  expect_equal(s2$squared, (m / 100)^2)
})

test_that("each scale's term is the formula an lm job's PREDICTORS can take, and it evaluates to the scale", {
  m <- c(40, 50, 60, 80)
  term <- hvtiRtemplates:::.lg_term
  expect_identical(term("age", "raw", 50), "age")
  expect_identical(term("age", "log", 50), "log(age)")
  expect_identical(term("age", "log", 50, shift = 1), "log(age + 1)")
  expect_identical(term("age", "log", 50, shift = -0.5), "log(age - 0.5)")
  expect_identical(term("age", "inverse", 50), "I(50 / age)")
  expect_identical(term("age", "inverse_squared", 50), "I((50 / age)^2)")
  expect_identical(term("age", "squared", 50), "I((age / 50)^2)")
  expect_identical(term("age", "exp", 50), "I(exp(age / 50))")
  # A constant is written as a number, never in exponent form, and a name that needs it is quoted.
  expect_identical(term("weight", "inverse", 0.0001), "I(0.0001 / weight)")
  expect_identical(term("bsa", "squared", 1.5), "I((bsa / 1.5)^2)")
  expect_identical(term("log age", "log", 50), "log(`log age`)")
  expect_error(term("age", "cubic", 50), "^scale must be one of raw, log, inverse")
  # Each term, evaluated on the covariate, is the scale: the same formula drawn in the figure
  # is the one that goes into the model. The strings evaluated are the ones built above.
  s <- hvtiRtemplates:::.lg_scales(m, constant = 50, shift = 1)
  for (id in names(s)) {
    got <- eval(parse(text = term("age", id, 50, shift = 1)), data.frame(age = m))
    expect_equal(got, s[[id]], info = id)
  }
  # And lm's own helpers accept them: reformulate() builds the model formula, and
  # .check_job_columns() finds the covariate inside each term.
  terms <- vapply(names(s), function(id) term("age", id, 50, shift = 1), "")
  d <- data.frame(age = m, outcome = c(0, 1, 0, 1))
  expect_s3_class(stats::reformulate(terms, response = "outcome"), "formula")
  expect_silent(hvtiRtemplates:::.check_job_columns(d, PREDICTORS = terms))
  expect_error(hvtiRtemplates:::.check_job_columns(d, PREDICTORS = term("weight", "inverse", 50)),
               "^PREDICTORS names a column this dataset does not have: weight")
})

test_that("a scale that cannot be computed is drawn empty, with a note, not left out", {
  # The log of a mean at or below the shift.
  s <- hvtiRtemplates:::.lg_scales(c(0, 1, 2), constant = 1)
  expect_identical(names(s), c("raw", "log", "inverse", "inverse_squared", "squared", "exp"))
  expect_true(all(is.na(s$log)))
  expect_match(attr(s, "notes")[["log"]], "^A group mean plus the shift is not positive [(]the smallest is 0[)]")
  # An inverse through zero: the scale is empty for the whole covariate, not just the group at 0.
  expect_true(all(is.na(s$inverse)) && all(is.na(s$inverse_squared)))
  expect_match(attr(s, "notes")[["inverse"]], "^A group mean is 0, so the constant over the mean is undefined")
  expect_match(attr(s, "notes")[["inverse_squared"]], "^A group mean is 0")
  expect_equal(s$raw, c(0, 1, 2))
  expect_equal(s$squared, c(0, 1, 4))
  expect_named(attr(s, "notes"), c("log", "inverse", "inverse_squared"))
  # The shift makes the log safe.
  safe <- hvtiRtemplates:::.lg_scales(c(0, 1, 2), constant = 1, shift = 1)
  expect_equal(safe$log, log(c(1, 2, 3)))
  expect_false("log" %in% names(attr(safe, "notes")))
  # An exponential that overflows.
  big <- hvtiRtemplates:::.lg_scales(c(1, 1000), constant = 1)
  expect_true(all(is.na(big$exp)))
  expect_match(attr(big, "notes")[["exp"]], "^The exponential of the mean over the constant overflows")
})

test_that("with no constant the four constant-based scales are empty and say to set one; raw and log remain", {
  s <- hvtiRtemplates:::.lg_scales(c(0.2, 0.5, 0.8), constant = NA_real_)
  expect_equal(s$raw, c(0.2, 0.5, 0.8))
  expect_equal(s$log, log(c(0.2, 0.5, 0.8)))
  for (id in c("inverse", "inverse_squared", "squared", "exp")) {
    expect_true(all(is.na(s[[id]])), info = id)
    expect_match(attr(s, "notes")[[id]], "set constant for this covariate in VARIABLES", info = id)
  }
  expect_named(attr(s, "notes"), c("inverse", "inverse_squared", "squared", "exp"))
  # The log's own note still comes first when the shift is needed too.
  both <- hvtiRtemplates:::.lg_scales(c(0, 0.5, 1), constant = NA_real_)
  expect_named(attr(both, "notes"), c("log", "inverse", "inverse_squared", "squared", "exp"))
  # A term cannot be written without a constant, except the two that use none.
  expect_identical(hvtiRtemplates:::.lg_term("flag", "raw", NA_real_), "flag")
  expect_identical(hvtiRtemplates:::.lg_term("flag", "log", NA_real_, shift = 1), "log(flag + 1)")
  expect_error(hvtiRtemplates:::.lg_term("flag", "inverse", NA_real_), "^The scale inverse needs a constant")
})

test_that(".lg_scales() stops on a constant, shift or mean it cannot use", {
  expect_error(hvtiRtemplates:::.lg_scales(c(1, 2), constant = 0), "^constant must be one finite number other than 0")
  expect_error(hvtiRtemplates:::.lg_scales(c(1, 2), constant = c(1, 2)), "^constant must be one finite number")
  expect_error(hvtiRtemplates:::.lg_scales(c(1, 2), constant = Inf), "^constant must be one finite number")
  expect_error(hvtiRtemplates:::.lg_scales(c(1, 2), constant = 1, shift = NA_real_), "^shift must be one finite number")
  expect_error(hvtiRtemplates:::.lg_scales(c("a", "b"), constant = 1), "^mean must be numeric")
})

test_that("the default constant is the covariate's median to one significant figure", {
  # The SAS jobs typed it by hand: 50 for an age, 80 for a weight.
  const <- hvtiRtemplates:::.lg_constant
  expect_identical(const(c(41, 52, 58, 61, 70)), 60)
  expect_identical(const(c(44, 47, 52, 55, 90)), 50)
  expect_identical(const(c(1, 2, 2, 2, 4, NA)), 2)
  expect_identical(const(c(0.031, 0.04, 0.041, 0.9)), 0.04)
  expect_identical(const(c(1200, 1300, 1900)), 1000)
  expect_error(const(c(NA_real_, NA_real_), "age"), "^`age` has no value")
  # A median that rounds to 0 gives no default, and does not stop the job: the constant-based scales are not
  # computable for that covariate until the author sets one.
  expect_identical(const(c(0, 0, 0, 5), "los"), NA_real_)
  expect_identical(const(c(0, 1, 0, 1, 0)), NA_real_)
})

test_that(".lg_rsq() is the R-squared of a straight line fitted with the group sizes as weights", {
  rsq <- hvtiRtemplates:::.lg_rsq
  # Exactly linear: 1, whatever the weights.
  expect_equal(rsq(c(1, 2, 3, 4), c(5, 7, 9, 11), c(10, 1, 1, 30)), 1)
  # Not linear: the weighted squared correlation, worked from its definition.
  x <- c(1, 2, 3, 4)
  y <- c(1, 2, 3, 10)
  w <- c(1, 1, 1, 100)
  mx <- sum(w * x) / sum(w)
  my <- sum(w * y) / sum(w)
  by_hand <- sum(w * (x - mx) * (y - my))^2 / (sum(w * (x - mx)^2) * sum(w * (y - my)^2))
  expect_equal(rsq(x, y, w), by_hand)
  # The weights matter: the unweighted fit of the same points is a different number.
  expect_gt(abs(rsq(x, y, rep(1, 4)) - rsq(x, y, w)), 0.01)
  # A group with no link value is left out of the fit.
  expect_equal(rsq(c(1, 2, 3, 4, 5), c(5, 7, NA, 11, 13), c(1, 1, 1, 1, 1)), 1)
  # Fewer than three points, or no spread, is not a fit worth reporting.
  expect_identical(rsq(c(1, 2), c(1, 2), c(1, 1)), NA_real_)
  expect_identical(rsq(c(1, 2, 3), c(4, NA, 6), c(1, 1, 1)), NA_real_)
  expect_identical(rsq(c(2, 2, 2), c(1, 2, 3), c(1, 1, 1)), NA_real_)
  expect_identical(rsq(c(1, 2, 3), c(4, 4, 4), c(1, 1, 1)), NA_real_)
})

# The text each panel of a figure carries, by panel.
lg_panel_text <- function(p) {
  layer <- which(vapply(p$layers, function(l) inherits(l$geom, "GeomText"), logical(1L)))
  stats::setNames(ggplot2::layer_data(p, layer)$label, ggplot2::layer_data(p, layer)$PANEL)
}

test_that(".lg_plot() draws one panel per scale and reports 1 for points exactly linear on one", {
  skip_if_not_installed("ggplot2")
  means <- c(1, 2, 4, 8, 16)
  tab <- data.frame(group = 1:5, mean = means, n = c(20L, 30L, 25L, 18L, 22L), link = 2 + 3 * log(means))
  scales <- hvtiRtemplates:::.lg_scales(means, constant = 8)
  p <- hvtiRtemplates:::.lg_plot(tab, scales, link = "hazard", title = "Age")
  expect_s3_class(p, "ggplot")
  built <- ggplot2::ggplot_build(p)
  expect_identical(nrow(built$layout$layout), 6L)
  expect_identical(levels(p$data$panel), c("Raw", "Log", "Inverse", "Inverse squared", "Squared", "Exponential"))
  text <- lg_panel_text(p)
  # Log is panel 2: the link is 2 + 3 log(mean), a straight line on that scale.
  expect_identical(unname(text[["2"]]), "R-squared = 1.00")
  expect_false(identical(unname(text[["1"]]), "R-squared = 1.00"))
  expect_equal(hvtiRtemplates:::.lg_rsq(scales$log, tab$link, tab$n), 1)
  expect_match(ggplot2::get_labs(p)$y, "events per unit of follow-up")
})

test_that(".lg_plot() draws a scale that cannot be computed as an empty panel that says so", {
  skip_if_not_installed("ggplot2")
  means <- c(0, 1, 2, 3)
  tab <- data.frame(group = 1:4, mean = means, n = c(10L, 10L, 10L, 10L), link = c(-1, -0.5, 0, 0.4))
  scales <- hvtiRtemplates:::.lg_scales(means, constant = 1)
  p <- hvtiRtemplates:::.lg_plot(tab, scales, link = "logit")
  text <- lg_panel_text(p)
  # Log (2), Inverse (3) and Inverse squared (4) are undefined at a mean of 0.
  expect_identical(unname(text[c("2", "3", "4")]), rep("Not computable", 3L))
  expect_match(text[["1"]], "^R-squared = ")
  # The empty panels are still drawn, so the six stay in their places, and the figure renders.
  expect_identical(nrow(ggplot2::ggplot_build(p)$layout$layout), 6L)
  png <- withr::local_tempfile(fileext = ".png")
  hvtiRtemplates:::.save_figure(p, png, width = 9, height = 6)
  expect_true(file.exists(png) && file.exists(sub("[.]png$", ".pdf", png)))
})

test_that(".lg_plot() leaves a blank link value as a gap and says when no R-squared is available", {
  skip_if_not_installed("ggplot2")
  means <- c(10, 20, 30)
  tab <- data.frame(group = 1:3, mean = means, n = c(5L, 5L, 5L), link = c(-1, NA, 1))
  p <- hvtiRtemplates:::.lg_plot(tab, hvtiRtemplates:::.lg_scales(means, constant = 20), link = "logit")
  expect_true(all(startsWith(lg_panel_text(p), "R-squared not available")))
  expect_error(hvtiRtemplates:::.lg_plot(tab[1:2, ], hvtiRtemplates:::.lg_scales(means, constant = 20)),
               "^table and scales must have one row for each group")
})

# Each row of a five-patient fixture repeated six times, so that no rank group is smaller than the 5 patients
# .lg_variables() asks for. The values, and so the medians, are those of the five.
lg_repeat <- function(d, times = 6L) d[rep(seq_len(nrow(d)), each = times), , drop = FALSE]

test_that(".lg_variables() fills every default from the data and keeps what the author gave", {
  d <- lg_repeat(data.frame(age = c(41, 52, 58, 61, 70), nyha = c(1, 2, 2, 3, 4), wt = c(70, 80, 86, 90, 110)))
  v <- hvtiRtemplates:::.lg_variables(data.frame(name = c("age", "nyha")), d)
  expect_named(v, c("name", "kind", "groups", "constant", "shift", "label", "chosen"))
  expect_identical(v$name, c("age", "nyha"))
  expect_identical(v$kind, c("continuous", "continuous"))
  expect_identical(v$groups, c(5L, 5L))
  # The median to one significant figure: 58 gives 60, and a median of 2 stays 2.
  expect_identical(v$constant, c(60, 2))
  expect_identical(v$shift, c(0, 0))
  expect_identical(v$label, c("age", "nyha"))
  expect_identical(v$chosen, c(NA_character_, NA_character_))
  # What the author gives wins, row by row, and a blank in a column takes that row's default.
  given <- data.frame(
    name = c("age", "nyha", "wt"), kind = c("continuous", "ordinal", NA), groups = c(4, NA, 6),
    constant = c(50, NA, NA), shift = c(NA, 1, 0), label = c("Age (years)", NA, ""), chosen = c("log", "", NA)
  )
  v <- hvtiRtemplates:::.lg_variables(given, d)
  expect_identical(v$kind, c("continuous", "ordinal", "continuous"))
  expect_identical(v$groups, c(4L, 5L, 6L))
  expect_identical(v$constant, c(50, 2, 90))
  expect_identical(v$shift, c(0, 1, 0))
  expect_identical(v$label, c("Age (years)", "nyha", "wt"))
  expect_identical(v$chosen, c("log", NA, NA))
  # A logical NA, as a one-row data frame writes it, is no choice.
  expect_identical(hvtiRtemplates:::.lg_variables(data.frame(name = "age", chosen = NA), d)$chosen, NA_character_)
})

test_that(".lg_variables() stops on a table, column, name or value it cannot use, naming VARIABLES", {
  d <- lg_repeat(data.frame(ccfid = 1:5, age = c(41, 52, 58, 61, 70), sex = c("f", "m", "f", "m", "f"),
                            zero = c(0, 0, 0, 0, 1)))
  one <- function(...) hvtiRtemplates:::.lg_variables(data.frame(name = "age", ...), d)
  expect_error(hvtiRtemplates:::.lg_variables("age", d), "^VARIABLES must be a data frame with one row for each covariate")
  expect_error(hvtiRtemplates:::.lg_variables(data.frame(name = character()), d), "^VARIABLES must be a data frame")
  expect_error(hvtiRtemplates:::.lg_variables(data.frame(kind = "ordinal"), d), "^VARIABLES needs a `name` column")
  expect_error(one(color = "red"), "^VARIABLES has a column the job does not use: color. The columns are name, kind")
  expect_error(hvtiRtemplates:::.lg_variables(data.frame(name = c("age", "age")), d),
               "^VARIABLES names a covariate more than once: age")
  expect_error(hvtiRtemplates:::.lg_variables(data.frame(name = c("age", NA)), d), "^VARIABLES has a covariate with no name")
  expect_error(hvtiRtemplates:::.lg_variables(data.frame(name = c("age", "bmi", "bsa")), d),
               "^VARIABLES names columns this dataset does not have: bmi, bsa. Change VARIABLES in edit-study-choices[.]")
  expect_error(hvtiRtemplates:::.lg_variables(data.frame(name = "sex"), d), "^VARIABLES names a column that is not numeric: sex")
  expect_error(hvtiRtemplates:::.lg_variables(data.frame(name = c("age", "ccfid")), d, exclude = "ccfid"),
               "^VARIABLES names the patient identifier [(]`ccfid`[)]")
  expect_error(one(kind = "binary"), "^VARIABLES\\$kind must be \"continuous\" or \"ordinal\"")
  expect_error(one(groups = 1), "^VARIABLES\\$groups must be a whole number of at least 2")
  expect_error(one(groups = 2.5), "^VARIABLES\\$groups must be a whole number of at least 2")
  expect_error(one(groups = "five"), "^VARIABLES\\$groups must be a whole number")
  expect_error(one(constant = 0), "^VARIABLES\\$constant must be a finite number other than 0")
  expect_error(one(constant = Inf), "^VARIABLES\\$constant must be a finite number other than 0")
  expect_error(one(shift = Inf), "^VARIABLES\\$shift must be a finite number")
  expect_error(one(chosen = "cubic"), "^VARIABLES\\$chosen must be NA or one of raw, log, inverse, inverse_squared, squared, exp")
  # A covariate whose median rounds to 0 has no default constant: it is left NA, and the job goes on.
  expect_identical(hvtiRtemplates:::.lg_variables(data.frame(name = "zero"), d)$constant, NA_real_)
  expect_silent(hvtiRtemplates:::.lg_variables(data.frame(name = "zero", constant = 1), d))
})

test_that(".lg_variables() stops on an ordinal covariate with more than 20 levels, naming it and what to do", {
  many <- data.frame(many = rep(1:21, each = 5L))
  expect_error(hvtiRtemplates:::.lg_variables(data.frame(name = "many", kind = "ordinal"), many),
               paste0("^VARIABLES: `many` is ordinal with 21 levels, more than the 20 a group each can take. ",
                      "Treat it as continuous or recode it"))
  # 20 levels is the most that is allowed, and the same covariate as continuous is not an ordinal.
  enough <- data.frame(enough = rep(1:20, each = 5L))
  expect_silent(hvtiRtemplates:::.lg_variables(data.frame(name = "enough", kind = "ordinal"), enough))
  expect_silent(hvtiRtemplates:::.lg_variables(data.frame(name = "many", kind = "continuous"), many))
  # Missing values are not levels.
  expect_silent(hvtiRtemplates:::.lg_variables(data.frame(name = "enough", kind = "ordinal"),
                                               data.frame(enough = c(rep(1:20, each = 5L), NA, NA))))
})

test_that(".lg_variables() stops when a group has fewer than 5 patients, naming the covariate and never a value", {
  # Rank groups of 12 patients: five groups of 2 or 3.
  d <- data.frame(small = c(101:112), ok = rep(c(1, 2), each = 6L))
  expect_error(hvtiRtemplates:::.lg_variables(data.frame(name = "small"), d),
               "^VARIABLES: `small` has a group of fewer than 5 patients [(]the smallest has 2[)]. Lower groups for it in VARIABLES")
  # The message never carries the covariate's values.
  msg <- tryCatch(hvtiRtemplates:::.lg_variables(data.frame(name = "small"), d), error = conditionMessage)
  expect_false(grepl("10[1-9]|11[0-2]", msg))
  # Fewer groups makes each larger: two groups of six are enough.
  expect_silent(hvtiRtemplates:::.lg_variables(data.frame(name = "small", groups = 2), d))
  expect_silent(hvtiRtemplates:::.lg_variables(data.frame(name = "ok", groups = 2), d))
  # An ordinal level held by fewer than 5 patients says to combine levels instead.
  o <- data.frame(level = c(rep(1, 8), rep(2, 7), rep(3, 2)))
  expect_error(hvtiRtemplates:::.lg_variables(data.frame(name = "level", kind = "ordinal"), o),
               "^VARIABLES: `level` has a group of fewer than 5 patients [(]the smallest has 2[)]. Combine levels of it")
  # Exactly 5 is enough.
  expect_silent(hvtiRtemplates:::.lg_variables(data.frame(name = "level", kind = "ordinal"),
                                               data.frame(level = c(rep(1, 8), rep(2, 7), rep(3, 5)))))
  # Patients with no covariate value are in no group, and so cannot make one small or large.
  expect_error(hvtiRtemplates:::.lg_variables(data.frame(name = "level", kind = "ordinal"),
                                              data.frame(level = c(rep(1, 8), rep(2, 7), rep(3, 2), rep(NA, 30)))),
               "smallest has 2")
  # The groups counted are those the table will form: patients with no event value, or under the hazard no
  # follow-up, are not in n, so a group they empty out is small.
  e <- rep(c(1, 0), 10)
  expect_silent(hvtiRtemplates:::.lg_variables(data.frame(name = "x", groups = 2), data.frame(x = 1:20), event = e))
  expect_error(hvtiRtemplates:::.lg_variables(data.frame(name = "x", groups = 2), data.frame(x = 1:20),
                                              event = replace(e, 1:7, NA)), "smallest has 3")
  # A patient with no follow-up is dropped before the ranking, so the groups re-form on those left: 13 patients
  # make groups of 6 and 7, and 4 make two groups of 2.
  expect_silent(hvtiRtemplates:::.lg_variables(data.frame(name = "x", groups = 2), data.frame(x = 1:20), event = e,
                                               time = replace(rep(1, 20), 11:17, NA)))
  expect_error(hvtiRtemplates:::.lg_variables(data.frame(name = "x", groups = 2), data.frame(x = 1:20), event = e,
                                              time = c(1, 1, 1, 1, rep(NA, 16L))), "smallest has 2")
})

test_that(".lg_interval() drops patients who ended before the start and censors the rest at the end", {
  # Eight patients, the window c(0.25, 5), worked by hand:
  #   id   follow-up  event  what happens
  #    1     0.10       1     ended before the start: left out
  #    2     0.25       1     exactly at the start: kept, time at risk 0.25 - 0.25 = 0
  #    3     1.00       0     kept, time at risk 0.75
  #    4     5.00       1     exactly at the end: kept with its event, time at risk 4.75
  #    5     5.50       1     past the end: censored at 5, the event no longer counts, time at risk 4.75
  #    6      NA        1     no follow-up: left out
  #    7     3.00       0     kept, time at risk 2.75
  #    8     8.00       1     past the end: censored, event not counted, time at risk 4.75
  d <- data.frame(id = 1:8, t = c(0.1, 0.25, 1, 5, 5.5, NA, 3, 8), dead = c(1L, 1L, 0L, 1L, 1L, 1L, 0L, 1L))
  got <- hvtiRtemplates:::.lg_interval(d, "dead", "t", c(0.25, 5))
  expect_identical(got$data$id, c(2L, 3L, 4L, 5L, 7L, 8L))
  expect_identical(got$event, c(1L, 0L, 1L, 0L, 0L, 0L))
  expect_equal(got$time, c(0, 0.75, 4.75, 4.75, 2.75, 4.75))
  expect_identical(got$counts$count, c("Patients read", "Left out: follow-up before the start", "Left out: follow-up missing",
                                       "Patients kept", "Censored at the end", "Events after the end, no longer counted"))
  expect_identical(got$counts$patients, c(8L, 1L, 1L, 6L, 2L, 2L))
  # The columns of the data are not changed.
  expect_identical(got$data$dead, c(1L, 0L, 1L, 1L, 0L, 1L))
  # An event of NA past the end is censored too, as `dead=0` sets it in SAS.
  na_event <- hvtiRtemplates:::.lg_interval(transform(d, dead = replace(dead, 8L, NA)), "dead", "t", c(0.25, 5))
  expect_identical(na_event$event[[6L]], 0L)
  # No interval keeps everyone and has nothing to report; the event and follow-up come back as they are.
  none <- hvtiRtemplates:::.lg_interval(d, "dead", "t", NULL)
  expect_identical(none$data, d)
  expect_null(none$counts)
  expect_identical(none$event, d$dead)
  expect_identical(none$time, d$t)
  expect_null(hvtiRtemplates:::.lg_interval(d, "dead", NULL, NULL)$time)
  # A window that starts at 0, the SAS early phase, leaves nobody out for being early.
  early <- hvtiRtemplates:::.lg_interval(d, "dead", "t", c(0, 1))
  expect_identical(early$counts$patients[c(2L, 4L, 5L)], c(0L, 7L, 4L))
  expect_equal(early$time, c(0.1, 0.25, 1, 1, 1, 1, 1))
  expect_error(hvtiRtemplates:::.lg_interval(d, "dead", "t", c(10, 20)), "^INTERVAL keeps no patient")
  for (bad in list(5, c(5, 1), c(1, NA), c(1, 5, 9), "a", c(2, 2))) {
    expect_error(hvtiRtemplates:::.lg_interval(d, "dead", "t", bad), "^INTERVAL must be NULL or c[(]start, end[)]")
  }
  expect_error(hvtiRtemplates:::.lg_interval(d, "dead", "later", c(1, 2)), "^TIME names a column this dataset does not have: later")
  expect_error(hvtiRtemplates:::.lg_interval(d, "dead", NULL, c(1, 2)), "^INTERVAL needs TIME")
  expect_error(hvtiRtemplates:::.lg_interval(d, "died", "t", NULL), "^event must be coded 0 and 1")
})

test_that("a constant hazard censored past the window is recovered, not overstated", {
  # A true constant hazard of 0.1 a year, every patient followed to 10 years at most. The window c(0, 5) censors at
  # 5; leaving out the patients followed past 5, which keeps only the early events over their short times, would
  # give about 0.44.
  withr::local_seed(2026)
  n <- 20000L
  t_event <- stats::rexp(n, 0.1)
  d <- data.frame(x = stats::rnorm(n), follow = pmin(t_event, 10), dead = as.integer(t_event <= 10))
  got <- hvtiRtemplates:::.lg_interval(d, "dead", "follow", c(0, 5))
  tab <- hvtiRtemplates:::.lg_table(got$data$x, got$event, got$time, groups = 5L, link = "hazard")
  expect_lt(max(abs(tab$rate - 0.1)), 0.01)
  expect_lt(abs(sum(got$event) / sum(got$time) - 0.1), 0.005)
})

lg_chosen_fixture <- function() {
  variables <- data.frame(
    name = c("age", "wt", "nyha", "los"), kind = "continuous", groups = 5L, constant = c(50, 80, 2, 1),
    shift = c(0, 1, 0, 0), label = c("age", "wt", "nyha", "los"), chosen = c("log", "inverse", "raw", NA)
  )
  scales <- list(
    age = hvtiRtemplates:::.lg_scales(c(40, 50, 60), 50),
    wt = hvtiRtemplates:::.lg_scales(c(60, 80, 100), 80, 1),
    nyha = hvtiRtemplates:::.lg_scales(c(1, 2, 3), 2),
    los = hvtiRtemplates:::.lg_scales(c(0, 1, 2), 1)
  )
  # The patients behind the means: every value is on the domain of every scale chosen above.
  d <- data.frame(age = c(35, 45, 55, 65, NA), wt = c(55, 70, 90, 110, 120), nyha = c(1, 2, 2, 3, 3), los = c(0, 0, 1, 2, 3))
  list(variables = variables, scales = scales, d = d)
}

test_that(".lg_choices() gives each chosen scale as the term, constant and shift an lm job takes", {
  f <- lg_chosen_fixture()
  got <- hvtiRtemplates:::.lg_choices(f$variables[1:3, ], f$scales, f$d)
  expect_named(got$table, c("variable", "chosen", "term", "constant", "shift"))
  expect_identical(got$table$variable, c("age", "wt", "nyha"))
  expect_identical(got$table$chosen, c("log", "inverse", "raw"))
  expect_identical(got$table$term, c("log(age)", "I(80 / wt)", "nyha"))
  expect_identical(got$table$constant, c(50, 80, 2))
  expect_identical(got$table$shift, c(0, 1, 0))
  expect_length(got$problems, 0L)
})

test_that("a covariate with no choice, or a choice that cannot be computed, is a problem and not a row", {
  f <- lg_chosen_fixture()
  # los has no choice. Its log cannot be computed (a group mean is 0), so choosing it is a problem too.
  got <- hvtiRtemplates:::.lg_choices(f$variables, f$scales, f$d)
  expect_identical(got$table$variable, c("age", "wt", "nyha"))
  expect_identical(unname(got$problems), "no scale chosen yet")
  expect_named(got$problems, "los")
  f$variables$chosen[[4L]] <- "log"
  got <- hvtiRtemplates:::.lg_choices(f$variables, f$scales, f$d)
  expect_identical(got$table$variable, c("age", "wt", "nyha"))
  expect_named(got$problems, "los")
  expect_match(got$problems[["los"]], "^the chosen scale, log, cannot be computed: A group mean plus the shift is not positive")
  # Nothing chosen at all is an empty table with the same columns, and a problem for each.
  none <- hvtiRtemplates:::.lg_choices(transform(f$variables, chosen = NA_character_), f$scales, f$d)
  expect_identical(nrow(none$table), 0L)
  expect_named(none$table, c("variable", "chosen", "term", "constant", "shift"))
  expect_named(none$problems, c("age", "wt", "nyha", "los"))
})

test_that("a chosen scale that is not a number for some patient is a problem, even when every group mean is fine", {
  # Every group mean is above 0, so the scales of the means are all computable; two patients are 0.
  d <- data.frame(x = c(0, 0, 4, 5, 6, 7, 8, 9, NA))
  variables <- data.frame(name = "x", kind = "continuous", groups = 2L, constant = 5, shift = 0, label = "x", chosen = "log")
  scales <- list(x = hvtiRtemplates:::.lg_scales(c(2.5, 7), 5))
  expect_length(attr(scales$x, "notes"), 0L)
  got <- hvtiRtemplates:::.lg_choices(variables, scales, d)
  expect_identical(nrow(got$table), 0L)
  expect_named(got$problems, "x")
  expect_identical(got$problems[["x"]], paste0("the chosen scale, log, is not a number for 2 patients: ",
                                               "the covariate plus the shift is not above 0 for them. ",
                                               "Set shift for this covariate in VARIABLES, or choose another scale."))
  # The count of patients, never a value.
  expect_false(grepl("[0-9]+[.][0-9]", got$problems[["x"]]))
  # A shift that clears the zeros makes it computable.
  variables$shift <- 1
  scales <- list(x = hvtiRtemplates:::.lg_scales(c(2.5, 7), 5, 1))
  expect_identical(hvtiRtemplates:::.lg_choices(variables, scales, d)$table$term, "log(x + 1)")
  # The same zeros break the inverse, and one patient is said in the singular.
  variables$chosen <- "inverse"
  variables$shift <- 0
  one <- hvtiRtemplates:::.lg_choices(variables, scales, data.frame(x = c(0, 4, 5, 6, 7, 8)))
  expect_match(one$problems[["x"]], "^the chosen scale, inverse, is not a number for 1 patient: the constant over the covariate")
  # A raw scale is never impossible, and a patient with no value is not counted.
  variables$chosen <- "raw"
  expect_identical(hvtiRtemplates:::.lg_choices(variables, scales, d)$table$term, "x")
  # The exponential that overflows for a patient, though not for any mean.
  variables$chosen <- "exp"
  variables$constant <- 1
  big <- hvtiRtemplates:::.lg_choices(variables, list(x = hvtiRtemplates:::.lg_scales(c(2.5, 7), 1)),
                                      data.frame(x = c(1, 2, 1000)))
  expect_match(big$problems[["x"]], "^the chosen scale, exp, is not a number for 1 patient: the exponential overflows")
})

test_that("a covariate with no constant cannot be given a constant-based scale, and can be given raw or log", {
  d <- data.frame(flag = c(0, 0, 0, 1, 1, 0, 1, 0))
  variables <- data.frame(name = "flag", kind = "continuous", groups = 2L, constant = NA_real_, shift = 1, label = "flag",
                          chosen = "inverse")
  scales <- list(flag = hvtiRtemplates:::.lg_scales(c(0.1, 0.8), NA_real_, 1))
  got <- hvtiRtemplates:::.lg_choices(variables, scales, d)
  expect_match(got$problems[["flag"]],
               "^the chosen scale, inverse, cannot be computed: .*set constant for this covariate in VARIABLES")
  variables$chosen <- "log"
  expect_identical(hvtiRtemplates:::.lg_choices(variables, scales, d)$table$term, "log(flag + 1)")
  variables$chosen <- "raw"
  got <- hvtiRtemplates:::.lg_choices(variables, scales, d)
  expect_identical(got$table$term, "flag")
  expect_true(is.na(got$table$constant))
})

test_that(".lg_predictors() writes the PREDICTORS line to copy into an lm job, and it reads back as the terms", {
  line <- hvtiRtemplates:::.lg_predictors(c("log(age)", "I(80 / wt)", "nyha"))
  expect_identical(line, "PREDICTORS <- c(\"log(age)\", \"I(80 / wt)\", \"nyha\")")
  # The parse() calls read back strings this test built, to show they are valid R and name what was given.
  expect_identical(eval(parse(text = line)), c("log(age)", "I(80 / wt)", "nyha"))
  # A long one goes a term to a line, and still reads back.
  terms <- paste0("I(exp(covariate_number_", 1:6, " / 50))")
  long <- hvtiRtemplates:::.lg_predictors(terms)
  expect_match(long, "^PREDICTORS <- c[(]\n  \"I[(]exp[(]covariate_number_1 / 50[)][)]\",\n")
  expect_match(long, "\n[)]$")
  expect_identical(eval(parse(text = long)), terms)
  expect_identical(hvtiRtemplates:::.lg_predictors(character()), "No scale is chosen yet, so there is no PREDICTORS line.")
})
