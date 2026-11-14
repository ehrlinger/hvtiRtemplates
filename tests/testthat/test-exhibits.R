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

# Earlier-render copies of a figure's three files, each a few bytes no device writes.
plant_stale_figure <- function(root, stem = "fig") {
  files <- file.path(root, paste0(stem, c(".png", ".pdf", ".tiff")))
  for (f in files) writeBin(as.raw(1:8), f)
  files
}

test_that("a blank draw records nothing and leaves no earlier figure file", {
  # png() writes nothing for a page with nothing drawn, so an earlier render's files at the
  # same paths would survive. None may be recorded as this run's, or stay to be read as current.
  root <- local_exhibit_state()
  state <- hvtiRtemplates:::.run_state
  assign("written", character(), envir = state)
  withr::defer(rm("written", envir = state))
  files <- plant_stale_figure(root)
  expect_warning(hvtiRtemplates:::.save_figure(function() invisible(NULL), files[[1]], width = 2, height = 2, keep = "fig"),
                 "'fig' drew nothing; no figure files")
  expect_null(hvtiRtemplates:::.record_exhibit(files[[1]], "figure", label = "fig-blank"))
  # The PDF and TIFF devices would write blank pages for the publisher; none is written, and
  # the earlier render's copies go too.
  expect_false(any(file.exists(files)))
})

test_that("a figure saved again in the same run that draws nothing is not recorded", {
  root <- local_exhibit_state()
  state <- hvtiRtemplates:::.run_state
  assign("written", character(), envir = state)
  withr::defer(rm("written", envir = state))
  png <- file.path(root, "fig.png")
  hvtiRtemplates:::.save_figure(function() graphics::plot(1), png, 2, 2, save = FALSE, linked = TRUE)
  expect_warning(hvtiRtemplates:::.save_figure(function() invisible(NULL), png, 2, 2, save = FALSE, linked = TRUE),
                 "placeholder")
  expect_true(file.exists(png))
  expect_null(hvtiRtemplates:::.record_exhibit(png, "figure", label = "fig-again"))
})

test_that("a copy that fails partway leaves the earlier figure whole and no staged file", {
  # file.copy() empties its target before writing, so the copy goes beside the figure, never over it.
  root <- withr::local_tempdir()
  files <- plant_stale_figure(root)
  testthat::local_mocked_bindings(.copy_file = function(from, to) {
    writeBin(as.raw(0), to)
    FALSE
  })
  expect_error(hvtiRtemplates:::.save_figure(function() graphics::plot(1), files[[1]], 2, 2), "Could not write fig[.]png")
  expect_identical(readBin(files[[1]], "raw", 100L), as.raw(1:8))
  expect_setequal(list.files(root, all.files = TRUE, no.. = TRUE), basename(files))
})

test_that("a figure that cannot be renamed into place keeps the earlier one and no staged file", {
  root <- withr::local_tempdir()
  files <- plant_stale_figure(root)
  testthat::local_mocked_bindings(.rename_file = function(from, to) FALSE)
  expect_error(hvtiRtemplates:::.save_figure(function() graphics::plot(1), files[[1]], 2, 2), "Could not replace")
  expect_identical(readBin(files[[1]], "raw", 100L), as.raw(1:8))
  expect_setequal(list.files(root, all.files = TRUE, no.. = TRUE), basename(files))
})

test_that("a temporary folder that cannot be made names it", {
  root <- withr::local_tempdir()
  testthat::local_mocked_bindings(.make_dir = function(x) FALSE)
  expect_error(hvtiRtemplates:::.save_figure(function() graphics::plot(1), file.path(root, "fig.png"), 2, 2),
               "temporary folder .* cannot be written")
})

test_that("a linked placeholder is staged like any figure", {
  # A placeholder that cannot be put in place says why, rather than failing in the device.
  root <- withr::local_tempdir()
  png <- file.path(root, "fig.png")
  calls <- 0L
  testthat::local_mocked_bindings(.rename_file = function(from, to) {
    calls <<- calls + 1L
    FALSE
  })
  expect_error(hvtiRtemplates:::.save_figure(function() invisible(NULL), png, 2, 2, save = FALSE, linked = TRUE),
               "Could not replace")
  expect_identical(calls, 1L)
})

