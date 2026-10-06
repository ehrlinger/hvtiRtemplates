# Synthetic column created dynamically during cohort list processing.

#' Cut a study cohort from a master, recording who was dropped and why
#'
#' @description
#' The cohort step of a \code{bd} build job. It keeps the master rows a study
#' is made of and returns, beside them, an attrition table: one row per step,
#' with the rows each step removed and the patients left. A step is named by its
#' reason, never by its rule's text, so the table is safe to print whatever a
#' rule names.
#'
#' @param data A data frame read from the master.
#' @param exclude \code{NULL}, or a list of rules written
#'   \code{condition ~ "Reason"}, applied in order to the rows still kept. Each
#'   condition is evaluated against the data, with the rule's own environment
#'   for anything else it names, and must give \code{TRUE} or \code{FALSE} for
#'   every row. A row whose condition is missing is \strong{not} excluded, as SAS
#'   \code{if ... then delete} and an hvtiRdatabuild analysis set treat it, and
#'   the number of such rows is counted. A downstream job's \code{WHERE} drops
#'   such rows instead.
#' @param cohort \code{NULL}, or the path to a CSV cohort list, such as a REDCap
#'   export, carrying the \code{join_by} columns. Only master rows matched by a
#'   list row are kept. Dates are written YYYY-MM-DD. A list may carry
#'   \code{exclude} (1 to exclude) and \code{reason} columns; each reason becomes
#'   a step of its own. A list's reasons are printed in the report, so they
#'   must be categories (such as "Redo operation"), never free text, names or
#'   dates.
#' @param join_by The columns that match a cohort-list row to a master row. Used
#'   only with \code{cohort}.
#' @param id The patient identifier column, used to count patients.
#'
#' @details Identifiers are compared as text, so \code{100000} in the master
#'   matches \code{"100000"} in a list. No message names a data value: list rows
#'   that matched no master row are counted, never listed, and a rule that fails
#'   is named by its number and reason.
#'
#' @return A list:
#'   \itemize{
#'     \item \code{data}, the kept rows, with the master's columns;
#'     \item \code{attrition}, a data frame with one row per step and the
#'       columns \code{step}, \code{reason}, \code{rows_before},
#'       \code{removed}, \code{missing_condition}, \code{rows_after} and
#'       \code{patients_after}.
#'   }
#'
#' @examples
#' d <- data.frame(ccfid = c("S1", "S2", "S3", "S4"), age = c(17, 45, NA, 80),
#'                 redo = c(0, 0, 0, 1))
#' cut <- build_cohort(d, exclude = list(age < 18 ~ "Under 18",
#'                                       redo == 1 ~ "Redo operation"))
#' # One row per step: rows removed, rows whose condition was missing and so
#' # kept (S3, with no age), and the patients left.
#' cut$attrition
#' cut$data
#' @export
build_cohort <- function(data, exclude = NULL, cohort = NULL, join_by = NULL, id = "ccfid") {
  if (!is.data.frame(data)) stop("build_cohort(): data must be a data frame.", call. = FALSE)
  if (!is.character(id) || length(id) != 1L || !id %in% names(data)) {
    stop("build_cohort(): the ID column ", id, " is not in the data. Set ID in edit-study-choices.", call. = FALSE)
  }
  rules <- .cohort_rules(exclude)
  patients <- function(d) length(unique(d[[id]]))
  row <- function(step, reason, before, missing, d) {
    data.frame(step = step, reason = reason, rows_before = as.integer(before), removed = as.integer(before - nrow(d)),
               missing_condition = as.integer(missing), rows_after = nrow(d), patients_after = patients(d),
               stringsAsFactors = FALSE)
  }
  attrition <- list(row("master", "Rows read", nrow(data), 0L, data))
  if (!is.null(cohort)) {
    cut <- .cohort_join(data, cohort, join_by)
    attrition[[length(attrition) + 1L]] <- row("cohort", cut$reason, nrow(data), 0L, cut$data)
    data <- cut$data
    if (!nrow(data)) stop("build_cohort(): no master row matched the cohort list (", cohort, "). Check JOIN_BY.", call. = FALSE)
    rules <- c(cut$rules, rules)
  }
  for (i in seq_along(rules)) {
    rule <- rules[[i]]
    reason <- rlang::f_rhs(rule)
    hit <- .eval_cohort_rule(rule, data, i, reason)
    before <- nrow(data)
    data <- data[!(hit %in% TRUE), , drop = FALSE]
    step <- if (is.null(attr(rule, "step"))) "exclude" else attr(rule, "step")
    attrition[[length(attrition) + 1L]] <- row(step, reason, before, sum(is.na(hit)), data)
    if (!nrow(data)) stop("build_cohort(): \"", reason, "\" excluded every remaining row.", call. = FALSE)
  }
  data$.cohort_reason <- NULL
  rownames(data) <- NULL
  list(data = data, attrition = do.call(rbind, attrition))
}

# Every rule is `condition ~ "Reason"`, a single non-empty quoted reason.
.cohort_rules <- function(exclude) {
  if (is.null(exclude)) return(list())
  if (inherits(exclude, "formula")) exclude <- list(exclude)
  if (!is.list(exclude)) {
    stop("build_cohort(): EXCLUDE must be NULL or a list of rules written condition ~ \"Reason\".", call. = FALSE)
  }
  for (i in seq_along(exclude)) {
    rule <- exclude[[i]]
    ok <- inherits(rule, "formula") && length(rule) == 3L
    reason <- if (ok) rlang::f_rhs(rule) else NULL
    if (!ok || !is.character(reason) || length(reason) != 1L || is.na(reason) || !nzchar(reason)) {
      stop("build_cohort(): EXCLUDE rule ", i, " is not written condition ~ \"Reason\". Give every rule a condition ",
           "and a quoted reason.", call. = FALSE)
    }
  }
  exclude
}

