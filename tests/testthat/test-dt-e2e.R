test_that("a dt render after bd shows counts, and no patient row or identifier reaches the report", {
  skip_on_cran()
  dt_quarto_skip()
  s <- dt_study()
  # The rebuild: every event indicator flipped, one patient swapped for another, and a
  # column of distinctive strings to print, as a programmer's checks would print notes.
  dt_rebuild(s$root, function(d) {
    d$dead <- 1L - d$dead
    d$ccfid[[1L]] <- "PTSWAP001"
    d$note <- sprintf("ZQXNOTE%04d", seq_len(nrow(d)))
    d
  })
  queried <- readRDS(dt_working(s$root))$ccfid[[5L]]
  job <- dt_job(s$root, list(
    "^CROSSTABS <- " = "CROSSTABS <- list(c(\"dead\", \"sex\"))"
  ))
  lines <- readLines(job, warn = FALSE)
  # CHECKS is a block of several lines in the template: replace it whole.
  from <- grep("^CHECKS <- list\\($", lines)
  to <- from + which(lines[(from + 1L):length(lines)] == ")")[[1L]]
  lines <- c(lines[seq_len(from - 1L)],
             paste0("CHECKS <- list(!is.na(note) ~ \"Every row\", ccfid == \"", queried, "\" ~ \"Queried patient\")"),
             lines[(to + 1L):length(lines)])
  lines[grep("^PRINT_COLS <- ", lines)] <- "PRINT_COLS <- c(\"ccfid\", \"note\")"
  writeLines(lines, job)
  html <- dt_render(job)

  # The counts are in the report.
  expect_match(html, "A rebuild of the study dataset: study_cohort.rds", fixed = TRUE)
  expect_match(html, "Every row", fixed = TRUE)
  expect_match(html, "Queried patient", fixed = TRUE)
  expect_match(html, "differs", fixed = TRUE)
  expect_match(html, "In this build only", fixed = TRUE)
  expect_match(html, "dead by sex", fixed = TRUE)
  expect_true(grepl("About this run", html, fixed = TRUE))
  # The PHI guard: the printed rows went to the console. No printed value, no
  # identifier (the membership identifiers included), and not the one a check names.
  expect_false(grepl("ZQXNOTE", html, fixed = TRUE))
  ids <- unique(c(s$m$data$ccfid, "PTSWAP001"))
  leaked <- ids[vapply(ids, grepl, logical(1L), x = html, fixed = TRUE)]
  expect_identical(leaked, character())
})

test_that("a dt render with nothing registered says so, and a cross-tab named twice still renders", {
  skip_on_cran()
  dt_quarto_skip()
  s <- dt_study(register = FALSE)
  # The same pair twice: each cross-tab's chunk label carries its position, so the labels stay apart.
  job <- dt_job(s$root, list("^CROSSTABS <- " = "CROSSTABS <- list(c(\"dead\", \"sex\"), c(\"dead\", \"sex\"))"))
  html <- dt_render(job)
  expect_match(html, "Nothing is registered for this study yet", fixed = TRUE)
  expect_false(grepl("Rows in the registered version", html, fixed = TRUE))
  expect_false(grepl("compared by value", html, fixed = TRUE))
  expect_identical(lengths(regmatches(html, gregexpr("dead by sex, with a missing value", html, fixed = TRUE))), 2L)
})
