# VarPro: dependence

# VarPro: dependence

Published

2026-11-20 17:42

Gallery job on the synthetic cohort: how the nine preoperative
predictors the rf fits grow on depend on each other, with no outcome
entered.

A `vp-dependence` job asks how the study’s variables depend on each
other. It needs no outcome: unsupervised VarPro (`varPro::uvarpro()`)
grows a forest on the variables alone, and each variable’s release rules
ask which other variables separate the patients a rule picks out. No
other job in the set has to run first.

The job takes three steps. **The forest:** `uvarpro()` on the variables
and on permuted noise copies of them. **The matrix:**
`get.beta.entropy()` fits a lasso for every released variable, and its
coefficients say how strongly each other variable separates that
variable’s contrast. **The graph:** an edge is drawn only where that
strength beats the largest any noise column reached, and the whole thing
is refitted on subsamples to show which edges hold.

This template is **in flight**: it is built from one study’s dependence
analysis, and a second study running it through to its stability section
is what moves it to shipped.

Code

``` r
SUBJECT <- "preop"
TYPE    <- "vp"
.in <- knitr::current_input(dir = TRUE)
suppressPackageStartupMessages({
  library(varPro)
  library(ggRandomForests)
  library(hvtiRutilities)
})
# One thread, so the forest and the lasso reproduce from machine to machine.
# uvarpro() and get.beta.entropy() take no cores argument: rf.cores reaches the
# forest and mc.cores the lasso's workers.
options(rf.cores = 1L, mc.cores = 1L)
# The oldest versions this template works with. Below them a
# call here can fail or change meaning, and the message would arrive mid-render
# rather than here.
if (utils::packageVersion("randomForestSRC") < "3.7.0") {
  stop("This job needs randomForestSRC >= 3.7.0; ", utils::packageVersion("randomForestSRC"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
# 3.3.0 records which variable each encoded column came from (xvar.map) and
# aligns sdependent()'s matrix by name; this job relies on both.
if (utils::packageVersion("varPro") < "3.3.0") {
  stop("This job needs varPro >= 3.3.0; ", utils::packageVersion("varPro"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
if (utils::packageVersion("ggRandomForests") < "4.0.0") {
  stop("This job needs ggRandomForests >= 4.0.0; ", utils::packageVersion("ggRandomForests"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
# The dependence graph is drawn by ggRandomForests' plot method, which needs ggraph.
if (!requireNamespace("ggraph", quietly = TRUE)) {
  stop("This job needs the ggraph package to draw the dependence graph. Install it, then re-render.", call. = FALSE)
}
# The study root is the nearest directory above this file holding _study.yml,
# so the job renders the same from the Render button, quarto render, or
# render_job(), at any depth, with no path in this document to edit.
# Without the guard in .job_setup(), an unedited job renders green over a
# meaningless analysis. Here that is a graph of the template's placeholder
# variables, which looks exactly like a result.
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

# `vp-dependence` writes dependence.rds, in the `save` chunk near the foot of
# this file. No job reads it yet.
# The draft banners, if any, and the box under the title, after all the code above.
.job$notice
```

**final** · data `built` `built_20261120.parquet`, dated 2026-11-20 ·
rendered by gallery on gallery · hvtiRtemplates 1.6.2

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

# Demo: the patient identifier. If the data has no "ccfid" column, the job uses MRN, then eMRN;
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
#     or "nearest" with to = a cohort date column). A tie stops: picking one
#     record silently would be a hidden choice. This job reads one row per
#     patient, so a JOIN without REDUCE stops here.
#   JOIN_KEY: overrides the joined dataset's registered key.
JOIN <- NULL
JOIN_VARS <- NULL
REDUCE <- NULL
JOIN_KEY <- NULL

# Demo: the variables whose dependence on each other this job studies. Name
# them rather than taking every column: a built dataset carries identifiers,
# dates and derived outcomes, and dates in particular link to everything.
VARIABLES <- c("age", "female", "bmi", "hx_chf", "hx_dm", "nyha_pr", "lvef", "plvmassi", "creat_pr")

# Demo: optional outcome columns, entered as plain variables to see where the
# outcome sits among them. NULL enters none. A link to an outcome column is
# shared structure, not prediction. A survival outcome enters as two columns,
# the event (0/1) and the time.
OUTCOME <- NULL

# Demo: graded variables to enter as numbers (a grade 0-3, a count). Left as
# factors they are split into 0/1 columns, and the unsupervised forest then
# finds structure almost only between the levels of one factor, which this job
# removes. Unordered categories stay factors.
ORDINAL <- "nyha_pr"

# Demo: how many permuted noise columns to add, split between categorical and
# continuous variables in proportion to the variables. The largest dependence a
# noise column reaches is the bar an edge must clear.
NOISE_N <- 20

# Demo: the unsupervised forest. Below about 100 trees the noise reaches
# almost as high as a real link, so the bar loses its meaning. 1,000 is set by
# the rules below, not by the bar: see MAX_TREE.
NTREE <- 1000

