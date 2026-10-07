# dc-gfup's figure is rendered, not only read: its checks and hv_followup() calls
# run at render time, and a static test would pass a template whose figure chunk
# fails. The figure was the dp-gfup job until it moved here.
# scaffold_gfup() is in helper-migration.R.

# The fixture's iv_opyrs runs to 40, so the template's 1990 origin would place
# operations in 2030; the job refuses that, and these tests use 1980.
base_edits <- list(
  "^ANALYSIS_SET <- " = "ANALYSIS_SET <- NULL",
  "^ORIGIN_YEAR <- " = "ORIGIN_YEAR <- 1980"
)

test_that("dc-gfup renders a death panel and an event panel", {
  skip_on_cran()
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
  pngs <- file.path(s$root, "graphs", "cohort-eda", c("dc-gfup-all.png", "dc-gfup-repair.png"))
  expect_true(all(file.exists(pngs)))
  expect_true(all(file.info(pngs)$size > 1000))
})

# A refusal from hv_followup_panels() must not cost the study its follow-up
# tables: the job renders, says why the figure is missing, and draws no panel.
render_refused <- function(s) {
  quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = TRUE)
  html <- sub("[.]qmd$", ".html", s$job)
  testthat::expect_true(file.exists(html))
  out <- paste(readLines(html, warn = FALSE), collapse = "\n")
  testthat::expect_match(out, "The figure was not drawn", fixed = TRUE)
  testthat::expect_match(out, "Follow-up by interval and patient group", fixed = TRUE)
  testthat::expect_length(list.files(file.path(s$root, "graphs"), pattern = "^dc-gfup-.*[.]png$", recursive = TRUE), 0L)
  out
}

# The same refusal, from the job's own chunks rather than another render: every
# refusal takes the window chunk's one path, which render_refused() above
# renders end to end for the missing-column case. The warning stands for the
# render carrying on, and the follow-up table, made before the window, for the
# tables kept. Returns the warning and the output, for the message's check.
refused_chunks <- function(s) {
  # The setup chunk attaches these.
  withr::local_package("ggplot2")
  withr::local_package("hvtiPlotR")
  withr::local_package("hvtiRutilities")
  withr::local_dir(dirname(s$job))
  lines <- readLines(s$job, warn = FALSE)
  env <- new.env(parent = globalenv())
  env$.root <- s$root
  warned <- character()
  out <- withCallingHandlers(
    utils::capture.output(for (label in c("set", "edit-study-choices", "tbl-data", "qc", "tbl-qc-followup", "window",
                                          "figures")) {
      start <- match(paste0("#| label: ", label), lines)
      end <- start + match("```", lines[-seq_len(start)])
      eval(parse(text = lines[seq.int(start + 1L, end - 1L)]), env)
    }),
    warning = function(w) {
      if (grepl("figure was not drawn", conditionMessage(w), fixed = TRUE)) {
        warned <<- c(warned, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    }
  )
  testthat::expect_length(warned, 1L)
  out <- paste(c(warned, out), collapse = "\n")
  testthat::expect_match(out, "The figure was not drawn", fixed = TRUE)
  testthat::expect_gt(nrow(env$followup_table), 0L)
  testthat::expect_length(list.files(file.path(s$root, "graphs"), pattern = "^dc-gfup-.*[.]png$", recursive = TRUE), 0L)
  out
}

test_that("dc-gfup names every missing column in one message, and keeps its tables", {
  skip_on_cran()
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  out <- render_refused(scaffold_gfup(c(base_edits, list(
    "^  all = list\\(status = " = "  all = list(status = \"nope1\", time = \"nope2\", title = \"All deaths\")"
  ))))
  expect_match(out, "not in the data: nope1, nope2", fixed = TRUE)
})

test_that("dc-gfup reports a two-digit origin year, and keeps its tables", {
  out <- refused_chunks(scaffold_gfup(c(base_edits["^ANALYSIS_SET <- "], list("^ORIGIN_YEAR <- " = "ORIGIN_YEAR <- 85"))))
  expect_match(out, "Operations fall outside 1900", fixed = TRUE)
})

test_that("dc-gfup reports a name shared by PANELS and EVENTS, and keeps its tables", {
  out <- refused_chunks(scaffold_gfup(c(base_edits, list(
    "^EVENTS <- list\\(\\)$" = paste0(
      "EVENTS <- list(all = list(event = \"repair\", time = \"iv_fup\", ",
      "death = \"dead\", death_time = \"iv_dead\"))"
    )
  ))))
  expect_match(out, "all is used twice", fixed = TRUE)
})

test_that("a final dc-gfup render stops on a figure refusal", {
  skip_on_cran()
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  s <- scaffold_gfup(c(base_edits["^ANALYSIS_SET <- "], list("^ORIGIN_YEAR <- " = "ORIGIN_YEAR <- 85")))
  # Strict mode also stops on an unresolved marker, so clear them: the stop
  # under test must be the figure's.
  writeLines(gsub(paste0("ED", "IT:"), "Set:", readLines(s$job, warn = FALSE), fixed = TRUE), s$job)
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "1")
  err <- tryCatch({
    utils::capture.output(quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = FALSE),
                          type = "message")
    NULL
  }, error = function(e) conditionMessage(e))
  expect_false(is.null(err))
  expect_match(paste(err, collapse = "\n"), "figure was not drawn", fixed = TRUE)
})

