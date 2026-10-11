# The numerical core of the lg template: the grouped event rate of a covariate
# on a link scale, the six candidate scales the covariate might enter a model
# on, and the figure that sets them side by side. The design is
# dev/specs/2026-10-11-lg-template-design.md. These are internal, unit-tested
# and called from inst/templates/10_descriptive/lg.qmd, as .check_job_columns()
# and .save_figure() are, so a study's copy of the template carries none of
# this code.

# The covariate's groups. "continuous" is PROC RANK GROUPS=G exactly: rank with
# ties averaged, then group floor(rank * G / (n + 1)), so a converted job
# reproduces the SAS groups and tied values share a group. "ordinal" is
# %logitgr: each observed level is a group, numbered from 0 in order, and
# `groups` is not used. A missing x is dropped, given NA and counted.
.lg_groups <- function(x, groups = 5L, kind = c("continuous", "ordinal")) {
  kind <- match.arg(kind)
  if (!is.numeric(x)) stop("x must be numeric.", call. = FALSE)
  seen <- !is.na(x)
  if (!any(seen)) stop("x has no value to group: every value is missing.", call. = FALSE)
  group <- rep(NA_integer_, length(x))
  if (identical(kind, "ordinal")) {
    group[seen] <- match(x[seen], sort(unique(x[seen]))) - 1L
  } else {
    if (!is.numeric(groups) || length(groups) != 1L || is.na(groups) || groups < 2 || groups != round(groups)) {
      stop("groups must be a whole number of at least 2.", call. = FALSE)
    }
    # rank * G is exact (ranks are whole or end in .5), so a product that is a
    # multiple of n + 1 divides exactly and floor() cannot land one group low.
    group[seen] <- as.integer(floor(rank(x[seen], ties.method = "average") * groups / (sum(seen) + 1)))
  }
  list(group = group, missing = sum(!seen))
}

# An event as 0 and 1. A logical is read as 1 for TRUE; anything else that is not 0, 1 or
# missing stops, so a column coded 1 and 2 does not become a rate of 1.5.
.lg_event <- function(event) {
  if (is.logical(event)) event <- as.integer(event)
  if (!is.numeric(event) || !all(event[!is.na(event)] %in% c(0, 1))) {
    stop("event must be coded 0 and 1 (or TRUE and FALSE), 1 for an event.", call. = FALSE)
  }
  event
}

# One row per group: the covariate's mean, minimum and maximum, the patients with
# an event value (n), their events, the event rate and its value on the link scale.
#   logit:  rate = events / n, link = log(rate / (1 - rate))
#   hazard: rate = events / sum(time), link = log(rate), the constant-hazard
#           rate %logit calls with cox=1 (events per unit of follow-up).
# A patient with no covariate value, or under "hazard" no follow-up, is left out
# before the groups are formed, as %logit deletes them. A patient with no event
# value is ranked with the rest, as in SAS, but counts in neither n nor events.
# A group whose link cannot be computed (a rate of 0 or 1, or no events under
# "hazard") keeps its row with a missing link and is named in attr(, "notes").
# attr(, "dropped") counts the patients without a covariate, without follow-up
# and without an event value.
.lg_table <- function(x, event, time = NULL, groups = 5L, kind = c("continuous", "ordinal"),
                      link = c("logit", "hazard")) {
  kind <- match.arg(kind)
  link <- match.arg(link)
  hazard <- identical(link, "hazard")
  if (length(event) != length(x)) stop("x and event must be the same length.", call. = FALSE)
  event <- .lg_event(event)
  if (hazard) {
    if (is.null(time)) stop("link = \"hazard\" needs time, the follow-up of each patient.", call. = FALSE)
    if (!is.numeric(time) || length(time) != length(x)) {
      stop("time must be numeric, one value for each patient.", call. = FALSE)
    }
    negative <- sum(time < 0, na.rm = TRUE)
    if (negative) {
      stop("time holds ", negative, " negative value", if (negative > 1L) "s", ": follow-up cannot be negative.",
           call. = FALSE)
    }
  }
  keep <- !is.na(x) & (if (hazard) !is.na(time) else TRUE)
  dropped <- c(covariate = sum(is.na(x)), follow_up = if (hazard) sum(!is.na(x) & is.na(time)) else 0L,
               event = sum(keep & is.na(event)))
  x <- x[keep]
  event <- event[keep]
  follow_up <- if (hazard) time[keep]
  rows <- split(seq_along(x), .lg_groups(x, groups, kind)$group)
  n <- vapply(rows, function(i) sum(!is.na(event[i])), integer(1L), USE.NAMES = FALSE)
  events <- vapply(rows, function(i) as.integer(sum(event[i], na.rm = TRUE)), integer(1L), USE.NAMES = FALSE)
  total <- if (hazard) vapply(rows, function(i) sum(follow_up[i]), numeric(1L), USE.NAMES = FALSE)
  defined <- if (hazard) events > 0L & total > 0 else events > 0L & events < n
  rate <- if (hazard) events / total else events / n
  rate[!is.finite(rate)] <- NA_real_
  value <- rep(NA_real_, length(rows))
  value[defined] <- if (hazard) log(rate[defined]) else log(rate[defined] / (1 - rate[defined]))
  out <- data.frame(
    group = seq_along(rows),
    mean = vapply(rows, function(i) mean(x[i]), numeric(1L), USE.NAMES = FALSE),
    min = vapply(rows, function(i) min(x[i]), numeric(1L), USE.NAMES = FALSE),
    max = vapply(rows, function(i) max(x[i]), numeric(1L), USE.NAMES = FALSE),
    n = n, events = events, rate = rate, link = value
  )
  why <- function(k) {
    if (hazard) {
      if (events[[k]] == 0L) return("no patient had the event, so the hazard rate is 0 and its log is undefined")
      return("the follow-up time sums to 0, so the hazard rate is undefined")
    }
    if (n[[k]] == 0L) return("no patient has an event value, so there is no rate")
    if (events[[k]] == 0L) return("no patient had the event, so the rate is 0 and its logit is undefined")
    "every patient had the event, so the rate is 1 and its logit is undefined"
  }
  attr(out, "notes") <- vapply(which(!defined), function(k) {
    paste0("Group ", k, " (n = ", n[[k]], ", events = ", events[[k]], "): ", why(k), ". The point is left blank.")
  }, character(1L))
  attr(out, "dropped") <- dropped
  out
}
