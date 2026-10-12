# What a report says about the run that made it: the one-line box .job_setup()
# prints under the title, and the "About this run" table the last chunk draws.
# The design is dev/specs/2026-10-12-setup-and-run-info-design.md, section 4.
#
# Every value comes from what the job already records (read_job_data()'s read,
# the manifest entry, the handoff lineage, .provenance_data) or from the run
# itself (start, end, user, host, seed, renv). No patient identifier and no data
# value is in it: names, dates, counts and hashes only.

# The run's own ledger, which a new .job_setup() clears: what read_job_data()
# read, and what each upstream handoff said it was built from. Package state
# rather than variables in the job, because the job's names for a read differ
# from one template to the next (job_data, .up, ...), and a ledger that depended
# on them would need an edit in every template.
.run_state <- new.env(parent = emptyenv())
.run_state$reads <- list()
.run_state$handoffs <- list()

# Who ran the render, and on which machine. HVTI_RUN_USER and HVTI_RUN_HOST
# replace the two, for a report that is published and should not carry a real
# username (the gallery sets both). Quarto starts the render in a process of its
# own, which inherits environment variables and not options().
.run_identity <- function() {
  info <- Sys.info()
  pick <- function(variable, field) {
    set <- Sys.getenv(variable)
    if (nzchar(set)) set else if (is.null(info)) NA_character_ else unname(info[[field]])
  }
  list(user = pick("HVTI_RUN_USER", "user"), host = pick("HVTI_RUN_HOST", "nodename"))
}

.package_version <- function() as.character(utils::packageVersion("hvtiRtemplates"))

# Quarto knits through an intermediate (.rmarkdown), so the name is put back to .qmd.
.job_file_name <- function(input) {
  if (is.null(input)) NULL else sub("[.][^.]+$", ".qmd", basename(input))
}

# The run record .job_setup() starts: what is known at the top of the render.
# A job is a draft while an EDIT: marker, a skipped chunk or a stop_here() is
# open; the guards have just counted them.
.run_begin <- function(started, input, subject, type, markers) {
  kinds <- vapply(.partial_state$points, function(p) p$kind, "")
  who <- .run_identity()
  list(
    started = started, file = .job_file_name(input), subject = subject, type = type,
    user = who$user, host = who$host,
    markers = as.integer(markers), skipped = sum(kinds == "skip"), stopped = any(kinds == "stop"),
    state = if (markers > 0L || length(kinds) > 0L) "draft" else "final"
  )
}

.n_of <- function(n, noun) paste(n, if (n == 1L) noun else paste0(noun, "s"))

.open_summary <- function(run) {
  paste(c(if (run$markers > 0L) .n_of(run$markers, "open marker"),
          if (run$skipped > 0L) .n_of(run$skipped, "skipped chunk"),
          if (run$stopped) "the render stops early"), collapse = ", ")
}

# Markdown for a value that is not ours: a user or host name, a file name.
.md_text <- function(x) gsub("([\\\\`*_<>|])", "\\\\\\1", x)

# ---- The registered version a report names -----------------------------------

.manifest_entries <- function(root) {
  path <- file.path(root, "manifest.yaml")
  if (!file.exists(path)) return(list())
  Filter(is.list, yaml::read_yaml(path)$datasets)
}

# The manifest record of a dated version file, or of the dataset registered from
# a source file: its source file, version file and extract (registration) date.
# An earlier version is found in the entry's history.
.manifest_find <- function(root, version = NULL, source = NULL) {
  for (entry in .manifest_entries(root)) {
    records <- c(list(entry), if (is.list(entry$history)) entry$history else list())
    for (record in records) {
      hit <- if (!is.null(version)) identical(record$parquet, version) else identical(entry$file, source)
      if (hit) {
        return(list(source_file = entry$file, version_file = record$parquet, registered = record$extract_date))
      }
    }
  }
  NULL
}

