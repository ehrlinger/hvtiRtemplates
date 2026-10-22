# The sid templates are run chunk by chunk through rf_run() (helper-rf.R),
# whose chunk runner is not specific to random forests.

# The helpers in sid-clusters' `sid-helpers` chunk, evaluated alone, so they
# can be tested on hand-built inputs with no fit.
sid_helpers_env <- function() {
  src <- readLines(template_path("sid", "clusters"), warn = FALSE)
  env <- new.env(parent = globalenv())
  eval(parse(text = rf_chunk(src, "sid-helpers")), envir = env)  # nolint: object_usage_linter.
  env
}

# Three well-separated groups of 50 on four continuous variables and one
# factor, with a few values missing so the imputation has work to do. Seeded,
# so a test sees the same patients every run. `truth` is the planted group;
# it is not a clustering variable.
sid_data <- function(n_per = 50L, seed = 20261022L) {
  withr::with_seed(seed, {
    truth <- rep(1:3, each = n_per)
    center <- c(-3, 0, 3)[truth]
    d <- data.frame(
      a = stats::rnorm(3 * n_per, center), b = stats::rnorm(3 * n_per, -center),
      c = stats::rnorm(3 * n_per, center / 2), e = stats::rnorm(3 * n_per),
      f = factor(ifelse(truth == 3, "y", sample(c("x", "y"), 3 * n_per, replace = TRUE, prob = c(0.8, 0.2))))
    )
    d$a[sample(nrow(d), 5)] <- NA
    d$f[sample(nrow(d), 3)] <- NA
  })
  d$truth <- truth
  d
}

# NTREE = 500: at 50 trees the planted groups were not recovered (normalized
# measure 0.92, measured in review); at 200 it was 0.12. Each fit takes well
# under a second on 150 rows.
sid_fit_choices <- list(
  VARS = c("a", "b", "c", "e", "f"), MAX_MISSING = 0.4, NTREE = 500, SID_REDUCE = FALSE,
  IMPUTE = "mice", M = 1, MICE_MAXIT = 5, SEED = 1, REFIT = FALSE
)

# Every chunk of sid-fit, in order.
sid_fit_labels <- c("setup", "edit-study-choices", "tbl-data", "tbl-missing", "impute", "fit", "tbl-used", "tbl-agreement", "save")

# sid-fit run end to end in a throwaway study.
sid_fit_first <- function(data = sid_data(), choices = sid_fit_choices, .local_envir = parent.frame()) {
  rf_skip_unless_stack(rf_template_packages("sid", "fit"))  # nolint: object_usage_linter.
  env <- rf_env(data, .local_envir)  # nolint: object_usage_linter.
  rf_run("sid", "fit", sid_fit_labels, env, choices)  # nolint: object_usage_linter.
  env
}

sid_clusters_choices <- list(K_RANGE = 2:5, K = 3L, OVERRIDES = list(), COLLAPSE = NULL, MIN_SIZE = 20,
                             K_METRICS_MAX = 8, SAVE_FIGURES = FALSE, FIGURES = NULL)

# Every chunk of sid-clusters, in order.
sid_clusters_labels <- c("setup", "edit-study-choices", "sid-helpers", "handoff", "pam", "fig-metrics", "tbl-metrics",
                         "tbl-sizes", "small-clusters", "fig-sankey", "k-unset", "fig-silhouette", "tbl-silhouette", "fig-mds",
                         "tbl-collapse", "save")

# sid-clusters run in the set a sid-fit just wrote, in the same study.
sid_clusters_after <- function(env, choices = sid_clusters_choices) {
  rf_skip_unless_stack(rf_template_packages("sid", "clusters"))  # nolint: object_usage_linter.
  rf_run("sid", "clusters", sid_clusters_labels, env, choices)  # nolint: object_usage_linter.
}

# sid-fit rendered with Quarto in a throwaway study whose built dataset has a TEXT clustering
# variable (f) and missing values in a numeric one (a). Returns the study root and the job
# paths; sid_render_clusters() renders sid-clusters in it.
sid_render_fixture <- function(.local_envir = parent.frame()) {
  root <- tempfile("sid-study-")
  withr::defer(unlink(root, recursive = TRUE), envir = .local_envir)
  suppressMessages(hvtiRutilities::study_setup(root, study = "Synthetic sid study", study_tracker_id = 42L, renv = FALSE))
  d <- sid_data()
  d$f <- as.character(d$f)
  d <- cbind(ccfid = seq_len(nrow(d)), d[c("a", "b", "c", "e", "f")])
  utils::write.csv(d, file.path(root, "00_datasets", "built.csv"), row.names = FALSE)
  suppressMessages(hvtiRutilities::register_data(root, built = "built.csv", role = "study", population = "Synthetic cohort"))
  fit <- add_job("sid", "morph", "sid", dir = root, qualifier = "fit")  # nolint: object_usage_linter.
  sid_edit_job(fit, c('VARS <- c("a", "b", "c", "e", "f")', "NTREE <- 200", "SID_REDUCE <- FALSE", "MICE_MAXIT <- 5", "M <- 2"))
  quarto::quarto_render(fit, execute_dir = dirname(fit), quiet = TRUE)
  list(root = root, fit = fit)
}

# EDIT: markers reviewed and the named study choices set, each on its first assignment.
sid_edit_job <- function(job, choices) {
  lines <- gsub("EDIT:", "REVIEWED:", readLines(job, warn = FALSE), fixed = TRUE)
  for (choice in choices) {
    lines[which(grepl(paste0("^", sub(" .*", "", choice), " +<- "), lines))[1L]] <- choice
  }
  writeLines(lines, job)
}

# sid-clusters rendered in a fixture, with `choices` set. `before_csv` is lines to insert ahead of
# the save chunk's CSV name, for simulating a failure there. Returns the html path.
sid_render_clusters <- function(fixture, choices, before_csv = NULL, quiet = TRUE) {
  job <- list.files(dirname(fixture$fit), pattern = "clusters.*[.]qmd$", full.names = TRUE)[1L]
  if (is.na(job)) job <- add_job("sid", "morph", "sid", dir = fixture$root, qualifier = "clusters")  # nolint: object_usage_linter.
  sid_edit_job(job, choices)
  if (!is.null(before_csv)) {
    lines <- readLines(job, warn = FALSE)
    at <- grep("^\\.csv_name <- ", lines)[1L]
    writeLines(append(lines, before_csv, after = at - 1L), job)
  }
  quarto::quarto_render(job, execute_dir = dirname(job), quiet = quiet)
  sub("[.]qmd$", ".html", job)
}
