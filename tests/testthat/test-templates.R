test_that("template_list() has the expected shape", {
  tl <- template_list()
  expect_s3_class(tl, "data.frame")
  expect_named(tl, c("name", "prefix", "ordinal", "folder", "file"))
})

test_that("template_list() finds templates in taxonomy subfolders", {
  # Templates live one level down, under the taxonomy folder they scaffold into,
  # so the glob must recurse. A non-recursive glob would report zero templates
  # and every downstream test would pass vacuously.
  tl <- template_list()
  expect_true("ac" %in% tl$prefix)
  i <- match("ac", tl$prefix)
  expect_equal(tl$folder[[i]], "distributions")
  expect_equal(tl$ordinal[[i]], "03.01")
  expect_equal(tl$name[[i]], "03.01-ac")
})

test_that("template_list() reads folder from the directory, not the taxonomy", {
  # The filesystem is the authority on where a template lives. Joining through
  # hvti_taxonomy() instead would report the folder the prefix is *filed* under
  # even when the file sits somewhere else -- hiding exactly the mistake the
  # cross-check in test-taxonomy.R exists to catch.
  tl <- template_list()
  expect_equal(tl$folder, basename(dirname(tl$file)))
})

test_that("every listed template exists and every template file is listed", {
  tl <- template_list()
  dir <- system.file("templates", package = "hvtiRtemplates")
  skip_if(dir == "", "templates not installed")
  on_disk <- list.files(dir, pattern = "[.]qmd$", recursive = TRUE)
  expect_setequal(tl$file, file.path(dir, on_disk))
  expect_true(all(file.exists(tl$file)))
})

test_that("template_path() resolves a prefix", {
  expect_true(file.exists(template_path("ac")))
  expect_error(template_path("zz"), "unknown template")
})

test_that("every template prefix is in the taxonomy", {
  tl <- template_list()
  expect_true(all(tl$prefix %in% hvti_taxonomy()$prefix))
})

test_that(".template_fields() parses a structured template name", {
  # A template is named "<NN>.<MM>-<prefix>.qmd". The name is parsed by pattern
  # rather than by splitting on separators, because `.` is both a field
  # separator inside the ordinal and the extension separator -- a split cannot
  # tell the two apart.
  expect_equal(hvtiRtemplates:::.template_fields("03.01-ac.qmd")$ordinal, "03.01")
  expect_equal(hvtiRtemplates:::.template_fields("03.01-ac.qmd")$prefix, "ac")
  expect_equal(hvtiRtemplates:::.template_fields("04.19-rfs.qmd")$prefix, "rfs")
})

test_that(".template_fields() returns NA for a name it cannot parse", {
  # NA rather than an error: template_list() reports what is on disk, and a
  # stray file should not stop it. The unclassified-prefix test in
  # test-taxonomy.R is what turns an unparsed name into a build failure.
  expect_true(is.na(hvtiRtemplates:::.template_fields("ac.qmd")$prefix))
  expect_true(is.na(hvtiRtemplates:::.template_fields("README.md")$prefix))
})

test_that("no two templates share a prefix", {
  # `template_path()` and `new_job()` both resolve with `match()`, which takes
  # the first hit silently. Under the old flat layout one directory guaranteed
  # one file per prefix; a recursive glob does not, so the invariant has to be
  # asserted rather than assumed.
  tl <- template_list()
  expect_false(any(duplicated(stats::na.omit(tl$prefix))))
})

test_that("every installed template's name parses", {
  # .template_fields() returns NA rather than erroring on a name it cannot
  # parse, so a stray file does not stop template_list(). But nothing on disk
  # should actually BE that stray file: an unparseable template name is a real
  # defect, and letting it through as an NA prefix/ordinal produces three
  # confusing downstream failures (the taxonomy folder check, the taxonomy
  # cross-check, and the "every template exists" check) instead of one test
  # that names the actual problem. This is that one test.
  tl <- template_list()
  expect_false(any(is.na(tl$ordinal)),
               info = "a template file name did not match <NN.MM>-<prefix>.qmd")
  expect_false(any(is.na(tl$prefix)),
               info = "a template file name did not match <NN.MM>-<prefix>.qmd")
})

test_that(".template_fields() rejects an unpadded ordinal", {
  # The zero-padding is what makes `ls` sort a set in run order past nine
  # entries. Accepting "3.1" here would let an unsortable name into the tree
  # silently, so the parser is where the padding rule is enforced.
  expect_true(is.na(hvtiRtemplates:::.template_fields("3.1-ac.qmd")$ordinal))
  expect_true(is.na(hvtiRtemplates:::.template_fields("03.1-ac.qmd")$ordinal))
})
