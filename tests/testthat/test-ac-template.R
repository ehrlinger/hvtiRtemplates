# The ac template, run chunk by chunk as a render would, after the biostats team
# review of 2026-10-21: numbers at risk, the censored-row option, the strata
# tests, the follow-up summary, missing strata dropped as %KAPLAN drops them,
# optional expected counts, and the figures.

ac_chunks <- c("tbl-data", "tbl-cohort", "tbl-event-freq", "tbl-followup", "derive", "tbl-derive-check", "km-helpers",
               "tbl-km-overall", "tbl-horizons", "km-strata", "km-figures", "fig-km-views", "fig-km-survival",
               "km-strata-figures")

# The helpers below call the test helpers and testthat, which lintr cannot see from here.
# nolint start: object_usage_linter.
ac_data <- function() {
  d <- hazard_data()
  d$grp <- rep(c("a", "b"), length.out = nrow(d))
  d$grp[1:5] <- NA
  d$male[6:8] <- 0.6
  d
}

ac_run <- function(data, choices = list(), labels = ac_chunks, .local_envir = parent.frame()) {
  root <- hazard_study(data, .local_envir = .local_envir)
  env <- hazard_env(root)
  warned <- character(0)
  withCallingHandlers(
    utils::capture.output({
      hazard_run("ac", c("set", "edit-study-choices"), env, choices)
      hazard_run("ac", labels, env)
    }),
    warning = function(w) {
      warned <<- c(warned, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  env$.warnings <- warned
  env
}

# The setup chunk's library(hvtiRutilities) does not run under hazard_run(), so it is attached here.
skip_ac <- function(env = parent.frame()) {
  skip_on_cran()
  skip_if_not_installed("TemporalHazard", minimum_version = "1.2.12")
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.7.0")
  skip_if_not_installed("patchwork")
  withr::local_package("hvtiRutilities", .local_envir = env)
}

# Built layers of the manuscript figure's curve, by geom, from ggplot_build().
built_layers <- function(curve) {
  b <- ggplot2::ggplot_build(curve)
  stats::setNames(b$data, vapply(curve$layers, function(l) class(l$geom)[[1]], ""))
}
# nolint end

test_that("an ac job runs unedited but for its strata, with no warning, and saves its figures", {
  skip_ac()
  local_child_chunks()
  env <- ac_run(ac_data(), list(STRATA = c("male", "grp")))
  expect_identical(env$.warnings, character(0))
  # EXPECTED is optional: NULL checks the counts against nothing.
  expect_null(env$EXPECTED)
  expect_identical(env$cc$n, 160L)
  expect_named(env$strata_fits, c("male", "grp"))
  expect_identical(attr(env$strata_fits$male, "dropped")$n, 3L)
  expect_identical(attr(env$strata_fits$grp, "dropped")$value, "NA")
  graphs <- file.path(hvtiRutilities::study_dir("graphs", env$.root), "dead_pa-hz")
  for (name in c("ac-survival", "ac-survival-male", "ac-survival-grp")) {
    expect_true(file.exists(file.path(graphs, paste0(name, ".png"))), info = name)
    expect_true(file.exists(file.path(graphs, paste0(name, ".pdf"))), info = name)
  }
  # hp reads the overall life table by set, as the event rows.
  saved <- readRDS(hazard_set_path(env$.root, "ac.rds"))
  expect_true(all(saved$overall$n_event > 0))
})

test_that("ac reports survival and the number at risk at each horizon", {
  skip_ac()
  env <- ac_run(hazard_data(), labels = c("tbl-data", "tbl-cohort"))
  at <- life_table_at(env$d, env$TIME, env$EVENT, times = env$grid, labels = env$labs)
  expect_identical(at$horizon[1:3], c("0.08214", "0.5", "1"))
  expect_identical(at$n_risk, vapply(env$grid, function(g) sum(env$d$iv_dead > g), integer(1)))
})

test_that("ac's expected counts, when given, still stop an unreconciled cohort", {
  skip_ac()
  bad <- list(EXPECTED = list(n = 1L, n_events = 1L, n_censored = 0L))
  expect_error(ac_run(hazard_data(), bad, labels = c("tbl-data", "tbl-cohort")), "cohort gate")
})

test_that("ac's derivation check reads each derived category against its source", {
  skip_ac()
  env <- ac_run(hazard_data(), labels = c("tbl-data", "tbl-cohort", "derive"))
  env$d$age_grp <- 2L
  env$d$age_grp[which(env$d$age < 50)] <- 1L
  env$DERIVED <- c(age_grp = "age")
  utils::capture.output(hazard_run("ac", "tbl-derive-check", env))
  rows <- env$derived_rows("age_grp")
  expect_identical(rows$level, c(1L, 2L))
  expect_identical(sum(rows$n), 160L)
  expect_lt(rows$src_max[[1]], rows$src_min[[2]])
  env$DERIVED <- c(nope = "age")
  expect_error(hazard_run("ac", "tbl-derive-check", env), "DERIVED names column\\(s\\) not in the data: nope")
})

test_that("ac's follow-up summary uses SAS's percentile definition", {
  skip_ac()
  env <- ac_run(hazard_data(), labels = c("tbl-data", "tbl-cohort", "tbl-followup"))
  row <- env$fu_row("all", c(1, 2, 3, 4))
  # PCTLDEF=5 takes the mean of the two middle values at an even split.
  expect_identical(row$median, 2.5)
  expect_identical(row$p25, 1.5)
})

test_that("an ac job completes when one stratum is all censored", {
  skip_ac()
  local_child_chunks()
  d <- hazard_data()
  d$grp <- ifelse(seq_len(nrow(d)) <= 20, "b", "a")
  d$dead[d$grp == "b"] <- 0L
  env <- ac_run(d, list(STRATA = "grp"))
  expect_identical(env$.warnings, character(0))
  counts <- attr(env$strata_fits$grp, "counts")
  expect_identical(counts$n[counts$stratum == "b"], 20L)
  expect_identical(counts$n_events[counts$stratum == "b"], 0L)
  graphs <- file.path(hvtiRutilities::study_dir("graphs", env$.root), "dead_pa-hz")
  expect_true(file.exists(file.path(graphs, "ac-survival-grp.png")))
  # The views draw it too, flat at 100% to the end of its follow-up.
  surv <- env$km_views(env$strata_fits$grp)[[1]]$data
  b <- surv[surv$stratum == "b", ]
  expect_identical(unique(b$survival), 1)
  expect_identical(max(b$time), counts$max_fup[counts$stratum == "b"])
  # The manuscript figure's straight line runs flat for it too, with no event point.
  layers <- built_layers(env$km_figure("grp")[[1]])
  b_group <- match("b", counts$stratum)
  line_b <- layers$GeomLine[layers$GeomLine$group == b_group, ]
  expect_identical(unique(line_b$y), 100)
  expect_identical(max(line_b$x), counts$max_fup[counts$stratum == "b"])
  expect_false(b_group %in% layers$GeomPoint$group)
})

test_that("an ac job completes when no patient has the event", {
  skip_ac()
  local_child_chunks()
  d <- hazard_data()
  d$dead <- 0L
  env <- ac_run(d)
  expect_identical(env$.warnings, character(0))
  expect_identical(env$cc$n_events, 0L)
  expect_identical(nrow(env$km), 0L)
  surv <- env$km_views(env$km)[[1]]$data
  expect_identical(unique(surv$survival), 1)
  # The cumulative-hazard panels are empty. The scale's warnings arrive only when the patchwork is
  # drawn, not when it is built, so it is drawn.
  withr::local_pdf(NULL)
  expect_no_warning(print(env$km_views(env$km)))
  graphs <- file.path(hvtiRutilities::study_dir("graphs", env$.root), "dead_pa-hz")
  expect_true(file.exists(file.path(graphs, "ac-survival.png")))
})

test_that("CI_TIMES draws confidence bars at those times, with the tables' limits", {
  skip_ac()
  local_child_chunks()
  geoms <- function(p) vapply(p$layers, function(l) class(l$geom)[[1]], "")
  # 0.005 years is before the first event (follow-up starts at 0.01) and 50 is past follow-up:
  # neither has limits to draw.
  env <- ac_run(ac_data(), list(STRATA = "grp", CI_TIMES = c(0.005, 1, 3, 50), CI_BAND = FALSE))
  expect_identical(env$.warnings, character(0))
  curve <- env$km_figure("grp")[[1]]
  # CI_BAND = FALSE with CI_TIMES set: the SAS figure's bars alone.
  expect_true("GeomErrorbar" %in% geoms(curve))
  expect_false("GeomRibbon" %in% geoms(curve))
  bars <- curve$layers[[match("GeomErrorbar", geoms(curve))]]$data
  at <- life_table_at(env$d, env$TIME, env$EVENT, times = c(1, 3), strata = "grp", conf_level = env$CLEVEL)
  expect_identical(nrow(bars), 4L)
  expect_identical(sort(unique(bars$time)), c(1, 3))
  expect_equal(bars$cl_lower, at$cl_lower)
  expect_equal(bars$cl_upper, at$cl_upper)
  expect_identical(levels(bars$strata), c("a", "b"))
  layer <- curve$layers[[match("GeomErrorbar", geoms(curve))]]
  expect_s3_class(layer$position, "PositionDodge")
  expect_false(isTRUE(layer$show.legend))
  env$CI_TIMES <- c(1, NA)
  expect_error(env$km_figure("grp"), "CI_TIMES must be NULL or nonnegative times")
  env$CI_TIMES <- c(1, 3, 50)
  # The overall figure gets them too.
  expect_true("GeomErrorbar" %in% geoms(env$km_figure()[[1]]))
  # With the band left on, the figure carries both.
  env$CI_BAND <- TRUE
  expect_true(all(c("GeomRibbon", "GeomErrorbar") %in% geoms(env$km_figure("grp")[[1]])))
  # And with neither, no limits are drawn at all.
  env$CI_BAND <- FALSE
  env$CI_TIMES <- NULL
  expect_false(any(c("GeomRibbon", "GeomErrorbar") %in% geoms(env$km_figure("grp")[[1]])))
})

test_that("by default the manuscript figure draws the band and no bars", {
  skip_ac()
  local_child_chunks()
  geoms <- function(p) vapply(p$layers, function(l) class(l$geom)[[1]], "")
  env <- ac_run(ac_data())
  expect_null(env$CI_TIMES)
  expect_true(env$CI_BAND)
  curve <- env$km_figure()[[1]]
  expect_true("GeomRibbon" %in% geoms(curve))
  expect_false("GeomErrorbar" %in% geoms(curve))
})

test_that("numeric strata keep one color for curve, band and bars (1, 2, 10 sort as numbers)", {
  skip_ac()
  local_child_chunks()
  d <- hazard_data()
  d$grp3 <- rep(c(1, 2, 10), length.out = nrow(d))
  env <- ac_run(d, list(STRATA = "grp3", CI_TIMES = c(1, 3), CI_BAND = TRUE))
  expect_identical(env$.warnings, character(0))
  curve <- env$km_figure("grp3")[[1]]
  expect_no_warning(layers <- built_layers(curve))
  b <- ggplot2::ggplot_build(curve)
  # ggplot's own name for the color aesthetic and its built-data column.
  col_aes <- ggplot2::standardise_aes_names("color")
  expect_identical(b$plot$scales$get_scales(col_aes)$get_limits(), c("1", "2", "10"))
  expect_identical(b$plot$scales$get_scales("fill")$get_limits(), c("1", "2", "10"))
  by_group <- function(x, col) tapply(x[[col]], x$group, function(v) unique(v)[[1]])
  line <- by_group(layers$GeomLine, col_aes)
  band <- by_group(layers$GeomRibbon, "fill")
  bar <- by_group(layers$GeomErrorbar, col_aes)
  expect_identical(unname(line), unname(band))
  expect_identical(unname(line), unname(bar))
})

test_that("the curves join event points with straight lines by default, and STEPS draws steps", {
  skip_ac()
  local_child_chunks()
  geoms <- function(p) vapply(p$layers, function(l) class(l$geom)[[1]], "")
  env <- ac_run(ac_data(), list(STRATA = "grp"))
  expect_identical(env$.warnings, character(0))
  expect_false(env$STEPS)
  events <- sort(unique(env$km$time[env$km$time <= env$plot_max]))
  # The manuscript figure: a line through the events, with a point at each, and no corner at a censored time.
  curve <- env$km_figure()[[1]]
  expect_true(all(c("GeomLine", "GeomPoint") %in% geoms(curve)))
  expect_false("GeomStep" %in% geoms(curve))
  layers <- built_layers(curve)
  expect_equal(sort(unique(layers$GeomPoint$x)), events)
  expect_true(all(layers$GeomLine$x %in% c(0, events, max(layers$GeomLine$x))))
  # The reading page: the same, panel by panel.
  page <- env$km_views(env$km)
  for (i in 1:5) expect_true(all(c("GeomLine", "GeomPoint") %in% geoms(page[[i]])))
  expect_equal(sort(unique(ggplot2::ggplot_build(page[[1]])$data[[2]]$x)), events)
  # STEPS = TRUE draws the Kaplan-Meier steps, and keeps the points.
  env$STEPS <- TRUE
  expect_true(all(c("GeomStep", "GeomPoint") %in% geoms(env$km_figure()[[1]])))
  expect_true(all(c("GeomStep", "GeomPoint") %in% geoms(env$km_views(env$km)[[1]])))
  expect_no_warning(print(env$km_figure("grp")))
})

test_that("one curve is black, and no stratum takes the event's red or censored blue", {
  skip_ac()
  local_child_chunks()
  col_aes <- ggplot2::standardise_aes_names("color")
  # Both the role colors and the rotation's look-alikes, so the test holds on either hvtiPlotR.
  roles <- c(hvtiPlotR::hv_role_palette(c("e", "c"), event = "e", censored = "c"), "#0072B2", "#D55E00")
  d <- hazard_data()
  d$grp3 <- rep(c(1, 2, 10), length.out = nrow(d))
  env <- ac_run(d, list(STRATA = "grp3"))
  one <- unique(built_layers(env$km_figure()[[1]])$GeomLine[[col_aes]])
  expect_identical(one, "#000000")
  expect_identical(unique(ggplot2::ggplot_build(env$km_views(env$km)[[1]])$data[[1]][[col_aes]]), "#000000")
  three <- unique(built_layers(env$km_figure("grp3")[[1]])$GeomLine[[col_aes]])
  expect_length(three, 3L)
  expect_false(any(toupper(three) %in% toupper(roles)))
  views <- unique(ggplot2::ggplot_build(env$km_views(env$strata_fits$grp3)[[1]])$data[[1]][[col_aes]])
  expect_identical(sort(views), sort(three))
})

test_that("bars at close early times on a long axis stay at their own time and after zero", {
  skip_ac()
  local_child_chunks()
  d <- hazard_data()
  d$grp3 <- rep(c(1, 2, 10), length.out = nrow(d))
  early <- c(30, 90) / 365.2425
  env <- ac_run(d, list(STRATA = "grp3", CI_TIMES = early, CI_BAND = FALSE, PLOT_MAX = 20))
  expect_identical(env$.warnings, character(0))
  curve <- env$km_figure("grp3")[[1]]
  expect_no_warning(layers <- built_layers(curve))
  bars <- layers$GeomErrorbar
  expect_true(all(bars$xmin >= 0))
  # Each bar sits nearer its own time than the other one, so 30- and 90-day bars never interleave.
  own <- early[apply(abs(outer(bars$x, early, "-")), 1, which.min)]
  expect_identical(sort(unique(own)), early)
  expect_lt(max(bars$xmax[own == early[[1]]]), min(bars$xmin[own == early[[2]]]))
})
