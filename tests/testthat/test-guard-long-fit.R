test_that("an interactive session with no cached fit is stopped and told to submit the job", {
  withr::local_options(rlang_interactive = TRUE, hvtiRtemplates.allow_interactive_fit = NULL)
  dir <- withr::local_tempdir()
  expect_error(guard_long_fit("nb-boostmtree-fit", dir = dir, why = "a boostmtree fit takes hours"),
               "submit_job(", fixed = TRUE)
  expect_error(guard_long_fit("nb-boostmtree-fit", dir = dir, why = "a boostmtree fit takes hours"),
               "a boostmtree fit takes hours", fixed = TRUE)
})

test_that("a cached fit, the escape option, or a non-interactive render lets the fit proceed", {
  dir <- withr::local_tempdir()
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
  expect_error(guard_long_fit(c("a", "b"), dir = ".", why = "slow"), "`name`")
  expect_error(guard_long_fit("a", dir = NA_character_, why = "slow"), "`dir`")
})
