# The vt templates are run chunk by chunk through rf_run() (helper-rf.R).

# Two arms of unequal size with a planted arm-by-covariate effect: high `xs`
# does better on arm "A", low `xs` on arm "B". `x1` and `g1` are null. Five arm
# "A" patients are planted far from every arm "B" patient in `xs`, and ten
# rows have no arm. Seeded, so a test sees the same patients every run.
vt_data <- function(n = 300L, seed = 20261022L) {
  withr::with_seed(seed, {
    arm <- sample(c("A", "B"), n, replace = TRUE, prob = c(0.65, 0.35))
    xs <- stats::rnorm(n)
    d <- data.frame(
      ccfid = seq_len(n), arm = arm, xs = xs, x1 = stats::rnorm(n),
      g1 = factor(sample(c("u", "v", "w"), n, replace = TRUE))
    )
    d$xs[which(d$arm == "A")[1:5]] <- 6 + (1:5) / 10
    lp <- ifelse(d$arm == "A", -1.2 * d$xs, 1.2 * d$xs)
    event_time <- stats::rexp(n, 0.2 * exp(lp))
    censor <- stats::runif(n, 2, 8)
  })
  d$time <- pmin(event_time, censor)
  d$event <- as.integer(event_time <= censor)
  d$arm[(n - 9):n] <- NA
  d
}

vt_choices <- list(
  TIME = "time", STATUS = "event", ID = "ccfid", ARM = "arm", ARMS = c("A", "B"),
  VP_SET = NULL, PREDICTORS = c("xs", "x1", "g1"), EXCLUDE = character(),
  ELIGIBILITY = "gower", COMBINE = "any", SID_SET = NULL,
  NA_ACTION = "na.impute", IMPUTATION = NULL, IMPUTATION_USE = 1L,
  HORIZON = 2, NTREE = 50, NSPLIT = 8, SEED = 1, SAVE_FIGURES = FALSE
)

# Every chunk of vt-fit, in order. Tasks 2 and 3 extend it.
vt_fit_labels <- c("setup", "edit-study-choices", "tbl-data", "predictors",
                   "ood", "eligibility", "tbl-ood", "fig-ood", "tbl-agreement")

vt_fit_labels_all <- c(vt_fit_labels, "fit", "tbl-performance", "curves-helper", "curves", "rmst-helper",
                       "rmst", "fig-curves", "save")

# The digest the job keys a raw ID by, in a fixture study.
vt_digest <- function(env, ids) hvtiRtemplates:::.id_digest(ids, hvtiRtemplates:::.study_id_key(env$.root))

vt_fit_first <- function(data = vt_data(), choices = vt_choices, labels = vt_fit_labels,
                         .local_envir = parent.frame()) {
  # rf_run() strips library() from setup, so attach the template's own stack
  # (and skip when it is absent) rather than rely on an earlier test having.
  rf_skip_unless_stack(rf_template_packages("vt", "fit"))  # nolint: object_usage_linter.
  env <- rf_env(data, .local_envir)  # nolint: object_usage_linter.
  rf_run("vt", "fit", labels, env, choices)  # nolint: object_usage_linter.
  env
}

# The helper chunks of vt-fit, evaluated alone, so a test can call vt_ood()
# without a study or a forest.
vt_helpers <- function() {
  env <- new.env()
  src <- readLines(template_path("vt", "fit"), warn = FALSE)
  for (label in c("ood", "curves-helper", "rmst-helper")) {
    if (any(trimws(src) == paste0("#| label: ", label))) {
      eval(parse(text = rf_chunk(src, label)), envir = env)  # nolint: object_usage_linter.
    }
  }
  env
}

vt_explain_labels <- c("setup", "edit-study-choices", "handoff", "explain-data", "fig-contrast", "fig-ranking",
                       "fig-twin-curves", "fig-received-best", "tbl-sensitivity")
# Not "provenance": that chunk refuses to run outside a render.
vt_explain_labels_all <- c(vt_explain_labels, "stratify", "tbl-stratum", "overlap-weights", "tbl-betas", "fig-betas", "tbl-benefit")

# rf_run() strips library() from setup; attach the explain stack itself.
vt_explain_defaults <- list(STRATIFY = NULL, BOOT = 0L, GAIN_MIN = 0, SAVE_FIGURES = FALSE)
vt_explain <- function(env, labels = vt_explain_labels, choices = vt_explain_defaults) {
  rf_skip_unless_stack(rf_template_packages("vt", "explain"))  # nolint: object_usage_linter.
  rf_run("vt", "explain", labels, env, choices)  # nolint: object_usage_linter.
}

# A sibling vp-fit set holding a hand-built screen, then vt-fit through
# `predictors`. setup runs first so set_path() exists to place the sibling.
vt_with_screen <- function(screen, choices, .local_envir = parent.frame()) {
  env <- rf_env(vt_data(), .local_envir)  # nolint: object_usage_linter.
  rf_run("vt", "fit", "setup", env, choices)  # nolint: object_usage_linter.
  vp_dir <- file.path(dirname(dirname(env$set_path("estimates", "vt.rds"))), choices$VP_SET)
  dir.create(vp_dir, recursive = TRUE)
  saveRDS(screen, file.path(vp_dir, "vp.rds"))
  # The hand-built screen carries no lineage, which .read_handoff() would refuse.
  testthat::local_mocked_bindings(
    .read_handoff = function(path, ...) list(value = readRDS(path), lineage = list(data = list()), record = list()),
    .package = "hvtiRtemplates", .env = .local_envir
  )
  rf_run("vt", "fit", c("edit-study-choices", "tbl-data", "predictors"), env, choices)  # nolint: object_usage_linter.
  env
}

# A fresh study with both vt jobs scaffolded, edited and rendered through Quarto.
vt_render_fixture <- function(.local_envir = parent.frame()) {
  root <- tempfile("vt-study-")
  withr::defer(unlink(root, recursive = TRUE), envir = .local_envir)
  suppressMessages(hvtiRutilities::study_setup(root, study = "Synthetic vt study", study_tracker_id = 42L, renv = FALSE))
  utils::write.csv(vt_data(), file.path(root, "00_datasets", "built.csv"), row.names = FALSE)
  suppressMessages(hvtiRutilities::register_data(root, built = "built.csv", role = "study", population = "Synthetic cohort"))
  set_line <- function(lines, key, value) {
    lines[which(grepl(paste0("^", key, " <- "), lines))[1L]] <- paste(key, "<-", value)
    lines
  }
  jobs <- vapply(c("fit", "explain"), function(q) {
    job <- add_job("vt", "dead", "vt", dir = root, qualifier = q)
    lines <- gsub("EDIT:", "REVIEWED:", readLines(job, warn = FALSE), fixed = TRUE)
    if (q == "fit") {
      for (kv in list(c("TIME", '"time"'), c("STATUS", '"event"'), c("ARM", '"arm"'), c("ARMS", 'c("A", "B")'),
                      c("PREDICTORS", 'c("xs", "x1", "g1")'), c("HORIZON", "2"), c("NTREE", "50"))) {
        lines <- set_line(lines, kv[1], kv[2])
      }
    } else {
      lines <- set_line(lines, "BOOT", "20")
    }
    writeLines(lines, job)
    job
  }, "")
  for (job in jobs) quarto::quarto_render(job, execute_dir = dirname(job), quiet = TRUE)
  list(root = root, jobs = jobs, outputs = sub("[.]qmd$", ".html", jobs))
}