test_that("without ragg an earlier render's TIFF is removed, not left beside the new figure", {
  root <- withr::local_tempdir()
  files <- plant_stale_figure(root)
  testthat::local_mocked_bindings(.ragg_available = function(...) FALSE)
  fig <- ggplot2::ggplot(data.frame(x = 1, y = 1), ggplot2::aes(x, y)) + ggplot2::geom_point()
  hvtiRtemplates:::.save_figure(fig, files[[1]], width = 2, height = 2)
  expect_false(file.exists(files[[3]]))
  expect_gt(file.size(files[[1]]), 8)
})

test_that("a draw that fails leaves the earlier figure in place and nothing else in the study", {
  root <- withr::local_tempdir()
  files <- plant_stale_figure(root)
  draw <- function() {
    graphics::plot(1)
    stop("no data to draw")
  }
  expect_error(hvtiRtemplates:::.save_figure(draw, files[[1]], width = 2, height = 2), "no data to draw")
  expect_identical(readBin(files[[1]], "raw", 100L), as.raw(1:8))
  # Drawing happens in R's temporary folder, so nothing is left in the study either.
  expect_setequal(list.files(root, all.files = TRUE, no.. = TRUE), basename(files))
})

test_that("an earlier figure that cannot be removed stops the render", {
  # On the share a viewer can hold the old PNG open; left in place it would be taken as current.
  root <- withr::local_tempdir()
  files <- plant_stale_figure(root)
  testthat::local_mocked_bindings(.unlink = function(x) 1L)
  expect_error(hvtiRtemplates:::.save_figure(function() invisible(NULL), files[[1]], width = 2, height = 2),
               "Could not replace")
})

test_that("a linked page that draws nothing gets a placeholder, which is not recorded", {
  # The report embeds a linked PNG; without one it would show a broken image.
  root <- local_exhibit_state()
  state <- hvtiRtemplates:::.run_state
  assign("written", character(), envir = state)
  withr::defer(rm("written", envir = state))
  files <- plant_stale_figure(root)
  expect_warning(hvtiRtemplates:::.save_figure(function() invisible(NULL), files[[1]], 2, 2, save = FALSE, linked = TRUE),
                 "'fig' drew nothing")
  expect_gt(file.size(files[[1]]), 8)
  expect_null(hvtiRtemplates:::.record_exhibit(files[[1]], "figure", label = "fig-blank"))
})

test_that("a new figure that cannot be written stops the render and keeps the earlier one", {
  root <- withr::local_tempdir()
  files <- plant_stale_figure(root)
  testthat::local_mocked_bindings(.copy_file = function(from, to) FALSE)
  fig <- ggplot2::ggplot(data.frame(x = 1, y = 1), ggplot2::aes(x, y)) + ggplot2::geom_point()
  expect_error(hvtiRtemplates:::.save_figure(fig, files[[1]], 2, 2), "Could not write")
  expect_identical(readBin(files[[1]], "raw", 100L), as.raw(1:8))
})

test_that("a figure for a folder that does not exist names the folder", {
  missing <- file.path(withr::local_tempdir(), "no-such-folder", "fig.png")
  expect_error(hvtiRtemplates:::.save_figure(function() graphics::plot(1), missing, 2, 2), "no-such-folder does not exist")
})

test_that("without ragg a stale TIFF that cannot be removed warns and the figure is still saved", {
  root <- withr::local_tempdir()
  files <- plant_stale_figure(root)
  testthat::local_mocked_bindings(.ragg_available = function(...) FALSE, .unlink = function(x) 1L)
  fig <- ggplot2::ggplot(data.frame(x = 1, y = 1), ggplot2::aes(x, y)) + ggplot2::geom_point()
  expect_warning(hvtiRtemplates:::.save_figure(fig, files[[1]], 2, 2), "Could not replace .*fig[.]tiff")
  expect_gt(file.size(files[[1]]), 8)
  expect_gt(file.size(files[[2]]), 8)
})

