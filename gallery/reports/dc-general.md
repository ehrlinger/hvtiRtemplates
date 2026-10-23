# General descriptive checks

# General descriptive checks

Published

2026-10-23 13:35

Replaces `descriptive/dc.general`.

A `dc-general` job is the first look at a built cohort, before any table
or model: what the data contain, how each categorical variable breaks
down, how each continuous variable is distributed, and which variables
move together. It uses base procedures only.

The tables below are checks on the data, not tables for a paper. For a
manuscript table, run a `dc-tables` job alongside this one:
`add_job("dc", SUBJECT, TYPE, qualifier = "tables")`. It takes the same
grouped variable lists, renders them in the CORR house format, and saves
the table to Word.

Code

``` r
SUBJECT <- "cohort"
TYPE    <- "eda"
.in <- knitr::current_input(dir = TRUE)
suppressPackageStartupMessages(library(hvtiRutilities))
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
# The draft banners, if any, and the box under the title, after all the code above.
.job$notice
```

**final** · data `built` `built_20261023.parquet`, registered 2026-10-23
· rendered by gallery on gallery · hvtiRtemplates 1.5.0

## Study choices

Edit these values for this study before rendering.

Code

``` r
# Demo: the registered dataset this job reads ("built" is the study dataset).
DATASET <- "built"

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
                                          where = WHERE, id = ID, key = KEY, join = JOIN, join_vars = JOIN_VARS,
                                          reduce = REDUCE, join_key = JOIN_KEY)
d <- job_data$data
.provenance_data <- c(if (exists(".provenance_data")) .provenance_data else list(), list(job_data$provenance),
                      if (!is.null(job_data$provenance_join)) list(job_data$provenance_join))
knitr::kable(job_data$record, col.names = c("Data", ""))
```

