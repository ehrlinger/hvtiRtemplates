# What an ar render shows for an item, and when it warns. Spec sections 6.1 and 6.2.

ar_item_md <- function(root, methods = list(""), ...) {
  path <- file.path(root, "50_documents", "ar.dead.question.qmd")
  dir.create(dirname(path), showWarnings = FALSE)
  writeLines(c("```{r}", 'hvtiRtemplates::ar_item("hz.dead.hz#fig-fit")', "```", "", "::: methods",
               methods[[1]], ":::"), path)
  list(path = path, md = function() {
    it <- hvtiRtemplates:::.ar_parse(readLines(path))[[1]]
    r <- hvtiRtemplates:::.ar_resolve(it$id, root)
    paste(hvtiRtemplates:::.ar_item_markdown(r, it, dirname(path)), collapse = "\n")
  })
}

test_that("a figure is embedded, numbered, downloadable and linked to its job", {
  root <- ar_fake_study()
  ar_fake_job(root)
  x <- ar_item_md(root)
  ar_paste_methods(x$path)
  md <- x$md()
  expect_match(md, "**Item 1**", fixed = TRUE)
  expect_match(md, "](../graphs/dead-hz/hz-fit.png)", fixed = TRUE)
  expect_match(md, "data:image/png;base64,", fixed = TRUE)
  expect_match(md, "(../20_distributions/hz.dead.hz.html)", fixed = TRUE)
  expect_false(grepl("callout", md))
})

test_that("an empty methods slot asks for ar_paste_methods()", {
  root <- ar_fake_study()
  ar_fake_job(root)
  expect_match(ar_item_md(root)$md(), "ar_paste_methods()", fixed = TRUE)
})

test_that("a source rendered again on changed data, Methods unchanged, raises the review callout until reviewed", {
  root <- ar_fake_study()
  ar_fake_job(root)
  x <- ar_item_md(root)
  ar_paste_methods(x$path)
  ar_fake_job(root, rendered = "2026-11-13T09:00:00Z")
  md <- x$md()
  expect_match(md, "rendered again since this item's text was reviewed")
  expect_false(grepl("Methods paragraph has changed", md))
  ar_review(x$path)
  expect_false(grepl("callout", x$md()))
})

test_that("changed boilerplate raises the drift callout", {
  root <- ar_fake_study()
  ar_fake_job(root)
  x <- ar_item_md(root)
  ar_paste_methods(x$path)
  ar_fake_job(root, methods = list(text = "A different method.", sha256 = NULL))
  expect_match(x$md(), "Methods paragraph has changed")
})

test_that("an edited source job and a template with no boilerplate each raise a callout", {
  root <- ar_fake_study()
  qmd <- ar_fake_job(root, methods = NULL)
  x <- ar_item_md(root)
  ar_paste_methods(x$path)
  cat("# edited\n", file = qmd, append = TRUE)
  md <- x$md()
  expect_match(md, "edited since its last render")
  expect_match(md, "writes no Methods paragraph yet")
})

test_that("a table renders as a table", {
  root <- ar_fake_study()
  ar_fake_job(root)
  r <- hvtiRtemplates:::.ar_resolve("hz.dead.hz#tbl-estimates", root)
  it <- list(id = r$id, index = 2L, empty = FALSE, stamp = NULL)
  dir.create(file.path(root, "50_documents"), showWarnings = FALSE)
  md <- paste(hvtiRtemplates:::.ar_item_markdown(r, it, file.path(root, "50_documents")), collapse = "\n")
  expect_match(md, "|term |", fixed = TRUE)
})

test_that("ar_value() returns a field, and names the fields it has when one is misspelled", {
  root <- ar_fake_study()
  ar_fake_job(root)
  withr::local_dir(root)
  expect_identical(ar_value("hz.dead.hz#methods", "n"), 160L)
  expect_error(ar_value("hz.dead.hz#methods", "N"), "it has: n, events")
  expect_error(ar_value("hz.dead.hz#fig-fit", "n"), "not a saved value")
})
