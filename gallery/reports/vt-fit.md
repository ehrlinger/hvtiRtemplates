# Virtual twins: fit

# Virtual twins: fit

Published

2026-10-29 10:42

Gallery job on the synthetic cohort: mitral repair against replacement,
and freedom from reintervention to eight years.

A `vt-fit` job builds virtual twins. A forest is grown on each arm
alone, and every patient is then predicted under **both** arms: the arm
they received and the one they did not. That gives each patient two
predicted survival curves, one per arm. The difference in restricted
mean survival time (RMST) to `HORIZON` between the two curves is the
patient’s estimated effect of the treatment.

A patient’s twin curve for the arm they did not receive is an
extrapolation from patients who did. Where no such patients resemble
them, the prediction says nothing, so the job also judges eligibility:
which patients have comparable patients in the other arm.

This template is **in flight**: it is built from one study, and a second
study running it through to `vt-explain` is what moves it to shipped.

Code

``` r
SUBJECT <- "reint"
TYPE    <- "vt"
.in <- knitr::current_input(dir = TRUE)
suppressPackageStartupMessages({
  library(randomForestSRC)
  library(cluster)
  library(hvtiRpropensity)
  library(hvtiPlotR)
  library(hvtiRutilities)
})
# One thread, so a fit reproduces from machine to machine. Left unset,
# randomForestSRC runs on every core its OpenMP build can see, and the forests
# changed with the thread count with every seed held fixed.
options(rf.cores = 1L, mc.cores = 1L)
# The versions this template was verified against on 2026-10-22. Below them a
# call here can fail or change meaning, and the message would arrive mid-render
# rather than here.
for (.floor in list(c("randomForestSRC", "3.7.0"), c("hvtiRpropensity", "0.2.0"), c("hvtiPlotR", "2.8.9"))) {
  if (utils::packageVersion(.floor[1]) < .floor[2]) {
    stop("This job needs ", .floor[1], " >= ", .floor[2], "; ", utils::packageVersion(.floor[1]),
         " is installed.\nUpdate it, then re-render.", call. = FALSE)
  }
}
# The study root is the nearest directory above this file holding _study.yml,
# so the job renders the same from the Render button, quarto render, or
# render_job(), at any depth, with no path in this document to edit.
# Without the guard in .job_setup(), an unedited job renders green over a
# meaningless analysis. Here that is a fit of the template's placeholder
# arms and outcome, whose tables look exactly like a result.
# To render a job you have not finished, leave a chunk out with the chunk
# option skip, giving the reason in quotes, or call hvtiRtemplates::stop_here()
# in a chunk to leave out everything below it. A draft lists each one in a
# callout; a final render refuses them, as it refuses an unresolved marker.
# ?stop_here has more.
.job <- hvtiRtemplates:::.job_setup(SUBJECT, TYPE, envir = environment())
.root <- .job$root
set_path <- .job$set_path
.provenance_data <- list()
# Saves a figure as <name>.png, .pdf and .tiff in this set's graphs/ folder (or `kind`'s),
# under the SAVE_FIGURES and FIGURES study choices.
save_figure <- function(plot, name, width = 6, height = 4, kind = "graphs", linked = FALSE) {
  hvtiRtemplates:::.save_figure(plot, set_path(kind, paste0(name, ".png")), width, height,
                                SAVE_FIGURES, FIGURES, linked)
}

# The draft banners, if any, and the box under the title, after all the code above.
.job$notice
```

**final** · data `built` `built_20261029.parquet`, dated 2026-10-29 ·
rendered by gallery on gallery · hvtiRtemplates 1.5.4

## Study choices

Edit these values for this study before rendering.

Code

``` r
DATASET <- "built"
ANALYSIS_SET <- NULL
WHERE <- NULL
ID <- "patient_id"
KEY <- NULL

# Optional, and needs no edit: NULL reads the cohort alone. To join one
# registered ancillary dataset (labs, echoes), name it in JOIN. The cohort
# above decides the patients, one row each; the joined records of other
# patients are dropped and counted in the data table.
#   JOIN_VARS: the cohort columns each joined row carries; NULL carries all.
#   REDUCE: NULL keeps a row per joined record; list(rule = "first", by = "date")
#     keeps one row per patient. This job models one row per
#     patient, so a JOIN without REDUCE stops here.
#   JOIN_KEY: overrides the joined dataset's registered key.
JOIN <- NULL
JOIN_VARS <- NULL
REDUCE <- NULL
JOIN_KEY <- NULL
TIME <- "iv_reint"
STATUS <- "reint"
ARM <- "mv_procedure"
# Demo: the two arms, in the order the difference is taken: a positive diff
# favors ARMS[1].
ARMS <- c("repair", "replace")
# Demo: rows that received neither arm are predicted under both and fit by
# neither. NULL treats a missing ARM as no arm; a vector of levels names them.
NO_ARM <- NULL
# Demo: a vp-fit set ("<subject>-<type>") whose selected set the forests use,
# or NULL to use PREDICTORS. The screen must not have seen the arm: that is what
# makes it treatment-blind, and this job checks it.
VP_SET <- NULL
PREDICTORS <- c("age", "female", "bmi", "hx_chf", "hx_dm", "nyha_pr", "lvef", "creat_pr", "lvedd", "lvesd", "la_diam", "rvsp", "e_e")
# Demo: anything measured after the treatment decision. A screen does not know
# when a variable was measured, and a later procedure flag predicts the outcome
# because it is part of the path to it.
EXCLUDE <- character()
# Demo: eligibility methods, one or more of "gower" and "sid". "sid" reads the
# SID distance of the sid set named in SID_SET.
ELIGIBILITY <- c("gower", "sid")
COMBINE <- "any"                            # Demo: "any" flags a patient any method flags; "all" only when all do.
SID_SET <- "echo-sid"
# Demo: graded predictors coded as numbers (a 0 to 3 degree, say). The Gower
# distance ranks them, so 0 against 3 is farther than 0 against 1; unnamed, every
# mismatched grade counts the same. Names the predictors do not include are ignored.
ORDINAL <- character()
# Demo: "na.impute" imputes missing predictors inside each forest; "na.omit"
# drops the patient. The outcome is required either way.
NA_ACTION <- "na.impute"
# Demo: for stacked multiple imputations, the column numbering them. This
# release uses one completed dataset, IMPUTATION_USE; pooling is not done.
IMPUTATION <- NULL
IMPUTATION_USE <- 1L
# Demo: the RMST horizon, in TIME's units. Keep it inside the follow-up of both
# arms; past the last follow-up every curve is cut at the same place and the
# difference means nothing. This job stops if it is not.
HORIZON <- 8
NTREE <- 500
NSPLIT <- 8
SEED <- 1024                                # Demo: part of every cache key.
# Set TRUE after changing a choice above. A cache whose inputs changed stops the
# render instead of returning the old result; TRUE recomputes only the caches
# that are out of date.
REFIT <- FALSE

# Each figure is saved to graphs/ as a PNG (for Word), and a PDF and a TIFF (for the publisher).
# SAVE_FIGURES <- FALSE saves none; FIGURES keeps only the figures whose names
# start with one of its entries, e.g. FIGURES <- c("vp-fit-coverage"). The names are the
# file names, listed for each template in the templates README.
SAVE_FIGURES <- TRUE
FIGURES <- NULL
```

