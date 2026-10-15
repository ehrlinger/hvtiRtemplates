* `dc-eda` draws against the surgery date by default, `X_VAR <- "dt_surg"`,
  rather than a `year` column no study dataset carries, which stopped a fresh
  job with "Unknown EDA column(s): year". A date column is drawn as a decimal
  calendar year: whole years for the percent and count bars, the point in the
  year for the continuous panels. Any other column is drawn as it is. The new
  `X_LABEL` choice titles the axis, "Year of operation" by default; set it
  and `X_VAR` when time 0 is not an operation, such as an enrollment date. A
  missing `X_VAR` column now stops with "Set X_VAR in the study choices to
  the study's reference date or year column."
