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

test_that("INTERVAL drops patients who ended before the start, censors the rest at the end, and reports both counts", {
  local_child_chunks()
  d <- lg_data()
  kept <- d$iv_dead >= 0.25
  past <- kept & d$iv_dead > 5
  s <- lg_fixture("INTERVAL <- c(0.25, 5)")
  env <- lm_eval_job(s$job)
  expect_identical(nrow(env$d), sum(kept))
  # Patients read, left out before the start, left out for no follow-up, kept, censored at the end,
  # and the events that fell after it.
  expect_identical(env$.interval$counts$patients,
                   c(nrow(d), sum(d$iv_dead < 0.25), 0L, sum(kept), sum(past), sum(d$dead[past])))
  expect_gt(sum(d$iv_dead < 0.25), 0L)
  expect_gt(sum(past), 0L)
  # What the tables will read: no event after the end, and the time at risk inside the window.
  expect_identical(env$.event, ifelse(d$iv_dead[kept] > 5, 0L, d$dead[kept]))
  expect_equal(env$.time, pmin(d$iv_dead[kept], 5) - 0.25)
  # The covariates' defaults are those of the patients kept.
  expect_identical(env$variables$constant, signif(stats::median(d$age[kept]), 1L))
  # Without an interval, every patient is calibrated as read and there is nothing to report.
  env <- lm_eval_job(lg_fixture()$job)
  expect_identical(nrow(env$d), nrow(d))
  expect_null(env$.interval$counts)
  expect_identical(env$.event, d$dead)
  expect_equal(env$.time, d$iv_dead)
  expect_identical(env$variables$constant, signif(stats::median(d$age), 1L))
})

