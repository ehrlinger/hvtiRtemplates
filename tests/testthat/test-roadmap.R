# The roadmap ledger's vocabulary must match the taxonomy's.
#
# This lives in R rather than beside the other roadmap guards in Python for one
# reason: it needs `hvti_taxonomy()`, and R is where that already is. The
# Python guard checks everything the filesystem can answer on its own; this
# checks the one thing it cannot.
#
# `dev/` is .Rbuildignore'd, so the ledger is ABSENT from a built package and
# from `R CMD check` on the tarball. Without the skip below, every check of a
# built package would fail on a missing file that is deliberately missing.

ledger_path <- function() {
  # testthat runs with the working directory at tests/testthat/, so the repo
  # root is two levels up -- which is what the `".."`, `".."` below say.
  # `testthat::test_path()` is not used: it resolves inside tests/testthat/,
  # and the ledger is deliberately outside the package.
  file.path("..", "..", "dev", "specs", "artifacts",
            "2026-08-29-template-roadmap.json")
}

require_ledger <- function() {
  if (file.exists(ledger_path())) {
    return(invisible(TRUE))
  }
  # `dev/` is .Rbuildignore'd, so the ledger is absent from a built package and
  # these tests must skip there -- that is not a failure, it is the file being
  # deliberately out of the tarball.
  #
  # But on the SOURCE tree in CI the ledger IS present, and a skip would mean
  # the path resolution broke. A silently skipped guard is worse than no guard:
  # it reports green while checking nothing, which is the exact failure this
  # file exists to prevent. So CI sets HVTI_ROADMAP_STRICT and a skip becomes
  # a hard stop there.
  if (nzchar(Sys.getenv("HVTI_ROADMAP_STRICT"))) {
    stop("roadmap ledger not found at ", ledger_path(),
         ", but HVTI_ROADMAP_STRICT is set -- the source tree should have it")
  }
  testthat::skip("roadmap ledger not present")
}

test_that("every taxonomy prefix has a roadmap row", {
  require_ledger()
  skip_if_not_installed("jsonlite")

  ledger <- jsonlite::fromJSON(ledger_path(), simplifyDataFrame = FALSE)
  rows <- ledger$prefixes
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

  ledger <- jsonlite::fromJSON(ledger_path(), simplifyDataFrame = FALSE)
  rows <- ledger$prefixes
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

  ledger <- jsonlite::fromJSON(ledger_path(), simplifyDataFrame = FALSE)
  intake <- Filter(function(r) identical(r$status, "intake"), ledger$prefixes)

  # An intake row without a blocker is indistinguishable from a forgotten one.
  # The blocker is what tells a reader why it is not scheduled.
  for (r in intake) {
    expect_true(!is.null(r$blocked_on) && nzchar(r$blocked_on),
                label = paste("intake row", r$prefix, "has no blocked_on"))
  }
})
