#' Migrate a legacy job into a supported analysis template
#'
#' @description
#' Reads a legacy source job and copies its deterministic choices into a
#' supported template. Writes the migrated job and an evidence report beside
#' it. Review the remaining \code{EDIT:} markers before rendering the job.
#'
#' @details
#' Migration is available for \code{dc-tables}, \code{dc-gfup},
#' \code{dp-trends}, and \code{dp-postage}. Each template has its own
#' interpreter; unsupported source choices remain for review.
#'
#' Source and evidence files must be readable files beneath \code{dir}.
#' Relative paths are resolved from that study root, and symbolic links are
#' checked after resolution. The evidence files are never modified.
#'
#' The job uses the filename and study folder selected by \code{\link{add_job}}.
#' Its report replaces the \code{.qmd} extension with \code{-migration.md} and
#' records study-relative evidence paths, SHA-256 checksums, the package
#' version, translated choices, unresolved choices, and ignored material.
#' Absolute paths within quoted source text are redacted. SAS log errors
#' leave a blocking \code{EDIT:} marker in the generated job.
#'
#' Both outputs are prepared before placement. Migration refuses to overwrite
#' either existing target. If placement fails, newly placed outputs are
#' removed. The destination filesystem must support hard links within each
#' output directory, which provide atomic creation without overwriting.
#'
#' @param source Path to one legacy source job.
#' @param endpoint Endpoint field for the new job's filename.
#' @param type Analysis-type field for the new job's filename.
#' @param prefix Template prefix, such as \code{"dc"}.
#' @param qualifier Template qualifier, such as \code{"tables"}.
#'   Filename fields must match \code{[A-Za-z0-9_]+}.
#' @param lst Optional path to a SAS listing.
#' @param log Optional path to a SAS log.
#' @param reference Optional vector of paths to output references, such as
#'   RTF or DOCX files. They record comparison targets, not analysis choices.
#' @param dir Existing study root. Defaults to the current directory.
#'
#' @return The migrated job path, invisibly. The report is written beside it.
#' @seealso \code{\link{add_job}}, \code{\link{template_list}}
#' @export
migrate_job <- function(source, endpoint, type, prefix, qualifier = NULL,
                        lst = NULL, log = NULL, reference = NULL, dir = ".") {
  .check_field("endpoint", endpoint)
  .check_field("type", type)
  .check_field("prefix", prefix)
  if (!is.null(qualifier)) .check_field("qualifier", qualifier)
  .check_scalar_string("dir", dir)
  root <- normalizePath(dir, winslash = "/", mustWork = TRUE)
  if (!dir.exists(root)) stop("migrate_job(): study root must be a directory.", call. = FALSE)
  .check_scalar_string("source", source)
  if (!is.null(lst)) .check_scalar_string("lst", lst)
  if (!is.null(log)) .check_scalar_string("log", log)
  if (!is.null(reference) && (!is.character(reference) || !length(reference) ||
                                anyNA(reference) || any(!nzchar(reference)))) {
    stop("migrate_job(): `reference` must contain existing file paths.", call. = FALSE)
  }
  paths <- c(source = source, lst = lst, log = log, reference = reference)
  paths <- vapply(paths, .migration_path, character(1L), root = root)
  row <- .select_template(template_list(), prefix, qualifier)
  adapter <- .migration_adapter(prefix, qualifier)
  evidence <- .migration_evidence(paths, root)
  template <- .migration_template(row, endpoint, type, root)
  result <- adapter(evidence, template$lines)
  .migration_finish(template, evidence, result)
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
  report <- .migration_report(evidence, result, template$name)
  report_path <- sub("[.]qmd$", "-migration.md", template$out)
  .write_migration_pair(lines, report, template$out, report_path)
  invisible(template$out)
}

.migration_path <- function(path, root) {
  if (!grepl("^(/|[A-Za-z]:[/\\\\]|\\\\\\\\)", path)) path <- file.path(root, path)
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
  if (!key %in% names(registry)) {
    stop("migrate_job(): migration is not supported for ", prefix,
         if (!is.null(qualifier)) paste0("-", qualifier), ".", call. = FALSE)
  }
  get(registry[[key]], envir = asNamespace("hvtiRtemplates"), mode = "function", inherits = FALSE)
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
    log = .sas_log_findings(optional_text("log")),
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

.migration_redact_text <- function(text) {
  absolute <- "(?:[A-Za-z]:[/\\\\]|\\\\\\\\|/)"
  quoted <- paste0("(?s)([\"'])", absolute, ".*?\\1")
  text <- gsub(quoted, "\\1[absolute path]\\1", text, perl = TRUE)
  # Unquoted paths have no reliable whitespace delimiter. Redact through
  # their field's next statement delimiter, including any path components
  # containing spaces. This runs before fields are joined into report rows.
  unquoted <- paste0(
    "(?<![[:alnum:]_./\\\\])", absolute,
    "[^[:space:]\"'<>;|)\\]}][^\\r\\n\"'<>;|)\\]}]*"
  )
  gsub(unquoted, "[absolute path]", text, perl = TRUE)
}

.migration_report <- function(evidence, result, template,
                              version = as.character(utils::packageVersion("hvtiRtemplates"))) {
  .check_migration_result(result)
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
    section("Evidence (SHA-256)", evidence$files, redact = FALSE),
    section("Translated", result$translated),
    section("Unresolved", result$unresolved),
    section("Ignored", result$ignored),
    section("Log findings", evidence$log),
    section("Listing facts", evidence$lst),
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
    stop("Migration output already exists; refusing to overwrite.", call. = FALSE)
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
  for (i in seq_along(targets)) {
    # Both files are complete before publication. A hard link creates a new
    # directory entry atomically and cannot replace another writer's file.
    if (!suppressWarnings(file.link(staged[[i]], targets[[i]]))) {
      stop("Could not place ", labels[[i]], "; refusing to overwrite an existing target.", call. = FALSE)
    }
    placed <- c(placed, targets[[i]])
  }
  complete <- TRUE
  invisible(targets)
}
