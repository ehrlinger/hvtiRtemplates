# What every report says about its run: the top box .job_setup() prints, and the
# "About this run" table and `run` provenance the last chunk adds. The design is
# dev/specs/2026-10-12-setup-and-run-info-design.md, sections 4 to 6. All data
# are synthetic.

# A study, a job set up in it, and the study's config.
run_fixture <- function(.local_envir = parent.frame()) {
  fx <- setup_fixture(.local_envir = .local_envir)  # nolint: object_usage_linter.
  env <- new.env(parent = globalenv())
  r <- run_setup(env = env)  # nolint: object_usage_linter.
  list(root = fx$root, env = env, run = r$job$run, out = r$out, cfg = hvtiRutilities::study_config(start = fx$root))
}

run_facts <- function(rf, data = list(), artifacts = list()) {
  hvtiRtemplates:::.run_facts(rf$run, data = data, artifacts = artifacts, cfg = rf$cfg, envir = rf$env)
}

test_that("the run is stamped with the user and host, which two environment variables override", {
  withr::with_envvar(c(HVTI_RUN_USER = NA, HVTI_RUN_HOST = NA), {
    id <- hvtiRtemplates:::.run_identity()
    expect_identical(id$user, unname(Sys.info()[["user"]]))
    expect_identical(id$host, unname(Sys.info()[["nodename"]]))
  })
  withr::with_envvar(c(HVTI_RUN_USER = "gallery", HVTI_RUN_HOST = "gallery-host"), {
    id <- hvtiRtemplates:::.run_identity()
    expect_identical(id, list(user = "gallery", host = "gallery-host"))
  })
  withr::with_envvar(c(HVTI_RUN_USER = "", HVTI_RUN_HOST = ""), {
    expect_identical(hvtiRtemplates:::.run_identity()$user, unname(Sys.info()[["user"]]))
  })
})

test_that("the top box names final or draft, the dataset version and its registration, who ran it, and the package", {
  withr::local_envvar(HVTI_RUN_USER = "tester", HVTI_RUN_HOST = "testhost")
  rf <- run_fixture()
  box <- grep("^\\*\\*final\\*\\*", rf$out, value = TRUE)
  expect_length(box, 1L)
  expect_match(box, "data `built` `built_[0-9]{8}[.]parquet`, registered [0-9]{4}-[0-9]{2}-[0-9]{2}")
  expect_match(box, paste0("registered ", format(Sys.Date())), fixed = TRUE)
  expect_match(box, "rendered by tester on testhost", fixed = TRUE)
  expect_match(box, paste0("hvtiRtemplates ", utils::packageVersion("hvtiRtemplates")), fixed = TRUE)
  expect_match(rf$out[[2L]], "^::: \\{\\.callout")
  expect_identical(rf$out[[length(rf$out) - 1L]], ":::")
})

test_that("a draft's box counts the open markers and the skipped chunks", {
  setup_fixture(c(edit_marker("one"), edit_marker("two"),
                  "```{r}", "#| skip: \"waiting\"", "x <- 1", "```"))
  expect_warning(expect_warning(r <- run_setup()))
  box <- grep("^\\*\\*draft\\*\\*", r$out, value = TRUE)
  expect_length(box, 1L)
  expect_match(box, "^\\*\\*draft\\*\\* \\(2 open markers, 1 skipped chunk\\)")
})

test_that("a study with no registered dataset gets a box without the dataset clause", {
  fx <- setup_fixture()
  unlink(file.path(fx$root, "manifest.yaml"))
  r <- run_setup()
  box <- grep("^\\*\\*final\\*\\*", r$out, value = TRUE)
  expect_length(box, 1L)
  expect_false(grepl("data `", box, fixed = TRUE))
  expect_match(box, "rendered by ", fixed = TRUE)
})