# Demo: the rules uvarpro() builds. It samples MAX_TREE of the trees (all of
# NTREE at most) and up to MAX_RULES_TREE branches in each, and a variable is
# examined only through the rules that release it: too few and a variable that
# rarely splits gets no rule and is never looked at. The forest builds about 10
# rules a tree whatever MAX_RULES_TREE is from 20 up, so MAX_TREE is the lever.
# In simulations with the noise columns below (5 variables and 200 patients, 31
# and 400; dev/vp/uvarpro-coverage.R, 2026-11-15), 1,000 trees gave every
# variable a rule at every seed. Forests of 500 trees left one or two of 31
# variables without a rule at 6 of 20 seeds (and one of 5 at 1 of 30), and 750
# trees one of 31 at 5 of 20. The cost is the lasso, fitted once per rule: at
# 200 patients and 25 columns it took 56 s at 500 trees, 83 s at 750 and 110 s
# at 1,000, for the full fit and again for each refit. Lower both to 500 to
# halve that where the coverage table stays full.
MAX_TREE <- 1000
MAX_RULES_TREE <- 20
# Demo: how many of the variables (VARIABLES and OUTCOME) may go unexamined,
# with no release rule in the full fit, before the render stops. A variable
# with no rule has no edge leaving it, and that absence must not be read as
# independence. The render stops when the unexamined are both more than
# MAX_UNTESTED's share of the variables and more than MIN_UNTESTED of them.
# At the defaults above none went unexamined in the simulations, so a share
# past 0.1 says the forest is too small for these data and the fix is more
# trees (MAX_TREE with NTREE). The share alone allows none at 10 variables or
# fewer, where one unexamined variable can be chance: a nine-variable cohort
# left one of nine unexamined at 1,000 trees (three at 500). MIN_UNTESTED lets
# that one through and still stops on two; 0 holds a small study to the share
# alone. NULL MAX_UNTESTED reports the unexamined in the coverage table and
# does not stop.
MAX_UNTESTED <- NULL
MIN_UNTESTED <- 1

# Demo: the fixed edge cutoff the noise bar is reported beside, and falls back
# to when no noise column earned any weight. 0.25 is varPro's default.
THRESHOLD_FIXED <- 0.25

# Demo: the stability check. REPEATS refits, each on SUBSAMPLE of the patients
# drawn without replacement and with a fresh noise draw. 0 skips it; each
# refit costs one forest and one lasso step.
REPEATS <- 3
SUBSAMPLE <- 0.632

# Demo: missing values. uvarpro() removes every patient with a missing value
# and ignores na.action, so the choice is made here. "na.impute" fills the
# VARIABLES once by random forest, from each other and never from OUTCOME: the
# graph measures edges into OUTCOME, and an imputation that used it would draw
# some of them itself. "na.omit" keeps complete cases. A patient missing
# OUTCOME, when it is set, is dropped either way.
NA_ACTION <- "na.impute"
# Demo: the largest share of patients a variable may be missing in and still be imputed.
MAX_MISSING <- 0.4

# Demo: the seed. It is part of every cache key, seeds R's generator before
# the forest and again before the lasso, and is handed to uvarpro() as `seed =`.
SEED <- 2026

# Set TRUE after changing a choice above. A cache whose inputs changed stops the
# render instead of returning the old result; TRUE recomputes only the caches
# that are out of date.
REFIT <- FALSE

# Each figure is saved to graphs/ as a PNG (for Word) and a PDF (for the publisher), and as a TIFF when ragg is installed.
# SAVE_FIGURES <- FALSE saves none; FIGURES keeps only the figures whose names
# start with one of its entries, e.g. FIGURES <- c("vp-dependence-graph"). The names are the
# file names, listed for each template in the templates README.
SAVE_FIGURES <- TRUE
FIGURES <- NULL
```

## Data

Code

``` r
# The checksum of every dataset in manifest.yaml is checked before anything is
# read, so a result can name the data that produced it. It stops on a mismatch.
hvtiRutilities::verify_manifest(file.path(.root, "manifest.yaml"))
.cfg <- study_config(start = .root)
job_data <- hvtiRtemplates::read_job_data(.cfg, dataset = DATASET, analysis_set = ANALYSIS_SET,
                                          where = WHERE, id_col = ID, key_cols = KEY, join = JOIN, join_cols = JOIN_VARS,
                                          reduce = REDUCE, join_key_cols = JOIN_KEY, one_row_per_patient = TRUE)
d <- job_data$data
.provenance_data <- c(if (exists(".provenance_data")) .provenance_data else list(), list(job_data$provenance),
                      if (!is.null(job_data$provenance_join)) list(job_data$provenance_join))
