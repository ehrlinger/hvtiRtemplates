* `migrate_job()` now migrates a `%desc_tab` job in the shape
  `tp.dc.tables.ods.sas` ships: each table written twice, overall (`by=`
  blank) and by group. It stopped on that pair before, so the mapping added
  for `%desc_tab` jobs never reached a typical one. The group becomes `BY`
  and the overall calls become the table's Overall column, which the report
  says, but only when every patient has a group: where the registered data
  has patients with no `BY` value, which SAS's overall calls counted and the
  R table's Overall column leaves out, the report lists it as unresolved with
  the count instead. A group variable an overall call summarized as a row is
  taken out of `GROUPS`, since its levels are now the columns. Calls naming
  two different groups still stop.
