.provenance_hook_files <- function() {
  c(
    pre = file.path(".hvtiR", "hooks", "hvti-provenance-pre-render.R"),
    post = file.path(".hvtiR", "hooks", "hvti-provenance-post-render.R")
  )
}

.provenance_hook_command <- function(which = c("pre", "post")) {
  which <- match.arg(which)
  .provenance_hook_files()[[which]]
}

.provenance_hooks <- function(value, name) {
  if (is.null(value)) return(character())
  if (is.character(value) && all(!is.na(value)) && all(nzchar(value))) return(value)
  if (is.list(value)) {
    ok <- vapply(value, function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x), logical(1L))
    if (all(ok)) return(unlist(value, use.names = FALSE))
  }
  stop("_quarto.yml: project ", name, " must be a command or a list of commands.", call. = FALSE)
}

.read_quarto_config <- function(path) {
  if (!file.exists(path)) return(list())
  lines <- readLines(path, warn = FALSE)
  yaml_11_string <- "(y|yes|n|no|on|off)"
  mapping <- paste0("^([[:space:]]*[^#][^:]*:[[:space:]]*)", yaml_11_string, "([[:space:]]*(#.*)?)$")
  sequence <- paste0("^([[:space:]]*-[[:space:]]*)", yaml_11_string, "([[:space:]]*(#.*)?)$")
  lines <- sub(mapping, "\\1'\\2'\\3", lines, ignore.case = TRUE)
  lines <- sub(sequence, "\\1'\\2'\\3", lines, ignore.case = TRUE)
  tryCatch(
    yaml::yaml.load(paste(lines, collapse = "\n")),
    error = function(e) stop("_quarto.yml could not be parsed: ", conditionMessage(e), call. = FALSE)
  )
}

.write_quarto_config <- function(config, path) {
  lines <- strsplit(yaml::as.yaml(config), "\n", fixed = TRUE)[[1L]]
  mapping_yes <- "^([[:space:]]*[^#][^:]*:[[:space:]]*)yes([[:space:]]*(#.*)?)$"
  mapping_no <- "^([[:space:]]*[^#][^:]*:[[:space:]]*)no([[:space:]]*(#.*)?)$"
  sequence_yes <- "^([[:space:]]*-[[:space:]]*)yes([[:space:]]*(#.*)?)$"
  sequence_no <- "^([[:space:]]*-[[:space:]]*)no([[:space:]]*(#.*)?)$"
  lines <- sub(mapping_yes, "\\1true\\2", lines)
  lines <- sub(mapping_no, "\\1false\\2", lines)
  lines <- sub(sequence_yes, "\\1true\\2", lines)
  lines <- sub(sequence_no, "\\1false\\2", lines)
  writeLines(lines, path)
}

.yaml_command <- function(command) {
  as.character(jsonlite::toJSON(command, auto_unbox = TRUE))
}

.project_bounds <- function(lines) {
  start <- grep("^project[[:space:]]*:", lines)
  if (length(start) != 1L) return(NULL)
  following <- if (start < length(lines)) seq.int(start + 1L, length(lines)) else integer()
  end <- following[grepl("^[^[:space:]#][^:]*[[:space:]]*:", lines[following])][1L]
  if (is.na(end)) end <- length(lines) + 1L
  c(start = start, end = end)
}

