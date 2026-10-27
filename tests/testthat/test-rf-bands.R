band_forest <- function(family = c("surv", "class", "regr")) {
  family <- match.arg(family)
  e <- new.env()
  utils::data("veteran", package = "randomForestSRC", envir = e)
  # rfsrc() parses the formula text and does not accept survival::Surv.
  Surv <- survival::Surv # nolint: object_name_linter, object_usage_linter.
  switch(family,
    surv = randomForestSRC::rfsrc(Surv(time, status) ~ ., e$veteran, ntree = 20, seed = -1),
    class = randomForestSRC::rfsrc(Species ~ ., datasets::iris, ntree = 20, seed = -1),
    regr = randomForestSRC::rfsrc(Ozone ~ ., stats::na.omit(datasets::airquality), ntree = 20, seed = -1)
  )
}

test_that("the default subratio follows randomForestSRC's rule, and a chosen one is checked", {
  expect_equal(hvtiRtemplates:::.band_subratio(500, NULL), exp(-1))
  expect_equal(hvtiRtemplates:::.band_subratio(4000, NULL), exp(-1) * sqrt(1000 / 4000))
  expect_equal(hvtiRtemplates:::.band_subratio(500, 0.25), 0.25)
  for (bad in list(0, 0.6, -1, NA_real_, c(0.2, 0.3), "0.2")) {
    expect_error(hvtiRtemplates:::.band_subratio(500, bad), "SUBRATIO")
  }
  expect_identical(hvtiRtemplates:::.band_size(100, 0.37), 37L)
  expect_identical(hvtiRtemplates:::.band_size(3, 0.1), 2L)
})

test_that("with theta_hat as subsample()'s own VIMP, the SE is the jackknife SE extract.subsample() reports", {
  skip_if_not_installed("randomForestSRC", "3.9.0")
  for (fam in c("surv", "class", "regr")) {
    f <- band_forest(fam)
    set.seed(2)
    s <- randomForestSRC::subsample(f, B = 4, subratio = 0.4, importance = "anti", verbose = FALSE)
    star <- hvtiRtemplates:::.band_vimp_star(s)
    # One row per predictor, one column per subsample; a classification forest's overall column.
    expect_identical(dim(star), c(length(f$xvar.names), 4L), info = fam)
    expect_identical(rownames(star), f$xvar.names, info = fam)
    hat <- s$vmp[[1]][, if (fam == "class") "all" else 1]
    expect_equal(hvtiRtemplates:::.band_se(hat, star, s$subratio),
                 randomForestSRC::extract.subsample(s, standardize = FALSE)$se.jk.Z, tolerance = 1e-10, info = fam)
    # The cache holds the matrix and not the object, which carries a forest.
    expect_lt(as.numeric(utils::object.size(star)), as.numeric(utils::object.size(s)) / 10)
  }
})

test_that("the importance SE is taken about the plotted estimate, not subsample()'s own full-forest VIMP", {
  star <- cbind(c(1, 2), c(3, 2), c(2, 6))
  rownames(star) <- c("a", "b")
  est <- c(b = 2.5, a = 1.5) # the importance figure's order, which is not the subsample matrix's
  se <- hvtiRtemplates:::.band_vimp_se(est, star, 0.4)
  expect_identical(names(se), names(est))
  expect_equal(unname(se), sqrt(0.4 * c(mean((star["b", ] - 2.5)^2), mean((star["a", ] - 1.5)^2))))
  # Centred on subsample()'s own estimate the SE would differ.
  expect_false(isTRUE(all.equal(unname(se), unname(hvtiRtemplates:::.band_se(c(b = 2, a = 1), star, 0.4)[c("b", "a")]))))
  expect_error(hvtiRtemplates:::.band_vimp_se(c(zz = 1), star, 0.4), "zz")
})

test_that("an NA replicate is left out of the SE rather than making it NA", {
  star <- matrix(c(1, 2, NA, 3, 1, 2), nrow = 2)
  expect_equal(hvtiRtemplates:::.band_se(c(2, 2), star, 0.5),
               sqrt(0.5 * c(mean(c(1, 1)), mean(c(0, 1, 0)))))
})

test_that("interpolating at a grid point reproduces that grid point", {
  x <- c(10, 20, 30)
  hat <- c(1, 2, 4)
  star <- cbind(c(1, 3, 5), c(0, 2, 2))
  at <- hvtiRtemplates:::.band_at(x, hat, star, c(20, 25))
  expect_equal(at$hat, c(2, 3))
  expect_equal(at$star, rbind(c(3, 2), c(4, 2)))
  expect_error(hvtiRtemplates:::.band_at(x, hat, star, 40), "observed range")
})