test_that("a figure that is a link is written through to its target, and the link stays", {
  # A rename replaces the link itself, so a figure linked into a manuscript folder would
  # silently stop updating there.
  root <- withr::local_tempdir()
  elsewhere <- withr::local_tempdir()
  target <- file.path(elsewhere, "fig.png")
  writeBin(as.raw(1:8), target)
  png <- file.path(root, "fig.png")
  linked <- suppressWarnings(file.symlink(target, png))
  skip_if_not(linked, "This platform does not permit creating symbolic links.")
  hvtiRtemplates:::.save_figure(function() graphics::plot(1), png, 2, 2, save = FALSE, linked = TRUE)
  # Sys.readlink() reads "" on Windows, so the link is shown to stand by reading through it.
  expect_gt(file.size(target), 8)
  expect_identical(readBin(png, "raw", 1e6), readBin(target, "raw", 1e6))
})

test_that("a replaced figure keeps its permissions", {
  root <- withr::local_tempdir()
  files <- plant_stale_figure(root)
  Sys.chmod(files[[1]], "664", use_umask = FALSE)
  before <- file.mode(files[[1]])
  hvtiRtemplates:::.save_figure(function() graphics::plot(1), files[[1]], 2, 2, save = FALSE, linked = TRUE)
  expect_gt(file.size(files[[1]]), 8)
  expect_identical(file.mode(files[[1]]), before)
})

test_that("a staged copy a killed render left is cleared once it is a day old", {
  root <- withr::local_tempdir()
  old <- file.path(root, ".drawing-1a2b-fig.png")
  young <- file.path(root, ".drawing-3c4d-fig.png")
  writeBin(as.raw(1:8), old)
  writeBin(as.raw(1:8), young)
  Sys.setFileTime(old, Sys.time() - 2 * 86400)
  hvtiRtemplates:::.save_figure(function() graphics::plot(1), file.path(root, "fig.png"), 2, 2, save = FALSE, linked = TRUE)
  expect_false(file.exists(old))
  expect_true(file.exists(young))
})

test_that("a blank linked figure's warning says its PDF and TIFF were not saved", {
  root <- withr::local_tempdir()
  files <- plant_stale_figure(root)
  expect_warning(hvtiRtemplates:::.save_figure(function() invisible(NULL), files[[1]], 2, 2, linked = TRUE),
                 "placeholder, and no PDF or TIFF was saved")
  expect_false(file.exists(files[[2]]))
})

test_that("a figure removed between saves cannot vouch for a later placeholder", {
  root <- local_exhibit_state()
  state <- hvtiRtemplates:::.run_state
  assign("written", character(), envir = state)
  withr::defer(rm("written", envir = state))
  png <- file.path(root, "fig.png")
  hvtiRtemplates:::.save_figure(function() graphics::plot(1), png, 2, 2, save = FALSE, linked = TRUE)
  unlink(png)
  expect_warning(hvtiRtemplates:::.save_figure(function() invisible(NULL), png, 2, 2, save = FALSE, linked = TRUE),
                 "placeholder")
  expect_true(file.exists(png))
  expect_null(hvtiRtemplates:::.record_exhibit(png, "figure", label = "fig-removed"))
})

test_that("a page that drew nothing leaves no file, even from a device that writes a blank one", {
  # png() on Windows writes a blank image for an empty page, as pdf() does everywhere, so
  # whether a page was drawn cannot be read from the file.
  f <- file.path(withr::local_tempdir(), "fig.pdf")
  hvtiRtemplates:::.draw_figure(function() invisible(NULL), f, 2, 2, "pdf")
  expect_false(file.exists(f))
  # grid draws without grid.newpage(), as grid.draw() of a grob does; that is a page.
  hvtiRtemplates:::.draw_figure(function() grid::grid.rect(), f, 2, 2, "pdf")
  expect_true(file.exists(f))
})

test_that("a linked figure is followed where links read as empty, as on Windows", {
  root <- withr::local_tempdir()
  elsewhere <- withr::local_tempdir()
  target <- file.path(elsewhere, "fig.png")
  writeBin(as.raw(1:8), target)
  png <- file.path(root, "fig.png")
  skip_if_not(suppressWarnings(file.symlink(target, png)), "This platform does not permit creating symbolic links.")
  testthat::local_mocked_bindings(.read_link = function(x) "")
  hvtiRtemplates:::.save_figure(function() graphics::plot(1), png, 2, 2, save = FALSE, linked = TRUE)
  expect_gt(file.size(target), 8)
})

