.migrate_dp_trends <- function(evidence, template) {
  # This is the fixture's declaration grammar, not a SAS execution engine.
  rows <- .gfup_statements(evidence$source)
  rows <- rows[order(rows$line, seq_len(nrow(rows))), ]
  code <- tolower(rows$code)
  decisions_env <- new.env(parent = emptyenv())
  decisions_env$status <- rep("unresolved", nrow(rows))
  decisions_env$reason <- rep("Unsupported source statement or inactive comment; review manually, do not execute.", nrow(rows))
  record <- function(i, category, why) {
    decisions_env$status[i] <- category
    decisions_env$reason[i] <- why
  }
  match_code <- function(pattern) which(!rows$comment & grepl(pattern, code, perl = TRUE))
  capture <- function(pattern, text) regmatches(text, regexec(pattern, text, perl = TRUE))[[1L]][-1L]
  quote_r <- function(x) encodeString(x, quote = '"')
  quote_name <- function(x) if (identical(make.names(x), x)) x else paste0("`", x, "`")
  plain <- "[a-z_][a-z0-9_]*"
  number <- "-?[0-9]+(?:[.][0-9]+)?"
  unquoted <- gsub("'(?:[^']|'')*'|\"(?:[^\"]|\"\")*\"", " ", code, perl = TRUE)
  active <- unquoted[!rows$comment]
  # Count declarations independently of the grammar that can translate them.
  # Otherwise an unsupported later definition leaves a stale supported value.
  names_in <- function(text, pattern) {
    matches <- regmatches(text, gregexpr(pattern, text, perl = TRUE))
    unlist(lapply(matches, function(x) sub(pattern, "\\1", x, perl = TRUE)), use.names = FALSE)
  }
  inputs <- which(!rows$comment & grepl("(^|\\bthen\\s+|^else\\s+)set(?:\\s|$)", unquoted, perl = TRUE))
  selection <- list(dataset = NA_character_, reason = "Exactly one plain SET statement is required to select registered data.")
  if (length(inputs) == 1L && grepl(paste0("^set\\s+", plain, "$"), code[inputs], perl = TRUE)) {
    selection <- .dc_tables_dataset(evidence$root, sub("^set\\s+", "", code[inputs], perl = TRUE))
  }
  record(inputs, if (is.na(selection$dataset)) "unresolved" else "translated", selection$reason)
  data <- paste0("DATASET <- ", if (is.na(selection$dataset)) "NA_character_" else quote_r(selection$dataset))
  if (is.na(selection$dataset)) data <- c(data, "# EDIT: resolve the registered dataset from complete SET evidence.")

  assigned <- unique(unlist(lapply(unquoted[!rows$comment], .gfup_assigned), use.names = FALSE))
  years <- which(!rows$comment & vapply(unquoted, function(x) "year" %in% .gfup_assigned(x), logical(1L)))
  year <- c("# EDIT: resolve the calendar-year assignment from source evidence.", "d$year <- NA_real_")
  year_pattern <- paste0("^year\\s*=\\s*floor\\s*\\(\\s*(", plain, ")\\s*\\)\\s*\\+\\s*([0-9]{4})$")
  interval_pattern <- paste0("^year\\s*=\\s*floor\\s*\\(\\s*(", plain, ")\\s*\\)$")
  if (length(years) == 1L) {
    i <- years[[1L]]
    parts <- capture(year_pattern, code[i])
    if (length(parts) && !parts[1L] %in% assigned) {
      year <- paste0("d$year <- floor(d$", quote_name(parts[1L]), ") + ", parts[2L])
      record(i, "translated", "Explicit whole-year assignment and origin.")
    } else {
      interval <- capture(interval_pattern, code[i])
      candidates <- which(rows$comment & grepl("year origin: *[0-9]{4}", tolower(rows$text)))
      if (length(interval) && !interval %in% assigned && length(candidates) == 1L) {
        origin <- sub(".*year origin: *([0-9]{4}).*", "\\1", tolower(rows$text[candidates]))
        year <- c(paste0("# EDIT: confirm inferred origin from source line ", rows$line[candidates], "."),
                  paste0("d$year <- floor(d$", quote_name(interval), ") + ", origin))
        record(c(i, candidates), "unresolved", "Candidate origin occurs only in prose; original year review marker must remain.")
      }
    }
  }
  if (length(years) > 1L) record(years, "unresolved", "Multiple year assignments; no assignment selected.")

  declarations <- match_code(paste0("^%let\\s+(percent|continuous)\\s*=\\s*", plain, "(?:\\s+", plain, ")*$"))
  fields <- kinds <- character()
  declaration_rows <- integer()
  declaration_kinds <- names_in(active, "%let\\s+(percent|continuous)\\b")
  for (i in declarations) {
    parts <- capture("^%let\\s+(percent|continuous)\\s*=\\s*(.*)$", code[i])
    vars <- strsplit(parts[2L], "\\s+", perl = TRUE)[[1L]]
    fields <- c(fields, vars)
    kinds <- c(kinds, rep(parts[1L], length(vars)))
    declaration_rows <- c(declaration_rows, rep(i, length(vars)))
    record(i, "translated", "Explicit variable list and percent/continuous intent.")
  }
  disabled <- duplicated(fields) | duplicated(fields, fromLast = TRUE) | fields %in% assigned
  overwritten <- names(which(table(declaration_kinds) > 1L))
  disabled <- disabled | kinds %in% overwritten
  record(declaration_rows[disabled], "unresolved", "Repeated intent declarations or repeated/locally assigned fields remain disabled.")
  fields <- fields[!disabled]
  kinds <- kinds[!disabled]

  labels <- list()
  label_pattern <- paste0("(?i)^label\\s+(", plain, ")\\s*=\\s*('(?:[^']|'')*'|\"(?:[^\"]|\"\")*\")$")
  label_rows <- match_code(label_pattern)
  label_definitions <- active[grepl("(?:^|%then\\s+)label\\s", active, perl = TRUE)]
  label_fields <- names_in(label_definitions, paste0("\\b(", plain, ")\\s*="))
  for (i in label_rows) {
    parts <- capture(label_pattern, rows$code[i])
    field <- tolower(parts[1L])
    if (field %in% fields && sum(label_fields == field) == 1L) {
      value <- substr(parts[2L], 2L, nchar(parts[2L]) - 1L)
      delimiter <- substr(parts[2L], 1L, 1L)
      labels[[field]] <- gsub(paste0(delimiter, delimiter), delimiter, value, fixed = TRUE)
      record(i, "translated", "Explicit series label.")
    }
  }
  axes <- list()
  axis_pattern <- paste0("^axis([0-9]+)\\s+order\\s*=\\s*\\(\\s*(", number, ")\\s+to\\s+(", number,
                         ")\\s+by\\s+(", number, ")\\s*\\)$")
  axis_rows <- match_code(axis_pattern)
  axis_ids <- names_in(active, "(?:^|%then\\s+)axis([0-9]+)\\b")
  for (i in axis_rows) {
    parts <- capture(axis_pattern, code[i])
    values <- as.numeric(parts[-1L])
    if (sum(axis_ids == parts[1L]) == 1L && values[2L] >= values[1L] && values[3L] > 0 &&
          (values[2L] - values[1L]) / values[3L] <= 1000) {
      axes[[parts[1L]]] <- parts[-1L]
      record(i, "translated", "Explicit axis range and equally spaced breaks; horizontal range supplies breaks only.")
    }
  }
  plots <- list()
  plot_pattern <- paste0("^plot\\s+(", plain, ")\\s*\\*\\s*year\\s*/\\s*haxis=axis([0-9]+)\\s+vaxis=axis([0-9]+)$")
  plot_rows <- match_code(plot_pattern)
  plot_definitions <- active[grepl("(?:^|%then\\s+)plot\\s", active, perl = TRUE)]
  plot_definitions <- sub("/.*$", "", plot_definitions)
  plot_fields <- names_in(plot_definitions, paste0("\\b(", plain, ")\\b"))
  xaxes <- character()
  for (i in plot_rows) {
    parts <- capture(plot_pattern, code[i])
    if (parts[1L] %in% fields && sum(plot_fields == parts[1L]) == 1L &&
          all(parts[2:3] %in% names(axes))) {
      plots[[parts[1L]]] <- axes[[parts[3L]]]
      xaxes <- c(xaxes, parts[2L])
      record(i, "translated", "Plot variable and axes only; drawing and smoothing replaced by hv_trends().")
    }
  }
  seq_r <- function(values) paste0("seq(", paste(values, collapse = ", "), ")")
  trends <- vapply(seq_along(fields), function(i) {
    field <- fields[i]
    label <- if (is.null(labels[[field]])) field else labels[[field]]
    axis <- plots[[field]]
    ylim <- if (is.null(axis)) "NULL" else paste0("c(", paste(axis[1:2], collapse = ", "), ")")
    ybreaks <- if (is.null(axis)) "NULL" else seq_r(axis)
    paste0("  ", quote_name(field), " = list(cols = ", quote_r(field), ", kind = ", quote_r(kinds[i]), ",\n",
           "    labels = ", quote_r(label), ", ylab = ", quote_r(if (kinds[i] == "percent") "Patients (%)" else label), ",\n",
           "    ylim = ", ylim, ", ybreaks = ", ybreaks, ")")
  }, character(1L))
  trends <- if (length(trends)) {
    c("TRENDS <- list(", paste(trends, collapse = ",\n"), ")")
  } else {
    c("# EDIT: supply explicit, unambiguous trend fields and their measurement kinds.", "TRENDS <- list()")
  }
  xaxes <- unique(xaxes)
  if (length(xaxes) > 1L) record(plot_rows, "unresolved", "Conflicting horizontal axes cannot become one shared XBREAKS value.")
  xbreaks <- if (length(xaxes) == 1L) {
    paste0("XBREAKS <- ", seq_r(axes[[xaxes]]))
  } else {
    c("# EDIT: resolve a shared horizontal axis from the source plots.", "XBREAKS <- NULL")
  }
  quoted <- "('(?:[^']|'')*'|\"(?:[^\"]|\"\")*\")"
  wrapper_patterns <- c(
    "^(run|quit)$", paste0("^data\\s+", plain, "$"),
    paste0("^proc\\s+means\\s+data\\s*=\\s*", plain, "\\s+noprint$"),
    paste0("^proc\\s+gplot\\s+data\\s*=\\s*", plain, "$"), "^class\\s+year$",
    paste0("^var\\s+", plain, "(?:\\s+", plain, ")*$"),
    paste0("^output\\s+out\\s*=\\s*", plain, "\\s+mean\\s*=$"),
    paste0("^title[0-9]*\\s+", quoted, "$"), paste0("^filename\\s+", plain, "\\s+", quoted, "$"),
    paste0("^smooth[.]spline\\(\\s*", plain, "\\s*,\\s*", plain, "\\s*\\)$")
  )
  wrappers <- match_code(paste(wrapper_patterns, collapse = "|"))
  record(wrappers, "ignored", "Legacy aggregation, plotting, title or destination replaced by the template's hv_trends() output.")
  subgroups <- c("# EDIT: review source filters and subgroup intent before accepting the whole cohort.",
                 "SUBGROUPS <- list(all = function(d) rep(TRUE, nrow(d)))")
  decisions <- function(category) {
    keep <- decisions_env$status == category
    data.frame(line = rows$line[keep], text = rows$text[keep], reason = decisions_env$reason[keep])
  }
  regions <- list("dp-trends-data" = data, "dp-trends-year" = year, "dp-trends-trends" = trends,
                  "dp-trends-xbreaks" = xbreaks, "dp-trends-subgroups" = subgroups)
  regions <- vapply(regions, paste, character(1L), collapse = "\n")
  for (name in names(regions)) {
    tryCatch(parse(text = regions[[name]]), error = function(e) {
      stop("Generated dp-trends region '", name, "' is not valid R: ", conditionMessage(e), call. = FALSE)
    })
  }
  list(regions = regions, translated = decisions("translated"),
       unresolved = decisions("unresolved"), ignored = decisions("ignored"))
}
