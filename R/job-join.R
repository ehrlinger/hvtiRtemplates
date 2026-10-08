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
  paste0(reduce$rule, " by ", reduce$by, if (identical(reduce$rule, "nearest")) paste0(" to ", reduce$to) else "")
}

.join_orderable <- function(x) is.numeric(x) || inherits(x, c("Date", "POSIXt"))

# What kind of order a column carries: a number, a date or a date-time. Nearest
# subtracts one from the other, which means nothing across kinds.
.join_order_kind <- function(x) if (inherits(x, "Date")) "date" else if (inherits(x, "POSIXt")) "date-time" else "number"

.check_reduce <- function(reduce, ancillary, cohort) {
  extra <- setdiff(names(reduce), c("rule", "by", "to"))
  if (length(extra) || is.null(names(reduce)) || any(!nzchar(names(reduce)))) {
    stop("REDUCE takes only rule, by and to", if (length(extra)) paste0(", not ", toString(extra)), ".", call. = FALSE)
  }
  rule <- reduce$rule
  by <- reduce$by
  to <- reduce$to
  if (!is.character(rule) || length(rule) != 1L || !rule %in% .reduce_rules) {
    stop("REDUCE needs rule = \"first\", \"last\" or \"nearest\". Change REDUCE in edit-study-choices.", call. = FALSE)
  }
  if (!is.character(by) || length(by) != 1L || !by %in% names(ancillary)) {
    stop("REDUCE's by names a column the joined dataset does not have: ", toString(by), ".", call. = FALSE)
  }
  if (!.join_orderable(ancillary[[by]])) {
    stop("REDUCE's by column, ", by, ", must be a number or a date.", call. = FALSE)
  }
  if (identical(rule, "nearest")) {
    if (!is.character(to) || length(to) != 1L || !to %in% names(cohort) || !.join_orderable(cohort[[to]])) {
      stop("REDUCE with rule = \"nearest\" needs to = a cohort column holding a number or a date.", call. = FALSE)
    }
    if (!identical(.join_order_kind(ancillary[[by]]), .join_order_kind(cohort[[to]]))) {
      stop("REDUCE's by (", by, ", a ", .join_order_kind(ancillary[[by]]), ") and to (", to, ", a ",
           .join_order_kind(cohort[[to]]), ") must be the same kind of value for rule = \"nearest\".", call. = FALSE)
    }
  } else if (!is.null(to)) {
    stop("REDUCE's to is used only with rule = \"nearest\".", call. = FALSE)
  }
  invisible(TRUE)
}

.join_ancillary <- function(cohort, ancillary, id, ancillary_id, join_key, join_vars = NULL, reduce = NULL) {
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
  # The cohort decides the patients, one row each; with more, every joined
  # record would be repeated once per cohort row.
  repeats <- length(unique(cohort_ids[duplicated(cohort_ids)]))
  if (repeats) {
    stop(repeats, if (repeats == 1L) " patient has" else " patients have", " more than one row in the cohort. ",
         "JOIN needs one row per patient: keep one with WHERE or ANALYSIS_SET, or set KEY to ID.", call. = FALSE)
  }
  anc_ids <- .id_text(ancillary[[ancillary_id]])
  inside <- !is.na(anc_ids) & anc_ids %in% cohort_ids[!is.na(cohort_ids)]
  outside <- sum(!inside)
  ancillary <- ancillary[inside, , drop = FALSE]
  anc_ids <- anc_ids[inside]
  if (!identical(ancillary_id, id)) names(ancillary)[names(ancillary) == ancillary_id] <- id

  if (is.null(reduce)) {
    carried <- cohort[match(anc_ids, cohort_ids), setdiff(cols, id), drop = FALSE]
    out <- cbind(ancillary, carried)
    rownames(out) <- NULL
    return(list(data = out, key = replace(join_key, join_key == ancillary_id, id), outside = outside,
                without = sum(!cohort_ids %in% anc_ids), ignored = 0L, rule = NULL))
  }

  .check_reduce(reduce, ancillary, cohort)
  rule <- reduce$rule
  by <- reduce$by
  score <- as.numeric(ancillary[[by]])
  if (identical(rule, "nearest")) score <- abs(score - as.numeric(cohort[[reduce$to]][match(anc_ids, cohort_ids)]))
  if (identical(rule, "last")) score <- -score
  usable <- !is.na(score)
  ignored <- sum(!usable)
  ancillary <- ancillary[usable, , drop = FALSE]
  anc_ids <- anc_ids[usable]
  score <- score[usable]

  if (length(score)) {
    best <- stats::ave(score, anc_ids, FUN = min)
    at_best <- stats::ave(as.numeric(score == best), anc_ids, FUN = sum)
    ties <- length(unique(anc_ids[at_best > 1]))
    if (ties) {
      stop(ties, if (ties == 1L) " patient has" else " patients have", " more than one record at the same ", by,
           ". REDUCE cannot choose between them; choose another rule, or reduce the joined dataset when it is built.",
           call. = FALSE)
    }
  }
  chosen <- order(anc_ids, score, method = "radix")
  chosen <- chosen[!duplicated(anc_ids[chosen])]
  picked <- ancillary[chosen, setdiff(names(ancillary), id), drop = FALSE]
  m <- match(cohort_ids, anc_ids[chosen])
  out <- cbind(cohort[cols], picked[m, , drop = FALSE])
  rownames(out) <- NULL
  list(data = out, key = id, outside = outside, without = sum(is.na(m)), ignored = ignored, rule = .reduce_text(reduce))
}
