.migrate_dc_tables <- function(evidence, template) {
  inline <- .sas_inline_data(evidence$source)
  evidence$source <- inline$source
  calls <- .sas_calls(evidence$source$text, "desc_tab")
  if (!length(calls)) stop("dc-tables migration requires a %desc_tab call.", call. = FALSE)
  args <- lapply(calls, function(call) .sas_arguments(call$text))
  scalar <- function(name) {
    vapply(args, function(x) {
      if (is.null(x[[name]])) "" else tolower(trimws(x[[name]]))
    }, character(1L))
  }
  inputs <- unique(scalar("input"))
  by <- unique(scalar("by"))
  if (length(inputs) != 1L || length(by) != 1L) {
    stop("All %desc_tab calls must use the same input and by; separate conflicting jobs.", call. = FALSE)
  }
  if (nzchar(by) && !grepl("^[a-z_][a-z0-9_]*$", by)) {
    stop("dc-tables requires one plain BY variable.", call. = FALSE)
  }
  types <- scalar("vartype")
  if (any(!types %in% c("category", "continuous"))) {
    stop("Unsupported %desc_tab vartype; expected category or continuous.", call. = FALSE)
  }
  groups <- list()
  buckets <- list(continuous = character(), category = character())
  translated <- data.frame(line = integer(), text = character(), reason = character())
  unresolved <- translated
  record <- function(line, text, reason) data.frame(line = line, text = text, reason = reason)
  for (i in seq_along(calls)) {
    parsed <- .dc_tables_groups(args[[i]]$varlist)
    for (group in names(parsed)) {
      variables <- parsed[[group]]
      others <- unlist(groups[setdiff(names(groups), group)], use.names = FALSE)
      if (length(intersect(variables, others))) {
        stop("A table variable may not appear in multiple groups.", call. = FALSE)
      }
      groups[[group]] <- unique(c(groups[[group]], variables))
    }
    variables <- tolower(strsplit(trimws(.sas_mask_comments(args[[i]]$varlist)), "[[:space:]]+")[[1L]])
    other_type <- setdiff(names(buckets), types[[i]])
    if (length(intersect(variables, buckets[[other_type]]))) {
      stop("Conflicting vartype declarations for the same variable.", call. = FALSE)
    }
    buckets[[types[[i]]]] <- unique(c(buckets[[types[[i]]]], variables))
    translated <- rbind(translated, record(
      calls[[i]]$start, paste0(types[[i]], ": ", paste(variables, collapse = ", ")),
      "Declared vartype and source row order."
    ))
    # A heading is a SAS comment body. It becomes a GROUPS key in the job, but
    # reports carry no source-comment text, so the report row names a placeholder.
    for (group in names(parsed)) {
      translated <- rbind(translated, record(calls[[i]]$start,
                                             paste0("[heading]: ", paste(parsed[[group]], collapse = ", ")),
                                             "Source comment heading and grouped rows."))
    }
    # A blank argument takes the macro's default, as SAS passes it.
    exposure <- trimws(args[[i]]$exposure %||% "")
    if (nzchar(exposure) && exposure != "1") {
      unresolved <- rbind(unresolved, record(calls[[i]]$start, paste0("exposure=", exposure),
                                             paste("%desc_tab treated the group as an outcome and printed incidence",
                                                   "by row; dc-tables does not reproduce it.")))
    }
    presentation <- setdiff(names(args[[i]]), c("input", "by", "varlist", "vartype", "perctile", "exposure"))
    for (name in presentation) {
      unresolved <- rbind(unresolved, record(calls[[i]]$start, paste0(name, "=", args[[i]][[name]]),
                                             "SAS presentation or unsupported option: review; no equivalent assumed."))
    }
  }
  selection <- .dc_tables_dataset(evidence$root, inputs)
  selected <- record(calls[[1L]]$start, paste0("input=", inputs), selection$reason)
  if (is.na(selection$dataset)) {
    unresolved <- rbind(unresolved, selected)
  } else {
    translated <- rbind(translated, selected)
  }
  translated <- rbind(translated, record(calls[[1L]]$start, paste0("by=", by),
                                         "BY selects a column, not a comparison test or a subset of levels."))
  d <- selection$data
  binary <- categorical <- character()
  unknown <- character()
  for (variable in buckets$category) {
    values <- if (!is.null(d) && variable %in% names(d)) unique(stats::na.omit(d[[variable]])) else NULL
    if (is.numeric(values) && setequal(values, c(0, 1))) {
      binary <- c(binary, variable)
    } else if (length(values) >= 2L) {
      categorical <- c(categorical, variable)
    } else {
      unknown <- c(unknown, variable)
    }
  }
  if (length(binary) || length(categorical)) {
    translated <- rbind(translated, record(
      calls[[1L]]$start,
      paste0("BINARY: ", paste(binary, collapse = ", "), "; CATEGORICAL: ", paste(categorical, collapse = ", ")),
      paste("Classification from registered dataset", selection$dataset,
            "(binary requires observed numeric 0 and 1; categorical requires at least two other observed levels).")
    ))
  }
  if (length(unknown) || is.null(d)) {
    unresolved <- rbind(unresolved, record(calls[[1L]]$start,
                                           paste("classification:", paste(unknown, collapse = ", ")),
                                           paste("Registered data cannot prove the binary/categorical split.", selection$reason)))
  }
  missing <- setdiff(c(buckets$continuous, if (nzchar(by)) by), if (is.null(d)) character() else names(d))
  if (length(missing)) {
    unresolved <- rbind(unresolved, record(calls[[1L]]$start, paste(missing, collapse = ", "),
                                           "Column presence cannot be verified in the selected registered data."))
  }
  titles <- .dc_tables_titles(evidence$source)
  for (i in seq_len(nrow(titles))) {
    unresolved <- rbind(unresolved, record(titles$line[[i]], titles$text[[i]],
                                           "Review title against the combined Word table."))
  }
  for (path in evidence$reference) {
    if (grepl("[.]rtf$", path, ignore.case = TRUE)) {
      text <- readLines(file.path(evidence$root, path), warn = FALSE)
      if (length(text)) {
        unresolved <- rbind(unresolved, record(
          seq_along(text), rep(path, length(text)),
          "RTF content withheld; review the referenced source line locally."
        ))
      } else {
        unresolved <- rbind(unresolved, record(NA_integer_, path, "Empty RTF reference: supply readable output for comparison."))
      }
    } else {
      unresolved <- rbind(unresolved, record(NA_integer_, path, "Output reference requires manual comparison."))
    }
  }
  # What %desc_tab printed: a p-value whenever by= named a group, and both the
  # mean +/- SD and three percentiles (perctile=, 15 50 85 by default) for each
  # continuous variable.
  compare <- if (nzchar(by)) "pvalue" else "none"
  continuous_stat <- if (length(buckets$continuous)) "both" else "median"
  percentiles <- c(15, 85)
  if (length(buckets$continuous)) {
    continuous_calls <- which(types == "continuous")
    given <- unique(vapply(args[continuous_calls], function(x) {
      given <- trimws(x$perctile %||% "")
      if (!nzchar(given)) given <- "15 50 85"
      paste(strsplit(given, "[[:space:]]+")[[1L]], collapse = " ")
    }, character(1L)))
    triple <- suppressWarnings(as.numeric(strsplit(given[[1L]], " ", fixed = TRUE)[[1L]]))
    if (length(given) == 1L && length(triple) == 3L && !anyNA(triple) && triple[[2L]] == 50 &&
          triple[[1L]] < 50 && triple[[3L]] > 50 && all(triple == round(triple))) {
      percentiles <- triple[c(1L, 3L)]
      translated <- rbind(translated, record(calls[[continuous_calls[[1L]]]]$start, paste0("perctile=", given),
                                             "Low and high percentiles; the middle one is the median."))
    } else {
      unresolved <- rbind(unresolved, record(calls[[continuous_calls[[1L]]]]$start,
                                             paste0("perctile=", paste(given, collapse = " | ")),
                                             "Not one low/median/high triple across the calls; PERCENTILES keeps 15, 85."))
    }
    unresolved <- rbind(unresolved, record(
      NA_integer_, "PCTLDEF=4",
      paste("%desc_tab computed percentiles with PROC STDIZE PCTLDEF=4; the R table uses SAS's default",
            "definition (PCTLDEF=5), so the low and high percentiles can differ in small groups. The median agrees.")
    ))
  }
  if (nzchar(by) && length(buckets$continuous)) {
    unresolved <- rbind(unresolved, record(
      NA_integer_, "continuous test",
      paste("%desc_tab reported the Kruskal-Wallis chi-square p-value for any number of groups; for two",
            "groups the R table uses the Wilcoxon rank-sum test, exact in small groups, so p-values differ",
            "(for groups 1-5 and 6-10: 0.0090 in SAS, 0.0079 in R).")
    ))
  }
  if (nzchar(by) && length(buckets$category)) {
    unresolved <- rbind(unresolved, record(
      NA_integer_, "categorical test",
      paste("%desc_tab always used chi-square; the R table uses Fisher's exact test when any expected cell",
            "count is under 5, so p-values for sparse categorical rows differ.")
    ))
  }
  translated <- rbind(translated, record(calls[[1L]]$start,
                                         paste0("COMPARE: ", compare, "; CONTINUOUS_STAT: ", continuous_stat),
                                         "What %desc_tab printed: a p-value when by= named a group; mean +/- SD and percentiles."))
  unresolved <- rbind(unresolved, record(NA_integer_, "abbreviations, Word filename",
                                         "Template defaults require review; SAS options do not prove these choices."))
  statements <- .gfup_statements(evidence$source)
  # Only presentation statements and complete calls are accounted for above.
  # Without DATA-step lineage, even a matching input name cannot prove that
  # the registered rows and measurements are the ones supplied to the macro.
  exterior <- statements[!statements$comment & !grepl(
    "^(%desc_tab[[:space:]]*\\(|title[0-9]*\\b|footnote[0-9]*\\b|options\\b|ods\\b|run$|quit$)",
    statements$code, ignore.case = TRUE, perl = TRUE
  ), ]
  if (nrow(exterior)) {
    unresolved <- rbind(unresolved, record(
      exterior$line, exterior$text,
      "Unsupported source logic; verify cohort and measurements in the registered data build."
    ))
    translated$reason <- paste("Candidate only; source logic prevents deterministic mapping.", translated$reason)
    unresolved <- rbind(unresolved, translated)
    translated <- translated[FALSE, ]
    selection$dataset <- NA_character_
    buckets$continuous <- binary <- categorical <- character()
    by <- ""
    compare <- "none"
    continuous_stat <- "median"
    percentiles <- c(15, 85)
  }
  quote_r <- function(x) encodeString(x, quote = '"')
  vector_r <- function(x) if (length(x)) paste0("c(", paste(quote_r(x), collapse = ", "), ")") else "character(0)"
  group_lines <- vapply(names(groups), function(name) {
    key <- if (identical(make.names(name), name)) name else encodeString(name, quote = "`")
    paste0("  ", key, " = ", vector_r(groups[[name]]))
  }, character(1L))
  group_lines <- paste0(group_lines, c(rep(",", length(group_lines) - 1L), ""))
  # The data region holds DATASET alone: ANALYSIS_SET, WHERE, ID and KEY keep
  # the template's defaults, which read the whole dataset as the SAS job did.
  data_lines <- paste0("DATASET <- ", if (is.na(selection$dataset)) "NA_character_" else quote_r(selection$dataset))
  if (is.na(selection$dataset)) data_lines <- c(data_lines, "# EDIT: resolve the registered dataset for the SAS input.")
  config <- c(
    paste0("BY <- ", if (nzchar(by)) quote_r(by) else "NULL"),
    "GROUPS <- list(", group_lines, ")",
    paste0("CONTINUOUS <- ", vector_r(buckets$continuous)),
    paste0("BINARY <- ", vector_r(binary)), paste0("CATEGORICAL <- ", vector_r(categorical)),
    paste0("COMPARE <- ", quote_r(compare)), paste0("CONTINUOUS_STAT <- ", quote_r(continuous_stat)),
    paste0("PERCENTILES <- c(", paste(percentiles, collapse = ", "), ")"),
    "ABBREVIATIONS <- character(0)", 'WORD_FILE <- "dc-tables.docx"',
    "# EDIT: review SAS presentation choices in the migration report.",
    "# EDIT: confirm comparison, summaries, percentiles, abbreviations and Word filename."
  )
  if (length(unknown) || is.null(d) || length(missing)) {
    config <- c(config, "# EDIT: resolve registered-data column checks and binary/categorical classification.")
  }
  if (nrow(exterior)) config <- c(config, "# EDIT: resolve source cohort and measurement logic before enabling mappings.")
  .sas_inline_result(list(
    regions = c("dc-tables-data" = paste(data_lines, collapse = "\n"),
                "dc-tables-config" = paste(config, collapse = "\n")),
    translated = translated, unresolved = unresolved, ignored = data.frame()
  ), inline)
}

