test_that("the template catalog ships every owed job type", {
  catalog <- template_catalog()
  expect_s3_class(catalog, "data.frame")
  expect_equal(nrow(catalog), 55L)
  expect_equal(length(unique(catalog$prefix)), 44L)
  expect_false(any(c("destination", "replaced_by") %in% names(catalog)))
  expect_true(all(c("uses", "upstream", "downstream", "workflows") %in% names(catalog)))
  expect_type(catalog$uses, "list")
  expect_type(catalog$sas_breadth_jobs, "integer")
  expect_false(any(c("rf", "rfsrc") %in% catalog$prefix))
  expect_false(anyNA(catalog$status))
})

test_that("a missing catalog is an error", {
  expect_error(.read_template_catalog(tempfile(fileext = ".json")), "not found")
})

test_that("malformed scalar fields name the row and field", {
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path))
  writeLines(jsonlite::toJSON(list(templates = list(
    list(prefix = "ab", status = c("queued", "shipped"))
  )), auto_unbox = TRUE), path)
  expect_error(.template_catalog_from(path), "row 1.*status")
  writeLines(jsonlite::toJSON(list(templates = list(
    list(prefix = "ab", sas_breadth = "many")
  )), auto_unbox = TRUE), path)
  expect_error(.template_catalog_from(path), "row 1.*sas_breadth")
  writeLines(jsonlite::toJSON(list(templates = list(
    list(prefix = "ab", sas_breadth = 1.5)
  )), auto_unbox = TRUE), path)
  expect_error(.template_catalog_from(path), "row 1.*sas_breadth")
  # A JSON boolean or a numeric string is not an integer count, although
  # as.integer() turns TRUE into 1 and "3" into 3 without complaint.
  writeLines(jsonlite::toJSON(list(templates = list(
    list(prefix = "ab", r_jobs = TRUE)
  )), auto_unbox = TRUE), path)
  expect_error(.template_catalog_from(path), "row 1.*r_jobs")
  writeLines(jsonlite::toJSON(list(templates = list(
    list(prefix = "ab", r_jobs = "3")
  )), auto_unbox = TRUE), path)
  expect_error(.template_catalog_from(path), "row 1.*r_jobs")
})
