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

test_that("render_job runs Quarto's R on the calling R unless QUARTO_R is set", {
  skip_if_not_installed("quarto")
  job <- tempfile(fileext = ".qmd")
  writeLines("x", job)
  on.exit(unlink(job), add = TRUE)
  seen <- character()
  local_mocked_bindings(
    quarto_render = function(...) seen[[length(seen) + 1L]] <<- Sys.getenv("QUARTO_R", NA),
    .package = "quarto"
  )
  old <- Sys.getenv("QUARTO_R", unset = NA)
  on.exit(if (is.na(old)) Sys.unsetenv("QUARTO_R") else Sys.setenv(QUARTO_R = old), add = TRUE)

  Sys.unsetenv("QUARTO_R")
  render_job(job)
  expect_identical(seen[[1L]], R.home("bin"))
  expect_true(is.na(Sys.getenv("QUARTO_R", unset = NA)))

  Sys.setenv(QUARTO_R = "/opt/R/chosen/bin")
  render_job(job)
  expect_identical(seen[[2L]], "/opt/R/chosen/bin")
  expect_identical(Sys.getenv("QUARTO_R"), "/opt/R/chosen/bin")

  Sys.setenv(QUARTO_R = "")
  render_job(job)
  expect_identical(seen[[3L]], R.home("bin"))
  expect_identical(Sys.getenv("QUARTO_R", unset = NA), "")
})

test_that("render_job unsets QUARTO_R after a failed render", {
  skip_if_not_installed("quarto")
  job <- tempfile(fileext = ".qmd")
  writeLines("x", job)
  on.exit(unlink(job), add = TRUE)
  local_mocked_bindings(quarto_render = function(...) stop("render failed"), .package = "quarto")
  old <- Sys.getenv("QUARTO_R", unset = NA)
  Sys.unsetenv("QUARTO_R")
  on.exit(if (is.na(old)) Sys.unsetenv("QUARTO_R") else Sys.setenv(QUARTO_R = old), add = TRUE)

  expect_error(render_job(job), "render failed")
  expect_true(is.na(Sys.getenv("QUARTO_R", unset = NA)))
})
