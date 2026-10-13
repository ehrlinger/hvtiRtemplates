eda_page <- function(section, d) {
  testthat::skip_if_not_installed("hvtiPlotR")
  testthat::skip_if_not_installed("patchwork")
  sec <- hvtiPlotR::hv_eda_pages(d, x_col = "year", section = section, vars = setdiff(names(d), "year"))
  plot(sec, ncol = 4, nrow = 4)[[1L]] & hvtiPlotR::theme_hv_manuscript(base_size = 8)
}

eda_data <- function() {
  # A category missing from the last year, as a rare one often is.
  data.frame(year = rep(2001:2010, each = 10L),
             valve = factor(c(rep(c("Bicuspid", "Tricuspid"), 45L), rep("Unicuspid", 5L), rep("Bicuspid", 5L))),
             age = seq(40, 89.5, by = 0.5))
}

test_that("a percent panel names every category it holds, in its own color, and drops the legend", {
  page <- hvtiRtemplates:::.eda_direct_labels(eda_page("percent", eda_data()))
  p <- page[[1L]]
  text <- Filter(function(l) inherits(l$geom, "GeomText"), p$layers)
  expect_length(text, 1L)
  labels <- text[[1L]]$aes_params$label
  expect_setequal(labels, c("Bicuspid", "Tricuspid", "Unicuspid"))
  # Each label's color is its band's fill.
  built <- ggplot2::ggplot_build(p)
  fills <- unique(built$data[[1L]]$fill)
  # ggplot2 stores the aesthetic under its British name whatever the call spelled.
  expect_true(all(unlist(lapply(list(text[[1L]]$aes_params), `[[`, "colour")) %in% fills))
  # Within the panel's height, in order, and apart.
  y <- text[[1L]]$data$y
  expect_true(all(y >= 0 & y <= 1))
  expect_true(all(diff(sort(y)) >= 0.08 - 1e-9))
  expect_identical(built$plot$theme$legend.position, "none")
})

test_that("a count panel is labeled in counts, and the year axis keeps about five labels", {
  page <- hvtiRtemplates:::.eda_direct_labels(eda_page("count", eda_data()))
  p <- page[[1L]]
  built <- ggplot2::ggplot_build(p)
  top <- max(built$data[[1L]]$ymax)
  y <- Filter(function(l) inherits(l$geom, "GeomText"), p$layers)[[1L]]$data$y
  expect_true(all(y > 0 & y <= top))
  expect_identical(built$layout$panel_params[[1L]]$x$get_breaks()[!is.na(built$layout$panel_params[[1L]]$x$get_breaks())],
                   c("2001", "2003", "2005", "2007", "2009"))
})

test_that("a continuous panel keeps its own x axis and gains no labels", {
  page <- hvtiRtemplates:::.eda_direct_labels(eda_page("continuous", eda_data()))
  p <- page[[1L]]
  expect_false(any(vapply(p$layers, function(l) inherits(l$geom, "GeomText"), logical(1L))))
  expect_false(ggplot2::ggplot_build(p)$layout$panel_params[[1L]]$x$is_discrete())
})

test_that(".eda_x_breaks keeps the first level and about n in all", {
  expect_identical(hvtiRtemplates:::.eda_x_breaks(letters[1:4]), letters[1:4])
  expect_identical(hvtiRtemplates:::.eda_x_breaks(as.character(1:16)), c("1", "5", "9", "13"))
})

test_that("measuring a label leaves the graphics devices as it found them", {
  # From no device at all, which is where the default device used to be opened and left.
  grDevices::graphics.off()
  expect_gt(hvtiRtemplates:::.eda_text_width_pt(c("Bicuspid", "Tricuspid"), 8), 0)
  expect_null(grDevices::dev.list())
  # With a device open, as during a render, it measures there and leaves it current.
  grDevices::pdf(NULL)
  mine <- grDevices::dev.cur()
  hvtiRtemplates:::.eda_text_width_pt("Bicuspid", 8)
  expect_identical(grDevices::dev.cur(), mine)
  grDevices::dev.off()
})
