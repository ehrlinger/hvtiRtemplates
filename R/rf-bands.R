# Confidence bands for the rf explain templates: VIMP intervals from randomForestSRC's
# subsample(), and pointwise bands on the partial plots from refits of our own on
# subsamples drawn the same way. The design is dev/specs/2026-10-26-rf-confidence-bands-design.md.

# randomForestSRC's default subsample fraction, or the study's, checked. The value is
# always passed to subsample() explicitly, so a change of default there cannot make the
# two kinds of band use different subsamples.
.band_subratio <- function(n, subratio) {
  if (is.null(subratio)) return(if (n <= 1000) exp(-1) else exp(-1) * sqrt(1000 / n))
  if (!is.numeric(subratio) || length(subratio) != 1L || is.na(subratio) || subratio <= 0 || subratio > 0.5) {
    stop("SUBRATIO must be NULL or one number above 0 and at most 0.5: above that every subsample ",
         "forest is nearly the full forest and the bands shrink to its tree-to-tree noise.", call. = FALSE)
  }
  subratio
}

.band_size <- function(n, subratio) max(2L, as.integer(round(subratio * n)))

# The delete-d jackknife standard error extract.subsample() reports as se.jk.Z: the
# mean squared deviation of the subsample estimates about the full forest's, scaled by
# the subsample fraction. `star` has one row per point and one column per subsample;
# a subsample that could not give a value (NA) is left out of that point's mean.
.band_se <- function(hat, star, subratio) {
  sqrt(subratio * rowMeans((star - hat)^2, na.rm = TRUE))
}

# The band read off at the values a study chose for its bars, each subsample's curve
# taken straight between grid points, as the figure draws the line.
.band_at <- function(x, hat, star, at) {
  if (any(at < min(x) | at > max(x))) {
    stop("BAND_AT asks for values outside the observed range, ", signif(min(x), 4), " to ", signif(max(x), 4),
         ".", call. = FALSE)
  }
  # approx() errors on fewer than two non-NA points; a failed subsample reads as NA instead.
  lin <- function(y) if (sum(!is.na(y)) < 2L) rep(NA_real_, length(at)) else stats::approx(x, y, xout = at)$y
  list(x = at, hat = lin(hat), star = matrix(apply(star, 2L, lin), nrow = length(at)))
}

# The smallest subsample fraction that gives `floor` of the rarest outcome, from the
# cohort's count of it.
.band_floor_need <- function(rare_total, floor = 100) floor / rare_total

# The groups a subsample is drawn within, as subsample() draws them: event status for a
# survival forest, the class for a classification forest, none for regression.
.band_strata <- function(forest) {
  switch(forest$family,
    surv = factor(forest$yvar[[forest$yvar.names[2]]] > 0, levels = c(FALSE, TRUE)),
    class = factor(forest$yvar),
    NULL
  )
}

# B subsamples of the forest's rows, each a fraction `subratio` of them, drawn without
# replacement within the strata. R's generator draws them, which cache_fit() seeds.
.band_rows <- function(forest, B, subratio) { # nolint: object_name_linter. B is the subsample() argument's name.
  n <- forest$n
  b <- .band_size(n, subratio)
  strata <- .band_strata(forest)
  draw <- function() {
    if (is.null(strata)) return(sort(sample.int(n, b)))
    sort(unlist(lapply(split(seq_len(n), strata), function(i) {
      k <- min(length(i), as.integer(round(b * length(i) / n)))
      i[sample.int(length(i), k)]
    }), use.names = FALSE))
  }
  rows <- lapply(seq_len(B), function(i) draw())
  if (identical(forest$family, "surv")) {
    event <- forest$yvar[[forest$yvar.names[2]]] > 0
    if (any(vapply(rows, function(r) !any(event[r]), logical(1)))) {
      stop("A subsample of ", b, " patients holds no event. Raise SUBRATIO.", call. = FALSE)
    }
  }
  rows
}

