tables_migrate <- function(root, evidence = TRUE) {
  migrate_job(
    file.path(root, "descriptive", "dc.tables.sas"), "cohort", "eda", "dc", "tables",
    lst = if (evidence) file.path(root, "descriptive", "dc.tables.lst") else NULL,
    log = if (evidence) file.path(root, "descriptive", "dc.tables.log") else NULL,
    reference = if (evidence) file.path(root, "documents", "general.rtf") else NULL,
    dir = root
  )
}

tables_region <- function(job, name) {
  lines <- readLines(job, warn = FALSE)
  first <- match(paste0("# MIGRATE-BEGIN: ", name), lines)
  last <- match(paste0("# MIGRATE-END: ", name), lines)
  lines[seq.int(first + 1L, last - 1L)]
}

tables_source <- function(root, lines) {
  writeLines(lines, file.path(root, "descriptive", "dc.tables.sas"))
}

test_that("dc-tables ignores commented calls beside an active call", {
  for (comment in c("%*", "* multiline\n")) {
    root <- migration_study_fixture("dc-tables")
    tables_source(root, c(
      paste0(comment, " %desc_tab(vartype=bad,input=wrong,varlist=/* Bad */ wrong);"),
      "%desc_tab(vartype=continuous,input=built,varlist=/* Demography */ age);"
    ))
    out <- tables_migrate(root, evidence = FALSE)
    env <- new.env()
    eval(parse(text = tables_region(out, "dc-tables-config")), env)
    expect_identical(env$CONTINUOUS, "age")
    expect_identical(env$GROUPS, list(Demography = "age"))
  }
})

test_that("dc-tables blocks local DATA-step filters and transformed measurements", {
  root <- migration_study_fixture("dc-tables")
  tables_source(root, c(
    "data built; set built; if female=1; age=age+10; run;",
    "%desc_tab(vartype=continuous,input=built,by=treatment,",
    "          varlist=/* Demography */ age);"
  ))
  out <- tables_migrate(root, evidence = FALSE)
  env <- new.env()
  eval(parse(text = c(tables_region(out, "dc-tables-data"), tables_region(out, "dc-tables-config"))), env)
  expect_true(is.na(env$DATASET))
  expect_identical(env$CONTINUOUS, character())
  # Nothing mapped, so nothing about the comparison is claimed either.
  expect_identical(env$COMPARE, "none")
  expect_identical(env$CONTINUOUS_STAT, "median")
  expect_identical(env$MANUSCRIPT_LAYOUT, "compare")
  expect_true(any(grepl("EDIT:.*source.*logic", readLines(out))))
  report <- readLines(sub("[.]qmd$", "-migration.md", out))
  translated <- report[seq.int(match("## Translated", report), match("## Unresolved", report) - 1L)]
  expect_false(any(grepl("input=built|continuous: age", translated)))
  expect_true(any(grepl("line=1; text=if female=1;", report, fixed = TRUE)))
  expect_true(any(grepl("line=1; text=age=age+10;", report, fixed = TRUE)))
  # The layout row moved to Unresolved with the rest; its reason must be true
  # after the reset to "compare", so it no longer says the statistic is both.
  expect_true(any(grepl("MANUSCRIPT_LAYOUT: compare", report, fixed = TRUE)))
  expect_false(any(grepl("CONTINUOUS_STAT is both", report, fixed = TRUE)))
})

test_that("dc-tables migrates desc_tab groups and types", {
  root <- migration_study_fixture("dc-tables")
  out <- tables_migrate(root)
  txt <- readLines(out, warn = FALSE)
  for (line in c(
    'DATASET <- "built"', "ANALYSIS_SET <- NULL", 'BY <- "treatment"',
    '  Demography = c("female", "race_grp", "age", "bmi"),',
    'CONTINUOUS <- c("age", "bmi", "iv_dead")',
    'CATEGORICAL <- c("race_grp")', 'BINARY <- c("female", "repair")'
  )) expect_true(line %in% txt, info = line)
  env <- new.env()
  eval(parse(text = tables_region(out, "dc-tables-config")), env)
  expect_identical(env$GROUPS, list(
    Demography = c("female", "race_grp", "age", "bmi"),
    Procedure = "repair", `Follow-up` = "iv_dead"
  ))
  # %desc_tab printed a p-value whenever by= named a group, and both mean +/- SD
  # and the percentiles for a continuous variable.
  expect_identical(env$COMPARE, "pvalue")
  expect_identical(env$CONTINUOUS_STAT, "both")
  expect_identical(env$PERCENTILES, c(15, 85))
  report <- paste(readLines(sub("[.]qmd$", "-migration.md", out)), collapse = "\n")
  for (value in c("byvalue", "countpersig", "outrtf", 'title3 "[string]";', "[heading]: iv_dead")) {
    expect_match(report, value, fixed = TRUE)
  }
  expect_false(grepl("Follow-up", report, fixed = TRUE))
  expect_match(report, "BINARY: female, repair", fixed = TRUE)
  expect_match(paste(txt, collapse = "\n"), "EDIT: review SAS presentation choices", fixed = TRUE)
})

