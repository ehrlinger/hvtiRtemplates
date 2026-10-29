# Multivariable hazard model

# Multivariable hazard model

Published

2026-10-29 10:31

An `hm` job builds the risk-factor model **on top of** the shape
parameters the `hz` job fitted. The shapes are not re-derived here; they
are read. Patient-level predictions from this model are an `hs` job and
the bootstrap of this screen is `bh`; neither belongs here, and **nor
does SAS parity** — a parity job borrows the ordinal of the job it
checks and lives in `parity/`.

Code

``` r
SUBJECT <- "dead"
TYPE    <- "hz"
.in <- knitr::current_input(dir = TRUE)
.provenance_artifacts <- list()
suppressPackageStartupMessages({
  library(TemporalHazard)
  library(hvtiRutilities)
})
# numDeriv is a Suggests of TemporalHazard, not a hard dependency. Without it,
# interval- or left-censored multiphase fits SILENTLY produce no standard
# errors: the fit succeeds, `converged` is TRUE, and vcov() is simply absent.
# A model with forty covariates and no standard errors is not a smaller result,
# it is a different one -- so this is a hard stop.
if (!requireNamespace("numDeriv", quietly = TRUE)) {
  stop("numDeriv is not installed. Interval-censored multiphase fits will ",
       "produce no standard errors, and will not tell you so. Install it ",
       "before reading anything below.", call. = FALSE)
}
# The study root is the nearest directory above this file holding _study.yml,
# so the job renders the same from the Render button, quarto render, or
# render_job(), at any depth, with no path in this document to edit.
# Without the guard in .job_setup(), an unedited job renders green over a
# meaningless analysis. In THIS file the danger is sharper than a wrong number:
# the unedited entry and stay levels are `hzr_stepwise()`'s defaults, which are
# LOOSER than the SAS job's, so an unedited screen admits variables the job
# being reproduced rejected -- and reports them as risk factors, in a table that
# looks exactly like a result.
# To render a job you have not finished, leave a chunk out with the chunk
# option skip, giving the reason in quotes, or call hvtiRtemplates::stop_here()
# in a chunk to leave out everything below it. A draft lists each one in a
# callout; a final render refuses them, as it refuses an unresolved marker.
# ?stop_here has more.
.job <- hvtiRtemplates:::.job_setup(SUBJECT, TYPE, envir = environment())
.root <- .job$root
set_path <- .job$set_path
.provenance_data <- list()
# The figures draw with hvtiPlotR. Checked here, before the fit, so a missing
# package stops the render at once rather than after the fit and before the save.
if (!requireNamespace("hvtiPlotR", quietly = TRUE)) stop("This job needs hvtiPlotR for its figures.", call. = FALSE)
# Saves a figure as <name>.png, .pdf and .tiff in this set's graphs/ folder,
# under the SAVE_FIGURES and FIGURES study choices.
save_figure <- function(plot, name, width = 6, height = 4, kind = "graphs", linked = FALSE) {
  hvtiRtemplates:::.save_figure(plot, set_path(kind, paste0(name, ".png")), width, height,
                                SAVE_FIGURES, FIGURES, linked)
}
# `hm` reads the `hz` fit through this and writes its own model back, both by
# set, so a model can never be filed against a different set than the shapes it
# was built on. The write is in the `save` chunk at the foot of this file.
# The draft banners, if any, and the box under the title, after all the code above.
.job$notice
```

**final** · data: see About this run · rendered by gallery on gallery ·
hvtiRtemplates 1.5.4

## Study choices

Edit these values for this study before rendering.

Code

``` r
# The data, rows, identifier, time and event of the hz fit this model builds
# on. NULL takes the value hz used; set it only to confirm it. A value set here
# that differs from hz's stops the job rather than fit another cohort.
DATASET <- NULL
ANALYSIS_SET <- NULL
WHERE <- NULL
ID <- NULL
KEY <- NULL
TIME <- NULL
EVENT <- NULL

# No expected counts here: they are typed once, in the hz job, and hz.rds
# carries them. The cohort chunk checks this job's rows against them.

# Demo: SAS job and macro holding covariate blocks. NULL for a study with no
# SAS job, which then lists COVARIATES per phase in the edit-covariates chunk.
SAS_JOB   <- c("analyses", "hm.dead.sas")

SAS_MACRO <- "^\\s*%macro\\s+model\\s*;"

# Phase shape and scale parameters.
# Demo: phase shape and scale parameter names.
SHAPE_PARAMS <- c("early.log_mu", "early.log_t_half", "early.nu", "early.m",
                  "late.log_mu", "late.log_tau", "late.gamma", "late.alpha",
                  "late.eta")

# Selection levels and maximum number of steps.
# Demo: selection settings from the SAS job.
SLENTRY   <- 0.1     # SAS sle=

SLSTAY    <- 0.07    # SAS sls=

MAX_STEPS <- 50L     # SAS maxsteps=

# Calibration horizon.
# Demo: calibration horizon.
DECILE_TIME <- 10

# Each figure is saved to graphs/ as a PNG (for Word), and a PDF and a TIFF (for the publisher).
# SAVE_FIGURES <- FALSE saves none; FIGURES keeps only the figures whose names
# start with one of its entries, e.g. FIGURES <- c("hm-calibration").
SAVE_FIGURES <- TRUE
FIGURES <- NULL
```

