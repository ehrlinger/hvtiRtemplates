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
  blank <- FALSE
  if (selected || linked) {
    .unmark_written(png)
    .write_figure(plot, png, width, height, "png")
    # A blank page writes no file, and its earlier PNG is gone. Mark only what this run drew.
    blank <- !file.exists(png)
    if (!blank) .mark_written(png)
  }
  # A page that drew nothing has no publication copies either: the PDF and TIFF devices
  # would write blank pages. Without ragg no TIFF is written, so an earlier render's TIFF
  # would sit beside this run's PNG and PDF as though it matched them. Nothing in the run
  # reads either copy, so one that cannot be removed is reported, not fatal.
  if (selected && !blank) .write_figure(plot, pdf, width, height, "pdf") else if (selected) .drop_stale(pdf)
  if (selected && !blank && .ragg_available()) {
    .write_figure(plot, tiff, width, height, "tiff")
  } else if (selected) {
    .drop_stale(tiff)
  }
  # A PNG the report embeds gets a placeholder, which is never recorded.
  if (blank) {
    # The mark is dropped once the placeholder exists: one taken before a save cannot see a
    # figure removed between saves, whose earlier mark would otherwise vouch for the placeholder.
    if (linked) .unmark_written(.blank_placeholder(png))
    warning("Figure '", name, "' drew nothing; ",
            if (linked) "the report shows a placeholder" else "no figure files were saved for it",
            if (linked && selected) ", and no PDF or TIFF was saved" else "", ".", call. = FALSE)
  }
  invisible(png)
}

.drop_stale <- function(file) {
  tryCatch(.remove_figure_file(file), error = function(e) warning(conditionMessage(e), call. = FALSE))
}

# The figure is drawn in R's own temporary folder, copied beside the target under a
# hidden name, and renamed over it. file.copy() empties its target before it writes, so
# copying straight over the figure would lose the earlier one to a full disk or a dropped
# share; a rename within one folder replaces it whole. A draw or copy that fails leaves
# the earlier figure where it was. A page that drew nothing leaves no file; the earlier
# figure is then removed, so it cannot survive as this run's. A figure that is a link is
# written through to its target, and the target keeps its permissions.
.write_figure <- function(plot, file, width, height, format) {
  file <- .link_target(file)
  if (!dir.exists(dirname(file))) {
    stop("Cannot save ", basename(file), ": the folder ", dirname(file), " does not exist.", call. = FALSE)
  }
  # The scratch copy keeps the file's own name, which devices and ggsave() see.
  drawing <- tempfile("drawing-")
  if (!.make_dir(drawing)) {
    stop("Cannot draw ", basename(file), ": R's temporary folder ", dirname(drawing), " cannot be written.", call. = FALSE)
  }
  on.exit(unlink(drawing, recursive = TRUE), add = TRUE)
  scratch <- file.path(drawing, basename(file))
  .draw_figure(plot, scratch, width, height, format)
  if (!file.exists(scratch)) return(.remove_figure_file(file))
  .sweep_staged(dirname(file))
  staged <- file.path(dirname(file), paste0(".", basename(drawing), "-", basename(file)))
  on.exit(if (file.exists(staged)) unlink(staged), add = TRUE)
  if (!.copy_file(scratch, staged)) {
    stop("Could not write ", basename(file), " into ", dirname(file), ": check the folder's space and permissions, ",
         "and render again.", call. = FALSE)
  }
  if (file.exists(file)) Sys.chmod(staged, file.mode(file), use_umask = FALSE)
  if (!.rename_file(staged, file)) {
    stop("Could not replace ", file, ": close whatever holds it open, or remove it, and render again.", call. = FALSE)
  }
  invisible(file)
}

