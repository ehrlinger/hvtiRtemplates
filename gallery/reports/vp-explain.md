# VarPro: explain

# VarPro: explain

Published

2026-10-23 13:44

Explains the `vp-fit` screen in this set: survival at five years along
each selected predictor.

Draws VarPro’s partial dependence for the variables the `vp-fit` job in
this set selected.

A `vp-explain` job never fits VarPro. It reads `vp.rds`, which the fit
job writes, so the plots describe exactly the screen that report judged.
A variable the screen did not test is never drawn: its partial would
rest on almost no rules. The partials are the expensive step and are
cached on their own.

This template is **in flight**, with `vp-fit`.

Code

``` r
SUBJECT <- "dead"
TYPE    <- "vp"
.in <- knitr::current_input(dir = TRUE)
suppressPackageStartupMessages({
  library(varPro)
  library(ggRandomForests)
  library(hvtiRutilities)
})
# One thread, so a partial reproduces from machine to machine: each point is a
# prediction from VarPro's forests. mc.cores does the same for varPro's own
# workers, which rf.cores does not reach.
options(rf.cores = 1L, mc.cores = 1L)
# The versions this template was verified against on 2026-10-21.
if (utils::packageVersion("randomForestSRC") < "3.7.0") {
  stop("This job needs randomForestSRC >= 3.7.0; ", utils::packageVersion("randomForestSRC"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
if (utils::packageVersion("varPro") < "3.2.0") {
  stop("This job needs varPro >= 3.2.0; ", utils::packageVersion("varPro"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
if (utils::packageVersion("ggRandomForests") < "4.0.0") {
  stop("This job needs ggRandomForests >= 4.0.0; ", utils::packageVersion("ggRandomForests"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
# The study root is the nearest directory above this file holding _study.yml,
# so the job renders the same from the Render button, quarto render, or
# render_job(), at any depth, with no path in this document to edit.
# Without the guard in .job_setup(), an unedited job renders green over a
# meaningless analysis. Here that is partials at a placeholder survival
# horizon, in units the study's follow-up may not use, which look exactly like
# a result.
# To render a job you have not finished, leave a chunk out with the chunk
# option skip, giving the reason in quotes, or call hvtiRtemplates::stop_here()
# in a chunk to leave out everything below it. ?stop_here has more.
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

# `vp-explain` reads the screen `vp-fit` wrote in this same set, and caches its
# own work beside it.
# The draft banners, if any, and the box under the title, after all the code above.
.job$notice
```

**final** · data: see About this run · rendered by gallery on gallery ·
hvtiRtemplates 1.5.0

## Study choices

Edit these values for this study before rendering. The outcome and
candidates are not here: they come from the screen.

Code

``` r
# Demo: the screen's selection is used; set any of these only to confirm it.
# NULL takes the value the fit job used.
WHERE <- NULL
ID <- NULL
KEY <- NULL

# Demo: or name the variables yourself. NULL takes the screen's selected set.
# A variable the screen did not test is left out either way, and named below.
PARTIAL_VARS <- NULL

# Demo: for a survival screen, the scale and the horizon of the partials.
# "surv" draws survival at HORIZON; HORIZON is in the units of the fit job's
# time variable, so a screen fit in years takes HORIZON <- 5 for five years and
# one fit in days takes 1826. A horizon past the longest follow-up stops the
# render rather than draw a flat curve. Both are ignored for classification or
# regression.
SCALE <- "surv"
HORIZON <- 5

# Demo: the seed for the partials. It is part of their cache key.
SEED <- 2026

# Set TRUE after changing a choice above. A cache whose inputs changed stops the
# render instead of returning the old result; TRUE recomputes only the caches
# that are out of date.
REFIT <- FALSE

# Each figure is saved to graphs/ as a PNG (for Word), and a PDF and a TIFF (for the publisher).
# SAVE_FIGURES <- FALSE saves none; FIGURES keeps only the figures whose names
# start with one of its entries, e.g. FIGURES <- c("vp-explain-dependence"). The names are the
# file names, listed for each template in the templates README.
SAVE_FIGURES <- TRUE
FIGURES <- NULL
```

## The screen

Code

``` r
.handoff <- set_path("estimates", "vp.rds")
if (!file.exists(.handoff)) {
  stop("No screen at ", .handoff, ". Render the vp-fit job in this set first; ",
       "this job explains that screen and never fits its own.", call. = FALSE)
}
.cfg <- study_config(start = .root)
.vp_read <- hvtiRtemplates:::.read_handoff(.handoff, "screen", .cfg, "the vp-fit job")
fit <- .vp_read$value$fit
cov <- .vp_read$value$coverage
selected <- .vp_read$value$selected
.provenance_data <- .vp_read$lineage$data
.provenance_artifacts <- c(.vp_read$lineage$artifacts, list(.vp_read$record))
CACHE_DIR <- dirname(.handoff)
```

Code

``` r
# This job reads no data: the screen carries its rows. The fit job recorded how
# it chose them, and a setting above that differs from the fit's stops here.
.sel <- hvtiRtemplates:::.read_upstream_job_data(
  .cfg, .vp_read$lineage, list(where = WHERE, id = ID, key = KEY), read = FALSE, source = "vp.rds"
)$selection
knitr::kable(data.frame(step = c("ID", "KEY", "WHERE", "Rows"),
                        value = c(.sel$id, paste(.sel$key, collapse = ", "),
                                  if (length(.sel$where_shown)) paste(.sel$where_shown, collapse = "; ") else "none",
                                  .sel$rows)),
             col.names = c("Data", ""))
```

| Data  |            |
|:------|:-----------|
| ID    | patient_id |
| KEY   | patient_id |
| WHERE | none       |
| Rows  | 800        |

Table 1: The data the fit job read