.project_hook_lines <- function(lines, name, commands) {
  bounds <- .project_bounds(lines)
  start <- bounds[["start"]]
  end <- bounds[["end"]]
  body <- if (end > start + 1L) seq.int(start + 1L, end - 1L) else integer()
  content <- body[nzchar(trimws(lines[body])) & !grepl("^[[:space:]]*#", lines[body])]
  indent <- if (length(content)) min(nchar(sub("^([[:space:]]*).*", "\\1", lines[content]))) else 2L
  key_pattern <- paste0("^[[:space:]]{", indent, "}", name, "[[:space:]]*:")
  key <- body[grepl(key_pattern, lines[body])]
  if (length(key) > 1L) stop("_quarto.yml contains more than one project ", name, " key.", call. = FALSE)
  if (length(key)) {
    later <- if (key < length(lines)) seq.int(key + 1L, length(lines)) else integer()
    next_key <- later[
      nzchar(trimws(lines[later])) &
        !grepl("^[[:space:]]*#", lines[later]) &
        !grepl("^[[:space:]]*-", lines[later]) &
        nchar(sub("^([[:space:]]*).*", "\\1", lines[later])) <= indent
    ][1L]
    if (is.na(next_key)) next_key <- length(lines) + 1L
    lines <- lines[-seq.int(key, next_key - 1L)]
    bounds <- .project_bounds(lines)
    end <- bounds[["end"]]
  }
  block <- c(
    paste0(strrep(" ", indent), name, ":"),
    paste0(strrep(" ", indent + 2L), "- ", vapply(commands, .yaml_command, character(1L)))
  )
  append(lines, block, after = end - 1L)
}

.copy_provenance_file <- function(from, to, overwrite = FALSE) {
  file.copy(from, to, overwrite = overwrite)
}

.rename_provenance_file <- function(from, to) {
  suppressWarnings(file.rename(from, to))
}

.provenance_file_state <- function(path) {
  if (!file.exists(path)) return(list(exists = FALSE))
  info <- file.info(path)
  list(
    exists = TRUE,
    contents = readBin(path, "raw", n = info$size),
    mode = info$mode
  )
}

.backup_provenance_file <- function(path, state) {
  if (!state$exists) return(NA_character_)
  backup <- tempfile(pattern = paste0(".", basename(path), "-backup-"), tmpdir = dirname(path))
  keep <- FALSE
  on.exit(if (!keep && file.exists(backup)) unlink(backup), add = TRUE)
  if (!.copy_provenance_file(path, backup, overwrite = FALSE)) {
    stop("Could not preserve the pre-install file '", path, "'.", call. = FALSE)
  }
  Sys.chmod(backup, mode = state$mode)
  if (!identical(.provenance_file_state(backup), state)) {
    stop("The recovery backup for '", path, "' did not match the original file.", call. = FALSE)
  }
  keep <- TRUE
  backup
}

.restore_provenance_file <- function(path, state, backup = NA_character_) {
  if (!state$exists) {
    if (file.exists(path) && unlink(path) != 0L) {
      stop("Could not remove the newly installed file.", call. = FALSE)
    }
    return(invisible(NULL))
  }
  if (is.na(backup) || !file.exists(backup)) {
    stop("The recovery backup is missing.", call. = FALSE)
  }
  staging <- tempfile(pattern = paste0(".", basename(path), "-restore-"), tmpdir = dirname(path))
  on.exit(if (file.exists(staging)) unlink(staging), add = TRUE)
  if (!.copy_provenance_file(backup, staging, overwrite = FALSE)) {
    stop("Could not stage the recovery backup.", call. = FALSE)
  }
  Sys.chmod(staging, mode = state$mode)
  if (!.provenance_file_unchanged(staging, state)) {
    stop("The staged recovery file did not match the original.", call. = FALSE)
  }
  if (.rename_provenance_file(staging, path)) {
    if (!.provenance_file_unchanged(path, state)) {
      stop("The atomically restored file did not match the original.", call. = FALSE)
    }
    unlink(backup)
    return(invisible(NULL))
  }
  stop("Could not atomically restore the recovery backup.", call. = FALSE)
}

.provenance_file_unchanged <- function(path, state) {
  identical(.provenance_file_state(path), state)
}

