* `read_job_data()` now drops `masterid` and its numbered copies (`masterid0`, `masterid1`), and an SSN
  column whose name carries one source qualifier, such as `ssn_base` or `ssn_ssdi`. Under 1.5.3 such a
  column was dropped only if every value it held was shaped like an SSN, so one malformed value let
  `ssn_base` through to the EDA report.
