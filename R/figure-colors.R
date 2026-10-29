# Colors for compared groups, such as a survival figure's strata. In every house figure red
# means the event and blue censored (hvtiPlotR::hv_role_palette()), so a group drawn in either
# reads as the deaths or as the censored. The groups therefore take the role rotation with
# those two left out, then Paul Tol's muted colors past it, exactly as the other levels of a
# figure with a role do: a placeholder event level asks hv_role_palette() for that, and is
# dropped. A single curve has nothing to tell apart, and is black.
#
# More groups than that palette holds take grDevices' "Dark 3" colors with a warning, as
# hvtiPlotR::scale_color_hv() falls back for the same limit, rather than stopping the figure.
#
# Returns a character vector of hex colors named by `levels`, for a manual scale's `values`.
.group_colors <- function(levels) {
  levels <- as.character(levels)
  if (length(levels) == 1L) return(stats::setNames("#000000", levels))
  tryCatch(
    hvtiPlotR::hv_role_palette(c("\u0001event", levels), event = "\u0001event")[-1L],
    hv_role_palette_capacity = function(e) {
      warning(length(levels), " groups are more than the house colors tell apart; drawn in ",
              "grDevices::hcl.colors(\"Dark 3\"), whose colors may include a red or a blue.", call. = FALSE)
      stats::setNames(grDevices::hcl.colors(length(levels), "Dark 3"), levels)
    }
  )
}

# Line types and point shapes for the same groups, so color is never the only channel and
# the groups still read apart on a grayscale printer: the first group, or a single curve,
# is solid with a filled circle. Past six groups the sequence repeats.
#
# Returns a vector named by `levels`, for a manual scale's `values`.
.group_linetypes <- function(levels) {
  levels <- as.character(levels)
  types <- c("solid", "dashed", "dotted", "dotdash", "longdash", "twodash")
  stats::setNames(rep_len(types, length(levels)), levels)
}

.group_shapes <- function(levels) {
  levels <- as.character(levels)
  stats::setNames(rep_len(c(16L, 17L, 15L, 3L, 4L, 8L), length(levels)), levels)
}