.install_provenance_hooks <- function(root) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  config_path <- file.path(root, "_quarto.yml")
  config <- .read_quarto_config(config_path)
  if (is.null(config)) config <- list()
  if (!is.list(config) || (length(config) && is.null(names(config)))) {
    stop("_quarto.yml must contain a named mapping.", call. = FALSE)
  }

  project <- config$project
  if (is.null(project)) {
    project <- list()
  } else if (is.character(project) && length(project) == 1L && !is.na(project)) {
    project <- list(type = project)
  } else if (!is.list(project) || is.null(names(project))) {
    stop("_quarto.yml: `project` must be a mapping or a scalar project type.", call. = FALSE)
  }

  installed <- list()
  for (which in c("pre", "post")) {
    name <- paste0(which, "-render")
    commands <- .provenance_hooks(project[[name]], name)
    command <- .provenance_hook_command(which)
    project[[name]] <- c(commands[commands != command], command)
    installed[[name]] <- project[[name]]
  }

  temporary <- tempfile(pattern = "_quarto-", tmpdir = root, fileext = ".yml")
  on.exit(if (file.exists(temporary)) unlink(temporary), add = TRUE)
  lines <- if (file.exists(config_path)) readLines(config_path, warn = FALSE) else character()
  bounds <- .project_bounds(lines)
  if (is.null(bounds)) {
    lines <- c(lines, if (length(lines) && nzchar(utils::tail(lines, 1L))) "", "project:")
  } else {
    project_line <- lines[bounds[["start"]]]
    inline <- sub("^project[[:space:]]*:[[:space:]]*", "", project_line)
    inline_value <- trimws(sub("[[:space:]]+#.*$", "", inline))
    if (nzchar(inline_value) && !startsWith(inline_value, "#")) {
      if (!is.character(config$project) || length(config$project) != 1L) {
        stop("_quarto.yml: inline project mappings cannot be updated safely; use a project block.", call. = FALSE)
      }
      lines[bounds[["start"]]] <- "project:"
      lines <- append(lines, paste0("  type: ", inline), after = bounds[["start"]])
    }
  }
  for (name in names(installed)) lines <- .project_hook_lines(lines, name, installed[[name]])
  writeLines(lines, temporary)
  .read_quarto_config(temporary)

  hook_files <- .provenance_hook_files()
  hook_sources <- file.path(system.file("hooks", package = "hvtiRtemplates"), basename(hook_files))
  missing_source <- !nzchar(hook_sources) | !file.exists(hook_sources)
  if (any(missing_source)) {
    stop("add_job(): installed provenance hook is missing: ",
         basename(hook_files[missing_source][[1L]]), ".", call. = FALSE)
  }
  hook_dir <- file.path(root, dirname(hook_files[[1L]]))
  hook_dir_existed <- dir.exists(hook_dir)
  targets <- c(config_path, file.path(root, hook_files))
  states <- lapply(targets, .provenance_file_state)
  backups <- rep(NA_character_, length(targets))
  mutation_started <- FALSE
  ok <- FALSE
  on.exit({
    if (ok || !mutation_started) {
      existing_backups <- backups[!is.na(backups) & file.exists(backups)]
      if (length(existing_backups)) unlink(existing_backups)
    } else {
      failures <- character()
      preserve <- rep(FALSE, length(targets))
      for (i in rev(seq_along(targets))) {
        tryCatch(
          {
            if (.provenance_file_unchanged(targets[[i]], states[[i]])) {
              if (!is.na(backups[[i]]) && file.exists(backups[[i]])) unlink(backups[[i]])
            } else {
              .restore_provenance_file(targets[[i]], states[[i]], backups[[i]])
            }
          },
          error = function(error) {
            recovery <- if (!is.na(backups[[i]]) && file.exists(backups[[i]])) {
              preserve[[i]] <<- TRUE
              paste0(" Original bytes remain at '", backups[[i]], "'.")
            } else {
              " No recovery backup is available."
            }
            failures <<- c(failures, paste0(targets[[i]], ": ", conditionMessage(error), recovery))
          }
        )
      }
      disposable <- backups[!preserve & !is.na(backups) & file.exists(backups)]
      if (length(disposable)) unlink(disposable)
      if (length(failures)) {
        warning("Provenance hook rollback could not restore: ", paste(failures, collapse = "; "), call. = FALSE)
      }
      if (!hook_dir_existed && dir.exists(hook_dir) && !length(list.files(hook_dir, all.files = TRUE, no.. = TRUE))) {
        unlink(hook_dir)
      }
    }
  }, add = TRUE)
  for (i in seq_along(targets)) {
    backups[[i]] <- .backup_provenance_file(targets[[i]], states[[i]])
  }
  mutation_started <- TRUE
  if (!dir.exists(hook_dir)) dir.create(hook_dir, recursive = TRUE)
  for (i in seq_along(hook_files)) {
    if (!.copy_provenance_file(hook_sources[[i]], file.path(root, hook_files[[i]]), overwrite = TRUE)) {
      stop("add_job(): could not install provenance hook: ", hook_files[[i]], ".", call. = FALSE)
    }
  }

  if (!.copy_provenance_file(temporary, config_path, overwrite = TRUE)) {
    stop("add_job(): could not update _quarto.yml.", call. = FALSE)
  }
  ok <- TRUE
  invisible(config_path)
}