.dc_tables_titles <- function(source) {
  text <- paste(source$text, collapse = "\n")
  # Keep quoted strings (including doubled quotes) and block comments whole,
  # so only a semicolon outside them ends a title statement.
  pattern <- paste0(
    "(?s)/\\*.*?\\*/|", .sas_macro_quote, "|'(?:[^']|'')*'|\"(?:[^\"]|\"\")*\"|;|",
    "[^[:space:];'\"/%]+|[/%]"
  )
  positions <- gregexpr(pattern, text, perl = TRUE)[[1L]]
  tokens <- regmatches(text, list(positions))[[1L]]
  line_starts <- cumsum(c(1L, nchar(source$text) + 1L))
  out <- data.frame(line = integer(), text = character())
  start <- NA_integer_
  is_title <- FALSE
  for (i in seq_along(tokens)) {
    token <- tokens[[i]]
    if (startsWith(token, "/*")) next
    if (token == ";") {
      if (is_title) {
        out <- rbind(out, data.frame(
          line = source$line[[findInterval(start, line_starts)]],
          text = substr(text, start, positions[[i]])
        ))
      }
      start <- NA_integer_
      is_title <- FALSE
    } else if (is.na(start)) {
      start <- positions[[i]]
      is_title <- grepl("^title[0-9]*$", token, ignore.case = TRUE)
    }
  }
  out
}

