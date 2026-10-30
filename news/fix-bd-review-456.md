* `bd` checks the dataset it built before registering it. A new Checks section, between the working file and
  Register, reports what the rebuild changed against the registered version, cross-tabs, the follow-up columns and
  the study's named checks (`CROSSTABS`, `EVENT`, `FOLLOWUP`, `CHECKS` and `PRINT_COLS`). The report shows field
  values such as ranges and cross-tab levels, because it prepares an analysis; patient rows and identifier values go to the
  console: `ID`, `KEY`, `JOIN_BY`, the new `OTHER_IDENTIFIERS` and any column named for an MRN, CCFID or SSN. `bd` no
  longer drops an identifier a job keeps from the built, so a patient can be found to correct follow-up; `read_job_data()`
  still drops them for analysis jobs. A finding never blocks registration. `bd` now needs hvtiRutilities 1.5.17
  and hvtiRdatabuild 0.3.3. Design: `dev/specs/2026-10-29-bd-checks-design.md`.  A draft
  render prints the SHA-256 of the file it wrote in its report, and a registering render registers only a file
  whose bytes that report names, rehashed at the registration boundary. It stops when run outside a Quarto render,
  when no draft report is found and when no report names these bytes. A draft may use a custom output name or a
  project `output-dir`. A draft whose check chunks did
  not all run (one set to `eval: false`, say, or deleted) reviews nothing, and a registering render stops naming
  them. A check that cannot run stops the render; a finding never does.
