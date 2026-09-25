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
