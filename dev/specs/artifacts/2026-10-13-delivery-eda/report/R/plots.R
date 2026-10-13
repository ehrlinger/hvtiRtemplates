# Plots for the data delivery EDA report.
#
# These are plain ggplot2 placeholders for the hvtiPlotR postage stamps, so the
# template runs anywhere. Swap each function body for the hvtiPlotR version
# without changing its arguments.

eda_colors <- c(base = "#1a2e4a", flagged = "#c2410c", muted = "#94a3b8",
                event = "#c2410c", censored = "#4b6a8a")

theme_eda <- function(base_size = 10) {
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      strip.text = ggplot2::element_text(face = "bold", hjust = 0),
      plot.title.position = "plot",
      legend.position = "bottom"
    )
}

chunk <- function(x, size) split(x, ceiling(seq_along(x) / size))

#' Goodness of follow-up: each patient at (index date, observed interval),
#' against the potential-follow-up line, one panel per event.
plot_gof <- function(gof, close_date) {
  gof$status <- ifelse(gof$event %in% 1, "Event", "Censored")
  pot <- gof[order(gof$index), c("event_label", "index", "potential")]
  ggplot2::ggplot(gof[!is.na(gof$interval), ], ggplot2::aes(index, interval)) +
    ggplot2::geom_line(data = pot, ggplot2::aes(y = potential), colour = eda_colors[["muted"]],
                       linewidth = 0.6) +
    ggplot2::geom_point(ggplot2::aes(colour = status, shape = status), size = 0.9, alpha = 0.7) +
    ggplot2::scale_colour_manual(values = c(Event = eda_colors[["event"]],
                                            Censored = eda_colors[["censored"]]), name = NULL) +
    ggplot2::scale_shape_manual(values = c(Event = 4, Censored = 16), name = NULL) +
    ggplot2::facet_wrap(~event_label, scales = "free_y") +
    ggplot2::labs(x = "Index date", y = sprintf("Follow-up (%s)", gof$unit[1]),
                  caption = sprintf("Grey line: potential follow-up to %s. Censored points well below it are short follow-up.",
                                    close_date)) +
    theme_eda()
}

plot_missing_share <- function(summ) {
  s <- summ[summ$n_missing > 0, ]
  if (nrow(s) == 0) return(NULL)
  s$variable <- stats::reorder(s$variable, s$share_missing)
  ggplot2::ggplot(s, ggplot2::aes(share_missing, variable)) +
    ggplot2::geom_col(fill = eda_colors[["base"]], width = 0.7) +
    ggplot2::scale_x_continuous(labels = scales::percent, limits = c(0, 1)) +
    ggplot2::labs(x = "Missing", y = NULL) +
    theme_eda()
}

plot_missing_era <- function(by_year, vars) {
  if (is.null(by_year)) return(NULL)
  b <- by_year[by_year$variable %in% vars, ]
  if (nrow(b) == 0) return(NULL)
  ggplot2::ggplot(b, ggplot2::aes(year, variable, fill = share)) +
    ggplot2::geom_tile(colour = "white") +
    ggplot2::scale_fill_gradient(low = "#f0f4f8", high = eda_colors[["base"]],
                                 labels = scales::percent, limits = c(0, 1), name = "Missing") +
    ggplot2::labs(x = "Year of index date", y = NULL) +
    theme_eda()
}

#' Continuous postage stamps: each variable over the index date (or row order),
#' with values outside the flag bounds highlighted.
plot_continuous_stamps <- function(df, vars, date_var, bounds) {
  x <- if (is.null(date_var)) seq_len(nrow(df)) else df[[date_var]]
  long <- dplyr::bind_rows(lapply(vars, function(v) {
    b <- bounds[[v]]
    y <- df[[v]]
    tibble::tibble(variable = v, x = x, y = y,
                   flagged = !is.null(b) & !is.na(y) & (y < b[1] | y > b[2]))
  }))
  long <- long[!is.na(long$y), ]
  ggplot2::ggplot(long, ggplot2::aes(x, y)) +
    ggplot2::geom_point(ggplot2::aes(colour = flagged), size = 0.6, alpha = 0.5) +
    ggplot2::scale_colour_manual(values = c(`FALSE` = eda_colors[["base"]],
                                            `TRUE` = eda_colors[["flagged"]]),
                                 labels = c(`FALSE` = "Within bounds", `TRUE` = "Flagged"),
                                 name = NULL) +
    ggplot2::facet_wrap(~variable, scales = "free_y", ncol = 3) +
    ggplot2::labs(x = if (is.null(date_var)) "Row" else "Index date", y = NULL) +
    theme_eda()
}

