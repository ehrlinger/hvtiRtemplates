# dp-gfup is deprecated in favor of dc-gfup. The warning is driven by the
# catalog's deprecated_by field, not by a name in the code. dp-postage, once
# deprecated in favor of dp-eda, was removed after 1.3.0.

test_that("the catalog marks dp-gfup deprecated, and nothing else", {
  catalog <- template_catalog()
  marked <- catalog[!is.na(catalog$deprecated_by), , drop = FALSE]
  expect_identical(paste(marked$prefix, marked$qualifier, sep = "-"), "dp-gfup")
  expect_identical(marked$deprecated_by, "dc-gfup")
  expect_identical(marked$status, "shipped")
  expect_match(marked$deprecation_note, 'add_job("dc.gfup", subject = "cohort", type = "eda")', fixed = TRUE)
})

test_that("template_path(), add_job() and open_job() warn once for dp-gfup and still work", {
  expect_warning(path <- template_path("dp", "gfup"), "dp.gfup is deprecated in favor of dc.gfup",
                 class = "hvtiRtemplates_deprecated")
  expect_true(file.exists(path))
  expect_warning(template_path("dp-gfup"), class = "hvtiRtemplates_deprecated")

  root <- migration_study_fixture(NULL)
  caught <- list()
  job <- withCallingHandlers(
    add_job("dp-gfup", "cohort", "eda", dir = root),
    warning = function(w) {
      caught[[length(caught) + 1L]] <<- w
      invokeRestart("muffleWarning")
    }
  )
  expect_true(file.exists(job))
  expect_length(caught, 1L)
  expect_s3_class(caught[[1L]], "hvtiRtemplates_deprecated")
  message <- conditionMessage(caught[[1L]])
  expect_match(message, "^add_job\\(\\): dp[.]gfup is deprecated in favor of dc[.]gfup")
  expect_match(message, 'add_job("dc.gfup", subject = "cohort", type = "eda")', fixed = TRUE)

  # open_job() creates through add_job(), and says it once, in its own name.
  caught <- list()
  suppressMessages(withCallingHandlers(
    open_job("dp", "other", "eda", dir = root, qualifier = "gfup"),
    warning = function(w) {
      caught[[length(caught) + 1L]] <<- w
      invokeRestart("muffleWarning")
    }
  ))
  expect_length(caught, 1L)
  expect_match(conditionMessage(caught[[1L]]), "^open_job\\(\\): dp[.]gfup is deprecated")
})

test_that("the removed dp-postage is an unknown template, and the error offers dp.eda", {
  # No removed-template register exists: the catalog row went with the file, so
  # the standard error answers, and it lists dp.eda among the dp templates.
  root <- migration_study_fixture(NULL)
  for (call in list(quote(add_job("dp.postage", "cohort", "eda", dir = root)),
                    quote(add_job("dp", "cohort", "eda", dir = root, qualifier = "postage")),
                    quote(template_path("dp", "postage")))) {
    expect_error(eval(call), "no template qualified 'postage'. Available for this prefix: [^\n]*dp[.]eda",
                 info = deparse(call))
  }
  expect_length(list.files(root, "postage", recursive = TRUE), 0L)
  expect_false("dp.postage" %in% template_list()$name)
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
  expect_no_warning(template_path("dp", "gfup"))
})