## Cohort

Code

``` r
# The checksum of every dataset in manifest.yaml is checked before anything is
# read, so a result can name the data that produced it. It stops on a mismatch.
hvtiRutilities::verify_manifest(file.path(.root, "manifest.yaml"))
.cfg <- study_config(start = .root)
# Stacked imputations repeat each patient once per imputation, so a row is unique on the ID and the imputation.
if (!is.null(IMPUTATION)) KEY <- unique(c(if (is.null(KEY)) ID else KEY, IMPUTATION))
job_data <- hvtiRtemplates::read_job_data(.cfg, dataset = DATASET, analysis_set = ANALYSIS_SET,
                                          where = WHERE, id = ID, key = KEY, join = JOIN, join_vars = JOIN_VARS,
                                          reduce = REDUCE, join_key = JOIN_KEY, one_row_per_patient = TRUE,
                                          imputation = IMPUTATION)
d <- job_data$data
.provenance_data <- c(if (exists(".provenance_data")) .provenance_data else list(), list(job_data$provenance),
                      if (!is.null(job_data$provenance_join)) list(job_data$provenance_join))
knitr::kable(job_data$record, col.names = c("Data", ""))
if (!is.null(IMPUTATION)) {
  IMPUTATION <- attr(job_data$record, "selection")$imputation
  .m <- length(unique(d[[IMPUTATION]]))
  if (!IMPUTATION_USE %in% d[[IMPUTATION]]) {
    stop("IMPUTATION_USE = ", IMPUTATION_USE, " is not an imputation in ", IMPUTATION, ".", call. = FALSE)
  }
  d <- d[d[[IMPUTATION]] == IMPUTATION_USE, setdiff(names(d), IMPUTATION), drop = FALSE]
  cat("This job uses imputation ", IMPUTATION_USE, " of ", .m, ". The forests are not pooled across imputations.\n",
      sep = "")
}
# read_job_data() matches ID case-insensitively and falls back from ccfid to an
# MRN, without changing ID here. Take the name it resolved.
ID <- attr(job_data$record, "selection")$id
# This job saves one row per patient (vt.rds), and a sid set joins on it. No
# saved artifact holds a raw identifier, an MRN least of all (#203), so the ID
# is replaced here by its digest under the study's key, the form a sid set
# saves too. Everything below, and everything saved, carries only the digest.
.id_key <- hvtiRtemplates:::.study_id_key(.root)
d[[ID]] <- hvtiRtemplates:::.id_digest(d[[ID]], .id_key)
.no_arm <- if (is.null(NO_ARM)) is.na(d[[ARM]]) else d[[ARM]] %in% NO_ARM
.treated <- d[[ARM]] %in% ARMS
.other <- !.no_arm & !.treated
if (any(.other)) {
  stop(sum(.other), " row(s) have an ARM that is neither in ARMS nor NO_ARM: ",
       paste(unique(d[[ARM]][.other]), collapse = ", "), ".", call. = FALSE)
}
# Arms are names, never positions. A numeric ARM (0 and 1) would otherwise index
# the lists of forests by position, so ARMS and the arm column become text once,
# here, and every list below is keyed by that text. A missing arm stays NA.
ARMS <- as.character(ARMS)
d[[ARM]] <- as.character(d[[ARM]])
.no_outcome <- .treated & (is.na(d[[TIME]]) | is.na(d[[STATUS]]))
if (any(.no_outcome)) {
  stop(sum(.no_outcome), " treated patient(s) have no outcome. A forest cannot learn from them, and imputing one ",
       "would invent follow-up. Resolve them in the dataset build.", call. = FALSE)
}
if (!all(d[[STATUS]][.treated] %in% c(0, 1))) stop(STATUS, " must be coded 0 and 1.", call. = FALSE)
NA_ACTION <- match.arg(NA_ACTION, c("na.impute", "na.omit"))
# Run again after na.omit drops patients (predictors chunk): the guard must hold for the patients the forests see.
.arm_counts <- function(d, when = "") {
  counts <- do.call(base::rbind, lapply(ARMS, function(a) {
    i <- d[[ARM]] %in% a
    data.frame(Arm = a, Patients = sum(i), Events = sum(d[[STATUS]][i] == 1, na.rm = TRUE))
  }))
  thin <- counts$Patients < 2 | counts$Events < 1
  if (any(thin)) {
    stop("Each arm needs at least 2 treated patients and 1 event", when, "; ",
         paste0(counts$Arm[thin], " has ", counts$Patients[thin], " patient(s) and ", counts$Events[thin], " event(s)",
                collapse = "; "), ".", call. = FALSE)
  }
  counts
}
.counts <- .arm_counts(d)
.counts <- base::rbind(.counts, data.frame(Arm = "No arm", Patients = sum(.no_arm), Events = NA_integer_))
knitr::kable(.counts)
```

| Data                |                                          |
|:--------------------|:-----------------------------------------|
| Source              | dataset `built` (built_20261029.parquet) |
| Rows read           | 800                                      |
| ID                  | `patient_id`                             |
| Identifiers dropped | none                                     |
| Rows kept           | 800 rows on 800 patients                 |

| Arm     | Patients | Events |
|:--------|---------:|-------:|
| repair  |      412 |     72 |
| replace |      388 |     57 |
| No arm  |        0 |     NA |

Table 1: The data this job read

## Predictors

Code

