# The figures hz, hm and hs-setup draw inside their own jobs (figure sweep,
# 2026-10-21). Each figure chunk runs after the chunks it reads from, as a
# render runs it, and must raise no warning and save its PNG, PDF and TIFF.

# Run `labels` of template `prefix` in `env`, returning every warning's message.
figure_warnings <- function(prefix, labels, env) {
  warned <- character(0)
  withCallingHandlers(
    utils::capture.output(hazard_run(prefix, labels, env)),  # nolint: object_usage_linter.
    warning = function(w) {
      warned <<- c(warned, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  warned
}

figure_files <- function(env, name) {
  file.exists(env$set_path("graphs", paste0(name, c(".png", ".pdf", ".tiff"))))
}

test_that("hz draws its fit over the Kaplan-Meier estimate, with no warning", {
  skip_on_cran()
  skip_if_not_installed("ragg")
  skip_if_not_installed("TemporalHazard", minimum_version = "1.2.8")
  skip_if_not_installed("numDeriv")
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  env <- hz_fit_run("noconserve")
  expect_identical(figure_warnings("hz", c("tbl-conservation-binding", "edit-estimates", "tbl-estimates", "fig-fit"), env),
                   character(0))
  expect_true(all(figure_files(env, "hz-fit")))
  # The figure draws the step function from every analyzed row, and the curve to the last time.
  expect_identical(nrow(env$.km), length(unique(env$resp$time)) + 1L)
  expect_identical(max(env$.grid$time), max(env$resp$time))
  expect_identical(grDevices::dev.cur(), c("null device" = 1L))
})

test_that("hm and hs-setup draw calibration and expected survival, with no warning", {
  skip_on_cran()
  skip_if_not_installed("ragg")
  skip_if_not_installed("TemporalHazard", minimum_version = "1.2.8")
  skip_if_not_installed("hvtiRlifetables", minimum_version = "0.1.2")
  skip_if_not_installed("numDeriv")
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  withr::local_package("hvtiRlifetables")
  data <- hazard_data()
  hm_env <- hazard_chain_run(hazard_study(data), data)

  expect_identical(figure_warnings("hm", "fig-calibration", hm_env), character(0))
  expect_true(all(figure_files(hm_env, "hm-calibration")))

  env <- globalenv()
  expect_identical(figure_warnings("hs-setup", "fig-expected", env), character(0))
  expect_true(all(figure_files(env, "hs-setup-expected")))
  # The grid recomputes the table's numbers: at each horizon on it, the curves
  # pass through the table's points.
  at <- match(get("obs_vs_exp", envir = env)$horizon, get(".curves", envir = env)$time)
  expect_false(anyNA(at))
  curves <- get(".curves", envir = env)
  points <- get(".points", envir = env)
  expect_equal(curves$survival[curves$curve == "model"][at], points$survival[points$curve == "model"])
  expect_equal(curves$survival[curves$curve == "population"][at], points$survival[points$curve == "population"])
  expect_identical(grDevices::dev.cur(), c("null device" = 1L))
})

test_that("hs-setup's grid keeps a horizon that seq() lands a rounding error away from (#381 review)", {
  skip_on_cran()
  skip_if_not_installed("ragg")
  skip_if_not_installed("TemporalHazard", minimum_version = "1.2.8")
  skip_if_not_installed("hvtiRlifetables", minimum_version = "0.1.2")
  skip_if_not_installed("numDeriv")
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  withr::local_package("hvtiRlifetables")
  # seq(0, 5, length.out = 51) holds 0.6000000000000001 beside the horizon 0.6:
  # kept as two times, they were averaged as one, and the figure stopped.
  horizons <- c(0.6, 1, 5)
  expect_false(0.6 %in% seq(0, 5, length.out = 51L))
  data <- hazard_data()
  hazard_chain_run(hazard_study(data), data, hs_choices = list(HORIZONS = horizons))
  env <- globalenv()
  expect_identical(figure_warnings("hs-setup", "fig-expected", env), character(0))
  grid <- get(".grid", envir = env)
  expect_true(all(horizons %in% grid))
  expect_false(any(diff(grid) < 1e-8 * max(horizons)))
  curves <- get(".curves", envir = env)
  expect_identical(nrow(curves), 2L * (length(grid) + 1L))
})
