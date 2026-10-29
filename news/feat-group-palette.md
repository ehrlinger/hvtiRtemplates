* Compared groups in outcome curves now take `hvtiPlotR::hv_group_palette()`:
  black for one curve; two to five groups take red, blue, teal, magenta and
  cyan, and six or seven all switch to Paul Tol's muted colors. Until now the
  strata of the `ac` survival figures, and the horizons of the `rfs-explain`
  partial-dependence bands, were kept off red and blue and drew in bluish
  green, reddish purple and olive, of which the first two nearly merge for a
  reader with deuteranopia. Red and blue still mean the event and censored in
  figures that color by outcome. `ac` and `rfs-explain` now check for hvtiPlotR
  2.8.20, and so does the shared color helper, so a job copied into a study
  before this change stops with an upgrade message on an older hvtiPlotR
  instead of failing mid-render.