test_that("a drawing that closes its own device keeps its figure and opens no other", {
  root <- withr::local_tempdir()
  withr::local_dir(root)
  png <- file.path(root, "fig.png")
  # grid drawing with no grid.newpage() fires no page hook, so the check after drawing runs.
  draw <- function() {
    grid::grid.rect(gp = grid::gpar(fill = "gray"))
    grDevices::dev.off()
  }
  expect_no_warning(hvtiRtemplates:::.save_figure(draw, png, 2, 2, save = FALSE, linked = TRUE))
  expect_gt(file.size(png), 1000)
  expect_false(file.exists(file.path(root, "Rplots.pdf")))
})

test_that("a blank figure is caught end to end where png() writes a blank image, as on Windows", {
  root <- withr::local_tempdir()
  files <- plant_stale_figure(root)
  testthat::local_mocked_bindings(.png_device = function(file, ...) grDevices::pdf(file))
  expect_warning(hvtiRtemplates:::.save_figure(function() invisible(NULL), files[[1]], 2, 2),
                 "'fig' drew nothing; no figure files")
  expect_false(any(file.exists(files)))
})

test_that("a link to a missing file that cannot be read is refused, not replaced", {
  root <- withr::local_tempdir()
  png <- file.path(root, "fig.png")
  skip_if_not(suppressWarnings(file.symlink(file.path(root, "gone", "fig.png"), png)),
              "This platform does not permit creating symbolic links.")
  testthat::local_mocked_bindings(.read_link = function(x) "")
  # Windows file.exists() reports the link itself, so there the mapped-drive guard refuses it;
  # either refusal leaves the link in place.
  expect_error(hvtiRtemplates:::.save_figure(function() graphics::plot(1), png, 2, 2, save = FALSE, linked = TRUE),
               "link (to a file that does not exist|this system could not follow)")
  expect_true(basename(png) %in% list.files(root, all.files = TRUE))
})

test_that("a study reached through a linked folder keeps its own path in messages", {
  real <- withr::local_tempdir()
  parent <- withr::local_tempdir()
  study <- file.path(parent, "study")
  local_dir_link(real, study)
  writeBin(as.raw(1:8), file.path(real, "fig.png"))
  testthat::local_mocked_bindings(.copy_file = function(from, to) FALSE)
  err <- tryCatch(hvtiRtemplates:::.save_figure(function() graphics::plot(1), file.path(study, "fig.png"), 2, 2,
                                                save = FALSE, linked = TRUE), error = conditionMessage)
  # dirname() writes / on Windows, so the comparison is made in that form.
  expect_match(err, chartr("\\", "/", file.path(parent, "study")), fixed = TRUE)
})

test_that("a page that is only set up, by base or grid, counts as drawing nothing", {
  # plot.new() and grid.newpage() record on the display list without marking the page.
  root <- local_exhibit_state()
  state <- hvtiRtemplates:::.run_state
  assign("written", character(), envir = state)
  withr::defer(rm("written", envir = state))
  setups <- list(base = function() {
    graphics::plot.new()
    graphics::plot.window(c(0, 1), c(0, 1))
  }, grid = function() {
    grid::grid.newpage()
    grid::pushViewport(grid::viewport())
  })
  for (nm in names(setups)) {
    files <- plant_stale_figure(root, nm)
    expect_warning(hvtiRtemplates:::.save_figure(setups[[nm]], files[[1]], 2, 2, linked = TRUE),
                   "placeholder, and no PDF or TIFF was saved")
    expect_null(hvtiRtemplates:::.record_exhibit(files[[1]], "figure", label = paste0("fig-", nm)))
    expect_false(any(file.exists(files[2:3])))
  }
})

test_that("a figure that is a link the system could not follow is refused, not replaced", {
  # On a mapped Windows drive normalizePath() can return the link's own path.
  root <- withr::local_tempdir()
  files <- plant_stale_figure(root)
  testthat::local_mocked_bindings(.is_link = function(file) TRUE)
  expect_error(hvtiRtemplates:::.save_figure(function() graphics::plot(1), files[[1]], 2, 2, save = FALSE, linked = TRUE),
               "link this system could not follow")
  expect_identical(readBin(files[[1]], "raw", 100L), as.raw(1:8))
})

