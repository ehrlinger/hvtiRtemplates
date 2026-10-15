#' Rewrite a job from the current version of its template
#'
#' @description
#' Upgrades \strong{one job}: the file you name in \code{path}. It does not
#' look for other jobs, so to upgrade several, call it once for each.
#'
#' A job is a copy of its template as it stood on the day \code{\link{add_job}}
#' wrote it. \code{upgrade_job()} writes the job again from the template as it
#' stands now and carries the study's choices across, so a job keeps up with
#' its template without re-entering every choice by hand.
#'
#' @section Upgrading a job:
#' Name the job's \code{.qmd} file. From the study root, a cohort EDA job is
#' \preformatted{upgrade_job("10_descriptive/dc.general.cohort.eda.qmd")}
#' and several jobs are upgraded one call each:
#' \preformatted{for (job in c("10_descriptive/dc.general.cohort.eda.qmd",
#'               "10_descriptive/dc.general.cohort.gfup.qmd")) {
#'   upgrade_job(job)
#' }}
#' You never name the template: the job's file name says which one it is.
#' \code{dir} is needed only when the job sits outside the study it belongs
#' to.
#'
#' Afterwards, render the job and read its report,
#' \code{<job>-upgrade.md}, for the chunks to check. The old job is kept as
#' \code{<job>.pre-upgrade}. Move that aside before upgrading the same job
#' again: \code{upgrade_job()} never overwrites a file, so a second upgrade
#' stops.
#'
#' @details
#' The template is read from the job's file name, in either spelling
#' \code{\link{add_job}} has used. A study's choices are the top-level
#' assignments to an upper-case name, such as \code{DATASET <- "built"}, in the
#' job's \code{edit-*} chunks. Each choice the current template also has
#' replaces the template's assignment, its source text unchanged, multi-line
#' values included. \code{SUBJECT} and \code{TYPE} are not carried: the file
#' name owns them. Where the job had resolved a choice's \code{EDIT:} marker,
#' the upgraded job drops the template's marker for it too.
#'
#' Nothing is dropped silently. A choice the current template no longer has is
#' written, commented out, at the end of the template's
#' \code{edit-study-choices} chunk under a new \code{EDIT:} marker, so the job
#' renders as a draft until someone decides. Prose and code outside the
#' choices come from the current template, because without the template the
#' job was copied from an analyst's edit cannot be told from the old
#' template's text. The report lists every chunk that may hold such an edit.
#'
#' The old job is kept beside the new one as \code{<file>.pre-upgrade}, a name
#' nothing renders. The upgraded job takes the name \code{\link{add_job}}
#' would give it today, so a job named before 2026-10 moves to the
#' \code{.}-separated spelling. The report is written beside the job, with the
#' \code{.qmd} extension replaced by \code{-upgrade.md}. It records the
#' template, the package version, the old job's checksum, and the choices
#' carried, not placed and new, with the chunks to review. It names choices
#' and lines but never quotes their values, since a value can identify a
#' patient. The upgrade refuses to overwrite any existing file.
#'
#' @param path The one job to upgrade: its \code{.qmd} file, relative to the
#'   working directory or absolute, such as
#'   \code{"10_descriptive/dc.general.cohort.eda.qmd"}.
#' @param dir Any directory in the study, used only to locate the study root.
#'   Defaults to the directory of \code{path}, which is right for any job
#'   inside its study.
#'
#' @return The upgraded job's path, invisibly. The report is written beside it.
#' @seealso \code{\link{add_job}}, \code{\link{migrate_job}}
#' @examples
#' \donttest{
#' root <- file.path(tempdir(), "upgrade-job-example")
#' invisible(hvtiRutilities::study_setup(root, "Example", 1L))
#' job <- add_job("dc", "cohort", "eda", dir = root, qualifier = "general")
#' # A study choice, made in the job.
#' lines <- readLines(job)
#' lines <- sub('^DATASET <- "built"', 'DATASET <- "built_r"', lines)
#' writeLines(lines, job)
#' upgraded <- upgrade_job(job)
#' grep("^DATASET <- ", readLines(upgraded), value = TRUE)
#' unlink(root, recursive = TRUE)
#' }
#' @export
upgrade_job <- function(path, dir = NULL) {
  tryCatch(.check_scalar_string("path", path), error = function(e) {
    stop("upgrade_job(): ", sub("^template selection: ", "", conditionMessage(e)), call. = FALSE)
  })
  if (!file.exists(path) || dir.exists(path)) stop("upgrade_job(): job not found: ", path, call. = FALSE)
  if (!grepl("[.]qmd$", path)) stop("upgrade_job(): a job is a .qmd file: ", path, call. = FALSE)
  path <- normalizePath(path, winslash = "/")
  root <- hvtiRutilities::study_root(if (is.null(dir)) dirname(path) else dir)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  if (!.path_within(path, root)) stop("upgrade_job(): the job must be beneath the study root.", call. = FALSE)

  fields <- .job_template_fields(path)
  if (is.null(fields)) {
    stop("upgrade_job(): '", basename(path), "' does not name a template; expected ",
         "<prefix>[.<qualifier>].<subject>.<type>.qmd.", call. = FALSE)
  }
  row <- tryCatch(
    .select_template(template_list(), fields$prefix, fields$qualifier),
    error = function(e) stop("upgrade_job(): ", conditionMessage(e), call. = FALSE)
  )
  .warn_if_deprecated(row, "upgrade_job")

  target <- .job_path(row, fields$subject, fields$type, root)
  backup <- paste0(path, ".pre-upgrade")
  report_path <- sub("[.]qmd$", "-upgrade.md", target)
  # A symbolic link counts as taken even when it dangles: file.exists() says
  # FALSE for one, and writing through it would create a file wherever it points.
  taken <- function(p) {
    link <- Sys.readlink(p)
    file.exists(p) | (!is.na(link) & nzchar(link))
  }
  for (p in c(backup, report_path)) {
    if (taken(p)) stop("upgrade_job(): '", p, "' already exists; refusing to overwrite.", call. = FALSE)
  }
  # Any other spelling of this job, current, before 2026-10 or under the
  # template's name before a rename, is a second copy of the same set's edits.
  others <- c(target, .job_path_legacy(row, fields$subject, fields$type, root),
              .job_paths_renamed(row, fields$subject, fields$type, root))
  others <- others[taken(others) & normalizePath(others, winslash = "/", mustWork = FALSE) != path]
  if (length(others)) {
    stop("upgrade_job(): '", others[[1L]], "' is another copy of this job; refusing to write a second.",
         call. = FALSE)
  }

  staging <- tempfile(pattern = "upgrade-stage-")
  dir.create(staging)
  on.exit(unlink(staging, recursive = TRUE), add = TRUE)
  qualifier <- if (is.na(row$qualifier[[1L]])) NULL else row$qualifier[[1L]]
  staged <- suppressWarnings(add_job(row$prefix[[1L]], fields$subject, fields$type, dir = staging,
                                     qualifier = qualifier))
  old <- readLines(path, warn = FALSE)
  upgraded <- .upgrade_lines(old, readLines(staged, warn = FALSE))

  report <- .upgrade_report(upgraded, row$name[[1L]], old, path, backup, root)
  # A renamed template can live in another folder, which the study may not have
  # yet. Wherever it resolves to, it must be inside the study.
  if (!dir.exists(dirname(target))) dir.create(dirname(target), recursive = TRUE)
  if (!.path_within(normalizePath(dirname(target), winslash = "/", mustWork = TRUE), root)) {
    stop("upgrade_job(): the upgraded job's folder resolves outside the study root.", call. = FALSE)
  }
  # The current template's provenance checks need the study's hooks, which a
  # study older than them may lack; add_job() installs them the same way.
  .install_provenance_hooks(root)
  mode <- file.info(path)$mode
  if (!file.rename(path, backup)) stop("upgrade_job(): could not set the old job aside as '", backup, "'.", call. = FALSE)
  ok <- FALSE
  on.exit(if (!ok) {
    unlink(c(target, report_path))
    file.rename(backup, path)
  }, add = TRUE)
  writeLines(upgraded$lines, target)
  writeLines(report, report_path)
  # The job keeps its permissions: a job closed to other readers stays closed.
  Sys.chmod(c(target, report_path), mode, use_umask = FALSE)
  ok <- TRUE
  .open_in_editor(target)
}

