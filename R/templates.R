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
#' \code{folder}. \code{\link{hvti_taxonomy}} is a cross-check
#' on that, enforced by the test suite, not a source for it.
#'
#' @return A data frame with columns \code{name}, \code{prefix},
#'   \code{qualifier}, \code{folder} and \code{file}. \code{folder} is the
#'   taxonomy name with the directory's ordering digits stripped, so
#'   \code{20_distributions} reports as \code{distributions}.
#'   \code{qualifier} is \code{NA} for a prefix carrying a single template,
#'   which is every template shipped today.
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
    file      = files,
    stringsAsFactors = FALSE
  )
}

#' Path to a supported template
#'
#' @param prefix Analysis prefix, e.g. \code{"ac"}. See \code{\link{template_list}}.
#' @param qualifier Job type within the prefix, e.g. \code{"trends"} for
#'   \code{dp}. Required only where a prefix carries more than one template;
#'   omitting it there is an error naming the choices, never a silent pick.
#' @return The full path, as \code{character(1)}.
#' @export
#' @examples
#' try(template_path("ac"))
template_path <- function(prefix, qualifier = NULL) {
  .select_template(template_list(), prefix, qualifier)$file[[1L]]
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
# template, which is every template shipped today, so no existing call changes.
.select_template <- function(tl, prefix, qualifier = NULL) {
  # Validate before comparing. `hit$qualifier == NA_character_` is NA, not
  # FALSE, so an NA qualifier produces NA-indexed rows and an error that names
  # nothing useful; a length-2 qualifier recycles silently. `new_job()` screens
  # its argument, `template_path()` did not, and this is the shared path.
  # Raised by Copilot on #76.
  # `prefix` gets the same treatment as `qualifier`. Validating one argument
  # and not its sibling is how a length-2 prefix reaches `tl$prefix == prefix`,
  # recycles, and selects rows nobody asked for. The old `match()` path errored
  # cleanly there, so leaving it unchecked would be a regression as well as a
  # gap. Raised by Copilot on #76.
  .check_scalar_string("prefix", prefix)
  if (!is.null(qualifier)) .check_scalar_string("qualifier", qualifier)
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
         " templates; name one with `qualifier`. Available: ",
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
.qualifier_menu <- function(hit) {
  paste(ifelse(is.na(hit$qualifier), "<none>", hit$qualifier), collapse = ", ")
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