## Cohort

Code

``` r
# The checksum of every dataset in manifest.yaml is checked before anything is
# read, so a result can name the data that produced it. It stops on a mismatch.
hvtiRutilities::verify_manifest(file.path(.root, "manifest.yaml"))
.cfg <- study_config(start = .root)
# The shape values come from the companion hz job, NOT from a literal. This is
# what "builds on the HZ fit" means concretely: SAS holds the shapes with
# `fixthalf fixnu fixm fixeta` while it screens covariates.
.hz_read <- hvtiRtemplates:::.read_handoff(
  set_path("estimates", "hz.rds"), "hazard-shape-model", .cfg, "the hz job"
)
hz_art <- .hz_read$value
.provenance_data <- c(.hz_read$lineage$data, .provenance_data)
.provenance_artifacts <- c(.hz_read$lineage$artifacts, list(.hz_read$record))
```

Code

``` r
.up <- hvtiRtemplates:::.read_upstream_job_data(
  .cfg, .hz_read$lineage,
  list(dataset = DATASET, analysis_set = ANALYSIS_SET, where = WHERE, id = ID, key = KEY,
       time = TIME, event = EVENT),
  source = "hz.rds"
)
job_data <- .up$job_data
d <- job_data$data
TIME <- .up$selection$time
EVENT <- .up$selection$event
# NULL unless hz was fitted on start/stop rows, when it names the segment start.
START <- .up$selection$start
# Start/stop calibration needs an hzr_deciles() that subtracts H(start).
hvtiRtemplates:::.check_start_engine(START)
.provenance_data <- c(if (exists(".provenance_data")) .provenance_data else list(), list(job_data$provenance),
                      if (!is.null(job_data$provenance_join)) list(job_data$provenance_join))
knitr::kable(job_data$record, col.names = c("Data", ""))
```

| Data                |                                          |
|:--------------------|:-----------------------------------------|
| Source              | dataset `study` (built_20261029.parquet) |
| Rows read           | 800                                      |
| ID                  | `patient_id`                             |
| Identifiers dropped | none                                     |
| `!is.na(creat_pr)`  | removed 75                               |
| Rows kept           | 725 rows on 725 patients                 |

Table 1: The data this job read, as hz read it

Code

``` r
# The counts hz.rds records, from hz's EXPECTED; a mismatch names both.
cc <- hvtiRtemplates:::.check_upstream_cohort(d, .hz_read$lineage, event = EVENT, time = TIME, source = "hz.rds")

knitr::kable(data.frame(
  quantity = c("n_analysable", "n_events", "n_censored"),
  n        = c(cc$n, cc$n_events, cc$n_censored)
))
```

| quantity     |   n |
|:-------------|----:|
| n_analysable | 725 |
| n_events     | 406 |
| n_censored   | 319 |

Table 2: Analysable patients, events and censored patients

A rendered report is itself evidence the gate passed. Report the counts
anyway — a gate that passes silently tells the reader nothing about what
it passed on.

**An event flag that is 0/1 in SAS may arrive as `logical`**, because
`read_clinical_data()` infers binary columns as logical while `Surv()`
requires a numeric status. The `as.numeric()` coercions below are not
decoration — and see the covariate audit above for the same problem on
the covariate side, where it changes the model rather than erroring.

## Covariates

The covariate blocks are **read out of the SAS job**, not transcribed. A
transcribed list drifts from the job it claims to reproduce and nothing
catches it. Only the names are taken: the `name=value` coefficients in a
block are the *other* study’s answers and must not be inherited by a
copy of it.

Code

``` r
# your time, event and interval-censoring variables -- SAS `time`,
# `event`, and the flag named by `icensor X=`.

# the SAS job to read the candidate blocks from, and the macro inside it
# that holds the model. Naming the MACRO matters: a job commonly defines
# several, and they do not agree.
#
# ⚠️ A macro can be defined and never invoked. One real job carries a `%final`
# whose variable list is another study's variables entirely, pasted in and left
# there; the `.lst` shows only the macro that ran. Read the `.sas` and check
# which macro is actually called before naming it here.
```

Code

``` r
# The covariates offered to each phase, one entry per phase of the hz fit and
# named as it names them. A SAS hazard model offers candidates per phase and the
# blocks need not be identical, so a covariate is estimated only in the phases
# whose entry names it.
#
# Demo: where the lists come from. With SAS_JOB set they are read from that
# job's phase blocks, by the markers below. A study with no SAS job sets
# SAS_JOB <- NULL above and lists them here, in place of the read:
#   COVARIATES <- list(early = c("age", "hx_chf"), late = c("age", "creat_pr"))
sas_lines <- if (!is.null(SAS_JOB)) readLines(do.call(sas_path, as.list(SAS_JOB)), warn = FALSE)
COVARIATES <- if (!is.null(sas_lines)) list(
  early = sas_variable_block(sas_lines, "^\\s*early\\s*$", after = SAS_MACRO,
                             what = "early covariate block"),
  late  = sas_variable_block(sas_lines, "^\\s*late\\s*$",  after = SAS_MACRO,
                             what = "late covariate block")
)
if (!is.list(COVARIATES) || !length(COVARIATES)) {
  stop("No covariates to offer. Set SAS_JOB to the SAS job holding the phase blocks, or list COVARIATES ",
       "per phase in the edit-covariates chunk.", call. = FALSE)
}
```

