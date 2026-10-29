bd_edits <- function(m, register, exclude = "list(age < 40 ~ \"Under 40\", ccfid == \"PT00007\" ~ \"Withdrew consent\")") {
  list(
    "^MASTER <- " = paste0("MASTER <- ", encodeString(m$parquet, quote = "\"")),
    "^KEEP <- c[(]" = "KEEP <- c(\"age\", \"sex\", \"iv_dead\", \"dead\", \"dt_surg\")",
    "^EXCLUDE <- " = paste0("EXCLUDE <- ", exclude),
    "^REGISTER <- " = paste0("REGISTER <- ", register)
  )
}

bd_render <- function(job) {
  quarto::quarto_render(job, execute_dir = dirname(job), quiet = TRUE)
  paste(readLines(sub("[.]qmd$", ".html", job), warn = FALSE), collapse = "\n")
}

# One registering render, made on first use and shared, because a render is most
# of this file's time: the first test reads it, the purl test compares its
# dataset against it, and the _r2 test, last in this file because it changes
# the study, renders it again. Kept until the file's tests finish.
bd_registered <- local({
  cache <- NULL
  function() {
    if (is.null(cache)) {
      m <- bd_master(.local_envir = testthat::teardown_env())
      root <- bd_study(.local_envir = testthat::teardown_env())
      job <- bd_job(root, bd_edits(m, register = "TRUE"))
      cache <<- list(m = m, root = root, job = job, html = bd_render(job))
    }
    cache
  }
})

test_that("bd registers a dated version with its build record, and ac reads it", {
  skip_on_cran()
  bd_quarto_skip()
  testthat::skip_if_not_installed("TemporalHazard")
  pub <- bd_registered()
  m <- pub$m
  root <- pub$root
  html <- pub$html

  cfg <- hvtiRutilities::study_config(root)
  expect_identical(cfg$built, "study_cohort.rds")
  expect_match(bd_current_version(root), "^study_cohort_[0-9]{8}[.]parquet$")
  prov <- bd_provenance(root)
  expect_identical(prov$origin, "bd")
  # Rendered, the record names the job by its path within the study.
  expect_identical(prov$build$job, file.path(basename(dirname(pub$job)), basename(pub$job)))
  status <- hvtiRutilities::verify_manifest(file.path(root, "manifest.yaml"))
  expect_true(all(status$status == "OK"))

  # No identifier anywhere in the report: not the master's IDs, not its MRNs,
  # and not the one an EXCLUDE rule names in the job's source.
  ids <- c(m$data$ccfid, m$data$mrn)
  expect_false(any(vapply(ids, grepl, logical(1L), x = html, fixed = TRUE)))
  expect_match(html, "Withdrew consent", fixed = TRUE)
  # The report says how it was run: the box under the title, and the table that closes it (bd has no
  # provenance chunk to carry the table, so it has a chunk of its own).
  expect_true(grepl("<strong>(final|draft)</strong>", html))
  expect_true(grepl("About this run", html, fixed = TRUE))

  # ac, chunk by chunk as the hazard chain tests run it, reads the registered version.
  built <- readRDS(file.path(hvtiRutilities::study_dir("datasets", root), cfg$built))
  cc <- hvtiRutilities::cohort_counts(built, event = "dead", time = "iv_dead")
  withr::local_package("TemporalHazard")
  withr::local_package("hvtiRutilities")
  env <- hazard_env(root)
  suppressWarnings(utils::capture.output({
    hazard_run("ac", c("set", "edit-study-choices"), env,
               list(EXPECTED = list(n = cc$n, n_events = cc$n_events, n_censored = cc$n_censored)))
    hazard_run("ac", c("tbl-data", "tbl-cohort", "km-helpers", "tbl-km-overall"), env)
  }))
  expect_setequal(env$d$ccfid, built$ccfid)
})

test_that("the purled job runs as a script and registers the same dataset in a fresh study", {
  bd_quarto_skip()
  # Study A: the shared registering render establishes the expected dataset.
  pub <- bd_registered()
  m <- pub$m
  root_a <- pub$root
  cfg_a <- hvtiRutilities::study_config(root_a)

  # Study B: scaffold only (never render), then source the purled script.
  root_b <- bd_study()
  job_b <- bd_job(root_b, bd_edits(m, register = "TRUE"))
  script <- withr::local_tempfile(fileext = ".R")
  knitr::purl(job_b, output = script, documentation = 0L, quiet = TRUE)
  withr::with_dir(dirname(job_b), utils::capture.output(source(script, local = new.env(parent = globalenv()))))

  # Study B must have exactly one version, cut by bd, and its working file must match A's.
  expect_length(bd_versions(root_b), 1L)
  cfg_b <- hvtiRutilities::study_config(root_b)
  expect_identical(bd_provenance(root_b)$origin, "bd")
  sha_a <- digest::digest(file.path(hvtiRutilities::study_dir("datasets", root_a), cfg_a$built),
                          algo = "sha256", file = TRUE)
  sha_b <- digest::digest(file.path(hvtiRutilities::study_dir("datasets", root_b), cfg_b$built),
                          algo = "sha256", file = TRUE)
  expect_identical(sha_a, sha_b)
})