``` r
.vp_read <- NULL
if (!is.null(VP_SET)) {
  .vp_path <- file.path(dirname(dirname(set_path("estimates", "vt.rds"))), VP_SET, "vp.rds")
  if (!file.exists(.vp_path)) stop("No vp-fit screen at ", .vp_path, ". Render that job first.", call. = FALSE)
  .vp_read <- hvtiRtemplates:::.read_handoff(.vp_path, "screen", .cfg, "the vp-fit job")
  if (tolower(ARM) %in% tolower(.vp_read$value$coverage$variable)) {
    stop("The screen in ", VP_SET, " was given ", ARM, " as a candidate, so it is not treatment-blind. ",
         "Re-run vp-fit without the arm.", call. = FALSE)
  }
  .predictors <- .vp_read$value$selected
  .provenance_data <- c(.provenance_data, .vp_read$lineage$data)
} else {
  .predictors <- PREDICTORS
}
.predictors <- setdiff(.predictors, EXCLUDE)
.leaks <- intersect(tolower(.predictors), tolower(c(ARM, TIME, STATUS, ID)))
if (length(.leaks)) {
  stop("PREDICTORS (or the screen) includes the arm, outcome or ID: ", paste(.leaks, collapse = ", "), ".",
       call. = FALSE)
}
.missing <- setdiff(.predictors, names(d))
if (length(.missing)) stop("Not in the data this job read: ", paste(.missing, collapse = ", "), call. = FALSE)
if (!length(.predictors)) stop("No predictors are left after EXCLUDE.", call. = FALSE)
.chr <- .predictors[vapply(d[.predictors], is.character, logical(1L))]
d[.chr] <- lapply(d[.chr], factor)
if (NA_ACTION == "na.omit") {
  .kept <- stats::complete.cases(d[.predictors])
  cat(sum(!.kept), "patient(s) missing a predictor were dropped (NA_ACTION = \"na.omit\").\n")
  d <- d[.kept, , drop = FALSE]
  invisible(.arm_counts(d, " after NA_ACTION = \"na.omit\" dropped patients"))
  .no_arm <- .no_arm[.kept]
  .treated <- .treated[.kept]
}
d <- d[, c(ID, ARM, TIME, STATUS, .predictors), drop = FALSE]
cat("Predictors:", paste(.predictors, collapse = ", "), "\n")
```

    Predictors: age, female, bmi, hx_chf, hx_dm, nyha_pr, lvef, creat_pr, lvedd, lvesd, la_diam, rvsp, e_e 

## The observed outcome

What happened in each arm, before any model: Kaplan-Meier, with 70%
confidence limits (about one standard error). The twins below predict
each patient under both arms, so this is the check that each arm’s
follow-up reaches the horizon with patients still at risk. An arm with
few at risk at `HORIZON` carries a twin curve there that rests on little
data.

Code

``` r
.km_data <- d[.treated, c(TIME, STATUS, ARM), drop = FALSE]
.km_data[[ARM]] <- factor(.km_data[[ARM]], levels = ARMS)
.km_data[[STATUS]] <- as.integer(.km_data[[STATUS]])
.km_times <- sort(unique(c(pretty(c(0, max(.km_data[[TIME]]))), HORIZON)))
.km <- hvtiPlotR::hv_survival(.km_data, time_col = TIME, event_col = STATUS, group_col = ARM, conf_level = 0.70,
                              report_times = .km_times)
.km_at <- .km$tables$report[.km$tables$report$report_time == HORIZON, , drop = FALSE]
# The number at risk comes from the risk table the figure draws, so table and figure agree; the report
# table's own n.risk is survfit's, counted just before the time, and can differ by a patient.
.km_risk <- .km$tables$risk[.km$tables$risk$report_time == HORIZON, , drop = FALSE]
.km_tbl <- do.call(base::rbind, lapply(ARMS, function(a) {
  x <- .km_data[.km_data[[ARM]] == a, , drop = FALSE]
  h <- .km_at[as.character(.km_at$strata) == a, , drop = FALSE]
  k <- .km_risk$n.risk[as.character(.km_risk$strata) == a]
  data.frame(arm = a, patients = nrow(x), events = sum(x[[STATUS]] == 1L), last_follow_up = max(x[[TIME]]),
             at_risk = if (length(k)) k else 0L, survival = if (nrow(h)) h$surv else NA_real_,
             lower = if (nrow(h)) h$lower else NA_real_, upper = if (nrow(h)) h$upper else NA_real_)
}))
names(.km_tbl)[5:8] <- paste0(c("at_risk", "survival", "lower", "upper"), "_", HORIZON)
knitr::kable(.km_tbl, digits = 3, row.names = FALSE)
```

| arm     | patients | events | last_follow_up | at_risk_8 | survival_8 | lower_8 | upper_8 |
|:--------|---------:|-------:|---------------:|----------:|-----------:|--------:|--------:|
| repair  |      412 |     72 |         34.426 |       168 |      0.818 |   0.793 |   0.840 |
| replace |      388 |     57 |         30.877 |       147 |      0.855 |   0.829 |   0.877 |

Table 2: Each arm’s observed outcome: patients, events, and Kaplan-Meier
survival at the horizon with 70% confidence limits

Code

``` r
.fig <- plot(.km) +
  ggplot2::geom_vline(xintercept = HORIZON, linetype = "dashed") +
  ggplot2::labs(x = "Time", y = "Survival (%)", color = "Arm", fill = "Arm") +
  hvtiPlotR::theme_hv_manuscript(base_size = 12) +
  # The house theme drops the legend; two arms need it to tell the curves apart.
  ggplot2::theme(legend.position = "top")
.fig <- hvtiPlotR::hv_atrisk_compose(.fig, hvtiPlotR::hv_atrisk(.km))
save_figure(.fig, "vt-fit-km", height = 5)
.fig
```

![](assets/214504ee434ed5ad81cb324958738553.png)

Figure 1: Kaplan-Meier survival in each arm, with 70% confidence limits
and the numbers at risk. The dashed line is the RMST horizon.

## Eligibility

A patient’s twin curve for the arm they did not receive is only as good
as the patients it was learned from. **Out of distribution** means a
patient has no close counterpart in an arm, so that arm’s forest would
be extrapolating for them. The rule is the same for every distance this
job can use. For each arm, each patient’s nearest neighbor in that arm
(never themself) is compared with the largest nearest-neighbor distance
among the arm’s own patients. That reference is the arm’s own largest
gap: a patient farther from the arm than its own members are from each
other is outside what the arm covers. A treated patient is judged
against the other arm; a patient with no arm is judged against both and
must pass both.

Patients are **flagged, not dropped**. The flags are saved with the fit
and the effect estimates carry them, so a report can show the effect
with and without the flagged patients.

