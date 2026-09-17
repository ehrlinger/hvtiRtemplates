#' Migrate a legacy job into a supported analysis template
#'
#' @description
#' Reads a legacy source job and copies its deterministic choices into a
#' supported template. Writes the migrated job and an evidence report beside
#' it. Review the remaining \code{EDIT:} markers before rendering the job.
#'
#' @details
#' A converter is available for \code{dc-tables}, \code{dc-gfup},
#' \code{dp-trends}, and \code{dp-postage}, each interpreting its own source
#' choices; choices the interpreter does not recognize remain for review. A
#' template with no converter yet still migrates: it is scaffolded with every
#' \code{EDIT:} marker kept, the evidence travels with it, and the report
#' says the migration adapter is not yet available.
#'
#' Relative \code{source}, \code{lst}, \code{log} and \code{reference} paths
#' resolve against the working directory, as in any R function; \code{dir}
#' only locates the study root. Each file must exist, be readable and lie
#' beneath that root, and symbolic links are checked after resolution. The
#' evidence files are never modified. The report records whether the listing
#' and log were supplied, found beside the source, or not found.
#'
#' The job uses the filename and study folder selected by \code{\link{add_job}}.
#' Its report replaces the \code{.qmd} extension with \code{-migration.md} and
#' records study-relative evidence paths, SHA-256 checksums, the package
#' version, translated choices, unresolved choices, and ignored material.
#' Source text quoted in the report is masked, whichever converter ran:
#' string literal contents (R raw strings included), SAS and R comment bodies,
#' \code{\%let} values (whole, even when a macro-quoting function such as
#' \code{\%str()} holds a semicolon), \code{\%put} text, unquoted
#' \code{title} and \code{footnote} text, and digit runs of five or more are
#' replaced by placeholders such as \code{"[string]"} or \code{[text]}, and
#' Quarto or R Markdown prose and YAML are withheld.
#' Statement keywords, variable names and operators remain. Absolute paths in
#' any remaining text are redacted. The job is not masked. SAS log errors
#' leave a blocking \code{EDIT:} marker in the generated job.
#' Listings, RTF files and log messages may contain patient observations.
#' Their text is withheld; locations remain available for local review.
#' Logs retain severity, error codes and recognized aggregate counts only.
#'
#' Both outputs are prepared as temporary files beside their targets before
#' placement. Migration refuses to overwrite an existing target, checked for
#' each output immediately before it is placed. Outputs are placed by hard
#' link, which cannot replace an existing file; where the filesystem refuses
#' hard links, the prepared file is renamed into place after a fresh check, so
#' a concurrent writer landing between that check and the rename can still be
#' replaced. If placement fails, only the outputs this call placed are removed,
#' along with its temporary files.
#'
#' @param source Path to one legacy source job, relative to the working
#'   directory or absolute.
#' @param endpoint Endpoint field for the new job's filename.
#' @param type Analysis-type field for the new job's filename.
#' @param prefix Template prefix, such as \code{"dc"}. Read from the SAS
#'   filename when \code{NULL}. When given without \code{qualifier}, the
#'   qualifier is still read from the filename's second field if that field
#'   names one of this prefix's templates.
#' @param qualifier Template qualifier, such as \code{"tables"}. Read from the
#'   SAS filename when \code{NULL}. When given without \code{prefix}, the
#'   prefix is read from the filename and this qualifier is used. Filename
#'   fields must match \code{[A-Za-z0-9_]+}.
#' @param lst Optional path to a SAS listing, relative to the working
#'   directory or absolute. Defaults to the same-named file beside
#'   \code{source} when present.
#' @param log Optional path to a SAS log, relative to the working directory
#'   or absolute. Defaults to the same-named file beside \code{source} when
#'   present.
#' @param reference Optional vector of paths to output references, such as
#'   RTF or DOCX files, relative to the working directory or absolute. They
#'   record comparison targets, not analysis choices.
#' @param dir Any directory in the study, used only to locate the study root.
#'   Defaults to the directory of \code{source}.
#'
#' @return The migrated job path, invisibly. The report is written beside it.
#' @seealso \code{\link{add_job}}, \code{\link{template_list}}
#' @export
migrate_job <- function(source, endpoint, type, prefix = NULL, qualifier = NULL,
                        lst = NULL, log = NULL, reference = NULL, dir = NULL) {
  .check_field("endpoint", endpoint, fn = "migrate_job")
  .check_field("type", type, fn = "migrate_job")
  # The shared string check speaks for template selection; these arguments
  # are migrate_job()'s own, so its errors carry this function's label.
  check_string <- function(what, x) {
    tryCatch(.check_scalar_string(what, x), error = function(e) {
      stop("migrate_job(): ", sub("^template selection: ", "", conditionMessage(e)), call. = FALSE)
    })
  }
  check_string("source", source)
  if (!is.null(prefix)) .check_field("prefix", prefix, fn = "migrate_job")
  if (!is.null(qualifier)) .check_field("qualifier", qualifier, fn = "migrate_job")
  if (!is.null(dir)) check_string("dir", dir)
  # Relative paths resolve against the working directory, as in any R
  # function; `dir` only locates the study root. Each path is resolved once,
  # and the existence check and the evidence both use that resolution.
  resolve <- function(arg, path) {
    if (!file.exists(path)) stop("migrate_job(): ", arg, " not found: ", path, call. = FALSE)
    normalizePath(path, winslash = "/")
  }
  source <- resolve("source", source)
  root <- if (is.null(dir)) hvtiRutilities::study_root(dirname(source)) else hvtiRutilities::study_root(dir)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  found <- c(lst = "supplied", log = "supplied")
  for (arg in c("lst", "log")) {
    given <- get(arg)
    if (!is.null(given)) {
      check_string(arg, given)
      assign(arg, resolve(paste0("`", arg, "`"), given))
    } else {
      assign(arg, .default_evidence(source, arg))
      found[[arg]] <- if (is.null(get(arg))) "not found beside source" else "found beside source"
    }
  }
  if (!is.null(reference)) {
    if (!is.character(reference) || !length(reference) || anyNA(reference) || any(!nzchar(reference))) {
      stop("migrate_job(): `reference` must contain existing file paths.", call. = FALSE)
    }
    reference <- vapply(reference, resolve, character(1L), arg = "`reference`", USE.NAMES = FALSE)
  }
  tpl <- .infer_template(source, prefix, qualifier)
  prefix <- tpl$prefix
  qualifier <- tpl$qualifier
  paths <- c(source = source, lst = lst, log = log, reference = reference)
  paths <- vapply(paths, .migration_path, character(1L), root = root)
  row <- tryCatch(
    .select_template(template_list(), prefix, qualifier),
    error = function(e) stop("migrate_job(): ", conditionMessage(e), call. = FALSE)
  )
  adapter <- .migration_adapter(prefix, qualifier)
  evidence <- .migration_evidence(paths, root)
  evidence$found <- found
  template <- .migration_template(row, endpoint, type, root)
  result <- adapter(evidence, template$lines)
  .migration_finish(template, evidence, result)
}