Code

``` r
.real <- cov$variable[!cov$noise]
.tested <- cov$variable[!cov$noise & cov$tested]
if (is.null(PARTIAL_VARS)) {
  sel <- selected
} else {
  # A misspelt name would otherwise fail deep inside the partial call.
  .unknown <- setdiff(PARTIAL_VARS, .real)
  if (length(.unknown)) {
    stop("PARTIAL_VARS names variable(s) the screen was not given: ", paste(.unknown, collapse = ", "), call. = FALSE)
  }
  sel <- PARTIAL_VARS
}
.untested <- setdiff(sel, .tested)
if (length(.untested)) {
  cat("Not drawn, because the screen did not test them: ", paste(.untested, collapse = ", "), "\n", sep = "")
  sel <- setdiff(sel, .untested)
}
if (!length(sel)) {
  stop("No tested variable to draw. The screen selected none; name tested variables in PARTIAL_VARS.", call. = FALSE)
}
# Each figure is drawn a page at a time, panels in a grid no larger than the
# printed page (6.5 by 9 in), and each page is a child chunk of its own so
# Quarto numbers it.
.fence <- strrep("`", 3)
.page_child <- function(kind, i, pages, vars, caption) {
  page <- pages[[i]]
  if (length(pages) > 1L) {
    caption <- paste0(caption, " Page ", i, " of ", length(pages), ": ",
                      paste(vars[page$index], collapse = ", "), ".")
  }
  code <- c(paste0(.fence, "{r}"), paste0("#| label: fig-", kind, "-", i),
            paste0("#| fig-cap: ", encodeString(caption, quote = "\"")),
            sprintf("#| fig-width: %g", hvtiRtemplates:::.report_size(page$width)),
            sprintf("#| fig-height: %g", hvtiRtemplates:::.report_size(page$height)), ".fig", .fence)
  cat(knitr::knit_child(text = code, envir = parent.frame(), quiet = TRUE), sep = "\n")
  cat("\n")
}
```

## Dependence

Code

``` r
# unnumbered: each page below is a child chunk with its own label and caption
.survival <- identical(fit$family, "surv")
if (.survival) {
  # y.org holds the time and event as the fit was given them; y is varPro's
  # transformed response and is not in follow-up units.
  .longest <- max(fit$y.org[[1L]])
  if (HORIZON > .longest) {
    stop("HORIZON is ", HORIZON, " but the longest follow-up in the screen is ", signif(.longest, 4),
         ", in the units of the fit job's time variable. Choose a horizon inside follow-up.", call. = FALSE)
  }
}
pv <- cache_fit("vp-partial",
                gg_partial_varpro(object = fit, xvar.names = sel,
                                  scale = if (.survival) SCALE else "auto", time = if (.survival) HORIZON else NULL),
                seed = SEED, dir = CACHE_DIR, refit = REFIT)
# The manuscript theme hides the legend and its title, and the caption reads the line types from the legend.
.cap <- paste("VarPro partial dependence on each drawn predictor, one panel per predictor. For a",
              "continuous predictor a black solid line marks the nonparametric partial effect and a black",
              "dashed line the parametric one, as in the legend; for a categorical predictor black box",
              "plots show the spread of the partial effect at each level.")
# Free size, paged: one facet per predictor, two by two.
.pages <- hvtiRtemplates:::.figure_pages(length(sel), panel_width = 3.25, panel_height = 3, page_height = 6)
for (.i in seq_along(.pages)) {
  .vars <- sel[.pages[[.i]]$index]
  .fig <- plot(hvtiRtemplates:::.partial_subset(pv, .vars)) &
    hvtiPlotR::theme_hv_manuscript(base_size = 12, legend.position = "top", legend.title = ggplot2::element_text())
  save_figure(.fig, sprintf("vp-explain-dependence-varpro-page-%02d", .i),
              width = .pages[[.i]]$width, height = .pages[[.i]]$height)
  .page_child("dependence-varpro", .i, .pages, sel, .cap)
}
```

    Warning: Removed 280 rows containing non-finite outside the scale range
    (`stat_boxplot()`).
    Removed 280 rows containing non-finite outside the scale range
    (`stat_boxplot()`).
    Removed 280 rows containing non-finite outside the scale range
    (`stat_boxplot()`).

Code

``` r
.fig
```

    Warning: Removed 280 rows containing non-finite outside the scale range
    (`stat_boxplot()`).

![](assets/5a356a2ddf7d25b2b659333b823c1e33.png)

Figure 1: VarPro partial dependence on each drawn predictor, one panel
per predictor. For a continuous predictor a black solid line marks the
nonparametric partial effect and a black dashed line the parametric one,
as in the legend; for a categorical predictor black box plots show the
spread of the partial effect at each level.

## About this run

| Group | Item | Value |
|:---|:---|:---|
| Run | Started | 2026-10-23 13:44:36 EDT |
|  | Ended | 2026-10-23 13:44:41 EDT |
|  | Duration | 5 s |
|  | Status | final |
|  | Rendered by | gallery |
|  | Host | gallery |
| Job | File | vp.explain.dead.vp.qmd |
|  | Template | vp.explain |
|  | Subject | dead |
|  | Type | vp |
|  | hvtiRtemplates | 1.5.0 |
| Dataset `built` | Version file | built_20261023.parquet |
|  | Registered | 2026-10-23 |
|  | Source file | built.rds |
|  | sha256 | b236a472f1f3 |
|  | Manifest | current |
| Upstream | Handoff | `dead-vp/vp.rds` (screen), rendered 2026-10-23 13:43:40 -0400, data built_20261023.parquet |
| Reproducibility | Seed | 2026 |
|  | renv | not active |
|  | renv.lock sha256 | d09f96b6cd21 |