Code

``` r
knitr::kable(data.frame(
  phase     = names(COVARIATES),
  n         = vapply(COVARIATES, length, integer(1)),
  variables = vapply(COVARIATES, paste, character(1), collapse = ", "),
  source    = if (is.null(SAS_JOB)) "listed in this job" else paste0("SAS job ", SAS_JOB[[length(SAS_JOB)]]),
  row.names = NULL
))
```

| phase |   n | variables                | source              |
|:------|----:|:-------------------------|:--------------------|
| early |   3 | age, creat_pr, hx_chf    | SAS job hm.dead.sas |
| late  |   4 | age, hx_chf, lvef, hx_dm | SAS job hm.dead.sas |

Table 3: Number and names of the covariates in each phase, and where the
lists came from

### What these columns are, before they become covariates

`vars.sas`, called as `%vars(missing=1, impute=1)`, fills a column’s
missing values with the column mean and adds a paired `ms_*` flag
marking the rows it filled. Those `ms_*` flags are themselves covariates
here. It also means a yes/no variable can show a third value: 0, 1, or
the mean. One real column reads `0.714`, the share of the cohort with
hypertension, not any one patient’s status. That is expected, not a data
error.

What changes in R is how these columns are read. In SAS they are numbers
and enter the model as numbers. R can read them as factors instead, and
it treats a factor as a set of categories (R calls this dummy-coding).
That turns “this value was imputed” into its own category with its own
coefficient, which is a different model from the SAS one, and nothing in
the output would say so. The chunk below converts the model’s columns
back to plain numbers, so the fit matches the SAS job.

Code

``` r
audit <- covariate_audit(d, unlist(COVARIATES))
knitr::kable(audit, row.names = FALSE)
# Fail rather than fit a model whose covariates are not what the job specifies.
if (any(grepl("^ERROR", audit$action))) {
  stop("covariate_audit() reports ERROR for: ",
       paste(audit$variable[grepl("^ERROR", audit$action)], collapse = ", "),
       ". Resolve these before fitting.", call. = FALSE)
}

# hazard() cannot take a missing value, and failed on one with "Predictor rows
# must match the length of 'time'", naming neither the column nor why. Stop
# here instead, naming each column and how many rows it is missing.
invisible(hvtiRtemplates:::.missing_cases(d, START = START, TIME = TIME, EVENT = EVENT, COVARIATES = unlist(COVARIATES),
                                          action = "stop"))

# Only the columns the model uses. A hazard() fit keeps a copy of its data,
# which is saved in hm.rds, and `d` also holds the patient identifier.
dd <- covariates_to_numeric(d[unique(c(START, TIME, EVENT, unlist(COVARIATES)))], unlist(COVARIATES))
```

| variable | storage | n_levels | noninteger_levels | action          |
|:---------|:--------|---------:|:------------------|:----------------|
| age      | numeric |       63 | NA                | left as numeric |
| creat_pr | numeric |      147 | NA                | left as numeric |
| hx_chf   | integer |        2 |                   | left as numeric |
| lvef     | numeric |       53 | NA                | left as numeric |
| hx_dm    | integer |        2 |                   | left as numeric |

Table 4: Covariate storage and the conversion applied

One column can be genuinely categorical, and there a factor is the right
call. The `action` column records what was done to each one. Read it
before you read any coefficient.

Code

``` r
# What concept grouping structurally CANNOT catch. Grouping works on
# transformations; two candidates that are the same information under unrelated
# names share no affix relationship and are invisible to it.
#
# `male` and `female` are the case that got through a real screen: exact
# complements, both offered, and 101 of 500 replicates selected BOTH. A design
# holding both is singular, and nothing in the output said so.
collinear <- pool_collinear_pairs(dd, unlist(COVARIATES))
if (nrow(collinear)) {
  knitr::kable(collinear, row.names = FALSE, digits = 4)
} else {
  knitr::kable(data.frame(result = "no candidate pair reaches |r| = 0.99"))
}
```

| result                                 |
|:---------------------------------------|
| no candidate pair reaches \|r\| = 0.99 |

Table 5: Candidate pairs at \|r\| \>= 0.99

An exact `complement` is a coding duplicate and one of the pair should
simply not be a candidate. A high correlation between genuinely
different measurements is a judgment call about what the model can
identify — make it here, not after reading a coefficient.

## Phases

Code

``` r
# hz_art is the hz job's saved fit, read above with the data it was fitted on.
hz_fit <- hz_art$deterministic

# the shape/scale parameter names your phase specification produces.
# Named explicitly so that anything else in coef() is a covariate -- including
# a dummy column, which would otherwise be silently counted as a shape.

# `fixed` is what makes stage 1 stage 1: shapes held, covariates free.
make_phases <- function(hold_shapes) {
  p <- hz_art$phases
  if (!hold_shapes) return(p)
  # Every shape the phase's family has, as hzr_phase() expands fixed = "shapes":
  # g3 holds tau, gamma, alpha and eta, less one a `constraint` derives (it is
  # computed, and may not be named in `fixed`); cdf and hazard hold t_half, nu
  # and m; constant has none. A phase object has no `par` field to read them
  # from, and reading one held nothing, so stage 1 was stage 2.
  lapply(p, function(ph) {
    derived <- switch(if (is.null(ph$constraint)) "none" else ph$constraint,
                      alpha_gamma_eta = "alpha", eta_gamma = "eta", character(0))
    shapes <- switch(ph$type,
                     g3 = setdiff(c("tau", "gamma", "alpha", "eta"), derived),
                     cdf = , hazard = c("t_half", "nu", "m"),
                     character(0))
    ph$fixed <- union(ph$fixed, shapes)
    ph
  })
}
knitr::kable(data.frame(
  parameter = names(coef(hz_fit)),
  from_hz   = unname(coef(hz_fit))
), digits = 6)
```

