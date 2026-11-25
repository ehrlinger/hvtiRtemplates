# SID clustering: fit

# SID clustering: fit

Published

2026-11-25 13:21

This job builds the dissimilarity that `sid-clusters` turns into
clusters. SID clustering (Mantero and Ishwaran, 2021) is unsupervised:
there is no outcome. It stretches the clustering variables into
staggered copies and their pairwise interactions, grows a multivariate
random forest predicting the one from the other, and measures how often
two patients fall in the same terminal nodes. Two patients the forest
cannot tell apart are close.

The forest needs complete data, so the job first drops variables that
are mostly missing and fills the rest with one imputation, unless the
data arrive complete. The imputed values stay inside this job. Whatever
describes the clusters later reads the study data, so it describes what
was measured, not what was imputed.

This template is **in flight**: no study has yet run it end to end.

Code

``` r
SUBJECT <- "echo"
TYPE    <- "sid"
.in <- knitr::current_input(dir = TRUE)
suppressPackageStartupMessages({
  library(randomForestSRC)
  library(mice)
  library(hvtiRutilities)
})
# One thread, so a fit reproduces from machine to machine. Left unset,
# randomForestSRC runs on every core its OpenMP build can see, and the forest
# changes with the thread count with every seed held fixed.
options(rf.cores = 1L, mc.cores = 1L)
# The oldest versions this template works with.
# randomForestSRC 3.7.0 is the release the random forest templates were written
# and tested against (2026-09-19); this job copied the floor from them. It needs
# nothing new in 3.7.0: sidClustering() has taken every argument used here since
# 3.4.5 at least, and 3.7.0 changed survival prediction and added a hybrid
# distance, neither used here. randomForestSRC is
# in Suggests, so the floor gates this job, not installing hvtiRtemplates. To
# reproduce an analysis, match its version: from 3.10.0 the same seed grows a
# different forest (rfsrc.RNGversion() selects the old generator).
if (utils::packageVersion("randomForestSRC") < "3.7.0") {
  stop("This job needs randomForestSRC >= 3.7.0; ", utils::packageVersion("randomForestSRC"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
if (utils::packageVersion("mice") < "3.19.0") {
  stop("This job needs mice >= 3.19.0; ", utils::packageVersion("mice"),
       " is installed.\nUpdate it, then re-render.", call. = FALSE)
}
# To render a job you have not finished, leave a chunk out with the chunk
# option skip, giving the reason in quotes, or call hvtiRtemplates::stop_here()
# in a chunk to leave out everything below it. A draft lists each one in a
# callout; a final render refuses them, as it refuses an unresolved marker.
# ?stop_here has more.
.job <- hvtiRtemplates:::.job_setup(SUBJECT, TYPE, envir = environment())
.root <- .job$root
set_path <- .job$set_path
.provenance_data <- list()
# `sid-fit` writes sid.rds and `sid-clusters` reads it, both by set.
# The draft banners, if any, and the box under the title, after all the code above.
.job$notice
```

**final** · data `built` `built_20261125.parquet`, dated 2026-11-25 ·
rendered by gallery on gallery · hvtiRtemplates 1.6.3

## Study choices

Edit these values for this study before rendering.

Code