test_that("the end table's facts cover the run, the job and a dataset read", {
  withr::local_envvar(HVTI_RUN_USER = "tester", HVTI_RUN_HOST = "testhost")
  rf <- run_fixture()
  job <- read_job_data(rf$cfg, where = quote(age >= 30))
  facts <- run_facts(rf, data = list(job$provenance))
  expect_true(all(c("status", "user", "job", "datasets", "upstream", "reproducibility") %in% names(facts)))
  expect_identical(facts$user, "tester")
  expect_identical(facts$host, "testhost")
  expect_identical(facts$status, "final")
  expect_identical(facts$open_markers, 0L)
  expect_match(facts$start, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}[+-][0-9]{4}$")
  expect_match(facts$end, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}[+-][0-9]{4}$")
  expect_true(nzchar(facts$time_zone))
  expect_gte(facts$duration_seconds, 0)
  expect_identical(facts$job$file, "dc.general.cohort.eda.qmd")
  expect_identical(facts$job$template, "dc.general")
  expect_identical(facts$job$prefix, "dc")
  expect_identical(facts$job$qualifier, "general")
  expect_identical(facts$job$subject, "cohort")
  expect_identical(facts$job$type, "eda")
  expect_identical(facts$job$hvtiRtemplates, as.character(utils::packageVersion("hvtiRtemplates")))
  expect_length(facts$datasets, 1L)
  ds <- facts$datasets[[1L]]
  expect_identical(ds$name, "built")
  expect_identical(ds$version_file, basename(job$provenance$path))
  expect_match(ds$version_file, "^built_[0-9]{8}[.]parquet$")
  expect_identical(ds$registered, format(Sys.Date()))
  expect_identical(ds$source_file, "built.csv")
  expect_identical(ds$rows, nrow(job$data))
  expect_identical(ds$patients, length(unique(job$data$ccfid)))
  expect_identical(ds$where, "age >= 30")
  expect_identical(ds$sha256, substr(job$provenance$sha256, 1L, 12L))
  expect_identical(nchar(ds$sha256), 12L)
  expect_identical(ds$manifest, "current")
  expect_length(facts$upstream, 0L)
})

test_that("a dataset read with no WHERE says none, and a read counts once however often it is repeated", {
  rf <- run_fixture()
  first <- read_job_data(rf$cfg)
  read_job_data(rf$cfg)
  facts <- run_facts(rf, data = list(first$provenance, first$provenance))
  expect_length(facts$datasets, 1L)
  expect_identical(facts$datasets[[1L]]$where, character(0))
})

test_that("one dataset read under two filters is listed once for each", {
  rf <- run_fixture()
  adults <- read_job_data(rf$cfg, where = quote(age >= 30))
  everyone <- read_job_data(rf$cfg)
  facts <- run_facts(rf, data = list(adults$provenance, everyone$provenance))
  expect_length(facts$datasets, 2L)
  expect_identical(vapply(facts$datasets, function(d) paste(d$where, collapse = ";"), ""), c("age >= 30", ""))
  expect_identical(vapply(facts$datasets, `[[`, 0L, "rows"), c(nrow(adults$data), nrow(everyone$data)))
  expect_identical(facts$datasets[[1L]]$sha256, facts$datasets[[2L]]$sha256)
})

test_that("a newer file waiting is reported against the version the job read", {
  rf <- run_fixture()
  utils::write.csv(hazard_data(n = 170L), file.path(hvtiRutilities::study_dir("datasets", rf$root), "built.csv"),
                   row.names = FALSE)
  job <- read_job_data(rf$cfg)
  facts <- run_facts(rf, data = list(job$provenance))
  expect_identical(facts$datasets[[1L]]$manifest, "newer file waiting")
  expect_identical(facts$datasets[[1L]]$rows, 160L)
})

