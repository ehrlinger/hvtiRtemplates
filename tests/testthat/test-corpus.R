test_that("corpus_manifest() describes every corpus file", {
  m <- corpus_manifest()
  expect_s3_class(m, "data.frame")
  expect_named(m, c("file", "prefix", "folder", "kind", "bytes"))
  expect_equal(nrow(m), 240)
  expect_true(all(m$bytes > 0))
  expect_true(all(m$kind %in% c("sas")))
})

test_that("corpus file counts match the recorded import", {
  # The corpus was reduced to SAS only for public release: a filter-repo pass
  # purged inst/corpus/r, inst/corpus/assets and inst/corpus/docs from every
  # commit, along with the file that carried patient data. 240 SAS templates
  # remain.
  #
  # This number is the point of the test: a partial copy or a silent deletion
  # fails the build rather than looking like a smaller corpus.
  m <- corpus_manifest()
  expect_equal(sum(m$kind == "sas"), 240)
})

test_that("corpus_path() resolves a known file", {
  p <- corpus_path("sas", "distributions", "tp.hz.dead.sas")
  expect_true(file.exists(p))
})

test_that("corpus_path() errors on a missing file", {
  expect_error(corpus_path("sas", "distributions", "nope.sas"), "not found")
})

test_that("prefix classification covers files that lack the tp. marker", {
  # Task 7's classification test only scanned basenames matching `^tp\.`, but
  # the corpus also holds files named `<prefix>.<description>...` with no `tp.`
  # marker at all -- `ar.a1c.hdeath.R`, `dp.estimates.errorbar.pdf`,
  # `lp.hdeath.Minimal.depth.pdf`. Every prefix used that way happens to be
  # classified today, so that test passes; but a new file in that style with an
  # undocumented prefix would never be seen. This closes the hole.
  #
  # Scope is inst/corpus only. inst/macros does not use the prefix convention
  # -- its files are named for the macro they define (`kaplan`, `cumhaz`) --
  # so scanning it would produce noise, not coverage.
  root <- system.file("corpus", package = "hvtiRtemplates")
  skip_if(root == "", "corpus not installed")
  files <- basename(list.files(root, recursive = TRUE))
  files <- sub("^tp\\.", "", files)
  first <- sub("\\..*$", "", files)
  candidates <- unique(first[grepl("^[A-Za-z]{2,5}$", first)])
  unclassified <- setdiff(candidates,
                          c(hvti_taxonomy()$prefix, hvti_non_prefixes()))
  expect_equal(unclassified, character(0),
               info = paste("unclassified prefix-shaped field(s):",
                            paste(unclassified, collapse = ", ")))
})

test_that("corpus_manifest() derives prefix and folder correctly", {
  # Shape assertions cannot catch a wrong derivation -- these can. tp.hz.dead.sas
  # is a stable landmark: it is the hazard-fit template, it lives in
  # distributions/, and it is what the R hz template reproduces.
  m <- corpus_manifest()
  skip_if(nrow(m) == 0, "corpus not installed")

  row <- m[basename(m$file) == "tp.hz.dead.sas", ]
  expect_equal(nrow(row), 1)
  expect_equal(row$prefix, "hz")
  expect_equal(row$folder, "distributions")
  expect_equal(row$kind, "sas")

  # A file nested deeper than one level: folder must still be the study folder,
  # not the subdirectory.
  deep <- m[basename(m$file) == "tp.bd.data.ccf.heart.sas", ]
  expect_equal(nrow(deep), 1)
  expect_equal(deep$folder, "datasets")

  # A name that does not carry an analysis prefix must yield NA, not a guess:
  # "echo_readin" is 11 characters, too long to be a prefix field.
  expect_true(all(is.na(m$prefix[basename(m$file) == "tp.echo_readin.sas"])))
})
