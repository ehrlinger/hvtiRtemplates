# Descriptive tables

# Descriptive tables

Published

2026-10-15 21:14

A `dc-tables` job is the formatted descriptive table: every variable the
study reports, grouped under the section headings the SAS `%desc_tab`
lists carried as comments, categorical as `n (%)` and continuous in the
summary form you select. The default is median (15th, 85th percentile).
`%desc_tab` wrote the categorical and continuous tables as two RTF
files; `hv_tbl_summary()` writes one table with both. It describes; with
`BY` set it separates the groups into columns. `COMPARE` chooses whether
to test them; a p-value here is a prompt for an analysis, not a result.

Code

``` r
# unnumbered: setup, and the box under the title
SUBJECT <- "cohort"
TYPE    <- "eda"
.in <- knitr::current_input(dir = TRUE)
suppressPackageStartupMessages({
  library(hvtiRutilities)
  library(hvtiRtables)
  library(hvtiPlotR)
  library(ggplot2)
})
if (utils::packageVersion("hvtiRtables") < "1.0.5") {
  stop("This job needs hvtiRtables >= 1.0.5 for hv_correlation_table() and the %summarytable layout of ",
       "hv_man_table_save(); ",
       utils::packageVersion("hvtiRtables"), " is installed.", call. = FALSE)
}
if (utils::packageVersion("hvtiPlotR") < "2.7.14") {
  stop("This job needs hvtiPlotR >= 2.7.14 for hv_correlation_matrix(); ",
       utils::packageVersion("hvtiPlotR"), " is installed.", call. = FALSE)
}
# The study root is the nearest directory above this file holding _study.yml,
# so the job renders the same from the Render button, quarto render, or
# render_job(), at any depth, with no path in this document to edit.
# To render a job you have not finished, leave a chunk out with the chunk
# option skip, giving the reason in quotes, or call hvtiRtemplates::stop_here()
# in a chunk to leave out everything below it. A draft lists each one in a
# callout; a final render refuses them, as it refuses an unresolved marker.
# ?stop_here has more.
.job <- hvtiRtemplates:::.job_setup(SUBJECT, TYPE, envir = environment())
.root <- .job$root
set_path <- .job$set_path
.provenance_data <- list()
# Saves a figure as <name>.png, .pdf and .tiff in this set's graphs/ folder (or `kind`'s),
# under the SAVE_FIGURES and FIGURES study choices.
save_figure <- function(plot, name, width = 6, height = 4, kind = "graphs", linked = FALSE) {
  hvtiRtemplates:::.save_figure(plot, set_path(kind, paste0(name, ".png")), width, height,
                                SAVE_FIGURES, FIGURES, linked)
}
# The draft banners, if any, and the box under the title, after all the code above.
.job$notice
```

**final** · data `built` `built_20261015.parquet`, registered 2026-10-15
· rendered by gallery on gallery · hvtiRtemplates 1.4.1

## Study choices

Set the values in this chunk before rendering.

Code