test_that("dc-tables only classifies from the selected registered data", {
  root <- migration_study_fixture("dc-tables")
  source <- readLines(file.path(root, "descriptive", "dc.tables.sas"))
  tables_source(root, gsub("input=built", "input=categorical", source, fixed = TRUE))
  path <- file.path(root, "datasets", "categorical.csv")
  d <- utils::read.csv(file.path(root, "datasets", "complete_cases.csv"))
  d$female <- rep(1:3, 8)
  utils::write.csv(d, path, row.names = FALSE)
  suppressMessages(hvtiRutilities::register_data(
    root, built = "categorical.csv",
    dataset = "categorical", role = "named", population = "Synthetic categorical fixture"
  ))
  out <- tables_migrate(root)
  expect_true('DATASET <- "categorical"' %in% readLines(out))
  env <- new.env()
  eval(parse(text = tables_region(out, "dc-tables-config")), env)
  expect_identical(env$BINARY, "repair")
  expect_identical(env$CATEGORICAL, c("female", "race_grp"))
})

test_that("the study dataset is selected as \"built\", by either name or by its file's stem", {
  # The study dataset's file is cohort.csv, so "built" cannot match a file stem.
  root <- withr::local_tempdir()
  suppressMessages(hvtiRutilities::study_setup(root, "Built name", 42L, adopt = TRUE, cleanup = FALSE, renv = FALSE))
  utils::write.csv(data.frame(ccfid = 1:3), file.path(hvtiRutilities::study_dir("datasets", root), "cohort.csv"),
                   row.names = FALSE)
  suppressMessages(hvtiRutilities::register_data(root, built = "cohort.csv", role = "study"))
  for (input in c("built", "study", "cohort")) {
    expect_identical(hvtiRtemplates:::.dc_tables_dataset(root, input)$dataset, "built", info = input)
  }
  expect_true(is.na(hvtiRtemplates:::.dc_tables_dataset(root, "absent")$dataset))
  # SAS `set built;` names a file: an additional dataset in built.csv keeps it.
  utils::write.csv(data.frame(ccfid = 1:2), file.path(hvtiRutilities::study_dir("datasets", root), "built.csv"),
                   row.names = FALSE)
  suppressMessages(hvtiRutilities::register_data(root, built = "built.csv", dataset = "subset", role = "named",
                                                 population = "Synthetic subset"))
  expect_identical(hvtiRtemplates:::.dc_tables_dataset(root, "built")$dataset, "subset")
  expect_identical(hvtiRtemplates:::.dc_tables_dataset(root, "study")$dataset, "built")
})

tables_chunk <- function(job, label) {
  lines <- readLines(job, warn = FALSE)
  start <- match(paste0("#| label: ", setup_label(label)), lines)  # nolint: object_usage_linter.
  end <- start + match("```", lines[-seq_len(start)])
  chunk_expression(lines[seq.int(start + 1L, end - 1L)], label)  # nolint: object_usage_linter.
}

