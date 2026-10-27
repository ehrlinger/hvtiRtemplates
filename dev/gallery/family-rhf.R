# Random hazard forest family: rhf-fit and rhf-explain, both in flight. A
# random hazard forest grows on counting-process data, one row per interval of
# a patient's follow-up, and the cohort has one row per patient, so this
# family's prepare() writes a second dataset and registers it as "intervals".
# The fit reads it by DATASET; the explain job reads the forest the fit saved
# in the same (subject, type) set, so the fit is listed first.
#
# The intervals are simulated by randomForestRHF itself, as the package's own
# tests do (tests/testthat/helper-rhf.R): 150 patients, up to four intervals
# each, a time-varying marker xtd and five baseline markers x_1 to x_5. 150,
# not fewer: tune.treesize.rhf() bounds the tree size by the events it sees
# divided by ten, and refuses a range whose top is under its floor of 5. Each
# simulated patient takes the identifier of one of the cohort's, so the two
# datasets share patient_id; nothing else is drawn from the cohort.
#
# Every number is simulated; no study appears here.

rhf_intervals <- function(built) {
  withr::with_seed(20261026, {
    sim <- randomForestRHF::hazard.simulation(type = 1, n = 150L, p = 3, nrecords = 4)
  })
  d <- if (is.data.frame(sim)) sim else sim$dta
  names(d) <- gsub(".", "_", names(d), fixed = TRUE)
  d$patient_id <- built$patient_id[d$id]
  d <- d[c("patient_id", setdiff(names(d), c("id", "patient_id")))]
  labels <- c(
    patient_id = "Patient identifier (synthetic)", start = "Interval start (follow-up time)",
    stop = "Interval stop (follow-up time)", event = "Event at the interval's stop",
    xtd = "Time-varying marker (simulated)"
  )
  baseline <- grep("^x_[0-9]+$", names(d), value = TRUE)
  labels[baseline] <- paste0("Baseline marker ", sub("^x_", "", baseline), " (simulated)")
  for (v in names(labels)) attr(d[[v]], "label") <- labels[[v]]
  d
}

rhf_register_intervals <- function(root, job) {
  dir <- hvtiRutilities::study_dir("datasets", root)
  if (file.exists(file.path(dir, "intervals.rds"))) return(invisible())
  saveRDS(rhf_intervals(readRDS(file.path(dir, "built.rds"))), file.path(dir, "intervals.rds"))
  invisible(utils::capture.output(suppressMessages(hvtiRutilities::register_data(
    root, built = "intervals.rds", dataset = "intervals", role = "named",
    population = "Synthetic counting-process intervals, 150 patients, one row per interval"
  ))))
}

gallery_family(
  "rhf",
  jobs = list(
    "rhf-fit" = list(subject = "event", type = "rhf", prepare = rhf_register_intervals, choices = list(
      # The opening line of the multi-line EDIT comment takes the sentence; the
      # rest stays a hidden comment, as family-rf.R does.
      "^<!-- EDIT: say which outcome this forest models" = paste0(
        "Gallery job on the synthetic intervals: the hazard of the simulated event, from one ",
        "time-varying marker (xtd) and three baseline markers.\n\n<!--"
      ),
      "^DATASET <- \"built\"$" = "DATASET <- \"intervals\"",
      "^ID <- \"ccfid\"$" = "ID <- \"patient_id\"",
      "^START <- " = "START <- \"start\"",
      "^STOP  <- " = "STOP  <- \"stop\"",
      "^EVENT <- " = "EVENT <- \"event\"",
      "^PREDICTORS <- " = "PREDICTORS <- c(\"xtd\", \"x_1\", \"x_2\", \"x_3\")",
      "^NTREE <- " = "NTREE <- 300"
    )),
    "rhf-explain" = list(subject = "event", type = "rhf", choices = list(
      "^<!-- EDIT: say which rhf-fit job in this set this explains" = paste0(
        "Explains the forest the `rhf-fit` job in this set saved: how well it ranks patients over ",
        "follow-up, their hazard curves, and which markers drive it.\n\n<!--"
      ),
      "^N_CURVES <- " = "N_CURVES <- 10"
    ))
  )
)
