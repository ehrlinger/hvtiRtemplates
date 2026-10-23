# Virtual twins family, in flight: vt-fit grows a survival forest on each arm
# and predicts every patient under both, and vt-explain shows what the twins
# say. The decision is mitral repair against replacement, and the outcome
# reintervention, censored at death or last contact.
#
# columns() adds both, under its own seed. Repair is chosen more often for
# younger patients without heart failure, so the arms differ at baseline, as
# they do in a real study. The effect is heterogeneous on purpose: repair
# lowers the reintervention hazard in a ventricle of normal size and raises it
# in a dilated one, by LV end-diastolic dimension, which family-sid.R adds. So
# the twins have a benefit that changes sign to find, and vt-explain's strata,
# the echo-phenotype clusters, split along it. This file sorts after
# family-sid.R, whose columns and set it reads.

vt_columns <- function(d) {
  lvedd <- ifelse(is.na(d$lvedd), mean(d$lvedd, na.rm = TRUE), d$lvedd)
  withr::with_seed(20261024, {
    n <- nrow(d)
    repair <- stats::rbinom(n, 1L, stats::plogis(0.4 - 0.04 * (d$age - 60) - 0.6 * d$hx_chf))
    rate <- 0.02 * exp(0.02 * (d$age - 60) + 0.3 * d$hx_dm + repair * (-0.4 + 1.2 * (lvedd - 5.2)))
    t_reint <- stats::rexp(n, rate)
  })
  d$mv_procedure <- c("replace", "repair")[repair + 1L]
  d$reint <- as.integer(t_reint < d$iv_dead)
  d$iv_reint <- round(pmin(t_reint, d$iv_dead), 3)
  d$iv_reint[d$iv_reint == 0] <- 0.00025
  labels <- c(mv_procedure = "Mitral repair or replacement", reint = "Reintervention",
              iv_reint = "Follow-up to reintervention, death or censoring (years)")
  for (v in names(labels)) attr(d[[v]], "label") <- labels[[v]]
  d
}

gallery_family(
  "vt",
  columns = vt_columns,
  jobs = list(
    # Eligibility by Gower distance and by the echo-phenotype set's SID
    # distance. 500 trees an arm, not 1000, keep the render short.
    "vt-fit" = list(subject = "reint", type = "vt", choices = list(
      "^<!-- EDIT: say what this analysis is for" = paste0(
        "Gallery job on the synthetic cohort: mitral repair against replacement, and freedom from ",
        "reintervention to eight years.\n\n<!--"
      ),
      "^DATASET <- " = "DATASET <- \"built\"",
      "^ID <- \"ccfid\"" = "ID <- \"patient_id\"",
      "^TIME <- " = "TIME <- \"iv_reint\"",
      "^STATUS <- " = "STATUS <- \"reint\"",
      "^ARM <- " = "ARM <- \"mv_procedure\"",
      "^ARMS <- c\\(" = "ARMS <- c(\"repair\", \"replace\")",
      "^PREDICTORS <- " = paste0(
        "PREDICTORS <- c(\"age\", \"female\", \"bmi\", \"hx_chf\", \"hx_dm\", \"nyha_pr\", \"lvef\", ",
        "\"creat_pr\", \"lvedd\", \"lvesd\", \"la_diam\", \"rvsp\", \"e_e\")"
      ),
      "^ELIGIBILITY <- " = "ELIGIBILITY <- c(\"gower\", \"sid\")",
      "^SID_SET <- " = "SID_SET <- \"echo-sid\"",
      "^HORIZON <- " = "HORIZON <- 8",
      "^NTREE <- " = "NTREE <- 500"
    )),
    # 200 bootstraps, not 1000, keep the render short; the intervals are rough.
    "vt-explain" = list(subject = "reint", type = "vt", choices = list(
      "^<!-- EDIT: say which vt-fit job" = paste0(
        "Explains the `vt-fit` job in this set: which patients the twins say repair suits, ",
        "stratified by the echo-phenotype clusters.\n\n<!--"
      ),
      "^STRATIFY <- " = "STRATIFY <- list(set = \"echo-sid\")",
      "^BOOT <- " = "BOOT <- 200"
    ))
  )
)
