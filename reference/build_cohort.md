# Cut a study cohort from a master, recording who was dropped and why

The cohort step of a `bd` build job. It keeps the master rows a study is
made of and returns, beside them, an attrition table: one row per step,
with the rows each step removed and the patients left. A step is named
by its reason, never by its rule's text, so the table is safe to print
whatever a rule names.

## Usage

``` r
build_cohort(data, exclude = NULL, cohort = NULL, join_by = NULL, id = "ccfid")
```

## Arguments

- data:

  A data frame read from the master.

- exclude:

  `NULL`, or a list of rules written `condition ~ "Reason"`, applied in
  order to the rows still kept. Each condition is evaluated against the
  data, with the rule's own environment for anything else it names, and
  must give `TRUE` or `FALSE` for every row. A row whose condition is
  missing is **not** excluded, as SAS `if ... then delete` and an
  hvtiRdatabuild analysis set treat it, and the number of such rows is
  counted. A downstream job's `WHERE` drops such rows instead.

- cohort:

  `NULL`, or the path to a CSV cohort list, such as a REDCap export,
  carrying the `join_by` columns. Only master rows matched by a list row
  are kept. Dates are written YYYY-MM-DD. A list may carry `exclude` (1
  to exclude) and `reason` columns; each reason becomes a step of its
  own. A list's reasons are printed in the report, so they must be
  categories (such as "Redo operation"), never free text, names or
  dates.

- join_by:

  The columns that match a cohort-list row to a master row. Used only
  with `cohort`.

- id:

  The patient identifier column, used to count patients.

## Value

A list:

- `data`, the kept rows, with the master's columns;

- `attrition`, a data frame with one row per step and the columns
  `step`, `reason`, `rows_before`, `removed`, `missing_condition`,
  `rows_after` and `patients_after`.

## Details

Identifiers are compared as text, so `100000` in the master matches
`"100000"` in a list. No message names a data value: list rows that
matched no master row are counted, never listed, and a rule that fails
is named by its number and reason.

## Examples

``` r
d <- data.frame(ccfid = c("S1", "S2", "S3", "S4"), age = c(17, 45, NA, 80),
                redo = c(0, 0, 0, 1))
cut <- build_cohort(d, exclude = list(age < 18 ~ "Under 18",
                                      redo == 1 ~ "Redo operation"))
# One row per step: rows removed, rows whose condition was missing and so
# kept (S3, with no age), and the patients left.
cut$attrition
#>      step         reason rows_before removed missing_condition rows_after
#> 1  master      Rows read           4       0                 0          4
#> 2 exclude       Under 18           4       1                 1          3
#> 3 exclude Redo operation           3       1                 0          2
#>   patients_after
#> 1              4
#> 2              3
#> 3              2
cut$data
#>   ccfid age redo
#> 1    S2  45    0
#> 2    S3  NA    0
```
