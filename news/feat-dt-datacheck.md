* New `dt` template, `00_datasets/dt.qmd`: the data check a programmer runs after a `bd` build and
  before registering it, scaffolded as `dt.<subject>.<type>.qmd`. It reads the working file `bd`
  writes, `datasets/<DATASET_ID>.rds`, and checks it in four sections: what the rebuild changed against
  the version registered now, compared by value and joined on `KEY` through
  `hvtiRdatabuild::compare_built()`, so a rebuild that keeps the shape and changes every event
  indicator is reported, not passed; cross-tabs with a missing value as a level of its own; the
  follow-up columns through `followup_check()`; and the study's named checks, written
  `condition ~ "Label"` as `bd`'s `EXCLUDE` is. A comparison build, under a `DATASET_ID` that is not
  the study's dataset, is compared against the study's dataset and the report says so. The report
  holds counts only: the rows behind a check and the patients on one side of a rebuild go to the
  console, never into the HTML. A check never writes. It needs `hvtiRutilities::proc_print()`
  (hvtiRutilities#262) and hvtiRdatabuild 0.3.3. Design: `dev/specs/2026-10-27-dt-datacheck-design.md`.
