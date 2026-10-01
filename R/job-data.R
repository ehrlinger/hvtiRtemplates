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

# A condition that uses .data can reach any column, the ID included, through
# a string such as .data[["ccfid"]], which all.vars() does not see as a column,
# so it is masked as though it named the ID. The column named inside .data[[ ]]
# stays visible: it is the condition's shape, not a value.
.mask_condition <- function(x, cols) {
  text <- if (is.character(x)) x else paste(deparse(x, width.cutoff = 500L), collapse = " ")
  expr <- if (is.character(x)) tryCatch(str2lang(x), error = function(e) NULL) else x
  vars <- tolower(all.vars(expr))
  if (is.null(expr) || !(".data" %in% vars || length(intersect(vars, tolower(cols))))) return(text)
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

# A condition is saved as text and re-evaluated by downstream jobs in another
# environment, so a value it takes from outside the data is fixed into it here:
# .env$x, .env[["x"]] and a bare symbol that is not a column of `cols` become
# the value of x in `env`, as rlang::eval_tidy() would find it. Functions, and
# every symbol in call position, are left alone, as is a symbol found nowhere,
# so eval_tidy() still names it in its error.
.resolve_outside <- function(cond, cols, env) {
  value_of <- function(name) {
    if (!is.character(name) || length(name) != 1L || !exists(name, envir = env)) return(NULL)
    value <- get(name, envir = env)
    if (is.function(value)) NULL else list(value)
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
    for (i in seq_along(e)[-1L]) {
      # Tested in place, never bound: an empty argument, as in x[, 1], cannot
      # be assigned to a variable.
      if (is.name(e[[i]]) && !nzchar(as.character(e[[i]]))) next
      e[[i]] <- walk(e[[i]])
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

# The columns a condition names, for the refusal below. Unlike the masking,
# which hides the values of any condition that uses .data, this resolves
# .data$x and .data[["x"]] to x, so a filter on an ordinary column through .data
# is allowed. Any other use of .data, such as .data[[nm]], names a column that
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
    if (is.call(e)) {
      # Tested in place, never bound: an empty argument cannot be assigned.
      for (i in seq_along(e)) if (!(is.name(e[[i]]) && !nzchar(as.character(e[[i]])))) walk(e[[i]])
    }
    invisible()
  }
  walk(expr)
  list(columns = unique(found), opaque = opaque)
}

# Every condition's exact text is saved in the job's hand-off, so a condition on
# the patient identifier would put identifier values in the job's output. Each
# condition is checked before any is evaluated, and the message shows only the
# masked text. `identifiers` are the ID and any MRN or eMRN column.
.refuse_identifier_where <- function(conditions, identifiers, cols) {
  for (cond in conditions) {
    named <- .where_columns(cond)
    reached <- identifiers[tolower(identifiers) %in% tolower(named$columns)]
    if (!length(reached) && !named$opaque) next
    what <- if (length(reached)) {
      paste0("uses the patient identifier (", paste0("`", reached, "`", collapse = ", "), ")")
    } else {
      paste0("uses .data without a literal column name, so it may reach the patient identifier; name the ",
             "column literally, as .data$age or .data[[\"age\"]]")
    }
    stop(errorCondition(paste0(
      "WHERE condition `", .mask_condition(cond, unique(c(identifiers, cols))), "` ", what, ". Each WHERE ",
      "condition is saved, values included, in this job's output, so a filter on identifier values would ",
      "be saved with it. Exclude those patients in the dataset build, or with an hvtiRdatabuild analysis ",
      "set, and remove the condition from WHERE."
    ), class = "hvti_where_identifier", call = NULL))
  }
  invisible(TRUE)
}

.apply_where <- function(d, where, env = parent.frame(), cols = character(), identifiers = character()) {
  conditions <- .where_conditions(where)
  .refuse_identifier_where(conditions, identifiers, cols)
  steps <- data.frame(condition = character(), shown = character(), removed = integer(),
                      missing = integer())
  for (cond in conditions) {
    cond <- .resolve_outside(cond, names(d), env)
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

#' Read a job's data, keep its rows, and record what was done
#'
#' @description The shared data step of every analysis template. It reads a
#'   registered dataset (or an hvtiRdatabuild analysis set), resolves the
#'   patient identifier, drops the medical record number columns, keeps the rows
#'   \code{where} selects and checks that rows are unique on \code{key}.
#'
#' @param cfg Study configuration, from \code{\link[hvtiRutilities]{study_config}}.
#' @param dataset Name of a dataset registered in \code{_study.yml};
#'   \code{"study"} is the built dataset.
#' @param analysis_set Name of an analysis set written by
#'   \code{hvtiRdatabuild::write_analysis_set()}, or \code{NULL} to read
#'   \code{dataset} whole. Analysis sets derive from \code{"study"} only.
#' @param where Rows to keep: \code{NULL}, one condition from \code{quote()}, or
#'   a list from \code{rlang::exprs()}, all of which must hold. Conditions follow
#'   \code{dplyr::filter()}: a row where a condition is \code{NA} is dropped. A
#'   value from outside the data, written \code{.env$min_age} or as a name that
#'   is not a column, is fixed into the condition when the data are read, so the
#'   recorded condition rebuilds the same rows wherever it runs. A condition
#'   that mentions the \code{id} column or a column named \code{MRN} or
#'   \code{eMRN} (ignoring case), directly or as \code{.data$x} or
#'   \code{.data[["x"]]}, stops before any row is filtered, because each
#'   condition is saved, values included, in the job's output. Exclude those
#'   patients in the dataset build, or with an hvtiRdatabuild analysis set,
#'   instead. So does a \code{.data} use whose column is not written literally,
#'   such as \code{.data[[nm]]}, since the column it reaches cannot be known.
#' @param id The patient identifier column. When it is the default
#'   \code{"ccfid"} and absent, \code{MRN} and then \code{eMRN} are used.
#' @param key Columns that make a row unique; defaults to \code{id}, one row
#'   per patient. Add a visit time or date for repeated measures.
#'
#' @details Columns named \code{MRN} or \code{eMRN} (ignoring case) are
#'   dropped unless one is the identifier. An explicit \code{id} or \code{key}
#'   matches its column ignoring case, because
#'   \code{hvtiRutilities::read_built()} lowercases column names. Identifier,
#'   key and date values are not printed: the record holds counts, and a
#'   \code{where} condition that mentions a \code{key} column or uses
#'   \code{.data} is shown, in the record and in error messages, with its values
#'   replaced by \code{<value>}. So is a condition on \code{id} in a selection
#'   saved before such conditions were refused. Every setting is checked before the data are read.
#'
#' @return A list:
#'   \itemize{
#'     \item \code{data}, the selected rows;
#'     \item \code{record}, a data frame of \code{step} and \code{value} to
#'       print, whose \code{"selection"} attribute holds the settings used;
#'     \item \code{provenance}, the read's provenance record;
#'     \item \code{attrition}, an analysis set's per-rule attrition table, or
#'       \code{NULL} for a dataset read whole.
#'   }
#'   The \code{"selection"} attribute is a list that a job saves in its
#'   hand-off, so a downstream job can rebuild the same rows:
#'   \itemize{
#'     \item \code{dataset} and \code{analysis_set}, as given;
#'     \item \code{where}, the exact text of each condition, values included,
#'       used to rebuild the rows; it stays inside the study and is never
#'       printed;
#'     \item \code{where_shown}, the same conditions as a report may show them,
#'       with the values of any condition on a \code{key} column, or using \code{.data}, replaced;
#'     \item \code{id} and \code{key}, the resolved column names;
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
                          id = "ccfid", key = id) {
  .check_job_settings(dataset, analysis_set, where, id, key)
  read <- .read_job_source(cfg, dataset, analysis_set)
  d <- read$value
  # Taken now: subsetting the columns below drops attributes.
  attrition <- attr(d, "attrition", exact = TRUE)
  rows_read <- nrow(d)
  who <- .resolve_job_id(d, id)
  key <- .match_columns(replace(key, key == id, who$id), names(d))
  ids <- .drop_identifiers(d, who$id)
  # MRN and eMRN are refused even when dropped: the condition would be saved.
  identifiers <- unique(c(who$id, names(d)[tolower(names(d)) %in% .job_identifier_names], .job_identifier_names))
  kept <- .apply_where(ids$data, where, env = parent.frame(), cols = c(who$id, key), identifiers = identifiers)
  counts <- .check_job_key(kept$data, key, who$id)
  record <- .job_record(read$source, rows_read, who, ids$dropped, kept$steps, counts)
  attr(record, "selection") <- list(
    dataset = dataset, analysis_set = analysis_set, where = kept$steps$condition,
    where_shown = kept$steps$shown,
    id = who$id, key = key, rows = counts$rows, patients = counts$patients,
    key_hash = .key_hash(kept$data, key)
  )
  list(data = kept$data, record = record, provenance = read$record, attrition = attrition)
}

# Every setting is checked before the read, so a typo fails fast and is named.
.check_job_settings <- function(dataset, analysis_set, where, id, key) {
  if (!is.character(dataset) || length(dataset) != 1L || is.na(dataset) || !nzchar(dataset)) {
    stop("DATASET must name one dataset registered in _study.yml, such as \"study\".", call. = FALSE)
  }
  if (!is.null(analysis_set) &&
        (!is.character(analysis_set) || length(analysis_set) != 1L || is.na(analysis_set) || !nzchar(analysis_set))) {
    stop("ANALYSIS_SET must be NULL or name one analysis set, such as \"eda\".", call. = FALSE)
  }
  if (!is.null(analysis_set) && !identical(dataset, "study")) {
    stop("An analysis set is written from the study dataset, not `", dataset,
         "`. Set ANALYSIS_SET <- NULL to read `", dataset, "` whole.", call. = FALSE)
  }
  .where_conditions(where)
  if (!is.character(id) || length(id) != 1L || is.na(id) || !nzchar(id)) {
    stop("ID must name one column, such as \"ccfid\".", call. = FALSE)
  }
  if (!is.character(key) || !length(key) || anyNA(key) || !all(nzchar(key))) {
    stop("KEY must name one or more columns, such as ID or c(ID, \"iv_echo\").", call. = FALSE)
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
    read <- .provenance_read(dataset, cfg, function() hvtiRutilities::read_built(cfg = cfg, dataset = dataset))
    read$source <- paste0("dataset `", dataset, "` (", basename(hvtiRutilities::built_path(cfg = cfg, dataset = dataset)), ")")
    return(read)
  }
  .require_databuild()
  path <- file.path(hvtiRutilities::study_dir("datasets", cfg$root), paste0(analysis_set, ".parquet"))
  read <- .provenance_file_read(
    paste0("analysis_set:", analysis_set), path, cfg,
    function() hvtiRdatabuild::read_analysis_set(analysis_set, cfg = cfg),
    role = paste0("analysis_set:", analysis_set)
  )
  read$source <- paste0("analysis set `", analysis_set, "` of the study dataset")
  read
}

.job_record <- function(source, rows_read, who, dropped, steps, counts) {
  rows <- list(
    c("Source", source),
    c("Rows read", format(rows_read, big.mark = ",")),
    c("ID", if (who$fallback) paste0("`", who$id, "` (no ccfid; fell back to ", who$id, ")") else paste0("`", who$id, "`")),
    c("Identifiers dropped", if (length(dropped)) paste0("`", dropped, "`", collapse = ", ") else "none")
  )
  for (i in seq_len(nrow(steps))) {
    rows[[length(rows) + 1L]] <- c(
      paste0("`", steps$shown[[i]], "`"),
      paste0("removed ", steps$removed[[i]], if (steps$missing[[i]]) paste0(" (", steps$missing[[i]], " missing)") else "")
    )
  }
  rows[[length(rows) + 1L]] <- c("Rows kept", paste0(format(counts$rows, big.mark = ","), " rows on ",
                                                     format(counts$patients, big.mark = ","), " patients"))
  data.frame(step = vapply(rows, `[[`, "", 1L), value = vapply(rows, `[[`, "", 2L))
}

# A downstream job reuses its upstream job's selection. A setting the job sets
# itself must agree; one left NULL is taken from upstream. Every field the
# upstream selection carries keeps its upstream value, including the ones not
# compared here (rows, patients): a setting only fills a field upstream lacks.
.upstream_fields <- c(dataset = "DATASET", analysis_set = "ANALYSIS_SET", where = "WHERE", id = "ID",
                      key = "KEY", time = "TIME", event = "EVENT")

.check_upstream_selection <- function(upstream, settings) {
  if (is.null(settings)) settings <- list()
  if (is.null(upstream)) return(settings)
  out <- upstream
  for (field in intersect(names(.upstream_fields), names(settings))) {
    mine <- settings[[field]]
    if (is.null(mine)) next
    if (is.call(mine) || is.name(mine) || is.list(mine)) {
      mine <- vapply(.where_conditions(mine), function(x) paste(deparse(x, width.cutoff = 500L), collapse = " "), "")
    }
    if (!field %in% names(upstream)) {
      out[[field]] <- mine
      next
    }
    theirs <- as.character(upstream[[field]])
    same <- if (field %in% c("id", "key")) identical(tolower(mine), tolower(theirs)) else identical(as.character(mine), theirs)
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
    do.call(read_job_data, list(cfg, dataset = sel$dataset, analysis_set = sel$analysis_set,
                                where = where, id = sel$id, key = sel$key),
            quote = TRUE, envir = parent.frame()),
    # A file saved before WHERE on the identifier was refused can carry one.
    hvti_where_identifier = function(e) {
      stop("The upstream job's saved output", if (!is.null(source)) paste0(" (", source, ")"),
           " filters on the patient identifier, which this version refuses. ", conditionMessage(e),
           " Then rerun the upstream job, and this one.", call. = FALSE)
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
