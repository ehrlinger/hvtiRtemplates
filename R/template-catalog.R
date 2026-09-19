#' Catalog of analysis templates owed by this package
#'
#' The catalog records one row per job type, including templates still queued
#' or blocked on functions in other packages. `template_list()` reports the
#' files already shipped; this catalog records the full work plan.
#'
#' @return A data frame. `uses`, `upstream`, `downstream`, and `workflows` are
#'   list columns of character vectors. Unmeasured counts are `NA_integer_`.
#' @export
#' @examples
#' table(template_catalog()$status)
template_catalog <- function() {
  path <- system.file("extdata", "templates.json", package = "hvtiRtemplates")
  .template_catalog_from(path)
}

.read_template_catalog <- function(path) {
  if (!length(path) || !nzchar(path) || !file.exists(path)) {
    stop("Template catalog not found: ", path, call. = FALSE)
  }
  catalog <- tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE),
                      error = function(e) {
                        stop("Cannot read template catalog: ",
                             conditionMessage(e), call. = FALSE)
                      })
  if (!is.list(catalog$templates)) {
    stop("Template catalog has no 'templates' array.", call. = FALSE)
  }
  catalog$templates
}

.template_catalog_from <- function(path) {
  raw <- .read_template_catalog(path)
  scalar <- function(row, i, field) {
    value <- row[[field]]
    if (!is.null(value) && length(value) != 1L) {
      stop("template_catalog(): row ", i, " (prefix '", row$prefix,
           "') gives ", length(value), " values for '", field, "'.",
           call. = FALSE)
    }
    value
  }
  chr <- function(field) {
    vapply(seq_along(raw), function(i) {
      value <- scalar(raw[[i]], i, field)
      if (is.null(value)) NA_character_ else as.character(value)
    }, character(1))
  }
  int <- function(field) {
    vapply(seq_along(raw), function(i) {
      value <- scalar(raw[[i]], i, field)
      if (is.null(value)) return(NA_integer_)
      # Require a JSON number before coercing. as.integer() accepts TRUE as 1
      # and "3" as 3, so without this a boolean or a string count passed as an
      # integer instead of erroring (Codex review on #134).
      result <- if (is.numeric(value)) suppressWarnings(as.integer(value)) else NA_integer_
      if (!is.numeric(value) ||
            (is.na(result) && !is.na(value)) ||
            (!is.na(result) && !identical(as.numeric(value), as.numeric(result)))) {
        stop("template_catalog(): row ", i, " (prefix '", raw[[i]]$prefix,
             "') gives '", value, "' for '", field,
             "', which must be an integer.", call. = FALSE)
      }
      result
    }, integer(1))
  }
  out <- data.frame(
    prefix = chr("prefix"), qualifier = chr("qualifier"),
    name = chr("name"), folder = chr("folder"), family = chr("family"),
    kind = chr("kind"), status = chr("status"),
    disposition = chr("disposition"), batch = int("batch"),
    sas_breadth = int("sas_breadth"),
    sas_breadth_jobs = int("sas_breadth_jobs"),
    r_jobs = int("r_jobs"), r_exemplars = int("r_exemplars"),
    blocked_on = chr("blocked_on"), spec = chr("spec"), note = chr("note"),
    stringsAsFactors = FALSE
  )
  for (field in c("uses", "upstream", "downstream", "workflows")) {
    out[[field]] <- lapply(raw, function(row) {
      values <- unlist(row[[field]], use.names = FALSE)
      if (is.null(values)) character(0) else as.character(values)
    })
  }
  out
}
