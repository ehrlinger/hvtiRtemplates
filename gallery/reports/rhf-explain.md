# Random hazard forest: explain

# Random hazard forest: explain

Published

2026-10-27 15:35

Explains the forest the `rhf-fit` job in this set saved: how well it
ranks patients over follow-up, their hazard curves, and which markers
drive it.

Explains the forest the `rhf-fit` job in this set saved.

An `rhf-explain` job never grows a forest. It reads `rhf.rds`, which the
fit job writes, and reports how well the forest separates patients who
have the event from those still at risk, over follow-up; the hazard it
predicts for a sample of patients; and how much each predictor matters,
at several points of follow-up. Each expensive step is cached on its
own. The importance step builds a VarPro cache, `rhf-varpro-cache`,
which later VarPro work on this forest reads instead of building again.

Code

``` r
SUBJECT <- "event"
TYPE    <- "rhf"
.in <- knitr::current_input(dir = TRUE)
suppressPackageStartupMessages({
  library(randomForestRHF)
  library(ggRandomForests)
  library(hvtiRutilities)
})
# One thread, so the VarPro cache reproduces from machine to machine; see rhf-fit.
options(rf.cores = 1L)
# The versions this template was verified against, end to end, on 2026-10-26.
if (utils::packageVersion("randomForestRHF") < "2.1.0") {
  stop("This job needs randomForestRHF >= 2.1.0; ", utils::packageVersion("randomForestRHF"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
if (utils::packageVersion("ggRandomForests") < "4.0.0") {
  stop("This job needs ggRandomForests >= 4.0.0; ", utils::packageVersion("ggRandomForests"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
if (utils::packageVersion("hvtiPlotR") < "2.8.18") {
  stop("This job needs hvtiPlotR >= 2.8.18 for the house theme; ", utils::packageVersion("hvtiPlotR"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
# The study root, the guards and the run record come from .job_setup(); see rhf-fit.
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
# `rhf-explain` reads the forest `rhf-fit` wrote in this same set, and caches
# its own results beside it.
.job$notice
```

**final** · data: see About this run · rendered by gallery on gallery ·
hvtiRtemplates 1.5.2

## Study choices

Edit these values for this study before rendering. The outcome and
predictors are not here: they come from the forest.

Code

``` r
# Demo: the fit's selection is used; set any of these only to confirm it.
# NULL takes the value the fit job used.
WHERE <- NULL
ID <- NULL
KEY <- NULL

# Demo: the horizon for AUC(t), in the units of the fit job's interval columns.
# NULL takes randomForestRHF's default, the range of follow-up.
TAU <- NULL

# Demo: how many patients get hazard curves, drawn at random. The forest's
# patients are numbered 1 to n by the fit job, so a curve cannot be asked for by
# study identifier, and the plots carry no legend that could print one.
N_CURVES <- 10

# Demo: the VarPro cache behind importance, at randomForestRHF's defaults. It is
# the slow step at full scale, and smaller values are faster and coarser in a way
# that shows: a predictor no rule tested gets NA. On the first real study, 2,386
# patients and 35 predictors, 30 rules and 20 trees left 13 untested; 150 and 150
# left 6 to 8, and which ones depended on the seed.
MAX_RULES_TREE <- 150
MAX_TREE <- 150

# Demo: importance at this many evenly spaced points of follow-up. A hazard
# forest's importance changes with time, so one number per predictor would hide
# when it matters.
N_TIMES <- 5

# Demo: seed for the sample of curves and the VarPro cache. It is part of every
# cache key.
SEED <- 2026

# Set TRUE after changing a choice above. A cache whose inputs changed stops the
# render instead of returning the old result; TRUE recomputes only the caches
# that are out of date.
REFIT <- FALSE

# Each figure is saved to graphs/ as a PNG (for Word), and a PDF and a TIFF (for the publisher).
# SAVE_FIGURES <- FALSE saves none; FIGURES keeps only the figures whose names
# start with one of its entries, e.g. FIGURES <- c("rhf-explain-importance").
SAVE_FIGURES <- TRUE
FIGURES <- NULL
```

## The forest

Code

