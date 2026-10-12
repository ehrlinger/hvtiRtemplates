# Binary-treatment propensity model

# Binary-treatment propensity model

Published

2026-10-12 16:18

Fits a binary-treatment propensity model, including pooled inference for
stacked imputations and the scored columns used by matching and
weighting jobs.

Code

``` r
SUBJECT <- "approach"
TYPE    <- "propensity"
.in <- knitr::current_input(dir = TRUE)
suppressPackageStartupMessages({
  library(hvtiRpropensity)
  library(hvtiRutilities)
})
if (utils::packageVersion("hvtiRpropensity") < "0.1.10") {
  stop("This template needs hvtiRpropensity >= 0.1.10.", call. = FALSE)
}
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

TREATMENT <- "approach"
PREDICTORS <- c("age", "female", "hx_chf", "hx_dm", "lvef", "bmi")
TREATMENT_LEVELS <- c("surgical", "transcatheter")
TREATED_LEVEL <- "transcatheter"
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
fit <- hvtiRpropensity::ps_logistic(
  model_formula, d, treatment_col = TREATMENT, id_col = .id,
  imputation_col = IMPUTATION, covariates = PREDICTORS,
  treatment_levels = TREATMENT_LEVELS, treated_level = TREATED_LEVEL
)
```

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
| (Intercept) | -4.4144100 | 0.8833955 | -4.9970939 | Inf | 0.0000006 | -6.1458333 | -2.6829868 | 0.0121017 | FALSE |
| age | 0.0859845 | 0.0082538 | 10.4176104 | Inf | 0.0000000 | 0.0698074 | 0.1021616 | 1.0897895 | FALSE |
| female | -0.2280664 | 0.1729966 | -1.3183289 | Inf | 0.1873936 | -0.5671335 | 0.1110007 | 0.7960714 | FALSE |
| hx_chf | 1.0893223 | 0.1952936 | 5.5778689 | Inf | 0.0000000 | 0.7065538 | 1.4720908 | 2.9722592 | FALSE |
| hx_dm | 0.1208708 | 0.1980184 | 0.6104018 | Inf | 0.5415957 | -0.2672381 | 0.5089797 | 1.1284791 | FALSE |
| lvef | -0.0252926 | 0.0093520 | -2.7045057 | Inf | 0.0068406 | -0.0436223 | -0.0069630 | 0.9750245 | FALSE |
| bmi | -0.0239989 | 0.0187276 | -1.2814727 | Inf | 0.2000277 | -0.0607043 | 0.0127065 | 0.9762868 | FALSE |

Table 3: Coefficient estimates of the fitted model

Code

``` r
knitr::kable(fit$tables$covariance)
```

|  | (Intercept) | age | female | hx_chf | hx_dm | lvef | bmi |
|:---|---:|---:|---:|---:|---:|---:|---:|
| (Intercept) | 0.7803875 | -0.0040721 | -0.0074753 | -0.0700837 | -0.0024740 | -0.0042977 | -0.0094316 |
| age | -0.0040721 | 0.0000681 | -0.0000754 | 0.0003480 | -0.0000012 | -0.0000062 | -0.0000046 |
| female | -0.0074753 | -0.0000754 | 0.0299278 | -0.0007026 | 0.0007122 | 0.0000056 | 0.0000398 |
| hx_chf | -0.0700837 | 0.0003480 | -0.0007026 | 0.0381396 | 0.0006987 | 0.0006687 | 0.0000078 |
| hx_dm | -0.0024740 | -0.0000012 | 0.0007122 | 0.0006987 | 0.0392113 | -0.0000329 | -0.0001929 |
| lvef | -0.0042977 | -0.0000062 | 0.0000056 | 0.0006687 | -0.0000329 | 0.0000875 | 0.0000005 |
| bmi | -0.0094316 | -0.0000046 | 0.0000398 | 0.0000078 | -0.0001929 | 0.0000005 | 0.0003507 |

Table 4: Covariance matrix of the coefficient estimates

Code

``` r
knitr::kable(fit$tables$smd)
```

|        | variable |     smd |
|:-------|:---------|--------:|
| age    | age      |  0.8446 |
| female | female   | -0.0664 |
| hx_chf | hx_chf   |  0.4385 |
| hx_dm  | hx_dm    |  0.0450 |
| lvef   | lvef     | -0.3432 |
| bmi    | bmi      | -0.0920 |

Table 5: Standardized mean differences between the treatment groups

Code

``` r
knitr::kable(fit$tables$group_counts)
```

| group         | treated |   n |
|:--------------|:--------|----:|
| surgical      | FALSE   | 514 |
| transcatheter | TRUE    | 286 |

Table 6: Patients in each group

Code

``` r
MODEL_PATH <- set_path("estimates", "lm-propensity_binary.rds")
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
| Run | Started | 2026-10-12 16:18:37 EDT |
|  | Ended | 2026-10-12 16:18:38 EDT |
|  | Duration | 0 s |
|  | Status | final |
|  | Rendered by | gallery |
|  | Host | gallery |
| Job | File | lm.propensity_binary.approach.propensity.qmd |
|  | Template | lm.propensity_binary |
|  | Subject | approach |
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
