# Multiphase parametric hazard fit

# Multiphase parametric hazard fit

Replaces `distributions/<job>.sas`: describe its `PROC HAZARD` call here
— the phase structure, what is estimated and what is held fixed.

An `hz` job produces a parametric fit and persists it. The life table it
is read against is an `ac` job, the figures over it are `hp`, and the
covariate model built on its shape parameters is `hm`; none of those
belong here. **Nor does SAS parity** — a parity job borrows the ordinal
of the job it checks and lives in `parity/`.

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
# file the unedited `theta0` is a vector of neutral 1s and the unedited `phases`
# are all-neutral shapes: that is a well-formed model, so it fits, converges,
# reports standard errors and saves an .rds for `hp` and `hm` to read. Nothing
# errors, and nothing in the output says the numbers describe no study.
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

# An `hz` job ALWAYS persists: `hp` plots what it writes and `hm` fixes its
# shape parameters at these converged values, both by set. The write itself is
# in the `save` chunk at the foot of this file, not here.
```

## Study choices

Edit these values for this study before rendering.

Code

``` r
# Demo: the registered dataset this job reads ("study" is the built dataset).
DATASET <- "study"

# Demo: an hvtiRdatabuild analysis set, or NULL to read the whole dataset.
ANALYSIS_SET <- NULL

# Demo: rows to keep, dplyr::filter() style, or NULL to keep every row:
#   WHERE <- quote(age >= 18)
#   WHERE <- rlang::exprs(age >= 18, hx_chf == 1)
WHERE <- quote(!is.na(creat_pr))

# Demo: the patient identifier. Without "ccfid" the job uses MRN, then eMRN;
# name another column, such as "randid", if the study uses one.
ID <- "patient_id"

# Demo: what makes a row unique; one row per patient unless repeated measures
# add their visit time or date, for example KEY <- c(ID, "iv_echo").
KEY <- ID

# Model phases and fixed parameters.
# Demo: phases and the fixed set on each.
phases <- list(
  early = hzr_phase("cdf", t_half = 0.04, nu = 1, m = 1),
  late  = hzr_phase("g3", tau = 1, gamma = 1, alpha = 1, eta = 1,
                    fixed = c("tau", "gamma", "alpha"))
)

# Starting values in the order returned by hzr_theta_names(phases).
# Demo: starting values from the SAS estimates.
theta0 <- c(log(0.05), log(0.04), 1, 1,
            log(0.035), log(1), 1, 1, 1)

# Demo: time, event, and counts from the SAS reference for the rows this job
# analyses. Leave these invalid defaults in place until the job is reconciled.
TIME   <- "iv_dead"

EVENT  <- "dead"

EXPECTED <- list(n = 725L, n_events = 402L, n_censored = 323L)
```

## Cohort

Code

``` r
# The checksum of every dataset in manifest.yaml is checked before anything is
# read, so a result can name the data that produced it. It stops on a mismatch.
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
| `!is.na(creat_pr)`  | removed 75                  |
| Rows kept           | 725 rows on 725 patients    |

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
cc <- cohort_counts(d, event = EVENT, time = TIME)
assert_cohort(d, expected = EXPECTED, event = EVENT, time = TIME)

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
decoration.

Code

``` r
# numDeriv is a Suggests of TemporalHazard, not a hard dependency. Without it,
# interval- or left-censored multiphase fits SILENTLY produce no standard
# errors: the fit succeeds, `converged` is TRUE, and vcov() is simply absent.
# A model reported without uncertainty is not a smaller result, it is a
# different one -- so this is a hard stop rather than a warning.
if (!requireNamespace("numDeriv", quietly = TRUE)) {
  stop("numDeriv is not installed. Interval-censored multiphase fits will ",
       "produce no standard errors, and will not tell you so. Install it ",
       "before reading anything below.", call. = FALSE)
}
```

## Model

