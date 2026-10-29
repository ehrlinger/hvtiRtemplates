# Continuous-exposure balancing score

# Continuous-exposure balancing score

Published

2026-10-29 12:54

Fits an ordinary least-squares balancing score for a continuous
exposure, such as a nadir hematocrit or a dose: the exposure each
patient was expected to receive given their pre-exposure covariates.
Patients are then stratified on that expected value, so a within-stratum
comparison sets patients with a similar expected exposure side by side.
This is a score for the exposure, not an analysis of an outcome;
`rm-linear` fits an outcome.

Code

``` r
SUBJECT <- "cpbtime"
TYPE    <- "balancing"
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

**final** · data `built` `built_20261029.parquet`, dated 2026-10-29 ·
rendered by gallery on gallery · hvtiRtemplates 1.5.4

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

# Demo: the continuous exposure, named as the column.
OUTCOME <- "cpb_time"
# Demo: the scale the exposure is modeled on. "identity" models it as measured;
# "log" models log(OUTCOME), for a skewed exposure such as a dose. The score is
# then an expected log exposure; the report's reading follows this choice.
RESPONSE_SCALE <- "identity"
PREDICTORS <- c("age", "female", "bmi", "hx_chf", "hx_dm", "lvef")
N_STRATA <- 5L
IMPUTATION <- NULL                          # Demo: imputation column, or NULL.
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
# This job's data are the model's training data.
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
# RESPONSE_SCALE as a plain "identity" or "log", so the fit, the paragraph on
# reading it and the figures all branch on one value.
RESPONSE_SCALE <- hvtiRtemplates:::.response_scale(RESPONSE_SCALE)
# The model's response on the RESPONSE_SCALE chosen: OUTCOME, or log(OUTCOME).
.response <- hvtiRtemplates:::.response_term(d, OUTCOME, RESPONSE_SCALE)
```

| Data                |                                          |
|:--------------------|:-----------------------------------------|
| Source              | dataset `built` (built_20261029.parquet) |
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
.missing_values <- hvtiRtemplates:::.missing_cases(d, OUTCOME = .response, PREDICTORS = PREDICTORS,
                                                   imputation = IMPUTATION)
knitr::kable(.missing_values)
```

| Variable       | Setting | Missing                                |
|:---------------|:--------|:---------------------------------------|
| Complete cases |         | 800 of 800 rows analyzed; none dropped |

Table 2: Missing values in the model’s variables

Code

``` r
model_formula <- stats::reformulate(PREDICTORS, response = .response)
fit <- hvtiRpropensity::bs_continuous(
  model_formula, d, outcome_col = OUTCOME, id_col = .id,
  imputation_col = IMPUTATION, n_strata = N_STRATA, covariates = PREDICTORS
)
```

Code

``` r
cat(hvtiRtemplates:::.response_note(model_formula, RESPONSE_SCALE, "exposure"))
```

The model fitted is
`cpb_time ~ age + female + bmi + hx_chf + hx_dm + lvef`. The exposure is
modeled as measured: a coefficient is the expected change in the
exposure, in its own units, for a unit change in a numeric predictor, or
against the reference level of a categorical one, the others held fixed.

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
# The paragraph above says the scale these coefficients are on.
knitr::kable(fit$tables$estimates)
```

| term | estimate | std.error | statistic | df | p.value | conf.low | conf.high | pooled |
|:---|---:|---:|---:|---:|---:|---:|---:|:---|
| (Intercept) | 52.0135833 | 7.9514205 | 6.5414203 | 793 | 0.0000000 | 36.4052629 | 67.6219037 | FALSE |
| age | 0.5218523 | 0.0638027 | 8.1791604 | 793 | 0.0000000 | 0.3966102 | 0.6470944 | FALSE |
| female | 0.0018968 | 1.6011159 | 0.0011847 | 793 | 0.9990551 | -3.1410297 | 3.1448233 | FALSE |
| bmi | 1.1313213 | 0.1738584 | 6.5071433 | 793 | 0.0000000 | 0.7900443 | 1.4725983 | FALSE |
| hx_chf | 13.5229710 | 1.8466067 | 7.3231463 | 793 | 0.0000000 | 9.8981559 | 17.1477860 | FALSE |
| hx_dm | 6.6053732 | 1.8735162 | 3.5256558 | 793 | 0.0004467 | 2.9277358 | 10.2830105 | FALSE |
| lvef | -0.3262833 | 0.0865909 | -3.7681017 | 793 | 0.0001767 | -0.4962578 | -0.1563089 | FALSE |

