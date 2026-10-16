# Ordered-treatment propensity model

# Ordered-treatment propensity model

Published

2026-10-15 21:16

Fits a proportional-odds propensity model for an explicitly ordered
treatment.

Code

``` r
SUBJECT <- "valvesize"
TYPE    <- "propensity"
.in <- knitr::current_input(dir = TRUE)
suppressPackageStartupMessages({
  library(hvtiRpropensity)
  library(hvtiRutilities)
})
if (utils::packageVersion("hvtiRpropensity") < "0.2.0") stop("This template needs hvtiRpropensity >= 0.2.0.", call. = FALSE)
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

**final** · data `built` `built_20261015.parquet`, registered 2026-10-15
· rendered by gallery on gallery · hvtiRtemplates 1.4.1

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
#     breaks it. This job models one row per
#     patient, so a JOIN without REDUCE stops here.
#   JOIN_KEY: overrides the joined dataset's registered key.
JOIN <- NULL
JOIN_VARS <- NULL
REDUCE <- NULL
JOIN_KEY <- NULL

TREATMENT <- "valve_size"
PREDICTORS <- c("age", "female", "hx_chf", "hx_dm", "lvef", "bmi")
TREATMENT_LEVELS <- c("small", "medium", "large")
IMPUTATION <- NULL
# Stacked imputations repeat each patient once per imputation.
if (!is.null(IMPUTATION)) KEY <- unique(c(KEY, IMPUTATION))
```

Code

``` r
# The checksum of every dataset in manifest.yaml is checked before anything is
# read, so a result can name the data that produced it. It stops on a mismatch.
hvtiRutilities::verify_manifest(file.path(.root, "manifest.yaml"))
.cfg <- study_config(start = .root)
job_data <- hvtiRtemplates::read_job_data(.cfg, dataset = DATASET, analysis_set = ANALYSIS_SET,
                                          where = WHERE, id = ID, key = KEY, join = JOIN, join_vars = JOIN_VARS,
                                          reduce = REDUCE, join_key = JOIN_KEY, one_row_per_patient = TRUE,
                                          imputation = IMPUTATION)
# This job's data are the model's training data, which lm-checkpred tells from its validation data.
job_data$provenance$role <- "training"
if (!is.null(job_data$provenance_join)) job_data$provenance_join$role <- "training"
d <- job_data$data
.provenance_data <- c(if (exists(".provenance_data")) .provenance_data else list(), list(job_data$provenance),
                      if (!is.null(job_data$provenance_join)) list(job_data$provenance_join))
# The identifier column read_job_data() used: MRN or eMRN when there is no ccfid.
.id <- attr(job_data$record, "selection")$id
# The imputation column read_job_data() matched, in the data's own spelling.
IMPUTATION <- attr(job_data$record, "selection")$imputation
knitr::kable(job_data$record, col.names = c("Data", ""))
# A column the study choices name that the data lack stops here, naming the setting to change.
hvtiRtemplates:::.check_job_columns(d, TREATMENT = TREATMENT, PREDICTORS = PREDICTORS)
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
# The fit drops a row missing any model variable, so the cohort it uses is said here,
# counted within one imputation when the data are multiply imputed.
.missing_values <- hvtiRtemplates:::.missing_cases(d, TREATMENT = TREATMENT, PREDICTORS = PREDICTORS,
                                                   imputation = IMPUTATION)
knitr::kable(.missing_values)
```

| Variable       | Setting | Missing                                |
|:---------------|:--------|:---------------------------------------|
| Complete cases |         | 800 of 800 rows analyzed; none dropped |

Table 2: Missing values in the model’s variables

Code

``` r
model_formula <- stats::reformulate(PREDICTORS, response = TREATMENT)
fit <- hvtiRpropensity::ps_ordinal(
  model_formula, d, treatment_col = TREATMENT, id_col = .id,
  imputation_col = IMPUTATION, covariates = PREDICTORS,
  treatment_levels = TREATMENT_LEVELS
)
```

Code

``` r
# A proportional-odds model's signs depend on which way it accumulates; this
# line says which, as lm-ordinal's does.
cat("Cumulative direction:", fit$meta$cumulative_direction, "\n")
```

    Cumulative direction: P(Y <= level) = logistic(threshold - linear predictor) 

Code

``` r
knitr::kable(fit$tables$fit_status)
```

| imputation | converged | n_input | n_analyzed | n_excluded |
|-----------:|:----------|--------:|-----------:|-----------:|
|          1 | TRUE      |     800 |        800 |          0 |

Table 3: Fit status of the model

Code

``` r
knitr::kable(fit$tables$estimates)
```

| term | estimate | std.error | statistic | df | p.value | conf.low | conf.high | odds_ratio | pooled |
|:---|---:|---:|---:|---:|---:|---:|---:|---:|:---|
| age | -0.0075171 | 0.0055738 | -1.3486590 | Inf | 0.1774465 | -0.0184416 | 0.0034073 | 0.9925110 | FALSE |
| female | -1.3321217 | 0.1462178 | -9.1105289 | Inf | 0.0000000 | -1.6187034 | -1.0455400 | 0.2639167 | FALSE |
| hx_chf | 0.2926474 | 0.1615459 | 1.8115434 | Inf | 0.0700568 | -0.0239767 | 0.6092716 | 1.3399703 | FALSE |
| hx_dm | 0.0230920 | 0.1636286 | 0.1411246 | Inf | 0.8877715 | -0.2976142 | 0.3437982 | 1.0233607 | FALSE |
| lvef | -0.0024776 | 0.0075827 | -0.3267455 | Inf | 0.7438603 | -0.0173394 | 0.0123842 | 0.9975255 | FALSE |
| bmi | 0.1249687 | 0.0160140 | 7.8037054 | Inf | 0.0000000 | 0.0935818 | 0.1563556 | 1.1331130 | FALSE |
| threshold:small\|medium | 1.6504353 | 0.6979309 | 2.3647545 | Inf | 0.0180420 | 0.2825158 | 3.0183547 | NA | FALSE |
| threshold:medium\|large | 3.6502805 | 0.7081205 | 5.1548859 | Inf | 0.0000003 | 2.2623898 | 5.0381712 | NA | FALSE |