.dc_tables_groups <- function(varlist) {
  if (is.null(varlist) || !grepl("^[[:space:]]*/\\*", varlist)) {
    stop("Every table variable must follow a /* group */ heading.", call. = FALSE)
  }
  # Parse each original comment segment with the shared helper, then merge.
  # The helper deliberately rejects duplicate headings within a single input.
  starts <- gregexpr("(?s)/\\*.*?\\*/", varlist, perl = TRUE)[[1L]]
  groups <- list()
  for (i in seq_along(starts)) {
    end <- if (i < length(starts)) starts[[i + 1L]] - 1L else nchar(varlist)
    parsed <- .sas_grouped_vars(substr(varlist, starts[[i]], end))
    group <- names(parsed)[[1L]]
    variables <- tolower(parsed[[1L]])
    if (!length(variables) || any(!grepl("^[a-z_][a-z0-9_]*$", variables))) {
      stop("Each table group needs plain SAS variable names; variable-list expressions require review.", call. = FALSE)
    }
    groups[[group]] <- c(groups[[group]], variables)
  }
  groups
}

.dc_tables_dataset <- function(root, input) {
  unresolved <- function(reason, dataset = NA_character_) list(dataset = dataset, data = NULL, reason = reason)
  cfg <- tryCatch(hvtiRutilities::study_config(root), error = function(e) e)
  if (inherits(cfg, "error")) return(unresolved(conditionMessage(cfg)))
  keys <- c("study", names(cfg$additional_datasets))
  files <- c(cfg$built, vapply(cfg$additional_datasets, function(x) x$built, character(1L)))
  stems <- tolower(tools::file_path_sans_ext(basename(files)))
  matches <- which(tolower(keys) == input | stems == input)
  # SAS `set built;` names a file, so a stem match above wins. Only when no
  # file is called built does the word select the study dataset by its name.
  if (!length(matches) && identical(input, "built")) matches <- 1L
  if (!nzchar(input) || length(matches) != 1L) {
    return(unresolved("SAS input does not uniquely match a registered dataset key or filename stem."))
  }
  # Written as "built", as the templates say; "study" is its older name.
  dataset <- c("built", keys[-1L])[[matches]]
  data <- tryCatch(hvtiRutilities::read_built(cfg, dataset = dataset), error = function(e) e)
  if (inherits(data, "error")) return(unresolved(conditionMessage(data), dataset))
  list(dataset = dataset, data = data, reason = paste("Selected registered dataset", dataset, "by key or filename stem."))
}
