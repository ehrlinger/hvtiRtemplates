# Unit tests for the check functions. Each test plants one problem in a small
# synthetic table and confirms the matching flag fires, and that clean data
# raises no warning or error flags.
#
# Run from the report/ directory:  Rscript -e 'testthat::test_file("tests/test-checks.R")'

library(testthat)
source(file.path(if (dir.exists("R")) "R" else "../R", "checks.R"))

pspec <- list(
  name = "patients", role = "patient", id = "pt_id", date_var = "surgery_date",
  events = list(
    list(label = "Death", event = "dead", interval = "iv_dead", unit = "years", terminal = TRUE),
    list(label = "Reop", event = "reop", interval = "iv_reop", unit = "years")
  )
)
close <- as.Date("2025-01-01")

clean_patients <- function(n = 200, seed = 1) {
  set.seed(seed)
  idx <- as.Date("2005-01-01") + sample(0:5000, n, replace = TRUE)
  pot <- as.numeric(close - idx) / 365.25
  iv_dead <- pot * runif(n, 0.6, 1)
  dead <- rbinom(n, 1, 0.2)
  iv_reop <- iv_dead * runif(n, 0.3, 1)
  reop <- rbinom(n, 1, 0.1)
  data.frame(pt_id = sprintf("P%04d", seq_len(n)), surgery_date = idx,
             age = round(rnorm(n, 65, 10)), bmi = rnorm(n, 28, 4),
             sex = sample(c("F", "M"), n, TRUE),
             dead = dead, iv_dead = iv_dead, reop = reop, iv_reop = iv_reop)
}

has_flag <- function(flags, check, variable = NULL) {
  hit <- flags$check == check
  if (!is.null(variable)) hit <- hit & flags$variable == variable
  any(hit)
}

serious <- function(flags) flags[flags$severity %in% c("error", "warning"), ]

test_that("clean data raises no warning or error flags", {
  pts <- prepare_patient_table(clean_patients(), pspec)
  kinds <- classify_vars(pts, c("pt_id", "surgery_date", "dead", "iv_dead", "reop", "iv_reop"))
  f <- bind_flags(
    check_followup(pts, pspec, close)$flags,
    check_missing(pts, "patients", kinds$variable, "pt_id", "surgery_date")$flags,
    check_outliers(pts, "patients", kinds, "pt_id", list(bmi = c(12, 80)), close)$flags
  )
  expect_equal(nrow(serious(f)), 0)
  expect_true(has_flag(f, "FU-COMPLETENESS"))
})

test_that("guards stop on bad input", {
  d <- clean_patients()
  expect_error(prepare_patient_table(d[, names(d) != "iv_reop"], pspec), "IN-VAR")
  expect_error(prepare_patient_table(rbind(d, d[1, ]), pspec), "IN-DUPID")
  d2 <- d; d2$dead[1] <- 2
  expect_error(prepare_patient_table(d2, pspec), "IN-EVENT")
  d3 <- d; d3$surgery_date <- as.character(d3$surgery_date); d3$surgery_date[2] <- "12/31/2010"
  expect_error(prepare_patient_table(d3, pspec), "IN-TYPE")
  d4 <- d; d4$surgery_date <- as.character(d4$surgery_date)
  expect_s3_class(prepare_patient_table(d4, pspec)$surgery_date, "Date")
})

test_that("follow-up problems are flagged", {
  d <- clean_patients()
  d$iv_dead[1] <- -0.5                                   # negative
  d$iv_dead[2] <- 40                                     # past close
  d$dead[3] <- 1; d$iv_dead[3] <- 0                      # event at zero
  d$dead[4] <- 1; d$iv_dead[4] <- 1; d$iv_reop[4] <- 3   # reop after death
  d$iv_reop[5] <- NA                                     # missing
  pts <- prepare_patient_table(d, pspec)
  f <- check_followup(pts, pspec, close)$flags
  expect_true(has_flag(f, "FU-NEG", "iv_dead"))
  expect_true(has_flag(f, "FU-PAST-CLOSE", "iv_dead"))
  expect_true(has_flag(f, "FU-ZERO-EVENT", "iv_dead"))
  expect_true(has_flag(f, "FU-AFTER-TERMINAL", "iv_reop"))
  expect_true(has_flag(f, "FU-MISSING", "iv_reop"))
  expect_true("P0004" %in% f$ids[f$check == "FU-AFTER-TERMINAL"][[1]])
})

test_that("completeness index is 1 with full follow-up and lower with loss", {
  d <- clean_patients()
  d$dead <- 0
  d$iv_dead <- as.numeric(close - d$surgery_date) / 365.25
  d$reop <- 0; d$iv_reop <- d$iv_dead
  pts <- prepare_patient_table(d, pspec)
  expect_equal(check_followup(pts, pspec, close)$completeness$Death, 1)
  d$iv_dead <- d$iv_dead / 2
  pts <- prepare_patient_table(d, pspec)
  expect_equal(check_followup(pts, pspec, close)$completeness$Death, 0.5, tolerance = 1e-8)
})

