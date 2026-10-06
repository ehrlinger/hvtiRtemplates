# General descriptive checks

# General descriptive checks

Replaces `descriptive/dc.general`.

A `dc-general` job is the first look at a built cohort, before any table
or model: what the data contain, how each categorical variable breaks
down, how each continuous variable is distributed, and which variables
move together. It uses base procedures only. The formatted manuscript
table is a `dc-tables` job.

Code

``` r
# The study root is the nearest directory above this file holding _study.yml,
# so the job renders the same from the Render button, quarto render, or
# render_job(), at any depth, with no path in this document to edit.
.in <- knitr::current_input(dir = TRUE)
.root <- hvtiRtemplates:::.find_study_root(if (is.null(.in)) getwd() else dirname(.in))
.provenance_data <- list()
for (f in list.files(file.path(.root, "R"), pattern = "[.]R$", full.names = TRUE)) source(f)
suppressPackageStartupMessages(library(hvtiRutilities))
```

Code

``` r
# The markers in this file name work a study author still has to do, and a job
# that still contains one has not been finished. This chunk is what makes that
# TRUE rather than merely stated: an unedited job would otherwise render green
# over placeholder columns.
.tok <- paste0("ED", "IT", ":")
.cur <- knitr::current_input()
if (!is.null(.cur)) {
  .src  <- readLines(.cur, warn = FALSE)
  .hits <- grep(.tok, .src, fixed = TRUE)
  if (length(.hits)) {
    .msg <- paste0(
      length(.hits), " unresolved ", .tok, " marker(s) remain in this job:\n",
      paste0("  - ", trimws(substr(.src[.hits], 1L, 96L)), collapse = "\n"),
      "\nA job that still contains one has not been finished. Work each ",
      "marker and delete it."
    )
    if (tolower(Sys.getenv("HVTI_TEMPLATE_STRICT")) %in% c("", "0", "false", "no")) {
      warning(.msg, "\nRendering as a draft; the banner goes when the last marker does. ",
              "Set HVTI_TEMPLATE_STRICT to 1, true or yes to make this stop.", call. = FALSE)
      cat("\n::: {.callout-important title=\"DRAFT -- this job is unfinished\"}\n")
      cat("Unresolved markers remain. **The numbers below are not",
          "a result.**\n\n```\n", .msg, "\n```\n", sep = "")
      cat(":::\n\n")
    } else {
      stop(.msg, "\nThis render stops because HVTI_TEMPLATE_STRICT is '",
           Sys.getenv("HVTI_TEMPLATE_STRICT"), "'. Unset it, or set it to 0, false ",
           "or no, to render a draft instead.", call. = FALSE)
    }
  }
}
```

Code

``` r
# unnumbered: a callout, printed only when part of the job is left out
# To render a job you have not finished, leave a chunk out with the chunk
# option skip, giving the reason in quotes, or call hvtiRtemplates::stop_here()
# in a chunk to leave out everything below it. A draft lists each one here; a
# final render refuses them, as it refuses an EDIT marker. ?stop_here has more.
hvtiRtemplates:::.guard_partial(knitr::current_input())
```

Code

``` r
SUBJECT <- "cohort"
TYPE    <- "eda"

.current <- knitr::current_input()
if (!is.null(.current)) {
  .fields <- strsplit(sub("[.][^.]+$", "", basename(.current)), "-", fixed = TRUE)[[1L]]
  .name_subject <- if (length(.fields) >= 1L) .fields[[1L]] else NA_character_
  .name_type <- if (length(.fields) >= 2L) .fields[[2L]] else NA_character_
  if (!identical(.name_subject, SUBJECT) || !identical(.name_type, TYPE)) {
    stop("This file is named '", .current, "' (subject '", .name_subject,
         "', type '", .name_type, "'), but declares SUBJECT = \"", SUBJECT,
         "\", TYPE = \"", TYPE, "\". Fix the declaration or the filename before rendering.",
         call. = FALSE)
  }
}

set_path <- function(kind, file) {
  d <- file.path(hvtiRutilities::study_dir(kind, .root),
                 paste0(SUBJECT, "-", TYPE))
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  file.path(d, file)
}
```