``` r
.handoff <- set_path("estimates", "rhf.rds")
if (!file.exists(.handoff)) {
  stop("No forest at ", .handoff, ". Render the rhf-fit job in this set first; ",
       "this job explains that forest and never grows its own.", call. = FALSE)
}
.cfg <- study_config(start = .root)
.forest_read <- hvtiRtemplates:::.read_handoff(.handoff, "forest", .cfg, "the rhf-fit job")
forest <- .forest_read$value
.provenance_data <- .forest_read$lineage$data
.provenance_artifacts <- c(.forest_read$lineage$artifacts, list(.forest_read$record))
if (!inherits(forest, "rhf")) {
  stop("rhf.rds does not hold a random hazard forest.", call. = FALSE)
}
CACHE_DIR <- dirname(.handoff)
# Every cache below is built from the forest's patient-level rows, so each is
# written owner-only, as rhf.rds is.
.cache_file <- function(name) file.path(CACHE_DIR, paste0(name, ".rds"))
# A forest grown on rows the fit job repaired is a draft's, and so is every
# explanation of it: a final render stops here.
cat(hvtiRtemplates:::.cp_repair_notice(unlist(.forest_read$lineage$analysis$repair)))
```

Code

``` r
# This job reads no data: the forest carries its training rows. A setting above
# that differs from the fit's stops here.
.sel <- hvtiRtemplates:::.read_upstream_job_data(
  .cfg, .forest_read$lineage, list(where = WHERE, id = ID, key = KEY), read = FALSE, source = "rhf.rds"
)$selection
knitr::kable(data.frame(step = c("ID", "KEY", "WHERE", "Rows"),
                        value = c(.sel$id, paste(.sel$key, collapse = ", "),
                                  if (length(.sel$where_shown)) paste(.sel$where_shown, collapse = "; ") else "none",
                                  .sel$rows)),
             col.names = c("Data", ""))
```

| Data  |                   |
|:------|:------------------|
| ID    | patient_id        |
| KEY   | patient_id, start |
| WHERE | none              |
| Rows  | 471               |

Table 1: The data the fit job read

## Discrimination over follow-up

Code

``` r
# The marker here is a cumulative hazard the trees aggregate on the full time
# grid, not the out-of-bag path chf.oob drawn under Hazard curves, so the AUC and
# those curves are not the same estimate.
auc_cum <- hvtiRtemplates:::.owner_only(.cache_file("rhf-auc-cumulative"), cache_fit(
  "rhf-auc-cumulative",
  auct.rhf(forest, marker = "cumhaz", method = "cumulative", tau = TAU, verbose = FALSE),
  seed = SEED, dir = CACHE_DIR, refit = REFIT
))
.fig <- plot(gg_auct(forest, auct_fit = auc_cum)) + hvtiPlotR::theme_hv_manuscript(base_size = 12)
save_figure(.fig, "rhf-explain-auc-cumulative")
.fig
```

![](assets/041a466106f1cd0e8178842c53091617.png)

Figure 1: Cumulative AUC(t): how well the predicted cumulative hazard
separates patients who have had the event by time t from those still at
risk. 0.5 is chance.

Code

``` r
auc_inc <- hvtiRtemplates:::.owner_only(.cache_file("rhf-auc-incident"), cache_fit(
  "rhf-auc-incident",
  auct.rhf(forest, marker = "hazard", method = "incident", riskset = "subject", tau = TAU,
           verbose = FALSE),
  seed = SEED, dir = CACHE_DIR, refit = REFIT
))
.fig <- plot(gg_auct(forest, auct_fit = auc_inc)) + hvtiPlotR::theme_hv_manuscript(base_size = 12)
save_figure(.fig, "rhf-explain-auc-incident")
.fig
```

![](assets/291ddf7ec9007b6b45bb3969f408fb60.png)

Figure 2: Incident AUC(t): how well the predicted hazard separates
patients who have the event at time t from those still at risk then. 0.5
is chance.

Code

``` r
# Uno's iAUC, not iAUC.std. In randomForestRHF 2.1.0 iAUC.std is wrong when an
# AUC(t) is NA: it drops the NA from the integral but still divides by the whole
# time range, so it reads low.
data.frame(measure = c("Cumulative", "Incident"),
           iAUC = round(c(auc_cum$iAUC.uno, auc_inc$iAUC.uno), 3))
```

         measure  iAUC
    1 Cumulative 0.751
    2   Incident 0.551

