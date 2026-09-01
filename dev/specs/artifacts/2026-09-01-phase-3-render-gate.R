# Produce a bootstrap screen that 04.02-bl, 04.03-br and 04.04-bc can be
# rendered against, before any study has run one.
#
# No R job found on the share calls boot_select(), so there is no bl, br or bc
# bag to read. This runs a screen instead. Given a staged study project it
# screens that study's real built dataset -- real names, real correlations,
# real row count -- which is what makes read_built() and pool_collinear_pairs()
# render rather than error. Given no project it falls back to simulated
# columns, so the gate still runs when the share is not mounted.
#
# What neither mode covers is a candidate pool and a dropped set a study author
# chose. The design says so in section 8; do not let this script's success read
# as more than it is.
#
# NO STUDY PATH, STUDY NAME OR VARIABLE NAME IS RECORDED HERE. The project root
# arrives as an argument and the pool is derived from the data.
#
# Usage:
#   Rscript 2026-09-01-phase-3-render-gate.R <project-dir> <model> [<prefix>]
#     <model> is linear, logistic or cox
#     <prefix> defaults to "bagging"
# Writes <project-dir>/estimates/<prefix>.rds.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2L) {
  stop("Usage: <project-dir> <model:linear|logistic|cox> [<prefix>]",
       call. = FALSE)
}
proj   <- args[[1L]]
model  <- match.arg(args[[2L]], c("linear", "logistic", "cox"))
prefix <- if (length(args) >= 3L) args[[3L]] else "bagging"

suppressPackageStartupMessages({
  library(hvtiRbootstrap)
  library(hvtiRutilities)
})
if (utils::packageVersion("hvtiRbootstrap") < "0.9.2") {
  stop("boot_bag() lands in 0.9.2; ", utils::packageVersion("hvtiRbootstrap"),
       " is installed.", call. = FALSE)
}
dir.create(file.path(proj, "estimates"), recursive = TRUE,
           showWarnings = FALSE)

# Real data when the project carries a study manifest, simulated otherwise.
# Announced either way: a gate that silently degraded to simulation would
# report the weaker run as though it were the stronger one.
have_study <- file.exists(file.path(proj, "_study.yml"))
if (have_study) {
  cfg <- study_config(proj)
  d   <- read_built(cfg)
  cat("mode        : real built dataset\n")
} else {
  set.seed(20260901)
  n   <- 400
  age <- stats::rnorm(n, 60, 10)
  bmi <- stats::rnorm(n, 27, 4)
  d <- data.frame(age = age, ln_age = log(age), age2 = age^2,
                  bmi = bmi, ln_bmi = log(bmi),
                  noise1 = stats::rnorm(n), noise2 = stats::rnorm(n))
  lp <- 0.05 * (d$age - 60) + 0.12 * (d$bmi - 27)
  d$.y_bin <- stats::rbinom(n, 1, stats::plogis(lp))
  d$.t     <- stats::rexp(n, rate = exp(lp) / 50)
  d$.e     <- stats::rbinom(n, 1, 0.7)
  cfg <- list(cohort = list(event = ".e", time = ".t"))
  cat("mode        : simulated, no study project at ", proj, "\n", sep = "")
}

# The pool is DERIVED, never named: numeric, non-constant, not an outcome.
# Naming columns here would put a study's variable names in a public repo, and
# deriving them also means the pool is whatever the data actually offers.
outcomes <- unlist(cfg$cohort[c("event", "time")], use.names = FALSE)
num <- vapply(d, is.numeric, logical(1))
ok  <- vapply(d, function(x) length(unique(x[!is.na(x)])) > 2L, logical(1))
cand <- setdiff(names(d)[num & ok], outcomes)

# Drop the mostly-missing columns, then restrict to complete cases.
#
# NOT optional, and not tidiness. A real built dataset carries columns that are
# 60% NA, and glm() drops those rows per replicate: with twelve such candidates
# almost every resample loses its fit, boot_select() exhausts max_attempts and
# stops with "gave up after 600 attempts with 2 valid models of 60". Measured
# on a real study, which is how this line came to exist -- the first version of
# this script had no filtering and could not complete a single gate run.
cand <- cand[vapply(d[cand], function(x) mean(is.na(x)) < 0.05, logical(1))]
cand <- cand[seq_len(min(12L, length(cand)))]   # 12 keeps the gate to minutes
if (length(cand) < 3L) {
  stop("Only ", length(cand), " usable candidate columns; the concept and ",
       "cluster tables need more than that to show anything.", call. = FALSE)
}
keep <- stats::complete.cases(d[, c(cand, outcomes), drop = FALSE])
d <- d[keep, , drop = FALSE]
cat("pool        : ", length(cand), " candidates, ", nrow(d), " rows\n",
    sep = "")

# The outcome each fitter needs, taken from the manifest rather than guessed.
#
# The linear branch screens the first candidate against the rest. That is
# arbitrary and it is meant to be: a study manifest declares an event and a
# time, not a continuous outcome, and this gate needs a continuous response
# only to exercise fit_linear()'s code path. A real br screen names the outcome
# its own analysis is about.
rhs <- paste(cand[-1L], collapse = " + ")
spec <- switch(
  model,
  linear   = list(f = stats::as.formula(paste(cand[[1L]], "~", rhs)),
                  fitter = fit_linear),
  logistic = list(f = stats::as.formula(paste(outcomes[[1L]], "~",
                                              paste(cand, collapse = " + "))),
                  fitter = fit_logistic),
  cox      = list(f = stats::as.formula(
                    paste0("survival::Surv(", outcomes[[2L]], ", ",
                           outcomes[[1L]], ") ~ ",
                           paste(cand, collapse = " + "))),
                  fitter = fit_cox)
)

# n_rep is small on purpose. This proves the templates render; it does not
# claim any frequency is stable. A study's own run is where n_rep matters.
fit <- boot_select(d, spec$f, spec$fitter, n_rep = 60, sle = 0.10,
                   sls = 0.05, seed = 4242)

# A Cox model has no intercept, so base_params cannot be "(Intercept)" there.
# Taken from the screen's own terms rather than written in.
base <- if (model == "cox") colnames(fit$coefficients)[[1L]] else "(Intercept)"

bag <- boot_bag(
  fit,
  base_params = base,
  requested   = length(cand),
  manifest    = list(sha256 = "render-gate, screen run by the gate")
)

out <- file.path(proj, "estimates", paste0(prefix, ".rds"))
saveRDS(bag, out)

freq <- boot_frequencies(bag, threshold = 50)
cat("wrote       : ", out, "\n", sep = "")
cat("model       : ", model, "\n", sep = "")
cat("n_boot      : ", bag$n_boot, "\n", sep = "")
cat("n_rows      : ", bag$n_rows, "\n", sep = "")
cat("candidates  : ", nrow(freq), "\n", sep = "")
cat("base param  : ", base, "\n", sep = "")
cat("phase column: ", "phase" %in% names(freq), "  (must be FALSE)\n", sep = "")
