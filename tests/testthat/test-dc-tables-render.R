# dc-tables end to end with the %summarytable shape: %stddiff's difference
# beside the p-value, mean +/- SD for named variables, and the report showing
# the table that is saved to Word.

dc_tables_study <- function(.local_envir = parent.frame()) {
  root <- file.path(withr::local_tempdir(.local_envir = .local_envir), "dc-tables-study")
  suppressMessages(hvtiRutilities::study_setup(root, study = "dc-tables render", study_tracker_id = 1L))
  n <- 60L
  built <- data.frame(
    ccfid = seq_len(n),
    grp = rep(c(0L, 1L), length.out = n),
    age = 50 + (seq_len(n) * 7L) %% 31L,
    creat = round(exp(((seq_len(n) * 3L) %% 17L) / 8), 2),
    female = (seq_len(n) * 5L) %% 3L == 0L,
    nyha = 1L + (seq_len(n) * 11L) %% 4L,
    race = c("W", "B", "W", "O", "W")[1L + seq_len(n) %% 5L]
  )
  utils::write.csv(built, file.path(hvtiRutilities::study_dir("datasets", root), "built.csv"), row.names = FALSE)
  suppressWarnings(suppressMessages(hvtiRutilities::register_data(root, built = "built.csv")))
  root
}

set_choice <- function(lines, name, value) {
  at <- grep(paste0("^", name, " +<- "), lines)
  stopifnot(length(at) == 1L)
  lines[at] <- paste(name, "<-", value)
  lines
}

test_that("dc-tables renders %stddiff's difference and saves the table it shows", {
  skip_on_cran()
  skip_if_not_installed("quarto")
  skip_if_not_installed("hvtiRpropensity")
  skip_if(utils::packageVersion("hvtiRtables") < "1.0.6", "needs hvtiRtables >= 1.0.6")
  root <- dc_tables_study()
  job <- add_job("dc", "cohort", "tables", qualifier = "tables", dir = root)
  lines <- readLines(job, warn = FALSE)
  lines <- set_choice(lines, "BY", '"grp"')
  lines <- set_choice(lines, "CONTINUOUS", 'c("age", "creat")')
  lines <- set_choice(lines, "BINARY", '"female"')
  lines <- set_choice(lines, "CATEGORICAL", 'c("nyha", "race")')
  lines <- set_choice(lines, "COMPARE", '"pvalue"')
  lines <- set_choice(lines, "MEAN_SD", '"age"')
  lines <- set_choice(lines, "ORDINAL", '"nyha"')
  lines <- set_choice(lines, "STDDIFF", "TRUE")
  groups <- grep("^GROUPS <- list\\($", lines)
  lines <- c(lines[seq_len(groups)], '  Demography = c("age", "female", "race"),',
             '  Clinical = c("creat", "nyha")', ")", lines[-seq_len(groups + 3L)])
  writeLines(lines, job)

  quarto::quarto_render(job, execute_dir = dirname(job), quiet = TRUE)

  html <- paste(readLines(sub("[.]qmd$", ".html", job), warn = FALSE), collapse = "\n")
  expect_match(html, "Std. Diff. (%)", fixed = TRUE)
  # The report prints the flextable that is saved, not gtsummary's working
  # object, whose cells carry the internal "N ||| stat" sentinel.
  expect_false(grepl("|||", html, fixed = TRUE))
  docx <- list.files(hvtiRutilities::study_dir("documents", root), pattern = "[.]docx$",
                     recursive = TRUE, full.names = TRUE)
  expect_length(docx, 1L)
  expect_identical(nrow(hvtiRtables::hv_check_docx(docx)), 0L)
})
