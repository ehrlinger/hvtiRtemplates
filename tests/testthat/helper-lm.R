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
  # "set" is the old name of the setup chunk, and a list that names both runs it once.
  for (label in unique(vapply(labels, setup_label, ""))) {  # nolint: object_usage_linter.
    if (identical(label, "setup")) {
      eval_setup_chunk(lm_chunk(src, label), env)  # nolint: object_usage_linter.
    } else {
      suppressMessages(eval(parse(text = lm_chunk(src, label)), envir = env))
    }
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

# Scaffold the `qualifier` job in a fresh study, work its EDIT: markers, and
# render it through Quarto, or, with `render = FALSE`, evaluate its chunks in
# this session (lm_eval_job).
lm_render_fixture <- function(qualifier, data = NULL, render = TRUE, choices = character(), .local_envir = parent.frame()) {
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
  # Study choices a test sets beyond the qualifier's own, such as `IMPUTATION <- "imp"`.
  replacements <- c(replacements, choices)
  lines <- gsub("EDIT:", "REVIEWED:", readLines(job, warn = FALSE), fixed = TRUE)
  for (replacement in replacements) {
    key <- sub(" .*", "", replacement)
    # The first line only: the study choice, not a later `IMPUTATION <- attr(...)` that reads a resolved value back.
    lines[which(grepl(paste0("^", key, " <- "), lines))[1L]] <- replacement
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
  if (!render) {
    return(list(root = root, job = job, env = lm_eval_job(job)))
  }
  quarto::quarto_render(job, execute_dir = dirname(job), quiet = TRUE)
  list(root = root, job = job, output = sub("[.]qmd$", ".html", job))
}

# Evaluate every chunk of the scaffolded `job` in order, from its directory and
# in an environment of its own, as a render would, but in this R session: a
# Quarto render starts Quarto, an R process and pandoc, three to five seconds
# a job before any of the job's own code runs. knitr::current_input() names
# the job, as it does in a render, so the chunks that read their own file do.
# The `provenance` chunk is not run: it refuses to run outside the study's
# Quarto project, on purpose, and test-template-provenance.R evaluates it for
# every lm template. Returns the environment the chunks ran in.
lm_eval_job <- function(job) {
  src <- readLines(job, warn = FALSE)
  labels <- setdiff(sub("^#\\| label: ", "", grep("^#\\| label: ", src, value = TRUE)), "provenance")
  env <- new.env(parent = globalenv())
  # `setup` attaches the job's packages, which a render does in a process of
  # its own; they come off the search path again here.
  attached <- search()
  on.exit(for (pkg in rev(setdiff(search(), attached))) detach(pkg, character.only = TRUE), add = TRUE)
  withr::local_dir(dirname(job))
  testthat::local_mocked_bindings(
    current_input = function(dir = FALSE) if (isTRUE(dir)) job else basename(job),
    .package = "knitr"
  )
  utils::capture.output(for (label in labels) {
    suppressMessages(eval(parse(text = lm_chunk(src, label)), envir = env))
  })
  env
}

# lp-mirror: a study whose lm-propensity_binary job has run, and the mirror
# job's own helpers. Kept in this file because they call the lm_* helpers above.

# The lm cohort with a pair-match flag, as a SAS match would leave it: two
# patients in three are matched. The identifiers are seven digits that occur
# nowhere else, so a report that printed one would be caught.
lp_data <- function(n = 120L) {
  d <- lm_data(n)
  d$ccfid <- 9100000L + d$ccfid
  d$match <- as.integer(d$ccfid %% 3L != 0L)
  d
}

# A study whose lm-propensity_binary job ran in the outcome-analysis set, with
# an lp-mirror job scaffolded beside it and its markers worked. Each element of
# `lines` replaces the study-choice line that starts with its setting's name,
# as lm_render_fixture() does. Returns the root, the job and the bundle path.
lp_fixture <- function(lines = character(), data = lp_data(), .local_envir = parent.frame()) {
  fit <- lm_render_fixture("propensity_binary", data = data, render = FALSE, .local_envir = .local_envir)
  job <- add_job("lp.mirror", "outcome", "analysis", dir = fit$root)
  src <- gsub("EDIT:", "REVIEWED:", readLines(job, warn = FALSE), fixed = TRUE)
  for (line in lines) {
    key <- sub(" .*", "", line)
    src[grepl(paste0("^", key, " <- "), src)] <- line
  }
  writeLines(src, job)
  list(root = fit$root, job = job, bundle = fit$env$MODEL_PATH)
}

# The lp-mirror template's helper functions, in an environment of their own.
lp_helpers <- function() {
  env <- new.env(parent = globalenv())
  src <- readLines(template_path("lp", "mirror"), warn = FALSE)
  # The package's own template chunk, as lm_run() evaluates the lm templates.
  eval(parse(text = lm_chunk(src, "helpers")), envir = env)
  env
}

# A second dataset in the fixture's study, registered as `match_file`, holding
# only the patients in `rows` of lp_data() plus `foreign` patients the scores
# were not computed for, with the pair-match flag `flag` for the kept rows.
lp_register_match <- function(root, rows, foreign = 0L, flag = lp_data()$match[rows]) {
  d <- lp_data()[rows, c("ccfid", "match"), drop = FALSE]
  d$match <- flag
  if (foreign > 0L) {
    d <- rbind(d, data.frame(ccfid = 9200000L + seq_len(foreign), match = rep(1L, foreign)))
  }
  utils::write.csv(d, file.path(root, "00_datasets", "match_file.csv"), row.names = FALSE)
  suppressMessages(hvtiRutilities::register_data(root, "match_file.csv", dataset = "match_file", role = "named",
                                                 key = "ccfid"))
}

# lg: a study whose built dataset the lg job calibrates, and the job scaffolded
# and its markers worked. Kept in this file because it calls the lm_* helpers
# above, which object_usage_linter must see.

# Seven-digit identifiers that occur nowhere else, so a report that printed one
# would be caught. `dead` and `iv_dead` are a death and its follow-up in years,
# the risk rising with age and NYHA class; `hdead` is an in-hospital death, the
# binary event; `nyha` is the ordinal covariate; `n_prior` counts prior
# operations and is 0 for most patients, which breaks the log and the inverse.
lg_data <- function(n = 400L) {
  withr::local_seed(11)
  age <- round(stats::rnorm(n, 62, 12))
  nyha <- sample(1:4, n, replace = TRUE, prob = c(0.2, 0.4, 0.3, 0.1))
  t_death <- stats::rexp(n, exp(-3 + 0.03 * (age - 60) + 0.4 * (nyha - 2)))
  censor <- stats::runif(n, 1, 10)
  data.frame(
    ccfid = 8300000L + seq_len(n), age = age, nyha = nyha,
    n_prior = stats::rpois(n, 0.4),
    dead = as.integer(t_death <= censor), iv_dead = round(pmin(t_death, censor), 3) + 0.001,
    hdead = stats::rbinom(n, 1L, stats::plogis(-3 + 0.04 * (age - 60) + 0.5 * (nyha - 2)))
  )
}

# The VARIABLES the fixture's job calibrates unless a test gives others: age, with
# a scale chosen, so the job renders without the warning a blank choice raises.
lg_chosen_variables <- c(
  "VARIABLES <- data.frame(",
  "  name = c(\"age\"),",
  "  chosen = c(\"log\")",
  ")"
)

# A study with an lg job scaffolded into it. Each element of `lines` replaces the
# study-choice line that starts with its setting's name, as lp_fixture() does;
# `variables` is the lines of the whole VARIABLES data frame, since it runs over
# several, and NULL leaves the template's own. Returns the root and the job.
lg_fixture <- function(lines = character(), variables = lg_chosen_variables, data = lg_data(),
                       .local_envir = parent.frame()) {
  root <- lm_study(.local_envir = .local_envir, data = data)
  job <- add_job("lg", "dead", "calibration", dir = root)
  src <- gsub("EDIT:", "REVIEWED:", readLines(job, warn = FALSE), fixed = TRUE)
  for (line in lines) {
    key <- sub(" .*", "", line)
    src[grepl(paste0("^", key, " <- "), src)] <- line
  }
  if (!is.null(variables)) {
    at <- which(src == "VARIABLES <- data.frame(")
    end <- at + which(src[(at + 1L):length(src)] == ")")[[1L]]
    src <- c(src[seq_len(at - 1L)], variables, src[-seq_len(end)])
  }
  writeLines(src, job)
  list(root = root, job = job)
}
