test_that("an interactive session with no cached fit is stopped and told to submit the job", {
  withr::local_options(rlang_interactive = TRUE, hvtiRtemplates.allow_interactive_fit = NULL)
  dir <- withr::local_tempdir()
  expect_error(guard_long_fit("nb-boostmtree-fit", dir = dir, why = "a boostmtree fit takes hours"),
               "run_job(", fixed = TRUE)
  expect_error(guard_long_fit("nb-boostmtree-fit", dir = dir, why = "a boostmtree fit takes hours"),
               "a boostmtree fit takes hours", fixed = TRUE)
})

test_that("a cached fit, the escape option, or a non-interactive render lets the fit proceed", {
  dir <- withr::local_tempdir()
  # Unset RSTUDIO, or this reads as a Render-button render when the suite runs from the RStudio console.
  withr::local_envvar(RSTUDIO = NA, RSTUDIO_TERM = NA, HVTI_JOB_MARKER = NA)
  withr::local_options(rlang_interactive = FALSE)
  expect_false(guard_long_fit("x", dir = dir, why = "slow"))
  withr::local_options(rlang_interactive = TRUE)
  saveRDS(1, file.path(dir, "x.rds"))
  expect_false(guard_long_fit("x", dir = dir, why = "slow"))
  unlink(file.path(dir, "x.rds"))
  withr::local_options(hvtiRtemplates.allow_interactive_fit = TRUE)
  expect_false(guard_long_fit("x", dir = dir, why = "slow"))
})

test_that("guard_long_fit() checks its arguments", {
  expect_error(guard_long_fit("a", dir = NA_character_, why = "slow"), "`dir`")
})

test_that("refit = TRUE is refused even with a cached fit, and refit = FALSE passes", {
  dir <- withr::local_tempdir()
  withr::local_options(rlang_interactive = TRUE, hvtiRtemplates.allow_interactive_fit = NULL)
  saveRDS(1, file.path(dir, "x.rds"))
  expect_error(guard_long_fit("x", dir = dir, why = "slow", refit = TRUE), "REFIT")
  expect_false(guard_long_fit("x", dir = dir, why = "slow", refit = FALSE))
  expect_error(guard_long_fit("x", dir = dir, why = "slow", refit = NA), "`refit`")
})

test_that("several names pass only when every cache exists", {
  dir <- withr::local_tempdir()
  withr::local_options(rlang_interactive = TRUE, hvtiRtemplates.allow_interactive_fit = NULL)
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

test_that("a Render-button render with no cached fit is stopped and told to submit the job", {
  dir <- withr::local_tempdir()
  withr::local_envvar(RSTUDIO = "1", RSTUDIO_TERM = NA, HVTI_JOB_MARKER = NA)
  withr::local_options(rlang_interactive = FALSE, hvtiRtemplates.allow_interactive_fit = NULL)
  expect_error(guard_long_fit("x", dir = dir, why = "slow"), "Render button", fixed = TRUE)
  expect_error(guard_long_fit("x", dir = dir, why = "slow"), "hvtiRtemplates::run_job(", fixed = TRUE)
  expect_error(guard_long_fit("x", dir = dir, why = "slow"), "the Render button works again", fixed = TRUE)
  expect_error(guard_long_fit("x", dir = dir, why = "slow", refit = TRUE), "REFIT")
})

test_that("a Render-button render passes once the fit is cached, or with the escape option", {
  dir <- withr::local_tempdir()
  withr::local_envvar(RSTUDIO = "1", RSTUDIO_TERM = NA, HVTI_JOB_MARKER = NA)
  withr::local_options(rlang_interactive = FALSE, hvtiRtemplates.allow_interactive_fit = NULL)
  saveRDS(1, file.path(dir, "x.rds"))
  expect_false(guard_long_fit("x", dir = dir, why = "slow"))
  unlink(file.path(dir, "x.rds"))
  withr::local_options(hvtiRtemplates.allow_interactive_fit = TRUE)
  expect_false(guard_long_fit("x", dir = dir, why = "slow"))
})

test_that("a render under submit_job() or from a terminal passes with no cached fit", {
  dir <- withr::local_tempdir()
  withr::local_options(rlang_interactive = FALSE, hvtiRtemplates.allow_interactive_fit = NULL)
  # submit_job() from inside RStudio: the detached render inherits RSTUDIO=1 but carries the job marker.
  withr::local_envvar(RSTUDIO = "1", RSTUDIO_TERM = NA, HVTI_JOB_MARKER = "PSHVTI1_1")
  expect_false(guard_long_fit("x", dir = dir, why = "slow"))
  # nohup quarto render from the Workbench Terminal tab.
  withr::local_envvar(RSTUDIO = "1", RSTUDIO_TERM = "2A3B4C5D", HVTI_JOB_MARKER = NA)
  expect_false(guard_long_fit("x", dir = dir, why = "slow"))
  # quarto render from an ssh login, outside RStudio.
  withr::local_envvar(RSTUDIO = NA, RSTUDIO_TERM = NA, HVTI_JOB_MARKER = NA)
  expect_false(guard_long_fit("x", dir = dir, why = "slow"))
})

test_that("the interactive stop keeps its own advice, not the Render button's", {
  dir <- withr::local_tempdir()
  withr::local_envvar(RSTUDIO = "1", RSTUDIO_TERM = NA, HVTI_JOB_MARKER = NA)
  withr::local_options(rlang_interactive = TRUE, hvtiRtemplates.allow_interactive_fit = NULL)
  expect_error(guard_long_fit("x", dir = dir, why = "slow"), "these chunks run interactively", fixed = TRUE)
})
