# The hazard chain (ac, hz, hm, hp, hs) is run here chunk by chunk, as the rf
# and lm templates are: each chunk is parsed out of the template by its label
# and evaluated in one environment.

# Evaluate the chunks `labels` of template `prefix` in `env`. After
# `edit-study-choices` runs, `choices` overwrites its values, as a study
# author's edits would.
hazard_run <- function(prefix, labels, env, choices = list()) {
  src <- readLines(template_path(prefix), warn = FALSE)
  for (label in labels) {
    at <- which(trimws(src) == paste0("#| label: ", label))
    if (length(at) != 1L) stop("chunk '", label, "' found ", length(at), " times", call. = FALSE)
    end <- at + which(src[(at + 1L):length(src)] == "```")[1L]
    suppressMessages(eval(parse(text = src[(at + 1L):(end - 1L)]), envir = env))
    if (identical(label, "edit-study-choices")) list2env(choices, envir = env)
  }
  invisible(env)
}

# A cohort with an early and a late risk, so a two-phase fit has something to
# find. `id` names the identifier column: "ccfid", or "MRN" to exercise the
# fallback that keeps MRN as the job's ID.
hazard_data <- function(n = 160L, id = "ccfid") {
  set.seed(20260929)
  age <- round(stats::runif(n, 20, 85))
  x1 <- stats::rnorm(n)
  early <- stats::rexp(n, 2)
  late <- stats::rweibull(n, shape = 2, scale = 6 * exp(-0.3 * x1))
  censor <- stats::runif(n, 1, 8)
  death <- ifelse(stats::runif(n) < 0.3, early, late)
  d <- data.frame(
    id = 73500000L + seq_len(n), age = age, x1 = x1,
    male = stats::rbinom(n, 1L, 0.6), other = stats::rbinom(n, 1L, 0.2),
    iv_dead = pmax(pmin(death, censor), 0.01), dead = as.integer(death <= censor)
  )
  names(d)[[1L]] <- id
  d
}

# A study whose built dataset is `data`, registered so read_job_data() and
# verify_manifest() work as they do in a real study.
hazard_study <- function(data = hazard_data(), .local_envir = parent.frame()) {
  root <- withr::local_tempdir("hazard-study-", .local_envir = .local_envir)
  suppressMessages(hvtiRutilities::study_setup(root, study = "Hazard chain test", study_tracker_id = 7L, adopt = TRUE))
  utils::write.csv(data, file.path(hvtiRutilities::study_dir("datasets", root), "built.csv"), row.names = FALSE)
  suppressWarnings(suppressMessages(hvtiRutilities::register_data(root, built = "built.csv")))
  normalizePath(root)
}

# A fresh chunk environment for `root`. Its parent is the global environment,
# as a render's is. The setup chunk is not run, so what it defines is supplied:
# study_config(), from the hvtiRutilities it attaches, and the empty provenance.
hazard_env <- function(root) {
  env <- new.env(parent = globalenv())
  env$.root <- root
  env$.provenance_data <- list()
  env$.provenance_artifacts <- list()
  env$study_config <- hvtiRutilities::study_config
  env
}

# The hand-off lineage an upstream hazard job records: the data it read, its
# rows as a selection, and the time and event it fitted.
hazard_lineage <- function(root, where = NULL, time = "iv_dead", event = "dead") {
  cfg <- hvtiRutilities::study_config(root)
  job <- read_job_data(cfg, where = where)
  list(
    data = list(job$provenance),
    analysis = list(time = list(variable = time), event = list(variable = event, event = 1L, censored = 0L)),
    cohort = list(n = nrow(job$data)),
    selection = c(attr(job$record, "selection"), list(time = time, event = event))
  )
}

hazard_save <- function(object, lineage, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  saveRDS(hvtiRtemplates:::.attach_handoff_lineage(
    object, data = lineage$data, analysis = lineage$analysis, cohort = lineage$cohort,
    selection = lineage$selection
  ), path)
  path
}

# The set directory the templates' `set` chunk resolves: SUBJECT dead_pa, TYPE hz.
hazard_set_path <- function(root, file) {
  file.path(hvtiRutilities::study_dir("estimates", root), "dead_pa-hz", file)
}

# Every upstream hand-off a downstream job reads, all recording `lineage`.
hazard_upstream <- function(root, lineage) {
  hazard_save(list(overall = data.frame(time = 1)), lineage, hazard_set_path(root, "ac.rds"))
  hazard_save(list(deterministic = list(ok = TRUE)), lineage, hazard_set_path(root, "hz.rds"))
  hazard_save(list(reported = list(ok = TRUE)), lineage, hazard_set_path(root, "hm.rds"))
}

# Run a downstream job's choices, then its upstream read and data chunk.
hazard_downstream <- function(prefix, root, choices = list()) {
  env <- hazard_env(root)
  hazard_run(prefix, c("set", "edit-study-choices"), env, choices)
  hazard_run(prefix, c("read-upstream", "data"), env)
  env
}
