# Synthetic: identifiers are 1 to 4, echo dates are day numbers. No patient's
# records tie on distance to dt_surg, so "nearest" has one answer.
cohort <- data.frame(ccfid = 1:3, age = c(50, 60, 70), dt_surg = c(100, 100, 100))
echo <- data.frame(
  ccfid = c(1L, 1L, 1L, 2L, 4L),
  echo_date = c(95, 110, 130, 95, 100),
  ef = c(50, 55, 60, 45, 40)
)
join <- function(...) hvtiRtemplates:::.join_ancillary(cohort, echo, "ccfid", "ccfid", c("ccfid", "echo_date"), ...)

test_that("the long form keeps one row per record, for cohort patients only", {
  out <- join()
  expect_identical(nrow(out$data), 4L)
  expect_setequal(names(out$data), c("ccfid", "echo_date", "ef", "age", "dt_surg"))
  expect_identical(sort(unique(out$data$ccfid)), 1:2)
  expect_identical(out$data$age[out$data$ccfid == 1L], c(50, 50, 50))
  expect_identical(out$key, c("ccfid", "echo_date"))
  expect_identical(out$outside, 1L)
  expect_identical(out$without, 1L)
  expect_identical(out$ignored, 0L)
  expect_null(out$rule)
})

test_that("join_vars limits the cohort columns carried, and may name only the ID", {
  out <- join(join_vars = "age")
  expect_setequal(names(out$data), c("ccfid", "echo_date", "ef", "age"))
  out <- join(join_vars = "ccfid")
  expect_setequal(names(out$data), c("ccfid", "echo_date", "ef"))
  expect_identical(nrow(out$data), 4L)
})

test_that("join_vars naming a column the cohort lacks stops and names it", {
  expect_error(join(join_vars = "nope"), "JOIN_VARS names a column the cohort does not have: nope")
})

test_that("identifiers are matched as text, and a missing one is outside the cohort", {
  odd <- echo
  odd$ccfid <- c("1", "1", "1", NA, "4")
  out <- hvtiRtemplates:::.join_ancillary(cohort, odd, "ccfid", "ccfid", c("ccfid", "echo_date"))
  expect_identical(nrow(out$data), 3L)
  expect_identical(out$outside, 2L)
  expect_identical(out$without, 2L)
})

test_that("the joined dataset's identifier may have another name", {
  other <- stats::setNames(echo, c("pid", "echo_date", "ef"))
  out <- hvtiRtemplates:::.join_ancillary(cohort, other, "ccfid", "pid", c("pid", "echo_date"))
  expect_identical(out$key, c("ccfid", "echo_date"))
  expect_false("pid" %in% names(out$data))
})

test_that("a cohort with more than one row per patient stops with a count", {
  twice <- rbind(cohort, cohort[1, ])
  expect_error(hvtiRtemplates:::.join_ancillary(twice, echo, "ccfid", "ccfid", c("ccfid", "echo_date")),
               "1 patient has more than one row in the cohort")
})

test_that("first, last and nearest each keep one row per cohort patient", {
  first <- join(reduce = list(rule = "first", by = "echo_date"))
  expect_identical(nrow(first$data), 3L)
  expect_identical(first$data$ccfid, 1:3)
  expect_identical(first$key, "ccfid")
  expect_identical(first$data$ef[first$data$ccfid == 1L], 50)
  expect_identical(first$data$ef[first$data$ccfid == 2L], 45)
  expect_true(is.na(first$data$ef[first$data$ccfid == 3L]))
  expect_identical(first$without, 1L)
  expect_identical(first$outside, 1L)
  expect_identical(first$rule, "first by echo_date")

  last <- join(reduce = list(rule = "last", by = "echo_date"))
  expect_identical(last$data$ef[last$data$ccfid == 1L], 60)

  near <- join(reduce = list(rule = "nearest", by = "echo_date", to = "dt_surg"))
  expect_identical(near$data$ef[near$data$ccfid == 1L], 50)
  expect_identical(near$rule, "nearest by echo_date to dt_surg")
})

test_that("nearest reads dates", {
  dated <- transform(cohort, dt_surg = as.Date("2020-01-01") + dt_surg)
  dechos <- transform(echo, echo_date = as.Date("2020-01-01") + echo_date)
  near <- hvtiRtemplates:::.join_ancillary(dated, dechos, "ccfid", "ccfid", c("ccfid", "echo_date"),
                                           reduce = list(rule = "nearest", by = "echo_date", to = "dt_surg"))
  expect_identical(near$data$ef[near$data$ccfid == 1L], 50)
})

test_that("nearest refuses a date compared with a number", {
  dated <- transform(cohort, dt_surg = as.Date("2020-01-01") + dt_surg)
  expect_error(hvtiRtemplates:::.join_ancillary(dated, echo, "ccfid", "ccfid", c("ccfid", "echo_date"),
                                                reduce = list(rule = "nearest", by = "echo_date", to = "dt_surg")),
               "the same kind")
})

