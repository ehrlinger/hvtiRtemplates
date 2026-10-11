# lg: the logit calibration job. The design is
# dev/specs/2026-10-11-lg-template-design.md; its section 5 lists what these
# tests cover. The numerical core has its own tests in test-logit-calibration.R.
# All data are synthetic.

test_that("lg is a descriptive template that add_job() scaffolds, and its catalog row is shipped as Logit calibration", {
  tl <- template_list()
  row <- tl[tl$name == "lg", ]
  expect_identical(nrow(row), 1L)
  expect_identical(row$folder, "descriptive")
  expect_identical(row$call, "add_job(\"lg\", subject = \"dead\", type = \"calibration\")")
  root <- lm_study()
  job <- add_job("lg", "dead", "calibration", dir = root)
  expect_identical(basename(job), "lg.dead.calibration.qmd")
  expect_identical(normalizePath(dirname(job)), normalizePath(hvtiRutilities::study_dir("descriptive", root)))
  src <- readLines(job, warn = FALSE)
  expect_identical(grep("^SUBJECT\\s+<- ", src, value = TRUE), "SUBJECT <- \"dead\"")
  expect_identical(grep("^TYPE\\s+<- ", src, value = TRUE), "TYPE    <- \"calibration\"")
  catalog <- template_catalog()
  entry <- catalog[catalog$prefix == "lg", ]
  expect_identical(nrow(entry), 1L)
  expect_identical(entry$name, "Logit calibration")
  expect_identical(entry$status, "shipped")
  expect_true(is.na(entry$qualifier))
  expect_identical(entry$spec, "dev/specs/2026-10-11-lg-template-design.md")
  expect_identical(entry$downstream[[1L]], "lm")
})

test_that("the job checks its choices against the data before any calibration, naming the setting", {
  local_child_chunks()
  run <- function(...) lm_eval_job(lg_fixture(...)$job)
  expect_error(run("LINK <- \"cox\""), "^LINK must be \"logit\" or \"hazard\"")
  expect_error(run("EVENT <- \"died\""), "^EVENT names a column this dataset does not have: died")
  expect_error(run("EVENT <- c(\"dead\", \"hdead\")"), "^EVENT must be one column name")
  expect_error(run("TIME <- \"later\""), "^TIME names a column this dataset does not have: later")
  expect_error(run("EVENT <- \"ccfid\""), "^EVENT and TIME cannot be the patient identifier")
  expect_error(run(variables = c("VARIABLES <- data.frame(", "  name = c(\"age\", \"bmi\")", ")")),
               "^VARIABLES names a column this dataset does not have: bmi. Change VARIABLES in edit-study-choices")
  expect_error(run(variables = c("VARIABLES <- data.frame(", "  name = \"ccfid\"", ")")),
               "^VARIABLES names the patient identifier")
  # TIME is read by the hazard link and by INTERVAL only: a logit job with no INTERVAL need not have it.
  expect_no_error(run(c("LINK <- \"logit\"", "EVENT <- \"hdead\"", "TIME <- \"later\"")))
  expect_error(run(c("LINK <- \"logit\"", "EVENT <- \"hdead\"", "TIME <- \"later\"", "INTERVAL <- c(0, 5)")),
               "^TIME names a column this dataset does not have: later")
})

test_that("INTERVAL keeps the patients whose follow-up is in the window and reports how many it kept", {
  local_child_chunks()
  d <- lg_data()
  inside <- d$iv_dead >= 0.25 & d$iv_dead <= 5
  s <- lg_fixture("INTERVAL <- c(0.25, 5)")
  env <- lm_eval_job(s$job)
  expect_identical(nrow(env$d), sum(inside))
  expect_identical(env$.interval$counts$patients,
                   c(nrow(d), sum(d$iv_dead < 0.25), sum(d$iv_dead > 5), 0L, sum(inside)))
  # The covariates' defaults are those of the patients kept.
  expect_identical(env$variables$constant, signif(stats::median(d$age[inside]), 1L))
  # Without an interval, every patient is calibrated and there is nothing to report.
  env <- lm_eval_job(lg_fixture()$job)
  expect_identical(nrow(env$d), nrow(d))
  expect_null(env$.interval$counts)
  expect_identical(env$variables$constant, signif(stats::median(d$age), 1L))
})

# The two variables of the synthetic study the job's tests calibrate: a continuous
# age and an ordinal NYHA class, as a VARIABLES data frame the fixture splices in.
lg_two_variables <- c(
  "VARIABLES <- data.frame(",
  "  name = c(\"age\", \"nyha\"),",
  "  kind = c(\"continuous\", \"ordinal\"),",
  "  chosen = c(\"log\", \"raw\")",
  ")"
)

