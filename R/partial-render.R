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
#' show in a diff and in review, as commented-out code does not.
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
  input <- get0(".in", envir = envir, ifnotfound = NULL)
  if (is.null(input)) input <- knitr::current_input(dir = TRUE)
  extra <- Filter(Negate(is.null), list(subject = get0("SUBJECT", envir = envir, ifnotfound = NULL),
                                        type = get0("TYPE", envir = envir, ifnotfound = NULL)))
  provenance <- .embed_provenance(input, data = get0(".provenance_data", envir = envir, ifnotfound = list()),
                                  extra = extra)
  knitr::knit_exit()
  knitr::asis_output(provenance)
}

# The partial-render points in a job's source: every `#| skip:` chunk option and
# every stop_here() call. Read from the source, as the EDIT: guard reads its
# markers, so a draft can list them at the top before any of them is reached.
# The patterns are built in pieces so this file's own text never matches them.
.partial_points <- function(src) {
  skip_re <- paste0("^#\\|\\s*sk", "ip:\\s*")
  stop_re <- paste0("^\\s*(hvtiRtemplates::)?st", "op_here\\(\\s*\\)")
  skips <- grep(skip_re, src)
  stops <- grep(stop_re, src)
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

# Called by every template's guard-partial chunk, just after the EDIT: guard.
# Registers the `skip` chunk option, then lists the job's partial-render points
# in a draft or stops a strict render, by the EDIT: guard's own strictness rule.
.guard_partial <- function(input) {
  if (requireNamespace("knitr", quietly = TRUE)) {
    knitr::opts_hooks$set(skip = function(options) {
      if (!is.character(options$skip) || length(options$skip) != 1L || !nzchar(trimws(options$skip))) {
        stop("Chunk `", options$label, "`: `skip` needs its reason as a quoted string, for example ",
             "skip: \"waiting on the corrected coding\".", call. = FALSE)
      }
      options$eval <- FALSE
      options$include <- FALSE
      options
    })
  }
  options(hvtiRtemplates.partial = NULL)
  if (is.null(input) || !file.exists(input)) return(invisible(character()))
  points <- .partial_points(readLines(input, warn = FALSE))
  if (!nrow(points)) return(invisible(character()))
  # Read by .embed_provenance(), so the report's provenance says it is partial
  # whichever chunk embeds it.
  options(hvtiRtemplates.partial = lapply(unname(split(points, seq_len(nrow(points)))), as.list))
  items <- paste0("  - line ", points$line, ": ",
                  ifelse(points$kind == "skip", paste0("chunk skipped, ", points$reason), points$reason))
  msg <- paste0("This job is rendered in part (", nrow(points), " point(s)):\n", paste(items, collapse = "\n"))
  if (!tolower(Sys.getenv("HVTI_TEMPLATE_STRICT")) %in% c("", "0", "false", "no")) {
    stop(msg, "\nThis render stops because HVTI_TEMPLATE_STRICT is set: a final report is the whole job. ",
         "Remove each skip and stop_here() first.", call. = FALSE)
  }
  warning(msg, call. = FALSE)
  out <- paste0("\n::: {.callout-important title=\"PARTIAL -- parts of this job are left out\"}\n",
                "**This report is not the whole job.**\n\n```\n", msg, "\n```\n:::\n\n")
  cat(out)
  invisible(out)
}
