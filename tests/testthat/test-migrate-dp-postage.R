postage_chunk <- function(job, label) {
  lines <- readLines(job, warn = FALSE)
  start <- match(paste0("#| label: ", label), lines)
  end <- start + match("```", lines[-seq_len(start)])
  parse(text = lines[seq.int(start + 1L, end - 1L)])
}

postage_evidence <- function(root, lines, extension = "qmd") {
  list(root = root, paths = c(source = paste0("descriptive/source.", extension)),
       source = data.frame(line = seq_along(lines), text = lines))
}

postage_config <- function(result) {
  env <- new.env()
  eval(parse(text = result$regions[["dp-postage-config"]]), env)
  env
}

test_that("postage migration selects registered data and explicit ordered EDA controls", {
  root <- migration_study_fixture("dp-postage")
  source <- file.path(root, "descriptive", "dp.postage.qmd")
  bytes <- readBin(source, "raw", n = file.info(source)$size)
  job <- migrate_job(source, "cohort", "eda", "dp", "postage", dir = root)
  expect_identical(dirname(job), normalizePath(file.path(root, "descriptive"), winslash = "/"))
  env <- list2env(list(.root = root, read_built = hvtiRutilities::read_built,
                       study_config = hvtiRutilities::study_config))
  withr::local_dir(root)
  eval(postage_chunk(job, "study-choices"), env)
  capture.output(eval(postage_chunk(job, "data"), env))
  expect_identical(env$DATASET, "study")
  expect_null(env$ANALYSIS_SET)
  expect_equal(nrow(env$d), 40L)
  expect_identical(env$X_VAR, "iv_dead")
  expect_identical(env$VARIABLES, c("dead", "iv_dead", "iv_fup", "year", "female", "race_grp",
                                    "repair", "age", "bmi", "treatment", "hx_chf", "lvmassi",
                                    "iv_opyrs", "panel1", "panel2", "panel3", "panel4", "panel5"))
  expect_identical(env$GRID_NCOL, 4L)
  expect_identical(env$GRID_NROW, 4L)
  expect_identical(readBin(source, "raw", n = file.info(source)$size), bytes)
  report <- paste(readLines(sub("[.]qmd$", "-migration.md", job)), collapse = "\n")
  expect_match(report, "color choice remains unresolved", fixed = TRUE)
  expect_match(report, "d$age <- d$age + 1", fixed = TRUE)
  expect_true(any(grepl("EDIT:", readLines(job), fixed = TRUE)))
  expect_equal(ncol(hvtiRutilities::read_built(hvtiRutilities::study_config(root))), 18L)
  other <- migration_study_fixture()
  expect_equal(ncol(hvtiRutilities::read_built(hvtiRutilities::study_config(other))), 13L)
})

test_that("postage pages preserve order and reject invalid dimensions", {
  env <- new.env()
  spec <- postage_chunk(template_path("dp", "postage"), "spec")
  positive <- which(vapply(spec, function(x) is.call(x) && identical(x[[2L]], as.name("positive_whole")), logical(1L)))
  eval(spec[positive], env)
  eval(postage_chunk(template_path("dp", "postage"), "helpers"), env)
  expect_identical(env$.postage_pages(letters[1:18], 4L, 4L),
                   list(letters[1:16], letters[17:18]))
  expect_identical(env$.postage_pages(list(), 4L, 4L), list())
  for (bad in list(0, -1, 1.5, NA_real_, Inf, "4", c(1, 2))) {
    expect_error(env$.postage_pages(letters, bad, 4L), "positive whole")
    expect_error(env$.postage_pages(letters, 4L, bad), "positive whole")
  }
})