| parameter        |   from_hz |
|:-----------------|----------:|
| early.log_mu     | -3.547533 |
| early.log_t_half | -5.413998 |
| early.nu         |  2.693648 |
| early.m          | -0.219787 |
| late.log_mu      | -2.566396 |
| late.log_tau     |  0.000000 |
| late.gamma       |  1.000000 |
| late.alpha       |  1.000000 |
| late.eta         |  0.880007 |

Table 6: Shape parameters inherited from the hz job

## Fitting

### Two stages, and why it is not one

Fitting the shapes and forty covariates together **from a neutral start
lands in the wrong basin, and reports `converged = TRUE` while doing
it.** The stages below mirror what the SAS job itself does: it fixes the
shapes for selection and frees them only for the final fit.

Stage 1 holds the shapes at the `hz` fit and fits the covariates. Stage
2 frees the shapes, starting from stage 1. **The comparison is reported,
not assumed.**

`n_starts > 1` perturbs its restarts randomly, so the fit is not
reproducible without a seed. The RNG state is saved and restored, so
seeding this document does not change random behavior downstream of it.

Code

``` r
old_seed <- if (exists(".Random.seed", .GlobalEnv)) .GlobalEnv$.Random.seed else NULL
set.seed(20260827)   # any fixed value; it must not change between renders

# Each phase carries its own covariates, as the SAS phase blocks do. One
# formula for the model would offer every covariate to every phase, and the
# estimates would then not be comparable with the SAS model this replaces. A
# phase with no entry in COVARIATES is offered none.
# With START, the response is hz's start/stop one, Surv(START, TIME, EVENT).
form <- stats::as.formula(paste0("Surv(", paste(c(START, TIME, EVENT), collapse = ", "), ") ~ 1"))
# Stops on a response that drops the start hz fitted with, or names one it did not.
hvtiRtemplates:::.check_surv_start(form, START, TIME, EVENT)
# Each entry names one phase, once: [[ ]] takes the first of two entries with
# one name and finds nothing in an unnamed list, so either would drop
# covariates without a word.
.names <- names(COVARIATES)
if (is.null(.names) || anyNA(.names) || !all(nzchar(.names)) || anyDuplicated(.names)) {
  stop("Name every COVARIATES entry by its phase, once each, e.g. list(early = c(\"age\"), late = c(\"age\")).",
       call. = FALSE)
}
.unknown <- setdiff(.names, names(hz_art$phases))
if (length(.unknown)) {
  stop("COVARIATES names phases the hz fit does not have: ", paste(.unknown, collapse = ", "),
       ". Its phases are ", paste(names(hz_art$phases), collapse = ", "), ".", call. = FALSE)
}
with_covariates <- function(phases) {
  for (p in names(phases)) {
    rhs <- if (length(COVARIATES[[p]])) paste(COVARIATES[[p]], collapse = " + ") else "1"
    phases[[p]]$formula <- stats::as.formula(paste("~", rhs))
  }
  phases
}

# Demo: conserve = FALSE if the SAS final model carries `noconserve`.
ctl1 <- list(n_starts = 5, maxit = 2000, conserve = FALSE)
ctl2 <- list(n_starts = 1, maxit = 5000, conserve = FALSE)
ph1 <- with_covariates(make_phases(TRUE))
ph2 <- with_covariates(make_phases(FALSE))

# The fits run in an environment holding only what they use. A saved fit keeps
# the environment of its formula and of its call, and hm.rds would then carry
# every object there, `d` and its patient IDs included, whenever these chunks
# run anywhere but the global environment.
fit_env <- list2env(list(dd = dd, form = form, ph1 = ph1, ph2 = ph2, ctl1 = ctl1, ctl2 = ctl2),
                    parent = globalenv())
environment(fit_env$form) <- fit_env
# The phase formulas too: each would otherwise keep this chunk's environment.
for (.ph in c("ph1", "ph2")) {
  for (p in names(fit_env[[.ph]])) environment(fit_env[[.ph]][[p]]$formula) <- fit_env
}
local({
  stage1 <- suppressWarnings(
    hazard(form,
           data = dd,
           dist = "multiphase",
           phases = ph1,
           fit = TRUE,
           control = ctl1)
  )

  stage2 <- suppressWarnings(
    hazard(form,
           data = dd,
           dist = "multiphase",
           phases = ph2,
           theta = stage1$fit$theta,
           fit = TRUE,
           control = ctl2)
  )
}, envir = fit_env)
stage1 <- fit_env$stage1
stage2 <- fit_env$stage2

if (!is.null(old_seed)) .GlobalEnv$.Random.seed <- old_seed
```

Code