``` r
# Demo: the registered dataset this job reads ("built" is the study dataset).
# A file name, such as "match_set.rds", reads an unregistered file in the datasets folder, as a draft.
DATASET <- "built"

# Demo: an hvtiRdatabuild analysis set, or NULL to read the whole dataset.
ANALYSIS_SET <- NULL

# Demo: rows to keep, dplyr::filter() style, or NULL to keep every row:
#   WHERE <- quote(age >= 18)
WHERE <- NULL

# Demo: the patient identifier. If the data has no "ccfid" column, the job uses MRN, then eMRN;
# name another column, such as "randid", if the study uses one.
ID <- "patient_id"

# Demo: what makes a row unique. Clustering is one row per patient.
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
#     record silently would be a hidden choice. This job clusters one row per
#     patient, so a long JOIN without REDUCE stops here.
#   JOIN_KEY: overrides the joined dataset's registered key.
JOIN <- NULL
JOIN_VARS <- NULL
REDUCE <- NULL
JOIN_KEY <- NULL

# Demo: the clustering variables. These DEFINE the clusters: two patients are
# close when they are alike on these. Name measurements of the thing being
# grouped (anatomy, physiology), never an outcome: clustering on survival and
# then comparing survival by cluster answers its own question. Factors are
# allowed, but each adds staggered copies and interactions to the forest.
VARS <- c("lvedd", "lvesd", "la_diam", "rvsp", "e_e", "lvef")

# Demo: optionally, clustering variables to treat as categories rather than
# numbers, such as a graded degree (0 to 4) or a coded class (1 to 3):
#   FACTORS <- c("<graded variable>", "<coded variable>")
# sidClustering() staggers and interacts a factor differently from a number,
# so this changes the forest and the clusters. NULL keeps every variable that
# is not text a number, as this job always has. To match an analysis that ran
# hvtiRutilities::r_data_types() first, list the variables it made factors
# (by default, numbers with 3 to 9 distinct values). A 0/1 indicator needs
# nothing: the forest treats it the same whether it is a number or logical.
FACTORS <- NULL

# Demo: a variable missing in more than this share of patients is dropped and
# listed, not imputed. An imputation that invents most of a column decides the
# clusters it was meant to inform.
MAX_MISSING <- 0.4

# Demo: the forest. NTREE = 5000 is what the studies behind this template
# used. SID_REDUCE = TRUE runs sidClustering's holdout-VIMP step, which drops
# staggered variables that carry no structure; it is slow, and recommended
# with more than a handful of variables because the interactions grow with the
# square of their number. (It is not the join's REDUCE above.)
NTREE <- 1000
SID_REDUCE <- TRUE

# Demo: optionally, other sidClustering() arguments by name, to match an
# analysis that set them:
#   SID_ARGS <- list(ntree.reduce = 200, dist.sharpen = FALSE, nodesize = 5)
# sidClustering()'s own arguments are taken, and the rfsrc() arguments it hands
# on to the forest (mtry, nodesize). Each changes the distance. The ones this
# job sets above (data, method, ntree, reduce, seed, k), the formula and
# na.action are refused, and so are x.no.sid, case.wt and samp: they hold
# patient data, and SID_ARGS is recorded in the report. list() makes the call
# this job has always made, so caches from before SID_ARGS still load.
SID_ARGS <- list()

# Demo: how missing values are filled before the forest, which needs complete
# data. "mice" uses predictive mean matching; "forest" uses randomForestSRC's
# own imputation. "none" imputes nothing, for data already completed upstream,
# such as one draw of the imputation a published analysis used: the job stops
# if a clustering variable is missing anywhere, and needs M = 1. M is the
# number of imputations: with M > 1 one SID forest is grown on each and their
# distances are averaged, so the clusters reflect more than one draw of the
# missing values, at M times the cost. MICE_MAXIT is the number of mice
# iterations, used by "mice" only.
IMPUTE <- "mice"
M <- 1
MICE_MAXIT <- 50

# Demo: the seed. Imputation m and its forest use SEED + m - 1: it is part of
# each cache key, sets R's generator for the call (cache_fit() runs it under
# that seed), and is handed to sidClustering() as `seed =`. Both matter:
# SID_REDUCE = TRUE draws from R's generator as well as from the forest's seed.
SEED <- 1024

# Set TRUE after changing a choice above. A cache whose inputs changed stops the
# render instead of returning the old result; TRUE recomputes only the caches
# that are out of date.
REFIT <- FALSE
```

