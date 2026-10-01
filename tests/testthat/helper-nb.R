# nb-boostmtree is run here chunk by chunk, as the rf and hazard templates are.

nb_template <- function() {
  templates <- template_list()
  hit <- which(templates$name == "nb-boostmtree")
  if (length(hit) != 1L) stop("template 'nb-boostmtree' found ", length(hit), " times", call. = FALSE)
  templates$file[[hit]]
}

# Evaluate chunks `labels` in `env`; `choices` overwrite edit-study-choices.
nb_run <- function(labels, env, choices = list()) {
  src <- readLines(nb_template(), warn = FALSE)
  for (label in labels) {
    at <- which(trimws(src) == paste0("#| label: ", label))
    if (length(at) != 1L) stop("chunk '", label, "' found ", length(at), " times", call. = FALSE)
    end <- at + which(src[(at + 1L):length(src)] == "```")[1L]
    suppressMessages(eval(parse(text = src[(at + 1L):(end - 1L)]), envir = env))
    if (identical(label, "edit-study-choices")) list2env(choices, envir = env)
  }
  invisible(env)
}

# A small longitudinal cohort: 40 patients, 3 to 6 visits each, a continuous
# response that drifts with time and age. `id` names the ID column: "ccfid",
# or "MRN" to exercise the fallback that keeps MRN as the job's ID. IDs are
# ten digits, so a byte search cannot match one by chance.
nb_data <- function(n = 40L, id = "ccfid") {
  withr::local_seed(20261001)
  visits <- sample(3:6, n, replace = TRUE)
  pid <- rep(4730000000 + seq_len(n), visits)
  age <- rep(round(stats::runif(n, 30, 80)), visits)
  female <- rep(stats::rbinom(n, 1L, 0.4), visits)
  # Visit times are drawn without replacement, so no patient has two visits at
  # one time and the cohort is unique on KEY <- c(ID, TIME).
  iv_echo <- unlist(lapply(visits, function(k) sort(sample(0:800, k)) / 100))
  d <- data.frame(id = pid, iv_echo = iv_echo, age = age, female = female, grp = rep(sample(c("a", "b"), n, TRUE), visits))
  d$lvef <- 55 - 0.8 * d$iv_echo + 0.1 * (d$age - 55) - 2 * d$female + stats::rnorm(nrow(d), 0, 2)
  names(d)[[1L]] <- id
  d
}

nb_study <- function(data = nb_data(), .local_envir = parent.frame()) {
  root <- withr::local_tempdir("nb-study-", .local_envir = .local_envir)
  suppressMessages(hvtiRutilities::study_setup(root, study = "nb test", study_tracker_id = 9L, adopt = TRUE))
  utils::write.csv(data, file.path(hvtiRutilities::study_dir("datasets", root), "built.csv"), row.names = FALSE)
  suppressWarnings(suppressMessages(hvtiRutilities::register_data(root, built = "built.csv")))
  normalizePath(root)
}

# A chunk environment for `root`, parented on globalenv as a render's is.
nb_env <- function(root, parent = globalenv()) {
  env <- new.env(parent = parent)
  env$.root <- root
  env$.provenance_data <- list()
  env$study_config <- hvtiRutilities::study_config
  env
}

nb_skip_unless_stack <- function() {
  testthat::skip_if_not_installed("boostmtree", minimum_version = "2.0.2")
  testthat::skip_if_not_installed("ggBoostedTrees")
}

nb_choices <- function(...) {
  utils::modifyList(list(RESPONSE = "lvef", M = 20, SEED = 7), list(...))
}
