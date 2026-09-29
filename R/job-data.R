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
.mask_condition <- function(x, cols) {
  text <- if (is.character(x)) x else paste(deparse(x, width.cutoff = 500L), collapse = " ")
  expr <- if (is.character(x)) tryCatch(str2lang(x), error = function(e) NULL) else x
  if (is.null(expr) || !length(intersect(tolower(all.vars(expr)), tolower(cols)))) return(text)
  mask <- function(e) {
    if (is.call(e)) {
      # Testing e[[i]] in place, never binding it: an empty argument, as in
      # x[, 1], cannot be assigned to a variable.
      for (i in seq_along(e)[-1L]) {
        if (is.call(e[[i]]) || is.numeric(e[[i]]) || is.character(e[[i]]) || is.complex(e[[i]])) e[[i]] <- mask(e[[i]])
      }
      return(e)
    }
    if (is.numeric(e) || is.character(e) || is.complex(e)) return(as.name("<value>"))
    e
  }
  paste(deparse(mask(expr), width.cutoff = 500L, backtick = FALSE), collapse = " ")
}

.mask_conditions <- function(x, cols) vapply(as.character(x), .mask_condition, "", cols = cols, USE.NAMES = FALSE)

.apply_where <- function(d, where, env = parent.frame(), cols = character()) {
  conditions <- .where_conditions(where)
  steps <- data.frame(condition = character(), shown = character(), removed = integer(),
                      missing = integer())
  for (cond in conditions) {
    label <- paste(deparse(cond, width.cutoff = 500L), collapse = " ")
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
#'   \code{dplyr::filter()}: a row where a condition is \code{NA} is dropped.
#' @param id The patient identifier column. When it is the default
#'   \code{"ccfid"} and absent, \code{MRN} and then \code{eMRN} are used.
#' @param key Columns that make a row unique; defaults to \code{id}, one row
#'   per patient. Add a visit time or date for repeated measures.
#'
#' @details Columns named \code{MRN} or \code{eMRN} (ignoring case) are
#'   dropped unless one is the identifier. No identifier, key or date value is
#'   ever printed; the record holds counts.
#'
#' @return A list: \code{data}, the selected rows; \code{record}, a data frame
#'   of steps and values to print, carrying the settings used in its
#'   \code{"selection"} attribute; \code{provenance}, the read's provenance
#'   record.
#' @export
read_job_data <- function(cfg, dataset = "study", analysis_set = NULL, where = NULL,
                          id = "ccfid", key = id) {
  if (!is.character(dataset) || length(dataset) != 1L || is.na(dataset) || !nzchar(dataset)) {
    stop("DATASET must name one dataset registered in _study.yml, such as \"study\".", call. = FALSE)
  }
  if (!is.null(analysis_set) && !identical(dataset, "study")) {
    stop("An analysis set is written from the study dataset, not `", dataset,
         "`. Set ANALYSIS_SET <- NULL to read `", dataset, "` whole.", call. = FALSE)
  }
  read <- .read_job_source(cfg, dataset, analysis_set)
  d <- read$value
  rows_read <- nrow(d)
  who <- .resolve_job_id(d, id)
  key <- .match_columns(replace(key, key == id, who$id), names(d))
  ids <- .drop_identifiers(d, who$id)
  kept <- .apply_where(ids$data, where, env = parent.frame(), cols = c(who$id, key))
  counts <- .check_job_key(kept$data, key, who$id)
  record <- .job_record(read$source, rows_read, who, ids$dropped, kept$steps, counts)
  attr(record, "selection") <- list(
    dataset = dataset, analysis_set = analysis_set, where = kept$steps$condition,
    where_shown = kept$steps$shown,
    id = who$id, key = key, rows = counts$rows, patients = counts$patients
  )
  list(data = kept$data, record = record, provenance = read$record)
}

.read_job_source <- function(cfg, dataset, analysis_set) {
  if (is.null(analysis_set)) {
    read <- .provenance_read(dataset, cfg, function() hvtiRutilities::read_built(cfg = cfg, dataset = dataset))
    read$source <- paste0("dataset `", dataset, "` (", basename(hvtiRutilities::built_path(cfg = cfg, dataset = dataset)), ")")
    return(read)
  }
  if (!requireNamespace("hvtiRdatabuild", quietly = TRUE)) {
    stop("ANALYSIS_SET needs the hvtiRdatabuild package; install it or set ANALYSIS_SET <- NULL.", call. = FALSE)
  }
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
# job reads no data) rebuild exactly the upstream rows.
.read_upstream_job_data <- function(cfg, lineage, settings, read = TRUE, source = NULL) {
  upstream <- lineage$selection
  if (is.null(upstream)) {
    stop("The upstream job's saved output", if (!is.null(source)) paste0(" (", source, ")"),
         " predates the data contract: it does not record the rows it used. Rerun the upstream job ",
         "with the current template, then rerun this one.", call. = FALSE)
  }
  sel <- .check_upstream_selection(upstream, settings)
  if (!read) return(list(selection = sel))
  where <- if (length(sel$where)) lapply(sel$where, str2lang)
  job_data <- do.call(read_job_data, list(cfg, dataset = sel$dataset, analysis_set = sel$analysis_set,
                                          where = where, id = sel$id, key = sel$key),
                      quote = TRUE, envir = parent.frame())
  now <- attr(job_data$record, "selection")
  if (!identical(as.integer(now$rows), as.integer(upstream$rows)) ||
        !identical(as.integer(now$patients), as.integer(upstream$patients))) {
    stop("The upstream job used ", upstream$rows, " rows on ", upstream$patients, " patients; this job read ",
         now$rows, " rows on ", now$patients, " patients. This job did not rebuild the upstream cohort: ",
         "WHERE may refer to a variable rather than a value, or the data changed since the upstream job ran. ",
         "Rerun the upstream job.", call. = FALSE)
  }
  list(job_data = job_data, selection = sel)
}
