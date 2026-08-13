test_that("hvti_taxonomy() has the expected shape", {
  tx <- hvti_taxonomy()
  expect_s3_class(tx, "data.frame")
  expect_named(tx, c("prefix", "name", "folder", "description"))
  expect_gt(nrow(tx), 25)
  expect_false(any(duplicated(tx$prefix)))
  expect_true(all(nzchar(tx$description)))
})

test_that("every corpus folder is documented in the taxonomy", {
  # The corpus was reduced to SAS only for public release, and the SAS-only
  # corpus does not sample every folder the taxonomy documents -- notably
  # `documents` (the "ar" / Analysis report row), which held only
  # .doc/.Rnw/.qmd templates and never had a SAS file. That is expected: the
  # taxonomy records the group's analysis-prefix system, which is real
  # whether or not this corpus snapshot happens to touch every part of it, so
  # the taxonomy is not required to be a subset of the corpus's folders.
  #
  # The direction worth enforcing is the other one: every folder a corpus
  # file actually lives in must appear in the taxonomy, so a template landing
  # somewhere undocumented fails the build instead of going unnoticed. Do not
  # flip this back to "every taxonomy folder is in the corpus" -- that
  # direction breaks any time the corpus is a proper subset of the taxonomy,
  # which is expected, not a bug.
  tx <- hvti_taxonomy()
  m <- corpus_manifest()
  skip_if(nrow(m) == 0, "corpus not installed")
  expect_true(all(unique(m$folder) %in% tx$folder))
})

test_that("every prefix-shaped field in the corpus is classified", {
  # Not every `tp.X.…` file uses the prefix system: `tp.PPTs.R` and
  # `tp.plots.sas` are utilities whose second field is just a word. So the
  # test does not demand a taxonomy row for every X -- it demands that every X
  # is *classified*, either as an analysis prefix or explicitly as not one.
  #
  # That distinction is the whole value of the test. Demanding a taxonomy row
  # for every X would push `PPTs` and `test` into the taxonomy as if they were
  # analysis types; allowing unknowns through silently would let a genuinely
  # new prefix arrive undocumented, which is how the README drifted in the
  # first place. A new file with an unclassified second field fails the build
  # until someone decides which it is.
  root <- system.file("corpus", package = "hvtiRtemplates")
  skip_if(root == "", "corpus not installed")
  files <- list.files(root, pattern = "^tp\\.", recursive = TRUE)
  found <- unique(vapply(strsplit(basename(files), ".", fixed = TRUE),
                         function(x) if (length(x) > 1) x[[2]] else NA_character_,
                         character(1)))
  found <- found[!is.na(found) & nchar(found) <= 5]
  unclassified <- setdiff(found, c(hvti_taxonomy()$prefix, hvti_non_prefixes()))
  expect_equal(unclassified, character(0),
               info = paste("unclassified second field(s):",
                            paste(unclassified, collapse = ", "),
                            "- add to hvti_taxonomy() if an analysis prefix,",
                            "or to hvti_non_prefixes() if not"))
})

test_that("the taxonomy and the non-prefix list are disjoint", {
  expect_equal(intersect(hvti_taxonomy()$prefix, hvti_non_prefixes()),
               character(0))
})
