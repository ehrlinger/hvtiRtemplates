bd_edits <- function(m, publish, exclude = "list(age < 40 ~ \"Under 40\", ccfid == \"PT00007\" ~ \"Withdrew consent\")") {
  list(
    "^MASTER <- " = paste0("MASTER <- ", encodeString(m$parquet, quote = "\"")),
    "^KEEP <- c[(]" = "KEEP <- c(\"age\", \"iv_dead\", \"dead\", \"dt_surg\")",
    "^EXCLUDE <- " = paste0("EXCLUDE <- ", exclude),
    "^PUBLISH <- " = paste0("PUBLISH <- ", publish)
  )
}

bd_render <- function(job) {
  quarto::quarto_render(job, execute_dir = dirname(job), quiet = TRUE)
  paste(readLines(sub("[.]qmd$", ".html", job), warn = FALSE), collapse = "\n")
}

# One publishing render, made on first use and shared, because a render is most
# of this file's time: the first test reads it, the purl test compares its
# release against it, and the -r2 test, last in this file because it changes
# the study, renders it again. Kept until the file's tests finish.
bd_published <- local({
  cache <- NULL
  function() {
    if (is.null(cache)) {
      m <- bd_master(.local_envir = testthat::teardown_env())
      root <- bd_study(.local_envir = testthat::teardown_env())
      job <- bd_job(root, bd_edits(m, publish = "TRUE"))
      cache <<- list(m = m, root = root, job = job, html = bd_render(job))
    }
    cache
  }
})

test_that("bd publishes and registers a release, and ac reads it", {
  skip_on_cran()
  bd_quarto_skip()
  testthat::skip_if_not_installed("TemporalHazard")
  pub <- bd_published()
  m <- pub$m
  root <- pub$root
  html <- pub$html

  cfg <- hvtiRutilities::study_config(root)
  expect_match(cfg$release$release_id, "^study_cohort-[0-9]{8}-r1$")
  status <- hvtiRutilities::verify_manifest(file.path(root, "manifest.yaml"))
  expect_true(all(status$status == "OK"))

  # No identifier anywhere in the report: not the master's IDs, not its MRNs,
  # and not the one an EXCLUDE rule names in the job's source.
  ids <- c(m$data$ccfid, m$data$mrn)
  expect_false(any(vapply(ids, grepl, logical(1L), x = html, fixed = TRUE)))
  expect_match(html, "Withdrew consent", fixed = TRUE)

  # ac, chunk by chunk as the hazard chain tests run it, reads the release.
  release <- readRDS(file.path(hvtiRutilities::study_dir("datasets", root), cfg$built))
  cc <- hvtiRutilities::cohort_counts(release, event = "dead", time = "iv_dead")
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  env <- hazard_env(root)
  suppressWarnings(utils::capture.output({
    hazard_run("ac", c("set", "edit-study-choices"), env,
               list(EXPECTED = list(n = cc$n, n_events = cc$n_events, n_censored = cc$n_censored)))
    hazard_run("ac", c("tbl-data", "tbl-cohort", "km-helpers", "tbl-km-overall"), env)
  }))
  expect_setequal(env$d$ccfid, release$ccfid)
})

test_that("the purled job runs as a script and makes the release in a fresh study", {
  bd_quarto_skip()
  # Study A: the shared publishing render establishes the expected release.
  pub <- bd_published()
  m <- pub$m
  root_a <- pub$root
  cfg_a <- hvtiRutilities::study_config(root_a)

  # Study B: scaffold only (never render), then source the purled script.
  root_b <- bd_study()
  job_b <- bd_job(root_b, bd_edits(m, publish = "TRUE"))
  script <- withr::local_tempfile(fileext = ".R")
  knitr::purl(job_b, output = script, documentation = 0L, quiet = TRUE)
  withr::with_dir(dirname(job_b), utils::capture.output(source(script, local = new.env(parent = globalenv()))))

  # Study B must have exactly one release, and its release file must match A's.
  expect_length(bd_catalog_releases(root_b), 1L)
  cfg_b <- hvtiRutilities::study_config(root_b)
  expect_false(is.null(cfg_b$release$release_id))
  sha_a <- digest::digest(file.path(hvtiRutilities::study_dir("datasets", root_a), cfg_a$built),
                          algo = "sha256", file = TRUE)
  sha_b <- digest::digest(file.path(hvtiRutilities::study_dir("datasets", root_b), cfg_b$built),
                          algo = "sha256", file = TRUE)
  expect_identical(sha_a, sha_b)
})

test_that("a second publishing render with a changed rule adopts -r2, and a draft render publishes nothing", {
  skip_on_cran()
  bd_quarto_skip()
  # Last in this file: it changes the shared study the tests above read.
  pub <- bd_published()
  root <- pub$root
  job <- pub$job
  first <- hvtiRutilities::study_config(root)$release$release_id

  # The same job rendered again mints nothing.
  bd_render(job)
  expect_identical(hvtiRutilities::study_config(root)$release$release_id, first)
  expect_length(bd_catalog_releases(root), 1L)

  lines <- readLines(job, warn = FALSE)
  lines[grep("^EXCLUDE <- ", lines)] <- "EXCLUDE <- list(age < 50 ~ \"Under 50\")"
  writeLines(lines, job)
  html <- bd_render(job)
  second <- hvtiRutilities::study_config(root)$release$release_id
  expect_match(second, "-r2$")
  expect_match(html, "Adopted as the study dataset", fixed = TRUE)
  expect_true(all(hvtiRutilities::verify_manifest(file.path(root, "manifest.yaml"))$status == "OK"))

  lines[grep("^EXCLUDE <- ", lines)] <- "EXCLUDE <- list(age < 60 ~ \"Under 60\")"
  lines[grep("^PUBLISH <- ", lines)] <- "PUBLISH <- FALSE"
  writeLines(lines, job)
  html <- bd_render(job)
  expect_match(html, "Draft only: nothing published", fixed = TRUE)
  expect_length(bd_catalog_releases(root), 2L)
  expect_identical(hvtiRutilities::study_config(root)$release$release_id, second)
})
