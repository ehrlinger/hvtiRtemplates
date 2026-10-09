# Bootstrap variable selection family: bl (logistic), br (linear), bc (Cox)
# and bh (multiphase hazard). These templates REPORT on a screen; they do not
# run one. add_job() writes each report's companion runner beside it,
# <prefix>.<subject>.<type>.runner.R, and each job's prepare() works that
# runner as a study author would: it sets the runner's study choices
# (FINISHED <- TRUE among them), runs it with Rscript from inside the study,
# and leaves the bag where the report reads it, under the job's own set in
# estimates/. The runner reads its rows through read_job_data() and records
# the selection in the bag, which the report prints. A real screen is a
# thousand replicates over a hundred or more candidates and runs for hours;
# these run in minutes at most, so every frequency below carries a
# Monte-Carlo error of several points, bh's most of all.
#
# bc and bh screen death, as family-00-survival.R redraws it: an early phase
# carried by age, creatinine and heart failure, and a constant phase carried
# by age, heart failure, ejection fraction and diabetes. This family adds the
# two outcomes the other screens need, each with known drivers so a reader can
# check the frequencies against the truth:
#   vent       prolonged ventilation: age, heart failure, LV ejection fraction;
#   icu_hours  hours in intensive care: age, heart failure, diabetes.
# Not los: family-rf.R draws its own los, and a later family's column silently
# replaces an earlier one's of the same name.

# ---- Outcomes ----------------------------------------------------------------
bootstrap_columns <- function(d) {
  n <- nrow(d)
  withr::with_seed(20260930, {
    d$vent <- stats::rbinom(n, 1L, stats::plogis(-1.6 + 0.05 * (d$age - 58) + 0.9 * d$hx_chf - 0.04 * (d$lvef - 55)))
    d$icu_hours <- round(pmax(4, 24 + 0.6 * (d$age - 58) + 14 * d$hx_chf + 10 * d$hx_dm + stats::rnorm(n, 0, 18)))
  })
  attr(d$vent, "label") <- "Prolonged ventilation"
  attr(d$icu_hours, "label") <- "Hours in intensive care"
  d
}

# ---- The runner --------------------------------------------------------------
# The candidate pools: the true drivers of each outcome among a few that drive
# nothing, so the frequencies separate. creat_pr is missing for 8% of the
# cohort; boot_select()'s fitters drop those rows per replicate.
bootstrap_pool <- c("age", "female", "bmi", "hx_chf", "hx_dm", "nyha_pr", "lvef", "plvmassi")
bootstrap_death_pool <- c("age", "hx_chf", "lvef", "hx_dm", "creat_pr", "female", "bmi", "plvmassi")

r_vector <- function(x) paste0("c(", paste0("\"", x, "\"", collapse = ", "), ")")

# The runner add_job() wrote beside a report.
bootstrap_runner <- function(job) sub("[.]qmd$", ".runner.R", job)

# Run a runner as its header says to: with Rscript, from inside the study.
# `env` adds environment variables to that one run. Stops with the runner's
# own last lines when it fails.
bootstrap_run <- function(runner, env = character()) {
  out <- withr::with_dir(dirname(runner), suppressWarnings(system2(
    file.path(R.home("bin"), "Rscript"), shQuote(basename(runner)), stdout = TRUE, stderr = TRUE, env = env
  )))
  status <- attr(out, "status")
  if (!is.null(status) && status != 0L) {
    stop(basename(runner), " failed:\n", paste(utils::tail(out, 15L), collapse = "\n"), call. = FALSE)
  }
  invisible(out)
}

# The runner's study choices common to bl, br and bc: finished, the cohort's
# identifier, the pool, and a small run.
bootstrap_runner_choices <- function(pool, n_rep, seed) {
  list(
    "^FINISHED <- FALSE$" = "FINISHED <- TRUE",
    "^POOL <- c\\(\"age\", \"female\"\\)$" = paste("POOL <-", r_vector(pool)),
    "^ID <- \"ccfid\"$" = "ID <- \"patient_id\"",
    "^N_REP <- 1000$" = sprintf("N_REP <- %d", n_rep),
    "^SEED <- 20260101$" = sprintf("SEED <- %d", seed)
  )
}

# A boot_select() screen, as the bl, br and bc runners make it: one run, one
# file, BOOT_FILE's default name.
bootstrap_select <- function(choices) {
  force(choices)
  function(root, job) {
    runner <- bootstrap_runner(job)
    set_choices(runner, choices)
    bootstrap_run(runner)
  }
}

# The choices a boot_select() report needs: the run's size, and a cluster
# naming terms the screen carries. A member no replicate selected is refused
# rather than reported as 0%, so each cluster names drivers.
bootstrap_choices <- function(n_rep, cluster) {
  list(
    "^EXPECT_BOOT <- " = sprintf("EXPECT_BOOT <- %dL   # Demo: boot_select(n_rep = %d)", n_rep, n_rep),
    "^  Age = c\\(\"age\", \"ln_age\"\\)$" = cluster
  )
}

