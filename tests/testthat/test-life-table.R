# life_table() and its companions, which the ac job calls in place of the SAS
# %KAPLAN macro (biostats team review, 2026-10-21).

skip_if_not_installed("TemporalHazard", minimum_version = "1.2.12")

test_that("the strata tests reproduce PROC LIFETEST on the Gehan leukemia data", {
  skip_if_not_installed("MASS")
  # SAS PROC LIFETEST on these data prints Log-Rank 16.7929, Wilcoxon 13.4579 and
  # -2Log(LR) 16.4852, each on 1 df. The Wilcoxon is Gehan's, weighted by the
  # number at risk, and the LR test is of an exponential model.
  out <- life_table_tests(MASS::gehan, "time", "cens", "treat")
  expect_identical(out$test, c("Log-rank", "Wilcoxon", "-2Log(LR)"))
  expect_equal(out$chisq, c(16.7929, 13.4579, 16.4852), tolerance = 1e-5)
  expect_identical(out$df, rep(1L, 3))
  expect_equal(out$p_value, stats::pchisq(out$chisq, 1, lower.tail = FALSE))
})

test_that("the log-rank test agrees with survival::survdiff over three strata", {
  skip_if_not_installed("survival")
  d <- hazard_data()
  d$grp <- rep(c("a", "b", "c"), length.out = nrow(d))
  ours <- life_table_tests(d, "iv_dead", "dead", "grp")
  ref <- survival::survdiff(survival::Surv(iv_dead, dead) ~ grp, data = d)
  expect_equal(ours$chisq[[1]], ref$chisq, tolerance = 1e-8)
  expect_identical(ours$df[[1]], 2L)
})

test_that("life_table() is hzr_kaplan() per stratum, with the counts", {
  skip_if_not_installed("MASS")
  g <- MASS::gehan
  lt <- life_table(g, "time", "cens", strata = "treat")
  expect_identical(unique(lt$stratum), c("6-MP", "control"))
  ref <- as.data.frame(TemporalHazard::hzr_kaplan(g$time[g$treat == "6-MP"], g$cens[g$treat == "6-MP"],
                                                  conf_level = 0.68268948))
  mine <- lt[lt$stratum == "6-MP", -1]
  rownames(mine) <- NULL
  expect_equal(mine, ref, ignore_attr = TRUE)
  counts <- attr(lt, "counts")
  expect_identical(counts$n, c(21L, 21L))
  expect_identical(counts$n_events, c(9L, 21L))
  expect_identical(counts$max_fup, c(35, 23))
  # event_only = FALSE adds the censored times, as SAS PEVENT=0 does.
  all_rows <- life_table(g, "time", "cens", event_only = FALSE)
  expect_gt(nrow(all_rows), nrow(life_table(g, "time", "cens")))
  expect_true(any(all_rows$n_event == 0))
  expect_null(all_rows$stratum)
})

test_that("life_table_at() reads the estimate before a horizon and the count after it", {
  # Deaths at 1 and 3, censored at 2, 2.5 and 5. At horizon 2 the estimate is
  # the row at 1; the patient censored at exactly 2 is no longer at risk after it.
  d <- data.frame(t = c(1, 2, 2.5, 3, 5), e = c(1, 0, 0, 1, 0))
  at <- life_table_at(d, "t", "e", times = c(0.5, 2, 4, 5, 6))
  expect_equal(at$survival, c(1, 0.8, 0.8 * 0.5, 0.4, NA))
  expect_identical(at$n_risk, c(5L, 3L, 1L, 0L, 0L))
  # Before the first event survival is 1, with no limits to report.
  expect_true(is.na(at$cl_lower[[1]]))
  # Default labels are the horizons' values.
  expect_identical(at$horizon, c("0.5", "2", "4", "5", "6"))
  # Survival of zero stays known beyond the last observation.
  dead <- data.frame(t = c(1, 2), e = c(1, 1))
  expect_identical(life_table_at(dead, "t", "e", times = 3)$survival, 0)
})

test_that("life_table_at() checks its horizons and labels", {
  d <- data.frame(t = c(1, 2), e = c(1, 0))
  expect_error(life_table_at(d, "t", "e", times = -1), "nonnegative")
  expect_error(life_table_at(d, "t", "e", times = c(1, 2), labels = "one"), "1 entries for 2 horizons")
})

test_that("a missing or mean-imputed stratum is dropped, and the drop is recorded", {
  d <- hazard_data(60)
  d$male[1:4] <- NA
  d$male[5:7] <- 0.6
  lt <- life_table(d, "iv_dead", "dead", strata = "male")
  expect_identical(unique(lt$stratum), c("0", "1"))
  expect_identical(sum(attr(lt, "counts")$n), 53L)
  dropped <- attr(lt, "dropped")
  expect_identical(dropped$value, c("0.6", "NA"))
  expect_identical(dropped$n, c(3L, 4L))
  keep <- life_table_keep(d, "iv_dead", "dead", "male")
  expect_identical(sum(keep), 53L)
  expect_false(any(keep[1:7]))
  expect_identical(attr(life_table_tests(d, "iv_dead", "dead", "male"), "dropped"), dropped)
  # The whole cohort keeps every row with a time and an event.
  expect_null(attr(life_table(d, "iv_dead", "dead"), "dropped"))
  expect_identical(sum(life_table_keep(d, "iv_dead", "dead")), 60L)
})

test_that("the life table functions name what is wrong with their input", {
  d <- data.frame(t = c(1, 2), e = c(1, 0), g = c("a", "a"))
  expect_error(life_table(d, "t", "nope"), "not in the data: nope")
  expect_error(life_table(d, "t", "e", strata = c("g", "e")), "name one column")
  expect_error(life_table_tests(d, "t", "e", "g"), "fewer than two analysable strata")
  expect_error(life_table(data.frame(t = NA, e = 1), "t", "e"), "No row has a recorded time")
})
