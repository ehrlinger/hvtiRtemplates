# Patient-level predictions and expected survival

# Patient-level predictions and expected survival

Published

2026-10-15 11:14

An `hs` job turns the risk-factor model an `hm` job fitted into
**predictions for individual patients**, and sets those against the
survival the general population would have had. The model is not
refitted here; it is read.

**This job is filed under `graphs/`, which reads oddly for something
named “setup”.** That placement follows the corpus rather than the name:
all ten `tp.hs.*` templates in the SAS library, and ten of the eleven R
`hs` jobs across the study tree, sit in `graphs/`. An `hs` job computes
what the plotting jobs beside it consume — the `setup` / `uses_setup`
pairing the corpus uses throughout. The reasoning is in
`hvtiRtemplates:dev/specs/2026-08-29-hs-template-design.md`.

Validation metrics — C-index, Brier score — are **not** here. The corpus
files them under `hs`, but the only R implementation is a loose script
on a shared drive with no package and no version, and no supported
template depends on an unpackaged file. They arrive once it has a home.

Code

``` r
SUBJECT <- "dead"
TYPE    <- "hz"
.in <- knitr::current_input(dir = TRUE)
.provenance_artifacts <- list()
suppressPackageStartupMessages({
  library(TemporalHazard)
  library(hvtiRutilities)
  library(hvtiRlifetables)
})

# The edit-obs-vs-exp chunk calls us_cohort_curve(), which arrived in
# hvtiRlifetables 0.1.2. Without this check a study on 0.1.1 gets "could not
# find function" from the middle of a render, after the model has been read
# and every prediction made: the symbol is named, the fix is not.
if (utils::packageVersion("hvtiRlifetables") < "0.1.2") {
  stop("This job needs hvtiRlifetables >= 0.1.2; ",
       utils::packageVersion("hvtiRlifetables"), " is installed. ",
       "us_cohort_curve(), which the edit-obs-vs-exp chunk calls, arrived in ",
       "0.1.2.\nUpdate it, then re-render.", call. = FALSE)
}

# 1.2.12, not 1.2.11. This job stores se.fit, and TemporalHazard #281 changed
# it on the survival path from se(H) to se(S) without a version bump, so a
# build reporting 1.2.11 may write either. 1.2.12 is the first release that
# certainly writes se(S), which is what the pred frame below says it holds.
if (utils::packageVersion("TemporalHazard") < "1.2.12") {
  stop("This job needs TemporalHazard >= 1.2.12; ",
       utils::packageVersion("TemporalHazard"), " is installed. ",
       "Earlier builds may store se(H) in se.fit.\n",
       "Update it, then re-render.", call. = FALSE)
}
# The study root is the nearest directory above this file holding _study.yml,
# so the job renders the same from the Render button, quarto render, or
# render_job(), at any depth, with no path in this document to edit.
# Without the guard in .job_setup(), an unedited job renders green over a
# meaningless analysis. In THIS file the danger is sharper than a wrong number:
# the unedited entry and stay levels are `hzr_stepwise()`'s defaults, which are
# LOOSER than the SAS job's, so an unedited screen admits variables the job
# being reproduced rejected -- and reports them as risk factors, in a table that
# looks exactly like a result.
# To render a job you have not finished, leave a chunk out with the chunk
# option skip, giving the reason in quotes, or call hvtiRtemplates::stop_here()
# in a chunk to leave out everything below it. A draft lists each one in a
# callout; a final render refuses them, as it refuses an unresolved marker.
# ?stop_here has more.
.job <- hvtiRtemplates:::.job_setup(SUBJECT, TYPE, envir = environment())
.root <- .job$root
set_path <- .job$set_path
.provenance_data <- list()
# `hm` reads the `hz` fit through this and writes its own model back, both by
# set, so a model can never be filed against a different set than the shapes it
# was built on. The write is in the `save` chunk at the foot of this file.
# The draft banners, if any, and the box under the title, after all the code above.
.job$notice
```

**final** · data: see About this run · rendered by gallery on gallery ·
hvtiRtemplates 1.4.0

## Study choices

Edit these values for this study before rendering.

Code

