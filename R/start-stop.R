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

# Kept for bh runners and reports scaffolded before patient resampling, which
# call it by name: a study's copy of a job is not updated with the package. It
# keeps their behavior, a stop on start/stop rows and nothing otherwise. New
# scaffolds use .check_segmented_fit() and .check_bag_resampling() instead.
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

# TRUE when a recorded selection holds several rows for some patient: start/stop
# segments. Stacked imputations repeat each patient too, and are not segments.
# Read from the selection rather than a fit, because a runner that drops the
# start column fits a response with no entry times on the same segmented rows.
.repeats_patients <- function(selection) {
  isTRUE(selection$rows > selection$patients) && is.null(selection$imputation)
}

# A start/stop fit needs TemporalHazard 1.2.13: before it, hzr_deciles() counted
# expected events as H(stop) and not H(stop) - H(start), so hm's calibration
# counted each segment's exposure before its start again (TemporalHazard #545).
# The fit itself was right; only the diagnostic was not, and it prints a table
# that reads as a finding.
.check_start_engine <- function(start, version = utils::packageVersion("TemporalHazard")) {
  if (!is.null(start) && version < "1.2.13") {
    stop("The hz fit is on start/stop rows (START = \"", start, "\"), and TemporalHazard ", format(version),
         " is installed. Before 1.2.13 hzr_deciles() did not subtract each segment's hazard at its start, so this ",
         "job's calibration table would count exposure before entry. Update TemporalHazard, then rerun.",
         call. = FALSE)
  }
  invisible(TRUE)
}

# A bootstrap of start/stop data resamples patients, keeping each one's segments
# together, as SAS's %HAZBOOT does with _TVC=1 _IDVAR=; resampling rows splits a
# patient's segments across replicates. The bh runner passes the patient ID to
# hzr_bootstrap(id =), which TemporalHazard 1.2.17 added.

# The runner's base fit against its rows. Segmented rows fitted without the
# start treat every segment as followed from time zero: another model, which
# converges, and which the screen would then resample by patient regardless.
.check_segmented_fit <- function(segmented, fit) {
  if (isTRUE(segmented) && !.has_entry_times(fit)) {
    stop("The runner read several rows per patient, one per start/stop segment, but its base fit has no entry ",
         "times. Fit Surv(<start>, <stop>, <event>), and keep the start among the columns of `d`.", call. = FALSE)
  }
  invisible(TRUE)
}

# The report's check on what it reads: a bag screened on segmented rows must say
# it resampled patients. A bag from a runner before patient resampling did not,
# and its frequencies are those of a row bootstrap. Each chunk file says so for
# itself. A pre-pooled bag cannot: boot_pool_chunks() keeps its first chunk's
# fields and does not compare `resampled`, so a pool of a patient chunk and a
# row chunk would read as patients. A segmented screen is therefore read from
# its chunk files only.
.check_bag_resampling <- function(segmented, bags, pooled = FALSE) {
  if (isTRUE(segmented) && isTRUE(pooled)) {
    stop("The bootstrap screened several rows per patient, one per start/stop segment, and this report found ",
         "one pooled bag rather than the runner's chunk files. A pooled bag keeps only its first chunk's record ",
         "of how it resampled, so whether every chunk resampled patients cannot be read from it. Keep the chunk ",
         "files the runner wrote, remove the pooled bag, and render this report again.", call. = FALSE)
  }
  rows <- !vapply(bags, function(b) identical(b$resampled, "patients"), logical(1L))
  if (isTRUE(segmented) && any(rows)) {
    stop("The bootstrap screened several rows per patient, one per start/stop segment, and ", sum(rows), " of ",
         length(rows), " bag file(s) resampled rows, which splits each patient's segments across replicates. ",
         "Rerun the runner as add_job() now writes it, which resamples patients (hzr_bootstrap(id =)), then ",
         "render this report again.", call. = FALSE)
  }
  invisible(TRUE)
}

# hp and hs predict one row per patient per horizon, which a time-varying
# model does not define: a patient has a covariate row per segment. The SAS jobs
# they follow have no start/stop counterpart either; they predict from a model
# fitted with one row per patient. SAS scores a time-varying model one way, each
# segment at its own start, and hs-score does that (#436). `instead` names it
# where it answers the same question.
.stop_start_stop_prediction <- function(start, source, instead = NULL) {
  if (!is.null(start)) {
    stop("The fit in ", source, " is on start/stop rows (START = \"", start, "\"), with a covariate row per ",
         "patient segment. This job predicts one row per patient per horizon, which a time-varying model does ",
         "not define, and SAS has no start/stop counterpart to follow: its prediction jobs read a model fitted ",
         "with one row per patient.", if (!is.null(instead)) paste0(" ", instead), call. = FALSE)
  }
  invisible(TRUE)
}
