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

# Every top-level assignment in the template's chunks, `name <- value`, in
# order: a list of values, named by what they assign.
.top_assignments <- function(src, layout) {
  found <- list()
  for (k in setdiff(unique(layout$chunk), 0L)) {
    for (e in as.list(parse(text = src[layout$chunk == k], keep.source = FALSE))) {
      if (is.call(e) && isTRUE(.call_name(e) %in% c("<-", "=")) && is.symbol(e[[2L]])) {
        found[length(found) + 1L] <- list(e[[3L]])
        names(found)[length(found)] <- as.character(e[[2L]])
      }
    }
  }
  found
}

# Top-level names bound to an estimates file, such as
# MODEL_PATH <- set_path("estimates", "lm-binary.rds"). A name bound to two
# different files, or to anything else as well, is NA: it is not one file.
.estimates_bindings <- function(assigns) {
  files <- vapply(assigns, .estimates_literal, character(1L))
  vapply(split(files, factor(names(assigns), unique(names(assigns)))),
         function(v) if (length(unique(v)) == 1L) v[[1L]] else NA_character_, character(1L))
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
  assigns <- .top_assignments(src, layout)
  datasets <- unique(vapply(assigns[names(assigns) == "DATASET"], .literal, character(1L)))
  list(name = sub("[.]qmd$", "", basename(file)), folder = basename(dirname(file)), file = file, src = src,
       layout = layout, calls = .template_calls(src, layout), bindings = .estimates_bindings(assigns),
       dataset = if (length(datasets) == 1L) datasets else NA_character_, markers = .edit_marker_lines(src))
}

# The signatures the sheet reads arguments through, so a call is read the same
# whether its arguments are named or positional.
.sheet_signatures <- list(
  saveRDS = function(object, file = "", ...) NULL,
  .read_handoff = function(path, role, cfg, rebuild) NULL,
  cache_fit = function(name, code, seed = NULL, dir = NULL, refit = FALSE, packages = NULL) NULL,
  guard_long_fit = function(name, dir, why, refit = FALSE) NULL,
  .job_setup = function(subject, type, envir = NULL, show_markers = TRUE, box_data = TRUE) NULL
)

# Argument `arg` of a call to a function in .sheet_signatures; NULL when absent.
.call_arg <- function(entry, arg) {
  matched <- tryCatch(match.call(.sheet_signatures[[entry$fn]], entry$call), error = function(e) NULL)
  if (is.null(matched)) NULL else matched[[arg]]
}

# A string literal argument, or NA: a sheet quotes only what the template states.
.literal <- function(x) if (is.character(x) && length(x) == 1L) x else NA_character_

.calls_to <- function(facts, fn) Filter(function(e) identical(e$fn, fn), facts$calls)

# The catalog's name for a row, as the template files are named.
.catalog_names <- function(catalog) {
  ifelse(is.na(catalog$qualifier), catalog$prefix, paste0(catalog$prefix, "-", catalog$qualifier))
}

# Who reads what whom saves. A template that writes saveRDS(x, <estimates file>)
# is the producer for every template whose .read_handoff() reads that file in the
# same set. A read whose path the template does not state (a model file chosen
# at an EDIT: marker, say) takes its producers from the consumer's catalog
# `upstream`, a prefix or a template's full name; one with neither is an error,
# because a sheet that silently drops a prerequisite is worse than none. A
# literal read no template writes (a companion runner's file) has route "none".
# One row per read and producer.
.handoff_graph <- function(facts, catalog = template_catalog()) {
  names <- vapply(facts, `[[`, "", "name")
  writes <- do.call(rbind, c(list(data.frame(producer = character(), file = character())), lapply(facts, function(f) {
    files <- vapply(.calls_to(f, "saveRDS"), function(e) {
      path <- .call_arg(e, "file")
      if (is.null(path)) NA_character_ else .estimates_file(path, f$bindings)
    }, character(1L))
    files <- unique(files[!is.na(files)])
    if (length(files)) data.frame(producer = f$name, file = files) else NULL
  })))
  upstream <- stats::setNames(catalog$upstream, .catalog_names(catalog))
  rows <- list()
  for (f in facts) {
    for (e in .calls_to(f, ".read_handoff")) {
      path <- .call_arg(e, "path")
      file <- if (is.null(path)) NA_character_ else .estimates_file(path, f$bindings)
      rebuild <- .literal(.call_arg(e, "rebuild"))
      if (!is.na(file)) {
        producers <- setdiff(writes$producer[writes$file == file], f$name)
        route <- if (length(producers)) "literal" else "none"
      } else {
        up <- upstream[[f$name]]
        if (!length(up)) {
          stop("Template ", f$name, " reads a hand-off whose file it does not name, and its catalog row lists ",
               "no upstream. Add the templates it reads from to `upstream` in inst/extdata/templates.json.",
               call. = FALSE)
        }
        producers <- setdiff(names[(names %in% up | sub("-.*$", "", names) %in% up) & names %in% writes$producer], f$name)
        if (!length(producers)) {
          stop("Template ", f$name, "'s catalog upstream (", toString(up), ") names no template on disk that saves ",
               "a hand-off.", call. = FALSE)
        }
        route <- "catalog"
      }
      rows[[length(rows) + 1L]] <- data.frame(consumer = f$name, producer = if (length(producers)) producers else NA,
                                              file = file, route = route, rebuild = rebuild, line = e$line)
    }
  }
  out <- do.call(rbind, c(list(data.frame(consumer = character(), producer = character(), file = character(),
                                          route = character(), rebuild = character(), line = integer())), rows))
  unique(out)
}

