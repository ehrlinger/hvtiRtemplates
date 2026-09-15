extract_chunk <- function(path, label) {
  lines <- readLines(path, warn = FALSE)
  chunk_label <- grep(paste0("^#\\| label: ", label, "$"), lines)
  chunk_end <- chunk_label + which(lines[-seq_len(chunk_label)] == "```")[[1L]]
  parse(text = lines[(chunk_label + 1L):(chunk_end - 1L)])
}

use_whole_cohort <- function(code) {
  assignment <- vapply(code, function(expr) {
    is.call(expr) && identical(expr[[1L]], quote(`<-`)) &&
      identical(expr[[2L]], quote(ANALYSIS_SET))
  }, logical(1))
  stopifnot(sum(assignment) == 1L)
  code[[which(assignment)]] <- call("<-", as.name("ANALYSIS_SET"), NULL)
  code
}

test_that("descriptive templates can read the whole cohort", {
  template_dir <- system.file(
    "templates", "10_descriptive", package = "hvtiRtemplates"
  )
  if (!nzchar(template_dir)) {
    template_dir <- testthat::test_path(
      "..", "..", "inst", "templates", "10_descriptive"
    )
  }
  template_dir <- normalizePath(template_dir)
  templates <- file.path(template_dir, c(
    "dc-tables.qmd", "dc-gfup.qmd", "dp-postage.qmd"
  ))
  root <- file.path(tempdir(), "whole-cohort-study")
  unlink(root, recursive = TRUE)
  dir.create(file.path(root, "datasets"), recursive = TRUE)
  built <- data.frame(id = 1:4, dead = c(0, 1, 0, 1), iv_dead = c(1, 2, 3, 4))
  utils::write.csv(built, file.path(root, "datasets", "built.csv"), row.names = FALSE)
  suppressWarnings(suppressMessages(hvtiRutilities::study_setup(
    root,
    study = "Template route test",
    study_tracker_id = 999999L,
    umbrella = "Synthetic template fixture",
    owner = "hvtiRtemplates tests",
    irb_number = "SYNTHETIC",
    cvir_no = "SYNTHETIC",
    adopt = TRUE
  )))
  suppressWarnings(suppressMessages(hvtiRutilities::register_data(
    root,
    built = "built.csv",
    event = "dead",
    time = "iv_dead",
    role = "study"
  )))

  old_wd <- setwd(root)
  on.exit(setwd(old_wd), add = TRUE)
  for (template in templates) {
    env <- new.env(parent = globalenv())
    env$.root <- "."
    env$read_built <- hvtiRutilities::read_built

    code <- use_whole_cohort(extract_chunk(template, "data"))
    if (basename(template) %in% c("dc-tables.qmd", "dc-gfup.qmd", "dp-postage.qmd")) {
      env$study_config <- hvtiRutilities::study_config
      assignment <- vapply(code, function(expr) {
        is.call(expr) && identical(expr[[1L]], quote(`<-`)) && identical(expr[[2L]], quote(DATASET))
      }, logical(1))
      code[[which(assignment)]] <- call("<-", as.name("DATASET"), "study")
    }
    result <- withVisible(eval(code, envir = env))

    expect_equal(env$d, built, info = basename(template))
    expect_false(result$visible, info = basename(template))
  }
})
