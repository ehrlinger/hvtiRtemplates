#' Render a job only down to this point
#'
#' @description
#' Called in a chunk of a job, \code{stop_here()} ends the render there: the
#' report keeps everything above it and leaves out everything below. It is how
#' a part-built job is rendered, in place of commenting its unfinished sections
#' out. To leave out one chunk in the middle instead, give that chunk a
#' \code{skip} option with the reason:
#' \verb{#| skip: "waiting on the corrected coding"}.
#'
#' @details
#' Both are allowed in a draft and refused in a final render, by the same rule
#' as an unresolved \code{EDIT:} marker. A draft lists each one, with its line
#' and reason, in a callout at the top of the report, so a partial report
#' cannot pass for a whole one. \code{\link{render_job}} with
#' \code{final = TRUE}, or any render with \code{HVTI_TEMPLATE_STRICT} set,
#' stops while any remains. Both are found by reading the job's source, so they
#' show in a diff and in review, as commented-out code does not. A
#' \code{stop_here()} the source scan cannot see, as inside an \code{if ()} or
#' called with an argument, refuses a final render itself when it runs, and in a
#' draft is recorded in the report's provenance as a stop.
#'
#' A \code{skip} must give a reason as a non-empty quoted string;
#' \code{skip: true} is an error. A skipped chunk is neither run nor shown, so a
#' later chunk that needs what it would have made fails: use
#' \code{stop_here()} above both instead.
#'
#' Outside a render, run line by line or with Run All, \code{stop_here()} does
#' nothing, so the chunks below it still run interactively.
#'
#' A job's provenance is embedded by its last chunk, which a stopped render
#' never reaches, so \code{stop_here()} embeds it instead: the data the job
#' read, its subject and type, and the partial-render points. Call it on its own
#' line at the end of a chunk, so the chunk shows what it returns.
#'
#' @param envir The environment the job's chunks run in, where its data
#'   provenance, \code{SUBJECT} and \code{TYPE} are found. The default is right
#'   inside a chunk.
#' @return Outside a render, \code{NULL}, invisibly. Inside one, the job's
#'   provenance block, for the chunk to print as the last output of the report.
#' @seealso \code{\link{render_job}}
#' @examples
#' # Outside a render it does nothing.
#' stop_here()
#' @export
stop_here <- function(envir = parent.frame()) {
  if (!isTRUE(getOption("knitr.in.progress")) || !requireNamespace("knitr", quietly = TRUE)) {
    return(invisible(NULL))
  }
  # The source scan finds only a stop_here() alone on its line, so this one
  # checks too: one inside an if () or with an argument would otherwise end a
  # final render early, unnoticed and unrecorded.
  if (.strict_render()) {
    stop("stop_here() ran in a render with HVTI_TEMPLATE_STRICT set: a final report is the whole job. ",
         "Remove each skip and stop_here() first.", call. = FALSE)
  }
  if (!any(vapply(.partial_state$points, function(p) identical(p$kind, "stop"), logical(1L)))) {
    .partial_state$points <- c(.partial_state$points, list(list(
      line = NA_integer_, kind = "stop", reason = "the render stopped here, at a stop_here() the source scan did not find"
    )))
  }
  input <- get0(".in", envir = envir, ifnotfound = NULL)
  if (is.null(input)) input <- knitr::current_input(dir = TRUE)
  extra <- Filter(Negate(is.null), list(subject = get0("SUBJECT", envir = envir, ifnotfound = NULL),
                                        type = get0("TYPE", envir = envir, ifnotfound = NULL)))
  provenance <- .embed_provenance(input, data = get0(".provenance_data", envir = envir, ifnotfound = list()),
                                  extra = extra)
  knitr::knit_exit()
  knitr::asis_output(provenance)
}

# The partial-render points in a job's source: every `skip` chunk option and
# every stop_here() call. Read from the source, as the EDIT: guard reads its
# markers, so a draft can list them at the top before any of them is reached.
#
# Only live syntax counts. A skip is read only from the option header of an
# executable R chunk (the `#|` lines straight after a ```{r} fence), and a stop
# only from the body of one that runs, so a fenced documentation example, a
# plain code block, a `#|` line further down a chunk, or a stop_here() in an
# `eval: false` chunk is left alone. Fences follow Markdown: a block opened
# with N backticks closes at a line of N or more, and nothing inside a block
# opens another, which is how a ````-fenced example can show a ```{r} chunk.
# Raised in review on #243. The patterns are built in pieces so this file's
# own text never matches them.
.partial_points <- function(src) {
  skip_re <- paste0("^#\\|\\s*sk", "ip:\\s*")
  stop_re <- paste0("^\\s*(hvtiRtemplates::)?st", "op_here\\(\\s*\\)")
  skips <- integer()
  stops <- integer()
  fence <- NULL
  executable <- FALSE
  header <- FALSE
  runs <- TRUE
  for (i in seq_along(src)) {
    line <- src[[i]]
    if (is.null(fence)) {
      open <- regmatches(line, regexpr("^`{3,}", line))
      if (length(open)) {
        fence <- open
        executable <- grepl("^`{3,}\\s*\\{r([ ,}]|$)", line)
        header <- executable
        runs <- TRUE
      }
      next
    }
    if (grepl(paste0("^", fence, "`*\\s*$"), line)) {
      fence <- NULL
      next
    }
    if (!executable) next
    if (header && grepl("^#\\|", line)) {
      # A chunk that will not run holds no stop: eval false, or a skip, which
      # the skip hook turns into eval false.
      if (grepl("^#\\|\\s*eval:", line)) runs <- .eval_runs(sub("^#\\|\\s*eval:", "", line))
      if (grepl(skip_re, line)) {
        skips <- c(skips, i)
        runs <- FALSE
      }
      next
    }
    header <- FALSE
    if (runs && grepl(stop_re, line)) stops <- c(stops, i)
  }
  reason <- trimws(sub(skip_re, "", src[skips]))
  quoted <- grepl("^(\"[^\"]*\"|'[^']*')$", reason)
  reason <- ifelse(quoted, substr(reason, 2L, nchar(reason) - 1L), "")
  bad <- skips[!quoted | !nzchar(trimws(reason))]
  if (length(bad)) {
    stop("A `skip` chunk option needs its reason as a quoted string, for example ",
         "#| skip: \"waiting on the corrected coding\". Line(s) ", paste(bad, collapse = ", "),
         " give none.", call. = FALSE)
  }
  rbind(
    data.frame(line = skips, kind = rep("skip", length(skips)), reason = reason),
    data.frame(line = stops, kind = rep("stop", length(stops)),
               reason = rep("the render stops here; everything below is left out", length(stops)))
  )[order(c(skips, stops)), , drop = FALSE]
}

