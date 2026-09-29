# Logistic-model family: the eight lm templates, each in its own set so every
# report reads as one job. lm-checkpred validates the bundle lm-binary saves,
# so the two share the stroke-model set and lm-binary renders first. The
# outcomes, treatments and the count exposure are simulated from the demo
# covariates, so every model has something to find.

# lm-binary fits on operations before 2015 and lm-checkpred validates on 2015
# onward. The lm templates read a whole registered dataset (they have no
# ANALYSIS_SET), so the split is made here, as two more registered datasets.
lm_register_split <- function(root, job) {
  dir <- hvtiRutilities::study_dir("datasets", root)
  built <- readRDS(file.path(dir, "built.rds"))
  cohorts <- list(training = built$year < 2015, validation = built$year >= 2015)
  for (name in names(cohorts)) {
    file <- paste0("built-", name, ".rds")
    saveRDS(built[cohorts[[name]], , drop = FALSE], file.path(dir, file))
    invisible(utils::capture.output(suppressMessages(hvtiRutilities::register_data(
      root, built = file, dataset = name, role = "named",
      population = paste0("Synthetic cohort, ", name, " operations (",
                          if (name == "training") "1990-2014" else "2015-2024", ")")
    ))))
  }
}

lm_id <- list("^ID <- " = "ID <- \"patient_id\"", "^IMPUTATION <- " = "IMPUTATION <- NULL")
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
    })
    d$stroke <- c("no", "yes")[stroke + 1L]
    d$mr_grade <- c("none", "mild", "moderate", "severe")[mr]
    d$discharge <- c("home", "rehab", "nursing")[dest]
    d$approach <- c("surgical", "transcatheter")[tavr + 1L]
    d$valve_size <- c("small", "medium", "large")[size]
    d$valve_type <- c("mechanical", "bioprosthetic", "homograft")[valve]
    d$prior_ops <- prior
    labels <- c(
      stroke = "Postoperative stroke", mr_grade = "Postoperative mitral regurgitation grade",
      discharge = "Discharge destination", approach = "Surgical or transcatheter replacement",
      valve_size = "Prosthesis size", valve_type = "Prosthesis type",
      prior_ops = "Number of prior cardiac operations"
    )
    for (v in names(labels)) attr(d[[v]], "label") <- labels[[v]]
    d
  },
  jobs = list(
    "lm-binary" = list(subject = "stroke", type = "model", prepare = lm_register_split, choices = c(lm_id, list(
      "^DATASET <- " = "DATASET <- \"training\"",
      "^OUTCOME <- " = "OUTCOME <- \"stroke\"",
      "^PREDICTORS <- " = paste("PREDICTORS <-", lm_covariates),
      "^OUTCOME_LEVELS <- " = "OUTCOME_LEVELS <- c(\"no\", \"yes\")",
      "^EVENT_LEVEL <- " = "EVENT_LEVEL <- \"yes\""
    ))),
    "lm-checkpred" = list(subject = "stroke", type = "model", choices = list(
      "^DATASET <- " = "DATASET <- \"validation\"",
      "^OUTCOME <- " = "OUTCOME <- \"stroke\"",
      "^GROUPS <- " = "GROUPS <- 5L"
    )),
    "lm-ordinal" = list(subject = "mr", type = "model", choices = c(lm_id, list(
      "^DATASET <- " = "DATASET <- \"study\"",
      "^OUTCOME <- " = "OUTCOME <- \"mr_grade\"",
      "^PREDICTORS <- " = paste("PREDICTORS <-", lm_covariates),
      "^OUTCOME_LEVELS <- " = "OUTCOME_LEVELS <- c(\"none\", \"mild\", \"moderate\", \"severe\")"
    ))),
    "lm-nominal" = list(subject = "discharge", type = "model", choices = c(lm_id, list(
      "^DATASET <- " = "DATASET <- \"study\"",
      "^OUTCOME <- " = "OUTCOME <- \"discharge\"",
      "^PREDICTORS <- " = paste("PREDICTORS <-", lm_covariates),
      "^OUTCOME_LEVELS <- " = "OUTCOME_LEVELS <- c(\"home\", \"rehab\", \"nursing\")",
      "^REFERENCE_LEVEL <- " = "REFERENCE_LEVEL <- \"home\""
    ))),
    "lm-propensity_binary" = list(subject = "approach", type = "propensity", choices = c(lm_id, list(
      "^DATASET <- " = "DATASET <- \"study\"",
      "^TREATMENT <- " = "TREATMENT <- \"approach\"",
      "^PREDICTORS <- " = paste("PREDICTORS <-", lm_covariates),
      "^TREATMENT_LEVELS <- " = "TREATMENT_LEVELS <- c(\"surgical\", \"transcatheter\")",
      "^TREATED_LEVEL <- " = "TREATED_LEVEL <- \"transcatheter\""
    ))),
    "lm-propensity_ordinal" = list(subject = "valvesize", type = "propensity", choices = c(lm_id, list(
      "^DATASET <- " = "DATASET <- \"study\"",
      "^TREATMENT <- " = "TREATMENT <- \"valve_size\"",
      "^PREDICTORS <- " = paste("PREDICTORS <-", lm_covariates),
      "^TREATMENT_LEVELS <- " = "TREATMENT_LEVELS <- c(\"small\", \"medium\", \"large\")"
    ))),
    "lm-propensity_nominal" = list(subject = "valvetype", type = "propensity", choices = c(lm_id, list(
      "^DATASET <- " = "DATASET <- \"study\"",
      "^TREATMENT <- " = "TREATMENT <- \"valve_type\"",
      "^PREDICTORS <- " = paste("PREDICTORS <-", lm_covariates),
      "^TREATMENT_LEVELS <- " = "TREATMENT_LEVELS <- c(\"mechanical\", \"bioprosthetic\", \"homograft\")",
      "^REFERENCE_LEVEL <- " = "REFERENCE_LEVEL <- \"mechanical\""
    ))),
    "lm-balancing_count" = list(subject = "priorops", type = "balancing", choices = c(lm_id, list(
      "^DATASET <- " = "DATASET <- \"study\"",
      "^OUTCOME <- " = "OUTCOME <- \"prior_ops\"",
      "^PREDICTORS <- " = paste("PREDICTORS <-", lm_covariates),
      "^DISTRIBUTION <- " = "DISTRIBUTION <- \"poisson\"",
      "^N_STRATA <- " = "N_STRATA <- 5L"
    )))
  )
)
