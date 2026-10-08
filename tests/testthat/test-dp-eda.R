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

# The spec chunk reads the ID and KEY the data step resolved from
# read_job_data()'s record; a spec-only test supplies that record.
eda_job_data <- function(id, key = id) {
  list(record = structure(data.frame(step = character(), value = character()), selection = list(id = id, key = key)))
}

test_that("dp-eda renders every section into one self-contained report", {
  skip_on_cran()
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  # An event panel too: its color and shape mapping is this template's own
  # code, not hv_followup_panels()'s, so test-dp-gfup.R does not cover it here.
  edits <- c(eda_edits, list(
    "^EVENTS <- list\\(\\)$" = paste0(
      "EVENTS <- list(repair = list(event = \"repair\", time = \"iv_fup\", ",
      "death = \"dead\", death_time = \"iv_dead\", label = \"Repair\"))"
    ),
    "^ABBREVIATIONS <- NULL$" = "ABBREVIATIONS <- c(\"Goodness of follow-up\" = \"GFU\")"
  ))
  s <- scaffold_job("dp", "eda", edits, kind = "dp-postage")
  quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = TRUE)
  html <- sub("[.]qmd$", ".html", s$job)
  expect_true(file.exists(html))
  graphs <- file.path(s$root, "graphs", "cohort-eda")
  pages <- sprintf("dp-eda-%s-page-01.png", c("continuous", "percent", "count"))
  pngs <- file.path(graphs, c("dp-eda-gfup-all.png", "dp-eda-gfup-repair.png", pages))
  expect_true(all(file.exists(pngs)))
  # Each figure's publication copy sits beside its PNG, under the same name.
  expect_true(all(file.exists(sub("[.]png$", ".pdf", pngs))))
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
  # The label cap and the merged abbreviation list are recorded in provenance,
  # so the report can say which list shaped its labels.
  payload <- unlist(hvtiRtemplates:::.extract_provenance(text, managed = TRUE))
  expect_true(any(grepl("label_max$", names(payload)) & payload == "40"))
  # The job's own entry is recorded with its level, not merely a key. The list
  # is a data frame, one row per entry, so every row unlists to the same names
  # once the group list adds its entries: find the row by position.
  i <- which(payload == "Goodness of follow-up")
  expect_length(i, 1L)
  expect_true(all(mapply(grepl, c("abbreviation$", "source$"), names(payload)[i + 1:2])))
  expect_identical(unname(payload[i + 1:2]), c("GFU", "job"))
})

test_that("dp-eda draws the same pages as dp-postage over the same data", {
  skip_on_cran()
  # Each job's own chunks, run in order, not two more renders: the pages are
  # written by ggsave() inside the chunks, not by knitr's device, so they are
  # the files a render writes. Both templates render end to end elsewhere,
  # dp-eda above and dp-postage in test-migrate-dp-postage.R.
  withr::local_package("ggplot2")
  withr::local_package("hvtiPlotR")
  withr::local_package("hvtiRutilities")
  root <- migration_study_fixture("dp-postage")
  eda <- scaffold_job("dp", "eda", eda_edits, root = root)
  expect_warning(postage <- scaffold_job("dp", "postage", eda_edits["^ANALYSIS_SET <- "], root = root),
                 class = "hvtiRtemplates_deprecated")
  # The sections' tables and figures are child chunks.
  local_child_chunks()
  run_chunks <- function(job, labels) {
    lines <- readLines(job, warn = FALSE)
    env <- new.env(parent = globalenv())
    env$.root <- root
    # A render runs in the job's folder, and dp-postage's data chunk finds the
    # study from there.
    withr::local_dir(dirname(job))
    # The fixture carries no labels, and label_map() says so; that notice only.
    withCallingHandlers(
      utils::capture.output(for (label in labels) {
        start <- match(paste0("#| label: ", label), lines)
        end <- start + match("```", lines[-seq_len(start)])
        eval(parse(text = lines[seq.int(start + 1L, end - 1L)]), env)
      }),
      warning = function(w) if (grepl("lack descriptive labels", conditionMessage(w))) invokeRestart("muffleWarning")
    )
  }
  run_chunks(eda$job, c("set", "edit-study-choices", "tbl-data", "spec", "sections", "cont-pages", "pct-pages", "cnt-pages"))
  run_chunks(postage$job, c("set", "edit-study-choices", "data", "spec", "pages"))
  graphs <- file.path(root, "graphs", "cohort-eda")
  # PNGs only: a PDF records its creation time, so two renders' PDFs differ byte for byte.
  pages <- function(stem) {
    list.files(graphs, paste0("^", stem, "-(continuous|percent|count)-.*[.]png$"), full.names = TRUE)
  }
  expect_identical(sub("^dp-eda-", "", basename(pages("dp-eda"))),
                   sub("^dp-postage-", "", basename(pages("dp-postage"))))
  # Byte for byte: the same function, arguments and device give the same file.
  expect_identical(unname(tools::md5sum(pages("dp-eda"))), unname(tools::md5sum(pages("dp-postage"))))
  expect_gt(length(pages("dp-eda")), 2L)
})

