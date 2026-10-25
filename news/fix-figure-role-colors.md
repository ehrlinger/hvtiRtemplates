* `rfs-fit` and `rfs-explain` draw patients who had the event in red and those censored
  in blue, as every house figure does, under one "Event" / "Censored" key, with the loess smooth in black. They had
  taken ggplot's default colors, which drew the censored patients red.
* `ac` draws a single survival curve in black rather than ggplot's default red, and
  strata in colors that are never the event's red or censored blue, so no stratum
  reads as the deaths.
* `dc-gfup` and `dc-eda` captions call the deaths "red crosses", matching hvtiPlotR 2.8.18, whose
  event color is Paul Tol's red `#CC3311` rather than vermilion.
