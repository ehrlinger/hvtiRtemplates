# lp-mirror: the mirrored propensity histogram, read from a saved
# lm-propensity_binary bundle. The design is
# dev/specs/2026-10-11-lp-mirror-template-design.md; its section 7 lists what
# these tests cover. All data are synthetic.

test_that("lp-mirror is a graphs template that add_job() scaffolds by its full name", {
  tl <- template_list()
  row <- tl[tl$name == "lp.mirror", ]
  expect_identical(nrow(row), 1L)
  expect_identical(row$folder, "graphs")
  expect_identical(row$call, "add_job(\"lp.mirror\", subject = \"treatment\", type = \"propensity\")")
  root <- lm_study()
  job <- add_job("lp.mirror", "treatment", "propensity", dir = root)
  expect_identical(basename(job), "lp.mirror.treatment.propensity.qmd")
  expect_identical(normalizePath(dirname(job)), normalizePath(hvtiRutilities::study_dir("graphs", root)))
  src <- readLines(job, warn = FALSE)
  expect_identical(grep("^SUBJECT\\s+<- ", src, value = TRUE), "SUBJECT <- \"treatment\"")
  expect_identical(grep("^TYPE\\s+<- ", src, value = TRUE), "TYPE    <- \"propensity\"")
})

test_that("the job's package guards ask for the versions DESCRIPTION suggests", {
  src <- readLines(template_path("lp", "mirror"), warn = FALSE)
  suggests <- gsub("\\s+", " ", utils::packageDescription("hvtiRtemplates")$Suggests)
  for (pkg in c("hvtiRpropensity", "hvtiPlotR")) {
    minimum <- sub(paste0(".*", pkg, " \\(>= ([0-9.]+)\\).*"), "\\1", suggests)
    guard <- regmatches(src, regexpr(paste0("packageVersion[(]\"", pkg, "\"[)] < \"[0-9.]+\""), src))
    expect_length(guard, 1L)
    expect_identical(sub('.*< "([0-9.]+)"$', "\\1", guard), minimum, info = pkg)
    expect_true(any(grepl(paste0(pkg, " >= ", minimum), src, fixed = TRUE)), info = pkg)
  }
})

test_that("the job reads the bundle from its own set, or another through MODEL_SET, and never refits", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  s <- lp_fixture()
  testthat::local_mocked_bindings(
    ps_logistic = function(...) stop("lp-mirror refitted the model", call. = FALSE),
    .package = "hvtiRpropensity"
  )
  env <- lm_eval_job(s$job)
  expect_identical(env$MODEL_PATH, s$bundle)
  expect_identical(nrow(env$scores), 120L)
  expect_named(env$scores, c("id", "score", "group", "weight", "matched"))
  # The bundle moved to a set of its own is found through MODEL_SET.
  other <- file.path(hvtiRutilities::study_dir("estimates", s$root), "treatment-propensity")
  dir.create(other)
  file.rename(s$bundle, file.path(other, "lm-propensity_binary.rds"))
  expect_error(lm_eval_job(s$job), "^Saved model not found: .*outcome-analysis.*set MODEL_FILE and MODEL_SET")
  src <- readLines(s$job, warn = FALSE)
  writeLines(sub("^MODEL_SET <- NULL$", "MODEL_SET <- \"treatment-propensity\"", src), s$job)
  env <- lm_eval_job(s$job)
  expect_identical(normalizePath(env$MODEL_PATH), normalizePath(file.path(other, "lm-propensity_binary.rds")))
  # Neither setting can reach outside the study's estimates.
  writeLines(sub("^MODEL_SET <- NULL$", "MODEL_SET <- \"../treatment-propensity\"", src), s$job)
  expect_error(lm_eval_job(s$job), "^MODEL_SET must be NULL or one set name")
  writeLines(sub("^MODEL_FILE <- .*$", "MODEL_FILE <- \"../x/lm-propensity_binary.rds\"", src), s$job)
  expect_error(lm_eval_job(s$job), "^MODEL_FILE must name one [.]rds file")
  # A bundle without its matching weight is not one this job can draw.
  writeLines(sub("^MODEL_SET <- NULL$", "MODEL_SET <- \"treatment-propensity\"", src), s$job)
  bundle <- readRDS(file.path(other, "lm-propensity_binary.rds"))
  bundle$data$mt_wt <- NULL
  saveRDS(bundle, file.path(other, "lm-propensity_binary.rds"))
  expect_error(lm_eval_job(s$job), "is not a binary propensity model with its patients, treatment, score and matching weight")
})

test_that("a bundle without lineage, or built from data that changed since, stops with the job to rerun", {
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  s <- lp_fixture()
  bundle <- readRDS(s$bundle)
  lineage <- attr(bundle, "hvti_provenance")
  resave <- function(value) {
    attr(bundle, "hvti_provenance") <- value
    saveRDS(bundle, s$bundle)
  }
  resave(NULL)
  expect_error(lm_eval_job(s$job), "no complete hvti_provenance lineage. Rebuild it by rendering the lm-propensity_binary job")
  no_data <- lineage
  no_data$data <- list()
  resave(no_data)
  expect_error(lm_eval_job(s$job), "no source data lineage. Rebuild it by rendering the lm-propensity_binary job")
  resave(lineage[setdiff(names(lineage), "selection")])
  expect_error(lm_eval_job(s$job), "Render the lm-propensity_binary job again with the current template")
  # The same counts on other patients: the data changed since the bundle was saved.
  changed <- lineage
  changed$selection$key_hash <- strrep("0", 64L)
  resave(changed)
  expect_error(lm_eval_job(s$job), "The data changed since the upstream job ran")
})
