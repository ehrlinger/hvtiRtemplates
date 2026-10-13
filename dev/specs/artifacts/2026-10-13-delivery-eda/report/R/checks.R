# Check functions for the data delivery EDA report.
#
# Every check returns flags in one shape (see new_flags()). The report renders
# them; the runner reads them from flags.json to apply the notes gate. Checks
# never modify data.

#' Default thresholds. Override per request through params$thresholds.
eda_thresholds <- function(overrides = list()) {
  defaults <- list(
    miss_rate = 0.20,         # MISS-RATE: share missing above this
    miss_era_diff = 0.50,     # MISS-ERA: spread of yearly missing share
    miss_era_min_n = 20,      # MISS-ERA: rows needed for a year to count
    fence_k = 5,              # OUT-FENCE: median +/- k * scaled MAD
    jump_k = 6,               # LONG-JUMP: k * scaled MAD of consecutive changes
    shift_factor = 1.8,       # LONG-SHIFT: yearly median / overall median
    shift_min_n = 30,         # LONG-SHIFT: measurements needed for a year to count
    min_date = as.Date("1900-01-01"),
    id_cap = 50               # IDs kept per flag for the internal appendix
  )
  utils::modifyList(defaults, overrides)
}

# ---- Flag records -----------------------------------------------------------

new_flags <- function() {
  tibble::tibble(
    table = character(), variable = character(), check = character(),
    severity = character(), n = integer(), detail = character(),
    ids = list()
  )
}

flag <- function(table, variable, check, severity, n, detail, ids = character(),
                 cap = 50) {
  stopifnot(severity %in% c("error", "warning", "info"))
  tibble::tibble(
    table = table, variable = variable, check = check, severity = severity,
    n = as.integer(n), detail = detail,
    ids = list(utils::head(unique(as.character(ids)), cap))
  )
}

bind_flags <- function(...) {
  parts <- Filter(function(x) !is.null(x) && nrow(x) > 0, list(...))
  if (length(parts) == 0) return(new_flags())
  dplyr::bind_rows(parts)
}

# ---- Input normalization and guards -----------------------------------------

#' Raise a guard error the report shows verbatim.
guard_stop <- function(check, msg) {
  stop(structure(
    class = c("eda_guard_error", "error", "condition"),
    list(message = sprintf("[%s] %s", check, msg), call = NULL, check = check)
  ))
}

#' Coerce a column to Date. Accepts Date, POSIXct, or ISO-8601 text; stops on
#' anything that will not parse rather than producing silent NAs.
as_date_strict <- function(x, name) {
  if (inherits(x, "Date")) return(x)
  if (inherits(x, "POSIXt")) return(as.Date(x))
  if (is.character(x) || is.factor(x)) {
    x <- as.character(x)
    x[!is.na(x) & trimws(x) == ""] <- NA
    out <- as.Date(substr(x, 1, 10), format = "%Y-%m-%d")
    bad <- !is.na(x) & is.na(out)
    if (any(bad)) {
      guard_stop("IN-TYPE", sprintf(
        "`%s` has %d value(s) that are not ISO dates, e.g. '%s'.",
        name, sum(bad), x[which(bad)[1]]))
    }
    return(out)
  }
  guard_stop("IN-TYPE", sprintf("`%s` should be a date but is %s.", name,
                                class(x)[1]))
}

require_vars <- function(df, vars, table) {
  vars <- unique(stats::na.omit(unlist(vars)))
  missing <- setdiff(vars, names(df))
  if (length(missing) > 0) {
    guard_stop("IN-VAR", sprintf(
      "Table `%s` is missing variable(s) named in the parameters: %s.",
      table, paste0("`", missing, "`", collapse = ", ")))
  }
  invisible(TRUE)
}

require_numeric <- function(df, vars, table) {
  for (v in vars) {
    if (!is.numeric(df[[v]])) {
      guard_stop("IN-TYPE", sprintf("`%s.%s` should be numeric but is %s.",
                                    table, v, class(df[[v]])[1]))
    }
  }
  invisible(TRUE)
}

