# Validate a saved binary logistic model

# Validate a saved binary logistic model

Published

2026-10-15 11:15

Applies a saved `lm-binary` bundle to a declared validation cohort. This
job never refits, updates, or overwrites the source model.

Code

``` r
SUBJECT <- "stroke"
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

**final** · data `built` `built_20261015.parquet`, registered 2026-10-15
· rendered by gallery on gallery · hvtiRtemplates 1.4.0

Code

``` r
# The validation cohort: another registered dataset in DATASET, or rows of the
# study dataset that the training job did not use, chosen by WHERE. To validate
# on a file of its own, put it in the study's datasets folder and register it
# once, from the study root, under a name of its own:
#   hvtiRutilities::register_data(built = "validation.csv", dataset = "validation",
#                                 role = "named", population = "Operated 2015 onward")
# then set DATASET <- "validation". It must identify patients by the same column
# as the training data: the training-overlap chunk compares the two cohorts by
# that identifier and stops if they share a patient.
# Demo: the registered dataset this job reads ("built" is the study dataset).
DATASET <- "built"

# Demo: an hvtiRdatabuild analysis set, or NULL to read the whole dataset.
ANALYSIS_SET <- NULL

# Demo: rows to keep, dplyr::filter() style, or NULL to keep every row:
#   WHERE <- quote(age >= 18)
#   WHERE <- rlang::exprs(age >= 18, hx_chf == 1)
WHERE <- quote(year >= 2015)

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

MODEL_FILE <- "lm-binary.rds"              # Demo: reviewed source bundle, as lm-binary saved it.
# Optional, and needs no edit: the set whose estimates hold MODEL_FILE. NULL is
# this job's own set, which is where it is when this job shares the subject and
# type of the lm-binary job. A validation job in a set of its own names the
# training job's set, "<subject>-<type>", for example MODEL_SET <- "stroke-model".
MODEL_SET <- NULL
OUTCOME <- "stroke"
GROUPS <- 5L
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
# This job's data are the validation data; the saved model carries its training data.
job_data$provenance$role <- "validation"
if (!is.null(job_data$provenance_join)) job_data$provenance_join$role <- "validation"
d <- job_data$data
.provenance_data <- c(if (exists(".provenance_data")) .provenance_data else list(), list(job_data$provenance),
                      if (!is.null(job_data$provenance_join)) list(job_data$provenance_join))
# The identifier column read_job_data() used: MRN or eMRN when there is no ccfid.
.id <- attr(job_data$record, "selection")$id
knitr::kable(job_data$record, col.names = c("Data", ""))
# A column the study choices name that the data lack stops here, naming the setting to change.
hvtiRtemplates:::.check_job_columns(d, OUTCOME = OUTCOME)
```

| Data                |                                          |
|:--------------------|:-----------------------------------------|
| Source              | dataset `built` (built_20261015.parquet) |
| Rows read           | 800                                      |
| ID                  | `patient_id`                             |
| Identifiers dropped | none                                     |
| `year >= 2015`      | removed 572                              |
| Rows kept           | 228 rows on 228 patients                 |

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
# MODEL_FILE is a file name and MODEL_SET a set name, so neither can reach outside the study's estimates.
MODEL_PATH <- hvtiRtemplates:::.handoff_path(MODEL_FILE, MODEL_SET, .root, function(file) set_path("estimates", file),
                                             upstream = "lm-binary", set_example = "stroke-model")
.model_read <- hvtiRtemplates:::.read_handoff(
  MODEL_PATH, "source-model", hvtiRutilities::study_config(start = .root), "the source lm job"
)
model <- .model_read$value
if (is.null(.model_read$lineage$analysis) || is.null(.model_read$lineage$cohort)) {
  stop(
    "The source model has no runtime analysis and cohort metadata. Rebuild it by rendering the source lm job.",
    call. = FALSE
  )
}
.provenance_data <- c(.model_read$lineage$data, .provenance_data)
.provenance_artifacts <- c(.model_read$lineage$artifacts, list(.model_read$record))
```

Code

