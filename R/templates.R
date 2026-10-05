#' List the supported R job templates
#'
#' These templates are supported: they render, they are tested, and they are
#' the intended starting point for a new analysis job.
#'
#' A template is named \code{<prefix>.qmd}, or
#' \code{<prefix>-<qualifier>.qmd} where one prefix carries several job
#' types, and lives in a numbered directory named for the taxonomy folder it
#' scaffolds into, so \code{folder} is read from the tree rather than looked
#' up. The directory's leading digits order the folders and are stripped from
#' \code{folder}. The placement test requires the job catalog and skips when
#' it is absent. Its internal lookup helper uses the catalog's
#' \code{(prefix, qualifier)} row, falling back to
#' \code{\link{hvti_taxonomy}} when the catalog or matching row is absent.
#' A separate test checks that every template directory names a taxonomy
#' folder, including when the catalog is absent.
#'
#' @return A data frame with columns \code{name}, \code{prefix},
#'   \code{qualifier}, \code{folder}, \code{call} and \code{file}.
#'   \code{call} is the \code{\link{add_job}} call that scaffolds the
#'   template, with only the arguments it requires and runnable as printed,
#'   e.g. \code{add_job("dc-gfup", subject = "cohort", type = "eda")}. The
#'   \code{subject} and \code{type} shown are the template's own defaults;
#'   change them to name the job. \code{folder} is the
#'   taxonomy name with the directory's ordering digits stripped, so
#'   \code{20_distributions} reports as \code{distributions}.
#'   \code{qualifier} is \code{NA} for a prefix carrying a single template.
#' @export
#' @examples
#' template_list()
template_list <- function() {
  dir <- system.file("templates", package = "hvtiRtemplates")
  files <- if (nzchar(dir)) {
    list.files(dir, pattern = "[.]qmd$", full.names = TRUE, recursive = TRUE)
  } else {
    character(0)
  }
  fields <- do.call(rbind, lapply(basename(files), .template_fields))
  if (is.null(fields)) {
    fields <- data.frame(prefix = character(0), qualifier = character(0),
                         stringsAsFactors = FALSE)
  }

  data.frame(
    name      = sub("[.]qmd$", "", basename(files)),
    prefix    = fields$prefix,
    qualifier = fields$qualifier,
    folder    = .folder_name(basename(dirname(files))),
    call      = vapply(files, .template_call, character(1), USE.NAMES = FALSE),
    file      = files,
    stringsAsFactors = FALSE
  )
}

# The add_job() call that scaffolds `file`, runnable as printed. The full name
# selects the template on its own, qualified or not, so subject and type are
# the only other arguments add_job() requires. Their values are the template's
# own SUBJECT and TYPE lines, the ones add_job() rewrites, so the example is
# one that fits the template, and naming the arguments shows they are the
# caller's to change. NA where a template lacks exactly one of either line,
# which add_job() refuses to scaffold anyway.
.template_call <- function(file) {
  txt <- readLines(file, warn = FALSE)
  value <- function(marker) {
    line <- grep(paste0("^", marker, "\\s+<- "), txt, value = TRUE)
    if (length(line) != 1L) return(NA_character_)
    sub('^[^"]*"([^"]*)".*$', "\\1", line)
  }
  subject <- value("SUBJECT")
  type <- value("TYPE")
  if (is.na(subject) || is.na(type)) return(NA_character_)
  sprintf('add_job("%s", subject = "%s", type = "%s")', sub("[.]qmd$", "", basename(file)), subject, type)
}

#' Path to a supported template
#'
#' @param prefix Analysis prefix, e.g. \code{"ac"}, or a template's full name,
#'   e.g. \code{"dp-trends"}, which carries its qualifier and leaves
#'   \code{qualifier} \code{NULL}. See \code{\link{template_list}}.
#' @param qualifier Job type within the prefix, e.g. \code{"trends"} for
#'   \code{dp}. Required only where a prefix carries more than one template;
#'   omitting it there is an error naming the choices, never a silent pick.
#' @return The full path, as \code{character(1)}. A template the catalog
#'   marks deprecated, such as \code{dp-postage}, still resolves, with a
#'   warning naming its replacement.
#' @export
#' @examples
#' try(template_path("ac"))
template_path <- function(prefix, qualifier = NULL) {
  row <- .select_template(template_list(), prefix, qualifier)
  .warn_if_deprecated(row, "template_path")
  row$file[[1L]]
}