#' Categorical postage stamps: percentage of each level by year of index date.
#' One small panel per variable, each with its own legend; missing and unknown
#' codes are grey so they read as gaps rather than as levels.
plot_categorical_stamps <- function(df, vars, date_var, unknown_codes = character()) {
  yr <- if (is.null(date_var)) rep("All", nrow(df)) else format(df[[date_var]], "%Y")
  pal <- c("#1a2e4a", "#4b6a8a", "#8fb1d4", "#c2410c", "#e8a33d", "#2f7d5b", "#7c5a9e", "#b8c4d1")
  panels <- lapply(vars, function(v) {
    lev <- as.character(df[[v]])
    lev[is.na(lev) | trimws(lev) == ""] <- "(missing)"
    d <- dplyr::count(tibble::tibble(year = yr, level = lev), year, level)
    grey_lev <- unique(d$level[d$level == "(missing)" | tolower(d$level) %in% tolower(unknown_codes)])
    real <- sort(setdiff(unique(d$level), grey_lev))
    cols <- c(stats::setNames(rep(pal, length.out = length(real)), real),
              stats::setNames(rep("#cbd5e1", length(grey_lev)), grey_lev))
    d$level <- factor(d$level, levels = c(real, grey_lev))
    ggplot2::ggplot(d, ggplot2::aes(year, n, fill = level)) +
      ggplot2::geom_col(position = "fill", width = 0.9) +
      ggplot2::scale_fill_manual(values = cols, name = NULL) +
      ggplot2::scale_y_continuous(labels = scales::percent) +
      ggplot2::scale_x_discrete(breaks = function(b) b[seq(1, length(b), by = max(1, length(b) %/% 5))]) +
      ggplot2::labs(title = v, x = NULL, y = NULL) +
      theme_eda(9) +
      ggplot2::theme(legend.position = "right", legend.key.size = ggplot2::unit(0.35, "cm"),
                     plot.title = ggplot2::element_text(face = "bold", size = 9))
  })
  patchwork::wrap_plots(panels, ncol = 2)
}

#' Measurement timing: one row per sampled patient, ordered by index date,
#' with a point at each measurement's time from index.
plot_measurement_timing <- function(long, pts, lspec, pspec, n_sample = 150, seed = 1) {
  ids <- unique(long[[lspec$id]][!is.na(long$.years)])
  set.seed(seed)
  ids <- if (length(ids) > n_sample) sample(ids, n_sample) else ids
  d <- long[long[[lspec$id]] %in% ids & !is.na(long$.years), ]
  idx <- pts[[pspec$date_var]][match(ids, pts[[pspec$id]])]
  rank <- stats::setNames(rank(idx, ties.method = "first"), ids)
  d$row <- rank[as.character(d[[lspec$id]])]
  ggplot2::ggplot(d, ggplot2::aes(.years, row)) +
    ggplot2::geom_vline(xintercept = 0, colour = eda_colors[["muted"]]) +
    ggplot2::geom_point(size = 0.6, colour = eda_colors[["base"]], alpha = 0.7) +
    ggplot2::labs(x = "Years from index", y = sprintf("Patients (sample of %d, earliest index at bottom)", length(ids))) +
    theme_eda() +
    ggplot2::theme(axis.text.y = ggplot2::element_blank(), panel.grid.major.y = ggplot2::element_blank())
}

plot_per_patient <- function(per_patient) {
  ggplot2::ggplot(per_patient, ggplot2::aes(n)) +
    ggplot2::geom_histogram(binwidth = 1, fill = eda_colors[["base"]], colour = "white") +
    ggplot2::labs(x = "Measurements per cohort patient", y = "Patients") +
    theme_eda()
}

#' Trajectories for a sample of patients with the binned median and IQR.
plot_trajectories <- function(long, lspec, value, n_sample = 30, seed = 1) {
  d <- long[!is.na(long[[value]]) & !is.na(long$.years), ]
  if (nrow(d) == 0) return(NULL)
  d$y <- d[[value]]
  d$bin <- round(d$.years)
  band <- dplyr::summarise(dplyr::group_by(d, bin), n = dplyr::n(),
                           lo = stats::quantile(y, 0.25), med = stats::median(y),
                           hi = stats::quantile(y, 0.75), .groups = "drop")
  band <- band[band$n >= 10, ]
  set.seed(seed)
  ids <- unique(d[[lspec$id]])
  ids <- if (length(ids) > n_sample) sample(ids, n_sample) else ids
  s <- d[d[[lspec$id]] %in% ids, ]
  s <- s[order(s[[lspec$id]], s$.years), ]
  s$grp <- s[[lspec$id]]
  ggplot2::ggplot() +
    ggplot2::geom_ribbon(data = band, ggplot2::aes(bin, ymin = lo, ymax = hi),
                         fill = "#dde4ed") +
    ggplot2::geom_line(data = s, ggplot2::aes(.years, y, group = grp),
                       colour = eda_colors[["censored"]], alpha = 0.5, linewidth = 0.3) +
    ggplot2::geom_line(data = band, ggplot2::aes(bin, med), colour = eda_colors[["base"]],
                       linewidth = 0.9) +
    ggplot2::labs(x = "Years from index", y = value,
                  caption = sprintf("Thin lines: %d sampled patients. Band: yearly IQR; dark line: median (bins with at least 10 measurements).",
                                    length(ids))) +
    theme_eda()
}
