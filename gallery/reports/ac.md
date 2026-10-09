# Actuarial life table

# Actuarial life table

Replaces `distributions/<job>.sas`: describe its `%KAPLAN` calls here —
overall, and each stratification.

An `ac` job produces life tables. Figures over the same estimates are an
`hp` job, and the parametric fit is `hz`; neither belongs here.

Code

``` r
# The study root is the nearest directory above this file holding _study.yml,
# so the job renders the same from the Render button, quarto render, or
# render_job(), at any depth, with no path in this document to edit.
.in <- knitr::current_input(dir = TRUE)
.root <- hvtiRtemplates:::.find_study_root(if (is.null(.in)) getwd() else dirname(.in))
.provenance_data <- list()
for (f in list.files(file.path(.root, "R"), pattern = "[.]R$", full.names = TRUE)) source(f)
suppressPackageStartupMessages({
  library(TemporalHazard)
  library(hvtiRutilities)
})
```

Code

``` r
# The markers in this file name work a study author still has to do, and
# README.md says a job that still contains one has not been finished. This
# chunk is what makes that TRUE rather than merely stated.
#
# Without it an unedited job renders green over a meaningless analysis. The
# edit-derive chunk below indexes a placeholder column; when that column is absent
# `!is.na(d$<col>)` is logical(0), and assignment through a zero-length index
# is a SILENT no-op in R. Every patient keeps the initial category, every
# stratified estimate is computed over one dummy stratum, and nothing errors.
#
# knitr::current_input() is NULL outside a render -- a study author stepping
# through chunks in RStudio -- and there is no file to scan then, so this is a
# no-op in that case. Same handling as the `set` guard below, for the same
# reason.
#
# The token is BUILT, not written literally, and that is not stylistic. Quarto
# knits through an intermediate and current_input() returns THAT file, so the
# scan reads a copy of this chunk along with everything else: a literal
# grep("<token>", .src) here matches its own source line, and the guard then
# fires on every render, finished or not. Measured, not theorised -- a probe
# found three markers in a file containing two. A guard that cries wolf on a
# finished job is a guard that gets deleted, which returns us to issue #27.
.tok <- paste0("ED", "IT", ":")
.cur <- knitr::current_input()
if (!is.null(.cur)) {
  .src  <- readLines(.cur, warn = FALSE)
  .hits <- grep(.tok, .src, fixed = TRUE)
  if (length(.hits)) {
    # Report the marker TEXT. Line numbers here are the intermediate's, not
    # this .qmd's, so they need not match what the author sees in an editor.
    .msg <- paste0(
      length(.hits), " unresolved ", .tok, " marker(s) remain in this job:\n",
      paste0("  - ", trimws(substr(.src[.hits], 1L, 96L)), collapse = "\n"),
      "\nA job that still contains one has not been finished. Work each ",
      "marker and delete it."
    )
    # A job renders as a draft by default, so an author can iterate on a
    # working report and remove markers as they go. HVTI_TEMPLATE_STRICT
    # turns the draft into a stop for a final render. Only unset, 0, false
    # and no mean "not strict": an unrecognized value stops on purpose, so a
    # mistyped switch is seen rather than quietly ignored, which is the safe
    # direction to be wrong in.
    if (tolower(Sys.getenv("HVTI_TEMPLATE_STRICT")) %in% c("", "0", "false", "no")) {
      # The banner is not optional. A draft render that looks like a finished
      # one is the same defect with an extra step: the warning scrolls past in
      # a log, while the .html is the artifact that gets sent to someone.
      warning(.msg, "\nRendering as a draft; the banner goes when the last marker does. ",
              "Set HVTI_TEMPLATE_STRICT to 1, true or yes to make this stop.", call. = FALSE)
      cat("\n::: {.callout-important title=\"DRAFT -- this job is unfinished\"}\n")
      cat("Unresolved markers remain. **The numbers below are not",
          "a result.**\n\n```\n", .msg, "\n```\n", sep = "")
      cat(":::\n\n")
    } else {
      stop(.msg, "\nThis render stops because HVTI_TEMPLATE_STRICT is '",
           Sys.getenv("HVTI_TEMPLATE_STRICT"), "'. Unset it, or set it to 0, false ",
           "or no, to render a draft instead.", call. = FALSE)
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
SUBJECT <- "dead"
TYPE    <- "hz"

# `add_job()` writes SUBJECT/TYPE from the same values it put in this file's
# name, but a hand-edited declaration can drift from it afterward. set_path()
# below resolves from the declarations, not the filename, so a drifted
# declaration would silently write into ANOTHER set's artifact directory --
# exactly the collision the (subject, type) key exists to prevent, re-entered
# through the body instead of the name.
#
# knitr::current_input() is NULL outside a render (a study author running
# chunks interactively in RStudio), and there is no filename to check against
# yet, so this is a no-op in that case rather than a spurious error.
.current <- knitr::current_input()
if (!is.null(.current)) {
  # The name is template first, <prefix>[.<qualifier>].<subject>.<type>, or
  # <subject>-<type>-<prefix>[-<qualifier>] for a job scaffolded before
  # 2026-10. .job_name_fields() reads subject and type from either, whatever
  # the extension: Quarto knits through an intermediate, so
  # `knitr::current_input()` names the `.rmarkdown` file here, not the `.qmd`.
  .fields <- hvtiRtemplates:::.job_name_fields(.current)
  .name_subject <- if (length(.fields) >= 1L) .fields[[1L]] else NA_character_
  .name_type     <- if (length(.fields) >= 2L) .fields[[2L]] else NA_character_
  if (!identical(.name_subject, SUBJECT) || !identical(.name_type, TYPE)) {
    stop("This file is named '", .current, "' (subject '", .name_subject, "', type '",
         .name_type, "'), but declares SUBJECT = \"", SUBJECT, "\", TYPE = \"", TYPE,
         "\". Fix the declaration or the filename before rendering.", call. = FALSE)
  }
}

# Resolve a path inside this set's artifact directory. `kind` is the artifact
# folder -- "estimates" for serialized results, "graphs" for figures. The set
# directory sits one layer under the kind and never two, which is the whole
# layout rule.
#
# Created on first use rather than up front, so a job that writes nothing leaves
# no empty directories behind.
set_path <- function(kind, file) {
  d <- file.path(hvtiRutilities::study_dir(kind, .root),
                 paste0(SUBJECT, "-", TYPE))
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  file.path(d, file)
}

# The overall life table is saved after it is fitted. `hp` reads that exact
# handoff by set and refuses an older lineage-free artifact.
```

