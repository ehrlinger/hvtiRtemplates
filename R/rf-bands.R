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

# The VIMP of every subsample forest, read off a subsample() object: one row per predictor, one
# column per subsample, in the column the importance figure plots (a classification forest's
# "all", otherwise the only one). Only this matrix is cached. The object is large because it
# carries the full forest, and the standard error needs nothing else from it.
.band_vimp_star <- function(s) {
  hat <- s$vmp[[1L]]
  col <- if ("all" %in% colnames(hat)) "all" else 1L
  star <- do.call(cbind, lapply(s$vmpS, function(v) as.numeric(v[[1L]][[col]])))
  dimnames(star) <- list(rownames(hat), NULL)
  star
}

# The SE of the importance figure's own estimate `est`, about that estimate and not about the full
# forest's VIMP inside subsample(), which is another Monte Carlo draw of the same quantity. The
# rows of `star` are matched to `est` by name.
.band_vimp_se <- function(est, star, subratio) {
  absent <- setdiff(names(est), rownames(star))
  if (length(absent)) stop("No subsample VIMP for ", toString(absent), ".", call. = FALSE)
  .band_se(est, star[names(est), , drop = FALSE], subratio)
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

# How many of `b` rows each stratum gives, in proportion to its size, by the largest remainder:
# the shares sum to exactly `b`, where rounding each share alone can miss it by a row or more.
.band_shares <- function(sizes, b) {
  exact <- b * sizes / sum(sizes)
  share <- floor(exact + 1e-9)
  extra <- b - sum(share)
  if (extra > 0L) {
    pick <- order(exact - share, decreasing = TRUE)[seq_len(extra)]
    share[pick] <- share[pick] + 1
  }
  as.integer(share)
}

# B subsamples of the forest's rows, each a fraction `subratio` of them, drawn without
# replacement within the strata. R's generator draws them, which cache_fit() seeds.
.band_rows <- function(forest, B, subratio) { # nolint: object_name_linter. B is the subsample() argument's name.
  n <- forest$n
  b <- .band_size(n, subratio)
  strata <- .band_strata(forest)
  groups <- if (!is.null(strata)) split(seq_len(n), strata)
  share <- if (!is.null(strata)) .band_shares(lengths(groups), b)
  # A class that gets no rows is missing from every subsample forest, and a partial of a
  # classification forest is the first level's probability, which then means another class's.
  if (identical(forest$family, "class") && any(lengths(groups) > 0L & share == 0L)) {
    stop("A subsample of ", b, " patients would hold none of the smallest class. Raise SUBRATIO.", call. = FALSE)
  }
  draw <- function() {
    if (is.null(strata)) return(sort(sample.int(n, b)))
    sort(unlist(lapply(seq_along(groups), function(k) groups[[k]][sample.int(length(groups[[k]]), share[k])]),
                use.names = FALSE))
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
# What the object records and rfsrc() accepts is carried: the tree settings (ntree, mtry,
# nodesize, nodedepth, nsplit, splitrule), how each tree's sample is drawn (bootstrap, samptype,
# sampsize), the case and variable weights and the missing-data handling. Settings that
# only matter for importance, proximities or performance are left out, and so is ntime, which the
# object does not record. sampsize is stored as a function of the sample size; it is rescaled
# to the same share of the subsample as the full forest took of the cohort, and never exceeds it.
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
  grown <- forest$forest
  args <- list(formula, data = d, ntree = forest$ntree, mtry = forest$mtry, nodesize = forest$nodesize,
               nsplit = forest$nsplit, splitrule = forest$splitrule, importance = "none", seed = -abs(seed))
  if (isTRUE(forest$nodedepth >= 0)) args$nodedepth <- forest$nodedepth
  # Weights are carried when the fit set them: unit weights are rfsrc()'s default.
  uneven <- function(w) length(unique(w)) > 1L
  if (uneven(forest$xvar.wt)) args$xvar.wt <- forest$xvar.wt
  if (uneven(forest$split.wt)) args$split.wt <- forest$split.wt
  if (length(grown$case.wt) == forest$n && uneven(grown$case.wt)) args$case.wt <- grown$case.wt[rows]
  if (identical(grown$bootstrap, "by.user")) {
    stop("The forest was grown with bootstrap = \"by.user\", whose samples cannot be redrawn for a subsample.",
         call. = FALSE)
  }
  if (!is.null(grown$bootstrap)) args$bootstrap <- grown$bootstrap
  if (!is.null(grown$samptype)) args$samptype <- grown$samptype
  if (!is.null(grown$sampsize)) {
    full <- if (is.function(grown$sampsize)) grown$sampsize(forest$n) else grown$sampsize
    args$sampsize <- max(1, min(length(rows), round(full * length(rows) / forest$n)))
  }
  na_action <- grown$na.action
  if (is.null(na_action)) na_action <- if (length(forest$imputed.indv)) "na.impute" else "na.omit"
  args$na.action <- na_action
  if (identical(na_action, "na.impute")) args$nimpute <- forest$nimpute
  do.call(randomForestSRC::rfsrc, args)
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
  failed <- character()
  for (b in seq_len(B)) {
    # A subsample whose refit fails leaves its column NA for every variable; the forests grown before it are kept.
    fit <- tryCatch(.band_refit(forest, rows[[b]], seed = abs(seed) + b), error = function(e) {
      failed <<- c(failed, conditionMessage(e))
      NULL
    })
    if (!is.null(fit)) {
      for (v in pool$vars) {
        # A factor level absent from this subsample, say, leaves its column NA; the SE is read from the rest.
        value <- tryCatch(.partial_values(fit, v, pool$grids[[v]]$x, times), error = function(e) NULL)
        if (length(value) == nrow(pool$star[[v]])) pool$star[[v]][, b] <- value
      }
      rm(fit)
    }
    if (is.function(pool$progress)) pool$progress(b, B)
  }
  # Warn once per variable when subsample forests gave it no value; the NA columns are left as they are.
  why <- if (length(failed)) {
    paste0(" ", length(failed), " subsample refit", if (length(failed) > 1L) "s", " failed: ", failed[1L], ".")
  }
  for (v in pool$vars) {
    mat <- pool$star[[v]]
    lost <- sum(colSums(is.na(mat)) == nrow(mat))
    if (lost == B) {
      warning(v, ": ", B, " of ", B, " subsample forests gave no partial value; it has no band.", why, call. = FALSE)
    } else if (lost > 0L) {
      warning(v, ": ", lost, " of ", B, " subsample forests gave no partial value; its band rests on the other ",
              B - lost, ".", why, call. = FALSE)
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
    if (identical(style, "ribbon")) {
      message("BAND_AT is ignored under BAND_STYLE = \"ribbon\".")
    } else {
      # Refused here, before any band is computed, rather than when the figure is drawn.
      for (v in names(at)) {
        if (anyNA(at[[v]])) stop("BAND_AT for ", v, " has a missing value.", call. = FALSE)
        x <- .band_grid(pd, v)$x
        if (any(at[[v]] < min(x) | at[[v]] > max(x))) {
          stop("BAND_AT for ", v, " asks for values outside the observed range, ", signif(min(x), 4), " to ",
               signif(max(x), 4), ".", call. = FALSE)
        }
      }
    }
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

# Each predictor's importance, the estimate the importance figure shows, with a 95% interval of
# plus and minus 1.96 subsampling jackknife SEs, ranked as that figure ranks them (largest at the
# top). Intervals above zero are drawn in one color and the rest in another.
.plot_vimp_intervals <- function(vimp, se, alpha = 0.05) {
  se <- se[names(vimp)]
  z <- stats::qnorm(1 - alpha / 2)
  d <- data.frame(vars = names(vimp), vimp = as.numeric(vimp), lower = as.numeric(vimp) - z * as.numeric(se),
                  upper = as.numeric(vimp) + z * as.numeric(se))
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
    ggplot2::labs(x = "VIMP (anti-split importance)", y = NULL)
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
    colour <- if (timed) ggplot2::aes(color = !!sym("time"), group = !!sym("time"))
    dodge <- ggplot2::position_dodge(width = if (identical(band$type, "continuous")) diff(range(line$x)) / 40 else 0.4)
    p <- ggplot2::ggplot(fr, ggplot2::aes(x = !!sym("x"), y = !!sym("hat"))) + colour
    # A layer is drawn in the legend only if it is the empty line added below, the same in every panel,
    # because patchwork's guides = "collect" merges the panels' Time keys only when they are identical.
    if (identical(band$type, "categorical")) {
      p <- p + ggplot2::geom_errorbar(ggplot2::aes(ymin = !!sym("lower"), ymax = !!sym("upper")), width = 0.2,
                                      position = dodge, show.legend = FALSE) +
        ggplot2::geom_point(size = 2, position = dodge, show.legend = FALSE)
    } else if (identical(style, "ribbon")) {
      # Only the ribbon takes the horizon as a fill, so no fill key joins the legend.
      ribbon <- if (timed) {
        ggplot2::aes(ymin = !!sym("lower"), ymax = !!sym("upper"), fill = !!sym("time"))
      } else {
        ggplot2::aes(ymin = !!sym("lower"), ymax = !!sym("upper"))
      }
      p <- p + ggplot2::geom_ribbon(ribbon, alpha = 0.2, color = NA, show.legend = FALSE) +
        ggplot2::geom_line(show.legend = FALSE)
    } else {
      p <- p + ggplot2::geom_line(data = line, show.legend = FALSE) +
        ggplot2::geom_errorbar(ggplot2::aes(ymin = !!sym("lower"), ymax = !!sym("upper")),
                               width = diff(range(line$x)) / 30, position = dodge, show.legend = FALSE)
    }
    if (timed) {
      cols <- .group_colors(levels(fr$time))
      p <- p + ggplot2::geom_line(data = fr[0, ], show.legend = TRUE) +
        ggplot2::scale_color_manual(values = cols, name = "Time", labels = function(b) format(round(as.numeric(b), 2)))
      if (identical(band$type, "continuous") && identical(style, "ribbon")) {
        p <- p + ggplot2::scale_fill_manual(values = cols, name = "Time", guide = "none")
      }
    }
    p + ggplot2::labs(x = band$var, y = NULL)
  })
  patchwork::wrap_plots(panels, ncol = ncol, guides = "collect")
}