# ---- The wording ---------------------------------------------------------------
# Everything a sheet says is written here, in Markdown, so a snapshot shows the
# wording and one place changes it. The sheet is the outline: it says what to
# have ready, what the job walks through, how to run it and what comes next,
# and leaves what to set, and why, to the comments in the template.

.site <- "https://ehrlinger.github.io/hvtiRtemplates/articles/"

# The name add_job() takes for a template: "rfs-explain" is "rfs.explain".
.add_job_name <- function(name) sub("-", ".", name, fixed = TRUE)

.and_list <- function(x) {
  if (length(x) <= 2L) paste(x, collapse = " and ") else paste0(paste(x[-length(x)], collapse = ", "), " and ", x[length(x)])
}

.bold_list <- function(x) .and_list(paste0("**", x, "**"))

.plural <- function(n, one, many = paste0(one, "s")) paste(n, if (n == 1L) one else many)

# The heading each line belongs to: its index in `headings`, 0 above the first.
.section_of <- function(lines, headings) findInterval(lines, headings$line)

# What the code under each heading does, as notes: index 0 is above the first
# heading. Calls are placed by their chunk's first line, markers by their own.
.section_notes <- function(facts, graph) {
  h <- facts$layout$headings
  notes <- replicate(nrow(h) + 1L, character(), simplify = FALSE)
  add <- function(line, text) {
    i <- .section_of(line, h) + 1L
    if (!text %in% notes[[i]]) notes[[i]] <<- c(notes[[i]], text)
  }
  marker_sections <- table(factor(.section_of(facts$markers$line, h), levels = 0:nrow(h)))
  for (i in seq_along(notes)) {
    n <- marker_sections[[i]]
    if (n) notes[[i]] <- paste(.plural(n, "choice"), "marked `EDIT:`")
  }
  for (e in facts$calls) {
    switch(e$fn,
      read_job_data = add(e$line, "reads the study data"),
      .read_bootstrap_artifact = add(e$line, "reads what the bootstrap runner saved"),
      guard_memory = add(e$line, "checks the fit's memory need against this session's limit before it starts"),
      guard_long_fit = {
        why <- .literal(.call_arg(e, "why"))
        add(e$line, paste0("a long fit", if (!is.na(why)) paste0(" (", why, ")"), " that will not start in an ",
                           "interactive session, so the job runs in the background"))
      },
      .read_handoff = {
        rows <- graph[graph$consumer == facts$name & graph$line == e$line, , drop = FALSE]
        for (route in unique(rows$route)) {
          r <- rows[rows$route == route, , drop = FALSE]
          text <- if (route == "literal") {
            paste0("reads what ", .bold_list(unique(r$producer)), " saved (",
                   paste0("`", unique(r$file), "`", collapse = ", "), ")")
          } else if (route == "catalog") {
            "reads a saved result from the job its choices name"
          } else {
            paste0("reads `", r$file[[1L]], "`, which ",
                   if (is.na(r$rebuild[[1L]])) "another step" else r$rebuild[[1L]], " writes")
          }
          add(e$line, text)
        }
      },
      NULL
    )
  }
  # cache_fit() calls are gathered per section, so a section of five cached steps says so once.
  fits <- .calls_to(facts, "cache_fit")
  for (i in unique(.section_of(vapply(fits, `[[`, 1L, "line"), h))) {
    here <- Filter(function(e) .section_of(e$line, h) == i, fits)
    refit <- any(vapply(here, function(e) identical(.call_arg(e, "refit"), quote(REFIT)), logical(1L)))
    add(here[[1L]]$line, paste0("fits and caches its results, so a later render reloads them",
                                if (refit) " (`REFIT <- TRUE` recomputes them)"))
  }
  # A saved file is worth a note only when another template reads it.
  for (e in .calls_to(facts, "saveRDS")) {
    path <- .call_arg(e, "file")
    file <- if (is.null(path)) NA_character_ else .estimates_file(path, facts$bindings)
    if (is.na(file)) next
    readers <- unique(graph$consumer[graph$producer %in% facts$name & graph$route == "literal" & graph$file %in% file])
    chosen <- unique(graph$consumer[graph$producer %in% facts$name & graph$route == "catalog"])
    who <- c(if (length(readers)) paste0(.bold_list(readers), " read", if (length(readers) == 1L) "s"),
             if (length(chosen)) paste(.bold_list(chosen), "can read"))
    if (length(who)) add(e$line, paste0("saves `", file, "`, which ", paste(who, collapse = " and ")))
  }
  notes
}

