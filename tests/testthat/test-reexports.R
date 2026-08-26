test_that("hvti_taxonomy() and hvti_non_prefixes() are on the package's export list", {
  # R/reexports.R re-exports these from hvtiRutilities via
  # `@importFrom` + `@export`. testthat runs a package's own tests inside
  # that package's namespace, where an `importFrom` binding resolves
  # directly whether or not it is also `@export`ed -- so a plain
  # `exists("hvti_taxonomy")` (or calling it) here would pass even if the
  # `@export` tag were dropped from R/reexports.R. That is exactly the bug
  # this test exists to catch: dropping `@export` removes the entry from
  # NAMESPACE and breaks every real caller (`library(hvtiRtemplates);
  # hvti_taxonomy()`) with `could not find function "hvti_taxonomy"`,
  # while every other test in the suite stays green because they all run
  # inside the namespace too.
  #
  # getNamespaceExports() reads the export list itself -- what a caller in
  # a fresh session actually sees -- rather than the internal bindings, so
  # it is the one instrument that can tell the two states apart.
  exports <- getNamespaceExports("hvtiRtemplates")

  # Built here rather than inline: the same explanation serves both
  # assertions, and a failure message is only useful if someone reads it.
  why <- function(fn) {
    paste0(
      fn, " is not in hvtiRtemplates's export list. A missing '@export' ",
      "above hvtiRutilities::", fn, " in R/reexports.R (followed by ",
      "devtools::document()) drops export(", fn, ") from NAMESPACE. Every ",
      "other test still passes, because testthat runs inside the package ",
      "namespace where the importFrom binding resolves either way -- but a ",
      "real caller doing library(hvtiRtemplates); ", fn, "() then fails ",
      "with 'could not find function \"", fn, "\"'."
    )
  }

  expect_true("hvti_taxonomy" %in% exports, info = why("hvti_taxonomy"))
  expect_true("hvti_non_prefixes" %in% exports, info = why("hvti_non_prefixes"))
})

test_that("the re-exported functions are identical to the hvtiRutilities originals", {
  # A re-export that resolved to a different function -- a stale local
  # copy, a wrapper, a typo'd importFrom target -- would be exactly the
  # drift this refactor exists to prevent, and nothing else pins it.
  expect_identical(hvtiRtemplates::hvti_taxonomy, hvtiRutilities::hvti_taxonomy)
  expect_identical(hvtiRtemplates::hvti_non_prefixes, hvtiRutilities::hvti_non_prefixes)
})
