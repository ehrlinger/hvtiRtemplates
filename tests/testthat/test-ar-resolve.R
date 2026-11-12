# From an ar item id to verified evidence: every stop in spec section 6.2.

test_that("a well-formed id resolves to the exhibit, its file and its sidecar", {
  root <- ar_fake_study()
  ar_fake_job(root)
  r <- hvtiRtemplates:::.ar_resolve("hz.dead.hz#fig-fit", root)
  expect_identical(r$exhibit$kind, "figure")
  expect_true(file.exists(r$path))
  expect_false(r$source_changed)
})

test_that("a malformed id is refused with the expected form", {
  expect_error(hvtiRtemplates:::.ar_parse_id("hz.dead.hz"), "<job>#<label>")
  expect_error(hvtiRtemplates:::.ar_parse_id(c("a#b", "c#d")), "<job>#<label>")
})

test_that("a job that is absent, or has no sidecar, stops", {
  root <- ar_fake_study()
  expect_error(hvtiRtemplates:::.ar_resolve("hz.none.hz#fig-fit", root), "no job")
  qmd <- ar_fake_job(root)
  unlink(hvtiRutilities::provenance_path(sub("[.]qmd$", ".html", qmd)))
  expect_error(hvtiRtemplates:::.ar_resolve("hz.dead.hz#fig-fit", root), "no provenance record")
})

test_that("a draft source stops, whether by an open marker or a runtime reason, with no partial render", {
  root <- ar_fake_study()
  ar_fake_job(root, run = list(status = "draft", open_markers = 2L, skipped_chunks = 0L, stopped_early = FALSE))
  expect_error(hvtiRtemplates:::.ar_resolve("hz.dead.hz#fig-fit", root), "2 open EDIT: marker")
  ar_fake_job(root, run = list(status = "draft", open_markers = 0L, skipped_chunks = 0L, stopped_early = FALSE,
                               draft_reasons = list("the bootstrap pool is incomplete")))
  expect_error(hvtiRtemplates:::.ar_resolve("hz.dead.hz#fig-fit", root), "bootstrap pool is incomplete")
})

test_that("a sidecar with no run status is not presumed final", {
  root <- ar_fake_study()
  ar_fake_job(root, run = NULL)
  expect_error(hvtiRtemplates:::.ar_resolve("hz.dead.hz#fig-fit", root), "cannot be presumed final")
})

test_that("an unrecorded label stops and lists what the job recorded", {
  root <- ar_fake_study()
  ar_fake_job(root)
  expect_error(hvtiRtemplates:::.ar_resolve("hz.dead.hz#fig-other", root), "fig-fit, tbl-estimates, methods")
})

test_that("a missing exhibit file stops", {
  root <- ar_fake_study()
  ar_fake_job(root)
  unlink(file.path(root, "graphs", "dead-hz", "hz-fit.png"))
  expect_error(hvtiRtemplates:::.ar_resolve("hz.dead.hz#fig-fit", root), "is missing")
})

test_that("an exhibit overwritten after its sidecar was written stops on the digest", {
  root <- ar_fake_study()
  ar_fake_job(root)
  # As a re-render that wrote the figure and failed before publishing would leave it.
  writeBin(as.raw(1:4), file.path(root, "graphs", "dead-hz", "hz-fit.png"))
  expect_error(hvtiRtemplates:::.ar_resolve("hz.dead.hz#fig-fit", root), "no longer holds the bytes")
})

test_that("a job file edited since its render is flagged, not stopped", {
  root <- ar_fake_study()
  qmd <- ar_fake_job(root)
  cat("# edited\n", file = qmd, append = TRUE)
  expect_true(hvtiRtemplates:::.ar_resolve("hz.dead.hz#fig-fit", root)$source_changed)
})

test_that("Methods come from the sidecar, or from the floor when the template writes none", {
  root <- ar_fake_study()
  ar_fake_job(root)
  m <- hvtiRtemplates:::.ar_methods(hvtiRtemplates:::.ar_resolve("hz.dead.hz#fig-fit", root))
  expect_false(m$floor)
  expect_identical(m$text, "A hazard was modeled.")
  ar_fake_job(root, methods = NULL)
  m <- hvtiRtemplates:::.ar_methods(hvtiRtemplates:::.ar_resolve("hz.dead.hz#fig-fit", root))
  expect_true(m$floor)
  expect_match(m$text, "TemporalHazard 1.2.8")
  expect_false(grepl("base 4.6.1", m$text, fixed = TRUE))
})

# Rewrite the first exhibit record of a fake job's sidecar.
ar_corrupt_record <- function(qmd, ...) {
  sc <- hvtiRutilities::provenance_path(sub("[.]qmd$", ".html", qmd))
  x <- jsonlite::read_json(sc)
  edits <- list(...)
  for (n in names(edits)) x$exhibits[[1L]][[n]] <- edits[[n]]
  jsonlite::write_json(x, sc, auto_unbox = TRUE, null = "null")
}

test_that("a malformed sidecar record stops cleanly, naming the job and the label", {
  root <- ar_fake_study()
  qmd <- ar_fake_job(root)
  id <- "hz.dead.hz#fig-fit"
  ar_corrupt_record(qmd, file = "../../etc/passwd.png")
  expect_error(hvtiRtemplates:::.ar_resolve(id, root), "hz.dead.hz.*fig-fit.*inside the study")
  ar_fake_job(root)
  ar_corrupt_record(qmd, file = "/etc/hosts")
  expect_error(hvtiRtemplates:::.ar_resolve(id, root), "inside the study")
  ar_fake_job(root)
  ar_corrupt_record(qmd, kind = "bogus")
  expect_error(hvtiRtemplates:::.ar_resolve(id, root), "unknown kind 'bogus'")
  ar_fake_job(root)
  ar_corrupt_record(qmd, file = "graphs/dead-hz/a b;.png")
  expect_error(hvtiRtemplates:::.ar_resolve(id, root), "unexpected characters")
  ar_fake_job(root)
  ar_corrupt_record(qmd, label = NULL)
  expect_error(hvtiRtemplates:::.ar_resolve(id, root), "`label` is not a single string")
})

test_that("a record that resolves outside the study through a link stops", {
  root <- ar_fake_study()
  qmd <- ar_fake_job(root)
  outside <- withr::local_tempdir()
  file.copy(file.path(root, "graphs", "dead-hz", "hz-fit.png"), file.path(outside, "x.png"))
  link <- file.path(root, "graphs", "lnk")
  linked <- suppressWarnings(file.symlink(outside, link))
  skip_if_not(linked, "This platform does not permit creating symbolic links.")
  # Windows: withr's recursive unlink() of root warns on the directory reparse point, so
  # remove the link itself first, as test-migrate-job.R does. Deferred after root's and
  # outside's cleanups, it runs before them (LIFO). Built from `link`, never
  # normalizePath(), which would follow the link and have rmdir remove `outside`.
  if (.Platform$OS.type == "windows") {
    windows_link <- chartr("/", "\\", link)
    withr::defer({
      status <- system2("cmd", c("/c", "rmdir", shQuote(windows_link)))
      if (!identical(as.integer(status), 0L)) warning("rmdir on the test link returned ", status, call. = FALSE)
    })
  }
  ar_corrupt_record(qmd, file = "graphs/lnk/x.png")
  expect_error(hvtiRtemplates:::.ar_resolve("hz.dead.hz#fig-fit", root), "resolves outside the study")
})