# list(prefix, qualifier, subject, type) from a job's file name, or NULL.
# `<prefix>[.<qualifier>].<subject>.<type>.qmd` since 2026-10, and
# `<subject>-<type>-<prefix>[-<qualifier>].qmd` before it.
.job_template_fields <- function(path) {
  stem <- sub("[.]qmd$", "", basename(path))
  ok <- function(x) all(grepl("^[A-Za-z0-9_]+$", x))
  dash <- grepl("-", stem, fixed = TRUE)
  parts <- strsplit(stem, if (dash) "-" else ".", fixed = TRUE)[[1L]]
  if (!length(parts) %in% 3:4 || !ok(parts)) return(NULL)
  if (dash) {
    list(prefix = parts[[3L]], qualifier = if (length(parts) == 4L) parts[[4L]],
         subject = parts[[1L]], type = parts[[2L]])
  } else {
    n <- length(parts)
    list(prefix = parts[[1L]], qualifier = if (n == 4L) parts[[2L]],
         subject = parts[[n - 1L]], type = parts[[n]])
  }
}

# The marker token, built rather than written, as in .guard_edits().
.edit_token <- function() paste0("ED", "IT", ":")

# R chunks: a data frame of label, first and last code line (fences excluded).
# A fence is three or more backticks, and the chunk closes on a fence of the
# same length, as Quarto reads it. A label may be quoted.
.qmd_chunks <- function(lines) {
  open <- grep("^`{3,}\\{r[ ,}]", lines)
  rows <- lapply(open, function(o) {
    ticks <- sub("^(`+).*$", "\\1", lines[[o]])
    close <- which(lines == ticks | grepl(paste0("^", ticks, "\\s*$"), lines))
    e <- close[close > o][1L]
    if (is.na(e)) return(NULL)
    body <- if (e > o + 1L) (o + 1L):(e - 1L) else integer()
    lab <- sub("^#\\|\\s*label:\\s*", "", grep("^#\\|\\s*label:", lines[body], value = TRUE))
    # knitr's header form, ```{r label, opt = x}, names a chunk too.
    head <- regmatches(lines[[o]], regexec("^`{3,}\\{r[ ,]+([A-Za-z0-9_.-]+)\\s*[,}]", lines[[o]]))[[1L]]
    if (!length(lab) && length(head)) lab <- head[[2L]]
    lab <- if (length(lab)) gsub("^[\"']|[\"']$", "", trimws(lab[[1L]])) else NA_character_
    data.frame(label = lab, open = o, close = e)
  })
  do.call(rbind, c(list(data.frame(label = character(), open = integer(), close = integer())), rows))
}