Code

``` r
# One rule, applied to any patient-by-patient distance. For each arm, each
# patient's nearest neighbor in that arm (never themself) is compared with the
# largest nearest-neighbor distance among the arm's own patients. Farther than
# that, STRICTLY, and the arm's forest would be extrapolating. A treated patient
# is judged against the other arm; a row with no arm against both.
#
# A distance can be unavailable: Gower gives NA for two patients who share no
# observed predictor. An unavailable distance is no evidence of nearness, so it
# counts as infinitely far. A patient with no finite distance to any patient in
# an arm has no comparable neighbor there and is out of distribution for it,
# with that reason; an arm member with no finite within-arm neighbor does not
# set the arm's reference. Every judged patient therefore gets TRUE or FALSE,
# never NA.
vt_ood <- function(dist, ids, arm, arms) {
  dist <- as.matrix(dist)[ids, ids, drop = FALSE]
  dist[is.na(dist)] <- Inf
  diag(dist) <- Inf
  rows <- lapply(arms, function(a) {
    members <- which(arm %in% a)
    nn_within <- apply(dist[members, members, drop = FALSE], 1L, min)
    nn_within <- nn_within[is.finite(nn_within)]
    # An arm whose members have no finite neighbor has no reference gap, so nobody can be shown
    # to sit inside it: they are flagged with that reason, and the eligibility chunk stops on it.
    reference <- if (length(nn_within)) max(nn_within) else NA_real_
    judged <- which(is.na(arm) | !arm %in% c(a, NA))
    if (!length(judged)) return(NULL)
    sub <- dist[judged, members, drop = FALSE]
    nn <- apply(sub, 1L, which.min)
    distance <- sub[cbind(seq_along(judged), nn)]
    none <- !is.finite(distance)
    out <- none | is.na(reference) | distance > reference
    reason <- ifelse(none, sprintf("no comparable %s patient (no predictor observed in common)", a), "")
    if (is.na(reference)) {
      reason[!none] <- sprintf("arm %s has no reference gap", a)
    } else {
      reason[out & !none] <- sprintf("nearest %s patient at %.3f, beyond that arm's largest gap %.3f",
                                     a, distance[out & !none], reference)
    }
    data.frame(ID = ids[judged], method = NA_character_, arm = a, nn_id = ifelse(none, NA, ids[members][nn]),
               distance = distance, reference = reference,
               ratio = if (length(nn_within)) distance / stats::median(nn_within) else NA_real_,
               in_distribution = !out, reason = reason)
  })
  do.call(base::rbind, rows)
}

# Gower over the model predictors only: mixed types, no model, bounded in [0, 1].
# A 0/1 column is declared symmetric binary. daisy() would otherwise treat it as
# interval scaled, which gives the same distance, and warn in every report.
# daisy() scores any mismatch of an unordered factor as 1, so a grade of 0
# against 3 would count the same as 0 against 1. The `ordinal` predictors become
# ordered factors, levels sorted by their numeric codes, which daisy ranks and
# scales to [0, 1]. Only the distance sees this; the forests keep the data as read.
vt_elig_gower <- function(d, predictors, id, ordinal = character()) {
  x <- d[predictors]
  for (v in intersect(ordinal, predictors)) {
    lv <- levels(factor(x[[v]]))
    num <- suppressWarnings(as.numeric(lv))
    if (anyNA(num)) {
      stop("ORDINAL predictor ", v, " has levels that are not numeric codes: ", paste(lv[is.na(num)], collapse = ", "),
           ".", call. = FALSE)
    }
    x[[v]] <- factor(as.character(x[[v]]), levels = lv[order(num)], ordered = TRUE)
  }
  binary <- predictors[vapply(x, function(col) {
    col <- stats::na.omit(col)
    is.numeric(col) && length(unique(col)) == 2L && all(col %in% c(0, 1))
  }, logical(1L))]
  m <- as.matrix(cluster::daisy(x, metric = "gower", type = if (length(binary)) list(symm = binary) else list()))
  dimnames(m) <- list(d[[id]], d[[id]])
  m
}

# Which predictors put an out-of-distribution patient outside the arm they were
# judged against: a number outside the range the arm's patients span, or a level
# that at most `rare` of them share. A distance says how far; this says why, in
# terms a clinician can check against the chart. At most `n` are named; a patient
# with none is unusual only in combination.
vt_ood_features <- function(out_rows, d, id, arm_of, predictors, n = 3L, rare = 2L) {
  vapply(seq_len(nrow(out_rows)), function(i) {
    p <- d[match(out_rows$ID[i], d[[id]]), , drop = FALSE]
    members <- d[arm_of %in% out_rows$arm[i], , drop = FALSE]
    why <- character()
    for (v in predictors) {
      a <- p[[v]]
      u <- members[[v]]
      if (is.na(a)) next
      if (is.numeric(u) && !all(stats::na.omit(u) %in% c(0, 1))) {
        rg <- range(u, na.rm = TRUE)
        if (a < rg[1] || a > rg[2]) {
          why <- c(why, sprintf("%s %s outside %s's range [%s, %s]", v, format(signif(a, 3)), out_rows$arm[i],
                                format(signif(rg[1], 3)), format(signif(rg[2], 3))))
        }
      } else {
        k <- sum(as.character(u) == as.character(a), na.rm = TRUE)
        if (k <= rare) why <- c(why, sprintf("%s = %s (%d of %d in %s)", v, as.character(a), k, nrow(members), out_rows$arm[i]))
      }
    }
    if (!length(why)) "none alone; unusual in combination" else paste(utils::head(why, n), collapse = "; ")
  }, character(1L))
}

# The SID distance a sid job saved. Read, never refit, and refused when it does
# not cover every patient here.
# Returns the distance with the whole reader result as attribute "read", so the
# eligibility chunk can carry the sid set's record and lineage into vt.rds.
vt_elig_sid <- function(path, ids, cfg, key = NULL,
                        read = function(p) hvtiRtemplates:::.read_handoff(p, "SID fit", cfg, "the sid job")) {
  if (!file.exists(path)) stop("No sid clustering at ", path, ". Render that job first.", call. = FALSE)
  got <- read(path)
  # A sid set's distance is labeled by ID digests under the study key, with the
  # key's fingerprint saved beside it. A different fingerprint means the key
  # changed since, and every digest would miss.
  if (!is.null(key) && !identical(got$value$id_key, hvtiRtemplates:::.id_key_fingerprint(key))) {
    stop("The sid set at ", path, " was digested under a different study key. Re-render it.", call. = FALSE)
  }
  m <- as.matrix(got$value$dist)
  absent <- setdiff(ids, rownames(m))
  if (length(absent)) {
    stop(length(absent), " patient(s) in this job are not in the sid distance at ", path, ".", call. = FALSE)
  }
  structure(m[ids, ids, drop = FALSE], read = got)
}

# A patient is eligible when every arm they were judged against passed, per
# method; then methods combine: "any" flag excludes, or "all" must.
vt_combine <- function(rows, combine = c("any", "all")) {
  combine <- match.arg(combine)
  per <- stats::aggregate(in_distribution ~ ID + method, rows, all)
  flagged <- stats::aggregate(!in_distribution ~ ID, per, if (combine == "any") any else all)
  data.frame(ID = flagged$ID, elig = !flagged[[2]])
}
```

