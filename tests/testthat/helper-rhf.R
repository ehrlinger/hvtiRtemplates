# Counting-process data for rhf, simulated by randomForestRHF itself: one row
# per interval, with `id`, `start`, `stop`, `event`, a time-varying `xtd` and
# baseline `x.1` to `x.p`. The id becomes ccfid, as a built dataset names it,
# and is offset so the saved-forest scan below can tell a study id from the
# job-local numbers the forest is grown on. read_built() lowercases names.
# 150 patients, not fewer: tune.treesize.rhf() bounds the tree size by the events
# it sees divided by ten and refuses a range whose top is under its floor of 5,
# which 60 patients (about 50 events) fall short of.
rhf_data <- function(n = 150L) {
  withr::local_seed(20261026)
  sim <- randomForestRHF::hazard.simulation(type = 1, n = n, p = 3, nrecords = 4)
  d <- if (is.data.frame(sim)) sim else sim$dta
  names(d)[names(d) == "id"] <- "ccfid"
  d$ccfid <- 7350000000 + d$ccfid
  names(d) <- gsub(".", "_", names(d), fixed = TRUE)
  d
}

rhf_choices <- list(KEY = c("ccfid", "start"), START = "start", STOP = "stop", EVENT = "event",
                    PREDICTORS = c("xtd", "x_1", "x_2", "x_3"), NTREE = 20, SEED = 1, TREESIZE = NULL)

rhf_fit_labels <- c("setup", "edit-study-choices", "tbl-data", "cap", "tbl-cohort", "repair", "tbl-lookahead", "fit", "fig-tuning",
                    "save")

# A fit in a throwaway study; returns its chunk environment.
rhf_fit_first <- function(data = rhf_data(), choices = rhf_choices, .local_envir = parent.frame()) {
  env <- rf_env(data, .local_envir)  # nolint: object_usage_linter.
  rf_run("rhf", "fit", rhf_fit_labels, env, choices)  # nolint: object_usage_linter.
  env
}
