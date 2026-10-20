# The packages a template's setup chunk attaches and the version floors it
# checks: the one place a template states what it needs, read rather than
# copied into a second list that would drift from it.
.template_packages <- function(file) {
  lines <- readLines(file, warn = FALSE)
  start <- grep("^#\\|\\s*label:\\s*setup\\s*$", lines)[1L]
  if (is.na(start)) stop("no setup chunk in ", file, call. = FALSE)
  end <- start + grep("^```\\s*$", lines[-seq_len(start)])[1L]
  chunk <- lines[start:end]
  # library() may sit inside suppressPackageStartupMessages(), so match it anywhere in a line.
  code <- sub("\\s#.*$", "", chunk[!grepl("^\\s*#", chunk)])
  calls <- unlist(regmatches(code, gregexpr("\\blibrary\\([A-Za-z0-9.]+\\)", code)))
  attached <- sub("^library\\(([A-Za-z0-9.]+)\\)$", "\\1", calls)
  hits <- regmatches(chunk, regexec('packageVersion\\("([A-Za-z0-9.]+)"\\)\\s*<\\s*"([0-9.-]+)"', chunk))
  hits <- hits[lengths(hits) == 3L]
  floor_pkg <- vapply(hits, `[[`, character(1), 2L)
  floor_val <- vapply(hits, `[[`, character(1), 3L)
  package <- unique(c(attached, floor_pkg))
  data.frame(package = package, floor = floor_val[match(package, floor_pkg)],
             stringsAsFactors = FALSE)
}
