extract_chunk <- function(path, label) {
  lines <- readLines(path, warn = FALSE)
  # A chunk holding an EDIT: marker is labeled edit-<label>, and one that shows a
  # table is labeled tbl-<label>; any of them names it.
  chunk_label <- grep(paste0("^#\\| label: (edit-)?(tbl-)?", label, "$"), lines)
  chunk_end <- chunk_label + which(lines[-seq_len(chunk_label)] == "```")[[1L]]
  parse(text = lines[(chunk_label + 1L):(chunk_end - 1L)])
}

data_route_chunks <- function(path) {
  lines <- readLines(path, warn = FALSE)
  choices <- if (any(grepl("#| label: edit-study-choices", lines, fixed = TRUE))) {
    extract_chunk(path, "edit-study-choices")
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
    "dc-general.qmd", "dc-tables.qmd", "dc-gfup.qmd", "dc-stddiff.qmd", "dp-postage.qmd", "dp-eda.qmd"
  ))
  root <- file.path(tempdir(), "whole-cohort-study")
  unlink(root, recursive = TRUE)
  suppressMessages(hvtiRutilities::study_setup(
    root, study = "Template route test", study_tracker_id = 1L
  ))
  built <- data.frame(ccfid = 1:4, dead = c(0, 1, 0, 1), iv_dead = c(1, 2, 3, 4))
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
    # hvtiRutilities is imported, not attached: run alone, this file finds
    # study_config() only if it is supplied here.
    env$study_config <- hvtiRutilities::study_config
    chunks <- data_route_chunks(template)
    if (length(chunks$choices)) eval(use_whole_cohort(chunks$choices), envir = env)
    result <- withVisible(eval(
      if (length(chunks$choices)) chunks$data else use_whole_cohort(chunks$data), envir = env
    ))

    expect_equal(env$d, built, info = basename(template))
    # A chunk that shows the data record ends in that table, so its value is visible;
    # nothing else may leak out of it.
    expect_identical(result$visible, inherits(result$value, "knitr_kable"), info = basename(template))
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
    "dc-general.qmd", "dc-tables.qmd", "dc-gfup.qmd", "dc-stddiff.qmd", "dp-postage.qmd", "dp-eda.qmd"
  ))
  root <- file.path(tempdir(), "named-dataset-study")
  unlink(root, recursive = TRUE)
  suppressMessages(hvtiRutilities::study_setup(
    root, study = "Template named dataset test", study_tracker_id = 1L
  ))
  built <- data.frame(ccfid = 1:4, dead = c(0, 1, 0, 1), iv_dead = c(1, 2, 3, 4), x = 5:8)
  subset <- built[c("ccfid", "dead", "iv_dead")]
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
    env$study_config <- hvtiRutilities::study_config
    eval(set_assignment(code, "ANALYSIS_SET", NULL), envir = env)
    if (length(chunks$choices)) eval(chunks$data, envir = env)
    expect_equal(env$d, subset, info = basename(template))

    # An analysis set derives from the study dataset, so pairing one with a
    # named dataset must stop rather than silently read the wrong parent.
    env <- new.env(parent = globalenv())
    env$.root <- "."
    env$study_config <- hvtiRutilities::study_config
    expect_error({
      eval(set_assignment(code, "ANALYSIS_SET", "eda"), envir = env)
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
    # A job that reads through read_job_data() names DATASET the same way; only
    # the unconverted dp-postage still points a migrated job at its report.
    message <- if (basename(template) == "dp-postage.qmd") {
      "DATASET.*_study[.]yml.*\"built\".*migration report"
    } else {
      "DATASET.*_study[.]yml.*\"built\""
    }
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
      message,
      info = paste(basename(template), deparse(value))
      )
    }
  }
})

