.source_lines <- function(path) {
  lines <- readLines(path, warn = FALSE)
  data.frame(
    line = seq_along(lines),
    text = lines,
    stringsAsFactors = FALSE
  )
}

.sas_inline_data <- function(source) {
  text <- paste(source$text, collapse = "\n")
  starts <- cumsum(c(1L, nchar(source$text) + 1L))
  withheld <- data.frame(line = integer(), text = character(), reason = character())
  hide <- function(text, first, last, label) {
    rows <- withheld[FALSE, ]
    if (last < first) return(list(text = text, rows = rows))
    payload <- substr(text, first, last)
    lines <- strsplit(payload, "\n", fixed = TRUE)[[1L]]
    offsets <- cumsum(c(0L, nchar(lines) + 1L))[seq_along(lines)]
    locations <- findInterval(first + offsets[nzchar(trimws(lines))], starts)
    if (length(locations)) {
      rows <- data.frame(
        line = source$line[locations], text = label,
        reason = "Review withheld source locally; no patient values copied or source choices inferred."
      )
    }
    substr(text, first, last) <- gsub("[^\n]", " ", payload)
    list(text = text, rows = rows)
  }
  pattern <- "(?s)^(?:/\\*.*?(?:\\*/|$)|'(?:[^']|'')*'|\"(?:[^\"]|\"\")*\"|;|[^;'\"/%]+|[/%%])"
  pos <- statement_start <- 1L
  statement <- ""
  while (pos <= nchar(text)) {
    remaining <- substr(text, pos, nchar(text))
    # Statement comments end at a semicolon even with unmatched apostrophes.
    # Mask them before the downstream statement readers inspect quotes.
    comment_pattern <- if (nzchar(trimws(statement))) "^[[:space:]]*%\\*[^;]*(?:;|$)" else "^[[:space:]]*%?\\*[^;]*(?:;|$)"
    comment <- regmatches(remaining, regexpr(comment_pattern, remaining, perl = TRUE))
    if (length(comment) && nzchar(comment)) {
      substr(text, pos, pos + nchar(comment) - 1L) <- gsub("[^\n]", " ", comment)
      pos <- pos + nchar(comment)
      if (!nzchar(trimws(statement))) statement_start <- pos
      next
    }
    token <- regmatches(remaining, regexpr(pattern, remaining, perl = TRUE))
    if (!length(token) || !nzchar(token) || (startsWith(token, "/*") && !endsWith(token, "*/"))) {
      hidden <- hide(text, statement_start, nchar(text), "SAS source content withheld after uncertain tokenization; review locally.")
      text <- hidden$text
      withheld <- rbind(withheld, hidden$rows)
      break
    }
    pos <- pos + nchar(token)
    if (startsWith(token, "/*")) {
      statement <- paste0(statement, " ")
    } else if (token != ";") {
      statement <- paste0(statement, token)
    } else {
      alias <- tolower(trimws(statement))
      statement <- ""
      statement_start <- pos
      if (!grepl("^(datalines|cards|lines)4?$", alias)) next
      remaining <- substr(text, pos, nchar(text))
      terminator <- if (endsWith(alias, "4")) ";;;;" else ";"
      # Only a standalone terminator on a subsequent line is unambiguous.
      # Same-line payload and apparent terminators stay data, through EOF if
      # necessary. Record quotes and semicolons never enter the SAS tokenizer.
      ending <- regexpr(paste0("(?m)(?<=\n)[[:blank:]]*", terminator, "[[:blank:]]*$"), remaining, perl = TRUE)
      size <- if (ending[[1L]] > 0L) ending[[1L]] + attr(ending, "match.length") - 1L else nchar(remaining)
      hidden <- hide(text, pos, pos + size - 1L, "Inline SAS data content withheld; review the source locally.")
      text <- hidden$text
      withheld <- rbind(withheld, hidden$rows)
      pos <- pos + size
      statement_start <- pos
    }
  }
  source$text <- vapply(seq_len(nrow(source)), function(i) {
    substr(text, starts[[i]], starts[[i]] + nchar(source$text[[i]]) - 1L)
  }, character(1L))
  list(source = source, withheld = withheld)
}

.sas_inline_result <- function(result, inline) {
  if (!is.null(inline) && nrow(inline$withheld)) {
    result$unresolved <- rbind(result$unresolved, inline$withheld)
    result$regions[[1L]] <- paste(result$regions[[1L]],
                                  "# EDIT: review withheld SAS source locally before interpreting this job.", sep = "\n")
  }
  result
}

