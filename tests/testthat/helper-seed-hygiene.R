# Seed hygiene, ported from the AVSD virtual-twins study (2026-10-07). Every
# call that draws from R's generator must be seeded where it runs, and a
# randomForestSRC-family call must also carry a NEGATIVE `seed =`:
#
# * varpro() given the same `seed =` after a different chunk gave different
#   importances, because it also draws from R's generator. `seed =` alone does
#   not pin it.
# * rfsrc() with no `seed =` takes one from R's generator, so the forest depends
#   on what ran before it, cache hits and misses of earlier chunks included.
# * set.seed(s) just before the call AND `seed = -abs(s)` in it reproduced to
#   the last digit across a 192-thread server and a single-threaded Mac.

# Calls that draw from R's generator.
seed_random_calls <- c(
  "rfsrc", "rfsrc.fast", "imbalanced", "isopro", "varpro", "cv.varpro", "uvarpro", "impute", "impute.rfsrc",
  "sidClustering", "mice", "partialpro", "gg_partial_varpro", "outpro", "get.beta.entropy", "vimp",
  "tune.rfsrc", "boostmtree", "sample", "sample.int", "runif", "rnorm", "rbinom", "rpois", "rexp"
)

# The subset that must also be handed a negative `seed =`: the randomForestSRC
# family members that HAVE a `seed` argument (randomForestSRC 3.9.0, varPro
# 3.3.0). imbalanced(), impute() and isopro() have none to require.
seed_negative_calls <- c("rfsrc", "vimp", "tune.rfsrc", "varpro", "cv.varpro", "uvarpro")

# A call counts as seeded when a set.seed() starts this many lines before it or
# fewer, in the same chunk. "Just before", as the study put it; a seed further
# up has usually been consumed by something else by the time the call runs.
seed_window <- 3L

# Random calls that are random on purpose, keyed "<file>:<function>" with the
# reason. Empty today: every random call in a shipped template is seeded. The
# package's own one, the stats::runif() in R/provenance.R's render_id, is
# outside this scan and random on purpose, since a reproducible render id
# would defeat it.
seed_allow <- c()

# Violations in one unit of R source (a chunk or a file), as "label:line: why".
seed_violations <- function(text, label, offset = 0L) {
  exprs <- tryCatch(parse(text = text, keep.source = TRUE), error = function(e) e)
  if (inherits(exprs, "error")) return(sprintf("%s: does not parse: %s", label, conditionMessage(exprs)))
  pd <- utils::getParseData(exprs, includeText = TRUE)
  if (is.null(pd) || !nrow(pd)) return(character(0))
  calls <- pd[pd$token == "SYMBOL_FUNCTION_CALL", c("id", "parent", "line1", "col1", "text")]
  # SYMBOL_FUNCTION_CALL sits in an expr that is the function position of the
  # call, so the call is that expr's parent; `pkg::fn` resolves the same way.
  calls$call <- pd$parent[match(calls$parent, pd$id)]
  parent_of <- stats::setNames(pd$parent, pd$id)
  ancestors <- function(id) {
    out <- integer(0)
    while (!is.na(id <- parent_of[as.character(id)]) && id > 0L) out <- c(out, id)
    out
  }
  call_of <- function(id) str2lang(utils::getParseText(pd, id))
  seed_arg <- function(id) as.list(call_of(id))[["seed"]]
  # A wrapper seeds everything inside it: with_seed() always, cache_fit() when
  # it is given a non-NULL `seed =`.
  wrappers <- calls$call[calls$text == "with_seed" |
                           (calls$text == "cache_fit" &
                              vapply(calls$call, function(id) !is.null(seed_arg(id)), logical(1)))]
  seeds <- calls[calls$text == "set.seed", ]
  out <- character(0)
  for (i in which(calls$text %in% seed_random_calls)) {
    fn <- calls$text[i]
    if (paste0(label, ":", fn) %in% names(seed_allow)) next
    where <- sprintf("%s:%d", label, offset + calls$line1[i])
    if (fn %in% seed_negative_calls) {
      s <- seed_arg(calls$call[i])
      negative <- (is.call(s) && identical(s[[1]], as.name("-")) && length(s) == 2L) || (is.numeric(s) && all(s < 0))
      if (!negative) out <- c(out, sprintf("%s: %s() needs a negative `seed =`, e.g. seed = -abs(SEED)", where, fn))
    }
    if (fn == "mice" && !is.null(seed_arg(calls$call[i]))) next  # mice seeds itself from `seed =`
    if (any(wrappers %in% ancestors(calls$call[i]))) next
    before <- seeds$line1 < calls$line1[i] | (seeds$line1 == calls$line1[i] & seeds$col1 < calls$col1[i])
    if (any(before & calls$line1[i] - seeds$line1 <= seed_window)) next
    out <- c(out, sprintf("%s: %s() is not seeded: wrap it in cache_fit(seed = ) or put set.seed() just before it",
                          where, fn))
  }
  out
}

# The R chunks of a .qmd, each with the line its code starts on. Chunks are
# checked one at a time: a set.seed() in an earlier chunk does not count, since
# a cached chunk between them can be skipped on the next render.
seed_qmd_chunks <- function(path) {
  src <- readLines(path, warn = FALSE)
  opens <- grep("^```\\{r[ ,}]", src)
  lapply(opens, function(at) {
    end <- at + which(src[(at + 1L):length(src)] == "```")[1L]
    list(text = src[(at + 1L):(end - 1L)], offset = at)
  })
}

# Every violation in the .qmd files under `templates`, as "file:line: why".
seed_hygiene_scan <- function(templates) {
  out <- character(0)
  for (f in list.files(templates, pattern = "[.]qmd$", recursive = TRUE, full.names = TRUE)) {
    label <- substring(f, nchar(templates) + 2L)
    for (chunk in seed_qmd_chunks(f)) out <- c(out, seed_violations(chunk$text, label, chunk$offset))
  }
  out
}
