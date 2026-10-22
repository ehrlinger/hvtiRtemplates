* `dc-tables` has a `TABLE_ORIENTATION` choice for the Word table's page,
  passed to `hvtiRtables::hv_man_table_save()`. `"auto"`, the default, turns
  a table too wide for portrait landscape, as before; `"portrait"` or
  `"landscape"` always wins. The job now needs hvtiRtables 1.0.11.
