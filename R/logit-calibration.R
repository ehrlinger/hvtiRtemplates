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
#   hazard: rate = events / sum(time) over the patients with an event value,
#           link = log(rate), the constant-hazard rate %logit calls with cox=1
#           (events per unit of follow-up).
# A patient with no covariate value, or under "hazard" no follow-up, is left out
# before the groups are formed, as %logit deletes them. A patient with no event
# value is ranked with the rest, as in SAS, but counts in none of n, events and
# (under "hazard") follow-up, so a rate never divides by time it has no event for.
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
  total <- if (hazard) vapply(rows, function(i) sum(follow_up[i][!is.na(event[i])]), numeric(1L), USE.NAMES = FALSE)
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

# The six scales a covariate might enter a model on, with the id each is chosen
# by in VARIABLES$chosen. The order is the figure's panel order.
.lg_scale_ids <- c("raw", "log", "inverse", "inverse_squared", "squared", "exp")

.lg_one_number <- function(x) is.numeric(x) && length(x) == 1L && is.finite(x)

# The default scale constant: the covariate's median, rounded to one significant
# figure. The SAS jobs typed it by hand (50 for an age, 80 for a weight); it only
# sets the inverse and exponential scales to a readable range, so a round number
# near the middle of the data does the same work. A median that rounds to 0 (a
# 0/1 covariate) has no such number: the default is NA, which leaves the four
# constant-based scales not computable for that covariate until the author sets
# a constant, and does not stop the job.
.lg_constant <- function(x, name = "x") {
  if (!any(!is.na(x))) stop("`", name, "` has no value to take a median of.", call. = FALSE)
  constant <- signif(stats::median(x, na.rm = TRUE), 1L)
  if (constant == 0) NA_real_ else constant
}

# The scales that read the constant; raw and log do not.
.lg_constant_scales <- c("inverse", "inverse_squared", "squared", "exp")

# One scale of a covariate's values, whether the values are group means or
# patients. The figure draws it, the model term writes it, and the chosen-scale
# check applies it to each patient, so all three read the same formula. A
# constant of NA gives NA for the scales that use it.
.lg_transform <- function(x, scale, constant, shift = 0) {
  switch(scale,
    raw = x,
    log = suppressWarnings(log(x + shift)),
    inverse = constant / x,
    inverse_squared = (constant / x)^2,
    squared = (x / constant)^2,
    exp = exp(x / constant)
  )
}

# The six scales of the group means, one column each and one row per group: raw
# is the mean, log is log(mean + shift), inverse is constant / mean, inverse_squared
# is that squared, squared is (mean / constant)^2 and exp is exp(mean / constant).
# A scale that cannot be computed is NA in every group, not only the group that
# breaks it: a line drawn through the other groups would look like a straight one.
# attr(, "notes") names why, by scale. The log of a mean at or below -shift, an
# inverse through a mean of 0 and an overflowing exponential are the cases. With
# no constant (NA), the four scales that use one are not computable.
.lg_scales <- function(mean, constant, shift = 0) {
  if (!is.numeric(mean)) stop("mean must be numeric.", call. = FALSE)
  no_constant <- is.numeric(constant) && length(constant) == 1L && is.na(constant)
  if (!no_constant && (!.lg_one_number(constant) || constant == 0)) {
    stop("constant must be one finite number other than 0.", call. = FALSE)
  }
  if (!.lg_one_number(shift)) stop("shift must be one finite number.", call. = FALSE)
  out <- lapply(stats::setNames(nm = .lg_scale_ids), function(id) .lg_transform(mean, id, constant, shift))
  notes <- character()
  if (any(mean + shift <= 0)) {
    notes[["log"]] <- paste0("A group mean plus the shift is not positive (the smallest is ", format(min(mean + shift), digits = 3),
                             "), so the log is undefined. Set shift for this covariate in VARIABLES to move it above 0.")
  }
  if (no_constant) {
    for (id in .lg_constant_scales) {
      notes[[id]] <- paste0("There is no default constant, because the median of this covariate rounds to 0: ",
                            "set constant for this covariate in VARIABLES to compute this scale.")
    }
  } else {
    if (any(mean == 0)) {
      notes[["inverse"]] <- "A group mean is 0, so the constant over the mean is undefined."
      notes[["inverse_squared"]] <- "A group mean is 0, so the constant over the mean is undefined."
    }
    if (any(!is.finite(out$exp))) {
      notes[["exp"]] <- paste0("The exponential of the mean over the constant overflows. ",
                               "Set a larger constant for this covariate in VARIABLES.")
    }
  }
  for (id in names(notes)) out[[id]][] <- NA_real_
  out <- as.data.frame(out)
  attr(out, "notes") <- notes
  out
}

