# The archive of shipped template texts upgrade_job() finds a job's base in.
# See dev/specs/2026-10-22-upgrade-job-merge-design.md, decisions 2 and 3.

state <- function(version, date, ...) {
  files <- lapply(list(...), function(x) charToRaw(paste0(paste(x, collapse = "\n"), "\n")))
  list(version = version, date = date, files = files)
}

test_that("a bump commit that changes no template maps the text to both versions", {
  states <- list(
    state("1.0.0", "2026-10-01", "inst/templates/30_analyses/nb-boostmtree.qmd" = c("a", "b")),
    state("1.0.0", "2026-10-02", "inst/templates/30_analyses/nb-boostmtree.qmd" = c("a", "B")),
    state("1.0.1", "2026-10-03", "inst/templates/30_analyses/nb-boostmtree.qmd" = c("a", "B"))
  )
  h <- hvtiRtemplates:::.history_from_states(states)
  expect_identical(length(h$texts), 2L)
  ix <- h$index[order(h$index$version, h$index$first), ]
  expect_identical(ix$template, rep("nb.boostmtree", 3L))
  expect_identical(ix$version, c("1.0.0", "1.0.0", "1.0.1"))
  expect_identical(ix$sha256[[2L]], ix$sha256[[3L]])
  expect_identical(h$texts[[ix$sha256[[3L]]]], "a\nB\n")
})

test_that("the shipped archive's texts hash to their keys and cover every current template", {
  h <- hvtiRtemplates:::.template_history()
  for (sha in names(h$texts)) {
    expect_identical(digest::digest(charToRaw(h$texts[[sha]]), algo = "sha256", serialize = FALSE), sha)
  }
  expect_true(all(h$index$sha256 %in% names(h$texts)))
  expect_true(all(c("template", "file", "version", "sha256", "first", "last") %in% names(h$index)))
})

test_that(".base_candidates(): a hash names one text, a version its texts oldest first", {
  states <- list(
    state("1.0.0", "2026-10-01", "inst/templates/10_descriptive/dc-general.qmd" = "old"),
    state("1.0.0", "2026-10-02", "inst/templates/10_descriptive/dc-general.qmd" = "newer"),
    state("1.0.1", "2026-10-03", "inst/templates/10_descriptive/dc-general.qmd" = "newest")
  )
  h <- hvtiRtemplates:::.history_from_states(states)
  sha <- h$index$sha256[h$index$version == "1.0.1"]
  exact <- hvtiRtemplates:::.base_candidates("dc.general", "1.0.1", sha, history = h)
  expect_identical(length(exact), 1L)
  expect_identical(exact[[1L]]$lines, "newest")
  both <- hvtiRtemplates:::.base_candidates("dc.general", "1.0.0", NA_character_, history = h)
  expect_identical(vapply(both, function(x) x$lines, ""), c("old", "newer"))
  expect_identical(hvtiRtemplates:::.base_candidates("dc.general", "0.9.0", NA_character_, history = h), list())
  expect_identical(hvtiRtemplates:::.base_candidates("dc.general", "1.0.1", strrep("0", 64L), history = h), list())
})
