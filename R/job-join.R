# Joining an ancillary dataset (echoes, labs) to a job's cohort. The cohort
# decides which patients are in; the ancillary dataset decides the rows, or, with
# `reduce`, one record is chosen per patient. Identifiers are compared as text,
# as everywhere in this package, and no value is ever printed: messages carry
# counts. Design: hvtiR dev/specs/2026-10-07-ancillary-datasets-design.md.

.reduce_rules <- c("first", "last", "nearest")

# One line naming a reduction, for the job's data table and for comparing a
# downstream job's REDUCE with its upstream job's.
.reduce_text <- function(reduce) {
  if (is.null(reduce)) return(NULL)
  paste0(reduce$rule, " by ", paste(reduce$by, collapse = ", "), if (identical(reduce$rule, "nearest")) paste0(" to ", reduce$to) else "")
}

# An identifier as text with surrounding spaces, leading zeros and letter case
# set aside, only to detect a format mismatch, never to join on.
.loose_id <- function(text) sub("^0+(?=.)", "", toupper(trimws(text)), perl = TRUE)

.join_orderable <- function(x) is.numeric(x) || inherits(x, c("Date", "POSIXt"))

# What kind of order a column carries: a number, a date or a date-time. Nearest
# subtracts one from the other, which means nothing across kinds.
.join_order_kind <- function(x) if (inherits(x, "Date")) "date" else if (inherits(x, "POSIXt")) "date-time" else "number"

# The checks that need no data, run with the other settings before anything is read.
.check_reduce_setting <- function(reduce) {
  if (!is.list(reduce) || is.null(names(reduce)) || any(!nzchar(names(reduce)))) {
    stop("REDUCE must be NULL or list(rule = ..., by = ...).", call. = FALSE)
  }
  extra <- setdiff(names(reduce), c("rule", "by", "to"))
  if (length(extra)) {
    stop("REDUCE takes only rule, by and to, not ", toString(extra), ".", call. = FALSE)
  }
  rule <- reduce$rule
  if (!is.character(rule) || length(rule) != 1L || !rule %in% .reduce_rules) {
    stop("REDUCE needs rule = \"first\", \"last\" or \"nearest\". Change REDUCE in edit-study-choices.", call. = FALSE)
  }
  # by may name more than one column: the later ones break a tie on the first.
  by <- reduce$by
  if (!is.character(by) || !length(by) || anyNA(by) || !all(nzchar(by)) || anyDuplicated(tolower(by))) {
    stop("REDUCE needs by = one column name, or several to break ties, such as c(\"echo_date\", \"echo_seq\").",
         call. = FALSE)
  }
  to <- reduce$to
  if (identical(rule, "nearest") && (!is.character(to) || length(to) != 1L || is.na(to) || !nzchar(to))) {
    stop("REDUCE with rule = \"nearest\" needs to = one column name.", call. = FALSE)
  }
  if (!identical(rule, "nearest") && !is.null(reduce$to)) {
    stop("REDUCE's to is used only with rule = \"nearest\".", call. = FALSE)
  }
  invisible(TRUE)
}

.check_reduce <- function(reduce, ancillary, cohort) {
  .check_reduce_setting(reduce)
  rule <- reduce$rule
  # Matched ignoring case, as every column setting is.
  by <- .match_columns(reduce$by, names(ancillary))
  to <- if (!is.null(reduce$to)) .match_columns(reduce$to, names(cohort))
  resolved <- list(by = by, to = to)
  absent <- setdiff(by, names(ancillary))
  if (length(absent)) {
    stop("REDUCE's by names a column the joined dataset does not have: ", toString(absent), ".", call. = FALSE)
  }
  for (col in by) {
    if (!.join_orderable(ancillary[[col]])) {
      stop("REDUCE's by column, ", col, ", must be a number or a date.", call. = FALSE)
    }
  }
  by <- by[[1L]]
  if (identical(rule, "nearest")) {
    if (!to %in% names(cohort) || !.join_orderable(cohort[[to]])) {
      stop("REDUCE with rule = \"nearest\" needs to = a cohort column holding a number or a date.", call. = FALSE)
    }
    if (!identical(.join_order_kind(ancillary[[by]]), .join_order_kind(cohort[[to]]))) {
      stop("REDUCE's by (", by, ", a ", .join_order_kind(ancillary[[by]]), ") and to (", to, ", a ",
           .join_order_kind(cohort[[to]]), ") must be the same kind of value for rule = \"nearest\".", call. = FALSE)
    }
  }
  invisible(resolved)
}