# The rule's error message is withheld: it can quote a data value.
.eval_cohort_rule <- function(rule, data, i, reason) {
  label <- paste0("build_cohort(): EXCLUDE rule ", i, " (\"", reason, "\")")
  failed <- structure(list(), class = "cohort_rule_failed")
  hit <- tryCatch(rlang::eval_tidy(rlang::f_lhs(rule), data = data, env = rlang::f_env(rule)), error = function(e) failed)
  if (inherits(hit, "cohort_rule_failed")) {
    stop(label, " could not be evaluated. Run its condition in the console against the data to see why; the message ",
         "is withheld here because it can carry a data value.", call. = FALSE)
  }
  if (!is.logical(hit) || length(hit) != nrow(data)) {
    stop(label, " must give TRUE or FALSE for each of the ", nrow(data), " rows; it gave a ", class(hit)[[1L]],
         " of length ", length(hit), ".", call. = FALSE)
  }
  hit
}

# Keep the master rows a cohort list names. A list carrying exclude and reason
# columns contributes one rule per reason, applied to a helper column that
# build_cohort() drops before it returns.
.cohort_join <- function(data, cohort, join_by) {
  where <- paste0("build_cohort(): the cohort list (", cohort, ")")
  if (!is.character(cohort) || length(cohort) != 1L || !file.exists(cohort)) {
    stop(where, " does not exist. Set COHORT in edit-study-choices.", call. = FALSE)
  }
  if (!is.character(join_by) || !length(join_by)) {
    stop("build_cohort(): JOIN_BY must name the columns that match the cohort list to the master.", call. = FALSE)
  }
  absent <- setdiff(join_by, names(data))
  if (length(absent)) {
    stop("build_cohort(): JOIN_BY column(s) ", toString(absent), " are not in the master. Set JOIN_BY.", call. = FALSE)
  }
  listed <- utils::read.csv(cohort, colClasses = "character", check.names = FALSE, na.strings = "")
  names(listed) <- tolower(names(listed))
  absent <- setdiff(join_by, names(listed))
  if (length(absent)) {
    stop(where, " has no column(s) ", toString(absent), ". Set JOIN_BY, or fix the list's header. ",
         "Column names are matched in lower case.", call. = FALSE)
  }
  list_key <- .cohort_key(listed, join_by, data, where)
  if (anyNA(list_key)) {
    stop(where, " has ", sum(is.na(list_key)), " row(s) with a blank JOIN_BY value. Complete or remove them.",
         call. = FALSE)
  }
  if (any(duplicated(list_key))) {
    stop(where, " repeats ", sum(duplicated(list_key)), " JOIN_BY key(s). Each list row must name one master row.",
         call. = FALSE)
  }
  master_key <- .cohort_key(data, join_by)
  keep <- !is.na(master_key) & master_key %in% list_key
  out <- data[keep, , drop = FALSE]
  rules <- list()
  if ("exclude" %in% names(listed)) {
    if (!"reason" %in% names(listed)) {
      stop(where, " has an exclude column and no reason column. Add one, so each exclusion is counted under its ",
           "reason.", call. = FALSE)
    }
    exclude_values <- trimws(listed$exclude)
    bad_exclude <- !is.na(exclude_values) & !exclude_values %in% c("0", "1")
    if (any(bad_exclude)) {
      stop(where, " has ", sum(bad_exclude), " exclude value(s) that are not 0 or 1. Recode the exclude column to 0 and 1.",
           call. = FALSE)
    }
    flagged <- listed$exclude %in% "1"
    blank_reason <- flagged & (is.na(listed$reason) | !nzchar(trimws(listed$reason)))
    if (any(blank_reason)) {
      stop(where, " flags ", sum(blank_reason),
           " row(s) for exclusion with no reason. Give each one a reason.", call. = FALSE)
    }
    out$.cohort_reason <- ifelse(flagged, trimws(listed$reason), NA_character_)[match(master_key[keep], list_key)]
    for (r in unique(trimws(listed$reason[flagged]))) {
      rule <- rlang::new_formula(rlang::expr(!!rlang::sym(".cohort_reason") %in% !!r), r, env = baseenv())
      rules[[length(rules) + 1L]] <- structure(rule, step = "cohort list")
    }
  }
  unmatched <- sum(!list_key %in% master_key)
  reason <- if (unmatched) {
    paste0("Not in the cohort list (", unmatched, " list row(s) matched no master row)")
  } else {
    "Not in the cohort list"
  }
  list(data = out, rules = rules, reason = reason)
}

# One text key per row: dates as YYYY-MM-DD, identifiers through .id_text(), so
# 100000 and "100000" agree. A row with any missing part has an NA key. When
# `master` is given, list columns are read as the master's types require.
.cohort_key <- function(d, cols, master = NULL, where = NULL) {
  parts <- lapply(cols, function(col) {
    x <- d[[col]]
    if (!is.null(master) && inherits(master[[col]], "Date")) {
      parsed <- as.Date(x, format = "%Y-%m-%d")
      bad <- sum(!is.na(x) & is.na(parsed))
      if (bad) {
        stop(where, ": ", bad, " value(s) of ", col, " are not dates written YYYY-MM-DD, as the master's ", col,
             " is a date.", call. = FALSE)
      }
      x <- format(parsed, "%Y-%m-%d")
    } else if (inherits(x, "Date")) {
      x <- format(x, "%Y-%m-%d")
    } else {
      x <- .id_text(x)
    }
    trimws(x)
  })
  key <- do.call(paste, c(parts, sep = "\r"))
  key[Reduce(`|`, lapply(parts, is.na))] <- NA_character_
  key
}