# The window table's "operation before origin" row follows hvtiPlotR: shown
# when hv_followup_panels() counts negative operation years, absent when an
# older version does not. The function is mocked, so both are tested whichever
# hvtiPlotR is installed. Raised in review on #240.
window_table <- function(n_negative) {
  lines <- readLines(template_path("dc", "gfup"), warn = FALSE)
  chunk <- function(label) {
    start <- match(paste0("#| label: ", label), lines)
    end <- start + match("```", lines[-seq_len(start)])
    lines[seq.int(start + 1L, end - 1L)]
  }
  meta <- list(n_obs = 10L, n_opyrs_missing = 0L, first_operation = as.Date("1989-06-01"),
               study_end = as.Date("2000-01-01"), close_date = as.Date("2001-01-01"),
               close_source = "estimated")
  meta$n_opyrs_negative <- n_negative
  testthat::local_mocked_bindings(hv_followup_panels = function(...) list(meta = meta), .package = "hvtiPlotR")
  env <- list2env(list(d = data.frame(), OPYRS = "iv_opyrs", ORIGIN_YEAR = 1990, CLOSE_DATE = NULL,
                       PANELS = list(), EVENTS = list()))
  eval(parse(text = chunk("window")), env)
  paste(utils::capture.output(eval(parse(text = chunk("tbl-window")), env)), collapse = "\n")
}

test_that("dc-gfup's window table counts operations before the origin when hvtiPlotR does", {
  skip_if_not_installed("hvtiPlotR")
  out <- window_table(3L)
  expect_match(out, "operation before origin\\s*\\|\\s*3\\s*\\|")
  expect_no_match(window_table(NULL), "operation before origin", fixed = TRUE)
  expect_match(window_table(NULL), "first operation", fixed = TRUE)
})

test_that("dp-eda's window table carries the same row", {
  lines <- readLines(template_path("dp", "eda"), warn = FALSE)
  expect_true(any(grepl("operation before origin", lines, fixed = TRUE)))
  expect_true(any(grepl(".before <- fp$meta$n_opyrs_negative", lines, fixed = TRUE)))
})

test_dc_gfup_window <- function(close_date) {
  job <- template_path("dc", "gfup")
  lines <- readLines(job, warn = FALSE)
  start <- match("#| label: window", lines)
  end <- start + match("```", lines[-seq_len(start)])
  env <- list2env(list(d = hvtiPlotR::sample_goodness_followup_data(n = 60, seed = 3), OPYRS = "iv_opyrs",
                       ORIGIN_YEAR = 1990, CLOSE_DATE = close_date, EVENTS = list(),
                       PANELS = list(all = list(status = "dead", time = "iv_dead"))))
  suppressWarnings(eval(parse(text = lines[seq.int(start + 1L, end - 1L)]), env))
  env$close_source
}

test_that("dc-gfup reports the close date's source by the job's own edit point", {
  skip_if_not_installed("hvtiPlotR", "2.7.17")
  expect_identical(test_dc_gfup_window(as.Date("2023-01-01")), "set in CLOSE_DATE")
  expect_match(test_dc_gfup_window(NULL), "estimated")
})