``` r
# Demo: the registered dataset this job reads ("built" is the study dataset).
# MIGRATE-BEGIN: dc-tables-data
DATASET <- "built"
# MIGRATE-END: dc-tables-data

# Demo: an hvtiRdatabuild analysis set, or NULL to read the whole dataset.
ANALYSIS_SET <- NULL

# Demo: rows to keep, dplyr::filter() style, or NULL to keep every row:
#   WHERE <- quote(age >= 18)
#   WHERE <- rlang::exprs(age >= 18, hx_chf == 1)
WHERE <- NULL

# Demo: the patient identifier. Without "ccfid" the job uses MRN, then eMRN;
# name another column, such as "randid", if the study uses one.
ID <- "patient_id"

# Demo: what makes a row unique; one row per patient unless repeated measures
# add their visit time or date, for example KEY <- c(ID, "iv_echo").
KEY <- ID

# Optional, and needs no edit: NULL reads the cohort alone. To join one
# registered ancillary dataset (echoes, labs), name it in JOIN. The cohort
# above decides the patients, one row each; the joined records of other
# patients are dropped and counted in the data table.
#   JOIN_VARS: the cohort columns each joined row carries; NULL carries all,
#     and a column both datasets have stops, so list only those the job needs.
#   REDUCE: NULL keeps a row per joined record, keyed on that dataset's key;
#     list(rule = "first", by = "echo_date") keeps one row per patient ("last",
#     or "nearest" with to = a cohort date column). WHERE on a joined column
#     filters the records first, so "last" with WHERE echo_type == "TTE"
#     keeps each patient's last TTE. A tie stops: picking one record
#     silently would be a hidden choice; by = c("echo_date", "echo_seq")
#     breaks it. A job that counts or models
#     patients, one row each, needs REDUCE: NULL would count every record.
#   JOIN_KEY: overrides the joined dataset's registered key.
JOIN <- NULL
JOIN_VARS <- NULL
REDUCE <- NULL
JOIN_KEY <- NULL

# Demo: the variables to report, grouped. Each name is a section heading and
# becomes a row group in the table, in this order. These are the /* Demography */
# style banners from the SAS varlist; carry them across unchanged so the R table
# reads like the SAS one. Commented-out SAS blocks stay out.
# MIGRATE-BEGIN: dc-tables-config
GROUPS <- list(
  Demography = c("age", "female", "race_grp", "bmi"),
  History    = c("hx_chf", "hx_dm", "nyha_pr"),
  Echo       = c("lvef", "plvmassi"),
  Laboratory = "creat_pr"
)
# Demo: NULL for the overall table. A column name reproduces the `%macro skip`
# by-group sections (by=): one column per observed level. Review byvalue=
# against the data before accepting the columns; COMPARE controls testing.
BY <- NULL
# All three NULL values use automatic classification for a new, unmigrated job.
# Migrated jobs declare every row explicitly; character(0) is an empty bucket.
CONTINUOUS <- NULL
BINARY <- NULL
CATEGORICAL <- NULL
COMPARE <- "none"             # Demo: choose whether to compare groups
CONTINUOUS_STAT <- "median"   # Demo: choose the continuous summary
PERCENTILES <- c(15, 85)       # Demo: choose the reported percentiles
ABBREVIATIONS <- character(0) # Demo: define abbreviations used in the table
WORD_FILE <- "dc-tables.docx"  # Demo: choose the Word filename within this set
# MIGRATE-END: dc-tables-config
# Demo: force a bucket where the data guess wrong, e.g. an ordinal score you
# want summarized as continuous: list(continuous = c("nyha_pr")). list() for none.
OVERRIDES <- list()
# Demo: NULL skips the correlation variant (dc.tables.ods_<topic>.sas). To run
# it, name the numeric columns, the anchor to correlate them against (NULL for
# every pair), and an optional stratum:
#   list(vars = c("glu_pr", "creat_pr"), with = "a1c_pr", by = "a1c_grp")
CORR <- NULL

# Each figure is saved to descriptive/ as a PNG (for Word), and a PDF and a TIFF (for the publisher).
# SAVE_FIGURES <- FALSE saves none; FIGURES keeps only the figures whose names
# start with one of its entries, e.g. FIGURES <- c("hp-survival"). The names are the
# file names, listed for each template in the templates README.
SAVE_FIGURES <- TRUE
FIGURES <- NULL
```

## Data

Code

``` r
# The checksum of every dataset in manifest.yaml is checked before anything is
# read, so a result can name the data that produced it. It stops on a mismatch.
hvtiRutilities::verify_manifest(file.path(.root, "manifest.yaml"))
.cfg <- study_config(start = .root)
job_data <- hvtiRtemplates::read_job_data(.cfg, dataset = DATASET, analysis_set = ANALYSIS_SET,
                                          where = WHERE, id = ID, key = KEY, join = JOIN, join_vars = JOIN_VARS,
                                          reduce = REDUCE, join_key = JOIN_KEY)
d <- job_data$data
.provenance_data <- c(if (exists(".provenance_data")) .provenance_data else list(), list(job_data$provenance),
                      if (!is.null(job_data$provenance_join)) list(job_data$provenance_join))
knitr::kable(job_data$record, col.names = c("Data", ""))
```

| Data                |                                          |
|:--------------------|:-----------------------------------------|
| Source              | dataset `built` (built_20261015.parquet) |
| Rows read           | 800                                      |
| ID                  | `patient_id`                             |
| Identifiers dropped | none                                     |
| Rows kept           | 800 rows on 800 patients                 |

