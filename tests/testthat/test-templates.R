test_that("template_list() has the expected shape", {
  tl <- template_list()
  expect_s3_class(tl, "data.frame")
  expect_named(tl, c("name", "prefix", "folder", "file"))
})

test_that("every listed template exists and every template file is listed", {
  tl <- template_list()
  dir <- system.file("templates", package = "hvtiRtemplates")
  skip_if(dir == "", "templates not installed")
  on_disk <- setdiff(list.files(dir, pattern = "[.]qmd$"), character(0))
  expect_setequal(basename(tl$file), on_disk)
  expect_true(all(file.exists(tl$file)))
})

test_that("every template prefix is in the taxonomy", {
  tl <- template_list()
  expect_true(all(tl$prefix %in% hvti_taxonomy()$prefix))
})

test_that(".prefix_of() derives a prefix for template-style names, not just tp.-marked ones", {
  # inst/templates/ has no .qmd files yet, so template_list() can't exercise
  # this; test the shared helper directly instead. A template named exactly
  # "<prefix>.qmd" is one shape, but the corpus convention is
  # "tp.<prefix>.<rest>", and a bare "<prefix>.<rest>.<ext>" (no "tp." marker)
  # must resolve the same way -- all three must agree.
  expect_equal(hvtiRtemplates:::.prefix_of("hz.qmd"), "hz")
  expect_equal(hvtiRtemplates:::.prefix_of("tp.hz.dead.qmd"), "hz")
  expect_equal(hvtiRtemplates:::.prefix_of("hz.dead.R"), "hz")
  expect_true(is.na(hvtiRtemplates:::.prefix_of("noprefix")))
})
