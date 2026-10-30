* `bd` checks the dataset it built before registering it. A new Checks section, between the working file and
  Register, reports what the rebuild changed against the registered version, cross-tabs, the follow-up columns and
  the study's named checks (`CROSSTABS`, `EVENT`, `FOLLOWUP`, `CHECKS` and `PRINT_COLS`). Counts go in the report;
  the rows behind them go to the console. A finding never blocks registration. `bd` now needs hvtiRutilities 1.5.17
  and hvtiRdatabuild 0.3.3. Design: `dev/specs/2026-10-29-bd-checks-design.md`. A cross-tab takes only a column
  that reads as a category (logical, factor, whole numbers or text, at most 20 levels, not one value per row, no
  text that reads as a date) and never `ID` or a column of `KEY` or `JOIN_BY`, so its levels never put an
  identifier in the report. A registering render registers only the bytes the last draft render
  wrote, and stops if the build differs. A check that cannot run stops the render; a finding never does.
* The `dt` template is removed, one release after it arrived as in-flight: its checks are `bd`'s Checks section.
  A job scaffolded from it should move its choices into the study's `bd` job. The taxonomy keeps its `dt` row, so
  `job_census()` still counts the legacy SAS `dt` jobs.