test_that("a display-list entry of an unexpected shape counts as drawing, not as an error", {
  odd <- list(list(quote(f), list()), list(quote(f)), list(quote(f), "x"))
  for (entry in odd) expect_true(hvtiRtemplates:::.marks_page(list(entry)))
})

test_that("a drawing that closes its own device on an empty page saves nothing", {
  # The real devices: png() writes no file for it on macOS and Linux and a blank image on Windows.
  root <- withr::local_tempdir()
  withr::local_dir(root)
  png <- file.path(root, "fig.png")
  expect_warning(hvtiRtemplates:::.save_figure(function() grDevices::dev.off(), png, 2, 2, save = TRUE, linked = FALSE),
                 "'fig' drew nothing; no figure files were saved")
  expect_false(file.exists(png))
})

test_that("a device-closed PNG that matches the device's empty page is taken as blank", {
  # A device that writes the same bytes whether or not anything is drawn, as Windows png()
  # writes the same blank image for every empty page of one size.
  root <- withr::local_tempdir()
  png <- file.path(root, "fig.png")
  testthat::local_mocked_bindings(.png_device = function(filename, ...) {
    writeBin(as.raw(1:4), filename)
    grDevices::pdf(NULL)
  })
  expect_warning(hvtiRtemplates:::.save_figure(function() grDevices::dev.off(), png, 2, 2, save = TRUE, linked = FALSE),
                 "'fig' drew nothing")
  expect_false(file.exists(png))
})

test_that("a figure made a link after an earlier save is checked again, not replaced", {
  # The mapped-drive case, where normalizePath() returns the link's own path: each save asks afresh.
  root <- withr::local_tempdir()
  files <- plant_stale_figure(root)
  answers <- c(FALSE, TRUE)
  testthat::local_mocked_bindings(.on_windows = function() TRUE, .windows_link = function(file) {
    answer <- answers[[1L]]
    answers <<- answers[-1L]
    answer
  })
  hvtiRtemplates:::.save_figure(function() graphics::plot(1), files[[1]], 2, 2, save = FALSE, linked = TRUE)
  saved <- readBin(files[[1]], "raw", file.size(files[[1]]))
  expect_error(hvtiRtemplates:::.save_figure(function() graphics::plot(2), files[[1]], 2, 2, save = FALSE, linked = TRUE),
               "link this system could not follow")
  expect_identical(readBin(files[[1]], "raw", file.size(files[[1]])), saved)
})

test_that("a link lookup that fails refuses the save rather than taking the file as plain", {
  root <- withr::local_tempdir()
  files <- plant_stale_figure(root)
  testthat::local_mocked_bindings(.on_windows = function() TRUE, .windows_link = function(file) NA)
  expect_error(hvtiRtemplates:::.save_figure(function() graphics::plot(1), files[[1]], 2, 2, save = FALSE, linked = TRUE),
               "whether it is a link could not be checked")
  expect_identical(readBin(files[[1]], "raw", 100L), as.raw(1:8))
})

test_that("the platform's own link lookup tells a link, a file and a failed lookup apart", {
  # The real lookup, not a stand-in: dir on Windows, Sys.readlink() elsewhere. The link's
  # name is not ASCII, which a codepage could mangle.
  root <- withr::local_tempdir()
  target <- file.path(root, "target.png")
  writeBin(as.raw(1:8), target)
  link <- file.path(root, enc2utf8("hz-s\u00fc\u00df.png"))
  plain <- file.path(root, "plain.png")
  writeBin(as.raw(1:8), plain)
  skip_if_not(suppressWarnings(file.symlink(target, link)), "This platform does not permit creating symbolic links.")
  expect_true(hvtiRtemplates:::.is_link(link))
  expect_false(hvtiRtemplates:::.is_link(plain))
  if (.Platform$OS.type == "windows") expect_true(is.na(hvtiRtemplates:::.windows_link(file.path(root, "absent.png"))))
})