.assert_provenance_hooks <- function(root) {
  path <- file.path(root, "_quarto.yml")
  config <- .read_quarto_config(path)
  project <- config$project
  if (!is.list(project)) {
    stop("Provenance hooks are not configured. Run add_job() in this study.", call. = FALSE)
  }
  for (which in c("pre", "post")) {
    name <- paste0(which, "-render")
    commands <- .provenance_hooks(project[[name]], name)
    command <- .provenance_hook_command(which)
    if (!length(commands) || !identical(utils::tail(commands, 1L), command)) {
      stop("Provenance ", name, " hook is missing or is not last. Run add_job() again.", call. = FALSE)
    }
  }
  missing <- .provenance_hook_files()[!file.exists(file.path(root, .provenance_hook_files()))]
  if (length(missing)) {
    stop("Provenance hook file is missing: ", missing[[1L]], ". Run add_job() again.", call. = FALSE)
  }
  invisible(TRUE)
}

.provenance_source <- function(input, root) {
  if (!is.character(input) || length(input) != 1L || is.na(input) || !nzchar(input)) {
    stop("Cannot resolve the canonical render input without one path.", call. = FALSE)
  }
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  input_path <- if (grepl("^(/|[A-Za-z]:[/\\\\])", input)) input else file.path(getwd(), input)
  input_path <- normalizePath(input_path, winslash = "/", mustWork = FALSE)
  extension <- tolower(tools::file_ext(input_path))
  if (identical(extension, "qmd") && file.exists(input_path)) {
    candidates <- input_path
  } else if (identical(extension, "rmarkdown")) {
    stem <- paste0(tools::file_path_sans_ext(basename(input_path)), ".qmd")
    adjacent <- file.path(dirname(input_path), stem)
    recursive <- list.files(root, pattern = paste0("^", .regex_escape(stem), "$"), recursive = TRUE, full.names = TRUE)
    candidates <- unique(c(adjacent[file.exists(adjacent)], recursive))
  } else {
    candidates <- character()
  }
  candidates <- unique(normalizePath(candidates, winslash = "/", mustWork = TRUE))
  if (!length(candidates)) {
    stop("Cannot resolve a canonical authored .qmd input from '", input, "'.", call. = FALSE)
  }
  if (length(candidates) != 1L) {
    stop("The render input '", input, "' is ambiguous across ", length(candidates), " authored .qmd files.", call. = FALSE)
  }
  prefix <- paste0(root, "/")
  if (!startsWith(candidates, prefix)) {
    stop("The canonical render input is outside the study root: ", candidates, ".", call. = FALSE)
  }
  substring(candidates, nchar(prefix) + 1L)
}

.regex_escape <- function(x) {
  gsub("([][{}()+*^$|\\\\.?])", "\\\\\\1", x)
}

.provenance_state_path <- function(root) {
  file.path(root, ".hvtiR", "provenance-render.json")
}