## Study choices

Edit these values for this study before rendering.

Code

``` r
# Demo: the registered dataset this job reads ("built" is the study dataset).
DATASET <- "built"

# Demo: an hvtiRdatabuild analysis set, or NULL to read the whole dataset.
ANALYSIS_SET <- NULL

# Demo: rows to keep, dplyr::filter() style, or NULL to keep every row:
#   WHERE <- quote(age >= 18)
#   WHERE <- rlang::exprs(age >= 18, hx_chf == 1)
WHERE <- quote(!is.na(creat_pr))

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

# Demo: each derived category and its source variable.
DERIVED <- c(lvef_grp = "lvef")

# Demo: stratification variables.
STRATA <- c("lvef_grp", "hx_chf")

# Demo: time and event variables.
TIME   <- "iv_dead"

EVENT  <- "dead"

# Demo: counts from the SAS reference for the rows this job analyses. Leave
# these invalid defaults in place until WHERE and the endpoint agree.
EXPECTED <- list(n = 725L, n_events = 402L, n_censored = 323L)

# Demo: reporting horizons and their labels.
grid <- c(30 / 365.2425, 0.5, 1, 5, 10)

labs <- c("30 days", "6 months", "1 year", "5 years", "10 years")
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
| Source              | dataset `built` (built_20261009.parquet) |
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

Code

``` r
cc <- cohort_counts(d, event = EVENT, time = TIME)
assert_cohort(d, expected = EXPECTED, event = EVENT, time = TIME)