# ---- The hazard runner -------------------------------------------------------
# hzr_bootstrap() is chunked, as a real hazard screen is: each chunk is an
# independent run of the runner with its own CHUNK and seed, written as
# bh.chunkNN.rds, and the report pools them. Chunks run side by side, which is
# the reason to chunk at all. Each replicate runs a stepwise screen over two
# phases and costs tens of seconds, so this run is four chunks of two, over a
# pool one noise variable smaller than bc's.
bh_chunks <- 4L
bh_per_chunk <- 2L
bh_pool <- setdiff(bootstrap_death_pool, "plvmassi")

# The runner screens the rows the hazard family analyses: complete cases on
# creatinine, since a candidate holding NA cannot be scored. Same-day deaths
# are already off t = 0 in the dataset (family-00-survival.R).
#
# The early shape is held fixed, as %hazboot does, at a half-life of about
# eleven days. It is written here rather than fitted: on this cohort a
# covariate-free fit of the early shape runs off to a degenerate phase
# (log t_half near 700, nu near 600) from any start, after which every
# replicate's refit fails and the screen selects nothing.
bh_runner_choices <- list(
  "^FINISHED <- FALSE$" = "FINISHED <- TRUE",
  "^POOL <- c\\(\"age\", \"female\"\\)$" = paste("POOL <-", r_vector(bh_pool)),
  "^WHERE <- NULL$" = "WHERE <- quote(!is.na(creat_pr))",
  "^ID <- \"ccfid\"$" = "ID <- \"patient_id\"",
  # One runner, run once per chunk: the chunk number comes from the run.
  "^CHUNK <- 1L$" = "CHUNK <- as.integer(Sys.getenv(\"GALLERY_CHUNK\"))",
  "^N_BOOT <- 20L$" = sprintf("N_BOOT <- %dL", bh_per_chunk),
  "^phases <- list\\(early = hzr_phase\\(\"cdf\", t_half = 0.05" =
    "phases <- list(early = hzr_phase(\"cdf\", t_half = 0.03, nu = 1, m = 1, fixed = \"shapes\"),",
  "^bs <- hzr_bootstrap\\(base, n_boot = N_BOOT, seed = SEED, scope = list\\(early = ~ age \\+ female" = paste0(
    "bs <- hzr_bootstrap(base, n_boot = N_BOOT, seed = SEED, scope = list(early = ~ ",
    paste(bh_pool, collapse = " + "), ", constant = ~ ", paste(bh_pool, collapse = " + "), "),"
  )
)

bootstrap_hazard <- function(root, job) {
  runner <- bootstrap_runner(job)
  set_choices(runner, bh_runner_choices)
  # mclapply() forks, which Windows cannot; run the chunks one after another there.
  cores <- if (.Platform$OS.type == "windows") 1L else bh_chunks
  runs <- parallel::mclapply(seq_len(bh_chunks), function(k) {
    tryCatch(bootstrap_run(runner, env = paste0("GALLERY_CHUNK=", k)), error = function(e) e)
  }, mc.cores = cores)
  failed <- vapply(runs, inherits, logical(1L), "error")
  if (any(failed)) stop(conditionMessage(runs[[which(failed)[[1L]]]]), call. = FALSE)
}

# ---- The jobs ----------------------------------------------------------------
gallery_family(
  "bootstrap",
  columns = bootstrap_columns,
  jobs = list(
    bl = list(
      subject = "vent", type = "boot",
      prepare = bootstrap_select(c(bootstrap_runner_choices(bootstrap_pool, 100L, 101L),
                                   list("^OUTCOME <- \"outcome\"$" = "OUTCOME <- \"vent\""))),
      choices = bootstrap_choices(100L, "  Heart = c(\"hx_chf\", \"lvef\")")
    ),
    br = list(
      subject = "icu", type = "boot",
      prepare = bootstrap_select(c(bootstrap_runner_choices(bootstrap_pool, 100L, 102L),
                                   list("^OUTCOME <- \"outcome\"$" = "OUTCOME <- \"icu_hours\""))),
      choices = bootstrap_choices(100L, "  History = c(\"hx_chf\", \"hx_dm\")")
    ),
    # A Cox model has no intercept, so the runner's BASE names a screened
    # term. Age is selected in every replicate, so its default "age" stands
    # in; its row leaves the frequency table, and the SD check watches it.
    # TIME and EVENT default to iv_dead and dead already.
    bc = list(
      subject = "dead", type = "boot",
      prepare = bootstrap_select(bootstrap_runner_choices(bootstrap_death_pool, 100L, 103L)),
      choices = bootstrap_choices(100L, "  Heart = c(\"hx_chf\", \"lvef\")")
    ),
    bh = list(
      subject = "dead", type = "boot",
      prepare = bootstrap_hazard,
      choices = list(
        "^EXPECT_CHUNKS <- " = sprintf("EXPECT_CHUNKS <- %dL    # Demo: four chunks, side by side", bh_chunks),
        "^EXPECT_BOOT   <- " = sprintf("EXPECT_BOOT   <- %dL    # Demo: two replicates each", bh_chunks * bh_per_chunk),
        "^  early[.]Age  = " = "  early.Age      = \"early.age\",",
        "^  const[.]Age  = " = "  constant.Heart = c(\"constant.hx_chf\", \"constant.lvef\")"
      )
    )
  )
)