## Study choices

Edit these values for this study before rendering.

Code

``` r
# Demo: the registered dataset this job reads ("study" is the built dataset).
DATASET <- "study"

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

# Demo: grouped categorical variables. Each name is a section heading, in this
# order. Carry the /* Demography */ banners across from the SAS %macro freq
# tables list. Missing values are tabulated as their own level (missprint).
CATEGORICAL <- list(
  Demography = c("female", "race_grp"),
  History    = c("hx_chf", "hx_dm", "nyha_pr")
)

# Demo: continuous variables, grouped the same way (the SAS %macro cdfs var
# list).
CONTINUOUS <- list(
  Demography = c("age", "bmi"),
  Echo       = c("lvef", "plvmassi"),
  Laboratory = "creat_pr"
)

# Demo: variables for the pairwise correlation sweep (SAS proc corr nosimple
# rank). Defaults to every continuous variable; character() skips the section.
CORR_VARS <- unlist(CONTINUOUS, use.names = FALSE)

# Demo: leave NULL to keep identifiers out of reports. A column name (the SAS
# job used id ccfid) labels the extreme values with it, which puts patient
# identifiers in the report: a report rendered that way must not be circulated.
ID_COL <- NULL
```

## Data

Code

``` r
hvtiRutilities::verify_manifest(file.path(.root, "manifest.yaml"))
.cfg <- study_config(start = .root)
job_data <- hvtiRtemplates::read_job_data(.cfg, dataset = DATASET, analysis_set = ANALYSIS_SET,
                                          where = WHERE, id = ID, key = KEY)
d <- job_data$data
.provenance_data <- c(if (exists(".provenance_data")) .provenance_data else list(), list(job_data$provenance))
knitr::kable(job_data$record, col.names = c("Data", ""))
```

| Data                |                             |
|:--------------------|:----------------------------|
| Source              | dataset `study` (built.rds) |
| Rows read           | 800                         |
| ID                  | `patient_id`                |
| Identifiers dropped | none                        |
| Rows kept           | 800 rows on 800 patients    |

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
# The identifier column the data step used: ID as named, or MRN when the data
# have no ccfid. It is kept out of every summary, because the overall minimum
# and maximum would each be one patient's identifier.
.id <- attr(job_data$record, "selection")$id
PROBS <- c(0, 0.01, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.99, 1)
check_group_names <- function(x, setting) {
  if (!length(x)) return(invisible())
  nm <- names(x)
  if (is.null(nm) || any(nm == "") || anyDuplicated(nm)) {
    stop(setting, " must be a list with a unique, non-empty name for every group.", call. = FALSE)
  }
}
check_group_names(CATEGORICAL, "CATEGORICAL")
check_group_names(CONTINUOUS, "CONTINUOUS")
if (!is.null(ID_COL) && !(is.character(ID_COL) && length(ID_COL) == 1L)) {
  stop("ID_COL must be NULL or a single column name.", call. = FALSE)
}
cat_vars <- unlist(CATEGORICAL, use.names = FALSE)
con_vars <- unlist(CONTINUOUS, use.names = FALSE)
unknown <- setdiff(unique(c(cat_vars, con_vars, CORR_VARS, ID_COL, .id)), names(d))
if (length(unknown)) {
  stop("Unknown column(s): ", paste(unknown, collapse = ", "), call. = FALSE)
}
numeric_vars <- unique(c(con_vars, CORR_VARS))
not_numeric <- numeric_vars[!vapply(numeric_vars, function(v) is.numeric(d[[v]]), logical(1))]
if (length(not_numeric)) {
  stop("Not numeric, so not summarized as continuous or correlated: ",
       paste(not_numeric, collapse = ", "), call. = FALSE)
}
key_overlap <- intersect(unique(c(cat_vars, con_vars, CORR_VARS)), .id)
if (length(key_overlap)) {
  stop("The ID column cannot be summarized: ", paste(key_overlap, collapse = ", "), call. = FALSE)
}
overall_vars <- setdiff(names(d)[vapply(d, is.numeric, logical(1))], c(.id, ID_COL))