``` r
se_of <- function(f) {
  v  <- vcov(f)
  dg <- if (is.matrix(v)) diag(v) else rep(NA_real_, length(coef(f)))
  # A non-positive-definite Hessian can put NEGATIVE numbers on the diagonal.
  # sqrt() of one is NaN, which prints as a blank cell and reads as "not
  # applicable" rather than "this variance is impossible". Make it NA, and
  # count them.
  stats::setNames(sqrt(ifelse(is.finite(dg) & dg >= 0, dg, NA_real_)),
                  names(coef(f)))
}
free_of <- function(f) names(coef(f))[!as.logical(f$fit$fixed_mask)]

stages <- data.frame(
  stage       = c("1: shapes fixed at hz", "2: shapes freed from stage 1"),
  converged   = c(stage1$fit$converged, stage2$fit$converged),
  objective   = c(stage1$fit$objective, stage2$fit$objective),
  # CHARACTER, not numeric: rcond is often ~1e-6 here, and kable's `digits`
  # rounds a numeric column, so two different condition numbers both print as
  # "1e-06" and the comparison this table exists for silently disappears.
  rcond       = format(c(stage1$fit$rcond, stage2$fit$rcond),
                       digits = 3, scientific = TRUE),
  pd          = c(stage1$fit$pd, stage2$fit$pd),
  free_params = c(length(free_of(stage1)), length(free_of(stage2))),
  free_without_se = c(sum(is.na(se_of(stage1)[free_of(stage1)])),
                      sum(is.na(se_of(stage2)[free_of(stage2)])))
)
knitr::kable(stages, digits = 6)
# Named explicitly rather than left to stopifnot(), whose message is the failed
# expression. In a rendered report the reader is not looking at this source,
# and "isTRUE(stage1$fit$converged) is not TRUE" tells them nothing they can
# act on.
```

| stage | converged | objective | rcond | pd | free_params | free_without_se |
|:---|:---|---:|:---|:---|---:|---:|
| 1: shapes fixed at hz | TRUE | -1419.555 | 8.65e-08 | TRUE | 9 | 0 |
| 2: shapes freed from stage 1 | TRUE | -1408.075 | 6.77e-11 | TRUE | 13 | 0 |

Table 7: Convergence and fit of each stage

Code

``` r
failed <- stages$stage[!vapply(list(stage1, stage2),
                               function(f) isTRUE(f$fit$converged), logical(1))]
if (length(failed)) {
  stop("These stages did not converge: ", paste(failed, collapse = "; "),
       ". Every estimate below would be read off a fit that never settled. ",
       "Check the shape parameters inherited from the hz job, and whether the ",
       "covariate set is identifiable on this cohort.", call. = FALSE)
}

cov_names <- setdiff(names(coef(stage1)), SHAPE_PARAMS)
delta <- abs(coef(stage1)[cov_names] - coef(stage2)[cov_names])
knitr::kable(data.frame(
  objective_gain_from_freeing_shapes = stage2$fit$objective - stage1$fit$objective,
  max_abs_covariate_change           = max(delta),
  changed_by_more_than_0.01          = sum(delta > 0.01)
), digits = 6)
```

| objective_gain_from_freeing_shapes | max_abs_covariate_change | changed_by_more_than_0.01 |
|---:|---:|---:|
| 11.48023 | 0.139262 | 4 |

Table 8: Change in the covariate estimates when the shape parameters are
freed

**Read the two tables together before choosing which fit to report.**
Freeing the shapes can gain almost nothing in objective, move no
covariate materially, and still turn `pd` from `TRUE` to `FALSE` while
leaving shape parameters with no standard error — in which case the
shapes were already at their optimum and freeing them buys nothing and
costs the covariance.

Reporting stage 1 in that case is a **deliberate divergence** from the
SAS `%final`, which frees them. It is legitimate when the table above is
the evidence for it. If `free_without_se` is 0 for stage 2 and `pd` is
`TRUE`, prefer stage 2.

**Whichever you report, the render stops below if any of its free
parameters has no standard error**, and names the phase and covariates
involved. A fit without a variance matrix gives `hs` no limits to work
with.

Code

``` r
reported <- stage1   # Demo: stage2 if the table above favors it
```

Code

``` r
# A fit can degenerate -- a phase runs off, its log_mu heading for -850 -- and
# still report converged = TRUE. It then carries no variance matrix, vcov()
# returns a scalar NA, and the only sign is a TemporalHazard warning the fits
# above suppress. Saved anyway, hm.rds fails far from the cause: hs cannot put
# limits on a prediction from it. So stop here, naming what is involved.
#
# FIXED parameters carry an all-NA row in vcov() by design; only FREE ones are
# checked. A negative variance is as unusable as a missing one.
.v <- vcov(reported)
.free <- names(coef(reported))[!as.logical(reported$fit$fixed_mask)]
.var <- if (is.matrix(.v) && nrow(.v) == length(coef(reported))) {
  stats::setNames(diag(.v), names(coef(reported)))[.free]
} else {
  stats::setNames(rep(NA_real_, length(.free)), .free)
}
.no_se <- .free[!(is.finite(.var) & .var >= 0)]
if (length(.no_se)) {
  .phase <- sub("[.].*$", "", .no_se)
  stop(if (is.matrix(.v)) "The reported fit has no finite standard error for "
       else "The reported fit has no variance matrix, so no standard error for ",
       length(.no_se), " of its ", length(.free), " free parameters. By phase: ",
       paste0(unique(.phase), " (",
              vapply(split(sub("^[^.]*[.]", "", .no_se), factor(.phase, unique(.phase))),
                     paste, character(1), collapse = ", "), ")", collapse = "; "),
       ". Covariates among them: ",
       if (length(setdiff(.no_se, SHAPE_PARAMS))) paste(setdiff(.no_se, SHAPE_PARAMS), collapse = ", ") else "none",
       ". A phase whose log_mu has run off has left the model; check its estimate. Refit with fewer ",
       "candidate covariates in that phase, or with its shapes fixed.",
       call. = FALSE)
}
```