# The catalog row marking (prefix, qualifier) deprecated, or NULL. The marker
# is the catalog's `deprecated_by` field, so deprecating a template is a
# catalog edit and no template name is written into the code.
.template_deprecation <- function(prefix, qualifier = NULL) {
  catalog <- template_catalog()
  same <- if (is.null(qualifier) || is.na(qualifier)) {
    is.na(catalog$qualifier)
  } else {
    !is.na(catalog$qualifier) & catalog$qualifier == qualifier
  }
  hit <- catalog[!is.na(catalog$prefix) & catalog$prefix == prefix & same &
                   !is.na(catalog$deprecated_by), , drop = FALSE]
  if (nrow(hit) != 1L) return(NULL)
  list(name = if (is.na(hit$qualifier)) hit$prefix else paste0(hit$prefix, "-", hit$qualifier),
       deprecated_by = hit$deprecated_by, note = hit$deprecation_note)
}

# Warn once when a selected template row is deprecated, naming the caller.
.warn_if_deprecated <- function(row, fn) {
  deprecated <- .template_deprecation(row$prefix[[1L]], row$qualifier[[1L]])
  if (is.null(deprecated)) return(invisible(NULL))
  .warn_deprecated(paste0(fn, "(): ", deprecated$name, " is deprecated in favor of ",
                          deprecated$deprecated_by, ". ", deprecated$note))
}

# The warning carries its own class, so a caller that has already warned, as
# open_job() has before it calls add_job(), can muffle the repeat.
.warn_deprecated <- function(message) {
  warning(structure(class = c("hvtiRtemplates_deprecated", "warning", "condition"),
                    list(message = message, call = NULL)))
}