Describe the phase structure here: how many phases, which of `THALF`,
`NU`, `M`, `MUE`, `TAU`, `GAMMA`, `ALPHA`, `ETA`, `MUL` are estimated,
and which are held.

⚠️ **A SAS hazard fit is always three-phase.** An absent phase sits in
the model at zero rather than being removed, so classify from the sums
table, never from the parameter block — a phase that contributed nothing
still prints nothing.

Code

``` r
# your phases, and the `fixed` set on each.

# The names, IN ORDER, that theta must supply. Read from the package rather
# than written as a literal: the count and the order are properties of the
# phase specification above, and a hand-written vector silently mis-assigns
# every value if the specification changes.
#
# hzr_theta_names() is exported from TemporalHazard 1.2.8 on. This job once
# reached the internal it replaced, which later changed shape and stopped every
# render here, so the floor is checked with a sentence a study author can act on.
if (utils::packageVersion("TemporalHazard") < "1.2.8") {
  stop("This job needs TemporalHazard 1.2.8 or later for hzr_theta_names(), ",
       "which states the order and count of `theta` below. Installed: ",
       utils::packageVersion("TemporalHazard"), ".", call. = FALSE)
}
theta_names <- hzr_theta_names(phases)
theta_table <- data.frame(
  position  = seq_along(theta_names),
  parameter = theta_names
)
knitr::kable(theta_table)
```

| position | parameter        |
|---------:|:-----------------|
|        1 | early.log_mu     |
|        2 | early.log_t_half |
|        3 | early.nu         |
|        4 | early.m          |
|        5 | late.log_mu      |
|        6 | late.log_tau     |
|        7 | late.gamma       |
|        8 | late.alpha       |
|        9 | late.eta         |

Table 3: Position and name of each parameter in theta

⚠️ **`theta` is positional, and the scales are not uniform.** For an
`early` + `late` pair the order is

    early.log_mu, early.log_t_half, early.nu, early.m,
    late.log_mu,  late.log_tau,     late.gamma, late.alpha, late.eta

Note the asymmetry: the late phase logs `mu` and `tau` but carries
`gamma`, `alpha` and `eta` on the natural scale. Wrapping the wrong
element in `log()` produces a fit, not an error.

## Starting values

Code

``` r
# unnumbered: ships no output; the table in the commented Shape B is a diagnostic only
# ---- Shape A: seed from the SAS job's converged estimates -------------------
# your SAS estimates, on their NATURAL scale, wrapped per `theta_names`
# above -- log() for the log-scale positions, bare for the rest.

# ---- Shape B: neutral shapes, data-derived time scale -----------------------
# Demo: delete Shape A above and uncomment this.
#
# ev_times <- sort(as.numeric(d[[TIME]][as.numeric(d[[EVENT]]) == 1]))
# t_half_0 <- as.numeric(stats::quantile(ev_times, 0.25))
# theta0   <- c(log(1), log(t_half_0), 1, 1,
#               log(1), log(1), 1, 1, 1)
# knitr::kable(data.frame(
#   n_events_used = length(ev_times), t_half_start = t_half_0,
#   note = "derived from the data; shapes start neutral at 1"))

if (length(theta0) != length(theta_names)) {
  stop("theta0 has ", length(theta0), " values but the phase specification ",
       "needs ", length(theta_names), ": ",
       paste(theta_names, collapse = ", "), call. = FALSE)
}
```

## Response

Code