test_that("dc-tables refuses a set cut from another dataset and reads a named registered dataset", {
  root <- migration_study_fixture("dc-tables")
  template <- template_path("dc", "tables")
  env <- new.env()
  env$.root <- root
  env$read_built <- hvtiRutilities::read_built
  env$study_config <- hvtiRutilities::study_config
  code <- tables_chunk(template, "tbl-data")
  assign <- vapply(code, function(x) {
    is.call(x) && identical(x[[1L]], quote(`<-`)) && as.character(x[[2L]]) %in% c("DATASET", "ANALYSIS_SET")
  }, logical(1))
  code <- code[!assign]
  withr::local_dir(root)
  env$DATASET <- "complete_cases"
  env$ANALYSIS_SET <- "eda"
  env$WHERE <- NULL
  env$ID <- env$KEY <- "ccfid"
  env$JOIN <- env$JOIN_VARS <- env$REDUCE <- env$JOIN_KEY <- NULL
  expect_error(eval(code, env), "written from the study dataset")
  env$ANALYSIS_SET <- NULL
  capture.output(eval(code, env))
  expect_equal(nrow(env$d), 24L)
})

test_that("migrated dc-tables writes an editable structurally clean document in the logical documents folder", {
  skip_on_cran()
  root <- migration_study_fixture("dc-tables")
  out <- tables_migrate(root)
  env <- new.env()
  env$.root <- root
  env$SUBJECT <- "cohort"
  env$TYPE <- "eda"
  env$OVERRIDES <- list()
  # The choices after the migrated block, at their template defaults.
  env$MEAN_SD <- env$ORDINAL <- character(0)
  env$STDDIFF <- FALSE
  env$GROUP_1 <- NULL
  env$SHOW_VARIABLE <- TRUE
  env$MANUSCRIPT_CAPTION <- "Table 1. Patient characteristics"
  env$MANUSCRIPT_FILL <- "#CAEDFB"
  env$TABLE_ORIENTATION <- "auto"
  env$study_dir <- hvtiRutilities::study_dir
  env$d <- hvtiRutilities::read_built(hvtiRutilities::study_config(root))
  eval(parse(text = tables_region(out, "dc-tables-config")), env)
  eval(tables_chunk(out, "helpers"), env)
  invisible(eval(tables_chunk(out, "tbl-table"), env))
  invisible(eval(tables_chunk(out, "word-file"), env))
  word <- file.path(root, "documents", "cohort-eda", "dc-tables.docx")
  expect_true(file.exists(word))
  expect_equal(nrow(hvtiRtables::hv_check_docx(word)), 0L)
  doc <- officer::docx_summary(officer::read_docx(word))
  expect_true(any(doc$content_type == "table cell"))
  expect_true(any(grepl("Demography", doc$text, fixed = TRUE)))
  env$BINARY <- c("female", "repair", "age")
  expect_error(eval(tables_chunk(out, "tbl-table"), env), "exactly one explicit bucket")
  env$BINARY <- NULL
  expect_error(eval(tables_chunk(out, "tbl-table"), env), "all three buckets")
  env$BINARY <- c("female", "repair")
  env$WORD_FILE <- "../escape.docx"
  invisible(eval(tables_chunk(out, "tbl-table"), env))
  expect_error(invisible(eval(tables_chunk(out, "word-file"), env)), "plain .docx filename", fixed = TRUE)
  expect_false(file.exists(file.path(root, "documents", "escape.docx")))
})

test_that("dc-tables stops on actual CORR structural findings", {
  path <- tempfile(fileext = ".docx")
  on.exit(unlink(path), add = TRUE)
  doc <- officer::body_add_xml(officer::read_docx(), paste0(
    '<w:p xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">',
    '<w:pPr><w:framePr w:w="100"/></w:pPr><w:r><w:t>Synthetic floating frame</w:t></w:r></w:p>'
  ))
  print(doc, target = path)
  expect_gt(nrow(hvtiRtables::hv_check_docx(path)), 0L)
  code <- tables_chunk(template_path("dc", "tables"), "word-file")
  start <- which(vapply(code, function(x) {
    is.call(x) && identical(x[[1L]], quote(`<-`)) && identical(x[[2L]], quote(check))
  }, logical(1)))
  expect_length(start, 1L)
  env <- new.env()
  env$word_path <- path
  expect_error(eval(code[seq.int(start, length(code))], env), "CORR structural check")
})