# A time of zero, a death on the day of operation, leaves the hazard likelihood
# undefined, and hz would stop on an optimizer error that names neither the
# time nor the patient. ac checks too, so the first job in the chain says so.
# The fix belongs in the dataset build, not here: a job reshapes data and never
# corrects it, and every job reading the cohort must see the same follow-up.
# Only rows the cohort counts are checked: a row with no EVENT is not analyzed.
.t <- as.numeric(d[[TIME]])[!is.na(d[[EVENT]])]
.n_zero <- sum(.t == 0, na.rm = TRUE)
.n_neg  <- sum(.t < 0, na.rm = TRUE)
if (.n_zero + .n_neg > 0) {
  stop(TIME, " has ", .n_zero, " time(s) of exactly zero and ", .n_neg, " negative time(s). ",
       "Correct them in the dataset build, not in this job. Move only the zeros to a small positive ",
       "value, such as 0.00025 years as the template gallery does; moving every time up to one day ",
       "ties the early deaths together. A negative time is an error in the data: trace it to its source.",
       call. = FALSE)
}

knitr::kable(data.frame(
  quantity = c("n_analysable", "n_events", "n_censored"),
  n        = c(cc$n, cc$n_events, cc$n_censored)
))
```

| quantity     |   n |
|:-------------|----:|
| n_analysable | 725 |
| n_events     | 402 |
| n_censored   | 323 |

Table 2: Analysable patients, events and censored patients

A rendered report is itself evidence the gate passed. Report the counts
anyway — a gate that passes silently tells the reader nothing about what
it passed on.

**An event flag that is 0/1 in SAS may arrive as `logical`**, because
`read_clinical_data()` infers binary columns as logical and
`hzr_kaplan()` requires a numeric status. The `as.numeric()` coercions
below are not decoration.

## Derived strata

Code

``` r
# Demo: your study's category derivations, in SAS order.
derive_cats <- function(d) {
  # Assert the source columns are present BEFORE deriving. Every condition
  # below is guarded by !is.na(d$src), and when `src` is absent that guard is
  # logical(0), so each assignment is a silent no-op: every patient keeps the
  # initial value, the counts still sum to the cohort, and the render is green
  # over a single dummy stratum. An absent column must fail here, loudly.
  .need <- "lvef"
  .miss <- setdiff(.need, names(d))
  if (length(.miss)) {
    stop("derive_cats(): source column(s) not in the data: ",
         paste(.miss, collapse = ", "),
         ". Edit this chunk for your study before rendering.", call. = FALSE)
  }

  d$lvef_grp <- 3L
  d$lvef_grp[!is.na(d$lvef) & d$lvef < 50] <- 2L
  d$lvef_grp[!is.na(d$lvef) & d$lvef < 40] <- 1L

  d
}
d <- derive_cats(d)
```

Code

``` r
knitr::kable(as.data.frame(table(lvef_grp = d$lvef_grp), stringsAsFactors = FALSE))
```

| lvef_grp | Freq |
|:---------|-----:|
| 1        |   79 |
| 2        |  215 |
| 3        |  431 |

Table 3: Patients in each derived category

Code

``` r
# A cumulative-overwrite derivation fails QUIETLY: reorder the conditions and
# every patient still lands in some category, the counts still sum to the
# cohort, and every stratified estimate below is wrong while looking entirely
# plausible. So the derivation is checked against the data it came from rather
# than against an external listing.
#
# Two things are visible here and nowhere else:
#   * the source RANGE within each category. Correctly ordered, the ranges are
#     disjoint and ascend with the category. Overlapping or inverted ranges mean
#     the overwrites ran in the wrong order.
#   * src_missing. Every condition is guarded by !is.na(), so a patient whose
#     source variable is missing keeps the INITIAL value and silently joins the
#     top category. That is a missingness stratum wearing a clinical label.

# Each derived category names the variable it was derived FROM.

# DERIVED is maintained by hand and can drift from derive_cats() above -- a
# category renamed there, or a source renamed here. Either way d[[src]] is NULL,
# every row below comes back empty, and a zero-row table renders quietly beside
# a derive table showing every patient in one category. The assertion covers
# both ends: sources must exist in the data, and each derived category must
# actually have been produced above.
.miss_src <- setdiff(unname(DERIVED), names(d))
.miss_cat <- setdiff(names(DERIVED),  names(d))
if (length(.miss_src) || length(.miss_cat)) {
  stop("DERIVED does not describe this data. ",
       if (length(.miss_src))
         paste0("Source column(s) absent: ", paste(.miss_src, collapse = ", "), ". "),
       if (length(.miss_cat))
         paste0("Derived column(s) absent -- not produced by derive_cats(): ",
                paste(.miss_cat, collapse = ", "), ". "),
       call. = FALSE)
}

