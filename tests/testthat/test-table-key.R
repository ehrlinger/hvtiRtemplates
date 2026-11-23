known <- function(phrase_to_abbr) {
  structure(phrase_to_abbr, expansion = names(phrase_to_abbr))
}

test_that("the key holds every study abbreviation the table prints, and no other", {
  study <- known(c("New York Heart Association" = "NYHA", "Body mass index" = "BMI",
                   "Coronary artery bypass grafting" = "CABG"))
  key <- .table_key(c("NYHA class", "III", "BMI (kg/m^2^)", "Age (y)"), study)
  expect_identical(key$key, c(BMI = "Body mass index", NYHA = "New York Heart Association"))
  expect_identical(key$missing, character(0))
})

test_that("ABBREVIATIONS adds to the key and overrides a study expansion", {
  study <- known(c("Body mass index" = "BMI"))
  key <- .table_key(c("BMI", "LVEF (%)"), study, c(LVEF = "left ventricular ejection fraction", BMI = "body mass index"))
  expect_identical(key$key, c(BMI = "body mass index", LVEF = "left ventricular ejection fraction"))
})

test_that("an abbreviation nothing expands is reported, not dropped silently", {
  key <- .table_key(c("eGFR", "FEV1 (L)", "hba1c", "NYHA class", "IV", "SBP (mmHg)", "Volume (mL)"))
  expect_identical(key$missing, c("FEV1", "NYHA", "SBP", "eGFR"))
  expect_length(key$key, 0L)
})

test_that("a word is matched whole or as its plural, and a phrase such as Std. Diff. is found", {
  study <- known(c("Aortic valve replacement" = "AVR", "Mitral valve repair" = "MVr"))
  key <- .table_key(c("Prior AVRs", "MVrX", "Std. Diff. (%)"), study, c("Std. Diff." = "standardized difference"))
  expect_identical(names(key$key), c("AVR", "Std. Diff."))
  expect_identical(key$missing, "MVrX")
})

test_that("an unnamed ABBREVIATIONS entry is an error", {
  expect_error(.table_key("CI", extra = "confidence interval"), "ABBREVIATIONS")
})

test_that("a blank or NA expansion is an error, not a silent override of the study's", {
  study <- known(c("New York Heart Association" = "NYHA"))
  expect_error(.table_key("NYHA class", study, c(NYHA = "")), "NYHA")
  expect_error(.table_key("NYHA class", study, c(NYHA = NA_character_)), "NYHA")
})

test_that("a cell's runs are joined before its words are read", {
  chunks <- data.frame(.part = c("header", "body", "body", "body", "footer"),
                       .row_id = c(1L, 1L, 1L, 2L, 1L), .col_id = c("a", "a", "a", "a", "a"),
                       txt = c("Variable", "HbA", "1c (%)", "Age", "Values are mean ± SD"))
  cells <- .table_cells_text(chunks)
  expect_identical(cells, c("Variable", "HbA1c (%)", "Age", "Values are mean ± SD"))
  key <- .table_key(cells, extra = c(HbA1c = "glycated hemoglobin", SD = "standard deviation"))
  expect_identical(key$key, c(HbA1c = "glycated hemoglobin", SD = "standard deviation"))
  expect_identical(key$missing, character(0))
})

test_that("a surname or eponym capitalized inside is not an unkeyed abbreviation", {
  key <- .table_key(c("McNemar test", "MacDonald score", "DeBakey type", "DiGeorge syndrome"))
  expect_identical(key$missing, character(0))
  # An acronym that happens to start the same way is still reported.
  expect_identical(.table_key(c("DeLVEF", "MacE2", "DaTscan"))$missing, c("DaTscan", "DeLVEF", "MacE2"))
})