| Data                |                                          |
|:--------------------|:-----------------------------------------|
| Source              | dataset `built` (built_20261023.parquet) |
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
# The identifier column the data step used: ID as named, or MRN when the data
# have no ccfid. It is kept out of every summary, because the overall minimum
# and maximum would each be one patient's identifier.
.id <- attr(job_data$record, "selection")$id
# The group reports the 15th and 85th percentiles, not the quartiles.
PROBS <- c(0, 0.01, 0.05, 0.10, 0.15, 0.50, 0.85, 0.90, 0.95, 0.99, 1)
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
    Variables:    41

       num     variable type format
    1    4          age  Num   <NA>
    2   25     approach Char   <NA>
    3    7          bmi  Num   <NA>
    4   30 complication  Num   <NA>
    5   33     cpb_time  Num   <NA>
    6   13     creat_pr  Num   <NA>
    7   14         dead  Num   <NA>
    8   24    discharge Char   <NA>
    9    2      dt_surg  Num   <NA>
    10  38          e_e  Num   <NA>
    11   5       female  Num   <NA>
    12   8       hx_chf  Num   <NA>
    13   9        hx_dm  Num   <NA>
    14  19    icu_hours  Num   <NA>
    15  15      iv_dead  Num   <NA>
    16   3     iv_opyrs  Num   <NA>
    17  41     iv_reint  Num   <NA>
    18  17      iv_reop  Num   <NA>
    19  36      la_diam  Num   <NA>
    20  32      log_los  Num   <NA>
    21  31          los  Num   <NA>
    22  34        lvedd  Num   <NA>
    23  11         lvef  Num   <NA>
    24  35        lvesd  Num   <NA>
    25  20         male  Num   <NA>
    26  29   match_pair  Num   <NA>
    27  23     mr_grade Char   <NA>
    28  39 mv_procedure Char   <NA>
    29  21     nonwhite  Num   <NA>
    30  10      nyha_pr  Num   <NA>
    31   1   patient_id Char   <NA>
    32  12     plvmassi  Num   <NA>
    33  28    prior_ops  Num   <NA>
    34   6     race_grp Char   <NA>
    35  40        reint  Num   <NA>
    36  16         reop  Num   <NA>
    37  37         rvsp  Num   <NA>
    38  22       stroke Char   <NA>
    39  26   valve_size Char   <NA>
    40  27   valve_type Char   <NA>
    41  18         vent  Num   <NA>
                                                         label     class n_unique
    1                                 Age at operation (years)   numeric       65
    2                    Surgical or transcatheter replacement character        2
    3                                  Body mass index (kg/m2)   numeric      190
    4                         Major postoperative complication   integer        2
    5                    Cardiopulmonary bypass time (minutes)   numeric      120
    6                                       Creatinine (mg/dL)   numeric      147
    7                                                    Death   integer        2
    8                                    Discharge destination character        3
    9                                        Date of operation      Date      766
    10                                       Mitral E/e' ratio   numeric      188
    11                                                  Female   integer        2
    12                                History of heart failure   integer        2
    13                                                Diabetes   integer        2
    14                                 Hours in intensive care   numeric       82
    15                 Follow-up to death or censoring (years)   numeric      777
    16                  Years from 1 January 1990 to operation   numeric      787
    17 Follow-up to reintervention, death or censoring (years)   numeric      775
    18                        Follow-up to reoperation (years)   numeric      774
    19                               Left atrial diameter (cm)   numeric       32
    20                 Postoperative length of stay (log days)   numeric       19
    21                     Postoperative length of stay (days)   integer       19
    22                         LV end-diastolic dimension (cm)   numeric       36
    23                                LV ejection fraction (%)   numeric       53
    24                          LV end-systolic dimension (cm)   numeric       40
    25                                                    Male   integer        2
    26                           In a matched pair (simulated)   integer        2
    27                Postoperative mitral regurgitation grade character        4
    28                            Mitral repair or replacement character        2
    29                                          Non-white race   integer        2
    30                                   NYHA functional class   numeric        4
    31                          Patient identifier (synthetic) character      800
    32                                    LV mass index (g/m2)   numeric      141
    33                      Number of prior cardiac operations   integer        4
    34                                                    Race character        3
    35                                          Reintervention   integer        2
    36                                             Reoperation   integer        2
    37                             RV systolic pressure (mmHg)   numeric       58
    38                                    Postoperative stroke character        2
    39                                         Prosthesis size character        3
    40                                         Prosthesis type character        3
    41                                   Prolonged ventilation   integer        2
       pct_missing
    1          0.0
    2          0.0
    3          0.0
    4          0.0
    5          0.0
    6          9.4
    7          0.0
    8          0.0
    9          0.0
    10         5.4
    11         0.0
    12         0.0
    13         0.0
    14         0.0
    15         0.0
    16         0.0
    17         0.0
    18         0.0
    19         5.8
    20         0.0
    21         0.0
    22         5.4
    23         0.0
    24         4.6
    25         0.0
    26         0.0
    27         0.0
    28         0.0
    29         0.0
    30         0.0
    31         0.0
    32         0.0
    33         0.0
    34         0.0
    35         0.0
    36         0.0
    37         4.2
    38         0.0
    39         0.0
    40         0.0
    41         0.0

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

           variable                                                   label   n
    1      iv_opyrs                  Years from 1 January 1990 to operation 800
    2           age                                Age at operation (years) 800
    3        female                                                  Female 800
    4           bmi                                 Body mass index (kg/m2) 800
    5        hx_chf                                History of heart failure 800
    6         hx_dm                                                Diabetes 800
    7       nyha_pr                                   NYHA functional class 800
    8          lvef                                LV ejection fraction (%) 800
    9      plvmassi                                    LV mass index (g/m2) 800
    10     creat_pr                                      Creatinine (mg/dL) 725
    11         dead                                                   Death 800
    12      iv_dead                 Follow-up to death or censoring (years) 800
    13         reop                                             Reoperation 800
    14      iv_reop                        Follow-up to reoperation (years) 800
    15         vent                                   Prolonged ventilation 800
    16    icu_hours                                 Hours in intensive care 800
    17         male                                                    Male 800
    18     nonwhite                                          Non-white race 800
    19    prior_ops                      Number of prior cardiac operations 800
    20   match_pair                           In a matched pair (simulated) 800
    21 complication                        Major postoperative complication 800
    22          los                     Postoperative length of stay (days) 800
    23      log_los                 Postoperative length of stay (log days) 800
    24     cpb_time                   Cardiopulmonary bypass time (minutes) 800
    25        lvedd                         LV end-diastolic dimension (cm) 757
    26        lvesd                          LV end-systolic dimension (cm) 763
    27      la_diam                               Left atrial diameter (cm) 754
    28         rvsp                             RV systolic pressure (mmHg) 766
    29          e_e                                       Mitral E/e' ratio 757
    30        reint                                          Reintervention 800
    31     iv_reint Follow-up to reintervention, death or censoring (years) 800
       nmiss       mean        std      min      max       sum
    1      0  17.432389  9.8319268  0.06600  34.9400 13945.911
    2      0  62.376250 12.1764123 32.00000 100.0000 49901.000
    3      0   0.373750  0.4841011  0.00000   1.0000   299.000
    4      0  27.902000  4.4563207 15.10000  44.8000 22321.600
    5      0   0.303750  0.4601637  0.00000   1.0000   243.000
    6      0   0.218750  0.4136573  0.00000   1.0000   175.000
    7      0   2.272500  0.7819899  1.00000   4.0000  1818.000
    8      0  51.777500  9.7894221 20.00000  75.0000 41422.000
    9      0 121.031250 29.4092912 28.00000 207.0000 96825.000
    10    75   1.086152  0.3555899  0.43000   2.7600   787.460
    11     0   0.556250  0.4971367  0.00000   1.0000   445.000
    12     0   9.479378  8.0874926  0.00025  34.6040  7583.503
    13     0   0.250000  0.4332836  0.00000   1.0000   200.000
    14     0   7.319961  6.6628164  0.00000  33.9340  5855.969
    15     0   0.315000  0.4648065  0.00000   1.0000   252.000
    16     0  33.922500 20.1484849  4.00000 108.0000 27138.000
    17     0   0.626250  0.4841011  0.00000   1.0000   501.000
    18     0   0.211250  0.4084507  0.00000   1.0000   169.000
    19     0   0.392500  0.6663323  0.00000   3.0000   314.000
    20     0   0.593750  0.4914395  0.00000   1.0000   475.000
    21     0   0.182500  0.3864977  0.00000   1.0000   146.000
    22     0   6.317500  2.6249394  1.00000  19.0000  5054.000
    23     0   1.763026  0.4032844  0.00000   2.9444  1410.421
    24     0 104.790000 24.6238973 35.00000 185.0000 83832.000
    25    43   5.338705  0.8181764  3.70000   7.2000  4041.400
    26    37   3.713237  1.0086088  2.10000   6.1000  2833.200
    27    46   4.270955  0.6164564  2.80000   6.0000  3220.300
    28    34  38.386423 11.7306157 10.00000  68.0000 29404.000
    29    43  12.114531  4.4209668  0.30000  25.2000  9170.700
    30     0   0.161250  0.3679915  0.00000   1.0000   129.000
    31     0   8.194820  7.4723428  0.00025  34.4260  6555.856

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

