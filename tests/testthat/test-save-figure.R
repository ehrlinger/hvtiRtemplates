save_figure_ <- hvtiRtemplates:::.save_figure
gg <- function() {
  testthat::skip_if_not_installed("ggplot2")
  ggplot2::ggplot() + ggplot2::geom_point(ggplot2::aes(x = 1:3, y = 1:3))
}

# A SHORT or LONG tag of a TIFF's first image, such as Compression (259; 5 is
# LZW), ImageWidth (256) or ImageLength (257).
tiff_tag <- function(file, tag) {
  con <- file(file, "rb")
  on.exit(close(con))
  endian <- if (identical(readChar(con, 2L, useBytes = TRUE), "II")) "little" else "big"
  short <- function(n = 1L) readBin(con, "integer", n = n, size = 2L, signed = FALSE, endian = endian)
  short()
  seek(con, readBin(con, "integer", size = 4L, endian = endian))
  for (i in seq_len(short())) {
    head <- short(2L)
    readBin(con, "integer", size = 4L, endian = endian)
    value <- short(2L)
    if (head[[1L]] != tag) next
    if (head[[2L]] == 3L) return(value[[1L]])
    return(if (endian == "little") value[[1L]] + value[[2L]] * 65536L else value[[1L]] * 65536L + value[[2L]])
  }
  NA_integer_
}

test_that("a selected ggplot is written as a PNG, a PDF and a TIFF of the same name", {
  testthat::skip_if_not_installed("ragg")
  dir <- withr::local_tempdir()
  out <- save_figure_(gg(), file.path(dir, "job-one.png"))
  expect_identical(out, file.path(dir, "job-one.png"))
  expect_setequal(list.files(dir), c("job-one.png", "job-one.pdf", "job-one.tiff"))
})

test_that("the TIFF is LZW-compressed at 300 dpi", {
  testthat::skip_if_not_installed("ragg")
  dir <- withr::local_tempdir()
  tiff <- file.path(dir, "job-one.tiff")
  save_figure_(gg(), file.path(dir, "job-one.png"), width = 2, height = 1)
  expect_equal(tiff_tag(tiff, 259L), 5)
  expect_equal(c(tiff_tag(tiff, 256L), tiff_tag(tiff, 257L)), c(600, 300))
})

test_that("without ragg the TIFF is skipped, and the user is told once a session", {
  old <- hvtiRtemplates:::.figure_state$ragg_told
  withr::defer(assign("ragg_told", old, envir = hvtiRtemplates:::.figure_state))
  assign("ragg_told", NULL, envir = hvtiRtemplates:::.figure_state)
  expect_message(expect_false(hvtiRtemplates:::.ragg_available(FALSE)), "install the ragg package")
  expect_no_message(expect_false(hvtiRtemplates:::.ragg_available(FALSE)))

  dir <- withr::local_tempdir()
  local_mocked_bindings(.ragg_available = function() FALSE)
  save_figure_(gg(), file.path(dir, "d.png"))
  expect_setequal(list.files(dir), c("d.png", "d.pdf"))
})

test_that("SAVE_FIGURES = FALSE writes nothing unless the report links the PNG", {
  dir <- withr::local_tempdir()
  save_figure_(gg(), file.path(dir, "a.png"), save = FALSE)
  expect_length(list.files(dir), 0L)
  local_mocked_bindings(.ragg_available = function() stop("a linked-only PNG needs no TIFF"))
  save_figure_(gg(), file.path(dir, "b.png"), save = FALSE, linked = TRUE)
  expect_identical(list.files(dir), "b.png")
})

test_that("FIGURES keeps the figures whose names start with one of its entries", {
  dir <- withr::local_tempdir()
  keep <- c("dc-eda-continuous", "hp-survival")
  save_figure_(gg(), file.path(dir, "dc-eda-continuous-page-01.png"), keep = keep)
  save_figure_(gg(), file.path(dir, "dc-eda-count-page-01.png"), keep = keep)
  kept <- if (requireNamespace("ragg", quietly = TRUE)) c("png", "pdf", "tiff") else c("png", "pdf")
  expect_setequal(list.files(dir), paste0("dc-eda-continuous-page-01.", kept))
})

test_that("a list of plots is saved one file pair per element", {
  dir <- withr::local_tempdir()
  out <- save_figure_(list(gg(), gg()), file.path(dir, "rf-dependence.png"))
  expect_identical(basename(out), c("rf-dependence-1.png", "rf-dependence-2.png"))
  expect_true(all(file.exists(file.path(dir, c("rf-dependence-1.pdf", "rf-dependence-2.pdf")))))
  if (requireNamespace("ragg", quietly = TRUE)) {
    expect_true(all(file.exists(file.path(dir, c("rf-dependence-1.tiff", "rf-dependence-2.tiff")))))
  }
})

test_that("a drawing function is saved through the graphics devices", {
  dir <- withr::local_tempdir()
  draw <- function() plot(1:3, 1:3)
  save_figure_(draw, file.path(dir, "hp-survival.png"), width = 9, height = 6)
  expect_true(all(file.exists(file.path(dir, c("hp-survival.png", "hp-survival.pdf")))))
  if (requireNamespace("ragg", quietly = TRUE)) {
    expect_equal(tiff_tag(file.path(dir, "hp-survival.tiff"), 259L), 5)
  }
  expect_identical(grDevices::dev.cur(), c("null device" = 1L))
})

test_that("without cairo the default PDF device is used", {
  dir <- withr::local_tempdir()
  local_mocked_bindings(.cairo_available = function() FALSE)
  expect_identical(hvtiRtemplates:::.pdf_device(), grDevices::pdf)
  save_figure_(gg(), file.path(dir, "c.png"))
  expect_true(file.exists(file.path(dir, "c.pdf")))
})

test_that("the cairo probe answers only TRUE when cairo_pdf() opens a device, and leaves the devices as it found them", {
  # macOS R reports capabilities("cairo") TRUE without XQuartz, and cairo_pdf()
  # then opens nothing, so the probe must try the device rather than trust the flag.
  probe <- withr::local_tempfile(fileext = ".pdf")
  writes <- isTRUE(capabilities("cairo")) && tryCatch({
    suppressWarnings(grDevices::cairo_pdf(probe))
    if (grDevices::dev.cur() > 1L) {
      graphics::plot.new()
      grDevices::dev.off()
    }
    file.exists(probe)
  }, error = function(e) FALSE)
  expect_identical(hvtiRtemplates:::.cairo_probe(), writes)
  expect_identical(grDevices::dev.cur(), c("null device" = 1L))
})

test_that("the cairo probe runs once a session, not once a PDF", {
  old <- hvtiRtemplates:::.figure_state$cairo
  withr::defer(assign("cairo", old, envir = hvtiRtemplates:::.figure_state))
  assign("cairo", NULL, envir = hvtiRtemplates:::.figure_state)
  probes <- 0L
  local_mocked_bindings(.cairo_probe = function() {
    probes <<- probes + 1L
    TRUE
  })
  expect_true(hvtiRtemplates:::.cairo_available())
  expect_true(hvtiRtemplates:::.cairo_available())
  expect_identical(probes, 1L)
})

test_that("anything else is refused by name", {
  expect_error(save_figure_(42, file.path(tempdir(), "x.png")), "ggplot, a list of ggplots, or a function")
})