``` r
# unnumbered: ships no output; the table in the commented Shape B is a diagnostic only
# ---- Shape A: no interval censoring -----------------------------------------
# SAS `time <t>; event <e>;` maps straight onto Surv(time, status). Nothing
# below needs the interval machinery and `objective = "sas"` does not apply.
# Demo: your time and status variables.
resp <- data.frame(time   = as.numeric(d[[TIME]]),
                   status = as.numeric(d[[EVENT]]))
stopifnot(all(resp$status %in% c(0, 1)), !anyNA(resp$time))

# ---- Shape B: interval-censored ---------------------------------------------
# Demo: delete Shape A above and uncomment this, from SAS's
#   time <upper>; icensor <flag>=<lower>;
# Expressed as Surv(type = "interval2"): an exact event is (t, t), a
# right-censored row is (t, NA), an interval-censored row is (lo, hi).
#
# ⚠️ Do NOT pass the bounds through time_lower/time_upper. time_lower is an
# ENTRY time for left truncation, not an interval bound, and using it that way
# fits a different model without complaining.
#
# status_sas <- ifelse(!is.na(d$<flag>) & d$<flag> == 1, 2,
#               ifelse(d$<event> == 1, 1, 0))
# lo   <- ifelse(status_sas == 2, d$<lower>, d$<upper>)
# hi   <- ifelse(status_sas == 0, NA,        d$<upper>)
# resp <- data.frame(lo = lo, hi = hi)
# knitr::kable(as.data.frame(table(`SAS status` = status_sas)))

# ONE source of truth for the response formula. Every hazard() call below uses
# it, so the Shape A / Shape B choice above is made once and only once. Three
# literal formulas would be three chances to edit two of them -- and while the
# mismatched call usually errors on a missing column, an author who edits all
# three INCONSISTENTLY gets no such warning.
surv_formula <- if (all(c("lo", "hi") %in% names(resp))) {
  Surv(lo, hi, type = "interval2") ~ 1
} else {
  Surv(time, status) ~ 1
}
```

Code

``` r
# The response build is the step that fails SILENTLY. Get it wrong -- mark an
# interval-censored death as right-censored at its upper bound, the opposite
# claim -- and the fit still converges, on a number that is simply wrong.
#
# So the two event counts are compared here rather than left for the reader to
# compare. A WARNING, not a stop: the cohort gate is defined on its own
# variables, and a study where those legitimately differ from the fitted pair
# should say so here rather than be blocked.
n_fitted <- if ("status" %in% names(resp)) {
  sum(resp$status == 1, na.rm = TRUE)
} else {
  sum(!is.na(resp$hi), na.rm = TRUE)
}
knitr::kable(data.frame(
  source = c("cohort gate", "response as built"),
  n_events = c(cc$n_events, n_fitted)
))
if (!identical(as.integer(n_fitted), as.integer(cc$n_events))) {
  warning("The response carries ", n_fitted, " events but the cohort gate ",
          "counted ", cc$n_events, ". Reconcile before reading the fit.",
          call. = FALSE)
}
```

| source            | n_events |
|:------------------|---------:|
| cohort gate       |      402 |
| response as built |      402 |

Table 4: Events in the cohort gate against events in the response as
built

Code

``` r
# The objective is a log-likelihood. A positive one is impossible: it signals a
# response that was mis-specified rather than a fit. Assert it, instead of
# reporting a plateau as a result.
check_fit <- function(f, label) {
  o <- f$fit$objective
  if (!is.finite(o) || o > 0) {
    stop(label, ": objective is ", o, ", which is not a log-likelihood.",
         call. = FALSE)
  }
  invisible(f)
}
```

## Fit

### Fit 1 — deterministic

The reported fit. One start, from `theta0`, so the result is
reproducible from the file alone.

Code

``` r
fit_det <- hazard(surv_formula, data = resp, dist = "multiphase",
                  phases = phases, theta = theta0, fit = TRUE,
                  control = list(conserve = TRUE, condition = 14,
                                 n_starts = 1, maxit = 2000))
```

    Warning: 'control' element(s) with no effect on this dist = "multiphase" fit,
    ignored: control$condition (SAS's CONDITION= has no equivalent: hazard() has no
    condition-number stop, and reports the Hessian's conditioning after the fit
    instead).

Code