## Cohort

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
.id <- attr(job_data$record, "selection")$id
if (tolower(.id) %in% tolower(VARS)) {
  stop("VARS names the patient identifier `", .id, "`. Remove it: an ID is not a measurement.", call. = FALSE)
}
.absent <- setdiff(tolower(VARS), names(d))
if (length(.absent)) {
  stop("VARS names column(s) the data do not have: ", toString(.absent), ".", call. = FALSE)
}
VARS <- tolower(VARS)
# sidClustering() staggers each variable by its range, which a text column does
# not have, so text variables are converted to factors here, and named.
.chr <- VARS[vapply(d[VARS], is.character, logical(1L))]
if (length(.chr)) {
  d[.chr] <- lapply(d[.chr], factor)
  cat("Text variables converted to factors: ", paste(.chr, collapse = ", "), "\n", sep = "")
}
# The variables FACTORS declares are factors too, before the missing values are counted and imputed, so
# the imputation fills them with one of their levels and the forest treats them as categories.
if (!is.null(FACTORS)) {
  if (!is.character(FACTORS) || anyNA(FACTORS)) {
    stop("FACTORS must be NULL or the names of clustering variables, such as c(\"grade\").", call. = FALSE)
  }
  FACTORS <- unique(tolower(FACTORS))
  .not_var <- setdiff(FACTORS, VARS)
  if (length(.not_var)) stop("FACTORS names variable(s) not in VARS: ", toString(.not_var), ".", call. = FALSE)
  d[FACTORS] <- lapply(d[FACTORS], factor)
  cat("Variables declared as factors: ", paste(FACTORS, collapse = ", "), "\n", sep = "")
}
.empty <- rowSums(!is.na(d[VARS])) == 0
d <- d[!.empty, , drop = FALSE]
if (nrow(d) == 0L) {
  stop("No patients are left: every patient is missing every clustering variable in VARS. Check the names in VARS.",
       call. = FALSE)
}
cat("Patients with every clustering variable missing, dropped:", sum(.empty), "\n")
```

    Patients with every clustering variable missing, dropped: 0 

| Data                |                                          |
|:--------------------|:-----------------------------------------|
| Source              | dataset `built` (built_20261125.parquet) |
| Rows read           | 800                                      |
| ID                  | `patient_id`                             |
| Identifiers dropped | none                                     |
| Rows kept           | 800 rows on 800 patients                 |

Table 1: The data this job read

## Missing values

Code

``` r
.miss <- vapply(d[VARS], function(x) mean(is.na(x)), numeric(1))
sid_dropped <- data.frame(variable = character(0), reason = character(0))
.sparse <- names(.miss)[.miss > MAX_MISSING]
if (length(.sparse)) {
  .why <- paste0("missing in more than ", 100 * MAX_MISSING, "%")
  sid_dropped <- rbind(sid_dropped, data.frame(variable = .sparse, reason = .why))
}
.flat <- VARS[vapply(d[VARS], function(x) length(unique(stats::na.omit(x))) < 2L, logical(1))]
.flat <- setdiff(.flat, .sparse)
if (length(.flat)) sid_dropped <- rbind(sid_dropped, data.frame(variable = .flat, reason = "one value only"))
sid_vars <- setdiff(VARS, sid_dropped$variable)
if (length(sid_vars) < 2L) stop("Fewer than two clustering variables are left to cluster on.", call. = FALSE)
# A patient seen only on a variable just dropped has nothing left to cluster on, and the forest
# imputation would drop that row without saying, leaving the distance a row short of the cohort.
.bare <- rowSums(!is.na(d[sid_vars])) == 0
d <- d[!.bare, , drop = FALSE]
if (nrow(d) == 0L) {
  stop("No patients are left: every patient is missing every retained clustering variable.", call. = FALSE)
}
cat("Patients with every retained clustering variable missing, dropped:", sum(.bare), "\n")
```

    Patients with every retained clustering variable missing, dropped: 0 

Code

``` r
knitr::kable(data.frame(variable = names(.miss), missing = sprintf("%.1f%%", 100 * .miss),
                        kept = names(.miss) %in% sid_vars))