# A corpus job is <prefix>.<variable>[.<more>].sas. For a prefix with
# qualified templates the second field must name one of them; otherwise the
# choice is the author's, and guessing is the defect add_job() refuses.
.infer_template <- function(source, prefix, qualifier) {
  fields <- strsplit(basename(source), ".", fixed = TRUE)[[1L]]
  tl <- template_list()
  if (!is.null(prefix)) {
    # The caller's prefix wins, but a qualified prefix still takes its
    # qualifier from the second field when that field names one. Anything
    # else is left for .select_template() to refuse as ambiguous.
    if (is.null(qualifier) && length(fields) >= 3L &&
          fields[[2L]] %in% stats::na.omit(tl$qualifier[tl$prefix == prefix])) {
      qualifier <- fields[[2L]]
    }
    return(list(prefix = prefix, qualifier = qualifier))
  }
  needed <- if (is.null(qualifier)) 3L else 2L
  if (length(fields) < needed || !fields[[1L]] %in% tl$prefix) {
    stop("migrate_job(): cannot read a template prefix from '", basename(source),
         "'; pass `prefix` (and `qualifier`).", call. = FALSE)
  }
  prefix <- fields[[1L]]
  # A qualifier the caller names wins over the filename; .select_template()
  # validates it against the prefix read here.
  if (!is.null(qualifier)) return(list(prefix = prefix, qualifier = qualifier))
  quals <- tl$qualifier[tl$prefix == prefix]
  if (all(is.na(quals))) return(list(prefix = prefix, qualifier = NULL))
  if (fields[[2L]] %in% quals) return(list(prefix = prefix, qualifier = fields[[2L]]))
  stop("migrate_job(): '", basename(source), "' does not name a ", prefix, " template; pass `qualifier` as one of: ",
       paste(sort(quals), collapse = ", "), ".", call. = FALSE)
}

