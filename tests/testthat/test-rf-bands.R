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

test_that("the SE is the jackknife SE extract.subsample() reports", {
  skip_if_not_installed("randomForestSRC", "3.9.0")
  e <- new.env()
  utils::data("veteran", package = "randomForestSRC", envir = e)
  Surv <- survival::Surv # rfsrc() parses the formula text and does not accept survival::Surv  # nolint: object_name_linter
  f <- randomForestSRC::rfsrc(Surv(time, status) ~ ., e$veteran, ntree = 30,
                              importance = "none", seed = -1)
  set.seed(2)
  s <- randomForestSRC::subsample(f, B = 4, importance = "anti", verbose = FALSE)
  hat <- s$vmp[[1]][, 1]
  star <- sapply(s$vmpS, function(v) v[[1]][[1]])
  expect_equal(unname(hvtiRtemplates:::.band_se(hat, star, s$subratio)),
               unname(randomForestSRC::extract.subsample(s, standardize = FALSE)$se.jk.Z))
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
  expect_message(suppressWarnings(plan("ribbon", list(karno = 50))), "BAND_AT is ignored")
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "")
  # veteran has 128 deaths, so 40% of them is about 51, under the floor of 100.
  expect_warning(p <- plan("ribbon", NULL), "SUBRATIO")
  expect_identical(p$subratio, 0.4)
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "1")
  expect_error(plan("ribbon", NULL), "HVTI_TEMPLATE_STRICT")
})
