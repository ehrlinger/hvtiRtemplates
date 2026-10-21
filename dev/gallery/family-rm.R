# Regression-model family: the two rm templates, ordinary least squares on one
# row per patient. rm-linear models length of stay on the log scale, the usual
# choice for a skewed outcome; los is family-rf.R's, so this model and rfr-fit
# read the same outcome. rm-balancing_continuous takes bypass time as the
# continuous exposure and stratifies patients on its balancing score. Bypass
# time is this family's one column, simulated from the demo covariates, so the
# balancing model has something to find.

rm_choices <- function(...) {
  c(list(
    "^DATASET <- " = "DATASET <- \"built\"",
    "^ID <- " = "ID <- \"patient_id\""
  ), list(...))
}

gallery_family(
  "rm",
  columns = function(d) {
    withr::with_seed(20261020, {
      cpb <- 95 + 0.6 * (d$age - 60) + 1.2 * (d$bmi - 27) + 12 * d$hx_chf - 0.4 * (d$lvef - 55) +
        8 * d$hx_dm + stats::rnorm(nrow(d), 0, 22)
    })
    d$cpb_time <- round(pmax(35, cpb))
    attr(d$cpb_time, "label") <- "Cardiopulmonary bypass time (minutes)"
    d
  },
  jobs = list(
    "rm-linear" = list(subject = "los", type = "model", choices = rm_choices(
      "^OUTCOME <- " = "OUTCOME <- \"los\"",
      "^RESPONSE_SCALE <- \"identity\"$" = "RESPONSE_SCALE <- \"log\"",
      "^PREDICTORS <- " = "PREDICTORS <- c(\"age\", \"female\", \"nyha_pr\", \"hx_chf\", \"hx_dm\", \"lvef\")"
    )),
    "rm-balancing_continuous" = list(subject = "cpbtime", type = "balancing", choices = rm_choices(
      "^OUTCOME <- " = "OUTCOME <- \"cpb_time\"",
      "^PREDICTORS <- " = "PREDICTORS <- c(\"age\", \"female\", \"bmi\", \"hx_chf\", \"hx_dm\", \"lvef\")",
      "^N_STRATA <- " = "N_STRATA <- 5L"
    ))
  )
)
