# Goodness of follow-up, graph

# Goodness of follow-up, graph

Replaces `graphs/dp.gfup`: list the follow-up panels it draws.

**Deprecated.** `dp-gfup` is deprecated in favor of `dc-gfup`, and will
be removed in a later release. For the same figure, start a `dc-gfup`
job with `add_job("dc-gfup", subject = "cohort", type = "eda")`: it
draws these panels with the same choices and the same call to
`hv_followup_panels()`, beside the follow-up tables, saved as
`dc-gfup-*.png` rather than `dp-gfup-*.png`.

A `dp-gfup` job draws the goodness-of-follow-up figure. Every patient is
one point: the year of operation across, the follow-up recorded for them
up, blue while alive and red once dead. The dashed diagonal is the
follow-up a patient **could** have had, from their operation to the
close date. A censored patient far below the diagonal is someone whose
follow-up stopped early, and a band of them is a follow-up problem to
settle before any time-related analysis.

The engine is `hvtiPlotR::hv_followup_panels()`, which the EDA report
also calls, so its follow-up panels are these. The tables that go with
this figure are the `dc-gfup` job, which reads the same data and rows.

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

Set the values in this chunk before rendering. Left as they are, they
draw the all-deaths panel for the whole study dataset, so the job runs
before it is tuned.

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

# Read the same data and rows as this study's dc-gfup job, so the figure and
# the tables describe the same patients.

# Demo: the years-since-origin interval to the operation, and that origin. The
# origin differs between studies, and a wrong one slides every point along the
# x-axis without any other symptom, which is why the operation years are
# checked and printed below.
OPYRS <- "iv_opyrs"
ORIGIN_YEAR <- 1990

# Demo: the close date of follow-up, as.Date("YYYY-MM-DD"). NULL estimates it
# as the latest operation date plus follow-up in the data, which is the date
# follow-up is known to reach, not the date it was closed; the report says
# which one it drew.
CLOSE_DATE <- as.Date("2025-12-31")

# Demo: one entry per death panel. `status` is the 1/0 death indicator and
# `time` its follow-up in years. A study that ascertains deaths two ways draws
# both, for example
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
EVENTS <- list(reop = list(event = "reop", time = "iv_reop", death = "dead", death_time = "iv_dead", label = "Reoperation"))

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

## Operation years and the close date

Code

``` r
# unnumbered: computes the follow-up window; the table chunk below shows it
# hvtiPlotR::hv_followup_panels() checks every panel and event against the data,
# names every missing column at once, refuses a name used twice and the
# wrong-origin mistake, and works out the window the panels share: from
# 1 January of ORIGIN_YEAR, where hv_followup() draws its diagonal, to the last
# operation. The EDA report calls the same function, so its panels are these.
fp <- hvtiPlotR::hv_followup_panels(d, opyrs_col = OPYRS, origin_year = ORIGIN_YEAR,
                                    panels = PANELS, events = EVENTS, close_date = CLOSE_DATE)
close_date <- fp$meta$close_date
# Name the edit point a reader can find in this file, not the function's argument.
close_source <- if (is.null(CLOSE_DATE)) fp$meta$close_source else "set in CLOSE_DATE"
```

Code

``` r
knitr::kable(data.frame(
  quantity = c("patients", "operation year missing", "first operation", "last operation",
               "close date", "close date is"),
  value = c(fp$meta$n_obs, fp$meta$n_opyrs_missing, format(fp$meta$first_operation),
            format(fp$meta$study_end), format(close_date), close_source)
))
```

| quantity               | value             |
|:-----------------------|:------------------|
| patients               | 800               |
| operation year missing | 0                 |
| first operation        | 1990-01-25        |
| last operation         | 2024-12-10        |
| close date             | 2025-12-31        |
| close date is          | set in CLOSE_DATE |

Table 2: Operation years and the close date

## Figures

A point below the diagonal is follow-up short of what the close date
allows. A dead patient’s point is where the death was recorded, so it is
expected below the line; it is the **blue** points drifting below it
that need an explanation.

Code

``` r
# unnumbered: each child chunk below carries its own label and caption
# The image link is relative to THIS document, which always sits in graphs/, so
# it is <set>/<file> whichever directory the render executes from. The file
# itself is written through set_path(), which resolves from the project root.
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
show_figure <- function(p, fname, title, nm) {
  p <- p + labs(x = "Year of operation", y = "Follow-up (years)", color = NULL, shape = NULL) +
    theme_hv_manuscript()
  png(set_path("graphs", fname), width = 7, height = 6, units = "in", res = 150)
  print(p)
  invisible(dev.off())
  .link <- file.path(paste0(SUBJECT, "-", TYPE), fname)
  .child(paste("fig gfup", nm), paste0("Follow-up against year of operation, ", title),
         "knitr::include_graphics(.link, error = FALSE)")
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
plots <- plot(fp, alpha = ALPHA)
panel_counts <- list()
for (i in seq_len(nrow(fp$data))) {
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
  show_figure(p, paste0("dp-gfup-", nm, ".png"), row$title, nm)
}
```

### All deaths

800 patients drawn; 0 missing a column this panel needs.

Code

``` r
knitr::include_graphics(.link, error = FALSE)
```

![](assets/e773382390e5c09bf10d2fe7199730bc.png)

Figure 1: Follow-up against year of operation, All deaths

### Reoperation

800 patients drawn; 0 missing a column this panel needs.

Code

``` r
knitr::include_graphics(.link, error = FALSE)
```

![](assets/541cd30ea2adc18cbfbfbff99752322e.png)

Figure 2: Follow-up against year of operation, Reoperation
