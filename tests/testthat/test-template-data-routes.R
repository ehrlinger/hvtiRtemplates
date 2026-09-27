extract_chunk <- function(path, label) {
  lines <- readLines(path, warn = FALSE)
  chunk_label <- grep(paste0("^#\\| label: ", label, "$"), lines)
  chunk_end <- chunk_label + which(lines[-seq_len(chunk_label)] == "```")[[1L]]
  parse(text = lines[(chunk_label + 1L):(chunk_end - 1L)])
}

data_route_chunks <- function(path) {
  lines <- readLines(path, warn = FALSE)
  choices <- if (any(grepl("#| label: study-choices", lines, fixed = TRUE))) {
    extract_chunk(path, "study-choices")
  } else {
    expression()
  }
  list(choices = choices, data = extract_chunk(path, "data"))
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
    "dc-general.qmd", "dc-tables.qmd", "dc-gfup.qmd", "dp-postage.qmd", "dp-eda.qmd"
  ))
  root <- file.path(tempdir(), "whole-cohort-study")
  unlink(root, recursive = TRUE)
  suppressMessages(hvtiRutilities::study_setup(
    root, study = "Template route test", study_tracker_id = 1L
  ))
  built <- data.frame(id = 1:4, dead = c(0, 1, 0, 1), iv_dead = c(1, 2, 3, 4))
  data_dir <- hvtiRutilities::study_dir("datasets", root)
  utils::write.csv(built, file.path(data_dir, "built.csv"), row.names = FALSE)
  suppressWarnings(
    suppressMessages(hvtiRutilities::register_data(
      root, built = "built.csv"
    ))
  )

  old_wd <- setwd(root)
  on.exit(setwd(old_wd), add = TRUE)
  for (template in templates) {
    env <- new.env(parent = globalenv())
    env$.root <- "."
    env$read_built <- hvtiRutilities::read_built
    chunks <- data_route_chunks(template)
    if (length(chunks$choices)) eval(use_whole_cohort(chunks$choices), envir = env)
    result <- withVisible(eval(
      if (length(chunks$choices)) chunks$data else use_whole_cohort(chunks$data), envir = env
    ))

    expect_equal(env$d, built, info = basename(template))
    expect_false(result$visible, info = basename(template))
  }
})

set_assignment <- function(code, name, value) {
  assignment <- vapply(code, function(expr) {
    is.call(expr) && identical(expr[[1L]], quote(`<-`)) &&
      identical(expr[[2L]], as.name(name))
  }, logical(1))
  stopifnot(sum(assignment) == 1L)
  code[[which(assignment)]] <- call("<-", as.name(name), value)
  code
}

test_that("descriptive templates read a named additional dataset", {
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
    "dc-general.qmd", "dc-tables.qmd", "dc-gfup.qmd", "dp-postage.qmd", "dp-eda.qmd"
  ))
  root <- file.path(tempdir(), "named-dataset-study")
  unlink(root, recursive = TRUE)
  suppressMessages(hvtiRutilities::study_setup(
    root, study = "Template named dataset test", study_tracker_id = 1L
  ))
  built <- data.frame(id = 1:4, dead = c(0, 1, 0, 1), iv_dead = c(1, 2, 3, 4), x = 5:8)
  subset <- built[c("id", "dead", "iv_dead")]
  data_dir <- hvtiRutilities::study_dir("datasets", root)
  utils::write.csv(built, file.path(data_dir, "built.csv"), row.names = FALSE)
  utils::write.csv(subset, file.path(data_dir, "builtr.csv"), row.names = FALSE)
  suppressWarnings(suppressMessages({
    hvtiRutilities::register_data(
      root, built = "built.csv"
    )
    hvtiRutilities::register_data(
      root, built = "builtr.csv",
      dataset = "builtr", role = "named"
    )
  }))

  old_wd <- setwd(root)
  on.exit(setwd(old_wd), add = TRUE)
  for (template in templates) {
    chunks <- data_route_chunks(template)
    code <- set_assignment(if (length(chunks$choices)) chunks$choices else chunks$data,
                           "DATASET", "builtr")

    env <- new.env(parent = globalenv())
    env$.root <- "."
    env$read_built <- hvtiRutilities::read_built
    eval(set_assignment(code, "ANALYSIS_SET", NULL), envir = env)
    if (length(chunks$choices)) eval(chunks$data, envir = env)
    expect_equal(env$d, subset, info = basename(template))

    # An analysis set derives from the study dataset, so pairing one with a
    # named dataset must stop rather than silently read the wrong parent.
    env <- new.env(parent = globalenv())
    env$.root <- "."
    expect_error({
      eval(code, envir = env)
      if (length(chunks$choices)) eval(chunks$data, envir = env)
    }, "written from the study dataset",
    info = basename(template))
  }
})

test_that("converter templates name DATASET before reading unresolved data", {
  template_root <- system.file("templates", package = "hvtiRtemplates")
  if (!nzchar(template_root)) template_root <- testthat::test_path("..", "..", "inst", "templates")
  templates <- file.path(normalizePath(template_root), c(
    "10_descriptive/dc-tables.qmd", "10_descriptive/dc-gfup.qmd",
    "10_descriptive/dp-postage.qmd", "10_descriptive/dp-eda.qmd", "40_graphs/dp-trends.qmd"
  ))
  for (template in templates) {
    chunks <- data_route_chunks(template)
    code <- chunks$data
    # The manifest check needs a real study; this test is about DATASET alone.
    code <- code[!vapply(code, function(expr) any(grepl("verify_manifest", deparse(expr))), logical(1))]
    choices <- if (length(chunks$choices)) chunks$choices else code
    has_set <- any(vapply(choices, function(expr) {
      is.call(expr) && identical(expr[[1L]], quote(`<-`)) && identical(expr[[2L]], quote(ANALYSIS_SET))
    }, logical(1)))
    if (has_set) choices <- set_assignment(choices, "ANALYSIS_SET", NULL)
    for (value in list(NA_character_, NULL, "", c("study", "builtr"), 1)) {
      env <- new.env(parent = globalenv())
      env$.root <- "."
      env$read_built <- function(...) stop("read_built() was reached")
      env$study_config <- function(...) list()
      expect_error({
        eval(set_assignment(choices, "DATASET", value), envir = env)
        if (length(chunks$choices)) eval(code, envir = env)
      },
      "DATASET.*_study[.]yml.*\"study\".*migration report",
      info = paste(basename(template), deparse(value))
      )
    }
  }
})
