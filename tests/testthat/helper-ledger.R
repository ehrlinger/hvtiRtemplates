# Shared access to the job catalog for the test suite.
#
# These helpers were defined at the top of `test-roadmap.R` until 2026-09-09.
# They moved here because `test-taxonomy.R` needs them too: testthat sources
# each test file in its own environment, so a function defined in one is not
# visible in another, and the alternative was a second copy of the path
# resolution. A second copy is exactly the defect that retired the
# `FOLDER_ORDINAL` guard -- a constant copied from an authority in another
# repository, free to drift. One copy, loaded by testthat before any test.
#
# The catalog does not live in this repo. It is in the sibling package
# `hvtiR`, at `inst/extdata/jobs.json`. `ledger_path()` resolves it the same
# way `dev/specs/artifacts/roadmap_render.py`'s `catalog_path()` does: the
# `HVTI_JOBS` environment variable first, then a sibling `hvtiR` checkout next
# to this repo, so a developer or CI runner has one convention across both
# languages.

ledger_path <- function() {
  env <- Sys.getenv("HVTI_JOBS")
  if (nzchar(env)) {
    return(env)
  }
  # testthat runs with the working directory at tests/testthat/, so the repo
  # root is two levels up. The sibling `hvtiR` checkout sits next to the repo
  # root, one level further up again -- matching
  # `roadmap_render.py`'s `../hvtiR/inst/extdata/jobs.json` relative to the
  # repo root. `testthat::test_path()` is not used: it resolves inside
  # tests/testthat/, and the catalog is deliberately outside the package.
  file.path("..", "..", "..", "hvtiR", "inst", "extdata", "jobs.json")
}

require_ledger <- function() {
  if (file.exists(ledger_path())) {
    return(invisible(TRUE))
  }

  # HVTI_JOBS being set is an explicit claim about where the catalog lives.
  # A wrong claim is a developer's typo or a broken CI variable, not a normal
  # "no sibling checkout" state, so it errors regardless of strict mode --
  # unlike the sibling-checkout fallback below, this has no legitimate absent
  # case to fall through to.
  env <- Sys.getenv("HVTI_JOBS")
  if (nzchar(env)) {
    stop("HVTI_JOBS is set to ", env, ", but no file exists there")
  }

  # The catalog is absent from a built package and from a checkout with no
  # sibling `hvtiR` -- that is not a failure, it is the file being
  # deliberately outside this repo.
  #
  # But on the SOURCE tree in CI the catalog IS available (via HVTI_JOBS or a
  # checked-out sibling), and a skip would mean the path resolution broke. A
  # silently skipped guard is worse than no guard: it reports green while
  # checking nothing, which is the exact failure this file exists to prevent.
  # So CI sets HVTI_ROADMAP_STRICT and a skip becomes a hard stop there.
  if (nzchar(Sys.getenv("HVTI_ROADMAP_STRICT"))) {
    stop("job catalog not found at ", ledger_path(),
         ", but HVTI_ROADMAP_STRICT is set -- the source tree should have it")
  }
  testthat::skip("job catalog not present")
}

require_jsonlite <- function() {
  if (requireNamespace("jsonlite", quietly = TRUE)) {
    return(invisible(TRUE))
  }
  # Same discipline as require_ledger(): under HVTI_ROADMAP_STRICT a skip is a
  # failure, so a missing Suggests dependency must be as loud as a missing
  # catalog, not the one remaining silent skip path in this file.
  if (nzchar(Sys.getenv("HVTI_ROADMAP_STRICT"))) {
    stop("jsonlite is not installed, but HVTI_ROADMAP_STRICT is set -- ",
         "the source tree's test environment should have it")
  }
  testthat::skip("jsonlite not installed")
}

# The catalog is written by `hvtiR` as `{"jobs": [...]}`; an older local
# ledger used `{"prefixes": [...]}`. Both are accepted here for the same
# reason `roadmap_render.load_catalog()` accepts both: a stray old-shaped file
# still reads, rather than failing on a key name that used to be right.
ledger_rows <- function() {
  ledger <- jsonlite::fromJSON(ledger_path(), simplifyDataFrame = FALSE)
  if (!is.null(ledger$jobs)) {
    return(ledger$jobs)
  }
  if (!is.null(ledger$prefixes)) {
    return(ledger$prefixes)
  }
  stop(ledger_path(), " has neither a top-level 'jobs' nor 'prefixes' key")
}

