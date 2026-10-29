* `read_job_data()` now drops `masterid` and its numbered copies (`masterid0`, `masterid1`), and an SSN
  column whose name carries one source qualifier, such as `ssn_base`, `ssn_ssdi` or `ssn_num_base`. Under
  1.5.3 such a column was dropped only if every value it held was shaped like an SSN, so one malformed value
  let `ssn_base` through to the EDA report. A qualified name whose values are all an indicator's, a 0/1
  `ssn_missing` or a Y/N `ssn_flag`, stays.
* A WHERE condition that names one of these columns, or holds one of their values, in the study dataset or a
  joined one, is now refused as one on MRN is, so neither its error nor the saved selection carries the value.
