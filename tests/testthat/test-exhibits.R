# Exhibits: what a job offers an ar analysis report, recorded by chunk label
# with its file and digest. dev/specs/2026-11-11-ar-question-report-design.md, section 4.

test_that("an exhibit is recorded by label, kind, study-relative file and digest", {
  root <- local_exhibit_state()
  dir.create(file.path(root, "graphs", "dead-hz"), recursive = TRUE)
  png <- file.path(root, "graphs", "dead-hz", "hz-fit.png")
  writeBin(as.raw(1:10), png)
  rec <- hvtiRtemplates:::.record_exhibit(png, "figure", label = "fig-fit")
  expect_identical(rec$file, "graphs/dead-hz/hz-fit.png")
  expect_identical(rec$sha256, digest::digest(png, algo = "sha256", file = TRUE))
  expect_named(hvtiRtemplates:::.run_state$exhibits, "fig-fit")
})

test_that("a file that was not written records nothing", {
  root <- local_exhibit_state()
  expect_null(hvtiRtemplates:::.record_exhibit(file.path(root, "absent.png"), "figure", label = "fig-x"))
  expect_length(hvtiRtemplates:::.run_state$exhibits, 0L)
})

test_that("a label is required, well formed and used once", {
  root <- local_exhibit_state()
  f <- file.path(root, "a.png")
  writeBin(as.raw(1), f)
  expect_error(hvtiRtemplates:::.record_exhibit(f, "figure", label = NULL), "chunk label")
  expect_error(hvtiRtemplates:::.record_exhibit(f, "figure", label = "has space"), "chunk label")
  hvtiRtemplates:::.record_exhibit(f, "figure", label = "fig-a")
  expect_error(hvtiRtemplates:::.record_exhibit(f, "figure", label = "fig-a"), "twice")
})

test_that("an exhibit outside the study is refused", {
  local_exhibit_state()
  outside <- withr::local_tempfile(fileext = ".png")
  writeBin(as.raw(1), outside)
  expect_error(hvtiRtemplates:::.record_exhibit(outside, "figure", label = "fig-o"), "outside the study")
})

test_that("a table is a data frame and a value is a named list", {
  root <- local_exhibit_state()
  f <- file.path(root, "t.rds")
  expect_error(hvtiRtemplates:::.save_exhibit(matrix(1), "table", f, label = "tbl-m"), "data frame")
  expect_error(hvtiRtemplates:::.save_exhibit(list(1, 2), "value", f, label = "v"), "named list")
  hvtiRtemplates:::.save_exhibit(data.frame(a = 1), "table", f, label = "tbl-a")
  expect_identical(readRDS(f), data.frame(a = 1))
  expect_identical(hvtiRtemplates:::.run_state$exhibits[["tbl-a"]]$kind, "table")
})

test_that("the Methods paragraph is recorded with its digest", {
  local_exhibit_state()
  hvtiRtemplates:::.methods_text("Survival was estimated.")
  m <- hvtiRtemplates:::.run_state$methods
  expect_identical(m$text, "Survival was estimated.")
  expect_identical(m$sha256, digest::digest("Survival was estimated.", algo = "sha256", serialize = FALSE))
  expect_error(hvtiRtemplates:::.methods_text(""), "Methods paragraph")
})

test_that("the sidecar extra carries an unnamed exhibit array and drops what is empty", {
  root <- local_exhibit_state()
  expect_identical(hvtiRtemplates:::.ar_extra("abc"), list(source_sha256 = "abc"))
  f <- file.path(root, "a.png")
  writeBin(as.raw(1), f)
  hvtiRtemplates:::.record_exhibit(f, "figure", label = "fig-a")
  x <- hvtiRtemplates:::.ar_extra("abc")
  expect_null(names(x$exhibits))
  expect_identical(x$exhibits[[1]]$label, "fig-a")
})

test_that("a file older than the run is not recorded, and one written in it is", {
  root <- local_exhibit_state()
  assign("started", Sys.time(), envir = hvtiRtemplates:::.run_state)
  withr::defer(rm("started", envir = hvtiRtemplates:::.run_state))
  old <- file.path(root, "old.png")
  writeBin(as.raw(1), old)
  Sys.setFileTime(old, Sys.time() - 3600)
  expect_null(hvtiRtemplates:::.record_exhibit(old, "figure", label = "fig-old"))
  expect_length(hvtiRtemplates:::.run_state$exhibits, 0L)
  fresh <- file.path(root, "fresh.png")
  writeBin(as.raw(1), fresh)
  expect_identical(hvtiRtemplates:::.record_exhibit(fresh, "figure", label = "fig-new")$label, "fig-new")
})
