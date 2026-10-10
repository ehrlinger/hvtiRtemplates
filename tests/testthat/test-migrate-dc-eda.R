eda_chunk <- function(job, label) {
  lines <- readLines(job, warn = FALSE)
  start <- match(paste0("#| label: ", label), lines)
  end <- start + match("```", lines[-seq_len(start)])
  parse(text = lines[seq.int(start + 1L, end - 1L)])
}

eda_evidence <- function(root, lines, extension = "qmd") {
  list(root = root, paths = c(source = paste0("descriptive/source.", extension)),
       source = data.frame(line = seq_along(lines), text = lines))
}

eda_config <- function(result) {
  env <- new.env()
  eval(parse(text = unname(result$regions[c("dc-eda-data", "dc-eda-variables")])), env)
  env
}

test_that("EDA migration selects registered data and explicit ordered EDA controls", {
  root <- migration_study_fixture("dp-postage")
  source <- file.path(root, "descriptive", "dp.postage.qmd")
  bytes <- readBin(source, "raw", n = file.info(source)$size)
  job <- migrate_job(source, "cohort", "eda", "dc", "eda", dir = root)
  expect_identical(dirname(job), normalizePath(file.path(root, "descriptive"), winslash = "/"))
  env <- list2env(list(.root = root, read_built = hvtiRutilities::read_built,
                       study_config = hvtiRutilities::study_config))
  withr::local_dir(root)
  eval(eda_chunk(job, "edit-study-choices"), env)
  capture.output(eval(eda_chunk(job, "tbl-data"), env))
  expect_identical(env$DATASET, "built")
  expect_null(env$ANALYSIS_SET)
  expect_equal(nrow(env$d), 40L)
  expect_identical(env$X_VAR, "iv_dead")
  expect_identical(env$VARIABLES, c("dead", "iv_dead", "iv_fup", "year", "female", "race_grp",
                                    "repair", "age", "bmi", "treatment", "hx_chf", "lvmassi",
                                    "iv_opyrs", "panel1", "panel2", "panel3", "panel4", "panel5"))
  expect_identical(env$GRID_NCOL, 4L)
  expect_identical(env$GRID_NROW, 4L)
  # A legacy EDA report drew no follow-up panels, so the dc-eda job draws its
  # three sections, and no more.
  expect_identical(basename(job), "dc.eda.cohort.eda.qmd")
  expect_identical(env$SECTIONS, c("continuous", "percent", "count"))
  expect_identical(readBin(source, "raw", n = file.info(source)$size), bytes)
  report <- paste(readLines(sub("[.]qmd$", "-migration.md", job)), collapse = "\n")
  expect_match(report, "color choice remains unresolved", fixed = TRUE)
  expect_match(report, "d$age <- d$age + 1", fixed = TRUE)
  expect_true(any(grepl("EDIT:", readLines(job), fixed = TRUE)))
  expect_equal(ncol(hvtiRutilities::read_built(hvtiRutilities::study_config(root))), 19L)
  other <- migration_study_fixture()
  expect_equal(ncol(hvtiRutilities::read_built(hvtiRutilities::study_config(other))), 14L)
})

test_that("EDA migration handles SAS controls without executing source cleaning or unsupported choices", {
  root <- migration_study_fixture()
  lines <- c("* %let pref_time_var=wrong;", "SET complete_cases;",
             "%LET pref_time_var=iv_dead;", "%let variables=age bmi female;",
             "%let exclude=bmi;", "%let ncol=2;", "%let nrow=1;",
             "%let pref_color_var=repair;", "%let stratify_by=female;",
             "%let alpha=0.2;", "axis1 order=(0 to 10 by 2);", "age=age+1;")
  result <- hvtiRtemplates:::.migrate_dc_eda(eda_evidence(root, lines, "sas"), character())
  env <- eda_config(result)
  expect_identical(env$DATASET, "complete_cases")
  expect_identical(env$X_VAR, "iv_dead")
  expect_identical(env$VARIABLES, c("age", "bmi", "female"))
  expect_identical(env$EXCLUDE, "bmi")
  expect_identical(env$GRID_NCOL, 2L)
  expect_identical(env$GRID_NROW, 1L)
  expect_true(all(c(8:9, 11:12) %in% result$unresolved$line))
  # A literal alpha now carries over; the template has an ALPHA edit point.
  expect_identical(env$ALPHA, 0.2)
  expect_true(10L %in% result$translated$line)
  expect_false(any(grepl("age\\+1|axis1|wrong|repair", result$regions)))
})

