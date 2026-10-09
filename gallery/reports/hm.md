# Multivariable hazard model

# Multivariable hazard model

Replaces `analyses/<job>.sas`: describe its `PROC HAZARD … selection`
call here — which covariates were offered to which phase, and at what
entry and stay levels.

An `hm` job builds the risk-factor model **on top of** the shape
parameters the `hz` job fitted. The shapes are not re-derived here; they
are read. Patient-level predictions from this model are an `hs` job and
the bootstrap of this screen is `bh`; neither belongs here, and **nor
does SAS parity** — a parity job borrows the ordinal of the job it
checks and lives in `parity/`.

Code

``` r
# The study root is the nearest directory above this file holding _study.yml,
# so the job renders the same from the Render button, quarto render, or
# render_job(), at any depth, with no path in this document to edit.
.in <- knitr::current_input(dir = TRUE)
.root <- hvtiRtemplates:::.find_study_root(if (is.null(.in)) getwd() else dirname(.in))
.provenance_data <- list()
.provenance_artifacts <- list()
for (f in list.files(file.path(.root, "R"), pattern = "[.]R$", full.names = TRUE)) source(f)
suppressPackageStartupMessages({
  library(TemporalHazard)
  library(hvtiRutilities)
})
```

Code

``` r
# The markers in this file name work a study author still has to do, and
# README.md says a job that still contains one has not been finished. This
# chunk is what makes that TRUE rather than merely stated.
#
# Without it an unedited job renders green over a meaningless analysis. In THIS
# file the danger is sharper than a wrong number: the unedited entry and stay
# levels are `hzr_stepwise()`'s defaults, which are LOOSER than the SAS job's,
# so an unedited screen admits variables the job being reproduced rejected --
# and reports them as risk factors, in a table that looks exactly like a
# result.
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
SUBJECT <- "dead"
TYPE    <- "hz"

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
  # The name is template first, <prefix>[.<qualifier>].<subject>.<type>, or
  # <subject>-<type>-<prefix>[-<qualifier>] for a job scaffolded before
  # 2026-10. .job_name_fields() reads subject and type from either, whatever
  # the extension: Quarto knits through an intermediate, so
  # `knitr::current_input()` names the `.rmarkdown` file here, not the `.qmd`.
  .fields <- hvtiRtemplates:::.job_name_fields(.current)
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

# `hm` reads the `hz` fit through this and writes its own model back, both by
# set, so a model can never be filed against a different set than the shapes it
# was built on. The write is in the `save` chunk at the foot of this file.
```

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

# Demo: SAS job and macro holding covariate blocks.
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
.provenance_data <- c(if (exists(".provenance_data")) .provenance_data else list(), list(job_data$provenance),
                      if (!is.null(job_data$provenance_join)) list(job_data$provenance_join))
knitr::kable(job_data$record, col.names = c("Data", ""))
```

| Data                |                                          |
|:--------------------|:-----------------------------------------|
| Source              | dataset `study` (built_20261009.parquet) |
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
| n_events     | 402 |
| n_censored   | 323 |

Table 2: Analysable patients, events and censored patients

A rendered report is itself evidence the gate passed. Report the counts
anyway — a gate that passes silently tells the reader nothing about what
it passed on.

**An event flag that is 0/1 in SAS may arrive as `logical`**, because
`read_clinical_data()` infers binary columns as logical while `Surv()`
requires a numeric status. The `as.numeric()` coercions below are not
decoration — and see the covariate audit above for the same problem on
the covariate side, where it changes the model rather than erroring.

Code

``` r
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
```

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
sas_lines <- readLines(do.call(sas_path, as.list(SAS_JOB)), warn = FALSE)

# Demo: your phase-block markers. A SAS hazard model offers candidates per
# phase, and the blocks need not be identical.
COVARIATES <- list(
  early = sas_variable_block(sas_lines, "^\\s*early\\s*$", after = SAS_MACRO,
                             what = "early covariate block"),
  late  = sas_variable_block(sas_lines, "^\\s*late\\s*$",  after = SAS_MACRO,
                             what = "late covariate block")
)
```

Code

``` r
knitr::kable(data.frame(
  phase     = names(COVARIATES),
  n         = vapply(COVARIATES, length, integer(1)),
  variables = vapply(COVARIATES, paste, character(1), collapse = ", "),
  row.names = NULL
))
```

| phase |   n | variables                |
|:------|----:|:-------------------------|
| early |   3 | age, creat_pr, hx_chf    |
| late  |   4 | age, hx_chf, lvef, hx_dm |

Table 3: Number and names of the covariates in each phase

### What these columns are, before they become covariates

`vars.sas` is commonly called with `%vars(missing=1, impute=1)`: it
**mean-imputes** missing values and adds a paired `ms_*` indicator,
which is why `ms_*` variables are themselves covariates in these models.
So a 0/1 clinical variable arrives carrying three distinct values — 0,
1, and the cohort mean. One real column’s third value is `0.714`, the
prevalence of hypertension, not any patient’s status.

In SAS these are numeric and enter **linearly**. Read into R they arrive
as **factors**, and a factor in a model formula is dummy-coded — which
makes “this value was imputed” its own category with its own
coefficient. **That is a different model, with a different parameter
count, and nothing in the output would say so.**

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

