* The `ac` template's manuscript survival figure can mark confidence limits at chosen times, as the SAS figures do.
  `CI_TIMES` draws a bar at each time given, spanning the `CLEVEL` limits the horizon tables report there, and
  `CI_BAND` (still `TRUE` by default) controls the continuous band, so a figure carries the band, the bars, both or
  neither. `CI_BAND <- FALSE` with `CI_TIMES` set gives the SAS figure's bars alone. A time before the first event or
  past the end of follow-up draws no bar.
