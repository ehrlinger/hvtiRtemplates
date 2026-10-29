# Hazard family: the parametric survival chain, ac -> hz -> hm -> hp ->
# hs-setup, all in one set (subject "dead", type "hz") because each job reads
# the saved output of the ones before it: hz.rds by hm, ac.rds and hz.rds by
# hp, hm.rds by hs-setup. hs-concordance follows, in a set of its own, reading
# one hm model per treatment group (see its prepare() below).
#
# The outcome is the gallery's own dead / iv_dead (family-00-survival.R): an
# early phase in the first months and a constant late phase. The template's
# late phase is a Weibull (tau, gamma, alpha held at 1), so a constant late
# hazard shows up as an estimated eta near 1 rather than being imposed.
#
# The only columns added are the two hs-setup's population matching reads, in the
# 0/1 coding the SAS macro used: the cohort carries `female` and `race_grp`.

hazard_columns <- function(d) {
  d$male <- 1L - d$female
  d$nonwhite <- as.integer(d$race_grp != "White")
  attr(d$male, "label") <- "Male"
  attr(d$nonwhite, "label") <- "Non-white race"
  d
}

# The rows every job in the chain analyses: complete cases on creatinine, a
# candidate in hm's early phase. Its 8% missing values reach hazard() as NA,
# and the fit stops with "Predictor rows must match the length of 'time'",
# naming neither the column nor the missingness. A SAS job would have
# mean-imputed it in vars.sas; dropping the rows is the smaller step here.
#
# The rule is a WHERE on ac and hz, the jobs that read the dataset. hm, hp and
# hs-setup rebuild hz's rows from the selection hz.rds records, and stop if
# their own settings differ, so they set none of it. Same-day deaths, which
# the likelihood cannot take at t = 0, are moved in the dataset itself
# (family-00-survival.R), since a WHERE selects rows and changes no value.
hazard_where <- "!is.na(creat_pr)"
hazard_rows <- list(
  "^ID <- \"ccfid\"$" = "ID <- \"patient_id\"",
  "^WHERE <- NULL$" = paste0("WHERE <- quote(", hazard_where, ")")
)
# The counts that selection holds. In a real job these come from the SAS
# reference; here they are the counts family-00-survival.R's outcome produces.
hazard_counts <- list(
  "^EXPECTED <- (NULL$|list\\(n = NA_integer_)" = "EXPECTED <- list(n = 725L, n_events = 406L, n_censored = 319L)"
)
# hz's starting values, shared by the chain's hz and by each treatment group's
# hz that hs-concordance reads. The probes need no override: since #169 the
# template perturbs only the free positions, read from each phase's fixed set.
hazard_hz_choices <- list(
  "^  early = hzr_phase\\(\"cdf\", t_half = 1" = "  early = hzr_phase(\"cdf\", t_half = 0.04, nu = 1, m = 1),",
  "^theta0 <- c\\(log\\(1\\), log\\(1\\), 1, 1,$" = "theta0 <- c(log(0.05), log(0.04), 1, 1,",
  "^            log\\(1\\), log\\(1\\), 1, 1, 1\\)$" = "            log(0.035), log(1), 1, 1, 1)"
)

# The companion SAS job hm reads its candidate covariates from. A real
# analyst has it already; here a small synthetic one is written.
hazard_sas <- c(
  "/* hm.dead.sas -- synthetic companion job for the template gallery. */",
  "%macro model;",
  "proc hazard data=built conserve;",
  "  time iv_dead; event dead;",
  "  early",
  "    age, creat_pr, hx_chf",
  "  ;",
  "  late",
  "    age, hx_chf, lvef, hx_dm",
  "  ;",
  "run;",
  "%mend;",
  "%model;"
)

hazard_write_sas <- function(root) {
  writeLines(hazard_sas, file.path(study_dir("analyses", root), "hm.dead.sas"))
}

# ---- hs-score ----------------------------------------------------------------
# hs-score scores start/stop segments, so it needs an hz and an hm fitted on
# them, in a set of their own (subject "dead_segments"). The segments are the
# cohort's own follow-up cut at 1 and 5 years, the event on the last segment,
# with creatinine re-measured at each cut: a time-varying covariate, which is
# what the layout exists for. Registered as a second dataset, "segments". The
# same WHERE keeps the same 725 patients, and the chain's starting values serve,
# since cutting follow-up leaves a fixed covariate's likelihood unchanged.
hazard_segment_cuts <- c(1, 5)