# A forest grown on `rows` with the settings of `forest`, read off the saved forest
# rather than its call: the fit job's call names its own variables (model, NTREE), which
# do not exist here. The seed is handed to rfsrc(), negated as randomForestSRC documents.
.band_refit <- function(forest, rows, seed) {
  y <- forest$yvar.names
  d <- forest$xvar
  if (is.data.frame(forest$yvar)) d <- cbind(forest$yvar, d) else d[[y]] <- forest$yvar
  d <- d[rows, , drop = FALSE]
  tick <- function(v) paste0("`", v, "`")
  formula <- if (identical(forest$family, "surv")) {
    stats::as.formula(sprintf("Surv(%s, %s) ~ .", tick(y[1]), tick(y[2])))
  } else {
    stats::as.formula(paste(tick(y), "~ ."))
  }
  na_action <- if (length(forest$imputed.indv)) "na.impute" else "na.omit"
  randomForestSRC::rfsrc(formula, data = d, ntree = forest$ntree, mtry = forest$mtry,
                         nodesize = forest$nodesize, nsplit = forest$nsplit, splitrule = forest$splitrule,
                         na.action = na_action, importance = "none", seed = -abs(seed))
}

# The values a variable's partial was drawn at, read from the full forest's
# gg_partial_rfsrc result, so every subsample forest is evaluated on the same grid.
.band_grid <- function(pd, var) {
  for (type in c("continuous", "categorical")) {
    frame <- pd[[type]]
    if (is.data.frame(frame) && var %in% frame$name) {
      x <- frame$x[frame$name == var]
      x <- if (is.factor(x)) levels(droplevels(x)) else sort(unique(x))
      return(list(type = type, x = x))
    }
  }
  stop("No partial was drawn for ", var, ".", call. = FALSE)
}

# The horizons the full forest's partial was read at, already snapped to its event times.
.band_times <- function(pd) {
  times <- unlist(lapply(pd[c("continuous", "categorical")], function(f) if (is.data.frame(f)) f$time))
  if (is.null(times)) NULL else sort(unique(as.numeric(times)))
}

# A forest's partial prediction for one variable at the values `x`, and for a survival
# forest at each horizon in `times`, averaged over the patients as gg_partial_rfsrc()
# averages it. A subsample forest snaps `times` to its own nearest event time.
# partial.rfsrc() takes a factor's values as its training level codes, so the labels
# .band_grid() reads off the plot data are matched to the forest's levels here.
.partial_values <- function(forest, var, x, times = NULL) {
  surv <- identical(forest$family, "surv")
  if (!is.numeric(x)) {
    lv <- levels(forest$xvar[[var]])
    x <- if (length(lv)) match(as.character(x), lv) else as.numeric(as.character(x))
  }
  p <- randomForestSRC::partial.rfsrc(forest, partial.xvar = var, partial.values = x,
                                      partial.type = if (surv) "surv", partial.time = if (surv) times)
  as.numeric(randomForestSRC::get.partial.plot.data(p)$yhat)
}

# The B subsample forests are grown once for every variable whose band is missing, and
# each forest is dropped as soon as its partials are read: B forests at once would not
# fit in a session. The first .band_partial() call fills the pool; the rest read it.
# The template reaches the pool through get(), so cache_fit() keys each band on its own
# variable's grid and not on the pool, which changes with the set of missing variables.
.band_pool <- function(vars, grids, progress = NULL) {
  pool <- new.env(parent = emptyenv())
  pool$vars <- vars
  pool$grids <- grids
  pool$progress <- progress
  pool
}

.band_fill <- function(pool, forest, rows, times, seed) {
  B <- length(rows) # nolint: object_name_linter. B is the subsample() argument's name.
  m <- function(v) length(pool$grids[[v]]$x) * max(1L, length(times))
  pool$star <- lapply(stats::setNames(pool$vars, pool$vars), function(v) matrix(NA_real_, m(v), B))
  for (b in seq_len(B)) {
    fit <- .band_refit(forest, rows[[b]], seed = abs(seed) + b)
    for (v in pool$vars) {
      # A factor level absent from this subsample, say, leaves its column NA; the SE is read from the rest.
      value <- tryCatch(.partial_values(fit, v, pool$grids[[v]]$x, times), error = function(e) NULL)
      if (length(value) == nrow(pool$star[[v]])) pool$star[[v]][, b] <- value
    }
    rm(fit)
    if (is.function(pool$progress)) pool$progress(b, B)
  }
  # Warn once per variable when subsample forests gave it no value; the NA columns are left as they are.
  for (v in pool$vars) {
    mat <- pool$star[[v]]
    lost <- sum(colSums(is.na(mat)) == nrow(mat))
    if (lost == B) {
      warning(v, ": ", B, " of ", B, " subsample forests gave no partial value; it has no band.", call. = FALSE)
    } else if (lost > 0L) {
      warning(v, ": ", lost, " of ", B, " subsample forests gave no partial value; its band rests on the other ",
              B - lost, ".", call. = FALSE)
    }
  }
  invisible(pool)
}

