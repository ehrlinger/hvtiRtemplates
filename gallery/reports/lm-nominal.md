# Nominal logistic model

# Nominal logistic model

Fits a generalized-logit outcome model with a declared level set and
reference.

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
SUBJECT <- "discharge"
TYPE    <- "model"
.current <- knitr::current_input()
if (!is.null(.current)) {
  .fields <- hvtiRtemplates:::.job_name_fields(.current)
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

OUTCOME <- "discharge"
PREDICTORS <- c("age", "female", "hx_chf", "hx_dm", "lvef", "bmi")
OUTCOME_LEVELS <- c("home", "rehab", "nursing")
REFERENCE_LEVEL <- "home"
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
```

| Data                |                                          |
|:--------------------|:-----------------------------------------|
| Source              | dataset `built` (built_20261009.parquet) |
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
model_formula <- stats::reformulate(PREDICTORS, response = OUTCOME)
fit <- hvtiRpropensity::fit_logistic(
  model_formula, d, family = "nominal", outcome_col = OUTCOME, id_col = .id,
  imputation_col = IMPUTATION, outcome_levels = OUTCOME_LEVELS,
  reference_level = REFERENCE_LEVEL, prediction_prefix = "predicted"
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
| rehab:(Intercept) | -4.5824763 | 0.9465660 | -4.8411586 | Inf | 0.0000013 | -6.4377117 | -2.7272410 | 0.0102295 | FALSE |
| rehab:age | 0.0704471 | 0.0085524 | 8.2371056 | Inf | 0.0000000 | 0.0536847 | 0.0872095 | 1.0729878 | FALSE |
| rehab:female | 0.1952436 | 0.1813405 | 1.0766688 | Inf | 0.2816283 | -0.1601772 | 0.5506644 | 1.2156071 | FALSE |
| rehab:hx_chf | -0.0766726 | 0.2137793 | -0.3586529 | Inf | 0.7198548 | -0.4956723 | 0.3423271 | 0.9261931 | FALSE |
| rehab:hx_dm | -0.0312094 | 0.2134788 | -0.1461944 | Inf | 0.8837679 | -0.4496201 | 0.3872013 | 0.9692726 | FALSE |
| rehab:lvef | -0.0130036 | 0.0099166 | -1.3112950 | Inf | 0.1897581 | -0.0324398 | 0.0064326 | 0.9870806 | FALSE |
| rehab:bmi | -0.0080165 | 0.0200035 | -0.4007553 | Inf | 0.6886003 | -0.0472226 | 0.0311896 | 0.9920155 | FALSE |
| nursing:(Intercept) | -8.8058369 | 1.3951253 | -6.3118607 | Inf | 0.0000000 | -11.5402324 | -6.0714415 | 0.0001499 | FALSE |
| nursing:age | 0.1195316 | 0.0127432 | 9.3800444 | Inf | 0.0000000 | 0.0945554 | 0.1445077 | 1.1269688 | FALSE |
| nursing:female | -0.0845704 | 0.2632366 | -0.3212714 | Inf | 0.7480048 | -0.6005046 | 0.4313639 | 0.9189070 | FALSE |
| nursing:hx_chf | 0.2269806 | 0.3032672 | 0.7484508 | Inf | 0.4541883 | -0.3674122 | 0.8213733 | 1.2548055 | FALSE |
| nursing:hx_dm | -0.0819168 | 0.3073893 | -0.2664920 | Inf | 0.7898603 | -0.6843887 | 0.5205551 | 0.9213486 | FALSE |
| nursing:lvef | -0.0120947 | 0.0142546 | -0.8484774 | Inf | 0.3961722 | -0.0400331 | 0.0158437 | 0.9879782 | FALSE |
| nursing:bmi | -0.0098824 | 0.0285192 | -0.3465164 | Inf | 0.7289547 | -0.0657789 | 0.0460142 | 0.9901663 | FALSE |

Table 3: Coefficient estimates of the fitted model

Code

``` r
knitr::kable(fit$tables$covariance)
```

|  | rehab:(Intercept) | rehab:age | rehab:female | rehab:hx_chf | rehab:hx_dm | rehab:lvef | rehab:bmi | nursing:(Intercept) | nursing:age | nursing:female | nursing:hx_chf | nursing:hx_dm | nursing:lvef | nursing:bmi |
|:---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| rehab:(Intercept) | 0.8959873 | -0.0045228 | -0.0120318 | -0.0687748 | -0.0040554 | -0.0051172 | -0.0109791 | 0.3776656 | -0.0021897 | -0.0049098 | -0.0259103 | 0.0002233 | -0.0020092 | -0.0044412 |
| rehab:age | -0.0045228 | 0.0000731 | -0.0000209 | 0.0001218 | -0.0000289 | -0.0000030 | -0.0000028 | -0.0021881 | 0.0000379 | -0.0000086 | 0.0000083 | -0.0000298 | -0.0000029 | -0.0000015 |
| rehab:female | -0.0120318 | -0.0000209 | 0.0328844 | -0.0002818 | 0.0010139 | -0.0000243 | 0.0000464 | -0.0023037 | -0.0000503 | 0.0137066 | 0.0001012 | 0.0007014 | -0.0000049 | 0.0000245 |
| rehab:hx_chf | -0.0687748 | 0.0001218 | -0.0002818 | 0.0457016 | 0.0005135 | 0.0008696 | 0.0000886 | -0.0273881 | 0.0000325 | 0.0001822 | 0.0175047 | -0.0002188 | 0.0003364 | 0.0000895 |
| rehab:hx_dm | -0.0040554 | -0.0000289 | 0.0010139 | 0.0005135 | 0.0455732 | -0.0000277 | -0.0001222 | 0.0005832 | -0.0000371 | 0.0006970 | -0.0001497 | 0.0181792 | -0.0000023 | -0.0000837 |
| rehab:lvef | -0.0051172 | -0.0000030 | -0.0000243 | 0.0008696 | -0.0000277 | 0.0000983 | 0.0000003 | -0.0020639 | -0.0000019 | -0.0000102 | 0.0003405 | -0.0000044 | 0.0000393 | 0.0000019 |
| rehab:bmi | -0.0109791 | -0.0000028 | 0.0000464 | 0.0000886 | -0.0001222 | 0.0000003 | 0.0004001 | -0.0044820 | -0.0000008 | 0.0000222 | 0.0000887 | -0.0000867 | 0.0000020 | 0.0001585 |
| nursing:(Intercept) | 0.3776656 | -0.0021881 | -0.0023037 | -0.0273881 | 0.0005832 | -0.0020639 | -0.0044820 | 1.9463747 | -0.0107015 | -0.0257755 | -0.1569208 | -0.0103720 | -0.0103279 | -0.0211917 |
| nursing:age | -0.0021897 | 0.0000379 | -0.0000503 | 0.0000325 | -0.0000371 | -0.0000019 | -0.0000008 | -0.0107015 | 0.0001624 | -0.0000076 | 0.0004776 | 0.0000431 | -0.0000071 | -0.0000157 |
| nursing:female | -0.0049098 | -0.0000086 | 0.0137066 | 0.0001822 | 0.0006970 | -0.0000102 | 0.0000222 | -0.0257755 | -0.0000076 | 0.0692935 | -0.0005173 | 0.0005035 | -0.0000082 | 0.0000648 |
| nursing:hx_chf | -0.0259103 | 0.0000083 | 0.0001012 | 0.0175047 | -0.0001497 | 0.0003405 | 0.0000887 | -0.1569208 | 0.0004776 | -0.0005173 | 0.0919710 | 0.0023615 | 0.0018399 | -0.0000416 |
| nursing:hx_dm | 0.0002233 | -0.0000298 | 0.0007014 | -0.0002188 | 0.0181792 | -0.0000044 | -0.0000867 | -0.0103720 | 0.0000431 | 0.0005035 | 0.0023615 | 0.0944882 | -0.0001711 | -0.0001956 |
| nursing:lvef | -0.0020092 | -0.0000029 | -0.0000049 | 0.0003364 | -0.0000023 | 0.0000393 | 0.0000020 | -0.0103279 | -0.0000071 | -0.0000082 | 0.0018399 | -0.0001711 | 0.0002032 | -0.0000059 |
| nursing:bmi | -0.0044412 | -0.0000015 | 0.0000245 | 0.0000895 | -0.0000837 | 0.0000019 | 0.0001585 | -0.0211917 | -0.0000157 | 0.0000648 | -0.0000416 | -0.0001956 | -0.0000059 | 0.0008133 |

Table 4: Covariance matrix of the coefficient estimates

Code

``` r
MODEL_PATH <- set_path("estimates", "lm-nominal.rds")
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