test_that("dc-tables leaves an unresolved split when registered data cannot prove it", {
  for (mode in c("missing", "unknown", "empty")) {
    root <- migration_study_fixture("dc-tables")
    if (mode == "missing") {
      # migrate_job() now resolves `dir` through hvtiRutilities::study_root(),
      # which requires _study.yml, so a missing study config is caught before
      # the adapter ever runs -- this mode can no longer reach the adapter's
      # own classification fallback below.
      unlink(file.path(root, "_study.yml"))
      expect_error(tables_migrate(root, evidence = FALSE), "_study.yml")
      next
    }
    if (mode == "unknown") {
      source <- readLines(file.path(root, "descriptive", "dc.tables.sas"))
      tables_source(root, gsub("input=built", "input=unregistered", source, fixed = TRUE))
    }
    if (mode == "empty") {
      tables_source(root, "%desc_tab(vartype=category,input=built,varlist=/* Empty */ absent);")
    }
    out <- tables_migrate(root, evidence = FALSE)
    txt <- readLines(out)
    expect_true("BINARY <- character(0)" %in% txt)
    expect_true(any(grepl("EDIT: resolve", txt, fixed = TRUE)))
    report <- paste(readLines(sub("[.]qmd$", "-migration.md", out)), collapse = "\n")
    expect_match(report, "classification", fixed = TRUE)
    if (mode == "unknown") {
      translated <- strsplit(strsplit(report, "## Translated", fixed = TRUE)[[1L]][[2L]],
                             "## Unresolved", fixed = TRUE)[[1L]][[1L]]
      expect_false(grepl("input=unregistered", translated, fixed = TRUE))
      unresolved <- strsplit(report, "## Unresolved", fixed = TRUE)[[1L]][[2L]]
      expect_match(unresolved, "input=unregistered", fixed = TRUE)
    }
  }
})

test_that("dc-tables merges repeated headings and rejects conflicting groups or calls", {
  root <- migration_study_fixture("dc-tables")
  tables_source(root, "%desc_tab(vartype=continuous,input=built,varlist=/* D */ age /* P */ bmi /* D */ iv_dead);")
  out <- tables_migrate(root, evidence = FALSE)
  env <- new.env()
  eval(parse(text = tables_region(out, "dc-tables-config")), env)
  expect_identical(env$GROUPS, list(D = c("age", "iv_dead"), P = "bmi"))
  expect_identical(env$CONTINUOUS, c("age", "bmi", "iv_dead"))
  for (source in c(
    "%desc_tab(vartype=continuous,input=built,varlist=/* D */ age /* P */ age);",
    "%desc_tab(vartype=continuous,input=built,varlist=age /* D */ bmi);",
    "%desc_tab(vartype=continuous,input=built,varlist=/* D */ age--bmi);",
    "%desc_tab(vartype=other,input=built,varlist=/* D */ age);",
    "data x; run;"
  )) {
    root <- migration_study_fixture("dc-tables")
    tables_source(root, source)
    expect_error(tables_migrate(root, evidence = FALSE), "group|variable|vartype|desc_tab")
    expect_false(file.exists(file.path(root, "descriptive", "dc.tables.cohort.eda.qmd")))
  }
  for (second in c(
    "%desc_tab(vartype=category,input=built,varlist=/* D */ age);",
    "%desc_tab(vartype=continuous,input=complete_cases,varlist=/* D */ bmi);"
    # An overall call beside a by-group one is the ODS template's own shape and
    # migrates; see "the overall and by-group calls of tp.dc.tables.ods.sas".
  )) {
    root <- migration_study_fixture("dc-tables")
    tables_source(root, c("%desc_tab(vartype=continuous,input=built,varlist=/* D */ age);", second))
    expect_error(tables_migrate(root, evidence = FALSE), "conflict|same")
  }
})

test_that("dc-tables reports an empty RTF reference without failing migration", {
  root <- migration_study_fixture("dc-tables")
  writeLines(character(), file.path(root, "documents", "general.rtf"))
  out <- tables_migrate(root)
  report <- paste(readLines(sub("[.]qmd$", "-migration.md", out)), collapse = "\n")
  expect_match(report, "Empty RTF reference", fixed = TRUE)
})

test_that("slashes in group headings do not become table variables", {
  root <- migration_study_fixture("dc-tables")
  tables_source(root, "%desc_tab(vartype=continuous,input=built,varlist=/* Height/Weight */ age);")
  out <- tables_migrate(root, evidence = FALSE)
  env <- new.env()
  eval(parse(text = tables_region(out, "dc-tables-config")), env)
  expect_identical(env$GROUPS, list(`Height/Weight` = "age"))
  expect_identical(env$CONTINUOUS, "age")
})

