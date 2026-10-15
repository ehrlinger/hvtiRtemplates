# dc-eda's pages are grids of small panels, two to a row on the 6.5 by 9 in
# page. A panel names none of its categories, in a legend or beside it: either
# took width the bars needed, and an EDA page is for seeing the data (John,
# 2026-10-15). The house colors tell the categories apart, and the report's
# frequency table names them. A discrete year axis keeps about five labels,
# which otherwise print over one another.

# About `n` evenly spaced labels from a discrete axis's levels, the first kept.
.eda_x_breaks <- function(levels, n = 5L) {
  if (length(levels) <= n) return(levels)
  levels[seq(1L, length(levels), by = ceiling(length(levels) / n))]
}

# Every panel of a patchwork page without its legend, and a discrete x axis
# thinned to about five labels across the panel's full width.
.eda_page_panels <- function(page) {
  for (pkg in c("ggplot2", "patchwork")) {
    if (!requireNamespace(pkg, quietly = TRUE)) stop("The ", pkg, " package is needed to draw the figure.", call. = FALSE)
  }
  for (j in seq_along(page)) {
    p <- page[[j]]
    x <- ggplot2::ggplot_build(p)$layout$panel_params[[1L]]$x
    if (inherits(x$scale, "ScaleDiscrete") || isTRUE(x$is_discrete())) {
      levels <- x$get_labels()
      p <- suppressMessages(p + ggplot2::scale_x_discrete(breaks = .eda_x_breaks(levels)))
      p <- suppressMessages(p + ggplot2::coord_cartesian(xlim = c(0.5, length(levels) + 0.5), expand = FALSE))
    }
    page[[j]] <- p + ggplot2::theme(legend.position = "none")
  }
  page
}
