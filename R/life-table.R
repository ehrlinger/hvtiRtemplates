#' Kaplan-Meier life tables, as the ac job reports them
#'
#' @description
#' The R counterpart of the SAS \code{\%KAPLAN} macro, as the \code{ac} job calls
#' it. \code{life_table()} returns the product-limit life table, overall or one
#' per stratum. \code{life_table_at()} reads survival and the number at risk at
#' reporting horizons, \code{life_table_tests()} compares strata, and
#' \code{life_table_keep()} names the rows all three analyze, so a figure can be
#' drawn over exactly the same patients.
#'
#' @details
#' \strong{Rows analyzed.} A row is analyzed when its time and event are both
#' recorded. With \code{strata}, a row whose stratum value is missing, or is a
#' mean-imputed level (\code{hvtiRutilities::imputed_levels()}), is dropped too,
#' as \code{\%KAPLAN} drops "invalid strata values". The dropped rows are not
#' silent: the result carries them in its \code{"dropped"} attribute, one row
#' per reason, and the \code{ac} job prints that table.
#'
#' \strong{Confidence level.} The default \code{conf_level} is
#' \code{\%KAPLAN}'s \code{CLEVEL} default, \code{0.68268948}: one standard
#' error, not 95\%.
#'
#' \strong{Reporting horizons.} Survival at a horizon is the last estimate at or
#' before it, and 1 before the first event. Beyond the last observation the
#' estimate is not defined and is \code{NA}, unless survival has already reached
#' zero. The number at risk is the number of patients whose time is greater than
#' the horizon: the at-risk count on the first life-table row AFTER the horizon,
#' when every censored time has a row (\code{PEVENT=0}). The estimate comes from
#' the row before, the count from the row after.
#'
#' \strong{Tests.} \code{life_table_tests()} reports the three tests SAS
#' \code{PROC LIFETEST} prints for strata: the log-rank, the Wilcoxon (Gehan's
#' weights, the number at risk) and \code{-2Log(LR)}, the likelihood ratio test
#' of an exponential model. All three use every analyzed row to the end of
#' follow-up. To compare curves only up to a horizon, censor the data there
#' first, in the job.
#'
#' @param data A data frame, one row per patient.
#' @param time Name of the follow-up time column.
#' @param event Name of the event column, 0/1 or logical.
#' @param strata Name of one stratification column, or \code{NULL} for the
#'   whole cohort.
#' @param conf_level Confidence level of the limits. Default \code{0.68268948}.
#' @param event_only \code{TRUE} returns a row per event time only (SAS
#'   \code{PEVENT=1}); \code{FALSE} adds a row per censoring time
#'   (\code{PEVENT=0}).
#' @param times Reporting horizons, in the unit of \code{time}.
#' @param labels Labels for \code{times}. \code{NULL} labels each horizon with
#'   its value.
#'
#' @return
#' \code{life_table()}: a data frame with the columns of
#' \code{TemporalHazard::hzr_kaplan()} (\code{time}, \code{n_risk},
#' \code{n_event}, \code{n_censor}, \code{survival}, \code{std_err},
#' \code{cl_lower}, \code{cl_upper}, \code{cumhaz}, \code{hazard},
#' \code{density}, \code{life}), led by \code{stratum} when \code{strata} is
#' given. Its attribute \code{"counts"} has a row per stratum with \code{n},
#' \code{n_events}, \code{n_censored} and \code{max_fup}, the last observed
#' time; \code{"dropped"} is described under Details, or \code{NULL}.
#'
#' \code{life_table_at()}: a data frame with a row per stratum and horizon:
#' \code{stratum} when \code{strata} is given, then \code{horizon},
#' \code{time}, \code{survival}, \code{cl_lower}, \code{cl_upper} and
#' \code{n_risk}, with the \code{"dropped"} attribute.
#'
#' \code{life_table_tests()}: a data frame with a row per test: \code{test},
#' \code{chisq}, \code{df} and \code{p_value}, with the \code{"dropped"}
#' attribute. A stratum with nobody at risk at any event time adds nothing to
#' the log-rank or Wilcoxon test and is left out of its degrees of freedom.
#'
#' \code{life_table_keep()}: a logical vector, \code{TRUE} for each analyzed
#' row of \code{data}.
#'
#' @examples
#' if (requireNamespace("TemporalHazard", quietly = TRUE)) {
#'   d <- data.frame(
#'     years = c(0.2, 0.5, 0.9, 1.3, 2.0, 2.4, 3.1, 4.0, 5.5, 6.0),
#'     dead  = c(1, 0, 1, 1, 0, 1, 0, 1, 0, 0),
#'     group = c("a", "b", "a", "b", "a", "b", "a", "b", "a", NA)
#'   )
#'   life_table(d, "years", "dead")
#'   life_table_at(d, "years", "dead", times = c(1, 2, 5), strata = "group")
#'   life_table_tests(d, "years", "dead", "group")
#' }
#' @name life_table
NULL

