eda_page <- function(section, d) {
  testthat::skip_if_not_installed("hvtiPlotR")
  testthat::skip_if_not_installed("patchwork")
  sec <- hvtiPlotR::hv_eda_pages(d, x_col = "year", section = section, vars = setdiff(names(d), "year"))
  plot(sec, ncol = 2, nrow = 4)[[1L]] & hvtiPlotR::theme_hv_manuscript(base_size = 8)
}

eda_data <- function() {
  # A category missing from the last year, as a rare one often is.
  data.frame(year = rep(2001:2010, each = 10L),
             valve = factor(c(rep(c("Bicuspid", "Tricuspid"), 45L), rep("Unicuspid", 5L), rep("Bicuspid", 5L))),
             age = seq(40, 89.5, by = 0.5))
}

has_text <- function(p) any(vapply(p$layers, function(l) inherits(l$geom, "GeomText"), logical(1L)))

test_that("a categorical panel names no category, in a legend or beside it, and keeps its colors", {
  for (section in c("percent", "count")) {
    p <- hvtiRtemplates:::.eda_page_panels(eda_page(section, eda_data()))[[1L]]
    built <- ggplot2::ggplot_build(p)
    expect_identical(built$plot$theme$legend.position, "none", info = section)
    expect_false(has_text(p), info = section)
    # One house color per category still tells the three apart.
    expect_length(unique(built$data[[1L]]$fill), 3L)
    # No gutter is held for names: the margin is the house theme's own.
    expect_identical(as.numeric(ggplot2::ggplot_build(p)$plot$theme$plot.margin),
                     as.numeric(hvtiPlotR::theme_hv_manuscript(base_size = 8)$plot.margin), info = section)
  }
})

test_that("the year axis keeps about five labels across the panel's full width", {
  p <- hvtiRtemplates:::.eda_page_panels(eda_page("count", eda_data()))[[1L]]
  x <- ggplot2::ggplot_build(p)$layout$panel_params[[1L]]$x
  expect_identical(x$get_breaks()[!is.na(x$get_breaks())], c("2001", "2003", "2005", "2007", "2009"))
  expect_equal(x$continuous_range, c(0.5, 10.5))
})

test_that("a continuous panel keeps its own x axis and only loses its legend", {
  p <- hvtiRtemplates:::.eda_page_panels(eda_page("continuous", eda_data()))[[1L]]
  expect_false(has_text(p))
  expect_false(ggplot2::ggplot_build(p)$layout$panel_params[[1L]]$x$is_discrete())
  expect_identical(ggplot2::ggplot_build(p)$plot$theme$legend.position, "none")
})

test_that(".eda_x_breaks keeps the first level and about n in all", {
  expect_identical(hvtiRtemplates:::.eda_x_breaks(letters[1:4]), letters[1:4])
  expect_identical(hvtiRtemplates:::.eda_x_breaks(as.character(1:16)), c("1", "5", "9", "13"))
})
