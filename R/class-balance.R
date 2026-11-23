# Class imbalance for rfc-fit. A classification forest scored by misclassification rewards always
# predicting the larger class: its error looks low, and its importance ranks variables by how well
# they predict that class. Two classes at or past `ratio` (larger count over smaller) are grown as
# randomForestSRC's quantile classifier (RFQ, O'Brien and Ishwaran 2019) and scored by normalized
# Brier, as imbalanced() does; predict(), vimp() and subsample() read both off the forest, so the
# learning curve and rfc-explain follow. RFQ is two-class only, so more classes get a warning.
# The ratio is a study choice with no evidence behind its default.
#
# Returns `rfq`, whether to grow the RFQ forest; `ratio`, the observed one; `metric`, what the
# forest's error is, for the captions; and `text`, the callout the report prints.
.class_balance <- function(y, ratio = 3) {
  if (!is.numeric(ratio) || length(ratio) != 1L || is.na(ratio) || ratio < 1) {
    stop("IMBALANCE_RATIO must be one number of at least 1, or Inf to never grow the RFQ forest.", call. = FALSE)
  }
  counts <- table(droplevels(as.factor(y)))
  observed <- as.numeric(max(counts) / min(counts))
  two <- length(counts) == 2L
  rfq <- two && observed >= ratio
  shown <- paste0(names(counts), " ", as.integer(counts), collapse = ", ")
  found <- sprintf("The classes are %s, a ratio of %.1f to 1 between the largest and smallest", shown, observed)
  text <- if (rfq) {
    paste0("::: {.callout-note}\n## Class imbalance\n\n", found, ", at or past ", ratio, " (IMBALANCE_RATIO). ",
           "A forest scored by misclassification would reward predicting the larger class every time, so this ",
           "forest is randomForestSRC's quantile classifier (RFQ), and its error and importance are the ",
           "normalized Brier score. The explain job's importance and intervals use the same score.\n:::\n")
  } else if (observed >= ratio) {
    paste0("::: {.callout-warning}\n## Class imbalance\n\n", found, ", at or past ", ratio, " (IMBALANCE_RATIO). ",
           "The quantile classifier this job grows for an imbalanced outcome takes two classes only, so this is ",
           "a standard forest. Its error rate and importance are dominated by the larger classes; consider ",
           "the class of interest against the rest, as two classes.\n:::\n")
  } else {
    ""
  }
  list(rfq = rfq, ratio = observed, metric = if (rfq) "normalized Brier score" else "error rate", text = text)
}