test_that("converted templates read a whole dataset without hvtiRdatabuild installed", {
  # read_job_data() asks for hvtiRdatabuild only when ANALYSIS_SET names a set,
  # so a newly registered study renders without it. A setup-chunk version check
  # would stop every job before the data were read.
  template_root <- system.file("templates", package = "hvtiRtemplates")
  if (!nzchar(template_root)) template_root <- testthat::test_path("..", "..", "inst", "templates")
  templates <- file.path(normalizePath(template_root), c(
    "10_descriptive/dc-general.qmd", "10_descriptive/dc-gfup.qmd", "10_descriptive/dc-tables.qmd",
    "10_descriptive/dp-eda.qmd", "40_graphs/dp-gfup.qmd", "40_graphs/dp-trends.qmd"
  ))
  root <- file.path(withr::local_tempdir(), "no-databuild-study")
  suppressMessages(hvtiRutilities::study_setup(root, study = "No databuild", study_tracker_id = 1L))
  built <- data.frame(ccfid = 1:4, dead = c(0, 1, 0, 1), iv_dead = c(1, 2, 3, 4))
  utils::write.csv(built, file.path(hvtiRutilities::study_dir("datasets", root), "built.csv"), row.names = FALSE)
  suppressWarnings(suppressMessages(hvtiRutilities::register_data(root, built = "built.csv")))

  real_version <- utils::packageVersion
  local_mocked_bindings(packageVersion = function(pkg, ...) {
    if (identical(pkg, "hvtiRdatabuild")) stop("there is no package called 'hvtiRdatabuild'", call. = FALSE)
    real_version(pkg, ...)
  }, .package = "utils")
  withr::local_dir(root)
  for (template in templates) {
    env <- new.env(parent = globalenv())
    chunks <- data_route_chunks(template)
    err <- tryCatch({
      suppressPackageStartupMessages(eval(extract_chunk(template, "setup"), envir = env))
      eval(use_whole_cohort(chunks$choices), envir = env)
      utils::capture.output(eval(chunks$data, envir = env))
      NULL
    }, error = conditionMessage)
    expect_null(err, info = basename(template))
    expect_equal(env$d, built, info = basename(template))
  }
})

test_that("dp-postage names the registered version and a waiting rebuild without a bare message", {
  skip_if_not_installed("arrow")
  template_root <- system.file("templates", package = "hvtiRtemplates")
  if (!nzchar(template_root)) template_root <- testthat::test_path("..", "..", "inst", "templates")
  template <- file.path(normalizePath(template_root), "10_descriptive", "dp-postage.qmd")
  root <- file.path(withr::local_tempdir(), "postage-rebuilt-study")
  suppressMessages(hvtiRutilities::study_setup(root, study = "Postage rebuilt", study_tracker_id = 1L))
  path <- file.path(hvtiRutilities::study_dir("datasets", root), "built.csv")
  built <- data.frame(ccfid = 1:4, dead = c(0, 1, 0, 1), iv_dead = c(1, 2, 3, 4))
  utils::write.csv(built, path, row.names = FALSE)
  suppressWarnings(suppressMessages(hvtiRutilities::register_data(root, built = "built.csv")))
  utils::write.csv(rbind(built, data.frame(ccfid = 5L, dead = 0, iv_dead = 5)), path, row.names = FALSE)

  withr::local_dir(root)
  env <- new.env(parent = globalenv())
  env$.root <- "."
  env$study_config <- hvtiRutilities::study_config
  env$study_dir <- hvtiRutilities::study_dir
  chunks <- data_route_chunks(template)
  eval(use_whole_cohort(chunks$choices), envir = env)
  expect_no_message(shown <- utils::capture.output(eval(chunks$data, envir = env)))

  # The registered rows, not the rebuilt file's five.
  expect_equal(env$d, built)
  expect_match(shown, "^Data read: dataset `built` [(]built_[0-9]{8}[.]parquet[)], 4 rows", all = FALSE)
  note <- grep("^Note: ", shown, value = TRUE)
  expect_length(note, 1L)
  expect_match(note, "update_manifest()", fixed = TRUE)
})