.default_evidence <- function(source, suffix) {
  # Without an extension in the file name, sub() either matches nothing and
  # returns the source as its own listing or log, or matches a dot in a
  # directory name and returns an unrelated path.
  if (!grepl("[.][^.]+$", basename(source))) return(NULL)
  path <- sub("[.][^.]+$", paste0(".", suffix), source)
  if (file.exists(path)) path else NULL
}

.migration_template <- function(row, endpoint, type, root) {
  staging <- tempfile(pattern = "migration-stage-")
  dir.create(staging)
  on.exit(unlink(staging, recursive = TRUE), add = TRUE)
  qualifier <- if (is.na(row$qualifier[[1L]])) NULL else row$qualifier[[1L]]
  staged <- add_job(row$prefix[[1L]], endpoint, type, dir = staging, qualifier = qualifier)
  folder <- hvtiRutilities::study_dir(row$folder[[1L]], root = root)
  if (.migration_target_exists(folder)) {
    resolved <- normalizePath(folder, winslash = "/", mustWork = TRUE)
    study_root <- normalizePath(root, winslash = "/", mustWork = TRUE)
    if (!startsWith(resolved, paste0(study_root, "/"))) {
      stop("migrate_job(): output must remain beneath the study root.", call. = FALSE)
    }
  }
  list(
    lines = readLines(staged, warn = FALSE),
    out = file.path(folder, basename(staged)),
    name = row$name[[1L]]
  )
}

.migration_finish <- function(template, evidence, result) {
  .check_migration_result(result)
  lines <- .replace_regions(template$lines, result$regions)
  if (any(evidence$log$severity == "error")) {
    lines <- c(lines, "", "<!-- EDIT: resolve SAS log errors before interpreting this job. -->")
  }
  report <- .migration_report(evidence, result, template$name, converter = !isFALSE(result$converter))
  report_path <- sub("[.]qmd$", "-migration.md", template$out)
  .write_migration_pair(lines, report, template$out, report_path)
  .open_in_editor(template$out)
}

.migration_path <- function(path, root) {
  resolved <- normalizePath(path, winslash = "/", mustWork = TRUE)
  if (!startsWith(resolved, paste0(root, "/"))) {
    stop("migrate_job(): evidence must be beneath the study root: ", path, call. = FALSE)
  }
  if (dir.exists(resolved) || file.access(resolved, 4L) != 0L) {
    stop("migrate_job(): evidence must be a readable file: ", path, call. = FALSE)
  }
  resolved
}

.migration_adapters <- function() {
  c(
    "dc\rtables" = ".migrate_dc_tables",
    "dc\rgfup" = ".migrate_dc_gfup",
    "dp\rtrends" = ".migrate_dp_trends",
    "dp\rpostage" = ".migrate_dp_postage"
  )
}

.migration_key <- function(prefix, qualifier) {
  paste(prefix, if (is.null(qualifier)) "" else qualifier, sep = "\r")
}

.migration_adapter <- function(prefix, qualifier = NULL) {
  key <- .migration_key(prefix, qualifier)
  registry <- .migration_adapters()
  if (!key %in% names(registry)) return(.migrate_no_converter)
  get(registry[[key]], envir = asNamespace("hvtiRtemplates"), mode = "function", inherits = FALSE)
}

