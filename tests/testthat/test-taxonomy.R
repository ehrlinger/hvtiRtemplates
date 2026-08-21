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

test_that("exactly the artifact-kind rows have an NA prefix", {
  # `folder` names two things: for most rows it is an analysis type's home
  # folder, matched to a real prefix; `estimates` is an artifact kind with no
  # analysis that produces it, so its prefix is NA. This pins that mapping
  # down explicitly -- without it, a future row could pick up an NA prefix by
  # typo, or a real prefix could silently go missing, and nothing here would
  # notice.
  tx <- hvti_taxonomy()
  artifact_kind_folders <- c("estimates")
  expect_equal(is.na(tx$prefix), tx$folder %in% artifact_kind_folders)
})

test_that("a template's ordinal major identifies the folder it sits in", {
  # The major is derived from the taxonomy's own folder order rather than from a
  # table written out here. A second copy of that mapping would be a second
  # thing to keep in step, which is the drift hvti_taxonomy() exists to prevent.
  tl <- template_list()
  skip_if(nrow(tl) == 0, "no templates installed")
  order_of <- unique(hvti_taxonomy()$folder)
  expect_equal(substr(tl$ordinal, 1L, 2L),
               sprintf("%02d", match(tl$folder, order_of)))
})

test_that("a template sits in the folder its prefix is filed under", {
  # template_list() reads `folder` from the directory, so this is a real check
  # and not a tautology: it catches a template filed somewhere the taxonomy does
  # not put its prefix.
  tl <- template_list()
  skip_if(nrow(tl) == 0, "no templates installed")
  tx <- hvti_taxonomy()
  expect_equal(tl$folder, tx$folder[match(tl$prefix, tx$prefix)])
})

test_that("within a folder, ordinal minors follow taxonomy row order", {
  # Deliberately per-folder rather than global. Global row order does not work:
  # `rfsrc`, `rfc`, `rfs` and `nb` are `analyses` rows that sit AFTER the
  # `documents` row `ar`, so an `rfs` template (major 04) would compare as later
  # than an `ar` template (major 07) on row order while being earlier on
  # ordinal. The majors already carry the between-folder ordering; only the
  # within-folder ordering is left for this check.
  tl <- template_list()
  skip_if(nrow(tl) == 0, "no templates installed")
  tx <- hvti_taxonomy()
  for (f in unique(tl$folder)) {
    k <- tl$folder == f
    expect_equal(order(tl$ordinal[k]),
                 order(match(tl$prefix[k], tx$prefix)),
                 info = paste("minors out of taxonomy order in", f))
  }
})

test_that("the within-folder ordering rule itself can fail, on a synthetic pair", {
  # The check above is structurally unable to fail while only one template is
  # installed: order() on a length-1 vector always returns 1, so that assertion
  # holds regardless of what ordinal or prefix contain. This block exercises the
  # same rule -- ordinal order must track taxonomy row order -- against a small
  # hand-built frame standing in for two templates in one folder, so a broken
  # rule is caught now rather than only once a second `distributions` template
  # actually lands.
  tx <- hvti_taxonomy()
  # `ac` and `hz` are both real `distributions` prefixes; `ac` sits earlier in
  # hvti_taxonomy() row order, so the expected minor order below is derived from
  # match(), not hard-coded, and stays correct if the taxonomy is reordered.
  expected_order <- order(match(c("ac", "hz"), tx$prefix))

  # Shaped like template_list()'s output: two rows standing in for two
  # `distributions` templates.
  ok <- data.frame(
    name    = c("03.01-ac", "03.02-hz"),
    prefix  = c("ac", "hz"),
    ordinal = c("03.01", "03.02"),
    folder  = c("distributions", "distributions"),
    file    = c("ac.qmd", "hz.qmd"),
    stringsAsFactors = FALSE
  )
  # Positive: minors agree with taxonomy row order.
  expect_equal(order(ok$ordinal), expected_order)

  # Negative: same two rows, minors swapped so ordinal order contradicts
  # taxonomy row order -- the rule must detect this, not pass it silently.
  bad <- ok
  bad$ordinal <- rev(bad$ordinal)
  expect_false(identical(order(bad$ordinal), expected_order))
})