hazard_segments <- function(built) {
  d <- built[c("patient_id", "dead", "iv_dead", "age", "creat_pr", "hx_chf", "lvef", "hx_dm")]
  withr::with_seed(20261029, {
    rows <- lapply(seq_len(nrow(d)), function(i) {
      p <- d[i, ]
      cuts <- hazard_segment_cuts[hazard_segment_cuts < p$iv_dead]
      k <- length(cuts) + 1L
      seg <- p[rep(1L, k), ]
      seg$iv_start <- c(0, cuts)
      seg$iv_dead <- c(cuts, p$iv_dead)
      seg$dead <- c(rep(0L, k - 1L), p$dead)
      seg$creat_pr <- round(p$creat_pr * exp(cumsum(c(0, stats::rnorm(k - 1L, 0.05, 0.1)))), 2)
      seg
    })
  })
  s <- do.call(rbind, rows)
  rownames(s) <- NULL
  s <- s[c("patient_id", "iv_start", setdiff(names(s), c("patient_id", "iv_start")))]
  attr(s$iv_start, "label") <- "Segment start (years)"
  attr(s$iv_dead, "label") <- "Segment stop (years)"
  attr(s$creat_pr, "label") <- "Creatinine at the segment's start (mg/dL)"
  s
}

hazard_register_segments <- function(root, job) {
  dir <- study_dir("datasets", root)
  if (file.exists(file.path(dir, "segments.rds"))) return(invisible())
  saveRDS(hazard_segments(readRDS(file.path(dir, "built.rds"))), file.path(dir, "segments.rds"))
  invisible(utils::capture.output(suppressMessages(register_data(
    root, built = "segments.rds", dataset = "segments", role = "named",
    population = "Synthetic start/stop segments of the cohort's follow-up, cut at 1 and 5 years"
  ))))
}

# ---- hs-concordance ----------------------------------------------------------
# hs-concordance predicts every patient through every treatment group's hm
# model, each fitted by its own hz and hm jobs on that group's patients, in
# that group's own set. The groups are the lm family's `approach`, surgical or
# transcatheter replacement. Its prepare() is those upstream jobs: an hz and
# an hm per group, scaffolded, set and rendered like any gallery job, so the
# concordance report reads real models. The group sets are dead-surgical and
# dead-transcatheter; the comparison set is dead-approach.
concordance_groups <- c("surgical", "transcatheter")

# A group's hz holds the early phase's nu fixed, as a SAS job does with
# fixnu, at the whole-cohort hz's estimate. Free, it cannot be estimated in the
# transcatheter group: four of its 265 deaths fall on the day of operation,
# and from every start tried the early phase collapses onto them (nu -> 0,
# t_half at its bound), which hz's check_fit() refuses as a positive
# objective. The other starting values are the whole-cohort estimates too.
# The template's probes already leave the fixed nu where it is.
concordance_hz_choices <- list(
  "^  early = hzr_phase\\(\"cdf\", t_half = 1" =
    "  early = hzr_phase(\"cdf\", t_half = 0.0017, nu = 1.85, m = -0.11, fixed = \"nu\"),",
  "^theta0 <- c\\(log\\(1\\), log\\(1\\), 1, 1,$" = "theta0 <- c(-3.85, -6.40, 1.85, -0.11,",
  "^            log\\(1\\), log\\(1\\), 1, 1, 1\\)$" = "            -2.47, log(1), 1, 1, 0.83)"
)

# A group's hm reads a smaller companion SAS job than the chain's hm: age in
# the early phase; age, heart failure and ejection fraction late. With this
# job every group model fits and hs-concordance renders. It is a study
# choice, made because the chain's five candidates do NOT work here: the
# surgical group's early phase, 13 deaths, runs off (early.log_mu near -850)
# and the fit carries no variance matrix. hm renders that fit without
# complaint (#228), and hs-concordance then stops in its decision chunk with
# an unhelpful message (#227). Both defects are filed against the templates;
# this configuration avoids the degenerate fit rather than hiding either.
concordance_sas <- c(
  "/* hm.dead_group.sas -- synthetic companion job for the template gallery. */",
  "%macro model;",
  "proc hazard data=built conserve;",
  "  time iv_dead; event dead;",
  "  early",
  "    age",
  "  ;",
  "  late",
  "    age, hx_chf, lvef",
  "  ;",
  "run;",
  "%mend;",
  "%model;"
)

# A group's counts, as a SAS reference for that group's rows would give them.
concordance_counts <- function(root, group) {
  d <- readRDS(file.path(study_dir("datasets", root), "built.rds"))
  d <- d[!is.na(d$creat_pr) & d$approach == group, , drop = FALSE]
  sprintf("EXPECTED <- list(n = %dL, n_events = %dL, n_censored = %dL)",
          nrow(d), sum(d$dead == 1L), sum(d$dead == 0L))
}

