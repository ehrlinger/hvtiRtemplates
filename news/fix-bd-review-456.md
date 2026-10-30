* `bd` checks the dataset it built before registering it. A new Checks section, between the working file and
  Register, reports what the rebuild changed against the registered version, cross-tabs, the follow-up columns and
  the study's named checks (`CROSSTABS`, `EVENT`, `FOLLOWUP`, `CHECKS` and `PRINT_COLS`). Counts go in the report;
  the rows behind them go to the console. A finding never blocks registration. `bd` now needs hvtiRutilities 1.5.17
  and hvtiRdatabuild 0.3.3. Design: `dev/specs/2026-10-29-bd-checks-design.md`. A cross-tab's levels are values, so
  they print in the console and never in the report, which shows each pair's shape: the levels of each column, the
  cells, the cells under 5 and the missing values. Any column of the built dataset may be cross-tabulated. A draft
  render prints the SHA-256 of the file it wrote in its report, and a registering render registers only a file
  whose bytes that report names, rehashed at the registration boundary. It stops when run outside a Quarto render,
  when no draft report sits beside the job and when the report names other bytes. A draft whose check chunks did
  not all run (one set to `eval: false`, say, or deleted) reviews nothing, and a registering render stops naming
  them. A check that cannot run stops the render; a finding never does.