## Estimates

Code

``` r
cf <- coef(reported)
se <- se_of(reported)
cov_names <- setdiff(names(cf), SHAPE_PARAMS)

# The IQR of each covariate AS FITTED -- from dd, after conversion, so it is
# the spread of the numbers that actually entered the model rather than of the
# column as stored.
iqr_of <- function(v) {
  x <- dd[[sub("^[^.]*[.]", "", v)]]
  if (is.null(x) || !is.numeric(x)) return(NA_real_)
  unname(diff(stats::quantile(x, c(0.25, 0.75), na.rm = TRUE)))
}
iqr <- vapply(cov_names, iqr_of, numeric(1))

est <- data.frame(
  parameter = cov_names,
  estimate  = unname(cf[cov_names]),
  se        = unname(se[cov_names]),
  iqr       = unname(iqr),
  # NA, not 1, on a degenerate IQR: exp(0) is 1 and would read as "no effect"
  # rather than "this scaling does not apply here".
  hr_per_iqr = unname(ifelse(is.finite(iqr) & iqr > 0,
                             exp(cf[cov_names] * iqr), NA_real_)),
  row.names = NULL
)
knitr::kable(est[order(-abs(est$estimate)), ], digits = 6, row.names = FALSE)
```

| parameter      |  estimate |       se |   iqr | hr_per_iqr |
|:---------------|----------:|---------:|------:|-----------:|
| early.creat_pr |  0.951359 | 0.586419 |  0.45 |   1.534357 |
| early.hx_chf   |  0.825335 | 0.473925 |  1.00 |   2.282644 |
| late.hx_chf    |  0.704118 | 0.117110 |  1.00 |   2.022063 |
| late.hx_dm     |  0.464980 | 0.119363 |  0.00 |         NA |
| early.age      |  0.079479 | 0.019480 | 17.00 |   3.861847 |
| late.age       |  0.040587 | 0.004770 | 17.00 |   1.993687 |
| late.lvef      | -0.020351 | 0.005486 | 14.00 |   0.752074 |

Table 9: Covariate estimates with standard errors and hazard ratios per
interquartile range, largest first

## Selection

The covariates above were taken as given. The SAS job’s `%model` macro
derives them by forward selection, which is a long job and is run from a
companion script rather than inline.

⚠️ **`hzr_stepwise()`’s defaults are not SAS’s.** `slentry = 0.3` and
`slstay = 0.2` against a typical `sle = 0.1`, `sls = 0.07`. Accepting
the R defaults runs a **different screen** from the job being
reproduced, admits more variables, and does not error.

