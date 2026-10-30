* `dc-eda` draws the house descriptive variable list by default: the variables
  the SAS ODS tables report (`descriptive/dc.tables.ods.sas`), in their section
  order, and only the ones the dataset has. The report lists the columns it
  leaves out. The new study choice `VARIABLE_SET <- "all"` draws every column,
  as before; naming columns in `VARIABLES` works as it did. The list ships as
  `inst/extdata/ods-variables.csv`, and `dc-tables`'s commented `GROUPS` example
  is held to it by a test.
  A job brought up to date with `upgrade_job()` or `migrate_job()` whose
  `VARIABLES` is `NULL` also draws the list now, where it drew every column.