.sas_mask_comments <- function(lines) {
  masked <- as.character(lines)
  in_block <- FALSE
  in_statement <- FALSE
  in_comment <- FALSE
  quote <- ""

  for (i in seq_along(masked)) {
    chars <- strsplit(masked[[i]], "", fixed = TRUE)[[1L]]
    j <- 1L

    while (j <= length(chars)) {
      char <- chars[[j]]
      next_char <- if (j < length(chars)) chars[[j + 1L]] else ""
      if (in_comment) {
        chars[[j]] <- " "
        if (char == ";") in_comment <- FALSE
        j <- j + 1L
      } else if (nzchar(quote)) {
        if (char == quote) {
          if (next_char == quote) {
            j <- j + 1L
          } else {
            quote <- ""
          }
        }
        j <- j + 1L
      } else if (in_block) {
        closes_block <- chars[[j]] == "*" && j < length(chars) && chars[[j + 1L]] == "/"
        chars[[j]] <- " "
        if (closes_block) {
          chars[[j + 1L]] <- " "
          in_block <- FALSE
          j <- j + 2L
        } else {
          j <- j + 1L
        }
      } else if (char == "/" && next_char == "*") {
        chars[[j]] <- " "
        chars[[j + 1L]] <- " "
        in_block <- TRUE
        j <- j + 2L
      } else if ((char == "%" && next_char == "*") ||
                   (char == "*" && !in_statement)) {
        in_comment <- TRUE
        chars[[j]] <- " "
        j <- j + 1L
      } else {
        if (char %in% c("'", '"')) quote <- char
        if (char == ";") {
          in_statement <- FALSE
        } else if (nzchar(trimws(char))) {
          in_statement <- TRUE
        }
        j <- j + 1L
      }
    }

    masked[[i]] <- paste(chars, collapse = "")
  }

  masked
}

.sas_calls <- function(lines, name) {
  masked <- .sas_mask_comments(lines)
  source <- paste(lines, collapse = "\n")
  scan_text <- paste(masked, collapse = "\n")
  pattern <- paste0("(?i)%", name, "[[:space:]]*\\(")
  starts <- gregexpr(pattern, scan_text, perl = TRUE)[[1L]]

  if (starts[[1L]] == -1L) {
    return(list())
  }

  lengths <- attr(starts, "match.length")
  line_starts <- cumsum(c(1L, nchar(lines) + 1L))
  calls <- list()

  for (i in seq_along(starts)) {
    open <- starts[[i]] + lengths[[i]] - 1L
    depth <- 0L
    close <- NA_integer_

    for (j in seq.int(open, nchar(scan_text))) {
      char <- substr(scan_text, j, j)
      if (char == "(") {
        depth <- depth + 1L
      } else if (char == ")") {
        depth <- depth - 1L
        if (depth == 0L) {
          close <- j
          break
        }
      }
    }

    if (!is.na(close)) {
      calls[[length(calls) + 1L]] <- list(
        start = findInterval(starts[[i]], line_starts),
        end = findInterval(close, line_starts),
        text = substr(source, starts[[i]], close)
      )
    }
  }

  calls
}

.sas_arguments <- function(call) {
  source <- paste(call, collapse = "\n")
  macro <- regexpr("^[[:space:]]*%[^[:space:](]+[[:space:]]*\\(", source, perl = TRUE)
  open <- if (macro[[1L]] > 0L) {
    macro[[1L]] + attr(macro, "match.length") - 1L
  } else {
    -1L
  }

  if (open > 0L) {
    chars <- strsplit(source, "", fixed = TRUE)[[1L]]
    depth <- 0L
    close <- NA_integer_
    for (i in seq.int(open, length(chars))) {
      if (chars[[i]] == "(") {
        depth <- depth + 1L
      } else if (chars[[i]] == ")") {
        depth <- depth - 1L
        if (depth == 0L) {
          close <- i
          break
        }
      }
    }
    source <- substr(source, open + 1L, close - 1L)
  }

  masked <- .sas_mask_comments(source)
  chars <- strsplit(masked, "", fixed = TRUE)[[1L]]
  depth <- 0L
  starts <- 1L
  pieces <- character()

  for (i in seq_along(chars)) {
    if (chars[[i]] == "(") {
      depth <- depth + 1L
    } else if (chars[[i]] == ")") {
      depth <- depth - 1L
    } else if (chars[[i]] == "," && depth == 0L) {
      pieces <- c(pieces, substr(source, starts, i - 1L))
      starts <- i + 1L
    }
  }
  pieces <- c(pieces, substr(source, starts, nchar(source)))

  arguments <- list()
  for (piece in pieces) {
    equals <- regexpr("=", piece, fixed = TRUE)[[1L]]
    if (equals > 0L) {
      key <- tolower(trimws(substr(piece, 1L, equals - 1L)))
      arguments[[key]] <- trimws(substr(piece, equals + 1L, nchar(piece)))
    }
  }

  arguments
}

