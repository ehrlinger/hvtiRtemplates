#' Rewrite a job from the current version of its template
#'
#' @description
#' A job is a copy of its template as it stood on the day \code{\link{add_job}}
#' wrote it. \code{upgrade_job()} writes the job again from the template as it
#' stands now and carries the study's choices across, so a job keeps up with
#' its template without re-entering every choice by hand.
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
#' @param path Path to the job, relative to the working directory or absolute.
#' @param dir Any directory in the study, used only to locate the study root.
#'   Defaults to the directory of \code{path}.
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
  if (file.exists(backup)) stop("upgrade_job(): '", backup, "' already exists; refusing to overwrite.", call. = FALSE)
  if (file.exists(report_path)) {
    stop("upgrade_job(): '", report_path, "' already exists; refusing to overwrite.", call. = FALSE)
  }
  # Any other spelling of this job, current, before 2026-10 or under the
  # template's name before a rename, is a second copy of the same set's edits.
  others <- c(target, .job_path_legacy(row, fields$subject, fields$type, root),
              .job_paths_renamed(row, fields$subject, fields$type, root))
  others <- others[file.exists(others) & normalizePath(others, winslash = "/", mustWork = FALSE) != path]
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
  if (!file.rename(path, backup)) stop("upgrade_job(): could not set the old job aside as '", backup, "'.", call. = FALSE)
  ok <- FALSE
  on.exit(if (!ok) {
    unlink(c(target, report_path))
    file.rename(backup, path)
  }, add = TRUE)
  writeLines(upgraded$lines, target)
  writeLines(report, report_path)
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
.qmd_chunks <- function(lines) {
  open <- grep("^```\\{r", lines)
  close <- grep("^```\\s*$", lines)
  rows <- lapply(open, function(o) {
    e <- close[close > o][1L]
    if (is.na(e)) return(NULL)
    body <- if (e > o + 1L) (o + 1L):(e - 1L) else integer()
    lab <- sub("^#\\|\\s*label:\\s*", "", grep("^#\\|\\s*label:", lines[body], value = TRUE))
    # knitr's header form, ```{r label, opt = x}, names a chunk too.
    head <- regmatches(lines[[o]], regexec("^```\\{r[ ,]+([A-Za-z0-9_.-]+)\\s*[,}]", lines[[o]]))[[1L]]
    if (!length(lab) && length(head)) lab <- head[[2L]]
    data.frame(label = if (length(lab)) trimws(lab[[1L]]) else NA_character_, open = o, close = e)
  })
  do.call(rbind, c(list(data.frame(label = character(), open = integer(), close = integer())), rows))
}

# A study's choices: top-level `NAME <- value` in `edit-*` chunks, with NAME
# upper case. A data frame of name, chunk, the assignment's first and last
# line, and whether an EDIT marker sits on it or in the comment block above.
.job_choices <- function(lines) {
  chunks <- .qmd_chunks(lines)
  chunks <- chunks[!is.na(chunks$label) & startsWith(chunks$label, "edit-"), , drop = FALSE]
  empty <- data.frame(name = character(), chunk = character(), start = integer(), end = integer(),
                      marker = logical())
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
                 marker = any(grepl(.edit_token(), c(block, lines[start:end]), fixed = TRUE)),
                 block_start = above + 1L)
    })
    do.call(rbind, c(list(cbind(empty, block_start = integer())), hits))
  })
  out <- do.call(rbind, c(list(cbind(empty, block_start = integer())), rows))
  # A name assigned twice cannot be carried by name; it is reported instead.
  out$duplicated <- out$name %in% out$name[duplicated(out$name)]
  out
}

# The upgraded job's lines and what happened to each choice.
.upgrade_lines <- function(old, new) {
  oc <- .job_choices(old)
  nc <- .job_choices(new)
  carry <- nc[nc$name %in% oc$name[!oc$duplicated] & !nc$duplicated, , drop = FALSE]
  out <- new
  # Bottom up, so each replacement leaves the earlier line numbers valid.
  for (i in rev(seq_len(nrow(carry)))) {
    o <- oc[oc$name == carry$name[[i]], , drop = FALSE][1L, ]
    if (!o$marker && carry$block_start[[i]] < carry$start[[i]]) {
      above <- carry$block_start[[i]]:(carry$start[[i]] - 1L)
      out[above] <- sub(paste0(.edit_token(), "\\s*"), "", out[above])
    }
    out <- c(out[seq_len(carry$start[[i]] - 1L)], old[o$start:o$end], out[-seq_len(carry$end[[i]])])
  }
  unplaced <- oc[!oc$name %in% carry$name, , drop = FALSE]
  if (nrow(unplaced)) {
    chunks <- .qmd_chunks(out)
    at <- chunks$close[which(chunks$label == "edit-study-choices")[1L]]
    if (is.na(at)) stop("upgrade_job(): the current template has no `edit-study-choices` chunk to hold the ",
                        "choices it could not place.", call. = FALSE)
    note <- c("", paste("#", .edit_token(), "upgrade_job() could not place these choices from the old job;",
                        "the current template has no assignment of the same name. Decide each, then delete this block."))
    for (i in seq_len(nrow(unplaced))) note <- c(note, paste0("# ", old[unplaced$start[[i]]:unplaced$end[[i]]]))
    out <- append(out, note, after = at - 1L)
  }
  list(lines = out, carried = carry$name, unplaced = unplaced,
       new = setdiff(nc$name, oc$name), old_chunks = .qmd_chunks(old), new_chunks = .qmd_chunks(new),
       old = old, new_lines = new)
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
    } else if (startsWith(lab, "edit-") || lab %in% retired) {
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
    "## Markers left", "", lst(paste0("line ", markers, ": ", trimws(substr(u$lines[markers], 1L, 96L)))), ""
  )
}
