# What a template's one `setup` chunk calls. It did the work of four chunks
# (`setup`, `guard-edits`, `guard-partial` and `set`) that every template carried
# a copy of, and it starts the run record the report's top box and end table
# read. The design is dev/specs/2026-10-12-setup-and-run-info-design.md.
#
# Jobs already in studies keep their four chunks and keep working, so what those
# chunks call (.find_study_root(), .guard_partial() and .job_name_fields()) is
# unchanged.

# Called by a template's setup chunk, after it declares SUBJECT and TYPE and
# attaches its packages, in the order the four chunks ran:
#   1. the study root, from the file being rendered or the working directory;
#   2. the study's R/ sourced into `envir`, the only place this writes;
#   3. the EDIT: marker guard: a DRAFT callout in a draft, a stop in a final render;
#   4. the partial-render guard;
#   5. the file name checked against `subject` and `type`;
#   6. the run record started, and
#   7. the top box made.
# Returns the study root, the set_path() function the job writes through, the
# run record, and the notice the report opens with: the draft banners, if any,
# then the box. `show_markers = FALSE` keeps a marker's source line out of the
# report, for a job whose markers can sit beside a patient's name (bd).
.job_setup <- function(subject, type, envir = parent.frame(), show_markers = TRUE) {
  started <- Sys.time()
  input <- knitr::current_input(dir = TRUE)
  root <- .find_study_root(if (is.null(input)) getwd() else dirname(input))
  for (f in list.files(file.path(root, "R"), pattern = "[.]R$", full.names = TRUE)) source(f, local = envir)
  # What the report says, kept and returned rather than printed: printed, it would
  # split the chunk's code in two "Code" folds, one each side of the output. The
  # chunk ends on .job$notice, so the output comes after all of its code.
  banner <- utils::capture.output(markers <- .guard_edits(show_source = show_markers))
  partial <- .guard_partial(knitr::current_input())
  .check_job_name(knitr::current_input(), subject, type)
  # A new run: what the last one read is not this one's.
  .run_state$reads <- list()
  .run_state$handoffs <- list()
  run <- .run_begin(started, input, subject, type, markers)
  notice <- paste0(c(if (length(banner)) paste(banner, collapse = "\n"), as.character(partial),
                     .run_box(run, .box_dataset(root, input))), collapse = "\n")
  # Resolves from `envir`, not from the arguments, so a test or an author who
  # changes SUBJECT or TYPE afterward moves the set, as the old chunk's did.
  set_path <- function(kind, file) {
    d <- file.path(hvtiRutilities::study_dir(kind, get0(".root", envir = envir, ifnotfound = root)),
                   paste0(get0("SUBJECT", envir = envir, ifnotfound = subject), "-",
                          get0("TYPE", envir = envir, ifnotfound = type)))
    if (!dir.exists(d)) dir.create(d, recursive = TRUE)
    file.path(d, file)
  }
  list(root = root, set_path = set_path, run = run, notice = knitr::asis_output(notice))
}

# add_job() writes SUBJECT and TYPE from the same values it put in the file's
# name, but a hand-edited declaration can drift from it afterward. set_path()
# resolves from the declarations, not the filename, so a drifted declaration
# would write into ANOTHER set's directory. knitr::current_input() is NULL
# outside a render, and there is no filename to check, so this is a no-op then.
.check_job_name <- function(current, subject, type) {
  if (is.null(current)) return(invisible(NULL))
  fields <- .job_name_fields(current)
  name_subject <- if (length(fields) >= 1L) fields[[1L]] else NA_character_
  name_type <- if (length(fields) >= 2L) fields[[2L]] else NA_character_
  if (!identical(name_subject, subject) || !identical(name_type, type)) {
    stop("This file is named '", current, "' (subject '", name_subject, "', type '", name_type,
         "'), but declares SUBJECT = \"", subject, "\", TYPE = \"", type,
         "\". Fix the declaration or the filename before rendering.", call. = FALSE)
  }
  invisible(NULL)
}

# The markers in a template's own text name work a study author still has to do,
# and a job that still contains one has not been finished. This guard is what
# makes that TRUE rather than merely stated: an unedited job would otherwise
# render green over placeholder columns. A job renders as a draft by default, so
# an author can iterate on a working report and remove markers as they go;
# HVTI_TEMPLATE_STRICT turns the draft into a stop for a final render. Only
# unset, 0, false and no mean "not strict": an unrecognized value stops on
# purpose, so a mistyped switch is seen rather than quietly ignored.
#
# The banner is not optional. A draft render that looks like a finished one is
# the same defect with an extra step: the warning scrolls past in a log, while
# the .html is the artifact that gets sent to someone.
#
# `show_source = FALSE` gives the report the COUNT only (bd: a marker line can
# sit beside an EXCLUDE rule that names a patient). The report would also embed
# a warning, so that warning carries the count and the lines go to the console
# directly, on stderr, where knitr does not collect them. Returns the number of
# markers, invisibly.
#
# The token is built, never written, so this file's own text does not match: a
# guard that searches for a literal matches its own source and fires on every
# render (see "no template writes the edit marker token literally").
.guard_edits <- function(input = knitr::current_input(), show_source = TRUE) {
  if (is.null(input)) return(invisible(0L))
  token <- paste0("ED", "IT", ":")
  src <- readLines(input, warn = FALSE)
  hits <- grep(token, src, fixed = TRUE)
  if (!length(hits)) return(invisible(0L))
  msg <- paste0(
    length(hits), " unresolved ", token, " marker(s) remain in this job:\n",
    paste0("  - ", trimws(substr(src[hits], 1L, 96L)), collapse = "\n"),
    if (show_source) "\nA job that still contains one has not been finished. Work each marker and delete it."
  )
  if (!.strict_render()) {
    if (!show_source) cat(msg, "\n", sep = "", file = stderr())
    warning(if (show_source) msg else paste0(length(hits), " unresolved ", token, " marker(s) remain in this job."),
            "\nRendering as a draft; the banner goes when the last marker does. ",
            "Set HVTI_TEMPLATE_STRICT to 1, true or yes to make this stop.", call. = FALSE)
    cat("\n::: {.callout-important title=\"DRAFT -- this job is unfinished\"}\n")
    if (show_source) {
      cat("Unresolved markers remain. **The numbers below are not a result.**\n\n```\n", msg, "\n```\n", sep = "")
    } else {
      cat(length(hits), "unresolved markers remain. **This dataset is not finished.**\n")
    }
    cat(":::\n\n")
  } else {
    stop(msg, "\nThis render stops because HVTI_TEMPLATE_STRICT is '", Sys.getenv("HVTI_TEMPLATE_STRICT"),
         "'. Unset it, or set it to 0, false or no, to render a draft instead.", call. = FALSE)
  }
  invisible(length(hits))
}
