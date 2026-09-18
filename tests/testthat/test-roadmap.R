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

  # An intake row without a blocker is indistinguishable from a forgotten one.
  # The blocker is what tells a reader why it is not scheduled.
  #
  # ⚠️ This asserted inside a `for` over the intake rows until 2026-09-17.
  # Intake is legitimately EMPTY whenever every proposed prefix has landed, as
  # it did that day when `rfr`, `sid` and `vt` left it, and a `for` over zero
  # rows makes no expectation: testthat reports an empty test as a SKIP, and
  # the strict CI step cannot see that kind (HVTI_ROADMAP_STRICT promotes only
  # the helper-driven skips). The logic now lives in intake_without_blocker(),
  # which returns a value, so this is an assertion at any row count. The
  # empty case is covered below from a temporary catalog, because CI reads the
  # real one from a PINNED hvtiR tag and cannot be relied on to be empty.
  missing <- intake_without_blocker(ledger_rows())
  expect_identical(missing, character(0),
                   label = paste("intake rows with no blocked_on:",
                                 paste(missing, collapse = ", ")))
})

test_that("the intake guard asserts on an empty intake, and still catches", {
  # Regression for the defect above, driven from TEMPORARY catalogs so it does
  # not depend on what the real one happens to hold. CI checks hvtiR out at a
  # pinned tag whose catalog still has intake rows, so without this the empty
  # path would never run there and a revert to the `for` loop would stay green
  # until the pin moved. Raised by Copilot on #131.
  shipped <- list(prefix = "ac", status = "shipped")
  # No intake rows at all: an assertion is still made, and it passes.
  with_temp_catalog(list(shipped), {
    expect_identical(intake_without_blocker(ledger_rows()), character(0))
  })
  # An intake row that names its blocker passes.
  named <- list(prefix = "zz", status = "intake",
                blocked_on = "hvtiRutilities#1")
  with_temp_catalog(list(shipped, named), {
    expect_identical(intake_without_blocker(ledger_rows()), character(0))
  })
  # One with no blocker, or an empty one, is caught and named.
  absent <- list(prefix = "zz", status = "intake")
  empty <- list(prefix = "yy", status = "intake", blocked_on = "")
  with_temp_catalog(list(shipped, absent, empty), {
    expect_identical(intake_without_blocker(ledger_rows()), c("zz", "yy"))
  })
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