Code

``` r
.methods <- match.arg(ELIGIBILITY, c("gower", "sid"), several.ok = TRUE)
.ids <- d[[ID]]
.arm <- ifelse(.no_arm, NA_character_, as.character(d[[ARM]]))
.sid_read <- NULL
.dist <- list(
  gower = function() vt_elig_gower(d, .predictors, ID, ORDINAL),
  sid = function() {
    if (is.null(SID_SET)) stop("ELIGIBILITY includes \"sid\"; name the sid set in SID_SET.", call. = FALSE)
    m <- vt_elig_sid(file.path(dirname(dirname(set_path("estimates", "vt.rds"))), SID_SET, "sid.rds"), .ids, .cfg,
                     key = .id_key)
    # The sid set decided some flags, so its record and data lineage travel
    # into vt.rds with the vp screen's (see `save`).
    .sid_read <<- attr(m, "read")
    .provenance_data <<- c(.provenance_data, .sid_read$lineage$data)
    m
  }
)
.elig_rows <- do.call(base::rbind, lapply(.methods, function(m) transform(vt_ood(.dist[[m]](), .ids, .arm, ARMS), method = m)))
if (anyNA(.elig_rows$reference)) {
  .bad <- unique(.elig_rows$method[is.na(.elig_rows$reference)])
  stop("An arm has no two patients with a finite distance by ", paste(.bad, collapse = ", "),
       ", so its reference gap is undefined. Check the predictors' missingness.", call. = FALSE)
}
.elig_rows$features <- ""
.ood_at <- which(!.elig_rows$in_distribution)
.elig_rows$features[.ood_at] <- vt_ood_features(.elig_rows[.ood_at, ], d, ID, .arm, .predictors)
# With no finite distance there is no comparison to explain; vt_ood()'s reason says why.
.nofin <- .ood_at[!is.finite(.elig_rows$distance[.ood_at])]
.elig_rows$features[.nofin] <- .elig_rows$reason[.nofin]
.elig <- vt_combine(.elig_rows, COMBINE)
for (m in .methods) {
  .one <- vt_combine(.elig_rows[.elig_rows$method == m, ], "any")
  .elig[[paste0("elig_", m)]] <- .one$elig[match(.elig$ID, .one$ID)]
}
# Sensitivity only, never part of the combined rule: forest propensity common support.
# ps_forest() refuses missing predictors, while the arm forests impute them
# (NA_ACTION = "na.impute"). So the propensity model gets a forest-imputed copy
# of the treated patients' predictors, seeded, and the arm forests keep the
# data as read. The arm is left out of the imputation, so the treatment does not
# shape the predictors that then predict it. Under "na.omit" nothing is missing and the copy equals d.
.ps_data <- d[.treated, c(ID, ARM, .predictors), drop = FALSE]
if (anyNA(.ps_data[.predictors])) {
  .imp <- .ps_data[.predictors]
  # impute() drops a patient who is missing every predictor, so the imputed
  # rows are matched back by ID (its row names), never by position.
  rownames(.imp) <- .ps_data[[ID]]
  set.seed(SEED)
  .imputed <- randomForestSRC::impute(data = .imp, ntree = 100L, seed = -abs(SEED), verbose = FALSE)
  .back <- match(.ps_data[[ID]], rownames(.imputed))
  if (anyNA(.back)) {
    cat(sum(is.na(.back)), " treated patient(s) could not be scored for the propensity sensitivity ",
        "(no predictor observed); they are not eligible under it.\n", sep = "")
  }
  .ps_data <- .ps_data[!is.na(.back), , drop = FALSE]
  .ps_data[.predictors] <- .imputed[.back[!is.na(.back)], .predictors, drop = FALSE]
}
set.seed(SEED)
# The propensity forest keeps its formula too, and reformulate() would tie it to this
# environment (and the raw IDs in `job_data`); point it at the global environment.
.ps_model <- stats::reformulate(.predictors, ARM, env = globalenv())
.ps <- ps_forest(.ps_model, data = .ps_data, treatment_col = ARM, id_col = ID,
                 treated_level = ARMS[1], ntree = NTREE, seed = -abs(SEED))
# ps_support() adds weak_common (outside the range both arms occupy) to $data.
# Patients with no arm have no propensity score and are not judged by it.
.support <- ps_support(.ps)$data
.elig$elig_propensity <- .elig$ID %in% .support[[ID]][!.support$weak_common]
.elig$elig_none <- TRUE
```

### Who is out of distribution

Code

``` r
.out <- .elig_rows[!.elig_rows$in_distribution, c("ID", "method", "arm", "distance", "reference", "features")]
if (nrow(.out)) {
  .out$distance <- round(.out$distance, 3)
  .out$reference <- round(.out$reference, 3)
}
cat(nrow(.out), "patient-by-arm judgments are out of distribution; every one is listed.\n")
```

    0 patient-by-arm judgments are out of distribution; every one is listed.

Code

``` r
knitr::kable(.out, row.names = FALSE)
```

| ID  | method | arm | distance | reference | features |
|-----|--------|-----|----------|-----------|----------|

Table 3: Patients out of distribution, by method and the arm they were
judged against

Code