test_that("dp-eda leaves out a section not named in SECTIONS", {
  skip_on_cran()
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

test_that("dp-eda colors every point of an event panel, by the house rule or from COLORS", {
  # A manual scale whose names miss one of the panel's levels still draws: the
  # unmatched points go gray and ggplot says nothing while any level matches.
  # Only the built plot shows it, so this runs the template's own chunks, once
  # with the default COLORS <- NULL and once with a study's own three.
  withr::local_package("ggplot2")
  withr::local_package("hvtiPlotR")
  withr::local_package("hvtiRutilities")
  # The panels' tables and figures are child chunks.
  local_child_chunks()
  root <- migration_study_fixture(NULL)
  job <- add_job("dp", "cohort", "eda", dir = root, qualifier = "eda")
  chunk <- function(label) {
    lines <- readLines(job, warn = FALSE)
    start <- match(paste0("#| label: ", label), lines)
    end <- start + match("```", lines[-seq_len(start)])
    parse(text = lines[seq.int(start + 1L, end - 1L)])
  }
  # old = TRUE mimics the choices chunk of a job older than the COLORS rename.
  event_panel_colors <- function(colors, old = FALSE) {
    env <- new.env(parent = globalenv())
    env$.root <- root
    env$.provenance_data <- list()
    env$d <- hvtiRutilities::read_built(hvtiRutilities::study_config(root))
    env$.cfg <- hvtiRutilities::study_config(root)
    env$job_data <- eda_job_data("ccfid")
    for (label in c("set", "edit-study-choices")) eval(chunk(label), env)
    env$ORIGIN_YEAR <- 1980
    if (old) {
      rm("COLORS", envir = env)
      env$COLOURS <- colors
    } else {
      env$COLORS <- colors
    }
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
  drawn <- event_panel_colors(NULL)
  expect_gt(length(drawn), 0L)
  expect_true(all(drawn %in% house), info = paste(setdiff(drawn, house), collapse = ", "))
  expect_true(house[["Repair"]] %in% drawn)
  expect_identical(house[["Repair"]], "#009E73")

  own <- c(alive = "#377EB8", dead = "#E41A1C", event = "#4DAF4A")
  drawn <- event_panel_colors(own)
  expect_true(all(drawn %in% own), info = paste(setdiff(drawn, own), collapse = ", "))
  expect_true(own[["event"]] %in% drawn)
  expect_error(event_panel_colors(c(alive = "blue", dead = "red")), "COLORS must be NULL")
  expect_error(event_panel_colors(own, old = TRUE), "COLOURS is now COLORS", fixed = TRUE)
})

test_that("dp-eda never draws the job's ID or KEY, which read_job_data() keeps", {
  # read_job_data() drops MRN and eMRN but keeps the ID, so the ID reaches d and
  # the spec chunk must leave it out. Run through a real study: the data chunk
  # and then the spec chunk, as a render would.
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(hvtiRutilities::study_setup(root, study = "EDA identifiers", study_tracker_id = 1L))
  n <- 12L
  built <- data.frame(year = 2000L + seq_len(n), ccfid = 1000L + seq_len(n), randid = 3000L + seq_len(n),
                      MRN = 5000L + seq_len(n), study_id = 7000L + seq_len(n), hosp_id = 9000L + seq_len(n),
                      pt_mrn_num = rep(0:1, 6), visit_mo = 3L * seq_len(n),
                      age = 40 + seq_len(n))
  utils::write.csv(built, file.path(hvtiRutilities::study_dir("datasets", root), "built.csv"), row.names = FALSE)
  suppressWarnings(suppressMessages(hvtiRutilities::register_data(root, built = "built.csv")))
  lines <- readLines(template_path("dp", "eda"), warn = FALSE)
  chunk <- function(label) {
    start <- match(paste0("#| label: ", label), lines)
    end <- start + match("```", lines[-seq_len(start)])
    parse(text = lines[seq.int(start + 1L, end - 1L)])
  }
  run <- function(id = "ccfid", variables = NULL, key = id) {
    env <- new.env(parent = globalenv())
    env$.root <- root
    env$study_config <- hvtiRutilities::study_config
    env$label_map <- function(d, ...) data.frame(key = names(d), label = names(d))
    eval(chunk("edit-study-choices"), env)
    env$ID <- id
    env$KEY <- key
    env$VARIABLES <- variables
    utils::capture.output(eval(chunk("tbl-data"), env))
    env$out <- utils::capture.output(eval(chunk("spec"), env))
    env
  }
  env <- run()
  expect_true("ccfid" %in% names(env$d))
  expect_false("mrn" %in% tolower(names(env$d)))
  expect_false("ccfid" %in% env$VARIABLES)
  expect_false("study_id" %in% env$VARIABLES)
  # An id token after a separator is an identifier too, by the generic name rule.
  expect_false("hosp_id" %in% env$VARIABLES)
  expect_true("pt_mrn_num" %in% env$VARIABLES)
  expect_match(paste(env$out, collapse = " "), "ccfid", fixed = TRUE)

  # An ID the name rule cannot recognize is left out because it is the ID.
  env <- run(id = "randid")
  expect_true("randid" %in% names(env$d))
  expect_false("randid" %in% env$VARIABLES)
  expect_true("ccfid" %in% names(env$d))
  expect_false("ccfid" %in% env$VARIABLES)

  # Named in VARIABLES, the ID is still not drawn, and the report says so.
  expect_warning(env <- run(id = "randid", variables = c("age", "randid")), "Not drawn, as the job's ID: randid")
  expect_identical(env$VARIABLES, "age")

  # A KEY column beside the ID, such as a visit time, is left out by default and
  # drawn when named.
  expect_true("visit_mo" %in% run()$VARIABLES)
  env <- run(key = c("ccfid", "visit_mo"))
  expect_false("visit_mo" %in% env$VARIABLES)
  expect_no_warning(env <- run(key = c("ccfid", "visit_mo"), variables = c("age", "visit_mo")))
  expect_identical(env$VARIABLES, c("age", "visit_mo"))
  # The name, date and free-text rules still flag a KEY column named there.
  expect_warning(env <- run(key = c("ccfid", "hosp_id"), variables = c("age", "hosp_id")),
                 "Selected likely identifier or date field\\(s\\): hosp_id")
  expect_identical(env$VARIABLES, c("age", "hosp_id"))
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
                       .cfg = list(), LABEL_MAX = 40, ABBREVIATIONS = NULL, job_data = eda_job_data("ccfid"),
                       label_map = function(d, ...) data.frame(key = names(d), label = names(d))))
  out <- capture.output(eval(spec, env))
  expect_identical(env$VARIABLES, c("age", "carotid"))
  expect_match(paste(out, collapse = " "), "ccfid, patientid")
})

test_that("dp-eda's overview leaves out identifiers but keeps dates", {
  local_child_chunks()
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
                                      patientid = sprintf("P%03d", seq_len(n)), carotid = rep(0:1, 6), eMRN = 5000L + seq_len(n),
                                      mrn_num = rep(0:1, 6),
                                      bnp_mrna = 0.5 * seq_len(n), dt_surg = as.Date("2020-01-01") + seq_len(n)),
                       X_VAR = "year", VARIABLES = c("age", "ccfid"), EXCLUDE = character(),
                       GRID_NCOL = 4L, GRID_NROW = 4L, UNIQUE_LIMIT = 6L,
                       SECTIONS = c("followup", "continuous", "percent", "count"), ALPHA = 0.5,
                       .cfg = list(), LABEL_MAX = 40, ABBREVIATIONS = NULL, job_data = eda_job_data("ccfid"),
                       label_map = function(d, ...) data.frame(key = names(d), label = names(d))))
  suppressWarnings(capture.output(eval(chunk("spec"), env)))
  out <- paste(capture.output(eval(chunk("overview-contents"), env)), collapse = "\n")
  # Only the exact names MRN and eMRN are record numbers: bnp_mrna and mrn_num
  # are study variables.
  expect_identical(env$shown$variable, c("year", "age", "carotid", "mrn_num", "bnp_mrna", "dt_surg"))
  expect_match(out, "Identifier columns, not described: ccfid, patientid, eMRN", fixed = TRUE)
})