test_that("the table holds every field, by group", {
  withr::local_envvar(HVTI_RUN_USER = "tester", HVTI_RUN_HOST = "testhost")
  rf <- run_fixture()
  job <- read_job_data(rf$cfg, where = quote(age >= 30))
  table <- paste(hvtiRtemplates:::.run_table(run_facts(rf, data = list(job$provenance))), collapse = "\n")
  for (field in c("Started", "Ended", "Duration", "Status", "Rendered by", "Host", "File", "Template", "Subject",
                  "Type", "hvtiRtemplates", "Version file", "Registered", "Source file", "Rows kept", "WHERE",
                  "sha256", "Manifest", "renv")) {
    expect_match(table, field, fixed = TRUE, info = field)
  }
  for (value in c("tester", "testhost", "dc.general.cohort.eda.qmd", "dc.general", basename(job$provenance$path),
                  "built.csv", "age >= 30", substr(job$provenance$sha256, 1L, 12L), "current")) {
    expect_match(table, value, fixed = TRUE, info = value)
  }
  expect_false(grepl(job$provenance$sha256, table, fixed = TRUE))
  expect_match(table, "\\| Run +\\|")
  expect_match(table, "\\| Job +\\|")
  expect_match(table, "Dataset `built`", fixed = TRUE)
})

test_that("the seed and renv rows appear when there is something to say, and not otherwise", {
  rf <- run_fixture()
  withr::local_envvar(RENV_PROJECT = NA)
  facts <- run_facts(rf)
  expect_null(facts$reproducibility$seed)
  expect_false(facts$reproducibility$renv$active)
  expect_null(facts$reproducibility$renv$lock_sha256)
  bare <- paste(hvtiRtemplates:::.run_table(facts), collapse = "\n")
  expect_false(grepl("Seed", bare, fixed = TRUE))
  expect_match(bare, "not active", fixed = TRUE)
  expect_false(grepl("renv.lock", bare, fixed = TRUE))

  rf$env$SEED <- 20261012L
  writeLines("{\"R\": {\"Version\": \"4.6.0\"}}", file.path(rf$root, "renv.lock"))
  withr::local_envvar(RENV_PROJECT = rf$root)
  facts <- run_facts(rf)
  expect_identical(facts$reproducibility$seed, "20261012")
  expect_true(facts$reproducibility$renv$active)
  expect_identical(facts$reproducibility$renv$lock_sha256,
                   substr(digest::digest(file.path(rf$root, "renv.lock"), algo = "sha256", file = TRUE), 1L, 12L))
  full <- paste(hvtiRtemplates:::.run_table(facts), collapse = "\n")
  expect_match(full, "Seed", fixed = TRUE)
  expect_match(full, "20261012", fixed = TRUE)
  expect_match(full, facts$reproducibility$renv$lock_sha256, fixed = TRUE)
})

test_that("a draft's facts count its markers and skipped chunks", {
  fx <- setup_fixture(c(edit_marker(), "```{r}", "#| skip: \"waiting\"", "x <- 1", "```"))
  env <- new.env(parent = globalenv())
  expect_warning(expect_warning(r <- run_setup(env = env)))
  cfg <- hvtiRutilities::study_config(start = fx$root)
  facts <- hvtiRtemplates:::.run_facts(r$job$run, data = list(), artifacts = list(), cfg = cfg, envir = env)
  expect_identical(facts$status, "draft")
  expect_identical(facts$open_markers, 1L)
  expect_identical(facts$skipped_chunks, 1L)
  table <- paste(hvtiRtemplates:::.run_table(facts), collapse = "\n")
  expect_match(table, "draft (1 open marker, 1 skipped chunk)", fixed = TRUE)
})

