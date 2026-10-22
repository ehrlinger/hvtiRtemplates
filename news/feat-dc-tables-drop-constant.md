* `dc-tables` leaves out a row whose every recorded value is the same, such as
  a finding every patient has by inclusion, and names each one in a note under
  the report's table. A constant binary row no longer stops the job.
  `DROP_CONSTANT <- FALSE` keeps every row.
