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

test_that("an exhibit of unknown kind stops, naming the item", {
  r <- list(id = "hz.dead.hz#x", exhibit = list(kind = "bogus"))
  expect_error(hvtiRtemplates:::.ar_exhibit_body(r, tempdir()), "hz.dead.hz#x.*unknown kind 'bogus'")
})

test_that("table cells and value names are escaped", {
  root <- ar_fake_study()
  ar_fake_job(root)
  saveRDS(data.frame(term = "<b>x</b> & y", n = 1), file.path(root, "documents", "dead-hz", "tbl-estimates.rds"))
  saveRDS(list(`<i>n</i>` = 1L), file.path(root, "estimates", "dead-hz", "hz-methods.rds"))
  sc <- hvtiRutilities::provenance_path(file.path(root, "20_distributions", "hz.dead.hz.html"))
  x <- jsonlite::read_json(sc)
  for (i in seq_along(x$exhibits)) {
    x$exhibits[[i]]$sha256 <- digest::digest(file.path(root, x$exhibits[[i]]$file), algo = "sha256", file = TRUE)
  }
  jsonlite::write_json(x, sc, auto_unbox = TRUE, null = "null")
  body <- function(lab) {
    r <- hvtiRtemplates:::.ar_resolve(paste0("hz.dead.hz#", lab), root)
    paste(hvtiRtemplates:::.ar_exhibit_body(r, root), collapse = "\n")
  }
  expect_match(body("tbl-estimates"), "&lt;b&gt;x&lt;/b&gt; &amp; y", fixed = TRUE)
  expect_false(grepl("<b>", body("tbl-estimates"), fixed = TRUE))
  expect_match(body("methods"), "&lt;i&gt;n&lt;/i&gt;", fixed = TRUE)
})

test_that("ar_value() warns when its source job has been edited since the render", {
  root <- ar_fake_study()
  qmd <- ar_fake_job(root)
  withr::local_dir(root)
  expect_no_warning(ar_value("hz.dead.hz#methods", "n"))
  cat("# edited\n", file = qmd, append = TRUE)
  expect_warning(v <- ar_value("hz.dead.hz#methods", "n"), "hz.dead.hz.*edited since its last render")
  expect_identical(v, 160L)
})