``` r
check_fit(fit_det, "deterministic")
summary(fit_det)
```

    Multiphase hazard model (2 phases)
      observations: 725 
      predictors:   0 
      dist:         multiphase 
      phase 1:      early - cdf (early risk)
      phase 2:      late - g3 (late risk)
      engine:       native-r-m2 
      converged:    TRUE 
      gradient:     relative 3.93e-06 (SAS/C requires <= 6.06e-06; met)
      log-lik:      -1506.93 
      Not done in this run: none
      evaluations: fn=6, gr=1

    Coefficients (internal scale):

      Phase: early (cdf)
                   estimate std_error     z_stat      p_value
      log_mu     -3.8472243 0.6808191 -5.6508763 1.596320e-08
      log_t_half -6.3960721 2.0652308 -3.0970254 1.954732e-03
      nu          1.8499270 1.8044470  1.0252044 3.052668e-01
      m          -0.1095311 0.4366474 -0.2508457 8.019334e-01

      Phase: late (g3)
                estimate  std_error    z_stat      p_value
      log_mu  -2.4729679 0.17647206 -14.01337 1.291332e-44
      log_tau  0.0000000         NA        NA           NA
      gamma    1.0000000         NA        NA           NA
      alpha    1.0000000         NA        NA           NA
      eta      0.8280507 0.05854893  14.14288 2.066408e-45

Code

``` r
# There is no logLik() method for class "hazard": the log-likelihood is
# fit$fit$objective.
#
# rcond and pd are read OFF THE FIT rather than recomputed from vcov(): vcov()
# includes every FIXED parameter as an all-NA row and column, and rcond()
# cannot take an NA matrix. The fit's own values are computed on the free
# parameters, which is also what SAS's condition number refers to.
#
# A multiphase fit reports how many times the optimizer evaluated the function
# and its gradient, not an iteration count. Each value is read through .one(),
# so a field a fit does not carry shows as "not reported" rather than changing
# the number of rows and stopping the render.
.one <- function(x, ...) if (length(x) == 1L && !is.na(x)) format(x, ...) else "not reported"
knitr::kable(data.frame(
  quantity = c("log-likelihood", "converged", "function evaluations", "gradient evaluations", "rcond", "pd"),
  value    = c(.one(fit_det$fit$objective, digits = 10), .one(fit_det$fit$converged),
               .one(fit_det$fit$counts["function"]), .one(fit_det$fit$counts["gradient"]),
               .one(fit_det$fit$rcond, digits = 6), .one(fit_det$fit$pd))
))
```

| quantity             | value        |
|:---------------------|:-------------|
| log-likelihood       | -1506.931573 |
| converged            | TRUE         |
| function evaluations | 6            |
| gradient evaluations | 1            |
| rcond                | 2.30178e-05  |
| pd                   | TRUE         |

Table 5: Convergence quantities of the reported fit

### Fit 2 — did the starting point matter?

Code

``` r
# The probes run at n_starts = 1 ON PURPOSE. Multi-start is what makes the
# reported fit robust -- it perturbs around its start until it escapes small
# basins -- which is exactly what would HIDE a second basin from this check. A
# single start goes where its starting point leads, so it is the thing that
# actually finds another optimum if one is there.
#
# Demo: widen or add probes if your model has more phases or free parameters.
# Every row must differ from every other row: a duplicated start is a fit that
# costs time and tests nothing.
.free  <- !theta_names %in% c("late.log_tau", "late.gamma", "late.alpha")
probes <- rbind(theta0, theta0 + 0.5 * .free, theta0 - 0.5 * .free)
if (anyDuplicated(probes)) {
  stop("Two probe rows are identical: that fit costs time and tests nothing.",
       call. = FALSE)
}
```

Code

