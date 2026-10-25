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
      start <- match(paste0("#| label: ", setup_label(label)), lines)  # nolint: object_usage_linter.
      end <- start + match("```", lines[-seq_len(start)])
      eval(chunk_expression(lines[seq.int(start + 1L, end - 1L)], label), env)  # nolint: object_usage_linter.
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

test_that("dc-eda's window table carries the same row", {
  lines <- readLines(template_path("dc", "eda"), warn = FALSE)
  expect_true(any(grepl("operation before origin", lines, fixed = TRUE)))
  expect_true(any(grepl(".before <- fp$meta$n_opyrs_negative", lines, fixed = TRUE)))
})

test_dc_gfup_window <- function(close_date) {
  job <- template_path("dc", "gfup")
  lines <- readLines(job, warn = FALSE)
  start <- match("#| label: window", lines)
  end <- start + match("```", lines[-seq_len(start)])
  env <- list2env(list(d = hvtiPlotR::sample_goodness_followup_data(n = 60, seed = 3), OPYRS = "iv_opyrs",
                       ORIGIN_YEAR = 1990, CLOSE_DATE = close_date, EVENTS = list(), ECHO = NULL,
                       PANELS = list(all = list(status = "dead", time = "iv_dead"))))
  suppressWarnings(eval(parse(text = lines[seq.int(start + 1L, end - 1L)]), env))
  env$close_source
}

test_that("dc-gfup reports the close date's source by the job's own edit point", {
  skip_if_not_installed("hvtiPlotR", "2.7.17")
  expect_identical(test_dc_gfup_window(as.Date("2023-01-01")), "set in CLOSE_DATE")
  expect_match(test_dc_gfup_window(NULL), "estimated")
})

# The window and figures chunks over hvtiPlotR's sample data, with a second
# non-fatal event and an echo column derived from it, as a render would run them
# after its data step. save_figure() keeps each panel instead of writing it.
# Returns the environment and everything the chunks printed.
gfup_drawn <- function(events, echo = NULL, colors = NULL) {
  withr::local_package("ggplot2")
  withr::local_package("hvtiPlotR")
  # Each child chunk is printed as written, so its caption can be read: knitr
  # outside a render drops Quarto's fig-cap.
  testthat::local_mocked_bindings(knit_child = function(text, ...) paste(text, collapse = "\n"), .package = "knitr")
  lines <- readLines(template_path("dc", "gfup"), warn = FALSE)
  chunk <- function(label) {
    start <- match(paste0("#| label: ", label), lines)
    end <- start + match("```", lines[-seq_len(start)])
    parse(text = lines[seq.int(start + 1L, end - 1L)])
  }
  d <- hvtiPlotR::sample_goodness_followup_data(n = 80, seed = 5)
  d$ev_stroke <- !d$ev_event & seq_len(nrow(d)) %% 4L == 0L
  # Every fifth patient has no echo: NA draws no tick and raises nothing.
  d$iv_echo <- ifelse(seq_len(nrow(d)) %% 5L == 0L, NA, d$iv_dead * 0.6)
  saved <- list()
  env <- new.env(parent = globalenv())
  list2env(list(d = d, EVENT = "dead", OPYRS = "iv_opyrs", ORIGIN_YEAR = 1990, CLOSE_DATE = NULL, ECHO = echo, EVENTS = events,
                PANELS = list(all = list(status = "dead", time = "iv_dead", title = "All deaths")),
                ALPHA = 0.5, COLORS = colors, .in = NULL,
                save_figure = function(plot, name, ...) {
                  saved[[name]] <<- plot
                  file.path(tempdir(), paste0(name, ".png"))
                }), env)
  out <- utils::capture.output(for (label in c("window", "figures")) eval(chunk(label), env))
  env$saved <- saved
  list(env = env, out = paste(out, collapse = "\n"))
}

# A built layer's colors; ggplot_build() names the column in British spelling.
drawn_colors <- function(layer) unlist(lapply(list(layer), `[[`, "colour"))

two_events <- list(nonfatal = list(event = c("ev_event", "ev_stroke"), time = c("iv_event", "iv_event"),
                                   death = "dead", death_time = "iv_dead", label = c("Reoperation", "Stroke")))

