#' List the supported R job templates
#'
#' These templates are supported: they render, they are tested, and they are
#' the intended starting point for a new analysis job.
#'
#' A template is named \code{<NN.MM>-<prefix>.qmd}, or
#' \code{<NN.MM>-<prefix>-<qualifier>.qmd} where one prefix carries several job
#' types, and lives in the taxonomy
#' folder it scaffolds into, so \code{folder} and \code{ordinal} are read from
#' the tree rather than looked up. \code{\link{hvti_taxonomy}} is a cross-check
#' on that, enforced by the test suite, not a source for it.
#'
#' @return A data frame with columns \code{name}, \code{prefix},
#'   \code{qualifier}, \code{ordinal}, \code{folder} and \code{file}.
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
    fields <- data.frame(ordinal = character(0), prefix = character(0),
                         qualifier = character(0), stringsAsFactors = FALSE)
  }

  data.frame(
    name      = sub("[.]qmd$", "", basename(files)),
    prefix    = fields$prefix,
    qualifier = fields$qualifier,
    ordinal   = fields$ordinal,
    folder    = basename(dirname(files)),
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
  if (nrow(hit) > 1L && any(is.na(hit$qualifier))) {
    stop("prefix '", prefix, "' mixes qualified and unqualified templates: ",
         paste(basename(hit$file), collapse = ", "),
         ". Decomposing a prefix means naming every job under it.",
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
# A template is named `<NN>.<MM>-<prefix>[-<qualifier>].qmd` -- "03.01-ac.qmd",
# or "06.03-dp-trends.qmd" where one prefix carries several job types. The
# qualifier is what `graphs/dp` needed: `trends`, `spaghetti` and `procs` are
# distinct jobs sharing a prefix, and a name that cannot say which is a name a
# study author cannot search. See
# dev/specs/2026-09-02-dp-dc-decomposition-design.md, which decided this.
#
# The prefix capture is `[A-Za-z0-9]+`, NOT `.+` as it was until 2026-09-02.
# `.+` is greedy and would read "06.03-dp-trends.qmd" as the single prefix
# "dp-trends", which parses, validates and is wrong. Restricting the prefix and
# making `-` the field separator is what keeps the two fields apart. It also
# means a prefix may never contain `-`, which matches `hvti_taxonomy()`.
#
# The name is
# fully structured, so it is matched by pattern rather than split on separators:
# `.` is a field separator inside the ordinal AND the extension separator, and a
# split-based parser cannot tell the two apart. This replaces `.prefix_of()`,
# whose heuristics (drop a leading "tp.", reject a first field over five
# characters) existed only because legacy names were unstructured.
#
# The two digits either side of the dot are required. The zero-padding is what
# makes a flat folder sort into run order past nine entries, so an unpadded name
# is rejected here rather than allowed to sort wrongly later.
#
# Returns `ordinal`, `prefix` and `qualifier` as NA for a name that does not match, rather
# than erroring: `template_list()` reports what is on disk, and a stray file
# should not stop it. The "every template name parses" test in
# test-templates.R is what turns an unparsed name into a build failure.
.template_fields <- function(name) {
  m <- regmatches(
    name,
    regexec("^(\\d{2}[.]\\d{2})-([A-Za-z0-9]+)(?:-([A-Za-z0-9_]+))?[.]qmd$", name)
  )[[1L]]
  if (length(m) != 4L) {
    return(data.frame(ordinal = NA_character_, prefix = NA_character_,
                      qualifier = NA_character_, stringsAsFactors = FALSE))
  }
  data.frame(
    ordinal = m[[2L]],
    prefix  = m[[3L]],
    # regexec returns "" for an optional group that did not participate. That
    # is a MATCH of an empty qualifier, not an absent one, and the two must
    # stay distinguishable: `03.01-ac.qmd` has no qualifier and must not read
    # as one that is blank.
    qualifier = if (nzchar(m[[4L]])) m[[4L]] else NA_character_,
    stringsAsFactors = FALSE
  )
}