#' Guard and normalize a patient-level table. Returns the table with date
#' variables coerced.
prepare_patient_table <- function(df, spec) {
  tbl <- spec$name
  ev <- spec$events %||% list()
  require_vars(df, c(spec$id, spec$date_var,
                     vapply(ev, `[[`, "", "event"),
                     vapply(ev, `[[`, "", "interval")), tbl)
  dup <- duplicated(df[[spec$id]]) & !is.na(df[[spec$id]])
  if (any(dup)) {
    guard_stop("IN-DUPID", sprintf(
      "Patient table `%s` has %d duplicated `%s` value(s); it must be one row per patient.",
      tbl, sum(dup), spec$id))
  }
  if (!is.null(spec$date_var)) {
    df[[spec$date_var]] <- as_date_strict(df[[spec$date_var]], spec$date_var)
  }
  for (e in ev) {
    require_numeric(df, e$interval, tbl)
    vals <- unique(stats::na.omit(df[[e$event]]))
    if (!all(vals %in% c(0, 1))) {
      guard_stop("IN-EVENT", sprintf(
        "Event indicator `%s.%s` has values other than 0/1: %s.", tbl, e$event,
        paste(utils::head(setdiff(vals, c(0, 1)), 5), collapse = ", ")))
    }
    df[[e$event]] <- as.integer(df[[e$event]])
  }
  df
}

#' TRUE when a table looks wide: one row per ID and numbered sibling columns.
looks_wide <- function(df, id) {
  one_row_each <- !anyDuplicated(df[[id]][!is.na(df[[id]])])
  stems <- sub("_[0-9]+$", "", grep("_[0-9]+$", names(df), value = TRUE))
  one_row_each && any(table(stems) >= 3)
}

