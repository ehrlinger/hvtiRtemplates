# One setup chunk for every template. The design is
# dev/specs/2026-10-12-setup-and-run-info-design.md; its section 6 lists what
# these tests cover. The run information it adds is tested in test-run-info.R.
# All data are synthetic.

test_that(".job_setup() finds the study root and returns the root, set_path() and the run record", {
  fx <- setup_fixture()
  r <- run_setup()
  expect_named(r$job, c("root", "set_path", "run", "notice"))
  expect_identical(normalizePath(r$job$root), normalizePath(fx$root))
  expect_true(is.function(r$job$set_path))
  expect_s3_class(r$job$run$started, "POSIXct")
  expect_identical(r$job$run$state, "final")
})

test_that(".job_setup() finds the root from the working directory when no file is being rendered", {
  fx <- setup_fixture()
  testthat::local_mocked_bindings(current_input = function(dir = FALSE) NULL, .package = "knitr")
  r <- run_setup()
  expect_identical(normalizePath(r$job$root), normalizePath(fx$root))
})

test_that(".job_setup() sources the study's R/ into envir and writes nowhere else", {
  setup_fixture()
  r <- run_setup()
  expect_true(is.function(r$env$study_helper))
  expect_identical(r$env$study_helper(), "from the study")
  expect_false(exists("study_helper", envir = globalenv(), inherits = FALSE))
  # It defines nothing else in envir: the template assigns what it keeps from the return.
  expect_setequal(ls(r$env, all.names = TRUE), "study_helper")
})

test_that("set_path() creates <kind>/<subject>-<type>/ and follows SUBJECT and TYPE in envir", {
  fx <- setup_fixture()
  r <- run_setup()
  path <- r$job$set_path("estimates", "fit.rds")
  expect_identical(basename(path), "fit.rds")
  expect_identical(basename(dirname(path)), "cohort-eda")
  expect_true(dir.exists(dirname(path)))
  expect_identical(normalizePath(dirname(dirname(path))),
                   normalizePath(hvtiRutilities::study_dir("estimates", fx$root)))
  # A test or an author who changes SUBJECT and TYPE after setup moves the set, as the old chunk did.
  r$env$SUBJECT <- "dead"
  r$env$TYPE <- "other"
  r$env$.root <- fx$root
  expect_identical(basename(dirname(r$job$set_path("graphs", "a.png"))), "dead-other")
})

test_that("a name that disagrees with SUBJECT and TYPE stops with the old message", {
  setup_fixture()
  expect_error(
    run_setup("cohort", "other"),
    paste0("This file is named 'dc.general.cohort.eda.qmd' (subject 'cohort', type 'eda'), but declares ",
           "SUBJECT = \"cohort\", TYPE = \"other\". Fix the declaration or the filename before rendering."),
    fixed = TRUE
  )
  expect_error(run_setup("dead", "eda"), "but declares SUBJECT = \"dead\"", fixed = TRUE)
})

test_that("an old-spelling file name is checked too", {
  fx <- setup_fixture()
  legacy <- file.path(dirname(fx$job), "cohort-eda-dc-general.qmd")
  writeLines("A finished job.", legacy)
  testthat::local_mocked_bindings(
    current_input = function(dir = FALSE) if (isTRUE(dir)) legacy else basename(legacy), .package = "knitr"
  )
  expect_silent(invisible(run_setup()$job))
  expect_error(run_setup("cohort", "other"), "but declares", fixed = TRUE)
})

test_that("open EDIT markers draft the job with the DRAFT callout, and a strict render stops", {
  setup_fixture(c("prose", edit_marker()))
  expect_warning(r <- run_setup(), "Rendering as a draft; the banner goes when the last marker does")
  expect_true(any(grepl("DRAFT -- this job is unfinished", r$out, fixed = TRUE)))
  expect_true(any(grepl("choose the endpoint", r$out, fixed = TRUE)))
  expect_identical(r$job$run$state, "draft")
  expect_identical(r$job$run$markers, 1L)
  for (v in c("1", "true", "yes")) {
    withr::with_envvar(c(HVTI_TEMPLATE_STRICT = v), expect_error(run_setup(), "1 unresolved .* marker\\(s\\) remain"))
  }
  withr::with_envvar(
    c(HVTI_TEMPLATE_STRICT = "ture"),
    expect_error(run_setup(), "This render stops because HVTI_TEMPLATE_STRICT is 'ture'", fixed = FALSE)
  )
  for (v in c("0", "false", "no")) {
    withr::with_envvar(c(HVTI_TEMPLATE_STRICT = v), expect_warning(run_setup(), "Rendering as a draft"))
  }
})