.write_json_atomic <- function(value, path) {
  if (!dir.exists(dirname(path))) dir.create(dirname(path), recursive = TRUE)
  temporary <- tempfile(pattern = paste0(".", basename(path), "-"), tmpdir = dirname(path), fileext = ".tmp")
  on.exit(if (file.exists(temporary)) unlink(temporary), add = TRUE)
  jsonlite::write_json(value, temporary, auto_unbox = TRUE, null = "null", pretty = TRUE)
  if (!file.copy(temporary, path, overwrite = TRUE)) {
    stop("Could not write render provenance state: ", path, ".", call. = FALSE)
  }
  invisible(path)
}

.read_provenance_state <- function(root) {
  path <- .provenance_state_path(root)
  if (!file.exists(path)) {
    stop("The provenance pre-render hook did not create render state. Run add_job() to install the study hooks.", call. = FALSE)
  }
  tryCatch(
    jsonlite::read_json(path, simplifyVector = FALSE),
    error = function(e) stop("The provenance render state is malformed: ", conditionMessage(e), call. = FALSE)
  )
}

.quarto_project_files <- function(name, root) {
  file_name <- sub("^QUARTO_PROJECT_", "QUARTO_USE_FILE_FOR_PROJECT_", name)
  list_path <- Sys.getenv(file_name, unset = NA_character_)
  if (!is.na(list_path) && nzchar(list_path)) {
    value <- paste(readLines(list_path, warn = FALSE), collapse = "\n")
  } else {
    value <- Sys.getenv(name, unset = NA_character_)
  }
  if (is.na(value) || !nzchar(value)) {
    stop(name, " is not set by Quarto.", call. = FALSE)
  }
  files <- strsplit(value, "\n", fixed = TRUE)[[1L]]
  files <- files[nzchar(files)]
  vapply(files, function(path) {
    if (grepl("^(/|[A-Za-z]:[/\\\\])", path)) path else file.path(root, path)
  }, character(1L), USE.NAMES = FALSE)
}

.provenance_read <- function(dataset, cfg, reader, role = "analysis") {
  if (!is.function(reader)) stop(".provenance_read(): `reader` must be a function.", call. = FALSE)
  before <- hvtiRutilities::provenance_data(dataset = dataset, cfg = cfg, role = role)
  value <- reader()
  after <- hvtiRutilities::provenance_data(dataset = dataset, cfg = cfg, role = role)
  if (!identical(before[c("bytes", "sha256")], after[c("bytes", "sha256")])) {
    stop("The registered dataset changed while it was read; discard this render and read it again.", call. = FALSE)
  }
  list(value = value, record = before)
}

.provenance_file_read <- function(dataset, path, cfg, reader, role = "analysis") {
  if (!is.function(reader)) stop(".provenance_file_read(): `reader` must be a function.", call. = FALSE)
  snapshot <- function() {
    c(list(dataset = dataset), hvtiRutilities::provenance_artifact(path = path, role = role, cfg = cfg))
  }
  before <- snapshot()
  value <- reader()
  after <- snapshot()
  if (!identical(before[c("bytes", "sha256")], after[c("bytes", "sha256")])) {
    stop("The data file changed while it was read; discard this render and read it again.", call. = FALSE)
  }
  list(value = value, record = before)
}

.handoff_lineage <- function(data, artifacts = list(), analysis = NULL,
                             cohort = NULL) {
  if (!is.list(data)) stop("Handoff lineage data must be a list of provenance records.", call. = FALSE)
  if (!is.list(artifacts)) stop("Handoff lineage artifacts must be a list of provenance records.", call. = FALSE)
  list(data = data, artifacts = artifacts, analysis = analysis, cohort = cohort)
}

.attach_handoff_lineage <- function(object, data, artifacts = list(),
                                    analysis = NULL, cohort = NULL) {
  attr(object, "hvti_provenance") <- .handoff_lineage(data, artifacts, analysis, cohort)
  object
}

