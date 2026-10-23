- `dc-gfup` gains a **Potential follow-up** table. For each panel it shows the
  follow-up recorded against the follow-up the close date allows, in
  patient-years, the percent of potential achieved, and the longest of each.
  It also counts patients with follow-up recorded past the close date. A
  patient who reached the panel's event counts as followed completely.
- The follow-up table in `dc-gfup` and in `dc-eda`'s follow-up section adds
  the 75th and 90th percentiles and `total`, the follow-up summed in
  patient-years.
- `dc-gfup` now checks that its figures draw `EVENT`, the event its table
  checks. A job checking reoperation in the table while drawing only deaths
  had shown no sign of the mismatch. A draft render now says so in a callout
  and marks itself a draft; a final render stops.
- A `dc-gfup` `PANELS` entry takes an optional `levels`, naming its two groups
  with the censored group first, for a non-fatal event drawn without death
  (`levels = c("No reoperation", "Reoperation")`). The legend and the caption
  use those names in place of Alive and Dead.
