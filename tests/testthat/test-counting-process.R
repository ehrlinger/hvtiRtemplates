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

test_that("a tie on start is settled by stop, whatever order the rows arrive in", {
  # Patient 1's second and third rows both start at 1, and the event row is the shorter. It sorts second, so both
  # input orders end in the "event before their last interval" error; the assertion is that they end in the same one.
  d <- cp_rows()
  d$t0[3] <- 1
  d$t1[2] <- 3
  d$t1[3] <- 2                        # rows 2 and 3 tie on start, and the event row is the shorter
  forward <- tryCatch(cp(d, "clip"), error = conditionMessage)
  backward <- tryCatch(cp(d[rev(seq_len(nrow(d))), ], "clip"), error = conditionMessage)
  expect_identical(forward, backward)
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

test_that("clip leaves no overlap behind when short intervals nest inside a long one", {
  d <- data.frame(id = c(1L, 1L, 1L, 2L), t0 = c(0, 1, 3, 0), t1 = c(10, 2, 4, 5),
                  dead = c(0L, 0L, 0L, 0L), lab = c(5, 5, 5, 5), age = c(60, 60, 60, 50))
  expect_error(cp(d), "2 overlapping intervals")
  out <- cp(d, "clip")
  expect_identical(out$data$t0[out$data$id == 1L], 0)
  expect_identical(out$data$t1[out$data$id == 1L], 10)
  expect_identical(out$repaired[["clip"]], "2 intervals left empty and dropped")
  furthest <- ave(out$data$t1, out$data$id, FUN = cummax)
  earlier <- ifelse(duplicated(out$data$id), c(-Inf, furthest[-nrow(out$data)]), -Inf)
  expect_false(any(out$data$t0 < earlier))
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

test_that(".cp_check() stops on a start or stop that is not numeric", {
  d <- cp_rows()
  d$t0 <- as.character(d$t0)
  expect_error(cp(d), "t0 must be numeric")
  d <- cp_rows()
  d$t1 <- as.character(d$t1)
  expect_error(cp(d), "t1 must be numeric.*sort as text")
  d <- cp_rows()
  d$t1 <- as.Date("2026-01-01") + d$t1
  msg <- tryCatch(cp(d), error = conditionMessage)
  expect_match(msg, "t1 must be numeric; it is Date\\.$")
})

test_that("a message names a ccfid-style id but never an MRN", {
  d <- cp_rows()
  d$t0[2] <- 0.5
  expect_error(cp(d), "1 overlapping interval \\(1\\)")
  for (name in c("mrn", "MRN", "emrn")) {
    m <- cp_rows()
    names(m)[names(m) == "id"] <- name
    m[[name]] <- m[[name]] + 7300000L
    m$t0[2] <- 0.5
    msg <- tryCatch(hvtiRtemplates:::.cp_check(m, id = name, start = "t0", stop = "t1", event = "dead",
                                               predictors = c("lab", "age")), error = conditionMessage)
    expect_match(msg, "1 overlapping interval")
    expect_false(grepl("73000", msg, fixed = TRUE), info = name)
    expect_match(msg, "row")
    # The other messages that name patients hold to it too.
    m <- cp_rows()
    names(m)[names(m) == "id"] <- name
    m[[name]] <- m[[name]] + 7300000L
    m$dead[1] <- 1L
    msg <- tryCatch(hvtiRtemplates:::.cp_check(m, id = name, start = "t0", stop = "t1", event = "dead",
                                               predictors = c("lab", "age")), error = conditionMessage)
    expect_match(msg, "an event before their last interval")
    expect_false(grepl("73000", msg, fixed = TRUE), info = name)
  }
})

test_that(".cp_check() reads an integer64 id by value, as Parquet hands one over", {
  skip_if_not_installed("bit64")
  ids <- bit64::as.integer64(9100000000000 + c(1, 1, 1, 2, 2, 3))
  d <- cp_rows()
  d$id <- ids
  # Clean rows pass: every patient's last interval is found, not the first.
  out <- cp(d)
  expect_identical(out$counts$value[out$counts$measure == "Patients"], "3")
  expect_s3_class(out$data$id, "integer64")
  # An event on a first row with later rows stops, and names the id with its digits.
  early <- d
  early$dead[1] <- 1L
  expect_error(cp(early), "1 patient has an event before their last interval \\(9100000000001\\)")
  # The same event on the last row of its patient passes.
  late <- d
  late$dead[4:5] <- c(0L, 1L)
  expect_length(cp(late)$repaired, 0L)
  # An overlap names the id too, rows come back in patient order, and a patient's rows are not mixed.
  over <- d
  over$t0[5] <- 0.5
  expect_error(cp(over), "1 overlapping interval \\(9100000000002\\)")
  shuffled <- cp(d[c(6, 3, 5, 1, 4, 2), ])
  expect_identical(as.character(shuffled$data$id), as.character(ids))
})

test_that("an MRN message points at the row's place in the sorted data, not in the data left after a repair", {
  # Patient 100's middle interval nests inside the first and clip drops it, which would move every later row up one.
  d <- data.frame(mrn = c(100, 100, 100, 200, 200), t0 = c(0, 1, 2, 0, 1), t1 = c(2, 1.5, 3, 1, 2),
                  dead = c(0L, 0L, 0L, 1L, 0L), lab = 5)
  msg <- tryCatch(hvtiRtemplates:::.cp_check(d, id = "mrn", start = "t0", stop = "t1", event = "dead",
                                             predictors = "lab", repair = "clip"), error = conditionMessage)
  expect_match(msg, "an event before their last interval \\(row 4 of the rows")
  expect_false(grepl("100|200", msg))
  # The positions are internal: the rows come back without the column that carried them.
  d$dead <- 0L
  out <- hvtiRtemplates:::.cp_check(d, id = "mrn", start = "t0", stop = "t1", event = "dead",
                                    predictors = "lab", repair = "clip")
  expect_identical(names(out$data), c("mrn", "t0", "t1", "dead", "lab"))
})
