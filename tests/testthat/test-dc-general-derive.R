template <- system.file(
  "templates", "10_descriptive", "dc-general.qmd",
  package = "hvtiRtemplates"
)
if (!nzchar(template)) {
  template <- testthat::test_path(
    "..", "..", "inst", "templates", "10_descriptive", "dc-general.qmd"
  )
}
template_lines <- readLines(template, warn = FALSE)
derive_label <- grep("^#\\| label: derive$", template_lines)
derive_end <- derive_label + which(template_lines[-seq_len(derive_label)] == "```")[[1L]]
derive_code <- parse(text = template_lines[(derive_label + 1L):(derive_end - 1L)])

synthetic <- function() {
  data.frame(
    ccfid = 1001:1012,
    female = c(0, 1, 1, 0, NA, 1, 0, 0, 1, 1, 0, 1),
    age = c(61, 45, 70, 58, NA, 66, 52, 80, 39, 74, 69, 55),
    creat = c(1.1, 0.9, 1.4, 2.2, 1.0, NA, 0.8, 3.1, 1.2, 1.0, 1.7, 0.95),
    nyha = c("I", "II", "III", "II", "I", "IV", "II", "III", "I", "II", "II", "I")
  )
}

run_derive <- function(d = synthetic(),
                       categorical = list(Demography = c("female", "nyha")),
                       continuous = list(Demography = "age", Labs = "creat"),
                       corr_vars = c("age", "creat"),
                       id_col = NULL,
                       key_cols = "ccfid") {
  env <- list2env(
    list(
      d = d, CATEGORICAL = categorical, CONTINUOUS = continuous,
      CORR_VARS = corr_vars, ID_COL = id_col, KEY_COLS = key_cols
    ),
    parent = baseenv()
  )
  eval(derive_code, envir = env)
  env
}

test_that("extreme values carry no identifier unless ID_COL is set", {
  off <- run_derive()
  extremes <- off$cdfs$Demography$age$extremes
  expect_named(extremes, c("end", "value"))
  expect_identical(extremes$end, rep(c("lowest", "highest"), each = 5L))
  expect_identical(extremes$value, c(39, 45, 52, 55, 58, 80, 74, 70, 69, 66))
  every_name <- unlist(lapply(off$cdfs, function(g) lapply(g, function(v) lapply(v, names))))
  expect_false("ccfid" %in% every_name)

  on <- run_derive(id_col = "ccfid")
  expect_named(on$cdfs$Demography$age$extremes, c("end", "value", "ccfid"))
  expect_identical(on$cdfs$Demography$age$extremes$ccfid[[1L]], 1009L)
})

test_that("an unknown column stops and names every one", {
  expect_error(
    run_derive(
      categorical = list(Demography = c("female", "nope")),
      corr_vars = c("age", "zilch")
    ),
    "Unknown column\\(s\\): nope, zilch"
  )
})

test_that("a non-numeric continuous column stops", {
  expect_error(
    run_derive(continuous = list(Demography = c("age", "nyha"))),
    "Not numeric.*: nyha"
  )
})

test_that("contingency tables show missing values as their own level", {
  female <- run_derive()$freqs$Demography$female
  expect_identical(female$level, c("0", "1", "(missing)"))
  expect_identical(female$n, c(5L, 6L, 1L))
})

test_that("percentages are over non-missing rows, as SAS MISSPRINT computes them", {
  female <- run_derive()$freqs$Demography$female
  expect_identical(
    female$percent,
    c(round(100 * 5 / 11, 1), round(100 * 6 / 11, 1), NA_real_)
  )
})

test_that("KEY_COLS keeps identifier columns out of the overall statistics", {
  overall_vars <- run_derive()$overall_vars
  expect_false("ccfid" %in% overall_vars)
  expect_true("age" %in% overall_vars)
})

test_that("a KEY_COLS name in CATEGORICAL, CONTINUOUS or CORR_VARS stops", {
  expect_error(
    run_derive(continuous = list(Demography = c("age", "ccfid"))),
    "Key column\\(s\\) cannot be summarised: ccfid"
  )
})

test_that("CATEGORICAL and CONTINUOUS must be lists with unique, non-empty names", {
  expect_error(
    run_derive(categorical = list(c("female", "nyha"))),
    "CATEGORICAL must be a list with a unique, non-empty name for every group\\."
  )
  expect_error(
    run_derive(continuous = stats::setNames(list("age", "creat"), c("Demography", "Demography"))),
    "CONTINUOUS must be a list with a unique, non-empty name for every group\\."
  )
})

test_that("ID_COL must be NULL or a single column name", {
  expect_error(
    run_derive(id_col = c("ccfid", "age")),
    "ID_COL must be NULL or a single column name\\."
  )
})

test_that("correlations list each distinct pair once, strongest first", {
  d <- synthetic()
  d$noise <- c(5, 1, 4, 2, 3, 6, 2, 5, 1, 4, 3, 6)
  corrs <- run_derive(d = d, corr_vars = c("age", "creat", "noise", "age"))$corrs

  expect_identical(nrow(corrs), 3L)
  expect_false(any(corrs$var1 == corrs$var2))
  expect_identical(anyDuplicated(paste(pmin(corrs$var1, corrs$var2), pmax(corrs$var1, corrs$var2))), 0L)
  expect_identical(order(-abs(corrs$r)), seq_len(nrow(corrs)))

  age_creat <- corrs[corrs$var1 == "age" & corrs$var2 == "creat", ]
  ok <- stats::complete.cases(d$age, d$creat)
  expect_equal(age_creat$r, stats::cor(d$age[ok], d$creat[ok]))
  expect_identical(age_creat$n, 10L)
})

test_that("quantiles follow SAS QNTLDEF=5", {
  creat <- run_derive()$cdfs$Labs$creat
  x <- synthetic()$creat
  expect_equal(creat$quantiles$percent, c(0, 1, 5, 10, 25, 50, 75, 90, 95, 99, 100))
  expect_equal(
    creat$quantiles$value,
    unname(stats::quantile(x, creat$quantiles$percent / 100, type = 2, na.rm = TRUE))
  )
  expect_identical(creat$summary$n, 11L)
  expect_identical(creat$summary$nmiss, 1L)

  # Hand-computed under SAS QNTLDEF=5, sorted non-missing values:
  # 0.8, 0.9, 0.95, 1.0, 1.0, 1.1, 1.2, 1.4, 1.7, 2.2, 3.1
  median <- creat$quantiles$value[creat$quantiles$percent == 50]
  p25 <- creat$quantiles$value[creat$quantiles$percent == 25]
  expect_equal(median, 1.1)
  expect_equal(p25, 0.95)
})

test_that("an empty CORR_VARS skips the sweep without error", {
  corrs <- run_derive(corr_vars = character())$corrs
  expect_identical(nrow(corrs), 0L)
  expect_named(corrs, c("var1", "var2", "r", "n"))
})
