test_that("render_job drafts by default and sets strict only for a final render", {
  skip_if_not_installed("quarto")
  job <- tempfile(fileext = ".qmd")
  writeLines("x", job)
  on.exit(unlink(job), add = TRUE)
  seen <- list()
  local_mocked_bindings(
    quarto_render = function(input, execute_dir, ...) {
      seen[[length(seen) + 1L]] <<- list(strict = Sys.getenv("HVTI_TEMPLATE_STRICT", NA), dir = execute_dir)
    },
    .package = "quarto"
  )
  old <- Sys.getenv("HVTI_TEMPLATE_STRICT", unset = NA)
  Sys.setenv(HVTI_TEMPLATE_STRICT = "0")
  on.exit(if (is.na(old)) Sys.unsetenv("HVTI_TEMPLATE_STRICT") else Sys.setenv(HVTI_TEMPLATE_STRICT = old), add = TRUE)

  render_job(job)
  render_job(job, final = TRUE)

  expect_identical(seen[[1L]]$strict, "0")
  expect_identical(seen[[2L]]$strict, "1")
  expect_identical(seen[[2L]]$dir, dirname(normalizePath(job, winslash = "/")))
  expect_identical(Sys.getenv("HVTI_TEMPLATE_STRICT"), "0")
})

test_that("render_job restores the environment when the render fails", {
  skip_if_not_installed("quarto")
  job <- tempfile(fileext = ".qmd")
  writeLines("x", job)
  on.exit(unlink(job), add = TRUE)
  local_mocked_bindings(quarto_render = function(...) stop("unresolved EDIT markers"), .package = "quarto")
  old <- Sys.getenv("HVTI_TEMPLATE_STRICT", unset = NA)
  Sys.unsetenv("HVTI_TEMPLATE_STRICT")
  on.exit(if (is.na(old)) Sys.unsetenv("HVTI_TEMPLATE_STRICT") else Sys.setenv(HVTI_TEMPLATE_STRICT = old), add = TRUE)

  expect_error(render_job(job, final = TRUE), "unresolved")
  expect_true(is.na(Sys.getenv("HVTI_TEMPLATE_STRICT", unset = NA)))
})

test_that("render_job rejects a missing file and a non-logical final", {
  expect_error(render_job(tempfile(fileext = ".qmd")), "render_job\\(\\):")
  job <- tempfile(fileext = ".qmd")
  writeLines("x", job)
  on.exit(unlink(job), add = TRUE)
  expect_error(render_job(job, final = "yes"), "render_job\\(\\):")
})

test_that("render_job rejects a directory path", {
  skip_if_not_installed("quarto")
  called <- FALSE
  local_mocked_bindings(quarto_render = function(...) called <<- TRUE, .package = "quarto")

  expect_error(render_job(tempdir()), "render_job\\(\\):")
  expect_false(called)
})
