# The numerical core of the lg template: the grouped event rate of a covariate
# on a link scale, the six candidate scales the covariate might enter a model
# on, and the figure that sets them side by side. The design is
# dev/specs/2026-10-11-lg-template-design.md. These are internal, unit-tested
# and called from inst/templates/10_descriptive/lg.qmd, as .check_job_columns()
# and .save_figure() are, so a study's copy of the template carries none of
# this code.

# The covariate's groups. "continuous" is PROC RANK GROUPS=G exactly: rank with
# ties averaged, then group floor(rank * G / (n + 1)), so a converted job
# reproduces the SAS groups and tied values share a group. "ordinal" is
# %logitgr: each observed level is a group, numbered from 0 in order, and
# `groups` is not used. A missing x is dropped, given NA and counted.
.lg_groups <- function(x, groups = 5L, kind = c("continuous", "ordinal")) {
  kind <- match.arg(kind)
  if (!is.numeric(x)) stop("x must be numeric.", call. = FALSE)
  seen <- !is.na(x)
  if (!any(seen)) stop("x has no value to group: every value is missing.", call. = FALSE)
  group <- rep(NA_integer_, length(x))
  if (identical(kind, "ordinal")) {
    group[seen] <- match(x[seen], sort(unique(x[seen]))) - 1L
  } else {
    if (!is.numeric(groups) || length(groups) != 1L || is.na(groups) || groups < 2 || groups != round(groups)) {
      stop("groups must be a whole number of at least 2.", call. = FALSE)
    }
    # rank * G is exact (ranks are whole or end in .5), so a product that is a
    # multiple of n + 1 divides exactly and floor() cannot land one group low.
    group[seen] <- as.integer(floor(rank(x[seen], ties.method = "average") * groups / (sum(seen) + 1)))
  }
  list(group = group, missing = sum(!seen))
}
