# Hazard family: the parametric survival chain, ac -> hz -> hm -> hp -> hs,
# all in one set (subject "dead", type "hz") because each job reads the saved
# output of the ones before it: hz.rds by hm, ac.rds and hz.rds by hp, hm.rds
# by hs.
#
# The outcome is the gallery's own dead / iv_dead (family-00-survival.R): an
# early phase in the first months and a constant late phase. The template's
# late phase is a Weibull (tau, gamma, alpha held at 1), so a constant late
# hazard shows up as an estimated eta near 1 rather than being imposed.
#
# The only columns added are the two hs's population matching reads, in the
# 0/1 coding the SAS macro used: the cohort carries `female` and `race_grp`.

hazard_columns <- function(d) {
  d$male <- 1L - d$female
  d$nonwhite <- as.integer(d$race_grp != "White")
  attr(d$male, "label") <- "Male"
  attr(d$nonwhite, "label") <- "Non-white race"
  d
}

# ac and hz analyse the whole cohort and share one reconciled count.
# In a real job these come from the SAS reference; here they are the counts
# family-00-survival.R's outcome produces.
hazard_counts <- list(
  "^EXPECTED <- list\\(n = NA_integer_" = "EXPECTED <- list(n = 800L, n_events = 443L, n_censored = 357L)"
)
# Six patients die on the day of operation, and iv_dead, rounded to 0.001
# years, records them at 0. The hazard likelihood is not defined at t = 0,
# and hz stops with "Multiphase optimization produced no usable fit from 1
# start: ... 1 ended where the likelihood is not defined". Flooring every
# time at one day is no better: it piles a dozen deaths on one tied time and
# the early phase collapses onto it (nu -> 0, a different optimum from each
# start). So only the zeros move, to 0.00025 years, the middle of the interval
# that rounds to 0. Every job that reads the cohort applies the same line, in
# its filter slot, so all five describe one cohort.
hazard_zero <- list(
  "^# d <- d\\[!is.na\\(d\\$<flag>\\) & d\\$<flag> == 1, , drop = FALSE\\]$" = paste(
    "# Same-day deaths are recorded at 0; the likelihood needs t > 0.",
    "d$iv_dead[d$iv_dead == 0] <- 0.00025", sep = "\n"
  )
)
# hm and hs (which must predict for the rows hm fitted) analyse complete
# cases on creatinine. Its 8% missing values reach hazard() as NA, and the
# fit stops with "Predictor rows must match the length of 'time'", naming
# neither the column nor the missingness; covariate_audit() just before it
# reports creat_pr as "left as numeric". A SAS job would have mean-imputed it
# in vars.sas; dropping the rows is the smaller step here.
hazard_model_rows <- list(
  "^# d <- d\\[!is.na\\(d\\$<flag>\\) & d\\$<flag> == 1, , drop = FALSE\\]$" = paste(
    hazard_zero[[1L]],
    "# Complete cases on creatinine, a candidate in the early phase.",
    "d <- d[!is.na(d$creat_pr), , drop = FALSE]", sep = "\n"
  ),
  "^EXPECTED <- list\\(n = NA_integer_" = "EXPECTED <- list(n = 725L, n_events = 402L, n_censored = 323L)"
)
# hm, hp and hs default to the SAS names iu_dead / idead; ac and hz already
# default to this cohort's iv_dead / dead.
hazard_tte <- list(
  "^TIME +<- \"iu_dead\"$" = "TIME <- \"iv_dead\"",
  "^EVENT +<- \"idead\"$" = "EVENT <- \"dead\""
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

gallery_family(
  "hazard",
  columns = hazard_columns,
  jobs = list(
    ac = list(subject = "dead", type = "hz", choices = c(hazard_counts, hazard_zero, list(
      "^DERIVED <- c\\(cat_a = \"src_a\"\\)$" = "DERIVED <- c(lvef_grp = \"lvef\")",
      "^STRATA <- c\\(\"cat_a\"\\)$" = "STRATA <- c(\"lvef_grp\", \"hx_chf\")",
      "^  \\.need <- \"src_a\"" = "  .need <- \"lvef\"",
      "^  d\\$cat_a <- 4L$" = "  d$lvef_grp <- 3L",
      "^  d\\$cat_a\\[!is.na\\(d\\$src_a\\) & d\\$src_a <  0.00\\] <- 3L$" =
        "  d$lvef_grp[!is.na(d$lvef) & d$lvef < 50] <- 2L",
      "^  d\\$cat_a\\[!is.na\\(d\\$src_a\\) & d\\$src_a < -0.60\\] <- 2L$" =
        "  d$lvef_grp[!is.na(d$lvef) & d$lvef < 40] <- 1L",
      "^  d\\$cat_a\\[!is.na\\(d\\$src_a\\) & d\\$src_a < -1.25\\] <- 1L$" = "",
      "^knitr::kable\\(as.data.frame\\(table\\(cat_a = d\\$cat_a\\)" =
        "knitr::kable(as.data.frame(table(lvef_grp = d$lvef_grp), stringsAsFactors = FALSE))"
    ))),
    hz = list(subject = "dead", type = "hz", choices = c(hazard_counts, hazard_zero, list(
      "^  early = hzr_phase\\(\"cdf\", t_half = 1" = "  early = hzr_phase(\"cdf\", t_half = 0.04, nu = 1, m = 1),",
      "^theta0 <- c\\(log\\(1\\), log\\(1\\), 1, 1,$" = "theta0 <- c(log(0.05), log(0.04), 1, 1,",
      "^            log\\(1\\), log\\(1\\), 1, 1, 1\\)$" = "            log(0.035), log(1), 1, 1, 1)",
      # The template's probes shift every position of theta0, the three the
      # late phase holds fixed (tau, gamma, alpha) included, so a probe fits a
      # different model and can "beat" the reported fit by changing it.
      # Perturb the free positions only.
      "^probes <- rbind\\(theta0, theta0 \\+ 0.5, theta0 - 0.5\\)$" = paste(
        ".free  <- !theta_names %in% c(\"late.log_tau\", \"late.gamma\", \"late.alpha\")",
        "probes <- rbind(theta0, theta0 + 0.5 * .free, theta0 - 0.5 * .free)", sep = "\n"
      ),
      # GALLERY WORKAROUND for a template defect, not a study choice. The
      # convergence table reads fit_det$fit$iterations, which a multiphase
      # fit does not carry (TemporalHazard 1.2.11): it is NULL, the table's
      # value column comes up one short, and the render stops with
      # "arguments imply differing number of rows: 5, 4". The fit reports
      # its optimizer counts in fit$counts instead.
      "^  quantity = c\\(\"log-likelihood\", \"converged\", \"iterations\"" =
        "  quantity = c(\"log-likelihood\", \"converged\", \"function evaluations\", \"rcond\", \"pd\"),",
      "^               fit_det\\$fit\\$converged, fit_det\\$fit\\$iterations,$" =
        "               fit_det$fit$converged, fit_det$fit$counts[[\"function\"]],"
    ))),
    hm = list(
      subject = "dead", type = "hz",
      prepare = function(root, job) {
        writeLines(hazard_sas, file.path(study_dir("analyses", root), "hm.dead.sas"))
      },
      # SAS_JOB already names analyses/hm.dead.sas, which prepare() writes.
      choices = c(hazard_tte, hazard_model_rows)
    ),
    hp = list(subject = "dead", type = "hz", choices = c(hazard_tte, list(
      "^t_max <- 3 " = "t_max <- 10"
    ))),
    hs = list(subject = "dead", type = "hz", choices = c(hazard_tte, hazard_model_rows, list(
      "^OTHER_COL +<- \"other\"$" = "OTHER_COL <- \"nonwhite\"",
      "^VINTAGE +<- NULL$" = "VINTAGE   <- \"table2023\""
    )))
  )
)