# One variable's band: the full forest's partial and the B subsample forests' at the
# same values, for cache_fit() to save under the variable's own name.
.band_partial <- function(pool, forest, rows, var, grid, times, seed) {
  if (!var %in% pool$vars) stop(var, " is not in the pool of variables still to compute.", call. = FALSE)
  if (is.null(pool$star)) .band_fill(pool, forest, rows, times, seed)
  list(var = var, type = grid$type, x = grid$x, time = times,
       hat = .partial_values(forest, var, grid$x, times), star = pool$star[[var]])
}

# Checks the band choices before anything is grown, and the table the report prints.
.band_plan <- function(forest, B, subratio, style, at, sel, pd) { # nolint: object_name_linter. B is the subsample() argument's name.
  if (!is.character(style) || length(style) != 1L || !style %in% c("ribbon", "bars")) {
    stop("BAND_STYLE must be \"ribbon\" or \"bars\".", call. = FALSE)
  }
  if (!is.null(at)) {
    if (!is.list(at) || is.null(names(at)) || !all(vapply(at, is.numeric, logical(1)))) {
      stop("BAND_AT must be NULL or a named list of numbers, e.g. list(age = c(50, 60, 70)).", call. = FALSE)
    }
    unknown <- setdiff(names(at), sel)
    if (length(unknown)) stop("BAND_AT names predictor(s) with no partial plot: ", toString(unknown), call. = FALSE)
    cat_vars <- names(at)[vapply(names(at), function(v) .band_grid(pd, v)$type == "categorical", logical(1))]
    if (length(cat_vars)) {
      stop("BAND_AT names categorical predictor(s), which get a bar at every level: ", toString(cat_vars),
           call. = FALSE)
    }
    if (identical(style, "ribbon")) message("BAND_AT is ignored under BAND_STYLE = \"ribbon\".")
  }
  n <- forest$n
  subratio <- .band_subratio(n, subratio)
  b <- .band_size(n, subratio)
  strata <- .band_strata(forest)
  rare <- if (is.null(strata)) NA_integer_ else if (identical(forest$family, "surv")) sum(strata == "TRUE") else
    min(table(strata))
  per <- if (is.na(rare)) NA_integer_ else as.integer(round(subratio * rare))
  what <- if (identical(forest$family, "surv")) "events" else "of the smallest class"
  if (!is.na(per) && per < 100L) {
    need <- .band_floor_need(rare)
    msg <- paste0("Each subsample holds about ", per, " ", what, ", under the 100 the bands need. ",
                  if (need <= 0.5) sprintf("SUBRATIO <- %.2f would give 100.", ceiling(need * 100) / 100) else
                    "The cohort is too small to reach 100 at SUBRATIO <= 0.5; read the bands as rough.")
    if (.strict_render()) {
      stop(msg, "\nThis render stops because HVTI_TEMPLATE_STRICT is '", Sys.getenv("HVTI_TEMPLATE_STRICT"),
           "'. Unset it, or set it to 0, false or no, to render a draft instead.", call. = FALSE)
    }
    warning(msg, call. = FALSE)
    .run_mark_draft(paste0("the confidence bands rest on subsamples of about ", per, " ", what))
  }
  table <- data.frame(
    item = c("Subsample forests", "Patients in each", "Fraction of the cohort",
             if (!is.na(per)) paste("Expected", what, "in each")),
    value = c(B, b, sprintf("%.3f", subratio), if (!is.na(per)) per)
  )
  list(subratio = subratio, table = table)
}

