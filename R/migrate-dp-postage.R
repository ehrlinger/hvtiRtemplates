.migrate_dp_postage <- function(evidence, template) {
  aliases <- c(dta_filename = "DATASET", dataset = "DATASET", pref_time_var = "X_VAR", x_var = "X_VAR",
               variables = "VARIABLES", include = "VARIABLES", varlist = "VARIABLES", exclude = "EXCLUDE",
               ncol = "GRID_NCOL", grid_ncol = "GRID_NCOL", nrow = "GRID_NROW", grid_nrow = "GRID_NROW",
               unique_limit = "UNIQUE_LIMIT", show_percent = "SHOW_PERCENT",
               pref_color_var = "COLOR", stratify_by = "STRATA", alpha = "ALPHA")
  source <- evidence$paths[["source"]]
  sas <- !is.null(source) && grepl("[.]sas$", source, ignore.case = TRUE)
  inline <- if (sas) .sas_inline_data(evidence$source) else NULL
  if (sas) evidence$source <- inline$source
  lines <- evidence$source$text
  statements <- if (sas) .postage_sas_controls(evidence$source, aliases) else .postage_r_controls(lines, aliases)
  declarations <- unlist(lapply(statements, `[[`, "declared"), use.names = FALSE)
  repeated <- unique(declarations[duplicated(declarations)])
  if (length(repeated)) stop("Multiple declarations of postage controls: ", paste(repeated, collapse = ", "), call. = FALSE)
  config <- list(DATASET = NA_character_, ANALYSIS_SET = NULL, X_VAR = NA_character_, VARIABLES = character(),
                 EXCLUDE = character(), GRID_NCOL = 4L, GRID_NROW = 4L, UNIQUE_LIMIT = 6L, SHOW_PERCENT = FALSE)
  decisions <- list(translated = list(), unresolved = list(), ignored = list())
  for (statement in statements) {
    field <- statement$field
    category <- "unresolved"
    reason <- "Unsupported source code or study-specific cleaning; review manually, do not execute."
    if (isTRUE(statement$inactive)) {
      category <- "ignored"
      reason <- "Non-executable source text or inactive comment."
    } else if (!is.null(field) && field %in% c("COLOR", "STRATA", "ALPHA")) {
      reason <- switch(field,
                       COLOR = "The color choice remains unresolved: hv_eda() has no color-variable argument.",
                       STRATA = "Stratification remains unresolved: the template draws the selected dataset without strata.",
                       ALPHA = "Point alpha remains unresolved: hv_eda() exposes no common alpha control.")
    } else if (grepl("scale_[xy]|^axis[0-9]", statement$text, ignore.case = TRUE)) {
      reason <- "Scale choice remains unresolved: categorical and continuous panels need separate axis review."
    } else if (!is.null(field) && isTRUE(statement$literal$ok)) {
      value <- statement$literal$value
      valid <- FALSE
      if (field %in% c("DATASET", "X_VAR", "VARIABLES", "EXCLUDE")) {
        valid <- is.character(value) && !anyNA(value) && all(nzchar(value)) && !anyDuplicated(value)
        if (field %in% c("DATASET", "X_VAR")) valid <- valid && length(value) == 1L
        if (field == "VARIABLES") valid <- valid && length(value) > 0L
      } else if (field %in% c("GRID_NCOL", "GRID_NROW", "UNIQUE_LIMIT")) {
        valid <- is.numeric(value) && length(value) == 1L && !is.na(value) && is.finite(value) &&
          value > 0 && value <= .Machine$integer.max && value == floor(value)
        if (valid) value <- as.integer(value)
      } else if (field == "SHOW_PERCENT") {
        valid <- is.logical(value) && length(value) == 1L && !is.na(value)
      }
      if (valid && field == "DATASET") {
        selection <- .dc_tables_dataset(evidence$root, tolower(tools::file_path_sans_ext(basename(value))))
        value <- selection$dataset
        valid <- !is.na(value)
        reason <- selection$reason
      }
      if (valid) {
        config[field] <- list(value)
        category <- "translated"
        reason <- paste("Explicit literal control:", field)
      }
    }
    decisions[[category]][[length(decisions[[category]]) + 1L]] <-
      data.frame(line = statement$line, text = statement$text, reason = reason)
  }
  decisions <- lapply(decisions, function(rows) {
    if (!length(rows)) return(data.frame(line = integer(), text = character(), reason = character()))
    do.call(rbind, rows)
  })
  region <- vapply(names(config), function(name) paste0(name, " <- ", paste(deparse(config[[name]]), collapse = " ")), character(1L))
  incomplete <- is.na(config$DATASET) || is.na(config$X_VAR) || !length(config$VARIABLES)
  if (nrow(decisions$unresolved) || incomplete) {
    region <- c(region, "# EDIT: review unresolved postage source choices in the migration report.")
  }
  .sas_inline_result(list(regions = c("dp-postage-config" = paste(region, collapse = "\n")),
                          translated = decisions$translated, unresolved = decisions$unresolved, ignored = decisions$ignored), inline)
}