test_that(".guard_edits() keeps a marker's source out of the report when asked, and puts it on the console", {
  fx <- setup_fixture(c("prose", edit_marker("EXCLUDE a patient")))
  warned <- NULL
  console <- utils::capture.output(
    out <- utils::capture.output(
      n <- withCallingHandlers(
        hvtiRtemplates:::.guard_edits(show_source = FALSE),
        warning = function(w) {
          warned <<- conditionMessage(w)
          invokeRestart("muffleWarning")
        }
      )
    ),
    type = "message"
  )
  expect_identical(n, 1L)
  # The warning knitr would embed in the report, and the banner, hold the count and no source.
  expect_match(warned, paste0("1 unresolved ", paste0("ED", "IT", ":"), " marker(s) remain in this job."), fixed = TRUE)
  expect_match(warned, "Rendering as a draft", fixed = TRUE)
  expect_false(grepl("EXCLUDE a patient", warned, fixed = TRUE))
  expect_true(any(grepl("1 unresolved markers remain", out, fixed = TRUE)))
  expect_false(any(grepl("EXCLUDE a patient", out, fixed = TRUE)))
  # The console has the line.
  expect_true(any(grepl("EXCLUDE a patient", console, fixed = TRUE)))
  expect_true(file.exists(fx$job))
})

test_that("a skipped chunk or a stop drafts the job with the PARTIAL list, and a strict render stops", {
  setup_fixture(c("prose", "```{r}", "#| skip: \"waiting on the corrected coding\"", "x <- 1", "```"))
  expect_warning(r <- run_setup(), "rendered in part")
  expect_true(any(grepl("PARTIAL -- parts of this job are left out", r$out, fixed = TRUE)))
  expect_true(any(grepl("waiting on the corrected coding", r$out, fixed = TRUE)))
  expect_identical(r$job$run$state, "draft")
  expect_identical(r$job$run$skipped, 1L)
  expect_identical(r$job$run$markers, 0L)
  withr::with_envvar(c(HVTI_TEMPLATE_STRICT = "1"), expect_error(run_setup(), "HVTI_TEMPLATE_STRICT is set"))
})

test_that("a finished job's notice is the top box and nothing else, and .job_setup() prints nothing", {
  setup_fixture()
  out <- utils::capture.output(job <- hvtiRtemplates:::.job_setup("cohort", "eda", envir = new.env()))
  expect_length(out, 0L)
  expect_s3_class(job$notice, "knit_asis")
  lines <- strsplit(as.character(job$notice), "\n", fixed = TRUE)[[1L]]
  expect_identical(lines[[1L]], "")
  expect_match(lines[[2L]], "^::: \\{\\.callout")
  expect_match(lines[[3L]], "^\\*\\*final\\*\\* ")
  expect_identical(lines[[4L]], ":::")
  expect_length(lines, 5L)
})

