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

# The six scales a covariate might enter a model on, with the id each is chosen
# by in VARIABLES$chosen. The order is the figure's panel order.
.lg_scale_ids <- c("raw", "log", "inverse", "inverse_squared", "squared", "exp")

.lg_one_number <- function(x) is.numeric(x) && length(x) == 1L && is.finite(x)

# The default scale constant: the covariate's median, rounded to one significant
# figure. The SAS jobs typed it by hand (50 for an age, 80 for a weight); it only
# sets the inverse and exponential scales to a readable range, so a round number
# near the middle of the data does the same work.
.lg_constant <- function(x, name = "x") {
  if (!any(!is.na(x))) stop("`", name, "` has no value to take a median of.", call. = FALSE)
  constant <- signif(stats::median(x, na.rm = TRUE), 1L)
  if (constant == 0) {
    stop("The median of `", name, "` rounds to 0, so there is no default constant: set constant for it in VARIABLES.",
         call. = FALSE)
  }
  constant
}

# The six scales of the group means, one column each and one row per group: raw
# is the mean, log is log(mean + shift), inverse is constant / mean, inverse_squared
# is that squared, squared is (mean / constant)^2 and exp is exp(mean / constant).
# A scale that cannot be computed is NA in every group, not only the group that
# breaks it: a line drawn through the other groups would look like a straight one.
# attr(, "notes") names why, by scale. The log of a mean at or below -shift, an
# inverse through a mean of 0 and an overflowing exponential are the cases.
.lg_scales <- function(mean, constant, shift = 0) {
  if (!is.numeric(mean)) stop("mean must be numeric.", call. = FALSE)
  if (!.lg_one_number(constant) || constant == 0) {
    stop("constant must be one finite number other than 0.", call. = FALSE)
  }
  if (!.lg_one_number(shift)) stop("shift must be one finite number.", call. = FALSE)
  out <- list(
    raw = mean,
    log = suppressWarnings(log(mean + shift)),
    inverse = constant / mean,
    inverse_squared = (constant / mean)^2,
    squared = (mean / constant)^2,
    exp = exp(mean / constant)
  )
  notes <- character()
  if (any(mean + shift <= 0)) {
    notes[["log"]] <- paste0("A group mean plus the shift is not positive (the smallest is ", format(min(mean + shift), digits = 3),
                             "), so the log is undefined. Set shift for this covariate in VARIABLES to move it above 0.")
  }
  if (any(mean == 0)) {
    notes[["inverse"]] <- "A group mean is 0, so the constant over the mean is undefined."
    notes[["inverse_squared"]] <- "A group mean is 0, so the constant over the mean is undefined."
  }
  if (any(!is.finite(out$exp))) {
    notes[["exp"]] <- "The exponential of the mean over the constant overflows. Set a larger constant for this covariate in VARIABLES."
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
  v <- .lg_variable_term(name)
  k <- .lg_number(constant)
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
    ggplot2::labs(title = title, x = "Group mean of the covariate, on the scale shown", y = ylab) +
    ggplot2::theme_bw() +
    ggplot2::theme(strip.background = ggplot2::element_rect(fill = "gray92"))
}

# The VARIABLES table, completed and checked against the data. Only `name` is
# required. A blank in any other column, or a column left out, takes that
# covariate's default: continuous, 5 groups, the median-rule constant, no shift,
# the name as its label, and no scale chosen. `exclude` holds columns that may
# not be covariates, the patient identifier. Every message names VARIABLES, the
# setting the author changes; none shows a data value.
.lg_variables <- function(variables, d, exclude = character()) {
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

# The patients whose follow-up is in the window c(lower, upper), both ends
# included, the SAS jobs' early, constant and late phases. Returns the rows kept
# and a count of what was read, what fell before or after the window, what had no
# follow-up and what was kept, never a patient. NULL keeps every row.
.lg_interval <- function(d, time, interval) {
  if (is.null(interval)) return(list(data = d, counts = NULL))
  if (!is.numeric(interval) || length(interval) != 2L || anyNA(interval) || interval[[1L]] >= interval[[2L]]) {
    stop("INTERVAL must be NULL or c(lower, upper) with lower below upper, such as c(0.25, 5).", call. = FALSE)
  }
  if (!time %in% names(d)) {
    stop("TIME names a column this dataset does not have: ", time, ". Change TIME in edit-study-choices.", call. = FALSE)
  }
  follow <- d[[time]]
  inside <- !is.na(follow) & follow >= interval[[1L]] & follow <= interval[[2L]]
  if (!any(inside)) {
    stop("INTERVAL keeps no patient: no follow-up falls between ", interval[[1L]], " and ", interval[[2L]],
         ". Change INTERVAL in edit-study-choices.", call. = FALSE)
  }
  counts <- data.frame(
    count = c("Patients read", "Follow-up before the window", "Follow-up after the window", "Follow-up missing",
              "Patients kept"),
    patients = c(nrow(d), sum(follow < interval[[1L]], na.rm = TRUE), sum(follow > interval[[2L]], na.rm = TRUE),
                 sum(is.na(follow)), sum(inside))
  )
  list(data = d[inside, , drop = FALSE], counts = counts)
}