# The templates that model one row per patient, so refuse a JOIN without REDUCE.
# Other descriptive templates and nb-boostmtree (repeated measures) take the long form.
patient_level_templates <- c(
  "ac.qmd", "hz.qmd", "dc-stddiff.qmd", "dc-gfup.qmd", "dp-gfup.qmd", "hs-concordance.qmd",
  "rfc-fit.qmd", "rfr-fit.qmd", "rfs-fit.qmd",
  "lm-balancing_count.qmd", "lm-binary.qmd", "lm-checkpred.qmd", "lm-nominal.qmd", "lm-ordinal.qmd",
  "lm-propensity_binary.qmd", "lm-propensity_nominal.qmd", "lm-propensity_ordinal.qmd"
)

test_that("every template that reads its own data offers the join and records the joined data", {
  template_root <- system.file("templates", package = "hvtiRtemplates")
  if (!nzchar(template_root)) template_root <- testthat::test_path("..", "..", "inst", "templates")
  files <- list.files(normalizePath(template_root), pattern = "[.]qmd$", recursive = TRUE, full.names = TRUE)
  readers <- 0L
  for (f in files) {
    src <- readLines(f, warn = FALSE)
    text <- paste(src, collapse = "\n")
    # A job that reads with its own DATASET; downstream and bootstrap reports
    # rebuild the selection their upstream job recorded instead.
    if (!grepl("read_job_data(.cfg, dataset = DATASET", text, fixed = TRUE)) next
    readers <- readers + 1L
    for (arg in c("join = JOIN", "join_vars = JOIN_VARS", "reduce = REDUCE", "join_key = JOIN_KEY")) {
      expect_true(grepl(arg, text, fixed = TRUE), info = paste(basename(f), arg))
    }
    choices <- data_route_chunks(f)$choices
    for (choice in c("JOIN", "JOIN_VARS", "REDUCE", "JOIN_KEY")) {
      set <- vapply(choices, function(expr) {
        is.call(expr) && identical(expr[[1L]], quote(`<-`)) && identical(expr[[2L]], as.name(choice)) &&
          is.null(expr[[3L]])
      }, logical(1))
      expect_identical(sum(set), 1L, info = paste(basename(f), choice))
    }
    # An optional choice carries no EDIT: marker, or a finished job would render as a draft.
    at <- grep("^JOIN <- NULL$", src)
    expect_false(any(grepl("EDIT:", src[(at - 11L):(at + 3L)], fixed = TRUE)), info = basename(f))
    expect_true(grepl("list(job_data$provenance_join)", text, fixed = TRUE), info = basename(f))
    # A job that models one row per patient says so to read_job_data(), and its JOIN comment says what follows.
    one_row <- basename(f) %in% patient_level_templates
    expect_identical(grepl("one_row_per_patient = TRUE", text, fixed = TRUE), one_row, info = basename(f))
    expect_identical(any(grepl("so a JOIN without REDUCE stops here", src[(at - 11L):at], fixed = TRUE)), one_row,
                     info = basename(f))
  }
  # Every first job of a set reads its own data; a drop here means one stopped offering the join.
  expect_identical(readers, 22L)
  # The refusal names the rest, read from the same templates.
  expect_identical(hvtiRtemplates:::.long_join_templates(normalizePath(template_root)),
                   c("dc-general", "dc-tables", "dp-eda", "dp-trends", "nb-boostmtree"))
})