rng <- function(x) {
  x <- x[!is.na(x)]
  if (!length(x)) c(NA_real_, NA_real_) else range(x)
}

derived_rows <- function(cat) {
  src <- DERIVED[[cat]]
  do.call(rbind, lapply(sort(unique(d[[cat]])), function(k) {
    v <- d[[src]][d[[cat]] == k]
    r <- rng(v)
    data.frame(
      category = cat, level = k, n = length(v), source = src,
      src_min = r[1], src_max = r[2], src_missing = sum(is.na(v))
    )
  }))
}

knitr::kable(
  do.call(rbind, lapply(names(DERIVED), derived_rows)),
  row.names = FALSE, digits = 4
)
```

| category | level |   n | source | src_min | src_max | src_missing |
|:---------|------:|----:|:-------|--------:|--------:|------------:|
| lvef_grp |     1 |  79 | lvef   |      20 |      39 |           0 |
| lvef_grp |     2 | 215 | lvef   |      40 |      49 |           0 |
| lvef_grp |     3 | 431 | lvef   |      50 |      75 |           0 |

Table 4: Each derived category against the variable it came from

**Read the ranges before reading anything below.** They must not overlap
between levels of the same category, and they must ascend with the
level. If a derivation is wrong, every stratified estimate downstream is
wrong in a way that still looks entirely plausible, and this table is
where that shows.

Any `src_missing` above zero is worth naming in the report: those
patients are in that stratum because their source value is unknown, not
because they belong to it clinically.

## Estimation

`hzr_kaplan()` takes vectors, not a formula with a strata term, so a
stratified fit is a split and a call per stratum.

The confidence level is SAS’s `%KAPLAN` `CLEVEL` default of `0.68268948`
— one standard deviation, **not** 95%. This is a SAS convention rather
than a study choice, so it is not marked as an edit; change it only if
your job overrides `CLEVEL`, and say so in the report if you do.

Code

``` r
# unnumbered: defines helpers only
CLEVEL <- 0.68268948

.fence <- strrep("`", 3)
.seen <- new.env()
.child <- function(label, caption, code) {
  label <- gsub("(^-+|-+$)", "", gsub("[^a-z0-9]+", "-", tolower(label)))
  if (!is.null(.seen[[label]])) stop("Two outputs would share the label ", label, ".", call. = FALSE)
  .seen[[label]] <- TRUE
  .opt <- paste0("#| ", sub("-.*$", "", label), "-cap: ", encodeString(caption, quote = "\""))
  cat(knitr::knit_child(text = c(paste0(.fence, "{r}"), paste0("#| label: ", label), .opt, code, .fence),
                        envir = parent.frame(), quiet = TRUE), sep = "\n")
  cat("\n")
}

# your time and status variables.

km_fit <- function(dd) {
  ok <- !is.na(dd[[TIME]]) & !is.na(dd[[EVENT]])
  out <- hzr_kaplan(time       = as.numeric(dd[[TIME]][ok]),
                    status     = as.numeric(dd[[EVENT]][ok]),
                    conf_level = CLEVEL)
  # End of follow-up, carried from the DATA. It cannot be recovered from the
  # life table: that has one row per EVENT time, so patients censored after the
  # last death extend follow-up without adding a row. max(out$time) is the last
  # event, which can be years short of the last observation.
  out$max_fup <- max(as.numeric(dd[[TIME]][ok]))
  out
}

# Bookkeeping columns km_fit()/km_by() attach for the code's benefit. They are
# constant down every row and must not appear in a table someone reads. Kept as
# columns rather than attributes because split()/rbind() drop attributes, and
# losing max_fup silently would restore the extrapolation bug it exists to stop.
INTERNAL_COLS <- c("max_fup", "n")
readable <- function(x) x[, setdiff(names(x), INTERNAL_COLS), drop = FALSE]

