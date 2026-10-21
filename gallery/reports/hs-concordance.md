# Concordance: every patient through every group’s model

# Concordance: every patient through every group’s model

Published

2026-10-21 08:02

An `hs-concordance` job predicts **every patient through every treatment
group’s model**. Each group’s risk-factor model was fitted by its own
`hm` job, on that group’s patients; this job reads them all, and asks of
each patient what the model for each treatment predicts at one horizon.
The corpus calls the result concordance and discordance: whether the
treatment a patient received is the one the models favor.

**This job reads models from other sets on purpose.** An `hs-setup` job
reads the `hm.rds` in its own set, so that a prediction can never be
filed against a model it did not come from. Here the crossing is the
point, so it is declared: `MODELS` below names the set each model comes
from, and every model read is recorded in this job’s provenance.

**The job has a core and an optional decision.** The core predicts and
saves. The section headed “Decision” chooses a best treatment per
patient and tables it against the treatment received. Delete that
section if the study does not make that claim; the rest of the job does
not depend on it.

The design, with the three studies it was drawn from and the failures
each guard below exists for, is in
`hvtiRtemplates:dev/specs/2026-09-30-hs-concordance-design.md`.

Code

``` r
SUBJECT <- "dead"
TYPE    <- "approach"
.in <- knitr::current_input(dir = TRUE)
.provenance_artifacts <- list()
suppressPackageStartupMessages({
  library(TemporalHazard)
  library(hvtiRutilities)
})
# The study root is the nearest directory above this file holding _study.yml,
# so the job renders the same from the Render button, quarto render, or
# render_job(), at any depth, with no path in this document to edit.
# Without the guard in .job_setup(), an unedited job renders green over a
# meaningless analysis. In THIS file that would be a table of best treatments,
# which reads as a clinical recommendation whether or not anyone finished the
# job.
# To render a job you have not finished, leave a chunk out with the chunk
# option skip, giving the reason in quotes, or call hvtiRtemplates::stop_here()
# in a chunk to leave out everything below it. A draft lists each one in a
# callout; a final render refuses them, as it refuses an unresolved marker.
# ?stop_here has more.
.job <- hvtiRtemplates:::.job_setup(SUBJECT, TYPE, envir = environment())
.root <- .job$root
set_path <- .job$set_path
.provenance_data <- list()
# This job reads other sets' models by path, in the models chunk. It writes only
# into its own set, the comparison set that SUBJECT and TYPE name.
# The draft banners, if any, and the box under the title, after all the code above.
.job$notice
```

**final** · data `built` `built_20261021.parquet`, registered 2026-10-21
· rendered by gallery on gallery · hvtiRtemplates 1.4.2

## Study choices

Edit these values for this study before rendering.

Code

``` r
# The data and rows this job predicts for. Unlike hs-setup, these are this
# job's own choice, not taken from a model: each hm model was fitted on ONE
# group's rows, and this job predicts for all of them.
# Demo: the dataset, and a WHERE that keeps every group being compared.
DATASET <- "built"
ANALYSIS_SET <- NULL
WHERE <- quote(!is.na(creat_pr))
ID <- "patient_id"
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

# The follow-up time and event columns every hm model was fitted on. NULL takes
# the columns the models recorded; set one only to confirm it. A value that
# differs from a model's stops the job, and so does a pair of models that
# disagree, because HORIZON below is one number applied to every model.
TIME <- NULL
EVENT <- NULL

# Demo: the counts this cohort must have. The invalid defaults stop an unedited
#       job before it predicts for a cohort nobody reconciled.
EXPECTED <- list(n = 725L, n_events = 406L, n_censored = 319L)

# Demo: one entry per treatment group. The NAME is the group's label and must
#       be a value of the GROUP column. The VALUE is the set whose hm job
#       fitted that group's model, "<subject>-<type>".
MODELS <- c(surgical = "dead-surgical", transcatheter = "dead-transcatheter")

# Demo: the column recording the treatment each patient actually received.
GROUP <- "approach"

# Demo: the single horizon, in TIME's own units. If the hm jobs worked in
#       years, 30 days is 30/365.25, not 30. A wrong unit gives a plausible
#       number at the wrong time, the failure with no symptom.
HORIZON <- 5

# Demo: columns a later plotting job needs beside each prediction, such as
#       age. They are saved once per patient, because the saved predictions
#       carry a row number, not a patient identifier.
CARRY <- c("age")

# Demo: how the cohort was made comparable across groups: "none", "matched"
#       or "common_support". Say which, and why, in the text above. The three
#       studies this template was drawn from made three different choices,
#       so there is no default.
OVERLAP <- "none"

# Demo: TRUE only when a MODELS entry is a path to another study's hm.rds.
#       Setting it is also your statement that the other study's time is in
#       TIME's unit: the saved model records its time column's name and no
#       unit, so this is the one check here that rests on your word. Write
#       the unit in the text above.
CROSS_STUDY <- FALSE
```