# A rename replaces a link itself, so a figure linked elsewhere, such as into a manuscript
# folder, is followed to the file it names. normalizePath() resolves a link to an existing
# file on every platform; Sys.readlink() is not implemented on Windows, so it serves only a
# link whose target is missing, read against the link's own folder. Only the file itself is
# resolved: a path through a linked folder keeps the spelling the analyst knows.
.link_target <- function(file) {
  if (file.exists(file)) {
    real <- normalizePath(file, winslash = "/", mustWork = TRUE)
    same <- identical(real, file.path(normalizePath(dirname(file), winslash = "/", mustWork = TRUE), basename(file)))
    return(if (same) file else real)
  }
  for (i in seq_len(20L)) {
    link <- .read_link(file)
    if (is.na(link) || !nzchar(link)) break
    file <- if (grepl("^(/|[A-Za-z]:)", link)) link else file.path(dirname(file), link)
    if (i == 20L) stop("Cannot save ", file, ": it is a chain of more than 20 links.", call. = FALSE)
  }
  # An entry the folder lists but file.exists() cannot reach is a link whose target is
  # missing that could not be read, as on Windows; replacing it would cut the link.
  if (!file.exists(file) && dir.exists(dirname(file)) &&
        basename(file) %in% list.files(dirname(file), all.files = TRUE, no.. = TRUE)) {
    stop("Cannot save ", file, ": it is a link to a file that does not exist. Restore the file it links to, ",
         "or remove the link, and render again.", call. = FALSE)
  }
  file
}

# A render killed between the copy and the rename leaves its staged copy, which on.exit()
# never removes. Any older than a day is cleared, once a session for each folder; a younger
# one may belong to a render still running.
.sweep_staged <- function(dir) {
  if (dir %in% .figure_state$swept) return(invisible())
  .figure_state$swept <- c(.figure_state$swept, dir)
  staged <- list.files(dir, pattern = "^[.]drawing-[0-9a-f]+-", all.files = TRUE, full.names = TRUE)
  old <- staged[difftime(Sys.time(), file.mtime(staged), units = "hours") > 24]
  if (length(old)) unlink(old)
  invisible()
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

# unlink(), file.copy(), file.rename() and dir.create() report failure only through their return values;
# these seams let a test make them fail. .read_link() lets a test read links as Windows does, and
# .png_device() lets one write a blank image for an empty page, as Windows does.
.unlink <- function(x) unlink(x)
.copy_file <- function(from, to) suppressWarnings(file.copy(from, to, overwrite = TRUE))
.rename_file <- function(from, to) suppressWarnings(file.rename(from, to))
.make_dir <- function(x) suppressWarnings(dir.create(x))
.read_link <- function(x) Sys.readlink(x)
.png_device <- function(...) grDevices::png(...)

# The report links this PNG, so a blank page would show as a broken image. Say so in the
# image; .save_figure() warns the analyst at render time.
.blank_placeholder <- function(png) {
  .write_figure(function() {
    graphics::par(mar = c(0, 0, 0, 0))
    graphics::plot.new()
    graphics::text(0.5, 0.5, "This figure drew nothing in this run.")
  }, png, 4, 1, "png")
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
    .png_device(file, width = width, height = height, units = "in", res = 300)
  }
  device <- grDevices::dev.cur()
  # Whether anything was drawn is read from the drawing, not from the file: png() writes
  # nothing for an empty page on macOS and Linux and a blank image on Windows, and pdf()
  # writes a blank page everywhere. Base and grid start a page through their new-page
  # hooks; grid drawing with no grid.newpage(), such as grid.draw() of a grob, lands on
  # grid's own display list, which grid keeps whatever the device's. Neither copies the
  # plot's data. A page that drew nothing leaves no file on every platform.
  paged <- FALSE
  started <- function(...) paged <<- TRUE
  for (hook in .page_hooks) setHook(hook, started)
  drew <- TRUE
  # dev.off() makes the next open device current, not the one that was; put
  # back the caller's, so later plotting does not land in another file. A drawing that
  # closed the device itself has written its file, which is kept.
  on.exit({
    for (hook in .page_hooks) setHook(hook, Filter(function(h) !identical(h, started), getHook(hook)), "replace")
    if (device %in% grDevices::dev.list()) grDevices::dev.off(device)
    if (before > 1L && before %in% grDevices::dev.list()) grDevices::dev.set(before)
    if (!drew) unlink(file)
  }, add = TRUE)
  plot()
  if (!paged && device %in% grDevices::dev.list()) {
    grDevices::dev.set(device)
    drew <- length(grid::grid.ls(print = FALSE)$name) > 0L
  }
  invisible(file)
}

.page_hooks <- c("before.plot.new", "before.grid.newpage")