# Literal extraction never evaluates legacy code, including calls inside c().
.postage_literal <- function(x) {
  if (is.null(x) || is.atomic(x)) return(list(ok = TRUE, value = x))
  if (is.call(x) && identical(x[[1L]], as.name("character")) && length(x) == 2L && identical(x[[2L]], 0)) {
    return(list(ok = TRUE, value = character()))
  }
  if (is.call(x) && identical(x[[1L]], as.name("c"))) {
    values <- lapply(as.list(x)[-1L], .postage_literal)
    if (all(vapply(values, `[[`, logical(1L), "ok"))) {
      return(list(ok = TRUE, value = unlist(lapply(values, `[[`, "value"), use.names = FALSE)))
    }
  }
  list(ok = FALSE, value = NULL)
}

.postage_r_controls <- function(lines, aliases) {
  # Only R fences contribute executable declarations; prose cannot select data.
  literal_eval <- function(option) {
    if (grepl("^\\s*#\\|", option)) {
      value <- sub("^\\s*#\\|\\s*eval\\s*:\\s*", "", option)
      value <- tolower(trimws(sub("\\s+#.*$", "", value)))
      if (value %in% c("true", "false")) return(value == "true")
      return(NA)
    }
    # Parse the complete inline argument without evaluating source expressions.
    header <- sub("^```\\{r\\s*,?\\s*", "", option)
    header <- sub("\\}\\s*$", "", header)
    parsed <- tryCatch(parse(text = paste0("alist(", header, ")"))[[1L]], error = function(e) NULL)
    args <- as.list(parsed)[-1L]
    values <- args[names(args) == "eval"]
    if (length(values) == 1L) {
      if (identical(values[[1L]], TRUE)) return(TRUE)
      if (identical(values[[1L]], FALSE)) return(FALSE)
    }
    NA
  }
  inside <- FALSE
  start <- 0L
  code <- rep("", length(lines))
  conditional <- rep(FALSE, length(lines))
  for (i in seq_along(lines)) {
    if (grepl("^```\\{r(?:[ ,}]|$)", lines[i], perl = TRUE)) {
      inside <- TRUE
      start <- i
    } else if (grepl("^```\\s*$", lines[i])) {
      if (inside) {
        block <- seq.int(start, i)
        options <- lines[block][grepl("^\\s*#\\|\\s*eval\\s*:|^```\\{r.*\\beval\\s*=", lines[block], perl = TRUE)]
        values <- vapply(options, literal_eval, logical(1L))
        if (length(values) && (anyNA(values) || !all(values))) {
          code[block] <- ""
          conditional[block] <- anyNA(values)
        }
      }
      inside <- FALSE
    } else if (inside) {
      code[i] <- lines[i]
    }
  }
  parsed <- tryCatch(parse(text = code, keep.source = TRUE), error = function(e) NULL)
  assigned <- function(x) {
    if (!is.call(x)) return(character())
    own <- character()
    if (as.character(x[[1L]])[1L] %in% c("<-", "=", "<<-") && is.symbol(x[[2L]])) {
      key <- tolower(as.character(x[[2L]]))
      if (key %in% names(aliases)) own <- unname(aliases[key])
    }
    c(own, unlist(lapply(as.list(x)[-1L], assigned), use.names = FALSE))
  }
  rows <- list()
  covered <- integer()
  for (i in seq_along(parsed)) {
    ref <- attr(parsed, "srcref")[[i]]
    indices <- seq.int(ref[1L], ref[3L])
    x <- parsed[[i]]
    field <- NULL
    literal <- list(ok = FALSE, value = NULL)
    if (is.call(x) && as.character(x[[1L]])[1L] %in% c("<-", "=") && is.symbol(x[[2L]])) {
      key <- tolower(as.character(x[[2L]]))
      if (key %in% names(aliases)) {
        field <- unname(aliases[key])
        literal <- .postage_literal(x[[3L]])
      }
    }
    rows[[length(rows) + 1L]] <- list(line = as.integer(ref[1L]), text = paste(lines[indices], collapse = "\n"),
                                      field = field, literal = literal, declared = assigned(x), inactive = FALSE)
    covered <- c(covered, indices)
  }
  for (i in setdiff(seq_along(lines), covered)) {
    if (!nzchar(trimws(lines[i]))) next
    rows[[length(rows) + 1L]] <- list(line = i, text = lines[i], field = NULL, declared = character(),
                                      inactive = !conditional[i] && (!nzchar(trimws(code[i])) || grepl("^\\s*#", code[i])))
  }
  rows[order(vapply(rows, `[[`, integer(1L), "line"))]
}

