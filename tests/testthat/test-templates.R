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
