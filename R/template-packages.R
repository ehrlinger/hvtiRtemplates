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
  # The package is the first argument, bare or quoted, perhaps as package =,
  # and other arguments may follow: library("rpart"), library(survival,
  # quietly = TRUE). A call not read is counted in the "unread" attribute
  # rather than dropped, e.g. library(pkg, character.only = TRUE).
  calls <- unlist(regmatches(code, gregexpr("\\blibrary\\([^()]*\\)", code)))
  args <- sub("^library\\((.*)\\)$", "\\1", calls)
  first <- sub("^package\\s*=\\s*", "", trimws(sub(",.*$", "", args)))
  bare <- grepl("^[A-Za-z][A-Za-z0-9.]*$", first) & !grepl("character\\.only\\s*=\\s*(TRUE|T)\\b", args)
  quoted <- grepl("^([\"'])[A-Za-z][A-Za-z0-9.]*\\1$", first)
  attached <- ifelse(quoted, substr(first, 2L, nchar(first) - 1L), first)[bare | quoted]
  unread <- sum(lengths(regmatches(code, gregexpr("\\blibrary\\(", code)))) - sum(bare | quoted)
  hits <- regmatches(chunk, regexec('packageVersion\\("([A-Za-z0-9.]+)"\\)\\s*<\\s*"([0-9.-]+)"', chunk))
  hits <- hits[lengths(hits) == 3L]
  floor_pkg <- vapply(hits, `[[`, character(1), 2L)
  floor_val <- vapply(hits, `[[`, character(1), 3L)
  # A package the setup chunk only checks for, e.g. if (!requireNamespace("patchwork", quietly = TRUE)).
  required <- unlist(regmatches(code, gregexpr('requireNamespace\\("[A-Za-z0-9.]+"', code)))
  required <- sub('^requireNamespace\\("([A-Za-z0-9.]+)"$', "\\1", required)
  package <- unique(c(attached, required, floor_pkg))
  structure(data.frame(package = package, floor = floor_val[match(package, floor_pkg)],
                       stringsAsFactors = FALSE),
            unread = unread)
}