test_that("a failed subsample interpolates to NA, and the others are read as before", {
  x <- c(10, 20, 30)
  hat <- c(1, 2, 4)
  star <- cbind(c(1, 3, 5), NA_real_)
  at <- hvtiRtemplates:::.band_at(x, hat, star, 25)
  expect_equal(at$star[1, 1], 4)
  expect_true(is.na(at$star[1, 2]))
  expect_equal(dim(at$star), c(1L, 2L))
})

test_that("the floor names the subratio that would give 100 rare cases", {
  expect_equal(hvtiRtemplates:::.band_floor_need(400), 0.25)
  expect_equal(hvtiRtemplates:::.band_floor_need(150), 100 / 150)
})

test_that("rows are drawn within event status, at the subsample size, the same under the same seed", {
  skip_if_not_installed("randomForestSRC", "3.9.0")
  f <- band_forest("surv")
  set.seed(1)
  rows <- hvtiRtemplates:::.band_rows(f, 3, 0.3)
  set.seed(1)
  expect_identical(hvtiRtemplates:::.band_rows(f, 3, 0.3), rows)
  expect_length(rows, 3L)
  status <- f$yvar[[2]] > 0
  for (r in rows) {
    expect_false(is.unsorted(r))
    expect_lte(abs(length(r) - hvtiRtemplates:::.band_size(f$n, 0.3)), 1L)
    expect_equal(mean(status[r]), mean(status), tolerance = 0.05)
  }
})

test_that("a survival subsample with no event stops, naming SUBRATIO", {
  skip_if_not_installed("randomForestSRC", "3.9.0")
  f <- band_forest("surv")
  f$yvar[[2]][] <- 0
  f$yvar[[2]][1] <- 1
  expect_error(hvtiRtemplates:::.band_rows(f, 2, 0.05), "SUBRATIO")
})

test_that("a classification subsample that would hold no row of a class stops, naming SUBRATIO", {
  skip_if_not_installed("randomForestSRC", "3.9.0")
  f <- band_forest("class")
  f$yvar <- factor(c(rep("a", f$n - 1L), "b"))
  # One "b" in n patients: a subsample of a few rows rounds its share to zero.
  expect_error(hvtiRtemplates:::.band_rows(f, 2, 0.05), "SUBRATIO")
})

test_that("a refit keeps the forest's settings and grows on the rows given", {
  skip_if_not_installed("randomForestSRC", "3.9.0")
  for (fam in c("surv", "class", "regr")) {
    f <- band_forest(fam)
    rows <- seq(1L, f$n, by = 2L) # every other row: iris is sorted by species, so a first half would drop a class
    g <- hvtiRtemplates:::.band_refit(f, rows, seed = -7)
    expect_identical(g$n, length(rows), info = fam)
    expect_identical(g$family, f$family, info = fam)
    expect_identical(c(g$ntree, g$mtry, g$nodesize), c(f$ntree, f$mtry, f$nodesize), info = fam)
    expect_identical(g$xvar.names, f$xvar.names, info = fam)
  }
})

test_that("partial values agree with gg_partial_rfsrc on its own grid", {
  skip_if_not_installed("randomForestSRC", "3.9.0")
  skip_if_not_installed("ggRandomForests", "4.0.0")
  f <- band_forest("surv")
  pd <- ggRandomForests::gg_partial_rfsrc(f, xvar.names = c("karno", "celltype"), partial.time = c(30, 90))
  times <- hvtiRtemplates:::.band_times(pd)
  g <- hvtiRtemplates:::.band_grid(pd, "karno")
  expect_identical(g$type, "continuous")
  v <- hvtiRtemplates:::.partial_values(f, "karno", g$x, times)
  ref <- pd$continuous[pd$continuous$name == "karno", ]
  ref <- ref[order(ref$time, ref$x), ]
  expect_equal(v, ref$yhat, tolerance = 1e-8)
  cg <- hvtiRtemplates:::.band_grid(pd, "celltype")
  expect_identical(cg$type, "categorical")
  cv <- hvtiRtemplates:::.partial_values(f, "celltype", cg$x, times)
  expect_length(cv, length(cg$x) * length(times))
  expect_true(all(cv >= 0 & cv <= 1))
})