.sas_grouped_vars <- function(text) {
  source <- paste(text, collapse = "\n")
  starts <- gregexpr("(?s)/\\*.*?\\*/", source, perl = TRUE)[[1L]]

  if (starts[[1L]] == -1L) {
    return(stats::setNames(list(), character()))
  }

  lengths <- attr(starts, "match.length")
  headings <- vapply(
    seq_along(starts),
    function(i) {
      comment <- substr(source, starts[[i]], starts[[i]] + lengths[[i]] - 1L)
      trimws(sub("\\*/$", "", sub("^/\\*", "", comment)))
    },
    character(1L)
  )

  if (any(!nzchar(headings))) {
    stop("SAS variable-list group headings must not be empty.", call. = FALSE)
  }
  if (anyDuplicated(headings)) {
    stop("SAS variable-list group headings must be unique.", call. = FALSE)
  }

  variables <- lapply(seq_along(starts), function(i) {
    segment_start <- starts[[i]] + lengths[[i]]
    segment_end <- if (i == length(starts)) {
      nchar(source)
    } else {
      starts[[i + 1L]] - 1L
    }
    segment <- trimws(substr(source, segment_start, segment_end))
    if (!nzchar(segment)) {
      return(character())
    }
    strsplit(segment, "[[:space:]]+", perl = TRUE)[[1L]]
  })

  stats::setNames(variables, headings)
}

.sas_log_findings <- function(lines, path = NA_character_) {
  lines <- as.character(lines)
  note_pattern <- paste0(
    "^[[:space:]]*NOTE:.*([0-9][0-9,]*[[:space:]]+observations?|",
    "observations?[[:space:]]+(read|created|written|deleted|added))"
  )
  severity <- ifelse(
    grepl("^[[:space:]]*ERROR(?:[[:space:]]+[0-9]+-[0-9]+)?:", lines, ignore.case = TRUE, perl = TRUE),
    "error",
    ifelse(
      grepl("^[[:space:]]*WARNING:", lines, ignore.case = TRUE),
      "warning",
      ifelse(
        grepl(note_pattern, lines, ignore.case = TRUE),
        "note",
        NA_character_
      )
    )
  )
  keep <- !is.na(severity)
  messages <- lines[keep]
  capture <- function(pattern, group) {
    matches <- regmatches(messages, regexec(pattern, messages, ignore.case = TRUE, perl = TRUE))
    vapply(matches, function(x) if (length(x) > group) x[[group + 1L]] else NA_character_, character(1L))
  }
  count <- "([0-9]+(?:,[0-9]{3})*)"
  read_pattern <- paste0("^[[:space:]]*NOTE:[[:space:]]+There (?:were|was) ", count,
                         " observations? (?:read|created|written|deleted|added)\\b")
  dataset_pattern <- paste0("^[[:space:]]*NOTE:[[:space:]]+The data set [^[:space:]]+ has ", count,
                            " observations? and ", count, " variables?\\b")
  # Only complete recognized count prefixes supply numeric facts. Numbers
  # elsewhere in a diagnostic may be observation values or identifiers.
  observations <- as.numeric(gsub(",", "", capture(read_pattern, 1L), fixed = TRUE))
  dataset_counts <- as.numeric(gsub(",", "", capture(dataset_pattern, 1L), fixed = TRUE))
  observations[is.na(observations)] <- dataset_counts[is.na(observations)]

  data.frame(
    line = which(keep),
    severity = unname(severity[keep]),
    category = ifelse(severity[keep] == "note", "observation_note", paste0("sas_", severity[keep])),
    error_code = capture("^[[:space:]]*ERROR[[:space:]]+([0-9]+-[0-9]+):", 1L),
    observations = observations,
    variables = as.numeric(gsub(",", "", capture(dataset_pattern, 2L), fixed = TRUE)),
    path = rep(unname(path), sum(keep)),
    text = rep("SAS log message content withheld; review the source locally.", sum(keep)),
    stringsAsFactors = FALSE
  )
}

.listing_facts <- function(lines) {
  lines <- as.character(lines)
  keep <- nzchar(trimws(lines))

  # Listings can interleave aggregate tables and patient observations. Without
  # a verified table schema, retain locations only, never arbitrary cell text.
  data.frame(
    line = which(keep),
    text = rep("Nonblank listing line; content withheld. Review the source locally.", sum(keep)),
    stringsAsFactors = FALSE
  )
}