# A variable as a model term: backquoted when its name is not a syntactic one.
.lg_variable_term <- function(name) if (identical(make.names(name), name)) name else paste0("`", name, "`")

# A number as it is written in a term: never in exponent form, never padded.
.lg_number <- function(x) format(x, digits = 15L, scientific = FALSE, trim = TRUE)

# The term for one chosen scale, ready for an lm job's PREDICTORS. Evaluated on
# the covariate it gives the scale .lg_scales() draws, which the tests check.
.lg_term <- function(name, scale, constant, shift = 0) {
  if (!scale %in% .lg_scale_ids) {
    stop("scale must be one of ", paste(.lg_scale_ids, collapse = ", "), ".", call. = FALSE)
  }
  if (scale %in% .lg_constant_scales && !.lg_one_number(constant)) {
    stop("The scale ", scale, " needs a constant: set constant for this covariate in VARIABLES.", call. = FALSE)
  }
  v <- .lg_variable_term(name)
  k <- if (.lg_one_number(constant)) .lg_number(constant)
  switch(scale,
    raw = v,
    log = if (shift == 0) paste0("log(", v, ")") else paste0("log(", v, if (shift < 0) " - " else " + ", .lg_number(abs(shift)), ")"),
    inverse = paste0("I(", k, " / ", v, ")"),
    inverse_squared = paste0("I((", k, " / ", v, ")^2)"),
    squared = paste0("I((", v, " / ", k, ")^2)"),
    exp = paste0("I(exp(", v, " / ", k, "))")
  )
}

# The R-squared of a straight line through the group points, weighted by group
# size, which is the weighted squared correlation of x and y. It is guidance for
# "straightest", not a decision: a group of 3 patients should not pull the line
# as hard as a group of 300. NA when fewer than three groups have a link value,
# or when either side has no spread, because two points are always on a line.
# Computed from the correlation rather than summary(lm()), which warns on the
# exact fit this is most often asked to recognize.
.lg_rsq <- function(x, y, w) {
  ok <- is.finite(x) & is.finite(y) & w > 0
  if (sum(ok) < 3L || length(unique(x[ok])) < 2L || length(unique(y[ok])) < 2L) return(NA_real_)
  w <- w[ok]
  dx <- x[ok] - sum(w * x[ok]) / sum(w)
  dy <- y[ok] - sum(w * y[ok]) / sum(w)
  sum(w * dx * dy)^2 / (sum(w * dx^2) * sum(w * dy^2))
}

.lg_panel_labels <- c(raw = "Raw", log = "Log", inverse = "Inverse", inverse_squared = "Inverse squared",
                      squared = "Squared", exp = "Exponential")