.sheet_outline <- function(facts, graph) {
  h <- facts$layout$headings
  notes <- .section_notes(facts, graph)
  entry <- function(title, n) paste0("**", title, "**", if (length(n)) paste0(": ", paste(n, collapse = "; "), "."))
  out <- character()
  if (!nrow(h)) return(paste("1.", entry("The whole job", notes[[1L]])))
  if (length(notes[[1L]])) out <- paste("1.", entry("Above the first section", notes[[1L]]))
  for (i in seq_len(nrow(h))) {
    line <- entry(h$text[i], notes[[i + 1L]])
    out <- c(out, if (h$level[i] == 2L) paste("1.", line) else paste("   -", line))
  }
  out
}

.sheet_prerequisites <- function(facts, graph, packages, catalog) {
  fns <- vapply(facts$calls, `[[`, "", "fn")
  box_data <- Filter(Negate(is.null), lapply(.calls_to(facts, ".job_setup"), .call_arg, "box_data"))
  out <- paste0("- **A study.** The job runs inside a study folder set up with `_study.yml`. [Start a new study](",
                .site, "new-study.html) shows how.")
  if (any(vapply(box_data, isFALSE, logical(1L)))) {
    out <- c(out, paste("- **No dataset to read.** This job builds the study dataset rather than reading one;",
                        "the choices marked `EDIT:` say what it starts from."))
  } else if (!is.na(facts$dataset) || "read_job_data" %in% fns) {
    named <- if (!is.na(facts$dataset)) {
      paste0("`DATASET` names the registered dataset it reads (`\"", facts$dataset, "\"` unless you change it).")
    } else {
      "Its choices name the registered dataset it reads."
    }
    out <- c(out, paste("- **The study's data.**", named, "A draft can read a build that is not registered yet, so you",
                        "can start before the build is final, and the report then says it is a draft. A final render",
                        "reads registered data only: register the build with `hvtiRutilities::update_manifest()` first."))
  }
  up <- graph[graph$consumer == facts$name, , drop = FALSE]
  literal <- unique(up$producer[up$route == "literal"])
  # A catalog value is a template's name, or a prefix standing for any of its templates.
  from <- if (any(up$route == "catalog")) unlist(catalog$upstream[.catalog_names(catalog) == facts$name]) else character()
  from <- ifelse(from %in% .catalog_names(catalog), paste0("**", from, "**"), paste0("one of the **", from, "** jobs"))
  if (length(literal) || length(from)) {
    n <- length(literal) + length(from)
    said <- c(
      if (length(literal)) {
        paste0("Render ", .bold_list(literal), " first, in this same set: the same `subject` and `type` as this job, ",
               "which is how it finds what ", if (length(literal) == 1L) "that job" else "they", " saved (",
               paste0("`", unique(up$file[up$route == "literal"]), "`", collapse = ", "), ").")
      },
      if (length(from)) {
        paste0("Render ", .and_list(from), " first", if (length(literal)) " too", "; its choices marked `EDIT:` name ",
               "the file it saved and the set it sits in.")
      },
      paste0("For a final render, render ", if (n == 1L) "it" else "them", " final too: a final render refuses a ",
             "hand-off saved from unregistered data.")
    )
    out <- c(out, paste0("- **The job", if (n > 1L) "s", " it reads from.** ", paste(said, collapse = " ")))
  }
  for (i in which(up$route == "none")) {
    who <- if (is.na(up$rebuild[i])) "the step that writes it" else up$rebuild[i]
    out <- c(out, paste0("- **Run ", who, " first.** It writes `", up$file[i], "`, which this job reads."))
  }
  if (".read_bootstrap_artifact" %in% fns) {
    prefix <- sub("-.*$", "", facts$name)
    out <- c(out, paste0("- **Its bootstrap runner, run first.** The screen runs in a companion script, `", prefix,
                         ".<subject>.<type>.runner.R`, which `add_job()` writes beside the job. This job reports on ",
                         "what the runner saved."))
  }
  if (nrow(packages)) {
    pk <- ifelse(is.na(packages$floor), paste0("`", packages$package, "`"),
                 paste0("`", packages$package, "` (>= ", packages$floor, ")"))
    out <- c(out, paste0("- **Packages:** ", paste(pk, collapse = ", "), ". The job checks each floor when it starts, ",
                         "so an older library stops it at the top rather than partway through."))
  }
  if ("guard_long_fit" %in% fns) {
    out <- c(out, paste("- **The `hvti` command.** A long job starts from a terminal with `hvti run`;",
                        "`install_hvti()` puts the command on your PATH, once."))
  }
  out
}

