# setup.R sets HVTI_ALLOW_LONG_FIT for the template renders; every test here unsets it, with the job marker, so it
# tests the guard itself. RSTUDIO and RSTUDIO_TERM are set as the Render button and the Terminal tab set them.
local_guard_env <- function(..., .local_envir = parent.frame()) {
  withr::local_envvar(c(HVTI_ALLOW_LONG_FIT = NA, HVTI_JOB_MARKER = NA, RSTUDIO = NA, RSTUDIO_TERM = NA, ...),
                      .local_envir = .local_envir)
  withr::local_options(hvtiRtemplates.allow_interactive_fit = NULL, .local_envir = .local_envir)
}

test_that("an interactive session with no cached fit is stopped and told to submit the job", {
  local_guard_env()
  withr::local_options(rlang_interactive = TRUE)
  dir <- withr::local_tempdir()
  expect_error(guard_long_fit("nb-boostmtree-fit", dir = dir, why = "a boostmtree fit takes hours"),
               "run_job(", fixed = TRUE)
  expect_error(guard_long_fit("nb-boostmtree-fit", dir = dir, why = "a boostmtree fit takes hours"),
               "a boostmtree fit takes hours", fixed = TRUE)
  expect_error(guard_long_fit("nb-boostmtree-fit", dir = dir, why = "a boostmtree fit takes hours"),
               class = "hvtiRtemplates_long_fit")
})

test_that("a render outside run_job() with no cached fit is stopped, from the Render button or any terminal", {
  dir <- withr::local_tempdir()
  withr::local_options(rlang_interactive = FALSE)
  # The Render button: RSTUDIO=1 and no RSTUDIO_TERM, as measured on lri 2026-11-16.
  local_guard_env(RSTUDIO = "1")
  expect_error(guard_long_fit("x", dir = dir, why = "slow"), "hvtiRtemplates::run_job(", fixed = TRUE)
  expect_error(guard_long_fit("x", dir = dir, why = "slow"), "the Render button and these chunks work again",
               fixed = TRUE)
  # quarto render, foreground or nohup, in the Workbench Terminal tab: still a child of the session.
  local_guard_env(RSTUDIO = "1", RSTUDIO_TERM = "2A3B4C5D")
  expect_error(guard_long_fit("x", dir = dir, why = "slow"), "run_job(", fixed = TRUE)
  # quarto render from an ssh login, outside RStudio.
  local_guard_env()
  expect_error(guard_long_fit("x", dir = dir, why = "slow"), "run_job(", fixed = TRUE)
})

test_that("a render under submit_job() or run_job() passes with no cached fit", {
  dir <- withr::local_tempdir()
  withr::local_options(rlang_interactive = FALSE)
  # Submitted from the RStudio console, the render inherits RSTUDIO=1 and carries the job marker.
  local_guard_env(RSTUDIO = "1", HVTI_JOB_MARKER = "PSHVTI1_1")
  expect_false(guard_long_fit("x", dir = dir, why = "slow"))
  expect_false(guard_long_fit("x", dir = dir, why = "slow", refit = TRUE))
})

test_that("a cached fit or an explicit opt-in lets the fit proceed anywhere", {
  dir <- withr::local_tempdir()
  for (interactive in c(TRUE, FALSE)) {
    withr::local_options(rlang_interactive = interactive)
    local_guard_env(RSTUDIO = "1")
    saveRDS(1, file.path(dir, "x.rds"))
    expect_false(guard_long_fit("x", dir = dir, why = "slow"))
    unlink(file.path(dir, "x.rds"))
    withr::local_options(hvtiRtemplates.allow_interactive_fit = TRUE)
    expect_false(guard_long_fit("x", dir = dir, why = "slow"))
    local_guard_env(RSTUDIO = "1", HVTI_ALLOW_LONG_FIT = "true")
    expect_false(guard_long_fit("x", dir = dir, why = "slow"))
    local_guard_env(RSTUDIO = "1", HVTI_ALLOW_LONG_FIT = "false")
    expect_error(guard_long_fit("x", dir = dir, why = "slow"), "run_job(", fixed = TRUE)
  }
})

test_that("guard_long_fit() checks its arguments", {
  expect_error(guard_long_fit("a", dir = NA_character_, why = "slow"), "`dir`")
})

