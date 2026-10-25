# Logit calibration

# Logit calibration

Published

2026-10-25 18:28

An `lg` job decides which scale a covariate should enter a model on,
before it goes into `PREDICTORS` in an `lm` job. A model of an event
rate on a covariate assumes the rate is straight in the covariate on the
link scale, and a covariate that is skewed, or that acts through its
inverse, breaks that quietly: the model fits and reports a coefficient
for a shape the data do not have. This job shows the shape first.

For each covariate it ranks the patients into groups (usually five),
takes the event rate of each group on a link scale, and plots that
against the covariate on six candidate scales, so the analyst can pick
the one that comes out straightest. It replaces the SAS `%logit` macro,
which ranked with `PROC RANK`, and `%logitgr`, which took each level of
an ordinal covariate as a group. The link is the logit,
`log(p / (1 - p))`, for a binary event, or, for time-related death, the
log of the constant hazard rate, `log(events / sum of follow-up)`, which
is what the SAS jobs called with `cox=1`. The R-squared in each panel is
the weighted straight-line fit of the groups, weighted by group size. It
is guidance for “straightest”, not a decision: the choice goes in
`chosen`, and the job saves it.

Code

``` r
# unnumbered: setup, and the box under the title
SUBJECT <- "dead"
TYPE    <- "calibration"
.in <- knitr::current_input(dir = TRUE)
suppressPackageStartupMessages(library(hvtiRutilities))
if (utils::packageVersion("hvtiPlotR") < "2.8.8") {
  stop("This job needs hvtiPlotR >= 2.8.8 for hv_panel_size()'s 6.5 inch page; ",
       utils::packageVersion("hvtiPlotR"), " is installed.", call. = FALSE)
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
# Saves a figure as <name>.png, .pdf and .tiff in this set's graphs/ folder (or `kind`'s),
# under the SAVE_FIGURES and FIGURES study choices.
save_figure <- function(plot, name, width = 6, height = 4, kind = "graphs", linked = FALSE) {
  hvtiRtemplates:::.save_figure(plot, set_path(kind, paste0(name, ".png")), width, height,
                                SAVE_FIGURES, FIGURES, linked)
}
# The draft banners, if any, and the box under the title, after all the code above.
.job$notice
```

**final** · data `built` `built_20261025.parquet`, dated 2026-10-25 ·
rendered by gallery on gallery · hvtiRtemplates 1.5.1

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

# Demo: the event, a 0/1 column, 1 for a patient who had it (the SAS macro's
# EVENT=). TRUE and FALSE also work. A patient with no value is ranked with the
# rest, as in SAS, but counts toward no group's rate: not in its patients, its
# events or, under "hazard", its follow-up.
EVENT <- "dead"

# Demo: the link, the scale the group rates are put on before they are plotted.
# "hazard" is the log of the constant hazard rate, log(events / sum of follow-up),
# for an event with variable follow-up such as death (the SAS call's cox=1).
# "logit" is log(p / (1 - p)), for an event every patient was followed to the same
# point for, such as in-hospital death or a complication.
LINK <- "hazard"

# Demo: the follow-up column, in the unit the study reports (years here). Only
# "hazard" reads it, and INTERVAL below reads it for either link. A patient with
# no value is left out of a "hazard" calibration, as the SAS macro left them out.
TIME <- "iv_dead"

# Demo: NULL, or a window on follow-up, c(start, end), such as c(0.25, 5): one phase
# of a hazard, the SAS early, constant or late phase, in the unit of TIME. A patient
# whose follow-up ended before `start` is left out and counted. Everyone else is
# censored at `end`: a patient followed past it counts as followed to `end`, and an
# event after it does not count. Under "hazard" the time at risk is then the time
# inside the window, TIME capped at `end`, less `start`; the SAS template summed it
# from 0. Under "logit" the same patients are kept and an event counts only if it
# falls inside the window. Both counts are reported under the data table.
INTERVAL <- NULL