concordance_upstream <- function(root, job) {
  writeLines(concordance_sas, file.path(study_dir("analyses", root), "hm.dead_group.sas"))
  for (g in concordance_groups) {
    rows <- list(
      "^ID <- \"ccfid\"$" = "ID <- \"patient_id\"",
      "^WHERE <- NULL$" = sprintf("WHERE <- quote(%s & approach == \"%s\")", hazard_where, g),
      "^EXPECTED <- list\\(n = NA_integer_" = concordance_counts(root, g)
    )
    hz <- set_choices(add_job("hz", "dead", g, dir = root), c(rows, concordance_hz_choices))
    # hm takes its counts from this group's hz.rds, so only the SAS job is set.
    hm <- set_choices(add_job("hm", "dead", g, dir = root), list(
      "^SAS_JOB   <- c\\(\"analyses\", \"hm.dead.sas\"\\)$" = "SAS_JOB   <- c(\"analyses\", \"hm.dead_group.sas\")"
    ))
    for (upstream in c(hz, hm)) {
      tryCatch(render_job(upstream, final = TRUE, quiet = TRUE), error = function(e) {
        stop("hs-concordance's upstream ", basename(upstream), " did not render: ", conditionMessage(e), call. = FALSE)
      })
    }
  }
}

gallery_family(
  "hazard",
  columns = hazard_columns,
  jobs = list(
    ac = list(subject = "dead", type = "hz", choices = c(hazard_rows, hazard_counts, list(
      "^STRATA <- NULL$" = "STRATA <- c(\"lvef_grp\", \"hx_chf\")",
      "^#   d\\$lvef_grp <- 3L$" = "d$lvef_grp <- 3L",
      "^#   d\\$lvef_grp\\[which\\(d\\$lvef < 50\\)\\] <- 2L$" = "d$lvef_grp[which(d$lvef < 50)] <- 2L",
      "^#   d\\$lvef_grp\\[which\\(d\\$lvef < 40\\)\\] <- 1L$" = "d$lvef_grp[which(d$lvef < 40)] <- 1L",
      "^#   d\\$lvef_grp\\[is.na\\(d\\$lvef\\)\\] <- NA$" = "d$lvef_grp[is.na(d$lvef)] <- NA",
      "^DERIVED <- NULL$" = "DERIVED <- c(lvef_grp = \"lvef\")"
    ))),
    hz = list(subject = "dead", type = "hz", choices = c(hazard_rows, hazard_counts, hazard_hz_choices)),
    # hm, hp and hs-setup take the data, rows, ID, time and event from hz.rds.
    # Their counts too: hz.rds carries hz's EXPECTED, so they set none (#177).
    hm = list(
      subject = "dead", type = "hz",
      prepare = function(root, job) hazard_write_sas(root),
      # SAS_JOB already names analyses/hm.dead.sas, which prepare() writes.
      choices = list()
    ),
    hp = list(subject = "dead", type = "hz", choices = list(
      "^t_max <- 3 " = "t_max <- 10"
    )),
    "hs-setup" = list(subject = "dead", type = "hz", choices = list(
      "^OTHER_COL +<- \"other\"$" = "OTHER_COL <- \"nonwhite\"",
      "^VINTAGE +<- NULL$" = "VINTAGE   <- \"table2023\""
    )),
    "hs-concordance" = list(
      subject = "dead", type = "approach",
      prepare = concordance_upstream,
      choices = c(hazard_rows, hazard_counts, list(
        "^MODELS <- NULL$" = "MODELS <- c(surgical = \"dead-surgical\", transcatheter = \"dead-transcatheter\")",
        "^GROUP <- NULL$" = "GROUP <- \"approach\"",
        "^HORIZON <- 10$" = "HORIZON <- 5",
        "^CARRY <- character\\(\\)$" = "CARRY <- c(\"age\")",
        "^OVERLAP <- NULL$" = "OVERLAP <- \"none\""
      ))
    ),
    "hz-segments" = list(
      template = "hz", subject = "dead_segments", type = "hz", prepare = hazard_register_segments,
      choices = c(hazard_rows, hazard_hz_choices, list(
        "^DATASET <- \"built\"$" = "DATASET <- \"segments\"",
        "^KEY <- ID$" = "KEY <- c(ID, \"iv_start\")",
        "^START  <- NULL$" = "START  <- \"iv_start\"",
        # Segments, as SAS counts observations: the chain's 406 events, one per patient who died.
        "^EXPECTED <- (NULL$|list\\(n = NA_integer_)" = "EXPECTED <- list(n = 1823L, n_events = 406L, n_censored = 1417L)"
      ))
    ),
    "hm-segments" = list(
      template = "hm", subject = "dead_segments", type = "hz",
      prepare = function(root, job) hazard_write_sas(root),
      choices = list()
    ),
    "hs-score" = list(subject = "dead_segments", type = "hz", choices = list(
      "^CARRY <- character\\(\\)$" = "CARRY <- \"creat_pr\""
    ))
  )
)
