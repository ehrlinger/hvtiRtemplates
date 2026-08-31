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

test_that("the guard's folder map still matches the taxonomy", {
  # Replaces the two row-position tests retired from test-taxonomy.R on
  # 2026-08-31. This one checks a KEY, not a position, so it is consistent with
  # #56's rule that an ordinal is assigned once and never recomputed.
  #
  # `check-roadmap-counts.py` validates every ordinal's major against
  # FOLDER_ORDINAL, which is a HARDCODED map. The authority it copies is
  # `hvti_taxonomy()`'s folder order -- and that table lives in hvtiRutilities,
  # a different repository. So the map can go stale the same way `bh`'s 04.06
  # did: an upstream correctness fix silently invalidates a downstream constant,
  # with nothing in either clone showing the two were connected.
  #
  # The Python guard cannot check this itself -- reading the taxonomy needs R,
  # which is the whole reason the guards are split by language. So it lives here.
  require_ledger()

  guard <- file.path("..", "..", "dev", "specs", "artifacts",
                     "check-roadmap-counts.py")
  skip_if_not(file.exists(guard), "roadmap guard not present")

  src <- readLines(guard, warn = FALSE)
  open_at <- grep("^FOLDER_ORDINAL = \\{", src)
  expect_length(open_at, 1L)
  close_at <- open_at + which(trimws(src[(open_at + 1L):length(src)]) == "}")[[1L]]

  body <- src[(open_at + 1L):(close_at - 1L)]
  m <- regmatches(body, regexec('"([^"]+)":\\s*"([0-9]{2})"', body))
  kept <- vapply(m, function(x) length(x) == 3L, logical(1))
  mapped <- vapply(m[kept], function(x) x[[3L]], character(1))
  names(mapped) <- vapply(m[kept], function(x) x[[2L]], character(1))

  # The taxonomy's folder order IS the majors, in order of first appearance.
  folders <- unique(hvti_taxonomy()$folder)
  expected <- sprintf("%02d", seq_along(folders))
  names(expected) <- folders

  expect_identical(
    mapped[order(names(mapped))], expected[order(names(expected))],
    label = paste0(
      "FOLDER_ORDINAL in check-roadmap-counts.py has drifted from ",
      "hvti_taxonomy()'s folder order. Update the map, and check whether any ",
      "shipped ordinal's major is now wrong -- a stale map validates against ",
      "the wrong folder silently."
    )
  )
})
