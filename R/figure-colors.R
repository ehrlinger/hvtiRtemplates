# Colors for compared groups, such as a survival figure's strata: hvtiPlotR::hv_group_palette(),
# black for a single curve; two to five groups take red, blue, teal, magenta and cyan, and six or
# seven all switch to Paul Tol's muted colors. Red and blue mean the event and censored only in a
# figure that draws those roles (hvtiPlotR::hv_role_palette()); in an outcome curve the colors
# stand for groups, and red and blue are the two a colorblind reader best tells apart. Decided
# 2026-10-29, after the house rule had kept them off every curve.
#
# More groups than that palette holds take grDevices' "Dark 3" colors with a warning, as
# hvtiPlotR::scale_color_hv() falls back for the same limit, rather than stopping the figure.
#
# A job copied into a study before 2026-10-29 guards an older hvtiPlotR but still calls this
# helper from the installed package, so the check for hv_group_palette() lives here too: without
# it such a job passes its own guard and then fails mid-render on an unexported object.
#
# Returns a character vector of hex colors named by `levels`, for a manual scale's `values`.
.group_colors <- function(levels) {
  if (!.has_group_palette())
    stop("This figure needs hvtiPlotR >= 2.8.20 for hv_group_palette(); ", utils::packageVersion("hvtiPlotR"),
         " is installed.\nUpdate it, then re-render.", call. = FALSE)
  levels <- as.character(levels)
  tryCatch(
    hvtiPlotR::hv_group_palette(levels),
    hv_group_palette_capacity = function(e) {
      warning(length(levels), " groups are more than the house colors tell apart; drawn in ",
              "grDevices::hcl.colors(\"Dark 3\").", call. = FALSE)
      stats::setNames(grDevices::hcl.colors(length(levels), "Dark 3"), levels)
    }
  )
}

# A function of its own so a test can stand in an hvtiPlotR that predates the palette.
.has_group_palette <- function() {
  "hv_group_palette" %in% getNamespaceExports("hvtiPlotR")
}

# Line types and point shapes for the same groups, so color is never the only channel and
# the groups still read apart on a grayscale printer: the first group, or a single curve,
# is solid with a filled circle. Seven of each, as many as hv_group_palette() has colors.
# Past seven the shapes shift by one each time the line types come round again, so no two
# groups share both: the colors there are a fallback that may not tell them apart.
#
# Returns a vector named by `levels`, for a manual scale's `values`.
.group_linetypes <- function(levels) {
  levels <- as.character(levels)
  # "331313" is dash-dot-dot, the seventh pattern none of R's named line types draws.
  types <- c("solid", "dashed", "dotted", "dotdash", "longdash", "twodash", "331313")
  stats::setNames(types[(seq_along(levels) - 1L) %% 7L + 1L], levels)
}

.group_shapes <- function(levels) {
  levels <- as.character(levels)
  i <- seq_along(levels) - 1L
  stats::setNames(c(16L, 17L, 15L, 3L, 4L, 8L, 18L)[(i + i %/% 7L) %% 7L + 1L], levels)
}