# A template without a converter still migrates: the scaffold keeps every
# EDIT: marker, and the evidence travels with the job for the manual port.
.migrate_no_converter <- function(evidence, lines) {
  none <- data.frame(line = integer(), text = character(), reason = character())
  list(regions = character(), translated = none, unresolved = none, ignored = none, converter = FALSE)
}

.replace_regions <- function(lines, regions) {
  if (!is.character(regions) || anyNA(regions) ||
        (length(regions) && (is.null(names(regions)) || anyNA(names(regions)) || any(!nzchar(names(regions)))))) {
    stop("Migration regions must be a named character vector.", call. = FALSE)
  }
  if (anyDuplicated(names(regions))) stop("Migration region names must be unique.", call. = FALSE)
  if (!length(regions)) return(lines)
  markers <- lapply(names(regions), function(name) {
    begin <- which(trimws(lines) == paste0("# MIGRATE-BEGIN: ", name))
    end <- which(trimws(lines) == paste0("# MIGRATE-END: ", name))
    if (length(begin) != 1L || length(end) != 1L) {
      stop("Migration region '", name, "' requires exactly one complete marker pair.", call. = FALSE)
    }
    if (begin >= end) stop("Migration region '", name, "' must begin before its end marker.", call. = FALSE)
    c(begin, end)
  })
  begins <- vapply(markers, `[`, integer(1L), 1L)
  ends <- vapply(markers, `[`, integer(1L), 2L)
  order <- order(begins)
  if (length(order) > 1L && any(begins[order[-1L]] <= ends[order[-length(order)]])) {
    stop("Migration regions must not overlap.", call. = FALSE)
  }
  for (i in rev(order)) {
    after <- if (ends[[i]] < length(lines)) lines[seq.int(ends[[i]] + 1L, length(lines))] else character()
    replacement <- strsplit(regions[[i]], "\n", fixed = TRUE)[[1L]]
    lines <- c(lines[seq_len(begins[[i]])], replacement, lines[ends[[i]]], after)
  }
  lines
}

.migration_target_exists <- function(path) {
  file.exists(path) || (!is.na(Sys.readlink(path)) && nzchar(Sys.readlink(path)))
}

.migration_evidence <- function(paths, root) {
  # c(source = named_path) inherits the caller's name as source.filename.
  names(paths) <- sub("^(source|lst|log|reference)[.].*$", "\\1", names(paths))
  paths <- vapply(paths, .migration_path, character(1L), root = root)
  relative <- substring(unname(paths), nchar(root) + 2L)
  optional_text <- function(name) {
    if (name %in% names(paths)) readLines(paths[[name]], warn = FALSE) else character()
  }
  list(
    root = root,
    paths = stats::setNames(relative, names(paths)),
    files = data.frame(
      role = names(paths),
      path = relative,
      sha256 = unname(vapply(paths, digest::digest, character(1L), algo = "sha256", file = TRUE))
    ),
    source = .source_lines(paths[["source"]]),
    lst = .listing_facts(optional_text("lst")),
    log = .sas_log_findings(optional_text("log"),
                            if ("log" %in% names(paths)) relative[match("log", names(paths))] else NA_character_),
    reference = unname(relative[grepl("^reference", names(paths))])
  )
}

.check_migration_result <- function(result) {
  sections <- c("translated", "unresolved", "ignored")
  if (!is.list(result) || !all(c("regions", sections) %in% names(result)) ||
        !all(vapply(result[sections], is.data.frame, logical(1L))) ||
        !is.character(result$regions) || anyNA(result$regions) ||
        (length(result$regions) && (is.null(names(result$regions)) || anyNA(names(result$regions)) ||
                                      any(!nzchar(names(result$regions))) || anyDuplicated(names(result$regions))))) {
    stop("Invalid migration adapter result: expected named character regions and decision data frames.", call. = FALSE)
  }
  invisible(result)
}

