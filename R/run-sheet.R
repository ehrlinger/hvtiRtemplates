# Run sheets: the "before you run" page each template gets in the gallery. The
# sheet is the outline and the template holds the details, so everything here
# is read from the template (its sections, markers and calls), from the other
# templates (who reads what it saves) and from the catalog, never written by
# hand. The design is dev/specs/2026-10-26-run-sheets-design.md.

.templates_dir <- function() system.file("templates", package = "hvtiRtemplates")

# ---- Reading one template ----------------------------------------------------

# Which lines sit in an R chunk (the chunk's number; 0 outside one), and the
# ## and ### headings outside chunks, where a # line is a comment, not a section.
.qmd_layout <- function(src) {
  chunk <- integer(length(src))
  open <- FALSE
  k <- 0L
  for (i in seq_along(src)) {
    if (!open && grepl("^```\\{r", src[i])) {
      open <- TRUE
      k <- k + 1L
    } else if (open && grepl("^```", src[i])) {
      open <- FALSE
    } else if (open) {
      chunk[i] <- k
    }
  }
  heads <- which(chunk == 0L & grepl("^#{2,3} \\S", src))
  list(chunk = chunk,
       headings = data.frame(line = heads, level = nchar(sub(" .*$", "", src[heads])),
                             text = trimws(sub("^#+ ", "", src[heads])), stringsAsFactors = FALSE))
}

# The function a call calls, bare or through :: and :::; NA for anything else.
.call_name <- function(call) {
  f <- call[[1L]]
  if (is.symbol(f)) return(as.character(f))
  if (is.call(f) && is.symbol(f[[1L]]) && as.character(f[[1L]]) %in% c("::", ":::")) return(as.character(f[[3L]]))
  NA_character_
}

# Every call in `x`, depth first. Arguments, function bodies and default
# arguments are all searched: vt-fit reads a hand-off inside a default argument.
.walk_calls <- function(x, acc = list()) {
  if (!is.call(x) && !is.pairlist(x)) return(acc)
  if (is.call(x)) acc[[length(acc) + 1L]] <- x
  parts <- as.list(x)
  for (i in seq_along(parts)) {
    # A formal with no default is the empty symbol, which cannot be touched as a value.
    if (identical(parts[[i]], quote(expr = ))) next
    acc <- .walk_calls(parts[[i]], acc)
  }
  acc
}

# One entry per call in the template's R chunks: the chunk's first line, the
# function's name and the call itself.
.template_calls <- function(src, layout) {
  out <- list()
  for (k in setdiff(unique(layout$chunk), 0L)) {
    lines <- which(layout$chunk == k)
    for (e in as.list(parse(text = src[lines], keep.source = FALSE))) {
      for (call in .walk_calls(e)) out[[length(out) + 1L]] <- list(line = lines[1L], fn = .call_name(call), call = call)
    }
  }
  out
}

# The file a set_path("estimates", "<file>") call names; NA for any other call.
.estimates_literal <- function(x) {
  if (is.call(x) && identical(.call_name(x), "set_path") && length(x) == 3L &&
        identical(x[[2L]], "estimates") && is.character(x[[3L]])) x[[3L]] else NA_character_
}

# Top-level names bound to an estimates file, such as
# MODEL_PATH <- set_path("estimates", "lm-binary.rds"). A name bound to two
# different files, or to anything else as well, is NA: it is not one file.
.estimates_bindings <- function(src, layout) {
  found <- list()
  for (k in setdiff(unique(layout$chunk), 0L)) {
    for (e in as.list(parse(text = src[layout$chunk == k], keep.source = FALSE))) {
      if (is.call(e) && isTRUE(.call_name(e) %in% c("<-", "=")) && is.symbol(e[[2L]])) {
        name <- as.character(e[[2L]])
        found[[name]] <- c(found[[name]], .estimates_literal(e[[3L]]))
      }
    }
  }
  vapply(found, function(v) if (length(unique(v)) == 1L) v[[1L]] else NA_character_, character(1L))
}

# The estimates file an argument names: a literal set_path() call, or a
# top-level name bound to one. NA when the template does not say.
.estimates_file <- function(x, bindings) {
  if (is.symbol(x)) {
    v <- bindings[as.character(x)]
    return(if (length(v) == 1L && !is.na(v)) unname(v) else NA_character_)
  }
  .estimates_literal(x)
}

# Everything a sheet reads from one template file.
.run_sheet_facts <- function(file) {
  src <- readLines(file, warn = FALSE)
  layout <- .qmd_layout(src)
  list(name = sub("[.]qmd$", "", basename(file)), folder = basename(dirname(file)), file = file, src = src,
       layout = layout, calls = .template_calls(src, layout), bindings = .estimates_bindings(src, layout),
       markers = .edit_marker_lines(src))
}
