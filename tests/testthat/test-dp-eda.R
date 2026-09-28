# dp-eda is rendered, not only read: its sections call hv_followup_panels(),
# followup_check() and hv_eda_pages() at render time, and a static test would
# pass a template whose section chunk fails. scaffold_job() is in
# helper-migration.R. One fixture per render keeps the check time down.

# The fixture's iv_opyrs runs to 40, so the template's 1990 origin would place
# operations in 2030; the job refuses that, and these tests use 1980.
eda_edits <- list(
  "^ANALYSIS_SET <- " = "ANALYSIS_SET <- NULL",
  "^ORIGIN_YEAR <- " = "ORIGIN_YEAR <- 1980"
)

test_that("dp-eda renders every section into one self-contained report", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  # An event panel too: its colour and shape mapping is this template's own
  # code, not hv_followup_panels()'s, so test-dp-gfup.R does not cover it here.
  edits <- c(eda_edits, list(
    "^EVENTS <- list\\(\\)$" = paste0(
      "EVENTS <- list(repair = list(event = \"repair\", time = \"iv_fup\", ",
      "death = \"dead\", death_time = \"iv_dead\", label = \"Repair\"))"
    )
  ))
  s <- scaffold_job("dp", "eda", edits, kind = "dp-postage")
  quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = TRUE)
  html <- sub("[.]qmd$", ".html", s$job)
  expect_true(file.exists(html))
  graphs <- file.path(s$root, "graphs", "cohort-eda")
  pages <- sprintf("dp-eda-%s-page-01.png", c("continuous", "percent", "count"))
  pngs <- file.path(graphs, c("dp-eda-gfup-all.png", "dp-eda-gfup-repair.png", pages))
  expect_true(all(file.exists(pngs)))
  text <- paste(readLines(html, warn = FALSE), collapse = "\n")
  for (heading in c("Overview", "Goodness of follow-up", "Continuous variables",
                    "Categorical variables, percent", "Categorical variables, counts")) {
    expect_match(text, paste0("<h2[^>]*>[^<]*", heading), info = heading)
  }
  expect_match(text, "<h3[^>]*>[^<]*Repair")
  # embed-resources: every saved figure is inside the report. An image Quarto
  # could not find is left as a file link and would not be counted here.
  # regmatches(), not length(gregexpr()): no match returns -1, whose length is 1.
  n_png <- length(list.files(graphs, "^dp-eda-.*[.]png$"))
  expect_identical(length(regmatches(text, gregexpr("src=\"data:image/png", text))[[1L]]), n_png)
})

test_that("dp-eda draws the same pages as dp-postage over the same data", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  root <- migration_study_fixture("dp-postage")
  eda <- scaffold_job("dp", "eda", eda_edits, root = root)
  postage <- scaffold_job("dp", "postage", eda_edits["^ANALYSIS_SET <- "], root = root)
  for (job in c(eda$job, postage$job)) quarto::quarto_render(job, execute_dir = dirname(job), quiet = TRUE)
  graphs <- file.path(root, "graphs", "cohort-eda")
  pages <- function(stem) list.files(graphs, paste0("^", stem, "-(continuous|percent|count)-"), full.names = TRUE)
  expect_identical(sub("^dp-eda-", "", basename(pages("dp-eda"))),
                   sub("^dp-postage-", "", basename(pages("dp-postage"))))
  # Byte for byte: the same function, arguments and device give the same file.
  expect_identical(unname(tools::md5sum(pages("dp-eda"))), unname(tools::md5sum(pages("dp-postage"))))
  expect_gt(length(pages("dp-eda")), 2L)
})

test_that("dp-eda leaves out a section not named in SECTIONS", {
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  edits <- c(eda_edits, list("^SECTIONS <- " = "SECTIONS <- c(\"count\", \"continuous\")"))
  s <- scaffold_job("dp", "eda", edits, kind = "dp-postage", subfolder = "checks")
  quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = TRUE)
  graphs <- file.path(s$root, "graphs", "cohort-eda")
  expect_false(file.exists(file.path(graphs, "dp-eda-gfup-all.png")))
  expect_length(list.files(graphs, "^dp-eda-percent-"), 0L)
  expect_true(file.exists(file.path(graphs, "dp-eda-count-page-01.png")))
  # A job kept in a subfolder still embeds its pages.
  text <- paste(readLines(sub("[.]qmd$", ".html", s$job), warn = FALSE), collapse = "\n")
  n_png <- length(list.files(graphs, "^dp-eda-.*[.]png$"))
  expect_identical(length(regmatches(text, gregexpr("src=\"data:image/png", text))[[1L]]), n_png)
  # The heading, not the folded source that prints it.
  expect_false(grepl("<h2[^>]*>[^<]*Goodness of follow-up", text))
})

