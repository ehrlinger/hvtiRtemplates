test_that("NEWS separates endpoint-neutral contract changes as unreleased", {
  path <- testthat::test_path("..", "..", "NEWS.md")
  testthat::skip_if_not(file.exists(path), "NEWS source not available")
  news <- readLines(path, warn = FALSE)
  unreleased <- match("# hvtiRtemplates (unreleased)", news)
  release <- match("# hvtiRtemplates 1.2.1", news)

  expect_false(is.na(unreleased))
  expect_false(is.na(release))
  expect_lt(unreleased, release)

  changes <- news[seq.int(unreleased + 1L, release - 1L)]
  changes <- paste(changes, collapse = " ")
  expect_true(grepl("\\*\\*Breaking:\\*\\*.*`subject`", changes))
  expect_true(grepl("provenance", changes, fixed = TRUE))
})
