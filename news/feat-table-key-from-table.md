- `dc-tables` builds each table's Key from what the table prints. Every
  abbreviation the study's list (`_study.yml`, then the group defaults) can
  expand is defined under the table, and `ABBREVIATIONS` adds to or overrides
  it. Until now the Key was only what a job typed into `ABBREVIATIONS`, which a
  new job starts empty, so a table printing NYHA went out with no Key. A
  table's abbreviations belong in its own Key, not only in the manuscript's
  Abbreviations list, which is for the text. An acronym the table prints that
  nothing expands is named in a warning, and a `STDDIFF` column's "Std. Diff."
  is keyed as standardized difference.
