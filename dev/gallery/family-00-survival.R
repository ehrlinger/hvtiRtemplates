# Survival outcome for the gallery. The demo cohort's death times carry almost
# no covariate signal (a Cox model on its covariates reaches C = 0.52), which
# is fine for descriptive checks and empty for every survival template. This
# redraws dead / iv_dead, and reop / iv_reop with them, for the gallery only;
# dev/demo keeps its own cohort and reference numbers.
#
# Two phases, the shape the hazard templates look for: an early phase in the
# first months after operation, carried by age, creatinine and heart failure,
# and a constant late phase carried by age, heart failure, ejection fraction
# and diabetes. Follow-up is censored at the close date, with one patient in
# ten lost early, as in the demo.
#
# The file name sorts first, so every other family sees these columns.

gallery_family(
  "survival",
  jobs = list(),
  columns = function(d) {
    withr::with_seed(20261001, {
      n <- nrow(d)
      creat <- ifelse(is.na(d$creat_pr), stats::median(d$creat_pr, na.rm = TRUE), d$creat_pr)
      early_lp <- -3.6 + 0.05 * (d$age - 60) + 0.9 * (creat - 1) + 0.7 * d$hx_chf
      early <- stats::runif(n) < stats::plogis(early_lp)
      t_early <- stats::rweibull(n, shape = 0.6, scale = 0.08)
      late_rate <- 0.035 * exp(0.045 * (d$age - 60) + 0.6 * d$hx_chf - 0.025 * (d$lvef - 55) + 0.4 * d$hx_dm)
      t_late <- stats::rexp(n, late_rate)
      t_death <- ifelse(early, t_early, t_late)
      potential <- as.numeric(as.Date("2025-12-31") - d$op_date) / 365.25
      lost <- stats::runif(n) < 0.10
      t_censor <- ifelse(lost, stats::runif(n, 0, potential), potential)
      d$dead <- as.integer(t_death <= t_censor)
      d$iv_dead <- round(pmin(t_death, t_censor), 3)
      t_reop <- stats::rexp(n, 1 / 30)
      d$reop <- as.integer(t_reop < d$iv_dead)
      d$iv_reop <- round(pmin(t_reop, d$iv_dead), 3)
    })
    labels <- c(dead = "Death", iv_dead = "Follow-up to death or censoring (years)",
                reop = "Reoperation", iv_reop = "Follow-up to reoperation (years)")
    for (v in names(labels)) attr(d[[v]], "label") <- labels[[v]]
    d
  }
)