# Reports are pasted into issues and agent sessions, so source text is masked
# here, at the one layer every converter's report passes through. Statement
# shape survives; string contents, comment bodies, macro values and long
# digit runs do not. The job itself is unaffected.
.migration_mask_source <- function(text, language = c("sas", "r")) {
  language <- match.arg(language)
  vapply(as.character(text), .migration_mask_one, character(1L), language = language, USE.NAMES = FALSE)
}

.migration_mask_one <- function(x, language) {
  if (is.na(x) || !nzchar(x)) return(x)
  chars <- strsplit(x, "", fixed = TRUE)[[1L]]
  n <- length(chars)
  find_from <- function(target, from) {
    hit <- if (from <= n) which(chars[seq.int(from, n)] %in% target) else integer()
    if (length(hit)) from + hit[[1L]] - 1L else n + 1L
  }
  out <- character()
  i <- 1L
  statement_start <- TRUE
  while (i <= n) {
    ch <- chars[[i]]
    nx <- if (i < n) chars[[i + 1L]] else ""
    raw <- if (language == "r" && ch %in% c("r", "R") && nx %in% c("'", "\"") &&
                 (i == 1L || !grepl("[[:alnum:]._]", chars[[i - 1L]]))) {
      k <- i + 2L
      while (k <= n && chars[[k]] == "-") k <- k + 1L
      if (k <= n && chars[[k]] %in% c("(", "[", "{")) k
    }
    if (!is.null(raw)) {
      # An R raw string, r"(...)" or r"-[...]-", may hold either quote; it
      # ends only at its own closing bracket, dashes and quote.
      dashes <- strrep("-", raw - i - 2L)
      ending <- paste0(c("(" = ")", "[" = "]", "{" = "}")[[chars[[raw]]]], dashes, nx)
      rest <- if (raw < n) paste(chars[seq.int(raw + 1L, n)], collapse = "") else ""
      hit <- regexpr(ending, rest, fixed = TRUE)[[1L]]
      out <- c(out, ch, nx, dashes, chars[[raw]], "[string]", if (hit > 0L) ending)
      i <- if (hit > 0L) raw + hit + nchar(ending) else n + 1L
      statement_start <- FALSE
    } else if (ch %in% c("'", "\"")) {
      j <- i + 1L
      while (j <= n) {
        if (language == "r" && chars[[j]] == "\\") {
          j <- j + 2L
        } else if (chars[[j]] == ch && language == "sas" && j < n && chars[[j + 1L]] == ch) {
          j <- j + 2L
        } else if (chars[[j]] == ch) {
          break
        } else {
          j <- j + 1L
        }
      }
      out <- c(out, ch, "[string]", if (j <= n) ch)
      i <- j + 1L
      statement_start <- FALSE
    } else if (language == "r" && ch == "#") {
      out <- c(out, "# [comment]")
      i <- find_from("\n", i)
    } else if (language == "sas" && ch == "/" && nx == "*") {
      close <- n + 1L
      if (i + 2L < n) {
        stars <- which(chars[seq.int(i + 2L, n - 1L)] == "*" & chars[seq.int(i + 3L, n)] == "/")
        if (length(stars)) close <- i + 1L + stars[[1L]]
      }
      out <- c(out, "/* [comment] */")
      i <- close + 2L
    } else if (language == "sas" && ((ch == "%" && nx == "*") || (ch == "*" && statement_start))) {
      end <- find_from(";", i)
      out <- c(out, if (ch == "%") "%* [comment]" else "* [comment]", if (end <= n) ";")
      i <- end + 1L
      statement_start <- TRUE
    } else {
      out <- c(out, ch)
      if (ch == ";") {
        statement_start <- TRUE
      } else if (nzchar(trimws(ch))) {
        statement_start <- FALSE
      }
      i <- i + 1L
    }
  }
  masked <- paste(out, collapse = "")
  if (language == "sas") {
    # A macro-quoted argument such as %str(a;b) holds semicolons that do not
    # end the statement, so it is consumed whole. %put text and unquoted
    # title or footnote text are free text; quoted titles are literals above.
    value <- paste0("(?:", .sas_macro_quote, "|[^;])*")
    masked <- gsub(paste0("(?i)(%let\\s+[^=;]*=)", value), "\\1 [value]", masked, perl = TRUE)
    masked <- gsub(paste0("(?i)(%put)(?![a-z0-9_])", value), "\\1 [text]", masked, perl = TRUE)
    literals_only <- "(?!(?:\\s*(?:\"\\[string\\]\"|'\\[string\\]'))*\\s*(?:;|$))"
    masked <- gsub(paste0("(?i)(^|;|\\*/)(\\s*)(title|footnote)([0-9]*)(?![a-z0-9_])", literals_only, value),
                   "\\1\\2\\3\\4 [text]", masked, perl = TRUE)
  }
  gsub("[0-9]{5,}", "[number]", masked)
}