``` r
# The data, rows, identifier, time and event of the hz fit the hm model builds
# on, as hm.rds records them. NULL takes the value hz used; set it only to
# confirm it. A value set here that differs stops the job rather than predict
# for another cohort.
DATASET <- NULL
ANALYSIS_SET <- NULL
WHERE <- NULL
ID <- NULL
KEY <- NULL
TIME <- NULL
EVENT <- NULL

# No expected counts here: they are typed once, in the hz job, and hm.rds
# carries them. The cohort chunk checks this job's rows against them.

# Prediction horizons.
# Demo: prediction horizons.
HORIZONS <- c(1, 5, 10)

# Population survival matching columns and life table.
# Demo: population survival matching and life table settings.
AGE_COL   <- "age"

MALE_COL  <- "male"

# Demo: the values of MALE_COL that mean male, and of OTHER_COL that mean
# non-white, as the life tables split race. A 0/1 column takes 1; a `female`
# column takes MALE_LEVEL <- 0, a sex factor MALE_LEVEL <- "M", and a race
# factor every non-white level, OTHER_LEVELS <- c("Black", "Asian", "Other").
# A race level left out counts as white: the cohort chunk shows the mapping.
MALE_LEVEL <- 1

OTHER_COL <- "nonwhite"

OTHER_LEVELS <- 1

VINTAGE   <- "table2023"

TABLE     <- "sexrace"

SCALE     <- "years"
```

## Cohort and model

Code

``` r
# The checksum of every dataset in manifest.yaml is checked before anything is
# read, so a result can name the data that produced it. It stops on a mismatch.
hvtiRutilities::verify_manifest(file.path(.root, "manifest.yaml"))
.cfg <- study_config(start = .root)
# The model, not a refit. `hm.rds` is written by the hm job in this same set,
# so a prediction can never be filed against a different set than the model it
# came from.
.hm_read <- hvtiRtemplates:::.read_handoff(
  set_path("estimates", "hm.rds"), "hazard-regression-model", .cfg, "the hm job"
)
hm_art <- .hm_read$value
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
.provenance_data <- c(if (exists(".provenance_data")) .provenance_data else list(), list(job_data$provenance),
                      if (!is.null(job_data$provenance_join)) list(job_data$provenance_join))
knitr::kable(job_data$record, col.names = c("Data", ""))
```

| Data                |                                          |
|:--------------------|:-----------------------------------------|
| Source              | dataset `study` (built_20261015.parquet) |
| Rows read           | 800                                      |
| ID                  | `patient_id`                             |
| Identifiers dropped | none                                     |
| `!is.na(creat_pr)`  | removed 75                               |
| Rows kept           | 725 rows on 725 patients                 |

Table 1: The data this job read, as hz read it

Code

``` r
# The counts hm.rds records, which hm checked against hz's EXPECTED.
cc <- hvtiRtemplates:::.check_upstream_cohort(d, .hm_read$lineage, event = EVENT, time = TIME, source = "hm.rds")
```

Code

``` r
fit    <- hm_art$reported

# The covariates the model was actually fitted on. Taken from the artifact
# rather than re-declared here: a re-declared list drifts from the model the
# moment the hm job's screen changes, and `predict()` would then either error
# on a missing column or -- worse -- silently use a stale set.
#
# `hm` stores its screen as a LIST -- list(early = <chr>, late = <chr>) -- one
# character vector per phase, and saves it in that shape. Flatten it the same
# way hm itself does when it builds the model formula: `unique()` matters,
# because a variable offered to BOTH phases appears twice, and a duplicated
# column here makes a design matrix wider than the fitted coefficients.
COVARIATES <- unique(unlist(hm_art$covariates, use.names = FALSE))
stopifnot(is.character(COVARIATES), length(COVARIATES) > 0L)
missing_cols <- setdiff(COVARIATES, names(d))
if (length(missing_cols)) {
  stop("The model was fitted on covariate(s) absent from this cohort: ",
       paste(missing_cols, collapse = ", "),
       ". The cohort here is not the cohort hm was fitted on.", call. = FALSE)
}
```

## Predictions

Code

