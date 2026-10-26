# A small counting-process data set: patient 1 has three intervals and dies
# in the last, patient 2 two intervals and is censored, patient 3 one.
cp_rows <- function() {
  data.frame(id = c(1L, 1L, 1L, 2L, 2L, 3L), t0 = c(0, 1, 2, 0, 1, 0), t1 = c(1, 2, 3, 1, 2, 4),
             dead = c(0L, 0L, 1L, 0L, 0L, 0L), lab = c(5, 6, 7, 5, 5, 9), age = c(60, 60, 60, 70, 70, 50))
}
cp <- function(d, repair = character()) {
  hvtiRtemplates:::.cp_check(d, id = "id", start = "t0", stop = "t1", event = "dead",
                             predictors = c("lab", "age"), repair = repair)
}

test_that(".cp_check() passes clean rows through and counts them", {
  out <- cp(cp_rows()[c(6, 2, 1, 3, 5, 4), ])
  expect_identical(out$data$id, c(1L, 1L, 1L, 2L, 2L, 3L))
  expect_identical(out$data$t0, c(0, 1, 2, 0, 1, 0))
  expect_identical(names(out$data), c("id", "t0", "t1", "dead", "lab", "age"))
  expect_length(out$repaired, 0L)
  value <- function(m) out$counts$value[out$counts$measure == m]
  expect_identical(value("Patients"), "3")
  expect_identical(value("Intervals"), "6")
  expect_identical(value("Events"), "1")
  expect_identical(value("Gaps between intervals"), "0")
})

test_that(".cp_check() stops on an overlap unless REPAIR clips it", {
  d <- cp_rows()
  d$t0[2] <- 0.5                      # patient 1's second interval starts inside the first
  expect_error(cp(d), "1 overlapping interval.*REPAIR <- \"clip\"")
  out <- cp(d, "clip")
  expect_identical(out$data$t0[2], 1)
  expect_match(out$repaired[["clip"]], "1 overlapping interval clipped")
})

test_that("clip drops an interval it leaves empty, and refuses to drop an event", {
  d <- rbind(cp_rows(), data.frame(id = 2L, t0 = 1.2, t1 = 1.8, dead = 0L, lab = 5, age = 70))
  out <- cp(d, "clip")                # the extra interval lies inside patient 2's second
  expect_identical(nrow(out$data), 6L)
  expect_match(out$repaired[["clip"]], "1 interval left empty and dropped")
  d <- cp_rows()
  d$t0[3] <- 1                        # patient 1's event interval duplicates the one before it
  d$t1[3] <- 2
  expect_error(cp(d, "clip"), "would drop an interval that carries the event")
})

test_that(".cp_check() stops on a zero-length interval unless REPAIR clips it", {
  d <- cp_rows()
  d$t1[6] <- 0
  expect_error(cp(d), "1 interval of zero or negative length")
  expect_identical(nrow(cp(d, "clip")$data), 5L)
})

test_that(".cp_check() stops on an event before a patient's last interval, with no repair", {
  d <- cp_rows()
  d$dead[1] <- 1L
  expect_error(cp(d, c("clip", "drop_na")), "1 patient has an event before their last interval")
})

test_that(".cp_check() stops on an event not coded 0/1 and on a missing id, start, stop or event", {
  d <- cp_rows()
  d$dead[3] <- 2L
  expect_error(cp(d), "dead must be coded 0 and 1")
  d <- cp_rows()
  d$t1[4] <- NA
  expect_error(cp(d, c("clip", "drop_na")), "1 interval has no id, start, stop or event")
})

test_that(".cp_check() stops on a missing predictor unless REPAIR drops it", {
  d <- cp_rows()
  d$lab[4] <- NA
  expect_error(cp(d), "1 interval is missing a predictor.*REPAIR <- \"drop_na\"")
  out <- cp(d, "drop_na")
  expect_identical(nrow(out$data), 5L)
  expect_match(out$repaired[["drop_na"]], "1 interval missing a predictor dropped")
  d <- cp_rows()
  d$lab[3] <- NA                      # the event interval
  expect_error(cp(d, "drop_na"), "would drop an interval that carries the event")
  d <- cp_rows()
  d$lab <- NA_real_
  expect_error(cp(d, "drop_na"), "no values: lab")
})

test_that(".cp_check() counts gaps and refuses an unknown repair", {
  d <- cp_rows()
  d$t0[5] <- 1.5                      # patient 2 is not at risk from 1 to 1.5
  out <- cp(d)
  expect_identical(out$counts$value[out$counts$measure == "Gaps between intervals"], "1")
  expect_error(cp(cp_rows(), "fill"), "REPAIR may name only \"clip\" and \"drop_na\"")
})

test_that("a repair that changes nothing is not reported", {
  expect_length(cp(cp_rows(), c("clip", "drop_na"))$repaired, 0L)
})

test_that(".cp_repair_notice() marks a draft, and stops a final render", {
  expect_identical(hvtiRtemplates:::.cp_repair_notice(character()), "")
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "")
  marked <- NULL
  local_mocked_bindings(.run_mark_draft = function(reason) marked <<- reason, .package = "hvtiRtemplates")
  note <- hvtiRtemplates:::.cp_repair_notice(c(clip = "1 overlapping interval clipped"))
  expect_match(note, "callout-important")
  expect_match(note, "1 overlapping interval clipped")
  expect_match(marked, "rows repaired in the job")
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "1")
  expect_error(hvtiRtemplates:::.cp_repair_notice(c(clip = "1 overlapping interval clipped")),
               "HVTI_TEMPLATE_STRICT")
})
