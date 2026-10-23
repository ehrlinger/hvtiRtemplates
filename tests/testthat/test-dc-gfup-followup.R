# dc-gfup's potential follow-up table, the check that its table and figures
# describe one event, and the two named groups of a non-fatal panel. Asked for
# at the 2026-10-23 Mitral umbrella review, where a real job checked
# reoperation in its table and drew deaths in its figure.

gfup_chunk <- function(label) {
  lines <- readLines(template_path("dc", "gfup"), warn = FALSE)
  start <- match(paste0("#| label: ", label), lines)
  end <- start + match("```", lines[-seq_len(start)])
  parse(text = lines[seq.int(start + 1L, end - 1L)])
}

test_that("the potential table sums follow-up recorded against follow-up possible", {
  # Operations on 1 January 2000; the close date ten years on.
  d <- data.frame(iv_opyrs = 0, dead = c(0, 0, 1, NA), iv_dead = c(10, 5, 2, 3))
  env <- list2env(list(d = d, OPYRS = "iv_opyrs", ORIGIN_YEAR = 2000, close_date = as.Date("2010-01-01"),
                       figure_drawn = TRUE, PANELS = list(all = list(status = "dead", time = "iv_dead",
                                                                     title = "All deaths"))))
  eval(gfup_chunk("potential"), env)
  row <- env$potential_table
  ten <- as.numeric(as.Date("2010-01-01") - as.Date("2000-01-01")) / 365.2425
  # The patient with no status is left out; the one who died is followed completely.
  expect_identical(row$patients, 3L)
  expect_equal(row$possible, 2 * ten + 2)
  expect_equal(row$recorded, 10 + 5 + 2)
  expect_equal(row$percent, 100 * 17 / (2 * ten + 2))
  expect_equal(row$max_possible, ten)
  expect_identical(row$past_close, 0L)
})

test_that("follow-up recorded past the close date counts only up to it, and is counted", {
  d <- data.frame(iv_opyrs = 0, dead = 0, iv_dead = c(12, 4))
  env <- list2env(list(d = d, OPYRS = "iv_opyrs", ORIGIN_YEAR = 2000, close_date = as.Date("2010-01-01"),
                       figure_drawn = TRUE, PANELS = list(all = list(status = "dead", time = "iv_dead"))))
  eval(gfup_chunk("potential"), env)
  ten <- as.numeric(as.Date("2010-01-01") - as.Date("2000-01-01")) / 365.2425
  expect_identical(env$potential_table$panel, "all")
  expect_identical(env$potential_table$past_close, 1L)
  expect_equal(env$potential_table$recorded, ten + 4)
  expect_lte(env$potential_table$percent, 100)
})

# The figures chunk with no figure drawn: enough to run its checks and print
# its callouts without drawing a panel.
gfup_checks <- function(event, panels, events = list()) {
  env <- list2env(list(EVENT = event, PANELS = panels, EVENTS = events, COLORS = NULL, ALPHA = 0.5,
                       figure_drawn = FALSE, fp = simpleError("not drawn"), panel_counts = list()))
  out <- utils::capture.output(eval(gfup_chunk("figures"), env))
  paste(out, collapse = "\n")
}
deaths <- list(all = list(status = "dead", time = "iv_dead", title = "All deaths"))
reop <- list(reop = list(event = "ev_reop", time = "iv_reop", death = "dead", death_time = "iv_dead"))

test_that("a job whose figures do not draw EVENT says so, and is a draft", {
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "")
  withr::defer(.run_state$draft_reasons <- NULL)
  .run_state$draft_reasons <- NULL
  expect_warning(out <- gfup_checks("ev_reop", deaths), "describe different events")
  expect_match(out, "EVENT is ev_reop, which no figure draws: PANELS draws dead and EVENTS none", fixed = TRUE)
  expect_true("the follow-up table and the figures describe different events" %in% .run_state$draft_reasons)
})

test_that("a final render stops when the figures do not draw EVENT", {
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "1")
  expect_error(gfup_checks("ev_reop", deaths), "describe different events")
})

test_that("EVENT drawn by a PANELS or an EVENTS entry passes the check", {
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "1")
  expect_no_warning(out <- gfup_checks("dead", deaths))
  expect_no_match(out, "different events", fixed = TRUE)
  expect_no_warning(gfup_checks("ev_reop", deaths, reop))
  two <- c(deaths, list(reop = list(status = "ev_reop", time = "iv_reop", levels = c("No reoperation", "Reoperation"))))
  expect_no_warning(gfup_checks("ev_reop", two))
})

test_that("a panel's levels must be two distinct names", {
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "")
  for (bad in list("Reoperation", c("Reop", "Reop"), c("No reop", NA), c("", "Reop"), 1:2)) {
    panels <- list(reop = list(status = "dead", time = "iv_dead", levels = bad))
    expect_error(gfup_checks("dead", panels), "`levels` must be two distinct names")
  }
})

test_that("a two-group panel draws and captions its own group names", {
  skip_on_cran()
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  s <- scaffold_gfup(list(
    "^ANALYSIS_SET <- " = "ANALYSIS_SET <- NULL",
    "^ORIGIN_YEAR <- " = "ORIGIN_YEAR <- 1980",
    "^EVENT <- " = "EVENT <- \"repair\"",
    "^  all = list\\(status = " = paste0("  all = list(status = \"dead\", time = \"iv_dead\", title = \"All deaths\"),\n",
                                         "  repair = list(status = \"repair\", time = \"iv_fup\", title = \"Repair\",\n",
                                         "                levels = c(\"No repair\", \"Repair\"))")
  ))
  quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = TRUE)
  html <- paste(readLines(sub("[.]qmd$", ".html", s$job), warn = FALSE), collapse = "\n")
  expect_match(html, "Blue open circles mark No repair and vermillion crosses Repair", fixed = TRUE)
  expect_match(html, "Follow-up recorded against follow-up possible", fixed = TRUE)
  # The phrase the callout prints, which the folded code does not contain.
  expect_no_match(html, "EVENT is repair", fixed = TRUE)
  expect_true(file.exists(file.path(s$root, "graphs", "cohort-eda", "dc-gfup-repair.png")))
})