```

| variable | missing | kept |
|:---------|:--------|:-----|
| lvedd    | 5.4%    | TRUE |
| lvesd    | 4.6%    | TRUE |
| la_diam  | 5.8%    | TRUE |
| rvsp     | 4.2%    | TRUE |
| e_e      | 5.4%    | TRUE |
| lvef     | 0.0%    | TRUE |

Table 2: Share of patients missing each clustering variable

## Imputation

The forest needs complete data. Each imputation fills the missing values
once, by predictive mean matching (`"mice"`) or by randomForestSRC’s
forest imputation (`"forest"`). With one imputation the filled values
are treated as known, so the cluster boundaries are conditional on one
draw; with several, the forests’ distances are averaged below. Either
way, nothing later describes the clusters with imputed values. With
`IMPUTE = "none"` this job imputes nothing: the data must be complete as
supplied, for example imputed upstream, and the job stops if they are
not.

Code

``` r
if (!is.character(IMPUTE) || length(IMPUTE) != 1L || !IMPUTE %in% c("mice", "forest", "none")) {
  stop("IMPUTE must be \"mice\", \"forest\" or \"none\".", call. = FALSE)
}
if (!is.numeric(M) || length(M) != 1L || M < 1 || M != trunc(M)) stop("M must be a whole number, 1 or more.", call. = FALSE)
CACHE_DIR <- dirname(set_path("estimates", "sid.rds"))
.to_impute <- d[sid_vars]
.n_missing <- sum(is.na(.to_impute))
if (identical(IMPUTE, "none")) {
  # Complete data give M identical forests but for their seeds, which is not M imputations.
  if (M != 1) stop("IMPUTE = \"none\" needs M = 1: with nothing imputed there is one dataset.", call. = FALSE)
  .gaps <- colSums(is.na(.to_impute))
  .gaps <- .gaps[.gaps > 0L]
  if (length(.gaps)) {
    stop("IMPUTE = \"none\", but clustering variables have missing values: ",
         paste0(names(.gaps), " (", .gaps, ")", collapse = ", "),
         ". Supply completed data, drop the variables from VARS, or choose \"mice\" or \"forest\".", call. = FALSE)
  }
  cat("No imputation (IMPUTE = \"none\"): the clustering variables were complete as supplied.\n")
}
# Imputation m is cached under its own name and seeded SEED + m - 1, so raising
# M later reuses the imputations already made.
# The cache keys on this code as written, so it must not change: an imputation cached by an earlier copy of
# this job then still loads.
.impute_mice <- quote(mice::mice(.to_impute, m = 1, maxit = MICE_MAXIT, method = "pmm", printFlag = FALSE))
.impute_forest <- quote(randomForestSRC::impute(data = .to_impute, ntree = 250, verbose = FALSE))
.impute_code <- if (identical(IMPUTE, "mice")) .impute_mice else .impute_forest
.todo <- .n_missing > 0L & vapply(seq_len(M), function(m) {
  hvtiRutilities::cache_would_fit(paste0("sid-fit-impute-", m), .impute_code, seed = SEED + m - 1L, dir = CACHE_DIR,
                                  refit = REFIT)
}, logical(1L))
# Each imputation that runs is reported to job_status() and the render log as done of total, with an estimate
# of what is left. Imputations read from the cache are not counted. Outside a render the reporter is NULL.
.tick <- .job$progress("imputation")
d_complete <- lapply(seq_len(M), function(m) {
  if (.n_missing == 0L) return(.to_impute)
  s <- SEED + m - 1L
  out <- if (identical(IMPUTE, "mice")) {
    mice::complete(cache_fit(paste0("sid-fit-impute-", m), .impute_mice, seed = s, dir = CACHE_DIR, refit = REFIT), 1)
  } else {
    cache_fit(paste0("sid-fit-impute-", m), .impute_forest, seed = s, dir = CACHE_DIR, refit = REFIT)
  }
  if (.todo[m] && !is.null(.tick)) .tick(sum(.todo[seq_len(m)]), sum(.todo))
  out
})
if (any(vapply(d_complete, nrow, integer(1L)) != nrow(d))) {
  stop("The imputation returned fewer patients than the cohort holds, so the distances could not be matched to patients.",
       call. = FALSE)
}
if (!identical(IMPUTE, "none")) cat("Values imputed in each of", M, "imputation(s):", .n_missing, "\n")
```

    Values imputed in each of 1 imputation(s): 203 

## The SID forest

Code

``` r
# No na.action: the data are complete by now, so a gap here is a bug and should stop the
# job. Before randomForestSRC 3.10.0, sidClustering() failed on a missing value even with
# na.action = "na.impute"; from 3.10.0 it applies na.action first, omitting incomplete rows
# by default, which would hide the gap instead.
# cache_fit(seed = ) runs each fit under withr::with_seed(), which sets R's
# generator for the holdout-VIMP step; `seed =` is the forest's own.
# sidClustering() catches an error inside randomForestSRC and returns dist = NULL
# instead of stopping, so the check inside the cached expression turns that into
# a stop: a failed fit is then never cached, and the message names the imputation.
# Only the distance and the kept variables are cached; the forest, which
# holds patient values, is left out of the cache as it is of sid.rds.
.sid_names <- names(SID_ARGS)
if (!is.list(SID_ARGS) || (length(SID_ARGS) && (is.null(.sid_names) || anyNA(.sid_names) || !all(nzchar(.sid_names)) ||
                                                  anyDuplicated(.sid_names)))) {
  stop("SID_ARGS must be list() or a list of sidClustering() arguments, each named once, such as list(fast = TRUE).",
       call. = FALSE)
}
.owned <- intersect(.sid_names, c("data", "method", "ntree", "reduce", "seed", "k", "formula", "na.action"))
if (length(.owned)) {
  stop("SID_ARGS names argument(s) this job sets itself: ", toString(.owned),
       ". Set NTREE, SID_REDUCE, SEED or IMPUTE above instead.", call. = FALSE)
}
# These carry patient data, which SID_ARGS would write into the cache key, sid.rds and the report.
.data_args <- intersect(.sid_names, c("x.no.sid", "case.wt", "samp"))
if (length(.data_args)) {
  stop("SID_ARGS cannot carry patient-level data: ", toString(.data_args), ". It is recorded in the report.",
       call. = FALSE)
}
# The method's formals as well as the generic's, in case a release declares only (data, method, ...) on the generic.
.takes <- unlist(lapply(list(randomForestSRC::sidClustering, randomForestSRC:::sidClustering.rfsrc, randomForestSRC::rfsrc),
                        function(f) names(formals(f))))
