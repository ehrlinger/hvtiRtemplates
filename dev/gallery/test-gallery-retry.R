# Tests for gallery_build()'s retry after a Quarto CLI crash. dev/ is left out
# of the package build, so R CMD check never runs these. Run them from the
# repository root, against a private library (other sessions overwrite the
# default one):
#
#   R_LIBS=<lib> Rscript -e 'testthat::test_file("dev/gallery/test-gallery-retry.R")'
#
# Every error below is raised by quarto::quarto_render() or processx itself,
# never built by hand, so a change to the quarto package's error chain fails
# here. The crash comes from a fake quarto launcher that prints what bash
# prints when Deno segfaults. The real crash is intermittent and cannot be
# summoned on demand.

library(testthat)

repo <- local({
  d <- normalizePath(getwd())
  while (!file.exists(file.path(d, "dev", "gallery", "gallery.R"))) {
    if (dirname(d) == d) stop("Run from inside the hvtiRtemplates repository.")
    d <- dirname(d)
  }
  d
})
withr::with_dir(repo, source(file.path("dev", "gallery", "gallery.R")))

scratch <- withr::local_tempdir()
fake_quarto <- file.path(scratch, "quarto")
writeLines(c(
  "#!/bin/bash",
  'if [ "$1" = "--version" ]; then echo 1.10.18; exit 0; fi',
  # bash's report of a Deno segfault, verbatim from the launcher's line 206.
  paste0("echo '/Applications/quarto/bin/quarto: line 206: 4242 Segmentation fault: 11  ",
         '"${QUARTO_DENO}" ${QUARTO_ACTION} ${QUARTO_DENO_OPTIONS} "${QUARTO_TARGET}" "$@"', "' >&2"),
  "exit 139"
), fake_quarto)
Sys.chmod(fake_quarto, "755")
doc <- file.path(scratch, "doc.qmd")
writeLines(c("---", "title: doc", "---", "text"), doc)
# A job whose chunk fails, and whose error names the token the crash carries.
bad <- file.path(scratch, "bad.qmd")
writeLines(c("---", "title: bad", "---", "```{r}",
             'stop("QUARTO_DENO is intentionally mentioned by this analysis")', "```"), bad)

render_error <- function(expr) {
  tryCatch({
    expr
    NULL
  }, error = function(e) e)
}
crash <- function() {
  withr::with_envvar(c(QUARTO_PATH = fake_quarto), quarto::quarto_render(doc, quiet = TRUE))
}
job_fails <- function(quiet) quarto::quarto_render(bad, quiet = quiet)
has_quarto <- function() isTRUE(tryCatch(quarto::quarto_available(), error = function(e) FALSE))

test_that("the masked Deno crash is recognised", {
  e <- render_error(crash())
  expect_s3_class(e, "error")
  expect_true(gallery_quarto_crash(e))
})

test_that("a chunk error that mentions QUARTO_DENO is not a crash", {
  skip_if_not(has_quarto(), "Quarto is not installed")
  for (quiet in c(TRUE, FALSE)) {
    e <- render_error(job_fails(quiet))
    expect_s3_class(e, "error")
    expect_false(gallery_quarto_crash(e), label = paste("quiet =", quiet))
  }
})

test_that("an exit status, high or from a signal, is not a crash", {
  for (cmd in c("exit 200", "exit 139", "kill -SEGV $$")) {
    e <- render_error(processx::run("sh", c("-c", cmd), error_on_status = TRUE))
    expect_s3_class(e, "system_command_status_error")
    expect_false(gallery_quarto_crash(e), label = cmd)
  }
})

test_that("a plain error is not a crash", {
  expect_false(gallery_quarto_crash(simpleError("object 'QUARTO_DENO' not found")))
  expect_false(gallery_quarto_crash(simpleError("QUARTO_DENO")))
})

# ---- gallery_build() ---------------------------------------------------------
root <- suppressMessages(gallery_study(file.path(scratch, "study")))
first_jobs <- names(gallery_jobs())[1:3]
# Counts the renders gallery_build() asks for, so a test can see the retry.
counter <- new.env()
build <- function(only, render) {
  counter$n <- 0L
  counted <- function(job, final, quiet) {
    counter$n <- counter$n + 1L
    render(job, counter$n)
  }
  suppressMessages(gallery_build(root, only = only, render = counted))
}
write_report <- function(job) writeLines("<html></html>", sub("[.]qmd$", ".html", job))

test_that("a crash is retried once, and a good retry gives a report", {
  b <- build(first_jobs[[1]], function(job, n) if (n == 1L) crash() else write_report(job))
  expect_identical(counter$n, 2L)
  expect_identical(b$retries, 1L)
  expect_false(is.na(b$report))
  expect_true(is.na(b$error))
})

test_that("a second crash is not retried again, and the job fails", {
  b <- build(first_jobs[[2]], function(job, n) crash())
  expect_identical(counter$n, 2L)
  expect_identical(b$retries, 1L)
  expect_true(is.na(b$report))
  expect_match(b$error, "QUARTO_DENO", fixed = TRUE)
})

test_that("a job error fails at once, with no retry", {
  skip_if_not(has_quarto(), "Quarto is not installed")
  b <- build(first_jobs[[3]], function(job, n) job_fails(FALSE))
  expect_identical(counter$n, 1L)
  expect_identical(b$retries, 0L)
  expect_true(is.na(b$report))
})
