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

test_that("a file an earlier render left is not recorded, and one this run wrote is", {
  root <- local_exhibit_state()
  state <- hvtiRtemplates:::.run_state
  had <- exists("written", envir = state, inherits = FALSE)
  saved <- if (had) get("written", envir = state)
  assign("written", character(), envir = state)
  withr::defer(if (had) assign("written", saved, envir = state) else rm("written", envir = state))
  # Left on disk by an earlier render: present, with a current timestamp, but not written by this run.
  old <- file.path(root, "old.png")
  writeBin(as.raw(1), old)
  expect_null(hvtiRtemplates:::.record_exhibit(old, "figure", label = "fig-old"))
  expect_length(state$exhibits, 0L)
  # Written by this run through .save_figure(), the route save_figure() takes in a template.
  fig <- ggplot2::ggplot(data.frame(x = 1, y = 1), ggplot2::aes(x, y)) + ggplot2::geom_point()
  fresh <- file.path(root, "fresh.png")
  hvtiRtemplates:::.save_figure(fig, fresh, width = 2, height = 2, keep = "fresh")
  expect_identical(hvtiRtemplates:::.record_exhibit(fresh, "figure", label = "fig-new")$label, "fig-new")
  # A table saved by .save_exhibit() marks itself.
  expect_identical(hvtiRtemplates:::.save_exhibit(data.frame(a = 1), "table", file.path(root, "t.rds"),
                                                  label = "tbl-t")$label, "tbl-t")
  # With SAVE_FIGURES off, .save_figure() writes nothing and the leftover file stays unrecorded.
  hvtiRtemplates:::.save_figure(fig, old, width = 2, height = 2, save = FALSE)
  expect_null(hvtiRtemplates:::.record_exhibit(old, "figure", label = "fig-old"))
})

test_that("marking a file the device never wrote is silent", {
  # png() writes nothing for a page with nothing drawn on it, so .save_figure() can mark a
  # file that does not exist. That must not warn; the file is simply never recorded.
  root <- local_exhibit_state()
  state <- hvtiRtemplates:::.run_state
  assign("written", character(), envir = state)
  withr::defer(rm("written", envir = state))
  absent <- file.path(root, "blank.png")
  expect_no_warning(hvtiRtemplates:::.mark_written(absent))
  expect_null(hvtiRtemplates:::.record_exhibit(absent, "figure", label = "fig-blank"))
})