.validate_handoff_lineage <- function(object, path, rebuild) {
  lineage <- attr(object, "hvti_provenance", exact = TRUE)
  required <- c("data", "artifacts", "analysis", "cohort")
  valid <- is.list(lineage) && identical(names(lineage), required) &&
    is.list(lineage$data) && is.list(lineage$artifacts)
  if (!valid) {
    stop(
      "The package handoff '", path, "' has no complete hvti_provenance lineage. ",
      "Rebuild it by rendering ", rebuild, " with the current template.",
      call. = FALSE
    )
  }
  if (!length(lineage$data)) {
    stop(
      "The package handoff '", path, "' has no source data lineage. ",
      "Rebuild it by rendering ", rebuild, " with the current template.",
      call. = FALSE
    )
  }
  lineage
}

.read_handoff <- function(path, role, cfg, rebuild) {
  before <- hvtiRutilities::provenance_artifact(path, role = role, cfg = cfg)
  value <- readRDS(path)
  after <- hvtiRutilities::provenance_artifact(path, role = role, cfg = cfg)
  if (!identical(before[c("bytes", "sha256")], after[c("bytes", "sha256")])) {
    stop("The artifact changed while it was read; discard this render and read it again.", call. = FALSE)
  }
  list(
    value = value,
    record = before,
    lineage = .validate_handoff_lineage(value, path, rebuild)
  )
}

.read_bootstrap_artifact <- function(path, role, cfg, explicit_data) {
  before <- hvtiRutilities::provenance_artifact(path, role = role, cfg = cfg)
  value <- readRDS(path)
  after <- hvtiRutilities::provenance_artifact(path, role = role, cfg = cfg)
  if (!identical(before[c("bytes", "sha256")], after[c("bytes", "sha256")])) {
    stop("The bootstrap artifact changed while it was read; discard this render and read it again.", call. = FALSE)
  }
  lineage <- attr(value, "hvti_provenance", exact = TRUE)
  missing_data <- is.null(lineage) ||
    (is.list(lineage) && is.list(lineage$data) && !length(lineage$data))
  if (missing_data) {
    if (!is.list(explicit_data) || !length(explicit_data)) {
      stop(
        "This bootstrap artifact has no carried lineage. Re-run its producer with hvti_provenance lineage, ",
        "or supply the original provenance_data() records explicitly in BOOTSTRAP_DATA.",
        call. = FALSE
      )
    }
    complete_shape <- is.list(lineage) &&
      identical(names(lineage), c("data", "artifacts", "analysis", "cohort")) &&
      is.list(lineage$data) && is.list(lineage$artifacts)
    if (is.null(lineage)) {
      lineage <- .handoff_lineage(explicit_data)
    } else if (complete_shape) {
      lineage <- .handoff_lineage(
        explicit_data, lineage$artifacts, lineage$analysis, lineage$cohort
      )
    } else {
      .validate_handoff_lineage(value, path, "the bootstrap producer")
    }
    attr(value, "hvti_provenance") <- lineage
    lineage <- .validate_handoff_lineage(value, path, "the bootstrap producer")
  } else {
    lineage <- .validate_handoff_lineage(value, path, "the bootstrap producer")
  }
  list(value = value, record = before, lineage = lineage)
}

.combine_handoff_lineage <- function(lineages = list(), data = list(),
                                     artifacts = list(), analysis = NULL,
                                     cohort = NULL) {
  carried_data <- unlist(lapply(lineages, `[[`, "data"), recursive = FALSE)
  carried_artifacts <- unlist(lapply(lineages, `[[`, "artifacts"), recursive = FALSE)
  common <- function(field) {
    values <- lapply(lineages, `[[`, field)
    values <- values[!vapply(values, is.null, logical(1L))]
    if (!length(values)) return(NULL)
    if (!all(vapply(values[-1L], identical, logical(1L), values[[1L]]))) {
      stop("Input handoffs disagree on their ", field, " lineage.", call. = FALSE)
    }
    values[[1L]]
  }
  if (is.null(analysis)) analysis <- common("analysis")
  if (is.null(cohort)) cohort <- common("cohort")
  .handoff_lineage(
    data = c(carried_data, data),
    artifacts = c(carried_artifacts, artifacts),
    analysis = analysis,
    cohort = cohort
  )
}