test_that("EDA migration accepts literal QMD controls only and keeps incomplete choices blocked", {
  root <- migration_study_fixture()
  lines <- c("```{r}", 'dta_filename <- "built.csv"', 'pref_time_var <- "iv_dead"',
             'variables <- c("age", "bmi")', 'exclude <- "bmi"', "ncol <- 2L", "```")
  result <- hvtiRtemplates:::.migrate_dc_eda(eda_evidence(root, lines), character())
  expect_identical(eda_config(result)$VARIABLES, c("age", "bmi"))
  expect_identical(eda_config(result)$EXCLUDE, "bmi")
  for (extra in c('pref_time_var <- "year"', 'if (flag) pref_time_var <- "year"',
                  'pref_time_var <- paste0("iv_", "dead")')) {
    changed <- append(lines, extra, after = 6L)
    expect_error(hvtiRtemplates:::.migrate_dc_eda(eda_evidence(root, changed), character()), "Multiple declarations")
  }
  lines[4L] <- 'variables <- system("touch should-never-exist")'
  result <- hvtiRtemplates:::.migrate_dc_eda(eda_evidence(root, lines), character())
  expect_null(eda_config(result)$VARIABLES)
  expect_true(4L %in% result$unresolved$line)
  expect_false(any(grepl("system|touch", result$regions)))
  expect_match(paste(result$regions, collapse = "\n"), "EDIT:", fixed = TRUE)
})

test_that("a migrated legacy EDA report renders real eighteen-panel pages under the logical graphs route", {
  skip_on_cran()
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  out <- render_migrated_fixture("dp-postage")
  expect_identical(basename(out$job), "dc.eda.cohort.eda.qmd")
  expected <- file.path(out$root, "graphs", "cohort-eda",
                        sprintf("dc-eda-%s-page-01.png", c("continuous", "percent", "count")))
  expect_true(all(expected %in% out$outputs))
  expect_true(all(file.info(expected)$size > 1000))
  html <- sub("[.]qmd$", ".html", out$job)
  expect_true(file.exists(html))
  # The PNGs existing is not the report showing them: an absolute image path
  # rendered with every file saved and nothing embedded.
  embedded <- regmatches(paste(readLines(html, warn = FALSE), collapse = "\n"),
                         gregexpr("src=\"data:image/png", paste(readLines(html, warn = FALSE), collapse = "\n")))[[1L]]
  expect_gte(length(embedded), length(expected))
})

test_that("EDA migration does not require databuild for registered data but validates analysis-set mode", {
  root <- migration_study_fixture("dp-postage")
  job <- migrate_job(file.path(root, "descriptive", "dp.postage.qmd"), "cohort", "eda", "dc", "eda", dir = root)
  env <- list2env(list(.root = root, read_built = hvtiRutilities::read_built, study_config = hvtiRutilities::study_config))
  # The full setup and registered-data branch run with the actual dependencies.
  withr::local_dir(dirname(job))
  eval(eda_chunk(job, "setup"), env)
  eval(eda_chunk(job, "edit-study-choices"), env)
  capture.output(eval(eda_chunk(job, "tbl-data"), env))
  expect_equal(nrow(env$d), 40L)
  # The migrated job reads through read_job_data(), which checks every setting
  # before reading and asks for hvtiRdatabuild only for an analysis set.
  data <- eda_chunk(job, "tbl-data")
  env$ANALYSIS_SET <- NULL
  env$DATASET <- ""
  expect_error(eval(data, env), "DATASET must name one dataset")
  env$DATASET <- "study"
  env$ANALYSIS_SET <- "eda"
  if (!requireNamespace("hvtiRdatabuild", quietly = TRUE) || utils::packageVersion("hvtiRdatabuild") < "0.2.1") {
    expect_error(eval(data, env), "hvtiRdatabuild 0.2.1", fixed = TRUE)
  }
})

test_that("EDA migration SAS quoted declarations cannot override active controls", {
  root <- migration_study_fixture()
  lines <- c("set built;", "%let pref_time_var=iv_dead;", "%let variables=age bmi;",
             'title "Example: %let variables=wrong; set absent;";')
  result <- hvtiRtemplates:::.migrate_dc_eda(eda_evidence(root, lines, "sas"), character())
  expect_identical(eda_config(result)$DATASET, "built")
  expect_identical(eda_config(result)$VARIABLES, c("age", "bmi"))
  expect_true(4L %in% result$unresolved$line)
})

test_that("EDA migration treats SAS field names case-insensitively", {
  root <- migration_study_fixture()
  lines <- c("SET BUILT;", "%LET PREF_TIME_VAR=IV_DEAD;", "%LET VARIABLES=AGE BMI;", "%LET EXCLUDE=BMI;")
  result <- hvtiRtemplates:::.migrate_dc_eda(eda_evidence(root, lines, "sas"), character())
  env <- eda_config(result)
  expect_identical(env$X_VAR, "iv_dead")
  expect_identical(env$VARIABLES, c("age", "bmi"))
  expect_identical(env$EXCLUDE, "bmi")
})

