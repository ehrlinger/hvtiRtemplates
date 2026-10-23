- `dc-tables` carries a fuller variable grouping to start from, commented out
  above `GROUPS`: the house summary-table categories, with the SAS template's
  added where they differ, 26 groups of CORR database columns. Uncomment it and
  delete the groups and rows the study's data does not have. It sits outside the
  block `migrate_job()` rewrites, so a migrated job keeps it too.