# One panel per scale: the group link value against the group mean on that scale,
# the points joined by a line as the SAS plots did, and the weighted R-squared in
# the corner. A scale that cannot be computed is an empty panel that says so. No
# fitted line is drawn: the figure is for reading by eye, and the R-squared is
# its only aid. `table` is .lg_table()'s result and `scales` .lg_scales()'s.
.lg_plot <- function(table, scales, link = c("logit", "hazard"), title = NULL) {
  link <- match.arg(link)
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("The ggplot2 package is needed to draw the figure.", call. = FALSE)
  if (nrow(table) != nrow(scales)) stop("table and scales must have one row for each group.", call. = FALSE)
  ids <- .lg_scale_ids
  panel <- function(id) factor(rep(.lg_panel_labels[[id]], nrow(table)), levels = .lg_panel_labels)
  points <- do.call(rbind, lapply(ids, function(id) data.frame(panel = panel(id), x = scales[[id]], y = table$link)))
  rsq <- vapply(ids, function(id) .lg_rsq(scales[[id]], table$link, table$n), numeric(1L))
  empty <- vapply(ids, function(id) all(is.na(scales[[id]])), logical(1L))
  say <- data.frame(
    panel = factor(unname(.lg_panel_labels), levels = .lg_panel_labels),
    label = ifelse(empty, "Not computable",
                   ifelse(is.na(rsq), "R-squared not available", sprintf("R-squared = %.2f", rsq)))
  )
  # An empty panel has no x to scale on, so it is given the unit range.
  frame <- data.frame(panel = factor(unname(.lg_panel_labels)[empty], levels = .lg_panel_labels))
  blank <- if (nrow(frame)) {
    y <- range(table$link, finite = TRUE, na.rm = TRUE)
    data.frame(panel = rep(frame$panel, each = 2L), x = c(0, 1), y = if (all(is.finite(y))) y else c(0, 1))
  } else {
    data.frame(panel = factor(character(), levels = .lg_panel_labels), x = numeric(), y = numeric())
  }
  ylab <- if (identical(link, "hazard")) "Log of events per unit of follow-up" else "Logit of the event rate"
  ggplot2::ggplot(points, ggplot2::aes(x = !!rlang::sym("x"), y = !!rlang::sym("y"))) +
    ggplot2::geom_blank(data = blank) +
    ggplot2::geom_line(na.rm = TRUE, color = "gray45") +
    ggplot2::geom_point(na.rm = TRUE, size = 2) +
    ggplot2::geom_text(data = say, ggplot2::aes(label = !!rlang::sym("label")), x = -Inf, y = Inf, hjust = -0.1, vjust = 1.6,
                       size = 3.2, inherit.aes = FALSE) +
    ggplot2::facet_wrap("panel", ncol = 3L, scales = "free_x") +
    # Headroom, so the R-squared in the corner never sits on a point.
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0.05, 0.2))) +
    # About three ticks: a panel is under 2 inches wide, and five 12 pt labels run together.
    ggplot2::scale_x_continuous(n.breaks = 3) +
    ggplot2::labs(title = title, x = "Group mean of the covariate, on the scale shown", y = ylab) +
    hvtiPlotR::theme_hv_manuscript(base_size = 12) +
    ggplot2::theme(strip.background = ggplot2::element_rect(fill = "gray92"))
}

# The smallest group a rate is read from, and the most levels an ordinal
# covariate takes a group each for.
.lg_min_group <- 5L
.lg_max_levels <- 20L

# One covariate's groups, checked: an ordinal covariate with more than
# .lg_max_levels levels, or any group with fewer than .lg_min_group patients,
# stops. The count is the table's n: patients with a covariate value (and, under
# the hazard, follow-up) and an event value, in the group the ranking gives them.
.lg_check_groups <- function(name, x, kind, groups, event = NULL, time = NULL) {
  if (identical(kind, "ordinal")) {
    levels <- length(unique(x[!is.na(x)]))
    if (levels > .lg_max_levels) {
      stop("VARIABLES: `", name, "` is ordinal with ", levels, " levels, more than the ", .lg_max_levels,
           " a group each can take. Treat it as continuous or recode it into fewer levels.", call. = FALSE)
    }
  }
  seen <- !is.na(x) & (if (is.null(time)) TRUE else !is.na(time))
  if (!any(seen)) stop("VARIABLES: `", name, "` has no patient with a value to group.", call. = FALSE)
  group <- .lg_groups(x[seen], groups, kind)$group
  counted <- if (is.null(event)) rep(TRUE, sum(seen)) else !is.na(event[seen])
  size <- vapply(sort(unique(group)), function(g) sum(group == g & counted), integer(1L))
  if (min(size) < .lg_min_group) {
    stop("VARIABLES: `", name, "` has a group of fewer than ", .lg_min_group, " patients (the smallest has ", min(size), "). ",
         if (identical(kind, "ordinal")) {
           "Combine levels of it, by recoding the column, so that each group is larger."
         } else {
           "Lower groups for it in VARIABLES so that each group is larger."
         }, call. = FALSE)
  }
}