``` r
# A `hazard` object carries `call`, `call_env`, `spec`, `data`, `fit`,
# `legacy_args` and `engine` -- there is NO `formula` slot, and `spec` holds
# only dist/control/time_windows/phases. The formula is recoverable from
# `fit$call` only when the model was built through the formula interface;
# `hazard()` also accepts time=/status=, in which case it is not there at all.
# So the time column comes from the data selection hm.rds records rather than
# from the fit.
# A `hazard` object's `data` slot is a CONTAINER -- time, time_lower,
# time_upper, status, x, weights, frame -- not the model frame. The study's own
# columns are one level down, in `fit$data$frame`. Reading `fit$data[[TIME]]`
# returns NULL, which makes this guard unsatisfiable and turns the max() below
# into -Inf. Measured, not assumed.
if (!TIME %in% names(fit$data$frame)) {
  stop("TIME is \"", TIME, "\", which is not a column of the data the model was ",
       "fitted on. It must name the same follow-up column the hm job used.",
       call. = FALSE)
}

# The model cannot extrapolate past the follow-up it was fitted on, and
# `predict()` will not say so -- it returns a number for any time you give it.
# Beyond the last observed time that number is the fitted parametric form
# running on, not an estimate the data supports.
# An all-missing time column makes max(na.rm = TRUE) return -Inf rather than
# error, and the check below would then report "beyond the last observed time
# (-Inf)", which explains nothing. Catch the empty case where it can still be
# named.
if (!any(is.finite(fit$data$frame[[TIME]]))) {
  stop("Column \"", TIME, "\" in the fitted data has no finite values, so there ",
       "is no observed follow-up to compare HORIZONS against.", call. = FALSE)
}
# HORIZONS must be sorted. `us_matched()` enforces it too, but three chunks
# later and about `times`, not about the value the author actually edited --
# and the expected-survival join below pairs `us_cohort_curve()`'s output
# (times in order of first appearance) with `split()`'s (numeric order), which
# agree only while HORIZONS is sorted. Fail at the edit, not downstream of it.
if (is.unsorted(HORIZONS, strictly = TRUE)) {
  stop("HORIZONS must be in increasing order with no repeats; got ",
       paste(HORIZONS, collapse = ", "), ".", call. = FALSE)
}

.max_obs <- max(fit$data$frame[[TIME]], na.rm = TRUE)
if (any(HORIZONS > .max_obs)) {
  stop("HORIZONS contains ", paste(HORIZONS[HORIZONS > .max_obs], collapse = ", "),
       ", beyond the last observed time (", signif(.max_obs, 4),
       "). Shorten the horizon or say in the text why extrapolation is defensible.",
       call. = FALSE)
}
```

`predict()` needs one row per (patient, horizon): the covariates
identify the patient and a `time` column names the horizon.

⚠️ **The confidence limits this job computes are about 68%, not 95%.**
`CLEVEL` is `0.68268948`, which is `pnorm(1) - pnorm(-1)`: plus or minus
one standard error. That is the SAS `HAZPRED` convention, recovered from
its source during parity work rather than chosen here, and the published
papers state it, so the limits are correct. What can go wrong is the
reading of them. On the same fit and the same grid a 95% band is **1.97
times the width**, so anyone who takes these for 95% limits is reading
an interval roughly half as wide as they believe.

It matters more here than in a job that only prints them, because this
one does not draw them: `lower` and `upper` travel in the saved `pred`
artifact and the plotting jobs read them from there. By the time the
band reaches a figure, nothing beside it records which coverage it is.
**State the coverage wherever these numbers appear**, in this report and
in anything built from it.

Code

