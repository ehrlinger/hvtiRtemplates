* `bd`'s report no longer prints the range of each numeric column. A range is two values from the data, and a
  numeric column that is not `ID` or `KEY`, such as a second record number or a date kept as SAS day numbers, put
  two of them in the report that is meant to hold counts only. The Columns table keeps each column's type and
  missing count; the ranges go to the console, as the Checks section's rows do.