# Resolve (prefix, qualifier) to exactly one template row, or stop.
#
# The rule is that ambiguity is an ERROR, not a default. A prefix carrying four
# templates and a caller naming none is a question the caller has not answered,
# and answering it for them by taking the first row is how `dp` came to look
# like one job type in the first place: `match()` returns the first hit and says
# nothing about the rest. See
# dev/specs/2026-09-02-dp-dc-decomposition-design.md section 8.
#
# `qualifier = NULL` is still accepted where the prefix has exactly one
# template, so existing unqualified calls keep their meaning.
.select_template <- function(tl, prefix, qualifier = NULL) {
  # Validate before comparing. `hit$qualifier == NA_character_` is NA, not
  # FALSE, so an NA qualifier produces NA-indexed rows and an error that names
  # nothing useful; a length-2 qualifier recycles silently. `add_job()` screens
  # its argument, `template_path()` did not, and this is the shared path.
  # Raised by Copilot on #76.
  # `prefix` gets the same treatment as `qualifier`. Validating one argument
  # and not its sibling is how a length-2 prefix reaches `tl$prefix == prefix`,
  # recycles, and selects rows nobody asked for. The old `match()` path errored
  # cleanly there, so leaving it unchecked would be a regression as well as a
  # gap. Raised by Copilot on #76.
  .check_scalar_string("prefix", prefix)
  parts <- .split_template_name(prefix, qualifier)
  prefix <- parts$prefix
  qualifier <- parts$qualifier
  hit <- tl[!is.na(tl$prefix) & tl$prefix == prefix, , drop = FALSE]
  if (!nrow(hit)) {
    stop("unknown template: ", prefix,
         if (nrow(tl)) {
           paste0(". Available: ",
                  paste(sort(unique(stats::na.omit(tl$prefix))), collapse = ", "))
         } else {
           ". No templates are installed yet."
         },
         call. = FALSE)
  }
  # A prefix half-decomposed is a broken estate, not a choice. The ambiguity
  # error below lists `<none>` for an unqualified row, and a caller cannot ask
  # for it: naming a qualifier filters to qualified rows, and naming none is
  # the ambiguity. Rather than invent an NA sentinel to select a row that
  # should not exist, say so. Raised by Copilot on #76.
  # `any(is.na())` alone called two UNQUALIFIED rows "mixed", which they are
  # not: that is a duplicate pair, a different fault with a different fix.
  # Mixed means BOTH kinds present. Raised by Copilot on #76.
  n_unqualified <- sum(is.na(hit$qualifier))
  if (n_unqualified > 0L && n_unqualified < nrow(hit)) {
    stop("prefix '", prefix, "' mixes qualified and unqualified templates: ",
         paste(basename(hit$file), collapse = ", "),
         ". Decomposing a prefix means naming every job under it.",
         call. = FALSE)
  }
  if (n_unqualified > 1L) {
    stop("prefix '", prefix, "' has ", n_unqualified,
         " unqualified templates; the (prefix, qualifier) pair must be ",
         "unique. Found: ", paste(basename(hit$file), collapse = ", "),
         call. = FALSE)
  }
  if (!is.null(qualifier)) {
    q <- hit[!is.na(hit$qualifier) & hit$qualifier == qualifier, , drop = FALSE]
    if (!nrow(q)) {
      stop("prefix '", prefix, "' has no template qualified '", qualifier,
           "'. Available for this prefix: ", .qualifier_menu(hit), call. = FALSE)
    }
    # A named pair matching more than once is a broken estate, not a choice.
    # Returning the first row here would be the same silent pick this function
    # exists to refuse, one level further in: the caller takes [[1L]] and never
    # learns there was a second. Raised by Copilot on #76.
    if (nrow(q) > 1L) {
      stop("prefix '", prefix, "' has ", nrow(q), " templates qualified '",
           qualifier, "'; the pair must be unique. Found: ",
           paste(basename(q$file), collapse = ", "), call. = FALSE)
    }
    return(q)
  }
  if (nrow(hit) > 1L) {
    stop("prefix '", prefix, "' carries ", nrow(hit),
         " templates; name one with `qualifier`, or by its full name. Available: ",
         .qualifier_menu(hit), call. = FALSE)
  }
  hit
}

# One non-empty, non-NA string, or stop. `hit$qualifier == NA_character_` is
# NA rather than FALSE, so an NA argument produces NA-indexed rows and an error
# naming nothing useful, and a length-2 argument recycles silently.
.check_scalar_string <- function(what, x) {
  if (length(x) != 1L || !is.character(x) || is.na(x) || !nzchar(x)) {
    stop("template selection: `", what, "` must be a single non-empty, ",
         "non-NA string. Got ", class(x)[[1L]], " of length ", length(x), ".",
         call. = FALSE)
  }
  invisible(x)
}

# The qualifiers on offer for a prefix, for an error message. An unqualified
# template is shown as NA rather than omitted, so a prefix holding one
# unqualified and two qualified templates reads as the three it is.
# Each is shown by its full name, "dp-trends", which is also a form a caller
# can type back.
.qualifier_menu <- function(hit) {
  paste(ifelse(is.na(hit$qualifier), hit$prefix, paste0(hit$prefix, "-", hit$qualifier)), collapse = ", ")
}