# Demo: the covariates to calibrate, one row each. `name` is a column of the data;
# `kind` is "continuous" (ranked into groups) or "ordinal" (each level is a
# group). The other columns are optional, and a covariate that does not give
# one takes the default:
#   groups    5      how many groups a continuous covariate is ranked into; the
#                    job stops if any group has fewer than 5 patients, and for
#                    an ordinal covariate (at most 20 levels) if any level has
#   constant  the covariate's median to one significant figure; the c in the
#             inverse, inverse squared, squared and exponential scales. A
#             median that rounds to 0 (a 0/1 indicator) leaves it NA, and
#             those four scales are not computable until you set one
#   shift     0      added before the log, for a covariate that can be 0
#   label     the name   the heading over its table and figure
#   chosen    NA     the scale to use: "raw", "log", "inverse",
#                    "inverse_squared", "squared" or "exp". Leave it NA until
#                    you have seen the figure; the job then warns, and a final
#                    render stops until every covariate has one.
VARIABLES <- data.frame(
  name   = c("age", "nyha_pr"),
  kind   = c("continuous", "ordinal"),
  chosen = c("raw", "raw")
)

# Each figure is saved to graphs/ as a PNG (for Word), and a PDF and a TIFF (for the publisher).
# SAVE_FIGURES <- FALSE saves none; FIGURES keeps only the figures whose names
# start with one of its entries, e.g. FIGURES <- c("lg-age"). The names are the
# file names, listed for each template in the templates README.
SAVE_FIGURES <- TRUE
FIGURES <- NULL
```

## Data

Code

``` r
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
| Source              | dataset `built` (built_20261025.parquet) |
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
# unnumbered: checks the choices against the data and shows nothing
# Every choice is checked against the data before any calibration, so a
# misspelled column stops here by name rather than as an error from inside it.
.id <- attr(job_data$record, "selection")$id
if (!identical(LINK, "logit") && !identical(LINK, "hazard")) {
  stop("LINK must be \"logit\" or \"hazard\".", call. = FALSE)
}
one_column <- function(x, setting) {
  if (!(is.character(x) && length(x) == 1L && !is.na(x))) stop(setting, " must be one column name.", call. = FALSE)
}
one_column(EVENT, "EVENT")
# TIME is read by the hazard link and by INTERVAL, and by nothing else.
.needs_time <- identical(LINK, "hazard") || !is.null(INTERVAL)
if (.needs_time) one_column(TIME, "TIME")
hvtiRtemplates:::.check_job_columns(d, EVENT = EVENT, TIME = if (.needs_time) TIME)
if (.id %in% c(EVENT, if (.needs_time) TIME)) {
  stop("EVENT and TIME cannot be the patient identifier.", call. = FALSE)
}
if (.needs_time && !is.numeric(d[[TIME]])) {
  stop("TIME must be a number, the follow-up in years or months: `", TIME, "` is not numeric.", call. = FALSE)
}
if (.needs_time) hvtiRtemplates:::.lg_follow_up(d[[TIME]], TIME)
# INTERVAL leaves patients out and censors the rest before anything else is
# computed, so the constants and the groups below are those of the patients
# calibrated, and the event and follow-up the tables read are the windowed ones.
.interval <- hvtiRtemplates:::.lg_interval(d, EVENT, if (.needs_time) TIME, INTERVAL)
d <- .interval$data
.event <- .interval$event
.time <- .interval$time
variables <- hvtiRtemplates:::.lg_variables(VARIABLES, d, exclude = .id, event = .event,
                                            time = if (identical(LINK, "hazard")) .time)
```

Code

``` r
# unnumbered: its child chunk carries its own label and caption
if (!is.null(.interval$counts)) {
  .fence <- strrep("`", 3)
  .cap <- paste0("The window of follow-up from ", INTERVAL[[1L]], " to ", INTERVAL[[2L]], " (INTERVAL): patients left out, ",
                 "and patients censored at its end")
  cat(knitr::knit_child(text = c(
    paste0(.fence, "{r}"), "#| label: tbl-lg-interval",
    paste0("#| tbl-cap: ", encodeString(.cap, quote = "\"")),
    "knitr::kable(.interval$counts, col.names = c(\"\", \"Patients\"))", .fence
  ), envir = environment(), quiet = TRUE), sep = "\n")
}
```

## Covariates

Each covariate with the defaults filled in. The `constant` is the `c` in
the inverse, inverse squared, squared and exponential scales: it only
sets them to a readable range, so the median rounded to one figure does
the work the SAS jobs’ hand-typed 50 for an age or 80 for a weight did.
Set it, or `shift` for a covariate that can be 0, in `VARIABLES` to
change either.

Code

``` r
knitr::kable(variables, col.names = c("Covariate", "Kind", "Groups", "Constant", "Shift", "Label", "Chosen"),
             row.names = FALSE)