test_that("postage handles SAS controls without executing source cleaning or unsupported choices", {
  root <- migration_study_fixture()
  lines <- c("* %let pref_time_var=wrong;", "SET complete_cases;",
             "%LET pref_time_var=iv_dead;", "%let variables=age bmi female;",
             "%let exclude=bmi;", "%let ncol=2;", "%let nrow=1;",
             "%let pref_color_var=repair;", "%let stratify_by=female;",
             "%let alpha=0.2;", "axis1 order=(0 to 10 by 2);", "age=age+1;")
  result <- hvtiRtemplates:::.migrate_dp_postage(postage_evidence(root, lines, "sas"), character())
  env <- postage_config(result)
  expect_identical(env$DATASET, "complete_cases")
  expect_identical(env$X_VAR, "iv_dead")
  expect_identical(env$VARIABLES, c("age", "bmi", "female"))
  expect_identical(env$EXCLUDE, "bmi")
  expect_identical(env$GRID_NCOL, 2L)
  expect_identical(env$GRID_NROW, 1L)
  expect_true(all(8:12 %in% result$unresolved$line))
  expect_false(any(grepl("age\\+1|axis1|wrong|repair", result$regions)))
})

test_that("postage accepts literal QMD controls only and keeps incomplete choices blocked", {
  root <- migration_study_fixture()
  lines <- c("```{r}", 'dta_filename <- "built.csv"', 'pref_time_var <- "iv_dead"',
             'variables <- c("age", "bmi")', 'exclude <- "bmi"', "ncol <- 2L", "```")
  result <- hvtiRtemplates:::.migrate_dp_postage(postage_evidence(root, lines), character())
  expect_identical(postage_config(result)$VARIABLES, c("age", "bmi"))
  expect_identical(postage_config(result)$EXCLUDE, "bmi")
  for (extra in c('pref_time_var <- "year"', 'if (flag) pref_time_var <- "year"',
                  'pref_time_var <- paste0("iv_", "dead")')) {
    changed <- append(lines, extra, after = 6L)
    expect_error(hvtiRtemplates:::.migrate_dp_postage(postage_evidence(root, changed), character()), "Multiple declarations")
  }
  lines[4L] <- 'variables <- system("touch should-never-exist")'
  result <- hvtiRtemplates:::.migrate_dp_postage(postage_evidence(root, lines), character())
  expect_identical(postage_config(result)$VARIABLES, character())
  expect_true(4L %in% result$unresolved$line)
  expect_false(any(grepl("system|touch", result$regions)))
  expect_match(result$regions[[1L]], "EDIT:", fixed = TRUE)
})

test_that("postage template validates selection and plotting settings before saving", {
  job <- template_path("dp", "postage")
  data <- postage_chunk(job, "data")
  # Run validation separately from the template's editable declarations.
  env <- list2env(list(d = data.frame(year = 1:10, age = 41:50, patient_id = 11:20, visit_date = 21:30),
                       X_VAR = "year", VARIABLES = "age", EXCLUDE = character(),
                       GRID_NCOL = 4L, GRID_NROW = 4L, UNIQUE_LIMIT = 6L, SHOW_PERCENT = FALSE))
  expect_error({
    selection <- data[seq.int(which(vapply(data, function(x) is.call(x) && identical(x[[1]], as.name("if")), logical(1)))[1],
                              length(data))]
    eval(selection, list2env(list(DATASET = "complete_cases", ANALYSIS_SET = "eda")))
  }, "written from the study dataset")
  spec <- postage_chunk(job, "spec")
  expect_no_error(eval(spec, env))
  for (field in c("X_VAR", "VARIABLES", "EXCLUDE", "GRID_NCOL", "GRID_NROW", "UNIQUE_LIMIT", "SHOW_PERCENT")) {
    original <- env[[field]]
    env[[field]] <- NA
    expect_error(eval(spec, env), info = field)
    env[[field]] <- original
  }
  env$VARIABLES <- "absent"
  expect_error(eval(spec, env), "Unknown EDA")
  env$VARIABLES <- c("patient_id", "visit_date")
  expect_warning(eval(spec, env), "identifier or date")
  env$VARIABLES <- c("age", "year")
  env$EXCLUDE <- "year"
  eval(spec, env)
  expect_identical(env$VARIABLES, "age")
  env$EXCLUDE <- "age"
  expect_error(eval(spec, env), "No EDA variables")
})