test_that("the job tabulates each covariate's groups and draws its six-panel figure, saved as PNG and PDF", {
  local_child_chunks()
  s <- lg_fixture(variables = lg_two_variables)
  # What the job's asis chunks would print: the child chunks they knit.
  printed <- character()
  testthat::local_mocked_bindings(
    knit_child = function(text, envir, ...) {
      printed <<- c(printed, text)
      ""
    },
    .package = "knitr"
  )
  env <- lm_eval_job(s$job)
  d <- lg_data()
  # The hazard link of the study's death and follow-up, on five rank groups of age and a group per NYHA class.
  age <- hvtiRtemplates:::.lg_table(d$age, d$dead, d$iv_dead, groups = 5L, link = "hazard")
  expect_equal(env$calibration$age$table, age)
  expect_identical(nrow(age), 5L)
  nyha <- hvtiRtemplates:::.lg_table(d$nyha, d$dead, d$iv_dead, kind = "ordinal", link = "hazard")
  expect_equal(env$calibration$nyha$table, nyha)
  expect_identical(nrow(nyha), 4L)
  expect_equal(env$calibration$age$scales, hvtiRtemplates:::.lg_scales(age$mean, env$variables$constant[[1L]]))
  # One numbered table and one numbered figure for each covariate, in that order.
  labels <- sub("^#\\| label: ", "", grep("^#\\| label: (tbl|fig)-lg-(age|nyha)$", printed, value = TRUE))
  expect_identical(labels, c("tbl-lg-age", "fig-lg-age", "tbl-lg-nyha", "fig-lg-nyha"))
  graphs <- file.path(hvtiRutilities::study_dir("graphs", s$root), "dead-calibration")
  expect_setequal(list.files(graphs), c("lg-age.png", "lg-age.pdf", "lg-nyha.png", "lg-nyha.pdf"))
})

test_that("the logit link calibrates a binary event with no follow-up, and FIGURES keeps only the PDFs it names", {
  local_child_chunks()
  s <- lg_fixture(c("LINK <- \"logit\"", "EVENT <- \"hdead\"", "TIME <- \"later\"", "FIGURES <- c(\"lg-age\")"),
                  variables = lg_two_variables)
  env <- lm_eval_job(s$job)
  d <- lg_data()
  expect_equal(env$calibration$age$table, hvtiRtemplates:::.lg_table(d$age, d$hdead, groups = 5L, link = "logit"))
  graphs <- file.path(hvtiRutilities::study_dir("graphs", s$root), "dead-calibration")
  # The PNG a report shows is always written; the PDF only for a figure FIGURES keeps.
  expect_setequal(list.files(graphs), c("lg-age.png", "lg-age.pdf", "lg-nyha.png"))
})

test_that("a group or scale that cannot be computed is named under its table, and a label never holds an underscore", {
  local_child_chunks()
  # n_prior is 0 for most patients, so its lowest group has a mean of 0.
  s <- lg_fixture(variables = c(
    "VARIABLES <- data.frame(",
    "  name = c(\"n_prior\"),",
    "  constant = c(1),",
    "  chosen = c(\"raw\")",
    ")"
  ))
  printed <- character()
  testthat::local_mocked_bindings(
    knit_child = function(text, envir, ...) {
      printed <<- c(printed, text)
      ""
    },
    .package = "knitr"
  )
  env <- lm_eval_job(s$job)
  # The labels carry hyphens, the file keeps the column's own name.
  expect_true(all(c("#| label: tbl-lg-n-prior", "#| label: fig-lg-n-prior") %in% printed))
  expect_true(file.exists(file.path(hvtiRutilities::study_dir("graphs", s$root), "dead-calibration", "lg-n_prior.png")))
  # The notes the chunk prints under the table: the three scales a mean of 0 breaks.
  expect_named(attr(env$calibration$n_prior$scales, "notes"), c("log", "inverse", "inverse_squared"))
  expect_match(env$.notes, "^Log: A group mean plus the shift is not positive", all = FALSE)
  expect_match(env$.notes, "^Inverse squared: A group mean is 0", all = FALSE)
  expect_false(any(grepl("^Exponential", env$.notes)))
})
test_that("the job saves lg-scales.rds with the term, constant and shift of each chosen scale, and the PREDICTORS line", {
  local_child_chunks()
  d <- lg_data()
  s <- lg_fixture(variables = c(
    "VARIABLES <- data.frame(",
    "  name = c(\"age\", \"nyha\"),",
    "  kind = c(\"continuous\", \"ordinal\"),",
    "  chosen = c(\"log\", \"inverse\")",
    ")"
  ))
  # Nothing is warned when every covariate has a usable choice.
  expect_no_warning(env <- lm_eval_job(s$job))
  saved <- readRDS(file.path(hvtiRutilities::study_dir("estimates", s$root), "dead-calibration", "lg-scales.rds"))
  expect_s3_class(saved, "data.frame")
  expect_named(saved, c("variable", "chosen", "term", "constant", "shift"))
  expect_identical(saved$variable, c("age", "nyha"))
  expect_identical(saved$chosen, c("log", "inverse"))
  expect_identical(saved$constant, c(signif(stats::median(d$age), 1L), signif(stats::median(d$nyha), 1L)))
  expect_identical(saved$shift, c(0, 0))
  # The term is the constant and the name, written as an lm job takes it.
  expect_identical(saved$term, c("log(age)", paste0("I(", saved$constant[[2L]], " / nyha)")))
  expect_identical(env$.predictors, paste0("PREDICTORS <- c(\"log(age)\", \"", saved$term[[2L]], "\")"))
  # The file carries the lineage of the data it came from, and no patient.
  lineage <- attr(saved, "hvti_provenance")
  expect_length(lineage$data, 1L)
  expect_identical(lineage$analysis$event, "dead")
  expect_identical(lineage$analysis$link, "hazard")
  expect_identical(lineage$cohort$patients, nrow(d))
  # The terms go into a model as they stand: lm's own check finds the columns, and the model fits.
  expect_silent(hvtiRtemplates:::.check_job_columns(d, PREDICTORS = saved$term))
  fit <- stats::glm(stats::reformulate(saved$term, response = "hdead"), family = stats::binomial, data = d)
  expect_s3_class(fit, "glm")
})