test_that("descriptive templates join an ancillary dataset, long and one row per patient", {
  skip_if_not_installed("arrow")
  template_root <- system.file("templates", package = "hvtiRtemplates")
  if (!nzchar(template_root)) template_root <- testthat::test_path("..", "..", "inst", "templates")
  templates <- file.path(normalizePath(template_root), "10_descriptive",
                         c("dc-general.qmd", "dc-tables.qmd", "dp-eda.qmd"))
  root <- file.path(withr::local_tempdir(), "join-study")
  suppressMessages(hvtiRutilities::study_setup(root, study = "Join route test", study_tracker_id = 1L))
  data_dir <- hvtiRutilities::study_dir("datasets", root)
  built <- data.frame(ccfid = 1:3, dead = c(0, 1, 0), iv_dead = c(1, 2, 3))
  echo <- data.frame(ccfid = c(1L, 1L, 2L, 4L), echo_day = c(5, 9, 5, 5), ef = c(50, 55, 45, 40))
  utils::write.csv(built, file.path(data_dir, "built.csv"), row.names = FALSE)
  utils::write.csv(echo, file.path(data_dir, "echo.csv"), row.names = FALSE)
  suppressWarnings(suppressMessages({
    hvtiRutilities::register_data(root, built = "built.csv")
    hvtiRutilities::register_data(root, built = "echo.csv", dataset = "echo", role = "named",
                                  kind = "ancillary", key = c("ccfid", "echo_day"))
  }))
  withr::local_dir(root)
  for (template in templates) {
    chunks <- data_route_chunks(template)
    for (reduce in list(NULL, quote(list(rule = "last", by = "echo_day")))) {
      code <- set_assignment(use_whole_cohort(chunks$choices), "JOIN", "echo")
      code <- set_assignment(code, "REDUCE", reduce)
      env <- new.env(parent = globalenv())
      env$.root <- "."
      env$study_config <- hvtiRutilities::study_config
      eval(code, envir = env)
      utils::capture.output(eval(chunks$data, envir = env))
      info <- paste(basename(template), if (is.null(reduce)) "long" else "reduced")
      expect_identical(nrow(env$d), 3L, info = info)
      if (is.null(reduce)) {
        expect_identical(sort(unique(env$d$ccfid)), 1:2, info = info)
      } else {
        expect_equal(env$d$ef, c(55, 45, NA), info = info)
      }
      steps <- env$job_data$record$step
      expect_true(all(c("Joined", "Joined records outside the cohort", "Cohort patients with no joined record") %in%
                        steps), info = info)
      expect_identical("Reduced to one row per patient" %in% steps, !is.null(reduce), info = info)
      datasets <- vapply(env$.provenance_data, `[[`, "", "dataset")
      expect_identical(datasets, c("study", "echo"), info = info)
    }
  }
})

# The data chunk up to and including its read_job_data() call: the refusal is
# about the read, and what follows it needs study columns this test has no use for.
data_read_prefix <- function(code) {
  at <- which(vapply(code, function(expr) any(grepl("read_job_data(", deparse(expr), fixed = TRUE)), logical(1)))
  stopifnot(length(at) == 1L)
  code[seq_len(at)]
}

test_that("templates that model one row per patient refuse a long join; long-data templates take it", {
  skip_if_not_installed("arrow")
  template_root <- system.file("templates", package = "hvtiRtemplates")
  if (!nzchar(template_root)) template_root <- testthat::test_path("..", "..", "inst", "templates")
  files <- list.files(normalizePath(template_root), pattern = "[.]qmd$", recursive = TRUE, full.names = TRUE)
  refuse <- files[basename(files) %in% patient_level_templates]
  expect_length(refuse, length(patient_level_templates))
  # Repeated measures (nb-boostmtree's KEY includes TIME) and a descriptive figure keep the long form.
  accept <- files[basename(files) %in% c("nb-boostmtree.qmd", "dp-trends.qmd")]
  expect_length(accept, 2L)
  root <- file.path(withr::local_tempdir(), "one-row-study")
  suppressMessages(hvtiRutilities::study_setup(root, study = "One row route test", study_tracker_id = 1L))
  data_dir <- hvtiRutilities::study_dir("datasets", root)
  built <- data.frame(ccfid = 1:3, dead = c(0, 1, 0), iv_dead = c(1, 2, 3), iv_echo = c(0, 0, 0))
  echo <- data.frame(ccfid = c(1L, 1L, 2L, 4L), echo_day = c(5, 9, 5, 5), ef = c(50, 55, 45, 40))
  utils::write.csv(built, file.path(data_dir, "built.csv"), row.names = FALSE)
  utils::write.csv(echo, file.path(data_dir, "echo.csv"), row.names = FALSE)
  suppressWarnings(suppressMessages({
    hvtiRutilities::register_data(root, built = "built.csv")
    hvtiRutilities::register_data(root, built = "echo.csv", dataset = "echo", role = "named",
                                  kind = "ancillary", key = c("ccfid", "echo_day"))
  }))
  withr::local_dir(root)
  run <- function(template, reduce) {
    chunks <- data_route_chunks(template)
    code <- set_assignment(use_whole_cohort(chunks$choices), "JOIN", "echo")
    code <- set_assignment(code, "REDUCE", reduce)
    env <- new.env(parent = globalenv())
    env$.root <- "."
    env$study_config <- hvtiRutilities::study_config
    # Only the settings the read takes: other choices call the model's packages.
    read_settings <- c("DATASET", "ANALYSIS_SET", "WHERE", "ID", "TIME", "KEY", "JOIN", "JOIN_VARS", "REDUCE", "JOIN_KEY")
    for (expr in code) {
      if (is.call(expr) && identical(expr[[1L]], quote(`<-`)) && is.name(expr[[2L]]) &&
            as.character(expr[[2L]]) %in% read_settings) {
        eval(expr, envir = env)
      }
    }
    eval(data_read_prefix(chunks$data), envir = env)
    env$job_data
  }
  for (template in refuse) {
    expect_error(run(template, NULL), "this job models one row per patient", info = basename(template))
    reduced <- run(template, quote(list(rule = "last", by = "echo_day")))
    expect_equal(reduced$data$ef, c(55, 45, NA), info = basename(template))
  }
  for (template in accept) {
    long <- run(template, NULL)
    expect_identical(nrow(long$data), 3L, info = basename(template))
    expect_identical(sort(unique(long$data$ccfid)), 1:2, info = basename(template))
  }
})