.sheet_run <- function(facts) {
  guard <- .calls_to(facts, "guard_long_fit")
  draft <- paste0("**Render a draft as you go.** `render_job(job)` runs the whole job in a clean R session and writes ",
                  "the report beside it. Render early and often: while any `EDIT:` marker is left, the report opens ",
                  "with a DRAFT banner listing them, and its numbers are not a result. [Work a job](", .site,
                  "work-a-job.html#render-as-you-go) explains why to render rather than run chunks by hand.")
  final <- paste("**Then the final.** Once no marker is left, `render_job(job, final = TRUE)` renders the accepted",
                 "result. It refuses an open marker, a skipped chunk, `stop_here()` and unregistered data, and it",
                 "records the job's provenance beside the report.")
  if (!length(guard)) return(c(draft, "", final))
  why <- .literal(.call_arg(guard[[1L]], "why"))
  job <- paste0(facts$folder, "/", .add_job_name(facts$name), ".<subject>.<type>.qmd")
  c(paste0("**Run it in the background.** The fit is long", if (!is.na(why)) paste0(" (", why, ")"),
           ", and a fit run in the console dies with the session. From a terminal in the study, `hvti run ", job,
           "` checks the job, then renders it in the background on the R the study's `renv.lock` records; add ",
           "`--final` for the final render. From R, `run_job(job)` does the same. `hvti status` follows it and ",
           "`hvti cancel` stops it. Once the fit is cached, its chunks run interactively and load it."),
    "", draft, "", final)
}

.sheet_next <- function(facts, graph) {
  down <- graph[graph$producer %in% facts$name, , drop = FALSE]
  out <- character()
  # Readers in this same set first, then those whose choices name the file.
  for (consumer in unique(down$consumer[order(down$route != "literal", down$consumer)])) {
    r <- down[down$consumer == consumer, , drop = FALSE]
    call <- paste0("`add_job(\"", .add_job_name(consumer), "\", subject = \"<subject>\", type = \"<type>\")`")
    out <- c(out, if (all(r$route == "literal")) {
      paste0("- **", consumer, "** reads what this job saves (", paste0("`", unique(r$file), "`", collapse = ", "),
             "). Add it to the same set, with this job's `subject` and `type`, because that shared pair is how it ",
             "finds the file: ", call, ".")
    } else {
      paste0("- **", consumer, "** can read what this job saves; its choices marked `EDIT:` name the file and its ",
             "set. Add it with ", call, ".")
    })
  }
  out
}

# One template's sheet, as Markdown lines.
.run_sheet_md <- function(facts, graph, catalog) {
  row <- catalog[.catalog_names(catalog) == facts$name, , drop = FALSE]
  title <- if (nrow(row) && !is.na(row$name[[1L]])) paste0(facts$name, ": ", row$name[[1L]]) else facts$name
  what <- if (nrow(row) && !is.na(row$description[[1L]])) row$description[[1L]] else "The catalog does not describe it yet."
  if (nrow(row) && !is.na(row$deprecation_note[[1L]])) what <- paste(what, row$deprecation_note[[1L]])
  nxt <- .sheet_next(facts, graph)
  c(paste("#", title), "",
    "## What it does", "", paste0(what, " [See the report it produces](reports/", facts$name,
                                  ".html) on the gallery's synthetic study."), "",
    "## Prerequisites", "", .sheet_prerequisites(facts, graph, .template_packages(facts$file), catalog), "",
    "## Outline", "",
    paste0("These are the job's own sections, in order. The detail lives in the template: the comments at each ",
           "`EDIT:` marker say what to set and why, and [Work a job](", .site,
           "work-a-job.html#find-what-you-have-to-change) shows three ways to find them."), "",
    .sheet_outline(facts, graph), "",
    "## Run it", "", .sheet_run(facts),
    if (length(nxt)) c("", "## Where to go next", "", nxt))
}

