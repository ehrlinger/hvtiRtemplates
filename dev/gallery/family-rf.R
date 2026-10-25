# Random-forest family: the three fit/explain pairs, one set each, and the
# in-flight VarPro pair, vp-fit and vp-explain. Each explain job reads the
# forest its fit job saved in the same (subject, type) set, so the fit is
# listed first.
#
# rfs grows on the demo's own death outcome. rfc and rfr need outcomes the
# demo cohort does not carry, so columns() adds a major postoperative
# complication (binary) and a postoperative length of stay (continuous, with
# its log). Both are driven by the existing covariates, so importance and
# dependence have something to find: the complication by age, heart failure,
# ejection fraction and creatinine; the stay by age, NYHA class, ejection
# fraction, diabetes and body mass index.

rf_columns <- function(d) {
  withr::with_seed(20260929, {
    n <- nrow(d)
    creat <- ifelse(is.na(d$creat_pr), 1, d$creat_pr)
    lp <- -2.2 + 0.04 * (d$age - 60) + 0.8 * d$hx_chf - 0.04 * (d$lvef - 55) + 1.2 * (creat - 1)
    complication <- stats::rbinom(n, 1L, stats::plogis(lp))
    log_los <- log(5) + 0.012 * (d$age - 60) + 0.12 * (d$nyha_pr - 2) - 0.008 * (d$lvef - 55) +
      0.15 * d$hx_dm + 0.01 * (d$bmi - 28) + 0.25 * complication + stats::rnorm(n, 0, 0.3)
    los <- pmax(1L, as.integer(round(exp(log_los))))
  })
  d$complication <- complication
  d$los <- los
  d$log_los <- round(log(los), 4)
  attr(d$complication, "label") <- "Major postoperative complication"
  attr(d$los, "label") <- "Postoperative length of stay (days)"
  attr(d$log_los, "label") <- "Postoperative length of stay (log days)"
  d
}

rf_predictors <- paste0(
  "PREDICTORS <- c(\"age\", \"female\", \"bmi\", \"hx_chf\", \"hx_dm\", \"nyha_pr\", ",
  "\"lvef\", \"plvmassi\", \"creat_pr\")"
)

# Choices common to every fit: the cohort's identifier, predictors, forest
# size, the prose line naming the job it replaces. Each explain job takes its
# data, rows and identifier from the forest its fit saved, so sets none.
rf_fit_choices <- function(what, na_action) {
  list(
    "^ID <- \"ccfid\"$" = "ID <- \"patient_id\"",
    # #300 made the job's "replaces" note a multi-line EDIT comment; the
    # sentence takes its opening line and the rest stays a hidden comment.
    "^<!-- EDIT: name the job this replaces" = paste0("Gallery job on the synthetic cohort: ", what, ".\n\n<!--"),
    "^PREDICTORS <- " = rf_predictors,
    "^NTREE <- " = "NTREE <- 300",
    "^NA_ACTION <- " = paste0("NA_ACTION <- \"", na_action, "\"")
  )
}

rf_explain_choices <- function(prefix, extra = list()) {
  c(list(
    "^Explains the forest the `" =
      paste0("Explains the forest the `", prefix, "-fit` job in this set saved: which predictors drive it, and how."),
    "^TOP_K <- " = "TOP_K <- 4"
  ), extra)
}

gallery_family(
  "rf",
  columns = rf_columns,
  jobs = list(
    "rfs-fit" = list(subject = "dead", type = "rf", choices = rf_fit_choices(
      "survival after operation (iv_dead, dead) on nine preoperative predictors", "na.omit"
    )),
    "rfs-explain" = list(subject = "dead", type = "rf", choices = rf_explain_choices(
      "rfs", list("^TIMES <- " = "TIMES <- c(1, 5, 10)")
    )),
    "rfc-fit" = list(subject = "complication", type = "rf", choices = c(
      rf_fit_choices("major postoperative complication (complication, 0/1)", "na.impute"),
      list(
        "^RESPONSE <- " = "RESPONSE <- \"complication\"",
        "^ROC_CLASS <- " = "ROC_CLASS <- \"1\""
      )
    )),
    "rfc-explain" = list(subject = "complication", type = "rf", choices = rf_explain_choices("rfc")),
    "rfr-fit" = list(subject = "los", type = "rf", choices = c(
      rf_fit_choices("postoperative length of stay, logged (log_los)", "na.impute"),
      list("^RESPONSE <- " = "RESPONSE <- \"log_los\"")
    )),
    "rfr-explain" = list(subject = "los", type = "rf", choices = rf_explain_choices("rfr")),
    # The VarPro screen, in flight: survival after operation on the nine
    # predictors rfs-fit grows on, so the two read side by side. Five stability
    # refits, not twenty, keep the render short; the selection frequencies are
    # rough for it.
    "vp-fit" = list(subject = "dead", type = "vp", choices = list(
      "^<!-- EDIT: say what this screen is for" = paste0(
        "Gallery job on the synthetic cohort: a VarPro screen of survival after operation (iv_dead, dead) ",
        "on the nine preoperative predictors rfs-fit grows on.\n\n<!--"
      ),
      "^ID <- \"ccfid\"$" = "ID <- \"patient_id\"",
      "^PREDICTORS <- " = rf_predictors,
      "^REPEATS <- " = "REPEATS <- 5"
    )),
    "vp-explain" = list(subject = "dead", type = "vp", choices = list(
      "^<!-- EDIT: say which vp-fit screen" =
        "Explains the `vp-fit` screen in this set: survival at five years along each selected predictor.\n\n<!--"
    )),
    "vp-individual" = list(subject = "dead", type = "vp", choices = list(
      "^<!-- EDIT: say which vp-fit screen" =
        "Describes the `vp-fit` screen in this set patient by patient: each selected predictor's local gradient.\n\n<!--"
    )),
    # No outcome: the nine predictors the rf fits grow on, with NYHA class entered as
    # the grade it is. A smaller forest and three refits keep the render short.
    "vp-dependence" = list(subject = "preop", type = "vp", choices = list(
      "^<!-- EDIT: say which variables this studies" = paste0(
        "Gallery job on the synthetic cohort: how the nine preoperative predictors the rf fits grow on ",
        "depend on each other, with no outcome entered.\n\n<!--"
      ),
      "^ID <- \"ccfid\"$" = "ID <- \"patient_id\"",
      "^VARIABLES <- " = sub("^PREDICTORS", "VARIABLES", rf_predictors),
      "^ORDINAL <- " = "ORDINAL <- \"nyha_pr\"",
      "^NTREE <- " = "NTREE <- 200",
      "^REPEATS <- " = "REPEATS <- 3"
    ))
  )
)
