* `dc-tables` reports the house ODS list by default. `GROUPS <- NULL`, now the template's default, draws every section
  the SAS ODS tables report, keeping only the columns the dataset has, under the dataset's own spelling, as `dc-eda`'s
  `VARIABLE_SET <- "ods"` does: nobody sorts the list against the data by hand. The report counts the columns and
  names the dataset's columns left out, and `BY` is never also a row. Named `GROUPS` work as before, a name missing
  from the data still stops the table, and jobs that already set `GROUPS` keep it.