# ---- The page ------------------------------------------------------------------
# The gallery publishes each sheet as a page of its own, so the Markdown above is
# turned into HTML here, where a test can see it, rather than in package.py.

# One line of Markdown to HTML: everything escaped, then `code`, **bold** and
# [text](href) converted, the only forms a sheet writes. Nothing inside a code
# span is converted. `base` goes before a relative href.
.md_inline_html <- function(x, base = "") {
  esc <- function(s) {
    for (p in list(c("&", "&amp;"), c("<", "&lt;"), c(">", "&gt;"), c("\"", "&quot;"))) s <- gsub(p[1L], p[2L], s, fixed = TRUE)
    s
  }
  parts <- strsplit(x, "`", fixed = TRUE)[[1L]]
  if (endsWith(x, "`")) parts <- c(parts, "")
  for (i in seq_along(parts)) {
    p <- esc(parts[i])
    if (i %% 2L == 0L) {
      parts[i] <- paste0("<code>", p, "</code>")
      next
    }
    p <- gsub("\\*\\*([^*]+)\\*\\*", "<strong>\\1</strong>", p)
    links <- regmatches(p, gregexpr("\\[[^]]+\\]\\([^)]+\\)", p))[[1L]]
    for (l in links) {
      text <- sub("^\\[([^]]+)\\].*$", "\\1", l)
      href <- sub("^.*\\]\\(([^)]+)\\)$", "\\1", l)
      if (!grepl("^([a-z]+:|#|/)", href)) href <- paste0(base, href)
      p <- sub(l, paste0("<a href=\"", href, "\">", text, "</a>"), p, fixed = TRUE)
    }
    parts[i] <- p
  }
  paste(parts, collapse = "")
}

# A sheet's Markdown to block HTML. Blocks are separated by blank lines, and a
# heading is a block of its own: # and ## headings, paragraphs, and - and 1.
# lists, with a list nested under an item by three spaces.
.run_sheet_html <- function(md, base = "") {
  inline <- function(x) .md_inline_html(x, base)
  heading <- grepl("^#{1,2} ", md)
  blank <- !nzchar(trimws(md))
  block <- cumsum(blank | heading | c(FALSE, heading[-length(md)]))
  blocks <- split(md[!blank], block[!blank])
  item <- "^(- |[0-9]+\\. )"
  html <- vapply(blocks, function(b) {
    if (grepl("^#{1,2} ", b[1L])) {
      level <- nchar(sub(" .*$", "", b[1L]))
      return(sprintf("<h%d>%s</h%d>", level, inline(sub("^#+ ", "", b[1L])), level))
    }
    if (!grepl(item, b[1L])) return(paste0("<p>", inline(paste(b, collapse = " ")), "</p>"))
    kind <- if (startsWith(b[1L], "- ")) "ul" else "ol"
    li <- vapply(split(b, cumsum(!startsWith(b, "   - "))), function(it) {
      nested <- vapply(sub("^   - ", "", it[-1L]), inline, character(1L), USE.NAMES = FALSE)
      paste0("<li>", inline(sub(item, "", it[1L])),
             if (length(nested)) paste0("<ul>", paste0("<li>", nested, "</li>", collapse = ""), "</ul>"), "</li>")
    }, character(1L))
    paste(c(paste0("<", kind, ">"), li, paste0("</", kind, ">")), collapse = "\n")
  }, character(1L))
  paste(html, collapse = "\n")
}

# Every template's sheet, for the gallery: its name, its title, the Markdown and
# the HTML. A sheet page sits one folder below the gallery's index, in sheets/,
# hence `base`.
.run_sheets <- function(dir = .templates_dir(), base = "../", catalog = template_catalog()) {
  files <- list.files(dir, "[.]qmd$", recursive = TRUE, full.names = TRUE)
  facts <- stats::setNames(lapply(files, .run_sheet_facts), sub("[.]qmd$", "", basename(files)))
  graph <- .handoff_graph(facts, catalog)
  unname(lapply(facts, function(f) {
    md <- .run_sheet_md(f, graph, catalog)
    list(name = f$name, title = sub("^# ", "", md[[1L]]), markdown = paste(md, collapse = "\n"),
         html = .run_sheet_html(md, base))
  }))
}