# The dataset the job reads, for the box, which is printed before the data are.
# The job declares DATASET in its study choices, after the setup chunk, so the
# declaration is read from the job's own file: a literal DATASET <- "name" wins,
# and anything else (NULL, an expression, no declaration) is the study's dataset,
# "built". The end table is the record of what was actually read; the box is
# the manifest's word for it at the top. A study with no registered dataset gets
# a box without the clause, not an error.
.box_dataset <- function(root, input) {
  name <- "built"
  if (!is.null(input) && file.exists(input)) {
    src <- readLines(input, warn = FALSE)
    hit <- regmatches(src, regexec("^DATASET\\s*<-\\s*\"([^\"]+)\"", src))
    hit <- Filter(length, hit)
    if (length(hit)) name <- hit[[1L]][[2L]]
  }
  found <- tryCatch({
    cfg <- hvtiRutilities::study_config(start = root)
    .manifest_find(root, source = basename(hvtiRutilities::built_path(cfg, name)))
  }, error = function(e) NULL)
  c(list(name = name), found)
}

# ---- The top box -------------------------------------------------------------

.run_box <- function(run, dataset = NULL) {
  state <- if (identical(run$state, "draft")) paste0("**draft** (", .open_summary(run), ")") else "**final**"
  data <- if (!is.null(dataset) && !is.null(dataset$version_file)) {
    paste0("data `", dataset$name, "` `", dataset$version_file, "`",
           if (!is.null(dataset$registered)) paste0(", registered ", dataset$registered))
  }
  who <- paste0("rendered by ", .md_text(run$user), " on ", .md_text(run$host))
  line <- paste(c(state, data, who, paste0("hvtiRtemplates ", .package_version())), collapse = " · ")
  paste0("\n::: {.callout-note appearance=\"simple\" icon=false}\n", line, "\n:::\n\n")
}

# ---- What read_job_data() and the handoff readers leave in the ledger --------

# One dataset read, summarized: the counts kept, the conditions as a report may
# show them (never the exact text, which holds values), and whether the source
# was rebuilt since it was registered.
.note_job_read <- function(provenance, selection, notes, join = NULL) {
  add <- function(entry) .run_state$reads[[length(.run_state$reads) + 1L]] <- entry
  add(list(dataset = provenance$dataset, sha256 = provenance$sha256,
           rows = as.integer(selection$rows), patients = as.integer(selection$patients),
           where = as.character(selection$where_shown),
           newer = any(grepl("update_manifest", notes, fixed = TRUE))))
  if (!is.null(join$provenance)) {
    add(list(dataset = join$provenance$dataset, sha256 = join$provenance$sha256,
             rows = as.integer(join$summary$rows), patients = NULL, where = NULL, newer = FALSE))
  }
  invisible(NULL)
}

# The dated data versions an upstream handoff was built from.
.note_handoff <- function(record, lineage) {
  versions <- vapply(lineage$data, function(r) if (is.character(r$path)) basename(r$path) else NA_character_, "")
  .run_state$handoffs[[length(.run_state$handoffs) + 1L]] <- list(
    sha256 = record$sha256, versions = unique(versions[!is.na(versions)])
  )
  invisible(NULL)
}

# ---- The facts ---------------------------------------------------------------

.iso_time <- function(t) format(t, "%Y-%m-%dT%H:%M:%S%z")

.facts_run <- function(run, ended) {
  Filter(Negate(is.null), list(
    start = .iso_time(run$started), end = .iso_time(ended), time_zone = format(ended, "%Z"),
    duration_seconds = round(as.numeric(difftime(ended, run$started, units = "secs")), 1),
    status = run$state, open_markers = run$markers, skipped_chunks = run$skipped,
    stopped_early = run$stopped, user = run$user, host = run$host
  ))
}

.facts_job <- function(run) {
  parts <- if (is.null(run$file)) character(0) else .job_name_template(run$file)
  qualifier <- if (length(parts) && !is.na(parts[["qualifier"]])) parts[["qualifier"]]
  Filter(Negate(is.null), list(
    file = run$file,
    template = if (length(parts)) paste(c(parts[["prefix"]], qualifier), collapse = "."),
    prefix = if (length(parts)) parts[["prefix"]], qualifier = qualifier,
    subject = run$subject, type = run$type, hvtiRtemplates = .package_version()
  ))
}