test_that("under INTERVAL the hazard sums the time at risk inside the window and the logit counts only events inside it", {
  local_child_chunks()
  d <- lg_data()
  kept <- d$iv_dead >= 0.25
  inside <- ifelse(d$iv_dead[kept] > 5, 0L, d$dead[kept])
  hazard <- lm_eval_job(lg_fixture("INTERVAL <- c(0.25, 5)")$job)
  expected <- hvtiRtemplates:::.lg_table(d$age[kept], inside, pmin(d$iv_dead[kept], 5) - 0.25, groups = 5L, link = "hazard")
  expect_equal(hazard$calibration$age$table, expected)
  expect_lt(sum(expected$events), sum(d$dead[kept]))
  logit <- lm_eval_job(lg_fixture(c("LINK <- \"logit\"", "INTERVAL <- c(0.25, 5)"))$job)
  expect_equal(logit$calibration$age$table, hvtiRtemplates:::.lg_table(d$age[kept], inside, groups = 5L, link = "logit"))
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

test_that("a chosen scale that is not a number for some patient warns in a draft and stops a final render", {
  local_child_chunks()
  # Four patients are 0, but they sit in a lowest group whose mean is far above 0, so every scale of the group
  # means is computable. The log and the inverse of those four patients are not.
  d <- lg_data()
  d$age_z <- d$age
  d$age_z[1:4] <- 0
  pick <- function(scale) {
    lg_fixture(variables = c("VARIABLES <- data.frame(", "  name = c(\"age_z\"),", paste0("  chosen = c(\"", scale, "\")"), ")"),
               data = d, .local_envir = parent.frame())$job
  }
  for (scale in c("log", "inverse")) {
    expect_warning(env <- lm_eval_job(pick(scale)), paste0("`age_z`: the chosen scale, ", scale, ", is not a number for 4 patients"))
    expect_identical(nrow(env$choices$table), 0L)
    expect_false(any(is.na(env$calibration$age_z$scales[[scale]])))
    withr::with_envvar(c(HVTI_TEMPLATE_STRICT = "1"), {
      expect_error(lm_eval_job(pick(scale)), paste0("`age_z`: the chosen scale, ", scale, ", is not a number for 4 patients"))
    })
  }
  # A scale every patient can take is not a problem.
  expect_no_warning(lm_eval_job(pick("raw")))
})

test_that("a covariate whose median rounds to 0 gets no default constant: the job goes on, and a constant-based choice is a problem", {
  local_child_chunks()
  d <- lg_data()
  d$flag <- as.integer(seq_len(nrow(d)) %% 4L == 0L)
  pick <- function(scale) {
    lg_fixture(variables = c("VARIABLES <- data.frame(", "  name = c(\"flag\"),", paste0("  chosen = c(\"", scale, "\")"), ")"),
               data = d, .local_envir = parent.frame())$job
  }
  env <- lm_eval_job(pick("raw"))
  expect_true(is.na(env$variables$constant))
  expect_identical(env$choices$table$term, "flag")
  scales <- env$calibration$flag$scales
  expect_false(any(is.na(scales$raw)))
  expect_true(all(is.na(scales$inverse)) && all(is.na(scales$exp)))
  expect_match(env$.notes, "^Inverse: .*set constant for this covariate in VARIABLES", all = FALSE)
  expect_warning(lm_eval_job(pick("inverse")), "`flag`: the chosen scale, inverse, cannot be computed: .*set constant")
  withr::with_envvar(c(HVTI_TEMPLATE_STRICT = "1"), {
    expect_error(lm_eval_job(pick("exp")), "`flag`: the chosen scale, exp, cannot be computed: .*set constant")
  })
})

test_that("the job stops on a covariate with a group of fewer than 5 patients or an ordinal with more than 20 levels", {
  local_child_chunks()
  d <- lg_data()
  d$rare <- ifelse(seq_len(nrow(d)) <= 3L, 2L, 1L)
  d$many <- rep(1:25, length.out = nrow(d))
  run <- function(name, kind) {
    lm_eval_job(lg_fixture(variables = c("VARIABLES <- data.frame(", paste0("  name = \"", name, "\","),
                                         paste0("  kind = \"", kind, "\","), "  chosen = \"raw\"", ")"),
                           data = d, .local_envir = parent.frame())$job)
  }
  expect_error(run("rare", "ordinal"),
               "^VARIABLES: `rare` has a group of fewer than 5 patients [(]the smallest has 3[)]. Combine levels")
  expect_error(run("many", "ordinal"), "^VARIABLES: `many` is ordinal with 25 levels")
  expect_no_error(run("many", "continuous"))
})

test_that("the job renders two figures and two tables for two covariates, naming no patient", {
  skip_on_cran()
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  d <- lg_data()
  windows <- list(none = character(), window = "INTERVAL <- c(0.25, 5)")
  for (window in names(windows)) {
    s <- lg_fixture(windows[[window]], variables = c(
      "VARIABLES <- data.frame(",
      "  name = c(\"age\", \"nyha\"),",
      "  kind = c(\"continuous\", \"ordinal\"),",
      "  chosen = c(\"log\", \"raw\")",
      ")"
    ))
    quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = TRUE)
    html <- paste(readLines(sub("[.]qmd$", ".html", s$job), warn = FALSE), collapse = "\n")
    # Two figures and two tables, one of each for each covariate, numbered; the interval table only with INTERVAL.
    ids <- function(prefix) {
      found <- regmatches(html, gregexpr(paste0("id=\"", prefix, "-lg-[a-z-]+\""), html))[[1L]]
      sort(unique(sub("^id=\"(.*)\"$", "\\1", found)))
    }
    expect_identical(ids("fig"), c("fig-lg-age", "fig-lg-nyha"), info = window)
    expect_identical(ids("tbl"), sort(c("tbl-lg-age", "tbl-lg-nyha", "tbl-lg-scales", "tbl-lg-variables",
                                        if (window == "window") "tbl-lg-interval")), info = window)
    graphs <- file.path(hvtiRutilities::study_dir("graphs", s$root), "dead-calibration")
    expect_setequal(list.files(graphs), c("lg-age.png", "lg-age.pdf", "lg-nyha.png", "lg-nyha.pdf"))
    # The choices are saved with the right terms, and the report prints the line to copy.
    saved <- readRDS(file.path(hvtiRutilities::study_dir("estimates", s$root), "dead-calibration", "lg-scales.rds"))
    expect_identical(saved$term, c("log(age)", "nyha"), info = window)
    plain <- gsub("<[^>]+>", "", html)
    expect_match(plain, "PREDICTORS &lt;- c(&quot;log(age)&quot;, &quot;nyha&quot;)", fixed = TRUE)
    # No patient identifier, raw or digested, appears in the report. Embedded images and fonts are base64
    # data URIs, whose text can spell any short digit run by chance, so they are dropped before the scan,
    # and an identifier counts only as a whole token. The provenance JSON is not a data URI, so it is scanned.
    text <- gsub("data:[A-Za-z0-9.+/-]+(;[^,\"')]*)?,[^\"') ]*", "", html, perl = TRUE)
    key <- hvtiRtemplates:::.study_id_key(s$root)
    for (id in c(as.character(d$ccfid), hvtiRtemplates:::.id_digest(d$ccfid, key))) {
      at <- regexpr(paste0("(?<![A-Za-z0-9])", id, "(?![A-Za-z0-9])"), text, perl = TRUE)[[1L]]
      # On a hit, show the text around it, so a CI failure says where it came from.
      expect_false(at > 0L, info = if (at > 0L) substring(text, max(1L, at - 120L), at + 120L) else id)
    }
    # The provenance names the data read, the choices and the window, never a patient.
    payload <- hvtiRtemplates:::.extract_provenance(html, managed = TRUE)
    expect_length(payload$data, 1L)
    expect_identical(payload$lg$event, "dead")
    expect_identical(payload$lg$link, "hazard")
    expect_identical(payload$lg$time, "iv_dead")
    expect_identical(vapply(payload$lg$variables, function(v) v$name, ""), c("age", "nyha"))
    expect_identical(vapply(payload$lg$variables, function(v) v$chosen, ""), c("log", "raw"))
    if (window == "window") {
      kept <- d$iv_dead >= 0.25
      expect_identical(unlist(payload$lg$interval), c(start = 0.25, end = 5, left_out = sum(!kept), kept = sum(kept),
                                                      censored = sum(kept & d$iv_dead > 5)))
      expect_identical(payload$lg$patients, sum(kept))
    } else {
      expect_null(payload$lg$interval)
      expect_identical(payload$lg$patients, nrow(d))
    }
  }
})
