# Bootstrap variable selection family: bl (logistic), br (linear), bc (Cox)
# and bh (multiphase hazard). These templates REPORT on a screen; they do not
# run one. Each job's prepare() is therefore the companion runner a study
# author writes by hand: it reads the registered dataset, runs the screen
# small, and saves the bag where the report reads it, under the job's own set
# in estimates/. A real screen is a thousand replicates over a hundred or more
# candidates and runs for hours; these run in minutes at most, so every frequency
# below carries a Monte-Carlo error of several points, bh's most of all.
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

# What a runner starts from: the registered dataset, and the provenance record
# of the exact file it screened, taken before the screen.
bootstrap_input <- function(root) {
  cfg <- hvtiRutilities::study_config(start = root)
  list(data = hvtiRutilities::read_built(cfg = cfg),
       record = hvtiRutilities::provenance_data(cfg = cfg, role = "bootstrap-training"))
}

# The set directory a report reads from, taken from the job's own file name,
# <subject>-<type>-<prefix>.qmd, as the report's set_path() takes it.
bootstrap_set_dir <- function(root, job) {
  fields <- strsplit(basename(job), "-", fixed = TRUE)[[1L]]
  d <- file.path(hvtiRutilities::study_dir("estimates", root), paste(fields[1:2], collapse = "-"))
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

# The reports refuse a bag that carries no data lineage, and neither boot_bag()
# nor hzr_bootstrap() attaches one, so the runner does. The shape is the one
# the reports read: data, artifacts, analysis and cohort, in that order.
bootstrap_lineage <- function(bag, record) {
  attr(bag, "hvti_provenance") <- list(data = list(record), artifacts = list(), analysis = NULL, cohort = NULL)
  bag
}

# A boot_select() screen, as the bl, br and bc runners write it: one run, one
# file, BOOT_FILE's default name.
bootstrap_select <- function(response, pool, fitter, base_params, n_rep, seed) {
  force(response)
  force(pool)
  function(root, job) {
    input <- bootstrap_input(root)
    formula <- stats::as.formula(paste(response, "~", paste(pool, collapse = " + ")))
    screen <- hvtiRbootstrap::boot_select(input$data, formula, fitter, n_rep = n_rep,
                                          sle = 0.10, sls = 0.05, seed = seed)
    bag <- hvtiRbootstrap::boot_bag(screen, base_params = base_params, requested = length(pool),
                                    manifest = list(sha256 = input$record$sha256))
    saveRDS(bootstrap_lineage(bag, input$record), file.path(bootstrap_set_dir(root, job), "bagging.rds"))
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
# independent run with its own seed, written as bh.chunkNN.rds, and the report
# pools them. Chunks run side by side, which is the reason to chunk at all.
# Each replicate runs a stepwise screen over two phases and costs tens of
# seconds, so this run is four chunks of two, over a pool one noise variable
# smaller than bc's.
bh_chunks <- 4L
bh_per_chunk <- 2L

bootstrap_hazard <- function(root, job) {
  input <- bootstrap_input(root)
  d <- input$data
  # Two things hazard() will not take that a Cox fit does. A follow-up of zero
  # has no likelihood (six deaths round to 0.000 years), and a candidate
  # holding NA cannot be scored, so creat_pr would never be tested. Floor
  # follow-up at one day and impute creatinine at its median, in the runner's
  # copy only. This differs from the hazard family, which moves only the zeros
  # to 0.00025 years: here the shape-fixing fit has no covariates, and with
  # six deaths at 0.00025 it runs off to a degenerate early phase (log t_half
  # near 600, nu near 500) from the default and from hz's starting values,
  # after which every replicate's refit fails and the screen selects nothing.
  # The one-day floor gives an early half-life near ten days. Same-day deaths
  # need a named rule in the templates themselves (hvtiRtemplates#175).
  d$iv_dead <- pmax(d$iv_dead, 1 / 365.25)
  d$creat_pr[is.na(d$creat_pr)] <- stats::median(d$creat_pr, na.rm = TRUE)

  # Shapes from a fit with no covariates, then held fixed, as %hazboot does.
  phases <- function(early) list(early = early, constant = TemporalHazard::hzr_phase("constant"))
  free <- TemporalHazard::hazard(survival::Surv(iv_dead, dead) ~ 1, data = d, dist = "multiphase",
                                 phases = phases(TemporalHazard::hzr_phase("cdf", t_half = 0.05, nu = 1, m = 1)),
                                 fit = TRUE)
  cf <- stats::coef(free)
  early <- TemporalHazard::hzr_phase("cdf", t_half = exp(cf[["early.log_t_half"]]), nu = cf[["early.nu"]],
                                     m = cf[["early.m"]], fixed = "shapes")
  base <- TemporalHazard::hazard(survival::Surv(iv_dead, dead) ~ 1, data = d, dist = "multiphase",
                                 phases = phases(early), fit = TRUE)

  pool <- setdiff(bootstrap_death_pool, "plvmassi")
  scope <- stats::as.formula(paste("~", paste(pool, collapse = " + ")))
  offered <- c(early = length(pool), constant = length(pool))
  dir <- bootstrap_set_dir(root, job)
  run_chunk <- function(k) {
    seed <- 20261000L + k
    t0 <- Sys.time()
    bs <- suppressWarnings(TemporalHazard::hzr_bootstrap(
      base, n_boot = bh_per_chunk, seed = seed, scope = list(early = scope, constant = scope),
      slentry = 0.10, slstay = 0.05, max_steps = 50L
    ))
    chunk <- list(
      n_boot = bs$n_success, seed = seed, slentry = 0.10, slstay = 0.05, max_steps = 50L,
      # The first base parameter must be free: boot_health() watches its SD.
      base_params = c("early.log_mu", "constant.log_mu", "early.log_t_half", "early.nu", "early.m"),
      requested = offered, usable = offered, n_rows = nrow(d),
      elapsed_mins = as.numeric(difftime(Sys.time(), t0, units = "mins")),
      manifest = list(sha256 = input$record$sha256),
      th_version = format(utils::packageVersion("TemporalHazard")),
      boot = bs[c("replicates", "summary", "n_success", "n_failed")]
    )
    saveRDS(bootstrap_lineage(chunk, input$record), file.path(dir, sprintf("bh.chunk%02d.rds", k)))
  }
  # mclapply() forks, which Windows cannot; run the chunks one after another there.
  cores <- if (.Platform$OS.type == "windows") 1L else bh_chunks
  invisible(parallel::mclapply(seq_len(bh_chunks), run_chunk, mc.cores = cores))
}

# ---- The jobs ----------------------------------------------------------------
gallery_family(
  "bootstrap",
  columns = bootstrap_columns,
  jobs = list(
    bl = list(
      subject = "vent", type = "boot",
      prepare = bootstrap_select("vent", bootstrap_pool, hvtiRbootstrap::fit_logistic, "(Intercept)", 100L, 101L),
      choices = bootstrap_choices(100L, "  Heart = c(\"hx_chf\", \"lvef\")")
    ),
    br = list(
      subject = "icu", type = "boot",
      prepare = bootstrap_select("icu_hours", bootstrap_pool, hvtiRbootstrap::fit_linear, "(Intercept)", 100L, 102L),
      choices = bootstrap_choices(100L, "  History = c(\"hx_chf\", \"hx_dm\")")
    ),
    # A Cox model has no intercept and fit_cox() cannot force a term, but
    # boot_bag() requires a base model that names a screened term. Age is
    # selected in every replicate, so it stands in; its row leaves the
    # frequency table, and the SD check watches it.
    bc = list(
      subject = "dead", type = "boot",
      prepare = bootstrap_select("survival::Surv(iv_dead, dead)", bootstrap_death_pool, hvtiRbootstrap::fit_cox,
                                 "age", 100L, 103L),
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
