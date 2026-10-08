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
  eval(parse(text = unname(result$regions[c("dp-eda-data", "dp-eda-variables")])), env)
  env
}

# dp-postage is deprecated but still ships, so its own code is still tested
# here. Read its path from template_list(), not template_path(), which warns.
postage_template <- function() {
  tl <- template_list()
  tl$file[tl$name == "dp-postage"]
}

test_that("postage migration selects registered data and explicit ordered EDA controls", {
  root <- migration_study_fixture("dp-postage")
  source <- file.path(root, "descriptive", "dp.postage.qmd")
  bytes <- readBin(source, "raw", n = file.info(source)$size)
  job <- migrate_job(source, "cohort", "eda", "dp", "eda", dir = root)
  expect_identical(dirname(job), normalizePath(file.path(root, "descriptive"), winslash = "/"))
  env <- list2env(list(.root = root, read_built = hvtiRutilities::read_built,
                       study_config = hvtiRutilities::study_config))
  withr::local_dir(root)
  eval(postage_chunk(job, "edit-study-choices"), env)
  capture.output(eval(postage_chunk(job, "tbl-data"), env))
  expect_identical(env$DATASET, "built")
  expect_null(env$ANALYSIS_SET)
  expect_equal(nrow(env$d), 40L)
  expect_identical(env$X_VAR, "iv_dead")
  expect_identical(env$VARIABLES, c("dead", "iv_dead", "iv_fup", "year", "female", "race_grp",
                                    "repair", "age", "bmi", "treatment", "hx_chf", "lvmassi",
                                    "iv_opyrs", "panel1", "panel2", "panel3", "panel4", "panel5"))
  expect_identical(env$GRID_NCOL, 4L)
  expect_identical(env$GRID_NROW, 4L)
  # A legacy EDA report drew no follow-up panels, so the dp-eda job draws the
  # three sections dp-postage drew, and no more.
  expect_identical(basename(job), "cohort-eda-dp-eda.qmd")
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

test_that("postage handles SAS controls without executing source cleaning or unsupported choices", {
  root <- migration_study_fixture()
  lines <- c("* %let pref_time_var=wrong;", "SET complete_cases;",
             "%LET pref_time_var=iv_dead;", "%let variables=age bmi female;",
             "%let exclude=bmi;", "%let ncol=2;", "%let nrow=1;",
             "%let pref_color_var=repair;", "%let stratify_by=female;",
             "%let alpha=0.2;", "axis1 order=(0 to 10 by 2);", "age=age+1;")
  result <- hvtiRtemplates:::.migrate_dp_eda(postage_evidence(root, lines, "sas"), character())
  env <- postage_config(result)
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

test_that("postage accepts literal QMD controls only and keeps incomplete choices blocked", {
  root <- migration_study_fixture()
  lines <- c("```{r}", 'dta_filename <- "built.csv"', 'pref_time_var <- "iv_dead"',
             'variables <- c("age", "bmi")', 'exclude <- "bmi"', "ncol <- 2L", "```")
  result <- hvtiRtemplates:::.migrate_dp_eda(postage_evidence(root, lines), character())
  expect_identical(postage_config(result)$VARIABLES, c("age", "bmi"))
  expect_identical(postage_config(result)$EXCLUDE, "bmi")
  for (extra in c('pref_time_var <- "year"', 'if (flag) pref_time_var <- "year"',
                  'pref_time_var <- paste0("iv_", "dead")')) {
    changed <- append(lines, extra, after = 6L)
    expect_error(hvtiRtemplates:::.migrate_dp_eda(postage_evidence(root, changed), character()), "Multiple declarations")
  }
  lines[4L] <- 'variables <- system("touch should-never-exist")'
  result <- hvtiRtemplates:::.migrate_dp_eda(postage_evidence(root, lines), character())
  expect_null(postage_config(result)$VARIABLES)
  expect_true(4L %in% result$unresolved$line)
  expect_false(any(grepl("system|touch", result$regions)))
  expect_match(paste(result$regions, collapse = "\n"), "EDIT:", fixed = TRUE)
})

test_that("postage template validates selection and plotting settings before saving", {
  job <- postage_template()
  data <- postage_chunk(job, "data")
  # Run validation separately from the template's editable declarations.
  env <- list2env(list(d = data.frame(year = 1:10, age = 41:50, patient_id = 11:20, visit_date = 21:30),
                       X_VAR = "year", VARIABLES = "age", EXCLUDE = character(),
                       GRID_NCOL = 4L, GRID_NROW = 4L, UNIQUE_LIMIT = 6L,
                       SECTIONS = c("continuous", "percent", "count"), ALPHA = 0.5,
                       LABEL_MAX = 40, ABBREVIATIONS = NULL))
  expect_error({
    selection <- data[seq.int(which(vapply(data, function(x) is.call(x) && identical(x[[1]], as.name("if")), logical(1)))[1],
                              length(data))]
    eval(selection, list2env(list(DATASET = "complete_cases", ANALYSIS_SET = "eda")))
  }, "written from the study dataset")
  spec <- postage_chunk(job, "spec")
  expect_no_error(eval(spec, env))
  for (field in c("X_VAR", "VARIABLES", "EXCLUDE", "GRID_NCOL", "GRID_NROW", "UNIQUE_LIMIT", "SECTIONS", "ALPHA",
                  "LABEL_MAX", "ABBREVIATIONS")) {
    original <- env[[field]]
    env[[field]] <- NA
    expect_error(eval(spec, env), info = field)
    env[[field]] <- original
  }
  # The two label settings fail naming themselves, not label_map()'s arguments.
  env$LABEL_MAX <- 3
  expect_error(eval(spec, env), "LABEL_MAX")
  env$LABEL_MAX <- Inf
  expect_no_error(eval(spec, env))
  env$LABEL_MAX <- 40
  env$ABBREVIATIONS <- c("SP", "Proc")
  expect_error(eval(spec, env), "ABBREVIATIONS")
  env$ABBREVIATIONS <- NULL
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

test_that("a migrated legacy EDA report renders real eighteen-panel pages under the logical graphs route", {
  skip_on_cran()
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  out <- render_migrated_fixture("dp-postage")
  expect_identical(basename(out$job), "cohort-eda-dp-eda.qmd")
  expected <- file.path(out$root, "graphs", "cohort-eda",
                        sprintf("dp-eda-%s-page-01.png", c("continuous", "percent", "count")))
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

test_that("postage routes actual pages through numbered study folders and embeds the saved files", {
  root <- migration_study_fixture("dp-postage")
  local_child_chunks()
  d <- hvtiRutilities::read_built(hvtiRutilities::study_config(root))
  for (name in names(d)) attr(d[[name]], "label") <- paste("Synthetic", name)
  folders <- c("datasets", "descriptive", "distributions", "analyses", "graphs", "documents", "estimates")
  numbered <- c("00_datasets", "10_descriptive", "20_distributions", "30_analyses", "40_graphs", "50_documents", "90_estimates")
  expect_true(all(file.rename(file.path(root, folders), file.path(root, numbered))))
  env <- list2env(list(
    .root = root, d = d, X_VAR = "iv_dead", VARIABLES = c("age", "bmi", "lvmassi"), EXCLUDE = character(),
    GRID_NCOL = 2L, GRID_NROW = 1L, UNIQUE_LIMIT = 6L, SECTIONS = c("continuous", "percent", "count"), ALPHA = 0.5,
    get_label = hvtiRutilities::get_label, label_map = hvtiRutilities::label_map,
    theme_hv_manuscript = hvtiPlotR::theme_hv_manuscript, scale_fill_hv = hvtiPlotR::scale_fill_hv,
    .cfg = hvtiRutilities::study_config(root), LABEL_MAX = 40, ABBREVIATIONS = NULL,
    SAVE_FIGURES = TRUE, FIGURES = NULL
  ))
  job <- postage_template()
  for (label in c("set", "spec")) eval(postage_chunk(job, label), env)
  capture.output(paths <- eval(postage_chunk(job, "pages"), env))
  # All three are continuous, so only that section draws pages: two at 2 x 1.
  expected <- file.path(root, "40_graphs", "cohort-eda", sprintf("dp-postage-continuous-page-%02d.png", 1:2))
  expect_identical(as.character(paths), expected)
  expect_identical(lapply(env$pages, attr, "variables"), list(c("age", "bmi"), "lvmassi"))
  expect_true(all(file.info(expected)$size > 1000))
  expect_false(dir.exists(file.path(root, "graphs")))
})

test_that("postage draws its categorical pages in the role colors", {
  # The page is handed to ggsave() whole, so capture it there and build each
  # panel: every bar must be a house color, blue first, missing gray.
  root <- migration_study_fixture("dp-postage")
  local_child_chunks()
  saved <- list()
  local_mocked_bindings(ggsave = function(filename, plot, ...) {
    saved[[basename(filename)]] <<- plot
    invisible(filename)
  }, .package = "ggplot2")
  env <- list2env(list(
    .root = root, d = hvtiRutilities::read_built(hvtiRutilities::study_config(root)), X_VAR = "iv_dead",
    VARIABLES = c("female", "hx_chf"), EXCLUDE = character(), GRID_NCOL = 2L, GRID_NROW = 1L,
    UNIQUE_LIMIT = 6L, SECTIONS = "percent", ALPHA = 0.5,
    get_label = hvtiRutilities::get_label, label_map = hvtiRutilities::label_map,
    theme_hv_manuscript = hvtiPlotR::theme_hv_manuscript, scale_fill_hv = hvtiPlotR::scale_fill_hv,
    .cfg = hvtiRutilities::study_config(root), LABEL_MAX = 40, ABBREVIATIONS = NULL,
    SAVE_FIGURES = TRUE, FIGURES = NULL
  ))
  job <- postage_template()
  for (label in c("set", "spec")) eval(postage_chunk(job, label), env)
  suppressWarnings(capture.output(eval(postage_chunk(job, "pages"), env)))
  expect_identical(names(saved), c("dp-postage-percent-page-01.png", "dp-postage-percent-page-01.pdf"))
  page <- saved[[1L]]
  fills <- unique(unlist(lapply(seq_along(page), function(k) ggplot2::ggplot_build(page[[k]])$data[[1L]]$fill)))
  expect_true(all(fills %in% c(hvtiPlotR::hv_ppt_palette("light"), "#CCCCCC")), info = paste(fills, collapse = ", "))
  expect_true("#0072B2" %in% fills)
})

# These tests exercise the job, study and initials levels of the abbreviation
# list. hvtiRutilities (>= 1.4.3) adds a group default list underneath, which
# shortens "aortic valve replacement" too; turn it off so each test sees only
# the level it is about. The group list has its own test below.
without_group_list <- function(env = parent.frame()) {
  real <- hvtiRutilities::study_abbreviations
  testthat::local_mocked_bindings(
    study_abbreviations = function(cfg, extra = NULL, defaults = TRUE) real(cfg, extra = extra, defaults = FALSE),
    .package = "hvtiRutilities", .env = env
  )
}

test_that("postage shortens labels that share a heading and prints their key", {
  # Two labels over LABEL_MAX share a heading: both show its abbreviation, and
  # the section says what it stands for. A job's own entry beats the initials.
  root <- migration_study_fixture("dp-postage")
  local_child_chunks()
  local_mocked_bindings(ggsave = function(filename, plot, ...) invisible(filename), .package = "ggplot2")
  without_group_list()
  d <- hvtiRutilities::read_built(hvtiRutilities::study_config(root))
  attr(d$female, "label") <- "Surgical procedure: aortic valve replacement with root enlargement"
  attr(d$hx_chf, "label") <- "Surgical procedure: mitral valve repair with annuloplasty ring"
  run_pages <- function(abbreviations) {
    env <- list2env(list(
      .root = root, d = d, X_VAR = "iv_dead", VARIABLES = c("female", "hx_chf"), EXCLUDE = character(),
      GRID_NCOL = 2L, GRID_NROW = 1L, UNIQUE_LIMIT = 6L, SECTIONS = "percent", ALPHA = 0.5,
      get_label = hvtiRutilities::get_label, label_map = hvtiRutilities::label_map,
      theme_hv_manuscript = hvtiPlotR::theme_hv_manuscript, scale_fill_hv = hvtiPlotR::scale_fill_hv,
      .cfg = list(), LABEL_MAX = 40, ABBREVIATIONS = abbreviations,
      SAVE_FIGURES = TRUE, FIGURES = NULL
    ))
    job <- postage_template()
    for (label in c("set", "spec")) eval(postage_chunk(job, label), env)
    out <- suppressWarnings(utils::capture.output(eval(postage_chunk(job, "pages"), env)))
    list(labels = unname(env$labels[c("female", "hx_chf")]), text = paste(out, collapse = "\n"))
  }
  initials <- run_pages(NULL)
  expect_match(initials$labels, "^SP: ")
  expect_match(initials$text, "Abbreviations: SP = Surgical procedure.", fixed = TRUE)
  own <- run_pages(c("Surgical procedure" = "Proc"))
  expect_match(own$labels, "^Proc: ")
  expect_match(own$text, "Abbreviations: Proc = Surgical procedure.", fixed = TRUE)
})

test_that("postage prints a key only under sections whose labels were shortened, from every level", {
  # A label that already says "SP" in its own words (systolic pressure) is not
  # a shortened label: its section gets no key claiming SP = Surgical procedure.
  # The study's list applies unless the job overrides it.
  root <- migration_study_fixture("dp-postage")
  local_child_chunks()
  local_mocked_bindings(ggsave = function(filename, plot, ...) invisible(filename), .package = "ggplot2")
  without_group_list()
  d <- hvtiRutilities::read_built(hvtiRutilities::study_config(root))
  attr(d$age, "label") <- "SP at admission (mmHg)"
  attr(d$female, "label") <- "Surgical procedure: aortic valve replacement with root enlargement"
  attr(d$hx_chf, "label") <- "Surgical procedure: mitral valve repair with annuloplasty ring"
  run_pages <- function(cfg, abbreviations) {
    env <- list2env(list(
      .root = root, d = d, X_VAR = "iv_dead", VARIABLES = c("age", "female", "hx_chf"), EXCLUDE = character(),
      GRID_NCOL = 2L, GRID_NROW = 1L, UNIQUE_LIMIT = 6L, SECTIONS = c("continuous", "percent"), ALPHA = 0.5,
      get_label = hvtiRutilities::get_label, label_map = hvtiRutilities::label_map,
      theme_hv_manuscript = hvtiPlotR::theme_hv_manuscript, scale_fill_hv = hvtiPlotR::scale_fill_hv,
      .cfg = cfg, LABEL_MAX = 40, ABBREVIATIONS = abbreviations,
      SAVE_FIGURES = TRUE, FIGURES = NULL
    ))
    job <- postage_template()
    for (label in c("set", "spec")) eval(postage_chunk(job, label), env)
    out <- suppressWarnings(utils::capture.output(eval(postage_chunk(job, "pages"), env)))
    list(labels = unname(env$labels[c("female", "hx_chf")]), text = paste(out, collapse = "\n"))
  }
  initials <- run_pages(list(), NULL)
  sections <- strsplit(initials$text, "## Categorical", fixed = TRUE)[[1L]]
  expect_false(grepl("Abbreviations:", sections[1L], fixed = TRUE))
  expect_match(sections[2L], "Abbreviations: SP = Surgical procedure.", fixed = TRUE)
  study <- run_pages(list(abbreviations = list("Surgical procedure" = "SProc")), NULL)
  expect_match(study$labels, "^SProc: ")
  job <- run_pages(list(abbreviations = list("Surgical procedure" = "SProc")), c("Surgical procedure" = "Proc"))
  expect_match(job$labels, "^Proc: ")
})

test_that("the group abbreviation list shortens further, when it is installed", {
  skip_if(!length(hvtiRutilities::study_abbreviations(list())), "hvtiRutilities has no group abbreviation list")
  root <- migration_study_fixture("dp-postage")
  local_child_chunks()
  local_mocked_bindings(ggsave = function(filename, plot, ...) invisible(filename), .package = "ggplot2")
  d <- hvtiRutilities::read_built(hvtiRutilities::study_config(root))
  attr(d$female, "label") <- "Surgical procedure: aortic valve replacement with root enlargement"
  attr(d$hx_chf, "label") <- "Surgical procedure: mitral valve repair with annuloplasty ring"
  env <- list2env(list(
    .root = root, d = d, X_VAR = "iv_dead", VARIABLES = c("female", "hx_chf"), EXCLUDE = character(),
    GRID_NCOL = 2L, GRID_NROW = 1L, UNIQUE_LIMIT = 6L, SECTIONS = "percent", ALPHA = 0.5,
    get_label = hvtiRutilities::get_label, label_map = hvtiRutilities::label_map,
    theme_hv_manuscript = hvtiPlotR::theme_hv_manuscript, scale_fill_hv = hvtiPlotR::scale_fill_hv,
    .cfg = list(), LABEL_MAX = 40, ABBREVIATIONS = NULL,
    SAVE_FIGURES = TRUE, FIGURES = NULL
  ))
  job <- postage_template()
  for (label in c("set", "spec")) eval(postage_chunk(job, label), env)
  out <- paste(suppressWarnings(utils::capture.output(eval(postage_chunk(job, "pages"), env))), collapse = "\n")
  # The group list names both procedures; the key lists every entry it used.
  expect_match(out, "AVR = Aortic valve replacement", fixed = TRUE)
  expect_match(out, "MVr = Mitral valve repair", fixed = TRUE)
})

test_that("postage does not require databuild for registered data but validates analysis-set mode", {
  root <- migration_study_fixture("dp-postage")
  job <- migrate_job(file.path(root, "descriptive", "dp.postage.qmd"), "cohort", "eda", "dp", "eda", dir = root)
  env <- list2env(list(.root = root, read_built = hvtiRutilities::read_built, study_config = hvtiRutilities::study_config))
  # The full setup and registered-data branch run with the actual dependencies.
  withr::local_dir(dirname(job))
  eval(postage_chunk(job, "setup"), env)
  eval(postage_chunk(job, "edit-study-choices"), env)
  capture.output(eval(postage_chunk(job, "tbl-data"), env))
  expect_equal(nrow(env$d), 40L)
  # The migrated job reads through read_job_data(), which checks every setting
  # before reading and asks for hvtiRdatabuild only for an analysis set.
  data <- postage_chunk(job, "tbl-data")
  env$ANALYSIS_SET <- NULL
  env$DATASET <- ""
  expect_error(eval(data, env), "DATASET must name one dataset")
  env$DATASET <- "study"
  env$ANALYSIS_SET <- "eda"
  if (!requireNamespace("hvtiRdatabuild", quietly = TRUE) || utils::packageVersion("hvtiRdatabuild") < "0.2.1") {
    expect_error(eval(data, env), "hvtiRdatabuild 0.2.1", fixed = TRUE)
  }
})

test_that("postage SAS quoted declarations cannot override active controls", {
  root <- migration_study_fixture()
  lines <- c("set built;", "%let pref_time_var=iv_dead;", "%let variables=age bmi;",
             'title "Example: %let variables=wrong; set absent;";')
  result <- hvtiRtemplates:::.migrate_dp_eda(postage_evidence(root, lines, "sas"), character())
  expect_identical(postage_config(result)$DATASET, "built")
  expect_identical(postage_config(result)$VARIABLES, c("age", "bmi"))
  expect_true(4L %in% result$unresolved$line)
})

test_that("postage treats SAS field names case-insensitively", {
  root <- migration_study_fixture()
  lines <- c("SET BUILT;", "%LET PREF_TIME_VAR=IV_DEAD;", "%LET VARIABLES=AGE BMI;", "%LET EXCLUDE=BMI;")
  result <- hvtiRtemplates:::.migrate_dp_eda(postage_evidence(root, lines, "sas"), character())
  env <- postage_config(result)
  expect_identical(env$X_VAR, "iv_dead")
  expect_identical(env$VARIABLES, c("age", "bmi"))
  expect_identical(env$EXCLUDE, "bmi")
})

test_that("postage leaves disabled QMD chunks inactive and conditional chunks unresolved", {
  root <- migration_study_fixture()
  lines <- c("```{r}", 'dta_filename <- "built.csv"', 'pref_time_var <- "iv_dead"',
             'variables <- "age"', "```", "```{r}", "#| eval: false", 'variables <- "bmi"', "```")
  result <- hvtiRtemplates:::.migrate_dp_eda(postage_evidence(root, lines), character())
  expect_identical(postage_config(result)$VARIABLES, "age")
  expect_true(8L %in% result$ignored$line)
  lines <- c("```{r}", "#| eval: !expr run_eda", 'variables <- "age"', "```")
  result <- hvtiRtemplates:::.migrate_dp_eda(postage_evidence(root, lines), character())
  expect_null(postage_config(result)$VARIABLES)
  expect_true(3L %in% result$unresolved$line)
})

test_that("postage retains cleaning with omitted subscript arguments as unresolved evidence", {
  root <- migration_study_fixture()
  lines <- c("```{r}", 'dta_filename <- "built.csv"', 'pref_time_var <- "iv_dead"',
             'variables <- "age"', 'd[, "age"] <- d[, "age"] + 1', "```")
  result <- hvtiRtemplates:::.migrate_dp_eda(postage_evidence(root, lines), character())
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
      result <- hvtiRtemplates:::.migrate_dp_eda(postage_evidence(root, lines), character())
      env <- postage_config(result)
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

test_that("postage recognizes complete inline boolean eval options", {
  root <- migration_study_fixture()
  for (value in c("TRUE", "FALSE")) {
    lines <- c(paste0("```{r setup, eval=", value, ", echo=FALSE}"),
               'dta_filename <- "built.csv"', 'pref_time_var <- "iv_dead"', 'variables <- "age"', "```")
    result <- hvtiRtemplates:::.migrate_dp_eda(postage_evidence(root, lines), character())
    if (value == "TRUE") {
      expect_identical(postage_config(result)$VARIABLES, "age")
      expect_true(all(2:4 %in% result$translated$line))
    } else {
      expect_null(postage_config(result)$VARIABLES)
      expect_true(all(2:4 %in% result$ignored$line))
    }
  }
})

test_that("postage VARIABLES = NULL draws every column but ids, dates and exclusions, and says so", {
  spec <- postage_chunk(postage_template(), "spec")
  env <- list2env(list(d = data.frame(year = 1:10, age = 41:50, patient_id = 11:20, op_date = Sys.Date() + 0:9,
                                      female = rep(0:1, 5), bmi = 21:30),
                       X_VAR = "year", VARIABLES = NULL, EXCLUDE = "bmi",
                       GRID_NCOL = 4L, GRID_NROW = 4L, UNIQUE_LIMIT = 6L,
                       SECTIONS = c("continuous", "percent", "count"), ALPHA = 0.5,
                       LABEL_MAX = 40, ABBREVIATIONS = NULL))
  out <- capture.output(eval(spec, env))
  expect_identical(env$VARIABLES, c("age", "female"))
  expect_match(paste(out, collapse = " "), "patient_id, op_date")
  env$VARIABLES <- c("age", "nope1", "nope2")
  expect_error(eval(spec, env), "nope1, nope2")
  env$VARIABLES <- NULL
  env$SECTIONS <- c("continuous", "percentage")
  expect_error(eval(spec, env), "SECTIONS")
  # A repeated section would draw twice over the same page files.
  env$SECTIONS <- c("percent", "percent")
  expect_error(eval(spec, env), "SECTIONS")
})

test_that("postage VARIABLES = NULL leaves out identifiers written without a separator", {
  spec <- postage_chunk(postage_template(), "spec")
  # ccfid, the CCF patient identifier, has no "_" before "id", so the token rule
  # alone drew it as one bar per patient. carotid, steroid and case end the same
  # way and are study variables, so a bare id$ would be the opposite defect.
  n <- 12L
  env <- list2env(list(d = data.frame(year = seq_len(n), age = 40 + seq_len(n), ccfid = 1000L + seq_len(n),
                                      patientid = sprintf("P%03d", seq_len(n)), mrn = 5000L + seq_len(n),
                                      eMRN = 7000L + seq_len(n), pt_mrn_num = rep(0:1, 6), bnp_mrna = 0.5 * seq_len(n),
                                      surgeon_note = sprintf("note %d", seq_len(n)),
                                      carotid = rep(0:1, 6), steroid = rep(0:1, 6), case = rep(0:1, 6)),
                       X_VAR = "year", VARIABLES = NULL, EXCLUDE = character(),
                       GRID_NCOL = 4L, GRID_NROW = 4L, UNIQUE_LIMIT = 6L,
                       SECTIONS = c("continuous", "percent", "count"), ALPHA = 0.5,
                       LABEL_MAX = 40, ABBREVIATIONS = NULL))
  out <- capture.output(eval(spec, env))
  # Only the exact names MRN and eMRN are record numbers: pt_mrn_num and the
  # mRNA variable bnp_mrna are study variables like any other.
  expect_identical(env$VARIABLES, c("age", "pt_mrn_num", "bnp_mrna", "carotid", "steroid", "case"))
  expect_match(paste(out, collapse = " "), "ccfid, patientid, mrn, eMRN, surgeon_note")
  # Below ten values a distinct character column is kept: a small check frame
  # is not a register.
  env$d <- env$d[1:9, ]
  env$VARIABLES <- NULL
  capture.output(eval(spec, env))
  expect_true("surgeon_note" %in% env$VARIABLES)
  expect_false("ccfid" %in% env$VARIABLES)
})

test_that("postage migration records a legacy show_percent as ignored, not translated", {
  root <- migration_study_fixture()
  lines <- c("```{r}", 'dta_filename <- "built.csv"', 'pref_time_var <- "iv_dead"', "show_percent <- TRUE", "```")
  result <- hvtiRtemplates:::.migrate_dp_eda(postage_evidence(root, lines), character())
  env <- postage_config(result)
  expect_true(4L %in% result$ignored$line)
  expect_match(result$ignored$reason[result$ignored$line == 4L], "replaced by SECTIONS")
  expect_identical(env$SECTIONS, c("continuous", "percent", "count"))
  expect_false(exists("SHOW_PERCENT", envir = env, inherits = FALSE))
  expect_null(env$VARIABLES)
})

test_that("postage embeds its pages when the job sits in a subfolder", {
  skip_on_cran()
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  root <- migration_study_fixture(NULL)
  expect_warning(job <- add_job("dp", "cohort", "eda", dir = root, qualifier = "postage"), "deprecated")
  nested <- file.path(dirname(job), "eda", basename(job))
  dir.create(dirname(nested))
  lines <- sub('^ANALYSIS_SET <- "eda"', "ANALYSIS_SET <- NULL", readLines(job, warn = FALSE))
  writeLines(lines, nested)
  unlink(job)
  quarto::quarto_render(nested, execute_dir = dirname(nested), quiet = TRUE)
  html <- paste(readLines(sub("[.]qmd$", ".html", nested), warn = FALSE), collapse = "\n")
  pngs <- list.files(file.path(root, "graphs", "cohort-eda"), pattern = "^dp-postage-.*[.]png$")
  expect_gte(length(pngs), 1L)
  # regmatches(), not length(gregexpr()): no match returns -1, whose length is 1.
  expect_identical(length(regmatches(html, gregexpr("src=\"data:image/png", html))[[1L]]), length(pngs))
})

test_that("naming the deprecated dp-postage in migrate_job() warns and writes a dp-eda job", {
  root <- migration_study_fixture("dp-postage")
  source <- file.path(root, "descriptive", "dp.postage.qmd")
  expect_warning(job <- migrate_job(source, "cohort", "eda", "dp", "postage", dir = root),
                 "dp-postage is deprecated in favor of dp-eda", class = "hvtiRtemplates_deprecated")
  expect_identical(basename(job), "cohort-eda-dp-eda.qmd")
  expect_false(file.exists(file.path(root, "descriptive", "cohort-eda-dp-postage.qmd")))
  lines <- readLines(job, warn = FALSE)
  expect_true('SECTIONS <- c("continuous", "percent", "count")' %in% lines)
  expect_true('X_VAR <- "iv_dead"' %in% lines)
  # Read from the filename's second field, the same redirect applies.
  other <- migration_study_fixture("dp-postage")
  expect_warning(job <- migrate_job(file.path(other, "descriptive", "dp.postage.qmd"), "cohort", "eda",
                                    prefix = "dp", dir = other), class = "hvtiRtemplates_deprecated")
  expect_identical(basename(job), "cohort-eda-dp-eda.qmd")
})

test_that("postage names an analysis set the study has not built (#173)", {
  # dp-postage reads its analysis set outside read_job_data(), and defaults
  # ANALYSIS_SET to "eda", which a freshly registered study does not have.
  root <- withr::local_tempdir()
  suppressMessages(hvtiRutilities::study_setup(root, "Postage", 1L, adopt = TRUE))
  utils::write.csv(data.frame(ccfid = 1:3, year = 2001:2003),
                   file.path(hvtiRutilities::study_dir("datasets", root), "built.csv"), row.names = FALSE)
  suppressMessages(hvtiRutilities::register_data(root, "built.csv"))
  # Either name for the study dataset reaches the analysis set.
  for (dataset in c("built", "study")) {
    env <- list2env(list(.root = root, DATASET = dataset, ANALYSIS_SET = "eda",
                         study_config = hvtiRutilities::study_config, study_dir = hvtiRutilities::study_dir,
                         read_built = hvtiRutilities::read_built))
    err <- tryCatch(eval(postage_chunk(postage_template(), "data"), env), error = conditionMessage)
    expect_match(err, "ANALYSIS_SET names `eda`, an analysis set this study has not built", fixed = TRUE)
    expect_match(err, "ANALYSIS_SET <- NULL", fixed = TRUE)
    expect_no_match(err, "hvtiRdatabuild >= 0.2.1|missing file")
  }
  # Anything but one of the two names stops on the named rule, not a base-R error.
  for (dataset in list(NULL, c("built", "other"), "other")) {
    env$DATASET <- dataset
    expect_error(eval(postage_chunk(postage_template(), "data"), env), "written from the study dataset")
  }
})