.join_ancillary <- function(cohort, ancillary, id, ancillary_id, join_key, join_vars = NULL, reduce = NULL,
                            filter = NULL) {
  cols <- if (is.null(join_vars)) names(cohort) else unique(c(id, .match_columns(join_vars, names(cohort))))
  absent <- setdiff(cols, names(cohort))
  if (length(absent)) {
    stop("JOIN_VARS names a column the cohort does not have: ", toString(absent),
         ". Change JOIN_VARS in edit-study-choices.", call. = FALSE)
  }
  clash <- intersect(setdiff(cols, id), setdiff(names(ancillary), ancillary_id))
  if (length(clash)) {
    stop("The cohort and the joined dataset both have: ", toString(clash),
         ". List only the cohort columns this job needs in JOIN_VARS.", call. = FALSE)
  }
  cohort_ids <- .id_text(cohort[[id]])
  # A row with no identifier names no patient, so no record can join it.
  missing <- sum(is.na(cohort_ids))
  if (missing) {
    stop(missing, if (missing == 1L) " cohort row has" else " cohort rows have", " no ", id, ". JOIN matches records ",
         "to patients by ", id, ", so every cohort row needs one: drop or fix those rows in the dataset build.",
         call. = FALSE)
  }
  # The cohort decides the patients, one row each; with more, every joined
  # record would be repeated once per cohort row.
  repeats <- length(unique(cohort_ids[duplicated(cohort_ids)]))
  if (repeats) {
    stop(repeats, if (repeats == 1L) " patient has" else " patients have", " more than one row in the cohort. ",
         "JOIN needs a cohort of one row per patient: read a dataset or analysis set that has one, and ",
         "join the repeated records as the joined dataset.", call. = FALSE)
  }
  anc_ids <- .id_text(ancillary[[ancillary_id]])
  inside <- !is.na(anc_ids) & anc_ids %in% cohort_ids[!is.na(cohort_ids)]
  outside <- sum(!inside)
  # Not one match is a mismatch of identifiers, such as text with leading
  # zeros against numbers, rather than a cohort no record belongs to.
  if (length(anc_ids) && !any(inside)) {
    stop("No record of the joined dataset belongs to a cohort patient: check that both hold the same ",
         "identifier, stored the same way.", call. = FALSE)
  }
  # Some matching is no proof the rest are other patients: records whose
  # identifier matches a cohort patient's once spaces, leading zeros and case
  # are set aside were stored another way, and would be lost as "outside".
  # Never coerced here, which would hide the build's mistake.
  loose <- .loose_id(anc_ids)
  near <- !inside & !is.na(anc_ids) & loose %in% .loose_id(cohort_ids[!is.na(cohort_ids)])
  if (any(near)) {
    n <- sum(near)
    who <- length(unique(loose[near]))
    stop(n, if (n == 1L) " record" else " records", " of the joined dataset, on ", who,
         if (who == 1L) " cohort patient," else " cohort patients,", " carry an identifier that matches the cohort's ",
         "only once surrounding spaces, leading zeros or letter case are set aside. Store the identifier the same way ",
         "in both datasets, in the dataset build, and register them again.", call. = FALSE)
  }
  ancillary <- ancillary[inside, , drop = FALSE]
  anc_ids <- anc_ids[inside]
  if (!identical(ancillary_id, id)) names(ancillary)[names(ancillary) == ancillary_id] <- id
  # The cohort's identifier, as its own type: matched as text, it may be stored another way here.
  ancillary[[id]] <- cohort[[id]][match(anc_ids, cohort_ids)]

  carried <- cohort[match(anc_ids, cohort_ids), setdiff(cols, id), drop = FALSE]
  if (is.null(reduce)) {
    out <- cbind(ancillary, carried)
    rownames(out) <- NULL
    return(list(data = out, key = replace(join_key, join_key == ancillary_id, id), outside = outside,
                without = sum(!cohort_ids %in% anc_ids), ignored = 0L, rule = NULL, steps = NULL))
  }

  columns <- .check_reduce(reduce, ancillary, cohort)
  # Records are filtered before one is chosen (maintainer's decision,
  # 2026-10-09), so "last echo where echo_type is TTE" is each patient's last
  # TTE. `filter` sees each record with the cohort columns it carries, and
  # returns which rows it keeps and the steps for the data table.
  steps <- NULL
  if (!is.null(filter)) {
    kept <- filter(cbind(ancillary, carried), setdiff(names(ancillary), id))
    ancillary <- ancillary[kept$rows, , drop = FALSE]
    anc_ids <- anc_ids[kept$rows]
    steps <- kept$steps
  }
  rule <- reduce$rule
  by <- columns$by
  # One score per by column, smallest best: the first is the order the rule
  # names (or the distance to `to`), and each later one breaks a tie on those
  # before it, in the same direction.
  scores <- lapply(by, function(col) as.numeric(ancillary[[col]]))
  if (identical(rule, "nearest")) {
    scores[[1L]] <- abs(scores[[1L]] - as.numeric(cohort[[columns$to]][match(anc_ids, cohort_ids)]))
  }
  if (identical(rule, "last")) scores <- lapply(scores, `-`)
  usable <- Reduce(`&`, lapply(scores, function(x) !is.na(x)))
  ignored <- sum(!usable)
  ancillary <- ancillary[usable, , drop = FALSE]
  anc_ids <- anc_ids[usable]
  scores <- lapply(scores, `[`, usable)

  chosen <- do.call(order, c(list(anc_ids), scores, list(method = "radix")))
  best <- chosen[!duplicated(anc_ids[chosen])]
  # A tie: another record of the patient scores the same as the chosen one.
  tuple <- do.call(paste, c(list(anc_ids), lapply(scores, sprintf, fmt = "%.17g"), sep = "\r"))
  ties <- sum(tuple[best] %in% tuple[duplicated(tuple)])
  if (ties) {
    what <- if (identical(rule, "nearest") && length(by) == 1L) {
      paste0(" equally far from ", columns$to, " (by ", by, ")")
    } else {
      paste0(" with the same ", paste(by, collapse = " and "))
    }
    stop(ties, if (ties == 1L) " patient has" else " patients have", " more than one record", what,
         ", so REDUCE cannot choose between them. Break the tie with another by column, such as by = c(\"",
         by[[1L]], "\", \"<sequence>\")", if (identical(rule, "nearest")) ", or use rule = \"first\" or \"last\"",
         ", or reduce the joined dataset when it is built.", call. = FALSE)
  }
  chosen <- best
  picked <- ancillary[chosen, setdiff(names(ancillary), id), drop = FALSE]
  m <- match(cohort_ids, anc_ids[chosen])
  out <- cbind(cohort[cols], picked[m, , drop = FALSE])
  rownames(out) <- NULL
  # The reduction as resolved, its fields in name order and its columns as the
  # data spell them, so the same choice written two ways records the same.
  resolved <- c(list(by = columns$by, rule = rule), if (identical(rule, "nearest")) list(to = columns$to))
  list(data = out, key = id, outside = outside, without = sum(is.na(m)), ignored = ignored, rule = .reduce_text(resolved),
       steps = steps, reduce = resolved)
}
