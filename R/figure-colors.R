# Colors for compared groups, such as a survival figure's strata: hvtiPlotR::hv_group_palette(),
# black for a single curve, then red, blue, teal, magenta and cyan. Red and blue mean the event and
# censored only in a figure that draws those roles (hvtiPlotR::hv_role_palette()); in an outcome
# curve the colors stand for groups, and red and blue are the two a colorblind reader best tells
# apart. Decided 2026-10-29, after the house rule had kept them off every curve.
#
# More groups than that palette holds take grDevices' "Dark 3" colors with a warning, as
# hvtiPlotR::scale_color_hv() falls back for the same limit, rather than stopping the figure.
#
# Returns a character vector of hex colors named by `levels`, for a manual scale's `values`.
.group_colors <- function(levels) {
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
