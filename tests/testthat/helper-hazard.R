# The hazard chain (ac, hz, hm, hp, hs) is run here chunk by chunk, as the rf
# and lm templates are: each chunk is parsed out of the template by its label
# and evaluated in one environment.

# The file of the template called `name`, as template_list() names it: "hm", or
# "hs-setup" for a qualified one. template_path() takes a prefix and stops on
# one that carries several templates.
hazard_template <- function(name) {
  templates <- template_list()
  hit <- which(templates$name == name)
  if (length(hit) != 1L) stop("template '", name, "' found ", length(hit), " times", call. = FALSE)
  templates$file[[hit]]
}

# Evaluate the chunks `labels` of template `prefix` in `env`. After
# `edit-study-choices` runs, `choices` overwrites its values, as a study
# author's edits would.
hazard_run <- function(prefix, labels, env, choices = list()) {
  src <- readLines(hazard_template(prefix), warn = FALSE)
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
  withr::local_seed(20260929)
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

# ---- #203: searching a saved file for patient identifiers ----------------------

# TRUE when `bytes` hold `value` as text or as R's big-endian integer or double encoding.
hazard_bytes_hold <- function(bytes, value) {
  patterns <- list(charToRaw(as.character(value)), writeBin(as.double(value), raw(), endian = "big"),
                   writeBin(as.integer(value), raw(), endian = "big"))
  any(vapply(patterns, function(p) length(grepRaw(p, bytes, fixed = TRUE)) > 0L, logical(1L)))
}

hazard_rds_bytes <- function(path) {
  con <- gzfile(path, "rb")
  on.exit(close(con))
  readBin(con, "raw", n = 1e8)
}

# Run ac, hz, hm and hs on `data`, keyed on MRN. A render evaluates every chunk
# in the global environment, which a saved fit refers to by reference only, so
# they run there, and the names they create are removed when `.local_envir`
# ends. hm runs in `hm_env`, so a test can also run it somewhere a render does
# not. Returns the environment hm ran in.
hazard_chain_run <- function(root, data, hm_env = globalenv(), .local_envir = parent.frame()) {
  cc <- hvtiRutilities::cohort_counts(data, event = "dead", time = "iv_dead")
  expected <- list(n = cc$n, n_events = cc$n_events, n_censored = cc$n_censored)
  env <- globalenv()
  before <- ls(env, all.names = TRUE)
  withr::defer(rm(list = setdiff(ls(env, all.names = TRUE), before), envir = env), envir = .local_envir)
  list2env(as.list(hazard_env(root), all.names = TRUE), envir = env)
  if (!identical(hm_env, env)) list2env(as.list(hazard_env(root), all.names = TRUE), envir = hm_env)
  # TemporalHazard's own notes on a synthetic fit (an ignored control, a
  # Hessian that is not positive-definite) are about the fit, not the file.
  suppressWarnings(utils::capture.output({
    hazard_run("ac", c("set", "edit-study-choices"), env, list(EXPECTED = expected))
    hazard_run("ac", c("data", "cohort", "km-helpers", "km-overall"), env)
    hazard_run("hz", c("set", "edit-study-choices"), env, list(EXPECTED = expected))
    hazard_run("hz", c("data", "cohort", "phases", "edit-start", "edit-response", "response-check", "guard",
                       "fit-deterministic", "convergence", "edit-multistart", "noconserve", "conservation-binding",
                       "edit-estimates", "save"), env)
    hazard_run("hm", c("set", "edit-study-choices"), hm_env, list(EXPECTED = expected, DECILE_TIME = 3))
    hm_env$COVARIATES <- list(early = "x1", late = c("x1", "age"))
    hazard_run("hm", c("read-upstream", "data", "cohort", "audit", "phases", "edit-fit", "edit-reported",
                       "calibration", "save"), hm_env)
    hazard_run("hs-setup", c("set", "edit-study-choices"), env,
               list(EXPECTED = expected, HORIZONS = c(1, 2), VINTAGE = "table2023"))
    hazard_run("hs-setup", c("read-upstream", "data", "cohort", "model", "horizons", "predict", "expected",
                             "edit-obs-vs-exp", "save"), env)
  }))
  hm_env
}

# TRUE when any of `ids` is in the decompressed bytes of the saved `file`.
hazard_file_holds_any <- function(root, file, ids) {
  bytes <- hazard_rds_bytes(hazard_set_path(root, file))
  any(vapply(ids, function(v) hazard_bytes_hold(bytes, v), logical(1L)))
}

# ---- hs-concordance -----------------------------------------------------------
# hs-concordance reads one fitted hm model per treatment group, each from its
# own set. This builds that estate: a study whose built data carries a `group`
# column, and an hz and hm fit for each group, in sets `dead-<group>`.

# hazard_data() with a treatment group whose late risk differs, so the two
# groups' models predict differently.
concordance_data <- function(n = 240L) {
  d <- hazard_data(n)
  withr::local_seed(20260930)
  d$group <- ifelse(stats::runif(n) < 0.5, "a", "b")
  d
}

# Fit hz and hm on each group's rows, in set `dead-<group>`, in the global
# environment as a render would. Returns the environment the last hm ran in.
concordance_fit <- function(root, data, groups = c("a", "b"), .local_envir = parent.frame()) {
  env <- globalenv()
  before <- ls(env, all.names = TRUE)
  withr::defer(rm(list = setdiff(ls(env, all.names = TRUE), before), envir = env), envir = .local_envir)
  for (g in groups) {
    rows <- data[data$group == g, , drop = FALSE]
    cc <- hvtiRutilities::cohort_counts(rows, event = "dead", time = "iv_dead")
    expected <- list(n = cc$n, n_events = cc$n_events, n_censored = cc$n_censored)
    list2env(as.list(hazard_env(root), all.names = TRUE), envir = env)
    where <- bquote(group == .(g))
    suppressWarnings(utils::capture.output({
      hazard_run("hz", c("set", "edit-study-choices"), env,
                 list(EXPECTED = expected, WHERE = where, SUBJECT = "dead", TYPE = g))
      hazard_run("hz", c("data", "cohort", "phases", "edit-start", "edit-response", "response-check", "guard",
                         "fit-deterministic", "convergence", "edit-multistart", "noconserve", "conservation-binding",
                         "edit-estimates", "save"), env)
      hazard_run("hm", c("set", "edit-study-choices"), env, list(EXPECTED = expected, DECILE_TIME = 3, SUBJECT = "dead", TYPE = g))
      env$COVARIATES <- list(early = "x1", late = c("x1", "age"))
      hazard_run("hm", c("read-upstream", "data", "cohort", "audit", "phases", "edit-fit", "edit-reported",
                         "calibration", "save"), env)
    }))
  }
  invisible(env)
}

# The core chunks of hs-concordance, in order, without the decision.
concordance_core <- c("data", "cohort", "models", "groups", "covariates", "horizon", "support", "predict")

# Choices that make the job runnable against concordance_fit()'s estate.
concordance_choices <- function(data, ...) {
  cc <- hvtiRutilities::cohort_counts(data, event = "dead", time = "iv_dead")
  utils::modifyList(list(
    EXPECTED = list(n = cc$n, n_events = cc$n_events, n_censored = cc$n_censored),
    MODELS = c(a = "dead-a", b = "dead-b"), GROUP = "group", HORIZON = 2,
    CARRY = "age", OVERLAP = "none", SUBJECT = "dead", TYPE = "ab"
  ), list(...))
}

# Run hs-concordance's `labels` in a fresh environment with `choices`.
concordance_run <- function(root, choices, labels = c(concordance_core, "edit-decision", "save")) {
  env <- hazard_env(root)
  suppressWarnings(utils::capture.output({
    hazard_run("hs-concordance", c("set", "edit-study-choices"), env, choices)
    hazard_run("hs-concordance", labels, env)
  }))
  env
}

concordance_estate <- function(.local_envir = parent.frame()) {
  data <- concordance_data()
  root <- hazard_study(data, .local_envir = .local_envir)
  concordance_fit(root, data, .local_envir = .local_envir)
  list(root = root, data = data)
}

skip_concordance <- function() {
  testthat::skip_if_not_installed("TemporalHazard", minimum_version = "1.2.8")
  testthat::skip_if_not_installed("numDeriv")
}