test_that("dc-tables retains complete title statements and their starting lines", {
  root <- migration_study_fixture("dc-tables")
  source <- c(
    "options nodate; title3",
    '  "General; Descriptive Analyses"',
    '  "continued title text";',
    'footnote "Evidence only"; TiTlE4 "Same-line title";',
    'title5 "A ""quoted; phrase"" remains intact"; title6 "Second title";',
    '* title7 "Not active";',
    '/* title8 "Not active either"; */',
    "%desc_tab(vartype=continuous,input=built,varlist=/* Demography */ age);"
  )
  tables_source(root, source)
  evidence <- hvtiRtemplates:::.migration_evidence(
    c(source = file.path(root, "descriptive", "dc.tables.sas")), normalizePath(root)
  )
  result <- hvtiRtemplates:::.migrate_dc_tables(evidence, readLines(template_path("dc", "tables")))
  titles <- result$unresolved[result$unresolved$reason == "Review title against MANUSCRIPT_CAPTION, the Word table's caption.", ]
  expect_identical(titles$line, c(1L, 4L, 5L, 5L))
  expect_identical(titles$text, c(
    'title3\n  "General; Descriptive Analyses"\n  "continued title text";',
    'TiTlE4 "Same-line title";',
    'title5 "A ""quoted; phrase"" remains intact";',
    'title6 "Second title";'
  ))
  out <- tables_migrate(root, evidence = FALSE)
  report <- paste(readLines(sub("[.]qmd$", "-migration.md", out)), collapse = "\n")
  # The report keeps each title statement's shape and masks its text.
  expect_match(report, 'line=1; text=title3\n  "[string]"\n  "[string]";', fixed = TRUE)
  expect_match(report, 'line=4; text=TiTlE4 "[string]";', fixed = TRUE)
  expect_false(grepl("Descriptive Analyses|Same-line title", report))
})

# ---- what %desc_tab printed ---------------------------------------------------

tables_config <- function(lines) {
  root <- migration_study_fixture("dc-tables")  # nolint: object_usage_linter.
  tables_source(root, lines)
  out <- tables_migrate(root, evidence = FALSE)
  env <- new.env()
  eval(parse(text = tables_region(out, "dc-tables-config")), env)
  report <- readLines(sub("[.]qmd$", "-migration.md", out))
  list(env = env, report = report,
       unresolved = report[seq.int(match("## Unresolved", report), length(report))],
       translated = report[seq.int(match("## Translated", report), match("## Unresolved", report) - 1L)])
}

test_that("a job with no group compares nothing, and a category-only job keeps the median default", {
  got <- tables_config("%desc_tab(vartype=category,input=built,by=,varlist=/* Demography */ female);")
  expect_identical(got$env$COMPARE, "none")
  expect_identical(got$env$CONTINUOUS_STAT, "median")
})

test_that("perctile= sets PERCENTILES when every call agrees on a median-centered triple", {
  got <- tables_config(c(
    "%desc_tab(vartype=continuous,input=built,by=treatment,perctile=10 50 90,varlist=/* Demography */ age);",
    "%desc_tab(vartype=continuous,input=built,by=treatment,perctile=10 50 90,varlist=/* Follow-up */ iv_dead);"
  ))
  expect_identical(got$env$PERCENTILES, c(10, 90))
  expect_true(any(grepl("perctile=10 50 90", got$translated, fixed = TRUE)))
  expect_false(any(grepl("perctile=", got$unresolved, fixed = TRUE)))
})

test_that("perctile= that cannot be expressed keeps the default and is left for review", {
  for (lines in list(
    c("%desc_tab(vartype=continuous,input=built,by=treatment,perctile=10 50 90,varlist=/* Demography */ age);",
      "%desc_tab(vartype=continuous,input=built,by=treatment,perctile=25 50 75,varlist=/* Follow-up */ iv_dead);"),
    "%desc_tab(vartype=continuous,input=built,by=treatment,perctile=25 75,varlist=/* Demography */ age);",
    "%desc_tab(vartype=continuous,input=built,by=treatment,perctile=25 40 75,varlist=/* Demography */ age);"
  )) {
    got <- tables_config(lines)
    expect_identical(got$env$PERCENTILES, c(15, 85), info = lines[[1L]])
    expect_true(any(grepl("perctile=", got$unresolved, fixed = TRUE)), info = lines[[1L]])
  }
})