freqs <- lapply(CATEGORICAL, function(vars) {
  stats::setNames(lapply(vars, function(v) {
    tab <- table(d[[v]], useNA = "ifany")
    is_na_level <- is.na(names(tab))
    n_int <- as.integer(tab)
    total_nonmissing <- sum(n_int[!is_na_level])
    percent <- rep(NA_real_, length(tab))
    if (total_nonmissing > 0L) {
      percent[!is_na_level] <- round(100 * n_int[!is_na_level] / total_nonmissing, 1)
    }
    data.frame(
      level = ifelse(is_na_level, "(missing)", names(tab)),
      n = n_int,
      percent = percent
    )
  }), vars)
})

cdfs <- lapply(CONTINUOUS, function(vars) {
  stats::setNames(lapply(vars, function(v) {
    x <- d[[v]]
    seen <- which(!is.na(x))
    lowest <- seen[order(x[seen])][seq_len(min(5L, length(seen)))]
    highest <- seen[order(-x[seen])][seq_len(min(5L, length(seen)))]
    extremes <- data.frame(
      end = rep(c("lowest", "highest"), c(length(lowest), length(highest))),
      value = x[c(lowest, highest)]
    )
    if (!is.null(ID_COL)) extremes[[ID_COL]] <- d[[ID_COL]][c(lowest, highest)]
    list(
      summary = data.frame(n = length(seen), nmiss = sum(is.na(x))),
      quantiles = data.frame(
        percent = 100 * PROBS,
        value = if (length(seen)) stats::quantile(x[seen], PROBS, type = 2, names = FALSE) else NA_real_
      ),
      extremes = extremes
    )
  }), vars)
})

