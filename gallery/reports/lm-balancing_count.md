# Count-exposure balancing score

# Count-exposure balancing score

Fits a Poisson or negative-binomial balancing score for a count
exposure. The distribution is a reviewed study choice; the template
never chooses it from the observed variance.

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
SUBJECT <- "priorops"
TYPE    <- "balancing"
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

OUTCOME <- "prior_ops"
PREDICTORS <- c("age", "female", "hx_chf", "hx_dm", "lvef", "bmi")
DISTRIBUTION <- "poisson"
N_STRATA <- 5L
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
fit <- hvtiRpropensity::bs_count(
  model_formula, d, outcome_col = OUTCOME, id_col = .id,
  imputation_col = IMPUTATION, dist = DISTRIBUTION,
  n_strata = N_STRATA, covariates = PREDICTORS
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
| (Intercept) | -3.9858306 | 0.5929265 | -6.7223011 | Inf | 0.0000000 | -5.1479453 | -2.8237160 | 0.0185770 | FALSE |
| age | 0.0325685 | 0.0047398 | 6.8713106 | Inf | 0.0000000 | 0.0232787 | 0.0418583 | 1.0331046 | FALSE |
| female | 0.1243881 | 0.1148936 | 1.0826372 | Inf | 0.2789695 | -0.1007992 | 0.3495755 | 1.1324553 | FALSE |
| hx_chf | 0.6616416 | 0.1284667 | 5.1502987 | Inf | 0.0000003 | 0.4098516 | 0.9134316 | 1.9379711 | FALSE |
| hx_dm | -0.1469391 | 0.1428249 | -1.0288056 | Inf | 0.3035710 | -0.4268708 | 0.1329926 | 0.8633466 | FALSE |
| lvef | 0.0084446 | 0.0063559 | 1.3286214 | Inf | 0.1839729 | -0.0040128 | 0.0209020 | 1.0084804 | FALSE |
| bmi | 0.0090351 | 0.0126133 | 0.7163166 | Inf | 0.4737959 | -0.0156865 | 0.0337567 | 1.0090761 | FALSE |

Table 3: Coefficient estimates of the fitted model

Code

``` r
knitr::kable(fit$tables$covariance)
```

|  | (Intercept) | age | female | hx_chf | hx_dm | lvef | bmi |
|:---|---:|---:|---:|---:|---:|---:|---:|
| (Intercept) | 0.3515619 | -0.0014987 | -0.0061893 | -0.0301910 | -0.0021275 | -0.0021932 | -0.0042699 |
| age | -0.0014987 | 0.0000225 | -0.0000023 | 0.0000737 | 0.0000072 | 0.0000003 | -0.0000017 |
| female | -0.0061893 | -0.0000023 | 0.0132005 | -0.0001256 | 0.0000823 | -0.0000027 | 0.0000403 |
| hx_chf | -0.0301910 | 0.0000737 | -0.0001256 | 0.0165037 | 0.0003342 | 0.0003591 | -0.0000051 |
| hx_dm | -0.0021275 | 0.0000072 | 0.0000823 | 0.0003342 | 0.0203990 | -0.0000254 | -0.0000421 |
| lvef | -0.0021932 | 0.0000003 | -0.0000027 | 0.0003591 | -0.0000254 | 0.0000404 | -0.0000017 |
| bmi | -0.0042699 | -0.0000017 | 0.0000403 | -0.0000051 | -0.0000421 | -0.0000017 | 0.0001591 |

Table 4: Covariance matrix of the coefficient estimates

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

Table 5: Patients in each stratum

Code

``` r
MODEL_PATH <- set_path("estimates", "lm-balancing_count.rds")
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