``` r
probe_ll <- vapply(seq_len(nrow(probes)), function(i) {
  f <- try(hazard(surv_formula, data = resp, dist = "multiphase",
                  phases = phases, theta = probes[i, ], fit = TRUE,
                  control = list(conserve = TRUE, condition = 14,
                                 n_starts = 1, maxit = 2000)), silent = TRUE)
  if (inherits(f, "try-error")) NA_real_ else f$fit$objective
}, numeric(1))
```

    Warning: 'control' element(s) with no effect on this dist = "multiphase" fit,
    ignored: control$condition (SAS's CONDITION= has no equivalent: hazard() has no
    condition-number stop, and reports the Hessian's conditioning after the fit
    instead).
    Warning: 'control' element(s) with no effect on this dist = "multiphase" fit,
    ignored: control$condition (SAS's CONDITION= has no equivalent: hazard() has no
    condition-number stop, and reports the Hessian's conditioning after the fit
    instead).

    Warning in .hzr_safe_solve(hess_result): Hessian is not positive-definite at
    the optimum; standard errors may be unreliable

    Warning in .hzr_safe_solve(hess_result): Non-positive variance estimates; the
    optimum may not be a proper maximum

    Warning: 'control' element(s) with no effect on this dist = "multiphase" fit,
    ignored: control$condition (SAS's CONDITION= has no equivalent: hazard() has no
    condition-number stop, and reports the Hessian's conditioning after the fit
    instead).

Code

``` r
probe_table <- data.frame(
  probe       = seq_len(nrow(probes)),
  logLik      = probe_ll,
  vs_reported = probe_ll - fit_det$fit$objective
)
knitr::kable(probe_table, digits = 6)
```

| probe |    logLik | vs_reported |
|------:|----------:|------------:|
|     1 | -1506.932 |           0 |
|     2 | -1506.932 |           0 |
|     3 | -1506.932 |           0 |

Table 6: Log-likelihood of each single-start probe fit against the
reported fit

A probe that beats the reported fit means the reported fit is in the
wrong basin, and the starting values need revisiting before anything
below is read.

### Fit 3 — `noconserve` sensitivity

⚠️ **This is a sensitivity, never a parity number.** A SAS `noconserve`
fit is only a conservation reference if it changes conservation *and
nothing else* — and in practice these fits often add a covariate at the
same time, which confounds the two changes.

Code

``` r
fit_nc <- hazard(surv_formula, data = resp, dist = "multiphase",
                 phases = phases, theta = theta0, fit = TRUE,
                 control = list(conserve = FALSE, condition = 14,
                                n_starts = 1, maxit = 2000))
```

    Warning: 'control' element(s) with no effect on this dist = "multiphase" fit,
    ignored: control$condition (SAS's CONDITION= has no equivalent: hazard() has no
    condition-number stop, and reports the Hessian's conditioning after the fit
    instead).

Code

``` r
check_fit(fit_nc, "noconserve")
```

Code

``` r
# Sum_i Lambda(t_i) is what `conserve` pins to the event count. Reporting it
# under BOTH settings is the only way a reader can tell "the control did
# nothing" from "the control had almost nothing to do" -- the two are identical
# in the likelihood column and mean opposite things.
sum_lambda <- c(
  sum(predict(fit_det, type = "cumulative_hazard")),
  sum(predict(fit_nc, type = "cumulative_hazard"))
)
conservation <- data.frame(
  conserve   = c(TRUE, FALSE),
  sum_lambda = sum_lambda,
  events     = cc$n_events
)
conservation$excess <- conservation$sum_lambda - conservation$events
knitr::kable(conservation, digits = 6)
```

| conserve | sum_lambda | events |  excess |
|:---------|-----------:|-------:|--------:|
| TRUE     |   402.0000 |    402 | 0.00000 |
| FALSE    |   402.0027 |    402 | 0.00275 |

Table 7: Sum of the cumulative hazard against the event count, with and
without conservation

## Estimates

Code