# This render's partial-render points, for .embed_provenance(), and the job
# whose render registered the skip hook. Package state rather than options():
# knitr restores options() after a knit but not opts_hooks, and a package
# should not leave the user's options changed.
.partial_state <- new.env(parent = emptyenv())

# Whether a chunk's `eval:` value lets it run, read as knitr reads it. The value
# is parsed as YAML, the parser knitr uses for `#|` options, so every false
# spelling it accepts counts (false, no, off, n, in any case) and nothing else
# does: a bare F is the string "F" to that parser, not FALSE. An `!expr` is not
# evaluated here, since scanning must not run the job's code: only a literal
# FALSE or F counts as false, and any other expression is taken to run, so a
# stop that might be reached stays listed. Raised by Codex on #257.
.eval_runs <- function(value) {
  value <- trimws(value)
  if (grepl("^!expr\\s", value)) return(!(trimws(sub("^!expr\\s+", "", value)) %in% c("FALSE", "F")))
  parsed <- tryCatch(yaml::yaml.load(paste0("eval: ", value), eval.expr = FALSE)$eval, error = function(e) NULL)
  !identical(parsed, FALSE)
}

# A final render: HVTI_TEMPLATE_STRICT set, as render_job(final = TRUE) sets it.
.strict_render <- function() !tolower(Sys.getenv("HVTI_TEMPLATE_STRICT")) %in% c("", "0", "false", "no")

# Called by every template's guard-partial chunk, just after the EDIT: guard.
# Registers the `skip` chunk option, then lists the job's partial-render points
# in a draft or stops a strict render, by the EDIT: guard's own strictness rule.
.guard_partial <- function(input) {
  .partial_state$points <- NULL
  .partial_state$input <- input
  if (requireNamespace("knitr", quietly = TRUE)) {
    # knitr cannot unregister a hook when the knit ends, so the hook stays in
    # the session. It acts only while the job that set it is the one knitting;
    # any other document's `skip` option passes through untouched.
    knitr::opts_hooks$set(skip = function(options) {
      if (!identical(knitr::current_input(), .partial_state$input)) return(options)
      if (!is.character(options$skip) || length(options$skip) != 1L || !nzchar(trimws(options$skip))) {
        stop("Chunk `", options$label, "`: `skip` needs its reason as a quoted string, for example ",
             "skip: \"waiting on the corrected coding\".", call. = FALSE)
      }
      options$eval <- FALSE
      options$include <- FALSE
      options
    })
  }
  if (is.null(input) || !file.exists(input)) return(invisible(character()))
  points <- .partial_points(readLines(input, warn = FALSE))
  if (!nrow(points)) return(invisible(character()))
  # Read by .embed_provenance(), so the report's provenance says it is partial
  # whichever chunk embeds it.
  .partial_state$points <- lapply(unname(split(points, seq_len(nrow(points)))), as.list)
  items <- paste0("  - line ", points$line, ": ",
                  ifelse(points$kind == "skip", paste0("chunk skipped, ", points$reason), points$reason))
  msg <- paste0("This job is rendered in part (", nrow(points), " point(s)):\n", paste(items, collapse = "\n"))
  if (.strict_render()) {
    stop(msg, "\nThis render stops because HVTI_TEMPLATE_STRICT is set: a final report is the whole job. ",
         "Remove each skip and stop_here() first.", call. = FALSE)
  }
  warning(msg, call. = FALSE)
  out <- paste0("\n::: {.callout-important title=\"PARTIAL -- parts of this job are left out\"}\n",
                "**This report is not the whole job.**\n\n```\n", msg, "\n```\n:::\n\n")
  # Returned, not cat(): the guard-partial chunk is `results: asis`, so knitr
  # prints it into the report, and nothing is written to the console. knitr is
  # only suggested; without it there is no report to print into.
  if (!requireNamespace("knitr", quietly = TRUE)) return(invisible(out))
  knitr::asis_output(out)
}
