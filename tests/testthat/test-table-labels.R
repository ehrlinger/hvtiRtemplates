# The dc-tables label layer: the labels and levels a table prints in place of
# the dataset's, and the build stamp the Word file carries. The labels are a
# mitral study table's, as its 2026-10-23 render printed them.

rules <- function(label, ...) hvtiRtemplates:::.table_label_rules(label, ...)

test_that("each rule tidies the analysis label it was written for", {
  expect_identical(rules("Preoperative MR grade")$label, "MR grade")
  expect_identical(rules("Pre-op NYHA class", protect = "NYHA")$label, "NYHA class")
  expect_identical(rules("Preop: creatinine")$label, "Creatinine")
  expect_identical(rules("Surgical approach (incision use for analysis)")$label, "Surgical approach")
  expect_identical(rules("Diabetes (Y/N)")$label, "Diabetes")
  expect_identical(rules("Diabetes 0/1")$label, "Diabetes")
  expect_identical(rules("MV leaflet Repair: Triangular resection (for analysis)")$label,
                   "MV leaflet repair: triangular resection")
  expect_identical(rules("Body mass index (kg/m2)")$label, "Body mass index (kg/m^2^)")
  expect_identical(rules("Preoperative MR grade")$rules, "preoperative")
  expect_identical(rules("Pre-op NYHA class (0/1)", protect = "NYHA")$rules, c("preoperative", "coding"))
})

test_that("a rule never empties a label or touches a word that only starts like one", {
  expect_identical(rules("Preoperative")$label, "Preoperative")
  expect_identical(rules("Preoperative")$rules, character(0))
  expect_identical(rules("Preoperation count")$label, "Preoperation count")
  expect_identical(rules("BSA (m2)")$label, "BSA (m2)")
  expect_identical(rules("Index (kg/m^2^)")$label, "Index (kg/m^2^)")
})

test_that("sentence case keeps acronyms and the study's abbreviations", {
  expect_identical(rules("Surgical Procedure: Congenital ASD/PFO suture closure")$label,
                   "Surgical procedure: congenital ASD/PFO suture closure")
  expect_identical(rules("eGFR at Discharge")$label, "eGFR at discharge")
  # Written wholly in capitals, a label says nothing about its acronyms, so only
  # the protected list keeps one.
  expect_identical(rules("TOTAL CPB TIME", protect = "CPB")$label, "Total CPB time")
  expect_identical(rules("TOTAL CPB TIME")$label, "Total cpb time")
  # A protected abbreviation is restored to its own spelling.
  expect_identical(rules("Nyha class I", protect = "NYHA")$label, "NYHA class I")
})

test_that("an abbreviation never changes a word's meaning or claims an ordinary word", {
  # AVR (replacement) and AVr (repair) may both be in a study's list.
  expect_identical(rules("Prior AVR", protect = c("AVr", "AVR"))$label, "Prior AVR")
  expect_identical(rules("Prior AVr", protect = c("AVR", "AVr"))$label, "Prior AVr")
  # A lower-case word is a word: "as" is not AS (aortic stenosis).
  expect_identical(rules("Valve as replaced", protect = "AS")$label, "Valve as replaced")
  expect_identical(rules("Preop. creatinine")$label, "Creatinine")
})

test_that("each rule can be turned off by leaving it out", {
  label <- "Preoperative Body Mass Index (kg/m2) (Y/N)"
  expect_identical(rules(label, use = character(0))$label, label)
  expect_identical(rules(label, use = "units")$label, "Preoperative Body Mass Index (kg/m^2^) (Y/N)")
  expect_identical(rules(label, use = c("preoperative", "coding"))$label, "Body Mass Index (kg/m2)")
  expect_identical(rules(label)$label, "Body mass index (kg/m^2^)")
})

label_study <- function(.local_envir = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = .local_envir)
  d <- data.frame(
    approach = c(1, 2, 3, 4, 1, 2),
    tri = c(0, 1, 9, 0, 1, 0),
    nyha = c(1, 2, 2, 3, 1, 2),
    bmi = c(25, 31, 28, 22, 27, 30),
    iabp = c(0, 0, 1, 0, 0, 0),
    analysis_only = c(1, 2, 3, 4, 5, 6)
  )
  attr(d$approach, "label") <- "Surgical approach (incision use for analysis)"
  attr(d$tri, "label") <- "MV leaflet Repair: Triangular resection (for analysis)"
  attr(d$nyha, "label") <- "Preoperative NYHA class"
  attr(d$bmi, "label") <- "Body mass index (kg/m2)"
  attr(d$analysis_only, "label") <- "Preoperative Not In The Table"
  # A study's files name variables this table does not show; that is not an error.
  writeLines(c("approach:", "  1: Full sternotomy", "  2: Partial sternotomy", "  3: Thoracotomy", "  4: Robotic",
               "tri:", "  0: \"No\"", "  1: \"Yes\"", "  9: Unknown",
               "nyha:", "  1: I", "  2: II", "  3: III", "  4: IV",
               "other_study_var:", "  1: One"), file.path(root, "value_labels.yml"))
  writeLines(c("tri: \"Triangular resection\"", "unshown: \"Not in this table\""), file.path(root, "table_labels.yml"))
  list(root = root, d = d)
}

