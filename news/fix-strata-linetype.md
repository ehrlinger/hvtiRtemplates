* The `ac` template's stratified survival and cumulative-hazard curves, and the `rfs-explain`
  horizon curves, now differ by line type and point shape as well as color, in the curves and in
  their legends, so the groups can be told apart on a grayscale printer. One curve stays solid.
  In `rfs-explain` this covers both the default partial-dependence pages and the confidence-band
  pages; the band pages' confidence bars stay solid. Seven groups, as many as the house group
  colors hold, each take their own line type and shape, and past seven no two groups share both.
  The first two group colors are of nearly equal luminance, so two strata drawn by color alone
  printed as the same gray.
