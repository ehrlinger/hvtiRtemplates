# import_job(): a job carried from one study into another (#479).

import_study <- function(name, .local_envir = parent.frame()) {
  root <- withr::local_tempdir(paste0("import-", name, "-"), .local_envir = .local_envir)
  suppressMessages(hvtiRutilities::study_setup(
    root, study = paste("Import", name), study_tracker_id = 7L, adopt = TRUE, cleanup = FALSE, renv = FALSE
  ))
  normalizePath(root, winslash = "/")
}

# An ac job in `root` with the other study's edits: a dataset, a row selection
# and an absolute path to that study's file.
edited_ac <- function(root) {
  job <- add_job("ac", subject = "death", type = "hz", dir = root)
  lines <- readLines(job, warn = FALSE)
  lines[lines == 'DATASET <- "built"'] <- 'DATASET <- "built_aorta"'
  lines[lines == "WHERE <- NULL"] <- "WHERE <- quote(aorta == 1)"
  at <- grep("^DATASET <- ", lines)
  lines <- append(lines, '# Cohort list from "/studies/aorta/datasets/cohort.csv".', after = at)
  writeLines(lines, job)
  job
}

test_that("a job is imported with its edits, renamed to the new set", {
  other <- import_study("other")
  here <- import_study("here")
  from <- edited_ac(other)
  msg <- character()
  out <- withCallingHandlers(import_job(from, subject = "reop", dir = here),
                             message = function(m) {
                               msg <<- c(msg, conditionMessage(m))
                               invokeRestart("muffleMessage")
                             })

  expect_identical(normalizePath(out, winslash = "/"),
                   normalizePath(file.path(hvtiRutilities::study_dir("distributions", here), "ac.reop.hz.qmd"),
                                 winslash = "/"))
  src <- readLines(from, warn = FALSE)
  got <- readLines(out, warn = FALSE)
  # Only the SUBJECT line differs; TYPE was kept.
  expect_identical(which(src != got), grep("^SUBJECT ", src))
  expect_identical(grep("^SUBJECT ", got, value = TRUE), 'SUBJECT <- "reop"')
  expect_identical(grep("^TYPE ", got, value = TRUE), grep("^TYPE ", src, value = TRUE))
  # The source's template stamp is kept, so upgrade_job() merges against the right text.
  expect_identical(grep("^<!-- hvtiRtemplates: ", got, value = TRUE), grep("^<!-- hvtiRtemplates: ", src, value = TRUE))
  expect_length(grep("^<!-- hvtiRtemplates: ", got), 1L)

  # Every carried choice is listed, by line, and no value is quoted.
  msg <- paste(msg, collapse = "\n")
  expect_match(msg, paste0("DATASET: line ", grep("^DATASET <- ", got), "\n"), fixed = TRUE)
  expect_match(msg, paste0("WHERE selection: line ", grep("^WHERE <- ", got), "\n"), fixed = TRUE)
  expect_match(msg, paste0("absolute paths: line ", grep("/studies/aorta", got, fixed = TRUE), "($|\n)"))
  expect_match(msg, paste0("EDIT: markers: lines ", toString(grep("EDIT:", got, fixed = TRUE))), fixed = TRUE)
  expect_no_match(msg, "aorta")
  # The source study is untouched.
  expect_identical(readLines(from, warn = FALSE), src)
})

test_that("a job with nothing study-specific left says so, and NULL selections are not listed", {
  other <- import_study("other")
  here <- import_study("here")
  from <- add_job("ac", subject = "death", type = "hz", dir = other)
  lines <- readLines(from, warn = FALSE)
  writeLines(gsub("EDIT:", "REVIEWED:", lines, fixed = TRUE), from)
  expect_message(out <- import_job(from, dir = here), "DATASET: line")
  msg <- paste(capture.output(import_job(from, type = "km", dir = here), type = "message"), collapse = "\n")
  expect_match(msg, "DATASET: line")
  expect_no_match(msg, "WHERE|EDIT|absolute")
  expect_true(file.exists(sub("[.]hz[.]qmd$", ".km.qmd", out)))
})