test_that("postage renders real eighteen-panel pages under the logical graphs route", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  out <- render_migrated_fixture("dp-postage")
  expected <- file.path(out$root, "graphs", "cohort-eda", sprintf("dp-postage-page-%02d.png", 1:2))
  expect_true(all(expected %in% out$outputs))
  expect_true(all(file.info(expected)$size > 1000))
  expect_true(file.exists(sub("[.]qmd$", ".html", out$job)))
})

test_that("postage routes actual pages through numbered study folders and embeds the saved files", {
  root <- migration_study_fixture("dp-postage")
  d <- hvtiRutilities::read_built(hvtiRutilities::study_config(root))
  for (name in names(d)) attr(d[[name]], "label") <- paste("Synthetic", name)
  folders <- c("datasets", "descriptive", "distributions", "analyses", "graphs", "documents", "estimates")
  numbered <- c("00_datasets", "10_descriptive", "20_distributions", "30_analyses", "40_graphs", "50_documents", "90_estimates")
  expect_true(all(file.rename(file.path(root, folders), file.path(root, numbered))))
  env <- list2env(list(
    .root = root, d = d, X_VAR = "iv_dead", VARIABLES = c("age", "bmi", "lvmassi"), EXCLUDE = character(),
    GRID_NCOL = 2L, GRID_NROW = 1L, UNIQUE_LIMIT = 6L, SHOW_PERCENT = FALSE,
    get_label = hvtiRutilities::get_label, label_map = hvtiRutilities::label_map,
    theme_hv_manuscript = hvtiPlotR::theme_hv_manuscript
  ))
  job <- template_path("dp", "postage")
  for (label in c("set", "spec", "helpers")) eval(postage_chunk(job, label), env)
  paths <- eval(postage_chunk(job, "pages"), env)
  expected <- file.path(root, "40_graphs", "cohort-eda", sprintf("dp-postage-page-%02d.png", 1:2))
  expect_identical(as.character(paths), expected)
  expect_equal(lengths(env$pages), c(2L, 1L))
  expect_true(all(file.info(expected)$size > 1000))
  expect_false(dir.exists(file.path(root, "graphs")))
})

test_that("postage does not require databuild for registered data but validates analysis-set mode", {
  root <- migration_study_fixture("dp-postage")
  job <- migrate_job(file.path(root, "descriptive", "dp.postage.qmd"), "cohort", "eda", "dp", "postage", dir = root)
  env <- list2env(list(.root = root, read_built = hvtiRutilities::read_built, study_config = hvtiRutilities::study_config))
  # The full setup and registered-data branch run with the actual dependencies.
  withr::local_dir(dirname(job))
  eval(postage_chunk(job, "setup"), env)
  eval(postage_chunk(job, "study-choices"), env)
  capture.output(eval(postage_chunk(job, "data"), env))
  expect_equal(nrow(env$d), 40L)
  data <- postage_chunk(job, "data")
  first_if <- which(vapply(data, function(x) is.call(x) && identical(x[[1L]], as.name("if")), logical(1L)))[1L]
  selection <- data[seq.int(first_if, length(data))]
  env$ANALYSIS_SET <- NULL
  env$DATASET <- ""
  expect_error(eval(selection, env), "DATASET must be set")
  env$DATASET <- "study"
  env$ANALYSIS_SET <- "eda"
  if (!requireNamespace("hvtiRdatabuild", quietly = TRUE) || utils::packageVersion("hvtiRdatabuild") < "0.2.1") {
    expect_error(eval(selection, env), "hvtiRdatabuild >= 0.2.1", fixed = TRUE)
  }
})

test_that("postage SAS quoted declarations cannot override active controls", {
  root <- migration_study_fixture()
  lines <- c("set built;", "%let pref_time_var=iv_dead;", "%let variables=age bmi;",
             'title "Example: %let variables=wrong; set absent;";')
  result <- hvtiRtemplates:::.migrate_dp_postage(postage_evidence(root, lines, "sas"), character())
  expect_identical(postage_config(result)$DATASET, "study")
  expect_identical(postage_config(result)$VARIABLES, c("age", "bmi"))
  expect_true(4L %in% result$unresolved$line)
})

