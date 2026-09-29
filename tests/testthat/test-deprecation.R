# dp-postage is deprecated in favor of dp-eda for one release. The warning is
# driven by the catalog's deprecated_by field, not by a name in the code.

test_that("the catalog marks dp-postage deprecated in favor of dp-eda, and nothing else", {
  catalog <- template_catalog()
  marked <- catalog[!is.na(catalog$deprecated_by), , drop = FALSE]
  expect_identical(paste(marked$prefix, marked$qualifier, sep = "-"), "dp-postage")
  expect_identical(marked$deprecated_by, "dp-eda")
  expect_identical(marked$status, "shipped")
  expect_match(marked$deprecation_note, 'SECTIONS <- c("continuous", "percent", "count")', fixed = TRUE)
  expect_match(marked$deprecation_note, "release after hvtiRtemplates 1.2.3", fixed = TRUE)
})

test_that("template_path(), add_job() and open_job() warn once for dp-postage and still work", {
  expect_warning(path <- template_path("dp", "postage"), "dp-postage is deprecated in favor of dp-eda",
                 class = "hvtiRtemplates_deprecated")
  expect_true(file.exists(path))
  expect_warning(template_path("dp-postage"), class = "hvtiRtemplates_deprecated")

  root <- migration_study_fixture(NULL)
  caught <- list()
  job <- withCallingHandlers(
    add_job("dp", "cohort", "eda", dir = root, qualifier = "postage"),
    warning = function(w) {
      caught[[length(caught) + 1L]] <<- w
      invokeRestart("muffleWarning")
    }
  )
  expect_true(file.exists(job))
  expect_length(caught, 1L)
  expect_s3_class(caught[[1L]], "hvtiRtemplates_deprecated")
  message <- conditionMessage(caught[[1L]])
  expect_match(message, "^add_job\\(\\): dp-postage is deprecated in favor of dp-eda")
  expect_match(message, 'qualifier = "eda"', fixed = TRUE)
  expect_match(message, 'SECTIONS <- c("continuous", "percent", "count")', fixed = TRUE)

  # open_job() creates through add_job(), and says it once, in its own name.
  caught <- list()
  suppressMessages(withCallingHandlers(
    open_job("dp", "other", "eda", dir = root, qualifier = "postage"),
    warning = function(w) {
      caught[[length(caught) + 1L]] <<- w
      invokeRestart("muffleWarning")
    }
  ))
  expect_length(caught, 1L)
  expect_match(conditionMessage(caught[[1L]]), "^open_job\\(\\): dp-postage is deprecated")
})

test_that("a supported template does not warn", {
  root <- migration_study_fixture(NULL)
  expect_no_warning(template_path("dp", "eda"))
  expect_no_warning(add_job("dp", "cohort", "eda", dir = root, qualifier = "eda"))
})

test_that("the warning follows the catalog, whichever template it marks", {
  catalog <- template_catalog()
  catalog$deprecated_by[catalog$prefix == "ac"] <- "hz"
  catalog$deprecation_note[catalog$prefix == "ac"] <- "A test note."
  local_mocked_bindings(template_catalog = function() catalog)
  expect_warning(template_path("ac"), "ac is deprecated in favor of hz. A test note.", fixed = TRUE)
  catalog$deprecated_by <- NA_character_
  expect_no_warning(template_path("dp", "postage"))
})
