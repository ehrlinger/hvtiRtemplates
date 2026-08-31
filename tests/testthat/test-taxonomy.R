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

# The two tests that stood here -- "within a folder, ordinal minors follow
# taxonomy row order" and its synthetic-pair sibling -- were RETIRED 2026-08-31.
#
# They asserted the derivation that #56 removed. An ordinal is a KEY, assigned
# once and recorded in the roadmap ledger, never recomputed from a row position:
# `bh` shipped as 04.06 when it was 6th in `analyses`, hvtiRutilities aeb20f2
# moved `hs` out to `graphs`, and the position changed while the shipped
# filename could not. Keeping a test that enforced position would have pinned
# the taxonomy's row order across a repository boundary, for a property the repo
# no longer claims.
#
# What replaced them is NOT another position check. `check-roadmap-counts.py`
# already owns the key side -- format, folder-major, uniqueness, retired
# ordinals, and agreement with the files on disk. The one thing it could not
# check is its own `FOLDER_ORDINAL` map, which is hardcoded; that check needs
# `hvti_taxonomy()` and so lives in R, in `test-roadmap.R`. See
# "the guard's folder map still matches the taxonomy" there.
