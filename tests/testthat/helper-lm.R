lm_chunk <- function(src, label) {
  at <- which(trimws(src) == paste0("#| label: ", label))
  if (length(at) != 1L) stop("chunk '", label, "' found ", length(at), " times", call. = FALSE)
  end <- at + which(src[(at + 1L):length(src)] == "```")[1L]
  src[(at + 1L):(end - 1L)]
}

lm_run <- function(qualifier, labels, env, choices = list()) {
  src <- readLines(template_path("lm", qualifier), warn = FALSE)
  for (label in labels) {
    suppressMessages(eval(parse(text = lm_chunk(src, label)), envir = env))
    if (identical(label, "study-choices")) list2env(choices, envir = env)
  }
  invisible(env)
}

lm_data <- function(n = 120L) {
  set.seed(42)
  d <- data.frame(id = seq_len(n), age = stats::rnorm(n), female = rep(0:1, length.out = n))
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

lm_render_fixture <- function(qualifier, .local_envir = parent.frame()) {
  root <- tempfile("lm-study-")
  withr::defer(unlink(root, recursive = TRUE), envir = .local_envir)
  d <- lm_data()
  d$time <- seq_len(nrow(d))
  suppressMessages(hvtiRutilities::study_setup(
    root, study = "Synthetic lm study", study_tracker_id = 42L
  ))
  utils::write.csv(d, file.path(root, "00_datasets", "built.csv"), row.names = FALSE)
  suppressMessages(hvtiRutilities::register_data(
    root, built = "built.csv", event = "outcome", time = "time",
    role = "study", population = "Synthetic cohort"
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
    checkpred = 'DATASET <- "study"',
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
      model_formula, d, family = "binary", outcome_col = "outcome",
      id_col = "id", outcome_levels = c("none", "event"), event_level = "event"
    )
    model_dir <- file.path(hvtiRutilities::study_dir("estimates", root), "outcome-analysis")
    dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)
    saveRDS(model, file.path(model_dir, "lm-binary.rds"))
  }
  quarto::quarto_render(job, execute_dir = dirname(job), quiet = TRUE)
  list(root = root, job = job, output = sub("[.]qmd$", ".html", job))
}