# A study's choices: top-level `NAME <- value` in `edit-*` chunks, with NAME
# upper case. A data frame of name, chunk, the assignment's first and last line
# and its first and last byte on them (two statements can share a line), and
# whether an EDIT marker sits on its lines or in the comment block above.
.job_choices <- function(lines) {
  chunks <- .qmd_chunks(lines)
  chunks <- chunks[!is.na(chunks$label) & startsWith(chunks$label, "edit-"), , drop = FALSE]
  empty <- data.frame(name = character(), chunk = character(), start = integer(), end = integer(),
                      first_byte = integer(), last_byte = integer(), marker = logical(), block_start = integer())
  rows <- lapply(seq_len(nrow(chunks)), function(i) {
    first <- chunks$open[[i]] + 1L
    code <- lines[first:(chunks$close[[i]] - 1L)]
    # A chunk that does not parse would drop its choices unseen; stop instead.
    exprs <- tryCatch(parse(text = code, keep.source = TRUE), error = function(e) {
      stop("upgrade_job(): chunk `", chunks$label[[i]], "` at line ", chunks$open[[i]],
           " does not parse, so its choices cannot be read: ", conditionMessage(e), call. = FALSE)
    })
    refs <- attr(exprs, "srcref")
    hits <- lapply(seq_along(exprs), function(j) {
      e <- exprs[[j]]
      if (!is.call(e) || !is.name(e[[1L]]) || !as.character(e[[1L]]) %in% c("<-", "=") || !is.name(e[[2L]])) {
        return(NULL)
      }
      name <- as.character(e[[2L]])
      if (!grepl("^[A-Z][A-Z0-9_]*$", name) || name %in% c("SUBJECT", "TYPE")) return(NULL)
      start <- first - 1L + refs[[j]][[1L]]
      end <- first - 1L + refs[[j]][[3L]]
      above <- start - 1L
      while (above >= first && grepl("^\\s*#", lines[[above]]) && !grepl("^#\\|", lines[[above]])) above <- above - 1L
      block <- if (above + 1L <= start - 1L) lines[(above + 1L):(start - 1L)] else character()
      data.frame(name = name, chunk = chunks$label[[i]], start = start, end = end,
                 first_byte = refs[[j]][[2L]], last_byte = refs[[j]][[4L]],
                 marker = any(grepl(.edit_token(), c(block, lines[start:end]), fixed = TRUE)),
                 block_start = above + 1L)
    })
    do.call(rbind, c(list(empty), hits))
  })
  out <- do.call(rbind, c(list(empty), rows))
  # A name assigned twice cannot be carried by name; it is reported instead.
  out$duplicated <- out$name %in% out$name[duplicated(out$name)]
  out
}

