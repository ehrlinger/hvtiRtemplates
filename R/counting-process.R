# Counting-process rows: one row per interval of a patient's follow-up, each
# with its start, stop and event, so a predictor may change over time. The rhf
# templates fit a hazard forest on them, and randomForestRHF refuses some
# defects only after the data are loaded, naming no patient. These checks run
# first and say what to fix.

.cp_repairs <- c("clip", "drop_na")

.cp_n <- function(n, noun, plural = paste0(noun, "s")) paste(n, if (n == 1L) noun else plural)

# Where, among the rows `rows` of `d`, a message points: the first few patients when the ID is a study number, and the
# first few row positions when it falls back to an MRN, which must not reach a render error or a submit_job() log.
# An integer64 ID is written by as.character(), which reads its value; .id_text() would write it as "0".
.cp_ids <- function(d, id, rows) {
  if (tolower(id) %in% .job_identifier_names) {
    at <- which(rows)
    return(paste0(" (row", if (length(at) > 1L) "s", " ", paste(utils::head(at, 5L), collapse = ", "),
                  if (length(at) > 5L) ", ...", " of the rows ordered by patient and start)"))
  }
  x <- d[[id]][rows]
  ids <- unique(if (inherits(x, "integer64")) as.character(x) else .id_text(x))
  paste0(" (", paste(utils::head(ids, 5L), collapse = ", "), if (length(ids) > 5L) ", ...", ")")
}

# The column the checks group a patient's rows by. An ID is matched here rather than compared as it is: duplicated()
# on an integer64 ignores fromLast, and ave() and == read its bits as a double. Numbering the patients in the order of
# their ID gives the checks a plain integer, and leaves the ID in the data as it was read.
.cp_group <- ".cp_patient"

