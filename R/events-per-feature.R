# Events per candidate feature, for the forest templates (rfs-fit, vt-fit).
#
# A survival split is decided by events, and a forest with few of them per
# feature it may split on fits noise that its OOB error does not show. The
# floor is a study choice with no evidence behind its default: 20 is the low
# end of a 20 to 30 rule of thumb, stated as a guess (CHSS AVSD, 2026-10-29).
# Below it a final render stops; any other render warns and is marked draft,
# as the rf band floor is (R/rf-bands.R). A floor of 0 reports and never warns.
#
# `events` is named by group (each arm, or the cohort), `n_features` is the
# number of features each forest is given. Returns the table the report prints.
.check_events_per_feature <- function(events, n_features, floor = 20) {
  epf <- events / max(n_features, 1L)
  table <- data.frame(group = names(events), events = as.integer(events), features = as.integer(n_features),
                      events_per_feature = round(epf, 1))
  thin <- epf < floor
  if (any(thin)) {
    msg <- paste0("Too few events per candidate feature for a forest: ",
                  paste0(names(events)[thin], " has ", events[thin], " event(s) for ", n_features, " feature(s), ",
                         sprintf("%.1f", epf[thin]), " each", collapse = "; "),
                  ", under the floor of ", floor, " (MIN_EVENTS_PER_FEATURE). The floor is a guess, not a rule; ",
                  "fewer features, or a model other than a forest, may suit this cohort.")
    if (.strict_render()) {
      stop(msg, "\nThis render stops because HVTI_TEMPLATE_STRICT is '", Sys.getenv("HVTI_TEMPLATE_STRICT"),
           "'. Unset it, or set it to 0, false or no, to render a draft instead.", call. = FALSE)
    }
    warning(msg, call. = FALSE)
    .run_mark_draft(paste0("a forest has fewer than ", floor, " events per candidate feature"))
  }
  table
}
