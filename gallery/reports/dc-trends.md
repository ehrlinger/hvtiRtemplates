# Trends over operation year

# Trends over operation year

Published

2026-10-20 15:01

A `dc-trends` job shows how the cohort changed over the years of
operation: the share of patients with a characteristic, or the level of
a measurement, year by year, with a smooth through it. It **describes**
the cohort. It fits no model and tests nothing, so a trend here is a
prompt for an analysis, not a result.

The engine is `hvtiPlotR::hv_trends()`. It takes one row per patient and
computes the per-year summary itself, so this job never aggregates by
hand. The `group_by()`/`summarize()` blocks and the per-series
`smooth.spline()` calls that older trends jobs carry are exactly what it
replaces.

Two neighbors are **not** this job. Procedure volume per year is
`dp-procs`, and the distribution of a single variable is `dc-variable`.

Code

``` r
# unnumbered: setup, and the box under the title
SUBJECT <- "cohort"
TYPE    <- "eda"
.in <- knitr::current_input(dir = TRUE)
suppressPackageStartupMessages({
  library(hvtiRutilities)
  library(hvtiPlotR)
  library(ggplot2)
})

# 2.7.7, not 2.7.6. This job reports how many rows each figure could not draw,
# and hv_trends() only counts them (meta$n_missing) from part-way through 2.7.6:
# the field arrived without a version bump, so a package reporting 2.7.6 may or
# may not have it. 2.7.7 is the first version that certainly does.
if (utils::packageVersion("hvtiPlotR") < "2.7.7") {
  stop("This job needs hvtiPlotR >= 2.7.7; ", utils::packageVersion("hvtiPlotR"),
       " is installed. Update it, then re-render.", call. = FALSE)
}
# The study root is the nearest directory above this file holding _study.yml,
# so the job renders the same from the Render button, quarto render, or
# render_job(), at any depth, with no path in this document to edit.
# Without the guard in .job_setup(), an unedited trends job would render green
# over the placeholder columns and the placeholder year origin below.
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

**final** · data `built` `built_20261020.parquet`, registered 2026-10-20
· rendered by gallery on gallery · hvtiRtemplates 1.4.1

## Study choices

Set the values in this chunk before rendering.

Code

``` r
# Demo: the registered dataset this job reads ("built" is the study dataset).
# MIGRATE-BEGIN: dc-trends-data
DATASET <- "built"
# MIGRATE-END: dc-trends-data

# Demo: an hvtiRdatabuild analysis set, or NULL to read the whole dataset.
ANALYSIS_SET <- NULL

# Demo: rows to keep, dplyr::filter() style, or NULL to keep every row:
#   WHERE <- quote(age >= 18)
#   WHERE <- rlang::exprs(age >= 18, hx_chf == 1)
# WHERE runs as the data are read, before `year` is derived below, so filter on
# the date column rather than on `year`.
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
#     breaks it. A job that counts or models
#     patients, one row each, needs REDUCE: NULL would count every record.
#   JOIN_KEY: overrides the joined dataset's registered key.
JOIN <- NULL
JOIN_VARS <- NULL
REDUCE <- NULL
JOIN_KEY <- NULL

# Demo: one entry per figure. `cols` are the columns drawn together: several
# columns become several series in one figure, which is how a set of 0/1
# indicators such as NYHA class I to IV is shown. `kind` says how to read them:
#   "percent"     0/1 or logical, drawn as the percent of patients with it
#   "continuous"  a measurement, drawn on its own scale
# `labels` names the series in the legend (default: the column names). Fixing
# `ylim` and `ybreaks` keeps figures for different subgroups comparable; either
# may be set alone, and `ylim` zooms without dropping any patient.
# `summary` is the per-year point drawn under the smooth. Percent trends must
# use "mean" (the default); continuous trends may use "mean" or "median".
# MIGRATE-BEGIN: dc-trends-trends
TRENDS <- list(
  chf = list(cols = "hx_chf", kind = "percent", labels = "Heart failure",
             ylab = "Patients (%)", ylim = c(0, 100), ybreaks = seq(0, 100, 20)),
  lvmass = list(cols = "plvmassi", kind = "continuous", labels = "LV mass index",
                ylab = "LV mass index", ylim = NULL, ybreaks = NULL)
)
# MIGRATE-END: dc-trends-trends