test_that("missingness flags rate, era, unknowns and all-missing", {
  d <- clean_patients(400)
  d$ef <- rnorm(400, 55, 8); d$ef[d$surgery_date < as.Date("2010-01-01")] <- NA
  d$nyha <- sample(c("I", "II", "III", "Unknown"), 400, TRUE)
  d$empty <- NA_real_
  d$blank <- ""; d$blank[1:10] <- "x"
  pts <- prepare_patient_table(d, pspec)
  m <- check_missing(pts, "patients", c("ef", "nyha", "empty", "blank"), "pt_id",
                     "surgery_date", c("unknown"))
  expect_true(has_flag(m$flags, "MISS-RATE", "ef"))
  expect_true(has_flag(m$flags, "MISS-ERA", "ef"))
  expect_true(has_flag(m$flags, "MISS-UNK", "nyha"))
  expect_true(has_flag(m$flags, "MISS-ALL", "empty"))
  expect_true(has_flag(m$flags, "MISS-RATE", "blank"))  # empty strings count as missing
  expect_false(has_flag(m$flags, "MISS-RATE", "nyha"))  # unknown is not missing
})

test_that("outliers use clinical ranges first, then a robust fence", {
  d <- clean_patients()
  d$bmi[1:3] <- c(180, 200, 210)
  d$crp <- rlnorm(200, 1, 0.3); d$crp[7] <- 900
  pts <- prepare_patient_table(d, pspec)
  kinds <- classify_vars(pts, c("pt_id", "surgery_date", "dead", "iv_dead", "reop", "iv_reop"))
  o <- check_outliers(pts, "patients", kinds, "pt_id", list(bmi = c(12, 80)), close)
  expect_true(has_flag(o$flags, "OUT-RANGE", "bmi"))
  expect_equal(o$flags$n[o$flags$check == "OUT-RANGE"], 3L)
  expect_true(has_flag(o$flags, "OUT-FENCE", "crp"))
  expect_false(has_flag(o$flags, "OUT-FENCE", "bmi"))
})

test_that("longitudinal checks find planted problems", {
  pts <- prepare_patient_table(clean_patients(300), pspec)
  set.seed(3)
  ids <- sample(pts$pt_id[-(1:20)], 900, TRUE)               # 20 patients never measured
  when <- pts$surgery_date[match(ids, pts$pt_id)] + sample(0:2000, 900, TRUE)
  when <- pmin(when, close - 1)
  base <- setNames(rnorm(nrow(pts), 55, 6), pts$pt_id)      # each patient's own level
  long <- data.frame(pt_id = ids, echo_date = when, lvef = base[ids] + rnorm(900, 0, 2))
  long <- rbind(long,
    data.frame(pt_id = "X9999", echo_date = as.Date("2015-01-01"), lvef = 50),          # orphan
    data.frame(pt_id = long$pt_id[1], echo_date = long$echo_date[1], lvef = 20),        # duplicate
    data.frame(pt_id = pts$pt_id[30], echo_date = pts$surgery_date[30] - 900, lvef = 55), # pre-index
    data.frame(pt_id = pts$pt_id[31], echo_date = close + 30, lvef = 55))              # post-close
  lspec <- list(name = "echo", role = "longitudinal", id = "pt_id", time = "echo_date",
                values = "lvef", baseline_window_days = 365)
  lt <- prepare_long_table(long, lspec)
  f <- check_longitudinal(lt, pts, lspec, pspec, close)$flags
  expect_true(has_flag(f, "LONG-ORPHAN"))
  expect_true(has_flag(f, "LONG-NOMEAS"))
  expect_true(has_flag(f, "LONG-DUP", "lvef"))
  expect_true(has_flag(f, "LONG-PREINDEX"))
  expect_true(has_flag(f, "LONG-POSTCLOSE"))
  expect_true(has_flag(f, "LONG-JUMP", "lvef"))   # the 20 against a mid-50s trajectory
})

test_that("a unit change shows as a yearly level shift", {
  pts <- prepare_patient_table(clean_patients(300), pspec)
  set.seed(4)
  ids <- sample(pts$pt_id, 1500, TRUE)
  when <- as.Date("2010-01-01") + sample(0:3650, 1500, TRUE)
  lvef <- rnorm(1500, 55, 6)
  y <- format(when, "%Y") == "2016"
  lvef[y] <- lvef[y] / 100                                 # recorded as a fraction that year
  long <- data.frame(pt_id = ids, echo_date = when, lvef = lvef)
  lspec <- list(name = "echo", role = "longitudinal", id = "pt_id", time = "echo_date",
                values = "lvef", baseline_window_days = 100000)
  f <- check_longitudinal(prepare_long_table(long, lspec), pts, lspec, pspec, close)$flags
  expect_true(has_flag(f, "LONG-SHIFT", "lvef"))
  expect_match(f$detail[f$check == "LONG-SHIFT"], "2016")
})

test_that("wide longitudinal tables are refused", {
  wide <- data.frame(pt_id = c("P1", "P2"), lvef_1 = 50, lvef_2 = 52, lvef_3 = 49,
                     echo_date = as.Date("2015-01-01"), lvef = 50)
  lspec <- list(name = "echo", id = "pt_id", time = "echo_date", values = "lvef")
  expect_error(prepare_long_table(wide, lspec), "IN-WIDE")
})

test_that("notes attach and the gate finds unexplained flags", {
  f <- bind_flags(
    flag("patients", "bmi", "OUT-RANGE", "warning", 3, "x"),
    flag("patients", "ef", "MISS-RATE", "warning", 40, "y"),
    flag("patients", "iv_dead", "FU-COMPLETENESS", "info", 200, "z"))
  notes <- list(patients = list(bmi = list(`OUT-RANGE` = "Unit error in source.")))
  f <- attach_notes(f, notes)
  u <- unexplained(f)
  expect_equal(nrow(u), 1)
  expect_equal(u$variable, "ef")
})