test_that("dp-eda colours every point of an event panel, by the house rule or from COLOURS", {
  # A manual scale whose names miss one of the panel's levels still draws: the
  # unmatched points go grey and ggplot says nothing while any level matches.
  # Only the built plot shows it, so this runs the template's own chunks, once
  # with the default COLOURS <- NULL and once with a study's own three.
  withr::local_package("ggplot2")
  withr::local_package("hvtiPlotR")
  withr::local_package("hvtiRutilities")
  root <- migration_study_fixture(NULL)
  job <- add_job("dp", "cohort", "eda", dir = root, qualifier = "eda")
  chunk <- function(label) {
    lines <- readLines(job, warn = FALSE)
    start <- match(paste0("#| label: ", label), lines)
    end <- start + match("```", lines[-seq_len(start)])
    parse(text = lines[seq.int(start + 1L, end - 1L)])
  }
  event_panel_colours <- function(colours) {
    env <- new.env(parent = globalenv())
    env$.root <- root
    env$.provenance_data <- list()
    env$d <- hvtiRutilities::read_built(hvtiRutilities::study_config(root))
    for (label in c("set", "study-choices")) eval(chunk(label), env)
    env$ORIGIN_YEAR <- 1980
    env$COLOURS <- colours
    env$EVENTS <- list(repair = list(event = "repair", time = "iv_fup", death = "dead",
                                     death_time = "iv_dead", label = "Repair"))
    # The fixture carries no labels, and label_map() says so; that notice only.
    withCallingHandlers(
      utils::capture.output(for (label in c("spec", "gfup-window", "gfup-panels")) eval(chunk(label), env)),
      warning = function(w) if (grepl("lack descriptive labels", conditionMessage(w))) invokeRestart("muffleWarning")
    )
    # The loop leaves p as the last panel drawn, the event panel.
    expect_identical(env$nm, "repair")
    built <- ggplot2::ggplot_build(env$p)
    points <- Filter(function(layer) "shape" %in% names(layer), built$data)
    unlist(lapply(points, `[[`, "colour"))
  }

  house <- hvtiPlotR::hv_role_palette(c("No event", "Repair", "Death"), event = "Death", censored = "No event")
  drawn <- event_panel_colours(NULL)
  expect_gt(length(drawn), 0L)
  expect_true(all(drawn %in% house), info = paste(setdiff(drawn, house), collapse = ", "))
  expect_true(house[["Repair"]] %in% drawn)
  expect_identical(house[["Repair"]], "#009E73")

  own <- c(alive = "#377EB8", dead = "#E41A1C", event = "#4DAF4A")
  drawn <- event_panel_colours(own)
  expect_true(all(drawn %in% own), info = paste(setdiff(drawn, own), collapse = ", "))
  expect_true(own[["event"]] %in% drawn)
  expect_error(event_panel_colours(c(alive = "blue", dead = "red")), "COLOURS must be NULL")
})

test_that("dp-eda VARIABLES = NULL leaves out identifiers written without a separator", {
  # The spec chunk, not a render: dp-postage's test covers the rule's edges, and
  # this one proves dp-eda carries the same rule rather than an older copy.
  lines <- readLines(template_path("dp", "eda"), warn = FALSE)
  start <- match("#| label: spec", lines)
  end <- start + match("```", lines[-seq_len(start)])
  spec <- parse(text = lines[seq.int(start + 1L, end - 1L)])
  n <- 12L
  env <- list2env(list(d = data.frame(year = seq_len(n), age = 40 + seq_len(n), ccfid = 1000L + seq_len(n),
                                      patientid = sprintf("P%03d", seq_len(n)), carotid = rep(0:1, 6)),
                       X_VAR = "year", VARIABLES = NULL, EXCLUDE = character(),
                       GRID_NCOL = 4L, GRID_NROW = 4L, UNIQUE_LIMIT = 6L,
                       SECTIONS = c("followup", "continuous", "percent", "count"), ALPHA = 0.5,
                       label_map = function(d) data.frame(key = names(d), label = names(d))))
  out <- capture.output(eval(spec, env))
  expect_identical(env$VARIABLES, c("age", "carotid"))
  expect_match(paste(out, collapse = " "), "ccfid, patientid")
})

test_that("dp-eda's overview leaves out identifiers but keeps dates", {
  # Named in VARIABLES, so the spec chunk's NULL branch does not decide this:
  # the overview applies the rule itself.
  lines <- readLines(template_path("dp", "eda"), warn = FALSE)
  chunk <- function(label) {
    start <- match(paste0("#| label: ", label), lines)
    end <- start + match("```", lines[-seq_len(start)])
    parse(text = lines[seq.int(start + 1L, end - 1L)])
  }
  n <- 12L
  env <- list2env(list(d = data.frame(year = seq_len(n), age = 40 + seq_len(n), ccfid = 1000L + seq_len(n),
                                      patientid = sprintf("P%03d", seq_len(n)), carotid = rep(0:1, 6), mrn_num = 5000L + seq_len(n),
                                      dt_surg = as.Date("2020-01-01") + seq_len(n)),
                       X_VAR = "year", VARIABLES = c("age", "ccfid"), EXCLUDE = character(),
                       GRID_NCOL = 4L, GRID_NROW = 4L, UNIQUE_LIMIT = 6L,
                       SECTIONS = c("followup", "continuous", "percent", "count"), ALPHA = 0.5,
                       label_map = function(d) data.frame(key = names(d), label = names(d))))
  suppressWarnings(capture.output(eval(chunk("spec"), env)))
  out <- paste(capture.output(eval(chunk("overview-contents"), env)), collapse = "\n")
  expect_identical(env$shown$variable, c("year", "age", "carotid", "dt_surg"))
  expect_match(out, "Identifier columns, not described: ccfid, patientid, mrn_num", fixed = TRUE)
})

test_that("dp-gfup and dp-eda choose follow-up colours with the same code", {
  # dp-eda's copy is drawn and checked above; this keeps dp-gfup's from drifting.
  block <- function(prefix, qualifier) {
    lines <- readLines(template_path(prefix, qualifier), warn = FALSE)
    start <- grep("^if \\(!is.null\\(COLOURS\\)", lines)
    end <- start + match("}", lines[-seq_len(start)])
    end <- end + match("}", lines[-seq_len(end)])
    lines[start:end]
  }
  expect_length(block("dp", "gfup"), 11L)
  expect_identical(block("dp", "gfup"), block("dp", "eda"))
})