# Levels of a stratification variable that are not clean integers. A missing
# binary that was MEAN-IMPUTED upstream is stored as a third factor level: a
# value such as 0.714047380714047 is the observed proportion, not an
# observation, and one imputation constant can propagate into several derived
# variables.
#
# Splitting on such a variable produces a stratum that LOOKS like a clinical
# group, has a plausible survival curve, and is really "this covariate was
# missing".
#
# SAS %KAPLAN DROPS these rows, reporting "NOTE: n observations with invalid
# ... strata values were deleted".
#
# THIS TEMPLATE DOES NOT DROP THEM. They are carried as an explicit "Unknown"
# stratum: "we do not know this patient's value" is a fact about the cohort
# worth showing, and the stratified table then accounts for every patient
# rather than quietly shedding some. This is a DELIBERATE DIVERGENCE from the
# SAS baseline, legitimate because an R_hazard job does the analysis; matching
# SAS is a parity job's business and applies only where a stored SAS answer
# exists.
#
# Consequence to state in any report built from this file: the Unknown
# stratum's curve is NOT a clinical subgroup and must not be read as one. It is
# a missingness stratum, and a difference between it and the others is evidence
# about who had the covariate recorded, not about the covariate.
# imputed_levels() is hvtiRutilities' (>= 1.1.4). This file carried a local copy
# until then; it was identical, so the copy only meant two places to fix.
UNKNOWN <- "Unknown"

# Stratified fits, one per level, with the level carried on the result so the
# strata cannot be silently transposed when the tables are stacked.
km_by <- function(dd, var) {
  raw    <- as.character(dd[[var]])
  imp_lv <- imputed_levels(dd[[var]])

  # Both imputed levels and outright NA mean "we do not know". They are folded
  # into one Unknown stratum, but their provenance is reported separately below
  # so the fold is never silent.
  lab <- raw
  lab[raw %in% imp_lv | is.na(raw)] <- UNKNOWN

  # Unknown sorts LAST, whatever the observed levels are called.
  obs <- sort(setdiff(unique(lab), UNKNOWN))
  lab <- factor(lab, levels = c(obs, if (UNKNOWN %in% lab) UNKNOWN))

  parts <- split(dd, lab)
  out <- do.call(rbind, lapply(levels(lab), function(lv) {
    p <- parts[[lv]]
    # Carry the number of patients FITTED. Do not report n_risk[1] as the
    # stratum size: that is the number at risk at the FIRST EVENT time, and any
    # patient censored before the stratum's first death is missing from it. The
    # two agree only when a stratum has a death at t=0, which large strata do
    # and small ones do not -- so the error appears exactly where it is hardest
    # to notice.
    cbind(stratum = lv,
          n       = sum(!is.na(p[[TIME]]) & !is.na(p[[EVENT]])),
          km_fit(p))
  }))

  src <- rbind(
    if (length(imp_lv)) {
      data.frame(
        source = imp_lv,
        n = vapply(imp_lv, function(l) sum(raw == l, na.rm = TRUE), integer(1)),
        reason = "mean-imputed level, not an observed value"
      )
    },
    if (anyNA(raw)) {
      data.frame(source = "NA", n = sum(is.na(raw)), reason = "missing outright")
    }
  )
  attr(out, "unknown_sources") <- if (!is.null(src)) `rownames<-`(src, NULL) else NULL
  out
}