test_that("the pool grows each subsample forest once for all its variables", {
  skip_if_not_installed("randomForestSRC", "3.9.0")
  skip_if_not_installed("ggRandomForests", "4.0.0")
  f <- band_forest("surv")
  pd <- ggRandomForests::gg_partial_rfsrc(f, xvar.names = c("karno", "age"), partial.time = c(30, 90))
  times <- hvtiRtemplates:::.band_times(pd)
  grids <- lapply(c(karno = "karno", age = "age"), function(v) hvtiRtemplates:::.band_grid(pd, v))
  set.seed(1)
  rows <- hvtiRtemplates:::.band_rows(f, 3, 0.4)
  grown <- 0L
  # The mock counts the refits and hands back the full forest, so the test grows nothing.
  local_mocked_bindings(.band_refit = function(...) {
    grown <<- grown + 1L
    f
  }, .package = "hvtiRtemplates")
  steps <- integer()
  pool <- hvtiRtemplates:::.band_pool(names(grids), grids, progress = function(step, steps_) steps <<- c(steps, step))
  a <- hvtiRtemplates:::.band_partial(pool, f, rows, "karno", grids$karno, times, 1)
  b <- hvtiRtemplates:::.band_partial(pool, f, rows, "age", grids$age, times, 1)
  expect_identical(grown, 3L)
  expect_identical(steps, 1:3)
  expect_identical(dim(a$star), c(length(grids$karno$x) * length(times), 3L))
  expect_length(b$hat, length(grids$age$x) * length(times))
  expect_error(hvtiRtemplates:::.band_partial(pool, f, rows, "trt", grids$karno, times, 1), "not in the pool")
})

test_that("a subsample forest that cannot give a value leaves NA for that subsample only", {
  skip_if_not_installed("randomForestSRC", "3.9.0")
  f <- band_forest("regr")
  grid <- list(type = "continuous", x = c(60, 80))
  pool <- hvtiRtemplates:::.band_pool("Temp", list(Temp = grid))
  calls <- 0L
  local_mocked_bindings(.partial_values = function(forest, ...) {
    calls <<- calls + 1L
    if (calls == 2L) stop("level absent") else c(1, 2)
  }, .package = "hvtiRtemplates")
  expect_warning(out <- hvtiRtemplates:::.band_partial(pool, f, list(1:50, 1:50), "Temp", grid, NULL, 1),
                 "Temp: 1 of 2 subsample forests gave no partial value")
  expect_false(anyNA(out$star[, 1]))
  expect_true(all(is.na(out$star[, 2])))
})

test_that("the plan refuses a bad style or BAND_AT, and warns below the floor", {
  skip_if_not_installed("randomForestSRC", "3.9.0")
  skip_if_not_installed("ggRandomForests", "4.0.0")
  f <- band_forest("surv")
  pd <- ggRandomForests::gg_partial_rfsrc(f, xvar.names = c("karno", "celltype"), partial.time = 30)
  plan <- function(...) hvtiRtemplates:::.band_plan(f, 3, 0.4, ..., sel = c("karno", "celltype"), pd = pd)
  expect_error(plan("dots", NULL), "BAND_STYLE")
  expect_error(plan("bars", list(trt = 1)), "BAND_AT")
  expect_error(plan("bars", list(celltype = 1)), "categorical")
  expect_error(plan("bars", list(karno = "50")), "BAND_AT")
  # An out-of-range or missing value stops here, before any band is computed, and names BAND_AT.
  expect_error(plan("bars", list(karno = 1000)), "BAND_AT.*outside")
  expect_error(plan("bars", list(karno = c(50, NA))), "BAND_AT.*missing")
  expect_message(suppressWarnings(plan("ribbon", list(karno = 50))), "BAND_AT is ignored")
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "")
  # veteran has 128 deaths, so 40% of them is about 51, under the floor of 100.
  expect_warning(p <- plan("ribbon", NULL), "SUBRATIO")
  expect_identical(p$subratio, 0.4)
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "1")
  expect_error(plan("ribbon", NULL), "HVTI_TEMPLATE_STRICT")
})

fake_band <- function(type = "continuous", times = NULL) {
  x <- if (type == "continuous") c(1, 2, 3) else c("a", "b")
  m <- length(x) * max(1L, length(times))
  set.seed(3)
  list(var = "v", type = type, x = x, time = times, hat = seq_len(m) / 10,
       star = matrix(seq_len(m) / 10 + stats::rnorm(m * 4, sd = 0.02), m, 4))
}

