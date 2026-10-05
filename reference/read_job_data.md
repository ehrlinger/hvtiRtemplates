# Read a job's data, keep its rows, and record what was done

The shared data step of every analysis template. It reads a registered
dataset (or an hvtiRdatabuild analysis set), resolves the patient
identifier, drops the medical record number columns, keeps the rows
`where` selects and checks that rows are unique on `key`.

## Usage

``` r
read_job_data(
  cfg,
  dataset = "study",
  analysis_set = NULL,
  where = NULL,
  id = "ccfid",
  key = id
)
```

## Arguments

- cfg:

  Study configuration, from
  [`study_config`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.html).

- dataset:

  Name of a dataset registered in `_study.yml`; `"study"` is the built
  dataset.

- analysis_set:

  Name of an analysis set written by
  [`hvtiRdatabuild::write_analysis_set()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/write_analysis_set.html),
  or `NULL` to read `dataset` whole. Analysis sets derive from `"study"`
  only.

- where:

  Rows to keep: `NULL`, one condition from
  [`quote()`](https://rdrr.io/r/base/substitute.html), or a list from
  [`rlang::exprs()`](https://rlang.r-lib.org/reference/defusing-advanced.html),
  all of which must hold. Conditions follow
  [`dplyr::filter()`](https://dplyr.tidyverse.org/reference/filter.html):
  a row where a condition is `NA` is dropped. A value from outside the
  data, written `.env$min_age` or as a name that is not a column, is
  fixed into the condition when the data are read, so the recorded
  condition rebuilds the same rows wherever it runs. Only a plain name
  and `.env$x` are fixed in; `x$y` and `x@y` are kept as written, and a
  name for a function stays a name. Such a value must be a vector,
  `NULL`, a symbol or a call; a data frame, list, environment or S4
  object stops, since it would be saved whole. A condition that mentions
  the `id` column or a column named `MRN` or `eMRN` (ignoring case),
  directly or as `.data$x` or `.data[["x"]]`, stops before any row is
  filtered, because each condition is saved, values included, in the
  job's output. Exclude those patients in the dataset build, or with an
  hvtiRdatabuild analysis set, instead. A value from outside the data is
  fixed in before this check, so `.data[[nm]]` is judged by the column
  `nm` names. A column reached any other way, as by
  `.data[[paste0(...)]]` or a string lookup such as
  [`get()`](https://rdrr.io/r/base/get.html), stops too, since it cannot
  be known. A function bound to such a lookup under another name is read
  as that lookup. Values are checked as well as names, after every name
  check: the check covers literal values (including a vector fixed in
  from outside) of five or more characters that equal a value of the
  identifier, `MRN` or `eMRN` columns in the data, and folds only
  arithmetic, [`c()`](https://rdrr.io/r/base/c.html), `paste`/`paste0`
  and numeric or character coercion of constants (such as
  `4730000000 + 1`) to check their result. So a wrapper function or a
  copy of the identifier under another name is caught when it is
  compared with such a value. The check never calls any other function:
  a value produced by any other call, or computed from a data column, as
  in `id2 / 2 != 2365000000.5`, is not checked. A threshold that happens
  to equal a patient's identifier is refused too, and the message says
  so; numbers are compared as whole numbers where they are whole, and
  `NA` never matches. Thresholds shorter than five characters, such as
  1, 18 or 2015, are not checked, so a study keyed on shorter
  identifiers relies on the name checks.

- id:

  The patient identifier column. When it is the default `"ccfid"` and
  absent, `MRN` and then `eMRN` are used.

- key:

  Columns that make a row unique; defaults to `id`, one row per patient.
  Add a visit time or date for repeated measures.

## Value

A list:

- `data`, the selected rows;

- `record`, a data frame of `step` and `value` to print, whose
  `"selection"` attribute holds the settings used;

- `provenance`, the read's provenance record;

- `attrition`, an analysis set's per-rule attrition table, or `NULL` for
  a dataset read whole.

The `"selection"` attribute is a list that a job saves in its hand-off,
so a downstream job can rebuild the same rows:

- `dataset` and `analysis_set`, as given;

- `where`, the exact text of each condition, values included, used to
  rebuild the rows; it stays inside the study and is never printed;

- `where_shown`, the same conditions as a report may show them, with the
  values of any condition on a `key` column, or using `.data` or a
  string lookup, replaced;

- `id` and `key`, the resolved column names;

- `rows` and `patients`, the counts kept;

- `key_hash`, a SHA-256 hash of the kept `key` values, so a downstream
  job can tell that it rebuilt the same patients and not only the same
  counts.

## Details

Columns named `MRN` or `eMRN` (ignoring case) are dropped unless one is
the identifier. An explicit `id` or `key` matches its column ignoring
case, because
[`hvtiRutilities::read_built()`](https://ehrlinger.github.io/hvtiRutilities/reference/read_built.html)
lowercases column names. Identifier, key and date values are not
printed: the record holds counts, and a `where` condition that mentions
a `key` column, uses `.data` or calls a string lookup such as
[`get()`](https://rdrr.io/r/base/get.html) is shown, in the record and
in error messages, with its values replaced by `<value>`. So is a
condition on `id` in a selection saved before such conditions were
refused. Every setting is checked before the data are read.

## Examples

``` r
# \donttest{
root <- file.path(tempdir(), "job-data-example")
dir.create(root)
hvtiRutilities::study_setup(root, "Example", 1L, adopt = TRUE)
#> Study: /tmp/RtmpEFOb4D/job-data-example
#> 
#> [x] _study.yml — study: Example
#> [ ] renv.lock — no renv.lock; run renv::init() in the study project
#> [ ] manifest.yaml — no manifest.yaml; register_data() creates it
#> [ ] dataset — no default dataset registered; run register_data()
#> [ ] provenance — no .qmd/.Rmd sources found; 0 sidecars
#> 
#> 0 .R  |  0 .qmd/.Rmd  |  0 .sas  |  0 provenance sidecars
d <- data.frame(ccfid = 1:4, age = c(15, 40, 55, 70))
utils::write.csv(d, file.path(hvtiRutilities::study_dir("datasets", root), "built.csv"),
                 row.names = FALSE)
hvtiRutilities::register_data(root, "built.csv")
#> Study: /tmp/RtmpEFOb4D/job-data-example
#> 
#> [x] _study.yml — study: Example
#> [ ] renv.lock — no renv.lock; run renv::init() in the study project
#> [x] manifest.yaml — 1 dataset entry verified by checksum
#> [x] dataset — built.csv
#> [ ] provenance — no .qmd/.Rmd sources found; 0 sidecars
#> 
#> 0 .R  |  0 .qmd/.Rmd  |  0 .sas  |  0 provenance sidecars
cfg <- hvtiRutilities::study_config(start = root)
job <- read_job_data(cfg, where = quote(age >= 18))
job$record
#>                  step                       value
#> 1              Source dataset `study` (built.csv)
#> 2           Rows read                           4
#> 3                  ID                     `ccfid`
#> 4 Identifiers dropped                        none
#> 5         `age >= 18`                   removed 1
#> 6           Rows kept        3 rows on 3 patients
unlink(root, recursive = TRUE)
# }
```
