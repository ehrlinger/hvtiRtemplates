# The ar file: its items, the pasted Methods text and the review stamps.
# dev/specs/2026-11-11-ar-question-report-design.md, sections 5.4 and 5.5.

ar_lines <- function(items = "hz.dead.hz#fig-fit", methods = rep(list(""), length(items))) {
  unlist(lapply(seq_along(items), function(i) {
    c(
      paste0("## Item ", i), "", "```{r}", paste0('hvtiRtemplates::ar_item("', items[[i]], '")'), "```", "",
      "::: methods", methods[[i]], ":::", "", "::: results", ":::", ""
    )
  }))
}

ar_report <- function(root, lines) {
  dir.create(file.path(root, "50_documents"), showWarnings = FALSE)
  path <- file.path(root, "50_documents", "ar.dead.question.qmd")
  writeLines(lines, path)
  path
}

test_that("items are found by their ar_item() call, with their methods div", {
  p <- hvtiRtemplates:::.ar_parse(ar_lines(c("a.b.c#x", "a.b.c#y")))
  expect_identical(vapply(p, `[[`, "", "id"), c("a.b.c#x", "a.b.c#y"))
  expect_true(p[[1]]$empty)
  expect_true(is.na(p[[1]]$stamp_line))
})

test_that("an item cited twice is refused", {
  expect_error(hvtiRtemplates:::.ar_parse(ar_lines(c("a.b.c#x", "a.b.c#x"), list("", ""))), "twice")
})

test_that("a methods div holding only a comment counts as empty, and prose does not", {
  expect_true(hvtiRtemplates:::.ar_parse(ar_lines(methods = list("<!-- run ar_paste_methods() -->")))[[1]]$empty)
  expect_false(hvtiRtemplates:::.ar_parse(ar_lines(methods = list("My own words.")))[[1]]$empty)
})

test_that("ar_paste_methods() fills an empty div with the stamp and the boilerplate", {
  root <- ar_fake_study()
  ar_fake_job(root)
  path <- ar_report(root, ar_lines())
  expect_identical(ar_paste_methods(path), "hz.dead.hz#fig-fit")
  p <- hvtiRtemplates:::.ar_parse(readLines(path))[[1]]
  expect_false(p$empty)
  expect_identical(p$stamp$rendered, "2026-11-12T10:00:00Z")
  expect_true(any(readLines(path) == "A hazard was modeled."))
})

test_that("ar_paste_methods() never touches a div that holds text, byte for byte", {
  root <- ar_fake_study()
  ar_fake_job(root)
  path <- ar_report(root, ar_lines(methods = list("My own words.")))
  before <- readBin(path, "raw", file.size(path))
  expect_identical(ar_paste_methods(path), character())
  expect_identical(readBin(path, "raw", file.size(path)), before)
})

test_that("ar_paste_methods() writes nothing when any item fails to resolve", {
  root <- ar_fake_study()
  ar_fake_job(root)
  path <- ar_report(root, ar_lines(c("hz.dead.hz#fig-fit", "hz.dead.hz#absent"), list("", "")))
  before <- readLines(path)
  expect_error(ar_paste_methods(path), "absent")
  expect_identical(readLines(path), before)
})

test_that("an item without a methods div is refused", {
  root <- ar_fake_study()
  ar_fake_job(root)
  path <- ar_report(root, c("```{r}", 'hvtiRtemplates::ar_item("hz.dead.hz#fig-fit")', "```"))
  expect_error(ar_paste_methods(path), "no ::: methods div")
})

test_that("ar_review() moves the stamp to the source's current run and keeps the analyst's text", {
  root <- ar_fake_study()
  ar_fake_job(root)
  path <- ar_report(root, ar_lines())
  ar_paste_methods(path)
  ar_fake_job(root, rendered = "2026-11-13T09:00:00Z")
  expect_identical(ar_review(path), "hz.dead.hz#fig-fit")
  p <- hvtiRtemplates:::.ar_parse(readLines(path))[[1]]
  expect_identical(p$stamp$rendered, "2026-11-13T09:00:00Z")
  expect_true(any(readLines(path) == "A hazard was modeled."))
})

test_that("ar_review() refuses an item never pasted", {
  root <- ar_fake_study()
  ar_fake_job(root)
  path <- ar_report(root, ar_lines())
  expect_error(ar_review(path), "ar_paste_methods\\(\\) first")
})
