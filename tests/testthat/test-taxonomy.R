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

test_that("every template directory is <NN>_<taxonomy folder>", {
  # The digits order the directories; the name after them must be a folder the
  # taxonomy actually has, or a template scaffolds into a folder no study uses.
  #
  # ⚠️ The digits are NOT checked against the taxonomy's row position, and
  # deliberately so. They are ASSIGNED: `estimates` is numbered 90 because it
  # holds saved output rather than jobs, though it is fifth in the table. That
  # is the same lesson the ordinal taught -- deriving identity from position is
  # what made `bh` need renumbering when an upstream row moved.
  dir <- system.file("templates", package = "hvtiRtemplates")
  skip_if(!nzchar(dir), "templates are not installed")
  dirs <- list.dirs(dir, full.names = FALSE, recursive = FALSE)
  skip_if(length(dirs) == 0, "no template directories")
  expect_true(all(grepl("^[0-9]{2}_", dirs)))
  expect_true(all(sub("^[0-9]+_", "", dirs) %in% hvti_taxonomy()$folder))
  expect_false(any(duplicated(substr(dirs, 1L, 2L))))
})

test_that("a template sits in the folder its row files it under", {
  # template_list() reads `folder` from the directory, so this is a real check
  # and not a tautology: it catches a template filed somewhere neither the
  # catalog nor the taxonomy puts it.
  #
  # ⭐ The expected folder came from `hvti_taxonomy()` alone until 2026-09-09.
  # That map has ONE row per prefix, and a prefix may span folders: `dp` is
  # `graphs` for trends/gfup/spaghetti/procs, `distributions` for `variable`,
  # and a `descriptive` row is planned for the postage-stamp sweep. So the old
  # form would have failed `dp-variable`, which is ALREADY scheduled in batch
  # 3, the moment anyone wrote it. The job catalog carries `folder` per row,
  # keyed on (prefix, qualifier), and is consulted first; the taxonomy answers
  # for rows the catalog does not have and whenever the catalog is absent.
  # See issue #97 and `dev/specs/2026-09-09-eda-templates-design.md` §8.3.
  #
  # The taxonomy is NOT the loser here: "every template directory is
  # <NN>_<taxonomy folder>" above still forces every directory to name a
  # folder the taxonomy has, so the catalog cannot invent one.
  tl <- template_list()
  skip_if(nrow(tl) == 0, "no templates installed")
  expect_equal(tl$folder, expected_template_folders(tl))
})

# ⭐ The ordinal was DROPPED ENTIRELY on 2026-09-03, so the history below is
# now the record of a field that no longer exists. `NN` moved onto the
# directory, where it is the thing rather than a copy of it, and `MM` went
# because templates within a folder are not ordered. See
# dev/specs/2026-09-03-template-identity-design.md, which decided it.
#
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

# ⭐ Coverage for the catalog-first folder lookup itself, added 2026-09-09.
#
# The check above runs the lookup, but every template shipped today is in the
# folder `hvti_taxonomy()` names, so catalog and taxonomy agree and the two
# branches are indistinguishable from its result. A regression to taxonomy-only
# would keep it green. These tests are the ones that would go red, and they
# drive the lookup with a temporary catalog rather than the real one so they do
# not go stale when the real catalog is edited.

# Write `rows` as a catalog to a temp file and point HVTI_JOBS at it for the
# duration of `code`. Base R rather than withr: this package does not Suggest
# it, and adding a dependency to reach one helper is a poor trade.
with_temp_catalog <- function(rows, code) {
  # require_jsonlite(), not testthat::skip_if_not_installed(). The latter skips
  # silently even under HVTI_ROADMAP_STRICT, so these five tests could drop out
  # of the strict step with it still reporting green, which is the defect this
  # block exists to prevent. require_jsonlite() is a hard stop there and a skip
  # everywhere else. Raised by Copilot on #98. The nolint is because
  # object_usage_linter checks function bodies and cannot see a helper
  # defined in helper-ledger.R; testthat loads that file before this one.
  require_jsonlite() # nolint: object_usage_linter.
  path <- tempfile(fileext = ".json")
  writeLines(jsonlite::toJSON(list(jobs = rows), auto_unbox = TRUE), path)
  old <- Sys.getenv("HVTI_JOBS", unset = NA)
  Sys.setenv(HVTI_JOBS = path)
  on.exit({
    if (is.na(old)) Sys.unsetenv("HVTI_JOBS") else Sys.setenv(HVTI_JOBS = old)
    unlink(path)
  }, add = TRUE)
  force(code)
}

# One template row as template_list() would report it.
.tl <- function(prefix, qualifier, folder) {
  data.frame(prefix = prefix, qualifier = qualifier, folder = folder,
             stringsAsFactors = FALSE)
}

test_that("the catalog's folder wins over the taxonomy's", {
  # `dp` is `graphs` in the taxonomy. A row filing it under `descriptive` must
  # be believed, or a descriptive/dp template can never ship.
  rows <- list(list(prefix = "dp", qualifier = "postage",
                    folder = "descriptive", destination = "hvtiRtemplates"))
  with_temp_catalog(rows, {
    got <- expected_template_folders(.tl("dp", "postage", "descriptive"))
    expect_identical(got, "descriptive")
    expect_false(identical(got, "graphs"))
  })
})

test_that("a template with no catalog row falls back to the taxonomy", {
  rows <- list(list(prefix = "dp", qualifier = "postage",
                    folder = "descriptive", destination = "hvtiRtemplates"))
  with_temp_catalog(rows, {
    # `ac` is absent from this catalog, so the taxonomy answers: distributions.
    expect_identical(expected_template_folders(.tl("ac", NA_character_, "x")),
                     "distributions")
  })
})

test_that("a row for another package cannot shadow ours", {
  # Same pair, two destinations, different folders. Filtering to this repo is
  # what makes the answer deterministic; without it `match()` would return
  # whichever row came first and report nothing.
  rows <- list(
    list(prefix = "dp", qualifier = "postage", folder = "graphs",
         destination = "hvtiPlotR"),
    list(prefix = "dp", qualifier = "postage", folder = "descriptive",
         destination = "hvtiRtemplates")
  )
  with_temp_catalog(rows, {
    expect_identical(expected_template_folders(.tl("dp", "postage", "descriptive")),
                     "descriptive")
  })
})

test_that("a duplicated pair stops rather than picking the first row", {
  rows <- list(
    list(prefix = "dp", qualifier = "postage", folder = "descriptive",
         destination = "hvtiRtemplates"),
    list(prefix = "dp", qualifier = "postage", folder = "graphs",
         destination = "hvtiRtemplates")
  )
  with_temp_catalog(rows, {
    expect_error(expected_template_folders(.tl("dp", "postage", "descriptive")),
                 "more than one row.*dp-postage")
  })
})

test_that("an absent qualifier does not collide with one spelled 'NA'", {
  # paste() renders NA as the three characters "NA", so a naive key would give
  # these two rows the same identity and one would silently shadow the other.
  rows <- list(
    list(prefix = "dp", qualifier = NULL, folder = "graphs",
         destination = "hvtiRtemplates"),
    list(prefix = "dp", qualifier = "NA", folder = "descriptive",
         destination = "hvtiRtemplates")
  )
  with_temp_catalog(rows, {
    expect_identical(expected_template_folders(.tl("dp", NA_character_, "graphs")),
                     "graphs")
    expect_identical(expected_template_folders(.tl("dp", "NA", "descriptive")),
                     "descriptive")
  })
})
