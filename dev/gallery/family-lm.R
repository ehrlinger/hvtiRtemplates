# Logistic-model family: the eight lm templates, each in its own set so every
# report reads as one job. lm-checkpred validates the bundle lm-binary saves,
# so the two share the stroke-model set and lm-binary renders first. The
# outcomes, treatments and the count exposure are simulated from the demo
# covariates, so every model has something to find. lp-mirror draws the
# lm-propensity_binary bundle, once in its approach-propensity set and once,
# as lp-mirror-matched, from a set of its own with a simulated match flag.

# lm-binary fits on operations before 2015 and lm-checkpred validates on 2015
# onward: one registered dataset, split by each job's WHERE on the year of
# dt_surg, the operation date, as a study's own data carry it.
lm_era <- function(where) list("^WHERE <- NULL$" = paste0("WHERE <- quote(", where, ")"))
lm_patient <- list("^ID <- " = "ID <- \"patient_id\"")
# Anchored on NULL: the templates' second IMPUTATION line takes the column
# read_job_data() matched, and must stay as it is.
lm_id <- c(lm_patient, list("^IMPUTATION <- NULL" = "IMPUTATION <- NULL"))
lm_covariates <- "c(\"age\", \"female\", \"hx_chf\", \"hx_dm\", \"lvef\", \"bmi\")"