.postage_sas_controls <- function(source, aliases) {
  rows <- .gfup_statements(source)
  lapply(seq_len(nrow(rows)), function(i) {
    code <- rows$code[i]
    pattern <- "(?i)^%let\\s+([a-z_][a-z0-9_]*)\\s*=\\s*(.*)$"
    parts <- regmatches(code, regexec(pattern, code, perl = TRUE))[[1L]]
    field <- NULL
    value <- NULL
    declarations <- character()
    if (!rows$comment[i]) {
      unquoted <- gsub("'(?:[^']|'')*'|\"(?:[^\"]|\"\")*\"", " ", tolower(code), perl = TRUE)
      defs <- regmatches(unquoted, gregexpr("%let\\s+[a-z_][a-z0-9_]*", unquoted, perl = TRUE))[[1L]]
      keys <- sub("%let\\s+", "", defs, perl = TRUE)
      declarations <- unname(aliases[keys[keys %in% names(aliases)]])
      if (grepl("\\bset(?:\\s|$)", unquoted, perl = TRUE)) declarations <- c(declarations, "DATASET")
      if (length(parts) && tolower(parts[2L]) %in% names(aliases)) {
        field <- unname(aliases[tolower(parts[2L])])
        raw <- trimws(parts[3L])
        if (field %in% c("GRID_NCOL", "GRID_NROW", "UNIQUE_LIMIT") && grepl("^[0-9]+$", raw)) {
          value <- as.numeric(raw)
        } else if (field == "SHOW_PERCENT" && toupper(raw) %in% c("TRUE", "FALSE")) {
          value <- toupper(raw) == "TRUE"
        } else if (grepl("^[a-zA-Z_][a-zA-Z0-9_.]*(?:\\s+[a-zA-Z_][a-zA-Z0-9_]*)*$", raw, perl = TRUE)) {
          value <- strsplit(raw, "\\s+", perl = TRUE)[[1L]]
        } else if (grepl("^('[^']*'|\"[^\"]*\")$", raw)) {
          value <- substr(raw, 2L, nchar(raw) - 1L)
        } else if (!nzchar(raw) && field == "EXCLUDE") {
          value <- character()
        }
      } else if (grepl("(?i)^set\\s+[a-z_][a-z0-9_]*$", code, perl = TRUE)) {
        field <- "DATASET"
        value <- tolower(sub("(?i)^set\\s+", "", code, perl = TRUE))
      }
    }
    if (!is.null(field) && field %in% c("X_VAR", "VARIABLES", "EXCLUDE") && is.character(value)) value <- tolower(value)
    list(line = rows$line[i], text = rows$text[i], field = field,
         literal = list(ok = !is.null(value), value = value), declared = declarations, inactive = rows$comment[i])
  })
}