test_that("dc-gfup, dp-gfup and dp-eda choose follow-up colors with the same code", {
  # dp-eda's copy is drawn and checked above; this keeps the others from drifting.
  # dp-gfup is deprecated, so its warning is muffled.
  block <- function(prefix, qualifier) {
    lines <- readLines(suppressWarnings(template_path(prefix, qualifier), classes = "hvtiRtemplates_deprecated"),
                       warn = FALSE)
    start <- grep("^if \\(exists\\(\"COLOURS\"", lines)
    end <- start + match("}", lines[-seq_len(start)])
    end <- end + match("}", lines[-seq_len(end)])
    lines[start:end]
  }
  expect_length(block("dc", "gfup"), 13L)
  expect_identical(block("dc", "gfup"), block("dp", "eda"))
  expect_identical(block("dp", "gfup"), block("dp", "eda"))
})

test_that("dc-gfup and dp-eda build their follow-up table with the same function", {
  block <- function(prefix, qualifier) {
    lines <- readLines(template_path(prefix, qualifier), warn = FALSE)
    start <- grep("^\\.followup_table <- function", lines)
    end <- start + match("}", lines[-seq_len(start)])
    lines[start:end]
  }
  expect_gt(length(block("dc", "gfup")), 10L)
  expect_identical(block("dc", "gfup"), block("dp", "eda"))
})

test_that("dp-postage and dp-eda shorten labels with the same code and edit points", {
  # dp-postage's copy is exercised in test-migrate-dp-postage.R; this keeps
  # dp-eda's from drifting from it.
  tl <- template_list()
  block <- function(qualifier, from, to) {
    lines <- readLines(tl$file[tl$name == paste0("dp.", qualifier)], warn = FALSE)
    start <- grep(from, lines)
    end <- start + grep(to, lines[-seq_len(start)])[1L]
    lines[start:end]
  }
  for (b in list(c("^# EDIT: the longest label", "^ABBREVIATIONS <- NULL$"),
                 c("^# Shortened labels stay distinct", "^}$"))) {
    expect_identical(block("postage", b[1], b[2]), block("eda", b[1], b[2]), info = b[1])
  }
  expect_length(block("eda", "^# Shortened labels stay distinct", "^}$"), 20L)
  # And each draws the key under its sections.
  for (q in c("postage", "eda")) {
    expect_true(any(grepl("^  abbreviation_key\\(vars\\)$", readLines(tl$file[tl$name == paste0("dp.", q)], warn = FALSE))),
                info = q)
  }
})