test_that("nb-boostmtree takes a long join whose visit time is only in the joined dataset", {
  skip_if_not_installed("arrow")
  template_root <- system.file("templates", package = "hvtiRtemplates")
  if (!nzchar(template_root)) template_root <- testthat::test_path("..", "..", "inst", "templates")
  template <- file.path(normalizePath(template_root), "30_analyses", "nb-boostmtree.qmd")
  root <- file.path(withr::local_tempdir(), "visit-study")
  suppressMessages(hvtiRutilities::study_setup(root, study = "Visit route test", study_tracker_id = 1L))
  data_dir <- hvtiRutilities::study_dir("datasets", root)
  # The cohort has no visit time: iv_echo is a column of the echoes alone.
  built <- data.frame(ccfid = 1:3, age = c(50, 60, 70))
  echo <- data.frame(ccfid = c(1L, 1L, 2L, 4L), iv_echo = c(0.5, 1, 0.5, 0.5), ef = c(50, 55, 45, 40))
  utils::write.csv(built, file.path(data_dir, "built.csv"), row.names = FALSE)
  utils::write.csv(echo, file.path(data_dir, "echo.csv"), row.names = FALSE)
  suppressWarnings(suppressMessages({
    hvtiRutilities::register_data(root, built = "built.csv")
    hvtiRutilities::register_data(root, built = "echo.csv", dataset = "echo", role = "named",
                                  kind = "ancillary", key = c("ccfid", "iv_echo"))
  }))
  withr::local_dir(root)
  chunks <- data_route_chunks(template)
  code <- set_assignment(use_whole_cohort(chunks$choices), "JOIN", "echo")
  env <- new.env(parent = globalenv())
  env$.root <- "."
  env$study_config <- hvtiRutilities::study_config
  for (expr in code) {
    if (is.call(expr) && identical(expr[[1L]], quote(`<-`)) && is.name(expr[[2L]]) &&
          as.character(expr[[2L]]) %in% c("DATASET", "ANALYSIS_SET", "WHERE", "ID", "TIME", "KEY", "JOIN",
                                          "JOIN_VARS", "REDUCE", "JOIN_KEY")) {
      eval(expr, envir = env)
    }
  }
  eval(data_read_prefix(chunks$data), envir = env)
  expect_identical(nrow(env$job_data$data), 3L)
  expect_identical(attr(env$job_data$record, "selection")$key, c("ccfid", "iv_echo"))
})
