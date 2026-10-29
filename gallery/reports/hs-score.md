# Risk score at the start of each segment

# Risk score at the start of each segment

Published

2026-10-29 10:33

An `hs-score` job scores each **segment** of a start/stop cohort with
the time-varying model an `hm` job fitted on it. A segment is a stretch
of one patient’s follow-up during which the covariates hold their
values. Its score is the model evaluated **at the segment’s own start,
with the segment’s own covariates**: the risk the model assigns to the
patient as they stood when that segment began. The model is not refitted
here; it is read.

It follows the SAS `hs.*.mort_score.tvc` jobs, which set the prediction
time to each segment’s start and ran `%HAZPRED` on the time-varying
model:

- `scr_haz` is 100 times the instantaneous hazard at the start;
- `scr_mort` is 100 times one minus the survival at the start, the
  percentage who would have died by then under that segment’s
  covariates.

`scr_mort` is **0 for every segment that starts at time zero**, which is
each patient’s first segment in most builds: no one has died by time
zero. SAS gives the same 0. A score that ought to separate patients at
entry is `scr_haz`.

`hs-setup` predicts one row per patient at fixed horizons, and stops on
a start/stop model: a patient has a covariate row per segment, and SAS
has no horizon prediction for a time-varying model to follow. This job
stops on a model that is not start/stop, for which `hs-setup` is the
job.

Code

``` r
SUBJECT <- "dead_segments"
TYPE    <- "hz"
.in <- knitr::current_input(dir = TRUE)
.provenance_artifacts <- list()
suppressPackageStartupMessages({
  library(TemporalHazard)
  library(hvtiRutilities)
})
# 1.2.13 is the floor hm sets for a start/stop fit, and the one this job's
# tests run against. An hm.rds of start/stop rows was written by 1.2.13 or
# later, and a reader older than its writer is not a pairing anyone tested.
if (utils::packageVersion("TemporalHazard") < "1.2.13") {
  stop("This job needs TemporalHazard >= 1.2.13; ",
       utils::packageVersion("TemporalHazard"), " is installed. ",
       "hm fits start/stop rows only from 1.2.13.\n",
       "Update it, then re-render.", call. = FALSE)
}
# The study root is the nearest directory above this file holding _study.yml,
# so the job renders the same from the Render button, quarto render, or
# render_job(), at any depth, with no path in this document to edit.
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

**final** · data: see About this run · rendered by gallery on gallery ·
hvtiRtemplates 1.5.4

## Study choices

Edit these values for this study before rendering.

Code

``` r
# The data, rows, identifier, time and event of the hz fit the hm model builds
# on, as hm.rds records them. NULL takes the value hz used; set it only to
# confirm it. A value set here that differs stops the job rather than score
# another cohort. The start comes from hm.rds too, and has no setting here.
DATASET <- NULL
ANALYSIS_SET <- NULL
WHERE <- NULL
ID <- NULL
KEY <- NULL
TIME <- NULL
EVENT <- NULL

# Demo: columns a later job needs beside each score, such as the covariates
#       or the segment's state. The scores carry a row number and a patient
#       sequence number, not the patient identifier, so a column naming the
#       identifier is refused.
CARRY <- "creat_pr"
```

## Cohort and model

Code

``` r
# The checksum of every dataset in manifest.yaml is checked before anything is
# read, so a result can name the data that produced it. It stops on a mismatch.
hvtiRutilities::verify_manifest(file.path(.root, "manifest.yaml"))
.cfg <- study_config(start = .root)
# The model, not a refit, from the hm job in this same set.
.hm_read <- hvtiRtemplates:::.read_handoff(
  set_path("estimates", "hm.rds"), "hazard-regression-model", .cfg, "the hm job"
)
hm_art <- .hm_read$value
# A segment score needs segments. A model with one row per patient has no
# segment start to score at; hs-setup predicts it at fixed horizons instead.
if (is.null(.hm_read$lineage$selection$start)) {
  stop("The fit in hm.rds has one row per patient, not start/stop segments: hz was run without START. ",
       "This job scores each segment at its start. For one row per patient, use hs-setup.", call. = FALSE)
}
.provenance_data <- c(.hm_read$lineage$data, .provenance_data)
.provenance_artifacts <- c(.hm_read$lineage$artifacts, list(.hm_read$record))
```

Code

``` r
.up <- hvtiRtemplates:::.read_upstream_job_data(
  .cfg, .hm_read$lineage,
  list(dataset = DATASET, analysis_set = ANALYSIS_SET, where = WHERE, id = ID, key = KEY,
       time = TIME, event = EVENT),
  source = "hm.rds"
)
job_data <- .up$job_data
d <- job_data$data
TIME <- .up$selection$time
EVENT <- .up$selection$event
START <- .up$selection$start
.provenance_data <- c(if (exists(".provenance_data")) .provenance_data else list(), list(job_data$provenance),
                      if (!is.null(job_data$provenance_join)) list(job_data$provenance_join))
