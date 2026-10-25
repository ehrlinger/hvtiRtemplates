# The labels a descriptive table prints, kept apart from the labels the dataset
# carries. A dataset's labels serve the analysis: they come from SAS, carry
# "Preoperative" on every row and codings such as "(Y/N)", and are shared by
# every job in the study. A manuscript table needs its own, and nobody should
# type them into Word by hand. Raised on a mitral study's table at the 2026-10-22
# Mitral umbrella meeting (items R3, R4 and I3 in the vault's harvest note).
#
# Three layers, applied in this order and only to the copy of the data the
# table is drawn from:
#   1. value_labels.yml at the study root gives coded columns their level text
#      (NYHA 1 to 4 as I to IV, an approach code as its name), through
#      hvtiRutilities::apply_value_labels(). Levels are declarations, never a
#      rule in code.
#   2. table_labels.yml at the study root, the same name-to-label mapping as
#      labels_overrides.yml, gives a variable the label its table prints. It
#      is read here and nowhere else, so the analysis labels stay as they are.
#      A study writes it once and every table job in the study shares it.
#   3. Rules in code tidy every other label: a leading "Preoperative", a
#      trailing coding hint, sentence case that keeps abbreviations, and the
#      m2 of a unit as a superscript. Each can be turned off.
# Every label that changed, and every variable with no label at all, is
# returned in `changes`, so the report can say what was rewritten and why.

.table_label_rule_names <- c("preoperative", "coding", "case", "units")

# One label through the rules `use` names. Returns the new label and the rules
# that changed it. `protect` is the abbreviations to keep in their own case,
# such as NYHA or MR, compared ignoring case.
.table_label_rules <- function(label, use = .table_label_rule_names, protect = character(0)) {
  # A coding (Y/N, 0/1) and a note to the analyst, "(for analysis)" or
  # "(incision use for analysis)", serve the dataset and not the reader.
  hint <- "(\\((y/n|0/1|[^()]*\\bfor analysis)\\)|\\b(y/n|0/1))[[:space:],:-]*$"
  rewrite <- list(
    preoperative = function(x) {
      sub("^(pre-?op(erative)?)(?![[:alpha:]])[[:space:]:,.-]*", "", x, ignore.case = TRUE, perl = TRUE)
    },
    coding = function(x) sub(hint, "", sub(hint, "", x, ignore.case = TRUE, perl = TRUE), ignore.case = TRUE, perl = TRUE),
    case = function(x) .sentence_case(x, protect),
    units = function(x) gsub("/m2(?![0-9^])", "/m^2^", x, ignore.case = TRUE, perl = TRUE)
  )
  fired <- character(0)
  for (rule in intersect(names(rewrite), use)) {
    new <- trimws(gsub("\\s+", " ", rewrite[[rule]](label)))
    if (nzchar(new) && !identical(new, label)) {
      fired <- c(fired, rule)
      label <- new
    }
  }
  list(label = label, rules = fired)
}

# Sentence case: the first word capitalized, every other word lower case,
# except an abbreviation in `protect` and a word that is plainly an acronym
# already, upper case past its first letter or holding a digit (MV, ASD, eGFR).
# A word spelled exactly as an abbreviation is kept as written, so AVR is never
# turned into AVr when the list holds both. A word that differs only in case is
# given the abbreviation's spelling (Nyha to NYHA), but only when it carries a
# capital: a lower-case "as" or "or" is a word, not AS or OR. A label written
# wholly in capitals says nothing about which of its words are acronyms, so
# there only `protect` counts.
.sentence_case <- function(label, protect = character(0)) {
  shouting <- !grepl("[[:lower:]]", label)
  at <- gregexpr("[[:alpha:]][[:alnum:]]*", label)[[1L]]
  if (at[[1L]] < 0L) return(label)
  words <- regmatches(label, list(at))[[1L]]
  exact <- words %in% protect
  acronym <- exact | !shouting & (grepl("^.[[:alnum:]]*[[:upper:]]|^[[:upper:]]$", words) | grepl("[[:digit:]]", words))
  known <- ifelse(acronym | !grepl("[[:upper:]]", words), NA_integer_, match(toupper(words), toupper(protect)))
  out <- ifelse(acronym, words, ifelse(!is.na(known), protect[known], tolower(words)))
  if (is.na(known[[1L]]) && !acronym[[1L]]) {
    out[[1L]] <- paste0(toupper(substr(out[[1L]], 1L, 1L)), substring(out[[1L]], 2L))
  }
  regmatches(label, list(at)) <- list(out)
  label
}

