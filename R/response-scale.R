# An rm job's RESPONSE_SCALE study choice as one plain string, "identity" or
# "log". Every reader of the setting branches on this value, never on the raw
# one: a name, as a lookup such as scales["outcome"] keeps, passes %in% but fails
# identical(), and c(outcome = "identity") once fitted log() under prose that
# read the coefficients as measured.
.response_scale <- function(scale) {
  if (!is.character(scale) || length(scale) != 1L || is.na(scale) || !scale %in% c("identity", "log")) {
    stop('RESPONSE_SCALE must be "identity" or "log". Change it in edit-study-choices.', call. = FALSE)
  }
  unname(scale)
}

# The response term of an rm job's formula, from its RESPONSE_SCALE study choice:
# "identity" is the column itself, "log" its natural log. A log scale stops on a
# value at or below zero, which has no log, rather than let the fit fail on -Inf
# with an error about the response or drop the row unannounced.
.response_term <- function(d, outcome, scale) {
  if (identical(.response_scale(scale), "identity")) return(outcome)
  if (!is.numeric(d[[outcome]])) {
    stop('RESPONSE_SCALE is "log", but ', outcome, " is not numeric. Change OUTCOME in edit-study-choices.",
         call. = FALSE)
  }
  low <- sum(d[[outcome]] <= 0, na.rm = TRUE)
  if (low > 0L) {
    stop('RESPONSE_SCALE is "log", but ', outcome, " has ", low, if (low == 1L) " value" else " values",
         " at or below zero, which have no log. Set RESPONSE_SCALE to \"identity\" in edit-study-choices,",
         " or derive a positive column in the dataset build.", call. = FALSE)
  }
  sprintf("log(%s)", outcome)
}

# The formula an rm job fitted and how to read its coefficients, as one markdown
# paragraph, so the report's reading follows the scale actually fitted. `what`
# names the response in prose: "outcome" or "exposure".
.response_note <- function(formula, scale, what) {
  reading <- if (identical(.response_scale(scale), "log")) {
    paste0("The ", what, " is modeled on the log scale: a coefficient is the change in the log ", what,
           " for a unit change in a numeric predictor, or against the reference level of a categorical one,",
           " the others held fixed, and exp() of it is a ratio of geometric means, not a difference.")
  } else {
    paste0("The ", what, " is modeled as measured: a coefficient is the expected change in the ", what,
           ", in its own units, for a unit change in a numeric predictor, or against the reference level",
           " of a categorical one, the others held fixed.")
  }
  paste0("The model fitted is `", paste(deparse(formula), collapse = " "), "`. ", reading, "\n")
}
