# Companion runner for a `bc` bootstrap report: a Cox screen with boot_select() and fit_cox().
#
# add_job("bc", subject, type) writes this file beside the report, named
# <subject>-<type>-bc-runner.R. It is a job of its own and runs FIRST:
# it screens and saves the bag, and the report only reads that bag. Run it from
# anywhere inside the study, with Rscript or source(), before rendering the
# report. Every study choice is marked by an EDIT marker below; work each
# marker and delete it.
#
# Two things here are the data contract and must survive your edits. The
# runner reads its rows with hvtiRtemplates::read_job_data(), and it saves the
# selection that call records in the bag's lineage. The report prints that
# selection, and stops on a bag that carries none.
#
# The runner also keeps the patient identifier out of what it saves: it
# resamples only the model's columns, and boot_bag() keeps
# coefficients, counts and settings: no row of data.

# Written by add_job() from the file name, as in the report; the bag lands in
# this set's estimates directory, where the report reads it.
SUBJECT <- "dead_pa"
TYPE    <- "hz"

# EDIT: set FINISHED to TRUE once every EDIT: marker below is worked and
# deleted. Until then this runner stops here, before it reads anything: a
# screen run on placeholder settings takes hours and produces a bag that looks
# like a result.
FINISHED <- FALSE
if (!FINISHED) {
  stop("This Cox bootstrap runner is unfinished: FINISHED is FALSE. It screens the candidates for the `bc` ",
       "report and saves the bag that report reads. Work every EDIT: marker in this file, set FINISHED <- TRUE, ",
       "then run it again.", call. = FALSE)
}

suppressPackageStartupMessages(library(hvtiRbootstrap))

# The report's own floor, checked here before the screen runs: below 0.9.3
# boot_select() records `sle` and `sls` and then selects on AIC, so a screen of
# hours would finish and then be refused by the report.
if (utils::packageVersion("hvtiRbootstrap") < "0.9.3") {
  stop("This runner needs hvtiRbootstrap >= 0.9.3; ",
       utils::packageVersion("hvtiRbootstrap"), " is installed. boot_bag() ",
       "converts a boot_select() screen into the bag the report reads, and ",
       "nothing below 0.9.2 has such a function; below 0.9.3 the screen ",
       "recorded `sle` and `sls` but selected on AIC, so the report's provenance ",
       "table would name criteria it never used.\nUpdate it, then ",
       "rerun.", call. = FALSE)
}

# EDIT: the follow-up time and the event indicator.
TIME <- "iv_dead"
EVENT <- "dead"

# EDIT: the candidate pool, every form offered, before any is dropped. Screen
# every form; the report groups them when it reads.
POOL <- c("age", "female")

# EDIT: the rows to screen, as in any job. DATASET and ANALYSIS_SET name the
# data, WHERE keeps rows (for example quote(age >= 18)), ID names the patient
# identifier and KEY the columns a row is unique on.
DATASET <- "study"
ANALYSIS_SET <- NULL
WHERE <- NULL
ID <- "ccfid"
KEY <- ID

# EDIT: from YOUR .sas %bootreg call: resampl=, sle= and sls=. The seed makes
# the run reproducible; the report prints it.
N_REP <- 1000
SLE <- 0.10
SLS <- 0.05
SEED <- 20260101

# EDIT: the base model. A Cox model has no intercept, so name a term the screen
# carries; its row leaves the frequency table, and the report's spread check
# watches it.
BASE <- "age"

# The data contract. read_job_data() reads the rows, leaves MRN and eMRN out,
# and records the selection; the bag carries that selection to the report.
cfg <- hvtiRutilities::study_config()
job <- hvtiRtemplates::read_job_data(cfg, dataset = DATASET, analysis_set = ANALYSIS_SET, where = WHERE, id = ID, key = KEY)
selection <- attr(job$record, "selection")

# Only the model's columns are resampled, so the patient identifier never
# reaches the screen.
model <- stats::as.formula(paste0("survival::Surv(", TIME, ", ", EVENT, ") ~ ", paste(POOL, collapse = " + ")))
d <- job$data[all.vars(model)]
screen <- boot_select(d, model, fit_cox, n_rep = N_REP, sle = SLE, sls = SLS, seed = SEED)
bag <- boot_bag(screen, base_params = BASE, requested = length(POOL),
                manifest = list(sha256 = job$provenance$sha256))
attr(bag, "hvti_provenance") <- list(data = list(job$provenance), artifacts = list(), analysis = NULL, cohort = NULL,
                                     selection = selection)
out_dir <- file.path(hvtiRutilities::study_dir("estimates", cfg$root), paste0(SUBJECT, "-", TYPE))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
saveRDS(bag, file.path(out_dir, "bagging.rds"))
