# The recommendation the rf fit templates (rfs-fit, rfc-fit, rfr-fit) print under their learning
# curve: are there enough events for a stable importance ranking, and enough predictors for a
# forest to be worth fitting? Both thresholds are study choices with no evidence behind their
# defaults, so the verdict is advice in a callout and never stops a render.

# The Jaccard index two top-k sets can take, by how many variables they share. With k = 5 a pair
# sharing four scores 0.67, which is why a mean of 0.8 needs most pairs to share all five.
.jaccard_steps <- function(k) {
  k <- as.integer(k)
  if (k < 2L) return("")
  shared <- seq.int(k - 1L, 1L)
  score <- sprintf("%.2f", shared / (2L * k - shared))
  paste0("With the top ", k, ", a pair sharing ", shared[1L], " of them scores ", score[1L],
         if (k > 2L) paste0(", ", paste(shared[-1L], "scores", score[-1L], collapse = ", ")), ".")
}

# `stability` is summary() of a gg_learning object: one row per fraction, with `fraction`, `events`,
# `jaccard`, `kendall` and `low_events`. The rightmost point is the whole-cohort bootstrap when it
# ran, otherwise the largest subsample. `unit` names what `events` counts, `model` the regression
# model a forest on few predictors should be checked against, `note` the learning note the
# template already prints. A rise above `tolerance` between the last two points reads as still rising.
.learning_verdict <- function(stability, n_predictors, k, agreement = 0.8, min_predictors = 10,
                              unit = "events", model = "a regression model", note = "", tolerance = 0.05) {
  st <- stability[order(stability$fraction), , drop = FALSE]
  last <- st[nrow(st), ]
  agree <- c(Jaccard = last$jaccard, `Kendall tau` = last$kendall)

  if (anyNA(agree)) {
    events <- "not assessed"
    events_text <- paste0("With one predictor there is no importance ranking to agree on, so the learning curve ",
                          "cannot say whether there are enough ", unit, ". Read the error curve only.")
  } else {
    met <- all(agree >= agreement)
    rise <- if (nrow(st) > 1L) max(agree - c(st$jaccard[nrow(st) - 1L], st$kendall[nrow(st) - 1L])) else NA_real_
    rising <- !is.na(rise) && rise > tolerance
    low <- isTRUE(last$low_events)
    events <- if (!met) "not yet" else if (rising || low) "borderline" else "enough"
    found <- sprintf(paste0("At the rightmost point, %s %s, the top-%d Jaccard is %.2f and Kendall tau %.2f, ",
                            "against %.2f (LEARNING_AGREEMENT)"),
                     format(last$events), unit, as.integer(k), agree[[1L]], agree[[2L]], agreement)
    trend <- if (is.na(rise)) "" else if (rising) {
      sprintf(", and agreement was still rising, by %.2f since the previous point", rise)
    } else {
      ", and agreement has levelled off"
    }
    reading <- switch(events,
      enough = paste0("The importance ranking is reproducible at this cohort size, so the explain job's top variables ",
                      "and the partial plots drawn from them can be read."),
      borderline = paste0("Agreement reaches the threshold, but ",
                          if (low) paste0("on fewer than 50 ", unit, ", too few to trust") else
                            paste0("more ", unit, " would still change the ranking"),
                          ". Read the explain job's top variables as provisional."),
      `not yet` = paste0("The top variables change from refit to refit at this cohort size. The forest may still ",
                         "predict (see the error curve), but its importance ranking and the partial plots drawn ",
                         "from it are not yet reproducible.")
    )
    events_text <- paste0(found, trend, ". ", reading)
  }

  features <- n_predictors >= min_predictors
  features_text <- if (features) {
    sprintf(paste0("%d predictors, at or above %d (MIN_PREDICTORS). A forest earns its place by finding ",
                   "interactions and non-linear effects among many candidates, and there are enough here for that ",
                   "search to matter."), as.integer(n_predictors), as.integer(min_predictors))
  } else {
    sprintf(paste0("%d predictors, under %d (MIN_PREDICTORS). With this few, %s on the same predictors is likely ",
                   "as informative and simpler to report; fit one alongside before relying on the forest."),
            as.integer(n_predictors), as.integer(min_predictors), model)
  }

  ok <- events == "enough" && features
  text <- paste0(
    "::: {.callout-", if (ok) "tip" else "warning", "}\n",
    "## Recommendation\n\n",
    "**Events: ", events, ".** ", events_text, "\n\n",
    "**Predictors: ", if (features) "enough" else "few", ".** ", features_text, "\n\n",
    "Both thresholds are study choices, set under `EDIT:`, not rules.",
    if (nzchar(note)) paste0(" ", note), "\n",
    ":::\n"
  )
  list(events = events, features = features, text = text)
}
