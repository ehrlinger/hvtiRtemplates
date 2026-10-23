* The `dc-tables` group-heading parser now names an unclosed `/*` heading
  rather than failing with "subscript out of bounds" or folding the next group
  into the last. `migrate_job()` never reaches it today, because the comment
  masker treats an unclosed `/*` as running to end of file and the migration
  already stops for want of a `%desc_tab` call. The guard keeps a later parser
  change from reopening the confusing error.