# Split a template's full name, "dp-trends", into prefix and qualifier, as
# template_list() reports it in `name`. A prefix may never contain "-", so
# splitting at the first one is exact. A full name AND a qualifier are two
# answers to one question; refusing is safer than preferring either. The
# qualifier is validated first, so a bad one is reported as itself.
# `prefix` must already be a single string.
.split_template_name <- function(prefix, qualifier = NULL) {
  if (!is.null(qualifier)) .check_scalar_string("qualifier", qualifier)
  if (!grepl("-", prefix, fixed = TRUE)) return(list(prefix = prefix, qualifier = qualifier))
  if (!is.null(qualifier)) {
    stop("template selection: name the template by its full name ('", prefix,
         "') or as prefix plus qualifier, not both.", call. = FALSE)
  }
  if (!grepl("^[^-]+-[^-]+$", prefix)) {
    stop("template selection: '", prefix, "' is not a template name; ",
         "expected <prefix>-<qualifier>, e.g. 'dp-trends'.", call. = FALSE)
  }
  list(prefix = sub("-.*$", "", prefix), qualifier = sub("^[^-]*-", "", prefix))
}

# Parse a template file name into its fields.
#
# A template is named `<prefix>[-<qualifier>].qmd` and lives in a numbered
# taxonomy directory, `20_distributions/ac.qmd`. The name carries no ordinal.
#
# ⭐ The ordinal was dropped on 2026-09-03, see
# dev/specs/2026-09-03-template-identity-design.md. It was `<NN>.<MM>-`, where
# `NN` was the taxonomy folder's position and `MM` a key assigned once per
# folder. `NN` duplicated the directory the file already sits in, and `MM`
# asserted an order among templates in a folder that does not exist. The
# digits now live on the DIRECTORY, where they order the folders and are the
# thing rather than a copy of it.
#
# A name that does not match returns NA rather than erroring: `template_list()`
# reports what is on disk, and a stray file should not stop it. The "every
# template name parses" test in test-templates.R turns an unparsed name into a
# build failure.
.template_fields <- function(name) {
  m <- regmatches(
    name,
    regexec("^([A-Za-z0-9]+)(?:-([A-Za-z0-9_]+))?[.]qmd$", name)
  )[[1L]]
  if (length(m) != 3L) {
    return(data.frame(prefix = NA_character_, qualifier = NA_character_,
                      stringsAsFactors = FALSE))
  }
  data.frame(
    prefix = m[[2L]],
    # regexec returns "" for an optional group that did not participate. That
    # is a MATCH of an empty qualifier, not an absent one, and the two must
    # stay distinguishable.
    qualifier = if (nzchar(m[[3L]])) m[[3L]] else NA_character_,
    stringsAsFactors = FALSE
  )
}

# The taxonomy folder name for a numbered template directory.
#
# `20_distributions` -> `distributions`. The digits order the directories for
# anyone reading `inst/templates/`; the name after them is the taxonomy's, and
# it is what a study's own folders are called. A directory without the numeric
# prefix is returned unchanged, so the function is safe on a hand-made path.
.folder_name <- function(dir) sub("^[0-9]+_", "", dir)

# Qualified catalog rows take precedence over the prefix-wide taxonomy.
.template_folder_authority <- function(prefix, qualifier, catalog = NULL) {
  fallback <- hvti_taxonomy()$folder[match(prefix, hvti_taxonomy()$prefix)]
  if (is.null(catalog) || !nrow(catalog)) return(fallback)
  if (anyDuplicated(catalog[c("prefix", "qualifier")])) {
    dup <- catalog[duplicated(catalog[c("prefix", "qualifier")]), , drop = FALSE]
    names <- ifelse(is.na(dup$qualifier), dup$prefix, paste(dup$prefix, dup$qualifier, sep = "-"))
    stop("template catalog has more than one row for the same (prefix, qualifier): ",
         paste(names, collapse = ", "), call. = FALSE)
  }
  same_qualifier <- if (is.null(qualifier) || is.na(qualifier)) {
    is.na(catalog$qualifier)
  } else {
    !is.na(catalog$qualifier) & catalog$qualifier == qualifier
  }
  hit <- which(!is.na(catalog$prefix) & catalog$prefix == prefix & same_qualifier)
  if (!length(hit)) return(fallback)
  folder <- catalog$folder[hit]
  if (length(folder) != 1L || is.na(folder) || !nzchar(folder)) {
    stop("Matching job catalog row has no folder.", call. = FALSE)
  }
  folder
}