⚠️ **The default `criterion = "score"` has a known defect**
([temporal_hazard#130](https://github.com/ehrlinger/temporal_hazard/issues/130)):
it declines the strongest candidates, because the observed information
goes indefinite at `beta = 0`. Consider `"wald"`, and say which you
used.

Code

``` r
# unnumbered: each child chunk below carries its own label and caption
# the levels from YOUR .sas `selection` statement, and the path your
# companion runner writes to.
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
sel_rds   <- set_path("estimates", "hm-selection.rds")

if (!file.exists(sel_rds)) {
  not_run <- data.frame(
    selection = "not run",
    how       = paste("Run the companion selection script, which writes",
                      basename(sel_rds)),
    slentry   = SLENTRY,
    slstay    = SLSTAY,
    max_steps = MAX_STEPS
  )
  .child("tbl selection not run", "Forward selection has not been run", "knitr::kable(not_run)")
} else {
  .selection_read <- hvtiRtemplates:::.read_handoff(
    sel_rds, "selection", hvtiRutilities::study_config(start = .root), "the companion hm selection runner"
  )
  sel <- .selection_read$value
  .provenance_data <- c(.selection_read$lineage$data, .provenance_data)
  .provenance_artifacts <- c(.provenance_artifacts, .selection_read$lineage$artifacts,
                             list(.selection_read$record))
  summary_tbl <- data.frame(
    slentry        = sel$slentry,
    slstay         = sel$slstay,
    max_steps      = sel$max_steps,
    steps_taken    = nrow(sel$steps),
    stopped_on_cap = sel$hit_cap
  )
  keep <- intersect(c("step_num", "action", "variable", "phase",
                      "p_value", "logLik", "n_coef"), names(sel$steps))
  # Each table is its own child chunk: only the last expression of a block is
  # auto-printed, and a child chunk is how each table gets its own number.
  .path <- sel$steps[, keep]
  .child("tbl selection summary", "Forward selection, from the companion runner", "knitr::kable(summary_tbl)")
  .child("tbl selection path", "Selection path", "knitr::kable(.path, row.names = FALSE, digits = 6)")
}
```

Code

``` r
knitr::kable(not_run)
```

| selection | how | slentry | slstay | max_steps |
|:---|:---|---:|---:|---:|
| not run | Run the companion selection script, which writes hm-selection.rds | 0.1 | 0.07 | 50 |

Table 10: Forward selection has not been run

Code

``` r
# unnumbered: each child chunk below carries its own label and caption
# A forward selection cannot legitimately LOWER the log-likelihood: adding a
# term to a nested model can only improve the maximized likelihood. If it
# drops, the post-entry REFIT landed in a worse optimum than the model it
# started from -- which happens when collinear transformations of one variable
# enter in succession -- and every step after that is built on it.
#
# The screen reports p = 0.000 for those entries either way, so this is the
# only place a reader would find out.
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
if (file.exists(sel_rds)) {
  sel <- .selection_read$value
  # A screen that admitted nothing is a real outcome, not a broken run: it says
  # no candidate cleared the entry level. Report that and skip the check, since
  # which.max() on an empty vector is integer(0) and data.frame() then fails
  # with "arguments imply differing number of rows" -- an error about the
  # REPORT, in a job whose actual finding is that nothing entered.
  if (nrow(sel$steps) == 0L) {
    .mono <- data.frame(
      steps = 0L,
      note  = paste("No variable entered the model, so there is no path to",
                    "check. Monotonicity skipped.")
    )
    .child("tbl selection monotone", "Is the selection path monotone?", "knitr::kable(.mono)")
  } else if ("logLik" %in% names(sel$steps)) {
    dropped <- c(FALSE, diff(sel$steps$logLik) < -1e-6)
    mono <- data.frame(
      steps                 = nrow(sel$steps),
      steps_lowering_loglik = sum(dropped),
      best_loglik_at_step   = which.max(sel$steps$logLik),
      loglik_at_last_step   = sel$steps$logLik[nrow(sel$steps)],
      best_loglik           = max(sel$steps$logLik)
    )
    .child("tbl selection monotone", "Is the selection path monotone?", "knitr::kable(mono, digits = 3)")
    if (any(dropped)) {
      warning("The selection path lowers the log-likelihood at step(s) ",
              paste(which(dropped), collapse = ", "),
              ". Those entries left the model worse than before them; the ",
              "variable list is not a nested improvement and must not be read ",
              "as one.", call. = FALSE)
    }
  }
}
```

Code

``` r
# unnumbered: each child chunk below carries its own label and caption
# How much of the step budget went to a concept the model already had.
#
# The monotonicity check above catches the SYMPTOM of collinear forms entering
# in succession (a log-likelihood that drops). This reports the CAUSE, and it
# fires whether or not the likelihood misbehaved. A step budget is shared, so a
# slot spent on a second form of a concept already in the model is a slot no
# other variable could have -- and when the screen also stopped ON the cap, the
# two facts together say the model is budget-limited BY REDUNDANCY.
#
# Grouping is conservative by construction, so this is a FLOOR: a concept
# nobody listed is still counted as separate variables. It understates and
# never overstates.
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
if (file.exists(sel_rds)) {
  sel <- .selection_read$value
  al  <- if (is.null(sel$concept_aliases)) character(0) else sel$concept_aliases
  cr  <- selection_crowding(sel$selected, aliases = al)
  redundant <- if (nrow(cr)) sum(cr$n_forms) - nrow(cr) else 0L
  crowding <- data.frame(
    selected         = length(sel$selected),
    crowded_concepts = nrow(cr),
    redundant_slots  = redundant
  )
  .child("tbl selection crowding", "Concept crowding among the selected covariates", "knitr::kable(crowding)")
  if (nrow(cr)) {
    .child("tbl selection crowding forms", "Concepts that more than one selected covariate expresses",
           "knitr::kable(cr, row.names = FALSE)")
  }
}
```

## Calibration

The model’s coefficients say which factors matter. **They do not say
whether the model is right.** The SAS job answers that with `%deciles`:
group patients by predicted risk and compare observed against expected
within each group.

Code

``` r
# the horizon, in the time unit of TIME. SAS: %deciles(..., time=10).

dec <- hzr_deciles(reported, time = DECILE_TIME, groups = 10)

# print(), NOT knitr::kable(). The print method carries the OVERALL chi-square,
# its degrees of freedom and its p value -- the one number that answers "does
# this model calibrate" -- and kable() renders only the per-group data frame,
# dropping it silently.
print(dec)
```

    Decile-of-risk calibration (risk grouped at time = 10 )
    725 subjects, all included.
    10 groups, 406 observed events, 406 expected

     group  n events expected observed_rate expected_rate chi_sq p_value
         1 73     13     20.2         0.178         0.277 2.5700   0.109
         2 72     25     27.1         0.347         0.377 0.1690   0.681
         3 73     29     25.9         0.397         0.355 0.3760   0.540
         4 72     29     38.8         0.403         0.538 2.4600   0.117
         5 73     44     35.7         0.603         0.489 1.9200   0.166
         6 72     45     38.2         0.625         0.531 1.2000   0.274
         7 73     52     41.8         0.712         0.572 2.5100   0.113
         8 72     48     46.4         0.667         0.644 0.0575   0.810
         9 73     61     64.7         0.836         0.886 0.2100   0.647
        10 72     60     67.2         0.833         0.934 0.7790   0.378
     mean_survival mean_cumhaz
             0.834       0.277
             0.757       0.377
             0.694       0.355
             0.644       0.538
             0.592       0.489
             0.533       0.531
             0.473       0.572
             0.395       0.644
             0.292       0.886
             0.148       0.934

    Overall: chi-sq = 12.2 on 9 df, p = 0.2 

Table 11: Observed against expected events in ten groups of predicted
risk

A group where observed and expected diverge is a region of risk the
model gets wrong, and it is invisible in a coefficient table.

Code

``` r
# The table above, drawn: a point above the line is a group with more events
# than the model expects. Read the pattern, not one point: a run of points on
# one side at the high-risk end is a model that under-predicts the sickest
# patients, which the overall chi-square can pass.
.lim <- c(0, 1.05 * max(dec$events, dec$expected))
.fig <- ggplot2::ggplot(dec, ggplot2::aes(x = .data$expected, y = .data$events)) +
  ggplot2::geom_abline(slope = 1, intercept = 0, linetype = "dashed") +
  ggplot2::geom_point() +
  ggplot2::geom_text(ggplot2::aes(label = .data$group), nudge_x = 0.03 * .lim[[2]], hjust = 0) +
  ggplot2::coord_equal(xlim = .lim, ylim = .lim, clip = "off") +
  ggplot2::labs(x = "Expected events", y = "Observed events") +
  hvtiPlotR::theme_hv_manuscript(base_size = 12)
save_figure(.fig, "hm-calibration")
.fig
```

![](assets/c9b59a57c8cbc02169fa6ead6d383764.png)

Figure 1: Observed against expected events in each group of predicted
risk, numbered from the lowest risk. The dashed line is perfect
calibration.

Code

``` r
# The parametric fit against the actuarial estimate over the whole follow-up,
# rather than at one horizon. This is the nearest available equivalent to the
# SAS `%check` step, which refits with `maxsteps=0` to compute Q-statistics for
# factors the screen may have overlooked -- that statistic has no R equivalent
# yet, so this checks the FIT rather than the omitted variables. Stated, rather
# than presented as the same thing.
gof <- hzr_gof(reported)
knitr::kable(utils::tail(gof[, intersect(c("time", "km_surv", "par_surv",
                                           "cum_observed", "cum_expected",
                                           "residual"), names(gof))], 10),
             row.names = FALSE, digits = 5)
```

|   time | km_surv | par_surv | cum_observed | cum_expected | residual |
|-------:|--------:|---------:|-------------:|-------------:|---------:|
| 30.215 | 0.23065 |  0.18476 |          406 |     397.4673 | -8.53274 |
| 30.547 | 0.23065 |  0.18141 |          406 |     398.1596 | -7.84040 |
| 30.669 | 0.23065 |  0.18020 |          406 |     398.7052 | -7.29476 |
| 30.877 | 0.23065 |  0.17814 |          406 |     401.2335 | -4.76645 |
| 32.110 | 0.23065 |  0.16645 |          406 |     401.7599 | -4.24009 |
| 32.279 | 0.23065 |  0.16491 |          406 |     402.2373 | -3.76273 |
| 32.352 | 0.23065 |  0.16425 |          406 |     403.7163 | -2.28366 |
| 32.362 | 0.23065 |  0.16416 |          406 |     404.2042 | -1.79585 |
| 34.426 | 0.23065 |  0.14652 |          406 |     404.8970 | -1.10298 |
| 34.604 | 0.23065 |  0.14509 |          406 |     406.0000 | -0.00001 |

Table 12: Observed vs parametric, last ten event times

## Save

Code

``` r
# `hs` builds patient-level predictions from this model and `bh` bootstraps
# this screen, both by set.
hm_art <- list(reported = reported, stage1 = stage1, stage2 = stage2,
               covariates = COVARIATES, audit = audit, deciles = dec)
hm_art <- hvtiRtemplates:::.attach_handoff_lineage(
  hm_art,
  data = .provenance_data,
  artifacts = .provenance_artifacts,
  analysis = list(
    time = list(variable = TIME),
    event = list(variable = EVENT, event = 1L, censored = 0L)
  ),
  cohort = cc,
  # hz's record, which hs rebuilds its rows from.
  selection = .up$selection
)
saveRDS(hm_art, set_path("estimates", "hm.rds"))
```

## About this run

| Group | Item | Value |
|:---|:---|:---|
| Run | Started | 2026-10-29 10:31:44 EDT |
|  | Ended | 2026-10-29 10:31:50 EDT |
|  | Duration | 6 s |
|  | Status | final |
|  | Rendered by | gallery |
|  | Host | gallery |
| Job | File | hm.dead.hz.qmd |
|  | Template | hm |
|  | Subject | dead |
|  | Type | hz |
|  | hvtiRtemplates | 1.5.4 |
| Dataset `built` | Version file | built_20261029.parquet |
|  | Version date | 2026-10-29 |
|  | Source file | built.rds |
|  | Rows kept | 725 rows on 725 patients |
|  | WHERE | `!is.na(creat_pr)` |
|  | sha256 | b236a472f1f3 |
|  | Manifest | current |
| Upstream | Handoff | `dead-hz/hz.rds` (hazard-shape-model), rendered 2026-10-29 10:31:32 -0400, data built_20261029.parquet |
| Reproducibility | renv | not active |
|  | renv.lock sha256 | d09f96b6cd21 |
