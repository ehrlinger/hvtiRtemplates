* `rfs-fit` and `rfs-explain` draw patients who had the event in red and those censored
  in blue, as every house figure does, under one "Event" / "Censored" key. They had
  taken ggplot's default colors, which drew the censored patients red.
* `ac` draws a single survival curve in black rather than ggplot's default red, and
  strata in colors that are never the event's red or censored blue, so no stratum
  reads as the deaths.
