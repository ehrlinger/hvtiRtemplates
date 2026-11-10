# Observed against model-expected events, and a band for the cohort-average curve. The design is
# dev/specs/2026-11-10-hs-oe-test-and-bands-design.md. Neither function takes a model: they take
# the numbers a model produced, so an hs job's hazard model and a vt job's forest can both call them.

# The one-sample log-rank test (Breslow 1975; Finkelstein, Muzikansky and Schoenfeld 2003).
# `event` is 0/1 per patient and `expected` each patient's expected cumulative hazard at their OWN
# follow-up, from the reference model. O is the events, E the sum of the cumulative hazards; the
# test is (O - E)^2 / E on one degree of freedom, and the interval for O/E is the exact Poisson
# interval on O divided by E. E is treated as fixed: the reference model's own uncertainty is not
# in the test (TemporalHazard#731 would let it be).
.one_sample_logrank <- function(event, expected, level = 0.95) {
  if (!is.numeric(level) || length(level) != 1L || is.na(level) || level <= 0 || level >= 1) {
    stop("The test's level must be one number between 0 and 1; got ", deparse(level), ".", call. = FALSE)
  }
  if (length(event) != length(expected)) {
    stop("`event` and `expected` must have one value per patient; got ", length(event), " and ",
         length(expected), ".", call. = FALSE)
  }
  if (anyNA(event) || !all(event %in% c(0, 1))) stop("`event` must be 0 or 1 for every patient.", call. = FALSE)
  # A cumulative hazard is finite and not negative. An NA here is a failed prediction, and summing
  # around it would understate E.
  if (!all(is.finite(expected)) || any(expected < 0)) {
    stop(sum(!is.finite(expected) | expected < 0), " expected cumulative hazard(s) are missing, ",
         "infinite or negative.", call. = FALSE)
  }
  o <- sum(event)
  e <- sum(expected)
  if (e <= 0) stop("The expected count is 0, so there is no ratio to test.", call. = FALSE)
  alpha <- 1 - level
  chisq <- (o - e)^2 / e
  data.frame(
    n = length(event), observed = o, expected = e, ratio = o / e,
    # qchisq(p, 0) is 0, so O = 0 gives a lower limit of 0, as the exact interval should.
    lower = stats::qchisq(alpha / 2, 2 * o) / 2 / e,
    upper = stats::qchisq(1 - alpha / 2, 2 * (o + 1)) / 2 / e,
    level = level, chisq = chisq, p = stats::pchisq(chisq, df = 1, lower.tail = FALSE)
  )
}

# The cohort-average survival curve and a band around it, chosen by name. `surv` is a patients x
# times matrix of predicted survival; `lower` and `upper`, the same shape, are the patients' limits
# at coverage `clevel`. Two bands, never confused with each other or with the confidence interval
# of the mean curve, which is a third quantity and is not available yet (TemporalHazard#731):
#   "limits_mean": the average of the patients' limits. Exact for the mean only if every patient's
#     error were perfectly correlated, so its width is an upper bound on the interval of the mean.
#   "spread": the 15th and 85th percentiles of the patients' predictions. It measures how patients
#     differ, does not narrow as the cohort grows, and is not a confidence interval of anything.
# Returns one row per time: the mean, the band's two edges, and the band's label as attribute "label".
.cohort_curve_band <- function(surv, lower = NULL, upper = NULL, band, clevel = NULL) {
  bands <- c("limits_mean", "spread")
  if (is.null(band) || length(band) != 1L || !band %in% bands) {
    stop("BAND must be one of ", paste0("\"", bands, "\"", collapse = ", "), ": the average of the patients' ",
         "limits, or the spread of their predictions. Say which in the text above.", call. = FALSE)
  }
  surv <- as.matrix(surv)
  if (!nrow(surv)) stop("There are no patients to average.", call. = FALSE)
  if (anyNA(surv)) stop("A predicted survival is missing; averaging around it would hide it.", call. = FALSE)
  mean_curve <- colMeans(surv)
  if (identical(band, "limits_mean")) {
    if (is.null(lower) || is.null(upper)) stop("BAND \"limits_mean\" needs the patients' limits.", call. = FALSE)
    lower <- as.matrix(lower)
    upper <- as.matrix(upper)
    if (!identical(dim(lower), dim(surv)) || !identical(dim(upper), dim(surv))) {
      stop("The limits must have one value per patient and time, as the predictions do.", call. = FALSE)
    }
    if (anyNA(lower) || anyNA(upper)) stop("A patient's limit is missing, so their average is not defined.", call. = FALSE)
    if (is.null(clevel)) stop("BAND \"limits_mean\" needs the limits' coverage, `clevel`.", call. = FALSE)
    pct <- signif(100 * clevel, 2)
    out <- data.frame(mean = mean_curve, lower = colMeans(lower), upper = colMeans(upper))
    label <- paste0("Average of the patients' ", pct, "% limits (an upper bound on the ", pct,
                    "% interval of the mean curve)")
  } else {
    q <- apply(surv, 2L, stats::quantile, probs = c(0.15, 0.85), names = FALSE, type = 7)
    out <- data.frame(mean = mean_curve, lower = q[1L, ], upper = q[2L, ])
    label <- "15th to 85th percentiles of the patients' predictions (their spread, not a confidence interval)"
  }
  attr(out, "label") <- label
  out
}