knitr::kable(job_data$record, col.names = c("Data", ""))
.cols <- c(VARIABLES, OUTCOME)
.duplicated <- unique(.cols[duplicated(.cols)])
if (length(.duplicated)) {
  stop("VARIABLES and OUTCOME name a variable more than once: ", paste(.duplicated, collapse = ", "), ".", call. = FALSE)
}
# An identifier would link to nothing but itself, and the saved fit keeps its
# data, so it would be written into dependence.rds.
.selection <- attr(job_data$record, "selection")
.identifiers <- .cols[tolower(.cols) %in% tolower(c(.selection$id, .selection$key))]
if (length(.identifiers)) {
  stop("Do not include the patient identifier or a KEY column: ", paste(.identifiers, collapse = ", "), ".", call. = FALSE)
}
.missing <- setdiff(.cols, names(d))
if (length(.missing)) {
  stop("Not in the data this job read: ", paste(.missing, collapse = ", "), call. = FALSE)
}
.not_listed <- setdiff(ORDINAL, .cols)
if (length(.not_listed)) {
  stop("ORDINAL names variable(s) not in VARIABLES or OUTCOME: ", paste(.not_listed, collapse = ", "), call. = FALSE)
}
d <- d[, .cols, drop = FALSE]
for (.v in ORDINAL) {
  .num <- suppressWarnings(as.numeric(as.character(d[[.v]])))
  if (any(is.na(.num) & !is.na(d[[.v]]))) {
    stop(.v, " is in ORDINAL but has values that are not numbers.", call. = FALSE)
  }
  d[[.v]] <- .num
}
.chr <- .cols[vapply(d[.cols], is.character, logical(1L))]
if (length(.chr)) {
  d[.chr] <- lapply(d[.chr], factor)
  cat("Text variables converted to factors: ", paste(.chr, collapse = ", "), "\n", sep = "")
}
.analysis <- list(kind = "unsupervised", variables = VARIABLES, outcome = OUTCOME)
```

| Data                |                                          |
|:--------------------|:-----------------------------------------|
| Source              | dataset `built` (built_20261120.parquet) |
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
# uvarpro() removes every patient with a missing value. NA_ACTION settles them
# here, once, before the noise columns and the refits.
NA_ACTION <- match.arg(NA_ACTION, c("na.impute", "na.omit"))
if (!(is.numeric(MAX_MISSING) && length(MAX_MISSING) == 1L && !is.na(MAX_MISSING) && MAX_MISSING > 0 && MAX_MISSING <= 1)) {
  stop("MAX_MISSING must be a single share in (0, 1].", call. = FALSE)
}
.empty <- .cols[vapply(d[.cols], function(x) all(is.na(x)), logical(1L))]
if (length(.empty)) {
  stop("VARIABLES or OUTCOME names a column with no values: ", paste(.empty, collapse = ", "),
       ". Remove it.", call. = FALSE)
}
.miss <- hvtiRtemplates:::.vp_missing(d, VARIABLES, outcome = OUTCOME, na_action = NA_ACTION, max_missing = MAX_MISSING)
d <- .miss$d
if (!nrow(d)) {
  stop("No patient is left: every one is missing OUTCOME or, under na.omit, a variable.", call. = FALSE)
}
if (anyNA(d[VARIABLES])) {
  # Bound first so the cache keys VARIABLES alone: a change to OUTCOME must not stale it.
  .to_impute <- d[VARIABLES]
  # impute() fills a logical column as a number, so a yes/no variable would come back as 0.496 and be graphed as
  # continuous. It is imputed as a factor and turned back into TRUE/FALSE, so the graph sees the same type either way.
  .lgl <- names(.to_impute)[vapply(.to_impute, is.logical, logical(1L))]
  .to_impute[.lgl] <- lapply(.to_impute[.lgl], factor)
  .imputed <- cache_fit("vp-dependence-impute",
                        randomForestSRC::impute(data = .to_impute, ntree = 250, verbose = FALSE),
                        seed = SEED, dir = dirname(set_path("estimates", "dependence.rds")), refit = REFIT,
                        packages = "randomForestSRC")
  # impute() removes a row with no observed value; a silent loss is what this chunk exists to stop.
  if (nrow(.imputed) != nrow(d)) {
    stop(nrow(d) - nrow(.imputed), " patient(s) have no observed value in VARIABLES and cannot be imputed. ",
         "Remove them in the dataset build.", call. = FALSE)
  }
  .imputed[.lgl] <- lapply(.imputed[.lgl], function(x) as.logical(as.character(x)))
  d[VARIABLES] <- .imputed[VARIABLES]
}
```

    cache_fit(): loaded 'vp-dependence-impute' from cache

Code

``` r
if (anyNA(d[.cols])) stop("Variables still hold missing values after NA_ACTION; uvarpro() would drop them.", call. = FALSE)
.missing_values <- .miss$table
.cohort <- c(list(n = as.integer(nrow(d))), .miss$cohort)
cat(attr(.missing_values, "rule"), "\n\n")
```

    Missing predictor values were imputed once by random forest, without the outcome, before the screen. 

Code

``` r
knitr::kable(.missing_values)
```

| Row                      | Count   |
|:-------------------------|:--------|
| Supplied                 | 800     |
| Outcome missing, dropped | 0       |
| Missing: creat_pr        | 75 (9%) |
| Imputed: creat_pr        | 75 (9%) |
| Used                     | 800     |

Table 2: Patients supplied, missing values, and patients used

## Noise

Each noise column is a permuted copy of a real variable. It keeps that
variable’s values and loses every link to the other columns, not only to
an outcome, so whatever dependence it shows is what chance alone shows.
The largest weight any noise column reaches is the bar a real edge must
clear.