Table 1: The data this job read

Code

``` r
# unnumbered: its child chunk carries its own label and caption
if (!is.null(job_data$attrition)) {
  .fence <- strrep("`", 3)
  cat(knitr::knit_child(text = c(
    paste0(.fence, "{r}"), "#| label: tbl-data-attrition",
    paste0("#| tbl-cap: ", encodeString(paste0("Analysis set `", ANALYSIS_SET, "`: exclusions, in order"), quote = "\"")),
    "knitr::kable(job_data$attrition)", .fence
  ), envir = environment(), quiet = TRUE), sep = "\n")
}
```

Code

``` r
classify_buckets <- function(d, vars, overrides = list()) {
  vars <- unique(as.character(vars))
  unknown <- setdiff(vars, names(d))
  if (length(unknown)) stop("Unknown table variable(s): ", paste(unknown, collapse = ", "), call. = FALSE)
  allowed <- c("continuous", "binary", "categorical")
  if (!is.list(overrides)) {
    stop("overrides must be a list named continuous, binary, or categorical.", call. = FALSE)
  }
  override_names <- names(overrides)
  if (length(overrides) &&
        (is.null(override_names) || anyNA(override_names) || any(!nzchar(override_names)))) {
    stop("Every override bucket must be named continuous, binary, or categorical.", call. = FALSE)
  }
  if (anyDuplicated(override_names)) {
    stop("Override bucket names must be unique.", call. = FALSE)
  }
  if (length(setdiff(override_names, allowed))) {
    stop("overrides must be a list named continuous, binary, or categorical.", call. = FALSE)
  }
  forced <- unlist(overrides, use.names = FALSE)
  if (anyDuplicated(forced)) stop("A variable may appear in only one override bucket.", call. = FALSE)
  if (length(setdiff(forced, vars))) {
    stop("Override variable(s) are not in vars: ", paste(setdiff(forced, vars), collapse = ", "), call. = FALSE)
  }

  is_binary <- vapply(d[vars], function(x) {
    if (is.logical(x)) return(TRUE)
    values <- unique(stats::na.omit(x))
    if (is.numeric(x)) return(setequal(values, c(0, 1)))
    if (is.factor(x)) {
      return(nlevels(x) == 2L && setequal(toupper(levels(x)), c("NO", "YES")))
    }
    if (is.character(x)) {
      return(length(values) == 2L && setequal(toupper(values), c("NO", "YES")))
    }
    FALSE
  }, logical(1))
  is_continuous <- vapply(d[vars], function(x) {
    is.numeric(x) && length(unique(x[!is.na(x)])) > 6L
  }, logical(1))
  buckets <- list(
    continuous = vars[!is_binary & is_continuous],
    binary = vars[is_binary],
    categorical = vars[!is_binary & !is_continuous]
  )
  for (bucket in intersect(allowed, names(overrides))) {
    move <- as.character(overrides[[bucket]])
    buckets <- lapply(buckets, setdiff, y = move)
    buckets[[bucket]] <- unique(c(buckets[[bucket]], move))
  }
  buckets
}
```

## Table

Code

``` r
explicit <- list(continuous = CONTINUOUS, binary = BINARY, categorical = CATEGORICAL)
if (all(vapply(explicit, is.null, logical(1)))) {
  b <- classify_buckets(d, unlist(GROUPS, use.names = FALSE), OVERRIDES)
  CONTINUOUS <- b$continuous
  BINARY <- b$binary
  CATEGORICAL <- b$categorical
} else {
  if (any(vapply(explicit, is.null, logical(1))) || length(OVERRIDES)) {
    stop("Declare all three buckets and leave OVERRIDES empty for explicit classification.", call. = FALSE)
  }
  rows <- unlist(GROUPS, use.names = FALSE)
  classified <- unlist(explicit, use.names = FALSE)
  if (anyDuplicated(rows) || anyDuplicated(classified) || !setequal(rows, classified)) {
    stop("Every grouped row must appear in exactly one explicit bucket.", call. = FALSE)
  }
  invisible(classify_buckets(d, rows, explicit))
}
tbl <- hvtiRtables::hv_tbl_summary(
  d, by = BY, groups = GROUPS, continuous = CONTINUOUS,
  binary = BINARY, categorical = CATEGORICAL, compare = COMPARE,
  percentiles = PERCENTILES, continuous_stat = CONTINUOUS_STAT
)
tbl
ft <- hvtiRtables::hv_man_table(tbl)
if (length(WORD_FILE) != 1L || is.na(WORD_FILE) ||
      !grepl("^[A-Za-z0-9_][A-Za-z0-9_.-]*[.]docx$", WORD_FILE)) {
  stop("WORD_FILE must be a plain .docx filename within this set.", call. = FALSE)
}
word_path <- file.path(study_dir("documents", .root), paste0(SUBJECT, "-", TYPE), WORD_FILE)
dir.create(dirname(word_path), recursive = TRUE, showWarnings = FALSE)
hvtiRtables::hv_man_table_save(ft, word_path, abbreviations = ABBREVIATIONS)
check <- hvtiRtables::hv_check_docx(word_path)
if (nrow(check)) stop("Word output failed the CORR structural check", call. = FALSE)
```

[TABLE]

Table 2: Summary statistics for the study cohort, as written to the Word
file

## Correlations

Code

``` r
# unnumbered: each child chunk below carries its own label and caption
if (is.null(CORR)) {
  cat("Correlation variant not requested (`CORR <- NULL`).\n")
} else {
  ct <- hv_correlation_table(d, vars = CORR$vars, with = CORR$with)
  conf_level <- attr(ct, "conf_level")
  if (!is.null(CORR$by)) {
    st <- hv_correlation_table(d, vars = CORR$vars, with = CORR$with, by = CORR$by)
    ct[[CORR$by]] <- "Overall"
    ct <- rbind(ct[names(st)], st)
    attr(ct, "conf_level") <- conf_level
  }
  cm <- hv_correlation_matrix(d, vars = unique(c(CORR$with, CORR$vars)))
  fname <- "dc-tables-correlation-matrix.png"
  # Free size: a scatter-plot matrix, so a single 6 by 4 panel would leave each cell too small to read.
  save_figure(plot(cm) + theme_hv_manuscript(base_size = 12), sub("[.]png$", "", fname), width = 10, height = 10,
              kind = "descriptive", linked = TRUE)
  .fence <- strrep("`", 3)
  .caption <- sprintf("Spearman and Pearson, %d%% Fisher interval", round(100 * conf_level))
  cat(knitr::knit_child(text = c(
    paste0(.fence, "{r}"), "#| label: tbl-correlation", paste0("#| tbl-cap: ", encodeString(.caption, quote = "\"")),
    "knitr::kable(ct)", .fence, "",
    paste0(.fence, "{r}"), "#| label: fig-correlation-matrix",
    paste0("#| fig-cap: \"Scatter-plot matrix of the correlated variables. Each cell plots one variable against another, ",
           "each patient a small translucent black filled circle.\""),
    "knitr::include_graphics(file.path(paste0(SUBJECT, \"-\", TYPE), fname), error = FALSE)", .fence
  ), envir = environment(), quiet = TRUE), sep = "\n")
}
```

Correlation variant not requested (`CORR <- NULL`).

## About this run

| Group           | Item           | Value                    |
|:----------------|:---------------|:-------------------------|
| Run             | Started        | 2026-10-15 21:14:18 EDT  |
|                 | Ended          | 2026-10-15 21:14:19 EDT  |
|                 | Duration       | 1 s                      |
|                 | Status         | final                    |
|                 | Rendered by    | gallery                  |
|                 | Host           | gallery                  |
| Job             | File           | dc.tables.cohort.eda.qmd |
|                 | Template       | dc.tables                |
|                 | Subject        | cohort                   |
|                 | Type           | eda                      |
|                 | hvtiRtemplates | 1.4.1                    |
| Dataset `built` | Version file   | built_20261015.parquet   |
|                 | Registered     | 2026-10-15               |
|                 | Source file    | built.rds                |
|                 | Rows kept      | 800 rows on 800 patients |
|                 | WHERE          | none                     |
|                 | sha256         | b55bc29fc6a4             |
|                 | Manifest       | current                  |
| Reproducibility | renv           | not active               |
