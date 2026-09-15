.migrate_dc_gfup <- function(evidence, template) {
  statements <- .gfup_statements(evidence$source)
  translated <- unresolved <- ignored <- data.frame(line = integer(), text = character(), reason = character())
  record <- function(row, reason) data.frame(line = row$line, text = row$text, reason = reason)
  active <- tolower(trimws(statements$code[!statements$comment]))
  ids <- active[grepl("^id[[:space:]]", active)]
  ids <- unique(unlist(strsplit(sub("^id[[:space:]]+", "", ids), "[[:space:]]+"), use.names = FALSE))
  ids <- ids[grepl("^[a-z_][a-z0-9_]*$", ids)]
  derived <- unique(unlist(lapply(active, .gfup_assigned), use.names = FALSE))
  input_code <- gsub("'(?:[^']|'')*'|\"(?:[^\"]|\"\")*\"", " ", statements$code, perl = TRUE)
  input_statement <- !statements$comment & grepl(
    "(^|\\bthen[[:space:]]+|^else[[:space:]]+)set([[:space:]]|$)", input_code, ignore.case = TRUE, perl = TRUE
  )
  intervals <- events <- character()
  for (i in seq_len(nrow(statements))) {
    row <- statements[i, ]
    code <- tolower(trimws(row$code))
    if (row$comment) {
      unresolved <- rbind(unresolved, record(row, "Commented scaffolding is not active evidence; review manually."))
    } else if (grepl("^var[[:space:]]+[a-z_][a-z0-9_[:space:]]*$", code)) {
      fields <- strsplit(sub("^var[[:space:]]+", "", code), "[[:space:]]+")[[1L]]
      intervals <- unique(c(intervals, setdiff(fields, c(ids, derived))))
      if (length(intersect(fields, derived))) {
        unresolved <- rbind(unresolved, record(row, "VAR includes a locally assigned interval; affected fields remain disabled."))
      } else if (length(intersect(fields, ids))) {
        unresolved <- rbind(unresolved, record(row, "VAR includes identifier fields, which remain disabled."))
      } else {
        translated <- rbind(translated, record(row, "Declared follow-up fields; no interval derivation reproduced."))
      }
    } else if (grepl("^by[[:space:]]+[a-z_][a-z0-9_[:space:]]*$", code)) {
      fields <- strsplit(sub("^by[[:space:]]+", "", code), "[[:space:]]+")[[1L]]
      events <- unique(c(events, fields[[1L]]))
      if (fields[[1L]] %in% derived) {
        unresolved <- rbind(unresolved, record(row, "BY names a locally assigned event; the field remains disabled."))
      } else {
        translated <- rbind(translated, record(row, "Leading BY field supplies event evidence; other sort fields do not filter data."))
      }
    } else if (grepl("^if[[:space:]]+[a-z_][a-z0-9_]*[[:space:]]*=[[:space:]]*0$", code)) {
      field <- sub("^if[[:space:]]+([a-z_][a-z0-9_]*)[[:space:]]*=.*$", "\\1", code)
      events <- unique(c(events, field))
      if (field %in% derived) {
        unresolved <- rbind(unresolved, record(row, "Filter names a locally assigned event; the field remains disabled."))
      } else {
        translated <- rbind(translated, record(row, "Censored subset evidence; the full registered cohort remains in the report."))
      }
    } else if (input_statement[[i]]) {
      # Resolve the complete SET evidence together after reading all statements.
      next
    } else if (grepl("^(run|quit)$|^data[[:space:]]|^proc[[:space:]]", code)) {
      ignored <- rbind(ignored, record(row, "SAS execution or procedure wrapper; review options against the new QC output."))
    } else {
      unresolved <- rbind(unresolved, record(row, "Identifier, transformation, include or unsupported statement: not executed."))
    }
  }
  if (length(events) > 1L) stop("dc-gfup has contradictory event fields in BY/filter evidence.", call. = FALSE)
  events <- setdiff(events, c(ids, derived))
  input_rows <- statements[input_statement, ]
  if (nrow(input_rows) == 1L && grepl("^set[[:space:]]+[a-z_][a-z0-9_]*$", input_rows$code, ignore.case = TRUE)) {
    input <- tolower(sub("^set[[:space:]]+", "", input_rows$code, ignore.case = TRUE))
    selection <- .dc_tables_dataset(evidence$root, input)
  } else {
    selection <- list(dataset = NA_character_, reason = "Exactly one plain SET statement is required to select registered data.")
  }
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

.gfup_assigned <- function(code) {
  # Recognize direct assignments and simple THEN/ELSE targets. Quoted text
  # supplies no assignment evidence; other SAS transformations stay unresolved.
  code <- gsub("'(?:[^']|'')*'|\"(?:[^\"]|\"\")*\"", " ", code, perl = TRUE)
  pattern <- "(?:^|\\b(?:then|else)[[:space:]]+)([a-z_][a-z0-9_]*)[[:space:]]*=(?!=)"
  matches <- regmatches(code, gregexpr(pattern, code, perl = TRUE))[[1L]]
  sub("^(?:(?:then|else)[[:space:]]+)?([a-z_][a-z0-9_]*)[[:space:]]*=$", "\\1", matches, perl = TRUE)
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