.provenance_source_frozen <- function(path) {
  if (!requireNamespace("quarto", quietly = TRUE)) {
    stop("The quarto R package is required to resolve frozen execution metadata.", call. = FALSE)
  }
  profile <- Sys.getenv("QUARTO_PROFILE", unset = NA_character_)
  metadata <- quarto::quarto_inspect(
    path,
    profile = if (is.na(profile) || !nzchar(profile)) NULL else strsplit(profile, ",", fixed = TRUE)[[1L]],
    quiet = TRUE
  )
  any(vapply(metadata$formats, function(format) {
    isTRUE(format$execute$freeze) || identical(format$execute$freeze, "auto")
  }, logical(1L)))
}

.provenance_html <- function(payload) {
  json <- jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null", digits = NA)
  json <- gsub("&", paste0("\\", "u0026"), json, fixed = TRUE)
  json <- gsub("<", paste0("\\", "u003c"), json, fixed = TRUE)
  json <- gsub(">", paste0("\\", "u003e"), json, fixed = TRUE)
  paste0(
    "<!-- hvti-provenance-managed -->\n",
    '<script type="application/json" id="hvti-provenance">', json, "</script>"
  )
}

.extract_provenance <- function(html, managed = grepl("<!-- hvti-provenance-managed -->", html, fixed = TRUE)) {
  opener <- '<script type="application/json" id="hvti-provenance">'
  starts <- gregexpr(opener, html, fixed = TRUE)[[1L]]
  if (length(starts) == 1L && starts[[1L]] == -1L) {
    if (managed) stop("Managed HTML is missing its provenance payload.", call. = FALSE)
    return(NULL)
  }
  if (length(starts) != 1L) stop("Managed HTML must contain exactly one provenance payload.", call. = FALSE)
  start <- starts[[1L]] + nchar(opener)
  remainder <- substring(html, start)
  close <- regexpr("</script>", remainder, fixed = TRUE)[[1L]]
  if (close < 1L) stop("Managed HTML contains a malformed provenance payload element.", call. = FALSE)
  json <- substring(remainder, 1L, close - 1L)
  tryCatch(
    jsonlite::fromJSON(json, simplifyVector = FALSE),
    error = function(e) stop("Managed HTML contains malformed provenance JSON: ", conditionMessage(e), call. = FALSE)
  )
}

.provenance_pre_render <- function(root = Sys.getenv("QUARTO_PROJECT_DIR", unset = getwd()), inputs = NULL) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  .assert_provenance_hooks(root)
  if (is.null(inputs)) inputs <- .quarto_project_files("QUARTO_PROJECT_INPUT_FILES", root)
  extensions <- tolower(tools::file_ext(inputs))
  candidates <- inputs[extensions %in% c("qmd", "rmarkdown")]
  sources <- unique(vapply(candidates, .provenance_source, character(1L), root = root))
  managed <- sources[vapply(file.path(root, sources), function(path) {
    any(grepl("hvtiRtemplates:::.embed_provenance(", readLines(path, warn = FALSE), fixed = TRUE))
  }, logical(1L))]

  sidecars <- list.files(
    root, pattern = "[.]provenance[.]json$", recursive = TRUE, full.names = TRUE, all.files = TRUE
  )
  for (sidecar in sidecars) {
    record <- tryCatch(
      jsonlite::read_json(sidecar, simplifyVector = FALSE),
      error = function(e) stop("Cannot inspect existing provenance sidecar '", sidecar, "': ", conditionMessage(e), call. = FALSE)
    )
    if (is.character(record$source) && length(record$source) == 1L && record$source %in% sources) unlink(sidecar)
  }

  state <- list(
    render_id = digest::digest(list(Sys.time(), Sys.getpid(), stats::runif(1L)), algo = "sha256"),
    managed_sources = as.list(managed),
    source_sha256 = stats::setNames(
      lapply(file.path(root, managed), digest::digest, algo = "sha256", file = TRUE),
      managed
    ),
    frozen_sources = as.list(managed[vapply(file.path(root, managed), .provenance_source_frozen, logical(1L))])
  )
  .write_json_atomic(state, .provenance_state_path(root))
  invisible(state)
}

