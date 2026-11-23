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
  key <- .table_key(c("eGFR", "FEV1 (L)", "NYHA class", "IV", "SBP (mmHg)", "Volume (mL)"))
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