Table 4: Coefficient estimates of the fitted model

Code

``` r
knitr::kable(fit$tables$covariance)
```

|  | (Intercept) | age | female | bmi | hx_chf | hx_dm | lvef |
|:---|---:|---:|---:|---:|---:|---:|---:|
| (Intercept) | 63.2250885 | -0.2562311 | -0.8171803 | -0.8481653 | -4.9837187 | -0.3966630 | -0.4069752 |
| age | -0.2562311 | 0.0040708 | -0.0029391 | 0.0000522 | 0.0077946 | -0.0034038 | 0.0000064 |
| female | -0.8171803 | -0.0029391 | 2.5635722 | 0.0069950 | -0.0608956 | 0.0449934 | -0.0027839 |
| bmi | -0.8481653 | 0.0000522 | 0.0069950 | 0.0302267 | 0.0039359 | -0.0072906 | -0.0000133 |
| hx_chf | -4.9837187 | 0.0077946 | -0.0608956 | 0.0039359 | 3.4099563 | 0.0590486 | 0.0649272 |
| hx_dm | -0.3966630 | -0.0034038 | 0.0449934 | -0.0072906 | 0.0590486 | 3.5100629 | 0.0001897 |
| lvef | -0.4069752 | 0.0000064 | -0.0027839 | -0.0000133 | 0.0649272 | 0.0001897 | 0.0074980 |

Table 5: Covariance matrix of the coefficient estimates

Code

``` r
knitr::kable(fit$tables$strata_counts)
```

| stratum |   n |
|:--------|----:|
| 1       | 160 |
| 2       | 160 |
| 3       | 160 |
| 4       | 160 |
| 5       | 160 |

Table 6: Patients in each stratum

Code

``` r
MODEL_PATH <- set_path("estimates", "rm-balancing_continuous.rds")
.fit_provenance <- hvtiRtemplates:::.lm_fit_provenance(fit)
fit <- hvtiRtemplates:::.attach_handoff_lineage(
  fit, data = if (exists(".provenance_data")) .provenance_data else list(),
  analysis = .fit_provenance$analysis, cohort = .fit_provenance$cohort,
  selection = attr(job_data$record, "selection")
)
# The saved copy holds a study-keyed digest of each patient ID, never the ID, so the file names no
# patient. A later job reattaches its own data by digesting its IDs with the same key.
saveRDS(hvtiRtemplates:::.digest_bundle_ids(fit, .root), MODEL_PATH)
```

## About this run

| Group | Item | Value |
|:---|:---|:---|
| Run | Started | 2026-10-29 12:54:44 EDT |
|  | Ended | 2026-10-29 12:54:44 EDT |
|  | Duration | 1 s |
|  | Status | final |
|  | Rendered by | gallery |
|  | Host | gallery |
| Job | File | rm.balancing_continuous.cpbtime.balancing.qmd |
|  | Template | rm.balancing_continuous |
|  | Subject | cpbtime |
|  | Type | balancing |
|  | hvtiRtemplates | 1.5.4 |
| Dataset `built` | Version file | built_20261029.parquet |
|  | Version date | 2026-10-29 |
|  | Source file | built.rds |
|  | Rows kept | 800 rows on 800 patients |
|  | WHERE | none |
|  | sha256 | b236a472f1f3 |
|  | Manifest | current |
| Reproducibility | renv | not active |
|  | renv.lock sha256 | d09f96b6cd21 |