.facts_datasets <- function(data, cfg) {
  seen <- character(0)
  out <- list()
  for (record in data) {
    key <- paste(record$dataset, record$sha256)
    if (key %in% seen) next
    seen <- c(seen, key)
    reads <- Filter(function(r) identical(r$dataset, record$dataset) && identical(r$sha256, record$sha256),
                    .run_state$reads)
    read <- if (length(reads)) reads[[length(reads)]]
    version <- if (is.character(record$path)) basename(record$path)
    found <- if (!is.null(version)) .manifest_find(cfg$root, version = version)
    out[[length(out) + 1L]] <- Filter(Negate(is.null), list(
      name = if (identical(record$dataset, "study")) "built" else record$dataset,
      version_file = version, registered = found$registered, source_file = found$source_file,
      rows = read$rows, patients = read$patients, where = read$where,
      sha256 = if (is.character(record$sha256)) substr(record$sha256, 1L, 12L),
      manifest = if (is.null(found)) "not in the manifest" else if (isTRUE(read$newer)) "newer file waiting" else "current"
    ))
  }
  out
}

.facts_upstream <- function(artifacts) {
  seen <- character(0)
  out <- list()
  for (record in artifacts) {
    key <- paste(record$path, record$sha256)
    if (key %in% seen) next
    seen <- c(seen, key)
    state <- Filter(function(h) identical(h$sha256, record$sha256), .run_state$handoffs)
    versions <- if (length(state)) state[[length(state)]]$versions
    out[[length(out) + 1L]] <- Filter(Negate(is.null), list(
      file = record$path, set = basename(dirname(record$path)), role = record$role, saved = record$mtime,
      dataset_version = if (length(versions)) paste(versions, collapse = ", ")
    ))
  }
  out
}

# The seed when the job sets SEED; renv active or not, and the lockfile's hash.
# renv is active when its project is the session's, or its library is on the path.
.facts_reproducibility <- function(cfg, envir) {
  seed <- get0("SEED", envir = envir, inherits = FALSE)
  seed <- if (length(seed) == 1L && !is.na(seed) && (is.numeric(seed) || is.character(seed))) {
    if (is.numeric(seed)) format(seed, scientific = FALSE, trim = TRUE) else seed
  }
  lock <- file.path(cfg$root, "renv.lock")
  active <- nzchar(Sys.getenv("RENV_PROJECT")) || any(grepl("[/\\\\]renv[/\\\\]library[/\\\\]", .libPaths()))
  Filter(Negate(is.null), list(
    seed = seed,
    renv = Filter(Negate(is.null), list(
      active = active,
      lock_sha256 = if (file.exists(lock)) substr(digest::digest(lock, algo = "sha256", file = TRUE), 1L, 12L)
    ))
  ))
}

# Everything the end table and the provenance's `run` hold, in one list: the
# run's own fields, then the job, the datasets, the upstream handoffs and what
# reproduces it.
.run_facts <- function(run, data = list(), artifacts = list(), cfg = hvtiRutilities::study_config(),
                       envir = parent.frame()) {
  c(.facts_run(run, Sys.time()), list(
    job = .facts_job(run),
    datasets = .facts_datasets(data, cfg),
    upstream = .facts_upstream(artifacts),
    reproducibility = .facts_reproducibility(cfg, envir)
  ))
}

# ---- The end table -----------------------------------------------------------

# The table alone, for a job with no provenance chunk to carry it (bd builds a
# dataset and embeds no provenance).
.about_run <- function(run, data = list(), artifacts = list(), cfg = hvtiRutilities::study_config(),
                       envir = parent.frame()) {
  paste(.run_table(.run_facts(run, data, artifacts, cfg, envir)), collapse = "\n")
}