.embed_provenance <- function(input, data, artifacts = list(), extra = list(), cfg = hvtiRutilities::study_config()) {
  root <- normalizePath(cfg$root, winslash = "/", mustWork = TRUE)
  project <- Sys.getenv("QUARTO_PROJECT_DIR", unset = NA_character_)
  if (is.na(project) || !identical(normalizePath(project, winslash = "/", mustWork = TRUE), root)) {
    stop("This managed job must be rendered through its configured Quarto study project. Run add_job() to install the hooks.",
         call. = FALSE)
  }
  .assert_provenance_hooks(root)
  source <- .provenance_source(input, root)
  state <- .read_provenance_state(root)
  managed <- unlist(state$managed_sources, use.names = FALSE)
  if (!source %in% managed) {
    stop("The provenance pre-render hook did not register this managed source: ", source, ".", call. = FALSE)
  }
  if (any(c("source", ".hvti_render_id", ".hvti_source_sha256") %in% names(extra))) {
    stop("Template provenance extras may not replace the source or render identity.", call. = FALSE)
  }
  payload <- hvtiRutilities::capture_provenance(
    job = tools::file_path_sans_ext(basename(source)),
    data = data,
    artifacts = artifacts,
    extra = c(extra, list(
      source = source,
      .hvti_render_id = state$render_id,
      .hvti_source_sha256 = state$source_sha256[[source]]
    )),
    cfg = cfg
  )
  .provenance_html(payload)
}

.provenance_post_render <- function(root = Sys.getenv("QUARTO_PROJECT_DIR", unset = getwd()), outputs = NULL) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  state_path <- .provenance_state_path(root)
  state <- .read_provenance_state(root)
  on.exit(if (file.exists(state_path)) unlink(state_path), add = TRUE)
  if (is.null(outputs)) outputs <- .quarto_project_files("QUARTO_PROJECT_OUTPUT_FILES", root)
  outputs <- outputs[tolower(tools::file_ext(outputs)) %in% c("html", "htm")]
  expected <- unlist(state$managed_sources, use.names = FALSE)
  seen <- character()
  published <- character()
  ok <- FALSE
  on.exit(if (!ok && length(published)) unlink(published), add = TRUE)

  for (output in outputs) {
    html <- paste(readLines(output, warn = FALSE), collapse = "\n")
    managed <- grepl("<!-- hvti-provenance-managed -->", html, fixed = TRUE)
    payload <- .extract_provenance(html, managed = managed)
    if (is.null(payload)) next
    if (!is.character(payload$source) || length(payload$source) != 1L || !payload$source %in% expected) {
      stop("Managed HTML carries a provenance source not registered for this render.", call. = FALSE)
    }
    frozen <- payload$source %in% unlist(state$frozen_sources, use.names = FALSE) &&
      identical(payload$.hvti_source_sha256, state$source_sha256[[payload$source]])
    if (!identical(payload$.hvti_render_id, state$render_id) && !frozen) {
      stop("Managed HTML carries a stale provenance payload from another render.", call. = FALSE)
    }
    if (payload$source %in% seen) stop("A managed source produced more than one provenance payload.", call. = FALSE)
    seen <- c(seen, payload$source)
    payload$.hvti_render_id <- NULL
    payload$.hvti_source_sha256 <- NULL
    hvtiRutilities::publish_provenance(output, payload)
    published <- c(published, hvtiRutilities::provenance_path(output))
  }
  missing <- setdiff(expected, seen)
  if (length(missing)) {
    stop("Managed output is missing a current provenance payload for source: ", missing[[1L]], ".", call. = FALSE)
  }
  ok <- TRUE
  invisible(published)
}