Table 4: Coefficient estimates of the fitted model

Code

``` r
knitr::kable(fit$tables$covariance)
```

|  | age | female | hx_chf | hx_dm | lvef | bmi | threshold:small\|medium | threshold:medium\|large |
|:---|---:|---:|---:|---:|---:|---:|---:|---:|
| age | 0.0000311 | -0.0000094 | 0.0000547 | -0.0000245 | 0.0000000 | -0.0000007 | 0.0019349 | 0.0019134 |
| female | -0.0000094 | 0.0213797 | -0.0010061 | 0.0002912 | -0.0000115 | -0.0002001 | 0.0024395 | -0.0013769 |
| hx_chf | 0.0000547 | -0.0010061 | 0.0260971 | 0.0005607 | 0.0004953 | 0.0000789 | 0.0385580 | 0.0393679 |
| hx_dm | -0.0000245 | 0.0002912 | 0.0005607 | 0.0267743 | 0.0000045 | -0.0000590 | 0.0031618 | 0.0032375 |
| lvef | 0.0000000 | -0.0000115 | 0.0004953 | 0.0000045 | 0.0000575 | -0.0000017 | 0.0030776 | 0.0030729 |
| bmi | -0.0000007 | -0.0002001 | 0.0000789 | -0.0000590 | -0.0000017 | 0.0002564 | 0.0068146 | 0.0071549 |
| threshold:small\|medium | 0.0019349 | 0.0024395 | 0.0385580 | 0.0031618 | 0.0030776 | 0.0068146 | 0.4871075 | 0.4892972 |
| threshold:medium\|large | 0.0019134 | -0.0013769 | 0.0393679 | 0.0032375 | 0.0030729 | 0.0071549 | 0.4892972 | 0.5014347 |

Table 5: Covariance matrix of the coefficient estimates

Code

``` r
# One row per covariate and level: `level` is compared with `versus`.
knitr::kable(fit$tables$smd)
```

| variable | level  | versus |     smd |
|:---------|:-------|:-------|--------:|
| age      | medium | small  | -0.1164 |
| female   | medium | small  | -0.5793 |
| hx_chf   | medium | small  | -0.0332 |
| hx_dm    | medium | small  |  0.0052 |
| lvef     | medium | small  | -0.0938 |
| bmi      | medium | small  |  0.3633 |
| age      | large  | small  | -0.1503 |
| female   | large  | small  | -0.8577 |
| hx_chf   | large  | small  |  0.1770 |
| hx_dm    | large  | small  |  0.0296 |
| lvef     | large  | small  | -0.1026 |
| bmi      | large  | small  |  0.7105 |

Table 6: Standardized mean differences, each treatment level against the
reference level

Code

``` r
knitr::kable(fit$tables$group_counts)
```

| group  |   n |
|:-------|----:|
| small  | 261 |
| medium | 323 |
| large  | 216 |

Table 7: Patients in each group

Code

``` r
knitr::kable(as.data.frame(table(quintile = fit$data$quintile)))
```

| quintile | Freq |
|:---------|-----:|
| 1        |  160 |
| 2        |  160 |
| 3        |  160 |
| 4        |  160 |
| 5        |  160 |

Table 8: Patients in each propensity quintile

Code

``` r
knitr::kable(as.data.frame(table(decile = fit$data$decile)))
```

| decile | Freq |
|:-------|-----:|
| 1      |   80 |
| 2      |   80 |
| 3      |   80 |
| 4      |   80 |
| 5      |   80 |
| 6      |   80 |
| 7      |   80 |
| 8      |   80 |
| 9      |   80 |
| 10     |   80 |

Table 9: Patients in each propensity decile

Code

``` r
MODEL_PATH <- set_path("estimates", "lm-propensity_ordinal.rds")
.fit_provenance <- hvtiRtemplates:::.lm_fit_provenance(fit)
fit <- hvtiRtemplates:::.attach_handoff_lineage(
  fit, data = if (exists(".provenance_data")) .provenance_data else list(),
  analysis = .fit_provenance$analysis, cohort = .fit_provenance$cohort,
  selection = attr(job_data$record, "selection")
)
# The saved copy holds a study-keyed digest of each patient ID, never the ID, so the file names no
# patient. A later job reattaches its own data by digesting its IDs with the same key: see lm-checkpred.
saveRDS(hvtiRtemplates:::.digest_bundle_ids(fit, .root), MODEL_PATH)
```

## About this run

| Group | Item | Value |
|:---|:---|:---|
| Run | Started | 2026-10-15 21:16:58 EDT |
|  | Ended | 2026-10-15 21:16:59 EDT |
|  | Duration | 0 s |
|  | Status | final |
|  | Rendered by | gallery |
|  | Host | gallery |
| Job | File | lm.propensity_ordinal.valvesize.propensity.qmd |
|  | Template | lm.propensity_ordinal |
|  | Subject | valvesize |
|  | Type | propensity |
|  | hvtiRtemplates | 1.4.1 |
| Dataset `built` | Version file | built_20261015.parquet |
|  | Registered | 2026-10-15 |
|  | Source file | built.rds |
|  | Rows kept | 800 rows on 800 patients |
|  | WHERE | none |
|  | sha256 | b55bc29fc6a4 |
|  | Manifest | current |
| Reproducibility | renv | not active |