# Only the columns the model uses. A hazard() fit keeps a copy of its data,
# which is saved in hm.rds, and `d` also holds the patient identifier.
dd <- covariates_to_numeric(d[unique(c(TIME, EVENT, unlist(COVARIATES)))], unlist(COVARIATES))
```

| variable | storage | n_levels | noninteger_levels | action          |
|:---------|:--------|---------:|:------------------|:----------------|
| age      | numeric |       63 | NA                | left as numeric |
| creat_pr | numeric |      147 | NA                | left as numeric |
| hx_chf   | integer |        2 |                   | left as numeric |
| lvef     | numeric |       53 | NA                | left as numeric |
| hx_dm    | integer |        2 |                   | left as numeric |

Table 4: Covariate storage and the conversion applied

**A factor left as a factor is dummy-coded on purpose** — the right
outcome for a genuinely categorical variable and the wrong one for a
mean-imputed binary. The `action` column is where that decision is
visible; check it before reading any coefficient.

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
| early.log_mu     | -3.847224 |
| early.log_t_half | -6.396072 |
| early.nu         |  1.849927 |
| early.m          | -0.109531 |
| late.log_mu      | -2.472968 |
| late.log_tau     |  0.000000 |
| late.gamma       |  1.000000 |
| late.alpha       |  1.000000 |
| late.eta         |  0.828051 |

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

# Demo: your covariate formula, and conserve = FALSE if the SAS final model
# carries `noconserve`.
rhs <- paste(unique(unlist(COVARIATES)), collapse = " + ")
form <- stats::as.formula(paste0("Surv(", TIME, ", ", EVENT, ") ~ ", rhs))

ctl1 <- list(n_starts = 5, maxit = 2000, conserve = FALSE)
ctl2 <- list(n_starts = 1, maxit = 5000, conserve = FALSE)
ph1 <- make_phases(TRUE)
ph2 <- make_phases(FALSE)

# The fits run in an environment holding only what they use. A saved fit keeps
# the environment of its formula and of its call, and hm.rds would then carry
# every object there, `d` and its patient IDs included, whenever these chunks
# run anywhere but the global environment.
fit_env <- list2env(list(dd = dd, form = form, ph1 = ph1, ph2 = ph2, ctl1 = ctl1, ctl2 = ctl2),
                    parent = globalenv())
environment(fit_env$form) <- fit_env
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
| 1: shapes fixed at hz | TRUE | -1420.774 | 5.37e-08 | TRUE | 12 | 0 |
| 2: shapes freed from stage 1 | TRUE | -1409.877 | 6.31e-09 | TRUE | 16 | 0 |

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
| 10.89681 | 0.244146 | 5 |

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
| early.creat_pr |  0.961085 | 0.586133 |  0.45 |   1.541087 |
| late.hx_chf    |  0.747069 | 0.118993 |  1.00 |   2.110805 |
| early.hx_chf   |  0.683661 | 0.541436 |  1.00 |   1.981118 |
| early.hx_dm    | -0.465688 | 0.687614 |  0.00 |         NA |
| late.hx_dm     |  0.453113 | 0.122488 |  0.00 |         NA |
| late.creat_pr  |  0.091371 | 0.145576 |  0.45 |   1.041974 |
| early.age      |  0.076389 | 0.019254 | 17.00 |   3.664187 |
| late.age       |  0.043786 | 0.004828 | 17.00 |   2.105112 |
| late.lvef      | -0.018780 | 0.005528 | 14.00 |   0.768804 |
| early.lvef     | -0.012608 | 0.025462 | 14.00 |   0.838188 |

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
    10 groups, 402 observed events, 402 expected

     group  n events expected observed_rate expected_rate chi_sq p_value
         1 73     12     20.7         0.164         0.283 3.6200  0.0569
         2 72     22     24.4         0.306         0.339 0.2340  0.6280
         3 73     30     28.4         0.411         0.388 0.0957  0.7570
         4 72     33     36.9         0.458         0.513 0.4190  0.5170
         5 73     45     36.0         0.616         0.493 2.2500  0.1330
         6 72     47     38.5         0.653         0.535 1.8700  0.1720
         7 73     46     41.7         0.630         0.572 0.4330  0.5100
         8 72     50     47.9         0.694         0.666 0.0896  0.7650
         9 73     59     61.1         0.808         0.837 0.0720  0.7880
        10 72     58     66.4         0.806         0.922 1.0600  0.3030
     mean_survival mean_cumhaz
             0.848       0.283
             0.773       0.339
             0.709       0.388
             0.657       0.513
             0.606       0.493
             0.546       0.535
             0.485       0.572
             0.402       0.666
             0.295       0.837
             0.150       0.922

    Overall: chi-sq = 10.2 on 9 df, p = 0.338 

Table 11: Observed against expected events in ten groups of predicted
risk

A group where observed and expected diverge is a region of risk the
model gets wrong, and it is invisible in a coefficient table.

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
| 32.742 | 0.25766 |  0.17410 |          402 |     392.8100 | -9.19000 |
| 32.909 | 0.25766 |  0.17257 |          402 |     393.2364 | -8.76363 |
| 33.117 | 0.25766 |  0.17069 |          402 |     393.8451 | -8.15488 |
| 33.328 | 0.25766 |  0.16881 |          402 |     395.1374 | -6.86257 |
| 33.344 | 0.25766 |  0.16867 |          402 |     396.6103 | -5.38967 |
| 33.383 | 0.25766 |  0.16832 |          402 |     399.3362 | -2.66377 |
| 34.784 | 0.25766 |  0.15636 |          402 |     399.7868 | -2.21317 |
| 35.567 | 0.25766 |  0.15005 |          402 |     400.3300 | -1.66996 |
| 35.611 | 0.25766 |  0.14970 |          402 |     400.9915 | -1.00853 |
| 35.696 | 0.25766 |  0.14903 |          402 |     401.9979 | -0.00215 |

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
