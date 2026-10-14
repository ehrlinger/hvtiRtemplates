* `read_job_data()`, so every template, now drops direct identifiers beyond MRN
  and eMRN, unless one is the job's ID or a KEY column: `ccfid`, Social Security numbers
  (`ssn`, `soc_sec`, `social_security`), patient names and contact details held as text, by
  name, and any column whose values are shaped like Social Security numbers,
  whatever its name. The data table lists every column dropped and notes the
  ones dropped by their values. `bd` drops the same columns from the built it
  writes, so `dc-eda` can no longer draw an SSN carried in from an SSDI join.