test_that("a handoff read is listed as upstream with its job set, role, time and dataset version", {
  root <- hazard_study()
  cfg <- hvtiRutilities::study_config(start = root)
  lineage <- hazard_lineage(root)
  path <- hazard_save(list(reported = list(ok = TRUE)), lineage, hazard_set_path(root, "hm.rds"))
  withr::local_dir(root)
  testthat::local_mocked_bindings(current_input = function(dir = FALSE) NULL, .package = "knitr")
  env <- new.env(parent = globalenv())
  r <- run_setup(env = env)
  read <- hvtiRtemplates:::.read_handoff(path, "hazard-moments", cfg, "the hm job")
  facts <- hvtiRtemplates:::.run_facts(r$job$run, data = lineage$data, artifacts = list(read$record), cfg = cfg,
                                       envir = env)
  expect_length(facts$upstream, 1L)
  up <- facts$upstream[[1L]]
  expect_identical(basename(up$file), "hm.rds")
  expect_identical(up$set, "dead_pa-hz")
  expect_identical(up$role, "hazard-moments")
  expect_identical(up$saved, read$record$mtime)
  expect_identical(up$dataset_version, basename(lineage$data[[1L]]$path))
  table <- paste(hvtiRtemplates:::.run_table(facts), collapse = "\n")
  expect_match(table, "Upstream", fixed = TRUE)
  expect_match(table, "hazard-moments", fixed = TRUE)
  expect_match(table, up$dataset_version, fixed = TRUE)
})

test_that("a long upstream list is capped in the table and complete in the facts", {
  rf <- run_fixture()
  records <- lapply(seq_len(30L), function(i) {
    list(path = sprintf("estimates/dead_pa-hz/chunk%02d.rds", i), role = "bootstrap-chunk", bytes = 10,
         mtime = "2026-10-12T12:00:00Z", sha256 = strrep("a", 64L))
  })
  facts <- run_facts(rf, artifacts = records)
  expect_length(facts$upstream, 30L)
  table <- hvtiRtemplates:::.run_table(facts)
  expect_lt(length(grep("chunk[0-9]+[.]rds", table)), 30L)
  expect_true(any(grepl("18 more", table, fixed = TRUE)))
})

test_that("read_job_data() leaves a record of each read, which a new setup clears", {
  rf <- run_fixture()
  expect_length(hvtiRtemplates:::.run_state$reads, 0L)
  read_job_data(rf$cfg, where = quote(age >= 30))
  expect_length(hvtiRtemplates:::.run_state$reads, 1L)
  r <- run_setup()
  expect_length(hvtiRtemplates:::.run_state$reads, 0L)
  expect_s3_class(r$job$run$started, "POSIXct")
})

test_that("the facts and the table carry no data value and no identifier", {
  rf <- run_fixture()
  job <- read_job_data(rf$cfg, where = quote(age > 0 | age < -1), id = "ccfid")
  facts <- run_facts(rf, data = list(job$provenance))
  text <- paste(c(unlist(facts), hvtiRtemplates:::.run_table(facts)), collapse = " ")
  d <- hazard_data()
  for (id in as.character(d$ccfid)) {
    expect_false(grepl(paste0("(?<![A-Za-z0-9])", id, "(?![A-Za-z0-9])"), text, perl = TRUE), info = id)
  }
})

test_that("the facts serialize to JSON with their names intact", {
  rf <- run_fixture()
  job <- read_job_data(rf$cfg)
  json <- jsonlite::toJSON(run_facts(rf, data = list(job$provenance)), auto_unbox = TRUE, null = "null", digits = NA)
  back <- jsonlite::fromJSON(json, simplifyVector = FALSE)
  expect_true(all(c("status", "user", "job", "datasets", "upstream", "reproducibility") %in% names(back)))
  expect_identical(back$datasets[[1L]]$source_file, "built.csv")
  expect_identical(back$job$template, "dc.general")
})

# ---- Rendered ----------------------------------------------------------------

skip_unless_quarto <- function() {
  testthat::skip_on_cran()
  testthat::skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
  testthat::skip_if_not_installed("quarto")
  testthat::skip_if_not(quarto::quarto_available())
}

report_html <- function(job) {
  paste(readLines(sub("[.]qmd$", ".html", job), warn = FALSE), collapse = "\n")
}

