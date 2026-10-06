# Ordered-treatment propensity model

# Ordered-treatment propensity model

Fits a proportional-odds propensity model for an explicitly ordered
treatment.

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
      stop(.msg, "\nThis render stops because HVTI_TEMPLATE_STRICT is '", Sys.getenv("HVTI_TEMPLATE_STRICT"), "'.", call. = FALSE)
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
SUBJECT <- "valvesize"
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
fit <- hvtiRpropensity::ps_ordinal(
  model_formula, d, treatment_col = TREATMENT, id_col = .id,
  imputation_col = IMPUTATION, covariates = PREDICTORS,
  treatment_levels = TREATMENT_LEVELS
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
knitr::kable(fit$tables$group_counts)
```

| group  |   n |
|:-------|----:|
| small  | 261 |
| medium | 323 |
| large  | 216 |

Table 5: Patients in each group

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

Table 6: Patients in each propensity quintile

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

Table 7: Patients in each propensity decile

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
