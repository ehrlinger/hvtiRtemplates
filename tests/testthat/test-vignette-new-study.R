new_study_vignette_path <- function() {
  source <- testthat::test_path("..", "..", "vignettes", "new-study.qmd")
  if (file.exists(source)) return(source)
  system.file("doc", "new-study.qmd", package = "hvtiRtemplates")
}

new_study_article <- function() {
  path <- new_study_vignette_path()
  testthat::skip_if_not(file.exists(path), "vignette source not available")
  paste(readLines(path, warn = FALSE), collapse = "\n")
}

# Calls only: a quoted prefix must follow the parenthesis, so prose such as
# "`add_job()` in a study" is not mistaken for a call that omits `subject =`.
add_job_calls <- function(article) {
  regmatches(article, gregexpr("add_job\\(\"[^)]*\\)", article))[[1L]]
}

test_that("the new-study guide starts from an empty study and a delivered dataset", {
  article <- new_study_article()

  expect_false(grepl("adopt = TRUE", article, fixed = TRUE))
  expect_true(grepl("Study Tracker", article, fixed = TRUE))
  expect_true(grepl("study-setup --dry-run", article, fixed = TRUE))
  expect_true(grepl("study_setup(", article, fixed = TRUE))
  expect_true(grepl("register_data(", article, fixed = TRUE))
  expect_true(grepl('role = "study"', article, fixed = TRUE))
  expect_false(grepl("setwd[[:space:]]*[(]", article))
})

test_that("every add_job() call in the guide names a subject, never an endpoint", {
  calls <- add_job_calls(new_study_article())

  expect_gte(length(calls), 4L)
  expect_true(all(grepl("subject = ", calls, fixed = TRUE)))
  expect_false(any(grepl("endpoint", calls, fixed = TRUE)))
  expect_true(any(grepl('add_job("dc", subject = "cohort", type = "eda"', calls, fixed = TRUE) &
                    grepl('qualifier = "general"', calls, fixed = TRUE)))
})

test_that("the worked chain scaffolds ac, hz and hp into one death set", {
  calls <- add_job_calls(new_study_article())

  for (prefix in c("ac", "hz", "hp")) {
    expect_true(
      any(startsWith(calls, sprintf('add_job("%s", subject = "death", type = "hz"', prefix))),
      info = prefix
    )
  }
})

test_that("the guide explains provenance and links its sibling", {
  article <- new_study_article()

  expect_true(grepl(".provenance.json", article, fixed = TRUE))
  expect_true(grepl("study-setup.html", article, fixed = TRUE))
  expect_true(grepl("template_list()", article, fixed = TRUE))
})
