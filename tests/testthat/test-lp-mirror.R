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

test_that("the groups are labelled by the bundle's declared levels, treated first, unless GROUP_LABELS says", {
  h <- lp_helpers()
  meta <- list(treatment_levels = c("control", "treated"), treated_level = "treated")
  expect_identical(h$mirror_groups(meta), list(levels = c("treated", "control"), labels = c("treated", "control")))
  # Named by level, in either order.
  expect_identical(h$mirror_groups(meta, c(control = "Surgical", treated = "Transcatheter"))$labels,
                   c("Transcatheter", "Surgical"))
  expect_identical(h$mirror_groups(meta, c(treated = "Transcatheter", control = "Surgical"))$labels,
                   c("Transcatheter", "Surgical"))
  expect_error(h$mirror_groups(meta, c("Surgical", "Transcatheter")),
               "^GROUP_LABELS must be NULL or two labels named by the treatment levels, such as c[(]control")
  expect_error(h$mirror_groups(meta, c(control = "a", other = "b")), "^GROUP_LABELS must be NULL")
  # A bundle saved before hvtiRpropensity 0.1.10 declares no levels.
  expect_error(h$mirror_groups(list(treatment_levels = NULL, treated_level = NULL)),
               "does not declare two treatment levels")
  # The job reads them from the saved bundle.
  skip_if_not_installed("hvtiRpropensity", minimum_version = "0.1.10")
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  s <- lp_fixture("GROUP_LABELS <- c(control = \"Surgical\", treated = \"Transcatheter\")")
  env <- lm_eval_job(s$job)
  expect_identical(env$groups, list(levels = c("treated", "control"), labels = c("Transcatheter", "Surgical")))
})

lp_scores <- function() {
  i <- seq_len(40L)
  data.frame(id = paste0("p", i), score = (i - 0.5) / 40, group = rep(c("treated", "control"), 20L),
             weight = 0.25 + (i %% 4L) / 4, matched = as.integer(i %% 3L != 0L))
}

test_that("the treated bars are above the axis and the y-limits are symmetric, from the tallest bar", {
  skip_if_not_installed("hvtiPlotR", minimum_version = "2.8.0")
  h <- lp_helpers()
  groups <- list(levels = c("treated", "control"), labels = c("Treated", "Control"))
  mh <- h$mirror_hist(lp_scores(), "unmatched", groups, 5)
  expect_true(all(mh$data$y[mh$data$group == "Treated"] >= 0))
  expect_true(all(mh$data$y[mh$data$group == "Control"] <= 0))
  # Only the all-patient bars: an unmatched figure has no matched layer.
  expect_setequal(unique(mh$data$layer), "Before")
  top <- max(abs(mh$data$y))
  expect_identical(h$mirror_limit(mh$data$y), top + max(1, ceiling(0.1 * top)))
  expect_identical(h$mirror_limit(c(3, -12)), 14)
  expect_identical(h$mirror_limit(numeric()), 1)
  p <- h$mirror_figure(mh, "unmatched")
  limits <- ggplot2::layer_scales(p)$y$get_limits()
  expect_identical(limits, c(-h$mirror_limit(mh$data$y), h$mirror_limit(mh$data$y)))
  # A tall treated side and a short control side, past the point where the
  # padding is one patient: the limits still match.
  tall <- lp_scores()[rep(seq_len(40L), 12L), ]
  tall$group[tall$group == "control"][seq_len(200L)] <- "treated"
  mh <- h$mirror_hist(tall, "unmatched", groups, 5)
  expect_gt(max(abs(mh$data$y)), 10)
  limits <- ggplot2::layer_scales(h$mirror_figure(mh, "unmatched"))$y$get_limits()
  expect_identical(limits, c(-h$mirror_limit(mh$data$y), h$mirror_limit(mh$data$y)))
})
