* `dc-eda` draws a short cohort in months. A new study choice, `X_UNIT` (`"auto"`, `"year"` or `"month"`), says what a
  date `X_VAR` is drawn in; `"auto"` draws months when the dates span less than three years. A six-month cohort drew
  one bar and a 2026.0 to 2026.5 axis; in months its percent and count bars are calendar months, in order, and its
  continuous panels a date axis. While `X_LABEL` is still `"Year of operation"`, a monthly axis reads
  `"Month of operation"`. A longer cohort, and an `X_VAR` that is not a date, draw as before.
