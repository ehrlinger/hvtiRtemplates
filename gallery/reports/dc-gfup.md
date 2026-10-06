# Goodness of follow-up

# Goodness of follow-up

Replaces `descriptive/dc.gfup`.

A `dc-gfup` job checks follow-up before time-related analyses. We
summarize the full cohort and the event and censored subsets, review
missing, negative and zero intervals, then draw the
goodness-of-follow-up figure. Follow-up units must be years. Derive any
potential-follow-up measures in the data build and register them before
selecting them here.

The tables describe recorded follow-up. The figure measures it against a
close date: every patient is one point, the year of operation across and
the follow-up recorded for them up, blue while alive and red once dead.
The dashed diagonal is the follow-up a patient **could** have had, from
their operation to the close date. A censored patient far below the
diagonal is someone whose follow-up stopped early, and a band of them is
a follow-up problem to settle before any time-related analysis.

The figure is `hvtiPlotR::hv_followup_panels()`, which the EDA report
also calls, so its follow-up panels are these. It was the separate
`dp-gfup` job, now deprecated in favor of this one.

Code

``` r
# unnumbered: loads packages and checks versions only
# The study root is the nearest directory above this file holding _study.yml,
# so the job renders the same from the Render button, quarto render, or
# render_job(), at any depth, with no path in this document to edit.
.in <- knitr::current_input(dir = TRUE)
.root <- hvtiRtemplates:::.find_study_root(if (is.null(.in)) getwd() else dirname(.in))
.provenance_data <- list()
for (f in list.files(file.path(.root, "R"), pattern = "[.]R$", full.names = TRUE)) source(f)
suppressPackageStartupMessages({
  library(hvtiRutilities)
  library(hvtiPlotR)
  library(ggplot2)
})
if (utils::packageVersion("hvtiRutilities") < "1.4.1") {
  stop("This job needs hvtiRutilities >= 1.4.1 for followup_check(); ",
       utils::packageVersion("hvtiRutilities"), " is installed.", call. = FALSE)
}
if (utils::packageVersion("hvtiPlotR") < "2.8.0") {
  stop("This job needs hvtiPlotR >= 2.8.0 for hv_followup_panels() and scale_color_hv(); ",
       utils::packageVersion("hvtiPlotR"), " is installed.", call. = FALSE)
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
    .msg <- paste0(
      length(.hits), " unresolved ", .tok, " marker(s) remain in this job:\n",
      paste0("  - ", trimws(substr(.src[.hits], 1L, 96L)), collapse = "\n"),
      "\nA job that still contains one has not been finished. Work each ",
      "marker and delete it."
    )
    if (tolower(Sys.getenv("HVTI_TEMPLATE_STRICT")) %in% c("", "0", "false", "no")) {
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
SUBJECT <- "cohort"
TYPE    <- "eda"

.current <- knitr::current_input()
if (!is.null(.current)) {
  .fields <- strsplit(sub("[.][^.]+$", "", basename(.current)), "-", fixed = TRUE)[[1L]]
  .name_subject <- if (length(.fields) >= 1L) .fields[[1L]] else NA_character_
  .name_type <- if (length(.fields) >= 2L) .fields[[2L]] else NA_character_
  if (!identical(.name_subject, SUBJECT) || !identical(.name_type, TYPE)) {
    stop("This file is named '", .current, "' (subject '", .name_subject,
         "', type '", .name_type, "'), but declares SUBJECT = \"", SUBJECT,
         "\", TYPE = \"", TYPE, "\". Fix the declaration or the filename before rendering.",
         call. = FALSE)
  }
}

set_path <- function(kind, file) {
  d <- file.path(hvtiRutilities::study_dir(kind, .root),
                 paste0(SUBJECT, "-", TYPE))
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  file.path(d, file)
}
```

## Study choices

Set the values in this chunk before rendering.

Code