# Demo: optional. x-axis breaks shared by every figure, e.g. seq(1985, 2025, 5).
# NULL lets ggplot choose.
# MIGRATE-BEGIN: dc-trends-xbreaks
XBREAKS <- NULL
# MIGRATE-END: dc-trends-xbreaks

# Demo: optional. Each entry is a filter, given as a function of the data that
# returns TRUE for the rows to keep. Every trend is drawn once per entry with
# the same axes, so the figures can be read side by side. The default draws the
# whole cohort only. A second entry might be
#   complex = function(d) d$complex == 1
# MIGRATE-BEGIN: dc-trends-subgroups
SUBGROUPS <- list(all = function(d) rep(TRUE, nrow(d)), diabetic = function(d) d$hx_dm == 1)
# MIGRATE-END: dc-trends-subgroups

# Each figure is saved to graphs/ as a PNG (for Word), and a PDF and a TIFF (for the publisher).
# SAVE_FIGURES <- FALSE saves none; FIGURES keeps only the figures whose names
# start with one of its entries, e.g. FIGURES <- c("hp-survival"). The names are the
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
                                          reduce = REDUCE, join_key = JOIN_KEY)
d <- job_data$data
.provenance_data <- c(if (exists(".provenance_data")) .provenance_data else list(), list(job_data$provenance),
                      if (!is.null(job_data$provenance_join)) list(job_data$provenance_join))
knitr::kable(job_data$record, col.names = c("Data", ""))
```

| Data                |                                          |
|:--------------------|:-----------------------------------------|
| Source              | dataset `built` (built_20261020.parquet) |
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
# Demo: the calendar year of operation, as a WHOLE year. hv_trends puts one
# summary point at every distinct value of x, so x must be the year itself.
# Years since an origin are an interval, fractional like every iv_ column, and
# origin plus a fractional interval would give one "annual" point per patient.
# Older jobs kept the two apart for this reason: they smoothed on the interval
# and averaged on an integer year column. If the dataset carries the calendar
# year, use that column; otherwise take the whole years of the interval and add
# the origin. The origin differs between studies, 1985 in one and 2000 in
# another, and a wrong one moves every figure along the x-axis, which is why
# the range is checked and printed below.
# MIGRATE-BEGIN: dc-trends-year
d$year <- floor(d$iv_opyrs) + 1990
# MIGRATE-END: dc-trends-year
```

Code

``` r
if (!is.numeric(d$year)) {
  stop("`year` is not numeric (", class(d$year)[1L], "). Build it from a ",
       "numeric column, such as years since an origin plus that origin.",
       call. = FALSE)
}
if (all(is.na(d$year))) {
  stop("`year` is missing for every patient, so there is nothing to plot. ",
       "Check the column it is built from.", call. = FALSE)
}
if (any(d$year != round(d$year), na.rm = TRUE)) {
  stop("`year` must be a whole calendar year. hv_trends draws one summary ",
       "point per distinct value, so a fractional year draws one point per ",
       "patient. Use floor() on a years-since-origin interval, or a ",
       "calendar-year column.", call. = FALSE)
}
# A plausible window, not a precise one. Its job is to catch the wrong-origin
# mistake, which lands decades or centuries out, not to police real data.
.this_year <- as.integer(format(Sys.Date(), "%Y"))
.out <- which(d$year < 1900 | d$year > .this_year + 1)
if (length(.out)) {
  stop(length(.out), " patient(s) have an operation year outside 1900 to ",
       .this_year + 1, " (for example ", d$year[.out[1L]], "). Check the ",
       "origin added to the years-since-origin column.", call. = FALSE)
}

knitr::kable(data.frame(
  quantity = c("patients", "year missing", "first year", "last year"),
  value    = c(nrow(d), sum(is.na(d$year)),
               min(d$year, na.rm = TRUE), max(d$year, na.rm = TRUE))
))
```

| quantity     | value |
|:-------------|------:|
| patients     |   800 |
| year missing |     0 |
| first year   |  1990 |
| last year    |  2024 |

Table 2: Operation years: patients, missing years, and the first and
last year

Code