## Cohort

Code

``` r
# The checksum of every dataset in manifest.yaml is checked before anything is
# read, so a result can name the data that produced it. It stops on a mismatch.
hvtiRutilities::verify_manifest(file.path(.root, "manifest.yaml"))
.cfg <- study_config(start = .root)
job_data <- hvtiRtemplates::read_job_data(.cfg, dataset = DATASET, analysis_set = ANALYSIS_SET,
                                          where = WHERE, id = ID, key = KEY, join = JOIN, join_vars = JOIN_VARS,
                                          reduce = REDUCE, join_key = JOIN_KEY, one_row_per_patient = TRUE)
d <- job_data$data
.provenance_data <- c(if (exists(".provenance_data")) .provenance_data else list(), list(job_data$provenance),
                      if (!is.null(job_data$provenance_join)) list(job_data$provenance_join))
knitr::kable(job_data$record, col.names = c("Data", ""))
```

| Data                |                                          |
|:--------------------|:-----------------------------------------|
| Source              | dataset `built` (built_20261021.parquet) |
| Rows read           | 800                                      |
| ID                  | `patient_id`                             |
| Identifiers dropped | none                                     |
| `!is.na(creat_pr)`  | removed 75                               |
| Rows kept           | 725 rows on 725 patients                 |

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

## Models

Code