``` r
# A validation cohort that shares patients with the training data measures how
# the model fits its own data, not how it predicts. The saved model keeps its
# training rows, so this compares patients rather than settings. It reports how
# many are shared, never which.
.train_id <- model$meta$id_col
if (!is.character(.train_id) || length(.train_id) != 1L || !.train_id %in% names(model$data)) {
  stop("The saved model does not keep its training identifiers, so this job cannot check that the validation ",
       "patients are new: refit it with the current lm-binary template.", call. = FALSE)
}
if (!identical(tolower(.id), tolower(.train_id))) {
  stop("The validation data identify patients by `", .id, "`, the training data by `", .train_id,
       "`: set ID so both use the same identifier.", call. = FALSE)
}
# A missing identifier cannot be compared, so it would pass as a new patient.
if (anyNA(d[[.id]]) || anyNA(model$data[[.train_id]])) {
  stop("Some patients have no `", .id, "` in the validation or training data, so the check cannot tell ",
       "whether they are new: drop or fix those rows in the data build.", call. = FALSE)
}
# A model saved by a current lm template keeps a study-keyed digest of each training ID, so the validation
# IDs are digested with the same key to compare. One saved before that holds raw identifiers, and is
# compared raw so it still validates; re-save it with its lm template to clear them from the file.
.validation_ids <- unique(hvtiRtemplates:::.bundle_ids(model, d[[.id]], .root))
.shared <- sum(.validation_ids %in% as.character(model$data[[.train_id]]))
if (.shared && .shared == length(.validation_ids)) {
  stop("The validation data are the training data: set DATASET or WHERE to the validation cohort.", call. = FALSE)
}
if (.shared) {
  stop(.shared, " validation patients were in the training data: set DATASET or WHERE to the validation cohort.",
       call. = FALSE)
}
```

Code

``` r
validation <- hvtiRpropensity::validate_logistic(
  model, d, outcome_col = OUTCOME, prediction_col = "predicted", groups = GROUPS
)
```

Code

``` r
knitr::kable(validation$tables$performance)
```

|   n | observed | expected | oe_ratio |       auc |     brier |
|----:|---------:|---------:|---------:|----------:|----------:|
| 228 |       26 | 22.50584 | 1.155256 | 0.7456207 | 0.0938063 |

Table 2: Performance of the saved model on the validation data

Code

``` r
knitr::kable(validation$tables$calibration)
```

| group |   n | observed | expected |
|------:|----:|---------:|---------:|
|     1 |  45 |        0 | 1.683087 |
|     2 |  46 |        4 | 2.632402 |
|     3 |  45 |        4 | 3.698191 |
|     4 |  46 |        5 | 5.552217 |
|     5 |  46 |       13 | 8.939945 |

Table 3: Calibration of the saved model on the validation data

Code

``` r
VALIDATION_PATH <- set_path("estimates", "lm-checkpred.rds")
if (identical(normalizePath(MODEL_PATH, mustWork = FALSE),
              normalizePath(VALIDATION_PATH, mustWork = FALSE))) {
  stop("Validation output would overwrite the source model: ", MODEL_PATH, call. = FALSE)
}
.validation_provenance <- hvtiRtemplates:::.lm_validation_provenance(validation)
.validation_analysis <- list(
  training = .model_read$lineage$analysis,
  validation = .validation_provenance$analysis
)
.validation_cohort <- list(
  training = .model_read$lineage$cohort,
  validation = .validation_provenance$cohort
)
validation <- hvtiRtemplates:::.attach_handoff_lineage(
  validation,
  data = .provenance_data,
  artifacts = .provenance_artifacts,
  analysis = .validation_analysis,
  cohort = .validation_cohort,
  selection = attr(job_data$record, "selection")
)
# The saved copy digests the validation IDs as the source model does its own. Models saved digested are
# left alone, since digesting them again would no longer match their patients.
saveRDS(hvtiRtemplates:::.digest_bundle_ids(validation, .root, .id,
                                            skip = if (isTRUE(model$meta$id_digest)) "models"),
        VALIDATION_PATH)
```

## About this run

| Group | Item | Value |
|:---|:---|:---|
| Run | Started | 2026-10-15 11:15:00 EDT |
|  | Ended | 2026-10-15 11:15:00 EDT |
|  | Duration | 0 s |
|  | Status | final |
|  | Rendered by | gallery |
|  | Host | gallery |
| Job | File | lm.checkpred.stroke.model.qmd |
|  | Template | lm.checkpred |
|  | Subject | stroke |
|  | Type | model |
|  | hvtiRtemplates | 1.4.0 |
| Dataset `built` | Version file | built_20261015.parquet |
|  | Registered | 2026-10-15 |
|  | Source file | built.rds |
|  | Rows kept | 228 rows on 228 patients |
|  | WHERE | `year >= 2015` |
|  | sha256 | f632480029c1 |
|  | Manifest | current |
| Upstream | Handoff | `stroke-model/lm-binary.rds` (source-model), rendered 2026-10-15 11:14:55 -0400, data built_20261015.parquet |
| Reproducibility | renv | not active |