``` r
# unnumbered: defines helpers only
# One row per patient per series: the shape hv_trends() takes. Several columns
# become several series through `series`, which hv_trends() groups on.
trend_long <- function(d, spec) {
  absent <- setdiff(spec$cols, names(d))
  if (length(absent)) {
    stop("TRENDS names column(s) not in the data: ",
         paste(absent, collapse = ", "), call. = FALSE)
  }
  labels <- if (is.null(spec$labels)) spec$cols else spec$labels
  if (length(labels) != length(spec$cols)) {
    stop("TRENDS entry has ", length(spec$cols), " column(s) but ",
         length(labels), " label(s).", call. = FALSE)
  }
  if (!spec$kind %in% c("percent", "continuous")) {
    stop("TRENDS `kind` must be \"percent\" or \"continuous\", not \"",
         spec$kind, "\".", call. = FALSE)
  }
  summary_fn <- if (is.null(spec$summary)) "mean" else spec$summary
  if (identical(spec$kind, "percent") && !identical(summary_fn, "mean")) {
    stop("A percent trend must use summary = \"mean\"; a median of a 0/1 ",
         "indicator is not a prevalence.", call. = FALSE)
  }
  parts <- lapply(seq_along(spec$cols), function(i) {
    v <- d[[spec$cols[i]]]
    if (identical(spec$kind, "percent")) {
      if (is.logical(v)) v <- as.numeric(v)
      if (!is.numeric(v)) {
        stop("`", spec$cols[i], "` is kind \"percent\" but is ",
             class(v)[1L], ". A percent column must be numeric or logical ",
             "and hold only 0/1 values.", call. = FALSE)
      }
      # A 1/2 or 0/1/9 code times 100 draws a plausible and wrong figure, so
      # anything other than 0/1 stops here instead of being scaled.
      bad <- setdiff(unique(v[!is.na(v)]), c(0, 1))
      if (length(bad)) {
        stop("`", spec$cols[i], "` is kind \"percent\" but holds ",
             paste(utils::head(bad, 5L), collapse = ", "),
             ". A percent column must be 0/1 or logical.", call. = FALSE)
      }
      v <- 100 * v
    }
    data.frame(year = d$year, value = v, series = labels[i],
               stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, parts)
  out$series <- factor(out$series, levels = labels)
  out
}
```

## Figures

Code

``` r
# unnumbered: each child chunk below carries its own label and caption
# This document sits in descriptive/ and its figures are written to graphs/
# through set_path(), so the image link is the figure's path relative to this
# document, worked out at render time, as dc-gfup's is.
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
figure_link <- function(file) {
  xfun::relative_path(file, if (exists(".in") && !is.null(.in)) dirname(.in) else getwd(), error = FALSE)
}
for (sg in names(SUBGROUPS)) {
  keep <- SUBGROUPS[[sg]](d)
  # One logical per patient, or the filter is wrong. R would silently recycle
  # a length-1 or short vector through d[keep, ] and select the wrong patients,
  # and a filter on a missing column returns logical(0).
  if (!is.logical(keep) || length(keep) != nrow(d)) {
    stop("SUBGROUPS entry `", sg, "` must return one TRUE/FALSE per patient (",
         nrow(d), "); it returned ", length(keep), " value(s) of type ",
         typeof(keep), ".", call. = FALSE)
  }
  keep[is.na(keep)] <- FALSE
  dd <- d[keep, , drop = FALSE]
  if (nrow(dd) == 0L) {
    stop("SUBGROUPS entry `", sg, "` selects no patients.", call. = FALSE)
  }
  cat("\n### ", sg, " (n = ", nrow(dd), ")\n\n", sep = "")
  for (nm in names(TRENDS)) {
    spec <- TRENDS[[nm]]
    tr <- hv_trends(trend_long(dd, spec), x_col = "year", y_col = "value",
                    group_col = if (length(spec$cols) == 1L) NULL else "series",
                    summary_fn = if (is.null(spec$summary)) "mean" else spec$summary)
    # Older jobs dropped incomplete rows with na.omit() and said nothing.
    # hv_trends() counts them, and the count is reported with every figure.
    cat("**", nm, "**: ", tr$meta$n_obs - tr$meta$n_missing, " of ",
        tr$meta$n_obs, " rows drawn; ", tr$meta$n_missing,
        " missing the year or the value.\n\n", sep = "")
    p <- plot(tr) +
      labs(x = "Year of operation", y = spec$ylab, color = NULL, shape = NULL) +
      # The manuscript theme hides the legend; several series need it to be told apart.
      theme_hv_manuscript(base_size = 12, legend.position = "top")
    # Limits through coord_cartesian(), not scale limits. A scale limit DROPS
    # the patients outside it before the smooth is fitted, so the curve would
    # stop passing through the yearly points hv_trends() computed from all of
    # them, and any stretch of the fitted line past the limit would vanish.
    # Breaks and limits are applied independently: either may be set alone.
    if (!is.null(spec$ybreaks)) p <- p + scale_y_continuous(breaks = spec$ybreaks)
    if (!is.null(spec$ylim)) p <- p + coord_cartesian(ylim = spec$ylim)
    if (!is.null(XBREAKS)) p <- p + scale_x_continuous(breaks = XBREAKS)
    fname <- paste0("dc-trends-", nm, "-", sg, ".png")
    file <- save_figure(p, sub("[.]png$", "", fname), linked = TRUE)
    .link <- figure_link(file)
    .child(paste("fig trends", nm, sg),
           paste0("Trend in ", nm, " by year of operation, ", sg, ". Filled circles mark the yearly summary and the ",
                  "solid line a LOESS smooth of the patients; a single series is black circles on a blue line, ",
                  "several get one color and point shape each, as in the legend."),
           "knitr::include_graphics(.link, error = FALSE)")
  }
}
```