test_that("dc-gfup draws competing events in one panel, each in its own house color and shape", {
  # 2.8.18 made the event red and censored a Tol blue; the caption names them.
  skip_if_not_installed("hvtiPlotR", "2.8.18")
  r <- gfup_drawn(two_events)
  expect_true(r$env$figure_drawn)
  expect_named(r$env$saved, c("dc-gfup-all", "dc-gfup-nonfatal"))
  expect_match(r$out, "### Reoperation, Stroke", fixed = TRUE)
  expect_match(r$out, paste0("Blue open circles mark patients without an event, green open triangles patients whose ",
                             "first event was Reoperation, reddish purple open squares patients whose first event ",
                             "was Stroke, and red crosses patients who died and the dashed"), fixed = TRUE)
  expect_no_match(r$out, "gray ticks", fixed = TRUE)
  built <- ggplot2::ggplot_build(r$env$saved[["dc-gfup-nonfatal"]])
  points <- built$data[[1L]]
  levels <- c("No event", "Reoperation", "Stroke", "Death")
  house <- hvtiPlotR::hv_role_palette(levels, event = "Death", censored = "No event")
  # The caption names these colors, so they are pinned here.
  expect_identical(unname(house), c("#0077BB", "#009E73", "#CC79A7", "#CC3311"))
  # Green, reddish purple, olive and black, up to the four events a panel draws.
  four <- hvtiPlotR::hv_role_palette(c("No event", LETTERS[1:4], "Death"), event = "Death", censored = "No event")
  expect_identical(unname(four[2:5]), c("#009E73", "#CC79A7", "#9D952B", "#000000"))
  expect_setequal(unique(drawn_colors(points)), house)
  expect_setequal(unique(points$shape), c(1, 2, 0, 4))
})

test_that("dc-gfup marks each patient's echo with a gray tick, and an NA echo with none", {
  skip_if_not_installed("hvtiPlotR", "2.8.17")
  expect_no_warning(r <- gfup_drawn(two_events, echo = "iv_echo"))
  expect_match(r$out, "64 with an echo marked.", fixed = TRUE)
  expect_match(r$out, "red crosses patients who died, gray ticks the follow-up at each patient's echo, and the dashed",
               fixed = TRUE)
  for (p in r$env$saved) {
    built <- ggplot2::ggplot_build(p)
    ticks <- Filter(function(layer) "shape" %in% names(layer) && all(drawn_colors(layer) == "gray40"), built$data)
    expect_length(ticks, 1L)
    expect_identical(nrow(ticks[[1L]]), 64L)
  }
})

test_that("dc-gfup takes COLORS' event colors in order, one per competing event", {
  skip_if_not_installed("hvtiPlotR", "2.8.17")
  own <- c(alive = "#377EB8", dead = "#E41A1C", event = "#4DAF4A", event = "#984EA3")
  r <- gfup_drawn(two_events, colors = own)
  built <- ggplot2::ggplot_build(r$env$saved[["dc-gfup-nonfatal"]])
  expect_setequal(unique(drawn_colors(built$data[[1L]])), unname(own))
  expect_error(gfup_drawn(two_events, colors = own[1:3]), "COLORS names 1 event color(s)", fixed = TRUE)
  expect_error(gfup_drawn(two_events, colors = c(alive = "blue", event = "green")), "COLORS must be NULL")
  five <- list(many = list(event = rep("ev_event", 5L), time = rep("iv_event", 5L), death = "dead",
                           death_time = "iv_dead", label = LETTERS[1:5]))
  expect_error(gfup_drawn(five), "a panel draws at most four", fixed = TRUE)
})

test_that("dc-gfup's single-event caption is unchanged by competing events", {
  skip_if_not_installed("hvtiPlotR", "2.8.17")
  one <- list(reop = list(event = "ev_event", time = "iv_event", death = "dead", death_time = "iv_dead",
                          label = "Reoperation"))
  r <- gfup_drawn(one)
  expect_match(r$out, paste0("Blue open circles mark patients without the event, green open triangles patients with ",
                             "the event, and red crosses patients who died and the dashed"), fixed = TRUE)
})