``` r
# Names first. They become model identifiers and the decision table's columns,
# so an empty or repeated one would make a winning model ambiguous.
if (is.null(MODELS) || !length(MODELS)) {
  stop("MODELS is unset. Name one hm set per treatment group, e.g. ",
       "c(cabg = \"dead-cabg\", pci = \"dead-pci\").", call. = FALSE)
}
.mn <- names(MODELS)
if (is.null(.mn) || anyNA(.mn) || any(!nzchar(.mn))) {
  stop("Every MODELS entry needs a name: the treatment group it models.", call. = FALSE)
}
if (anyDuplicated(.mn)) {
  stop("MODELS names must be unique; repeated: ", paste(unique(.mn[duplicated(.mn)]), collapse = ", "), ".",
       call. = FALSE)
}

# An entry with a path separator, "/" or "\\", is a path to an hm.rds; anything
# else is a set in this study. A path is refused unless CROSS_STUDY says it
# was meant, so a mistyped set name cannot quietly become a read from somewhere
# else.
.is_path <- stats::setNames(grepl("[/\\]", MODELS), .mn)
if (any(.is_path) && !isTRUE(CROSS_STUDY)) {
  stop("MODELS entr", if (sum(.is_path) == 1L) "y " else "ies ", paste(.mn[.is_path], collapse = ", "),
       " name a path, not a set. Set CROSS_STUDY <- TRUE if a model from another study is meant.",
       call. = FALSE)
}
.set_path <- file.path(hvtiRutilities::study_dir("estimates", .root), MODELS, "hm.rds")
.model_path <- stats::setNames(ifelse(.is_path, MODELS, .set_path), .mn)
.absent_model <- !file.exists(.model_path)
if (any(.absent_model)) {
  stop("No hm.rds for ", paste0(.mn[.absent_model], " (", .model_path[.absent_model], ")", collapse = ", "),
       ". Render that set's hm job first.", call. = FALSE)
}
# Two groups read through one model would compare a model with itself and
# still produce numbers. One of the three source jobs did exactly that.
.real <- normalizePath(.model_path)
if (anyDuplicated(.real)) {
  stop("MODELS entries ", paste(.mn[.real %in% .real[duplicated(.real)]], collapse = ", "),
       " resolve to the same file. Each group needs its own model.", call. = FALSE)
}

models <- list()
.times <- character()
.events <- character()
for (m in .mn) {
  # A model from another study is recorded against that study's root, which
  # is where its provenance is anchored.
  .mcfg <- if (.is_path[[m]]) study_config(start = dirname(.model_path[[m]])) else .cfg
  .read <- hvtiRtemplates:::.read_handoff(.model_path[[m]], "hazard-regression-model", .mcfg,
                                          paste0("the hm job for ", m))
  # The time and event the hm job recorded, checked against TIME and EVENT
  # when they are set, as hm, hp and hs-setup check theirs against upstream.
  .rec <- .read$lineage$selection
  if (is.null(.rec$time) || is.null(.rec$event)) {
    stop("The hm model for ", m, " records no time and event column: it predates the data contract. ",
         "Rerun that hm job, then this one.", call. = FALSE)
  }
  hvtiRtemplates:::.check_upstream_selection(.rec, list(time = TIME, event = EVENT))
  .times[[m]] <- .rec$time
  .events[[m]] <- .rec$event
  models[[m]] <- .read$value
  .provenance_data <- c(.provenance_data, .read$lineage$data)
  .provenance_artifacts <- c(.provenance_artifacts, .read$lineage$artifacts, list(.read$record))
}
# HORIZON is one number applied to every model, so the models share one time
# scale and one event.
if (length(unique(.times)) > 1L || length(unique(.events)) > 1L) {
  stop("The hm models were fitted on different time or event columns (",
       paste0(.mn, ": ", .times, " / ", .events, collapse = "; "), "). HORIZON is one number applied to ",
       "every model, so every model must share one time scale.", call. = FALSE)
}
TIME <- unname(.times[[1L]])
EVENT <- unname(.events[[1L]])
```

Code

``` r
cc <- cohort_counts(d, event = EVENT, time = TIME)
assert_cohort(d, expected = EXPECTED, event = EVENT, time = TIME)

# The three studies this template was drawn from made three overlap choices,
# and a fourth study made a fourth. Which one a study makes decides what its
# comparison means, so it is declared and saved, never defaulted.
.overlaps <- c("none", "matched", "common_support")
if (is.null(OVERLAP) || length(OVERLAP) != 1L || !OVERLAP %in% .overlaps) {
  stop("OVERLAP must be one of ", paste0("\"", .overlaps, "\"", collapse = ", "),
       ". Say in the text above how the cohort was made comparable across groups.", call. = FALSE)
}
```

Code

``` r
# Every group in the cohort must have a model: a patient whose own treatment
# has none cannot be compared with what they received. An author who means to
# leave a group out filters it with WHERE, where the choice is visible.
if (is.null(GROUP) || !GROUP %in% names(d)) {
  stop("GROUP must name the column recording each patient's treatment; got ",
       if (is.null(GROUP)) "NULL" else paste0("\"", GROUP, "\""), ".", call. = FALSE)
}
.actual <- as.character(d[[GROUP]])
if (anyNA(.actual)) {
  stop(sum(is.na(.actual)), " patient(s) have no value in ", GROUP, ". Filter them with WHERE.", call. = FALSE)
}
.no_model <- setdiff(unique(.actual), names(models))
if (length(.no_model)) {
  stop("Group(s) ", paste(.no_model, collapse = ", "), " in ", GROUP, " have no model in MODELS. ",
       "Add the model, or filter the group out with WHERE.", call. = FALSE)
}
# The reverse is allowed: a model no patient carries is a treatment nobody in
# this cohort received, which is a comparison worth making. It is reported.
knitr::kable(data.frame(model = names(models), patients = as.vector(table(factor(.actual, names(models))))))
```