### all (n = 800)

**chf**: 800 of 800 rows drawn; 0 missing the year or the value.

Code

``` r
knitr::include_graphics(.link, error = FALSE)
```

![](assets/521ddb55e9b3442fb4681b3a205bf1f9.png)

Figure 1: Trend in chf by year of operation, all. Filled circles mark
the yearly summary and the solid line a LOESS smooth of the patients; a
single series is black circles on a blue line, several get one color and
point shape each, as in the legend.

**lvmass**: 800 of 800 rows drawn; 0 missing the year or the value.

Code

``` r
knitr::include_graphics(.link, error = FALSE)
```

![](assets/d03a93bdd0dc8dbaf76e879dfd34351f.png)

Figure 2: Trend in lvmass by year of operation, all. Filled circles mark
the yearly summary and the solid line a LOESS smooth of the patients; a
single series is black circles on a blue line, several get one color and
point shape each, as in the legend.

### diabetic (n = 175)

**chf**: 175 of 175 rows drawn; 0 missing the year or the value.

Code

``` r
knitr::include_graphics(.link, error = FALSE)
```

![](assets/93f1840446e2638fa2462f7acc5c346b.png)

Figure 3: Trend in chf by year of operation, diabetic. Filled circles
mark the yearly summary and the solid line a LOESS smooth of the
patients; a single series is black circles on a blue line, several get
one color and point shape each, as in the legend.

**lvmass**: 175 of 175 rows drawn; 0 missing the year or the value.

Code

``` r
knitr::include_graphics(.link, error = FALSE)
```

![](assets/9f8ff0bb65dd4dfda0654c35255ef449.png)

Figure 4: Trend in lvmass by year of operation, diabetic. Filled circles
mark the yearly summary and the solid line a LOESS smooth of the
patients; a single series is black circles on a blue line, several get
one color and point shape each, as in the legend.

The smooth is LOESS, `hv_trends()`’s default, with `span = 0.75`. Older
jobs used `smooth.spline(df = 6)`, which is not reproduced: the two
differ at the ends of the year range, where data is thinnest, so compare
against an older figure by its shape and not point by point.
`plot(tr, span = ...)` changes the smoothing.

## About this run

| Group           | Item             | Value                    |
|:----------------|:-----------------|:-------------------------|
| Run             | Started          | 2026-10-20 15:01:50 EDT  |
|                 | Ended            | 2026-10-20 15:01:51 EDT  |
|                 | Duration         | 1 s                      |
|                 | Status           | final                    |
|                 | Rendered by      | gallery                  |
|                 | Host             | gallery                  |
| Job             | File             | dc.trends.cohort.eda.qmd |
|                 | Template         | dc.trends                |
|                 | Subject          | cohort                   |
|                 | Type             | eda                      |
|                 | hvtiRtemplates   | 1.4.1                    |
| Dataset `built` | Version file     | built_20261020.parquet   |
|                 | Registered       | 2026-10-20               |
|                 | Source file      | built.rds                |
|                 | Rows kept        | 800 rows on 800 patients |
|                 | WHERE            | none                     |
|                 | sha256           | 07a531bb5b35             |
|                 | Manifest         | current                  |
| Reproducibility | renv             | not active               |
|                 | renv.lock sha256 | d09f96b6cd21             |