test_that("postage treats SAS field names case-insensitively", {
  root <- migration_study_fixture()
  lines <- c("SET BUILT;", "%LET PREF_TIME_VAR=IV_DEAD;", "%LET VARIABLES=AGE BMI;", "%LET EXCLUDE=BMI;")
  result <- hvtiRtemplates:::.migrate_dp_postage(postage_evidence(root, lines, "sas"), character())
  env <- postage_config(result)
  expect_identical(env$X_VAR, "iv_dead")
  expect_identical(env$VARIABLES, c("age", "bmi"))
  expect_identical(env$EXCLUDE, "bmi")
})

test_that("postage leaves disabled QMD chunks inactive and conditional chunks unresolved", {
  root <- migration_study_fixture()
  lines <- c("```{r}", 'dta_filename <- "built.csv"', 'pref_time_var <- "iv_dead"',
             'variables <- "age"', "```", "```{r}", "#| eval: false", 'variables <- "bmi"', "```")
  result <- hvtiRtemplates:::.migrate_dp_postage(postage_evidence(root, lines), character())
  expect_identical(postage_config(result)$VARIABLES, "age")
  expect_true(8L %in% result$ignored$line)
  lines <- c("```{r}", "#| eval: !expr run_eda", 'variables <- "age"', "```")
  result <- hvtiRtemplates:::.migrate_dp_postage(postage_evidence(root, lines), character())
  expect_identical(postage_config(result)$VARIABLES, character())
  expect_true(3L %in% result$unresolved$line)
})

test_that("postage retains cleaning with omitted subscript arguments as unresolved evidence", {
  root <- migration_study_fixture()
  lines <- c("```{r}", 'dta_filename <- "built.csv"', 'pref_time_var <- "iv_dead"',
             'variables <- "age"', 'd[, "age"] <- d[, "age"] + 1', "```")
  result <- hvtiRtemplates:::.migrate_dp_postage(postage_evidence(root, lines), character())
  expect_identical(postage_config(result)$VARIABLES, "age")
  expect_true(5L %in% result$unresolved$line)
  expect_false(any(grepl("d[", result$regions, fixed = TRUE)))
})

test_that("postage preserves boolean-prefixed eval expressions as unresolved", {
  root <- migration_study_fixture()
  for (value in c("FALSE || run_eda", "TRUE && run_eda")) {
    for (header in list(c(paste0("```{r setup, eval=", value, ", echo=FALSE}")),
                        c("```{r}", paste0("#| eval: ", value)))) {
      lines <- c(header, 'dta_filename <- "built.csv"', 'pref_time_var <- "iv_dead"',
                 'variables <- "age"', "d$age <- d$age + 1", "```")
      result <- hvtiRtemplates:::.migrate_dp_postage(postage_evidence(root, lines), character())
      env <- postage_config(result)
      expect_identical(env$DATASET, NA_character_, info = paste(header, collapse = " "))
      expect_identical(env$X_VAR, NA_character_)
      expect_identical(env$VARIABLES, character())
      source_rows <- length(header) + 1:4
      expect_true(all(source_rows %in% result$unresolved$line))
      expect_false(any(source_rows %in% result$ignored$line))
      expect_false(any(source_rows %in% result$translated$line))
      expect_match(result$regions[[1L]], "EDIT:", fixed = TRUE)
    }
  }
})

test_that("postage recognizes complete inline boolean eval options", {
  root <- migration_study_fixture()
  for (value in c("TRUE", "FALSE")) {
    lines <- c(paste0("```{r setup, eval=", value, ", echo=FALSE}"),
               'dta_filename <- "built.csv"', 'pref_time_var <- "iv_dead"', 'variables <- "age"', "```")
    result <- hvtiRtemplates:::.migrate_dp_postage(postage_evidence(root, lines), character())
    if (value == "TRUE") {
      expect_identical(postage_config(result)$VARIABLES, "age")
      expect_true(all(2:4 %in% result$translated$line))
    } else {
      expect_identical(postage_config(result)$VARIABLES, character())
      expect_true(all(2:4 %in% result$ignored$line))
    }
  }
})