Code

``` r
# The copies are drawn by kind in proportion to the variables, with at least
# one of each kind present, so both kinds of column contribute to the null and
# neither crowds out the real variables. Half and half, the rule this replaced,
# made 10 of 20 columns binary copies of the one factor among 31 variables, and
# those copies took nearly half the forest's release rules (2026-11-14).
# An outcome column entered in OUTCOME is a source like any other: a
# permuted outcome is as much a null as any other permuted column.
#
# Only a variable with at least two observed values is a source: a permuted
# constant is a constant, which earns no rule and so sets no bar. With the
# proportional draw a kind can have a single copy, so one constant factor could
# otherwise leave no categorical null at all. A refit draws again from its own
# subsample, where a rare level can leave a factor constant.
#
# The kind rule is varpro_coverage()'s: a factor, text or logical column, or a
# number with at most 5 distinct values, is categorical.
vp_kind <- function(x) {
  if (is.factor(x) || is.character(x) || is.logical(x) || length(unique(stats::na.omit(x))) <= 5L) {
    "categorical"
  } else {
    "continuous"
  }
}
vp_add_noise <- function(d, predictors, n, seed) {
  predictors <- predictors[vapply(d[predictors], function(x) length(unique(stats::na.omit(x))) >= 2L, NA)]
  if (!length(predictors)) stop("No variable takes two or more values, so there is nothing to permute for the noise.", call. = FALSE)
  kinds <- vapply(d[predictors], vp_kind, "")
  pools <- split(predictors, kinds)
  n_cat <- as.integer(round(n * length(pools$categorical) / length(predictors)))
  if (length(pools$categorical) && length(pools$continuous) && n >= 2L) n_cat <- min(n - 1L, max(1L, n_cat))
  set.seed(abs(seed))
  draw <- function(pool, k) if (k == 0L) character() else pool[sample.int(length(pool), k, replace = k > length(pool))]
  src <- c(draw(pools$categorical, n_cat), draw(pools$continuous, n - n_cat))
  for (i in seq_along(src)) {
    set.seed(abs(seed) + i)
    d[[paste0("noise", i, "_", src[i])]] <- sample(d[[src[i]]])
  }
  d
}
if (NOISE_N < 1) {
  stop("NOISE_N must be at least 1: the edge bar needs noise to beat.", call. = FALSE)
}
if (!(SUBSAMPLE > 0 && SUBSAMPLE < 1)) {
  stop("SUBSAMPLE must be a share between 0 and 1 (0.632 draws 63.2% of the patients).", call. = FALSE)
}
if (REPEATS > 0 && floor(SUBSAMPLE * nrow(d)) < 2) {
  stop("SUBSAMPLE of ", nrow(d), " patients leaves fewer than 2 for a refit. Raise SUBSAMPLE or set REPEATS to 0.", call. = FALSE)
}
# The noise columns are found by the "noise" prefix, so a real variable named
# that way would be judged as noise.
.noisy <- grep("^noise", .cols, value = TRUE)
if (length(.noisy)) {
  stop("Variable(s) whose names start with \"noise\", which this job reserves for its noise columns: ",
       paste(.noisy, collapse = ", "), ". Rename them in the dataset build.", call. = FALSE)
}
d_noise <- vp_add_noise(d, .cols, NOISE_N, SEED)
# A kind among the variables with no noise column of its own has no null of its
# kind, so its edges are judged against the other kind's noise alone.
.no_null <- setdiff(vapply(d[.cols], vp_kind, ""), vapply(d_noise[grep("^noise", names(d_noise))], vp_kind, ""))
if (length(.no_null)) {
  cat("No ", paste(unique(.no_null), collapse = " or "), " variable takes two or more values, so no noise column of that ",
      "kind was drawn and the bar comes from the other kind alone.\n", sep = "")
}
```

Code