test_that("an existing job is never overwritten, and a refusal writes nothing", {
  other <- import_study("other")
  here <- import_study("here")
  from <- edited_ac(other)
  existing <- add_job("ac", subject = "death", type = "hz", dir = here)
  before <- readLines(existing, warn = FALSE)
  expect_error(import_job(from, dir = here), "^import_job\\(\\): .*already exists; refusing to overwrite")
  expect_identical(readLines(existing, warn = FALSE), before)

  # The dash spelling before 2026-10 is the same job.
  file.rename(existing, file.path(dirname(existing), "death-hz-ac.qmd"))
  expect_error(import_job(from, dir = here), "its name before 2026-10")
  expect_false(file.exists(existing))
})

test_that("a source without exactly one SUBJECT line is refused before anything is written", {
  other <- import_study("other")
  here <- import_study("here")
  from <- add_job("ac", subject = "death", type = "hz", dir = other)
  lines <- readLines(from, warn = FALSE)
  writeLines(lines[!grepl("^SUBJECT ", lines)], from)
  expect_error(import_job(from, dir = here), "0 lines matching")
  expect_length(list.files(here, pattern = "[.]qmd$", recursive = TRUE), 0L)
})

test_that("from must be a job named for a template", {
  here <- import_study("here")
  expect_error(import_job(file.path(here, "nope.qmd"), dir = here), "job not found")
  odd <- file.path(here, "notes.qmd")
  writeLines("x", odd)
  expect_error(import_job(odd, dir = here), "does not name a template")
  expect_error(import_job(c("a", "b"), dir = here), "^import_job\\(\\): ")
  other <- import_study("other")
  from <- add_job("ac", subject = "death", type = "hz", dir = other)
  expect_error(import_job(from, subject = "a.b", dir = here), "^import_job\\(\\): `subject`")
})

test_that("a job's runner comes with it, or the template's when it has none", {
  other <- import_study("other")
  here <- import_study("here")
  from <- add_job("bl", subject = "death", type = "boot", dir = other)
  src_runner <- sub("[.]qmd$", ".runner.R", from)
  r <- readLines(src_runner, warn = FALSE)
  r[r == 'DATASET <- "built"'] <- 'DATASET <- "built_aorta"'
  writeLines(r, src_runner)

  expect_message(out <- import_job(from, subject = "reop", dir = here),
                 paste0("Review in ", "bl.reop.boot.runner.R:\n  DATASET: line"), fixed = TRUE)
  got <- readLines(sub("[.]qmd$", ".runner.R", out), warn = FALSE)
  expect_identical(which(r != got), grep("^SUBJECT ", r))
  expect_true('DATASET <- "built_aorta"' %in% got)

  unlink(src_runner)
  expect_message(out2 <- import_job(from, subject = "stroke", dir = here), "is the template's")
  expect_identical(readLines(sub("[.]qmd$", ".runner.R", out2), warn = FALSE)[grepl("^DATASET <- ", r)],
                   'DATASET <- "built"')
})

test_that("an imported job renders in its new study", {
  skip_on_cran()
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.2.0")
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  fx <- lm_render_fixture("binary", render = FALSE)  # nolint: object_usage_linter.
  lines <- readLines(fx$job, warn = FALSE)
  lines[lines == "WHERE <- NULL"] <- "WHERE <- quote(time > 10)"
  writeLines(lines, fx$job)

  here <- import_study("here")
  d <- lm_data()  # nolint: object_usage_linter.
  d$time <- seq_len(nrow(d))
  utils::write.csv(d, file.path(hvtiRutilities::study_dir("datasets", here), "built.csv"), row.names = FALSE)
  suppressMessages(hvtiRutilities::register_data(here, built = "built.csv"))

  out <- suppressMessages(import_job(fx$job, dir = here))
  quarto::quarto_render(out, execute_dir = dirname(out), quiet = TRUE)
  html <- sub("[.]qmd$", ".html", out)
  expect_true(file.exists(html))
  # The other study's selection was carried and applied: 110 of 120 patients,
  # and the model was fit on them.
  text <- gsub("<[^>]+>", " ", readLines(html, warn = FALSE))
  text <- trimws(text[!grepl("base64", text, fixed = TRUE)])
  expect_true("110 rows on 110 patients" %in% text)
  expect_true("110 of 110 rows analyzed; none dropped" %in% text)
})
