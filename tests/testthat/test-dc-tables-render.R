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
    # Two events in sixty: expected cells under 5, so this row is Fisher's.
    redo = seq_len(n) %in% c(7L, 40L),
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
  withr::local_envvar(HVTI_TEMPLATE_STRICT = NA)
  root <- dc_tables_study()
  job <- add_job("dc", "cohort", "tables", qualifier = "tables", dir = root)
  lines <- readLines(job, warn = FALSE)
  lines <- set_choice(lines, "BY", '"grp"')
  lines <- set_choice(lines, "CONTINUOUS", 'c("age", "creat")')
  lines <- set_choice(lines, "BINARY", 'c("female", "redo")')
  lines <- set_choice(lines, "CATEGORICAL", 'c("nyha", "race")')
  lines <- set_choice(lines, "COMPARE", '"pvalue"')
  lines <- set_choice(lines, "MEAN_SD", '"age"')
  lines <- set_choice(lines, "ORDINAL", '"nyha"')
  lines <- set_choice(lines, "STDDIFF", "TRUE")
  groups <- grep("^GROUPS <- list\\($", lines)
  lines <- c(lines[seq_len(groups)], '  Demography = c("age", "female", "race", "redo"),',
             '  Clinical = c("creat", "nyha")', ")", lines[-seq_len(groups + 3L)])
  # Worked markers, as helper-rm.R does, so the render is the same draft or final.
  writeLines(gsub("EDIT:", "REVIEWED:", lines, fixed = TRUE), job)

  rendered <- tryCatch(quarto::quarto_render(job, execute_dir = dirname(job), quiet = TRUE),
                       error = function(e) e)
  # A quiet render's error says only that quarto failed; render again aloud so
  # the log names the chunk and the cause.
  if (inherits(rendered, "error")) quarto::quarto_render(job, execute_dir = dirname(job), quiet = FALSE)

  html <- paste(readLines(sub("[.]qmd$", ".html", job), warn = FALSE), collapse = "\n")
  # The report, not its folded source: the code carries the same label and
  # would match even if the table lost its column.
  html <- gsub("(?s)<pre[^>]*>.*?</pre>", "", html, perl = TRUE)
  expect_match(html, "Std. Diff. (%)", fixed = TRUE)
  # The report prints the flextable that is saved, not gtsummary's working
  # object, whose cells carry the internal "N ||| stat" sentinel.
  expect_false(grepl("|||", html, fixed = TRUE))
  # A Fisher row's double dagger is explained in the report, as in the .docx.
  expect_match(html, "\u2021", fixed = TRUE)
  expect_match(html, "Fisher exact test.", fixed = TRUE)
  docx <- list.files(hvtiRutilities::study_dir("documents", root), pattern = "[.]docx$",
                     recursive = TRUE, full.names = TRUE)
  expect_length(docx, 1L)
  expect_identical(nrow(hvtiRtables::hv_check_docx(docx)), 0L)
})