knitr::kable(job_data$record, col.names = c("Data", ""))
```

| Data                |                                                |
|:--------------------|:-----------------------------------------------|
| Source              | dataset `segments` (segments_20261029.parquet) |
| Rows read           | 2,014                                          |
| ID                  | `patient_id`                                   |
| Identifiers dropped | none                                           |
| `!is.na(creat_pr)`  | removed 191                                    |
| Rows kept           | 1,823 rows on 725 patients                     |

Table 1: The data this job read, as hz read it

Code

``` r
# The counts hm.rds records, which hm checked against hz's EXPECTED. For
# start/stop rows they count segments, as SAS counts observations.
cc <- hvtiRtemplates:::.check_upstream_cohort(d, .hm_read$lineage, event = EVENT, time = TIME, source = "hm.rds")
```

Code

``` r
fit <- hm_art$reported
# The selection says start/stop; the fit must agree. A fit without entry times
# followed every segment from time zero, and its scores belong to that model.
if (!hvtiRtemplates:::.has_entry_times(fit)) {
  stop("hm.rds records start/stop rows (START = \"", START, "\"), but its reported model has no entry times. ",
       "Rerun hm as add_job() writes it, which fits Surv(START, TIME, EVENT).", call. = FALSE)
}
# The covariates the model was fitted on, from the artifact: hm stores its
# screen as list(early = <chr>, late = <chr>), and a variable offered to both
# phases appears twice, so the list is flattened with unique() as hm does.
COVARIATES <- unique(unlist(hm_art$covariates, use.names = FALSE))
stopifnot(is.character(COVARIATES), length(COVARIATES) > 0L)
missing_cols <- setdiff(c(START, COVARIATES), names(d))
if (length(missing_cols)) {
  stop("Column(s) absent from this cohort: ", paste(missing_cols, collapse = ", "),
       ". The cohort here is not the cohort hm was fitted on.", call. = FALSE)
}
```

## Scores

Code

``` r
# hm fitted on covariates_to_numeric(d, ...), not on the raw built data, and
# hm.rds does not carry the converted frame, so the conversion is redone here.
# Predicting from the raw data would dummy-code a factor the model fitted
# linearly, and nothing in the output would say so.
dd <- covariates_to_numeric(d, COVARIATES)
if ("time" %in% COVARIATES) {
  stop("A covariate is named `time`, which is the column predict() reads the prediction time from. ",
       "Rename it in the built dataset.", call. = FALSE)
}
# Each segment at its OWN start, with its own covariates: SAS `years = iv_start`
# before %HAZPRED. The start, not the stop: at the stop the score would count the
# segment's own follow-up, which is not known when the segment begins.
nd <- dd[, COVARIATES, drop = FALSE]
nd$time <- d[[START]]
.haz <- predict(fit, newdata = nd, type = "hazard")
.surv <- predict(fit, newdata = nd, type = "survival")
# A first segment starts at zero, where the hazard is the early phase's limit.
# It is finite for the shapes measured: SAS wrote a non-missing _hazard on every
# row of a model with nu = -1, m = 0, and TemporalHazard agrees. With nu > 0 and
# m = 0, TemporalHazard returns NaN at exactly zero; no SAS output for that shape
# has been read, so it stops here rather than take a value from either side.
.bad <- !is.finite(.haz) | !is.finite(.surv)
if (any(.bad)) {
  stop(sum(.bad), " of ", nrow(nd), " segments have no finite score, ", sum(.bad & nd$time == 0), " of them ",
       "starting at zero. Check that the cohort's covariates match the ones the model was fitted on, and that ",
       START, " is in the units the hz job used. At zero, an early phase with nu > 0 and m = 0 has no value in ",
       "TemporalHazard.", call. = FALSE)
}
stopifnot(all(.surv >= 0 & .surv <= 1))