# Each predictor's importance with its 95% subsampling interval, ranked as the
# importance figure ranks them, an interval above zero in one color and one that is
# not in another.
.plot_vimp_intervals <- function(ci) {
  d <- data.frame(vars = rownames(ci), vimp = ci$mean, lower = ci$lower, upper = ci$upper)
  d$vars <- factor(d$vars, levels = d$vars[order(d$vimp)])
  d$clear <- factor(ifelse(d$lower > 0, "Interval above zero", "Interval not above zero"),
                    levels = c("Interval above zero", "Interval not above zero"))
  sym <- rlang::sym
  ggplot2::ggplot(d, ggplot2::aes(x = !!sym("vimp"), y = !!sym("vars"), color = !!sym("clear"))) +
    ggplot2::geom_vline(xintercept = 0, linetype = "dashed", color = "gray50") +
    ggplot2::geom_errorbar(ggplot2::aes(xmin = !!sym("lower"), xmax = !!sym("upper")), width = 0.3,
                           orientation = "y") +
    ggplot2::geom_point(size = 2) +
    ggplot2::scale_color_manual(values = c(`Interval above zero` = "black", `Interval not above zero` = "gray55"),
                                drop = FALSE, name = NULL) +
    ggplot2::labs(x = "Permutation importance", y = NULL)
}

# A band as plotting rows: the full forest's value and its pointwise interval, at the
# grid or, for a continuous predictor, at the values in `at`.
.band_frame <- function(band, subratio, at = NULL, alpha = 0.05) {
  nx <- length(band$x)
  nt <- max(1L, length(band$time))
  hat <- matrix(band$hat, nx, nt)
  star <- band$star
  x <- band$x
  if (!is.null(at) && identical(band$type, "continuous")) {
    parts <- lapply(seq_len(nt), function(t) {
      rows <- (t - 1L) * nx + seq_len(nx)
      .band_at(band$x, hat[, t], star[rows, , drop = FALSE], at)
    })
    hat <- do.call(cbind, lapply(parts, `[[`, "hat"))
    star <- do.call(rbind, lapply(parts, `[[`, "star"))
    x <- at
    nx <- length(at)
  }
  se <- .band_se(as.numeric(hat), star, subratio)
  z <- stats::qnorm(1 - alpha / 2)
  data.frame(x = rep(x, times = nt), time = if (length(band$time)) rep(band$time, each = nx) else NA_real_,
             hat = as.numeric(hat), lower = as.numeric(hat) - z * se, upper = as.numeric(hat) + z * se)
}

# One panel per predictor: the full forest's partial with a ribbon, or error bars, for
# a continuous predictor, and a point with error bars at each level of a categorical
# one. A survival forest's horizons share a color in line, band and bar.
.plot_partial_bands <- function(bands, subratio, style, at, ncol) {
  sym <- rlang::sym
  panels <- lapply(bands, function(band) {
    fr <- .band_frame(band, subratio, at = if (identical(style, "bars")) at[[band$var]])
    line <- .band_frame(band, subratio)
    timed <- !all(is.na(fr$time))
    fr$time <- factor(fr$time)
    line$time <- factor(line$time)
    colour <- if (timed) ggplot2::aes(color = !!sym("time"), fill = !!sym("time"), group = !!sym("time"))
    dodge <- ggplot2::position_dodge(width = if (identical(band$type, "continuous")) diff(range(line$x)) / 40 else 0.4)
    p <- ggplot2::ggplot(fr, ggplot2::aes(x = !!sym("x"), y = !!sym("hat"))) + colour
    if (identical(band$type, "categorical")) {
      p <- p + ggplot2::geom_errorbar(ggplot2::aes(ymin = !!sym("lower"), ymax = !!sym("upper")), width = 0.2,
                                      position = dodge) +
        ggplot2::geom_point(size = 2, position = dodge)
    } else if (identical(style, "ribbon")) {
      p <- p + ggplot2::geom_ribbon(ggplot2::aes(ymin = !!sym("lower"), ymax = !!sym("upper")), alpha = 0.2,
                                    color = NA) +
        ggplot2::geom_line()
    } else {
      p <- p + ggplot2::geom_line(data = line) +
        ggplot2::geom_errorbar(ggplot2::aes(ymin = !!sym("lower"), ymax = !!sym("upper")),
                               width = diff(range(line$x)) / 30, position = dodge)
    }
    if (timed) {
      cols <- .group_colors(levels(fr$time))
      p <- p + ggplot2::scale_color_manual(values = cols, name = "Time") +
        ggplot2::scale_fill_manual(values = cols, name = "Time")
    }
    p + ggplot2::labs(x = band$var, y = NULL)
  })
  patchwork::wrap_plots(panels, ncol = ncol, guides = "collect")
}
