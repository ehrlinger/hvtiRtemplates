# dc-eda is rendered, not only read: its sections call hv_followup_panels(),
# followup_check() and hv_eda_pages() at render time, and a static test would
# pass a template whose section chunk fails. scaffold_job() is in
# helper-migration.R. One fixture per render keeps the check time down.

# The fixture's iv_opyrs runs to 40, so the template's 1990 origin would place
# operations in 2030; the job refuses that, and these tests use 1980.
eda_edits <- list(
  "^ANALYSIS_SET <- " = "ANALYSIS_SET <- NULL",
  "^ORIGIN_YEAR <- " = "ORIGIN_YEAR <- 1980",
  # The fixture's reference column is a whole year, not the template's dt_surg.
  "^X_VAR <- " = "X_VAR <- \"year\""
)

# The spec chunk reads the ID and KEY the data step resolved from
# read_job_data()'s record; a spec-only test supplies that record.
eda_job_data <- function(id, key = id) {
  list(record = structure(data.frame(step = character(), value = character()), selection = list(id = id, key = key)))
}

# Figures embedded in a rendered report: images, plus the ggiraph widgets that
# carry a categorical page when ggiraph is installed. regmatches(), not
# length(gregexpr()): no match returns -1, whose length is 1.
n_embedded <- function(text) {
  count <- function(pattern) length(regmatches(text, gregexpr(pattern, text))[[1L]])
  count("src=\"data:image/png") + count("class=\"girafe html-widget")
}

test_that("dc-eda renders every section into one self-contained report", {
  skip_on_cran()
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  # An event panel too: its color and shape mapping is this template's own
  # code, not hv_followup_panels()'s, so test-dc-gfup-figure.R does not cover it here.
  edits <- c(eda_edits, list(
    "^EVENTS <- list\\(\\)$" = paste0(
      "EVENTS <- list(repair = list(event = \"repair\", time = \"iv_fup\", ",
      "death = \"dead\", death_time = \"iv_dead\", label = \"Repair\"))"
    ),
    "^ABBREVIATIONS <- NULL$" = "ABBREVIATIONS <- c(\"Goodness of follow-up\" = \"GFU\")"
  ))
  s <- scaffold_job("dc", "eda", edits, kind = "dp-postage")
  quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = TRUE)
  html <- sub("[.]qmd$", ".html", s$job)
  expect_true(file.exists(html))
  graphs <- file.path(s$root, "graphs", "cohort-eda")
  pages <- sprintf("dc-eda-%s-page-01.png", c("continuous", "percent", "count"))
  pngs <- file.path(graphs, c("dc-eda-gfup-all.png", "dc-eda-gfup-repair.png", pages))
  expect_true(all(file.exists(pngs)))
  # Each figure's publication copy sits beside its PNG, under the same name.
  expect_true(all(file.exists(sub("[.]png$", ".pdf", pngs))))
  text <- paste(readLines(html, warn = FALSE), collapse = "\n")
  for (heading in c("Overview", "Goodness of follow-up", "Continuous variables",
                    "Categorical variables, percent", "Categorical variables, counts")) {
    expect_match(text, paste0("<h2[^>]*>[^<]*", heading), info = heading)
  }
  expect_match(text, "<h3[^>]*>[^<]*Repair")
  # embed-resources: every saved figure is inside the report, as an image or,
  # for a categorical page with hover labels, as a widget. An image Quarto
  # could not find is left as a file link and would not be counted here.
  n_png <- length(list.files(graphs, "^dc-eda-.*[.]png$"))
  expect_identical(n_embedded(text), n_png)
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

test_that("dc-eda leaves out a section not named in SECTIONS", {
  skip_on_cran()
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  edits <- c(eda_edits, list("^SECTIONS <- " = "SECTIONS <- c(\"count\", \"continuous\")"))
  s <- scaffold_job("dc", "eda", edits, kind = "dp-postage", subfolder = "checks")
  quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = TRUE)
  graphs <- file.path(s$root, "graphs", "cohort-eda")
  expect_false(file.exists(file.path(graphs, "dc-eda-gfup-all.png")))
  expect_length(list.files(graphs, "^dc-eda-percent-"), 0L)
  expect_true(file.exists(file.path(graphs, "dc-eda-count-page-01.png")))
  # A job kept in a subfolder still embeds its pages.
  text <- paste(readLines(sub("[.]qmd$", ".html", s$job), warn = FALSE), collapse = "\n")
  n_png <- length(list.files(graphs, "^dc-eda-.*[.]png$"))
  expect_identical(n_embedded(text), n_png)
  # The heading, not the folded source that prints it.
  expect_false(grepl("<h2[^>]*>[^<]*Goodness of follow-up", text))
})