test_that("the study files and the rules relabel only the table's columns, and say what they changed", {
  s <- label_study()
  vars <- c("approach", "tri", "nyha", "bmi", "iabp")
  expect_no_warning(out <- hvtiRtemplates:::.table_labels(s$d, vars, s$root, protect = "NYHA"))
  d <- out$data
  # Levels: in code order, only the codes the data hold (NYHA IV is declared and unseen).
  expect_identical(levels(d$approach), c("Full sternotomy", "Partial sternotomy", "Thoracotomy", "Robotic"))
  expect_identical(levels(d$tri), c("No", "Yes", "Unknown"))
  expect_identical(levels(d$nyha), c("I", "II", "III"))
  expect_identical(as.character(d$nyha), c("I", "II", "II", "III", "I", "II"))
  # Labels: table_labels.yml wins over the rules; the rules tidy the rest.
  expect_identical(attr(d$tri, "label"), "Triangular resection")
  expect_identical(attr(d$approach, "label"), "Surgical approach")
  expect_identical(attr(d$nyha, "label"), "NYHA class")
  expect_identical(attr(d$bmi, "label"), "Body mass index (kg/m^2^)")
  # A column the table does not show is left exactly as read.
  expect_identical(d$analysis_only, s$d$analysis_only)
  ch <- out$changes
  expect_identical(names(ch), c("variable", "from", "to", "rule"))
  expect_identical(ch$rule[ch$variable == "tri" & grepl("^levels", ch$to)], "value_labels.yml")
  expect_identical(ch$to[ch$variable == "tri" & !grepl("^levels", ch$to)], "Triangular resection")
  expect_identical(ch$rule[ch$variable == "tri" & !grepl("^levels", ch$to)], "table_labels.yml")
  expect_identical(ch$rule[ch$variable == "nyha" & !grepl("^levels", ch$to)], "preoperative")
  expect_identical(ch$from[ch$variable == "nyha" & grepl("^levels", ch$to)], "levels 1, 2, 3")
  # A column with no label is named, so the table's column name does not go unnoticed.
  expect_match(ch$rule[ch$variable == "iabp"], "no label", fixed = TRUE)
  expect_false(any(ch$variable == "analysis_only"))
})

test_that("an unquoted No or Yes in value_labels.yml is level text, not a logical", {
  root <- withr::local_tempdir()
  writeLines(c("f:", "  0: No", "  1: Yes"), file.path(root, "value_labels.yml"))
  out <- hvtiRtemplates:::.table_labels(data.frame(f = c(0, 1, 1)), "f", root)
  expect_identical(levels(out$data$f), c("No", "Yes"))
  expect_identical(out$levels$f, c(`0` = "No", `1` = "Yes"))
})

test_that("two codes may share one text, and the map names each code", {
  root <- withr::local_tempdir()
  writeLines(c("disp:", "  1: Home", "  8: Unknown", "  9: Unknown"), file.path(root, "value_labels.yml"))
  out <- hvtiRtemplates:::.table_labels(data.frame(disp = c(1, 8, 9, 1)), "disp", root)
  expect_identical(levels(out$data$disp), c("Home", "Unknown"))
  expect_identical(as.character(out$data$disp), c("Home", "Unknown", "Unknown", "Home"))
  expect_identical(out$levels$disp, c(`1` = "Home", `8` = "Unknown", `9` = "Unknown"))
  expect_null(attr(out$data$disp, "codes"))
  # A partial mapping whose text matches a code left undeclared.
  writeLines(c("disp:", "  1: \"8\""), file.path(root, "value_labels.yml"))
  out <- hvtiRtemplates:::.table_labels(data.frame(disp = c(1, 8)), "disp", root)
  expect_identical(out$levels$disp, c(`1` = "8", `8` = "8"))
})

test_that("a column summarized as a number keeps its codes", {
  s <- label_study()
  out <- hvtiRtemplates:::.table_labels(s$d, c("nyha", "tri"), s$root, keep_codes = "nyha")
  expect_true(is.numeric(out$data$nyha))
  expect_null(out$levels$nyha)
  expect_identical(levels(out$data$tri), c("No", "Yes", "Unknown"))
})

test_that("rules = FALSE leaves every label but the declared ones as read", {
  s <- label_study()
  out <- hvtiRtemplates:::.table_labels(s$d, c("tri", "nyha", "bmi"), s$root, rules = FALSE)
  expect_identical(attr(out$data$nyha, "label"), "Preoperative NYHA class")
  expect_identical(attr(out$data$bmi, "label"), "Body mass index (kg/m2)")
  expect_identical(attr(out$data$tri, "label"), "Triangular resection")
  expect_identical(levels(out$data$nyha), c("I", "II", "III"))
})

