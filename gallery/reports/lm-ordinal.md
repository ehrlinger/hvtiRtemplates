# Ordinal logistic model

# Ordinal logistic model

Published

2026-10-20 15:04

Fits a proportional-odds cumulative-logit model. The complete outcome
order is declared rather than inferred, and thresholds remain distinct
from coefficients.

Code

``` r
SUBJECT <- "mr"
TYPE    <- "model"
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

**final** · data `built` `built_20261020.parquet`, registered 2026-10-20
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

OUTCOME <- "mr_grade"
PREDICTORS <- c("age", "female", "hx_chf", "hx_dm", "lvef", "bmi")
OUTCOME_LEVELS <- c("none", "mild", "moderate", "severe")
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
hvtiRtemplates:::.check_job_columns(d, OUTCOME = OUTCOME, PREDICTORS = PREDICTORS)
```

| Data                |                                          |
|:--------------------|:-----------------------------------------|
| Source              | dataset `built` (built_20261020.parquet) |
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
.missing_values <- hvtiRtemplates:::.missing_cases(d, OUTCOME = OUTCOME, PREDICTORS = PREDICTORS,
                                                   imputation = IMPUTATION)
knitr::kable(.missing_values)
```

| Variable       | Setting | Missing                                |
|:---------------|:--------|:---------------------------------------|
| Complete cases |         | 800 of 800 rows analyzed; none dropped |

Table 2: Missing values in the model’s variables

Code

``` r
model_formula <- stats::reformulate(PREDICTORS, response = OUTCOME)
fit <- hvtiRpropensity::fit_logistic(
  model_formula, d, family = "ordinal", outcome_col = OUTCOME, id_col = .id,
  imputation_col = IMPUTATION, outcome_levels = OUTCOME_LEVELS,
  prediction_prefix = "predicted"
)
```

Code

``` r
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
| age | 0.0697923 | 0.0064324 | 10.8501761 | Inf | 0.0000000 | 0.0571851 | 0.0823995 | 1.0722854 | FALSE |
| female | 0.3811403 | 0.1436094 | 2.6540061 | Inf | 0.0079542 | 0.0996710 | 0.6626096 | 1.4639530 | FALSE |
| hx_chf | 0.4114847 | 0.1640920 | 2.5076468 | Inf | 0.0121538 | 0.0898704 | 0.7330990 | 1.5090566 | FALSE |
| hx_dm | 0.0096598 | 0.1682791 | 0.0574034 | Inf | 0.9542239 | -0.3201612 | 0.3394808 | 1.0097066 | FALSE |
| lvef | -0.0414856 | 0.0079526 | -5.2166013 | Inf | 0.0000002 | -0.0570724 | -0.0258987 | 0.9593632 | FALSE |
| bmi | 0.0190263 | 0.0157074 | 1.2112991 | Inf | 0.2257808 | -0.0117596 | 0.0498122 | 1.0192085 | FALSE |
| threshold:none\|mild | 3.1007034 | 0.7299245 | 4.2479786 | Inf | 0.0000216 | 1.6700778 | 4.5313291 | NA | FALSE |
| threshold:mild\|moderate | 4.3393275 | 0.7382512 | 5.8778466 | Inf | 0.0000000 | 2.8923817 | 5.7862733 | NA | FALSE |
| threshold:moderate\|severe | 5.7865939 | 0.7517419 | 7.6975803 | Inf | 0.0000000 | 4.3132068 | 7.2599810 | NA | FALSE |

Table 4: Coefficient estimates of the fitted model

Code

``` r
knitr::kable(fit$tables$covariance)
```

|  | age | female | hx_chf | hx_dm | lvef | bmi | threshold:none\|mild | threshold:mild\|moderate | threshold:moderate\|severe |
|:---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| age | 0.0000414 | 0.0000225 | 0.0001257 | -0.0000054 | -0.0000046 | 0.0000021 | 0.0024929 | 0.0026061 | 0.0027079 |
| female | 0.0000225 | 0.0206237 | -0.0000353 | 0.0004932 | -0.0000385 | 0.0000481 | 0.0087683 | 0.0094017 | 0.0099698 |
| hx_chf | 0.0001257 | -0.0000353 | 0.0269262 | 0.0004430 | 0.0005052 | 0.0000471 | 0.0438316 | 0.0445029 | 0.0451153 |
| hx_dm | -0.0000054 | 0.0004932 | 0.0004430 | 0.0283179 | -0.0000065 | -0.0000805 | 0.0037374 | 0.0037384 | 0.0036385 |
| lvef | -0.0000046 | -0.0000385 | 0.0005052 | -0.0000065 | 0.0000632 | -0.0000018 | 0.0030560 | 0.0029873 | 0.0029232 |
| bmi | 0.0000021 | 0.0000481 | 0.0000471 | -0.0000805 | -0.0000018 | 0.0002467 | 0.0069406 | 0.0069754 | 0.0070125 |
| threshold:none\|mild | 0.0024929 | 0.0087683 | 0.0438316 | 0.0037374 | 0.0030560 | 0.0069406 | 0.5327897 | 0.5354436 | 0.5390296 |
| threshold:mild\|moderate | 0.0026061 | 0.0094017 | 0.0445029 | 0.0037384 | 0.0029873 | 0.0069754 | 0.5354436 | 0.5450149 | 0.5478020 |
| threshold:moderate\|severe | 0.0027079 | 0.0099698 | 0.0451153 | 0.0036385 | 0.0029232 | 0.0070125 | 0.5390296 | 0.5478020 | 0.5651159 |

Table 5: Covariance matrix of the coefficient estimates

Code

``` r
MODEL_PATH <- set_path("estimates", "lm-ordinal.rds")
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

| Group           | Item             | Value                    |
|:----------------|:-----------------|:-------------------------|
| Run             | Started          | 2026-10-20 15:04:03 EDT  |
|                 | Ended            | 2026-10-20 15:04:03 EDT  |
|                 | Duration         | 0 s                      |
|                 | Status           | final                    |
|                 | Rendered by      | gallery                  |
|                 | Host             | gallery                  |
| Job             | File             | lm.ordinal.mr.model.qmd  |
|                 | Template         | lm.ordinal               |
|                 | Subject          | mr                       |
|                 | Type             | model                    |
|                 | hvtiRtemplates   | 1.4.1                    |
| Dataset `built` | Version file     | built_20261020.parquet   |
|                 | Registered       | 2026-10-20               |
|                 | Source file      | built.rds                |
|                 | Rows kept        | 800 rows on 800 patients |
|                 | WHERE            | none                     |
|                 | sha256           | 07a531bb5b35             |
|                 | Manifest         | current                  |
| Reproducibility | renv             | not active               |
|                 | renv.lock sha256 | d09f96b6cd21             |