| model         | patients |
|:--------------|---------:|
| surgical      |      460 |
| transcatheter |      265 |

Table 2: Patients who received each modeled treatment

Code

``` r
# Each model's covariates are taken from its artifact, not re-declared, so the
# list cannot drift from the screen its hm job ran. The models need not share
# them: each group's model is its own, and the table shows where they differ.
covariates <- lapply(models, function(a) unique(unlist(a$covariates, use.names = FALSE)))
for (m in names(covariates)) {
  .miss <- setdiff(covariates[[m]], names(d))
  if (length(.miss)) {
    stop("The model for ", m, " was fitted on column(s) absent from this cohort: ",
         paste(.miss, collapse = ", "), ".", call. = FALSE)
  }
}
.all_cov <- sort(unique(unlist(covariates, use.names = FALSE)))
.cov_tbl <- data.frame(covariate = .all_cov,
                       vapply(covariates, function(v) ifelse(.all_cov %in% v, "yes", ""), character(length(.all_cov))),
                       check.names = FALSE)
knitr::kable(.cov_tbl)
# `hm` fitted on covariates_to_numeric(d, ...), so the conversion is redone
# here before any model sees the data, exactly as hs-setup does.
.clash <- intersect(.all_cov, "time")
if (length(.clash)) {
  stop("A covariate is named \"time\", which collides with the horizon column predict() needs. ",
       "Rename it in the built dataset.", call. = FALSE)
}
dd <- covariates_to_numeric(d, .all_cov)
```

| covariate | surgical | transcatheter |
|:----------|:---------|:--------------|
| age       | yes      | yes           |
| hx_chf    | yes      | yes           |
| lvef      | yes      | yes           |

Table 3: Covariates in each group’s model

## Horizon and support

Code

``` r
if (!is.numeric(HORIZON) || length(HORIZON) != 1L || !is.finite(HORIZON) || HORIZON <= 0) {
  stop("HORIZON must be one positive number, in TIME's units.", call. = FALSE)
}
# Each model is checked against its OWN follow-up. One of the three source jobs
# predicted a group at 10 years whose own header said it had no 10-year data.
.max_obs <- vapply(models, function(a) {
  t <- a$reported$data$frame[[TIME]]
  if (!any(is.finite(t))) NA_real_ else max(t, na.rm = TRUE)
}, numeric(1L))
.short <- is.na(.max_obs) | .max_obs < HORIZON
if (any(.short)) {
  stop("HORIZON (", HORIZON, ") is beyond the last observed time of the model for ",
       paste0(names(models)[.short], " (", signif(.max_obs[.short], 4), ")", collapse = ", "),
       ". A model's prediction past its own follow-up is its parametric form running on, not an estimate.",
       call. = FALSE)
}
```

Predicting a patient through another group’s model is the purpose of
this job, so a patient outside a model’s fitted range is not refused.
The table below counts them, per model and covariate, so a reader can
see how far each comparison reaches beyond the data behind it. What
counts as too far is a clinical judgment.

Code

``` r
support <- do.call(rbind, lapply(names(models), function(m) {
  frame <- models[[m]]$reported$data$frame
  do.call(rbind, lapply(covariates[[m]], function(v) {
    if (!is.numeric(frame[[v]]) || !is.numeric(dd[[v]])) return(NULL)
    lo <- min(frame[[v]], na.rm = TRUE)
    hi <- max(frame[[v]], na.rm = TRUE)
    data.frame(model = m, covariate = v, fitted_min = lo, fitted_max = hi,
               below = sum(dd[[v]] < lo, na.rm = TRUE), above = sum(dd[[v]] > hi, na.rm = TRUE))
  }))
}))
knitr::kable(support, row.names = FALSE, digits = 3)
```