``` r
.plot <- .elig_rows[is.finite(.elig_rows$distance), ]
.plot <- do.call(base::rbind, lapply(split(.plot, list(.plot$method, .plot$arm), drop = TRUE), function(x) {
  x$rank <- rank(x$distance, ties.method = "first")
  x
}))
.ref <- unique(.plot[c("method", "arm", "reference")])
.fig <- ggplot2::ggplot(.plot, ggplot2::aes(x = rank, y = distance, color = in_distribution)) +
  ggplot2::geom_point() +
  ggplot2::geom_hline(data = .ref, ggplot2::aes(yintercept = reference), linetype = "dashed") +
  ggplot2::facet_grid(method ~ arm, scales = "free") +
  ggplot2::scale_color_manual(values = c(`TRUE` = "gray60", `FALSE` = "black")) +
  ggplot2::labs(x = "Patient rank", y = "Distance to nearest patient in the arm", color = "In distribution") +
  hvtiPlotR::theme_hv_manuscript(base_size = 12)
save_figure(.fig, "vt-fit-eligibility")
.fig
```

![](assets/9a17487454c0a39071f9fbcbcb738114.png)

Figure 2: Distance to the nearest patient of the arm judged against,
patients ranked within each panel. The dashed line is that arm’s largest
nearest-neighbor gap among its own patients: points above it are out of
distribution.

Code

``` r
if (length(.methods) > 1L) {
  .pairs <- utils::combn(.methods, 2L, simplify = FALSE)
  for (.p in .pairs) {
    cat("Eligible under", .p[1], "(rows) and", .p[2], "(columns):\n\n")
    cat(knitr::kable(table(.elig[[paste0("elig_", .p[1])]], .elig[[paste0("elig_", .p[2])]],
                           dnn = paste0("elig_", .p))),
        sep = "\n")
    cat("\n")
  }
} else {
  cat("One eligibility method ran, so there is nothing to compare.\n")
}
```

Eligible under gower (rows) and sid (columns):

|      | TRUE |
|:-----|-----:|
| TRUE |  800 |

Table 4: Eligibility under each pair of methods

## The arm forests

One survival forest per arm, grown on the patients who received that
arm. A patient’s own-arm curve comes from their forest out of bag, so no
one is predicted by trees grown on them.

Code

``` r
CACHE_DIR <- dirname(set_path("estimates", "vt.rds"))
.model <- stats::as.formula(paste0("Surv(", TIME, ", ", STATUS, ") ~ ", paste(.predictors, collapse = " + ")))
# The saved forest keeps this formula, and a formula keeps the environment it
# was made in, `job_data` and its patient IDs included. Point it at the global
# environment, which a saved file only refers to (rfs-fit does the same).
environment(.model) <- globalenv()
# The IDs of each forest's training rows, in training order. survival.oob rows
# follow this order, and vt_curves() matches on it rather than on d's order.
.train_ids <- stats::setNames(lapply(ARMS, function(a) d[[ID]][d[[ARM]] %in% a & .treated]), ARMS)
.forests <- stats::setNames(lapply(ARMS, function(a) {
  da <- d[d[[ARM]] %in% a & .treated, c(TIME, STATUS, .predictors), drop = FALSE]
  set.seed(SEED)
  cache_fit(paste0("vt-fit-", a),
            rfsrc(.model, data = da, ntree = NTREE, nsplit = NSPLIT, na.action = NA_ACTION,
                  importance = "none", block.size = 1, seed = -abs(SEED)),
            seed = SEED, dir = CACHE_DIR, refit = REFIT)
}), ARMS)
```

The C-index below is computed from each forest’s out-of-bag predictions,
not from the stored error rate (which the study’s 2026-09-23 correction
showed is not the C-index).

Code

``` r
.perf <- do.call(base::rbind, lapply(ARMS, function(a) {
  f <- .forests[[a]]
  # yvar is the response as a data frame (time, status) for a survival forest.
  yt <- f$yvar[[1]]
  ys <- f$yvar[[2]]
  cc <- survival::concordance(survival::Surv(yt, ys) ~ f$predicted.oob, reverse = TRUE)
  se <- sqrt(cc$var)
  data.frame(arm = a, patients = f$n, events = sum(ys == 1), c_index = cc$concordance,
             lower = cc$concordance - 1.96 * se, upper = cc$concordance + 1.96 * se)
}))
cat(knitr::kable(.perf, digits = 3), sep = "\n")
```

Code

``` r
.weak <- .perf$arm[which(.perf$lower <= 0.5)]
if (length(.weak)) {
  cat("\n**The interval for", paste(.weak, collapse = " and "), "includes 0.5.** That arm's half of every",
      "contrast below is exploratory.\n")
}
```

| arm     | patients | events | c_index | lower | upper |
|:--------|---------:|-------:|--------:|------:|------:|
| repair  |      412 |     72 |   0.741 | 0.684 | 0.798 |
| replace |      388 |     57 |   0.398 | 0.311 | 0.484 |

Table 5: **The interval for replace includes 0.5.** That arm’s half of
every contrast below is exploratory.

The C-index says whether a forest ranks patients; it says nothing about
whether the survival it predicts is the right level, and the RMST
difference is a difference of levels. Calibration checks that: each
arm’s patients are split into fifths by their out-of-bag predicted
survival at the horizon, and each fifth’s mean prediction is set beside
its Kaplan-Meier survival. A small arm can rank well and still be far
off here.

Code

``` r
# Out-of-bag predicted survival at the horizon against Kaplan-Meier within
# groups of predicted survival, for one survival forest. survival.oob and yvar
# share the training order, so no matching by ID is needed. A patient never out
# of bag has no prediction and is left out, counted. A group whose follow-up
# ends before the horizon has no observed survival there: extending its curve
# would treat the last censored patients as immortal. It is NA, counted, unless
# the curve had already reached zero.
vt_calibration <- function(f, horizon, groups = 5L) {
  at <- findInterval(horizon, f$time.interest)
  pred <- if (at == 0L) rep(1, f$n) else f$survival.oob[, at]
  time <- f$yvar[[1]]
  status <- f$yvar[[2]]
  ok <- !is.na(pred)
  pred <- pred[ok]
  time <- time[ok]
  status <- status[ok]
  breaks <- unique(stats::quantile(pred, seq(0, 1, length.out = groups + 1L), names = FALSE))
  g <- if (length(breaks) > 1L) cut(pred, breaks, include.lowest = TRUE, labels = FALSE) else rep(1L, length(pred))
  out <- do.call(base::rbind, lapply(sort(unique(g)), function(k) {
    s <- g == k
    km <- summary(survival::survfit(survival::Surv(time[s], status[s]) ~ 1), times = horizon, extend = TRUE)
    observed <- if (length(km$surv)) km$surv else NA_real_
    if (max(time[s]) < horizon && !isTRUE(observed == 0)) observed <- NA_real_
    data.frame(group = k, patients = sum(s), events = sum(status[s] == 1), predicted = mean(pred[s]),
               observed = observed)
  }))
  attr(out, "no_prediction") <- sum(!ok)
  attr(out, "unsupported") <- sum(is.na(out$observed))
  out
}
```