#' @rdname life_table
#' @export
life_table <- function(data, time, event, strata = NULL, conf_level = 0.68268948, event_only = TRUE) {
  .lt_need_kaplan()
  parts <- .lt_parts(data, time, event, strata)
  fits <- lapply(names(parts$rows), function(s) {
    p <- parts$rows[[s]]
    fit <- as.data.frame(TemporalHazard::hzr_kaplan(time = p$time, status = p$status, conf_level = conf_level,
                                                    event_only = event_only))
    if (is.null(strata)) fit else cbind(stratum = s, fit)
  })
  out <- do.call(rbind, fits)
  rownames(out) <- NULL
  attr(out, "counts") <- parts$counts
  attr(out, "dropped") <- parts$dropped
  out
}

#' @rdname life_table
#' @export
life_table_at <- function(data, time, event, times, labels = NULL, strata = NULL, conf_level = 0.68268948) {
  .lt_need_kaplan()
  if (!is.numeric(times) || !length(times) || anyNA(times) || any(times < 0)) {
    stop("life_table_at(): `times` must be nonnegative numbers.", call. = FALSE)
  }
  if (is.null(labels)) labels <- format(signif(times, 4), trim = TRUE, drop0trailing = TRUE)
  if (length(labels) != length(times)) {
    stop("life_table_at(): `labels` has ", length(labels), " entries for ", length(times), " horizons.", call. = FALSE)
  }
  parts <- .lt_parts(data, time, event, strata)
  out <- do.call(rbind, lapply(names(parts$rows), function(s) {
    p <- parts$rows[[s]]
    fit <- TemporalHazard::hzr_kaplan(time = p$time, status = p$status, conf_level = conf_level, event_only = TRUE)
    max_fup <- max(p$time)
    rows <- do.call(rbind, lapply(times, function(g) {
      i <- which(fit$time <= g)
      beyond <- g > max_fup
      if (!length(i)) {
        est <- if (beyond) c(NA_real_, NA_real_, NA_real_) else c(1, NA_real_, NA_real_)
      } else {
        j <- max(i)
        est <- c(fit$survival[j], fit$cl_lower[j], fit$cl_upper[j])
        # Survival of zero is absorbing, so it stays known past the last observation.
        if (beyond && est[1] > 0) est <- c(NA_real_, NA_real_, NA_real_)
      }
      data.frame(time = g, survival = est[1], cl_lower = est[2], cl_upper = est[3], n_risk = sum(p$time > g))
    }))
    rows <- cbind(horizon = labels, rows)
    if (is.null(strata)) rows else cbind(stratum = s, rows)
  }))
  rownames(out) <- NULL
  attr(out, "dropped") <- parts$dropped
  out
}

#' @rdname life_table
#' @export
life_table_tests <- function(data, time, event, strata) {
  if (!is.character(strata) || length(strata) != 1L) {
    stop("life_table_tests(): `strata` must name one column.", call. = FALSE)
  }
  parts <- .lt_parts(data, time, event, strata)
  df <- length(parts$rows) - 1L
  if (df < 1L) {
    stop("life_table_tests(): ", strata, " has fewer than two analysable strata.", call. = FALSE)
  }
  tm <- unlist(lapply(parts$rows, `[[`, "time"), use.names = FALSE)
  st <- unlist(lapply(parts$rows, `[[`, "status"), use.names = FALSE)
  gr <- rep(seq_along(parts$rows), vapply(parts$rows, nrow, integer(1)))

  logrank <- .lt_weighted_test(tm, st, gr, function(n) 1)
  wilcoxon <- .lt_weighted_test(tm, st, gr, function(n) n)
  chisq <- c(logrank$chisq, wilcoxon$chisq, .lt_exponential_lr(tm, st, gr))
  dfs <- c(logrank$df, wilcoxon$df, df)
  out <- data.frame(test = c("Log-rank", "Wilcoxon", "-2Log(LR)"), chisq = chisq, df = dfs,
                    p_value = stats::pchisq(chisq, dfs, lower.tail = FALSE))
  attr(out, "dropped") <- parts$dropped
  out
}

#' @rdname life_table
#' @export
life_table_keep <- function(data, time, event, strata = NULL) {
  .lt_check_columns(data, time, event, strata)
  keep <- !is.na(data[[time]]) & !is.na(data[[event]])
  if (!is.null(strata)) {
    raw <- as.character(data[[strata]])
    keep <- keep & !is.na(raw) & !(raw %in% hvtiRutilities::imputed_levels(data[[strata]]))
  }
  keep
}