test_that("EDA migration leaves disabled QMD chunks inactive and conditional chunks unresolved", {
  root <- migration_study_fixture()
  lines <- c("```{r}", 'dta_filename <- "built.csv"', 'pref_time_var <- "iv_dead"',
             'variables <- "age"', "```", "```{r}", "#| eval: false", 'variables <- "bmi"', "```")
  result <- hvtiRtemplates:::.migrate_dc_eda(eda_evidence(root, lines), character())
  expect_identical(eda_config(result)$VARIABLES, "age")
  expect_true(8L %in% result$ignored$line)
  lines <- c("```{r}", "#| eval: !expr run_eda", 'variables <- "age"', "```")
  result <- hvtiRtemplates:::.migrate_dc_eda(eda_evidence(root, lines), character())
  expect_null(eda_config(result)$VARIABLES)
  expect_true(3L %in% result$unresolved$line)
})

test_that("EDA migration retains cleaning with omitted subscript arguments as unresolved evidence", {
  root <- migration_study_fixture()
  lines <- c("```{r}", 'dta_filename <- "built.csv"', 'pref_time_var <- "iv_dead"',
             'variables <- "age"', 'd[, "age"] <- d[, "age"] + 1', "```")
  result <- hvtiRtemplates:::.migrate_dc_eda(eda_evidence(root, lines), character())
  expect_identical(eda_config(result)$VARIABLES, "age")
  expect_true(5L %in% result$unresolved$line)
  expect_false(any(grepl("d[", result$regions, fixed = TRUE)))
})

test_that("EDA migration preserves boolean-prefixed eval expressions as unresolved", {
  root <- migration_study_fixture()
  for (value in c("FALSE || run_eda", "TRUE && run_eda")) {
    for (header in list(c(paste0("```{r setup, eval=", value, ", echo=FALSE}")),
                        c("```{r}", paste0("#| eval: ", value)))) {
      lines <- c(header, 'dta_filename <- "built.csv"', 'pref_time_var <- "iv_dead"',
                 'variables <- "age"', "d$age <- d$age + 1", "```")
      result <- hvtiRtemplates:::.migrate_dc_eda(eda_evidence(root, lines), character())
      env <- eda_config(result)
      expect_identical(env$DATASET, NA_character_, info = paste(header, collapse = " "))
      expect_identical(env$X_VAR, NA_character_)
      expect_null(env$VARIABLES)
      source_rows <- length(header) + 1:4
      expect_true(all(source_rows %in% result$unresolved$line))
      expect_false(any(source_rows %in% result$ignored$line))
      expect_false(any(source_rows %in% result$translated$line))
      expect_match(paste(result$regions, collapse = "\n"), "EDIT:", fixed = TRUE)
    }
  }
})

test_that("EDA migration recognizes complete inline boolean eval options", {
  root <- migration_study_fixture()
  for (value in c("TRUE", "FALSE")) {
    lines <- c(paste0("```{r setup, eval=", value, ", echo=FALSE}"),
               'dta_filename <- "built.csv"', 'pref_time_var <- "iv_dead"', 'variables <- "age"', "```")
    result <- hvtiRtemplates:::.migrate_dc_eda(eda_evidence(root, lines), character())
    if (value == "TRUE") {
      expect_identical(eda_config(result)$VARIABLES, "age")
      expect_true(all(2:4 %in% result$translated$line))
    } else {
      expect_null(eda_config(result)$VARIABLES)
      expect_true(all(2:4 %in% result$ignored$line))
    }
  }
})

test_that("EDA migration records a legacy show_percent as ignored, not translated", {
  root <- migration_study_fixture()
  lines <- c("```{r}", 'dta_filename <- "built.csv"', 'pref_time_var <- "iv_dead"', "show_percent <- TRUE", "```")
  result <- hvtiRtemplates:::.migrate_dc_eda(eda_evidence(root, lines), character())
  env <- eda_config(result)
  expect_true(4L %in% result$ignored$line)
  expect_match(result$ignored$reason[result$ignored$line == 4L], "replaced by SECTIONS")
  expect_identical(env$SECTIONS, c("continuous", "percent", "count"))
  expect_false(exists("SHOW_PERCENT", envir = env, inherits = FALSE))
  expect_null(env$VARIABLES)
})

test_that("naming the removed dp-postage in migrate_job() stops, and writes nothing", {
  # The catalog row went with the template, so there is no redirect left, and
  # since dp-eda became dc-eda no template carries the dp prefix at all: the
  # caller is told the prefixes on offer, dc among them.
  root <- migration_study_fixture("dp-postage")
  source <- file.path(root, "descriptive", "dp.postage.qmd")
  expect_error(migrate_job(source, "cohort", "eda", "dp", "postage", dir = root),
               "unknown template: dp[.]postage[.] Available: [^\n]*dc")
  # Left to the filename, whose second field names no template, the prefix
  # alone is unknown.
  expect_error(migrate_job(source, "cohort", "eda", prefix = "dp", dir = root),
               "unknown template: dp[.] Available: [^\n]*dc")
  expect_length(list.files(root, "[.]eda[.]qmd$|-migration[.]md$", recursive = TRUE), 0L)
})
