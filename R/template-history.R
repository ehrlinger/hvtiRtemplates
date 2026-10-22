# The texts of every template as it stood on `main` since add_job() began
# stamping its jobs (d3b741e, 2026-10-12), so upgrade_job() can find the text a
# job was copied from. dev/template-history/build.R reads git and calls
# .history_from_states(); nothing at run time touches git. See
# dev/specs/2026-10-22-upgrade-job-merge-design.md, decisions 2 and 3.

# `states` is one list(version, date, files) per first-parent commit, with
# `files` a named list of each template's raw bytes by its path. Every commit
# counts, not only those that touch a template: a bump commit that changes none
# still maps their texts to the new version, which a job scaffolded just after
# it stamps. Each text is stored once, by its SHA-256; the index keeps every
# (template, version, text) seen, with the first and last commit date.
.history_from_states <- function(states) {
  texts <- list()
  rows <- list()
  for (s in states) {
    for (path in names(s$files)) {
      raw <- s$files[[path]]
      sha <- digest::digest(raw, algo = "sha256", serialize = FALSE)
      if (is.null(texts[[sha]])) texts[[sha]] <- rawToChar(raw)
      rows[[length(rows) + 1L]] <- data.frame(template = .template_display_name(path), file = path,
                                              version = s$version, sha256 = sha, date = s$date)
    }
  }
  seen <- do.call(rbind, rows)
  key <- paste(seen$template, seen$version, seen$sha256)
  first <- !duplicated(key)
  index <- seen[first, c("template", "file", "version", "sha256")]
  index$first <- as.vector(tapply(seen$date, key, min)[key[first]])
  index$last <- as.vector(tapply(seen$date, key, max)[key[first]])
  rownames(index) <- NULL
  list(texts = texts, index = index)
}

.history_state <- new.env(parent = emptyenv())

# The shipped archive, read once per session. A test names another file with
# the option `hvtiRtemplates.template_history`.
.template_history <- function() {
  path <- getOption("hvtiRtemplates.template_history",
                    system.file("extdata", "template-history.rds", package = "hvtiRtemplates"))
  if (!identical(.history_state$path, path)) {
    if (!nzchar(path) || !file.exists(path)) stop("the template archive is missing: ", path, call. = FALSE)
    .history_state$value <- readRDS(path)
    .history_state$path <- path
  }
  .history_state$value
}

.text_lines <- function(text) {
  lines <- strsplit(text, "\r?\n")[[1L]]
  if (!length(lines)) character() else lines
}

# The texts a job stamped `template version [sha256]` may have been copied
# from, each list(sha256, lines, first), oldest first. A hash names at most one
# text; without one, every text the index lists for that template at that
# version is a candidate. The installed template counts too: a job scaffolded
# from `main` after a template changed has that text's hash before the next
# bump rebuilds the archive. Empty when there is none.
.base_candidates <- function(template, version, sha256, history = .template_history(),
                             current = .current_template(template)) {
  ix <- history$index[history$index$template == template, , drop = FALSE]
  ix <- if (is.na(sha256)) ix[ix$version == version, , drop = FALSE] else ix[ix$sha256 == sha256, , drop = FALSE]
  ix <- ix[!duplicated(ix$sha256), , drop = FALSE]
  ix <- ix[order(ix$first), , drop = FALSE]
  out <- lapply(seq_len(nrow(ix)), function(i) {
    list(sha256 = ix$sha256[[i]], lines = .text_lines(history$texts[[ix$sha256[[i]]]]), first = ix$first[[i]])
  })
  wanted <- !is.null(current) &&
    if (is.na(sha256)) identical(current$version, version) else identical(current$sha256, sha256)
  if (wanted && !current$sha256 %in% ix$sha256) {
    # The newest text there is, so it goes last.
    out[[length(out) + 1L]] <- list(sha256 = current$sha256, lines = .text_lines(current$text), first = NA_character_)
  }
  out
}

# The installed text of a template, as list(sha256, text, version), or NULL
# for a template this install does not have.
.current_template <- function(template) {
  rows <- template_list()
  file <- rows$file[rows$name == template]
  if (length(file) != 1L || !file.exists(file)) return(NULL)
  raw <- readBin(file, "raw", file.size(file))
  list(sha256 = digest::digest(raw, algo = "sha256", serialize = FALSE), text = rawToChar(raw),
       version = as.character(utils::packageVersion("hvtiRtemplates")))
}
