save_figure_ <- hvtiRtemplates:::.save_figure
gg <- function() {
  testthat::skip_if_not_installed("ggplot2")
  ggplot2::ggplot() + ggplot2::geom_point(ggplot2::aes(x = 1:3, y = 1:3))
}

test_that("a selected ggplot is written as a PNG and a PDF of the same name", {
  dir <- withr::local_tempdir()
  out <- save_figure_(gg(), file.path(dir, "job-one.png"))
  expect_identical(out, file.path(dir, "job-one.png"))
  expect_true(file.exists(file.path(dir, "job-one.png")))
  expect_true(file.exists(file.path(dir, "job-one.pdf")))
})

test_that("SAVE_FIGURES = FALSE writes nothing unless the report links the PNG", {
  dir <- withr::local_tempdir()
  save_figure_(gg(), file.path(dir, "a.png"), save = FALSE)
  expect_length(list.files(dir), 0L)
  save_figure_(gg(), file.path(dir, "b.png"), save = FALSE, linked = TRUE)
  expect_identical(list.files(dir), "b.png")
})

test_that("FIGURES keeps the figures whose names start with one of its entries", {
  dir <- withr::local_tempdir()
  keep <- c("dc-eda-continuous", "hp-survival")
  save_figure_(gg(), file.path(dir, "dc-eda-continuous-page-01.png"), keep = keep)
  save_figure_(gg(), file.path(dir, "dc-eda-count-page-01.png"), keep = keep)
  expect_setequal(list.files(dir), c("dc-eda-continuous-page-01.png", "dc-eda-continuous-page-01.pdf"))
})

test_that("a list of plots is saved one file pair per element", {
  dir <- withr::local_tempdir()
  out <- save_figure_(list(gg(), gg()), file.path(dir, "rf-dependence.png"))
  expect_identical(basename(out), c("rf-dependence-1.png", "rf-dependence-2.png"))
  expect_true(all(file.exists(file.path(dir, c("rf-dependence-1.pdf", "rf-dependence-2.pdf")))))
})

test_that("a drawing function is saved through the graphics devices", {
  dir <- withr::local_tempdir()
  draw <- function() plot(1:3, 1:3)
  save_figure_(draw, file.path(dir, "hp-survival.png"), width = 9, height = 6)
  expect_true(all(file.exists(file.path(dir, c("hp-survival.png", "hp-survival.pdf")))))
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
