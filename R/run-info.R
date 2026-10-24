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
.run_state$draft_reasons <- character()

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

# The name a report shows beside a login, from the group's people file:
#   people:
#     <login>: <First Last>
# HVTI_PEOPLE names the file, and the shared one on the server is read when it
# is unset. The names live there, never in this package. A login the file lacks,
# or no file, gives NULL and the report shows the login alone; a file that
# cannot be read warns, because a render should not stop for a display name.
.people_file <- "/studies/general/administrative/hvti_people.yml"
.person_name <- function(user) {
  if (length(user) != 1L || is.na(user) || !nzchar(user)) return(NULL)
  path <- Sys.getenv("HVTI_PEOPLE", .people_file)
  if (!nzchar(path) || !file.exists(path)) return(NULL)
  people <- tryCatch(yaml::read_yaml(path)$people, error = function(e) {
    warning("The people file ", path, " could not be read, so the report shows the login: ",
            conditionMessage(e), call. = FALSE)
    NULL
  })
  if (!is.list(people) || is.null(names(people))) return(NULL)
  name <- people[[match(tolower(user), tolower(names(people)))[1L]]]
  if (is.character(name) && length(name) == 1L && !is.na(name) && nzchar(name)) name else NULL
}

# "First Last (login)" when the people file names the login, else the login.
.who <- function(user, name) if (is.null(name)) user else paste0(name, " (", user, ")")

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
    user = who$user, user_name = .person_name(who$user), host = who$host,
    markers = as.integer(markers), skipped = sum(kinds == "skip"), stopped = any(kinds == "stop"),
    state = if (markers > 0L || length(kinds) > 0L) "draft" else "final"
  )
}

# The run record as it stands when the facts are emitted. .run_begin() counted the
# skipped chunks and stops the source scan could see, and the box printed that. A
# stop_here() the scan cannot see, inside an if () or given an argument, adds its
# stop to .partial_state$points only when it runs, so the setup-time record can
# say "final" over a report that ended early. The points are read again here, and
# any stop or skip makes the run a draft that stopped early. The setup record is
# returned edited, not changed: it is what the box printed.
#
# A template that finds at run time that its report is a draft (a scale not
# chosen, a pool incomplete) says so with .run_mark_draft(), the one path a
# runtime stop_here() takes too. Those reasons are read here as well.
.run_reconcile <- function(run) {
  kinds <- vapply(.partial_state$points, function(p) p$kind, "")
  run$skipped <- max(run$skipped, sum(kinds == "skip"))
  run$stopped <- run$stopped || any(kinds == "stop")
  run$reasons <- .run_state$draft_reasons
  if (run$markers > 0L || run$skipped > 0L || run$stopped || length(run$reasons)) run$state <- "draft"
  run
}

# Called by a template, or by stop_here(), when the report turns out to be a
# draft after the box under the title said otherwise. The box was printed at the
# start, before the data were read, so it cannot be taken back. The report says
# so where it can: the "About this run" table at the end opens with a notice
# naming each reason, and its status and the run facts read draft.
.run_mark_draft <- function(reason) {
  .run_state$draft_reasons <- unique(c(.run_state$draft_reasons, reason))
  invisible(NULL)
}

.n_of <- function(n, noun) paste(n, if (n == 1L) noun else paste0(noun, "s"))

.open_summary <- function(run) {
  paste(c(if (run$markers > 0L) .n_of(run$markers, "open marker"),
          if (run$skipped > 0L) .n_of(run$skipped, "skipped chunk"),
          if (run$stopped) "the render stops early", unlist(run$reasons)), collapse = ", ")
}

