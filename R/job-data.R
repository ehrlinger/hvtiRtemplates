# The shared data step every template calls. See the design spec at
# .superpowers/sdd/task-1-brief.md in dev/specs/

.job_identifier_names <- c("mrn", "emrn")

.resolve_job_id <- function(d, id) {
  if (!is.character(id) || length(id) != 1L || is.na(id) || !nzchar(id)) {
    stop("ID must name one column, such as \"ccfid\".", call. = FALSE)
  }
  if (id %in% names(d)) return(list(id = id, fallback = FALSE))
  if (identical(id, "ccfid")) {
    for (candidate in c("mrn", "emrn")) {
      hit <- names(d)[tolower(names(d)) == candidate]
      if (length(hit)) return(list(id = hit[[1L]], fallback = TRUE))
    }
    stop("This dataset has no ccfid, MRN or eMRN column. Name the patient identifier ",
         "in ID in edit-study-choices, for example ID <- \"randid\".",
         call. = FALSE)
  }
  stop("ID names a column this dataset does not have: ", id,
       ". Change ID in edit-study-choices.", call. = FALSE)
}

.drop_identifiers <- function(d, id) {
  drop <- names(d)[tolower(names(d)) %in% .job_identifier_names & names(d) != id]
  list(data = d[setdiff(names(d), drop)], dropped = drop)
}

.where_conditions <- function(where) {
  if (is.null(where)) return(list())
  if (is.call(where) || is.name(where)) return(list(where))
  if (is.list(where) && length(where) &&
        all(vapply(where, function(x) is.call(x) || is.name(x),
                   logical(1L)))) {
    return(unname(where))
  }
  stop("WHERE must be NULL, one condition from quote(), or a list from ",
       "rlang::exprs().", call. = FALSE)
}

.apply_where <- function(d, where, env = parent.frame()) {
  conditions <- .where_conditions(where)
  steps <- data.frame(condition = character(), removed = integer(),
                      missing = integer())
  for (cond in conditions) {
    keep <- rlang::eval_tidy(cond, data = d, env = env)
    label <- paste(deparse(cond, width.cutoff = 500L), collapse = " ")
    if (!is.logical(keep) ||
          !length(keep) %in% c(1L, nrow(d))) {
      stop("Each WHERE condition must give TRUE or FALSE for every row: ",
           label, call. = FALSE)
    }
    keep <- rep_len(keep, nrow(d))
    missing <- sum(is.na(keep))
    kept <- !is.na(keep) & keep
    steps[nrow(steps) + 1L, ] <- list(label, sum(!kept), missing)
    d <- d[kept, , drop = FALSE]
  }
  rownames(d) <- NULL
  list(data = d, steps = steps)
}

.check_job_key <- function(d, key, id) {
  if (!is.character(key) || !length(key) || anyNA(key)) {
    stop("KEY must name one or more columns, such as ID or c(ID, \"iv_echo\").",
         call. = FALSE)
  }
  absent <- setdiff(key, names(d))
  if (length(absent)) {
    stop("KEY names a column this dataset does not have: ",
         paste(absent, collapse = ", "),
         ". Change KEY in edit-study-choices.", call. = FALSE)
  }
  repeats <- sum(duplicated(d[key]))
  if (repeats) {
    stop(repeats, if (repeats == 1L) " value of KEY repeats" else
           " values of KEY repeat",
         ". Each row must be unique on KEY; for repeated measures add the ",
         "visit time or date, for example KEY <- c(ID, \"iv_echo\").",
         call. = FALSE)
  }
  list(rows = nrow(d), patients = length(unique(d[[id]])))
}
