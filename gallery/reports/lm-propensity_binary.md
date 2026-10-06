# Binary-treatment propensity model

# Binary-treatment propensity model

Fits a binary-treatment propensity model, including pooled inference for
stacked imputations and the scored columns used by matching and
weighting jobs.

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
if (utils::packageVersion("hvtiRpropensity") < "0.1.7") {
  stop("This template needs hvtiRpropensity >= 0.1.7.", call. = FALSE)
}
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
SUBJECT <- "approach"
TYPE    <- "propensity"
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

| group   |   n |
|:--------|----:|
| control | 514 |
| treated | 286 |

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