# In a Quarto or R Markdown source only fenced code is quoted; prose and the
# YAML header can name patients and are never copied into the report.
.migration_code_lines <- function(lines) {
  code <- logical(length(lines))
  inside <- FALSE
  for (i in seq_along(lines)) {
    if (!inside && grepl("^\\s*```+\\s*\\{", lines[[i]])) {
      inside <- TRUE
      code[[i]] <- TRUE
    } else if (inside) {
      code[[i]] <- TRUE
      if (grepl("^\\s*```+\\s*$", lines[[i]])) inside <- FALSE
    }
  }
  code
}

.migration_mask_rows <- function(rows, evidence) {
  if (!is.data.frame(rows) || !nrow(rows)) return(rows)
  source <- evidence$paths[["source"]]
  language <- if (!is.null(source) && !grepl("[.]sas$", source, ignore.case = TRUE)) "r" else "sas"
  columns <- setdiff(names(rows)[vapply(rows, function(x) is.character(x) || is.factor(x), logical(1L))], "reason")
  for (column in columns) rows[[column]] <- .migration_mask_source(rows[[column]], language)
  if (!is.null(source) && grepl("[.][qR]md$", source, ignore.case = TRUE) && all(c("line", "text") %in% names(rows))) {
    code <- .migration_code_lines(evidence$source$text)
    prose <- vapply(seq_len(nrow(rows)), function(i) {
      first <- suppressWarnings(as.integer(rows$line[[i]]))
      if (is.na(first)) return(FALSE)
      span <- first + seq_len(max(1L, lengths(strsplit(rows$text[[i]], "\n", fixed = TRUE)))) - 1L
      any(span < 1L | span > length(code)) || !all(code[span])
    }, logical(1L))
    rows$text[prose] <- "[prose withheld]"
  }
  rows
}

.migration_redact_text <- function(text) {
  absolute <- "(?:[A-Za-z]:[/\\\\]|\\\\\\\\|/)"
  quoted <- paste0("(?s)([\"'])", absolute, ".*?\\1")
  text <- gsub(quoted, "\\1[absolute path]\\1", text, perl = TRUE)
  # Unquoted paths have no reliable whitespace delimiter. Redact through
  # their field's next statement delimiter, including any path components
  # containing spaces. This runs before fields are joined into report rows.
  unquoted <- paste0(
    "(?<![[:alnum:]_./*\\\\])(?!/\\*)", absolute,
    "[^[:space:]\"'<>;|)\\]}][^\\r\\n\"'<>;|)\\]}]*"
  )
  gsub(unquoted, "[absolute path]", text, perl = TRUE)
}

