# Saving a template figure for a manuscript: a PNG to place in the Word draft,
# and a PDF of the same name for the publisher. Word converts an inserted PDF
# into a large EMF, so the two files have different jobs. The design is the
# 2026-10-07 figures-pdf-png note in the hvtiR repository's specs folder.
#
# A figure's name is its file stem, such as hp-survival or
# rfs-fit-diagnostics-brier. SAVE_FIGURES turns the publication copies off, and
# FIGURES keeps only the figures whose names start with one of its entries. A
# PNG the report embeds (`linked`) is written whatever they say, because the
# report would otherwise show a broken image.

# capabilities("cairo") is not enough: macOS R reports TRUE without XQuartz,
# and cairo_pdf() then only warns "failed to load cairo DLL" and opens no
# device, so the PDF would silently not be written. Probe by opening one.
.cairo_available <- function() {
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
  if (selected || linked) .write_figure(plot, png, width, height, "png")
  if (selected) .write_figure(plot, pdf, width, height, "pdf")
  invisible(png)
}

.write_figure <- function(plot, file, width, height, format) {
  if (inherits(plot, "ggplot")) {
    device <- if (identical(format, "pdf")) .pdf_device() else "png"
    ggplot2::ggsave(file, plot, device = device, width = width, height = height, units = "in", dpi = 300)
    return(invisible(file))
  }
  if (identical(format, "pdf")) {
    .pdf_device()(file, width = width, height = height)
  } else {
    grDevices::png(file, width = width, height = height, units = "in", res = 300)
  }
  on.exit(grDevices::dev.off(), add = TRUE)
  plot()
  invisible(file)
}