| model         | covariate | fitted_min | fitted_max | below | above |
|:--------------|:----------|-----------:|-----------:|------:|------:|
| surgical      | age       |         32 |         98 |     0 |     3 |
| surgical      | hx_chf    |          0 |          1 |     0 |     0 |
| surgical      | lvef      |         20 |         75 |     0 |     0 |
| transcatheter | age       |         35 |        100 |     5 |     0 |
| transcatheter | hx_chf    |          0 |          1 |     0 |     0 |
| transcatheter | lvef      |         22 |         73 |     1 |     7 |

Table 4: Patients outside each model’s fitted range, by covariate

## Predictions

⚠️ **The confidence limits here are about 68%, not 95%.** `CLEVEL` is
`0.68268948`, plus or minus one standard error, the SAS `HAZPRED`
convention that `hs-setup` also uses. A 95% band is nearly twice as
wide. The limits travel in the saved artifact, so **state the coverage
wherever they are shown.**

Code

``` r
# SAS convention, not a study choice: +/-1 SD, NOT 95%, with survival limits on
# the logit scale. hs-setup and hp use both; changing them here alone would put
# two coverages side by side with nothing saying so.
CLEVEL <- 0.68268948

pred <- do.call(rbind, lapply(names(models), function(m) {
  nd <- dd[, covariates[[m]], drop = FALSE]
  nd$time <- HORIZON
  p <- predict(models[[m]]$reported, newdata = nd, type = "survival",
               se.fit = TRUE, level = CLEVEL, conf.type = "logit")
  data.frame(row = seq_len(nrow(dd)), group = .actual, model = m,
             fit = p$fit, se.fit = p$se.fit, lower = p$lower, upper = p$upper)
}))

# A missing prediction is a failed one, and is caught before the range check,
# which would otherwise pass an all-NA result silently.
.bad <- !is.finite(pred$fit)
if (any(.bad)) {
  stop(sum(.bad), " of ", nrow(pred), " predictions are NA or non-finite, from model(s) ",
       paste(unique(pred$model[.bad]), collapse = ", "), ".", call. = FALSE)
}
# A finite fit with NA limits has one of two causes, and the fixes differ.
# Without a usable variance matrix, predict() returns se.fit as NA, and every
# limit with it. With one, a limit can still be undefined at the boundary: the
# logit limits need 0 < survival < 1, so a prediction of exactly 1 (or 0) has
# none. Left alone, either NA reaches the decision below, which stops on
# "missing value where TRUE/FALSE needed" and names neither the model nor the
# cause. This stops even where the decision is deleted: predictions without
# limits are not a result to save.
.no_cl <- !is.finite(pred$lower) | !is.finite(pred$upper)
.no_se <- .no_cl & !is.finite(pred$se.fit)
if (any(.no_se)) {
  stop("No confidence limits from the model(s) for ", paste(unique(pred$model[.no_se]), collapse = ", "),
       ": the hm fit has no usable variance matrix, missing or with a standard error ",
       "that is not finite, so no difference between groups can be judged. Refit that ",
       "group's hm model with fewer candidate covariates or with its shapes fixed.", call. = FALSE)
}
if (any(.no_cl)) {
  stop(sum(.no_cl), " of ", nrow(pred), " predictions from model(s) ",
       paste(unique(pred$model[.no_cl]), collapse = ", "), " have a standard error but no ",
       "confidence limits: the logit limits are undefined where predicted survival at ",
       "HORIZON is exactly 0 or 1 (here ", paste(unique(signif(pred$fit[.no_cl], 3)), collapse = ", "),
       "). Check HORIZON and the patients predicted there.", call. = FALSE)
}
stopifnot(all(pred$fit >= 0 & pred$fit <= 1))

# One row per patient: the treatment received and the CARRY columns a plotting
# job needs. The patient identifier is never saved: a study's ID can be the
# medical record number, and this file travels.
.id_col <- attr(job_data$record, "selection")$id
.carry_bad <- CARRY[tolower(CARRY) %in% tolower(c(.id_col, ID, "mrn", "emrn"))]
if (length(.carry_bad)) {
  stop("CARRY may not name a patient identifier: ", paste(.carry_bad, collapse = ", "), ".", call. = FALSE)
}
# `row` and `group` are the frame's own columns; a CARRY column of either name
# would sit beside them under the same name, and a reader takes the first.
.carry_clash <- intersect(CARRY, c("row", "group"))
if (length(.carry_clash)) {
  stop("CARRY may not name ", paste(.carry_clash, collapse = ", "), ": the saved frame already has ",
       "`row` and `group` columns. The treatment received is saved as `group` whatever GROUP is called.",
       call. = FALSE)
}
.carry_miss <- setdiff(CARRY, names(d))
if (length(.carry_miss)) {
  stop("CARRY names column(s) not in the cohort: ", paste(.carry_miss, collapse = ", "), ".", call. = FALSE)
}
patients <- data.frame(row = seq_len(nrow(d)), group = .actual)
patients <- cbind(patients, d[, CARRY, drop = FALSE])

summary_tbl <- stats::aggregate(fit ~ model + group, data = pred, FUN = stats::median)
names(summary_tbl)[names(summary_tbl) == "fit"] <- "median_survival"
knitr::kable(summary_tbl, row.names = FALSE, digits = 4)
```

