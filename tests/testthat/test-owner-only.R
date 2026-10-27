# POSIX mode bits do not govern access on Windows, so the modes are asserted elsewhere only;
# the value and the error paths are checked everywhere.
owner_only_mode <- function(path) format(file.mode(path))
posix <- .Platform$OS.type != "windows"
# A permissive umask for the test, as a shared server's default often is, restored afterwards.
local_permissive_umask <- function(.local_envir = parent.frame()) {
  old <- Sys.umask("0022")
  withr::defer(Sys.umask(old), envir = .local_envir)
}

test_that(".owner_only() creates a file owner-only and returns the value", {
  dir <- withr::local_tempdir()
  local_permissive_umask()
  f <- file.path(dir, "fit.rds")
  expect_identical(.owner_only(f, {
    saveRDS(1:3, f)
    "done"
  }), "done")
  if (posix) expect_identical(owner_only_mode(f), "600")
  expect_identical(Sys.umask(), as.octmode("0022"))
})

test_that(".owner_only() protects a file it writes over, which umask alone would leave as it was", {
  dir <- withr::local_tempdir()
  local_permissive_umask()
  f <- file.path(dir, "fit.rds")
  saveRDS(1, f)
  Sys.chmod(f, "0644", use_umask = FALSE)
  .owner_only(f, saveRDS(2, f))
  expect_identical(readRDS(f), 2)
  if (posix) expect_identical(owner_only_mode(f), "600")
})

test_that("a write interrupted inside .owner_only() leaves an owner-only file and restores the umask", {
  dir <- withr::local_tempdir()
  local_permissive_umask()
  f <- file.path(dir, "fit.rds")
  saveRDS(1, f)
  Sys.chmod(f, "0644", use_umask = FALSE)
  g <- file.path(dir, "partial.rds")
  expect_error(.owner_only(c(f, g), {
    writeLines("half", g)
    stop("interrupted")
  }), "interrupted")
  if (posix) {
    expect_identical(owner_only_mode(f), "600")
    expect_identical(owner_only_mode(g), "600")
  }
  expect_identical(Sys.umask(), as.octmode("0022"))
})

test_that(".owner_only() names a file whose mode it cannot set", {
  dir <- withr::local_tempdir()
  f <- file.path(dir, "fit.rds")
  saveRDS(1, f)
  local_mocked_bindings(Sys.chmod = function(paths, ...) rep(FALSE, length(paths)), .package = "base")
  expect_error(.owner_only(f, NULL), "Could not make .*fit\\.rds readable by its owner only")
})