gallery_family(
  "lm",
  columns = function(d) {
    withr::with_seed(20261003, {
      n <- nrow(d)
      a <- (d$age - 60) / 10
      ef <- (d$lvef - 55) / 10
      # Categories from a latent linear predictor, one draw per patient.
      pick <- function(eta) {
        p <- exp(cbind(0, eta))
        p <- p / rowSums(p)
        apply(p, 1L, function(pr) sample.int(ncol(p), 1L, prob = pr))
      }
      stroke <- stats::rbinom(n, 1L, stats::plogis(-2.8 + 0.5 * a + 0.7 * d$hx_dm + 0.5 * d$hx_chf))
      latent <- 0.6 * a - 0.5 * ef + 0.4 * d$hx_chf + stats::rlogis(n)
      mr <- cut(latent, c(-Inf, 0.5, 1.8, 3, Inf), labels = FALSE)
      dest <- pick(cbind(-1.2 + 0.8 * a + 0.4 * d$female, -2.6 + 1.2 * a + 0.6 * d$hx_chf))
      tavr <- stats::rbinom(n, 1L, stats::plogis(-1.2 + 0.9 * a + 0.6 * d$hx_chf - 0.3 * ef))
      size <- cut(-1.4 * d$female + 0.12 * (d$bmi - 27) + stats::rlogis(n), c(-Inf, -1.2, 0.8, Inf), labels = FALSE)
      valve <- pick(cbind(-0.5 + 1.1 * a, -2.4 - 0.4 * a))
      prior <- stats::rpois(n, exp(-1.2 + 0.25 * a + 0.5 * d$hx_chf))
      # A pair-match flag, as a SAS match would leave it: most transcatheter
      # patients find a surgical partner, and fewer surgical ones are used.
      # Drawn last, so no draw above moves.
      paired <- stats::rbinom(n, 1L, ifelse(tavr == 1L, 0.85, 0.45))
    })
    d$stroke <- c("no", "yes")[stroke + 1L]
    d$mr_grade <- c("none", "mild", "moderate", "severe")[mr]
    d$discharge <- c("home", "rehab", "nursing")[dest]
    d$approach <- c("surgical", "transcatheter")[tavr + 1L]
    d$valve_size <- c("small", "medium", "large")[size]
    d$valve_type <- c("mechanical", "bioprosthetic", "homograft")[valve]
    d$prior_ops <- prior
    d$match_pair <- paired
    labels <- c(
      stroke = "Postoperative stroke", mr_grade = "Postoperative mitral regurgitation grade",
      discharge = "Discharge destination", approach = "Surgical or transcatheter replacement",
      valve_size = "Prosthesis size", valve_type = "Prosthesis type",
      prior_ops = "Number of prior cardiac operations", match_pair = "In a matched pair (simulated)"
    )
    for (v in names(labels)) attr(d[[v]], "label") <- labels[[v]]
    d
  },
  jobs = list(
    "lm-binary" = list(subject = "stroke", type = "model", choices = c(lm_id, lm_era("as.integer(format(dt_surg, \"%Y\")) < 2015"), list(
      "^DATASET <- " = "DATASET <- \"built\"",
      "^OUTCOME <- " = "OUTCOME <- \"stroke\"",
      "^PREDICTORS <- " = paste("PREDICTORS <-", lm_covariates),
      "^OUTCOME_LEVELS <- " = "OUTCOME_LEVELS <- c(\"no\", \"yes\")",
      "^EVENT_LEVEL <- " = "EVENT_LEVEL <- \"yes\""
    ))),
    "lm-checkpred" = list(subject = "stroke", type = "model", choices = c(lm_patient, lm_era("as.integer(format(dt_surg, \"%Y\")) >= 2015"), list(
      "^DATASET <- " = "DATASET <- \"built\"",
      "^OUTCOME <- " = "OUTCOME <- \"stroke\"",
      "^GROUPS <- " = "GROUPS <- 5L"
    ))),
    "lm-ordinal" = list(subject = "mr", type = "model", choices = c(lm_id, list(
      "^DATASET <- " = "DATASET <- \"built\"",
      "^OUTCOME <- " = "OUTCOME <- \"mr_grade\"",
      "^PREDICTORS <- " = paste("PREDICTORS <-", lm_covariates),
      "^OUTCOME_LEVELS <- " = "OUTCOME_LEVELS <- c(\"none\", \"mild\", \"moderate\", \"severe\")"
    ))),
    "lm-nominal" = list(subject = "discharge", type = "model", choices = c(lm_id, list(
      "^DATASET <- " = "DATASET <- \"built\"",
      "^OUTCOME <- " = "OUTCOME <- \"discharge\"",
      "^PREDICTORS <- " = paste("PREDICTORS <-", lm_covariates),
      "^OUTCOME_LEVELS <- " = "OUTCOME_LEVELS <- c(\"home\", \"rehab\", \"nursing\")",
      "^REFERENCE_LEVEL <- " = "REFERENCE_LEVEL <- \"home\""
    ))),
    "lm-propensity_binary" = list(subject = "approach", type = "propensity", choices = c(lm_id, list(
      "^DATASET <- " = "DATASET <- \"built\"",
      "^TREATMENT <- " = "TREATMENT <- \"approach\"",
      "^PREDICTORS <- " = paste("PREDICTORS <-", lm_covariates),
      "^TREATMENT_LEVELS <- " = "TREATMENT_LEVELS <- c(\"surgical\", \"transcatheter\")",
      "^TREATED_LEVEL <- " = "TREATED_LEVEL <- \"transcatheter\""
    ))),
    # The mirrored histogram of that bundle, in its set, with no match flag.
    "lp-mirror" = list(subject = "approach", type = "propensity", choices = list(
      "^GROUP_LABELS <- " = "GROUP_LABELS <- c(surgical = \"Surgical\", transcatheter = \"Transcatheter\")"
    )),
    # The same bundle from a set of its own, with the simulated match flag, so
    # the matched figure is drawn too.
    "lp-mirror-matched" = list(template = "lp-mirror", subject = "approach", type = "matched", choices = list(
      "^MODEL_SET <- " = "MODEL_SET <- \"approach-propensity\"",
      "^GROUP_LABELS <- " = "GROUP_LABELS <- c(surgical = \"Surgical\", transcatheter = \"Transcatheter\")",
      "^MATCH <- " = "MATCH <- \"match_pair\"",
      "^ID <- " = "ID <- \"patient_id\""
    )),
    "lm-propensity_ordinal" = list(subject = "valvesize", type = "propensity", choices = c(lm_id, list(
      "^DATASET <- " = "DATASET <- \"built\"",
      "^TREATMENT <- " = "TREATMENT <- \"valve_size\"",
      "^PREDICTORS <- " = paste("PREDICTORS <-", lm_covariates),
      "^TREATMENT_LEVELS <- " = "TREATMENT_LEVELS <- c(\"small\", \"medium\", \"large\")"
    ))),
    "lm-propensity_nominal" = list(subject = "valvetype", type = "propensity", choices = c(lm_id, list(
      "^DATASET <- " = "DATASET <- \"built\"",
      "^TREATMENT <- " = "TREATMENT <- \"valve_type\"",
      "^PREDICTORS <- " = paste("PREDICTORS <-", lm_covariates),
      "^TREATMENT_LEVELS <- " = "TREATMENT_LEVELS <- c(\"mechanical\", \"bioprosthetic\", \"homograft\")",
      "^REFERENCE_LEVEL <- " = "REFERENCE_LEVEL <- \"mechanical\""
    ))),
    "lm-balancing_count" = list(subject = "priorops", type = "balancing", choices = c(lm_id, list(
      "^DATASET <- " = "DATASET <- \"built\"",
      "^OUTCOME <- " = "OUTCOME <- \"prior_ops\"",
      "^PREDICTORS <- " = paste("PREDICTORS <-", lm_covariates),
      "^DISTRIBUTION <- " = "DISTRIBUTION <- \"poisson\"",
      "^N_STRATA <- " = "N_STRATA <- 5L"
    )))
  )
)