# Checks counting-process rows and, when `repair` names it, repairs a defect a
# job may repair while the dataset fix is in flight. Returns the rows ordered by
# patient and start, a table of counts, and what each repair changed. A defect
# not repaired stops, naming its kind, its count and the first few patients, or
# their row positions when the ID is an MRN.
.cp_check <- function(d, id, start, stop, event, predictors, repair = character()) {
  unknown <- setdiff(repair, .cp_repairs)
  if (length(unknown)) {
    stop("REPAIR may name only \"clip\" and \"drop_na\"; it names ", paste(unknown, collapse = ", "), ".", call. = FALSE)
  }
  d <- d[, c(id, start, stop, event, predictors), drop = FALSE]
  for (col in c(start, stop)) {
    if (!is.numeric(d[[col]])) {
      stop(col, " must be numeric; it is ", class(d[[col]])[[1L]], ", and times read as text sort as text.", call. = FALSE)
    }
  }
  incomplete <- is.na(d[[id]]) | is.na(d[[start]]) | is.na(d[[stop]]) | is.na(d[[event]])
  if (any(incomplete)) {
    stop(.cp_n(sum(incomplete), "interval has", "intervals have"), " no id, start, stop or event. ",
         "Resolve them in the dataset build; no repair can.", call. = FALSE)
  }
  if (!all(d[[event]] %in% c(0, 1))) {
    stop(event, " must be coded 0 and 1 (1 = event); found ", paste(sort(unique(d[[event]])), collapse = ", "),
         ". Code a competing event 0, so it censors.", call. = FALSE)
  }
  empty <- predictors[vapply(d[predictors], function(x) all(is.na(x)), logical(1L))]
  if (length(empty)) {
    stop("PREDICTORS names a column with no values: ", paste(empty, collapse = ", "), ". Remove it from PREDICTORS.",
         call. = FALSE)
  }
  ids <- unique(d[[id]])
  d[[.cp_group]] <- match(d[[id]], sort(ids))
  # Ties on start are settled by stop, so the outcome does not depend on the order the rows arrived in.
  d <- d[order(d[[.cp_group]], d[[start]], d[[stop]]), , drop = FALSE]
  rownames(d) <- NULL
  repaired <- character()
  same <- function(d) c(FALSE, d[[.cp_group]][-1L] == d[[.cp_group]][-nrow(d)])
  # The furthest stop among a patient's earlier rows, -Inf on their first: a row is measured against all of them,
  # not only the one before, so a short interval nested in a long one cannot hide a later one.
  prev_stop <- function(d) {
    furthest <- stats::ave(d[[stop]], d[[.cp_group]], FUN = cummax)
    ifelse(same(d), c(-Inf, furthest[-nrow(d)]), -Inf)
  }
  # An event on a row that would be removed is an outcome lost, which no repair may do.
  refuse_event_drop <- function(drop, why) {
    if (any(d[[event]][drop] == 1)) {
      stop("REPAIR \"", why, "\" would drop an interval that carries the event", .cp_ids(d, id, drop & d[[event]] == 1),
           ". Fix it in the dataset build.", call. = FALSE)
    }
  }

  overlap <- same(d) & d[[start]] < prev_stop(d)
  if (any(overlap)) {
    if (!"clip" %in% repair) {
      stop(.cp_n(sum(overlap), "overlapping interval"), .cp_ids(d, id, overlap), ": an interval starts before the ",
           "one before it ends. Fix it in the dataset build, or set REPAIR <- \"clip\" to render a draft meanwhile.",
           call. = FALSE)
    }
    d[[start]][overlap] <- prev_stop(d)[overlap]
  }
  short <- d[[stop]] <= d[[start]]
  if (any(short)) {
    if (!"clip" %in% repair) {
      stop(.cp_n(sum(short), "interval"), " of zero or negative length", .cp_ids(d, id, short),
           ". Fix it in the dataset build, or set REPAIR <- \"clip\" to render a draft meanwhile.", call. = FALSE)
    }
    refuse_event_drop(short, "clip")
    d <- d[!short, , drop = FALSE]
  }
  if (any(overlap) || any(short)) {
    kept <- sum(overlap & !short)
    repaired[["clip"]] <- paste(c(if (kept) paste(.cp_n(kept, "overlapping interval"), "clipped"),
                                  if (any(short)) paste(.cp_n(sum(short), "interval"), "left empty and dropped")),
                                collapse = ", ")
  }

  last <- !duplicated(d[[.cp_group]], fromLast = TRUE)
  early <- d[[event]] == 1 & !last
  if (any(early)) {
    n <- length(unique(d[[.cp_group]][early]))
    stop(.cp_n(n, "patient has", "patients have"), " an event before their last interval", .cp_ids(d, id, early),
         ". An event ends follow-up; fix it in the dataset build.", call. = FALSE)
  }

  missing <- !stats::complete.cases(d[predictors])
  if (any(missing)) {
    if (!"drop_na" %in% repair) {
      stop(.cp_n(sum(missing), "interval is", "intervals are"), " missing a predictor", .cp_ids(d, id, missing),
           ". randomForestRHF cannot use them and dropping one opens a hole in the time at risk. Fill them in the ",
           "dataset build, or set REPAIR <- \"drop_na\" to render a draft meanwhile.", call. = FALSE)
    }
    refuse_event_drop(missing, "drop_na")
    d <- d[!missing, , drop = FALSE]
    repaired[["drop_na"]] <- paste(.cp_n(sum(missing), "interval"), "missing a predictor dropped")
  }

  gaps <- sum(same(d) & d[[start]] > prev_stop(d))
  per <- tabulate(d[[.cp_group]])
  per <- per[per > 0L]
  counts <- data.frame(
    measure = c("Patients", "Intervals", "Events", "Intervals per patient, median (range)", "Gaps between intervals",
                "Follow-up, from earliest start to latest stop"),
    value = c(length(per), nrow(d), sum(d[[event]] == 1),
              sprintf("%g (%d to %d)", stats::median(per), min(per), max(per)), gaps,
              paste(signif(min(d[[start]]), 4), "to", signif(max(d[[stop]]), 4))),
    stringsAsFactors = FALSE
  )
  d[[.cp_group]] <- NULL
  list(data = d, counts = counts, repaired = repaired)
}

# What a job says when it repaired its own rows. A repair belongs in the dataset
# build, so that every job in the study reads the same rows: a draft may carry
# one, marked as a draft, and a final render refuses it, as it refuses an open
# EDIT: marker.
.cp_repair_notice <- function(repaired) {
  if (!length(repaired)) return("")
  msg <- paste0("The counting-process rows were repaired in this job, not in the dataset: ",
                paste(repaired, collapse = "; "), ". Fix them in the dataset build, then set REPAIR <- character().")
  if (.strict_render()) {
    stop(msg, "\nThis render stops because HVTI_TEMPLATE_STRICT is '", Sys.getenv("HVTI_TEMPLATE_STRICT"),
         "': a final report rests on the dataset's own rows. Unset it, or set it to 0, false or no, to render a ",
         "draft instead.", call. = FALSE)
  }
  .run_mark_draft(paste0("rows repaired in the job: ", paste(repaired, collapse = "; ")))
  paste0("\n::: {.callout-important title=\"DRAFT -- rows repaired in the job\"}\n", msg, "\n:::\n\n")
}