``` r
# One row per patient per horizon. Built explicitly rather than by looping
# `predict()` per horizon, so every prediction comes from ONE call and cannot
# drift between horizons.
# `time`, `.id` and `.horizon` are constructed below. A covariate with one of
# those names would be silently overwritten by the construction rather than
# erroring, so the collision is checked rather than assumed away.
# `hm` fitted on covariates_to_numeric(d, ...), not on the raw built data: that
# conversion turns numeric-looking FACTORS into numerics, and a model fitted
# after it has a different parameter count from one fitted before. hm.rds does
# not carry the converted frame, so the conversion is redone here. Predicting
# from the raw data instead would dummy-code a factor the model fitted
# linearly -- a different design matrix, and nothing in the output would say so.
dd <- covariates_to_numeric(d, COVARIATES)

.clash <- intersect(COVARIATES, c("time", ".id", ".horizon"))
if (length(.clash)) {
  stop("Covariate(s) ", paste(.clash, collapse = ", "), " collide with the ",
       "column names this chunk builds. Rename the column in the built ",
       "dataset, or this job will predict from overwritten values.",
       call. = FALSE)
}
nd <- do.call(rbind, lapply(HORIZONS, function(h) {
  x <- dd[, COVARIATES, drop = FALSE]
  x$time <- h
  x$.id  <- seq_len(nrow(dd))
  x$.horizon <- h
  x
}))

# CLEVEL and conf.type are SAS conventions recovered from the HAZPRED source
# during parity work, not study choices -- and NEITHER errors when wrong.
#
# CLEVEL is 0.68268948, which is pnorm(1) - pnorm(-1): plus or minus one
# standard error, about 68%, NOT 95%. The published papers state it. On the
# same fit and grid a 95% band is 1.97x the width, so a reader who takes these
# for 95% limits reads an interval roughly half as wide as they think.
#
# Survival limits are formed on the logit scale. predict.hazard() defaults to
# "log-log", the survfit standard, so conf.type must be passed explicitly.
#
# `06.01-hp.qmd` uses both, and this job's estimates are read by plotting jobs
# that do. Changing either here alone puts two coverages on one figure with
# nothing saying so. Label the coverage wherever these numbers are published.
CLEVEL <- 0.68268948   # SAS convention, not a study choice. +/-1 SD, NOT 95%.

p <- predict(fit, newdata = nd[, c(COVARIATES, "time")], type = "survival",
             se.fit = TRUE, level = CLEVEL, conf.type = "logit")

# `se.fit` is the standard error of `fit` on fit's own scale, so on this
# survival path it is se(S), the delta method applied to S = exp(-H). A
# TemporalHazard build without #281 wrote se(H) into the same column, and #281
# shipped inside version 1.2.11, so what an hs.rds holds depends on the build
# that produced it, not on when it was written. The guard above requires
# 1.2.12. The limits are not fit +/- z * se.fit either: they are built from
# se(H) on the conf.type scale.
pred <- data.frame(id = nd$.id, horizon = nd$.horizon,
                   fit = p$fit, se.fit = p$se.fit,
                   lower = p$lower, upper = p$upper)

# Two checks, and the order matters. A prediction that came back NA is a
# FAILED prediction, not an out-of-range one -- and `all(..., na.rm = TRUE)`
# would strip them and then return TRUE for an empty vector, so a run where
# EVERY prediction failed would pass a range check silently and render a table
# of NA. Catch the missing case first, loudly, then range-check what remains
# without na.rm so a partial failure cannot hide either.
.bad <- !is.finite(pred$fit)
if (any(.bad)) {
  stop(sum(.bad), " of ", nrow(pred), " predictions are NA or non-finite. ",
       "predict() returned no usable value for those rows -- check that the ",
       "cohort's covariates match the ones the model was fitted on, and that ",
       "TIME and HORIZONS are in the units the hz job used.", call. = FALSE)
}
# Survival is a probability. A value outside [0, 1] means the delta-method
# interval was built on the wrong scale, not that a patient is 103% alive.
stopifnot(all(pred$fit >= 0 & pred$fit <= 1))
# Split out rather than nested inside kable(): a table built inside its own
# printing call is hard to inspect when a number looks wrong, and the nesting
# is what tripped the indentation and brace linters this repo keeps on for
# templates on purpose.
by_horizon <- split(pred, pred$horizon)
summary_tbl <- do.call(rbind, lapply(by_horizon, function(g) {
  data.frame(horizon = g$horizon[[1L]], n = nrow(g),
             median = stats::median(g$fit, na.rm = TRUE),
             min = min(g$fit, na.rm = TRUE),
             max = max(g$fit, na.rm = TRUE))
}))
knitr::kable(summary_tbl, row.names = FALSE, digits = 4)
```

| horizon |   n | median |    min |    max |
|--------:|----:|-------:|-------:|-------:|
|       1 | 725 | 0.9214 | 0.5012 | 0.9886 |
|       5 | 725 | 0.7417 | 0.1574 | 0.9535 |
|      10 | 725 | 0.5636 | 0.0269 | 0.9114 |

