# Missing values for a vp job, before any imputation. varPro removes every
# incomplete row and ignores na.action, so the vp templates settle missing
# values here, before varPro sees the data: a row missing the outcome is
# dropped in either mode; under "na.impute" the predictors are left for the
# template to impute once, and a predictor missing in more than max_missing of
# the rows is refused rather than filled; under "na.omit" incomplete rows go,
# as the templates did before. Returns the rows, a counts table with the rule
# as its "rule" attribute, and the counts for the handoff's cohort.
#' @noRd
.vp_missing <- function(d, predictors, outcome = character(), na_action = c("na.impute", "na.omit"),
                        max_missing = 0.4) {
  na_action <- match.arg(na_action)
  outcome <- as.character(outcome)
  n_supplied <- nrow(d)
  no_outcome <- if (length(outcome)) !stats::complete.cases(d[outcome]) else logical(n_supplied)
  d <- d[!no_outcome, , drop = FALSE]
  n_missing <- vapply(d[predictors], function(x) sum(is.na(x)), integer(1L))
  share <- if (nrow(d)) n_missing / nrow(d) else n_missing * 0
  n_dropped <- 0L
  if (na_action == "na.impute") {
    sparse <- names(share)[share > max_missing]
    if (length(sparse)) {
      stop("Missing in more than ", format(100 * max_missing), "% of the rows, too many to impute: ",
           paste0(sparse, " (", round(100 * share[sparse]), "%)", collapse = ", "),
           ". Remove them from the predictors, raise MAX_MISSING, or set NA_ACTION <- \"na.omit\".", call. = FALSE)
    }
    n_imputed <- n_missing
  } else {
    keep <- stats::complete.cases(d[predictors])
    n_dropped <- sum(!keep)
    d <- d[keep, , drop = FALSE]
    n_imputed <- n_missing * 0L
  }
  pct <- function(k) paste0(k, " (", round(100 * k / max(1L, n_supplied - sum(no_outcome))), "%)")
  hit <- names(n_missing)[n_missing > 0L]
  per <- function() vapply(n_missing[hit], pct, "", USE.NAMES = FALSE)
  imputing <- na_action == "na.impute"
  table <- data.frame(
    Row = c("Supplied", "Outcome missing, dropped",
            if (length(hit)) paste0("Missing: ", hit),
            if (length(hit) && imputing) paste0("Imputed: ", hit),
            if (!imputing) "Missing a predictor, dropped", "Used"),
    Count = c(as.character(n_supplied), as.character(sum(no_outcome)),
              if (length(hit)) per(),
              if (length(hit) && imputing) per(),
              if (!imputing) pct(n_dropped), as.character(nrow(d))),
    stringsAsFactors = FALSE
  )
  attr(table, "rule") <- if (na_action == "na.impute") {
    "Missing predictor values were imputed once by random forest, without the outcome, before the screen."
  } else {
    "Patients missing any predictor were excluded before the screen."
  }
  list(d = d, table = table,
       cohort = list(na_action = na_action, n_supplied = as.integer(n_supplied),
                     n_outcome_missing = as.integer(sum(no_outcome)),
                     n_imputed = n_imputed, n_dropped = as.integer(n_dropped)))
}
