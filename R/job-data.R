# The shared data step every template calls. See
# dev/specs/2026-09-29-template-data-contract-design.md for the design.

.job_identifier_names <- c("mrn", "emrn")

.resolve_job_id <- function(d, id) {
  if (!is.character(id) || length(id) != 1L || is.na(id) || !nzchar(id)) {
    stop("ID must name one column, such as \"ccfid\".", call. = FALSE)
  }
  if (id %in% names(d)) return(list(id = id, fallback = FALSE))
  same <- names(d)[tolower(names(d)) == tolower(id)]
  if (length(same)) return(list(id = same[[1L]], fallback = FALSE))
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

# hvtiRutilities::read_built() lowercases column names, so an explicit
# setting such as ID <- "MRN" names the column `mrn`.
.match_columns <- function(cols, present) {
  hit <- match(tolower(cols), tolower(present))
  ifelse(cols %in% present | is.na(hit), cols, present[hit])
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

# A WHERE condition that mentions the ID or KEY columns is shown with its
# values replaced by <value>, so no identifier, key or date value reaches a
# report or a message. The exact text stays in the selection, to rebuild rows.
# TRUE/FALSE and NULL stay visible: they are part of the condition's shape,
# not a value read from the data. Any other atomic constant, including a
# Date or POSIXct inlined with `!!`, is a value and is masked.
.is_maskable_value <- function(e) is.atomic(e) && !is.null(e) && !is.logical(e)

# Functions that turn a string into a column reference, as get("ccfid") or
# eval(as.name("ccfid")) do, or that call a function named by a string, as
# do.call("get", ...) does. A condition calling one can reach any column under
# a name all.vars() does not see, so it is masked like one that uses .data, and
# the refusal below cannot tell which column it reaches.
.string_lookups <- c("get", "get0", "mget", "eval", "evalq", "as.name", "as.symbol", "sym", "parse", "str2lang",
                     "str2expression", "do.call", "match.fun", "Recall")

# The lookup functions themselves, so a call through another name bound to one
# (alias <- get) is read as that lookup.
.lookup_alias <- function(name, env) {
  fn <- get0(name, envir = env, mode = "function")
  if (is.null(fn)) return(NULL)
  lookups <- list(get = base::get, get0 = base::get0, mget = base::mget, eval = base::eval, evalq = base::evalq,
                  as.name = base::as.name, as.symbol = base::as.symbol, sym = rlang::sym, parse = base::parse,
                  str2lang = base::str2lang, str2expression = base::str2expression, do.call = base::do.call,
                  match.fun = base::match.fun, Recall = base::Recall)
  for (lookup in names(lookups)) if (identical(fn, lookups[[lookup]])) return(lookup)
  NULL
}

.is_string_lookup <- function(e) {
  if (!is.call(e)) return(FALSE)
  head <- e[[1L]]
  if (is.call(head)) {
    # pkg::fn names a function; any other call in call position computes one at
    # run time, as match.fun("get")("ccfid") does, so it is treated as a lookup.
    if (!(length(head) == 3L && (identical(head[[1L]], as.name("::")) || identical(head[[1L]], as.name(":::"))))) {
      return(TRUE)
    }
    head <- head[[3L]]
  }
  is.name(head) && as.character(head) %in% .string_lookups
}

.uses_string_lookup <- function(e) {
  if (!is.call(e)) return(FALSE)
  if (.is_string_lookup(e)) return(TRUE)
  for (i in seq_along(e)) if (!(is.name(e[[i]]) && !nzchar(as.character(e[[i]]))) && .uses_string_lookup(e[[i]])) return(TRUE)
  FALSE
}

# A condition that uses .data can reach any column, the ID included, through
# a string such as .data[["ccfid"]], which all.vars() does not see as a column,
# so it is masked as though it named the ID. The column named inside .data[[ ]]
# stays visible: it is the condition's shape, not a value.
.mask_condition <- function(x, cols, force = FALSE) {
  text <- if (is.character(x)) x else paste(deparse(x, width.cutoff = 500L), collapse = " ")
  expr <- if (is.character(x)) tryCatch(str2lang(x), error = function(e) NULL) else x
  vars <- tolower(all.vars(expr))
  if (is.null(expr) || !(force || ".data" %in% vars || length(intersect(vars, tolower(cols))) ||
                           .uses_string_lookup(expr))) {
    return(text)
  }
  mask <- function(e) {
    if (.is_pronoun_lookup(e, ".data")) return(e)
    if (is.call(e)) {
      # Testing e[[i]] in place, never binding it: an empty argument, as in
      # x[, 1], cannot be assigned to a variable.
      for (i in seq_along(e)[-1L]) {
        if (is.call(e[[i]]) || .is_maskable_value(e[[i]])) e[[i]] <- mask(e[[i]])
      }
      return(e)
    }
    if (.is_maskable_value(e)) return(as.name("<value>"))
    e
  }
  paste(deparse(mask(expr), width.cutoff = 500L, backtick = FALSE), collapse = " ")
}

.is_pronoun_lookup <- function(e, pronoun) {
  is.call(e) && length(e) == 3L && (identical(e[[1L]], as.name("$")) || identical(e[[1L]], as.name("[["))) &&
    identical(e[[2L]], as.name(pronoun))
}

# How to name an outside value that cannot be fixed into a condition.
.outside_kind <- function(value) {
  if (is.data.frame(value)) "a data frame" else if (is.environment(value)) "an environment" else
    if (isS4(value)) "an S4 object" else if (is.list(value)) "a list" else paste("of class", class(value)[[1L]])
}

# A condition is saved as text and re-evaluated by downstream jobs in another
# environment, so a value it takes from outside the data is fixed into it here:
# .env$x, .env[["x"]] and a bare symbol that is not a column of `cols` become
# the value of x in `env`, as rlang::eval_tidy() would find it. Every symbol in
# call position is left alone, as is a symbol found nowhere, so eval_tidy()
# still names it in its error, and so is a name whose value is a function. Only
# an atomic value, NULL, a symbol or a call is fixed in; a data frame, list,
# environment or S4 object stops (see value_of below).
.resolve_outside <- function(cond, cols, env) {
  value_of <- function(name) {
    if (!is.character(name) || length(name) != 1L || !exists(name, envir = env)) return(NULL)
    value <- get(name, envir = env)
    # A function name carries no data, so it is left as the name.
    if (is.function(value)) return(NULL)
    # Only a value or a piece of a condition can be fixed in. A data frame,
    # list, environment or S4 object would be saved whole, whatever columns it
    # holds (the ID included), so it stops, named but never printed.
    if (!(is.null(value) || (is.atomic(value) && !isS4(value)) || is.name(value) || is.call(value))) {
      stop("WHERE takes `", name, "` from outside the data, and it is ", .outside_kind(value), ", not a value. ",
           "A condition is saved as text, so `", name, "` would be saved whole; filter on a column of the data ",
           "instead.", call. = FALSE)
    }
    list(value)
  }
  walk <- function(e) {
    if (is.name(e)) {
      name <- as.character(e)
      if (name %in% c(cols, ".data", ".env")) return(e)
      value <- value_of(name)
      return(if (is.null(value)) e else value[[1L]])
    }
    if (!is.call(e)) return(e)
    if (.is_pronoun_lookup(e, ".env")) {
      value <- value_of(if (is.name(e[[3L]])) as.character(e[[3L]]) else e[[3L]])
      return(if (is.null(value)) e else value[[1L]])
    }
    # The right side of $, @ and :: names a field, not a variable; a formula or
    # function has its own scope.
    head <- e[[1L]]
    if (is.name(head) && as.character(head) %in% c("$", "@", "::", ":::", "~", "function")) return(e)
    # A function bound to a lookup under another name is written as that lookup.
    lookup <- if (is.name(head)) .lookup_alias(as.character(head), env)
    if (!is.null(lookup)) e[[1L]] <- as.name(lookup)
    for (i in seq_along(e)[-1L]) {
      # Tested in place, never bound: an empty argument, as in x[, 1], cannot
      # be assigned to a variable.
      if (is.name(e[[i]]) && !nzchar(as.character(e[[i]]))) next
      # Assigned through [ ], so a NULL value is kept rather than deleting the argument.
      e[i] <- list(walk(e[[i]]))
    }
    e
  }
  walk(cond)
}

# The recorded text of a condition, which a downstream job parses to rebuild the rows. The default 15
# significant digits keep a typed 0.1 readable, but can round a value fixed in from outside the data
# (1/3, a mean), so fall back to 17 digits when the short text does not read back to the same condition.
.condition_text <- function(cond) {
  text <- paste(deparse(cond, width.cutoff = 500L), collapse = " ")
  if (identical(str2lang(text), cond)) return(text)
  paste(deparse(cond, width.cutoff = 500L, control = c("keepNA", "keepInteger", "niceNames", "showAttributes",
                                                       "digits17")), collapse = " ")
}

.mask_conditions <- function(x, cols) vapply(as.character(x), .mask_condition, "", cols = cols, USE.NAMES = FALSE)

# The columns a condition names, for the refusal below, read from the condition
# after .resolve_outside() has fixed outside values into it. Unlike the masking,
# which hides the values of any condition that uses .data, this resolves
# .data$x and .data[["x"]] to x, so a filter on an ordinary column through .data
# is allowed. A remaining bare name is a column; the field after $ or @ (as in
# .env$x) is not, nor is a string outside .data[[ ]] (as in .env[["x"]]). Any
# other use of .data, and a string lookup such as get(), reaches a column that
# cannot be known here, and is reported as `opaque`.
.where_columns <- function(expr) {
  found <- character()
  opaque <- FALSE
  walk <- function(e) {
    if (.is_pronoun_lookup(e, ".data")) {
      index <- e[[3L]]
      if (identical(e[[1L]], as.name("$")) && (is.name(index) || is.character(index))) {
        found <<- c(found, as.character(index))
      } else if (is.character(index) && length(index) == 1L) {
        found <<- c(found, index)
      } else {
        opaque <<- TRUE
        walk(index)
      }
      return(invisible())
    }
    if (is.name(e)) {
      name <- as.character(e)
      if (identical(name, ".data")) opaque <<- TRUE else found <<- c(found, name)
      return(invisible())
    }
    if (!is.call(e)) return(invisible())
    if (.is_string_lookup(e)) opaque <<- TRUE
    head <- e[[1L]]
    if (is.name(head) && as.character(head) %in% c("$", "@")) return(walk(e[[2L]]))
    if (is.call(head)) walk(head)
    # Tested in place, never bound: an empty argument cannot be assigned.
    for (i in seq_along(e)[-1L]) if (!(is.name(e[[i]]) && !nzchar(as.character(e[[i]])))) walk(e[[i]])
    invisible()
  }
  walk(expr)
  list(columns = unique(found), opaque = opaque)
}

# Every condition's exact text is saved in the job's hand-off, so a condition on
# the patient identifier would put identifier values in the job's output. Each
# condition is checked, after outside values are fixed in and before any is
# evaluated, and the message shows only the masked text. `identifiers` are the
# ID and any MRN or eMRN column. The condition carries `shown` and `what`, so an
# upstream rebuild can say where the condition lives.
#
# Names cannot see an alias or a wrapper (f <- function(x) get(x)), nor a copy
# of the ID under another name, so the values are checked too: every constant
# in the resolved condition, literal or folded from constants (.where_foldable), as text,
# against the values of the ID, MRN and eMRN columns (`id_values`, a named list
# of their unique values as text). A value computed from a data column is not
# seen. `data_cols` and `env` are the data's columns and the condition's
# environment; the environment is only consulted to refuse folding a shadowed
# function, never to call one.
.refuse_identifier_where <- function(conditions, identifiers, cols, id_values = list(), data_cols = NULL,
                                     env = emptyenv()) {
  # Every name check runs before any value is computed, across all conditions.
  for (pass in c("names", "values")) for (cond in conditions) {
    named <- .where_columns(cond)
    reached <- if (pass == "names") identifiers[tolower(identifiers) %in% tolower(named$columns)] else character()
    opaque <- pass == "names" && named$opaque
    matched <- character()
    if (pass == "values" && length(id_values)) {
      constants <- .where_constants(cond, data_cols, env)
      constants <- constants[nchar(constants) >= .min_id_value_chars]
      matched <- names(id_values)[vapply(id_values, function(v) any(constants %in% v), logical(1L))]
    }
    if (!length(reached) && !opaque && !length(matched)) next
    what <- if (length(reached)) {
      paste0("uses the patient identifier (", paste0("`", reached, "`", collapse = ", "), ")")
    } else if (opaque) {
      paste0("reaches a column through .data or a string lookup such as get(), so it may reach the patient ",
             "identifier; name the column literally, as age or .data$age")
    } else {
      paste0("holds a value that is also a patient identifier in the data (in ",
             paste0("`", matched, "`", collapse = ", "), "), so the filter would save it. A threshold that ",
             "happens to equal a patient's identifier is refused too")
    }
    shown <- .mask_condition(cond, unique(c(identifiers, cols)), force = length(matched) > 0L)
    stop(errorCondition(paste0(
      "WHERE condition `", shown, "` ", what, ". Each WHERE condition is saved, values included, in this ",
      "job's output, so a filter on identifier values would be saved with it. Exclude those patients in the ",
      "dataset build, or with an hvtiRdatabuild analysis set, and remove the condition from WHERE."
    ), class = "hvti_where_identifier", call = NULL, shown = shown, what = what))
  }
  invisible(TRUE)
}

# Real ccfid and MRN values are 6 to 10 digits, so a shorter constant (1, 18, 2015) is a threshold, not an ID.
.min_id_value_chars <- 5L

# The only functions the value check calls. Validation must never run a user's
# code (a stateful call would run twice, a refused one would run at all), so it
# folds just pure arithmetic, c(), paste and coercion of constants, from baseenv().
.where_foldable <- c("+", "-", "*", "/", "^", "%%", "%/%", "(", "c", "paste", "paste0", "as.numeric", "as.double",
                     "as.integer", "as.character")

# Every atomic constant in a condition, as .id_text() writes it: each literal,
# and the value of each maximal subexpression built only from .where_foldable
# calls over literals, so arithmetic such as 4730000000 + 1 cannot hide an
# identifier. The fold is evaluated in baseenv(); a function name shadowed in
# `env` by anything else is not folded, nor is any other call, which is left to
# the filter. Logical constants and NA are left out: neither can be an identifier.
.where_constants <- function(expr, data_cols = NULL, env = emptyenv()) {
  found <- character()
  add <- function(value) {
    if (is.atomic(value) && !is.null(value) && !is.logical(value)) found <<- c(found, .id_text(value[!is.na(value)]))
  }
  foldable <- function(e) {
    if (is.atomic(e)) return(TRUE)
    if (!is.call(e) || !is.name(e[[1L]])) return(FALSE)
    name <- as.character(e[[1L]])
    if (!name %in% .where_foldable) return(FALSE)
    bound <- get0(name, envir = env, mode = "function")
    if (!is.null(bound) && !identical(bound, get(name, envir = baseenv()))) return(FALSE)
    all(vapply(as.list(e)[-1L], foldable, logical(1L)))
  }
  walk <- function(e) {
    if (is.atomic(e)) return(add(e))
    if (!is.call(e)) return(invisible())
    if (!is.null(data_cols) && foldable(e)) {
      add(tryCatch(eval(e, baseenv()), error = function(err) NULL))
    }
    for (i in seq_along(e)) if (!(is.name(e[[i]]) && !nzchar(as.character(e[[i]])))) walk(e[[i]])
    invisible()
  }
  walk(expr)
  unique(found)
}

.apply_where <- function(d, where, env = parent.frame(), cols = character(), identifiers = character(),
                         id_values = list()) {
  # Outside values are fixed in first: one can be a symbol or a whole condition
  # that names the ID, which the refusal must see.
  conditions <- lapply(.where_conditions(where), .resolve_outside, cols = names(d), env = env)
  .refuse_identifier_where(conditions, identifiers, cols, id_values, data_cols = names(d), env = env)
  steps <- data.frame(condition = character(), shown = character(), removed = integer(),
                      missing = integer())
  for (cond in conditions) {
    label <- .condition_text(cond)
    shown <- .mask_condition(cond, cols)
    keep <- tryCatch(rlang::eval_tidy(cond, data = d, env = env), error = function(e) {
      stop("WHERE condition `", shown, "`: ", conditionMessage(e), call. = FALSE)
    })
    if (!is.logical(keep) ||
          !length(keep) %in% c(1L, nrow(d))) {
      stop("Each WHERE condition must give TRUE or FALSE for every row: ",
           shown, call. = FALSE)
    }
    keep <- rep_len(keep, nrow(d))
    missing <- sum(is.na(keep))
    kept <- !is.na(keep) & keep
    steps[nrow(steps) + 1L, ] <- list(label, shown, sum(!kept), missing)
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

# Which patients were kept, not only how many: a hash of the sorted KEY values,
# one string per row with the KEY columns joined by "\r". Sorted by radix, which
# does not depend on the locale. Only the hash is recorded, never the values.
.key_hash <- function(d, key) {
  tuples <- do.call(paste, c(unname(as.list(d[key])), sep = "\r"))
  digest::digest(sort(unique(tuples), method = "radix"), algo = "sha256")
}

# "built" is a second name for the study dataset (hvtiRutilities 1.5.1). The
# selection records "study", so an upstream job's record and a downstream
# setting agree whichever name each used.
.canonical_job_dataset <- function(dataset) {
  if (identical(dataset, "built")) "study" else dataset
}

#' Read a job's data, keep its rows, and record what was done
#'
#' @description The shared data step of every analysis template. It reads a
#'   registered dataset (or an hvtiRdatabuild analysis set), resolves the
#'   patient identifier, drops the medical record number columns, keeps the rows
#'   \code{where} selects and checks that rows are unique on \code{key}.
#'
#' @param cfg Study configuration, from \code{\link[hvtiRutilities]{study_config}}.
#' @param dataset Name of a dataset registered in \code{_study.yml};
#'   \code{"built"} and \code{"study"} both name the study dataset, and the
#'   selection records \code{"study"}.
#' @param analysis_set Name of an analysis set written by
#'   \code{hvtiRdatabuild::write_analysis_set()}, or \code{NULL} to read
#'   \code{dataset} whole. Analysis sets derive from the study dataset only.
#' @param where Rows to keep: \code{NULL}, one condition from \code{quote()}, or
#'   a list from \code{rlang::exprs()}, all of which must hold. Conditions follow
#'   \code{dplyr::filter()}: a row where a condition is \code{NA} is dropped. A
#'   value from outside the data, written \code{.env$min_age} or as a name that
#'   is not a column, is fixed into the condition when the data are read, so the
#'   recorded condition rebuilds the same rows wherever it runs. Only a plain
#'   name and \code{.env$x} are fixed in; \code{x$y} and \code{x@y} are kept as
#'   written, and a name for a function stays a name. Such a value must be a
#'   vector, \code{NULL}, a symbol or a call; a data frame, list, environment or
#'   S4 object stops, since it would be saved whole. A condition
#'   that mentions the \code{id} column or a column named \code{MRN} or
#'   \code{eMRN} (ignoring case), directly or as \code{.data$x} or
#'   \code{.data[["x"]]}, stops before any row is filtered, because each
#'   condition is saved, values included, in the job's output. Exclude those
#'   patients in the dataset build, or with an hvtiRdatabuild analysis set,
#'   instead. A value from outside the data is fixed in before this check, so
#'   \code{.data[[nm]]} is judged by the column \code{nm} names. A column
#'   reached any other way, as by \code{.data[[paste0(...)]]} or a string
#'   lookup such as \code{get()}, stops too, since it cannot be known.
#'   A function bound to such a lookup under another name is read as that
#'   lookup. Values are checked as well as names, after every name check: the
#'   check covers literal values (including a vector fixed in from outside) of
#'   five or more characters that equal a value of the identifier, \code{MRN}
#'   or \code{eMRN} columns in the data, and folds only arithmetic,
#'   \code{c()}, \code{paste}/\code{paste0} and numeric or character coercion
#'   of constants (such as \code{4730000000 + 1}) to check their result. So a
#'   wrapper function or a copy of the identifier under another name is caught
#'   when it is compared with such a value. The check never calls any other
#'   function: a value produced by any other call, or computed from a data
#'   column, as in \code{id2 / 2 != 2365000000.5}, is not checked. A threshold
#'   that happens to equal a patient's identifier is refused too, and the
#'   message says so; numbers are compared as whole numbers where they are
#'   whole, and \code{NA} never matches. Thresholds shorter than five
#'   characters, such as 1, 18 or 2015, are not checked, so a study keyed on
#'   shorter identifiers relies on the name checks.
#' @param id The patient identifier column. When it is the default
#'   \code{"ccfid"} and absent, \code{MRN} and then \code{eMRN} are used.
#' @param key Columns that make a row unique. \code{NULL} (the default) uses
#'   the key registered for \code{dataset}, and \code{id}, one row per
#'   patient, when none is registered. Add a visit time or date for repeated
#'   measures. A key that differs from the registered one is noted in the
#'   record. With \code{join}, the cohort must be one row per patient. A key
#'   of cohort columns is checked on the cohort, and the result is keyed as
#'   \code{reduce} says; a key that names a joined column, such as a visit
#'   time only the joined dataset carries, is checked on the joined rows and
#'   keys the result.
#' @param join Name of one registered ancillary dataset (such as echoes or
#'   labs) to join to the cohort on \code{id}, or \code{NULL}. The cohort,
#'   \code{dataset} or \code{analysis_set}, decides the patients: joined
#'   records of other patients are dropped and counted. A dataset registered
#'   with a \code{kind} other than \code{"ancillary"} is refused.
#' @param join_vars Cohort columns each joined row carries, the \code{id}
#'   always among them; \code{NULL} carries all of them. A column both
#'   datasets have stops, so list only the cohort columns the job needs.
#' @param reduce \code{NULL} keeps one row per joined record, keyed on the
#'   joined dataset's key. \code{list(rule = "first", by = "echo_date")}
#'   keeps one row per cohort patient, keyed on \code{id}: the record with
#'   the smallest \code{by} (\code{"first"}), the largest (\code{"last"}),
#'   or the one nearest a cohort column (\code{rule = "nearest"} with
#'   \code{to = "dt_surg"}). A patient with no record keeps the row with the
#'   joined columns missing. Records with no \code{by} value are left out and
#'   counted, and a patient whose chosen record ties with another stops the
#'   read, since picking one would be a hidden choice.
#' @param join_key Columns that make the joined dataset's rows unique,
#'   overriding its registered key. A join needs one or the other.
#' @param one_row_per_patient \code{TRUE} for a job that models one row per
#'   patient, such as a hazard, logistic or random forest fit. Such a job stops
#'   on a \code{join} without \code{reduce}, before any data are read, since
#'   the long form would count every joined record as a patient. \code{FALSE},
#'   the default, accepts the long form, as descriptive jobs and jobs that model
#'   repeated measures need.
#'
#' @details Columns named \code{MRN} or \code{eMRN} (ignoring case) are
#'   dropped unless one is the identifier, from a joined dataset too. An explicit \code{id} or \code{key}
#'   matches its column ignoring case, because
#'   \code{hvtiRutilities::read_built()} lowercases column names. Identifier,
#'   key and date values are not printed: the record holds counts, and a
#'   \code{where} condition that mentions a \code{key} column, uses
#'   \code{.data} or calls a string lookup such as \code{get()} is shown, in
#'   the record and in error messages, with its values replaced by
#'   \code{<value>}. So is a condition on \code{id} in a selection saved before
#'   such conditions were refused. Every setting is checked before the data are
#'   read, and \code{join}'s registration too; only what needs the data, such
#'   as whether a column exists, is checked after. With \code{join},
#'   \code{where} applies to the joined rows, so a condition may name a column
#'   from either dataset, though not a cohort column \code{join_vars} leaves
#'   out; the joined dataset's identifier values are refused in it as the
#'   cohort's are.
#'
#' @return A list:
#'   \itemize{
#'     \item \code{data}, the selected rows;
#'     \item \code{record}, a data frame of \code{step} and \code{value} to
#'       print, whose \code{"selection"} attribute holds the settings used. Its
#'       \code{"Source"} row names the file read, the dated version for a
#'       dataset registered as one. When the dataset's source has been rebuilt
#'       since it was registered, the registered version is read and a final
#'       \code{"Note"} row says so, naming
#'       \code{hvtiRutilities::update_manifest()}, the call that registers the
#'       new file. A stale analysis set read in a draft gets a \code{"Note"}
#'       row the same way. With \code{join}, rows name the joined dataset
#'       and the rows read from it, count its records outside the cohort and
#'       the cohort patients with none, and name the reduction;
#'     \item \code{provenance}, the read's provenance record;
#'     \item \code{provenance_join}, the joined dataset's provenance record,
#'       naming the version read, or \code{NULL} without \code{join};
#'     \item \code{attrition}, an analysis set's per-rule attrition table, or
#'       \code{NULL} for a dataset read whole.
#'   }
#'   The \code{"selection"} attribute is a list that a job saves in its
#'   hand-off, so a downstream job can rebuild the same rows:
#'   \itemize{
#'     \item \code{dataset}, with \code{"built"} recorded as \code{"study"},
#'       and \code{analysis_set}, as given;
#'     \item \code{where}, the exact text of each condition, values included,
#'       used to rebuild the rows; it stays inside the study and is never
#'       printed;
#'     \item \code{where_shown}, the same conditions as a report may show them,
#'       with the values of any condition on a \code{key} column, or using
#'       \code{.data} or a string lookup, replaced;
#'     \item \code{id} and \code{key}, the resolved column names, the
#'       key being the joined result's when there is a join;
#'     \item \code{join}, \code{join_vars}, \code{reduce} and
#'       \code{join_key}, the join as read, its key resolved, or \code{NULL},
#'       and with a join \code{cohort_key}, the cohort's own key;
#'     \item \code{rows} and \code{patients}, the counts kept;
#'     \item \code{key_hash}, a SHA-256 hash of the kept \code{key} values, so
#'       a downstream job can tell that it rebuilt the same patients and not
#'       only the same counts.
#'   }
#'
#' @examples
#' \donttest{
#' root <- file.path(tempdir(), "job-data-example")
#' dir.create(root)
#' hvtiRutilities::study_setup(root, "Example", 1L, adopt = TRUE)
#' d <- data.frame(ccfid = 1:4, age = c(15, 40, 55, 70))
#' utils::write.csv(d, file.path(hvtiRutilities::study_dir("datasets", root), "built.csv"),
#'                  row.names = FALSE)
#' hvtiRutilities::register_data(root, "built.csv")
#' cfg <- hvtiRutilities::study_config(start = root)
#' job <- read_job_data(cfg, where = quote(age >= 18))
#' job$record
#' unlink(root, recursive = TRUE)
#' }
#' @export
read_job_data <- function(cfg, dataset = "study", analysis_set = NULL, where = NULL,
                          id = "ccfid", key = NULL, join = NULL, join_vars = NULL, reduce = NULL,
                          join_key = NULL, one_row_per_patient = FALSE) {
  .check_job_settings(dataset, analysis_set, where, id, key, join, join_vars, reduce, join_key, one_row_per_patient)
  # The registration JOIN needs is checked before either dataset is read.
  join_shape <- if (!is.null(join)) .join_shape(cfg, join, join_key)
  read <- .read_job_source(cfg, dataset, analysis_set)
  d <- read$value
  # Taken now: subsetting the columns below drops attributes.
  attrition <- attr(d, "attrition", exact = TRUE)
  rows_read <- nrow(d)
  who <- .resolve_job_id(d, id)
  resolved <- .resolve_job_key(key, if (is.null(analysis_set)) .registered_shape(cfg, dataset)$key, id, "KEY",
                               "the registered key")
  key <- .match_columns(replace(resolved$key, resolved$key == id, who$id), names(d))
  ids <- .drop_identifiers(d, who$id)
  notes <- c(read$notes, resolved$note)
  # MRN and eMRN are refused even when dropped: the condition would be saved.
  identifiers <- unique(c(who$id, names(d)[tolower(names(d)) %in% .job_identifier_names], .job_identifier_names))
  # Their values too, read from `d` before MRN and eMRN are dropped.
  id_values <- if (!is.null(where)) {
    lapply(d[intersect(identifiers, names(d))], function(x) unique(.id_text(x[!is.na(x)])))
  }
  joined <- NULL
  if (!is.null(join)) {
    # A KEY wholly of cohort columns is the cohort's own, checked before the
    # join, and the joined rows are keyed as the join says. A KEY that names a
    # joined column, such as a visit time only the joined records carry, is the
    # joined rows' key and is checked on them, after WHERE, as any KEY is.
    cohort_only <- all(tolower(key) %in% tolower(names(ids$data)))
    if (cohort_only) .check_job_key(ids$data, key, who$id)
    cohort_key <- key
    joined <- .read_join(cfg, join, join_shape, ids$data, who$id, join_vars, reduce, values = !is.null(where))
    .check_where_join_vars(where, setdiff(names(ids$data), names(joined$data)))
    ids$data <- joined$data
    ids$dropped <- unique(c(ids$dropped, joined$dropped))
    key <- if (cohort_only) joined$key else .match_columns(key, names(joined$data))
    notes <- c(notes, joined$notes)
    for (col in names(joined$id_values)) id_values[[col]] <- unique(c(id_values[[col]], joined$id_values[[col]]))
  }
  kept <- .apply_where(ids$data, where, env = parent.frame(), cols = c(who$id, key), identifiers = identifiers,
                       id_values = if (is.null(id_values)) list() else id_values)
  counts <- .check_job_key(kept$data, key, who$id)
  record <- .job_record(read$source, rows_read, who, ids$dropped, kept$steps, counts, notes = unique(notes),
                        join = joined$summary)
  attr(record, "selection") <- list(
    dataset = .canonical_job_dataset(dataset), analysis_set = analysis_set, where = kept$steps$condition,
    where_shown = kept$steps$shown,
    id = who$id, key = key, rows = counts$rows, patients = counts$patients,
    key_hash = .key_hash(kept$data, key),
    join = join, join_vars = join_vars, reduce = reduce, join_key = joined$join_key,
    cohort_key = if (!is.null(join)) cohort_key
  )
  list(data = kept$data, record = record, provenance = read$record,
       provenance_join = joined$provenance, attrition = attrition)
}

# The key a dataset was registered with, and its kind. The study dataset's
# key is the top-level `key` of _study.yml; a named dataset's is on its entry.
.registered_shape <- function(cfg, dataset) {
  if (identical(.canonical_job_dataset(dataset), "study")) return(list(kind = "built", key = cfg$key))
  contract <- cfg$additional_datasets[[dataset]]
  list(kind = contract$kind, key = contract$key)
}

# A job's key overrides the registered one, and says so when they differ.
.resolve_job_key <- function(key, registered, fallback, setting, whose) {
  if (is.null(key)) return(list(key = if (is.null(registered)) fallback else registered, note = NULL))
  note <- if (!is.null(registered) && !setequal(tolower(key), tolower(registered))) {
    paste0("This job's ", setting, " (", toString(key), ") differs from ", whose, " (", toString(registered), ").")
  }
  list(key = key, note = note)
}

# Reads the dataset JOIN names and joins it to the cohort. Its identifier is
# the cohort's, by name: joining MRN to ccfid values would match nothing, or
# worse, so no fallback is taken here.
.join_shape <- function(cfg, join, join_key) {
  if (!identical(.canonical_job_dataset(join), "study") && !join %in% names(cfg$additional_datasets)) {
    named <- names(cfg$additional_datasets)
    stop("JOIN names `", join, "`, which is not registered in _study.yml",
         if (length(named)) paste0(" (registered: ", toString(named), ")"), ". Register it with ",
         "hvtiRutilities::register_data(kind = \"ancillary\", key = ...), or correct JOIN.", call. = FALSE)
  }
  shape <- .registered_shape(cfg, join)
  if (!is.null(shape$kind) && !identical(shape$kind, "ancillary")) {
    stop("JOIN names `", join, "`, registered as a ", shape$kind, " dataset. JOIN takes an ancillary dataset.",
         call. = FALSE)
  }
  resolved <- .resolve_job_key(join_key, shape$key, NULL, "JOIN_KEY", paste0("`", join, "`'s registered key"))
  if (is.null(resolved$key)) {
    stop("`", join, "` has no registered key and this job sets no JOIN_KEY. Register it with key = ... in ",
         "hvtiRutilities::register_data(), or set JOIN_KEY in this job's study choices.", call. = FALSE)
  }
  resolved
}

# JOIN_VARS leaves cohort columns out before WHERE runs on the joined rows. A
# condition naming one would otherwise take a value of that name from outside
# the data, silently, as WHERE does for any name that is not a column.
.check_where_join_vars <- function(where, left_out) {
  if (is.null(where) || !length(left_out)) return(invisible(TRUE))
  named <- unique(unlist(lapply(.where_conditions(where), function(cond) .where_columns(cond)$columns)))
  hit <- intersect(named, left_out)
  if (length(hit)) {
    stop("WHERE names ", toString(hit), ", a cohort column JOIN_VARS leaves out. Add it to JOIN_VARS.", call. = FALSE)
  }
  invisible(TRUE)
}

.read_join <- function(cfg, join, resolved, cohort, cohort_id, join_vars, reduce, values = FALSE) {
  jr <- .read_job_source(cfg, join, NULL)
  a <- jr$value
  a_id <- names(a)[tolower(names(a)) == tolower(cohort_id)]
  if (!length(a_id)) {
    stop("`", join, "` has no `", cohort_id, "` column, the identifier this job's cohort uses, so it cannot be ",
         "joined on it.", call. = FALSE)
  }
  a_id <- a_id[[1L]]
  jkey <- .match_columns(replace(resolved$key, tolower(resolved$key) == tolower(cohort_id), a_id), names(a))
  absent <- setdiff(jkey, names(a))
  if (length(absent)) {
    stop("The key for `", join, "` names a column it does not have: ", toString(absent),
         ". Change JOIN_KEY in edit-study-choices.", call. = FALSE)
  }
  repeats <- sum(duplicated(a[jkey]))
  if (repeats) {
    stop(repeats, if (repeats == 1L) " row" else " rows", " of `", join, "` repeat on its key (", toString(jkey),
         "). Set JOIN_KEY to columns that make each row unique.", call. = FALSE)
  }
  # Identifier values of the joined dataset are refused in WHERE as the cohort's are.
  id_values <- if (values) {
    held <- names(a)[tolower(names(a)) %in% c(tolower(cohort_id), .job_identifier_names)]
    stats::setNames(lapply(a[held], function(x) unique(.id_text(x[!is.na(x)]))), replace(held, held == a_id, cohort_id))
  }
  a_ids <- .drop_identifiers(a, a_id)
  j <- .join_ancillary(cohort, a_ids$data, cohort_id, a_id, jkey, join_vars, reduce)
  list(
    data = j$data, key = j$key, dropped = a_ids$dropped, notes = c(jr$notes, resolved$note),
    provenance = jr$record, join_key = replace(jkey, jkey == a_id, cohort_id), id_values = id_values,
    summary = list(source = jr$source, rows = nrow(a), outside = j$outside, without = j$without,
                   ignored = j$ignored, rule = j$rule)
  )
}

# Every setting is checked before the read, so a typo fails fast and is named.
.check_job_settings <- function(dataset, analysis_set, where, id, key, join = NULL, join_vars = NULL, reduce = NULL,
                                join_key = NULL, one_row_per_patient = FALSE) {
  if (!is.character(dataset) || length(dataset) != 1L || is.na(dataset) || !nzchar(dataset)) {
    stop("DATASET must name one dataset registered in _study.yml, such as \"built\".", call. = FALSE)
  }
  if (!is.null(analysis_set) &&
        (!is.character(analysis_set) || length(analysis_set) != 1L || is.na(analysis_set) || !nzchar(analysis_set))) {
    stop("ANALYSIS_SET must be NULL or name one analysis set, such as \"eda\".", call. = FALSE)
  }
  if (!is.null(analysis_set) && !identical(.canonical_job_dataset(dataset), "study")) {
    stop("An analysis set is written from the study dataset (\"built\"), not `", dataset,
         "`. Set ANALYSIS_SET <- NULL to read `", dataset, "` whole.", call. = FALSE)
  }
  .where_conditions(where)
  if (!is.character(id) || length(id) != 1L || is.na(id) || !nzchar(id)) {
    stop("ID must name one column, such as \"ccfid\".", call. = FALSE)
  }
  if (!is.null(key) && (!is.character(key) || !length(key) || anyNA(key) || !all(nzchar(key)))) {
    stop("KEY must be NULL or name one or more columns, such as ID or c(ID, \"iv_echo\").", call. = FALSE)
  }
  if (!is.null(join) && (!is.character(join) || length(join) != 1L || is.na(join) || !nzchar(join))) {
    stop("JOIN must be NULL or name one registered ancillary dataset, such as \"echo\".", call. = FALSE)
  }
  if (!is.null(join) && identical(.canonical_job_dataset(join), .canonical_job_dataset(dataset))) {
    stop("JOIN names the dataset this job already reads, `", dataset, "`.", call. = FALSE)
  }
  if (is.null(join) && (!is.null(join_vars) || !is.null(reduce) || !is.null(join_key))) {
    stop("JOIN_VARS, REDUCE and JOIN_KEY apply only with JOIN. Set JOIN, or set them back to NULL.", call. = FALSE)
  }
  if (!is.null(join_vars) && (!is.character(join_vars) || !length(join_vars) || anyNA(join_vars) ||
                                !all(nzchar(join_vars)))) {
    stop("JOIN_VARS must be NULL or name cohort columns.", call. = FALSE)
  }
  if (!is.null(reduce)) .check_reduce_setting(reduce)
  if (!is.null(join_key) && (!is.character(join_key) || !length(join_key) || anyNA(join_key) ||
                               !all(nzchar(join_key)))) {
    stop("JOIN_KEY must be NULL or name one or more columns.", call. = FALSE)
  }
  if (!is.logical(one_row_per_patient) || length(one_row_per_patient) != 1L || is.na(one_row_per_patient)) {
    stop("one_row_per_patient must be TRUE or FALSE.", call. = FALSE)
  }
  if (one_row_per_patient && !is.null(join) && is.null(reduce)) {
    stop("JOIN names `", join, "`, but this job models one row per patient, so a long join would count every ",
         "joined record as a patient. Set REDUCE to keep one record per patient, for example ",
         "REDUCE <- list(rule = \"last\", by = \"<date>\"), or use a template that models repeated measures, ",
         "such as dc-*, dp-* or nb-boostmtree.", call. = FALSE)
  }
  invisible(TRUE)
}

.require_databuild <- function(version = if (requireNamespace("hvtiRdatabuild", quietly = TRUE)) {
  utils::packageVersion("hvtiRdatabuild")
}) {
  if (is.null(version) || version < "0.2.1") {
    stop("ANALYSIS_SET needs hvtiRdatabuild 0.2.1 or later",
         if (!is.null(version)) paste0(" (", version, " is installed)"),
         "; install it or set ANALYSIS_SET <- NULL.", call. = FALSE)
  }
  invisible(TRUE)
}

.read_job_source <- function(cfg, dataset, analysis_set) {
  if (is.null(analysis_set)) {
    read <- .read_registered(dataset, cfg)
    read$source <- paste0("dataset `", dataset, "` (", basename(read$record$path), ")")
    return(read)
  }
  path <- file.path(hvtiRutilities::study_dir("datasets", cfg$root), paste0(analysis_set, ".parquet"))
  .check_analysis_set_built(path, analysis_set)
  .require_databuild()
  # A stale set, read in a draft, signals hvtiRutilities_out_of_date; the
  # message becomes a note in the data table, as a dataset's does.
  notes <- character()
  read <- withCallingHandlers(
    .provenance_file_read(
      paste0("analysis_set:", analysis_set), path, cfg,
      function() hvtiRdatabuild::read_analysis_set(analysis_set, cfg = cfg),
      role = paste0("analysis_set:", analysis_set)
    ),
    hvtiRutilities_out_of_date = function(m) {
      notes <<- c(notes, trimws(conditionMessage(m)))
      invokeRestart("muffleMessage")
    }
  )
  read$source <- paste0("analysis set `", analysis_set, "` of the study dataset")
  read$notes <- unique(notes)
  read
}

# Reads a registered dataset. When its source has been rebuilt but not
# registered, hvtiRutilities reads the registered version and signals a
# message of class hvtiRutilities_out_of_date. The message is kept as a note
# for the job's data table, where a reader sees it beside the file the job
# read, instead of a bare message wherever the chunk happens to print it.
# dp-postage reads outside read_job_data() and calls this too.
.read_registered <- function(dataset, cfg) {
  notes <- character()
  read <- withCallingHandlers(
    .provenance_read(dataset, cfg, function() hvtiRutilities::read_built(cfg = cfg, dataset = dataset)),
    hvtiRutilities_out_of_date = function(m) {
      notes <<- c(notes, trimws(conditionMessage(m)))
      invokeRestart("muffleMessage")
    }
  )
  read$notes <- unique(notes)
  read
}

# Checked before anything else, hvtiRdatabuild included: a new study has no
# analysis sets, and the reader's own error is a missing-file path that names
# neither the setting nor the way out (#173). dp-postage reads its analysis set
# outside read_job_data() and calls this too.
.check_analysis_set_built <- function(path, analysis_set) {
  if (!file.exists(path)) {
    stop("ANALYSIS_SET names `", analysis_set, "`, an analysis set this study has not built. ",
         "Set ANALYSIS_SET <- NULL to read the registered study dataset, or build the set with ",
         "hvtiRdatabuild::write_analysis_set() first.", call. = FALSE)
  }
  invisible(path)
}

.job_record <- function(source, rows_read, who, dropped, steps, counts, notes = character(), join = NULL) {
  rows <- list(
    c("Source", source),
    c("Rows read", format(rows_read, big.mark = ",")),
    c("ID", if (who$fallback) paste0("`", who$id, "` (no ccfid; fell back to ", who$id, ")") else paste0("`", who$id, "`")),
    c("Identifiers dropped", if (length(dropped)) paste0("`", dropped, "`", collapse = ", ") else "none")
  )
  # The join comes before WHERE, which runs on the joined rows.
  if (!is.null(join)) {
    rows[[length(rows) + 1L]] <- c("Joined", paste0(join$source, ", ", format(join$rows, big.mark = ","), " rows read"))
    rows[[length(rows) + 1L]] <- c("Joined records outside the cohort", format(join$outside, big.mark = ","))
    rows[[length(rows) + 1L]] <- c("Cohort patients with no joined record", format(join$without, big.mark = ","))
    if (!is.null(join$rule)) rows[[length(rows) + 1L]] <- c("Reduced to one row per patient", join$rule)
    if (isTRUE(join$ignored > 0L)) {
      rows[[length(rows) + 1L]] <- c("Joined records with no reduction value", format(join$ignored, big.mark = ","))
    }
  }
  for (i in seq_len(nrow(steps))) {
    rows[[length(rows) + 1L]] <- c(
      paste0("`", steps$shown[[i]], "`"),
      paste0("removed ", steps$removed[[i]], if (steps$missing[[i]]) paste0(" (", steps$missing[[i]], " missing)") else "")
    )
  }
  rows[[length(rows) + 1L]] <- c("Rows kept", paste0(format(counts$rows, big.mark = ","), " rows on ",
                                                     format(counts$patients, big.mark = ","), " patients"))
  for (note in notes) rows[[length(rows) + 1L]] <- c("Note", note)
  data.frame(step = vapply(rows, `[[`, "", 1L), value = vapply(rows, `[[`, "", 2L))
}

# A downstream job reuses its upstream job's selection. A setting the job sets
# itself must agree; one left NULL is taken from upstream. Every field the
# upstream selection carries keeps its upstream value, including the ones not
# compared here (rows, patients): a setting only fills a field upstream lacks.
.upstream_fields <- c(dataset = "DATASET", analysis_set = "ANALYSIS_SET", where = "WHERE", id = "ID",
                      key = "KEY", time = "TIME", event = "EVENT", join = "JOIN", join_vars = "JOIN_VARS",
                      reduce = "REDUCE", join_key = "JOIN_KEY")

.check_upstream_selection <- function(upstream, settings) {
  if (is.null(settings)) settings <- list()
  if (is.null(upstream)) return(settings)
  if (!is.null(settings$dataset)) settings$dataset <- .canonical_job_dataset(settings$dataset)
  if (!is.null(upstream$dataset)) upstream$dataset <- .canonical_job_dataset(upstream$dataset)
  out <- upstream
  for (field in intersect(names(.upstream_fields), names(settings))) {
    mine <- settings[[field]]
    if (is.null(mine)) next
    if (field == "reduce") {
      # Filled in as the list it is; compared as its one-line description.
      if (!field %in% names(upstream)) {
        out[[field]] <- mine
        next
      }
      mine <- .reduce_text(mine)
    } else if (is.call(mine) || is.name(mine) || is.list(mine)) {
      mine <- vapply(.where_conditions(mine), function(x) paste(deparse(x, width.cutoff = 500L), collapse = " "), "")
    }
    if (!field %in% names(upstream)) {
      out[[field]] <- mine
      next
    }
    theirs <- if (field == "reduce") .reduce_text(upstream[[field]]) else as.character(upstream[[field]])
    same <- if (field %in% c("id", "key", "join_vars", "join_key")) {
      identical(tolower(mine), tolower(theirs))
    } else {
      identical(as.character(mine), theirs)
    }
    if (!same) {
      if (field == "where") {
        cols <- unique(c(upstream$id, upstream$key, settings$id, settings$key))
        mine <- .mask_conditions(mine, cols)
        theirs <- .mask_conditions(theirs, cols)
      }
      stop(.upstream_fields[[field]], " here (", paste(mine, collapse = ", "), ") differs from the upstream job's (",
           paste(theirs, collapse = ", "), "). Leave it NULL to use the upstream value, or rerun ",
           "the upstream job with the new value.", call. = FALSE)
    }
  }
  out
}

# The data step of a downstream job: take the upstream job's selection from
# its hand-off lineage, check this job's settings against it, and (unless the
# job reads no data) rebuild exactly the upstream rows. `rerun` says what to
# run again when the hand-off carries no selection; a bootstrap report names
# its runner, which is a study script and not a template.
.read_upstream_job_data <- function(cfg, lineage, settings, read = TRUE, source = NULL,
                                    rerun = "Rerun the upstream job with the current template, then rerun this one.") {
  upstream <- lineage$selection
  if (is.null(upstream)) {
    stop("The upstream job's saved output", if (!is.null(source)) paste0(" (", source, ")"),
         " carries no single recorded data selection: it predates the data contract, or its inputs ",
         "disagreed and were combined. ", rerun, call. = FALSE)
  }
  sel <- .check_upstream_selection(upstream, settings)
  if (!read) return(list(selection = sel))
  where <- if (length(sel$where)) lapply(sel$where, str2lang)
  job_data <- withCallingHandlers(
    # With a join the recorded key is the joined result's; the cohort's own is
    # recorded beside it.
    do.call(read_job_data, list(cfg, dataset = sel$dataset, analysis_set = sel$analysis_set,
                                where = where, id = sel$id, key = if (is.null(sel$join)) sel$key else sel$cohort_key,
                                join = sel$join, join_vars = sel$join_vars, reduce = sel$reduce,
                                join_key = sel$join_key),
            quote = TRUE, envir = parent.frame()),
    # A file saved before WHERE on the identifier was refused can carry one.
    hvti_where_identifier = function(e) {
      stop("The upstream job's saved output", if (!is.null(source)) paste0(" (", source, ")"),
           " has a WHERE condition, `", e$shown, "`, that ", e$what, ", which this version refuses: each WHERE ",
           "condition is saved, values included, in a job's output. Exclude those patients in the dataset build, ",
           "or with an hvtiRdatabuild analysis set; remove it from the upstream job's WHERE, then rerun the ",
           "upstream job, and this one.", call. = FALSE)
    }
  )
  now <- attr(job_data$record, "selection")
  if (!identical(as.integer(now$rows), as.integer(upstream$rows)) ||
        !identical(as.integer(now$patients), as.integer(upstream$patients))) {
    stop("The upstream job used ", upstream$rows, " rows on ", upstream$patients, " patients; this job read ",
         now$rows, " rows on ", now$patients, " patients. This job did not rebuild the upstream cohort: ",
         "WHERE may refer to a variable rather than a value, or the data changed since the upstream job ran. ",
         "Rerun the upstream job.", call. = FALSE)
  }
  # A selection recorded before key_hash existed is checked on its counts alone.
  if (!is.null(upstream$key_hash) && !identical(now$key_hash, upstream$key_hash)) {
    stop("The patients this job read differ from the upstream job's, though the counts may match. ",
         "The data changed since the upstream job ran; rerun the upstream job.", call. = FALSE)
  }
  list(job_data = job_data, selection = sel)
}

# A downstream hazard job's cohort gate. The counts are typed once, as EXPECTED
# in the first job of the set (ac, hz), which saves them as its hand-off's
# `cohort`. A later job checks its rebuilt rows against those, so the same
# numbers are never retyped. Returns this job's counts, invisibly.
.check_upstream_cohort <- function(d, lineage, event, time, source) {
  keys <- c("n", "n_events", "n_censored")
  want <- lineage$cohort
  if (!is.list(want) || !all(keys %in% names(want))) {
    stop("The upstream job's saved output (", source, ") records no cohort counts: it predates them. ",
         "Rerun the upstream job with the current template, then rerun this one.", call. = FALSE)
  }
  # Checked before coercing: as.integer() truncates, so a saved n of 3.7 would
  # otherwise pass against a count of 3. Raised by Codex on #255.
  whole <- vapply(want[keys], function(x) {
    is.numeric(x) && length(x) == 1L && is.finite(x) && x >= 0 && x == round(x)
  }, logical(1L))
  if (!all(whole)) {
    stop("The upstream job's saved output (", source, ") records cohort counts that are not whole, ",
         "non-negative numbers (", paste(keys[!whole], collapse = ", "), "), so it is not a valid hand-off. ",
         "Rerun the upstream job with the current template, then rerun this one.", call. = FALSE)
  }
  want <- lapply(want[keys], as.integer)
  cc <- hvtiRutilities::cohort_counts(d, event = event, time = time)
  if (!identical(cc[keys], want)) {
    stop("The upstream job (", source, ") counted N=", want$n, " / events=", want$n_events, " / censored=",
         want$n_censored, "; this job counts N=", cc$n, " / events=", cc$n_events, " / censored=", cc$n_censored,
         " on the same rows. The data changed since the upstream job ran; rerun the upstream job, then this one.",
         call. = FALSE)
  }
  invisible(cc)
}

#' Stop on a bootstrap bag that carries patient-level data
#'
#' A bag holds a screen's replicates and its settings, never the rows it
#' resampled. \code{boot_bag()} builds one that way, but a hazard bag is a list
#' its runner writes by hand, and a field, or the environment of a formula or
#' a function saved in it, can hold the runner's data.
#'
#' The guard is by NAME. It stops on a list element, data frame column or
#' matrix column named for the job's ID, MRN or eMRN (ignoring case), wherever
#' it sits, and on such a binding in an environment a formula or function in
#' the bag carries. It does not see an ID stored under another name, an ID
#' used as row names, or data in an environment it does not walk: a named
#' environment (global, package, namespace), which is saved by reference, and
#' an unforced promise, which is skipped because reading it would evaluate it.
#' A binding that cannot be read, and an active binding, which is never
#' evaluated, are reported rather than passed. The carried lineage is searched
#' like any other attribute, except that the names of the selection's own
#' fields are not matched: \code{read_job_data()} writes them, and its
#' \code{id} field holds a column name, not patient values.
#'
#' @param bag The bag or chunk, as read.
#' @param id The job's resolved ID column.
#' @param source What to call the bag in the message.
#' @return \code{TRUE}, invisibly, or an error naming each place found.
#' @noRd
.check_bag_identifiers <- function(bag, id, source = "The bootstrap bag") {
  wanted <- unique(tolower(c(id, .job_identifier_names)))
  seen <- list()
  found <- character()
  walk <- function(x, at, match_names = TRUE) {
    if (is.environment(x)) {
      if (nzchar(environmentName(x)) || any(vapply(seen, identical, logical(1L), x))) return(invisible())
      seen[[length(seen) + 1L]] <<- x
      names <- ls(x, all.names = TRUE)
      # Reading either would run code: an unforced promise is skipped, and an
      # active binding, which could return anything, is reported unread.
      active <- names[rlang::env_binding_are_active(x, names)]
      for (name in active) found <<- c(found, paste0(at, ": ", name, " (an active binding, not read)"))
      lazy <- names[rlang::env_binding_are_lazy(x, names)]
      for (name in setdiff(names, c(active, lazy))) {
        here <- paste0(at, ": ", name)
        value <- tryCatch(get(name, envir = x), error = function(e) {
          found <<- c(found, paste0(here, " (unreadable: ", conditionMessage(e), ")"))
          NULL
        })
        if (tolower(name) %in% wanted && length(value)) found <<- c(found, here)
        walk(value, here)
      }
      return(walk(parent.env(x), at))
    }
    if (is.function(x) && !is.primitive(x)) walk(environment(x), paste0(at, ", a function's environment"))
    hit <- if (match_names) unique(c(names(x), colnames(x))) else colnames(x)
    hit <- hit[tolower(hit) %in% wanted]
    if (length(hit) && length(x)) found <<- c(found, paste0(at, "$", hit))
    extra <- attributes(x)
    extra <- extra[setdiff(names(extra), c("names", "row.names", "class", "dim", "dimnames"))]
    for (name in names(extra)) walk(extra[[name]], paste0(at, ", attribute ", name))
    if (is.list(x)) {
      labels <- if (is.null(names(x))) rep("", length(x)) else names(x)
      for (i in seq_along(x)) {
        here <- paste0(at, if (nzchar(labels[[i]])) paste0("$", labels[[i]]) else paste0("[[", i, "]]"))
        # The selection's fields are named by read_job_data(), and `id` holds a
        # column name; what they hold is still searched.
        walk(x[[i]], here, match_names = here != "bag, attribute hvti_provenance$selection")
      }
    }
    invisible()
  }
  walk(bag, "bag")
  if (length(found)) {
    stop(source, " holds patient-level data: ", paste(unique(found), collapse = "; "), ". A bag holds the screen's ",
         "replicates and its settings, never the rows it resampled or their patient identifier. Delete this ",
         "file and rerun the bootstrap runner without changing what it saves.",
         call. = FALSE)
  }
  invisible(TRUE)
}
