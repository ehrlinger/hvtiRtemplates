# The code each cache_fit() call in one template chunk keys on, for the calls whose name argument
# contains `name` (a fixed string, quotes included where that disambiguates). The code may be written
# inline or held in a variable the same chunk assigns with quote(): cache_fit() keys on the deparsed
# code, and both spellings deparse alike, so a template can move a call into quote() without making
# the fits cached by earlier copies stale. A snapshot of this text is what proves it did not.
cached_code <- function(prefix, qualifier, label, name) {
  src <- readLines(template_path(prefix, qualifier), warn = FALSE)
  exprs <- parse(text = rf_chunk(src, label), keep.source = FALSE)  # nolint: object_usage_linter.
  calls <- list()
  quoted <- list()
  walk <- function(e) {
    if (!is.call(e)) return(invisible())
    fn <- e[[1L]]
    if (identical(fn, as.name("cache_fit")) && grepl(name, paste(deparse(e[[2L]]), collapse = ""), fixed = TRUE)) {
      calls[[length(calls) + 1L]] <<- e
    }
    if (identical(fn, as.name("<-")) && is.name(e[[2L]]) && is.call(e[[3L]])) {
      found <- quotes_in(e[[3L]])
      if (length(found)) quoted[[as.character(e[[2L]])]] <<- found
    }
    args <- as.list(e)[-1L]
    for (i in seq_along(args)) if (!identical(args[[i]], quote(expr = ))) walk(args[[i]])
  }
  for (e in exprs) walk(e)
  if (!length(calls)) stop("no cache_fit() call named like ", name, " in chunk ", label, call. = FALSE)
  # A call written twice with the same code, as a check and then the fit, keys alike: each text once.
  unique(unlist(lapply(calls, function(call) {
    code <- call[[3L]]
    codes <- if (is.name(code)) quoted[[as.character(code)]] else list(code)
    if (is.null(codes)) stop("cache_fit() reads ", as.character(code), ", which no quote() in chunk ", label, " assigns",
                             call. = FALSE)
    vapply(codes, hvtiRutilities:::.cache_code_text, character(1L))
  })))
}

# Every quote() in an expression, such as both branches of `if (...) quote(a) else quote(b)`. A
# bquote() is spliced with each ..() it names at list(), a setting's default, so it reads as the code
# a job left at that default keys on.
quotes_in <- function(e) {
  if (!is.call(e)) return(list())
  if (identical(e[[1L]], as.name("quote"))) return(list(e[[2L]]))
  if (identical(e[[1L]], as.name("bquote"))) {
    spliced <- character()
    find <- function(x) {
      if (!is.call(x)) return(invisible())
      if (identical(x[[1L]], as.name("..")) && is.name(x[[2L]])) spliced <<- c(spliced, as.character(x[[2L]]))
      for (a in as.list(x)[-1L]) if (!identical(a, quote(expr = ))) find(a)
    }
    find(e[[2L]])
    at <- list2env(stats::setNames(rep(list(list()), length(spliced)), spliced))
    return(list(eval(e, at)))
  }
  args <- as.list(e)[-1L]
  unlist(lapply(seq_along(args), function(i) if (identical(args[[i]], quote(expr = ))) list() else quotes_in(args[[i]])),
         recursive = FALSE)
}

# Replaces a chunk environment's progress reporter with one that records each step. The function
# returned gives the steps recorded since it was last called, as c(unit, step, total).
progress_recorder <- function(env) {
  seen <- new.env()
  seen$steps <- list()
  env$.job$progress <- function(unit) function(step, total) seen$steps[[length(seen$steps) + 1L]] <- c(unit, step, total)
  function() {
    out <- seen$steps
    seen$steps <- list()
    out
  }
}