.lt_need_kaplan <- function() {
  if (!requireNamespace("TemporalHazard", quietly = TRUE)) {
    stop("The life table needs the TemporalHazard package, which is not installed.", call. = FALSE)
  }
}

.lt_check_columns <- function(data, time, event, strata) {
  if (!is.data.frame(data)) stop("`data` must be a data frame.", call. = FALSE)
  if (!is.null(strata) && (!is.character(strata) || length(strata) != 1L)) {
    stop("`strata` must name one column, or be NULL.", call. = FALSE)
  }
  miss <- setdiff(c(time, event, strata), names(data))
  if (length(miss)) stop("Column(s) not in the data: ", paste(miss, collapse = ", "), ".", call. = FALSE)
  invisible(TRUE)
}

# The analyzed rows of `data`, split by stratum, with the counts and the dropped rows.
.lt_parts <- function(data, time, event, strata) {
  .lt_check_columns(data, time, event, strata)
  ok <- !is.na(data[[time]]) & !is.na(data[[event]])
  dropped <- NULL
  if (is.null(strata)) {
    lab <- rep("All", nrow(data))
  } else {
    raw <- as.character(data[[strata]])
    imp <- hvtiRutilities::imputed_levels(data[[strata]])
    is_imp <- ok & raw %in% imp
    is_na <- ok & is.na(raw)
    dropped <- rbind(
      if (any(is_imp)) data.frame(value = imp, n = vapply(imp, function(l) sum(is_imp & raw == l), integer(1)),
                                  reason = "mean-imputed level, not an observed value"),
      if (any(is_na)) data.frame(value = "NA", n = sum(is_na), reason = "missing")
    )
    if (!is.null(dropped)) rownames(dropped) <- NULL
    ok <- ok & !is_imp & !is_na
    lab <- raw
  }
  if (!any(ok)) stop("No row has a recorded time, event and stratum.", call. = FALSE)
  tm <- as.numeric(data[[time]][ok])
  # An event flag that is 0/1 in SAS can arrive as logical; hzr_kaplan() needs a number.
  st <- as.numeric(data[[event]][ok])
  if (!all(st %in% c(0, 1))) {
    stop("`", event, "` must be 0/1 (or logical); it holds ", paste(sort(setdiff(unique(st), c(0, 1))), collapse = ", "),
         ".", call. = FALSE)
  }
  lab <- lab[ok]
  levels <- if (is.null(strata)) "All" else .lt_sort_levels(unique(lab))
  rows <- lapply(stats::setNames(levels, levels), function(s) {
    data.frame(time = tm[lab == s], status = st[lab == s])
  })
  counts <- do.call(rbind, lapply(levels, function(s) {
    p <- rows[[s]]
    data.frame(stratum = s, n = nrow(p), n_events = as.integer(sum(p$status)),
               n_censored = as.integer(sum(p$status == 0)), max_fup = max(p$time))
  }))
  list(rows = rows, counts = counts, dropped = dropped)
}

# Numeric levels sort as numbers, so "10" follows "9"; others sort as text.
.lt_sort_levels <- function(x) {
  num <- suppressWarnings(as.numeric(x))
  if (!anyNA(num)) x[order(num)] else sort(x)
}

# A weighted log-rank statistic over groups `gr`, with weight w(n at risk) at each event time.
.lt_weighted_test <- function(tm, st, gr, weight) {
  k <- max(gr)
  ev <- sort(unique(tm[st == 1]))
  u <- numeric(k)
  v <- matrix(0, k, k)
  for (t in ev) {
    at <- tm >= t
    n_g <- tabulate(gr[at], k)
    d_g <- tabulate(gr[at & tm == t & st == 1], k)
    n <- sum(n_g)
    d <- sum(d_g)
    w <- weight(n)
    u <- u + w * (d_g - n_g * d / n)
    if (n > 1) {
      p <- n_g / n
      v <- v + w^2 * d * (n - d) / (n - 1) * (diag(p, k) - p %o% p)
    }
  }
  # A stratum with nobody at risk at any event time adds nothing and would make v
  # singular; it is left out, and the degrees of freedom count only the others.
  live <- which(diag(v) > 0)
  if (length(live) < 2L) return(list(chisq = NA_real_, df = 0L))
  keep <- live[-length(live)]
  list(chisq = as.numeric(t(u[keep]) %*% solve(v[keep, keep, drop = FALSE], u[keep])), df = length(keep))
}

# The likelihood ratio test of one exponential rate against a rate per group.
.lt_exponential_lr <- function(tm, st, gr) {
  ll <- function(d, t) if (d > 0) d * log(d / t) - d else 0
  d_g <- tapply(st, gr, sum)
  t_g <- tapply(tm, gr, sum)
  2 * (sum(mapply(ll, d_g, t_g)) - ll(sum(st), sum(tm)))
}