test_that("a second registering render with a changed rule registers _r2, and one without REGISTER registers nothing", {
  skip_on_cran()
  bd_quarto_skip()
  # Last in this file: it changes the shared study the tests above read.
  pub <- bd_registered()
  root <- pub$root
  job <- pub$job
  first <- bd_current_version(root)

  # The same job rendered again registers nothing.
  bd_render(job)
  expect_identical(bd_current_version(root), first)
  expect_length(bd_versions(root), 1L)

  lines <- readLines(job, warn = FALSE)
  lines[grep("^EXCLUDE <- ", lines)] <- "EXCLUDE <- list(age < 50 ~ \"Under 50\")"
  writeLines(lines, job)
  html <- bd_render(job)
  second <- bd_current_version(root)
  expect_match(second, "_r2[.]parquet$")
  expect_match(html, "Registered as a new version of the study dataset", fixed = TRUE)
  expect_true(all(hvtiRutilities::verify_manifest(file.path(root, "manifest.yaml"))$status == "OK"))

  lines[grep("^EXCLUDE <- ", lines)] <- "EXCLUDE <- list(age < 60 ~ \"Under 60\")"
  lines[grep("^REGISTER <- ", lines)] <- "REGISTER <- FALSE"
  writeLines(lines, job)
  html <- bd_render(job)
  expect_match(html, "Working file only: nothing registered", fixed = TRUE)
  expect_length(bd_versions(root), 2L)
  expect_identical(bd_current_version(root), second)
})

test_that("a bd render shows the checks' counts above Register, and no patient row or identifier", {
  skip_on_cran()
  bd_quarto_skip()
  m <- bd_master()
  root <- bd_study()
  bd_run(root, bd_check_choices(m, register = TRUE))
  # The rebuild: a derivation that adds a column of distinctive strings, which a check prints.
  edits <- bd_edits(m, FALSE, exclude = "list(age < 40 ~ \"Under 40\")")
  edits[["^#   d\\$dead    <- "]] <- paste(
    "#   d$dead    <- as.integer(!is.na(d$dt_death))",
    "d$note <- sprintf(\"ZQXNOTE%04d\", seq_len(nrow(d)))", sep = "\n"
  )
  job <- bd_job(root, edits)
  lines <- readLines(job, warn = FALSE)
  queried <- readRDS(file.path(hvtiRutilities::study_dir("datasets", root), "study_cohort.rds"))$ccfid[[5L]]
  from <- grep("^CHECKS <- list\\($", lines)
  to <- from + which(lines[(from + 1L):length(lines)] == ")")[[1L]]
  lines <- c(lines[seq_len(from - 1L)],
             paste0("CHECKS <- list(!is.na(note) ~ \"Every row\", ccfid == \"", queried, "\" ~ \"Queried patient\")"),
             lines[(to + 1L):length(lines)])
  lines[grep("^PRINT_COLS <- ", lines)] <- "PRINT_COLS <- c(\"ccfid\", \"note\")"
  writeLines(lines, job)
  html <- bd_render(job)

  expect_match(html, "A rebuild of the study dataset: study_cohort.rds", fixed = TRUE)
  expect_match(html, "Every row", fixed = TRUE)
  expect_match(html, "Queried patient", fixed = TRUE)
  expect_match(html, "dead by sex", fixed = TRUE)
  # The Checks section comes before Register in the report.
  expect_lt(regexpr("What this rebuild changed", html, fixed = TRUE), regexpr(">Register<", html, fixed = TRUE))
  expect_false(grepl("ZQXNOTE", html, fixed = TRUE))
  leaked <- m$data$ccfid[vapply(m$data$ccfid, grepl, logical(1L), x = html, fixed = TRUE)]
  expect_identical(leaked, character())
})

test_that("a first bd render says nothing is registered, and a cross-tab named twice still renders", {
  skip_on_cran()
  bd_quarto_skip()
  m <- bd_master()
  root <- bd_study()
  edits <- bd_edits(m, FALSE, exclude = "list(age < 40 ~ \"Under 40\")")
  edits[["^CROSSTABS <- "]] <- "CROSSTABS <- list(c(\"dead\", \"sex\"), c(\"dead\", \"sex\"))"
  html <- bd_render(bd_job(root, edits))
  expect_match(html, "Nothing is registered for this study yet", fixed = TRUE)
  expect_false(grepl("Rows in the registered version", html, fixed = TRUE))
  expect_identical(lengths(regmatches(html, gregexpr("dead by sex, with a missing value", html, fixed = TRUE))), 2L)
})