.fmt_duration <- function(seconds) {
  s <- round(seconds)
  if (s < 60) return(paste(s, "s"))
  if (s < 3600) return(paste(s %/% 60, "min", s %% 60, "s"))
  paste(s %/% 3600, "h", (s %% 3600) %/% 60, "min")
}

.clock <- function(iso, zone) paste(sub("T", " ", substr(iso, 1L, 19L), fixed = TRUE), zone)

# A time the provenance records, in UTC with a trailing Z, read as a person reads one.
.clock_utc <- function(iso) sub("Z$", " UTC", sub("T", " ", iso, fixed = TRUE))

# At most this many upstream handoffs get a row; a bootstrap bag reads hundreds
# of chunk files, and the provenance JSON lists them all.
.upstream_rows <- 12L

# The "About this run" section: a heading that Quarto does not number, and a
# table of group, item and value.
.run_table <- function(facts) {
  # Rows for one group; the group is named on its first row. An item with no
  # value is left out, so a field the run did not have is not shown.
  group_rows <- function(group, items) {
    items <- Filter(function(i) length(i) == 2L, items)
    lapply(seq_along(items), function(k) c(if (k == 1L) group else "", items[[k]]))
  }
  status <- if (identical(facts$status, "draft")) {
    open <- list(markers = facts$open_markers, skipped = facts$skipped_chunks, stopped = isTRUE(facts$stopped_early))
    paste0("draft (", .open_summary(open), ")")
  } else {
    "final"
  }
  j <- facts$job
  rows <- c(
    group_rows("Run", list(c("Started", .clock(facts$start, facts$time_zone)), c("Ended", .clock(facts$end, facts$time_zone)),
                           c("Duration", .fmt_duration(facts$duration_seconds)), c("Status", status),
                           c("Rendered by", facts$user), c("Host", facts$host))),
    group_rows("Job", list(c("File", j$file), c("Template", j$template), c("Subject", j$subject), c("Type", j$type),
                           c("hvtiRtemplates", j$hvtiRtemplates))),
    unlist(lapply(facts$datasets, function(d) {
      group_rows(paste0("Dataset `", d$name, "`"), list(
        c("Version file", d$version_file), c("Registered", d$registered), c("Source file", d$source_file),
        c("Rows kept", if (!is.null(d$rows)) {
          paste0(format(d$rows, big.mark = ","), " rows on ", format(d$patients, big.mark = ","), " patients")
        }),
        c("WHERE", if (!is.null(d$rows)) {
          if (length(d$where)) paste0("`", d$where, "`", collapse = "; ") else "none"
        }),
        c("sha256", d$sha256), c("Manifest", d$manifest)
      ))
    }), recursive = FALSE),
    group_rows("Upstream", c(
      lapply(utils::head(facts$upstream, .upstream_rows), function(u) {
        c("Handoff", paste0("`", u$set, "/", basename(u$file), "`", if (!is.null(u$role)) paste0(" (", u$role, ")"),
                            if (!is.null(u$saved)) paste0(", saved ", .clock_utc(u$saved)),
                            if (!is.null(u$dataset_version)) paste0(", data ", u$dataset_version)))
      }),
      if (length(facts$upstream) > .upstream_rows) {
        list(c("", paste(length(facts$upstream) - .upstream_rows, "more, listed in the provenance")))
      }
    )),
    group_rows("Reproducibility", list(
      c("Seed", facts$reproducibility$seed),
      c("renv", if (isTRUE(facts$reproducibility$renv$active)) "active" else "not active"),
      c("renv.lock sha256", facts$reproducibility$renv$lock_sha256)
    ))
  )
  cell <- function(x) gsub("|", "\\|", if (is.null(x) || is.na(x)) "" else x, fixed = TRUE)
  body <- vapply(rows, function(row) paste0("| ", paste(vapply(row, cell, ""), collapse = " | "), " |"), "")
  c("", "## About this run {.unnumbered}", "", "| Group | Item | Value |", "|:--|:--|:--|", body, "")
}