``` r
# The decisions this job makes from the importance matrix, in one chunk of
# their own so they can be checked on a hand-built matrix without a fit.
#
# varPro splits a factor into one 0/1 column per level and records which
# variable each column came from, in attr(fit$x, "xvar.map"). That record is
# read, never guessed from the names: a factor f with a level s beside a
# numeric fs gets a column named fs.1, which belongs to f, and no rule on the
# spelling can tell.
vpd_parent <- function(fit) {
  map <- attr(fit$x, "xvar.map")
  if (is.null(map)) {
    stop("This varPro fit records no xvar.map, so its encoded columns cannot be traced to variables. ",
         "Update varPro to 3.3.0 or later, set REFIT <- TRUE, and re-render.", call. = FALSE)
  }
  map
}
# get.beta.entropy() returns rows only for the variables that formed a
# contrast, so the matrix is padded to square, missing entries 0. A patient is
# only ever one level of a factor, so links between two levels say nothing
# about the data and are zeroed, as gg_udependent() does.
vpd_square <- function(I, parent) {
  nm <- union(rownames(I), colnames(I))
  sq <- matrix(0, length(nm), length(nm), dimnames = list(nm, nm))
  sq[rownames(I), colnames(I)] <- I
  p <- parent[nm]
  same <- outer(p, p, "==")
  same[is.na(same)] <- FALSE
  sq[same] <- 0
  diag(sq) <- 0
  sq
}
# The bar: the largest weight any noise term reached, released (its row) or
# as a predictor (its column). Both are chance. A bar is usable only above 0;
# when no noise earned any weight the fixed threshold stands in, and says so.
vpd_bar <- function(I, noise, fixed) {
  w <- c(I[noise, , drop = FALSE], I[, noise, drop = FALSE])
  w <- w[is.finite(w)]
  if (length(w) && max(w) > 0) list(bar = max(w), from = "noise") else list(bar = fixed, from = "fixed (fallback)")
}
# Whether the forest examined each variable: how many release rules it built
# for it. fit$results has a row per rule, its `variable` an index into the
# encoded columns, which vpd_parent() traces to variables. A variable with no
# rule was never released, so no contrast of its own was ever tested.
vpd_coverage <- function(fit, cols) {
  parent <- vpd_parent(fit)
  released <- unname(parent[colnames(fit$x)[fit$results$variable]])
  rules <- vapply(cols, function(v) sum(released %in% v), integer(1L), USE.NAMES = FALSE)
  data.frame(variable = cols, rules = rules, state = ifelse(rules > 0L, "examined", "not examined"))
}
# How often each key, an edge or a signal-set variable, was drawn across the
# refits, over the refits that examined the variable it depends on, as vp-fit's
# vote counts a selection over the refits that tested the variable. A refit
# that built no rule for that variable never looked, so it counts neither for
# the key nor against it. Each run is list(edges = "from -> to" keys, signal =
# variable names, examined = variable names). A share with no such refit is NA,
# not 0.
vpd_share <- function(runs, what, owner = function(k) k) {
  keys <- sort(unique(unlist(lapply(runs, `[[`, what))))
  own <- owner(keys)
  refits <- drawn <- integer(length(keys))
  for (run in runs) {
    seen <- own %in% run$examined
    refits <- refits + seen
    drawn <- drawn + (seen & keys %in% run[[what]])
  }
  data.frame(key = keys, share = ifelse(refits > 0L, drawn / pmax(1L, refits), NA_real_), refits = refits)
}
# An edge runs from a variable's row of the matrix, its contrast, to a column,
# and every variable is a column in every row's lasso. So an edge needs only
# its tail examined: one into a variable with no rule can still be drawn. The
# graph is directed (gg_udependent()'s default, which vpd_graph() keeps), so no
# edge is read both ways.
vpd_edge_share <- function(runs) {
  s <- vpd_share(runs, "edges", owner = function(k) sub(" -> .*$", "", k))
  ends <- strsplit(s$key, " -> ", fixed = TRUE)
  data.frame(from = vapply(ends, `[`, "", 1L), to = vapply(ends, `[`, "", 2L), share = s$share, refits = s$refits)
}
vpd_signal_share <- function(runs) {
  s <- vpd_share(runs, "signal")
  data.frame(variable = s$key, share = s$share, refits = s$refits)
}
```

## Fit

Code

``` r
# Empty until the stability chunk fills it, which it does only when REPEATS is
# above 0, so a session that ran the job before cannot carry an old result in.
.vpd_stab <- NULL
# cache_fit() writes <dir>/<name>.rds and its default dir is the study's
# estimates folder, not this set's, so every call here names the set's.
CACHE_DIR <- dirname(set_path("estimates", "dependence.rds"))
.count_ok <- function(x) is.numeric(x) && length(x) == 1L && !is.na(x) && x >= 1
if (!.count_ok(MAX_TREE) || !.count_ok(MAX_RULES_TREE)) {
  stop("MAX_TREE and MAX_RULES_TREE must each be a single whole number of at least 1.", call. = FALSE)
}
if (!is.null(MAX_UNTESTED) && !(is.numeric(MAX_UNTESTED) && length(MAX_UNTESTED) == 1L && !is.na(MAX_UNTESTED) &&
                                  MAX_UNTESTED >= 0 && MAX_UNTESTED <= 1)) {
  stop("MAX_UNTESTED must be NULL or a single share in [0, 1].", call. = FALSE)
}
if (!(is.numeric(MIN_UNTESTED) && length(MIN_UNTESTED) == 1L && !is.na(MIN_UNTESTED) && MIN_UNTESTED >= 0 &&
        MIN_UNTESTED == round(MIN_UNTESTED))) {
  stop("MIN_UNTESTED must be a single whole number of at least 0.", call. = FALSE)
}
set.seed(abs(SEED))
# packages = keys each cache on the engine doing the work as well as on
# varPro, which only calls it: randomForestSRC grows the forest and glmnet
# fits the lasso, and an update to either must not reuse an old result.
# The rule limits are written into the call itself: cache_fit() keys the
# variables its expression names, so a changed MAX_TREE or MAX_RULES_TREE
# makes the cache stale rather than reloading a fit built under the old ones.
fit <- cache_fit("vp-dependence",
                 uvarpro(d_noise, ntree = NTREE, max.tree = min(MAX_TREE, NTREE), max.rules.tree = MAX_RULES_TREE,
                         seed = -abs(SEED)),
                 seed = SEED, dir = CACHE_DIR, refit = REFIT, packages = "randomForestSRC")
```

    cache_fit(): loaded 'vp-dependence' from cache

Code

``` r
# The lasso step draws its cross-validation folds from R's generator, so it is
# seeded again. pre.filter = FALSE keeps every column: the pre-filter would
# drop the noise the bar is made from, and any outcome column.
set.seed(abs(SEED))
beta_raw <- cache_fit("vp-dependence-beta", get.beta.entropy(fit, pre.filter = FALSE, papply = lapply),
                      seed = SEED, dir = CACHE_DIR, refit = REFIT, packages = "glmnet")
```

    cache_fit(): loaded 'vp-dependence-beta' from cache

## Coverage

A variable is **examined** when the forest built at least one release
rule for it. One that was not examined has no contrast of its own in the
matrix below, so no edge leaves it, and that is because it was not
looked at, not because it is independent. It is still a predictor in
every other variable’s lasso, so edges into it can still appear.

Code

``` r
.coverage <- vpd_coverage(fit, .cols)
.not_examined <- .coverage$variable[.coverage$state == "not examined"]
knitr::kable(.coverage, row.names = FALSE)
```

| variable | rules | state        |
|:---------|------:|:-------------|
| age      |     2 | examined     |
| female   |   612 | examined     |
| bmi      |     0 | not examined |
| hx_chf   |  3365 | examined     |
| hx_dm    |  2319 | examined     |
| nyha_pr  |    31 | examined     |
| lvef     |    36 | examined     |
| plvmassi |     0 | not examined |
| creat_pr |     5 | examined     |

Table 3: Whether the forest examined each variable

Code

``` r
# Below the table, so the reader sees the counts before the verdict.
if (length(.not_examined)) {
  cat("Not examined: ", paste(.not_examined, collapse = ", "), ". The forest built no rule for them, so no edge ",
      "leaves them; edges into them can still appear.\n", sep = "")
}
```

Not examined: bmi, plvmassi. The forest built no rule for them, so no
edge leaves them; edges into them can still appear.

Code

``` r
# Both must be exceeded, so MIN_UNTESTED is a floor under the share's allowance:
# at 9 variables and 0.1 the share allows none and MIN_UNTESTED one.
if (!is.null(MAX_UNTESTED) && length(.not_examined) > MIN_UNTESTED &&
      length(.not_examined) / length(.cols) > MAX_UNTESTED) {
  stop(length(.not_examined), " of ", length(.cols), " variables were not examined, more than MAX_UNTESTED (",
       MAX_UNTESTED, ") and MIN_UNTESTED (", MIN_UNTESTED, ") allow: ", paste(.not_examined, collapse = ", "),
       ". The forest built no release rule for them. Raise MAX_TREE (up to NTREE), MAX_RULES_TREE or NTREE, ",
       "set REFIT <- TRUE and re-render; MAX_UNTESTED <- NULL reports them without stopping.", call. = FALSE)
}
```

## The dependence matrix

Each row of the matrix is a variable VarPro released: its rules pick out
a group of patients, and the lasso asks which other variables separate
that group from the rest. Each entry is how strongly the column’s
variable does.

Code

``` r
.parent <- vpd_parent(fit)
beta <- vpd_square(beta_raw, .parent)
.noise <- startsWith(unname(.parent[rownames(beta)]), "noise") %in% TRUE
bar <- vpd_bar(beta, .noise, THRESHOLD_FIXED)
cat(if (bar$from == "noise") {
  sprintf("The noise bar is %.3g, the largest weight a permuted noise column reached; varPro's fixed cutoff is %.3g.\n",
          bar$bar, THRESHOLD_FIXED)
} else {
  sprintf("No noise column earned any weight, so the fixed cutoff %.3g stands in for the noise bar.\n", THRESHOLD_FIXED)
})
```

The noise bar is 0.598, the largest weight a permuted noise column
reached; varPro’s fixed cutoff is 0.25.

Code

``` r
# The graph holds real variables only. sdependent() keeps an edge at >= its
# threshold, so the noise entry the bar came from would otherwise be drawn.
beta_real <- beta[!.noise, !.noise, drop = FALSE]
# gg_udependent() warns when no edge clears the bar. This report says so in
# its own words below the graph, so that one warning is muffled, by its
# message and nothing else.
vpd_graph <- function(fit, beta, bar) {
  withCallingHandlers(
    gg_udependent(fit, beta.mat = beta, threshold = bar),
    warning = function(w) if (grepl("no edges found", conditionMessage(w), fixed = TRUE)) invokeRestart("muffleWarning")
  )
}
gg <- vpd_graph(fit, beta_real, bar$bar)
signal <- as.character(gg$nodes$variable[gg$nodes$selected])
.linked <- unique(c(gg$edges$variable_from, gg$edges$variable_to))
.unlinked <- setdiff(rownames(beta_real), .linked)
if (length(.unlinked)) {
  cat("\nNo link at the bar, so not drawn (not evidence of independence): ", paste(.unlinked, collapse = ", "), ".\n", sep = "")
}
```

No link at the bar, so not drawn (not evidence of independence): female,
hx_dm, age, bmi, nyha_pr, plvmassi, creat_pr.

Code

``` r
# With no edge there is nothing to draw, and the matrix chunk above has said
# which variables have no link. A blank panel stands in, so the caption still
# has its figure, and it says why.
.fig <- if (nrow(gg$edges) == 0L) {
  ggplot2::ggplot() +
    ggplot2::annotate("text", x = 0, y = 0, label = "No edge clears the bar.") +
    ggplot2::theme_void()
} else {
  plot(gg)
}
save_figure(.fig, "vp-dependence-graph", width = 6.5, height = 6)
.fig
```

![](assets/36e64144638771d52c66dc25a7c1641d.png)

Figure 1: Dependence between the variables, at the noise bar. An arrow
runs from a released variable to a variable that helps separate the
patients its rules pick out, and the stronger the link the darker the
arrow; blue variables are the signal set. A variable with no edge at the
bar is not drawn.

Code

``` r
.sym <- pmax(beta_real, t(beta_real))
.ord <- if (nrow(.sym) > 2L) rownames(.sym)[stats::hclust(stats::dist(.sym))$order] else rownames(.sym)
.long <- data.frame(row = rep(rownames(.sym), ncol(.sym)), col = rep(colnames(.sym), each = nrow(.sym)),
                    weight = as.vector(.sym))
.long$row <- factor(.long$row, levels = .ord)
.long$col <- factor(.long$col, levels = .ord)
.out <- .long[.parent[as.character(.long$row)] %in% OUTCOME | .parent[as.character(.long$col)] %in% OUTCOME, ]
.fig <- ggplot2::ggplot(.long, ggplot2::aes(col, row, fill = weight)) +
  ggplot2::geom_tile() +
  ggplot2::geom_tile(data = .out, fill = NA, color = "black", linewidth = 0.3) +
  ggplot2::scale_fill_gradient(low = "white", high = "steelblue4", name = "Weight") +
  ggplot2::labs(x = NULL, y = NULL) +
  hvtiPlotR::theme_hv_manuscript(base_size = 12) +
  ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 90, hjust = 1, vjust = 0.5))
save_figure(.fig, "vp-dependence-heatmap", width = 6.5, height = 6)
.fig
```

![](assets/55eb4576c70c91bc5bb23bdacb350b66.png)

Figure 2: Dependence between every pair of variables at any strength,
the larger of the two directions, clustered so related variables sit
together. Outcome columns, if any, are outlined.

## Stability

The graph refitted `REPEATS` times, each on a subsample of the patients
drawn without replacement and with a fresh noise draw, and each judged
against its own noise bar. An edge’s share is over the refits that
examined the variable the edge leaves, the count beside it: a refit that
examined it and drew no edge counts against the edge, and one that built
no rule for it never looked, so it does not count. The share is NA when
no refit examined that variable. A variable’s share in the signal set is
counted the same way, over the refits that examined it. An edge drawn in
most refits holds up; one drawn once in a while is the forest’s own
noise.

Code

``` r
# Each refit draws its patients and its noise from seeds that move with r
# (abs(SEED) + r, and abs(SEED + r) inside vp_add_noise(), as in vp-fit), and
# is cached on its own, so raising REPEATS computes only the new ones.
if (REPEATS > 0) {
  .runs <- lapply(seq_len(REPEATS), function(r) {
    set.seed(abs(SEED) + r)
    rows <- sort(sample.int(nrow(d), floor(SUBSAMPLE * nrow(d))))
    dr <- vp_add_noise(d[rows, , drop = FALSE], .cols, NOISE_N, SEED + r)
    set.seed(abs(SEED) + r)
    fr <- cache_fit(sprintf("vp-dependence-repeat-%02d", r),
                    uvarpro(dr, ntree = NTREE, max.tree = min(MAX_TREE, NTREE), max.rules.tree = MAX_RULES_TREE,
                            seed = -abs(SEED + r)),
                    seed = SEED + r, dir = CACHE_DIR, refit = REFIT, packages = "randomForestSRC")
    set.seed(abs(SEED) + r)
    br <- cache_fit(sprintf("vp-dependence-repeat-%02d-beta", r),
                    get.beta.entropy(fr, pre.filter = FALSE, papply = lapply),
                    seed = SEED + r, dir = CACHE_DIR, refit = REFIT, packages = "glmnet")
    pr <- vpd_parent(fr)
    sq <- vpd_square(br, pr)
    nz <- startsWith(unname(pr[rownames(sq)]), "noise") %in% TRUE
    b <- vpd_bar(sq, nz, THRESHOLD_FIXED)
    real <- sq[!nz, !nz, drop = FALSE]
    g <- vpd_graph(fr, real, b$bar)
    cr <- vpd_coverage(fr, .cols)
    list(bar = b$bar, edges = paste(g$edges$variable_from, g$edges$variable_to, sep = " -> "),
         signal = as.character(g$nodes$variable[g$nodes$selected]), examined = cr$variable[cr$rules > 0L])
  })
  .vpd_stab <- list(
    edges = vpd_edge_share(.runs),
    signal = vpd_signal_share(.runs),
    bars = vapply(.runs, `[[`, numeric(1L), "bar")
  )
  .vpd_stab$edges <- .vpd_stab$edges[order(-.vpd_stab$edges$share, na.last = TRUE), ]
  cat(sprintf("The noise bar ranged from %.3g to %.3g across the refits.\n", min(.vpd_stab$bars), max(.vpd_stab$bars)))
  if (!nrow(.vpd_stab$edges)) cat("No edge cleared its refit's bar in any refit.\n")
  knitr::kable(.vpd_stab$edges, digits = 2, row.names = FALSE)
} else {
  cat("Skipped: REPEATS is 0.\n")
}
```

    The noise bar ranged from 0.757 to 1.21 across the refits.

| from   | to   | share | refits |
|:-------|:-----|------:|-------:|
| hx_chf | lvef |     1 |      3 |

Table 4: How often each edge cleared its refit’s noise bar, most often
first

Code

``` r
# Over the refits that examined each variable, as the edge table is. Empty when REPEATS is 0.
if (!is.null(.vpd_stab)) {
  knitr::kable(.vpd_stab$signal[order(-.vpd_stab$signal$share, na.last = TRUE), ], digits = 2, row.names = FALSE)
}
```

| variable | share | refits |
|----------|-------|--------|

Table 5: How often each variable was in the signal set across the
refits, most often first

## Reading the result

**Missing values.** With `NA_ACTION <- "na.impute"`, missing values in
the variables were imputed once by random forest
(`randomForestSRC::impute()`, 250 trees) from the other variables, never
from `OUTCOME`, before the noise columns were added and before the
stability refits drew their patients. A variable missing in more than
`MAX_MISSING` of the patients is refused, not filled. Patients missing
`OUTCOME`, when it is set, were excluded. With `"na.omit"`, every
patient missing a variable was excluded instead. The table of missing
values above gives the counts either way.

**An edge is dependence in the data, not a cause.** It says that one
variable helps tell apart the patients another variable’s rules pick
out. Its arrow reads “the variable at the head helps separate the
contrast of the variable at the tail”, which is a statement about how
the data are arranged, not about which variable acts on which.

**A variable the forest did not examine is not an independent one.** It
has no rule of its own, so no edge leaves it in the graph: an edge it
lacks is missing because it was not looked at, not because the variable
is independent. Edges into it can still appear, because it is a
predictor in every other variable’s lasso. The coverage table says which
variables those are, and the render stops when their share passes
`MAX_UNTESTED` and their count passes `MIN_UNTESTED`, unless
`MAX_UNTESTED` is `NULL`.

**A variable with no edge is not an independent one.** A variable with
no edge at the bar has no link strong enough to beat the noise in this
forest. It may still depend on others more weakly, and the heatmap shows
every pair at any strength.

**The bar is chance, measured in this fit.** It is the largest weight a
permuted copy reached, so it moves with the data and the settings in a
way varPro’s fixed 0.25 does not. Read the stability tables before the
graph: an edge drawn in the full fit but rarely in the refits is a weak
one.

**An outcome among the variables is shared structure.** When `OUTCOME`
is set, an edge to an outcome column says that variable and the outcome
vary together among these patients. It is not a prediction, and nothing
here was fitted to predict the outcome.

Code

``` r
# The product of this job: the fit, the matrix, the bar and what it kept, in
# one file so they cannot drift apart.
vpd_handoff <- hvtiRtemplates:::.attach_handoff_lineage(
  list(fit = fit, beta = beta, bar = bar$bar, bar_from = bar$from, edges = gg$edges, signal = signal,
       stability = .vpd_stab, not_examined = .not_examined),
  data = .provenance_data, analysis = .analysis, cohort = .cohort,
  selection = attr(job_data$record, "selection")
)
saveRDS(vpd_handoff, set_path("estimates", "dependence.rds"))
```

## About this run

| Group           | Item           | Value                      |
|:----------------|:---------------|:---------------------------|
| Run             | Started        | 2026-11-20 17:39:10 EST    |
|                 | Ended          | 2026-11-20 17:42:10 EST    |
|                 | Duration       | 3 min 0 s                  |
|                 | Status         | final                      |
|                 | Rendered by    | gallery                    |
|                 | Host           | gallery                    |
| Job             | File           | vp.dependence.preop.vp.qmd |
|                 | Template       | vp.dependence              |
|                 | Subject        | preop                      |
|                 | Type           | vp                         |
|                 | hvtiRtemplates | 1.6.2                      |
| Dataset `built` | Version file   | built_20261120.parquet     |
|                 | Version date   | 2026-11-20                 |
|                 | Source file    | built.rds                  |
|                 | Rows kept      | 800 rows on 800 patients   |
|                 | WHERE          | none                       |
|                 | sha256         | d99147a5c095               |
|                 | Manifest       | current                    |
| Reproducibility | Seed           | 2026                       |
|                 | renv           | not active                 |
