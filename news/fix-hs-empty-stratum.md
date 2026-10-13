* `hs-setup` accepts a cohort with no one in a life-table stratum, all female or
  all white, as `us_matched()` does. Under the default `MALE_LEVEL <- 1`, an
  all-zero `male` column stopped, because the level never appeared in it. A
  level the column could take is now accepted: 0 or 1 in a 0/1 column, or a
  level a factor declares. An empty `OTHER_LEVELS` counts no one as non-white. A
  level the column could not take still stops, because it is a typo (#183).
