# The start/stop response of the hazard chain: SAS `lcensor <start>; time <stop>;
# event <e>;`, Surv(start, stop, event) in R. Each row is one stretch of a
# patient's follow-up during which the covariates hold their values, and it
# contributes H(stop) - H(start). The danger it carries is a SILENT wrong answer:
# a fit given the stop time without the start treats every row as followed
# from time zero, converges, and reports a different model. Every check here
# turns one way of losing the start into a stop.

# hz's settings, before the read. A KEY without the start keys the data on the
# patient alone, which cannot hold several segments per patient. A join
# without REDUCE stops as it does for a job with one row per patient: the
# segments are the rows this job models, and records joined onto them would
# multiply them.
.check_start_settings <- function(start, key, join = NULL, reduce = NULL) {
  if (is.null(start)) return(invisible(TRUE))
  if (!is.character(start) || length(start) != 1L || is.na(start) || !nzchar(start)) {
    stop("START must be one column name, or NULL for one row per patient.", call. = FALSE)
  }
  if (!tolower(start) %in% tolower(key)) {
    stop("START is \"", start, "\" but KEY (", paste(key, collapse = ", "), ") does not include it. ",
         "A start/stop dataset has one row per patient segment, so its rows are unique on the patient and ",
         "the segment's start together: set KEY <- c(ID, \"", start, "\").", call. = FALSE)
  }
  if (!is.null(join) && is.null(reduce)) {
    stop("START is set and JOIN has no REDUCE. The start/stop rows are the segments the model fits; a joined ",
         "dataset kept a row per record would multiply them. Set REDUCE, or build the joined values into the ",
         "segments in the dataset build.", call. = FALSE)
  }
  invisible(TRUE)
}

# Every segment must start before it stops, at or after time zero. A segment
# with start >= stop contributes nothing to the likelihood, or a negative
# amount, and is a split made wrongly in the dataset build.
.check_start_stop <- function(start, stop, start_name, stop_name) {
  bad_na <- sum(is.na(start))
  bad_neg <- sum(start < 0, na.rm = TRUE)
  bad_order <- sum(start >= stop, na.rm = TRUE)
  if (bad_na + bad_neg + bad_order > 0L) {
    stop(start_name, " is missing on ", bad_na, " row(s), negative on ", bad_neg, " and not before ", stop_name,
         " on ", bad_order, ". Every segment must start at or after zero and before it stops. Correct the ",
         "split in the dataset build, not in this job.", call. = FALSE)
  }
  invisible(TRUE)
}

# A downstream job's response formula against the selection it read. With a
# start in the selection the left-hand side must be Surv(start, time, event),
# naming that start first; without one, a three-argument Surv() names a start
# the fit it builds on never used.
.check_surv_start <- function(formula, start, time, event) {
  lhs <- formula[[2L]]
  args <- if (is.call(lhs)) vapply(as.list(lhs)[-1L], function(a) paste(deparse(a), collapse = ""), "") else character()
  want <- c(start, time, event)
  if (!identical(unname(args), want)) {
    stop("The response is ", paste(deparse(lhs), collapse = ""), " but the upstream fit's selection gives ",
         "Surv(", paste(want, collapse = ", "), ").",
         if (!is.null(start)) {
           paste0(" hz was fitted on start/stop rows, and a fit without \"", start, "\" treats every row as ",
                  "followed from time zero: a different model, which converges without complaint.")
         },
         " Build the response from START, TIME and EVENT as the template does.", call. = FALSE)
  }
  invisible(TRUE)
}

# TRUE when a hazard() fit has entry times: a start/stop or left-truncated
# response. An interval-censored fit carries a lower bound too, beside its upper
# one, which is how the two are told apart.
.has_entry_times <- function(fit) {
  !is.null(fit$data$time_lower) && is.null(fit$data$time_upper)
}

# A bootstrap that resamples rows of start/stop data splits patients across
# replicates: a patient's segments are drawn independently, so a replicate can
# hold a patient's later segment without the earlier one. SAS's %HAZBOOT
# resamples patients (_TVC=1 _IDVAR=). hzr_bootstrap() resamples rows until
# the patient-level bootstrap of TemporalHazard issue 667 lands.
.stop_row_bootstrap <- function(entry) {
  if (isTRUE(entry)) {
    stop("This bootstrap is on start/stop rows: several rows per patient, one per segment. ",
         "hzr_bootstrap() resamples rows, which splits each patient's segments across replicates, and the ",
         "selection frequencies it gives are not those of a patient-level bootstrap (SAS %HAZBOOT _TVC=1 ",
         "_IDVAR=). It waits on a patient-level bootstrap in TemporalHazard ",
         "(https://github.com/ehrlinger/TemporalHazard/issues/667).", call. = FALSE)
  }
  invisible(TRUE)
}

# hp and hs predict one row per patient per horizon, which a time-varying
# model does not define: a patient has a covariate row per segment. Which rule
# to use is open, ehrlinger/hvtiRtemplates#436 item 4.
.stop_start_stop_prediction <- function(start, source) {
  if (!is.null(start)) {
    stop("The fit in ", source, " is on start/stop rows (START = \"", start, "\"), with a covariate row per ",
         "patient segment. This job predicts one row per patient per horizon, which a time-varying model does ",
         "not define, and it has no rule for choosing one yet: ",
         "https://github.com/ehrlinger/hvtiRtemplates/issues/436.", call. = FALSE)
  }
  invisible(TRUE)
}
