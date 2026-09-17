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
    "%desc_tab(vartype=continuous,input=built,by=,",
    "          varlist=/* Demography */ age);"
  ))
  out <- tables_migrate(root, evidence = FALSE)
  env <- new.env()
  eval(parse(text = c(tables_region(out, "dc-tables-data"), tables_region(out, "dc-tables-config"))), env)
  expect_true(is.na(env$DATASET))
  expect_identical(env$CONTINUOUS, character())
  expect_true(any(grepl("EDIT:.*source.*logic", readLines(out))))
  report <- readLines(sub("[.]qmd$", "-migration.md", out))
  translated <- report[seq.int(match("## Translated", report), match("## Unresolved", report) - 1L)]
  expect_false(any(grepl("input=built|continuous: age", translated)))
  expect_true(any(grepl("line=1; text=if female=1;", report, fixed = TRUE)))
  expect_true(any(grepl("line=1; text=age=age+10;", report, fixed = TRUE)))
})

test_that("dc-tables migrates desc_tab groups and types", {
  root <- migration_study_fixture("dc-tables")
  out <- tables_migrate(root)
  txt <- readLines(out, warn = FALSE)
  for (line in c(
    'DATASET <- "study"', "ANALYSIS_SET <- NULL", 'BY <- "treatment"',
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
  expect_identical(env$COMPARE, "none")
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
    root, built = "categorical.csv", event = "dead", time = "iv_dead",
    dataset = "categorical", role = "named", population = "Synthetic categorical fixture"
  ))
  out <- tables_migrate(root)
  expect_true('DATASET <- "categorical"' %in% readLines(out))
  env <- new.env()
  eval(parse(text = tables_region(out, "dc-tables-config")), env)
  expect_identical(env$BINARY, "repair")
  expect_identical(env$CATEGORICAL, c("female", "race_grp"))
})

tables_chunk <- function(job, label) {
  lines <- readLines(job, warn = FALSE)
  start <- match(paste0("#| label: ", label), lines)
  end <- start + match("```", lines[-seq_len(start)])
  parse(text = lines[seq.int(start + 1L, end - 1L)])
}

test_that("dc-tables refuses a set cut from another dataset and reads a named registered dataset", {
  root <- migration_study_fixture("dc-tables")
  template <- template_path("dc", "tables")
  env <- new.env()
  env$.root <- root
  env$read_built <- hvtiRutilities::read_built
  env$study_config <- hvtiRutilities::study_config
  code <- tables_chunk(template, "data")
  assign <- vapply(code, function(x) {
    is.call(x) && identical(x[[1L]], quote(`<-`)) && as.character(x[[2L]]) %in% c("DATASET", "ANALYSIS_SET")
  }, logical(1))
  code <- code[!assign]
  withr::local_dir(root)
  env$DATASET <- "complete_cases"
  env$ANALYSIS_SET <- "eda"
  expect_error(eval(code, env), "written from the study dataset")
  env$ANALYSIS_SET <- NULL
  capture.output(eval(code, env))
  expect_equal(nrow(env$d), 24L)
})

test_that("migrated dc-tables writes an editable structurally clean document in the logical documents folder", {
  root <- migration_study_fixture("dc-tables")
  out <- tables_migrate(root)
  env <- new.env()
  env$.root <- root
  env$ENDPOINT <- "cohort"
  env$TYPE <- "eda"
  env$OVERRIDES <- list()
  env$study_dir <- hvtiRutilities::study_dir
  env$d <- hvtiRutilities::read_built(hvtiRutilities::study_config(root))
  eval(parse(text = tables_region(out, "dc-tables-config")), env)
  eval(tables_chunk(out, "helpers"), env)
  invisible(eval(tables_chunk(out, "table"), env))
  word <- file.path(root, "documents", "cohort-eda", "dc-tables.docx")
  expect_true(file.exists(word))
  expect_equal(nrow(hvtiRtables::hv_check_docx(word)), 0L)
  doc <- officer::docx_summary(officer::read_docx(word))
  expect_true(any(doc$content_type == "table cell"))
  expect_true(any(grepl("Demography", doc$text, fixed = TRUE)))
  env$BINARY <- c("female", "repair", "age")
  expect_error(eval(tables_chunk(out, "table"), env), "exactly one explicit bucket")
  env$BINARY <- NULL
  expect_error(eval(tables_chunk(out, "table"), env), "all three buckets")
  env$BINARY <- c("female", "repair")
  env$WORD_FILE <- "../escape.docx"
  expect_error(invisible(eval(tables_chunk(out, "table"), env)), "plain .docx filename", fixed = TRUE)
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
  code <- tables_chunk(template_path("dc", "tables"), "table")
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
    expect_false(file.exists(file.path(root, "descriptive", "cohort-eda-dc-tables.qmd")))
  }
  for (second in c(
    "%desc_tab(vartype=category,input=built,varlist=/* D */ age);",
    "%desc_tab(vartype=continuous,input=complete_cases,varlist=/* D */ bmi);",
    "%desc_tab(vartype=continuous,input=built,varlist=/* D */ bmi,by=treatment);"
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
  titles <- result$unresolved[result$unresolved$reason == "Review title against the combined Word table.", ]
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