Table 2: Integrated AUC over follow-up

## Hazard curves

Code

``` r
# The forest's patients are numbered 1 to n, so the sample says nothing about who
# they are. gg_rhf() labels each curve with its patient. Reading forest$chf.oob
# or forest$hazard.oob directly, note that their rows follow the sorted
# ensemble.id, not the order patients first appear in the data: join by id.
# A forest grown outside this template on the study's own id keeps that id as
# given in forest$id (text, zero-padded, say), while ensemble.id, and so gg_rhf(),
# carries as.integer() of it: join back to study data on as.integer(id).
haz <- gg_rhf(forest, source = "oob")
set.seed(abs(SEED))
.curve_ids <- sort(sample(unique(haz$id), min(N_CURVES, length(unique(haz$id)))))
```

Code

``` r
.fig <- plot(haz, idx = .curve_ids, hazard.only = TRUE) +
  hvtiPlotR::theme_hv_manuscript(base_size = 12, legend.position = "none")
save_figure(.fig, "rhf-explain-hazard")
.fig
```

![](assets/d84cabbcf6be2393622333db987140fc.png)

Figure 3: Out-of-bag predicted hazard over follow-up for a random sample
of patients, one line per patient.

Code

``` r
.fig <- plot(haz, idx = .curve_ids, hazard.only = FALSE) +
  hvtiPlotR::theme_hv_manuscript(base_size = 12, legend.position = "none")
save_figure(.fig, "rhf-explain-chf")
.fig
```

![](assets/d38cd6ce48d3018b4b1da6a8295a3141.png)

Figure 4: Out-of-bag predicted cumulative hazard over follow-up for the
same patients, one line per patient.

## Importance

Code

``` r
# The cache is the slow step, and its name is fixed on purpose: later VarPro
# work on this forest reads rhf-varpro-cache rather than building it again.
# The cache draws on R's generator, which rhf(seed =) does not cover. cache_fit()
# seeds it with SEED; unseeded, identical reruns on the first real study moved
# importance medians by about 3 and reordered ranks 2 to 6.
hvtiRtemplates::guard_long_fit("rhf-varpro-cache", dir = CACHE_DIR,
                               why = "the VarPro cache walks every rule of every tree at study size", refit = REFIT)
vp_cache <- hvtiRtemplates:::.owner_only(.cache_file("rhf-varpro-cache"), cache_fit(
  "rhf-varpro-cache",
  varpro.cache.rhf(forest, max.rules.tree = MAX_RULES_TREE, max.tree = MAX_TREE, verbose = FALSE),
  seed = SEED, dir = CACHE_DIR, refit = REFIT
))
.time_index <- unique(as.integer(round(seq.int(1L, vp_cache$K, length.out = N_TIMES))))
imp <- hvtiRtemplates:::.owner_only(.cache_file("rhf-importance"), cache_fit(
  "rhf-importance",
  importance.rhf(forest, cache = vp_cache, time.index = .time_index, verbose = FALSE),
  seed = SEED, dir = CACHE_DIR, refit = REFIT
))
.fig <- plot(gg_rhf_importance(forest, importance_fit = imp)) + hvtiPlotR::theme_hv_manuscript(base_size = 12)
save_figure(.fig, "rhf-explain-importance", height = 7)
.fig
```

![](assets/2484947ba7b1c2247b91d9740d7df607.png)

Figure 5: VarPro importance of each predictor at points across
follow-up.

Code