Code

``` r
.cal <- do.call(base::rbind, lapply(ARMS, function(a) {
  x <- vt_calibration(.forests[[a]], HORIZON)
  if (attr(x, "no_prediction")) {
    cat(attr(x, "no_prediction"), " ", a, " patient(s) were never out of bag and have no calibration prediction; ",
        "raise NTREE.\n\n", sep = "")
  }
  if (attr(x, "unsupported")) {
    cat(attr(x, "unsupported"), " ", a, " fifth(s) have no follow-up to ", HORIZON,
        " and no observed survival there; they are left out of the error.\n\n", sep = "")
  }
  cbind(arm = a, x)
}))
cat(knitr::kable(.cal, digits = 3, row.names = FALSE), sep = "\n")
```

Code

``` r
# One number per arm: the mean distance between predicted and observed over the fifths, in percentage points.
.cal_error <- tapply(abs(.cal$predicted - .cal$observed), .cal$arm, mean, na.rm = TRUE)[ARMS]
cat("\nMean calibration error at ", HORIZON, ", in percentage points: ",
    paste0(ARMS, " ", format(round(100 * .cal_error, 1), nsmall = 1), collapse = ", "), ".\n", sep = "")
```

| arm     | group | patients | events | predicted | observed |
|:--------|------:|---------:|-------:|----------:|---------:|
| repair  |     1 |       83 |     31 |     0.510 |    0.536 |
| repair  |     2 |       82 |     19 |     0.754 |    0.726 |
| repair  |     3 |       82 |      8 |     0.888 |    0.904 |
| repair  |     4 |       82 |     11 |     0.927 |    0.921 |
| repair  |     5 |       83 |      3 |     0.961 |    0.968 |
| replace |     1 |       78 |      7 |     0.767 |    0.915 |
| replace |     2 |       77 |     13 |     0.824 |    0.857 |
| replace |     3 |       78 |     10 |     0.851 |    0.918 |
| replace |     4 |       77 |     11 |     0.876 |    0.866 |
| replace |     5 |       78 |     16 |     0.910 |    0.722 |

Table 6: Mean calibration error at 8, in percentage points: repair 1.6,
replace 8.9.

Code

``` r
.lim <- range(c(.cal$predicted, .cal$observed), na.rm = TRUE)
.fig <- ggplot2::ggplot(.cal[!is.na(.cal$observed), , drop = FALSE], ggplot2::aes(x = predicted, y = observed)) +
  ggplot2::geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "gray40") +
  ggplot2::geom_line() +
  ggplot2::geom_point(size = 2) +
  ggplot2::facet_wrap(~ arm) +
  ggplot2::coord_equal(xlim = .lim, ylim = .lim) +
  ggplot2::labs(x = paste("Predicted survival at", HORIZON, "(out of bag)"), y = "Observed, Kaplan-Meier") +
  hvtiPlotR::theme_hv_manuscript(base_size = 12)
save_figure(.fig, "vt-fit-calibration")
.fig
```

![](assets/d6791edce3a2c8ec7730ff2a3d05cba7.png)

Figure 3: Calibration at the horizon. Each point is a fifth of an arm’s
patients; the dashed line is perfect agreement. Points below it: the
forest predicts better survival than was observed.

## Twin curves

Code

``` r
# Two curves per patient. The arm a patient received comes from that arm's
# forest OUT OF BAG, so no one is predicted by trees grown on them. The other
# arm comes from predict() on the other forest. Rows with no arm get both from
# predict(). Everything is keyed by ID: predict() returns rows in the order it
# was given them, and pairing by position silently swaps patients. Under
# na.impute predict() imputes the new rows at random, so it takes the seed too.
vt_curves <- function(forests, train_ids, d, id, arm, arms, no_arm, seed) {
  out <- list()
  for (a in arms) {
    f <- forests[[a]]
    own <- d[[arm]] %in% a & !no_arm
    own_ids <- d[[id]][own]
    # survival.oob rows are in TRAINING order, which train_ids records; d may
    # be in any order, so each own-arm patient is matched to their row by ID.
    at <- match(own_ids, train_ids[[a]])
    if (anyNA(at)) stop(sum(is.na(at)), " arm ", a, " patient(s) are not among its forest's training rows.", call. = FALSE)
    oob <- f$survival.oob[at, , drop = FALSE]
    out[[length(out) + 1L]] <- data.frame(ID = rep(own_ids, each = length(f$time.interest)), arm_of_curve = a,
                                          time = f$time.interest, surv = as.vector(t(oob)))
    other <- d[!own, , drop = FALSE]
    p <- predict(f, newdata = other[, f$xvar.names, drop = FALSE], na.action = "na.impute",
                 seed = seed)
    out[[length(out) + 1L]] <- data.frame(ID = rep(other[[id]], each = length(f$time.interest)), arm_of_curve = a,
                                          time = f$time.interest, surv = as.vector(t(p$survival)))
  }
  do.call(base::rbind, out)
}
```

Code

``` r
.own_n <- vapply(ARMS, function(a) .forests[[a]]$n, integer(1L))
stopifnot(all(.own_n == lengths(.train_ids[ARMS])))
set.seed(SEED)
.curves <- vt_curves(.forests, .train_ids, d, ID, ARM, ARMS, no_arm = .no_arm, seed = -abs(SEED))
```

## The difference in restricted mean survival time

Code