test_that("exposure=0 is left unresolved, and exposure=1 is the table dc-tables draws", {
  zero <- tables_config("%desc_tab(vartype=category,input=built,by=treatment,exposure=0,varlist=/* Demography */ female);")
  expect_true(any(grepl("exposure=0", zero$unresolved, fixed = TRUE) & grepl("outcome", zero$unresolved)))
  one <- tables_config("%desc_tab(vartype=category,input=built,by=treatment,exposure=1,varlist=/* Demography */ female);")
  expect_false(any(grepl("exposure=", one$unresolved, fixed = TRUE)))
})

test_that("the report says %desc_tab's percentiles used PCTLDEF=4", {
  got <- tables_config("%desc_tab(vartype=continuous,input=built,by=treatment,varlist=/* Demography */ age);")
  expect_true(any(grepl("PCTLDEF=4", got$unresolved, fixed = TRUE)))
  none <- tables_config("%desc_tab(vartype=category,input=built,by=treatment,varlist=/* Demography */ female);")
  expect_false(any(grepl("PCTLDEF", none$unresolved, fixed = TRUE)))
})

test_that("a blank exposure= or perctile= takes %desc_tab's default", {
  got <- tables_config(
    "%desc_tab(vartype=continuous,input=built,by=treatment,exposure=,perctile=,varlist=/* Demography */ age);"
  )
  expect_false(any(grepl("exposure=", got$unresolved, fixed = TRUE)))
  expect_false(any(grepl("perctile=", got$unresolved, fixed = TRUE)))
  expect_identical(got$env$PERCENTILES, c(15, 85))
})

test_that("a by-group job with categorical rows reports the Fisher difference", {
  got <- tables_config("%desc_tab(vartype=category,input=built,by=treatment,varlist=/* Demography */ female);")
  expect_true(any(grepl("chi-square", got$unresolved, fixed = TRUE) & grepl("Fisher", got$unresolved, fixed = TRUE)))
  none <- tables_config("%desc_tab(vartype=category,input=built,by=,varlist=/* Demography */ female);")
  expect_false(any(grepl("Fisher", none$unresolved, fixed = TRUE)))
})

test_that("a by-group job with continuous rows reports the Kruskal-Wallis difference", {
  got <- tables_config("%desc_tab(vartype=continuous,input=built,by=treatment,varlist=/* Demography */ age);")
  expect_true(any(grepl("Kruskal-Wallis", got$unresolved, fixed = TRUE) & grepl("Wilcoxon", got$unresolved, fixed = TRUE)))
  none <- tables_config("%desc_tab(vartype=continuous,input=built,by=,varlist=/* Demography */ age);")
  expect_false(any(grepl("Kruskal-Wallis", none$unresolved, fixed = TRUE)))
  categorical <- tables_config("%desc_tab(vartype=category,input=built,by=treatment,varlist=/* Demography */ female);")
  expect_false(any(grepl("Kruskal-Wallis", categorical$unresolved, fixed = TRUE)))
})

# ---- the template's own shape: each table overall and by group ----------------

test_that("the overall and by-group calls of tp.dc.tables.ods.sas migrate to one table", {
  root <- migration_study_fixture("dc-tables")  # nolint: object_usage_linter.
  file.copy(file.path(root, "descriptive", "dc.tables.ods.sas"),
            file.path(root, "descriptive", "dc.tables.sas"), overwrite = TRUE)
  out <- tables_migrate(root, evidence = FALSE)
  env <- new.env()
  eval(parse(text = tables_region(out, "dc-tables-config")), env)
  expect_identical(env$BY, "treatment")
  expect_identical(env$COMPARE, "pvalue")
  expect_identical(env$CONTINUOUS_STAT, "both")
  expect_identical(env$MANUSCRIPT_LAYOUT, "describe")
  expect_identical(env$PERCENTILES, c(15, 85))
  expect_identical(env$GROUPS, list(
    Demography = c("female", "race_grp", "age", "bmi"),
    Procedure = "repair", `Follow-up` = "iv_dead"
  ))
  report <- readLines(sub("[.]qmd$", "-migration.md", out))
  translated <- report[seq.int(match("## Translated", report), match("## Unresolved", report) - 1L)]
  expect_true(any(grepl("Overall column", translated, fixed = TRUE)))
})