Table 2: Predicted survival by horizon, across the cohort

## Expected population survival

Code

``` r
# Named columns are checked before use, as the model chunk does for covariates.
# Without this a typo surfaces as "`id` must be the same length as `age`; got
# N and 0" from inside us_matched(), which never names the column at fault.
.absent <- setdiff(c(AGE_COL, MALE_COL, OTHER_COL), names(d))
if (length(.absent)) {
  stop("Column(s) not in the cohort: ", paste(.absent, collapse = ", "),
       ". Set AGE_COL, MALE_COL and OTHER_COL to this study's own column names.",
       call. = FALSE)
}

# The 0/1 indicators the life tables take, derived from the study's own coding.
.male <- hvtiRtemplates:::.lifetable_indicator(d[[MALE_COL]], MALE_LEVEL, MALE_COL, "MALE_LEVEL",
                                               counted = c("female", "male"))
.other <- hvtiRtemplates:::.lifetable_indicator(d[[OTHER_COL]], OTHER_LEVELS, OTHER_COL, "OTHER_LEVELS",
                                                counted = c("white", "non-white"))
knitr::kable(rbind(attr(.male, "mapping"), attr(.other, "mapping")), row.names = FALSE)
```

| column   | value |   n | counted_as |
|:---------|:------|----:|:-----------|
| male     | 0     | 268 | female     |
| male     | 1     | 457 | male       |
| nonwhite | 0     | 571 | white      |
| nonwhite | 1     | 154 | non-white  |

Table 3: How each patient’s sex and race are counted for the life tables

Code

``` r
# Two failure modes, both caught here rather than inside us_matched(): unset,
# and set to something that is not a vintage. The second matters because the
# valid values are not guessable -- "table2023" is not "2023" -- and an error
# raised three calls down names neither the argument nor the alternatives.
#
# us_lifetable_vintages() returns a DATA FRAME -- vintage, n_strata,
# nonwhite_code, nonwhite_meaning, added -- not a character vector. The
# `$vintage` is deliberate; pasting the frame prints column-wise nonsense.
valid_vintages <- us_lifetable_vintages()$vintage
if (is.null(VINTAGE)) {
  stop("VINTAGE is unset. Choose one of: ", paste(valid_vintages, collapse = ", "),
       " -- and record WHY in the text above. There is no safe default; see the ",
       "comment on this chunk.", call. = FALSE)
}
if (!VINTAGE %in% valid_vintages) {
  stop("VINTAGE is \"", VINTAGE, "\", which is not a life table vintage. ",
       "Valid values: ", paste(valid_vintages, collapse = ", "), ".",
       call. = FALSE)
}

# Read this before choosing, and print it in the report:
knitr::kable(us_lifetable_vintages(), row.names = FALSE)
expected <- us_matched(
  age = d[[AGE_COL]], male = as.vector(.male), other = as.vector(.other),
  times = HORIZONS, id = seq_len(nrow(d)),
  vintage = VINTAGE, table = TABLE, scale = SCALE, individual = TRUE
)
```

| vintage | n_strata | nonwhite_code | nonwhite_meaning | added |
|:---|---:|:---|:---|:---|
| table84 | 9 | o | Other (all non-white), named honestly by this vintage | NA |
| table2008 | 9 | b | Black, per the macro’s documentation; not independently verified | NA |
| table2023 | 9 | b | risk-weighted average of Black, Asian, American Indian and Hispanic death rates, weighted by number at risk. NOT Black, despite the stratum code and despite the macro’s own comment. | 2025-12-23 |

Table 4: Life table vintages, and what each one’s non-white stratum
means

Code