# Bytes `from` to `to` of a line, as srcref counts them.
.bytes <- function(x, from, to = .Machine$integer.max) {
  r <- charToRaw(x)
  to <- min(to, length(r))
  if (from > to) "" else rawToChar(r[from:to])
}

# A choice's lines split three ways: the text before it on its first line, its
# own source text, and the text after it on its last line.
.choice_parts <- function(lines, ch) {
  own <- lines[ch$start:ch$end]
  n <- length(own)
  if (n == 1L) {
    own <- .bytes(own, ch$first_byte, ch$last_byte)
  } else {
    own[[1L]] <- .bytes(own[[1L]], ch$first_byte)
    own[[n]] <- .bytes(own[[n]], 1L, ch$last_byte)
  }
  list(before = .bytes(lines[[ch$start]], 1L, ch$first_byte - 1L), own = own,
       after = .bytes(lines[[ch$end]], ch$last_byte + 1L))
}

# A chunk's code with its choices taken out and comments and blank lines
# dropped: the code an upgrade does not carry.
.residual_code <- function(lines, chunk, choices) {
  for (i in rev(seq_len(nrow(choices)))) {
    ch <- choices[i, ]
    parts <- .choice_parts(lines, ch)
    lines <- c(lines[seq_len(ch$start - 1L)], paste0(parts$before, parts$after),
               rep("", ch$end - ch$start), lines[-seq_len(ch$end)])
  }
  code <- gsub("^[;[:space:]]+|[;[:space:]]+$", "", lines[(chunk$open + 1L):(chunk$close - 1L)])
  code[nzchar(code) & !startsWith(code, "#")]
}

# The upgraded job's lines and what happened to each choice.
.upgrade_lines <- function(old, new) {
  oc <- .job_choices(old)
  nc <- .job_choices(new)
  carry <- nc[nc$name %in% oc$name[!oc$duplicated] & !nc$duplicated, , drop = FALSE]
  token <- .edit_token()
  out <- new
  # Bottom up, so each replacement leaves the earlier line numbers valid.
  for (i in rev(seq_len(nrow(carry)))) {
    o <- oc[oc$name == carry$name[[i]], , drop = FALSE][1L, ]
    n <- carry[i, ]
    parts <- .choice_parts(out, n)
    above <- if (n$block_start < n$start) n$block_start:(n$start - 1L) else integer()
    if (!o$marker) {
      # Resolved in the old job, so resolved here.
      out[above] <- sub(paste0(token, "\\s*"), "", out[above])
      parts$after <- sub(paste0(token, "\\s*"), "", parts$after)
    }
    carried <- .choice_parts(old, o)$own
    carried[[1L]] <- paste0(parts$before, carried[[1L]])
    carried[[length(carried)]] <- paste0(carried[[length(carried)]], parts$after)
    # Still open in the old job: it stays open, whether or not the current
    # template marks this choice.
    if (o$marker && !any(grepl(token, c(out[above], carried), fixed = TRUE))) {
      carried <- c(paste("#", token, "still open in the old job; decide it, then delete this line."), carried)
    }
    out <- c(out[seq_len(n$start - 1L)], carried, out[-seq_len(n$end)])
  }
  unplaced <- oc[!oc$name %in% carry$name, , drop = FALSE]
  if (nrow(unplaced)) {
    chunks <- .qmd_chunks(out)
    at <- chunks$close[which(chunks$label == "edit-study-choices")[1L]]
    if (is.na(at)) stop("upgrade_job(): the current template has no `edit-study-choices` chunk to hold the ",
                        "choices it could not place.", call. = FALSE)
    note <- c("", paste("#", token, "upgrade_job() could not place these choices from the old job;",
                        "the current template has no assignment of the same name. Decide each, then delete this block."))
    for (i in seq_len(nrow(unplaced))) note <- c(note, paste0("# ", .choice_parts(old, unplaced[i, ])$own))
    out <- append(out, note, after = at - 1L)
  }
  list(lines = out, carried = carry$name, unplaced = unplaced, new = setdiff(nc$name, oc$name),
       old_chunks = .qmd_chunks(old), new_chunks = .qmd_chunks(new), old_choices = oc, new_choices = nc,
       new_lines = new)
}