test_that("calls naming two different groups still stop", {
  root <- migration_study_fixture("dc-tables")  # nolint: object_usage_linter.
  tables_source(root, c(
    "%desc_tab(vartype=category,input=built,by=treatment,varlist=/* Demography */ female);",
    "%desc_tab(vartype=category,input=built,by=repair,varlist=/* Demography */ female);"
  ))
  expect_error(tables_migrate(root, evidence = FALSE), "same input and one group")
})

test_that("an overall call beside a group with missing values is not reported as the Overall column", {
  root <- migration_study_fixture("dc-tables")  # nolint: object_usage_linter.
  built_path <- file.path(root, "datasets", "built.csv")
  built <- utils::read.csv(built_path)
  built$treatment[c(3L, 8L)] <- NA
  utils::write.csv(built, built_path, row.names = FALSE)
  withr::with_dir(root, suppressWarnings(suppressMessages(hvtiRutilities::update_manifest())))
  file.copy(file.path(root, "descriptive", "dc.tables.ods.sas"),
            file.path(root, "descriptive", "dc.tables.sas"), overwrite = TRUE)
  out <- tables_migrate(root, evidence = FALSE)
  report <- readLines(sub("[.]qmd$", "-migration.md", out))
  translated <- report[seq.int(match("## Translated", report), match("## Unresolved", report) - 1L)]
  unresolved <- report[seq.int(match("## Unresolved", report), length(report))]
  # SAS's overall calls counted the 2 patients with no treatment; the R table's
  # Overall column leaves them out, so the two are not the same table.
  expect_false(any(grepl("Overall column", translated, fixed = TRUE)))
  expect_true(any(grepl("treatment", unresolved, fixed = TRUE) & grepl("2 ", unresolved, fixed = TRUE) &
                    grepl("Overall", unresolved, fixed = TRUE)))
})

test_that("the group variable summarized in an overall call is taken out of GROUPS", {
  got <- tables_config(c(
    "%desc_tab(vartype=category,input=built,by=,varlist=/* Demography */ treatment female);",
    "%desc_tab(vartype=category,input=built,by=treatment,varlist=/* Demography */ female);"
  ))
  expect_identical(got$env$BY, "treatment")
  expect_identical(got$env$GROUPS, list(Demography = "female"))
  expect_false("treatment" %in% c(got$env$BINARY, got$env$CATEGORICAL, got$env$CONTINUOUS))
  expect_true(any(grepl("treatment", got$translated, fixed = TRUE) & grepl("column header", got$translated, fixed = TRUE)))
})

# ---- the Word table's layout --------------------------------------------------

test_that("a migrated job lays its Word table out by what %desc_tab printed", {
  # Mean +/- SD beside the percentiles is two statistics per group, which only
  # the describe layout draws; hv_man_table() refuses it in the compare layout.
  both <- tables_config("%desc_tab(vartype=continuous,input=built,by=treatment,varlist=/* Demography */ age);")
  expect_identical(both$env$CONTINUOUS_STAT, "both")
  expect_identical(both$env$MANUSCRIPT_LAYOUT, "describe")
  expect_true(any(grepl("MANUSCRIPT_LAYOUT: describe", both$translated, fixed = TRUE)))
  # One statistic per variable, by group or overall: the compare layout.
  by_group <- tables_config("%desc_tab(vartype=category,input=built,by=treatment,varlist=/* Demography */ female);")
  expect_identical(by_group$env$MANUSCRIPT_LAYOUT, "compare")
  expect_true(any(grepl("MANUSCRIPT_LAYOUT: compare", by_group$translated, fixed = TRUE)))
  expect_true(any(grepl("beside the groups", by_group$translated, fixed = TRUE)))
  overall <- tables_config("%desc_tab(vartype=category,input=built,by=,varlist=/* Demography */ female);")
  expect_identical(overall$env$MANUSCRIPT_LAYOUT, "compare")
  # No by= means no groups, so the reason must not talk about them.
  expect_true(any(grepl("for the whole cohort", overall$translated, fixed = TRUE)))
  expect_false(any(grepl("beside the groups", overall$translated, fixed = TRUE)))
  # The rule is the statistic, not the grouping: continuous rows with no by= are
  # still mean +/- SD beside the percentiles, so they still need describe.
  overall_continuous <- tables_config("%desc_tab(vartype=continuous,input=built,by=,varlist=/* Demography */ age);")
  expect_identical(overall_continuous$env$CONTINUOUS_STAT, "both")
  expect_identical(overall_continuous$env$MANUSCRIPT_LAYOUT, "describe")
})

