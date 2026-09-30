# Companion runner for a `bl` bootstrap report: a logistic screen with boot_select() and fit_logistic().
#
# add_job("bl", subject, type) writes this file beside the report, named
# <subject>-<type>-bl-runner.R. It is a job of its own and runs FIRST:
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

suppressPackageStartupMessages(library(hvtiRbootstrap))

# EDIT: the outcome column.
OUTCOME <- "outcome"

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

# The data contract. read_job_data() reads the rows, leaves MRN and eMRN out,
# and records the selection; the bag carries that selection to the report.
cfg <- hvtiRutilities::study_config()
job <- hvtiRtemplates::read_job_data(cfg, dataset = DATASET, analysis_set = ANALYSIS_SET, where = WHERE, id = ID, key = KEY)
selection <- attr(job$record, "selection")

# Only the model's columns are resampled, so the patient identifier never
# reaches the screen.
model <- stats::reformulate(POOL, response = OUTCOME)
d <- job$data[all.vars(model)]
screen <- boot_select(d, model, fit_logistic, n_rep = N_REP, sle = SLE, sls = SLS, seed = SEED)
bag <- boot_bag(screen, base_params = "(Intercept)", requested = length(POOL),
                manifest = list(sha256 = job$provenance$sha256))
attr(bag, "hvti_provenance") <- list(data = list(job$provenance), artifacts = list(), analysis = NULL, cohort = NULL,
                                     selection = selection)
out_dir <- file.path(hvtiRutilities::study_dir("estimates", cfg$root), paste0(SUBJECT, "-", TYPE))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
saveRDS(bag, file.path(out_dir, "bagging.rds"))