.upgrade_report <- function(u, template, old, path, backup, root,
                            version = as.character(utils::packageVersion("hvtiRtemplates"))) {
  rel <- function(p) {
    p <- .canonical_path(p)
    if (startsWith(p, paste0(root, "/"))) substring(p, nchar(root) + 2L) else p
  }
  stamp <- regmatches(old, regexpr("<!-- hvtiRtemplates: [^ ]+ [0-9.]+ -->", old))
  from <- if (length(stamp)) sub("<!-- hvtiRtemplates: [^ ]+ ([0-9.]+) -->", "\\1", stamp[[1L]]) else
    "not recorded (scaffolded before add_job() stamped its jobs)"
  lst <- function(x) if (length(x)) paste0("- ", x) else "None."
  nl <- u$new_lines
  oc <- u$old_chunks
  nc <- u$new_chunks
  # Chunks #303 folded into `setup`; their absence is the template's change, not an edit.
  retired <- c("guard-edits", "guard-partial", "set")
  body <- function(chunks, lines, lab) {
    k <- which(chunks$label == lab)[1L]
    code <- lines[(chunks$open[[k]] + 1L):(chunks$close[[k]] - 1L)]
    code[!grepl("^\\s*$", code)]
  }
  review <- character()
  for (k in seq_len(nrow(oc))) {
    lab <- oc$label[[k]]
    where <- paste0("old lines ", oc$open[[k]], "-", oc$close[[k]])
    if (is.na(lab)) {
      review <- c(review, paste0("an unlabeled chunk, ", where))
    } else if (startsWith(lab, "edit-")) {
      # Choices are carried; any other code in the chunk is not.
      k_new <- which(nc$label == lab)[1L]
      kept_old <- .residual_code(old, oc[k, ], u$old_choices[u$old_choices$chunk == lab, , drop = FALSE])
      kept_new <- if (is.na(k_new)) character() else
        .residual_code(nl, nc[k_new, ], u$new_choices[u$new_choices$chunk == lab, , drop = FALSE])
      if (!identical(kept_old, kept_new)) {
        review <- c(review, paste0("`", lab, "`, ", where, ": code other than its choices differs from the ",
                                   "current template, and only the choices were carried"))
      }
    } else if (lab %in% retired) {
      next
    } else if (!lab %in% nc$label) {
      review <- c(review, paste0("`", lab, "`, ", where, ": not in the current template"))
    } else if (!identical(body(oc, old, lab), body(nc, nl, lab))) {
      review <- c(review, paste0("`", lab, "`, ", where, ": differs from the current template"))
    }
  }
  markers <- grep(.edit_token(), u$lines, fixed = TRUE)
  c(
    "# Upgrade report", "",
    paste0("Template: hvtiRtemplates ", version, " / ", template), "",
    paste0("- Old job: ", rel(backup), " (SHA-256 ", digest::digest(file = path, algo = "sha256"), ")"),
    paste0("- Template version the old job came from: ", from), "",
    "## Carried", "", lst(paste0("`", u$carried, "`")), "",
    "## Not placed", "",
    "Set in the old job, absent from the current template. Each is commented out at the end of the ",
    "`edit-study-choices` chunk under a marker.", "",
    lst(paste0("`", u$unplaced$name, "`, old line ", u$unplaced$start,
               ifelse(u$unplaced$duplicated, " (assigned more than once in the old job)", ""))), "",
    "## New", "", "In the current template only, left at its default.", "",
    lst(paste0("`", u$new, "`")), "",
    "## Review", "",
    "Code outside the choices comes from the current template. These chunks of the old job may hold an ",
    "edit of your own; compare them with the old job.", "",
    lst(review), "",
    "## Markers left", "", lst(paste0("line ", markers)), ""
  )
}
