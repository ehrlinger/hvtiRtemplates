- `dc-eda` and `dc-gfup` read the follow-up origin from the operation date. A new choice, `OPDATE <- "dt_surg"`,
  is passed to `hvtiPlotR::hv_followup_panels(opdate_col =)`, and `ORIGIN_YEAR` now defaults to `NULL`, so the
  origin is each patient's operation date less `OPYRS`, checked for every patient who has one. A patient with
  an operation year but no operation date cannot be checked: the window table counts them in a new row,
  "origin not checked (no operation date)", and the render warns. `dc-gfup` draws each `GROUP` on the
  cohort's checked origin, so a group whose operation dates are all missing keeps its facet. A study that sets
  `ORIGIN_YEAR` has it checked against the data, and the render stops when the two disagree. Until now a wrong
  origin, such as the template's old default of 1990 on a study counting from another year, slid every point
  along the axis and printed a "first operation" years before the study began, with no other symptom. The
  "Operation years and the close date" table gains an "origin" row saying where the year came from. A study
  with no operation date sets `OPDATE <- NULL` and keeps `ORIGIN_YEAR`, unchecked as before. A job brought
  forward with `upgrade_job()` keeps its own `ORIGIN_YEAR`, which is now checked: if it was wrong, the render
  stops and names the year the data give. `dc-gfup` now
  needs hvtiPlotR 2.8.23, as `dc-eda` already did.
