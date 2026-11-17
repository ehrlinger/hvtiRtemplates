# The hvtiR family's shared conventions, implemented here in a few lines each
# rather than imported: Projects/hvtiR API rubric in the maintainer's vault.

# Quiet mode. Every informational message goes through this, so a study can
# silence the family at once with options(hvti.quiet = TRUE). Warnings and
# errors are never silenced by it. A function's own `quiet` argument stays,
# defaults to the option, and wins when given.
.hvti_inform <- function(...) {
  if (!isTRUE(getOption("hvti.quiet"))) message(...)
  invisible()
}

.hvti_quiet <- function() isTRUE(getOption("hvti.quiet"))

# An error a caller is expected to catch, classed hvtiRtemplates_<condition>.
# Base stop(), not rlang, with no call: the message carries the function name.
.abort <- function(..., class, parent = NULL) {
  stop(errorCondition(paste0(...), class = paste0("hvtiRtemplates_", class), call = NULL, parent = parent))
}

# Renamed arguments are deprecated for one release, then go. The old name keeps
# working with a warning once per session; giving both names is an error that
# names both, because a silent pick goes unnoticed on every later call.
.renamed_warned <- new.env(parent = emptyenv())

.take_renamed <- function(fn, old, new, value, new_given) {
  if (new_given) {
    stop(fn, "(): `", old, "` and `", new, "` were both given. `", old, "` is the old name of `", new,
         "`; give `", new, "` only.", call. = FALSE)
  }
  .warn_once(paste0(fn, ":", old), paste0(fn, "(): `", old, "` is renamed `", new, "`. The old name works for one ",
                                          "more release, then stops; this warning is shown once per session."))
  value
}

.warn_once <- function(key, message) {
  if (is.null(.renamed_warned[[key]])) {
    assign(key, TRUE, envir = .renamed_warned)
    .warn_deprecated(message)
  }
  invisible()
}

# A study-specific default is never a default: the argument becomes required,
# after one release in which leaving it out warns and takes the old value.
.dropped_default <- function(fn, arg, old_default) {
  .warn_once(paste0(fn, ":", arg, ":default"),
             paste0(fn, "(): `", arg, "` will have no default from the next release, because \"", old_default,
                    "\" is one study's identifier. Pass ", arg, " = \"", old_default, "\" to keep reading it; this ",
                    "warning is shown once per session."))
  old_default
}

# The hvtiR family's shared provenance record for a run: seven fields, each
# present and typed, NA where a value does not apply, so a table prints a gap
# rather than a plausible value. `method` is the template the job was made from.
.run_provenance <- function(run, template, envir) {
  # packageDescription() gives a bare NA, not a list, when it cannot find the package.
  desc <- suppressWarnings(utils::packageDescription("hvtiRtemplates"))
  sha <- if (is.list(desc)) desc$RemoteSha
  seed <- get0("SEED", envir = envir, inherits = FALSE)
  whole <- length(seed) == 1L && is.numeric(seed) && !is.na(seed) && seed == trunc(seed) &&
    abs(seed) <= .Machine$integer.max
  list(
    package = "hvtiRtemplates",
    version = .package_version(),
    sha = if (is.character(sha) && length(sha) == 1L && nzchar(sha)) sha else NA_character_,
    method = if (is.character(template) && length(template) == 1L) template else NA_character_,
    seed = if (whole) as.integer(seed) else NA_integer_,
    rng_kind = RNGkind(),
    time = if (inherits(run$started, "POSIXct")) run$started else as.POSIXct(NA)
  )
}