| variable |   n | nmiss |   0% |    1% |   5% |  10% |  15% |  50% |   85% |  90% |   95% |   99% |  100% |
|:---------|----:|------:|-----:|------:|-----:|-----:|-----:|-----:|------:|-----:|------:|------:|------:|
| age      | 800 |     0 | 32.0 | 35.00 | 41.0 | 46.0 | 49.0 | 63.0 | 75.00 | 78.0 | 82.00 | 90.00 | 100.0 |
| bmi      | 800 |     0 | 15.1 | 18.05 | 20.8 | 22.2 | 23.2 | 27.8 | 32.35 | 33.6 | 35.35 | 39.85 |  44.8 |

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

| variable |   n | nmiss |  0% |  1% |  5% | 10% | 15% | 50% | 85% | 90% | 95% |   99% | 100% |
|:---------|----:|------:|----:|----:|----:|----:|----:|----:|----:|----:|----:|------:|-----:|
| lvef     | 800 |     0 |  20 |  28 |  35 |  39 |  42 |  52 |  62 |  64 |  67 |  73.0 |   75 |
| plvmassi | 800 |     0 |  28 |  53 |  73 |  83 |  91 | 121 | 152 | 158 | 170 | 191.5 |  207 |

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

| variable |   n | nmiss |   0% |   1% |   5% | 10% |  15% |  50% |  85% |  90% | 95% |  99% | 100% |
|:---------|----:|------:|-----:|-----:|-----:|----:|-----:|-----:|-----:|-----:|----:|-----:|-----:|
| creat_pr | 725 |    75 | 0.43 | 0.53 | 0.63 | 0.7 | 0.75 | 1.02 | 1.43 | 1.52 | 1.7 | 2.34 | 2.76 |

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

## About this run

| Group           | Item             | Value                     |
|:----------------|:-----------------|:--------------------------|
| Run             | Started          | 2026-10-23 13:35:17 EDT   |
|                 | Ended            | 2026-10-23 13:35:17 EDT   |
|                 | Duration         | 0 s                       |
|                 | Status           | final                     |
|                 | Rendered by      | gallery                   |
|                 | Host             | gallery                   |
| Job             | File             | dc.general.cohort.eda.qmd |
|                 | Template         | dc.general                |
|                 | Subject          | cohort                    |
|                 | Type             | eda                       |
|                 | hvtiRtemplates   | 1.5.0                     |
| Dataset `built` | Version file     | built_20261023.parquet    |
|                 | Registered       | 2026-10-23                |
|                 | Source file      | built.rds                 |
|                 | Rows kept        | 800 rows on 800 patients  |
|                 | WHERE            | none                      |
|                 | sha256           | b236a472f1f3              |
|                 | Manifest         | current                   |
| Reproducibility | renv             | not active                |
|                 | renv.lock sha256 | d09f96b6cd21              |
