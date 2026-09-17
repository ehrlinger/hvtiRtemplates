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

  # Direction two, with one exemption: a row at status "intake" names a prefix
  # that is PROPOSED and not in the taxonomy yet, and says so. Any other row
  # naming a prefix the taxonomy does not have is a typo or a stale row, and
  # fails.
  #
  # ⭐ The three rows this exemption was written for -- `rfr`, `sid` and `vt`
  # -- landed in `hvti_taxonomy()` via hvtiRutilities PR #127 (on its `main`,
  # in no release yet, so NOT in 1.2.0) and left intake on 2026-09-17, so the
  # exemption currently covers nothing. It stays because it is the MECHANISM,
  # not a special case for those three, and the next proposed prefix needs
  # it. Do not remove it on the grounds that intake is empty today.
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
  #
  # ⚠️ Asserted over the whole set rather than inside a `for`, because the set
  # is legitimately EMPTY whenever every proposed prefix has landed -- as it
  # was on 2026-09-17, when `rfr`, `sid` and `vt` left intake. A `for`
  # over zero rows makes no expectation at all, testthat reports that as an
  # "empty test", and an empty test reports as a SKIP. The strict CI step
  # expects SKIP 0, but HVTI_ROADMAP_STRICT only promotes the helper-driven
  # skips to hard stops and `stop_on_failure` does not fire on a skip, so this
  # gate would have gone quiet underneath a green check. `all()` of an empty
  # logical is TRUE, which is the right answer AND is still an assertion.
  named <- vapply(intake,
                  function(r) !is.null(r$blocked_on) && nzchar(r$blocked_on),
                  logical(1))
  expect_true(all(named),
              label = paste("intake rows with no blocked_on:",
                            paste(vapply(intake[!named], function(r) r$prefix,
                                         character(1)), collapse = ", ")))
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