# A column carrying value labels as a factor of its level text, the levels in
# code order and only the codes the data hold, so a declared but unseen level
# does not print a row of zeros. A code with no declared text keeps its code.
# Two codes may share one text (8 and 9 both "Unknown"); they become one level,
# and attribute "codes" keeps each code's text, so nothing reads that map back
# from the levels, which are fewer than the codes.
.level_factor <- function(x) {
  labels <- attr(x, "labels", exact = TRUE)
  label <- attr(x, "label", exact = TRUE)
  values <- as.vector(unclass(x))
  attributes(values) <- NULL
  codes <- sort(unique(values[!is.na(values)]))
  text <- as.character(codes)
  hit <- match(codes, as.vector(unclass(labels)))
  text[!is.na(hit)] <- names(labels)[hit[!is.na(hit)]]
  out <- factor(values, levels = codes, labels = text)
  attr(out, "label") <- label
  attr(out, "codes") <- stats::setNames(text, codes)
  out
}

# YAML 1.1 reads an unquoted No or Yes as a logical, so `0: No` would print a
# level FALSE; the text is kept as written instead.
.read_label_yaml <- function(path, what) {
  if (!file.exists(path)) return(list())
  as_written <- function(x) x
  read <- yaml::read_yaml(path, handlers = list("bool#yes" = as_written, "bool#no" = as_written))
  if (is.null(read)) return(list())
  if (!is.list(read) || is.null(names(read)) || any(!nzchar(names(read)))) {
    stop(basename(path), " must map each variable name to its ", what, ".", call. = FALSE)
  }
  read
}

# The data the table is drawn from, relabeled, and a data frame of what
# changed: variable, from, to, rule. `vars` are the columns the table shows
# (its rows and its BY column); nothing else is touched. `rules` is TRUE for
# every rule, FALSE for none, or the names of the rules to apply. `keep_codes`
# are columns summarized as numbers, which keep their codes whatever
# value_labels.yml declares. The result's `levels` holds, for each column given
# level text, that text named by the code it replaced.
.table_labels <- function(data, vars, root, rules = TRUE, protect = character(0), keep_codes = character(0),
                          labels_file = file.path(root, "table_labels.yml"),
                          value_labels_file = file.path(root, "value_labels.yml")) {
  vars <- intersect(unique(as.character(vars)), names(data))
  if (isTRUE(rules)) {
    use <- .table_label_rule_names
  } else if (isFALSE(rules)) {
    use <- character(0)
  } else if (is.character(rules) && !anyNA(rules) && all(rules %in% .table_label_rule_names)) {
    use <- rules
  } else {
    stop("TABLE_LABEL_RULES must be TRUE, FALSE, or some of: ",
         paste(.table_label_rule_names, collapse = ", "), ".", call. = FALSE)
  }
  changes <- list(data.frame(variable = character(0), from = character(0), to = character(0), rule = character(0)))
  note <- function(variable, from, to, rule) data.frame(variable = variable, from = from, to = to, rule = rule)

  # The study's file declares every coded variable in the study, and this
  # table shows a few, so only those are passed on: apply_value_labels() warns
  # about a declared variable the data lack, which here would be all the rest.
  declared <- .read_label_yaml(value_labels_file, "codes and their text")
  carried <- vars[vapply(data[vars], function(x) length(attr(x, "labels", exact = TRUE)) > 0L, logical(1))]
  carried <- setdiff(carried, keep_codes)
  mine <- declared[setdiff(intersect(names(declared), vars), c(carried, keep_codes))]
  if (length(mine)) {
    subset_file <- tempfile(fileext = ".yml")
    on.exit(unlink(subset_file), add = TRUE)
    yaml::write_yaml(mine, subset_file)
    data <- hvtiRutilities::apply_value_labels(data, subset_file)
  }
  levels <- list()
  for (v in c(carried, names(mine))) {
    data[[v]] <- .level_factor(data[[v]])
    levels[[v]] <- attr(data[[v]], "codes")
    attr(data[[v]], "codes") <- NULL
    codes <- names(levels[[v]])
    origin <- if (v %in% carried) "value labels carried by the data" else basename(value_labels_file)
    changes <- c(changes, list(note(v, paste("levels", paste(codes, collapse = ", ")),
                                    paste("levels", paste(levels(data[[v]]), collapse = ", ")), origin)))
  }

  overrides <- .read_label_yaml(labels_file, "table label")
  for (v in vars) {
    from <- attr(data[[v]], "label", exact = TRUE)
    from <- if (length(from) == 1L && !is.na(from)) as.character(from) else ""
    if (v %in% names(overrides)) {
      to <- overrides[[v]]
      if (!is.character(to) || length(to) != 1L || is.na(to) || !nzchar(to)) {
        stop(basename(labels_file), " must give ", v, " one label as text.", call. = FALSE)
      }
      if (!identical(to, from)) changes <- c(changes, list(note(v, from, to, basename(labels_file))))
    } else if (!nzchar(from)) {
      changes <- c(changes, list(note(v, "", v, paste("no label: the table prints the column name; give it one in",
                                                      basename(labels_file)))))
      next
    } else {
      cleaned <- .table_label_rules(from, use, protect)
      if (!length(cleaned$rules)) next
      to <- cleaned$label
      changes <- c(changes, list(note(v, from, to, paste(cleaned$rules, collapse = ", "))))
    }
    attr(data[[v]], "label") <- to
  }
  list(data = data, changes = do.call(rbind, changes), levels = levels)
}