```

| Covariate | Kind       | Groups | Constant | Shift | Label   | Chosen |
|:----------|:-----------|-------:|---------:|------:|:--------|:-------|
| age       | continuous |      5 |       60 |     0 | age     | raw    |
| nyha_pr   | ordinal    |      5 |        2 |     0 | nyha_pr | raw    |

Table 2: The covariates calibrated, with their defaults

## Calibration

For each covariate, a table of its groups and the figure of the groups’
link values against six scales of the covariate. Read the figure for the
panel that comes out straightest. The R-squared in each corner is only a
guide: it is the fit of a straight line weighted by group size, so a
panel can score high and still bend. A group whose link value cannot be
computed keeps its row in the table, blank, and is named under it. A
scale that cannot be computed for the covariate is drawn as an empty
panel, and named there too.

Code

``` r
# unnumbered: each covariate's child chunks carry their own labels and captions
# The figure is saved as PNG and PDF under graphs/<subject>-<type>/lg-<covariate>,
# and the PNG is the one the report shows.
.fence <- strrep("`", 3)
.kable_na <- options(knitr.kable.NA = "")
calibration <- list()
for (i in seq_len(nrow(variables))) {
  .v <- variables[i, ]
  .tab <- hvtiRtemplates:::.lg_table(d[[.v$name]], .event, if (identical(LINK, "hazard")) .time,
                                     groups = .v$groups, kind = .v$kind, link = LINK)
  .scales <- hvtiRtemplates:::.lg_scales(.tab$mean, .v$constant, .v$shift)
  calibration[[.v$name]] <- list(table = .tab, scales = .scales)
  .plot <- hvtiRtemplates:::.lg_plot(.tab, .scales, LINK, title = .v$label)
  # Six facets, one per scale, in two rows of three: hv_panel_size() gives each a 3 by 2
  # inch panel, shrunk together to fit a 6.5 inch page, so the figure is no wider than a page.
  .dims <- hvtiPlotR::hv_panel_size(.plot)
  .file <- save_figure(.plot, paste0("lg-", .v$name), width = .dims$width, height = .dims$height, linked = TRUE)
  # This document sits in descriptive/ and the figure is written to graphs/, so
  # the image link is the figure's path relative to this document.
  .link <- xfun::relative_path(.file, if (!is.null(.in)) dirname(.in) else getwd(), error = FALSE)
  # A label holds letters, digits and hyphens, so an underscore in a name cannot
  # be read as markup in a cross-reference.
  .slug <- gsub("[^A-Za-z0-9]+", "-", .v$name)
  .heads <- c("Group", "Mean", "Minimum", "Maximum", "Patients", "Events",
              if (identical(LINK, "hazard")) "Events per unit of follow-up" else "Event rate",
              if (identical(LINK, "hazard")) "Log hazard rate" else "Logit")
  .cap_tbl <- paste0("Groups of ", .v$label, ", with the event rate and its link value")
  .cap_fig <- paste0(.v$label, ": the link value of each group against the covariate on six scales, ",
                     "with the R-squared of a weighted straight line. Black filled circles mark the groups, joined by a ",
                     "gray line, and the text in each panel corner gives the R-squared")
  cat("\n### ", .v$label, "\n\n", sep = "")
  cat(knitr::knit_child(text = c(
    paste0(.fence, "{r}"), paste0("#| label: tbl-lg-", .slug),
    paste0("#| tbl-cap: ", encodeString(.cap_tbl, quote = "\"")),
    "knitr::kable(.tab, col.names = .heads, digits = 3, row.names = FALSE)", .fence, "",
    paste0(.fence, "{r}"), paste0("#| label: fig-lg-", .slug),
    paste0("#| fig-cap: ", encodeString(.cap_fig, quote = "\"")),
    "knitr::include_graphics(.link, error = FALSE)", .fence
  ), envir = environment(), quiet = TRUE), sep = "\n")
  .dropped <- attr(.tab, "dropped")
  .scale_notes <- attr(.scales, "notes")
  .left <- c(if (.dropped[["covariate"]] > 0L) paste0(.dropped[["covariate"]], " without a value of the covariate"),
             if (.dropped[["follow_up"]] > 0L) paste0(.dropped[["follow_up"]], " without follow-up"))
  .notes <- c(
    if (length(.left)) paste0("Left out of the groups: ", paste(.left, collapse = ", "), "."),
    if (.dropped[["event"]] > 0L) {
      paste0(.dropped[["event"]], " with no event value are ranked but counted in no group's patients, events or follow-up.")
    },
    attr(.tab, "notes"),
    if (length(.scale_notes)) paste0(hvtiRtemplates:::.lg_panel_labels[names(.scale_notes)], ": ", .scale_notes)
  )
  if (length(.notes)) cat("\n", paste0("- ", .notes, collapse = "\n"), "\n", sep = "")
}
```

### age

Code

``` r
knitr::kable(.tab, col.names = .heads, digits = 3, row.names = FALSE)
```

| Group | Mean | Minimum | Maximum | Patients | Events | Events per unit of follow-up | Log hazard rate |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 44.904 | 32 | 52 | 156 | 60 | 0.028 | -3.559 |
| 2 | 55.881 | 53 | 59 | 159 | 83 | 0.048 | -3.041 |
| 3 | 62.482 | 60 | 65 | 170 | 94 | 0.062 | -2.776 |
| 4 | 68.968 | 66 | 72 | 157 | 95 | 0.071 | -2.639 |
| 5 | 79.500 | 73 | 100 | 158 | 113 | 0.126 | -2.074 |

Table 3: Groups of age, with the event rate and its link value

Code

``` r
knitr::include_graphics(.link, error = FALSE)
```

![](assets/d34862ed185fb0dbd2dda252049a1537.png)

Figure 1: age: the link value of each group against the covariate on six
scales, with the R-squared of a weighted straight line. Black filled
circles mark the groups, joined by a gray line, and the text in each
panel corner gives the R-squared

### nyha_pr

Code

``` r
knitr::kable(.tab, col.names = .heads, digits = 3, row.names = FALSE)
```

| Group | Mean | Minimum | Maximum | Patients | Events | Events per unit of follow-up | Log hazard rate |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 1 | 1 | 1 | 129 | 64 | 0.063 | -2.762 |
| 2 | 2 | 2 | 2 | 360 | 208 | 0.066 | -2.725 |
| 3 | 3 | 3 | 3 | 275 | 146 | 0.048 | -3.035 |
| 4 | 4 | 4 | 4 | 36 | 27 | 0.075 | -2.586 |

Table 4: Groups of nyha_pr, with the event rate and its link value

Code

``` r
knitr::include_graphics(.link, error = FALSE)
```

![](assets/38410c083c8c548267f58f99defdc2c8.png)

Figure 2: nyha_pr: the link value of each group against the covariate on
six scales, with the R-squared of a weighted straight line. Black filled
circles mark the groups, joined by a gray line, and the text in each
panel corner gives the R-squared

Code

``` r
options(.kable_na)
```

## Chosen scales

Once you have read the figures, set `chosen` for each covariate in
`VARIABLES` and render again. The job saves the choice as
`lg-scales.rds`, one row for each covariate: the scale, the term to
write for it, and the constant and shift it used. The term goes into the
`PREDICTORS` of an `lm` job as it stands, so the model is fitted on the
scale the figure showed.

A covariate with no choice, or whose chosen scale cannot be computed, is
not saved. In a draft the job warns and lists it here; a final render
stops, as it does for an open marker, so a finished job has chosen every
scale.

Code

``` r
# unnumbered: its child chunk carries its own label and caption
choices <- hvtiRtemplates:::.lg_choices(variables, lapply(calibration, `[[`, "scales"), d)
if (length(choices$problems)) {
  .msg <- paste0("These covariates have no usable scale chosen: ",
                 paste0("`", names(choices$problems), "`: ", choices$problems, collapse = "; "),
                 ". Read each figure above and set chosen for it in VARIABLES.")
  if (hvtiRtemplates:::.strict_render()) {
    stop(.msg, "\nThis render stops because HVTI_TEMPLATE_STRICT is '", Sys.getenv("HVTI_TEMPLATE_STRICT"),
         "': a final report names a scale for every covariate. Unset it, or set it to 0, false or no, ",
         "to render a draft instead.", call. = FALSE)
  }
  warning(.msg, "\nRendering as a draft; the banner goes when every covariate has a choice.", call. = FALSE)
  # The box under the title was printed before this was known; the end table says draft.
  hvtiRtemplates:::.run_mark_draft(paste0("a scale is not chosen for ", length(choices$problems), " covariate(s)"))
  cat("\n::: {.callout-important title=\"DRAFT -- a scale is not chosen\"}\n", .msg, "\n:::\n\n", sep = "")
}
# What is saved holds the covariates with a usable choice and no patient: the
# scale, its term, constant and shift. Its lineage says which data it came from.
saveRDS(
  hvtiRtemplates:::.attach_handoff_lineage(
    choices$table,
    data = .provenance_data,
    analysis = Filter(Negate(is.null), list(event = EVENT, link = LINK, time = if (.needs_time) TIME, interval = INTERVAL)),
    cohort = list(patients = nrow(d)),
    selection = attr(job_data$record, "selection")
  ),
  set_path("estimates", "lg-scales.rds")
)
if (nrow(choices$table)) {
  .fence <- strrep("`", 3)
  cat(knitr::knit_child(text = c(
    paste0(.fence, "{r}"), "#| label: tbl-lg-scales",
    "#| tbl-cap: \"The scale chosen for each covariate, and the term to write for it in an lm job\"",
    "knitr::kable(choices$table, col.names = c(\"Covariate\", \"Scale\", \"Term\", \"Constant\", \"Shift\"), row.names = FALSE)",
    .fence
  ), envir = environment(), quiet = TRUE), sep = "\n")
}
```

Code

``` r
knitr::kable(choices$table, col.names = c("Covariate", "Scale", "Term", "Constant", "Shift"), row.names = FALSE)
```

| Covariate | Scale | Term    | Constant | Shift |
|:----------|:------|:--------|---------:|------:|
| age       | raw   | age     |       60 |     0 |
| nyha_pr   | raw   | nyha_pr |        2 |     0 |

Table 5: The scale chosen for each covariate, and the term to write for
it in an lm job

Code

``` r
.predictors <- hvtiRtemplates:::.lg_predictors(choices$table$term)
if (nrow(choices$table)) {
  cat("\nThe line to copy into the `PREDICTORS` of an `lm` job, beside its other predictors:\n\n",
      "```r\n", .predictors, "\n```\n", sep = "")
} else {
  cat("\n", .predictors, "\n", sep = "")
}
```

The line to copy into the `PREDICTORS` of an `lm` job, beside its other
predictors:

``` r
PREDICTORS <- c("age", "nyha_pr")
```

## About this run

| Group           | Item             | Value                    |
|:----------------|:-----------------|:-------------------------|
| Run             | Started          | 2026-10-25 18:28:37 EDT  |
|                 | Ended            | 2026-10-25 18:28:40 EDT  |
|                 | Duration         | 3 s                      |
|                 | Status           | final                    |
|                 | Rendered by      | gallery                  |
|                 | Host             | gallery                  |
| Job             | File             | lg.dead.calibration.qmd  |
|                 | Template         | lg                       |
|                 | Subject          | dead                     |
|                 | Type             | calibration              |
|                 | hvtiRtemplates   | 1.5.1                    |
| Dataset `built` | Version file     | built_20261025.parquet   |
|                 | Version date     | 2026-10-25               |
|                 | Source file      | built.rds                |
|                 | Rows kept        | 800 rows on 800 patients |
|                 | WHERE            | none                     |
|                 | sha256           | b236a472f1f3             |
|                 | Manifest         | current                  |
| Reproducibility | renv             | not active               |
|                 | renv.lock sha256 | d09f96b6cd21             |
