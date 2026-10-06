# Nominal-treatment propensity model

# Nominal-treatment propensity model

Fits a generalized-logit propensity model for a nominal treatment with
an explicit reference level.

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
SUBJECT <- "valvetype"
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

TREATMENT <- "valve_type"
PREDICTORS <- c("age", "female", "hx_chf", "hx_dm", "lvef", "bmi")
TREATMENT_LEVELS <- c("mechanical", "bioprosthetic", "homograft")
REFERENCE_LEVEL <- "mechanical"
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
fit <- hvtiRpropensity::ps_nominal(
  model_formula, d, treatment_col = TREATMENT, id_col = .id,
  imputation_col = IMPUTATION, ref_level = REFERENCE_LEVEL,
  covariates = PREDICTORS, treatment_levels = TREATMENT_LEVELS
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
| bioprosthetic:(Intercept) | -8.6635804 | 0.9887681 | -8.7619943 | Inf | 0.0000000 | -10.6015302 | -6.7256305 | 0.0001728 | FALSE |
| bioprosthetic:age | 0.1139530 | 0.0093969 | 12.1266157 | Inf | 0.0000000 | 0.0955353 | 0.1323706 | 1.1206994 | FALSE |
| bioprosthetic:female | 0.2466996 | 0.1749089 | 1.4104462 | Inf | 0.1584080 | -0.0961155 | 0.5895148 | 1.2797946 | FALSE |
| bioprosthetic:hx_chf | 0.1386562 | 0.2006480 | 0.6910420 | Inf | 0.4895391 | -0.2546067 | 0.5319191 | 1.1487291 | FALSE |
| bioprosthetic:hx_dm | 0.1015217 | 0.2047081 | 0.4959341 | Inf | 0.6199409 | -0.2996987 | 0.5027422 | 1.1068539 | FALSE |
| bioprosthetic:lvef | 0.0157275 | 0.0095006 | 1.6554182 | Inf | 0.0978397 | -0.0028934 | 0.0343484 | 1.0158519 | FALSE |
| bioprosthetic:bmi | 0.0150187 | 0.0191347 | 0.7848917 | Inf | 0.4325171 | -0.0224846 | 0.0525220 | 1.0151320 | FALSE |
| homograft:(Intercept) | -2.5560068 | 1.5772021 | -1.6205957 | Inf | 0.1051044 | -5.6472661 | 0.5352524 | 0.0776140 | FALSE |
| homograft:age | -0.0325924 | 0.0145173 | -2.2450768 | Inf | 0.0247632 | -0.0610457 | -0.0041391 | 0.9679330 | FALSE |
| homograft:female | -0.1442486 | 0.3231946 | -0.4463212 | Inf | 0.6553652 | -0.7776983 | 0.4892011 | 0.8656725 | FALSE |
| homograft:hx_chf | -0.4546833 | 0.3751969 | -1.2118523 | Inf | 0.2255689 | -1.1900557 | 0.2806892 | 0.6346489 | FALSE |
| homograft:hx_dm | 0.1944299 | 0.3577770 | 0.5434388 | Inf | 0.5868277 | -0.5068002 | 0.8956600 | 1.2146184 | FALSE |
| homograft:lvef | 0.0058556 | 0.0167346 | 0.3499076 | Inf | 0.7264080 | -0.0269436 | 0.0386547 | 1.0058727 | FALSE |
| homograft:bmi | 0.0765753 | 0.0332296 | 2.3044284 | Inf | 0.0211986 | 0.0114464 | 0.1417041 | 1.0795835 | FALSE |

Table 3: Coefficient estimates of the fitted model

Code

``` r
knitr::kable(fit$tables$covariance)
```

|  | bioprosthetic:(Intercept) | bioprosthetic:age | bioprosthetic:female | bioprosthetic:hx_chf | bioprosthetic:hx_dm | bioprosthetic:lvef | bioprosthetic:bmi | homograft:(Intercept) | homograft:age | homograft:female | homograft:hx_chf | homograft:hx_dm | homograft:lvef | homograft:bmi |
|:---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| bioprosthetic:(Intercept) | 0.9776623 | -0.0059842 | -0.0160490 | -0.0660693 | -0.0058244 | -0.0052737 | -0.0104535 | 0.2478302 | -0.0012429 | -0.0027992 | -0.0166777 | -0.0017885 | -0.0015425 | -0.0032028 |
| bioprosthetic:age | -0.0059842 | 0.0000883 | 0.0000389 | 0.0001523 | 0.0000143 | 0.0000048 | 0.0000024 | -0.0009466 | 0.0000166 | -0.0000143 | 0.0000131 | -0.0000305 | -0.0000002 | 0.0000001 |
| bioprosthetic:female | -0.0160490 | 0.0000389 | 0.0305931 | 0.0002536 | 0.0014324 | 0.0000027 | 0.0000465 | -0.0014788 | -0.0000246 | 0.0096379 | -0.0004045 | 0.0000537 | -0.0000170 | 0.0000161 |
| bioprosthetic:hx_chf | -0.0660693 | 0.0001523 | 0.0002536 | 0.0402596 | 0.0000899 | 0.0007835 | 0.0001088 | -0.0137058 | -0.0000350 | -0.0004769 | 0.0116284 | 0.0002651 | 0.0002248 | 0.0000122 |
| bioprosthetic:hx_dm | -0.0058244 | 0.0000143 | 0.0014324 | 0.0000899 | 0.0419054 | -0.0000162 | -0.0001487 | -0.0031654 | -0.0000113 | 0.0000488 | 0.0002986 | 0.0136339 | 0.0000332 | -0.0000286 |
| bioprosthetic:lvef | -0.0052737 | 0.0000048 | 0.0000027 | 0.0007835 | -0.0000162 | 0.0000903 | 0.0000022 | -0.0015923 | 0.0000010 | -0.0000133 | 0.0002285 | 0.0000284 | 0.0000276 | 0.0000017 |
| bioprosthetic:bmi | -0.0104535 | 0.0000024 | 0.0000465 | 0.0001088 | -0.0001487 | 0.0000022 | 0.0003661 | -0.0038576 | 0.0000108 | 0.0000411 | 0.0000198 | -0.0000285 | 0.0000027 | 0.0001127 |
| homograft:(Intercept) | 0.2478302 | -0.0009466 | -0.0014788 | -0.0137058 | -0.0031654 | -0.0015923 | -0.0038576 | 2.4875663 | -0.0115168 | -0.0296646 | -0.1514703 | -0.0301959 | -0.0157699 | -0.0332685 |
| homograft:age | -0.0012429 | 0.0000166 | -0.0000246 | -0.0000350 | -0.0000113 | 0.0000010 | 0.0000108 | -0.0115168 | 0.0002108 | -0.0001050 | 0.0001350 | -0.0004179 | 0.0000022 | 0.0000039 |
| homograft:female | -0.0027992 | -0.0000143 | 0.0096379 | -0.0004769 | 0.0000488 | -0.0000133 | 0.0000411 | -0.0296646 | -0.0001050 | 0.1044547 | -0.0045619 | 0.0012545 | -0.0001919 | 0.0004620 |
| homograft:hx_chf | -0.0166777 | 0.0000131 | -0.0004045 | 0.0116284 | 0.0002986 | 0.0002285 | 0.0000198 | -0.1514703 | 0.0001350 | -0.0045619 | 0.1407727 | -0.0000846 | 0.0022446 | -0.0001900 |
| homograft:hx_dm | -0.0017885 | -0.0000305 | 0.0000537 | 0.0002651 | 0.0136339 | 0.0000284 | -0.0000285 | -0.0301959 | -0.0004179 | 0.0012545 | -0.0000846 | 0.1280044 | 0.0003360 | 0.0001886 |
| homograft:lvef | -0.0015425 | -0.0000002 | -0.0000170 | 0.0002248 | 0.0000332 | 0.0000276 | 0.0000027 | -0.0157699 | 0.0000022 | -0.0001919 | 0.0022446 | 0.0003360 | 0.0002800 | 0.0000161 |
| homograft:bmi | -0.0032028 | 0.0000001 | 0.0000161 | 0.0000122 | -0.0000286 | 0.0000017 | 0.0001127 | -0.0332685 | 0.0000039 | 0.0004620 | -0.0001900 | 0.0001886 | 0.0000161 | 0.0011042 |

Table 4: Covariance matrix of the coefficient estimates

Code

``` r
knitr::kable(fit$tables$group_counts)
```

| group         |   n |
|:--------------|----:|
| mechanical    | 387 |
| bioprosthetic | 361 |
| homograft     |  52 |

Table 5: Patients in each group

Code

``` r
MODEL_PATH <- set_path("estimates", "lm-propensity_nominal.rds")
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
