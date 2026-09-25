# dp-gfup is rendered, not only read: its checks and hv_followup() calls run at
# render time, and a static test would pass a template whose figure chunk fails.
# scaffold_gfup() is in helper-migration.R.

# The fixture's iv_opyrs runs to 40, so the template's 1990 origin would place
# operations in 2030; the job refuses that, and these tests use 1980.
base_edits <- list(
  "^ANALYSIS_SET <- " = "ANALYSIS_SET <- NULL",
  "^ORIGIN_YEAR <- " = "ORIGIN_YEAR <- 1980"
)

test_that("dp-gfup renders a death panel and an event panel", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  edits <- c(base_edits, list(
    "^EVENTS <- list\\(\\)$" = paste0(
      "EVENTS <- list(repair = list(event = \"repair\", time = \"iv_fup\", ",
      "death = \"dead\", death_time = \"iv_dead\", label = \"Repair\"))"
    )
  ))
  s <- scaffold_gfup(edits)
  quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = TRUE)
  expect_true(file.exists(sub("[.]qmd$", ".html", s$job)))
  pngs <- file.path(s$root, "graphs", "cohort-eda", c("dp-gfup-all.png", "dp-gfup-repair.png"))
  expect_true(all(file.exists(pngs)))
  expect_true(all(file.info(pngs)$size > 1000))
})

test_that("dp-gfup names every missing column in one error", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  edits <- c(base_edits, list(
    "^  all = list\\(status = " = "  all = list(status = \"nope1\", time = \"nope2\", title = \"All deaths\")"
  ))
  s <- scaffold_gfup(edits)
  # quiet = TRUE hides the R error, and the error text is what is under test.
  err <- tryCatch({
    utils::capture.output(quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = FALSE),
                          type = "message")
    NULL
  }, error = function(e) conditionMessage(e))
  expect_false(is.null(err))
  expect_match(paste(err, collapse = "\n"), "not in the data: nope1, nope2")
})

test_that("dp-gfup refuses a two-digit origin year", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  s <- scaffold_gfup(c(base_edits["^ANALYSIS_SET <- "], list("^ORIGIN_YEAR <- " = "ORIGIN_YEAR <- 85")))
  err <- tryCatch({
    utils::capture.output(quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = FALSE),
                          type = "message")
    NULL
  }, error = function(e) conditionMessage(e))
  expect_false(is.null(err))
  expect_match(paste(err, collapse = "\n"), "Check `origin_year`")
})

test_that("dp-gfup refuses a name shared by PANELS and EVENTS", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  edits <- c(base_edits, list(
    "^EVENTS <- list\\(\\)$" = paste0(
      "EVENTS <- list(all = list(event = \"repair\", time = \"iv_fup\", ",
      "death = \"dead\", death_time = \"iv_dead\"))"
    )
  ))
  s <- scaffold_gfup(edits)
  err <- tryCatch({
    utils::capture.output(quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = FALSE),
                          type = "message")
    NULL
  }, error = function(e) conditionMessage(e))
  expect_false(is.null(err))
  expect_match(paste(err, collapse = "\n"), "all is used twice")
})

test_dp_gfup_window <- function(close_date) {
  job <- template_path("dp", "gfup")
  lines <- readLines(job, warn = FALSE)
  start <- match("#| label: window", lines)
  end <- start + match("```", lines[-seq_len(start)])
  env <- list2env(list(d = hvtiPlotR::sample_goodness_followup_data(n = 60, seed = 3), OPYRS = "iv_opyrs",
                       ORIGIN_YEAR = 1990, CLOSE_DATE = close_date, EVENTS = list(),
                       PANELS = list(all = list(status = "dead", time = "iv_dead"))))
  suppressWarnings(eval(parse(text = lines[seq.int(start + 1L, end - 1L)]), env))
  env$close_source
}

test_that("dp-gfup reports the close date's source by the job's own edit point", {
  skip_if_not_installed("hvtiPlotR", "2.7.17")
  expect_identical(test_dp_gfup_window(as.Date("2023-01-01")), "set in CLOSE_DATE")
  expect_match(test_dp_gfup_window(NULL), "estimated")
})