``` r
as.data.frame(imp)
```

       variable       time time.index                   window      start
    1       xtd 0.01978419          1 (0.00000000, 0.01978419] 0.00000000
    2       x_1 0.01978419          1 (0.00000000, 0.01978419] 0.00000000
    4       x_3 0.01978419          1 (0.00000000, 0.01978419] 0.00000000
    3       x_2 0.01978419          1 (0.00000000, 0.01978419] 0.00000000
    6       x_1 0.07936124          4 (0.05925916, 0.07936124] 0.05925916
    5       xtd 0.07936124          4 (0.05925916, 0.07936124] 0.05925916
    8       x_3 0.07936124          4 (0.05925916, 0.07936124] 0.05925916
    7       x_2 0.07936124          4 (0.05925916, 0.07936124] 0.05925916
    10      x_1 0.15200539          6 (0.11833967, 0.15200539] 0.11833967
    12      x_3 0.15200539          6 (0.11833967, 0.15200539] 0.11833967
    11      x_2 0.15200539          6 (0.11833967, 0.15200539] 0.11833967
    9       xtd 0.15200539          6 (0.11833967, 0.15200539] 0.11833967
    14      x_1 0.26939733          9 (0.23891066, 0.26939733] 0.23891066
    16      x_3 0.26939733          9 (0.23891066, 0.26939733] 0.23891066
    15      x_2 0.26939733          9 (0.23891066, 0.26939733] 0.23891066
    13      xtd 0.26939733          9 (0.23891066, 0.26939733] 0.23891066
    18      x_1 1.58222842         12 (0.40479201, 1.58222842] 0.40479201
    20      x_3 1.58222842         12 (0.40479201, 1.58222842] 0.40479201
    19      x_2 1.58222842         12 (0.40479201, 1.58222842] 0.40479201
    17      xtd 1.58222842         12 (0.40479201, 1.58222842] 0.40479201
             stop    midpoint n.risk n.rules importance
    1  0.01978419 0.009892094    245    1310 4.14133218
    2  0.01978419 0.009892094    245    1310 0.77939241
    4  0.01978419 0.009892094    245    1310 0.34870874
    3  0.01978419 0.009892094    245    1310 0.19191829
    6  0.07936124 0.069310203    135     890 1.26089608
    5  0.07936124 0.069310203    135     890 0.72734812
    8  0.07936124 0.069310203    135     890 0.30455109
    7  0.07936124 0.069310203    135     890 0.11720421
    10 0.15200539 0.135172527    112     794 0.97050885
    12 0.15200539 0.135172527    112     794 0.40026483
    11 0.15200539 0.135172527    112     794 0.25148825
    9  0.15200539 0.135172527    112     794 0.19248935
    14 0.26939733 0.254153994     62     646 1.18221283
    16 0.26939733 0.254153994     62     646 0.26143557
    15 0.26939733 0.254153994     62     646 0.09655036
    13 0.26939733 0.254153994     62     646 0.00000000
    18 1.58222842 0.993510214     34     394 0.87807159
    20 1.58222842 0.993510214     34     394 0.19981972
    19 1.58222842 0.993510214     34     394 0.00000000
    17 1.58222842 0.993510214     34     394 0.00000000

Table 3: VarPro importance of each predictor at each point of follow-up

**NA means untested, not unimportant.** A predictor gets NA when no rule
in the cache split on it, and a larger cache (`MAX_RULES_TREE`,
`MAX_TREE`) tests more of them. A 0 means it was tested and had no
effect. Which predictors go untested depends on the seed, so an NA is no
evidence either way.

**Rank the top tier only once it holds across seeds.** One seed fixes
one cache, and the order below the first predictor or two can move with
it. Before a ranking goes into a report, render this job again with two
or three other `SEED` values and keep the predictors that stay near the
top in every run.

## About this run

| Group | Item | Value |
|:---|:---|:---|
| Run | Started | 2026-10-27 15:35:02 EDT |
|  | Ended | 2026-10-27 15:35:07 EDT |
|  | Duration | 5 s |
|  | Status | final |
|  | Rendered by | gallery |
|  | Host | gallery |
| Job | File | rhf.explain.event.rhf.qmd |
|  | Template | rhf.explain |
|  | Subject | event |
|  | Type | rhf |
|  | hvtiRtemplates | 1.5.2 |
| Dataset `intervals` | Version file | intervals_20261027.parquet |
|  | Version date | 2026-10-27 |
|  | Source file | intervals.rds |
|  | sha256 | f3770c09d63a |
|  | Manifest | current |
| Upstream | Handoff | `event-rhf/rhf.rds` (forest), rendered 2026-10-27 15:34:43 -0400, data intervals_20261027.parquet |
| Reproducibility | Seed | 2026 |
|  | renv | not active |
|  | renv.lock sha256 | d09f96b6cd21 |