# The VARIABLES table, completed and checked against the data. Only `name` is
# required. A blank in any other column, or a column left out, takes that
# covariate's default: continuous, 5 groups, the median-rule constant (NA when
# that rounds to 0), no shift, the name as its label, and no scale chosen.
# `exclude` holds columns that may not be covariates, the patient identifier.
# Two checks keep a figure from resting on groups too small to read: an ordinal
# covariate has at most 20 levels, and no group has fewer than 5 patients. The
# groups counted are those .lg_table() will form, so `event` (patients with no
# event value are in no group's n) and `time` (under the hazard, patients with
# no follow-up are left out before the ranking) are passed when the job has
# them. Every message names VARIABLES, the setting the author changes; none
# shows a data value.
.lg_variables <- function(variables, d, exclude = character(), event = NULL, time = NULL) {
  columns <- c("name", "kind", "groups", "constant", "shift", "label", "chosen")
  if (!is.data.frame(variables) || !nrow(variables)) {
    stop("VARIABLES must be a data frame with one row for each covariate and at least a `name` column.", call. = FALSE)
  }
  if (!"name" %in% names(variables)) stop("VARIABLES needs a `name` column.", call. = FALSE)
  unknown <- setdiff(names(variables), columns)
  if (length(unknown)) {
    stop("VARIABLES has a column the job does not use: ", paste(unknown, collapse = ", "),
         ". The columns are ", paste(columns, collapse = ", "), ".", call. = FALSE)
  }
  name <- as.character(variables$name)
  if (anyNA(name) || any(!nzchar(name))) stop("VARIABLES has a covariate with no name.", call. = FALSE)
  if (anyDuplicated(name)) {
    stop("VARIABLES names a covariate more than once: ", paste(unique(name[duplicated(name)]), collapse = ", "), ".",
         call. = FALSE)
  }
  absent <- setdiff(name, names(d))
  if (length(absent)) {
    stop("VARIABLES names ", if (length(absent) == 1L) "a column" else "columns", " this dataset does not have: ",
         paste(absent, collapse = ", "), ". Change VARIABLES in edit-study-choices.", call. = FALSE)
  }
  reached <- intersect(name, exclude)
  if (length(reached)) {
    stop("VARIABLES names the patient identifier (`", reached[[1L]], "`); a calibration cannot use it as a covariate.",
         call. = FALSE)
  }
  text <- name[!vapply(name, function(v) is.numeric(d[[v]]), logical(1L))]
  if (length(text)) {
    stop("VARIABLES names a column that is not numeric: ", paste(text, collapse = ", "),
         ". A calibration ranks the covariate, so recode it as a number first.", call. = FALSE)
  }
  column <- function(field) if (field %in% names(variables)) variables[[field]] else rep(NA, nrow(variables))
  number <- function(field, what) {
    x <- column(field)
    if (!(is.numeric(x) || all(is.na(x)))) stop("VARIABLES$", field, " must be ", what, ".", call. = FALSE)
    as.numeric(x)
  }
  kind <- as.character(column("kind"))
  kind[is.na(kind)] <- "continuous"
  if (!all(kind %in% c("continuous", "ordinal"))) {
    stop("VARIABLES$kind must be \"continuous\" or \"ordinal\".", call. = FALSE)
  }
  groups <- number("groups", "a whole number of at least 2")
  groups[is.na(groups)] <- 5
  if (any(!is.finite(groups) | groups < 2 | groups != round(groups))) {
    stop("VARIABLES$groups must be a whole number of at least 2.", call. = FALSE)
  }
  for (i in seq_along(name)) .lg_check_groups(name[[i]], d[[name[[i]]]], kind[[i]], as.integer(groups[[i]]), event, time)
  constant <- number("constant", "a finite number other than 0")
  if (any(!is.na(constant) & (!is.finite(constant) | constant == 0))) {
    stop("VARIABLES$constant must be a finite number other than 0.", call. = FALSE)
  }
  for (i in which(is.na(constant))) constant[[i]] <- .lg_constant(d[[name[[i]]]], name[[i]])
  shift <- number("shift", "a finite number")
  shift[is.na(shift)] <- 0
  if (any(!is.finite(shift))) stop("VARIABLES$shift must be a finite number.", call. = FALSE)
  label <- as.character(column("label"))
  label[is.na(label) | !nzchar(label)] <- name[is.na(label) | !nzchar(label)]
  chosen <- as.character(column("chosen"))
  chosen[!is.na(chosen) & !nzchar(chosen)] <- NA_character_
  if (any(!is.na(chosen) & !chosen %in% .lg_scale_ids)) {
    stop("VARIABLES$chosen must be NA or one of ", paste(.lg_scale_ids, collapse = ", "), ".", call. = FALSE)
  }
  data.frame(name = name, kind = kind, groups = as.integer(groups), constant = constant, shift = shift,
             label = label, chosen = chosen, stringsAsFactors = FALSE)
}