.migration_report <- function(evidence, result, template,
                              version = as.character(utils::packageVersion("hvtiRtemplates")),
                              converter = TRUE) {
  .check_migration_result(result)
  log <- evidence$log[intersect(c("line", "severity", "category", "error_code", "observations", "variables", "path"),
                                names(evidence$log))]
  log$text <- rep("SAS log message content withheld; review the source locally.", nrow(evidence$log))
  section <- function(title, rows, redact = TRUE) {
    body <- if (!nrow(rows)) {
      "None recorded."
    } else {
      vapply(seq_len(nrow(rows)), function(i) {
        values <- as.character(rows[i, ])
        if (redact) values <- .migration_redact_text(values)
        paste0("- ", paste(paste0(names(rows), "=", values), collapse = "; "))
      }, character(1L))
    }
    c(paste0("## ", title), "", body, "")
  }
  c(
    "# Migration report", "",
    paste0("Template: hvtiRtemplates ", version, " / ", template), "",
    if (!converter) c("**No converter: every choice is manual.** This template has no migration adapter yet; ",
                      "the job is the plain scaffold and the evidence below is for porting by hand.", "") else character(),
    section("Evidence (SHA-256)", evidence$files, redact = FALSE),
    if (!is.null(evidence$found)) {
      c(paste0("- Listing: ", evidence$found[["lst"]]), paste0("- Log: ", evidence$found[["log"]]), "")
    } else {
      character()
    },
    section("Translated", .migration_mask_rows(result$translated, evidence)),
    section("Unresolved", .migration_mask_rows(result$unresolved, evidence)),
    section("Ignored", .migration_mask_rows(result$ignored, evidence)),
    section("Log findings", log),
    section("Listing facts", .migration_mask_rows(evidence$lst, evidence)),
    "## Completion checklist", "",
    "- [ ] Resolve every EDIT: marker using the source evidence.",
    "- [ ] Review log errors and warnings before interpreting results.",
    "- [ ] Confirm the registered dataset and the job's analysis cohort.",
    "- [ ] Render the job and compare its outputs with the supplied references."
  )
}

.write_migration_pair <- function(job, report, out, report_path) {
  targets <- c(out, report_path)
  labels <- c("migration job", "migration report")
  if (identical(out, report_path)) stop("Migration outputs must have distinct paths.", call. = FALSE)
  if (any(vapply(targets, .migration_target_exists, logical(1L)))) {
    existing <- targets[vapply(targets, .migration_target_exists, logical(1L))]
    stop("Migration output already exists; refusing to overwrite: ", paste(existing, collapse = ", "), call. = FALSE)
  }
  staged <- character()
  placed <- character()
  complete <- FALSE
  on.exit({
    unlink(staged)
    if (!complete) unlink(placed)
  }, add = TRUE)
  values <- list(job, report)
  for (i in seq_along(targets)) {
    parent <- dirname(targets[[i]])
    if (!dir.exists(parent) && !suppressWarnings(dir.create(parent, recursive = TRUE))) {
      stop("Could not prepare ", labels[[i]], " directory.", call. = FALSE)
    }
    staged[[i]] <- tempfile(pattern = ".migration-", tmpdir = parent)
    tryCatch(
      suppressWarnings(writeLines(values[[i]], staged[[i]], useBytes = TRUE)),
      error = function(e) stop("Could not prepare ", labels[[i]], ": ", conditionMessage(e), call. = FALSE)
    )
  }
  refuse <- function(i) {
    stop("Could not place ", labels[[i]], "; refusing to overwrite an existing target: ", targets[[i]], call. = FALSE)
  }
  for (i in seq_along(targets)) {
    # Both files are complete before publication, and the refusal is checked
    # again immediately before each placement. A hard link creates a new
    # directory entry atomically and cannot replace another writer's file.
    if (.migration_target_exists(targets[[i]])) refuse(i)
    if (!.migration_link(staged[[i]], targets[[i]])) {
      # Some filesystems, SMB shares among them, refuse hard links. The
      # prepared file is then renamed into place after a fresh absence check.
      # Base R has no exclusive create, so a writer landing between that check
      # and the rename can still be replaced: a residual race, accepted.
      if (.migration_target_exists(targets[[i]])) refuse(i)
      if (!suppressWarnings(file.rename(staged[[i]], targets[[i]]))) {
        stop("Could not place ", labels[[i]], ": hard links are unsupported and the rename failed: ", targets[[i]],
             call. = FALSE)
      }
    }
    # Only a file this call placed is ever removed on a later failure.
    placed <- c(placed, targets[[i]])
  }
  complete <- TRUE
  invisible(targets)
}

# A seam for tests: base::file.link() cannot be mocked in place.
.migration_link <- function(from, to) {
  isTRUE(suppressWarnings(file.link(from, to)))
}
