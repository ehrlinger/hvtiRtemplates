.migrate_dc_gfup <- function(evidence, template) {
  statements <- .gfup_statements(evidence$source)
  translated <- unresolved <- ignored <- data.frame(line = integer(), text = character(), reason = character())
  record <- function(row, reason) data.frame(line = row$line, text = row$text, reason = reason)
  active <- tolower(trimws(statements$code[!statements$comment]))
  ids <- active[grepl("^id[[:space:]]", active)]
  ids <- unique(unlist(strsplit(sub("^id[[:space:]]+", "", ids), "[[:space:]]+"), use.names = FALSE))
  ids <- ids[grepl("^[a-z_][a-z0-9_]*$", ids)]
  assigned <- active[grepl("^[a-z_][a-z0-9_]*[[:space:]]*=", active)]
  derived <- sub("^([a-z_][a-z0-9_]*)[[:space:]]*=.*$", "\\1", assigned)
  intervals <- events <- inputs <- character()
  for (i in seq_len(nrow(statements))) {
    row <- statements[i, ]
    code <- tolower(trimws(row$code))
    if (row$comment) {
      unresolved <- rbind(unresolved, record(row, "Commented scaffolding is not active evidence; review manually."))
    } else if (grepl("^var[[:space:]]+[a-z_][a-z0-9_[:space:]]*$", code)) {
      fields <- strsplit(sub("^var[[:space:]]+", "", code), "[[:space:]]+")[[1L]]
      intervals <- unique(c(intervals, setdiff(fields, c(ids, derived))))
      if (length(intersect(fields, c(ids, derived)))) {
        unresolved <- rbind(unresolved, record(row, "VAR includes identifier or locally derived fields, which remain disabled."))
      } else {
        translated <- rbind(translated, record(row, "Declared follow-up fields; no interval derivation reproduced."))
      }
    } else if (grepl("^by[[:space:]]+[a-z_][a-z0-9_[:space:]]*$", code)) {
      fields <- strsplit(sub("^by[[:space:]]+", "", code), "[[:space:]]+")[[1L]]
      events <- unique(c(events, fields[[1L]]))
      translated <- rbind(translated, record(row, "Leading BY field supplies event evidence; other sort fields do not filter data."))
    } else if (grepl("^if[[:space:]]+[a-z_][a-z0-9_]*[[:space:]]*=[[:space:]]*0$", code)) {
      events <- unique(c(events, sub("^if[[:space:]]+([a-z_][a-z0-9_]*)[[:space:]]*=.*$", "\\1", code)))
      translated <- rbind(translated, record(row, "Censored subset evidence; the full registered cohort remains in the report."))
    } else if (grepl("^set[[:space:]]+[a-z_][a-z0-9_]*$", code)) {
      inputs <- unique(c(inputs, sub("^set[[:space:]]+", "", code)))
    } else if (grepl("^(run|quit)$|^data[[:space:]]|^proc[[:space:]]", code)) {
      ignored <- rbind(ignored, record(row, "SAS execution or procedure wrapper; review options against the new QC output."))
    } else {
      unresolved <- rbind(unresolved, record(row, "Identifier, transformation, include or unsupported statement: not executed."))
    }
  }
  if (length(events) > 1L) stop("dc-gfup has contradictory event fields in BY/filter evidence.", call. = FALSE)
  events <- setdiff(events, ids)
  if (length(inputs) == 1L) {
    selection <- .dc_tables_dataset(evidence$root, inputs)
  } else {
    selection <- list(dataset = NA_character_, reason = "A unique plain SET input is required to select registered data.")
  }
  input_rows <- statements[grepl("^set[[:space:]]", statements$code, ignore.case = TRUE) & !statements$comment, ]
  if (!nrow(input_rows)) input_rows <- data.frame(line = NA_integer_, text = "No plain SET input")
  if (is.na(selection$dataset)) {
    unresolved <- rbind(unresolved, record(input_rows, selection$reason))
  } else {
    translated <- rbind(translated, record(input_rows, selection$reason))
  }
  # Keep all source references to an ID in unresolved evidence, even when a
  # print or sort statement also names a usable follow-up field.
  has_id <- function(text) {
    vapply(tolower(text), function(x) any(ids %in% strsplit(x, "[^a-z0-9_]+")[[1L]]), logical(1L))
  }
  private <- has_id(translated$text)
  unresolved <- rbind(unresolved, translated[private, ])
  translated <- translated[!private, ]
  private <- has_id(ignored$text)
  unresolved <- rbind(unresolved, ignored[private, ])
  ignored <- ignored[!private, ]
  quote_r <- function(x) encodeString(x, quote = '"')
  data <- c(paste0("DATASET <- ", if (is.na(selection$dataset)) "NA_character_" else quote_r(selection$dataset)),
            "ANALYSIS_SET <- NULL")
  if (is.na(selection$dataset)) data <- c(data, "# EDIT: resolve the registered dataset from the migration evidence.")
  config <- c(
    paste0("EVENT <- ", if (length(events)) quote_r(events) else "NA_character_"),
    paste0("FOLLOWUP <- ", if (length(intervals)) paste0("c(", paste(quote_r(intervals), collapse = ", "), ")") else "character(0)"),
    "IDENTIFIER <- NULL", "MAX_REVIEW_ROWS <- 25L",
    "# EDIT: review unresolved migration evidence and confirm follow-up units in years."
  )
  if (!length(events) || !length(intervals)) {
    config <- c(config, "# EDIT: select event and follow-up fields; source evidence is incomplete.")
    unresolved <- rbind(unresolved, data.frame(line = NA_integer_, text = "EVENT/FOLLOWUP",
                                               reason = "Source evidence is incomplete; no default field was inferred."))
  }
  list(regions = c("dc-gfup-data" = paste(data, collapse = "\n"), "dc-gfup-config" = paste(config, collapse = "\n")),
       translated = translated, unresolved = unresolved, ignored = ignored)
}

.gfup_statements <- function(source) {
  text <- paste(source$text, collapse = "\n")
  pattern <- "(?s)/\\*.*?(?:\\*/|$)|'(?:[^']|'')*'|\"(?:[^\"]|\"\")*\"|;|[^;'\"/]+|/"
  positions <- gregexpr(pattern, text, perl = TRUE)[[1L]]
  tokens <- regmatches(text, list(positions))[[1L]]
  starts <- cumsum(c(1L, nchar(source$text) + 1L))
  out <- data.frame(line = integer(), text = character(), code = character(), comment = logical())
  start <- NA_integer_
  code <- ""
  add <- function(start, end, code, comment) {
    data.frame(line = source$line[[findInterval(start, starts)]], text = substr(text, start, end),
               code = trimws(code), comment = comment)
  }
  for (i in seq_along(tokens)) {
    token <- tokens[[i]]
    pos <- positions[[i]]
    if (startsWith(token, "/*")) {
      out <- rbind(out, add(pos, pos + nchar(token) - 1L, "", TRUE))
      code <- paste0(code, " ")
    } else if (token == ";") {
      if (!is.na(start)) out <- rbind(out, add(start, pos, code, grepl("^%?\\*", trimws(code))))
      start <- NA_integer_
      code <- ""
    } else if (nzchar(trimws(token))) {
      if (is.na(start)) start <- pos + regexpr("[^[:space:]]", token)[[1L]] - 1L
      code <- paste0(code, token)
    }
  }
  if (!is.na(start)) out <- rbind(out, add(start, nchar(text), code, TRUE))
  out
}