test_that("every template has one chunk before its study choices, labeled setup", {
  tl <- template_list()
  expect_gt(nrow(tl), 30L)
  for (f in tl$file) {
    src <- readLines(f, warn = FALSE)
    study <- grep("^#\\| label: edit-study-choices$", src)
    info <- basename(f)
    expect_length(study, 1L)
    head <- src[seq_len(study[[1L]] - 2L)]
    expect_identical(sum(grepl("^```\\{r", head)), 1L, info = info)
    expect_true("#| label: setup" %in% head, info = info)
    expect_true("#| results: asis" %in% head, info = info)
    for (gone in c("guard-edits", "guard-partial", "label: set$")) {
      expect_false(any(grepl(paste0("^#\\| label: ", sub("^label: ", "", gone)), src)), info = paste(info, gone))
    }
    expect_true(any(grepl("hvtiRtemplates:::.job_setup(SUBJECT, TYPE", head, fixed = TRUE)), info = info)
    expect_identical(sum(grepl("^SUBJECT\\s+<- ", src)), 1L, info = info)
    expect_identical(sum(grepl("^TYPE\\s+<- ", src)), 1L, info = info)
    expect_true(any(grepl("^\\.root <- \\.job\\$root$", head)), info = info)
    # bd builds a dataset and writes through no set.
    if (!identical(info, "bd.qmd")) expect_true(any(grepl("^set_path <- \\.job\\$set_path$", head)), info = info)
    expect_true(any(grepl("^\\.provenance_data <- list\\(\\)$", head)), info = info)
    # The output comes after all of the chunk's code, so the report shows one fold.
    at <- which(src == "#| label: setup")
    chunk <- src[(at + 1L):(at + which(src[(at + 1L):length(src)] == "```")[[1L]] - 1L)]
    expect_identical(utils::tail(chunk, 1L), ".job$notice", info = info)
    expect_no_error(parse(text = chunk))
  }
})

test_that("add_job() still substitutes SUBJECT and TYPE in every template's single setup chunk", {
  tl <- template_list()
  root <- hazard_study()
  for (i in seq_len(nrow(tl))) {
    prefix <- strsplit(tl$name[[i]], ".", fixed = TRUE)[[1L]]
    qualifier <- if (length(prefix) > 1L) paste(prefix[-1L], collapse = ".") else NULL
    job <- add_job(prefix[[1L]], "mysubject", "mytype", dir = root, qualifier = qualifier)
    src <- readLines(job, warn = FALSE)
    expect_identical(grep("^SUBJECT\\s+<- ", src, value = TRUE), "SUBJECT <- \"mysubject\"", info = tl$name[[i]])
    expect_identical(sub("\\s+", " ", grep("^TYPE\\s+<- ", src, value = TRUE)), "TYPE <- \"mytype\"",
                     info = tl$name[[i]])
    unlink(job)
  }
})

test_that("every template's header carries the render date", {
  for (f in template_list()$file) {
    lines <- readLines(f, warn = FALSE)
    fence <- which(lines == "---")
    meta <- yaml::yaml.load(paste(lines[(fence[1L] + 1L):(fence[2L] - 1L)], collapse = "\n"))
    expect_identical(meta$date, "now", info = basename(f))
    expect_identical(meta$`date-format`, "YYYY-MM-DD HH:mm", info = basename(f))
  }
})

test_that("a job with the old four-chunk header still renders", {
  skip_on_cran()
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  fx <- lm_render_fixture("binary", render = FALSE)
  src <- readLines(fx$job, warn = FALSE)
  open <- which(src == "#| label: setup") - 1L
  close <- open + which(src[(open + 1L):length(src)] == "```")[1L]
  old <- readLines(test_path("fixtures-setup", "lm-binary-four-chunks.txt"), warn = FALSE)
  rest <- src[(close + 1L):length(src)]
  # The rest of an old job is old too: its provenance chunk does not pass the run.
  rest <- rest[rest != "  run = .job$run,"]
  writeLines(c(src[seq_len(open - 1L)], old, rest), fx$job)
  expect_false(any(grepl(".job_setup", readLines(fx$job, warn = FALSE), fixed = TRUE)))
  quarto::quarto_render(fx$job, execute_dir = dirname(fx$job), quiet = TRUE)
  html <- paste(readLines(sub("[.]qmd$", ".html", fx$job), warn = FALSE), collapse = "\n")
  expect_true(grepl("hvti-provenance", html, fixed = TRUE))
  # The run information is new-header only: an old job gains neither the box nor the end table.
  expect_false(grepl("About this run", html, fixed = TRUE))
  payload <- hvtiRtemplates:::.extract_provenance(html, managed = TRUE)
  expect_null(payload$run)
  expect_identical(payload$subject, "outcome")
  # The chunks this test ran in the session left no graphics device open.
  expect_null(grDevices::dev.list())
})
