# Random forest classification: explain

# Random forest classification: explain

Explains the forest the `rfc-fit` job in this set saved: which
predictors drive it, and how.

An `rfc-explain` job never grows a forest. It reads `rfc.rds`, which the
fit job writes, and rebuilds the training data and the model from the
forest itself. VIMP, minimal depth and the partial-dependence plots all
describe that saved forest and no other; VarPro grows its own forests on
the same training data, so its panel and partial describe forests VarPro
grew, not the saved one. Each expensive step is cached on its own:
changing how many variables get dependence plots recomputes the partials
and nothing else.

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
  library(randomForestSRC)
  library(varPro)
  library(ggRandomForests)
  library(hvtiRutilities)
})
# The versions this template was verified against, end to end, on 2026-09-19.
# Below them a call here can fail or change meaning, and the message would
# arrive mid-render rather than here.
if (utils::packageVersion("randomForestSRC") < "3.7.0") {
  stop("This job needs randomForestSRC >= 3.7.0; ", utils::packageVersion("randomForestSRC"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
if (utils::packageVersion("ggRandomForests") < "4.0.0") {
  stop("This job needs ggRandomForests >= 4.0.0; ", utils::packageVersion("ggRandomForests"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
if (utils::packageVersion("varPro") < "3.2.0") {
  stop("This job needs varPro >= 3.2.0; ", utils::packageVersion("varPro"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
```

Code

``` r
# The markers in this file name work a study author still has to do, and
# README.md says a job that still contains one has not been finished. This
# chunk is what makes that TRUE rather than merely stated.
#
# Without it an unedited job renders green over a meaningless analysis. Here
# that is dependence plots for a placeholder number of variables, which look
# exactly like a result.
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
SUBJECT <- "complication"
TYPE    <- "rf"

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
  # Quarto knits through an intermediate, so `knitr::current_input()` returns
  # `<subject>-<type>-<prefix>.rmarkdown` here rather than the
  # `.qmd` this was scaffolded as. Strip whatever extension is actually present
  # rather than hard-coding one, so this doesn't depend on a build-tool detail
  # staying the same.
  .fields <- strsplit(sub("[.][^.]+$", "", basename(.current)), "-", fixed = TRUE)[[1L]]
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

# `rfc-explain` reads the forest `rfc-fit` wrote in this same set, and caches
# its own work beside it.
```

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

# Demo: how many variables get dependence plots, ranked by VIMP. The partials
# are the expensive step, so keep this small.
TOP_K <- 4

# Demo: or name the variables yourself. NULL takes the top TOP_K by VIMP.
PARTIAL_VARS <- NULL

# Demo: seed for VIMP, VarPro and the partials. It is part of every cache key.
SEED <- 2026

# Set TRUE after changing a choice above. A cache whose inputs changed stops the
# render instead of returning the old result; TRUE recomputes only the caches
# that are out of date.
REFIT <- FALSE
```

## The forest

Code

``` r
.handoff <- set_path("estimates", "rfc.rds")
if (!file.exists(.handoff)) {
  stop("No forest at ", .handoff, ". Render the rfc-fit job in this set first; ",
       "this job explains that forest and never grows its own.", call. = FALSE)
}
.cfg <- study_config(start = .root)
.forest_read <- hvtiRtemplates:::.read_handoff(.handoff, "forest", .cfg, "the rfc-fit job")
forest <- .forest_read$value
.provenance_data <- .forest_read$lineage$data
.provenance_artifacts <- c(.forest_read$lineage$artifacts, list(.forest_read$record))
if (!identical(forest$family, "class")) {
  stop("rfc.rds holds a '", forest$family, "' forest, not a classification forest.", call. = FALSE)
}
CACHE_DIR <- dirname(.handoff)

# The training data and the model, from the forest rather than re-read. A
# VarPro or partial call on a frame that differs from the fitted one explains a
# model nobody fit. The forest keeps no usable formula (`$formula` is NULL and
# `$call` holds whatever expression the fit job wrote), so the model is rebuilt
# from the outcome names. `xvar` keeps any missing values under na.impute, and
# varpro() handles them; the forest's `imputed.data` makes varpro() fail.
frame <- cbind(stats::setNames(data.frame(forest$yvar), forest$yvar.names), forest$xvar)
model <- stats::reformulate(".", response = forest$yvar.names)
```

Code

``` r
# This job reads no data: the forest carries its training rows. The fit job
# recorded how it chose them, and a setting above that differs from the fit's
# stops here rather than describe rows the forest was not grown on.
.sel <- hvtiRtemplates:::.read_upstream_job_data(
  .cfg, .forest_read$lineage, list(where = WHERE, id = ID, key = KEY), read = FALSE, source = "rfc.rds"
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

## Importance

Code

``` r
vi <- cache_fit("rfc-vimp", vimp(forest), seed = SEED, dir = CACHE_DIR, refit = REFIT)
plot(gg_vimp(vi))
```

![](assets/7ea5285d13c650c934130a5acfa39fa1.png)

Figure 1: Permutation importance of each predictor

Code

``` r
# A classification forest reports importance per class as well as overall;
# the ranking uses the overall column, so no variable is counted twice.
#
# Minimal depth ranks by how near the root a variable first splits, a second
# opinion that needs no permutation. Cheap, so not cached.
imp <- vi$importance[, "all"]
ranked <- names(sort(imp, decreasing = TRUE))
depth <- max.subtree(forest)$order[, 1]
data.frame(variable = ranked,
           vimp = round(imp[ranked], 4),
           min_depth = round(depth[ranked], 2),
           row.names = NULL)
```

      variable    vimp min_depth
    1 creat_pr  0.1502      2.27
    2     lvef  0.0937      1.54
    3   hx_chf  0.0539      1.41
    4      age  0.0429      1.62
    5 plvmassi  0.0330      2.12
    6      bmi  0.0117      2.65
    7    hx_dm  0.0088      4.13
    8   female -0.0013      4.31
    9  nyha_pr -0.0085      2.85

Table 2: Permutation importance and minimal depth of each predictor, in
order of importance

Code

``` r
if (is.null(PARTIAL_VARS)) {
  sel <- head(ranked, TOP_K)
} else {
  # A misspelt name would otherwise fail deep inside the partial call, or be
  # dropped from a plot without a word.
  .unknown <- setdiff(PARTIAL_VARS, forest$xvar.names)
  if (length(.unknown)) {
    stop("PARTIAL_VARS names variable(s) the forest was not grown on: ",
         paste(.unknown, collapse = ", "), call. = FALSE)
  }
  sel <- PARTIAL_VARS
}
```

## VarPro

Code

``` r
vp <- cache_fit("rfc-varpro", varpro(model, frame, verbose = FALSE),
                seed = SEED, dir = CACHE_DIR, refit = REFIT)
```

    Warning: varpro(): omitted 75 of 800 observations with missing values (725
    retained)

Code

``` r
plot(gg_varpro(vp))
```

![](assets/2d93be50e122ac7f04084c1b8f530352.png)

Figure 2: VarPro importance of each predictor

## Dependence

Code

``` r
# Marginal: predicted class probability against each variable, as observed.
plot(gg_variable(forest), xvar = sel)
```

    `geom_smooth()` using method = 'loess' and formula = 'y ~ x'

    Warning: Removed 75 rows containing non-finite outside the scale range
    (`stat_smooth()`).

    Warning: Removed 800 rows containing missing values or values outside the scale range
    (`geom_point()`).

    `geom_smooth()` using method = 'loess' and formula = 'y ~ x'

    Warning: Removed 800 rows containing missing values or values outside the scale range
    (`geom_point()`).
    Removed 800 rows containing missing values or values outside the scale range
    (`geom_point()`).

    `geom_smooth()` using method = 'loess' and formula = 'y ~ x'

    Warning: Removed 800 rows containing missing values or values outside the scale range
    (`geom_point()`).

![](assets/1af30723fc20f8fa3f659043a782511e.png)

Figure 3: Predicted class probability against each selected predictor,
as observed

Code

``` r
# Partial: the forest's prediction with every other variable held at its
# observed values.
pd <- cache_fit("rfc-partial", gg_partial_rfsrc(forest, xvar.names = sel),
                seed = SEED, dir = CACHE_DIR, refit = REFIT)
plot(pd)
```

![](assets/9b6a6c908ab209f2b2901902c2cf38a1.png)

Figure 4: Partial dependence of the forest’s prediction on each selected
predictor

Code

``` r
# The VarPro partial, computed from the varpro fit.
pv <- cache_fit("rfc-partial-varpro", gg_partial_varpro(object = vp, xvar.names = sel),
                seed = SEED, dir = CACHE_DIR, refit = REFIT)
plot(pv)
```

    Warning: Removed 228 rows containing non-finite outside the scale range
    (`stat_boxplot()`).

![](assets/d252f828fefcf5b7c66f03aef0174eb4.png)

Figure 5: VarPro partial dependence on each selected predictor
