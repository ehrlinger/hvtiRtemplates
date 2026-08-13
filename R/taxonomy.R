#' Analysis prefix taxonomy
#'
#' The two-letter prefix system inherited from the original CORR analysis
#' binder. The prefix encodes both the type of analysis and the folder the job
#' belongs in.
#'
#' This is data rather than documentation on purpose. The same table lived in a
#' README and drifted from the corpus it described; as a function it is checked
#' by the test suite against the files actually present.
#'
#' @return A data frame with columns `prefix`, `name`, `folder`, `description`.
#' @export
#' @examples
#' head(hvti_taxonomy())
hvti_taxonomy <- function() {
  tx <- rbind.data.frame(
    c("bd",    "Build",                     "datasets",      "assembles raw sources into the analytic dataset"),
    c("vars",  "Variables",                 "datasets",      "macro enhancing the dataset with temp vars, imputations, propensity"),
    c("dt",    "Data check",                "datasets",      "initial QC of the build dataset"),
    c("dc",    "Descriptive",               "descriptive",   "Table 1s, covariate summaries, balance tables"),
    c("lg",    "Logit trends",              "descriptive",   "variable transformation and linearity checks"),
    c("rg",    "Regression trends",         "descriptive",   "trend checks for continuous and polytomous outcomes"),
    c("ac",    "Actuarial",                 "distributions", "Kaplan-Meier / non-parametric life table"),
    c("hz",    "Hazard fit",                "distributions", "fits the underlying hazard distribution"),
    c("hs",    "Hazard setup",              "distributions", "patient-level survival predictions from the HM model"),
    c("cd",    "Cumulative distribution",   "distributions", "cumulative distribution plots; follow-up summaries"),
    c("nd",    "Nonparametric distributions","distributions","distribution estimates stratified by group"),
    c("hm",    "Hazard model",              "analyses",      "risk factor analysis; builds on the HZ fit"),
    c("mm",    "Mixed model",               "analyses",      "continuous repeated-measures longitudinal analysis"),
    c("gm",    "Generalized model",         "analyses",      "repeated-measures ordinal / count models"),
    c("lm",    "Logistic model",            "analyses",      "logistic regression; propensity score development"),
    c("bh",    "Bootstrap hazard",          "analyses",      "bootstrap variable selection or fixed-set hazard models"),
    c("bl",    "Bootstrap logistic",        "analyses",      "bootstrap variable selection or fixed-set logistic models"),
    c("bc",    "Bootstrap Cox",             "analyses",      "bootstrap variable selection or fixed-set Cox models"),
    c("bn",    "Bootstrap nonparametric",   "analyses",      "bootstrap confidence intervals for nonparametric estimates"),
    c("bq",    "Bootstrap quantile",        "analyses",      "quantile regression with bagging"),
    c("br",    "Bootstrap regression",      "analyses",      "linear regression with bagging"),
    c("nm",    "Nonparametric model",       "analyses",      "nonparametric regression models"),
    c("rf",    "Random forest",             "analyses",      "random forest and randomForestSRC models"),
    c("pm",    "Propensity model",          "analyses",      "count outcome with balancing score"),
    c("rm",    "Regression model",          "analyses",      "linear regression with balancing score"),
    c("cm",    "Cox matching",              "analyses",      "Cox PH with propensity matching / IPTW"),
    c("ls",    "Life table / STS",          "analyses",      "STS observed-versus-predicted analyses"),
    c("hp",    "Hazard plot",               "graphs",        "overlays actuarial and predicted survival; patient-specific curves"),
    c("mp",    "Mixed model plot",          "graphs",        "individual and population-level trends from MM"),
    c("lp",    "Logistic plot",             "graphs",        "ordinal or binary logistic model results"),
    c("np",    "Nonparametric plot",        "graphs",        "nonparametric distribution figures"),
    c("dp",    "Descriptive plot",          "graphs",        "bar, scatter, spaghetti, sankey, bubble plots"),
    c("fp",    "Forest plot",               "graphs",        "odds ratio or hazard ratio forest plots"),
    c("gp",    "Generalized model plot",    "graphs",        "depicts generalized / longitudinal model results"),
    c("cp",    "Cumulative probability plot","graphs",       "cumulative probability figures"),
    c("ce",    "Competing events",          "graphs",        "competing risks / multistate figures"),
    c("rp",    "Regression plot",           "graphs",        "regression and balance figures"),
    c("ar",    "Analysis report",           "documents",     "the written analysis report"),
    c("rfsrc", "Random forest (SRC)",       "analyses",      "randomForestSRC survival, regression and classification models"),
    c("rfc",   "Random forest classifier",  "analyses",      "random forest classification reporting"),
    c("rfs",   "Random forest survival",    "analyses",      "random forest survival analysis reporting"),
    c("nb",    "Notebook",                  "analyses",      "boosting notebooks (Boostmtree, BoostMLR)"),
    stringsAsFactors = FALSE
  )
  names(tx) <- c("prefix", "name", "folder", "description")
  tx
}

#' Second fields that are not analysis prefixes
#'
#' Some corpus files are named `tp.<word>.<ext>` where `<word>` is a utility
#' name rather than an analysis prefix — `tp.plots.sas`, `tp.PPTs.R`. They are
#' listed here so the test suite can tell "not a prefix" apart from "a prefix
#' nobody documented". Without this distinction the taxonomy either fills with
#' non-prefixes or stops catching real omissions.
#'
#' @return A character vector.
#' @export
#' @examples
#' hvti_non_prefixes()
hvti_non_prefixes <- function() {
  c("plots", "ppt", "PPTs", "test", "pp")
}