| model         | group         | median_survival |
|:--------------|:--------------|----------------:|
| surgical      | surgical      |          0.7917 |
| transcatheter | surgical      |          0.7638 |
| surgical      | transcatheter |          0.6208 |
| transcatheter | transcatheter |          0.6194 |

Table 5: Median predicted survival at 5, by model and treatment received

## Decision

A patient’s **best-predicted** treatment is the model giving the highest
survival. It is called **optimal** only when the choice is separated:
the best model’s lower limit lies above the runner-up’s upper limit.
Point estimates that differ in the fourth decimal are not a choice, and
exact equality would not catch them. The limits are about 68%, so
“separated” means separated at that coverage. The template sets no
clinical tolerance of its own; what difference in survival matters is
the study’s to say.

Code

``` r
# Demo: optional. A named list, model -> the logical column saying which
#       patients were eligible for that treatment. An ineligible prediction
#       takes no part in the choice and is left unchanged in `pred`.
ELIGIBLE <- list()
```

Code

``` r
.wide <- function(col) {
  w <- vapply(names(models), function(m) pred[[col]][pred$model == m], numeric(nrow(d)))
  matrix(w, nrow = nrow(d), dimnames = list(NULL, names(models)))
}
.fit <- .wide("fit")
.lo <- .wide("lower")
.hi <- .wide("upper")
# An unnamed entry would be skipped by the loop below, leaving every model
# eligible: a malformed eligibility rule must stop, not become an unmasked choice.
if (length(ELIGIBLE) && (is.null(names(ELIGIBLE)) || any(!nzchar(names(ELIGIBLE))) ||
                           anyDuplicated(names(ELIGIBLE)))) {
  stop("Every ELIGIBLE entry needs a unique name: the model it applies to.", call. = FALSE)
}
for (m in names(ELIGIBLE)) {
  if (!m %in% names(models)) stop("ELIGIBLE names ", m, ", which is not in MODELS.", call. = FALSE)
  .ok <- d[[ELIGIBLE[[m]]]]
  if (!is.logical(.ok) || anyNA(.ok)) {
    stop("ELIGIBLE column for ", m, " must be logical with no missing values.", call. = FALSE)
  }
  .fit[!.ok, m] <- NA
}

.choose <- function(i) {
  f <- .fit[i, ]
  ok <- which(!is.na(f))
  if (length(ok) < 2L) {
    return(c(best = if (length(ok)) names(f)[ok] else NA_character_, optimal = NA_character_, tie = "FALSE"))
  }
  o <- ok[order(f[ok], decreasing = TRUE)]
  tie <- f[o[1L]] == f[o[2L]]
  separated <- !tie && .lo[i, o[1L]] > .hi[i, o[2L]]
  c(best = if (tie) NA_character_ else names(f)[o[1L]],
    optimal = if (separated) names(f)[o[1L]] else NA_character_,
    tie = as.character(tie))
}
.ch <- vapply(seq_len(nrow(d)), .choose, character(3L))
decision <- data.frame(row = seq_len(nrow(d)), group = .actual,
                       best = .ch["best", ], optimal = .ch["optimal", ], tie = .ch["tie", ] == "TRUE")

.levels <- names(models)
# A tie, or a patient with fewer than two eligible models, has no best model.
# They are counted in their own columns so every patient is in the table.
.best_lbl <- ifelse(decision$tie, "(tie)", ifelse(is.na(decision$best), "(no choice)", decision$best))
best_tbl <- table(received = factor(decision$group, .levels),
                  best = factor(.best_lbl, c(.levels, "(tie)", "(no choice)")))
.sep <- !is.na(decision$optimal)
.optimal_caption <- paste0("Treatment received against optimal treatment, the ", sum(.sep),
                           " patients whose choice is separated at ~68%; ", sum(!.sep), " are not")
cat(sum(decision$tie), "patient(s) have an exact tie between their two best models.\n")
```

    0 patient(s) have an exact tie between their two best models.

