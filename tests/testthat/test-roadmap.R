# The roadmap ledger's vocabulary must match the taxonomy's.
#
# This lives in R rather than beside the other roadmap guards in Python for one
# reason: it needs `hvti_taxonomy()`, and R is where that already is. The
# Python guard checks everything the filesystem can answer on its own; this
# checks the one thing it cannot.
#
# The catalog itself no longer lives in this repo. It moved to the sibling
# package `hvtiR`, at `inst/extdata/jobs.json`. `ledger_path()`,
# `require_ledger()`, `require_jsonlite()` and `ledger_rows()` moved to
# `helper-ledger.R` on 2026-09-09, because `test-taxonomy.R` needs them too
# and testthat gives each test file its own environment.
#
# This test deliberately covers ALL 53 rows, not only the ones destined for
# hvtiRtemplates. The Python disk/doc checks filter to this repo's rows
# because they ask "does a template exist for this". This file asks a
# different question: does the catalog's vocabulary match `hvti_taxonomy()`.
# A row routed to another package (hvtiPlotR, say) still has to name a real
# taxonomy prefix, so no destination filter belongs here.
#
# On a built tarball the sibling checkout is absent and `HVTI_JOBS` is unset,
# so the catalog cannot be found. `require_ledger()` skips there, or stops
# under HVTI_ROADMAP_STRICT; without it every check of a built package would
# fail on a file that is deliberately not part of it.

test_that("every taxonomy prefix has a roadmap row", {
  require_ledger()
  require_jsonlite()

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
  require_jsonlite()

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
  require_jsonlite()

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