test_that("a band frame is the full forest's value plus and minus 1.96 SE", {
  band <- fake_band(times = c(30, 90))
  fr <- hvtiRtemplates:::.band_frame(band, subratio = 0.3)
  se <- hvtiRtemplates:::.band_se(band$hat, band$star, 0.3)
  expect_equal(fr$upper - fr$hat, stats::qnorm(0.975) * se)
  expect_identical(nrow(fr), 6L)
  expect_identical(sort(unique(fr$time)), c(30, 90))
  expect_equal(fr$hat[fr$time == 30], band$hat[1:3])
  expect_equal(fr$hat[fr$time == 90], band$hat[4:6])
  at <- hvtiRtemplates:::.band_frame(band, subratio = 0.3, at = 2.5)
  expect_identical(nrow(at), 2L)
  expect_true(all(at$x == 2.5))
})

test_that("the band figures build, with ribbons or bars as chosen", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("patchwork")
  skip_if_not_installed("hvtiPlotR")
  layers <- function(p) vapply(p[[1]]$layers, function(l) class(l$geom)[1], "")
  bands <- list(v = fake_band(times = c(30, 90)), w = fake_band("categorical"))
  bands$w$var <- "w"
  ribbon <- hvtiRtemplates:::.plot_partial_bands(bands, 0.3, "ribbon", NULL, ncol = 2)
  bars <- hvtiRtemplates:::.plot_partial_bands(bands, 0.3, "bars", list(v = c(1.5, 2.5)), ncol = 2)
  expect_true("GeomRibbon" %in% layers(ribbon))
  expect_false("GeomRibbon" %in% layers(bars))
  expect_true("GeomErrorbar" %in% layers(bars))
  # patchworkGrob() opens a device when none is open and leaves it; hold a null one and close it.
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)
  for (p in list(ribbon, bars)) expect_s3_class(patchwork::patchworkGrob(p), "gtable")
})

test_that("a page mixing continuous and categorical survival panels shows one Time legend", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("patchwork")
  skip_if_not_installed("hvtiPlotR")
  bands <- list(v = fake_band(times = c(30, 90)), w = fake_band("categorical", times = c(30, 90)))
  bands$w$var <- "w"
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)
  for (style in c("ribbon", "bars")) {
    p <- hvtiRtemplates:::.plot_partial_bands(bands, 0.3, style, list(v = c(1.5, 2.5)), ncol = 2) &
      hvtiPlotR::theme_hv_manuscript(base_size = 12, legend.position = "top", legend.title = ggplot2::element_text())
    g <- patchwork::patchworkGrob(p)
    box <- g$grobs[[which(grepl("guide-box", g$layout$name))[1]]]
    expect_identical(sum(box$layout$name == "guides"), 1L, info = style)
  }
})

test_that("the Time legend labels the horizons to two decimals, as the partial figure does", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("patchwork")
  bands <- list(v = fake_band(times = c(0.953492154067233, 3.04605413203369)))
  p <- hvtiRtemplates:::.plot_partial_bands(bands, 0.3, "ribbon", NULL, ncol = 1)
  b <- ggplot2::ggplot_build(p[[1]])
  expect_identical(trimws(b$plot$scales$get_scales("colour")$get_labels()), c("0.95", "3.05"))
})

test_that("the importance-interval figure centres on the importance estimate, +/- 1.96 SE, ranked by it", {
  skip_if_not_installed("ggplot2")
  est <- c(a = 0.05, b = 0.30, c = -0.02)
  se <- c(c = 0.04, a = 0.10, b = 0.05) # deliberately not in the estimate's order
  p <- hvtiRtemplates:::.plot_vimp_intervals(est, se)
  expect_s3_class(ggplot2::ggplot_build(p), "ggplot_built")
  d <- p$data
  expect_equal(d$vimp[match(names(est), d$vars)], unname(est))
  expect_equal(d$upper - d$vimp, stats::qnorm(0.975) * unname(se[as.character(d$vars)]))
  expect_equal(d$vimp - d$lower, stats::qnorm(0.975) * unname(se[as.character(d$vars)]))
  expect_identical(levels(d$vars), c("c", "a", "b")) # ascending, so the largest plots at the top
  # Labelled by the lower bound: a is 0.05 - 0.196 < 0, b is 0.30 - 0.098 > 0.
  expect_identical(as.character(d$clear[match(c("a", "b", "c"), d$vars)]),
                   c("Interval not above zero", "Interval above zero", "Interval not above zero"))
})

test_that("the interval figure's axis names the importance it draws: anti-split VIMP, not permutation", {
  skip_if_not_installed("ggplot2")
  p <- hvtiRtemplates:::.plot_vimp_intervals(c(a = 0.1, b = 0.2), c(a = 0.01, b = 0.02))
  label <- ggplot2::get_labs(p)$x
  expect_match(label, "anti-split", fixed = TRUE)
  expect_no_match(label, "ermutation")
})