``` r
cf <- coef(fit_det)

# vcov() returns a scalar NA rather than a matrix when the Hessian could not be
# inverted, so diag() on it errors. That is a result ABOUT the fit, not a bug
# to route around: report it and carry on with what does not need curvature.
V <- vcov(fit_det)
se_available <- is.matrix(V) && nrow(V) == length(cf) && any(is.finite(diag(V)))

# NOTE the brace. At top level `if (a) x` <newline> `else y` is a PARSE ERROR:
# `else` must not start a line outside a block. knitr captures that error into
# the document and carries on, so the chunk "runs" and silently emits nothing.
se <- if (se_available) {
  setNames(sqrt(diag(V)), names(cf))
} else {
  setNames(rep(NA_real_, length(cf)), names(cf))
}

# Demo: map your coefficients to their natural scale, and to the SAS names a
# reader will be comparing against. exp() where R reports a log, identity where
# it already reports the natural value.
est <- data.frame(
  parameter     = c("MUE", "THALF", "NU", "M", "MUL", "ETA"),
  estimate      = c(exp(cf[["early.log_mu"]]), exp(cf[["early.log_t_half"]]),
                    cf[["early.nu"]], cf[["early.m"]],
                    exp(cf[["late.log_mu"]]), cf[["late.eta"]]),
  se_on_r_scale = c(se[["early.log_mu"]], se[["early.log_t_half"]],
                    se[["early.nu"]], se[["early.m"]],
                    se[["late.log_mu"]], se[["late.eta"]]),
  r_scale       = c("log", "log", "natural", "natural", "log", "natural"),
  row.names     = NULL
)
```

Code

``` r
knitr::kable(est, digits = 6)
```

| parameter |  estimate | se_on_r_scale | r_scale |
|:----------|----------:|--------------:|:--------|
| MUE       |  0.021339 |      0.680819 | log     |
| THALF     |  0.001668 |      2.065231 | log     |
| NU        |  1.849927 |      1.804447 | natural |
| M         | -0.109531 |      0.436647 | natural |
| MUL       |  0.084334 |      0.176472 | log     |
| ETA       |  0.828051 |      0.058549 | natural |

Table 8: Parameter estimates on the natural scale, with standard errors
on the fitting scale

Code

``` r
# unnumbered: its child chunk carries its own label and caption
if (!se_available) {
  no_se <- data.frame(
    warning = "The Hessian could not be inverted: NO standard errors are available."
  )
  .fence <- strrep("`", 3)
  cat(knitr::knit_child(text = c(
    paste0(.fence, "{r}"), "#| label: tbl-estimates-no-se",
    "#| tbl-cap: \"Standard errors could not be computed\"", "knitr::kable(no_se)", .fence
  ), envir = environment(), quiet = TRUE), sep = "\n")
}
```

**A caveat that must travel with these standard errors.** Under a
near-singular Hessian — check `rcond` above — the marginal standard
errors on weakly identified shape parameters are unstable while the
fitted curve is not. The data can pin the survival function tightly and
still leave individual shape parameters loose, because
`se(S(t))² = gᵀVg` can be well determined when the diagonal of `V` is
not.

So report per-parameter standard errors with that caveat attached, and
treat the survival curve and its band — computed in the companion `hp`
job — as the quantity that actually reaches a clinician.

## Save

Code

``` r
# `hp` plots what this writes and `hm` fixes its shape parameters at these
# values, both by set. A job that persists nothing cannot be chained from.
hz_art <- list(deterministic = fit_det, noconserve = fit_nc,
               phases = phases, theta0 = theta0)
hz_art <- hvtiRtemplates:::.attach_handoff_lineage(
  hz_art,
  data = .provenance_data,
  analysis = list(
    time = list(variable = TIME),
    event = list(variable = EVENT, event = 1L, censored = 0L)
  ),
  cohort = cc,
  # hm, hp and hs rebuild exactly these rows from this record, and take TIME
  # and EVENT from it, so the chain cannot drift from the fit it builds on.
  selection = c(attr(job_data$record, "selection"), list(time = TIME, event = EVENT))
)
saveRDS(hz_art, set_path("estimates", "hz.rds"))
```
