- `sid-clusters` registers a new set's cluster letters as `.rds`, not CSV,
  so a patient ID with leading zeros keeps them and later jobs join on it.
  It had stopped every study keyed on a zero-padded ID before writing
  `sid-clusters.rds`, which also blocked `sid-stability` (#618). A set
  registered as CSV before keeps its CSV and its read-back check.