prepare_long_table <- function(df, spec) {
  tbl <- spec$name
  require_vars(df, c(spec$id, spec$time, spec$values), tbl)
  if (looks_wide(df, spec$id)) {
    stems <- unique(sub("_[0-9]+$", "", grep("_[0-9]+$", names(df), value = TRUE)))
    guard_stop("IN-WIDE", sprintf(
      "Longitudinal table `%s` is wide (one row per `%s`, numbered columns for %s). Reshape it to long in the runner before rendering.",
      tbl, spec$id, paste0("`", stems, "_*`", collapse = ", ")))
  }
  if (!is.numeric(df[[spec$time]])) {
    df[[spec$time]] <- as_date_strict(df[[spec$time]], spec$time)
  }
  require_numeric(df, spec$values, tbl)
  df
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# ---- Variable classification ------------------------------------------------

#' Classify analysis variables (everything not structural).
#' continuous: numeric with more than 10 distinct values
#' categorical: logical, factor, text with <= 30 levels, or numeric with <= 10
#' date: Date or POSIXct
#' text: free text with many levels (listed, not plotted)
classify_vars <- function(df, structural = character()) {
  vars <- setdiff(names(df), structural)
  kind <- vapply(vars, function(v) {
    x <- df[[v]]
    nd <- length(unique(stats::na.omit(x)))
    if (inherits(x, c("Date", "POSIXt"))) "date"
    else if (is.logical(x)) "categorical"
    else if (is.numeric(x)) if (nd > 10) "continuous" else "categorical"
    else if (nd <= 30) "categorical"
    else "text"
  }, character(1))
  tibble::tibble(variable = vars, kind = unname(kind))
}

# ---- Missingness ------------------------------------------------------------

is_missing <- function(x) {
  if (is.character(x) || is.factor(x)) is.na(x) | trimws(as.character(x)) == ""
  else is.na(x)
}

is_unknown <- function(x, codes) {
  if (length(codes) == 0 || !(is.character(x) || is.factor(x))) {
    return(rep(FALSE, length(x)))
  }
  !is.na(x) & tolower(trimws(as.character(x))) %in% tolower(codes)
}

#' Missingness summary and flags for a set of variables.
check_missing <- function(df, table, vars, id, date_var = NULL,
                          unknown_codes = character(), th = eda_thresholds()) {
  n <- nrow(df)
  summ <- tibble::tibble(
    variable = vars,
    n_missing = vapply(vars, function(v) sum(is_missing(df[[v]])), integer(1)),
    n_unknown = vapply(vars, function(v) sum(is_unknown(df[[v]], unknown_codes)), integer(1))
  )
  summ$share_missing <- if (n > 0) summ$n_missing / n else NA_real_

  flags <- list()
  for (i in seq_len(nrow(summ))) {
    v <- summ$variable[i]
    miss <- is_missing(df[[v]])
    if (n > 0 && all(miss)) {
      flags[[length(flags) + 1]] <- flag(table, v, "MISS-ALL", "error", n,
                                         "Every value is missing.", cap = th$id_cap)
      next
    }
    if (summ$share_missing[i] > th$miss_rate) {
      flags[[length(flags) + 1]] <- flag(
        table, v, "MISS-RATE", "warning", summ$n_missing[i],
        sprintf("%.0f%% missing.", 100 * summ$share_missing[i]),
        df[[id]][miss], cap = th$id_cap)
    }
    if (summ$n_unknown[i] > 0) {
      flags[[length(flags) + 1]] <- flag(
        table, v, "MISS-UNK", "info", summ$n_unknown[i],
        "Explicit unknown codes, counted apart from missing.", cap = th$id_cap)
    }
  }

  era <- NULL
  if (!is.null(date_var) && n > 0) {
    yr <- as.integer(format(df[[date_var]], "%Y"))
    era <- dplyr::bind_rows(lapply(vars, function(v) {
      tibble::tibble(variable = v, year = yr, miss = is_missing(df[[v]]))
    }))
    era <- era[!is.na(era$year), ]
    era <- dplyr::summarise(dplyr::group_by(era, variable, year),
                            n = dplyr::n(), share = mean(miss), .groups = "drop")
    for (v in vars) {
      e <- era[era$variable == v & era$n >= th$miss_era_min_n, ]
      if (nrow(e) >= 2 && (max(e$share) - min(e$share)) >= th$miss_era_diff) {
        lo <- e$year[which.min(e$share)]; hi <- e$year[which.max(e$share)]
        flags[[length(flags) + 1]] <- flag(
          table, v, "MISS-ERA", "warning", sum(is_missing(df[[v]])),
          sprintf("Missing share ranges from %.0f%% (%d) to %.0f%% (%d) by year of `%s`.",
                  100 * min(e$share), lo, 100 * max(e$share), hi, date_var),
          cap = th$id_cap)
      }
    }
  }
  list(summary = summ, by_year = era, flags = do.call(bind_flags, flags))
}

# ---- Outliers -----------------------------------------------------------------

scaled_mad <- function(x) stats::mad(x, na.rm = TRUE)  # constant 1.4826 by default

check_outliers <- function(df, table, kinds, id, ranges = list(),
                           close_date = NULL, th = eda_thresholds()) {
  flags <- list()
  bounds <- list()
  for (i in seq_len(nrow(kinds))) {
    v <- kinds$variable[i]; k <- kinds$kind[i]; x <- df[[v]]
    if (k == "date") {
      x <- as.Date(x)
      bad <- !is.na(x) & x < th$min_date
      if (!is.null(close_date)) bad <- bad | (!is.na(x) & x > close_date)
      if (any(bad)) {
        flags[[length(flags) + 1]] <- flag(
          table, v, "OUT-DATE", "error", sum(bad),
          sprintf("Dates before %s or after %s.", th$min_date,
                  if (is.null(close_date)) "the close date" else close_date),
          df[[id]][bad], cap = th$id_cap)
      }
      next
    }
    if (k != "continuous") next
    obs <- x[!is.na(x)]
    if (length(unique(obs)) == 1) {
      flags[[length(flags) + 1]] <- flag(table, v, "OUT-CONST", "info", length(obs),
                                         "Single value.", cap = th$id_cap)
      next
    }
    if (!is.null(ranges[[v]])) {
      lo <- ranges[[v]][[1]]; hi <- ranges[[v]][[2]]; chk <- "OUT-RANGE"
      why <- sprintf("Outside clinical range [%s, %s].", lo, hi)
    } else {
      m <- stats::median(obs); s <- scaled_mad(obs)
      if (!is.finite(s) || s == 0) next
      lo <- m - th$fence_k * s; hi <- m + th$fence_k * s; chk <- "OUT-FENCE"
      why <- sprintf("Beyond median +/- %g scaled MAD [%.3g, %.3g]; no clinical range given.",
                     th$fence_k, lo, hi)
    }
    bounds[[v]] <- c(lo, hi)
    bad <- !is.na(x) & (x < lo | x > hi)
    if (any(bad)) {
      flags[[length(flags) + 1]] <- flag(
        table, v, chk, "warning", sum(bad),
        sprintf("%s Values: %s.", why,
                paste(signif(utils::head(sort(unique(x[bad])), 6), 4), collapse = ", ")),
        df[[id]][bad], cap = th$id_cap)
    }
  }
  list(bounds = bounds, flags = do.call(bind_flags, flags))
}

# ---- Follow-up ------------------------------------------------------------------

unit_days <- function(unit) {
  switch(unit %||% "years", days = 1, weeks = 7, months = 30.4375, years = 365.25,
         guard_stop("IN-TYPE", sprintf("Unknown interval unit '%s'.", unit)))
}

#' Follow-up checks and goodness-of-follow-up data for every event.
check_followup <- function(df, spec, close_date, th = eda_thresholds()) {
  tbl <- spec$name; id <- spec$id; dv <- spec$date_var
  events <- spec$events %||% list()
  if (length(events) == 0 || is.null(dv)) {
    return(list(flags = new_flags(), gof = NULL, completeness = NULL))
  }
  term <- Filter(function(e) isTRUE(e$terminal), events)
  term <- if (length(term)) term[[1]] else NULL

  flags <- list(); gof <- list(); comp <- list()
  idx <- df[[dv]]
  for (e in events) {
    ev <- df[[e$event]]; iv <- df[[e$interval]]; ud <- unit_days(e$unit)
    pot <- as.numeric(close_date - idx) / ud

    miss <- is.na(ev) | is.na(iv)
    if (any(miss & !is.na(idx))) {
      flags[[length(flags) + 1]] <- flag(tbl, e$interval, "FU-MISSING", "warning",
        sum(miss & !is.na(idx)), sprintf("%s: event or interval missing.", e$label),
        df[[id]][miss], cap = th$id_cap)
    }
    neg <- !is.na(iv) & iv < 0
    if (any(neg)) {
      flags[[length(flags) + 1]] <- flag(tbl, e$interval, "FU-NEG", "error", sum(neg),
        sprintf("%s: negative interval.", e$label), df[[id]][neg], cap = th$id_cap)
    }
    # One day of tolerance for rounding of intervals stored in months or years.
    past <- !is.na(iv) & !is.na(pot) & iv > pot + 1 / ud
    if (any(past)) {
      flags[[length(flags) + 1]] <- flag(tbl, e$interval, "FU-PAST-CLOSE", "error", sum(past),
        sprintf("%s: follow-up runs past the close date %s.", e$label, close_date),
        df[[id]][past], cap = th$id_cap)
    }
    zero <- !is.na(iv) & !is.na(ev) & ev == 1 & iv == 0
    if (any(zero)) {
      flags[[length(flags) + 1]] <- flag(tbl, e$interval, "FU-ZERO-EVENT", "warning", sum(zero),
        sprintf("%s: event recorded at interval zero.", e$label), df[[id]][zero], cap = th$id_cap)
    }

    # Potential follow-up: to close date, to the event if it occurred, and for a
    # non-terminal event, to the terminal event if that occurred first.
    potential <- pot
    if (!is.null(term) && !identical(term$event, e$event)) {
      t_ev <- df[[term$event]]; t_iv <- df[[term$interval]] * unit_days(term$unit) / ud
      died <- !is.na(t_ev) & t_ev == 1 & !is.na(t_iv)
      after <- died & !is.na(iv) & iv > t_iv + 1 / ud
      if (any(after)) {
        flags[[length(flags) + 1]] <- flag(tbl, e$interval, "FU-AFTER-TERMINAL", "error",
          sum(after), sprintf("%s: follow-up continues after %s.", e$label, term$label),
          df[[id]][after], cap = th$id_cap)
      }
      potential[died] <- pmin(potential[died], t_iv[died])
    }
    had <- !is.na(ev) & ev == 1
    potential[had] <- iv[had]
    ok <- !is.na(iv) & !is.na(potential) & iv >= 0 & potential > 0
    c_index <- sum(pmin(iv[ok], potential[ok])) / sum(potential[ok])
    comp[[e$label]] <- c_index
    flags[[length(flags) + 1]] <- flag(tbl, e$interval, "FU-COMPLETENESS", "info", sum(ok),
      sprintf("%s: completeness C = %.2f (observed / potential person-time).", e$label, c_index),
      cap = th$id_cap)

    gof[[length(gof) + 1]] <- tibble::tibble(
      event_label = e$label, unit = e$unit %||% "years", index = idx,
      interval = iv, event = ev, potential = pot)
  }
  list(flags = do.call(bind_flags, flags), gof = dplyr::bind_rows(gof),
       completeness = comp)
}

# ---- Longitudinal ---------------------------------------------------------------

#' Measurement time in years from index, whether `time` is a date or an interval.
long_time_from_index <- function(long, pts, lspec, pspec) {
  idx <- pts[[pspec$date_var]][match(long[[lspec$id]], pts[[pspec$id]])]
  t <- long[[lspec$time]]
  if (inherits(t, "Date")) {
    list(years = as.numeric(t - idx) / 365.25, date = t)
  } else {
    ud <- unit_days(lspec$unit %||% "years")
    list(years = t * ud / 365.25, date = idx + t * ud)
  }
}

check_longitudinal <- function(long, pts, lspec, pspec, close_date,
                               th = eda_thresholds()) {
  tbl <- lspec$name; id <- lspec$id
  flags <- list()

  orphan <- !is.na(long[[id]]) & !(long[[id]] %in% pts[[pspec$id]])
  if (any(orphan)) {
    flags[[length(flags) + 1]] <- flag(tbl, "_table", "LONG-ORPHAN", "error", sum(orphan),
      sprintf("%d measurement(s) for %d ID(s) not in `%s`.", sum(orphan),
              length(unique(long[[id]][orphan])), pspec$name),
      long[[id]][orphan], cap = th$id_cap)
  }

  tt <- long_time_from_index(long, pts, lspec, pspec)
  long$.years <- tt$years; long$.date <- tt$date

  post <- unique(long[[id]][!is.na(long$.years) & long$.years >= 0])
  none <- setdiff(pts[[pspec$id]], post)
  if (length(none) > 0) {
    flags[[length(flags) + 1]] <- flag(tbl, "_table", "LONG-NOMEAS", "info", length(none),
      sprintf("%d of %d cohort patients (%.0f%%) have no measurement after index.",
              length(none), nrow(pts), 100 * length(none) / nrow(pts)),
      none, cap = th$id_cap)
  }

  win <- (lspec$baseline_window_days %||% 365) / 365.25
  pre <- !is.na(long$.years) & long$.years < -win
  if (any(pre)) {
    flags[[length(flags) + 1]] <- flag(tbl, lspec$time, "LONG-PREINDEX", "warning", sum(pre),
      sprintf("Measured more than %d days before index.", lspec$baseline_window_days %||% 365),
      long[[id]][pre], cap = th$id_cap)
  }
  pc <- !is.na(long$.date) & long$.date > close_date
  if (any(pc)) {
    flags[[length(flags) + 1]] <- flag(tbl, lspec$time, "LONG-POSTCLOSE", "error", sum(pc),
      sprintf("Measured after the close date %s.", close_date),
      long[[id]][pc], cap = th$id_cap)
  }

  for (v in lspec$values) {
    x <- long[[v]]
    key <- paste(long[[id]], long[[lspec$time]])
    d <- dplyr::summarise(
      dplyr::group_by(tibble::tibble(key = key, id = long[[id]], x = x)[!is.na(x), ], key),
      id = id[1], nd = length(unique(x)), .groups = "drop")
    dup <- d[d$nd > 1, ]
    if (nrow(dup) > 0) {
      flags[[length(flags) + 1]] <- flag(tbl, v, "LONG-DUP", "warning", nrow(dup),
        "Same patient and time recorded with different values.", dup$id, cap = th$id_cap)
    }

    o <- order(long[[id]], long$.years)
    s <- tibble::tibble(id = long[[id]][o], t = long$.years[o], x = x[o])
    s <- s[!is.na(s$x) & !is.na(s$t), ]
    dx <- ifelse(c(FALSE, s$id[-1] == s$id[-nrow(s)]), c(NA, diff(s$x)), NA)
    sd_dx <- scaled_mad(dx)
    if (is.finite(sd_dx) && sd_dx > 0) {
      j <- !is.na(dx) & abs(dx - stats::median(dx, na.rm = TRUE)) > th$jump_k * sd_dx
      if (any(j)) {
        flags[[length(flags) + 1]] <- flag(tbl, v, "LONG-JUMP", "warning", sum(j),
          sprintf("Consecutive within-patient change beyond %g scaled MAD (|change| > %.3g).",
                  th$jump_k, th$jump_k * sd_dx), s$id[j], cap = th$id_cap)
      }
    }

    yr <- as.integer(format(long$.date, "%Y"))
    ym <- dplyr::summarise(dplyr::group_by(tibble::tibble(yr = yr, x = x)[!is.na(x) & !is.na(yr), ], yr),
                           n = dplyr::n(), med = stats::median(x), .groups = "drop")
    ym <- ym[ym$n >= th$shift_min_n, ]
    overall <- stats::median(x, na.rm = TRUE)
    if (nrow(ym) > 0 && is.finite(overall) && overall != 0) {
      ratio <- ym$med / overall
      bad <- ratio >= th$shift_factor | ratio <= 1 / th$shift_factor
      if (any(bad)) {
        flags[[length(flags) + 1]] <- flag(tbl, v, "LONG-SHIFT", "warning",
          sum(ym$n[bad]),
          sprintf("Yearly median departs from the overall median (%.3g) by a factor of %.1f or more in %s: possible unit change.",
                  overall, th$shift_factor, paste(ym$yr[bad], collapse = ", ")),
          cap = th$id_cap)
      }
    }
  }

  per_pt <- dplyr::count(tibble::tibble(id = long[[id]][!orphan]), id)
  per_pt <- dplyr::bind_rows(per_pt, tibble::tibble(id = setdiff(pts[[pspec$id]], per_pt$id), n = 0L))
  list(flags = do.call(bind_flags, flags), data = long, per_patient = per_pt)
}

# ---- Orchestration ----------------------------------------------------------------

#' Read a delivery table. Production tables are parquet, read with arrow.
read_delivery_table <- function(path) {
  if (!requireNamespace("arrow", quietly = TRUE)) {
    stop("Reading parquet needs the arrow package.")
  }
  as.data.frame(arrow::read_parquet(path))
}

#' Run every check described by the report parameters.
run_checks <- function(params, reader = read_delivery_table) {
  th <- eda_thresholds(params$thresholds %||% list())
  ranges <- params$ranges %||% list()
  unk <- params$unknown_codes %||% character()
  specs <- params$tables
  pspecs <- Filter(function(s) identical(s$role, "patient"), specs)
  if (length(pspecs) != 1) {
    guard_stop("IN-VAR", "Exactly one table must have role: patient.")
  }
  pspec <- pspecs[[1]]

  pts <- prepare_patient_table(reader(pspec$path), pspec)

  close_date <- if (!is.null(params$close_date)) as.Date(params$close_date) else NULL
  close_estimated <- is.null(close_date)
  if (close_estimated && !is.null(pspec$date_var)) {
    ends <- pts[[pspec$date_var]]
    for (e in pspec$events %||% list()) {
      ends <- c(ends, pts[[pspec$date_var]] + pts[[e$interval]] * unit_days(e$unit))
    }
    close_date <- max(ends, na.rm = TRUE)
  }

  structural <- c(pspec$id, pspec$date_var,
                  unlist(lapply(pspec$events, function(e) c(e$event, e$interval))))
  kinds <- classify_vars(pts, structural)
  miss <- check_missing(pts, pspec$name, kinds$variable, pspec$id, pspec$date_var, unk, th)
  outl <- check_outliers(pts, pspec$name, kinds, pspec$id, ranges, close_date, th)
  fu <- check_followup(pts, pspec, close_date, th)

  longs <- list()
  lflags <- list()
  for (ls in Filter(function(s) identical(s$role, "longitudinal"), specs)) {
    if (is.null(pspec$date_var)) {
      guard_stop("IN-VAR", sprintf(
        "Longitudinal table `%s` needs `date_var` on the patient table to place measurements relative to index.",
        ls$name))
    }
    lt <- prepare_long_table(reader(ls$path), ls)
    lk <- tibble::tibble(variable = ls$values, kind = "continuous")
    lm <- check_missing(lt, ls$name, ls$values, ls$id, NULL, unk, th)
    lo <- check_outliers(lt, ls$name, lk, ls$id, ranges, close_date, th)
    lc <- check_longitudinal(lt, pts, ls, pspec, close_date, th)
    longs[[ls$name]] <- list(spec = ls, data = lc$data, per_patient = lc$per_patient,
                             missing = lm, bounds = lo$bounds)
    lflags[[ls$name]] <- bind_flags(lm$flags, lo$flags, lc$flags)
  }

  flags <- bind_flags(fu$flags, miss$flags, outl$flags, do.call(bind_flags, unname(lflags)))
  sev <- factor(flags$severity, levels = c("error", "warning", "info"))
  flags <- flags[order(sev, flags$table, flags$check, flags$variable), ]

  list(patients = pts, pspec = pspec, kinds = kinds, missing = miss,
       bounds = outl$bounds, followup = fu, longitudinal = longs, flags = flags,
       close_date = close_date, close_estimated = close_estimated, thresholds = th)
}

# ---- Notes ------------------------------------------------------------------------

#' Attach notes (table -> variable -> check -> text) to flags.
attach_notes <- function(flags, notes) {
  flags$note <- vapply(seq_len(nrow(flags)), function(i) {
    n <- notes[[flags$table[i]]][[flags$variable[i]]][[flags$check[i]]]
    if (is.null(n)) NA_character_ else as.character(n)
  }, character(1))
  flags
}

#' Flags that need a note before delivery and do not have one.
unexplained <- function(flags) {
  flags[flags$severity %in% c("error", "warning") & is.na(flags$note), ]
}

#' Write flags for the runner. The file holds record IDs, so it stays in the
#' runner's working directory and is never bundled.
write_flags_json <- function(flags, path) {
  out <- flags
  out$ids <- lapply(out$ids, function(x) I(as.character(x)))  # keep arrays when length 1
  jsonlite::write_json(out, path, auto_unbox = TRUE, pretty = TRUE, na = "null")
}
