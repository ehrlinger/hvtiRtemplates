# dc-eda's pages are grids of small panels, four to a row, so they use 8 pt type
# where a single figure uses 12. A legend over each panel does not fit there: a
# row of category names runs past the page edge. So a stacked panel, percent or
# count, names its categories directly instead: each category that appears in
# any bar is written in its own colour beside the panel, at the middle of its
# average band, and the legend is dropped. Labels too close to read are pushed
# apart in order. A discrete year axis keeps about five labels, which otherwise
# print over one another. A panel without a fill, the continuous section's, only
# loses its legend.

# The labels for one stacked panel: y position, text and colour, or NULL.
.eda_panel_labels <- function(p, gap = 0.08) {
  if (!all(c("x", "fill") %in% names(p$data))) return(NULL)
  b <- ggplot2::ggplot_build(p)
  bars <- b$data[[1L]]
  if (!all(c("ymin", "ymax", "fill") %in% names(bars)) || !nrow(bars)) return(NULL)
  top <- max(bars$ymax)
  gap <- gap * top
  pos <- tapply((bars$ymin + bars$ymax) / 2, bars$fill, mean)
  scale <- b$plot$scales$get_scales("fill")
  levels <- scale$get_breaks()
  colour <- names(pos)
  label <- as.character(levels[match(colour, scale$map(levels))])
  o <- order(pos)
  y <- unname(pos[o])
  label <- label[o]
  colour <- colour[o]
  for (i in seq_along(y)[-1L]) y[i] <- max(y[i], y[i - 1L] + gap)
  if (max(y) > top) y <- y - (max(y) - top)
  for (i in rev(seq_along(y))[-1L]) y[i] <- min(y[i], y[i + 1L] - gap)
  data.frame(y = y, label = label, colour = colour)
}

# About `n` evenly spaced labels from a discrete axis's levels, the first kept.
.eda_x_breaks <- function(levels, n = 5L) {
  if (length(levels) <= n) return(levels)
  levels[seq(1L, length(levels), by = ceiling(length(levels) / n))]
}

.eda_text_width_pt <- function(label, size_pt) {
  if (!length(label)) return(0)
  max(vapply(label, function(l) {
    grob <- grid::textGrob(l, gp = grid::gpar(fontsize = size_pt, fontface = "bold"))
    grid::convertWidth(grid::grobWidth(grob), "pt", valueOnly = TRUE)
  }, numeric(1L)))
}

# Every panel of a patchwork page, labelled as above. One right margin, wide
# enough for the page's longest label, keeps the panels the same width.
.eda_direct_labels <- function(page, size_pt = 8) {
  for (pkg in c("ggplot2", "patchwork")) {
    if (!requireNamespace(pkg, quietly = TRUE)) stop("The ", pkg, " package is needed to draw the figure.", call. = FALSE)
  }
  labels <- lapply(seq_along(page), function(j) .eda_panel_labels(page[[j]]))
  width <- .eda_text_width_pt(unlist(lapply(labels, `[[`, "label")), size_pt) + 6
  for (j in seq_along(page)) {
    p <- page[[j]]
    x <- ggplot2::ggplot_build(p)$layout$panel_params[[1L]]$x
    if (inherits(x$scale, "ScaleDiscrete") || isTRUE(x$is_discrete())) {
      levels <- x$get_labels()
      p <- suppressMessages(p + ggplot2::scale_x_discrete(breaks = .eda_x_breaks(levels)))
      if (!is.null(labels[[j]])) {
        l <- labels[[j]]
        p <- p + ggplot2::annotate("text", x = length(levels) + 0.7, y = l$y, label = l$label, colour = l$colour,
                                   hjust = 0, size = size_pt / ggplot2::.pt, fontface = "bold")
      }
      p <- suppressMessages(p + ggplot2::coord_cartesian(xlim = c(0.5, length(levels) + 0.5), expand = FALSE,
                                                         clip = "off"))
    }
    page[[j]] <- p + ggplot2::theme(legend.position = "none",
                                    plot.margin = ggplot2::margin(5.5, if (is.null(labels[[j]])) 5.5 else width, 5.5, 5.5, "pt"))
  }
  page
}
