vignette_source_path <- function(name) {
  source <- testthat::test_path("..", "..", "vignettes", name)
  if (file.exists(source)) return(source)
  system.file("doc", name, package = "hvtiRtemplates")
}

study_setup_vignette_path <- function() vignette_source_path("study-setup.qmd")

# The source is in the checkout (devtools::test()) and in the installed doc/
# folder (R CMD check). An install without built vignettes, as under covr, has
# neither, and that is a missing input rather than a failing vignette.
skip_without_vignette <- function() {
  path <- study_setup_vignette_path()
  testthat::skip_if_not(file.exists(path), "vignette source not available")
  path
}

test_that("study setup vignette declares the complete workflow", {
  path <- skip_without_vignette()
  txt <- readLines(path, warn = FALSE)
  expect_true(any(grepl("adopt = TRUE", txt, fixed = TRUE)))
  expect_true(any(grepl('role = "study"', txt, fixed = TRUE)))
  expect_true(any(grepl('qualifier = "general"', txt, fixed = TRUE)))
  expect_true(any(grepl('qualifier = "tables"', txt, fixed = TRUE)))
  expect_true(any(grepl('qualifier = "postage"', txt, fixed = TRUE)))
  expect_true(any(grepl("renv::init()", txt, fixed = TRUE)))
  expect_true(any(grepl("renv::snapshot()", txt, fixed = TRUE)))
  expect_false(any(grepl("inventory-adoption-cleanup", txt, fixed = TRUE)))
  expect_false(any(grepl("cleanup_targets", txt, fixed = TRUE)))
  expect_true(any(grepl("new-study.html", txt, fixed = TRUE)))
  article <- paste(txt, collapse = " ")
  expect_true(grepl("does not declare a study-wide endpoint or cohort", article,
                    fixed = TRUE))
})

test_that("study setup explains endpoint-neutral coordinated data updates", {
  article <- paste(readLines(skip_without_vignette(), warn = FALSE), collapse = " ")

  expect_true(grepl("endpoint-neutral", article, fixed = TRUE))
  expect_true(grepl("review_data_update()", article, fixed = TRUE))
  expect_true(grepl("adopt_data_update()", article, fixed = TRUE))
  expect_true(grepl("exact release ID", article, fixed = TRUE))
  expect_false(grepl("Registration also records cohort metadata", article, fixed = TRUE))
  expect_false(grepl("provides its coordinated update operation", article, fixed = TRUE))
})

test_that("the SAS guide uses adopted-study paths and loads its packages", {
  path <- vignette_source_path("sas-to-r-descriptive.qmd")
  testthat::skip_if_not(file.exists(path), "vignette source not available")
  text <- readLines(path, warn = FALSE)
  article <- paste(text, collapse = "\n")

  expect_true(grepl("library(hvtiRutilities)", article, fixed = TRUE))
  expect_true(grepl("library(hvtiRtemplates)", article, fixed = TRUE))
  expect_false(grepl(
    "10_descriptive/cohort-eda-dc-tables.qmd", article, fixed = TRUE
  ))
  expect_true(grepl(
    "descriptive/cohort-eda-dc-tables.qmd", article, fixed = TRUE
  ))
})

test_that("tutorials use the RStudio project as the study root", {
  tutorials <- vapply(
    c("study-setup.qmd", "sas-to-r-descriptive.qmd", "new-study.qmd"),
    vignette_source_path, character(1)
  )
  testthat::skip_if_not(all(file.exists(tutorials)),
                        "vignette sources not available")

  for (tutorial in tutorials) {
    text <- readLines(tutorial, warn = FALSE)
    expect_false(any(grepl("setwd[[:space:]]*[(]", text)))
    expect_true(any(grepl("RStudio", text, fixed = TRUE)))
    expect_true(any(grepl(".Rproj", text, fixed = TRUE)))
  }
})

test_that("adoption preserves a pinned R version and otherwise uses R 4.6", {
  text <- readLines(skip_without_vignette(), warn = FALSE)
  expect_true(any(grepl("renv.lock", text, fixed = TRUE)))
  expect_true(any(grepl("already pinned", text, fixed = TRUE)))
  expect_true(any(grepl("R 4.6", text, fixed = TRUE)))
})

test_that("the released legacy article name points to study setup", {
  legacy <- testthat::test_path(
    "..", "..", "vignettes", "legacy-study-migration.qmd"
  )
  if (!file.exists(legacy)) {
    legacy <- system.file(
      "doc", "legacy-study-migration.qmd", package = "hvtiRtemplates"
    )
  }
  testthat::skip_if_not(file.exists(legacy), "vignette source not available")
  txt <- readLines(legacy, warn = FALSE)
  expect_true(any(grepl("study-setup.html", txt, fixed = TRUE)))
})

test_that("the tutorial adopts an existing study before analysis", {
  path <- skip_without_vignette()
  lines <- readLines(path, warn = FALSE)
  starts <- which(lines == "```{r}")
  code <- character()
  for (start in starts) {
    end <- start + match("```", lines[-seq_len(start)])
    chunk <- lines[seq.int(start + 1L, end - 1L)]
    code <- c(code, chunk)
  }
  env <- new.env(parent = environment())
  # A single evaluation keeps the vignette's deferred cleanup after assertions.
  checks <- quote({
    expect_true(exists("adopted_root", envir = env, inherits = FALSE))
    expect_equal(nrow(env$study_data), 40L)
    expect_named(
      env$study_jobs,
      c("general", "tables", "gfup", "trends", "postage")
    )
    expect_true(all(file.exists(env$study_jobs)))
    expect_true(all(c("datasets", "descriptive", "distributions", "analyses", "graphs", "documents", "estimates") %in%
                      list.dirs(env$root, recursive = FALSE, full.names = FALSE)))
  })
  capture.output(eval(as.expression(c(as.list(parse(text = code)), list(checks))), env))
})

test_that("the final migration verifier returns four lasting rendered fixtures", {
  expect_true(exists("render_all_migration_fixtures", mode = "function"))
  if (!exists("render_all_migration_fixtures", mode = "function")) return(invisible(NULL))
  skip_if_not_installed("hvtiRdatabuild", "0.2.1")
  skip_if_not_installed("hvtiRtables", "1.0.1")
  skip_if_not_installed("hvtiPlotR", "2.7.14")
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available(), "Quarto CLI is required for rendering")
  results <- render_all_migration_fixtures()
  expect_named(results, c("dc-tables", "dc-gfup", "dp-trends", "dp-postage"))
  for (result in results) {
    expect_true(dir.exists(result$root))
    expect_true(file.exists(result$job))
    expect_true(file.exists(result$report))
    expect_true(any(grepl("[.]html$", result$outputs)))
    expect_true(all(file.exists(result$outputs)))
  }
  expect_true(any(grepl("[.]docx$", results[["dc-tables"]]$outputs)))
  expect_equal(sum(grepl("dp-postage-page-[0-9]+[.]png$", results[["dp-postage"]]$outputs)), 2L)
})
