# The roadmap ledger's vocabulary must match the taxonomy's.
#
# This lives in R rather than beside the other roadmap guards in Python for one
# reason: it needs `hvti_taxonomy()`, and R is where that already is. The
# Python guard checks everything the filesystem can answer on its own; this
# checks the one thing it cannot.
#
# The catalog itself no longer lives in this repo. It moved to the sibling
# package `hvtiR`, at `inst/extdata/jobs.json`. `ledger_path()` resolves it the
# same way `dev/specs/artifacts/roadmap_render.py`'s `catalog_path()` does:
# the `HVTI_JOBS` environment variable first, then a sibling `hvtiR` checkout
# next to this repo, so a developer or CI runner only has one convention to
# learn across both languages.
#
# This test deliberately covers ALL 53 rows, not only the ones destined for
# hvtiRtemplates. The Python disk/doc checks filter to this repo's rows
# because they ask "does a template exist for this". This file asks a
# different question: does the catalog's vocabulary match `hvti_taxonomy()`.
# A row routed to another package (hvtiPlotR, say) still has to name a real
# taxonomy prefix, so no destination filter belongs here.
#
# On a built tarball the sibling checkout is absent and `HVTI_JOBS` is unset,
# so the catalog cannot be found. Without the skip below, every check of a
# built package would fail on a file that is deliberately not part of it.

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

test_that("every taxonomy prefix has a roadmap row", {
  require_ledger()
  skip_if_not_installed("jsonlite")

  rows <- ledger_rows()
  in_ledger <- vapply(rows, function(r) r$prefix, character(1))
  tx <- stats::na.omit(hvti_taxonomy()$prefix)

  # Direction one: nothing the taxonomy names may be unscheduled. A prefix
  # added upstream in hvtiRutilities fails here until the roadmap accounts for
  # it, which is the whole point -- otherwise it arrives silently and nobody
  # decides which family it belongs to.
  expect_setequal(intersect(tx, in_ledger), as.character(tx))
})

test_that("every roadmap row is a taxonomy prefix, unless it is intake", {
  require_ledger()
  skip_if_not_installed("jsonlite")

  rows <- ledger_rows()
  tx <- as.character(stats::na.omit(hvti_taxonomy()$prefix))

  # Direction two, with one exemption. `rfr`, `sid` and `vt` are PROPOSED and
  # deliberately not in the taxonomy yet -- they block on a PR to
  # hvtiRutilities. They carry status "intake" to say so. Any other row naming
  # a prefix the taxonomy does not have is a typo or a stale row, and fails.
  live <- Filter(function(r) !identical(r$status, "intake"), rows)
  live_prefixes <- vapply(live, function(r) r$prefix, character(1))
  expect_true(all(live_prefixes %in% tx),
              label = paste("ledger rows not in the taxonomy:",
                            paste(setdiff(live_prefixes, tx), collapse = ", ")))
})

test_that("an intake row names what it blocks on", {
  require_ledger()
  skip_if_not_installed("jsonlite")

  intake <- Filter(function(r) identical(r$status, "intake"), ledger_rows())

  # An intake row without a blocker is indistinguishable from a forgotten one.
  # The blocker is what tells a reader why it is not scheduled.
  for (r in intake) {
    expect_true(!is.null(r$blocked_on) && nzchar(r$blocked_on),
                label = paste("intake row", r$prefix, "has no blocked_on"))
  }
})

# ⭐ RETIRED 2026-09-03: "the guard's folder map still matches the taxonomy".
#
# It parsed `FOLDER_ORDINAL` out of `check-roadmap-counts.py` and compared it
# against `hvti_taxonomy()`'s folder order, because that map was HARDCODED and
# copied an authority living in another repository. It could go stale the same
# way `bh`'s 04.06 did.
#
# The map is gone. `check_disk()` now derives the folder-to-directory mapping
# by reading `inst/templates/` itself, so there is no second copy to drift.
# The right response to "this constant can go stale" turned out to be deleting
# the constant, not testing it harder.
#
# What still holds is checked in test-taxonomy.R, "every template directory is
# <NN>_<taxonomy folder>": the directories must name folders the taxonomy has.
# Their DIGITS are deliberately unchecked against row position -- `estimates`
# is 90 though it is fifth -- because assigning identity from position is the
# defect this whole change removes.