test_that("a joined dataset with no record of any cohort patient stops: the identifiers differ", {
  zeros <- transform(echo, ccfid = sprintf("%05d", ccfid))
  expect_error(hvtiRtemplates:::.join_ancillary(cohort, zeros, "ccfid", "ccfid", c("ccfid", "echo_date")),
               "No record of the joined dataset belongs to a cohort patient")
})

test_that("a patient with no joined record at all keeps a row", {
  none <- echo[0L, ]
  out <- hvtiRtemplates:::.join_ancillary(cohort, none, "ccfid", "ccfid", c("ccfid", "echo_date"),
                                          reduce = list(rule = "first", by = "echo_date"))
  expect_identical(nrow(out$data), 3L)
  expect_true(all(is.na(out$data$ef)))
  expect_identical(out$without, 3L)
})

test_that("a tie on the reduction column stops with a count", {
  tied <- rbind(echo, data.frame(ccfid = 1L, echo_date = 95, ef = 99))
  expect_error(hvtiRtemplates:::.join_ancillary(cohort, tied, "ccfid", "ccfid", c("ccfid", "echo_date", "ef"),
                                                reduce = list(rule = "first", by = "echo_date")),
               "1 patient has more than one record")
  # A tie away from the chosen record does not matter.
  late <- rbind(echo, data.frame(ccfid = 1L, echo_date = 130, ef = 99))
  out <- hvtiRtemplates:::.join_ancillary(cohort, late, "ccfid", "ccfid", c("ccfid", "echo_date", "ef"),
                                          reduce = list(rule = "first", by = "echo_date"))
  expect_identical(out$data$ef[out$data$ccfid == 1L], 50)
})

test_that("records with no value of `by` are ignored and counted", {
  gap <- rbind(echo, data.frame(ccfid = 2L, echo_date = NA, ef = 10))
  out <- hvtiRtemplates:::.join_ancillary(cohort, gap, "ccfid", "ccfid", c("ccfid", "ef"),
                                          reduce = list(rule = "first", by = "echo_date"))
  expect_identical(out$ignored, 1L)
  expect_identical(out$data$ef[out$data$ccfid == 2L], 45)
})

test_that("a column in both datasets stops and names JOIN_VARS", {
  both <- cbind(echo, age = 1)
  expect_error(hvtiRtemplates:::.join_ancillary(cohort, both, "ccfid", "ccfid", c("ccfid", "echo_date")), "JOIN_VARS")
  # Leaving the clashing column out of JOIN_VARS resolves it.
  out <- hvtiRtemplates:::.join_ancillary(cohort, both, "ccfid", "ccfid", c("ccfid", "echo_date"), join_vars = "dt_surg")
  expect_identical(nrow(out$data), 4L)
})

test_that("bad reduce settings stop with the setting named", {
  expect_error(join(reduce = list(rule = "mean", by = "echo_date")), "REDUCE")
  expect_error(join(reduce = list(rule = "nearest", by = "echo_date")), "to =")
  expect_error(join(reduce = list(rule = "first", by = "echo_date", to = "dt_surg")), "only with rule")
  expect_error(join(reduce = list(rule = "first", by = "nope")), "nope")
  expect_error(join(reduce = list(rule = "first", by = "ef", extra = 1)), "extra")
  chr <- transform(echo, echo_date = as.character(echo_date))
  expect_error(hvtiRtemplates:::.join_ancillary(cohort, chr, "ccfid", "ccfid", c("ccfid", "echo_date"),
                                                reduce = list(rule = "first", by = "echo_date")),
               "must be a number or a date")
})

test_that("no message names an identifier value", {
  big <- data.frame(ccfid = c(98765431L, 98765432L), age = 1)
  rec <- data.frame(ccfid = c(98765431L, 98765431L), d = c(1, 1))
  err <- tryCatch(hvtiRtemplates:::.join_ancillary(big, rec, "ccfid", "ccfid", "ccfid",
                                                   reduce = list(rule = "first", by = "d")),
                  error = conditionMessage)
  expect_match(err, "more than one record")
  expect_no_match(err, "98765431")
})

test_that("identifiers that match only after spaces, leading zeros or case are removed stop, with counts", {
  # Patient 2's records carry a padded or zero-led identifier; patient 1's match.
  odd <- data.frame(ccfid = c("1", "1", "0002", " 2", "4"), echo_date = c(95, 110, 95, 96, 100), ef = 1:5)
  err <- tryCatch(hvtiRtemplates:::.join_ancillary(cohort, odd, "ccfid", "ccfid", c("ccfid", "echo_date")),
                  error = conditionMessage)
  expect_match(err, "2 records of the joined dataset, on 1 cohort patient", fixed = TRUE)
  expect_match(err, "leading zeros", fixed = TRUE)
  expect_match(err, "dataset build", fixed = TRUE)
  expect_no_match(err, "0002")
  # Case, for text identifiers.
  coh <- data.frame(pid = c("ab1", "ab2"), age = 1:2)
  anc <- data.frame(pid = c("ab1", "AB2"), d = 1:2)
  expect_error(hvtiRtemplates:::.join_ancillary(coh, anc, "pid", "pid", c("pid", "d")), "1 record of the joined")
  # A record of a patient outside the cohort is still only counted.
  expect_identical(join()$outside, 1L)
})
