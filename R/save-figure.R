# Saving a template figure for a manuscript: a PNG to place in the Word draft,
# and a PDF and a TIFF of the same name for the publisher, since journals ask
# for one or the other. Word converts an inserted PDF into a large EMF, so the
# files have different jobs. The design is the 2026-10-07 figures-pdf-png note
# in the hvtiR repository's specs folder. The TIFF is the raster format the
# family delivers by default, as hvtiPlotR's save_manuscript() does.
#
# A figure's name is its file stem, such as hp-survival or
# rfs-fit-diagnostics-brier. SAVE_FIGURES turns the publication copies off, and
# FIGURES keeps only the figures whose names start with one of its entries. A
# PNG the report embeds (`linked`) is written whatever they say, because the
# report would otherwise show a broken image; a linked page that draws nothing is
# written as a placeholder that says so.

# capabilities("cairo") is not enough: macOS R reports TRUE without XQuartz,
# and cairo_pdf() then only warns "failed to load cairo DLL" and opens no
# device, so the PDF would silently not be written. Probe by opening one,
# once a session: the answer does not change while R runs.
.figure_state <- new.env(parent = emptyenv())

.cairo_available <- function() {
  if (is.null(.figure_state$cairo)) .figure_state$cairo <- .cairo_probe()
  .figure_state$cairo
}

.cairo_probe <- function() {
  if (!isTRUE(capabilities("cairo"))) return(FALSE)
  probe <- tempfile(fileext = ".pdf")
  on.exit(unlink(probe), add = TRUE)
  before <- grDevices::dev.cur()
  opened <- tryCatch({
    suppressWarnings(grDevices::cairo_pdf(probe))
    !identical(grDevices::dev.cur(), before)
  }, error = function(e) FALSE)
  if (opened) {
    grDevices::dev.off()
    if (before > 1L) grDevices::dev.set(before)
  }
  opened
}

# Fonts are embedded with cairo, so 12 pt type prints as designed.
.pdf_device <- function() if (.cairo_available()) grDevices::cairo_pdf else grDevices::pdf

# grDevices::tiff() cannot compress on macOS without XQuartz, and an
# uncompressed 300 dpi TIFF runs to megabytes, so the TIFF goes through ragg.
# ragg is suggested, not imported: without it the TIFF is skipped, and the user
# is told once a session rather than once a figure.
.ragg_available <- function(installed = requireNamespace("ragg", quietly = TRUE)) {
  if (installed) return(TRUE)
  if (is.null(.figure_state$ragg_told)) {
    .figure_state$ragg_told <- TRUE
    message("Figures are saved without a TIFF copy: install the ragg package to write one.")
  }
  FALSE
}

.save_figure <- function(plot, png, width = 6, height = 4, save = TRUE, keep = NULL, linked = FALSE) {
  if (is.list(plot) && !inherits(plot, "ggplot")) {
    stems <- sprintf("%s-%d.png", sub("[.]png$", "", png), seq_along(plot))
    for (i in seq_along(plot)) .save_figure(plot[[i]], stems[[i]], width, height, save, keep, linked)
    return(invisible(stems))
  }
  if (!inherits(plot, "ggplot") && !is.function(plot)) {
    stop("A figure to save must be a ggplot, a list of ggplots, or a function that draws one.", call. = FALSE)
  }
  name <- sub("[.]png$", "", basename(png))
  selected <- isTRUE(save) && (is.null(keep) || any(startsWith(name, keep)))
  pdf <- sub("[.]png$", ".pdf", png)
  tiff <- sub("[.]png$", ".tiff", png)
  if (selected || linked) {
    .write_figure(plot, png, width, height, "png")
    # A blank page writes no file, and its earlier PNG is gone. Mark only what this run
    # drew; a PNG the report embeds gets a placeholder, which is never recorded.
    if (file.exists(png)) .mark_written(png) else if (linked) .blank_placeholder(png)
  }
  if (selected) .write_figure(plot, pdf, width, height, "pdf")
  # Without ragg no TIFF is written, so an earlier render's TIFF would sit beside this
  # run's PNG and PDF as though it matched them. Nothing in the run reads the TIFF, so
  # one that cannot be removed is reported, not fatal.
  if (selected && .ragg_available()) {
    .write_figure(plot, tiff, width, height, "tiff")
  } else if (selected) {
    tryCatch(.remove_figure_file(tiff), error = function(e) warning(conditionMessage(e), call. = FALSE))
  }
  invisible(png)
}