``` r
# Demo: the registered dataset this job reads ("study" is the built dataset).
# MIGRATE-BEGIN: dc-gfup-data
DATASET <- "study"
# MIGRATE-END: dc-gfup-data

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

# MIGRATE-BEGIN: dc-gfup-config
EVENT <- "dead"       # Demo: binary event indicator, 1=event and 0=censored
FOLLOWUP <- "iv_dead" # Demo: follow-up interval(s) this job checks, in years
IDENTIFIER <- NULL    # Demo: opt in only for local review
MAX_REVIEW_ROWS <- 25L
# MIGRATE-END: dc-gfup-config
# Demo: optional event-coding cross-tabs, each a vector of column names.
# Missing values are shown. Use list() when no additional checks are needed.
CHECKS <- list(c("dead", "reop"))

# The figure. These are dp-eda's follow-up choices, and mean what they mean there.
# Demo: the years-since-origin interval to the operation, and that origin, a
# calendar year such as 1990. The origin differs between studies, and a wrong
# one slides every point along the x-axis without any other symptom, which is
# why the operation years are checked and printed below.
OPYRS <- "iv_opyrs"
ORIGIN_YEAR <- 1990

# Demo: the close date of follow-up, as.Date("YYYY-MM-DD"). NULL estimates it
# as the latest operation date plus follow-up in the data, which is the date
# follow-up is known to reach, not the date it was closed; the report says
# which one it drew.
CLOSE_DATE <- NULL

# Demo: one entry per death panel. `status` is the 1/0 death indicator and
# `time` its follow-up in years; the default draws the same columns as the
# EVENT and FOLLOWUP defaults above. A study that ascertains deaths two ways draws both,
# for example
#   systematic = list(status = "deads", time = "iv_deads", title = "Systematic deaths")
PANELS <- list(
  all = list(status = "dead", time = "iv_dead", title = "All deaths")
)

# Demo: optional event panels, one entry per non-fatal event. `event` and
# `time` are the event's indicator and interval; `death` and `death_time` the
# death it competes with. A flagged event counts only when it comes strictly
# before death, so ties go to death. list() draws none. For example
#   reop = list(event = "ev_reop", time = "iv_reop", death = "dead",
#               death_time = "iv_dead", label = "Reoperation")
EVENTS <- list()

# Demo: point transparency. 0.5 lets a dense cohort read as a distribution
# rather than a blob; raise it for a small one.
ALPHA <- 0.5

# Demo: NULL draws the house colors through hvtiPlotR::scale_color_hv(): dead
# vermillion, alive blue and a non-fatal event green, all colorblind safe. Name
# all three to choose your own; c(alive = "#377EB8", dead = "#E41A1C",
# event = "#4DAF4A") is ColorBrewer Set1, what these jobs drew before 1.2.3.
COLORS <- NULL
```

## Data

Code

``` r
hvtiRutilities::verify_manifest(file.path(.root, "manifest.yaml"))
.cfg <- study_config(start = .root)
job_data <- hvtiRtemplates::read_job_data(.cfg, dataset = DATASET, analysis_set = ANALYSIS_SET,
                                          where = WHERE, id = ID, key = KEY)
d <- job_data$data
.provenance_data <- c(if (exists(".provenance_data")) .provenance_data else list(), list(job_data$provenance))
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

## Follow-up checks

One row per follow-up interval and patient group: every patient, those
with the event and those censored. A patient with no event status counts
among all patients only, and the report says how many there are.
Quartiles are SAS `QNTLDEF=5`, as `proc_means()` computes them.
Suspicious rows have missing event status or at least one missing,
negative or zero interval. The local review prints at most
`MAX_REVIEW_ROWS` of them, in source order, with only the selected
fields. Identifiers stay out until you select one; check the output
before sharing a report that contains an identifier.

Code

``` r
# The checks are hvtiRutilities::followup_check(), the function the EDA report
# calls too, so the two reports cannot disagree. It checks every choice above
# before computing anything, and names every missing column at once.
fc <- hvtiRutilities::followup_check(d, event = EVENT, followup = FOLLOWUP,
                                     identifier = IDENTIFIER, max_rows = MAX_REVIEW_ROWS)
