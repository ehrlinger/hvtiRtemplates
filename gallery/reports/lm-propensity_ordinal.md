# Ordered-treatment propensity model

# Ordered-treatment propensity model

Published

2026-10-12 16:18

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
if (utils::packageVersion("hvtiRpropensity") < "0.1.10") stop("This template needs hvtiRpropensity >= 0.1.10.", call. = FALSE)
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

**final** · data `built` `built_20261012.parquet`, registered 2026-10-12
· rendered by gallery on gallery · hvtiRtemplates 1.3.1

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
                                          reduce = REDUCE, join_key = JOIN_KEY, one_row_per_patient = TRUE)
# This job's data are the model's training data, which lm-checkpred tells from its validation data.
job_data$provenance$role <- "training"
if (!is.null(job_data$provenance_join)) job_data$provenance_join$role <- "training"
d <- job_data$data
.provenance_data <- c(if (exists(".provenance_data")) .provenance_data else list(), list(job_data$provenance),
                      if (!is.null(job_data$provenance_join)) list(job_data$provenance_join))
# The identifier column read_job_data() used: MRN or eMRN when there is no ccfid.
.id <- attr(job_data$record, "selection")$id
knitr::kable(job_data$record, col.names = c("Data", ""))
# A column the study choices name that the data lack stops here, naming the setting to change.
hvtiRtemplates:::.check_job_columns(d, TREATMENT = TREATMENT, PREDICTORS = PREDICTORS)
```

| Data                |                                          |
|:--------------------|:-----------------------------------------|
| Source              | dataset `built` (built_20261012.parquet) |
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

Table 2: Fit status of the model

Code

``` r
knitr::kable(fit$tables$estimates)
```

| term | estimate | std.error | statistic | df | p.value | conf.low | conf.high | odds_ratio | pooled |
|:---|---:|---:|---:|---:|---:|---:|---:|---:|:---|
| age | -0.0075169 | 0.0055295 | -1.3594215 | Inf | 0.1740131 | -0.0183546 | 0.0033207 | 0.9925112 | FALSE |
| female | -1.3321228 | 0.1466485 | -9.0837785 | Inf | 0.0000000 | -1.6195486 | -1.0446969 | 0.2639164 | FALSE |
| hx_chf | 0.2926523 | 0.1615654 | 1.8113554 | Inf | 0.0700859 | -0.0240100 | 0.6093146 | 1.3399768 | FALSE |
| hx_dm | 0.0230820 | 0.1637746 | 0.1409376 | Inf | 0.8879192 | -0.2979102 | 0.3440742 | 1.0233504 | FALSE |
| lvef | -0.0024774 | 0.0076051 | -0.3257515 | Inf | 0.7446124 | -0.0173830 | 0.0124283 | 0.9975257 | FALSE |
| bmi | 0.1249699 | 0.0160443 | 7.7890614 | Inf | 0.0000000 | 0.0935237 | 0.1564161 | 1.1331143 | FALSE |
| threshold:small\|medium | 1.6504835 | 0.6906183 | 2.3898635 | Inf | 0.0168546 | 0.2968965 | 3.0040704 | NA | FALSE |
| threshold:medium\|large | 3.6503472 | 0.7007987 | 5.2088382 | Inf | 0.0000002 | 2.2768069 | 5.0238875 | NA | FALSE |

Table 3: Coefficient estimates of the fitted model

Code

``` r
knitr::kable(fit$tables$covariance)
```

|  | age | female | hx_chf | hx_dm | lvef | bmi | threshold:small\|medium | threshold:medium\|large |
|:---|---:|---:|---:|---:|---:|---:|---:|---:|
| age | 0.0000306 | 0.0000018 | 0.0000437 | -0.0000273 | -0.0000010 | 0.0000009 | 0.0018944 | 0.0018738 |
| female | 0.0000018 | 0.0215058 | -0.0010081 | 0.0004882 | -0.0000298 | -0.0002061 | 0.0019821 | -0.0017919 |
| hx_chf | 0.0000437 | -0.0010081 | 0.0261034 | 0.0004604 | 0.0004755 | 0.0000635 | 0.0361898 | 0.0369932 |
| hx_dm | -0.0000273 | 0.0004882 | 0.0004604 | 0.0268221 | 0.0000049 | -0.0000434 | 0.0035119 | 0.0035146 |
| lvef | -0.0000010 | -0.0000298 | 0.0004755 | 0.0000049 | 0.0000578 | -0.0000041 | 0.0029529 | 0.0029467 |
| bmi | 0.0000009 | -0.0002061 | 0.0000635 | -0.0000434 | -0.0000041 | 0.0002574 | 0.0068126 | 0.0071511 |
| threshold:small\|medium | 0.0018944 | 0.0019821 | 0.0361898 | 0.0035119 | 0.0029529 | 0.0068126 | 0.4769536 | 0.4790811 |
| threshold:medium\|large | 0.0018738 | -0.0017919 | 0.0369932 | 0.0035146 | 0.0029467 | 0.0071511 | 0.4790811 | 0.4911189 |

Table 4: Covariance matrix of the coefficient estimates

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

Table 5: Standardized mean differences, each treatment level against the
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

Table 6: Patients in each group

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

Table 7: Patients in each propensity quintile

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

Table 8: Patients in each propensity decile

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
| Run | Started | 2026-10-12 16:18:55 EDT |
|  | Ended | 2026-10-12 16:18:55 EDT |
|  | Duration | 0 s |
|  | Status | final |
|  | Rendered by | gallery |
|  | Host | gallery |
| Job | File | lm.propensity_ordinal.valvesize.propensity.qmd |
|  | Template | lm.propensity_ordinal |
|  | Subject | valvesize |
|  | Type | propensity |
|  | hvtiRtemplates | 1.3.1 |
| Dataset `built` | Version file | built_20261012.parquet |
|  | Registered | 2026-10-12 |
|  | Source file | built.rds |
|  | Rows kept | 800 rows on 800 patients |
|  | WHERE | none |
|  | sha256 | 27b97c1d78ec |
|  | Manifest | current |
| Reproducibility | renv | not active |