corr_vars <- unique(CORR_VARS)
corrs <- data.frame(var1 = character(), var2 = character(), r = numeric(), n = integer())
if (length(corr_vars) >= 2L) {
  pairs <- utils::combn(corr_vars, 2L)
  pair_stats <- apply(pairs, 2L, function(p) {
    ok <- stats::complete.cases(d[[p[[1L]]]], d[[p[[2L]]]])
    r <- if (sum(ok) >= 2L) stats::cor(d[[p[[1L]]]][ok], d[[p[[2L]]]][ok]) else NA_real_
    c(r = r, n = sum(ok))
  })
  corrs <- data.frame(
    var1 = pairs[1L, ], var2 = pairs[2L, ],
    r = pair_stats["r", ], n = as.integer(pair_stats["n", ])
  )
  corrs <- corrs[order(-abs(corrs$r)), , drop = FALSE]
  rownames(corrs) <- NULL
}
```

## Other investigations

## Overall statistics

Code

``` r
proc_contents(d)
```

    Observations: 800
    Variables:    32

       num     variable type format                                    label
    1    5          age  Num   <NA>                 Age at operation (years)
    2   26     approach Char   <NA>    Surgical or transcatheter replacement
    3    8          bmi  Num   <NA>                  Body mass index (kg/m2)
    4   30 complication  Num   <NA>         Major postoperative complication
    5   14     creat_pr  Num   <NA>                       Creatinine (mg/dL)
    6   15         dead  Num   <NA>                                    Death
    7   25    discharge Char   <NA>                    Discharge destination
    8    6       female  Num   <NA>                                   Female
    9    9       hx_chf  Num   <NA>                 History of heart failure
    10  10        hx_dm  Num   <NA>                                 Diabetes
    11  20    icu_hours  Num   <NA>                  Hours in intensive care
    12  16      iv_dead  Num   <NA>  Follow-up to death or censoring (years)
    13   3     iv_opyrs  Num   <NA>   Years from 1 January 1990 to operation
    14  18      iv_reop  Num   <NA>         Follow-up to reoperation (years)
    15  32      log_los  Num   <NA>  Postoperative length of stay (log days)
    16  31          los  Num   <NA>      Postoperative length of stay (days)
    17  12         lvef  Num   <NA>                 LV ejection fraction (%)
    18  21         male  Num   <NA>                                     Male
    19  24     mr_grade Char   <NA> Postoperative mitral regurgitation grade
    20  22     nonwhite  Num   <NA>                           Non-white race
    21  11      nyha_pr  Num   <NA>                    NYHA functional class
    22   2      op_date  Num   <NA>                        Date of operation
    23   1   patient_id Char   <NA>           Patient identifier (synthetic)
    24  13     plvmassi  Num   <NA>                     LV mass index (g/m2)
    25  29    prior_ops  Num   <NA>       Number of prior cardiac operations
    26   7     race_grp Char   <NA>                                     Race
    27  17         reop  Num   <NA>                              Reoperation
    28  23       stroke Char   <NA>                     Postoperative stroke
    29  27   valve_size Char   <NA>                          Prosthesis size
    30  28   valve_type Char   <NA>                          Prosthesis type
    31  19         vent  Num   <NA>                    Prolonged ventilation
    32   4         year  Num   <NA>                        Year of operation
           class n_unique pct_missing
    1    numeric       65         0.0
    2  character        2         0.0
    3    numeric      190         0.0
    4    integer        2         0.0
    5    numeric      147         9.4
    6    integer        2         0.0
    7  character        3         0.0
    8    integer        2         0.0
    9    integer        2         0.0
    10   integer        2         0.0
    11   numeric       82         0.0
    12   numeric      779         0.0
    13   numeric      787         0.0
    14   numeric      774         0.0
    15   numeric       19         0.0
    16   integer       19         0.0
    17   numeric       53         0.0
    18   integer        2         0.0
    19 character        4         0.0
    20   integer        2         0.0
    21   numeric        4         0.0
    22      Date      766         0.0
    23 character      800         0.0
    24   numeric      141         0.0
    25   integer        4         0.0
    26 character        3         0.0
    27   integer        2         0.0
    28 character        2         0.0
    29 character        3         0.0
    30 character        3         0.0
    31   integer        2         0.0
    32   numeric       35         0.0

Table 2: Contents of the data: each column, its type and its label

Code

``` r
# unnumbered: its child chunk carries its own label and caption
if (length(overall_vars)) {
  .fence <- strrep("`", 3)
  cat(knitr::knit_child(text = c(
    paste0(.fence, "{r}"), "#| label: tbl-overall-means",
    "#| tbl-cap: \"Summary statistics of the overall variables\"",
    "proc_means(d, vars = overall_vars, stats = c(\"n\", \"nmiss\", \"mean\", \"std\", \"min\", \"max\", \"sum\"))",
    .fence
  ), envir = environment(), quiet = TRUE), sep = "\n")
}
```

Code

``` r
proc_means(d, vars = overall_vars, stats = c("n", "nmiss", "mean", "std", "min", "max", "sum"))
```

           variable                                   label   n nmiss        mean
    1      iv_opyrs  Years from 1 January 1990 to operation 800     0   17.432389
    2          year                       Year of operation 800     0 2006.940000
    3           age                Age at operation (years) 800     0   62.376250
    4        female                                  Female 800     0    0.373750
    5           bmi                 Body mass index (kg/m2) 800     0   27.902000
    6        hx_chf                History of heart failure 800     0    0.303750
    7         hx_dm                                Diabetes 800     0    0.218750
    8       nyha_pr                   NYHA functional class 800     0    2.272500
    9          lvef                LV ejection fraction (%) 800     0   51.777500
    10     plvmassi                    LV mass index (g/m2) 800     0  121.031250
    11     creat_pr                      Creatinine (mg/dL) 725    75    1.086152
    12         dead                                   Death 800     0    0.553750
    13      iv_dead Follow-up to death or censoring (years) 800     0    9.964107
    14         reop                             Reoperation 800     0    0.260000
    15      iv_reop        Follow-up to reoperation (years) 800     0    7.570521
    16         vent                   Prolonged ventilation 800     0    0.315000
    17    icu_hours                 Hours in intensive care 800     0   33.922500
    18         male                                    Male 800     0    0.626250
    19     nonwhite                          Non-white race 800     0    0.211250
    20    prior_ops      Number of prior cardiac operations 800     0    0.392500
    21 complication        Major postoperative complication 800     0    0.182500
    22          los     Postoperative length of stay (days) 800     0    6.317500
    23      log_los Postoperative length of stay (log days) 800     0    1.763026
              std      min       max         sum
    1   9.8319268 6.60e-02   34.9400   13945.911
    2   9.8260923 1.99e+03 2024.0000 1605552.000
    3  12.1764123 3.20e+01  100.0000   49901.000
    4   0.4841011 0.00e+00    1.0000     299.000
    5   4.4563207 1.51e+01   44.8000   22321.600
    6   0.4601637 0.00e+00    1.0000     243.000
    7   0.4136573 0.00e+00    1.0000     175.000
    8   0.7819899 1.00e+00    4.0000    1818.000
    9   9.7894221 2.00e+01   75.0000   41422.000
    10 29.4092912 2.80e+01  207.0000   96825.000
    11  0.3555899 4.30e-01    2.7600     787.460
    12  0.4974135 0.00e+00    1.0000     443.000
    13  8.5101358 2.50e-04   35.6960    7971.285
    14  0.4389086 0.00e+00    1.0000     208.000
    15  7.0693300 0.00e+00   35.6110    6056.417
    16  0.4648065 0.00e+00    1.0000     252.000
    17 20.1484849 4.00e+00  108.0000   27138.000
    18  0.4841011 0.00e+00    1.0000     501.000
    19  0.4084507 0.00e+00    1.0000     169.000
    20  0.6663323 0.00e+00    3.0000     314.000
    21  0.3864977 0.00e+00    1.0000     146.000
    22  2.6249394 1.00e+00   19.0000    5054.000
    23  0.4032844 0.00e+00    2.9444    1410.421

Table 3: Summary statistics of the overall variables

## Contingency tables for categorical variables

Code

``` r
# unnumbered: each child chunk below carries its own label and caption
.kable_na <- options(knitr.kable.NA = "")
.fence <- strrep("`", 3)
.seen <- new.env()
.child <- function(kind, key, caption, code) {
  label <- paste(kind, "freqs", gsub("(^-+|-+$)", "", gsub("[^a-z0-9]+", "-", tolower(key))), sep = "-")
  if (!is.null(.seen[[label]])) stop("Two outputs would share the label ", label, ".", call. = FALSE)
  .seen[[label]] <- TRUE
  cat(knitr::knit_child(text = c(paste0(.fence, "{r}"), paste0("#| label: ", label),
                                 paste0("#| ", kind, "-cap: ", encodeString(caption, quote = "\"")), code, .fence),
                        envir = parent.frame(), quiet = TRUE), sep = "\n")
}
# One table per group, a block of rows per variable, rather than a table per
# variable: a 0/1 variable is two rows, and a table of two rows each is most of
# a report spent on captions.
for (group in names(freqs)) {
  .freq <- do.call(rbind, lapply(names(freqs[[group]]), function(v) {
    f <- freqs[[group]][[v]]
    cbind(variable = ifelse(seq_len(nrow(f)) == 1L, v, ""), f)
  }))
  .child("tbl", group, paste0("Frequencies, ", group), "knitr::kable(.freq, row.names = FALSE)")
  cat("\n")
}
```

Code

``` r
knitr::kable(.freq, row.names = FALSE)
```

| variable | level |   n | percent |
|:---------|:------|----:|--------:|
| female   | 0     | 501 |    62.6 |
|          | 1     | 299 |    37.4 |
| race_grp | Black | 111 |    13.9 |
|          | Other |  58 |     7.2 |
|          | White | 631 |    78.9 |

Table 4: Frequencies, Demography

Code

``` r
knitr::kable(.freq, row.names = FALSE)
```

| variable | level |   n | percent |
|:---------|:------|----:|--------:|
| hx_chf   | 0     | 557 |    69.6 |
|          | 1     | 243 |    30.4 |
| hx_dm    | 0     | 625 |    78.1 |
|          | 1     | 175 |    21.9 |
| nyha_pr  | 1     | 129 |    16.1 |
|          | 2     | 360 |    45.0 |
|          | 3     | 275 |    34.4 |
|          | 4     |  36 |     4.5 |

Table 5: Frequencies, History

Code

``` r
options(.kable_na)
```

## Cumulative distributions for continuous variables

Code

``` r
# unnumbered: each child chunk below carries its own label and caption
.fence <- strrep("`", 3)
.seen <- new.env()
.child <- function(kind, key, caption, code) {
  label <- paste(kind, "cdfs", gsub("(^-+|-+$)", "", gsub("[^a-z0-9]+", "-", tolower(key))), sep = "-")
  if (!is.null(.seen[[label]])) stop("Two outputs would share the label ", label, ".", call. = FALSE)
  .seen[[label]] <- TRUE
  cat(knitr::knit_child(text = c(paste0(.fence, "{r}"), paste0("#| label: ", label),
                                 paste0("#| ", kind, "-cap: ", encodeString(caption, quote = "\"")), code, .fence),
                        envir = parent.frame(), quiet = TRUE), sep = "\n")
}
# One quantile table per group, a row per variable with its n and nmiss beside
# its quantiles, rather than a one-row count table and a quantile table for
# every variable. The extremes stay one table per variable, since ID_COL can
# add a column to them.
for (group in names(cdfs)) {
  cat("\n### ", group, "\n\n", sep = "")
  .quant <- do.call(rbind, lapply(names(cdfs[[group]]), function(v) {
    .cdf <- cdfs[[group]][[v]]
    row <- as.data.frame(as.list(stats::setNames(.cdf$quantiles$value, paste0(.cdf$quantiles$percent, "%"))),
                         check.names = FALSE)
    cbind(variable = v, .cdf$summary, row)
  }))
  .child("tbl", paste(group, "quantiles"), paste0("Quantiles, ", group, " (SAS QNTLDEF=5)"),
         "knitr::kable(.quant, row.names = FALSE)")
  cat("\n")
  for (v in names(cdfs[[group]])) {
    .cdf <- cdfs[[group]][[v]]
    .child("tbl", paste(group, v, "extremes"), paste0("Five lowest and five highest values, ", v),
           "knitr::kable(.cdf$extremes)")
    cat("\n")
  }
}
```

### Demography

Code

``` r
knitr::kable(.quant, row.names = FALSE)
```

| variable |   n | nmiss |   0% |    1% |   5% |  10% |  25% |  50% |   75% |  90% |   95% |   99% |  100% |
|:---------|----:|------:|-----:|------:|-----:|-----:|-----:|-----:|------:|-----:|------:|------:|------:|
| age      | 800 |     0 | 32.0 | 35.00 | 41.0 | 46.0 | 54.0 | 63.0 | 71.00 | 78.0 | 82.00 | 90.00 | 100.0 |
| bmi      | 800 |     0 | 15.1 | 18.05 | 20.8 | 22.2 | 24.8 | 27.8 | 30.85 | 33.6 | 35.35 | 39.85 |  44.8 |

Table 6: Quantiles, Demography (SAS QNTLDEF=5)

Code

``` r
knitr::kable(.cdf$extremes)
```

| end     | value |
|:--------|------:|
| lowest  |    32 |
| lowest  |    32 |
| lowest  |    33 |
| lowest  |    34 |
| lowest  |    34 |
| highest |   100 |
| highest |    99 |
| highest |    99 |
| highest |    98 |
| highest |    94 |

Table 7: Five lowest and five highest values, age

Code

``` r
knitr::kable(.cdf$extremes)
```

| end     | value |
|:--------|------:|
| lowest  |  15.1 |
| lowest  |  16.7 |
| lowest  |  16.8 |
| lowest  |  17.6 |
| lowest  |  17.7 |
| highest |  44.8 |
| highest |  41.1 |
| highest |  41.0 |
| highest |  40.8 |
| highest |  40.7 |

Table 8: Five lowest and five highest values, bmi

### Echo

Code

``` r
knitr::kable(.quant, row.names = FALSE)
```

| variable |   n | nmiss |  0% |  1% |  5% | 10% | 25% | 50% | 75% | 90% | 95% |   99% | 100% |
|:---------|----:|------:|----:|----:|----:|----:|----:|----:|----:|----:|----:|------:|-----:|
| lvef     | 800 |     0 |  20 |  28 |  35 |  39 |  45 |  52 |  59 |  64 |  67 |  73.0 |   75 |
| plvmassi | 800 |     0 |  28 |  53 |  73 |  83 | 100 | 121 | 141 | 158 | 170 | 191.5 |  207 |

Table 9: Quantiles, Echo (SAS QNTLDEF=5)

Code

``` r
knitr::kable(.cdf$extremes)
```

| end     | value |
|:--------|------:|
| lowest  |    20 |
| lowest  |    22 |
| lowest  |    23 |
| lowest  |    26 |
| lowest  |    26 |
| highest |    75 |
| highest |    75 |
| highest |    75 |
| highest |    75 |
| highest |    75 |

Table 10: Five lowest and five highest values, lvef

Code

``` r
knitr::kable(.cdf$extremes)
```

| end     | value |
|:--------|------:|
| lowest  |    28 |
| lowest  |    42 |
| lowest  |    45 |
| lowest  |    48 |
| lowest  |    49 |
| highest |   207 |
| highest |   200 |
| highest |   197 |
| highest |   196 |
| highest |   196 |

Table 11: Five lowest and five highest values, plvmassi

### Laboratory

Code

``` r
knitr::kable(.quant, row.names = FALSE)
```

| variable |   n | nmiss |   0% |   1% |   5% | 10% |  25% |  50% |  75% |  90% | 95% |  99% | 100% |
|:---------|----:|------:|-----:|-----:|-----:|----:|-----:|-----:|-----:|-----:|----:|-----:|-----:|
| creat_pr | 725 |    75 | 0.43 | 0.53 | 0.63 | 0.7 | 0.83 | 1.02 | 1.28 | 1.52 | 1.7 | 2.34 | 2.76 |

Table 12: Quantiles, Laboratory (SAS QNTLDEF=5)

Code

``` r
knitr::kable(.cdf$extremes)
```

| end     | value |
|:--------|------:|
| lowest  |  0.43 |
| lowest  |  0.48 |
| lowest  |  0.49 |
| lowest  |  0.49 |
| lowest  |  0.50 |
| highest |  2.76 |
| highest |  2.72 |
| highest |  2.60 |
| highest |  2.56 |
| highest |  2.50 |

Table 13: Five lowest and five highest values, creat_pr

## Pair-wise correlations

Code

``` r
# unnumbered: its child chunk carries its own label and caption
if (nrow(corrs)) {
  .fence <- strrep("`", 3)
  cat(knitr::knit_child(text = c(
    paste0(.fence, "{r}"), "#| label: tbl-corrs",
    "#| tbl-cap: \"Pearson correlations, pairwise complete, strongest first\"",
    "knitr::kable(corrs, digits = 3, row.names = FALSE)", .fence
  ), envir = environment(), quiet = TRUE), sep = "\n")
} else {
  cat("No correlation sweep: `CORR_VARS` names fewer than two variables.\n")
}
```

Code

``` r
knitr::kable(corrs, digits = 3, row.names = FALSE)
```

| var1     | var2     |      r |   n |
|:---------|:---------|-------:|----:|
| plvmassi | creat_pr | -0.079 | 725 |
| age      | creat_pr | -0.064 | 725 |
| age      | plvmassi | -0.043 | 800 |
| age      | lvef     |  0.029 | 800 |
| lvef     | creat_pr |  0.024 | 725 |
| bmi      | plvmassi |  0.016 | 800 |
| lvef     | plvmassi |  0.013 | 800 |
| bmi      | creat_pr | -0.008 | 725 |
| bmi      | lvef     |  0.006 | 800 |
| age      | bmi      | -0.004 | 800 |

Table 14: Pearson correlations, pairwise complete, strongest first

`proc_means()` covers every numeric column other than `ID` and `ID_COL`.
Percentages in the contingency tables are over non-missing rows, as SAS
`MISSPRINT` computes them; the `(missing)` row shows its count with a
blank percent. Quantiles are SAS `QNTLDEF=5`, the `proc univariate`
default. The highest extremes are listed largest first (SAS lists them
ascending). The SAS job printed `ccfid` beside every extreme value so an
author could look the patient up; this job prints the values alone
unless `ID_COL` is set under Study choices.