# Print what went into Unknown alongside the estimates, never instead of them.
report_unknown <- function(fit, var) {
  src <- attr(fit, "unknown_sources")
  if (is.null(src)) return(invisible(NULL))
  cap <- paste0(
    "What the ", var, " \"", UNKNOWN, "\" stratum is made of: a missingness ",
    "group, NOT a clinical subgroup. SAS %KAPLAN drops these rows."
  )
  .child(paste("tbl km strata", var, "unknown"), cap, "knitr::kable(src, row.names = FALSE)")
}
```

## Overall

Code

``` r
km <- km_fit(d)
knitr::kable(head(readable(km), 20))
ac_art <- hvtiRtemplates:::.attach_handoff_lineage(
  list(overall = km),
  data = .provenance_data,
  analysis = list(
    time = list(variable = TIME),
    event = list(variable = EVENT, event = 1L, censored = 0L)
  ),
  cohort = cc,
  # hp checks that ac and hz read the same rows with the same TIME and EVENT.
  selection = c(attr(job_data$record, "selection"), list(time = TIME, event = EVENT))
)
saveRDS(ac_art, set_path("estimates", "ac.rds"))
```

| time | n_risk | n_event | n_censor | survival | std_err | cl_lower | cl_upper | cumhaz | hazard | density | life |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 0.00025 | 725 | 6 | 0 | 0.9917241 | 0.0033646 | 0.9875825 | 0.9944921 | 0.0083103 | 33.2411885 | 33.1034483 | 0.0002500 |
| 0.00100 | 719 | 1 | 0 | 0.9903448 | 0.0036317 | 0.9859469 | 0.9933757 | 0.0097021 | 1.8557182 | 1.8390805 | 0.0009938 |
| 0.00200 | 718 | 2 | 0 | 0.9875862 | 0.0041122 | 0.9827244 | 0.9910922 | 0.0124915 | 2.7894021 | 2.7586207 | 0.0019841 |
| 0.00300 | 716 | 1 | 0 | 0.9862069 | 0.0043316 | 0.9811325 | 0.9899306 | 0.0138891 | 1.3976243 | 1.3793103 | 0.0029717 |
| 0.00500 | 715 | 1 | 0 | 0.9848276 | 0.0045398 | 0.9795510 | 0.9887582 | 0.0152887 | 0.6997902 | 0.6896552 | 0.0049441 |
| 0.01100 | 714 | 1 | 0 | 0.9834483 | 0.0047384 | 0.9779787 | 0.9875766 | 0.0166902 | 0.2335903 | 0.2298851 | 0.0108531 |
| 0.01400 | 713 | 2 | 0 | 0.9806897 | 0.0051109 | 0.9748576 | 0.9851895 | 0.0194992 | 0.9363302 | 0.9195402 | 0.0138034 |
| 0.01700 | 711 | 1 | 0 | 0.9793103 | 0.0052865 | 0.9733071 | 0.9839857 | 0.0209067 | 0.4691533 | 0.4597701 | 0.0167455 |
| 0.02200 | 709 | 1 | 0 | 0.9779291 | 0.0054565 | 0.9717600 | 0.9827744 | 0.0223181 | 1.4114328 | 1.3812558 | 0.0216421 |
| 0.02300 | 708 | 1 | 0 | 0.9765478 | 0.0056209 | 0.9702183 | 0.9815577 | 0.0237315 | 1.4134278 | 1.3812558 | 0.0226200 |
| 0.03500 | 706 | 1 | 0 | 0.9751646 | 0.0057807 | 0.9686792 | 0.9803344 | 0.0251490 | 0.1288577 | 0.1257466 | 0.0343386 |
| 0.03600 | 705 | 1 | 0 | 0.9737814 | 0.0059357 | 0.9671446 | 0.9791066 | 0.0265684 | 1.4194467 | 1.3832122 | 0.0353137 |
| 0.04100 | 704 | 2 | 0 | 0.9710150 | 0.0062328 | 0.9640879 | 0.9766383 | 0.0294134 | 0.5689904 | 0.5532849 | 0.0401826 |
| 0.05700 | 702 | 1 | 0 | 0.9696318 | 0.0063756 | 0.9625652 | 0.9753985 | 0.0308389 | 0.0890948 | 0.0864508 | 0.0557189 |
| 0.08200 | 701 | 1 | 0 | 0.9682486 | 0.0065148 | 0.9610460 | 0.9741552 | 0.0322664 | 0.0571021 | 0.0553285 | 0.0799597 |
| 0.08800 | 700 | 1 | 0 | 0.9668653 | 0.0066507 | 0.9595300 | 0.9729087 | 0.0336960 | 0.2382655 | 0.2305354 | 0.0857692 |
| 0.09800 | 699 | 1 | 0 | 0.9654821 | 0.0067835 | 0.9580171 | 0.9716591 | 0.0351277 | 0.1431639 | 0.1383212 | 0.0954378 |
| 0.10300 | 698 | 1 | 0 | 0.9640989 | 0.0069134 | 0.9565070 | 0.9704067 | 0.0365614 | 0.2867384 | 0.2766424 | 0.1002652 |
| 0.10600 | 697 | 1 | 0 | 0.9627157 | 0.0070405 | 0.9549996 | 0.9691515 | 0.0379971 | 0.4785835 | 0.4610707 | 0.1031575 |
| 0.12500 | 696 | 1 | 0 | 0.9613325 | 0.0071650 | 0.9534948 | 0.9678937 | 0.0394349 | 0.0756745 | 0.0728006 | 0.1214491 |

Table 5: Overall life table (first 20 rows)

Survival at reporting horizons, read off the step function as the last
estimate at or before each horizon.

Code

``` r
# your reporting horizons, in the time unit of TIME (years here).
# A wrong grid does not error — it produces a plausible-looking table.