test_that("dc-eda colors every point of an event panel, by the house rule or from COLORS", {
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
  job <- add_job("dc", "cohort", "eda", dir = root, qualifier = "eda")
  chunk <- function(label) {
    lines <- readLines(job, warn = FALSE)
    start <- match(paste0("#| label: ", setup_label(label)), lines)
    end <- start + match("```", lines[-seq_len(start)])
    chunk_expression(lines[seq.int(start + 1L, end - 1L)], label)
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
    # The fixture's reference column, as a study sets X_VAR to its own.
    env$X_VAR <- "year"
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

test_that("dc-eda never draws the job's ID or KEY, which read_job_data() keeps", {
  # read_job_data() drops MRN, eMRN and other direct identifiers but keeps the ID, so the ID reaches d and
  # the spec chunk must leave it out. Run through a real study: the data chunk
  # and then the spec chunk, as a render would.
  root <- file.path(withr::local_tempdir(), "study")
  suppressMessages(hvtiRutilities::study_setup(root, study = "EDA identifiers", study_tracker_id = 1L, renv = FALSE))
  n <- 12L
  built <- data.frame(year = 2000L + seq_len(n), ccfid = 1000L + seq_len(n), randid = 3000L + seq_len(n),
                      MRN = 5000L + seq_len(n), study_id = 7000L + seq_len(n), hosp_id = 9000L + seq_len(n),
                      pt_mrn_num = rep(0:1, 6), visit_mo = 3L * seq_len(n),
                      age = 40 + seq_len(n),
                      # Identifiers from an SSDI join: by name, and an SSN under a name nobody listed.
                      ssn = 100000000 + 7919 * seq_len(n), ssdi_ref = 100000000 + 7919 * seq_len(n),
                      last_name = "x")
  utils::write.csv(built, file.path(hvtiRutilities::study_dir("datasets", root), "built.csv"), row.names = FALSE)
  suppressWarnings(suppressMessages(hvtiRutilities::register_data(root, built = "built.csv")))
  lines <- readLines(template_path("dc", "eda"), warn = FALSE)
  chunk <- function(label) {
    start <- match(paste0("#| label: ", setup_label(label)), lines)
    end <- start + match("```", lines[-seq_len(start)])
    chunk_expression(lines[seq.int(start + 1L, end - 1L)], label)
  }
  run <- function(id = "ccfid", variables = NULL, key = id) {
    env <- new.env(parent = globalenv())
    env$.root <- root
    env$study_config <- hvtiRutilities::study_config
    env$label_map <- function(d, ...) data.frame(key = names(d), label = names(d))
    eval(chunk("edit-study-choices"), env)
    # Every column, so the identifier rules below are what decide.
    env$VARIABLE_SET <- "all"
    # The study's reference column, as a study sets X_VAR to its own.
    env$X_VAR <- "year"
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
  # An SSN never reaches the report, whether its name or its values give it away.
  expect_false(any(c("ssn", "ssdi_ref", "last_name") %in% names(env$d)))
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
  # ccfid is dropped at read when it is not the ID.
  expect_false("ccfid" %in% names(env$d))

  # Named in VARIABLES, the ID stops the job.
  expect_error(run(id = "randid", variables = c("age", "randid")), "VARIABLES names randid")

  # A KEY column beside the ID, such as a visit time, is left out by default and
  # stops the job when named.
  expect_true("visit_mo" %in% run()$VARIABLES)
  env <- run(key = c("ccfid", "visit_mo"))
  expect_false("visit_mo" %in% env$VARIABLES)
  expect_error(run(key = c("ccfid", "visit_mo"), variables = c("age", "visit_mo")), "VARIABLES names visit_mo")
  # hosp_id's values look like record numbers, so naming it stops the job.
  expect_error(run(variables = c("age", "hosp_id")), "VARIABLES names hosp_id, whose values look like record numbers")
  # Once the job clears that shape, the name, date and free-text rules still flag it.
  withr::local_options(hvtiRtemplates.not_identifiers = "hosp_id")
  expect_warning(env <- run(variables = c("age", "hosp_id")),
                 "Selected likely identifier or date field\\(s\\): hosp_id")
  expect_identical(env$VARIABLES, c("age", "hosp_id"))
})

# A chunk of the dc-eda template, parsed. The tests below run the spec chunk,
# and the section chunks after it, without a render: the rules under test are
# the template's own code, not a package function's.
eda_chunk <- function(label) {
  lines <- readLines(template_path("dc", "eda"), warn = FALSE)
  start <- match(paste0("#| label: ", setup_label(label)), lines)  # nolint: object_usage_linter.
  end <- start + match("```", lines[-seq_len(start)])
  chunk_expression(lines[seq.int(start + 1L, end - 1L)], label)  # nolint: object_usage_linter.
}

# The choices the spec chunk reads, with a stand-in label_map(); `...` replaces
# any of them, NULL included.
eda_spec_env <- function(d, ...) {
  env <- list2env(list(d = d, X_VAR = "year", X_LABEL = "Year of operation", VARIABLES = NULL, VARIABLE_SET = "all",
                       EXCLUDE = character(),
                       GRID_NCOL = 4L, GRID_NROW = 4L, UNIQUE_LIMIT = 6L,
                       SECTIONS = c("continuous", "percent", "count"), ALPHA = 0.5,
                       .cfg = list(), LABEL_MAX = 40, ABBREVIATIONS = NULL, job_data = eda_job_data("ccfid"),
                       label_map = function(d, ...) data.frame(key = names(d), label = names(d))))
  args <- list(...)
  for (name in names(args)) assign(name, args[[name]], envir = env)
  env
}

test_that("dc-eda's spec chunk checks every variable and plotting choice", {
  spec <- eda_chunk("spec")
  env <- eda_spec_env(data.frame(year = 1:10, age = 41:50, hosp_id = 11:20, visit_date = 21:30),
                      VARIABLES = "age")
  expect_no_error(eval(spec, env))
  for (field in c("X_VAR", "X_LABEL", "VARIABLES", "VARIABLE_SET", "EXCLUDE", "GRID_NCOL", "GRID_NROW", "UNIQUE_LIMIT", "SECTIONS",
                  "ALPHA", "LABEL_MAX", "ABBREVIATIONS")) {
    original <- env[[field]]
    env[[field]] <- NA
    expect_error(eval(spec, env), info = field)
    env[[field]] <- original
  }
  # The two label settings fail naming themselves, not label_map()'s arguments.
  env$LABEL_MAX <- 3
  expect_error(eval(spec, env), "LABEL_MAX")
  env$LABEL_MAX <- Inf
  expect_no_error(eval(spec, env))
  env$LABEL_MAX <- 40
  env$ABBREVIATIONS <- c("SP", "Proc")
  expect_error(eval(spec, env), "ABBREVIATIONS")
  env$ABBREVIATIONS <- NULL
  env$VARIABLES <- "absent"
  expect_error(eval(spec, env), "Unknown EDA")
  env$VARIABLES <- c("hosp_id", "visit_date")
  expect_warning(eval(spec, env), "identifier or date")
  env$VARIABLES <- c("age", "year")
  env$EXCLUDE <- "year"
  eval(spec, env)
  expect_identical(env$VARIABLES, "age")
  env$EXCLUDE <- "age"
  expect_error(eval(spec, env), "No EDA variables")
})

# The first panel of a section's first page, drawn from the spec chunk's data.
eda_first_panel <- function(env, section, vars) {
  sec <- hvtiPlotR::hv_eda_pages(env$.d_eda, x_col = env$X_LABEL, section = section, vars = vars)
  plot(sec, ncol = 2L, nrow = 4L)[[1L]][[1L]]
}

test_that("a date X_VAR is drawn as a decimal year under X_LABEL: whole-year bars, decimal points", {
  skip_if_not_installed("hvtiPlotR")
  # 2004 is a leap year, so its 1 July is day 183 of 366.
  dates <- as.Date(c("2001-01-01", "2001-07-02", "2002-01-01", "2003-01-01", "2004-01-01", "2004-07-01",
                     "2005-01-01", "2005-06-01", "2006-01-01", "2006-12-31"))
  d <- data.frame(dt_surg = dates, age = 41:50, valve = factor(rep(c("A", "B"), 5L)))
  env <- eda_spec_env(d, X_VAR = "dt_surg", VARIABLES = c("age", "valve", "dt_surg"))
  suppressWarnings(eval(eda_chunk("spec"), env))
  x <- env$.d_eda[["Year of operation"]]
  expect_equal(x[c(1L, 2L, 6L)], c(2001, 2001 + 182 / 365, 2004 + 182 / 366))
  # The date itself is never drawn as a variable, and the data as read are left alone.
  expect_identical(env$VARIABLES, c("age", "valve"))
  expect_false("Year of operation" %in% names(env$d))
  bars <- eda_first_panel(env, "percent", "valve")
  expect_identical(bars$labels$x, "Year of operation")
  expect_identical(ggplot2::ggplot_build(bars)$layout$panel_params[[1L]]$x$get_labels(), as.character(2001:2006))
  points <- eda_first_panel(env, "continuous", "age")
  expect_identical(points$labels$x, "Year of operation")
  expect_true(any(ggplot2::ggplot_build(points)$data[[1L]]$x %% 1 != 0))
})

test_that("a numeric X_VAR is drawn as it is, under X_LABEL", {
  d <- data.frame(year = 2001:2010, age = 41:50)
  env <- eda_spec_env(d, VARIABLES = "age")
  eval(eda_chunk("spec"), env)
  expect_identical(env$.d_eda[["Year of operation"]], d$year)
})

test_that("X_VAR cannot name a column no report may show", {
  d <- data.frame(ccfid = rep(1:5, 2L), recordnumber = 7700000L + 1:10, year = rep(2001:2005, 2L), age = 41:50)
  expect_error(eval(eda_chunk("spec"), eda_spec_env(d, X_VAR = "ccfid", VARIABLES = "age")), "X_VAR names ccfid")
  expect_error(eval(eda_chunk("spec"), eda_spec_env(d, X_VAR = "recordnumber", VARIABLES = "age")), "look like record numbers")
})

test_that("a missing X_VAR stops and says where to set it", {
  env <- eda_spec_env(data.frame(year = 2001:2010, age = 41:50), X_VAR = "dt_surg", VARIABLES = "age")
  expect_error(eval(eda_chunk("spec"), env),
               "Unknown EDA column(s): dt_surg. Set X_VAR in the study choices to the study's reference date or year column.",
               fixed = TRUE)
})

test_that("dc-eda VARIABLES = NULL draws every column but ids, dates and exclusions, and says so", {
  spec <- eda_chunk("spec")
  env <- eda_spec_env(data.frame(year = 1:10, age = 41:50, patient_id = 11:20, op_date = Sys.Date() + 0:9,
                                 female = rep(0:1, 5), bmi = 21:30),
                      EXCLUDE = "bmi")
  out <- capture.output(eval(spec, env))
  expect_identical(env$VARIABLES, c("age", "female"))
  expect_match(paste(out, collapse = " "), "patient_id, op_date")
  env$VARIABLES <- c("age", "nope1", "nope2")
  expect_error(eval(spec, env), "nope1, nope2")
  env$VARIABLES <- NULL
  env$SECTIONS <- c("continuous", "percentage")
  expect_error(eval(spec, env), "SECTIONS")
  # A repeated section would draw twice over the same page files.
  env$SECTIONS <- c("percent", "percent")
  expect_error(eval(spec, env), "SECTIONS")
})

test_that("dc-eda VARIABLE_SET = \"ods\" draws the house list's columns the data has, in the list's order", {
  spec <- eda_chunk("spec")
  # bmi before female in the data; the list has female first. hosp_tag is a
  # study's own column, outside the list.
  env <- eda_spec_env(data.frame(year = 1:10, bmi = 21:30, hosp_tag = rep(1:2, 5), female = rep(0:1, 5), age = 41:50,
                                 ccfid = 11:20, dead = rep(0:1, 5)),
                      VARIABLE_SET = "ods", EXCLUDE = "dead")
  out <- paste(capture.output(eval(spec, env)), collapse = " ")
  ods <- unlist(hvtiRtemplates:::.ods_groups(), use.names = FALSE)
  expect_identical(env$VARIABLES, c("female", "age", "bmi"))
  expect_identical(env$VARIABLES, intersect(ods, env$VARIABLES))
  expect_match(out, paste("3 of the", length(ods), "columns on the house ODS list"), fixed = TRUE)
  expect_match(out, "hosp_tag, ccfid", fixed = TRUE)
  # Named columns are drawn as named, whatever the set.
  env$VARIABLES <- c("hosp_tag", "age")
  eval(spec, env)
  expect_identical(env$VARIABLES, c("hosp_tag", "age"))
  # A name in capitals is still on the list, and keeps its own spelling.
  env <- eda_spec_env(data.frame(year = 1:10, BMI = 21:30, Age = 41:50), VARIABLE_SET = "ods")
  capture.output(eval(spec, env))
  expect_identical(env$VARIABLES, c("Age", "BMI"))
  # A dataset with none of the list's columns stops, and says how to go on.
  env <- eda_spec_env(data.frame(year = 1:10, hosp_tag = 1:10), VARIABLE_SET = "ods")
  expect_error(eval(spec, env), "VARIABLE_SET <- \"all\"", fixed = TRUE)
  env$VARIABLE_SET <- "every"
  expect_error(eval(spec, env), "VARIABLE_SET must be")
})

test_that("a follow-up-only dc-eda neither needs nor checks the house ODS list", {
  # Raised in review of #455: a job drawing only follow-up stopped because an
  # unused descriptive list had no column in the data.
  env <- eda_spec_env(data.frame(year = 1:10, hospital = rep(1:2, 5)), VARIABLE_SET = "ods", SECTIONS = "followup")
  expect_no_error(capture.output(eval(eda_chunk("spec"), env)))
  # Any descriptive section brings the list back, and its stop.
  env <- eda_spec_env(data.frame(year = 1:10, hospital = rep(1:2, 5)), VARIABLE_SET = "ods",
                      SECTIONS = c("followup", "percent"))
  expect_error(eval(eda_chunk("spec"), env), "None of the house ODS list")
})

test_that("dc-eda's setup stops, naming the update, under an hvtiRtemplates without the ODS list", {
  # A job copied from this template can render in a study library that still
  # holds an older hvtiRtemplates, possibly of the same version number.
  lines <- readLines(template_path("dc", "eda"), warn = FALSE)
  start <- grep('^if \\(!exists\\(".ods_groups"', lines)
  expect_length(start, 1L)
  end <- start + match("}", lines[-seq_len(start)])
  check <- parse(text = lines[start:end])
  older <- new.env()
  older$asNamespace <- function(...) new.env()
  expect_error(eval(check, older), "hvtiR::update(force = TRUE)", fixed = TRUE)
  expect_no_error(eval(check, new.env()))
})

test_that("the template's VARIABLE_SET sits outside the region migrate_job() rewrites, defaulting to the ODS list", {
  lines <- readLines(template_path("dc", "eda"), warn = FALSE)
  at <- grep("^VARIABLE_SET <- ", lines)
  expect_length(at, 1L)
  expect_identical(lines[at], 'VARIABLE_SET <- "ods"')
  expect_gt(at, grep("^# MIGRATE-END: dc-eda-variables$", lines))
})

test_that("dc-eda VARIABLES = NULL leaves out identifiers written without a separator", {
  spec <- eda_chunk("spec")
  # ccfid, the CCF patient identifier, has no "_" before "id", so the token rule
  # alone drew it as one bar per patient. carotid, steroid and case end the same
  # way and are study variables, so a bare id$ would be the opposite defect.
  # The job's ID is another column here, so the name rule alone must catch ccfid.
  n <- 12L
  env <- eda_spec_env(data.frame(year = seq_len(n), age = 40 + seq_len(n), ccfid = 1000L + seq_len(n),
                                 patientid = sprintf("P%03d", seq_len(n)), mrn = 5000L + seq_len(n),
                                 eMRN = 7000L + seq_len(n), pt_mrn_num = rep(0:1, 6), bnp_mrna = 0.5 * seq_len(n),
                                 surgeon_note = sprintf("note %d", seq_len(n)),
                                 carotid = rep(0:1, 6), steroid = rep(0:1, 6), case = rep(0:1, 6)),
                      job_data = eda_job_data("record_key"))
  out <- capture.output(eval(spec, env))
  # Only the exact names MRN and eMRN are record numbers: pt_mrn_num and the
  # mRNA variable bnp_mrna are study variables like any other.
  expect_identical(env$VARIABLES, c("age", "pt_mrn_num", "bnp_mrna", "carotid", "steroid", "case"))
  expect_match(paste(out, collapse = " "), "ccfid, patientid, mrn, eMRN, surgeon_note")
  # Below ten values a distinct character column is kept: a small check frame
  # is not a register.
  env$d <- env$d[1:9, ]
  env$VARIABLES <- NULL
  capture.output(eval(spec, env))
  expect_true("surgeon_note" %in% env$VARIABLES)
  expect_false("ccfid" %in% env$VARIABLES)
})

test_that("dc-eda's overview leaves out identifiers but keeps dates", {
  local_child_chunks()
  # Named in VARIABLES, so the spec chunk's NULL branch does not decide this:
  # the overview applies the rule itself.
  lines <- readLines(template_path("dc", "eda"), warn = FALSE)
  chunk <- function(label) {
    start <- match(paste0("#| label: ", setup_label(label)), lines)
    end <- start + match("```", lines[-seq_len(start)])
    chunk_expression(lines[seq.int(start + 1L, end - 1L)], label)
  }
  n <- 12L
  env <- list2env(list(d = data.frame(year = seq_len(n), age = 40 + seq_len(n), ccfid = 1000L + seq_len(n),
                                      patientid = sprintf("P%03d", seq_len(n)), carotid = rep(0:1, 6), eMRN = 5000L + seq_len(n),
                                      mrn_num = rep(0:1, 6),
                                      bnp_mrna = 0.5 * seq_len(n), dt_surg = as.Date("2020-01-01") + seq_len(n)),
                       X_VAR = "year", X_LABEL = "Year of operation", VARIABLES = "age",
                       VARIABLE_SET = "all", EXCLUDE = character(),
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

test_that("dc-gfup and dc-eda choose follow-up colors with the same code", {
  # dc-eda's copy is drawn and checked above; this keeps dc-gfup's from drifting.
  block <- function(prefix, qualifier) {
    lines <- readLines(template_path(prefix, qualifier), warn = FALSE)
    start <- grep("^if \\(exists\\(\"COLOURS\"", lines)
    end <- grep("^status_colors <- function", lines)
    end <- end + match("}", lines[-seq_len(end)])
    lines[start:end]
  }
  expect_length(block("dc", "gfup"), 25L)
  expect_identical(block("dc", "gfup"), block("dc", "eda"))
})

test_that("dc-gfup and dc-eda draw event panels with the same code", {
  # Both pass EVENTS to hv_followup_panels(), so both take competing events;
  # the levels and the caption key must follow the panel's own event_levels.
  block <- function(prefix, qualifier) {
    lines <- readLines(template_path(prefix, qualifier), warn = FALSE)
    start <- grep("^    levels <- fp\\$tables\\$panels\\[\\[nm\\]\\]\\$meta\\$event_levels$", lines)
    end <- start + match("  }", lines[-seq_len(start)])
    lines[start:end]
  }
  expect_gt(length(block("dc", "gfup")), 10L)
  expect_identical(block("dc", "gfup"), block("dc", "eda"))
})

test_that("dc-gfup and dc-eda build their follow-up table with the same function", {
  block <- function(prefix, qualifier) {
    lines <- readLines(template_path(prefix, qualifier), warn = FALSE)
    start <- grep("^\\.followup_table <- function", lines)
    end <- start + match("}", lines[-seq_len(start)])
    lines[start:end]
  }
  expect_gt(length(block("dc", "gfup")), 10L)
  expect_identical(block("dc", "gfup"), block("dc", "eda"))
  # And with the same statistics, so neither table gains a column alone.
  stats <- function(prefix, qualifier) {
    grep("^\\.followup_stats <- ", readLines(template_path(prefix, qualifier), warn = FALSE), value = TRUE)
  }
  expect_length(stats("dc", "gfup"), 1L)
  expect_identical(stats("dc", "gfup"), stats("dc", "eda"))
})

# The variable sections, run through the template's own set, spec and sections
# chunks over a migration fixture's data, as a render would after its data
# step. Returns the page files and everything the sections printed.
eda_draw <- function(root, d, ...) {
  env <- eda_spec_env(d, .root = root, X_VAR = "iv_dead", GRID_NCOL = 2L, GRID_NROW = 1L,
                      label_map = hvtiRutilities::label_map, .cfg = hvtiRutilities::study_config(root),
                      theme_hv_manuscript = hvtiPlotR::theme_hv_manuscript, scale_fill_hv = hvtiPlotR::scale_fill_hv,
                      SAVE_FIGURES = TRUE, FIGURES = NULL)
  args <- list(...)
  for (name in names(args)) assign(name, args[[name]], envir = env)
  for (label in c("set", "spec", "sections")) eval(eda_chunk(label), env)
  files <- character(0)
  out <- utils::capture.output(for (section in env$SECTIONS) files <- c(files, env$draw_section(section)))
  list(env = env, files = files, text = paste(out, collapse = "\n"))
}

test_that("dc-eda routes its pages through numbered study folders", {
  root <- migration_study_fixture("dp-postage")
  local_child_chunks()
  d <- hvtiRutilities::read_built(hvtiRutilities::study_config(root))
  for (name in names(d)) attr(d[[name]], "label") <- paste("Synthetic", name)
  folders <- c("datasets", "descriptive", "distributions", "analyses", "graphs", "documents", "estimates")
  numbered <- c("00_datasets", "10_descriptive", "20_distributions", "30_analyses", "40_graphs", "50_documents",
                "90_estimates")
  expect_true(all(file.rename(file.path(root, folders), file.path(root, numbered))))
  drawn <- eda_draw(root, d, VARIABLES = c("age", "bmi", "lvmassi"))
  # All three are continuous, so only that section draws pages: two at 2 x 1.
  expected <- file.path(root, "40_graphs", "cohort-eda", sprintf("dc-eda-continuous-page-%02d.png", 1:2))
  expect_identical(as.character(drawn$files), expected)
  expect_true(all(file.info(expected)$size > 1000))
  expect_false(dir.exists(file.path(root, "graphs")))
})

test_that("dc-eda draws its categorical pages in the role colors", {
  # The page is handed to ggsave() whole, so capture it there and build each
  # panel: every bar must be a house color, blue first, missing gray.
  root <- migration_study_fixture("dp-postage")
  local_child_chunks()
  saved <- list()
  local_mocked_bindings(ggsave = function(filename, plot, ...) {
    saved[[basename(filename)]] <<- plot
    invisible(filename)
  }, .package = "ggplot2")
  d <- hvtiRutilities::read_built(hvtiRutilities::study_config(root))
  suppressWarnings(eda_draw(root, d, VARIABLES = c("female", "hx_chf"), SECTIONS = "percent"))
  kept <- c("png", "pdf", if (requireNamespace("ragg", quietly = TRUE)) "tiff")
  expect_identical(names(saved), paste0("dc-eda-percent-page-01.", kept))
  page <- saved[[1L]]
  fills <- unique(unlist(lapply(seq_along(page), function(k) ggplot2::ggplot_build(page[[k]])$data[[1L]]$fill)))
  expect_true(all(fills %in% c(hvtiPlotR::hv_ppt_palette("light"), "#CCCCCC")), info = paste(fills, collapse = ", "))
  expect_true("#0072B2" %in% fills)
})

# These tests exercise the job, study and initials levels of the abbreviation
# list. hvtiRutilities (>= 1.4.3) adds a group default list underneath, which
# shortens "aortic valve replacement" too; turn it off so each test sees only
# the level it is about. The group list has its own test below.
without_group_list <- function(env = parent.frame()) {
  real <- hvtiRutilities::study_abbreviations
  testthat::local_mocked_bindings(
    study_abbreviations = function(cfg, extra = NULL, defaults = TRUE) real(cfg, extra = extra, defaults = FALSE),
    .package = "hvtiRutilities", .env = env
  )
}

test_that("dc-eda shortens labels that share a heading and prints their key", {
  # Two labels over LABEL_MAX share a heading: both show its abbreviation, and
  # the section says what it stands for. A job's own entry beats the initials.
  root <- migration_study_fixture("dp-postage")
  local_child_chunks()
  local_mocked_bindings(ggsave = function(filename, plot, ...) invisible(filename), .package = "ggplot2")
  without_group_list()
  d <- hvtiRutilities::read_built(hvtiRutilities::study_config(root))
  attr(d$female, "label") <- "Surgical procedure: aortic valve replacement with root enlargement"
  attr(d$hx_chf, "label") <- "Surgical procedure: mitral valve repair with annuloplasty ring"
  run_pages <- function(abbreviations) {
    drawn <- suppressWarnings(eda_draw(root, d, VARIABLES = c("female", "hx_chf"), SECTIONS = "percent",
                                       .cfg = list(), ABBREVIATIONS = abbreviations))
    list(labels = unname(drawn$env$labels[c("female", "hx_chf")]), text = drawn$text)
  }
  initials <- run_pages(NULL)
  expect_match(initials$labels, "^SP: ")
  expect_match(initials$text, "Abbreviations: SP = Surgical procedure.", fixed = TRUE)
  own <- run_pages(c("Surgical procedure" = "Proc"))
  expect_match(own$labels, "^Proc: ")
  expect_match(own$text, "Abbreviations: Proc = Surgical procedure.", fixed = TRUE)
})

test_that("dc-eda prints a key only under sections whose labels were shortened, from every level", {
  # A label that already says "SP" in its own words (systolic pressure) is not
  # a shortened label: its section gets no key claiming SP = Surgical procedure.
  # The study's list applies unless the job overrides it.
  root <- migration_study_fixture("dp-postage")
  local_child_chunks()
  local_mocked_bindings(ggsave = function(filename, plot, ...) invisible(filename), .package = "ggplot2")
  without_group_list()
  d <- hvtiRutilities::read_built(hvtiRutilities::study_config(root))
  attr(d$age, "label") <- "SP at admission (mmHg)"
  attr(d$female, "label") <- "Surgical procedure: aortic valve replacement with root enlargement"
  attr(d$hx_chf, "label") <- "Surgical procedure: mitral valve repair with annuloplasty ring"
  run_pages <- function(cfg, abbreviations) {
    drawn <- suppressWarnings(eda_draw(root, d, VARIABLES = c("age", "female", "hx_chf"),
                                       SECTIONS = c("continuous", "percent"), .cfg = cfg, ABBREVIATIONS = abbreviations))
    list(labels = unname(drawn$env$labels[c("female", "hx_chf")]), text = drawn$text)
  }
  initials <- run_pages(list(), NULL)
  # "\n## ", so a page heading ("### Categorical ...") does not split it again.
  sections <- strsplit(initials$text, "\n## Categorical", fixed = TRUE)[[1L]]
  expect_length(sections, 2L)
  expect_false(grepl("Abbreviations:", sections[1L], fixed = TRUE))
  expect_match(sections[2L], "Abbreviations: SP = Surgical procedure.", fixed = TRUE)
  study <- run_pages(list(abbreviations = list("Surgical procedure" = "SProc")), NULL)
  expect_match(study$labels, "^SProc: ")
  job <- run_pages(list(abbreviations = list("Surgical procedure" = "SProc")), c("Surgical procedure" = "Proc"))
  expect_match(job$labels, "^Proc: ")
})

test_that("dc-eda's group abbreviation list shortens further, when it is installed", {
  skip_if(!length(hvtiRutilities::study_abbreviations(list())), "hvtiRutilities has no group abbreviation list")
  root <- migration_study_fixture("dp-postage")
  local_child_chunks()
  local_mocked_bindings(ggsave = function(filename, plot, ...) invisible(filename), .package = "ggplot2")
  d <- hvtiRutilities::read_built(hvtiRutilities::study_config(root))
  attr(d$female, "label") <- "Surgical procedure: aortic valve replacement with root enlargement"
  attr(d$hx_chf, "label") <- "Surgical procedure: mitral valve repair with annuloplasty ring"
  drawn <- suppressWarnings(eda_draw(root, d, VARIABLES = c("female", "hx_chf"), SECTIONS = "percent", .cfg = list()))
  # The group list names both procedures; the key lists every entry it used.
  expect_match(drawn$text, "AVR = Aortic valve replacement", fixed = TRUE)
  expect_match(drawn$text, "MVr = Mitral valve repair", fixed = TRUE)
})

test_that("dc-eda's key comes from label_map()'s abbreviations_by_key, not from label text", {
  # A label that says "SP" in its own words, is over LABEL_MAX and is only cut,
  # contains the token SP without SP having shortened anything. Reading the cut
  # text would print SP = Surgical procedure under its section.
  root <- migration_study_fixture("dp-postage")
  local_child_chunks()
  local_mocked_bindings(ggsave = function(filename, plot, ...) invisible(filename), .package = "ggplot2")
  without_group_list()
  d <- hvtiRutilities::read_built(hvtiRutilities::study_config(root))
  attr(d$age, "label") <- "SP indicates systolic pressure measured at admission to hospital"
  attr(d$female, "label") <- "Surgical procedure: aortic valve replacement with root enlargement"
  attr(d$hx_chf, "label") <- "Surgical procedure: mitral valve repair with annuloplasty ring"
  drawn <- suppressWarnings(eda_draw(root, d, VARIABLES = c("age", "female", "hx_chf"),
                                     SECTIONS = c("continuous", "percent"), .cfg = list()))
  # The age label was cut, not abbreviated, and still contains the token.
  expect_match(drawn$env$labels[["age"]], "^SP indicates .*[.][.][.]$")
  sections <- strsplit(drawn$text, "\n## Categorical", fixed = TRUE)[[1L]]
  expect_length(sections, 2L)
  expect_false(grepl("Abbreviations:", sections[1L], fixed = TRUE))
  expect_match(sections[2L], "Abbreviations: SP = Surgical procedure.", fixed = TRUE)
})
