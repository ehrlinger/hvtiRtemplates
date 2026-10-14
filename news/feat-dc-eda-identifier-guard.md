* `read_job_data()`, so every template, now drops direct identifiers beyond MRN
  and eMRN, unless one is the job's ID or a KEY column, including a KEY that names a joined column: `ccfid`, Social Security numbers
  (`ssn`, `soc_sec`, `social_security`, each with or without a `_no`, `_num` or `_number`
  suffix), and patient names and contact details held as text, by name (a 0/1 or Y/N
  contact indicator stays, however it is stored), and any column whose values are shaped like Social Security numbers,
  whatever its name. The data table lists every column dropped and notes the
  ones dropped by their values. `bd` drops the same columns from the built it
  writes, so `dc-eda` can no longer draw an SSN carried in from an SSDI join.
