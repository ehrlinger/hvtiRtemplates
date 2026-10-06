# Ordinal logistic model

# Ordinal logistic model

Fits a proportional-odds cumulative-logit model. The complete outcome
order is declared rather than inferred, and thresholds remain distinct
from coefficients.

Code

``` r
.in <- knitr::current_input(dir = TRUE)
.root <- hvtiRtemplates:::.find_study_root(if (is.null(.in)) getwd() else dirname(.in))
.provenance_data <- list()
for (f in list.files(file.path(.root, "R"), pattern = "[.]R$", full.names = TRUE)) source(f)
suppressPackageStartupMessages({
  library(hvtiRpropensity)
  library(hvtiRutilities)
})
if (utils::packageVersion("hvtiRpropensity") < "0.1.7") stop("This template needs hvtiRpropensity >= 0.1.7.", call. = FALSE)
```

Code

``` r
.tok <- paste0("ED", "IT", ":")
.cur <- knitr::current_input()
if (!is.null(.cur)) {
  .src <- readLines(.cur, warn = FALSE)
  .hits <- grep(.tok, .src, fixed = TRUE)
  if (length(.hits)) {
    .msg <- paste0(length(.hits), " unresolved ", .tok, " marker(s) remain in this job:\n",
                   paste0("  - ", trimws(substr(.src[.hits], 1L, 96L)), collapse = "\n"))
    if (tolower(Sys.getenv("HVTI_TEMPLATE_STRICT")) %in% c("", "0", "false", "no")) {
      warning(.msg, "\nRendering as a draft; remove every marker for a final result.", call. = FALSE)
      cat("\n::: {.callout-important title=\"DRAFT -- this job is unfinished\"}\n", .msg, "\n:::\n", sep = "")
    } else {
      stop(.msg, "\nThis render stops because HVTI_TEMPLATE_STRICT is '",
           Sys.getenv("HVTI_TEMPLATE_STRICT"), "'.", call. = FALSE)
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
SUBJECT <- "mr"
TYPE    <- "model"
.current <- knitr::current_input()
if (!is.null(.current)) {
  .fields <- strsplit(sub("[.][^.]+$", "", basename(.current)), "-", fixed = TRUE)[[1L]]
  .name_subject <- if (length(.fields) >= 1L) .fields[[1L]] else NA_character_
  .name_type <- if (length(.fields) >= 2L) .fields[[2L]] else NA_character_
  if (!identical(.name_subject, SUBJECT) || !identical(.name_type, TYPE)) {
    stop("This file is named '", .current, "' (subject '", .name_subject,
         "', type '", .name_type, "'), but declares SUBJECT = \"", SUBJECT,
         "\", TYPE = \"", TYPE, "\". Fix the declaration or the filename before rendering.", call. = FALSE)
  }
}
set_path <- function(kind, file) {
  d <- file.path(hvtiRutilities::study_dir(kind, .root), paste0(SUBJECT, "-", TYPE))
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  file.path(d, file)
}
```

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
                                          where = WHERE, id = ID, key = KEY)
# This job's data are the model's training data, which lm-checkpred tells from its validation data.
job_data$provenance$role <- "training"
d <- job_data$data
.provenance_data <- c(if (exists(".provenance_data")) .provenance_data else list(), list(job_data$provenance))
# The identifier column read_job_data() used: MRN or eMRN when there is no ccfid.
.id <- attr(job_data$record, "selection")$id
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

Table 2: Fit status of the model

Code

``` r
knitr::kable(fit$tables$estimates)
```

| term | estimate | std.error | statistic | df | p.value | conf.low | conf.high | odds_ratio | pooled |
|:---|---:|---:|---:|---:|---:|---:|---:|---:|:---|
| age | 0.0697921 | 0.0064282 | 10.8572214 | Inf | 0.0000000 | 0.0571931 | 0.0823911 | 1.0722852 | FALSE |
| female | 0.3811503 | 0.1437501 | 2.6514778 | Inf | 0.0080140 | 0.0994052 | 0.6628954 | 1.4639677 | FALSE |
| hx_chf | 0.4114784 | 0.1643622 | 2.5034856 | Inf | 0.0122977 | 0.0893344 | 0.7336224 | 1.5090471 | FALSE |
| hx_dm | 0.0096555 | 0.1703095 | 0.0566939 | Inf | 0.9547890 | -0.3241450 | 0.3434560 | 1.0097023 | FALSE |
| lvef | -0.0414858 | 0.0079841 | -5.1960824 | Inf | 0.0000002 | -0.0571343 | -0.0258374 | 0.9593629 | FALSE |
| bmi | 0.0190266 | 0.0159296 | 1.1944180 | Inf | 0.2323145 | -0.0121948 | 0.0502480 | 1.0192087 | FALSE |
| threshold:none\|mild | 3.1006867 | 0.7295144 | 4.2503432 | Inf | 0.0000213 | 1.6708647 | 4.5305086 | NA | FALSE |
| threshold:mild\|moderate | 4.3393090 | 0.7380809 | 5.8791784 | Inf | 0.0000000 | 2.8926972 | 5.7859209 | NA | FALSE |
| threshold:moderate\|severe | 5.7865740 | 0.7525480 | 7.6893089 | Inf | 0.0000000 | 4.3116070 | 7.2615410 | NA | FALSE |

Table 3: Coefficient estimates of the fitted model

Code

``` r
knitr::kable(fit$tables$covariance)
```

|  | age | female | hx_chf | hx_dm | lvef | bmi | threshold:none\|mild | threshold:mild\|moderate | threshold:moderate\|severe |
|:---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| age | 0.0000413 | 0.0000245 | 0.0001332 | 0.0000049 | -0.0000047 | 0.0000003 | 0.0024293 | 0.0025444 | 0.0026588 |
| female | 0.0000245 | 0.0206641 | -0.0001257 | 0.0009187 | -0.0000397 | 0.0000628 | 0.0092666 | 0.0099061 | 0.0105623 |
| hx_chf | 0.0001332 | -0.0001257 | 0.0270149 | 0.0000367 | 0.0005152 | 0.0000436 | 0.0446240 | 0.0454430 | 0.0462829 |
| hx_dm | 0.0000049 | 0.0009187 | 0.0000367 | 0.0290053 | -0.0000279 | -0.0000521 | 0.0041083 | 0.0039682 | 0.0040427 |
| lvef | -0.0000047 | -0.0000397 | 0.0005152 | -0.0000279 | 0.0000637 | -0.0000019 | 0.0030640 | 0.0029980 | 0.0029437 |
| bmi | 0.0000003 | 0.0000628 | 0.0000436 | -0.0000521 | -0.0000019 | 0.0002538 | 0.0070362 | 0.0070666 | 0.0070784 |
| threshold:none\|mild | 0.0024293 | 0.0092666 | 0.0446240 | 0.0041083 | 0.0030640 | 0.0070362 | 0.5321913 | 0.5349990 | 0.5392785 |
| threshold:mild\|moderate | 0.0025444 | 0.0099061 | 0.0454430 | 0.0039682 | 0.0029980 | 0.0070666 | 0.5349990 | 0.5447633 | 0.5482416 |
| threshold:moderate\|severe | 0.0026588 | 0.0105623 | 0.0462829 | 0.0040427 | 0.0029437 | 0.0070784 | 0.5392785 | 0.5482416 | 0.5663285 |

Table 4: Covariance matrix of the coefficient estimates

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