# The patient identifier is never saved: a study's ID can be the medical
# record number, and this file travels. `row` is the row of the selection as
# the data chunk rebuilds it, and `patient` numbers the patients in the order
# they first appear, as the SAS job's `ptid` does.
.id_col <- .up$selection$id
.carry_bad <- CARRY[tolower(CARRY) %in% tolower(c(.id_col, ID, "mrn", "emrn"))]
if (length(.carry_bad)) {
  stop("CARRY may not name a patient identifier: ", paste(.carry_bad, collapse = ", "), ".", call. = FALSE)
}
.own <- c("row", "patient", START, TIME, EVENT, "scr_haz", "scr_mort")
.carry_clash <- intersect(CARRY, .own)
if (length(.carry_clash)) {
  stop("CARRY may not name ", paste(.carry_clash, collapse = ", "), ": the saved scores already carry it.",
       call. = FALSE)
}
.carry_miss <- setdiff(CARRY, names(d))
if (length(.carry_miss)) {
  stop("CARRY names column(s) not in the cohort: ", paste(.carry_miss, collapse = ", "), ".", call. = FALSE)
}
score <- data.frame(row = seq_len(nrow(d)), patient = match(d[[.id_col]], unique(d[[.id_col]])))
score[c(START, TIME, EVENT)] <- d[c(START, TIME, EVENT)]
score$scr_haz <- 100 * unname(.haz)
score$scr_mort <- 100 * (1 - unname(.surv))
score <- cbind(score, d[, CARRY, drop = FALSE])

summary_tbl <- data.frame(
  score = c("scr_haz", "scr_mort"),
  segments = nrow(score), patients = max(score$patient),
  median = c(stats::median(score$scr_haz), stats::median(score$scr_mort)),
  min = c(min(score$scr_haz), min(score$scr_mort)),
  max = c(max(score$scr_haz), max(score$scr_mort))
)
knitr::kable(summary_tbl, row.names = FALSE, digits = 4)
```

| score    | segments | patients | median |    min |      max |
|:---------|---------:|---------:|-------:|-------:|---------:|
| scr_haz  |     1823 |      725 | 9.2952 | 0.9032 | 1339.509 |
| scr_mort |     1823 |      725 | 5.0943 | 0.0000 |   84.430 |

Table 2: Scores across the segments, in percent

## Save

Code

``` r
# `start` travels with the scores, so a reader can tell they were taken at each
# segment's start and not at a horizon.
hs_art <- list(score = score, covariates = COVARIATES, start = START, time = TIME, event = EVENT)
hs_art <- hvtiRtemplates:::.attach_handoff_lineage(
  hs_art,
  data = .provenance_data,
  artifacts = .provenance_artifacts,
  analysis = list(
    time = list(variable = TIME),
    event = list(variable = EVENT, event = 1L, censored = 0L)
  ),
  cohort = cc
)
saveRDS(hs_art, set_path("estimates", "hs-score.rds"))
```

## About this run

| Group | Item | Value |
|:---|:---|:---|
| Run | Started | 2026-10-29 10:33:34 EDT |
|  | Ended | 2026-10-29 10:33:34 EDT |
|  | Duration | 0 s |
|  | Status | final |
|  | Rendered by | gallery |
|  | Host | gallery |
| Job | File | hs.score.dead_segments.hz.qmd |
|  | Template | hs.score |
|  | Subject | dead_segments |
|  | Type | hz |
|  | hvtiRtemplates | 1.5.4 |
| Dataset `segments` | Version file | segments_20261029.parquet |
|  | Version date | 2026-10-29 |
|  | Source file | segments.rds |
|  | Rows kept | 1,823 rows on 725 patients |
|  | WHERE | `!is.na(creat_pr)` |
|  | sha256 | 9590f19806c4 |
|  | Manifest | current |
| Upstream | Handoff | `dead_segments-hz/hz.rds` (hazard-shape-model), rendered not recorded |
|  | Handoff | `dead_segments-hz/hm.rds` (hazard-regression-model), rendered 2026-10-29 10:33:13 -0400, data segments_20261029.parquet |
| Reproducibility | renv | not active |
|  | renv.lock sha256 | d09f96b6cd21 |
