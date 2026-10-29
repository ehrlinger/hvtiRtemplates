* Compared groups in outcome curves now take `hvtiPlotR::hv_group_palette()`:
  black for one curve, then red, blue, teal, magenta and cyan. Until now the
  strata of the `ac` survival figures, and the horizons of the `rfs-explain`
  partial-dependence bands, were kept off red and blue and drew in bluish
  green, reddish purple and olive, of which the first two nearly merge for a
  reader with deuteranopia. Red and blue still mean the event and censored in
  figures that color by outcome. `ac` and `rfs-explain` now check for hvtiPlotR
  2.8.20.