cohort_counts <- fc$cohort
review_rows <- fc$review
# followup_check() returns five one-row tables: the group counts, the interval
# checks for all patients, and one proc_means() row per group. This is them as
# one table, a row per interval and group. The counts are each group's n, the
# negative and zero checks are counted within each group, and the summaries are
# proc_means()'s alone, so there is one quantile definition, not two. dp-eda
# carries the same function; test-dp-eda.R keeps the two from drifting.
.followup_table <- function(fc, d, event) {
  ev <- d[[event]]
  groups <- c(full = "All patients", event = "Event", censored = "Censored")
  rows <- lapply(names(groups), function(g) {
    m <- fc$means[[g]]
    keep <- switch(g, full = rep(TRUE, nrow(d)), event = !is.na(ev) & ev == 1, censored = !is.na(ev) & ev == 0)
    count <- function(test) vapply(m$variable, function(v) sum(test(d[[v]][keep]), na.rm = TRUE), integer(1L))
    data.frame(interval = m$variable, patients = groups[[g]], n = m$n, missing = m$nmiss,
               negative = count(function(x) x < 0), zero = count(function(x) x == 0),
               mean = m$mean, sd = m$std, min = m$min, p25 = m$p25, median = m$median,
               p75 = m$p75, max = m$max, row.names = NULL)
  })
  out <- do.call(rbind, rows)
  out[order(match(out$interval, unique(out$interval))), , drop = FALSE]
}
followup_table <- .followup_table(fc, d, EVENT)
```

Code

``` r
knitr::kable(followup_table, row.names = FALSE, digits = 3)
```

| interval | patients | n | missing | negative | zero | mean | sd | min | p25 | median | p75 | max |
|:---|:---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| iv_dead | All patients | 800 | 0 | 0 | 0 | 9.964 | 8.510 | 0.000 | 3.060 | 7.614 | 14.732 | 35.696 |
| iv_dead | Event | 443 | 0 | 0 | 0 | 7.056 | 6.465 | 0.000 | 1.866 | 5.012 | 10.992 | 27.287 |
| iv_dead | Censored | 357 | 0 | 0 | 0 | 13.573 | 9.331 | 0.021 | 5.769 | 11.190 | 20.318 | 35.696 |

Table 2: Follow-up by interval and patient group: missing, negative and
zero values, and the distribution (years)

Code

``` r
# unnumbered: two sentences, printed only when they have something to say
if (cohort_counts$missing_event > 0L) {
  cat(cohort_counts$missing_event, " patient(s) have no event status, so they count among all patients ",
      "but neither the event nor the censored group.\n\n", sep = "")
}
.n_suspicious <- attr(fc, "n_suspicious")
if (.n_suspicious == 0L) {
  cat("No suspicious rows: every patient has an event status, and every interval is present and positive.\n\n")
} else if (.n_suspicious > nrow(review_rows)) {
  cat(.n_suspicious, " suspicious rows; the table shows the first ", nrow(review_rows), ".\n\n", sep = "")
}
```

No suspicious rows: every patient has an event status, and every
interval is present and positive.

The migration report preserves legacy sort orders, date arithmetic and
includes for review; none establishes an equivalent follow-up definition
by itself.

## Operation years and the close date

Code

``` r
# unnumbered: computes the follow-up window; the table chunk below shows it
# hvtiPlotR::hv_followup_panels() checks every panel and event against the data,
# names every missing column at once, refuses a name used twice and the
# wrong-origin mistake, and works out the window the panels share: from
# 1 January of ORIGIN_YEAR, where hv_followup() draws its diagonal, to the last
# operation. The EDA report calls the same function, so its panels are these.
# A refusal does not stop a draft: the tables above are the follow-up check and
# do not depend on the figure, so the refusal is reported where the figure would
# be, and the render carries on. It is also raised as a warning, so a console
# render says so too.
panel_counts <- list()
fp <- tryCatch(
  hvtiPlotR::hv_followup_panels(d, opyrs_col = OPYRS, origin_year = ORIGIN_YEAR,
                                panels = PANELS, events = EVENTS, close_date = CLOSE_DATE),
  error = function(e) e
)
figure_drawn <- !inherits(fp, "error")
if (figure_drawn) {
  close_date <- fp$meta$close_date
  # Name the edit point a reader can find in this file, not the function's argument.
  close_source <- if (is.null(CLOSE_DATE)) fp$meta$close_source else "set in CLOSE_DATE"
} else {
  # A final render (render_job(final = TRUE), which sets HVTI_TEMPLATE_STRICT)
  # is the accepted result, and an accepted follow-up report has its figure.
  if (!tolower(Sys.getenv("HVTI_TEMPLATE_STRICT")) %in% c("", "0", "false", "no")) {
    stop("The goodness-of-follow-up figure was not drawn: ", conditionMessage(fp),
         "\nThis render stops because HVTI_TEMPLATE_STRICT is set; a draft render reports it and carries on.",
         call. = FALSE)
  }
  warning("The goodness-of-follow-up figure was not drawn: ", conditionMessage(fp), call. = FALSE)
  close_date <- NA
  close_source <- paste("not drawn:", conditionMessage(fp))
}
```

Code

``` r
# Operations before ORIGIN_YEAR are drawn, left of the diagonal, by an
# hvtiPlotR that counts them in meta$n_opyrs_negative; this row says how many,
# because a build counting from a later origin is a problem to fix there. An
# older hvtiPlotR refuses them instead, so the field is absent and so is the row.
.before <- fp$meta$n_opyrs_negative
knitr::kable(data.frame(
  quantity = c("patients", "operation year missing", if (!is.null(.before)) "operation before origin",
               "first operation", "last operation", "close date", "close date is"),
  value = c(fp$meta$n_obs, fp$meta$n_opyrs_missing, .before, format(fp$meta$first_operation),
            format(fp$meta$study_end), format(close_date), close_source)
))
```

| quantity | value |
|:---|:---|
| patients | 800 |
| operation year missing | 0 |
| first operation | 1990-01-25 |
| last operation | 2024-12-10 |
| close date | 2025-12-31 |
| close date is | estimated: the latest operation plus follow-up in the data |

Table 3: Operation years and the close date

## Goodness of follow-up

A point below the diagonal is follow-up short of what the close date
allows. A dead patient’s point is where the death was recorded, so it is
expected below the line; it is the **blue** points drifting below it
that need an explanation.

Code

``` r
# unnumbered: each child chunk below carries its own label and caption
# This document sits in descriptive/ and its figures are written to graphs/
# through set_path(), so the image link is the figure's path relative to this
# document, worked out at render time, as dp-eda's is.
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
if (!figure_drawn) {
  cat("\n::: {.callout-warning title=\"The figure was not drawn\"}\n",
      conditionMessage(fp), "\n\nThe tables above do not depend on it. Fix the choice the ",
      "message names, usually `OPYRS` or `ORIGIN_YEAR`, and render again.\n:::\n\n", sep = "")
}
figure_link <- function(file) {
  xfun::relative_path(file, if (exists(".in") && !is.null(.in)) dirname(.in) else getwd(), error = FALSE)
}
if (exists("COLOURS", inherits = FALSE)) stop("COLOURS is now COLORS: rename it in edit-study-choices ",
                                              "(study-choices in a job made before that rename).", call. = FALSE)