``` r
# RMST to the horizon: the area under a step survival curve, which starts at 1.
# The horizon must sit inside both arms' follow-up; past it every curve is cut
# at the same place and the difference is an artifact (a horizon in days on a
# fit in years gave identical curves once).
vt_rmst <- function(curves, horizon, arms, followup) {
  past <- names(followup)[followup < horizon]
  if (length(past)) {
    stop("HORIZON (", horizon, ") is beyond the largest follow-up time in arm(s) ", paste(past, collapse = ", "),
         " (", paste(signif(followup[past], 3), collapse = ", "), "). Check its units against TIME.", call. = FALSE)
  }
  # The risk is 1 - S(horizon), where S includes a step AT the horizon; the
  # area stops at the horizon, so a step there adds nothing to it.
  one <- function(t, s) {
    keep <- t < horizon
    knots <- c(0, t[keep], horizon)
    steps <- c(1, s[keep])
    at <- c(1, s[t <= horizon])
    c(rmst = sum(diff(knots) * steps), risk = 1 - utils::tail(at, 1L))
  }
  per <- lapply(split(curves, list(curves$ID, curves$arm_of_curve), drop = TRUE), function(x) {
    x <- x[order(x$time), ]
    v <- one(x$time, x$surv)
    data.frame(ID = x$ID[1L], arm_of_curve = x$arm_of_curve[1L], rmst = v[["rmst"]], risk = v[["risk"]])
  })
  long <- do.call(base::rbind, per)
  wide <- stats::reshape(long, idvar = "ID", timevar = "arm_of_curve", direction = "wide", sep = "_")
  wide$diff <- wide[[paste0("rmst_", arms[1])]] - wide[[paste0("rmst_", arms[2])]]
  # log_rr is +/-Inf or NaN when a patient's risk is 0 under an arm (vt-explain drops and counts those).
  wide$log_rr <- log(wide[[paste0("risk_", arms[1])]] / wide[[paste0("risk_", arms[2])]])
  rownames(wide) <- NULL
  wide
}
```

Code

``` r
.followup <- vapply(ARMS, function(a) max(d[[TIME]][d[[ARM]] %in% a & .treated]), numeric(1L))
.rmst <- vt_rmst(.curves, HORIZON, ARMS, .followup)
# no_arm marks the patients who received neither arm. Their arm is NA, never a label, so
# an arm that is really named "none" cannot be confused with them.
.rmst <- merge(data.frame(ID = d[[ID]], arm = ifelse(.no_arm, NA_character_, d[[ARM]]), no_arm = .no_arm),
               .rmst, by = "ID")
.rmst <- merge(.rmst, .elig, by = "ID")
```

Code

``` r
.in_dist <- .rmst$ID[.rmst$elig]
if (!length(.in_dist)) {
  cat("No patient is in distribution under the combined rule; see the eligibility tables.\n")
} else {
  .mc <- .curves[.curves$ID %in% .in_dist, ]
  .at <- match(.mc$ID, .rmst$ID)
  .mc$received <- ifelse(.rmst$no_arm[.at], "No arm", .rmst$arm[.at])
  .mc <- stats::aggregate(surv ~ received + arm_of_curve + time, data = .mc, FUN = mean)
  # hv_rmst_curves() wants right-continuous steps that start at time 0 with surv 1.
  .mc <- do.call(base::rbind, lapply(split(.mc, list(.mc$received, .mc$arm_of_curve), drop = TRUE), function(x) {
    base::rbind(data.frame(received = x$received[1L], arm_of_curve = x$arm_of_curve[1L], time = 0, surv = 1), x[order(x$time), ])
  }))
  .mc$facet <- paste("Received", .mc$received)
  .mc$arm <- .mc$arm_of_curve
  .fig <- plot(hvtiPlotR::hv_rmst_curves(.mc, tau = HORIZON, facet = "facet", arm = "arm")) +
    ggplot2::labs(x = "Time", y = "Mean predicted survival", color = "Curve under", fill = "Curve under")
  save_figure(.fig, "vt-fit-curves")
  .fig
}
```

![](assets/16b85c593c7a7ff8a4735151d6051354.png)

Figure 4: Mean predicted survival under each arm’s forest, for patients
in distribution, by the arm they received. The shaded area to the
horizon is the restricted mean survival time.

## Handoff

Code

``` r
# The product of this job, and what vt-explain reads, in one file so its parts
# cannot drift apart. The forests are kept so vt-explain grows none.
vt_handoff <- hvtiRtemplates:::.attach_handoff_lineage(
  list(rmst = .rmst, curves = .curves, forests = .forests,
       eligibility = list(rows = .elig_rows, methods = .methods, combine = COMBINE, sid_set = SID_SET, ordinal = ORDINAL,
                          ps = .ps),
       predictors = list(names = .predictors, vp_set = VP_SET),
       settings = list(performance = .perf, calibration = .cal, arms = ARMS, horizon = HORIZON, ntree = NTREE, seed = SEED,
                       time = TIME, status = STATUS,
                       id = ID, id_key = hvtiRtemplates:::.id_key_fingerprint(.id_key),
                       arm = ARM, imputation = IMPUTATION, imputation_use = IMPUTATION_USE,
                       imputation_m = if (!is.null(IMPUTATION)) .m,
                       # Everything read_job_data() was given, so vt-explain reads the same patients and values.
                       read = list(dataset = DATASET, analysis_set = ANALYSIS_SET, where = WHERE, key = KEY,
                                   join = JOIN, join_vars = JOIN_VARS, reduce = REDUCE, join_key = JOIN_KEY))),
  # .provenance_data already holds the vp and sid sets' data lineage (appended
  # where each was read); their handoff records go in as artifacts.
  data = .provenance_data,
  artifacts = c(list(), if (!is.null(.vp_read)) c(.vp_read$lineage$artifacts, list(.vp_read$record)),
                if (!is.null(.sid_read)) c(.sid_read$lineage$artifacts, list(.sid_read$record))),
  analysis = list(time = list(variable = TIME), event = list(variable = STATUS, event = 1L, censored = 0L)),
  selection = attr(job_data$record, "selection")
)
saveRDS(vt_handoff, set_path("estimates", "vt.rds"))
```

## About this run

| Group           | Item             | Value                    |
|:----------------|:-----------------|:-------------------------|
| Run             | Started          | 2026-10-29 10:42:35 EDT  |
|                 | Ended            | 2026-10-29 10:42:47 EDT  |
|                 | Duration         | 12 s                     |
|                 | Status           | final                    |
|                 | Rendered by      | gallery                  |
|                 | Host             | gallery                  |
| Job             | File             | vt.fit.reint.vt.qmd      |
|                 | Template         | vt.fit                   |
|                 | Subject          | reint                    |
|                 | Type             | vt                       |
|                 | hvtiRtemplates   | 1.5.4                    |
| Dataset `built` | Version file     | built_20261029.parquet   |
|                 | Version date     | 2026-10-29               |
|                 | Source file      | built.rds                |
|                 | Rows kept        | 800 rows on 800 patients |
|                 | WHERE            | none                     |
|                 | sha256           | b236a472f1f3             |
|                 | Manifest         | current                  |
| Reproducibility | Seed             | 1024                     |
|                 | renv             | not active               |
|                 | renv.lock sha256 | d09f96b6cd21             |