test_that("a blank chosen warns in a draft, saves only the covariates chosen, and stops a final render", {
  local_child_chunks()
  two <- c(
    "VARIABLES <- data.frame(",
    "  name = c(\"age\", \"nyha\"),",
    "  chosen = c(\"log\", NA)",
    ")"
  )
  s <- lg_fixture(variables = two)
  file <- file.path(hvtiRutilities::study_dir("estimates", s$root), "dead-calibration", "lg-scales.rds")
  expect_warning(env <- lm_eval_job(s$job),
                 "^These covariates have no usable scale chosen: `nyha`: no scale chosen yet. Read each figure")
  expect_identical(names(env$choices$problems), "nyha")
  expect_identical(readRDS(file)$variable, "age")
  expect_identical(env$.predictors, "PREDICTORS <- c(\"log(age)\")")
  unlink(file)
  # A final render, with HVTI_TEMPLATE_STRICT set as render_job(final = TRUE) sets it, stops, and saves nothing.
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "1")
  expect_error(lm_eval_job(s$job), paste0("^These covariates have no usable scale chosen: `nyha`: no scale chosen yet.*",
                                          "This render stops because HVTI_TEMPLATE_STRICT is '1'"))
  expect_false(file.exists(file))
  # Unset, or set to a false word, it is a draft again.
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "false")
  expect_warning(lm_eval_job(s$job), "no usable scale chosen")
})

test_that("the template's own blank chosen is a draft warning for the first covariate", {
  local_child_chunks()
  s <- lg_fixture(variables = NULL)
  expect_warning(env <- lm_eval_job(s$job), "^These covariates have no usable scale chosen: `age`: no scale chosen yet")
  expect_identical(nrow(readRDS(file.path(hvtiRutilities::study_dir("estimates", s$root), "dead-calibration", "lg-scales.rds"))), 0L)
  expect_identical(env$.predictors, "No scale is chosen yet, so there is no PREDICTORS line.")
})

test_that("a chosen scale that cannot be computed warns in a draft and stops a final render", {
  local_child_chunks()
  # n_prior is 0 in its lowest group, so its log is undefined.
  s <- lg_fixture(variables = c(
    "VARIABLES <- data.frame(",
    "  name = c(\"n_prior\"),",
    "  constant = c(1),",
    "  chosen = c(\"log\")",
    ")"
  ))
  expect_warning(lm_eval_job(s$job),
                 "`n_prior`: the chosen scale, log, cannot be computed: A group mean plus the shift is not positive")
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "yes")
  expect_error(lm_eval_job(s$job), "`n_prior`: the chosen scale, log, cannot be computed")
  # A shift makes it computable, and the term says so.
  fixed <- lg_fixture(variables = c(
    "VARIABLES <- data.frame(",
    "  name = c(\"n_prior\"),",
    "  constant = c(1),",
    "  shift = c(1),",
    "  chosen = c(\"log\")",
    ")"
  ))
  env <- lm_eval_job(fixed$job)
  expect_identical(env$choices$table$term, "log(n_prior + 1)")
})