# The figure is drawn in R's own temporary folder and copied over the target once
# drawing has finished. A draw that fails leaves the earlier figure where it was, and a
# render killed mid-draw leaves nothing in the study. A device that drew nothing writes
# no file; the earlier figure is then removed, so it cannot survive as this run's.
.write_figure <- function(plot, file, width, height, format) {
  if (!dir.exists(dirname(file))) {
    stop("Cannot save ", basename(file), ": the folder ", dirname(file), " does not exist.", call. = FALSE)
  }
  # The scratch copy keeps the file's own name, which devices and ggsave() see.
  drawing <- tempfile("drawing-")
  dir.create(drawing)
  on.exit(unlink(drawing, recursive = TRUE), add = TRUE)
  scratch <- file.path(drawing, basename(file))
  .draw_figure(plot, scratch, width, height, format)
  if (!file.exists(scratch)) return(.remove_figure_file(file))
  if (!.copy_file(scratch, file)) {
    stop("Could not write ", file, ": close whatever holds it open, and render again.", call. = FALSE)
  }
  invisible(file)
}

# A file that cannot be removed, such as one a viewer holds open on the share, stops the
# render: left in place it would be taken as this run's figure.
.remove_figure_file <- function(file) {
  if (file.exists(file)) .unlink(file)
  if (file.exists(file)) {
    stop("Could not replace ", file, ": close whatever holds it open, or remove it, and render again.", call. = FALSE)
  }
  invisible(file)
}

# unlink() and file.copy() report failure only through their return values; these seams
# let a test make them fail.
.unlink <- function(x) unlink(x)
.copy_file <- function(from, to) suppressWarnings(file.copy(from, to, overwrite = TRUE))

# The report links this PNG, so a blank page would show as a broken image. Say so in the
# image, and in a warning the analyst sees at render time.
.blank_placeholder <- function(png) {
  .draw_figure(function() {
    graphics::par(mar = c(0, 0, 0, 0))
    graphics::plot.new()
    graphics::text(0.5, 0.5, "This figure drew nothing in this run.")
  }, png, 4, 1, "png")
  warning("Figure '", sub("[.]png$", "", basename(png)), "' drew nothing; the report shows a placeholder.", call. = FALSE)
  invisible(png)
}

.draw_figure <- function(plot, file, width, height, format) {
  # ggsave() fills the background from the plot's theme, so a transparent plot
  # stays transparent, and it leaves the active device as it found it.
  if (inherits(plot, "ggplot")) {
    device <- switch(format, pdf = .pdf_device(), tiff = ragg::agg_tiff, "png")
    extra <- if (identical(format, "tiff")) list(compression = "lzw") else list()
    do.call(ggplot2::ggsave, c(list(file, plot, device = device, width = width, height = height,
                                    units = "in", dpi = 300), extra))
    return(invisible(file))
  }
  before <- grDevices::dev.cur()
  if (identical(format, "pdf")) {
    .pdf_device()(file, width = width, height = height)
  } else if (identical(format, "tiff")) {
    ragg::agg_tiff(file, width = width, height = height, units = "in", res = 300, compression = "lzw")
  } else {
    grDevices::png(file, width = width, height = height, units = "in", res = 300)
  }
  # dev.off() makes the next open device current, not the one that was; put
  # back the caller's, so later plotting does not land in another file.
  on.exit({
    grDevices::dev.off()
    if (before > 1L) grDevices::dev.set(before)
  }, add = TRUE)
  plot()
  invisible(file)
}
