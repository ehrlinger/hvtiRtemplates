# Binary logistic model

# Binary logistic model

Fits a binary outcome model and preserves the fitted model, predictions,
and pooled inference. For stacked imputations, coefficients and
covariance use Rubin pooling while patient predictions are averaged
across imputations.

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
SUBJECT <- "stroke"
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

## Study choices

Code

``` r
# Demo: the registered dataset this job reads ("study" is the built dataset).
DATASET <- "study"

# Demo: an hvtiRdatabuild analysis set, or NULL to read the whole dataset.
ANALYSIS_SET <- NULL

# Demo: rows to keep, dplyr::filter() style, or NULL to keep every row:
#   WHERE <- quote(age >= 18)
#   WHERE <- rlang::exprs(age >= 18, hx_chf == 1)
WHERE <- quote(year < 2015)

# Demo: the patient identifier. Without "ccfid" the job uses MRN, then eMRN;
# name another column, such as "randid", if the study uses one.
ID <- "patient_id"

# Demo: what makes a row unique; one row per patient unless repeated measures
# add their visit time or date, for example KEY <- c(ID, "iv_echo").
KEY <- ID

OUTCOME <- "stroke"
PREDICTORS <- c("age", "female", "hx_chf", "hx_dm", "lvef", "bmi")
OUTCOME_LEVELS <- c("no", "yes")
EVENT_LEVEL <- "yes"
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
required_formula <- stats::reformulate(PREDICTORS, response = OUTCOME)
needed <- unique(c(all.vars(required_formula), .id, IMPUTATION))
missing <- setdiff(needed, names(d))
if (length(missing)) stop("Missing model columns: ", paste(missing, collapse = ", "), call. = FALSE)
```

| Data                |                             |
|:--------------------|:----------------------------|
| Source              | dataset `study` (built.rds) |
| Rows read           | 800                         |
| ID                  | `patient_id`                |
| Identifiers dropped | none                        |
| `year < 2015`       | removed 228                 |
| Rows kept           | 572 rows on 572 patients    |

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
  model_formula, d, family = "binary", outcome_col = OUTCOME, id_col = .id,
  imputation_col = IMPUTATION, outcome_levels = OUTCOME_LEVELS,
  event_level = EVENT_LEVEL, prediction_prefix = "predicted"
)
```

## Fit health and pooled inference

Code

``` r
knitr::kable(fit$tables$fit_status)
```

| imputation | converged | n_input | n_analyzed | n_excluded |
|-----------:|:----------|--------:|-----------:|-----------:|
|          1 | TRUE      |     572 |        572 |          0 |

Table 2: Fit status of the model

Code

``` r
knitr::kable(fit$tables$estimates)
```

| term | estimate | std.error | statistic | df | p.value | conf.low | conf.high | odds_ratio | pooled |
|:---|---:|---:|---:|---:|---:|---:|---:|---:|:---|
| (Intercept) | -6.9627630 | 1.5661092 | -4.4458988 | Inf | 0.0000088 | -10.0322807 | -3.8932454 | 0.0009465 | FALSE |
| age | 0.0333576 | 0.0132053 | 2.5260777 | Inf | 0.0115344 | 0.0074757 | 0.0592395 | 1.0339202 | FALSE |
| female | 0.1167967 | 0.3035057 | 0.3848255 | Inf | 0.7003667 | -0.4780635 | 0.7116569 | 1.1238910 | FALSE |
| hx_chf | 0.9986454 | 0.3343592 | 2.9867438 | Inf | 0.0028197 | 0.3433133 | 1.6539775 | 2.7146021 | FALSE |
| hx_dm | 0.7204236 | 0.3298090 | 2.1843660 | Inf | 0.0289354 | 0.0740098 | 1.3668373 | 2.0553036 | FALSE |
| lvef | 0.0233691 | 0.0161888 | 1.4435356 | Inf | 0.1488696 | -0.0083604 | 0.0550986 | 1.0236443 | FALSE |
| bmi | 0.0257726 | 0.0340383 | 0.7571652 | Inf | 0.4489509 | -0.0409413 | 0.0924865 | 1.0261076 | FALSE |

Table 3: Coefficient estimates of the fitted model

Code

``` r
knitr::kable(fit$tables$covariance)
```

|  | (Intercept) | age | female | hx_chf | hx_dm | lvef | bmi |
|:---|---:|---:|---:|---:|---:|---:|---:|
| (Intercept) | 2.4526981 | -0.0108224 | -0.0393345 | -0.2067321 | -0.0187573 | -0.0144078 | -0.0306945 |
| age | -0.0108224 | 0.0001744 | -0.0001376 | 0.0004809 | -0.0000053 | -0.0000008 | -0.0000194 |
| female | -0.0393345 | -0.0001376 | 0.0921157 | 0.0030835 | 0.0048186 | 0.0000022 | 0.0002907 |
| hx_chf | -0.2067321 | 0.0004809 | 0.0030835 | 0.1117961 | 0.0081627 | 0.0023809 | -0.0001803 |
| hx_dm | -0.0187573 | -0.0000053 | 0.0048186 | 0.0081627 | 0.1087740 | 0.0000865 | -0.0008009 |
| lvef | -0.0144078 | -0.0000008 | 0.0000022 | 0.0023809 | 0.0000865 | 0.0002621 | -0.0000104 |
| bmi | -0.0306945 | -0.0000194 | 0.0002907 | -0.0001803 | -0.0008009 | -0.0000104 | 0.0011586 |

Table 4: Covariance matrix of the coefficient estimates

Code

``` r
MODEL_PATH <- set_path("estimates", "lm-binary.rds")
.fit_provenance <- hvtiRtemplates:::.lm_fit_provenance(fit)
fit <- hvtiRtemplates:::.attach_handoff_lineage(
  fit, data = if (exists(".provenance_data")) .provenance_data else list(),
  analysis = .fit_provenance$analysis, cohort = .fit_provenance$cohort,
  selection = attr(job_data$record, "selection")
)
# The saved copy holds a study-keyed digest of each patient ID, never the ID, so the file names no
# patient. A later job reattaches its own data by digesting its IDs with the same key: see lm-checkpred.
saveRDS(hvtiRtemplates:::.digest_bundle_ids(fit, .root), MODEL_PATH)
MODEL_PATH
```

    [1] "/private/tmp/claude-504/-Users-ehrlinj-Documents-GitHub-hvtiRtemplates/3e689488-70a2-4d31-a5fa-ec4b956271c5/scratchpad/gallery-build/90_estimates/stroke-model/lm-binary.rds"