Code

``` r
knitr::kable(best_tbl)
```

|               | surgical | transcatheter | (tie) | (no choice) |
|:--------------|---------:|--------------:|------:|------------:|
| surgical      |      381 |            79 |     0 |           0 |
| transcatheter |      127 |           138 |     0 |           0 |

Table 6: Treatment received against best-predicted treatment, every
patient

Code

``` r
knitr::kable(table(received = factor(decision$group[.sep], .levels), optimal = factor(decision$optimal[.sep], .levels)))
```

|               | surgical | transcatheter |
|:--------------|---------:|--------------:|
| surgical      |       23 |             0 |
| transcatheter |        5 |             0 |

Table 7: Treatment received against optimal treatment, the 28 patients
whose choice is separated at ~68%; 697 are not

## Save

Code

``` r
# Read by the plotting jobs in this set. `clevel`, `horizon` and `overlap`
# travel with the estimates because each changes what the numbers mean, and a
# reader of the file should not have to recover them from prose.
art <- list(pred = pred, patients = patients, horizon = HORIZON, time = TIME, clevel = CLEVEL,
            models = MODELS, covariates = covariates, support = support, overlap = OVERLAP,
            decision = if (exists("decision")) decision else NULL)
art <- hvtiRtemplates:::.attach_handoff_lineage(
  art,
  data = .provenance_data,
  artifacts = .provenance_artifacts,
  analysis = list(
    time = list(variable = TIME),
    event = list(variable = EVENT, event = 1L, censored = 0L)
  ),
  cohort = cc
)
saveRDS(art, set_path("estimates", "hs-concordance.rds"))
```

## About this run

| Group | Item | Value |
|:---|:---|:---|
| Run | Started | 2026-10-21 08:02:18 EDT |
|  | Ended | 2026-10-21 08:02:19 EDT |
|  | Duration | 0 s |
|  | Status | final |
|  | Rendered by | gallery |
|  | Host | gallery |
| Job | File | hs.concordance.dead.approach.qmd |
|  | Template | hs.concordance |
|  | Subject | dead |
|  | Type | approach |
|  | hvtiRtemplates | 1.4.2 |
| Dataset `built` | Version file | built_20261021.parquet |
|  | Registered | 2026-10-21 |
|  | Source file | built.rds |
|  | Rows kept | 725 rows on 725 patients |
|  | WHERE | `!is.na(creat_pr)` |
|  | sha256 | 07a531bb5b35 |
|  | Manifest | current |
| Upstream | Handoff | `dead-surgical/hz.rds` (hazard-shape-model), rendered not recorded |
|  | Handoff | `dead-surgical/hm.rds` (hazard-regression-model), rendered 2026-10-21 08:01:56 -0400, data built_20261021.parquet |
|  | Handoff | `dead-transcatheter/hz.rds` (hazard-shape-model), rendered not recorded |
|  | Handoff | `dead-transcatheter/hm.rds` (hazard-regression-model), rendered 2026-10-21 08:02:11 -0400, data built_20261021.parquet |
| Reproducibility | renv | not active |
|  | renv.lock sha256 | d09f96b6cd21 |