.unknown <- setdiff(.sid_names, setdiff(.takes, "..."))
if (length(.unknown)) {
  stop("SID_ARGS names argument(s) neither sidClustering() nor rfsrc() takes: ", toString(.unknown), ".", call. = FALSE)
}
# SID_ARGS is spliced into the call by value, so the call text, and with it the
# cache key, names each argument and changes when one does. With list() the
# call is exactly the one this job made before SID_ARGS existed.
.sid_code <- bquote({
  o <- sidClustering(d_complete[[m]], method = "sid", ntree = NTREE, reduce = SID_REDUCE, seed = -abs(s), ..(SID_ARGS))
  if (is.null(o$dist)) {
    stop("sidClustering() failed on imputation ", m, " (it returned no distance). Look above for the message ",
         "randomForestSRC gave, and check the clustering variables for a constant or near-empty factor.", call. = FALSE)
  }
  o[c("dist", "outcome.names")]
}, splice = TRUE)
.todo <- vapply(seq_len(M), function(m) {
  s <- SEED + m - 1L
  hvtiRutilities::cache_would_fit(paste0("sid-fit-", m), .sid_code, seed = s, dir = CACHE_DIR, refit = REFIT)
}, logical(1L))
# Each forest that grows is reported to job_status() and the render log as the imputations are, above.
.tick <- .job$progress("SID forest")
sid_fits <- lapply(seq_len(M), function(m) {
  if (anyNA(d_complete[[m]])) stop("Missing values reached the SID fit after imputation ", m, ".", call. = FALSE)
  s <- SEED + m - 1L
  f <- cache_fit(paste0("sid-fit-", m), .sid_code, seed = s, dir = CACHE_DIR, refit = REFIT)
  if (.todo[m] && !is.null(.tick)) .tick(sum(.todo[seq_len(m)]), sum(.todo))
  f
})
sid_dist <- Reduce(`+`, lapply(sid_fits, `[[`, "dist")) / M
# How closely each imputation's distances follow the mean. Near 1, the
# imputations agree; well below, the missing values are shaping the distance.
# With nothing missing, every imputation is the same data and the forests differ
# only by their seeds, so the correlation then measures the forest's own Monte
# Carlo noise, not the imputation.
.lower <- function(x) x[lower.tri(x)]
sid_agreement <- data.frame(
  imputation = seq_len(M),
  correlation_with_mean = vapply(sid_fits, function(f) stats::cor(.lower(f$dist), .lower(sid_dist)), numeric(1))
)
```

Code

``` r
.factors_used <- sid_vars[vapply(d[sid_vars], is.factor, logical(1L))]
knitr::kable(data.frame(
  step = c("Clustering variables", "Treated as factors", "Dropped before the fit", "Kept by the reduce step",
           "Imputation", "Patients"),
  value = c(toString(sid_vars), if (length(.factors_used)) toString(.factors_used) else "none",
            if (nrow(sid_dropped)) toString(sid_dropped$variable) else "none",
            toString(unique(unlist(lapply(sid_fits, `[[`, "outcome.names")))),
            if (identical(IMPUTE, "none")) "none: complete as supplied" else
              if (.n_missing == 0L) "none needed" else paste0(IMPUTE, ", ", M, " imputation(s)"),
            nrow(sid_dist))
), col.names = c("", ""))
```

|                         |                                        |
|:------------------------|:---------------------------------------|
| Clustering variables    | lvedd, lvesd, la_diam, rvsp, e_e, lvef |
| Treated as factors      | none                                   |
| Dropped before the fit  | none                                   |
| Kept by the reduce step | rvsp, e_e, lvesd, lvedd, la_diam       |
| Imputation              | mice, 1 imputation(s)                  |
| Patients                | 800                                    |

Table 3: What the forests were grown on

## Save

Code

``` r
# The product of this job, and what sid-clusters and vt-fit read. It is
# separate from the cache on purpose: cache_fit() stores a keyed record, so the
# cache is this job's internals and this file is its interface. The forests
# are not saved, here or in the caches: nothing downstream reads them, and they
# are the large part.
# Patients are named by a study-keyed digest of their ID, never the ID itself
# (#203), so the file can be matched on without holding an MRN.
if (nrow(sid_dist) != nrow(d)) {
  stop("The distance holds ", nrow(sid_dist), " patients but the cohort holds ", nrow(d), ".", call. = FALSE)
}
.key <- hvtiRtemplates:::.study_id_key(.root)
dimnames(sid_dist) <- rep(list(hvtiRtemplates:::.id_digest(d[[.id]], .key)), 2L)
.cohort <- list(n = as.integer(nrow(d)))
sid_handoff <- hvtiRtemplates:::.attach_handoff_lineage(
  list(dist = sid_dist, id_key = hvtiRtemplates:::.id_key_fingerprint(.key), vars = sid_vars, dropped = sid_dropped,
       reduced = unique(unlist(lapply(sid_fits, `[[`, "outcome.names"))),
       # The completed data each forest saw, so sid-stability can refit on exactly these values.
       data_fingerprint = vapply(d_complete, hvtiRtemplates:::.sid_data_fingerprint, character(1)),
       settings = list(ntree = NTREE, sid_reduce = SID_REDUCE, seed = SEED, impute = IMPUTE, m = M,
                       mice_maxit = MICE_MAXIT, max_missing = MAX_MISSING,
                       # The declared factors that were clustered on, which sid-stability converts the same way.
                       factors = if (length(intersect(FACTORS, sid_vars))) intersect(FACTORS, sid_vars),
                       # The other sidClustering() arguments the forests were grown with; list() for the defaults.
                       sid_args = SID_ARGS)),
  data = .provenance_data,
  cohort = .cohort,
  selection = attr(job_data$record, "selection")
)
saveRDS(sid_handoff, set_path("estimates", "sid.rds"))
```

## About this run

| Group           | Item           | Value                    |
|:----------------|:---------------|:-------------------------|
| Run             | Started        | 2026-11-25 13:21:48 EST  |
|                 | Ended          | 2026-11-25 13:21:53 EST  |
|                 | Duration       | 4 s                      |
|                 | Status         | final                    |
|                 | Rendered by    | gallery                  |
|                 | Host           | gallery                  |
| Job             | File           | sid.fit.echo.sid.qmd     |
|                 | Template       | sid.fit                  |
|                 | Subject        | echo                     |
|                 | Type           | sid                      |
|                 | hvtiRtemplates | 1.6.3                    |
| Dataset `built` | Version file   | built_20261125.parquet   |
|                 | Version date   | 2026-11-25               |
|                 | Source file    | built.rds                |
|                 | Rows kept      | 800 rows on 800 patients |
|                 | WHERE          | none                     |
|                 | sha256         | d99147a5c095             |
|                 | Manifest       | current                  |
| Reproducibility | Seed           | 1024                     |
|                 | renv           | not active               |