if (!is.null(COLORS) && !(is.character(COLORS) && !anyNA(COLORS) && length(COLORS) == 3L &&
                            setequal(names(COLORS), c("alive", "dead", "event")))) {
  stop("COLORS must be NULL or name exactly alive, dead and event.", call. = FALSE)
}
# Dead or Death is the event and Alive or No event the censored level, so a
# non-fatal event takes the house rule's next color, green.
status_colors <- function(levels) {
  if (is.null(COLORS)) return(scale_color_hv(event = c("Dead", "Death"), censored = c("Alive", "No event")))
  keys <- if (length(levels) == 2L) c("alive", "dead") else c("alive", "event", "dead")
  scale_color_manual(values = stats::setNames(COLORS[keys], levels))
}
plots <- if (figure_drawn) plot(fp, alpha = ALPHA) else list()
for (i in seq_len(if (figure_drawn) nrow(fp$data) else 0L)) {
  row <- fp$data[i, ]
  nm <- row$panel
  panel_counts[[nm]] <- list(drawn = row$n_drawn, excluded = row$n_excluded)
  cat("\n### ", row$title, "\n\n", row$n_drawn, " patients drawn; ", row$n_excluded,
      " missing a column this panel needs.\n\n", sep = "")
  if (row$type == "followup") {
    p <- plots[[nm]] +
      status_colors(c("Alive", "Dead")) +
      scale_shape_manual(values = c(Alive = 1, Dead = 4))
  } else {
    levels <- c("No event", row$title, "Death")
    p <- plots[[nm]] +
      status_colors(levels) +
      scale_shape_manual(values = stats::setNames(c(1, 2, 4), levels))
  }
  p <- p + labs(x = "Year of operation", y = "Follow-up (years)", color = NULL, shape = NULL) +
    theme_hv_manuscript()
  file <- set_path("graphs", paste0("dc-gfup-", nm, ".png"))
  ggplot2::ggsave(file, p, width = 7, height = 6, units = "in", dpi = 150)
  .link <- figure_link(file)
  .child(paste("fig gfup", nm), paste0("Follow-up against year of operation, ", row$title),
         "knitr::include_graphics(.link, error = FALSE)")
}
```

### All deaths

800 patients drawn; 0 missing a column this panel needs.

Code

``` r
knitr::include_graphics(.link, error = FALSE)
```

![](assets/8012782ffc4d393890acb06147148d38.png)

Figure 1: Follow-up against year of operation, All deaths

## Event-coding consistency

Code

``` r
# unnumbered: each child chunk below carries its own label and caption
unknown_checks <- setdiff(unlist(CHECKS, use.names = FALSE), names(d))
if (length(unknown_checks)) {
  stop("Unknown event-check column(s): ", paste(unknown_checks, collapse = ", "), call. = FALSE)
}
.fence <- strrep("`", 3)
.seen <- new.env()
.child <- function(kind, key, caption, code) {
  label <- paste(kind, "checks", gsub("(^-+|-+$)", "", gsub("[^a-z0-9]+", "-", tolower(key))), sep = "-")
  if (!is.null(.seen[[label]])) stop("Two outputs would share the label ", label, ".", call. = FALSE)
  .seen[[label]] <- TRUE
  cat(knitr::knit_child(text = c(paste0(.fence, "{r}"), paste0("#| label: ", label),
                                 paste0("#| ", kind, "-cap: ", encodeString(caption, quote = "\"")), code, .fence),
                        envir = parent.frame(), quiet = TRUE), sep = "\n")
}
for (cc in CHECKS) {
  .check <- as.data.frame(table(d[cc], useNA = "ifany"))
  .child("tbl", paste(cc, collapse = " by "), paste(cc, collapse = " by "), "knitr::kable(.check)")
  cat("\n")
}
```

Code

``` r
knitr::kable(.check)
```

| dead | reop | Freq |
|:-----|:-----|-----:|
| 0    | 0    |  229 |
| 1    | 0    |  363 |
| 0    | 1    |  128 |
| 1    | 1    |   80 |

Table 4: dead by reop
