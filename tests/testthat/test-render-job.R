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
  # Windows has no empty environment variable: setting one to "" removes it.
  if (.Platform$OS.type != "windows") expect_identical(Sys.getenv("QUARTO_R", unset = NA), "")
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

# Quarto's Deno runtime can die as it starts. bash reports it on stderr as the
# launcher's unexpanded source line, and the quarto package, formatting that
# line with cli, turns it into an unrelated error. processx::run() is mocked
# to fail the way the launcher does, so the quarto package builds that error
# itself, on every platform, without a crash to wait for.
quarto_fails_with <- function(stderr, status) {
  real_run <- processx::run
  function(command = NULL, args = character(), ...) {
    if (identical(args, "--version")) return(real_run(command, args, ...))
    cnd <- structure(
      list(message = "System command 'quarto' failed", call = NULL, stderr = stderr, stdout = "", status = status),
      class = c("system_command_status_error", "rlib_error_3_0", "rlib_error", "error", "condition")
    )
    stop(cnd)
  }
}
deno_crash_line <- paste0(
  "/Applications/quarto/bin/quarto: line 206: 4242 Segmentation fault: 11  ",
  "\"${QUARTO_DENO}\" ${QUARTO_ACTION} ${QUARTO_DENO_OPTIONS} \"${QUARTO_TARGET}\" \"$@\""
)

test_that("render_job reports a Deno crash as Quarto's, and keeps the original", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available(), "Quarto is not installed")
  job <- tempfile(fileext = ".qmd")
  writeLines("x", job)
  on.exit(unlink(job), add = TRUE)
  local_mocked_bindings(run = quarto_fails_with(deno_crash_line, 139L), .package = "processx")

  e <- tryCatch(render_job(job, quiet = TRUE), error = function(e) e)
  expect_s3_class(e, "hvtiRtemplates_quarto_crashed")
  expect_match(conditionMessage(e), "Quarto crashed before rendering", fixed = TRUE)
  expect_match(conditionMessage(e), "Render the job again", fixed = TRUE)
  expect_true(hvtiRtemplates:::.quarto_crashed(e$parent))
})

test_that("render_job passes a job's own failure through unchanged", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available(), "Quarto is not installed")
  job <- tempfile(fileext = ".qmd")
  writeLines("x", job)
  on.exit(unlink(job), add = TRUE)
  # A chunk error that names the token, an exit status no signal produced,
  # and a stderr carrying no braces: none of them is a Quarto crash.
  for (case in list(list("Error: QUARTO_DENO is mentioned by this analysis", 1L), list("", 200L))) {
    local_mocked_bindings(run = quarto_fails_with(case[[1L]], case[[2L]]), .package = "processx")
    e <- tryCatch(render_job(job, quiet = TRUE), error = function(e) e)
    expect_s3_class(e, "error")
    expect_false(inherits(e, "hvtiRtemplates_quarto_crashed"))
    expect_false(hvtiRtemplates:::.quarto_crashed(e))
  }
})

test_that(".quarto_crashed needs the exact pair, not the token", {
  skip_if_not_installed("processx")
  expect_false(hvtiRtemplates:::.quarto_crashed(simpleError("object 'QUARTO_DENO' not found")))
  expect_false(hvtiRtemplates:::.quarto_crashed(simpleError("Could not evaluate cli `{}` expression: `QUARTO_DENO`.")))
  e <- tryCatch(processx::run("sh", c("-c", "exit 200")), error = function(e) e)
  expect_false(hvtiRtemplates:::.quarto_crashed(e))
})