``` r
# The cohort average at each horizon, which is what gets overlaid on an
# actuarial curve. This was derived inline until hvtiRlifetables 0.1.2 shipped
# `us_cohort_curve()` (hvtiRlifetables#16); it is now one call, and the numbers
# are unchanged -- checked to 1e-12 against the derivation it replaces before
# the swap, because the comment that stood here promised exactly that.
#
# Prefer the function over re-deriving it. The averaging is not arbitrary: it
# follows `%usmatchd` (lines 338-350), taking the UNWEIGHTED cohort mean of
# survival, over SURVIVAL rather than cumulative hazard, with no patient
# weighted by follow-up. Two studies that each roll their own average
# differently is the drift that issue was filed to stop.
#
# ⚠️ It deliberately does NOT drop NA. Every value `us_matched()` returns is
# finite by construction, so an NA arriving here is a defect rather than a
# datum, and averaging around it would hide it. The inline version used
# `na.rm = TRUE` and would have.
#
# `us_cohort_curve()` returns `time`, `smatched` and `hmatched`. `smatched` is
# the matched SURVIVAL column -- `agesurv` in `us_matched()`'s output is the
# age-matched baseline, a different quantity, and taking it would be a
# plausible number for a different question.
#
# Demo: to report expected survival within groups -- age band, treatment arm,
#       era -- pass `by =`. It carries VALUES, not column names, and `expected`
#       holds one row per patient per time, so a patient-level grouping has to
#       be expanded to it. Grouping is not stratification: `table =` above
#       chose which strata the life TABLE is built from; `by` chooses how the
#       resulting curves are grouped for reporting, and a report broken down by
#       age band is normally still matched on "sexrace".
exp_curve <- us_cohort_curve(expected)
exp_avg <- stats::setNames(exp_curve$smatched, exp_curve$time)
obs_avg <- vapply(split(pred$fit, pred$horizon), mean, numeric(1), na.rm = TRUE)

stopifnot(identical(names(exp_avg), names(obs_avg)))
obs_vs_exp <- data.frame(
  horizon  = as.numeric(names(obs_avg)),
  observed = unname(obs_avg),
  expected = unname(exp_avg)
)
obs_vs_exp$ratio <- obs_vs_exp$observed / obs_vs_exp$expected
```

Code

``` r
knitr::kable(obs_vs_exp, row.names = FALSE, digits = 4)
```

| horizon | observed | expected |  ratio |
|--------:|---------:|---------:|-------:|
|       1 |   0.8996 |   0.9812 | 0.9169 |
|       5 |   0.7035 |   0.8999 | 0.7817 |
|      10 |   0.5364 |   0.7843 | 0.6840 |

Table 5: Model-predicted against age, sex and race matched population
survival

A ratio below 1 says the cohort does worse than the matched general
population at that horizon. It is a comparison, not a test — no interval
is attached, because the expected curve carries no sampling error of its
own here.

## Save

Code

``` r
# Read by the plotting jobs in this set. `vintage` travels WITH the estimates
# rather than being recorded only in prose: an expected curve whose vintage has
# to be recovered later is the defect this template's vintage marker exists to
# prevent, and it would be reintroduced here by omitting it.
#
# `clevel` travels with the estimates for the same reason `vintage` does: a
# confidence limit whose coverage has to be inferred later is a number waiting
# to be misread, and 0.68268948 is not the coverage anyone assumes.
hs_art <- list(pred = pred, expected = expected, obs_vs_exp = obs_vs_exp,
               horizons = HORIZONS, covariates = COVARIATES, vintage = VINTAGE,
               clevel = CLEVEL)
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
saveRDS(hs_art, set_path("estimates", "hs.rds"))
```

## About this run

| Group | Item | Value |
|:---|:---|:---|
| Run | Started | 2026-10-15 11:14:15 EDT |
|  | Ended | 2026-10-15 11:14:15 EDT |
|  | Duration | 0 s |
|  | Status | final |
|  | Rendered by | gallery |
|  | Host | gallery |
| Job | File | hs.setup.dead.hz.qmd |
|  | Template | hs.setup |
|  | Subject | dead |
|  | Type | hz |
|  | hvtiRtemplates | 1.4.0 |
| Dataset `built` | Version file | built_20261015.parquet |
|  | Registered | 2026-10-15 |
|  | Source file | built.rds |
|  | Rows kept | 725 rows on 725 patients |
|  | WHERE | `!is.na(creat_pr)` |
|  | sha256 | f632480029c1 |
|  | Manifest | current |
| Upstream | Handoff | `dead-hz/hz.rds` (hazard-shape-model), rendered not recorded |
|  | Handoff | `dead-hz/hm.rds` (hazard-regression-model), rendered 2026-10-15 11:13:58 -0400, data built_20261015.parquet |
| Reproducibility | renv | not active |