# Writes into a saved Word table what built it, as document properties: Word
# shows them under File > Info, and they travel with the file when it is
# emailed, which the report's provenance does not. A .docx that reaches a
# reader by itself can then answer "which version made this?" without anyone
# finding the job (item R1 of the 2026-10-22 Mitral umbrella meeting, where
# the table being critiqued turned out to predate two releases).
.stamp_docx <- function(path, run, data = list(), caption = NULL) {
  stamp <- function(p) {
    if (!requireNamespace(p, quietly = TRUE)) return(NA_character_)
    # A package installed from CRAN or RSPM carries its version as RemoteSha;
    # only a git install's 40-hex sha names a commit worth printing.
    sha <- utils::packageDescription(p)$RemoteSha
    git <- length(sha) == 1L && grepl("^[0-9a-f]{40}$", sha)
    paste0(utils::packageVersion(p), if (git) paste0(" (", substr(sha, 1L, 7L), ")"))
  }
  packages <- c("hvtiRtemplates", "hvtiRtables", "flextable", "officer")
  versions <- vapply(packages, stamp, character(1))
  read <- vapply(data, function(r) {
    paste0(r$path %||% r$dataset %||% "data", if (!is.null(r$sha256)) paste0(" sha256 ", substr(r$sha256, 1L, 12L)))
  }, character(1))
  rendered <- .iso_time(run$started)
  description <- paste0(
    "Written by ", run$file %||% "a job", " (", run$state %||% "draft", " render) at ", rendered, ". ",
    paste(packages, versions, collapse = ", "), ".",
    if (length(read)) paste0(" Data: ", paste(read, collapse = "; "), ".")
  )
  values <- c(list(hvti_job = run$file %||% "", hvti_rendered = rendered, hvti_status = run$state %||% ""),
              stats::setNames(as.list(versions), paste0("hvti_", packages)),
              list(hvti_data = paste(read, collapse = "; ")))
  doc <- officer::read_docx(path)
  doc <- officer::set_doc_properties(doc, title = caption, subject = run$file, creator = run$user_name %||% run$user,
                                     description = description)
  doc <- officer::set_doc_properties(doc, values = values)
  print(doc, target = path)
  invisible(path)
}