# One phase of follow-up, as the SAS jobs took it (the legacy constant-hazard
# template): INTERVAL = c(start, end).
#   * A patient whose follow-up ended before `start` is left out and counted
#     (`iv_dead < start` deleted them), as is one with no follow-up. A follow-up of
#     exactly `start` stays.
#   * Every other patient is censored at `end`: one followed past it (`iv_dead > end`)
#     has no event and counts as followed to `end`, and an event after `end` is not
#     counted. A follow-up of exactly `end` stays, with its event.
# The follow-up the hazard link sums is then the time at risk inside the window,
# pmin(time, end) - start. The legacy template summed pmin(time, end) from 0, so the
# months before `start` entered every patient's denominator; the shift is the one
# deliberate difference, and it is this line: `pmin(follow, end) - start`.
# The logit link keeps the same patients and the same censored events, and reads
# no follow-up. The columns of `d` are not changed: the adjusted event and
# follow-up come back as vectors for the rows kept. NULL keeps every row, and
# returns the event and follow-up as they are. `counts` reports what was read, left
# out before the start or for want of follow-up, kept, censored at the end and the
# events that fell after it, never a patient.
# Follow-up is a duration, so a negative value is a data error. It is refused
# rather than used: a hazard would sum it into time at risk, and a window with a
# start below 0 would even turn it positive. Counts only, never values.
.lg_follow_up <- function(x, name) {
  negative <- sum(x < 0, na.rm = TRUE)
  if (negative) {
    stop(negative, if (negative == 1L) " patient has" else " patients have", " negative follow-up in ", name,
         ". Follow-up is a duration and cannot be below 0: correct the data, or change TIME in edit-study-choices.",
         call. = FALSE)
  }
  invisible(x)
}

.lg_interval <- function(d, event, time, interval) {
  e <- .lg_event(d[[event]])
  if (is.null(interval)) {
    return(list(data = d, event = e, time = if (!is.null(time)) d[[time]], counts = NULL))
  }
  if (!is.numeric(interval) || length(interval) != 2L || anyNA(interval) || interval[[1L]] >= interval[[2L]]) {
    stop("INTERVAL must be NULL or c(start, end) with start below end, such as c(0.25, 5).", call. = FALSE)
  }
  if (interval[[1L]] < 0) {
    stop("INTERVAL must have a start of 0 or later: follow-up is measured from 0.", call. = FALSE)
  }
  if (is.null(time)) stop("INTERVAL needs TIME, the follow-up column.", call. = FALSE)
  if (!time %in% names(d)) {
    stop("TIME names a column this dataset does not have: ", time, ". Change TIME in edit-study-choices.", call. = FALSE)
  }
  start <- interval[[1L]]
  end <- interval[[2L]]
  follow <- .lg_follow_up(d[[time]], time)
  before <- !is.na(follow) & follow < start
  missing <- is.na(follow)
  kept <- !before & !missing
  if (!any(kept)) {
    stop("INTERVAL keeps no patient: no follow-up reaches ", start, ". Change INTERVAL in edit-study-choices.", call. = FALSE)
  }
  follow <- follow[kept]
  e <- e[kept]
  past <- follow > end
  counts <- data.frame(
    count = c("Patients read", "Left out: follow-up before the start", "Left out: follow-up missing", "Patients kept",
              "Censored at the end", "Events after the end, no longer counted"),
    patients = c(nrow(d), sum(before), sum(missing), sum(kept), sum(past), sum(e[past] == 1, na.rm = TRUE))
  )
  e[past] <- 0L
  list(data = d[kept, , drop = FALSE], event = e, time = pmin(follow, end) - start, counts = counts)
}

