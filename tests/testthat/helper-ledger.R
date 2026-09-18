# Shared access to the template catalog for roadmap and folder tests.

ledger_path <- function() {
  override <- Sys.getenv("HVTI_TEMPLATES", unset = "")
  if (nzchar(override)) return(override)
  installed <- system.file("extdata", "templates.json",
                           package = "hvtiRtemplates")
  if (nzchar(installed)) return(installed)
  testthat::test_path("..", "..", "inst", "extdata", "templates.json")
}

require_ledger <- function() {
  if (file.exists(ledger_path())) {
    return(invisible(TRUE))
  }

  stop("Template catalog not found at ", ledger_path(), call. = FALSE)
}

require_jsonlite <- function() {
  if (requireNamespace("jsonlite", quietly = TRUE)) {
    return(invisible(TRUE))
  }
  stop("jsonlite is required to read the template catalog", call. = FALSE)
}

# The catalog is written by `hvtiR` as `{"jobs": [...]}`; an older local
# ledger used `{"prefixes": [...]}`. Both are accepted here for the same
# reason `roadmap_render.load_catalog()` accepts both: a stray old-shaped file
# still reads, rather than failing on a key name that used to be right.
ledger_rows <- function() {
  ledger <- jsonlite::fromJSON(ledger_path(), simplifyDataFrame = FALSE)
  if (!is.list(ledger$templates)) {
    stop(ledger_path(), " has no top-level 'templates' array")
  }
  ledger$templates
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
# This helper does not skip when the catalog is missing; it answers from the
# taxonomy. Its caller, the placement test in test-taxonomy.R, does skip then,
# because a prefix spanning folders has no single taxonomy answer. The
# directory-name test beside it still runs without the catalog.
expected_template_folders <- function(tl) {
  rows <- ledger_rows_or_null()
  catalog <- if (!length(rows)) {
    NULL
  } else {
    fields <- lapply(c("prefix", "qualifier", "folder"), function(field) {
      vapply(rows, function(row) if (!length(row[[field]])) NA_character_ else as.character(row[[field]]), character(1L))
    })
    names(fields) <- c("prefix", "qualifier", "folder")
    as.data.frame(fields, stringsAsFactors = FALSE)
  }
  vapply(seq_len(nrow(tl)), function(i) {
    hvtiRtemplates:::.template_folder_authority(tl$prefix[i], tl$qualifier[i], catalog)
  }, character(1L))
}

# Moved here from test-taxonomy.R on 2026-09-17, when test-roadmap.R needed it
# too; see the header of this file for why a helper, and never a second copy.
# Write `rows` as a catalog to a temp file and point HVTI_TEMPLATES at it for the
# duration of `code`. Base R rather than withr: this package does not Suggest
# it, and adding a dependency to reach one helper is a poor trade.
with_temp_catalog <- function(rows, code) {
  # require_jsonlite(), not testthat::skip_if_not_installed(). The latter skips
  # silently even under HVTI_ROADMAP_STRICT, so a test built on this could drop out
  # of the strict step with it still reporting green, which is the defect this
  # block exists to prevent. require_jsonlite() always stops when missing.
  require_jsonlite()
  path <- tempfile(fileext = ".json")
  writeLines(jsonlite::toJSON(list(templates = rows), auto_unbox = TRUE), path)
  old <- Sys.getenv("HVTI_TEMPLATES", unset = NA)
  Sys.setenv(HVTI_TEMPLATES = path)
  on.exit({
    if (is.na(old)) Sys.unsetenv("HVTI_TEMPLATES") else Sys.setenv(HVTI_TEMPLATES = old)
    unlink(path)
  }, add = TRUE)
  force(code)
}

# The intake rows that do not say what they block on, by prefix.
#
# The intake guard's logic lives here, as a function returning a VALUE, rather
# than as assertions inside a loop in the test. A loop over zero rows makes no
# expectation, testthat reports that as an empty test, and an empty test is a
# SKIP -- which the strict CI step cannot see, because HVTI_ROADMAP_STRICT only
# promotes the helper-driven skips. `expect_identical(<this>, character(0))`
# is an assertion however many rows there are, zero included.
intake_without_blocker <- function(rows) {
  intake <- Filter(function(r) identical(r$status, "intake"), rows)
  named <- vapply(intake, function(r) {
    b <- r$blocked_on
    is.character(b) && length(b) == 1L && nzchar(b)
  }, logical(1))
  vapply(intake[!named], function(r) r$prefix, character(1))
}
