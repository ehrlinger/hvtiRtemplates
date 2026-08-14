test_that("hvti_taxonomy() has the expected shape", {
  tx <- hvti_taxonomy()
  expect_s3_class(tx, "data.frame")
  expect_named(tx, c("prefix", "name", "folder", "description"))
  expect_gt(nrow(tx), 25)
  expect_false(any(duplicated(tx$prefix)))
  expect_true(all(nzchar(tx$description)))
})

test_that("every template folder is documented in the taxonomy", {
  # The taxonomy records the group's analysis-prefix system, which is real
  # whether or not the installed templates happen to touch every part of it.
  # So the taxonomy is not required to be a subset of the folders in use.
  #
  # The direction worth enforcing is the other one: every folder a template
  # actually lands in must appear in the taxonomy, so a template landing
  # somewhere undocumented fails the build instead of going unnoticed. Do not
  # flip this to "every taxonomy folder has a template" -- that direction
  # breaks any time the templates are a proper subset of the taxonomy, which
  # is expected, not a bug. It is vacuously true until stage 3 adds the
  # templates, and becomes load-bearing the moment one arrives.
  tx <- hvti_taxonomy()
  tl <- template_list()
  folders <- unique(stats::na.omit(tl$folder))
  expect_true(all(folders %in% tx$folder))
})

test_that("every prefix-shaped template name is classified", {
  # Not every name uses the prefix system: `PPTs` and `plots` are utilities
  # whose leading field is just a word. So the test does not demand a taxonomy
  # row for every name -- it demands that every one is *classified*, either as
  # an analysis prefix or explicitly as not one.
  #
  # That distinction is the whole value of the test. Demanding a taxonomy row
  # for every name would push `PPTs` and `test` into the taxonomy as if they
  # were analysis types; allowing unknowns through silently would let a
  # genuinely new prefix arrive undocumented, which is how the README drifted
  # in the first place. A new template with an unclassified prefix fails the
  # build until someone decides which it is.
  tl <- template_list()
  found <- unique(stats::na.omit(tl$prefix))
  unclassified <- setdiff(found, c(hvti_taxonomy()$prefix, hvti_non_prefixes()))
  expect_equal(unclassified, character(0),
               info = paste("unclassified prefix(es):",
                            paste(unclassified, collapse = ", "),
                            "- add to hvti_taxonomy() if an analysis prefix,",
                            "or to hvti_non_prefixes() if not"))
})

test_that("the taxonomy and the non-prefix list are disjoint", {
  expect_equal(intersect(hvti_taxonomy()$prefix, hvti_non_prefixes()),
               character(0))
})