test_that("the Word table is drawn in the manuscript style, under the study's caption, fill and layout", {
  skip_on_cran()
  root <- migration_study_fixture("dc-tables")
  template <- template_path("dc", "tables")
  env <- new.env()
  env$.root <- root
  env$SUBJECT <- "cohort"
  env$TYPE <- "eda"
  env$study_dir <- hvtiRutilities::study_dir
  env$d <- hvtiRutilities::read_built(hvtiRutilities::study_config(root))
  env$GROUPS <- list(Demography = c("age", "female", "race_grp"), Procedure = "repair")
  env$BY <- "treatment"
  env$CONTINUOUS <- "age"
  env$BINARY <- c("female", "repair")
  env$CATEGORICAL <- "race_grp"
  env$COMPARE <- "pvalue"
  env$CONTINUOUS_STAT <- "median"
  env$PERCENTILES <- c(15, 85)
  env$ABBREVIATIONS <- character(0)
  env$WORD_FILE <- "dc-tables.docx"
  env$OVERRIDES <- list()
  env$MEAN_SD <- env$ORDINAL <- character(0)
  env$STDDIFF <- FALSE
  env$GROUP_1 <- NULL
  env$SHOW_VARIABLE <- TRUE
  env$MANUSCRIPT_LAYOUT <- "compare"
  env$MANUSCRIPT_CAPTION <- "Table 2. Operative details"
  env$MANUSCRIPT_FILL <- "#A5C9EB"
  env$TABLE_ORIENTATION <- "landscape"
  eval(tables_chunk(template, "helpers"), env)
  invisible(eval(tables_chunk(template, "tbl-table"), env))
  invisible(eval(tables_chunk(template, "word-file"), env))
  word <- file.path(root, "documents", "cohort-eda", "dc-tables.docx")
  # The report keeps the Variable column; the Word table never has it.
  expect_true("hv_variable" %in% env$ft$col_keys)
  expect_false("hv_variable" %in% env$word_ft$col_keys)
  expect_identical(attr(env$ft, "hv_style")$name, "report")
  expect_identical(attr(env$word_ft, "hv_style")$name, "manuscript")
  expect_identical(nrow(hvtiRtables::hv_check_docx(word, style = "manuscript")), 0L)
  doc <- officer::docx_summary(officer::read_docx(word))
  expect_identical(doc$text[doc$content_type == "paragraph"][[1L]], "Table 2. Operative details")
  cells <- doc[doc$content_type == "table cell", ]
  expect_identical(cells$text[cells$row_id == 1L][1:2], c("Characteristic", "n*"))
  expect_false(any(cells$text == "Variable"))
  xml <- xml2::read_xml(unzip(word, "word/document.xml", exdir = withr::local_tempdir()))
  fills <- xml2::xml_attr(xml2::xml_find_all(xml, "//w:tc/w:tcPr/w:shd", xml2::xml_ns(xml)), "fill")
  expect_true("A5C9EB" %in% fills)
  expect_false("CAEDFB" %in% fills)
  # TABLE_ORIENTATION reaches the page: this narrow table would stay portrait on "auto".
  page <- xml2::xml_find_first(xml, "//w:sectPr/w:pgSz", xml2::xml_ns(xml))
  expect_identical(xml2::xml_attr(page, "orient"), "landscape")
  # The describe layout draws both statistics, with a count beside each group.
  env$CONTINUOUS_STAT <- "both"
  env$MANUSCRIPT_LAYOUT <- "describe"
  invisible(eval(tables_chunk(template, "tbl-table"), env))
  invisible(eval(tables_chunk(template, "word-file"), env))
  cells <- officer::docx_summary(officer::read_docx(word))
  cells <- cells[cells$content_type == "table cell" & cells$row_id == 2L, ]
  expect_gt(sum(cells$text == "n*"), 1L)
  expect_identical(nrow(hvtiRtables::hv_check_docx(word, style = "manuscript")), 0L)
  # A manuscript table is never saved without its caption.
  env$MANUSCRIPT_CAPTION <- NULL
  expect_error(eval(tables_chunk(template, "word-file"), env), "needs `caption`", fixed = TRUE)
})