test_that("a study with neither file gets the rules alone, and a bad choice or file is refused", {
  s <- label_study()
  unlink(file.path(s$root, c("value_labels.yml", "table_labels.yml")))
  out <- hvtiRtemplates:::.table_labels(s$d, c("tri", "bmi"), s$root)
  expect_identical(out$data$tri, {
    x <- s$d$tri
    attr(x, "label") <- "MV leaflet repair: triangular resection"
    x
  })
  expect_error(hvtiRtemplates:::.table_labels(s$d, "bmi", s$root, rules = "spelling"), "TABLE_LABEL_RULES")
  expect_error(hvtiRtemplates:::.table_labels(s$d, "bmi", s$root, rules = NA), "TABLE_LABEL_RULES")
  writeLines("- just a list", file.path(s$root, "table_labels.yml"))
  expect_error(hvtiRtemplates:::.table_labels(s$d, "bmi", s$root), "table_labels.yml must map")
  writeLines("bmi: [one, two]", file.path(s$root, "table_labels.yml"))
  expect_error(hvtiRtemplates:::.table_labels(s$d, "bmi", s$root), "one label as text")
})

test_that("value labels a column already carries are used, not overwritten by the study file", {
  s <- label_study()
  x <- s$d$nyha
  attr(x, "labels") <- c(Mild = 1, Moderate = 2, Severe = 3)
  s$d$nyha <- x
  expect_no_warning(out <- hvtiRtemplates:::.table_labels(s$d, "nyha", s$root))
  expect_identical(levels(out$data$nyha), c("Mild", "Moderate", "Severe"))
  expect_match(out$changes$rule[grepl("^levels", out$changes$to)], "carried by the data")
})

test_that("the saved Word table says which job, render and releases built it", {
  skip_if_not_installed("officer")
  path <- withr::local_tempfile(fileext = ".docx")
  print(officer::read_docx(), target = path)
  run <- list(started = as.POSIXct("2026-10-24 09:00:00", tz = "UTC"), file = "cohort.eda.dc.tables.qmd",
              state = "final", user = "someone", user_name = "Some One")
  data <- list(list(dataset = "study", path = "datasets/built.parquet", sha256 = strrep("ab", 32L)))
  hvtiRtemplates:::.stamp_docx(path, run, data, caption = "Table 1. Patient characteristics")
  props <- officer::doc_properties(officer::read_docx(path))
  value <- function(tag) props$value[props$tag == tag]
  expect_identical(value("title"), "Table 1. Patient characteristics")
  expect_identical(value("subject"), "cohort.eda.dc.tables.qmd")
  expect_identical(value("creator"), "Some One")
  expect_match(value("description"), "cohort.eda.dc.tables.qmd (final render)", fixed = TRUE)
  expect_match(value("description"), paste0("hvtiRtemplates ", utils::packageVersion("hvtiRtemplates")), fixed = TRUE)
  expect_match(value("description"), "datasets/built.parquet sha256 abababababab", fixed = TRUE)
  expect_identical(value("hvti_job"), "cohort.eda.dc.tables.qmd")
  expect_identical(value("hvti_status"), "final")
  expect_match(value("hvti_hvtiRtemplates"), as.character(utils::packageVersion("hvtiRtemplates")), fixed = TRUE)
  expect_identical(value("hvti_officer"), as.character(utils::packageVersion("officer")))
})

test_that("the saved Word table reads draft when the run turned draft after setup", {
  skip_if_not_installed("officer")
  # dc-tables stamps the reconciled run, not the record the box printed at setup:
  # a working read found later (.run_mark_draft()) must reach the Word file too.
  tpl <- readLines(system.file("templates", "10_descriptive", "dc-tables.qmd", package = "hvtiRtemplates"))
  expect_true(any(grepl(".stamp_docx(word_path, hvtiRtemplates:::.run_reconcile(.job$run),", tpl, fixed = TRUE)))
  old <- list(reasons = .run_state$draft_reasons, points = .partial_state$points)
  withr::defer({
    .run_state$draft_reasons <- old$reasons
    .partial_state$points <- old$points
  })
  .run_state$draft_reasons <- character()
  .partial_state$points <- list()
  run <- list(started = as.POSIXct("2026-10-24 09:00:00", tz = "UTC"), file = "cohort.eda.dc.tables.qmd",
              state = "final", markers = 0L, skipped = 0L, stopped = FALSE)
  .run_mark_draft("it read the working built.csv, which is unregistered")
  path <- withr::local_tempfile(fileext = ".docx")
  print(officer::read_docx(), target = path)
  hvtiRtemplates:::.stamp_docx(path, .run_reconcile(run))
  props <- officer::doc_properties(officer::read_docx(path))
  expect_identical(props$value[props$tag == "hvti_status"], "draft")
  expect_match(props$value[props$tag == "description"], "(draft render)", fixed = TRUE)
})
