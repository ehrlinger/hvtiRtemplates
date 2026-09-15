.source_lines <- function(path) {
  lines <- readLines(path, warn = FALSE)
  data.frame(
    line = seq_along(lines),
    text = lines,
    stringsAsFactors = FALSE
  )
}

.sas_mask_comments <- function(lines) {
  masked <- as.character(lines)
  in_block <- FALSE
  in_statement <- FALSE

  for (i in seq_along(masked)) {
    chars <- strsplit(masked[[i]], "", fixed = TRUE)[[1L]]
    j <- 1L

    while (j <= length(chars)) {
      if (in_block) {
        closes_block <- chars[[j]] == "*" && j < length(chars) && chars[[j + 1L]] == "/"
        chars[[j]] <- " "
        if (closes_block) {
          chars[[j + 1L]] <- " "
          in_block <- FALSE
          j <- j + 2L
        } else {
          j <- j + 1L
        }
      } else if (j < length(chars) && chars[[j]] == "/" &&
                   chars[[j + 1L]] == "*") {
        chars[[j]] <- " "
        chars[[j + 1L]] <- " "
        in_block <- TRUE
        j <- j + 2L
      } else {
        j <- j + 1L
      }
    }

    text <- paste(chars, collapse = "")
    is_star_comment <- !in_statement && grepl("^[[:space:]]*\\*", text)

    if (is_star_comment) {
      masked[[i]] <- paste(rep(" ", length(chars)), collapse = "")
    } else {
      masked[[i]] <- text
      code <- trimws(text)
      if (nzchar(code)) {
        in_statement <- !grepl(";[[:space:]]*$", code)
      }
    }
  }

  masked
}

.sas_calls <- function(lines, name) {
  masked <- .sas_mask_comments(lines)
  source <- paste(lines, collapse = "\n")
  scan_text <- paste(masked, collapse = "\n")
  pattern <- paste0("(?i)%", name, "[[:space:]]*\\(")
  starts <- gregexpr(pattern, scan_text, perl = TRUE)[[1L]]

  if (identical(starts, -1L)) {
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

.sas_log_findings <- function(lines) {
  lines <- as.character(lines)
  note_pattern <- paste0(
    "^[[:space:]]*NOTE:.*([0-9][0-9,]*[[:space:]]+observations?|",
    "observations?[[:space:]]+(read|created|written|deleted|added))"
  )
  severity <- ifelse(
    grepl("^[[:space:]]*ERROR:", lines, ignore.case = TRUE),
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

  data.frame(
    line = which(keep),
    severity = unname(severity[keep]),
    text = lines[keep],
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