# The choices made, as the table lg-scales.rds holds: variable, chosen, term,
# constant and shift, one row for each covariate with a usable choice. `scales`
# is a list of .lg_scales() results by covariate name and `d` the data the groups
# came from. A covariate with no choice, or whose chosen scale cannot be computed,
# is not a row: it is named in $problems with the reason, so the job can warn in
# a draft and stop a final render, as an open EDIT marker does. A chosen scale is
# impossible when its group means cannot be computed, and also when it is not a
# number for some patient, though every mean is fine: the log of a covariate that
# is 0 for a few patients, say, whose lowest group still has a mean above 0. The
# model would drop those patients without a word. The message counts them and
# shows no value.
.lg_choices <- function(variables, scales, d) {
  problems <- character()
  usable <- logical(nrow(variables))
  for (i in seq_len(nrow(variables))) {
    name <- variables$name[[i]]
    chosen <- variables$chosen[[i]]
    if (is.na(chosen)) {
      problems[[name]] <- "no scale chosen yet"
    } else if (all(is.na(scales[[name]][[chosen]]))) {
      problems[[name]] <- paste0("the chosen scale, ", chosen, ", cannot be computed: ", attr(scales[[name]], "notes")[[chosen]])
    } else {
      x <- d[[name]]
      broken <- sum(!is.finite(.lg_transform(x[!is.na(x)], chosen, variables$constant[[i]], variables$shift[[i]])))
      if (broken) {
        problems[[name]] <- paste0("the chosen scale, ", chosen, ", is not a number for ", broken, " patient",
                                   if (broken > 1L) "s", ": ", .lg_patient_reason(chosen))
      } else {
        usable[[i]] <- TRUE
      }
    }
  }
  kept <- variables[usable, , drop = FALSE]
  terms <- vapply(seq_len(nrow(kept)), function(i) {
    .lg_term(kept$name[[i]], kept$chosen[[i]], kept$constant[[i]], kept$shift[[i]])
  }, character(1L))
  list(
    table = data.frame(variable = kept$name, chosen = kept$chosen, term = terms, constant = kept$constant,
                       shift = kept$shift, stringsAsFactors = FALSE),
    problems = problems
  )
}

# Why a scale is not a number for a patient, and what to change.
.lg_patient_reason <- function(scale) {
  switch(scale,
    log = paste0("the covariate plus the shift is not above 0 for them. ",
                 "Set shift for this covariate in VARIABLES, or choose another scale."),
    inverse = , inverse_squared = paste0("the constant over the covariate is undefined for them, ",
                                         "because the covariate is 0. Choose another scale."),
    squared = , exp = paste0("the ", if (identical(scale, "exp")) "exponential" else "square",
                             " overflows for them. Set a larger constant for this covariate in VARIABLES."),
    "the covariate is not a finite number for them."
  )
}

# The line an lm job's PREDICTORS takes for these terms: on one line when it fits
# in 100 characters, a term to a line when it does not.
.lg_predictors <- function(terms) {
  if (!length(terms)) return("No scale is chosen yet, so there is no PREDICTORS line.")
  items <- encodeString(terms, quote = "\"")
  one <- paste0("PREDICTORS <- c(", paste(items, collapse = ", "), ")")
  if (nchar(one) <= 100L) return(one)
  paste0("PREDICTORS <- c(\n", paste0("  ", items, collapse = ",\n"), "\n)")
}
