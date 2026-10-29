# Pages for a free-size figure whose panel count follows the study: one panel
# per selected predictor, or one facet per variable. The panels go in a grid
# at most `page_width` wide, as many rows as fit in `page_height` make a page,
# and the rest go on the next page. A panel larger than the page is shrunk to
# it. Unlike hvtiPlotR::hv_panel_size() this never refuses: a study's variable
# count must not stop a job (dev/specs/2026-10-13-figure-standard-design.md).
#
# Returns one element per page: `index`, the panels' positions in seq_len(n);
# `ncol`; and the page's `width` and `height` in inches.
.figure_pages <- function(n, panel_width = 3.25, panel_height = 3,
                          page_width = 6.5, page_height = 9) {
  stopifnot(length(n) == 1L, n >= 0)
  if (n == 0) return(list())
  panel_width <- min(panel_width, page_width)
  panel_height <- min(panel_height, page_height)
  # The tolerance keeps two 3.25 in panels on a 6.5 in page.
  ncol <- max(1L, floor(page_width / panel_width + 1e-9))
  nrow <- max(1L, floor(page_height / panel_height + 1e-9))
  pages <- split(seq_len(n), ceiling(seq_len(n) / (ncol * nrow)))
  lapply(unname(pages), function(index) {
    cols <- min(ncol, length(index))
    list(index = index, ncol = cols, width = cols * panel_width,
         height = ceiling(length(index) / cols) * panel_height)
  })
}

# A ggRandomForests partial-dependence result (gg_partial_rfsrc or
# gg_partial_varpro) cut to the variables `vars`, so plot() draws one page of
# its panels. Both keep a `continuous` and a `categorical` frame keyed by
# `name`; the class and attributes are kept.
.partial_subset <- function(x, vars) {
  for (part in names(x)) {
    frame <- x[[part]]
    if (is.data.frame(frame) && "name" %in% names(frame)) {
      x[[part]] <- frame[frame$name %in% vars, , drop = FALSE]
    }
  }
  x
}

# ggRandomForests draws a survival partial's horizons by color alone, lines and boxes alike. Each
# panel that does gets a line type per horizon as well, under the same "Time" title and labels so
# its legend stays one key, and the figure still reads apart printed in grayscale. `fig` is what
# plot() returns for a gg_partial_rfsrc: one ggplot, or a patchwork of a continuous and a
# categorical panel. A panel with no horizon is returned as it is.
.partial_horizon_keys <- function(fig) {
  key <- function(p) {
    if (!inherits(p, "ggplot") || !".time_factor" %in% names(p$data)) return(p)
    lv <- levels(p$data$.time_factor)
    p + ggplot2::aes(linetype = !!rlang::sym(".time_factor")) +
      ggplot2::scale_linetype_manual(values = .group_linetypes(lv), name = "Time",
                                     labels = format(round(as.numeric(lv), 2), trim = TRUE))
  }
  if (!inherits(fig, "patchwork")) return(key(fig))
  for (i in seq_along(fig)) fig[[i]] <- key(fig[[i]])
  fig
}

# A report shows each figure half as large again as the copy saved for the
# manuscript: 9 by 6 in for the 6 by 4 standard, at the same 12 pt type, so the
# plot gets more room in the report's 2000 px body while the saved copy still
# fits the printed page. Applied to the chunk options a template writes for a
# paged figure; save_figure() keeps the page size (2026-10-23).
.report_size <- function(inches) inches * 1.5