# A value in a Markdown code span. The fence is one backtick longer than the
# longest run inside, so a name such as `age at op` does not end the span, and
# the text is padded with a space when it begins or ends with a backtick.
.code_span <- function(x) {
  runs <- regmatches(x, gregexpr("`+", x))[[1L]]
  fence <- strrep("`", max(c(0L, nchar(runs))) + 1L)
  pad <- if (grepl("^`|`$", x)) " " else ""
  paste0(fence, pad, x, pad, fence)
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

# What a job's file declares for one of its study choices, when the declaration
# settles it: the quoted string of `NAME <- "x"` or `NAME <- 'x'`; NA when the
# value is NULL (nothing chosen); and NULL when it cannot be known from the file,
# which is no declaration, a second one, or anything but a literal (an upstream
# value, a call, a name). Only an assignment at the start of a line counts, as in
# the template's study choices.
.declared_literal <- function(src, name, absent = NULL) {
  hits <- grep(paste0("^", name, "\\s*<-"), src, value = TRUE)
  if (!length(hits)) return(absent)
  if (length(hits) > 1L) return(NULL)
  value <- sub(paste0("^", name, "\\s*<-\\s*"), "", hits)
  value <- sub("\\s*(#.*)?$", "", value)
  if (identical(value, "NULL")) return(NA_character_)
  quoted <- regmatches(value, regexec("^(?:\"([^\"]+)\"|'([^']+)')$", value, perl = TRUE))[[1L]]
  if (!length(quoted)) return(NULL)
  quoted[[if (nzchar(quoted[[2L]])) 2L else 3L]]
}

# The data the job reads, for the box, which is printed before the data are read.
# The job declares DATASET and ANALYSIS_SET in its study choices, after the setup
# chunk, so the declarations are read from the job's own file. The box names data
# ONLY when the file settles it: a literal ANALYSIS_SET (an analysis set of the
# study dataset, named with the time it was written when its sidecar says), else
# a literal DATASET. A value that is NULL, inherited from an upstream handoff,
# computed or not declared is unresolved, and the box never guesses "built" for
# it: the end table is the record of what was actually read, and the box sends the
# reader there. Returns NULL when unresolved. A study with no registered dataset
# gets the name without a version, not an error.
.box_dataset <- function(root, input) {
  if (is.null(input) || !file.exists(input)) return(NULL)
  src <- readLines(input, warn = FALSE)
  set <- .declared_literal(src, "ANALYSIS_SET", absent = NA_character_)
  dataset <- .declared_literal(src, "DATASET")
  # An ANALYSIS_SET the file does not settle leaves the data unknown, whatever DATASET says.
  if (is.null(set)) return(NULL)
  if (!is.na(set)) {
    datasets <- hvtiRutilities::study_dir("datasets", root)
    parquet <- paste0(set, ".parquet")
    sidecar <- file.path(datasets, paste0(set, ".set.yml"))
    written <- if (file.exists(sidecar)) {
      tryCatch(substr(yaml::read_yaml(sidecar)$written, 1L, 10L), error = function(e) NULL)
    }
    return(list(name = set, kind = "analysis set", how = "written", registered = written,
                version_file = if (file.exists(file.path(datasets, parquet))) parquet))
  }
  if (is.null(dataset) || is.na(dataset)) return(NULL)
  found <- tryCatch({
    cfg <- hvtiRutilities::study_config(start = root)
    .manifest_find(root, source = basename(hvtiRutilities::built_path(cfg, dataset)))
  }, error = function(e) NULL)
  c(list(name = dataset, kind = "data", how = "registered"), found)
}

# ---- The top box -------------------------------------------------------------

.run_box <- function(run, dataset = NULL, data_clause = TRUE) {
  state <- if (identical(run$state, "draft")) paste0("**draft** (", .open_summary(run), ")") else "**final**"
  data <- if (!data_clause) {
    NULL
  } else if (is.null(dataset)) {
    "data: see About this run"
  } else {
    paste0(dataset$kind, " `", dataset$name, "`", if (!is.null(dataset$version_file)) paste0(" `", dataset$version_file, "`"),
           if (!is.null(dataset$registered)) paste0(", ", dataset$how, " ", dataset$registered))
  }
  who <- paste0("rendered by ", .md_text(.who(run$user, run$user_name)), " on ", .md_text(run$host))
  line <- paste(c(state, data, who, paste0("hvtiRtemplates ", .package_version())), collapse = " \u00b7 ")
  paste0("\n::: {.callout-note appearance=\"simple\" icon=false}\n", line, "\n:::\n\n")
}

# ---- What read_job_data() and the handoff readers leave in the ledger --------

# One dataset read, summarized: the counts kept, the conditions as a report may
# show them (never the exact text, which holds values), and whether the source
# was rebuilt since it was registered. `notes` are the cohort source's own, and
# the joined source's are in `join$notes`: each source's freshness is its own.
#
# `selection_id` tells two reads apart by the whole selection, raw WHERE
# included, and is a hash: the report shows a WHERE with its values masked, and
# two conditions such as `age >= 30` and `age >= 70` mask to the same text.
# Used to count a read once; never shown, and never saved with the facts.
.note_job_read <- function(provenance, selection, notes, join = NULL) {
  add <- function(entry) .run_state$reads[[length(.run_state$reads) + 1L]] <- entry
  newer <- function(x) any(grepl("update_manifest", x, fixed = TRUE))
  id <- digest::digest(selection)
  add(list(dataset = provenance$dataset, sha256 = provenance$sha256, selection_id = id,
           rows = as.integer(selection$rows), patients = as.integer(selection$patients),
           where = as.character(selection$where_shown), newer = newer(notes)))
  if (!is.null(join$provenance)) {
    add(list(dataset = join$provenance$dataset, sha256 = join$provenance$sha256, selection_id = paste0(id, "-join"),
             rows = as.integer(join$summary$rows), patients = NULL, where = NULL, newer = newer(join$notes)))
  }
  invisible(NULL)
}

# The dated data versions an upstream handoff was built from, and when the job
# that saved it rendered, if the bundle says (one saved before that was recorded
# does not).
.note_handoff <- function(record, lineage) {
  versions <- vapply(lineage$data, function(r) if (is.character(r$path)) basename(r$path) else NA_character_, "")
  .run_state$handoffs[[length(.run_state$handoffs) + 1L]] <- list(
    sha256 = record$sha256, versions = unique(versions[!is.na(versions)]), rendered_at = lineage$rendered_at
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
    stopped_early = run$stopped, draft_reasons = if (length(run$reasons)) as.list(run$reasons),
    user = run$user, user_name = run$user_name, host = run$host
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

# One entry for each dataset version the job read, and for each distinct WHERE
# it read it under: the data records say which versions, and the ledger says
# what was kept from them.
.facts_datasets <- function(data, cfg) {
  seen <- character(0)
  out <- list()
  for (record in data) {
    key <- paste(record$dataset, record$sha256)
    if (key %in% seen) next
    seen <- c(seen, key)
    reads <- Filter(function(r) identical(r$dataset, record$dataset) && identical(r$sha256, record$sha256),
                    .run_state$reads)
    # By the selection read, not by the WHERE text shown, which hides values. A
    # newer file seen on any read of it counts.
    ids <- vapply(reads, `[[`, "", "selection_id")
    newer <- vapply(split(vapply(reads, function(r) isTRUE(r$newer), NA), ids), any, NA)
    reads <- lapply(reads[!duplicated(ids)], function(r) replace(r, "newer", newer[[r$selection_id]]))
    version <- if (is.character(record$path)) basename(record$path)
    found <- if (!is.null(version)) .manifest_find(cfg$root, version = version)
    for (read in if (length(reads)) reads else list(NULL)) {
      out[[length(out) + 1L]] <- Filter(Negate(is.null), list(
        name = if (identical(record$dataset, "study")) "built" else record$dataset,
        version_file = version, registered = found$registered, source_file = found$source_file,
        rows = read$rows, patients = read$patients, where = read$where,
        sha256 = if (is.character(record$sha256)) substr(record$sha256, 1L, 12L),
        manifest = if (is.null(found)) "not in the manifest" else if (isTRUE(read$newer)) "newer file waiting" else "current"
      ))
    }
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
    # When the upstream job rendered is what its bundle recorded, and absent from a
    # bundle saved before that was recorded. The file's modification time is not a
    # substitute: it changes on a copy or a touch.
    rendered <- if (length(state)) state[[length(state)]]$rendered_at
    out[[length(out) + 1L]] <- Filter(Negate(is.null), list(
      file = record$path, set = basename(dirname(record$path)), role = record$role, rendered_at = rendered,
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
  c(.facts_run(.run_reconcile(run), Sys.time()), list(
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

# A time recorded as ISO 8601 with its offset (.iso_time()), read as a person reads one.
.clock_offset <- function(iso) paste(sub("T", " ", substr(iso, 1L, 19L), fixed = TRUE), substring(iso, 20L))

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
    open <- list(markers = facts$open_markers, skipped = facts$skipped_chunks,
                 stopped = isTRUE(facts$stopped_early), reasons = facts$draft_reasons)
    paste0("draft (", .open_summary(open), ")")
  } else {
    "final"
  }
  j <- facts$job
  rows <- c(
    group_rows("Run", list(c("Started", .clock(facts$start, facts$time_zone)), c("Ended", .clock(facts$end, facts$time_zone)),
                           c("Duration", .fmt_duration(facts$duration_seconds)), c("Status", status),
                           c("Rendered by", .who(facts$user, facts$user_name)), c("Host", facts$host))),
    group_rows("Job", list(c("File", j$file), c("Template", j$template), c("Subject", j$subject), c("Type", j$type),
                           c("hvtiRtemplates", j$hvtiRtemplates))),
    unlist(lapply(facts$datasets, function(d) {
      group_rows(paste0("Dataset `", d$name, "`"), list(
        c("Version file", d$version_file), c("Registered", d$registered), c("Source file", d$source_file),
        c("Rows kept", if (!is.null(d$rows)) {
          # A joined source has rows and no patient count of its own.
          paste0(format(d$rows, big.mark = ","), " rows",
                 if (!is.null(d$patients)) paste0(" on ", format(d$patients, big.mark = ","), " patients"))
        }),
        # The cohort's conditions; a joined source has none of its own to show.
        c("WHERE", if (!is.null(d$rows) && !is.null(d$where)) {
          if (length(d$where)) paste(vapply(d$where, .code_span, ""), collapse = "; ") else "none"
        }),
        c("sha256", d$sha256), c("Manifest", d$manifest)
      ))
    }), recursive = FALSE),
    group_rows("Upstream", c(
      lapply(utils::head(facts$upstream, .upstream_rows), function(u) {
        c("Handoff", paste0("`", u$set, "/", basename(u$file), "`", if (!is.null(u$role)) paste0(" (", u$role, ")"),
                            ", rendered ", if (is.null(u$rendered_at)) "not recorded" else .clock_offset(u$rendered_at),
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
  # The box under the title was printed before the run could know; a run marked a
  # draft since then says so here, where the reader has the facts in front of them.
  notice <- if (length(facts$draft_reasons)) {
    c("::: {.callout-important title=\"This run ended as a draft\"}",
      paste0("The box under the title was printed at the start of the render and cannot change. ",
             "This report was found to be a draft while it ran: ", paste(unlist(facts$draft_reasons), collapse = "; "), "."),
      ":::", "")
  }
  c("", "## About this run {.unnumbered}", "", notice, "| Group | Item | Value |", "|:--|:--|:--|", body, "")
}