test_that("refit = TRUE is refused even with a cached fit, and refit = FALSE passes", {
  dir <- withr::local_tempdir()
  local_guard_env()
  withr::local_options(rlang_interactive = TRUE)
  saveRDS(1, file.path(dir, "x.rds"))
  expect_error(guard_long_fit("x", dir = dir, why = "slow", refit = TRUE), "REFIT")
  expect_false(guard_long_fit("x", dir = dir, why = "slow", refit = FALSE))
  expect_error(guard_long_fit("x", dir = dir, why = "slow", refit = NA), "`refit`")
})

test_that("several names pass only when every cache exists", {
  dir <- withr::local_tempdir()
  local_guard_env()
  withr::local_options(rlang_interactive = TRUE)
  saveRDS(1, file.path(dir, "a.rds"))
  expect_error(guard_long_fit(c("a", "b"), dir = dir, why = "slow"), "run_job(", fixed = TRUE)
  saveRDS(1, file.path(dir, "b.rds"))
  expect_false(guard_long_fit(c("a", "b"), dir = dir, why = "slow"))
  expect_error(guard_long_fit(c("a", "b"), dir = dir, why = "slow", refit = TRUE), "REFIT")
})

test_that("a name vector with an empty or NA element is refused", {
  expect_error(guard_long_fit(c("a", ""), dir = ".", why = "slow"), "`name`")
  expect_error(guard_long_fit(c("a", NA), dir = ".", why = "slow"), "`name`")
  expect_error(guard_long_fit(character(), dir = ".", why = "slow"), "`name`")
})

# The templates ask hvtiRutilities::cache_would_fit(), the decision cache_fit() makes, before they call the guard.
# A matching key loads even under REFIT, so the Render button rerenders after run_job() with REFIT left TRUE. Written
# out as the templates write it, because cache_would_fit() reads the call's values from the frame that calls it.
test_that("a matching cache under REFIT loads, and a stale one that really computes is refused", {
  dir <- withr::local_tempdir()
  local_guard_env(RSTUDIO = "1")
  withr::local_options(rlang_interactive = FALSE)
  x <- 3
  suppressMessages(hvtiRutilities::cache_fit("k", x + 1, seed = 1L, dir = dir))
  REFIT <- TRUE  # nolint: object_name_linter.
  .code <- quote(x + 1)
  if (hvtiRutilities::cache_would_fit("k", .code, seed = 1L, dir = dir, refit = REFIT)) {
    guard_long_fit("k", dir = dir, why = "slow", refit = REFIT)
  }
  expect_equal(suppressMessages(hvtiRutilities::cache_fit("k", .code, seed = 1L, dir = dir, refit = REFIT)), 4,
               ignore_attr = TRUE)
  .code <- quote(x + 2)
  expect_true(hvtiRutilities::cache_would_fit("k", .code, seed = 1L, dir = dir, refit = REFIT))
  expect_error(guard_long_fit("k", dir = dir, why = "slow", refit = REFIT), "is being recomputed (REFIT)", fixed = TRUE)
  unlink(file.path(dir, "k.rds"))
  REFIT <- FALSE  # nolint: object_name_linter.
  expect_true(hvtiRutilities::cache_would_fit("k", .code, seed = 1L, dir = dir, refit = REFIT))
  expect_error(guard_long_fit("k", dir = dir, why = "slow", refit = REFIT), "is not cached yet", fixed = TRUE)
})

test_that("every template asks cache_would_fit() before it calls guard_long_fit()", {
  files <- list.files(system.file("templates", package = "hvtiRtemplates"), "[.]qmd$", recursive = TRUE,
                      full.names = TRUE)
  skip_if(!length(files), "the template catalog is not installed")
  n <- 0L
  for (f in files) {
    lines <- readLines(f, warn = FALSE)
    for (i in grep("hvtiRtemplates::guard_long_fit(", lines, fixed = TRUE)) {
      n <- n + 1L
      code <- grep("^\\s*(#|$)", lines[seq_len(i - 1L)], invert = TRUE, value = TRUE)
      # The guard is the first line of an if block, whose condition may run over several lines.
      expect_match(utils::tail(code, 1L), "\\) \\{$", info = paste0(basename(f), ":", i))
      expect_true(any(grepl("^\\s*if \\(", utils::tail(code, 3L))), info = paste0(basename(f), ":", i))
      expect_true(any(grepl("cache_would_fit(", utils::tail(code, 8L), fixed = TRUE)),
                  info = paste0(basename(f), ":", i))
    }
  }
  expect_gt(n, 0L)
})
