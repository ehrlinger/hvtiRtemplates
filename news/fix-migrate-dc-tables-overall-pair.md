* `migrate_job()` now migrates a `%desc_tab` job in the shape
  `tp.dc.tables.ods.sas` ships: each table written twice, overall (`by=`
  blank) and by group. It stopped on that pair before, so the mapping added
  for `%desc_tab` jobs never reached a typical one. The group becomes `BY`
  and the overall calls become the table's Overall column, which the report
  says. Calls naming two different groups still stop.
