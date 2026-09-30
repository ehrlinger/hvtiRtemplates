# Companion runner for a `bh` bootstrap report: a multiphase hazard screen with TemporalHazard::hzr_bootstrap(), in chunks.
#
# add_job("bh", subject, type) writes this file beside the report, named
# <subject>-<type>-bh-runner.R. It is a job of its own and runs FIRST:
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
# resamples only the model's columns, and the bag's `boot`
# field takes four fields of the hzr_bootstrap() result and no more.


# Written by add_job() from the file name, as in the report; the bag lands in
# this set's estimates directory, where the report reads it.
SUBJECT <- "dead_pa"
TYPE    <- "hz"

suppressPackageStartupMessages(library(TemporalHazard))

# EDIT: the candidate pool, every form offered, before any is dropped. It sets
# which columns are read and how many candidates each phase was offered; the
# scope in the hzr_bootstrap() call below must name the same columns.
POOL <- c("age", "female")

# EDIT: the rows to screen, as in any job. DATASET and ANALYSIS_SET name the
# data, WHERE keeps rows (for example quote(age >= 18)), ID names the patient
# identifier and KEY the columns a row is unique on.
DATASET <- "study"
ANALYSIS_SET <- NULL
WHERE <- NULL
ID <- "ccfid"
KEY <- ID

# EDIT: this run's chunk. Run the script once per chunk, each with its own
# number: a screen is days of compute, and hzr_bootstrap() writes nothing until
# its final replicate, so chunks are what make it restartable.
CHUNK <- 1L
# EDIT: from YOUR .sas %hazboot call: replicates per chunk, slentry=, slstay=
# and the step cap. Each chunk's seed differs, and the report refuses two that share one.
N_BOOT <- 20L
SLENTRY <- 0.10
SLSTAY <- 0.05
MAX_STEPS <- 50L
SEED <- 20260100L + CHUNK

# The data contract. read_job_data() reads the rows, leaves MRN and eMRN out,
# and records the selection; the bag carries that selection to the report.
cfg <- hvtiRutilities::study_config()
job <- hvtiRtemplates::read_job_data(cfg, dataset = DATASET, analysis_set = ANALYSIS_SET, where = WHERE, id = ID, key = KEY)
selection <- attr(job$record, "selection")

# Only the model's columns are resampled, so the patient identifier never
# reaches the screen.
d <- job$data[c("iv_dead", "dead", POOL)]

# EDIT: the shapes, from your hz job, held fixed as %hazboot does, and the time
# and event columns. The model formula is written literally in the hazard()
# call: the report's health check shows what a formula held in a variable does.
phases <- list(early = hzr_phase("cdf", t_half = 0.05, nu = 1, m = 1, fixed = "shapes"),
               constant = hzr_phase("constant"))
base <- hazard(survival::Surv(iv_dead, dead) ~ 1, data = d, dist = "multiphase", phases = phases, fit = TRUE)
t0 <- Sys.time()
# EDIT: the scope, written literally per phase: the same columns as POOL.
bs <- hzr_bootstrap(base, n_boot = N_BOOT, seed = SEED, scope = list(early = ~ age + female, constant = ~ age + female),
                    slentry = SLENTRY, slstay = SLSTAY, max_steps = MAX_STEPS)

# The bag is a plain list. `boot` takes four fields of the result and no more:
# its `scope` holds formulas, and a formula saved whole carries the environment
# it was written in, the data included. The first base parameter must be free:
# the report's health check watches its spread.
offered <- c(early = length(POOL), constant = length(POOL))
bag <- list(
  n_boot = bs$n_success, seed = SEED, slentry = SLENTRY, slstay = SLSTAY, max_steps = MAX_STEPS,
  base_params = c("early.log_mu", "constant.log_mu"), requested = offered, usable = offered, n_rows = nrow(d),
  elapsed_mins = as.numeric(difftime(Sys.time(), t0, units = "mins")),
  manifest = list(sha256 = job$provenance$sha256), th_version = format(utils::packageVersion("TemporalHazard")),
  boot = bs[c("replicates", "summary", "n_success", "n_failed")]
)
attr(bag, "hvti_provenance") <- list(data = list(job$provenance), artifacts = list(), analysis = NULL, cohort = NULL,
                                     selection = selection)
out_dir <- file.path(hvtiRutilities::study_dir("estimates", cfg$root), paste0(SUBJECT, "-", TYPE))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
# The report reads chunks under its BOOT_PREFIX, "bh" unless you change it.
saveRDS(bag, file.path(out_dir, sprintf("bh.chunk%02d.rds", CHUNK)))