# The catalog's rows, or NULL when it cannot be read.
#
# Unlike require_ledger(), this NEVER skips and never stops. It is for a check
# that has a working answer without the catalog and only a better one with it.
ledger_rows_or_null <- function() {
  if (!file.exists(ledger_path())) {
    return(NULL)
  }
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    return(NULL)
  }
  tryCatch(ledger_rows(), error = function(e) NULL)
}

# A lookup key for a (prefix, qualifier) pair.
#
# ⚠️ An absent qualifier must not collapse into a present one spelled the same.
# `paste()` renders NA as the three characters "NA", so a hypothetical row
# qualified "NA" and an unqualified row would share a key and one would
# silently shadow the other. A qualifier matches `[A-Za-z0-9_]+`, so it can
# never be empty and never contain a control character: "" marks absent and
# "\r" separates, and neither can occur inside a real qualifier.
.pair_key <- function(prefix, qualifier) {
  qualifier <- ifelse(is.na(qualifier), "", as.character(qualifier))
  paste(as.character(prefix), qualifier, sep = "\r")
}

# The folder each template in `tl` is expected to sit in.
#
# `hvti_taxonomy()` maps a prefix to ONE folder, but a prefix may span several.
# `dp` is `graphs` for trends/gfup/spaghetti/procs and `distributions` for
# variable, with a `descriptive` row planned for the postage-stamp sweep. The
# job catalog records `folder` PER ROW, keyed on (prefix, qualifier), so it is
# the finer authority and is consulted first. See
# `dev/specs/2026-09-09-eda-templates-design.md` section 8.3 and issue #97.
#
# The taxonomy answers for any template the catalog has no row for, and for
# every template when the catalog is absent.
#
# ⚠️ Deliberately does NOT skip when the catalog is missing. The taxonomy
# fallback still catches a template filed under a folder no study uses, which
# is most of this check's value. A silently skipped guard is worse than no
# guard, which is the discipline require_ledger() states and this must not
# quietly opt out of.
expected_template_folders <- function(tl) {
  tx <- hvti_taxonomy()
  folder <- tx$folder[match(tl$prefix, tx$prefix)]

  rows <- ledger_rows_or_null()
  if (is.null(rows) || length(rows) == 0L) {
    return(folder)
  }

  # ⚠️ Filter to the rows this repo owns BEFORE matching. The catalog covers
  # every destination, and `check-roadmap-counts.py` only guarantees
  # (prefix, qualifier) uniqueness AFTER the same filter -- its own comment
  # says "a prefix mixed across destinations would not be caught here". Match
  # unfiltered and another package's row can shadow ours. The predicate is
  # copied from `roadmap_render.py`'s `load_catalog()`: destination absent or
  # null means unrouted and is kept.
  rows <- Filter(function(r) {
    is.null(r$destination) || identical(as.character(r$destination),
                                        "hvtiRtemplates")
  }, rows)
  if (length(rows) == 0L) {
    return(folder)
  }

  row_folder <- vapply(rows, function(r) {
    if (is.null(r$folder)) NA_character_ else as.character(r$folder)
  }, character(1))
  row_key <- vapply(rows, function(r) {
    .pair_key(r$prefix, if (is.null(r$qualifier)) NA_character_ else r$qualifier)
  }, character(1))

  # ⚠️ And stop rather than pick, if the pair is not unique even after
  # filtering. `match()` returns the first hit and says nothing about the
  # rest, which is the shape of the bug that made `dp` look like one job type
  # and that `template_path()` refuses to repeat. The Python guard enforces
  # this uniqueness, but it is a different language in a different workflow,
  # so relying on it silently would put this file one CI regression away from
  # picking a row at random.
  if (anyDuplicated(row_key)) {
    dup <- unique(row_key[duplicated(row_key)])
    # Render the key back as a reader would write it: `dp-variable` when
    # qualified, bare `ac` when not. A naive separator swap gives "ac-", which
    # reads as a qualifier that is empty rather than absent, and this message
    # is the entire value of stopping here.
    stop("job catalog has more than one row routed to hvtiRtemplates for ",
         "the same (prefix, qualifier): ",
         paste(sub("\r", "-", sub("\r$", "", dup)), collapse = ", "))
  }

  hit <- match(.pair_key(tl$prefix, tl$qualifier), row_key)
  from_catalog <- row_folder[hit]

  # A template with no catalog row, or a row carrying no folder, keeps the
  # taxonomy's answer rather than becoming NA and failing on a comparison that
  # was never about it.
  ifelse(is.na(from_catalog), folder, from_catalog)
}