test_that("a rendered report carries the date, the box under the title, and the end table, final then draft", {
  skip_unless_quarto()
  withr::local_envvar(HVTI_RUN_USER = "tester", HVTI_RUN_HOST = "testhost")
  s <- lm_render_fixture("binary")
  html <- report_html(s$job)
  # The date is in the title block.
  expect_true(grepl("<p class=\"date\">[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}</p>", html))
  # The box comes straight after the title block, before the first heading.
  title <- regexpr("<h1 class=\"title\">", html, fixed = TRUE)[[1L]]
  box <- regexpr("<strong>final</strong>", html, fixed = TRUE)[[1L]]
  heading <- regexpr("<h2 class=\"anchored\"", html, fixed = TRUE)[[1L]]
  expect_true(title > 0L && box > title && box < heading)
  # One setup chunk, so one "Code" fold between the title and the first heading, with the box after it.
  opening <- substr(html, title, heading)
  expect_identical(lengths(regmatches(opening, gregexpr("<details class=\"code-fold\">", opening, fixed = TRUE))), 1L)
  expect_true(regexpr("</details>", opening, fixed = TRUE)[[1L]] < regexpr("<strong>final</strong>", opening, fixed = TRUE)[[1L]])
  expect_true(grepl("rendered by tester on testhost", html, fixed = TRUE))
  expect_true(grepl(paste0("hvtiRtemplates ", utils::packageVersion("hvtiRtemplates")), html, fixed = TRUE))
  # The table is the last section, and its heading is unnumbered.
  headings <- regmatches(html, gregexpr("<h2 class=[^>]*>.*?</h2>", html, perl = TRUE))[[1L]]
  expect_match(utils::tail(headings, 1L), "About this run", fixed = TRUE)
  expect_match(utils::tail(headings, 1L), "unnumbered", fixed = TRUE)
  expect_true(grepl("built_[0-9]{8}[.]parquet", html))
  payload <- hvtiRtemplates:::.extract_provenance(html, managed = TRUE)
  expect_identical(payload$run$status, "final")
  expect_identical(payload$run$user, "tester")
  expect_identical(payload$run$host, "testhost")
  expect_identical(payload$run$job$template, "lm.binary")
  expect_identical(payload$run$job$subject, "outcome")
  expect_length(payload$run$datasets, 1L)
  expect_identical(payload$run$datasets[[1L]]$source_file, "built.csv")
  expect_false(grepl("/private/", sub(".*About this run", "", html)))

  # A marker left in the job makes it a draft, and the box and the table say so.
  writeLines(c(readLines(s$job, warn = FALSE), "", paste0("<!-- ", paste0("ED", "IT", ":"), " still to do -->")), s$job)
  quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = TRUE)
  html <- report_html(s$job)
  expect_true(grepl("<strong>draft</strong> (1 open marker", html, fixed = TRUE))
  expect_identical(hvtiRtemplates:::.extract_provenance(html, managed = TRUE)$run$status, "draft")
  expect_null(grDevices::dev.list())
})

test_that("a downstream report lists its upstream handoff, and names no patient", {
  skip_unless_quarto()
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  s <- lp_fixture()
  quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = TRUE)
  html <- report_html(s$job)
  payload <- hvtiRtemplates:::.extract_provenance(html, managed = TRUE)
  expect_gte(length(payload$run$upstream), 1L)
  up <- payload$run$upstream[[1L]]
  expect_match(up$file, "lm-propensity_binary[.]rds$")
  expect_identical(up$set, "outcome-analysis")
  expect_match(up$dataset_version, "^built_[0-9]{8}[.]parquet$")
  expect_true(grepl("Upstream", html, fixed = TRUE))
  # Neither the box nor the table names a patient (the scan lp-mirror uses: no data: URIs, whole tokens).
  text <- gsub("data:[A-Za-z0-9.+/-]+(;[^,\"')]*)?,[^\"') ]*", "", html, perl = TRUE)
  for (id in as.character(lp_data()$ccfid)) {
    at <- regexpr(paste0("(?<![A-Za-z0-9])", id, "(?![A-Za-z0-9])"), text, perl = TRUE)[[1L]]
    expect_false(at > 0L, info = if (at > 0L) substring(text, max(1L, at - 120L), at + 120L) else id)
  }
})
