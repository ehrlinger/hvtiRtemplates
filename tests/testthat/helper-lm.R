lm_chunk <- function(src, label) {
  at <- which(trimws(src) == paste0("#| label: ", label))
  if (length(at) != 1L) stop("chunk '", label, "' found ", length(at), " times", call. = FALSE)
  end <- at + which(src[(at + 1L):length(src)] == "```")[1L]
  src[(at + 1L):(end - 1L)]
}

# The chunks that show one qualifier's result tables, in order. Each table is a
# chunk of its own, so that Quarto numbers it; a table-showing chunk is labeled
# tbl-, and the one that states the cumulative direction is `direction`.
lm_results <- function(qualifier) {
  src <- readLines(template_path("lm", qualifier), warn = FALSE)
  labels <- sub("^#\\| label: ", "", grep("^#\\| label: ", src, value = TRUE))
  labels[grepl("^tbl-", labels) & labels != "tbl-data" | labels == "direction"]
}

lm_run <- function(qualifier, labels, env, choices = list()) {
  src <- readLines(template_path("lm", qualifier), warn = FALSE)
  for (label in labels) {
    suppressMessages(eval(parse(text = lm_chunk(src, label)), envir = env))
    if (identical(label, "edit-study-choices")) {
      list2env(choices, envir = env)
      # A test that supplies `d` itself skips the data chunk, which would set
      # the identifier read_job_data() resolved and the selection it recorded.
      if (!"tbl-data" %in% labels) {
        if (!exists(".id", envir = env, inherits = FALSE)) env$.id <- env$ID
        if (!exists("job_data", envir = env, inherits = FALSE)) env$job_data <- list()
      }
    }
  }
  invisible(env)
}

lm_data <- function(n = 120L) {
  withr::local_seed(42)
  d <- data.frame(
    ccfid = seq_len(n), id = seq_len(n), age = stats::rnorm(n), female = rep(0:1, length.out = n)
  )
  p <- stats::plogis(-0.2 + 0.8 * d$age - 0.3 * d$female)
  d$outcome <- ifelse(stats::runif(n) < p, "event", "none")
  d$treatment <- ifelse(stats::runif(n) < p, "treated", "control")
  d$ordinal <- rep(c("low", "middle", "high"), length.out = n)
  d$nominal <- rep(c("reference", "level_b", "level_c"), length.out = n)
  d$treatment_ordinal <- rep(c("low", "middle", "high"), length.out = n)
  d$treatment_nominal <- rep(c("reference", "level_b", "level_c"), length.out = n)
  d$count <- stats::rpois(n, exp(0.3 + 0.2 * d$age))
  d
}

lm_mi_data <- function(n = 120L) {
  d <- lm_data(n)
  first <- transform(d, imp = 1L)
  second <- d
  second$age <- second$age + stats::rnorm(n, 0, 0.05)
  second$imp <- 2L
  rbind(first, second)
}

lm_study <- function(.local_envir = parent.frame(), data = lm_data()) {
  root <- withr::local_tempdir("lm-study-", .local_envir = .local_envir)
  suppressMessages(hvtiRutilities::study_setup(
    root, study = "LM chunk test", study_tracker_id = 42L, adopt = TRUE
  ))
  utils::write.csv(
    data,
    file.path(hvtiRutilities::study_dir("datasets", root), "built.csv"),
    row.names = FALSE
  )
  suppressMessages(hvtiRutilities::register_data(root, built = "built.csv"))
  root
}

lm_render_fixture <- function(qualifier, data = NULL, .local_envir = parent.frame()) {
  root <- tempfile("lm-study-")
  withr::defer(unlink(root, recursive = TRUE), envir = .local_envir)
  d <- if (is.null(data)) lm_data() else data
  d$time <- seq_len(nrow(d))
  suppressMessages(hvtiRutilities::study_setup(
    root, study = "Synthetic lm study", study_tracker_id = 42L
  ))
  utils::write.csv(d, file.path(root, "00_datasets", "built.csv"), row.names = FALSE)
  suppressMessages(hvtiRutilities::register_data(
    root, built = "built.csv", role = "study", population = "Synthetic cohort"
  ))
  job <- add_job("lm", "outcome", "analysis", dir = root, qualifier = qualifier)
  replacements <- switch(
    qualifier,
    binary = c(
      'OUTCOME_LEVELS <- c("none", "event")',
      'EVENT_LEVEL <- "event"'
    ),
    ordinal = 'OUTCOME <- "ordinal"',
    nominal = 'OUTCOME <- "nominal"',
    propensity_ordinal = 'TREATMENT <- "treatment_ordinal"',
    propensity_nominal = 'TREATMENT <- "treatment_nominal"',
    # Validated on patients the saved model was not trained on (below). WHERE
    # may not name the ID, so it selects on `time`, which follows ccfid here.
    checkpred = "WHERE <- quote(time > 60)",
    balancing_count = c('OUTCOME <- "count"', 'DISTRIBUTION <- "poisson"'),
    character()
  )
  lines <- gsub("EDIT:", "REVIEWED:", readLines(job, warn = FALSE), fixed = TRUE)
  for (replacement in replacements) {
    key <- sub(" .*", "", replacement)
    lines[grepl(paste0("^", key, " <- "), lines)] <- replacement
  }
  writeLines(lines, job)
  if (identical(qualifier, "checkpred")) {
    model_formula <- stats::as.formula("outcome ~ age + female", env = baseenv())
    model <- hvtiRpropensity::fit_logistic(
      model_formula, d[d$ccfid <= 60, ], family = "binary", outcome_col = "outcome",
      id_col = "ccfid", outcome_levels = c("none", "event"), event_level = "event"
    )
    model_provenance <- hvtiRtemplates:::.lm_fit_provenance(model)
    model <- hvtiRtemplates:::.attach_handoff_lineage(
      model,
      data = list(hvtiRutilities::provenance_data(
        cfg = hvtiRutilities::study_config(root), role = "training"
      )),
      analysis = model_provenance$analysis,
      cohort = model_provenance$cohort
    )
    model_dir <- file.path(hvtiRutilities::study_dir("estimates", root), "outcome-analysis")
    dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)
    saveRDS(model, file.path(model_dir, "lm-binary.rds"))
  }
  quarto::quarto_render(job, execute_dir = dirname(job), quiet = TRUE)
  list(root = root, job = job, output = sub("[.]qmd$", ".html", job))
}