at_horizon <- function(fit, g) {
  i <- which(fit$time <= g)
  # BEFORE the first event: the life table starts at the first event time, so a
  # stratum with no event before `g` has no row at or below it. Survival there
  # is 1, not missing -- NA_real_ would read as "no data" in a stratum that
  # simply had no deaths yet, and small strata are where that happens.
  beyond <- g > fit$max_fup[1]
  if (!length(i)) return(if (beyond) NA_real_ else 1)
  s <- fit$survival[max(i)]
  # BEYOND THE END OF FOLLOW-UP the KM estimate is NOT DEFINED, and carrying the
  # last value forward silently reports a horizon nobody was observed to.
  # Return NA instead -- EXCEPT when survival has already reached 0, which is
  # absorbing: everyone has died, so 0 is genuinely known thereafter.
  # Compare against max_fup, NOT max(fit$time): the latter is the last EVENT.
  if (beyond && s > 0) return(NA_real_)
  s
}

knitr::kable(data.frame(
  horizon  = labs,
  survival = round(100 * vapply(grid, at_horizon, numeric(1), fit = km), 1)
))
```

| horizon  | survival |
|:---------|---------:|
| 30 days  |     96.8 |
| 6 months |     93.9 |
| 1 year   |     91.3 |
| 5 years  |     71.1 |
| 10 years |     56.1 |

Table 6: Overall survival (%) at reporting horizons

## Stratified

Code

``` r
# unnumbered: each child chunk below carries its own label and caption
stratum_row <- function(s) {
  data.frame(
    stratum  = s$stratum[1],
    n        = s$n[1],
    n_events = sum(s$n_event),
    setNames(as.list(round(100 * vapply(grid, at_horizon, numeric(1), fit = s), 1)), labs),
    check.names = FALSE
  )
}

# your stratification variables.
for (v in STRATA) {
  fit <- km_by(d, v)
  .strata <- do.call(rbind, lapply(split(fit, fit$stratum), stratum_row))
  .child(paste("tbl km strata", v), paste0("Survival (%) by ", v), "knitr::kable(.strata, row.names = FALSE)")
  report_unknown(fit, v)
}
```

Code

``` r
knitr::kable(.strata, row.names = FALSE)
```

| stratum |   n | n_events | 30 days | 6 months | 1 year | 5 years | 10 years |
|:--------|----:|---------:|--------:|---------:|-------:|--------:|---------:|
| 1       |  79 |       61 |    97.5 |     89.9 |   87.3 |    55.7 |     38.0 |
| 2       | 215 |      144 |    95.3 |     94.4 |   91.6 |    64.5 |     46.8 |
| 3       | 431 |      197 |    97.4 |     94.4 |   91.8 |    77.4 |     64.3 |

Table 7: Survival (%) by lvef_grp

Code

``` r
knitr::kable(.strata, row.names = FALSE)
```

| stratum |   n | n_events | 30 days | 6 months | 1 year | 5 years | 10 years |
|:--------|----:|---------:|--------:|---------:|-------:|--------:|---------:|
| 0       | 507 |      232 |    97.2 |     94.9 |   92.7 |    77.3 |     64.9 |
| 1       | 218 |      170 |    95.9 |     91.7 |   88.0 |    56.8 |     36.7 |

Table 8: Survival (%) by hx_chf

Nested stratification — one stratum variable within the levels of
another — is the same call applied to each subset.

Code

``` r
# Demo: your nesting, or delete this chunk if the job has none. It is
# `eval: false` because the template ships no second category; turn it on once
# `cat_b` exists.
for (outer in sort(unique(d$cat_b))) {
  sub <- d[d$cat_b == outer, , drop = FALSE]
  fit <- km_by(sub, "cat_a")
  print(knitr::kable(
    do.call(rbind, lapply(split(fit, fit$stratum), function(s) data.frame(
      cat_a    = s$stratum[1],
      n        = s$n[1],
      n_events = sum(s$n_event),
      setNames(as.list(round(100 * vapply(grid, at_horizon, numeric(1), fit = s), 1)), labs),
      check.names = FALSE
    ))),
    row.names = FALSE,
    caption = paste0("Survival (%) by cat_a within cat_b = ", outer)
  ))
  report_unknown(fit, "cat_a")
}
```
