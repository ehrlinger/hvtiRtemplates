# lg Template Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `inst/templates/10_descriptive/lg.qmd`, the logit calibration job, as designed in `dev/specs/2026-10-11-lg-template-design.md`: for each covariate it groups the patients, takes each group's event rate on the logit or constant-hazard scale, plots it against six candidate scales of the covariate with the weighted R-squared of a straight line, and saves the scale the analyst chooses as a term ready for an `lm` job's `PREDICTORS`.

**Architecture:** The numerical core is five internal functions in a new `R/logit-calibration.R` (`.lg_groups()`, `.lg_table()`, `.lg_scales()`, `.lg_plot()` and the helpers around them), unit-tested on hand-worked fixtures and called from the template, so a study's copy of the job carries no numerical code. The template follows `dc-stddiff.qmd`: the shared data step (`read_job_data()`), the guard chunks, a `set` chunk with `set_path()` and `save_figure()`, one table and one figure per covariate emitted as child chunks so Quarto numbers them, and a closing chunk that saves `lg-scales.rds` and prints the `PREDICTORS` line. Everything else is reused: `.check_job_columns()`, `.save_figure()`, `.attach_handoff_lineage()`, `.strict_render()`, `.embed_provenance()`.

**Tech Stack:** R, Quarto, testthat edition 3, ggplot2 (already in Suggests), Python 3 for the catalog scripts.

## Global Constraints

- The numerical code is internal, in `R/logit-calibration.R`, with no export, no `NAMESPACE` change and no `man/` change; any roxygen added is Rd markup (`\code{}`), not markdown.
- The template is `inst/templates/10_descriptive/lg.qmd`, unqualified, scaffolded by `add_job("lg", subject, type)`; its defaults are `SUBJECT <- "dead"` and `TYPE <- "calibration"`.
- The template has exactly one `^SUBJECT\s+<- ` line and one `^TYPE\s+<- ` line.
- An `EDIT:` marker appears only inside a chunk whose label starts with `edit-`; the optional settings (`JOIN` and its three companions, `SAVE_FIGURES`, `FIGURES`) carry none.
- The template carries no study identifier, and no output, raw or digested, holds a patient identifier: every table and figure is per group.
- Settings and defaults, from the spec: `EVENT <- "dead"`, `LINK <- "hazard"` (or `"logit"`), `TIME <- "iv_dead"` (read only by `"hazard"` and by `INTERVAL`), `INTERVAL <- NULL` (or `c(start, end)`), `DATASET <- "built"`, `ID <- "ccfid"`, `WHERE <- NULL`.
- `INTERVAL = c(start, end)` follows the SAS constant-phase template: patients whose follow-up ended before `start` are left out and counted; every other patient is censored at `end` (no event after it counts, and the follow-up caps there); under `"hazard"` the time at risk is `pmin(TIME, end) - start`; under `"logit"` the same patients are kept and an event counts only inside the window. The counts of the patients left out and of the patients censored are reported.
- `VARIABLES` is a data frame, one row per covariate, with columns `name`, `kind` (`"continuous"` default, or `"ordinal"`), `groups` (default 5), `constant` (default the median to one significant figure), `shift` (default 0), `label` (default the name) and `chosen` (default `NA`).
- The six scales and their ids, in panel order: `raw` (`mean`), `log` (`log(mean + shift)`), `inverse` (`c / mean`), `inverse_squared` (`(c / mean)^2`), `squared` (`(mean / c)^2`), `exp` (`exp(mean / c)`).
- Grouping is `PROC RANK GROUPS=G`: group `floor(rank * G / (n + 1))`, rank averaged over ties; an ordinal covariate takes each level as a group.
- A group whose link value cannot be computed keeps its row with a missing link and a note; a scale that cannot be computed is drawn empty with a note.
- The saved choices are `lg-scales.rds`, a table of `variable`, `chosen`, `term`, `constant` and `shift`; a blank `chosen`, or one naming a scale that cannot be computed, warns in a draft and stops a final render (`HVTI_TEMPLATE_STRICT`).
- Each figure is saved as PNG and PDF through `.save_figure()`, via the template's `save_figure()` wrapper, under `SAVE_FIGURES` and `FIGURES`; the file stem is `lg-<covariate>`.
- `.lintr` gains a key for the file `inst/templates/10_descriptive/lg.qmd`, never for a directory.
- Lines are at most 135 characters (`.lintr`).
- US spelling (`tools/check-us-spelling.sh`: "labeled", "gray", "color"), no em-dashes anywhere (code, comments, docs, commit messages, PR text), and no absolute local path (`tools/check-no-site-identifiers.sh`).
- A test that evaluates a job twice in one session calls `local_child_chunks()` first; the no-identifier scan drops `data:` URIs and matches whole tokens.
- News fragment `news/feat-lg.md`; `NEWS.md` is not edited and `Version:` in `DESCRIPTION` is untouched.
- No new dependency: ggplot2 is already in Suggests, and the job does not use hvtiPlotR, so no floor moves.
- Tests run with `NOT_CRAN=true`, one file per command.
- Never install into the user's R library. Everything installs into the scratch library `$SCRATCH/lib-lg`; every command spells it out in full.
- Branch `feat/lg` from `origin/main`. Never push to `main`.

---

## File Structure

| file | create / modify | responsibility |
|---|---|---|
| `R/logit-calibration.R` | create | `.lg_groups()`, `.lg_event()`, `.lg_table()`, `.lg_constant()`, `.lg_scales()`, `.lg_term()`, `.lg_rsq()`, `.lg_plot()`, `.lg_variables()`, `.lg_interval()`, `.lg_choices()`, `.lg_predictors()` |
| `inst/templates/10_descriptive/lg.qmd` | create | the template |
| `inst/extdata/templates.json` | modify (the `lg` row) | the `lg` row becomes shipped, named "Logit calibration" |
| `dev/specs/2026-08-29-template-conversion-roadmap.md` | regenerate | rendered by `roadmap_render.py`, never hand-edited |
| `.lintr` | modify | the file key for `lg.qmd` |
| `tests/testthat/test-logit-calibration.R` | create | unit tests of every internal |
| `tests/testthat/test-lg.R` | create | the template: scaffold, settings, tables and figures, choices, interval, render, no identifiers |
| `tests/testthat/helper-lm.R` | modify (append) | `lg_data()`, `lg_chosen_variables`, `lg_fixture()`; kept in this file so `object_usage_linter` sees the `lm_*` helpers they call |
| `tests/testthat/test-template-provenance.R` | modify | template count 32 to 33; `lg` among the templates with a local dataset choice |
| `tests/testthat/test-template-data-routes.R` | modify | `lg.qmd` among the one-row-per-patient templates; readers 21 to 22 |
| `tests/testthat/test-template-figures.R` | modify | `lg` among the figure templates, with its figure stem |
| `dev/gallery/family-descriptive.R` | modify | the `lg` job |
| `dev/gallery/notes.json` | modify | the `lg` note |
| `inst/templates/README.md` | modify | the template table and the figure-name table |
| `news/feat-lg.md` | create | the NEWS entry |

---

## Task 0: Branch and scratch library

**Files:** none in the repo.

**Interfaces:** produces the scratch library `LIB` (`$SCRATCH/lib-lg`) holding hvtiRutilities 1.5.1, hvtiRdatabuild and hvtiRpropensity from their `origin/main`, and this branch's hvtiRtemplates. ggplot2 is read from the user library, which `R_LIBS` still searches after `LIB`. A folder of the same kind, `lib-lpmirror`, may be copied instead of rebuilding the three dependencies.

- [ ] **Step 1: Set the two locations, then branch from origin/main.** `REPOS` is the folder holding the hvtiR clones, and `SCRATCH` a scratch folder outside every repo. Every later command uses both.

```bash
export REPOS=<folder holding the hvtiR clones>
export SCRATCH=<scratch folder outside any repo>
cd $REPOS/hvtiRtemplates
git fetch origin
git checkout -b feat/lg origin/main
```

- [ ] **Step 2: Export the three dependencies from their local clones and install them into LIB.**

```bash
mkdir -p $SCRATCH/lib-lg
mkdir -p $SCRATCH/src-lg
git -C $REPOS/hvtiRutilities fetch --tags origin
git -C $REPOS/hvtiRutilities archive --prefix=hvtiRutilities/ v1.5.1 | tar -x -C $SCRATCH/src-lg
git -C $REPOS/hvtiRdatabuild fetch origin
git -C $REPOS/hvtiRdatabuild archive --prefix=hvtiRdatabuild/ origin/main | tar -x -C $SCRATCH/src-lg
git -C $REPOS/hvtiRpropensity fetch origin
git -C $REPOS/hvtiRpropensity archive --prefix=hvtiRpropensity/ origin/main | tar -x -C $SCRATCH/src-lg
R_LIBS=$SCRATCH/lib-lg R CMD INSTALL --no-docs -l $SCRATCH/lib-lg $SCRATCH/src-lg/hvtiRutilities $SCRATCH/src-lg/hvtiRdatabuild $SCRATCH/src-lg/hvtiRpropensity
```

- [ ] **Step 3: Install this branch's hvtiRtemplates into LIB.** A Quarto render calls `hvtiRtemplates:::` internals from the installed package, not from `load_all()`, so this command is rerun before every render below (Tasks 9, 10 and 11 say where). The installed package must be reached by an absolute `R_LIBS`: a relative one is lost when Quarto starts its own R.

```bash
cd $REPOS/hvtiRtemplates
R_LIBS=$SCRATCH/lib-lg R CMD INSTALL --no-docs -l $SCRATCH/lib-lg .
```

- [ ] **Step 4: Verify the versions the gates run against.**

```bash
R_LIBS=$SCRATCH/lib-lg Rscript -e 'for (p in c("hvtiRutilities", "hvtiRdatabuild", "hvtiRpropensity", "ggplot2", "hvtiRtemplates")) cat(p, as.character(packageVersion(p)), "\n")'
```

Expected: `hvtiRutilities 1.5.1`, `hvtiRdatabuild` at least `0.2.3` (0.2.4 on 2026-10-11), `hvtiRpropensity` at least `0.1.10` (0.1.11 on 2026-10-11), `ggplot2` 3.5 or later (4.0.3 installed), `hvtiRtemplates` the DESCRIPTION version of this branch. If ggplot2 is missing, stop and ask: do not install it into the user library.

- [ ] **Step 5: Baseline.** Record the suite state before any change, so a later failure can be told from a pre-existing one:

```bash
for f in tests/testthat/test-*.R; do echo "== $f"; R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e "devtools::load_all(quiet=TRUE); testthat::test_file('$f')" 2>&1 | grep -E "FAIL [0-9]+ \| WARN [0-9]+ \| SKIP [0-9]+ \| PASS [0-9]+"; done > $SCRATCH/lg-baseline.txt
```

Expected: FAIL 0 everywhere, except any failure `origin/main` already carries with LIB's hvtiRdatabuild (the lp-mirror plan recorded one in `test-job-data.R`). `test-rf-templates.R` may show a nonzero WARN locally from varPro notices CI muffles; record it. No commit in this task.

---

## Task 1: `.lg_groups()`, the PROC RANK grouping

**Files:**
- Create: `R/logit-calibration.R`
- Create: `tests/testthat/test-logit-calibration.R`

**Interfaces:**
- Produces `.lg_groups(x, groups = 5L, kind = c("continuous", "ordinal"))`, returning `list(group, missing)`: `group` is an integer vector the length of `x`, numbered from 0, `NA` where `x` is missing; `missing` is the count of missing values. Continuous: `floor(rank(x, ties = "average") * groups / (n + 1))`. Ordinal: the position of each value among the observed levels, minus 1; `groups` is not used. Stops with `x must be numeric.`, `x has no value to group: every value is missing.` or `groups must be a whole number of at least 2.`.
- Consumed by: `.lg_table()` (Task 2).

- [ ] **Step 1: Write the failing test.** Create `tests/testthat/test-logit-calibration.R`. The fixture is worked by hand in the test's own comment: the tied 3s, 6s and 12s are what separates averaging ties from ranking them in order.

```r
# The numerical core of the lg template: the internals in R/logit-calibration.R.
# The design is dev/specs/2026-10-11-lg-template-design.md; its section 5 lists
# what these tests cover. All data are synthetic.

test_that(".lg_groups() reproduces PROC RANK GROUPS=5 on a 12-row fixture with ties", {
  # PROC RANK GROUPS=G assigns floor(rank * G / (n + 1)), the rank averaged over
  # ties. Worked by hand for n = 12 and G = 5, so n + 1 = 13:
  #
  #   sorted value        1    3    3    4    6    6    6    9   10    12    12   20
  #   rank (ties mean)    1  2.5  2.5    4    6    6    6    8    9  10.5  10.5   12
  #   rank * 5 / 13    0.38 0.96 0.96 1.54 2.31 2.31 2.31 3.08 3.46  4.04  4.04 4.62
  #   group               0    0    0    1    2    2    2    3    3     4     4    4
  #
  # The tied 3s, 6s and 12s each share a group. A rule that ranks ties in order
  # would split them: the second 3 would be rank 3 and fall in group 1.
  x <- c(12, 3, 20, 6, 1, 9, 6, 12, 4, 10, 3, 6)
  got <- hvtiRtemplates:::.lg_groups(x, groups = 5L)
  expect_identical(got$group, c(4L, 0L, 4L, 2L, 0L, 3L, 2L, 4L, 1L, 3L, 0L, 2L))
  expect_identical(got$missing, 0L)
  expect_identical(as.integer(table(got$group)), c(3L, 1L, 3L, 2L, 3L))
})

test_that(".lg_groups() puts a rank that makes the product a whole number in the higher group", {
  # n = 9, G = 5, so n + 1 = 10 and rank 2 gives exactly 2 * 5 / 10 = 1: group 1, not 0.
  got <- hvtiRtemplates:::.lg_groups(1:9, groups = 5L)
  expect_identical(got$group, c(0L, 1L, 1L, 2L, 2L, 3L, 3L, 4L, 4L))
})

test_that(".lg_groups() drops a missing covariate and counts it, without moving the other groups", {
  x <- c(12, 3, 20, 6, 1, 9, 6, 12, 4, 10, 3, 6)
  got <- hvtiRtemplates:::.lg_groups(c(x, NA, NA), groups = 5L)
  expect_identical(got$group, c(4L, 0L, 4L, 2L, 0L, 3L, 2L, 4L, 1L, 3L, 0L, 2L, NA, NA))
  expect_identical(got$missing, 2L)
})

test_that(".lg_groups() takes each observed level of an ordinal covariate as a group", {
  # %logitgr: the covariate is its own grouping, so `groups` has no say.
  x <- c(3, 1, 2, 2, 3, 3, 1, NA)
  got <- hvtiRtemplates:::.lg_groups(x, groups = 5L, kind = "ordinal")
  expect_identical(got$group, c(2L, 0L, 1L, 1L, 2L, 2L, 0L, NA))
  expect_identical(got$missing, 1L)
  # A level that is absent leaves no empty group: levels 1, 2 and 4 are groups 0, 1 and 2.
  expect_identical(hvtiRtemplates:::.lg_groups(c(4, 1, 2), kind = "ordinal")$group, c(2L, 0L, 1L))
})

test_that(".lg_groups() stops on a covariate or group count it cannot use", {
  expect_error(hvtiRtemplates:::.lg_groups(c("a", "b")), "^x must be numeric")
  expect_error(hvtiRtemplates:::.lg_groups(c(NA_real_, NA_real_)), "^x has no value")
  expect_error(hvtiRtemplates:::.lg_groups(1:9, groups = 1L), "^groups must be a whole number of at least 2")
  expect_error(hvtiRtemplates:::.lg_groups(1:9, groups = 2.5), "^groups must be a whole number of at least 2")
  expect_error(hvtiRtemplates:::.lg_groups(1:9, groups = NA_integer_), "^groups must be a whole number of at least 2")
  # The count is not checked for an ordinal covariate, which does not use it.
  expect_identical(hvtiRtemplates:::.lg_groups(1:3, groups = NA, kind = "ordinal")$group, 0:2)
})
```

- [ ] **Step 2: Run it.**

```bash
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-logit-calibration.R")'
```

Expected FAIL: `object '.lg_groups' not found` on every test; `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 0 ]`.

- [ ] **Step 3: Implement.** Create `R/logit-calibration.R`:

```r
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
```

- [ ] **Step 4: Run.** Same command. Expected PASS: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 15 ]`.

- [ ] **Step 5: Commit.**

```bash
git add R/logit-calibration.R tests/testthat/test-logit-calibration.R
git commit -m "Add .lg_groups(), the PROC RANK grouping of the lg template

Group floor(rank * G / (n + 1)) with ties averaged, as PROC RANK GROUPS=G
assigns it, or one group per level for an ordinal covariate. Tested on a
12-row fixture with ties worked by hand.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Mutation check.** Each mutation must turn the tests red; restore after each.

```bash
sed -i '' 's/ties.method = "average"/ties.method = "first"/' R/logit-calibration.R
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-logit-calibration.R")' | grep "FAIL"
git checkout -- R/logit-calibration.R
sed -i '' 's/\* groups \/ (sum(seen) + 1)/* groups \/ sum(seen)/' R/logit-calibration.R
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-logit-calibration.R")' | grep "FAIL"
git checkout -- R/logit-calibration.R
```

Expected: `[ FAIL 3 | ... ]` (ties ranked in order split the tied groups) and `[ FAIL 4 | ... ]` (dividing by n instead of n + 1 moves the groups). `git status --short` is clean afterwards.

---

## Task 2: `.lg_table()`, the links and the missing-link notes

**Files:**
- Modify: `R/logit-calibration.R` (append)
- Modify: `tests/testthat/test-logit-calibration.R` (append)

**Interfaces:**
- Produces `.lg_event(event)`: a logical becomes 0/1; stops with `event must be coded 0 and 1 (or TRUE and FALSE), 1 for an event.` on anything else.
- Produces `.lg_table(x, event, time = NULL, groups = 5L, kind = c("continuous", "ordinal"), link = c("logit", "hazard"))`: a data frame, one row per observed group, with columns `group` (1, 2, ... in order), `mean`, `min`, `max`, `n` (patients with an event value), `events`, `rate` and `link`. `logit`: `rate = events / n`, `link = log(rate / (1 - rate))`. `hazard`: `rate = events / sum(time)`, `link = log(rate)`. A group whose link cannot be computed has `link` `NA` and a note. Attributes: `notes` (character, one `Group k (n = , events = ): <reason>. The point is left blank.` for each), and `dropped` (a named integer `c(covariate, follow_up, event)`). A patient with no covariate value, or under `hazard` no follow-up, is left out before ranking; a patient with no event value is ranked but counted in neither `n` nor `events`, as in SAS. Stops on a length mismatch, a missing `time` under `hazard`, a non-numeric or negative `time`.
- Consumed by: `.lg_scales()` input (Task 3), `.lg_plot()` (Task 4), the template (Task 7).

- [ ] **Step 1: Write the failing tests.** Append to `tests/testthat/test-logit-calibration.R`. The fixture reuses the 12-row grouping fixture; the group table in its comment is worked by hand.

```r
# The 12-row fixture of the grouping test, with an event and a follow-up time
# for each patient. Its five groups are, in order:
#
#   group  x values    patients (positions)  events  follow-up
#     1    1, 3, 3     5, 2, 11              1       1 + 1 + 5 = 7
#     2    4           9                     0       6
#     3    6, 6, 6     4, 7, 12              2       3 + 2 + 3 = 8
#     4    9, 10       6, 10                 1       1 + 4 = 5
#     5    12, 12, 20  1, 8, 3                3       2 + 2 + 4 = 8
lg_fixture <- function() {
  list(
    x = c(12, 3, 20, 6, 1, 9, 6, 12, 4, 10, 3, 6),
    event = c(1L, 0L, 1L, 1L, 0L, 0L, 0L, 1L, 0L, 1L, 1L, 1L),
    time = c(2, 1, 4, 3, 5, 1, 2, 2, 6, 4, 1, 3)
  )
}

test_that(".lg_table() gives one row per group with the mean, range, counts and the logit", {
  f <- lg_fixture()
  tab <- hvtiRtemplates:::.lg_table(f$x, f$event, groups = 5L, link = "logit")
  expect_named(tab, c("group", "mean", "min", "max", "n", "events", "rate", "link"))
  expect_identical(tab$group, 1:5)
  expect_equal(tab$mean, c(7 / 3, 4, 6, 9.5, 44 / 3))
  expect_equal(tab$min, c(1, 4, 6, 9, 12))
  expect_equal(tab$max, c(3, 4, 6, 10, 20))
  expect_identical(tab$n, c(3L, 1L, 3L, 2L, 3L))
  expect_identical(tab$events, c(1L, 0L, 2L, 1L, 3L))
  expect_equal(tab$rate, c(1 / 3, 0, 2 / 3, 1 / 2, 1))
  # log(p / (1 - p)): log(1/2), then undefined for a rate of 0, log(2), 0, and undefined for a rate of 1.
  expect_equal(tab$link, c(log(0.5), NA, log(2), 0, NA))
  expect_identical(attr(tab, "dropped"), c(covariate = 0L, follow_up = 0L, event = 0L))
})

test_that(".lg_table() with the hazard link is the log of events over summed follow-up", {
  f <- lg_fixture()
  tab <- hvtiRtemplates:::.lg_table(f$x, f$event, f$time, groups = 5L, link = "hazard")
  expect_identical(tab$events, c(1L, 0L, 2L, 1L, 3L))
  expect_equal(tab$rate, c(1 / 7, 0, 2 / 8, 1 / 5, 3 / 8))
  # log(events / sum(time)); no events in group 2, so no log.
  expect_equal(tab$link, c(log(1 / 7), NA, log(2 / 8), log(1 / 5), log(3 / 8)))
})

test_that("a group whose link cannot be computed keeps its row, blank, and is named in a note", {
  f <- lg_fixture()
  tab <- hvtiRtemplates:::.lg_table(f$x, f$event, groups = 5L, link = "logit")
  expect_identical(nrow(tab), 5L)
  notes <- attr(tab, "notes")
  expect_length(notes, 2L)
  expect_match(notes[[1L]], "^Group 2 [(]n = 1, events = 0[)]: no patient had the event, so the rate is 0 and its logit is undefined")
  expect_match(notes[[2L]], paste0("^Group 5 [(]n = 3, events = 3[)]: every patient had the event, ",
                                   "so the rate is 1 and its logit is undefined"))
  expect_match(notes, "The point is left blank[.]$", all = TRUE)
  haz <- hvtiRtemplates:::.lg_table(f$x, f$event, f$time, groups = 5L, link = "hazard")
  expect_match(attr(haz, "notes"), "^Group 2 [(]n = 1, events = 0[)]: no patient had the event, so the hazard rate is 0")
  expect_length(attr(haz, "notes"), 1L)
  # A fully defined table has no note.
  expect_identical(attr(hvtiRtemplates:::.lg_table(f$x, rep(c(1L, 0L), 6L), groups = 2L), "notes"), character(0))
})

test_that(".lg_table() drops a missing covariate or follow-up and counts it, and leaves an unknown event out of n", {
  f <- lg_fixture()
  # Two more patients: one without the covariate, one without follow-up. A patient without an
  # event value is still ranked (PROC SUMMARY's N counts the event, not the covariate) but is
  # in neither n nor events.
  x <- c(f$x, NA, 5, 7)
  event <- c(f$event, 1L, 1L, NA)
  time <- c(f$time, 3, NA, 2)
  tab <- hvtiRtemplates:::.lg_table(x, event, time, groups = 5L, link = "hazard")
  expect_identical(attr(tab, "dropped"), c(covariate = 1L, follow_up = 1L, event = 1L))
  # 13 patients are ranked, so n + 1 = 14 and the groups move; the patient with x = 7 has no event.
  expect_identical(sum(tab$n), 12L)
  expect_identical(sum(tab$events), 7L)
  # The logit link does not need follow-up, so a missing time is not dropped.
  tab <- hvtiRtemplates:::.lg_table(x, event, time, groups = 5L, link = "logit")
  expect_identical(attr(tab, "dropped"), c(covariate = 1L, follow_up = 0L, event = 1L))
  expect_identical(sum(tab$n), 13L)
  expect_identical(sum(tab$events), 8L)
})

test_that(".lg_table() takes each level of an ordinal covariate as a group", {
  tab <- hvtiRtemplates:::.lg_table(c(1, 1, 2, 2, 2, 3, 3), c(0L, 1L, 0L, 1L, 1L, 1L, 1L), kind = "ordinal")
  expect_equal(tab$mean, 1:3)
  expect_identical(tab$n, c(2L, 3L, 2L))
  expect_equal(tab$link, c(0, log(2), NA))
})

test_that(".lg_table() stops on an event, follow-up or length it cannot use", {
  f <- lg_fixture()
  expect_error(hvtiRtemplates:::.lg_table(f$x, f$event + 1L), "^event must be coded 0 and 1")
  expect_error(hvtiRtemplates:::.lg_table(f$x, rep(c("yes", "no"), 6L)), "^event must be coded 0 and 1")
  expect_error(hvtiRtemplates:::.lg_table(f$x, f$event[-1L]), "^x and event must be the same length")
  expect_error(hvtiRtemplates:::.lg_table(f$x, f$event, link = "hazard"), "^link = \"hazard\" needs time")
  expect_error(hvtiRtemplates:::.lg_table(f$x, f$event, f$time[-1L], link = "hazard"), "^time must be numeric")
  expect_error(hvtiRtemplates:::.lg_table(f$x, f$event, replace(f$time, 2L, -1), link = "hazard"),
               "^time holds 1 negative value")
  # A logical event is 1 and 0.
  expect_identical(hvtiRtemplates:::.lg_table(f$x, f$event == 1L)$events, c(1L, 0L, 2L, 1L, 3L))
})
```

- [ ] **Step 2: Run them.** Same command as Task 1. Expected FAIL: `object '.lg_table' not found`; `[ FAIL 6 | WARN 0 | SKIP 0 | PASS 15 ]`.

- [ ] **Step 3: Implement.** Append to `R/logit-calibration.R`:

```r
# An event as 0 and 1. A logical is read as 1 for TRUE; anything else that is not 0, 1 or
# missing stops, so a column coded 1 and 2 does not become a rate of 1.5.
.lg_event <- function(event) {
  if (is.logical(event)) event <- as.integer(event)
  if (!is.numeric(event) || !all(event[!is.na(event)] %in% c(0, 1))) {
    stop("event must be coded 0 and 1 (or TRUE and FALSE), 1 for an event.", call. = FALSE)
  }
  event
}

# One row per group: the covariate's mean, minimum and maximum, the patients with
# an event value (n), their events, the event rate and its value on the link scale.
#   logit:  rate = events / n, link = log(rate / (1 - rate))
#   hazard: rate = events / sum(time), link = log(rate), the constant-hazard
#           rate %logit calls with cox=1 (events per unit of follow-up).
# A patient with no covariate value, or under "hazard" no follow-up, is left out
# before the groups are formed, as %logit deletes them. A patient with no event
# value is ranked with the rest, as in SAS, but counts in neither n nor events.
# A group whose link cannot be computed (a rate of 0 or 1, or no events under
# "hazard") keeps its row with a missing link and is named in attr(, "notes").
# attr(, "dropped") counts the patients without a covariate, without follow-up
# and without an event value.
.lg_table <- function(x, event, time = NULL, groups = 5L, kind = c("continuous", "ordinal"),
                      link = c("logit", "hazard")) {
  kind <- match.arg(kind)
  link <- match.arg(link)
  hazard <- identical(link, "hazard")
  if (length(event) != length(x)) stop("x and event must be the same length.", call. = FALSE)
  event <- .lg_event(event)
  if (hazard) {
    if (is.null(time)) stop("link = \"hazard\" needs time, the follow-up of each patient.", call. = FALSE)
    if (!is.numeric(time) || length(time) != length(x)) {
      stop("time must be numeric, one value for each patient.", call. = FALSE)
    }
    negative <- sum(time < 0, na.rm = TRUE)
    if (negative) {
      stop("time holds ", negative, " negative value", if (negative > 1L) "s", ": follow-up cannot be negative.",
           call. = FALSE)
    }
  }
  keep <- !is.na(x) & (if (hazard) !is.na(time) else TRUE)
  dropped <- c(covariate = sum(is.na(x)), follow_up = if (hazard) sum(!is.na(x) & is.na(time)) else 0L,
               event = sum(keep & is.na(event)))
  x <- x[keep]
  event <- event[keep]
  follow_up <- if (hazard) time[keep]
  rows <- split(seq_along(x), .lg_groups(x, groups, kind)$group)
  n <- vapply(rows, function(i) sum(!is.na(event[i])), integer(1L), USE.NAMES = FALSE)
  events <- vapply(rows, function(i) as.integer(sum(event[i], na.rm = TRUE)), integer(1L), USE.NAMES = FALSE)
  total <- if (hazard) vapply(rows, function(i) sum(follow_up[i]), numeric(1L), USE.NAMES = FALSE)
  defined <- if (hazard) events > 0L & total > 0 else events > 0L & events < n
  rate <- if (hazard) events / total else events / n
  rate[!is.finite(rate)] <- NA_real_
  value <- rep(NA_real_, length(rows))
  value[defined] <- if (hazard) log(rate[defined]) else log(rate[defined] / (1 - rate[defined]))
  out <- data.frame(
    group = seq_along(rows),
    mean = vapply(rows, function(i) mean(x[i]), numeric(1L), USE.NAMES = FALSE),
    min = vapply(rows, function(i) min(x[i]), numeric(1L), USE.NAMES = FALSE),
    max = vapply(rows, function(i) max(x[i]), numeric(1L), USE.NAMES = FALSE),
    n = n, events = events, rate = rate, link = value
  )
  why <- function(k) {
    if (hazard) {
      if (events[[k]] == 0L) return("no patient had the event, so the hazard rate is 0 and its log is undefined")
      return("the follow-up time sums to 0, so the hazard rate is undefined")
    }
    if (n[[k]] == 0L) return("no patient has an event value, so there is no rate")
    if (events[[k]] == 0L) return("no patient had the event, so the rate is 0 and its logit is undefined")
    "every patient had the event, so the rate is 1 and its logit is undefined"
  }
  attr(out, "notes") <- vapply(which(!defined), function(k) {
    paste0("Group ", k, " (n = ", n[[k]], ", events = ", events[[k]], "): ", why(k), ". The point is left blank.")
  }, character(1L))
  attr(out, "dropped") <- dropped
  out
}
```

- [ ] **Step 4: Run.** Expected PASS: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 52 ]`.

- [ ] **Step 5: Commit.**

```bash
git add R/logit-calibration.R tests/testthat/test-logit-calibration.R
git commit -m "Add .lg_table(), the grouped event rate on the logit or hazard link

One row per group with its mean, range, counts, rate and link value. A group
whose link cannot be computed keeps its row, blank, and is named in a note,
as SAS left a missing point without a word.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Mutation check.** Two mutations, each restored.

```bash
sed -i '' 's|log(rate\[defined\] / (1 - rate\[defined\]))|log(rate[defined])|' R/logit-calibration.R
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-logit-calibration.R")' | grep "FAIL"
git checkout -- R/logit-calibration.R
sed -i '' 's|^  attr(out, "notes") <- |  out <- out[defined, ]\n  attr(out, "notes") <- |' R/logit-calibration.R
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-logit-calibration.R")' | grep -E "FAIL|Maximum"
git checkout -- R/logit-calibration.R
```

Expected: `[ FAIL 2 | ... ]` (the logit is not the logit), then red with many failures (a dropped group is not a kept, blank row). `git status --short` is clean afterwards. If BSD `sed` wrote a literal `n` instead of a newline in the second, insert the line with an editor.

---

## Task 3: `.lg_scales()`, the terms and the constant rule

**Files:**
- Modify: `R/logit-calibration.R` (append)
- Modify: `tests/testthat/test-logit-calibration.R` (append)

**Interfaces:**
- Produces `.lg_scale_ids` (`c("raw", "log", "inverse", "inverse_squared", "squared", "exp")`).
- Produces `.lg_constant(x, name = "x")`: `signif(median(x, na.rm = TRUE), 1)`. Stops with ``` `name` has no value to take a median of. ``` for an all-missing `x` and with `The median of `name` rounds to 0, so there is no default constant: set constant for it in VARIABLES.` when the rounded median is 0.
- Produces `.lg_scales(mean, constant, shift = 0)`: a data frame of the six scales, one column each (named by `.lg_scale_ids`), one row per group. A scale that cannot be computed is `NA` in every row, and `attr(, "notes")` is a named character vector, named by scale id, saying why: `log` when any `mean + shift <= 0`, `inverse` and `inverse_squared` when any mean is 0, `exp` when `exp(mean / constant)` overflows. Stops with `mean must be numeric.`, `constant must be one finite number other than 0.` or `shift must be one finite number.`.
- Produces `.lg_term(name, scale, constant, shift = 0)`: the term string an `lm` job's `PREDICTORS` takes (`age`, `log(age)`, `log(age + 1)`, `I(50 / age)`, `I((50 / age)^2)`, `I((age / 50)^2)`, `I(exp(age / 50))`); a name that is not syntactic is backquoted.
- Consumed by: `.lg_plot()` (Task 4), `.lg_choices()` (Task 8), the template (Task 7).

- [ ] **Step 1: Write the failing tests.** Append to `tests/testthat/test-logit-calibration.R`. One test evaluates each term on the covariate and compares it with the scale, so the formula drawn is the formula that goes into the model, and checks lm's own `.check_job_columns()` and `reformulate()` accept it.

```r
test_that(".lg_scales() gives the six candidate scales of the group means", {
  m <- c(40, 50, 60, 80)
  s <- hvtiRtemplates:::.lg_scales(m, constant = 50)
  expect_named(s, c("raw", "log", "inverse", "inverse_squared", "squared", "exp"))
  expect_identical(nrow(s), 4L)
  expect_equal(s$raw, m)
  expect_equal(s$log, log(m))
  expect_equal(s$inverse, 50 / m)
  expect_equal(s$inverse_squared, (50 / m)^2)
  expect_equal(s$squared, (m / 50)^2)
  expect_equal(s$exp, exp(m / 50))
  expect_length(attr(s, "notes"), 0L)
  # The constant does not move the raw or log scales; the shift moves only the log.
  s2 <- hvtiRtemplates:::.lg_scales(m, constant = 100, shift = 1)
  expect_equal(s2$raw, m)
  expect_equal(s2$log, log(m + 1))
  expect_equal(s2$inverse, 100 / m)
  expect_equal(s2$squared, (m / 100)^2)
})

test_that("each scale's term is the formula an lm job's PREDICTORS can take, and it evaluates to the scale", {
  m <- c(40, 50, 60, 80)
  term <- hvtiRtemplates:::.lg_term
  expect_identical(term("age", "raw", 50), "age")
  expect_identical(term("age", "log", 50), "log(age)")
  expect_identical(term("age", "log", 50, shift = 1), "log(age + 1)")
  expect_identical(term("age", "log", 50, shift = -0.5), "log(age - 0.5)")
  expect_identical(term("age", "inverse", 50), "I(50 / age)")
  expect_identical(term("age", "inverse_squared", 50), "I((50 / age)^2)")
  expect_identical(term("age", "squared", 50), "I((age / 50)^2)")
  expect_identical(term("age", "exp", 50), "I(exp(age / 50))")
  # A constant is written as a number, never in exponent form, and a name that needs it is quoted.
  expect_identical(term("weight", "inverse", 0.0001), "I(0.0001 / weight)")
  expect_identical(term("bsa", "squared", 1.5), "I((bsa / 1.5)^2)")
  expect_identical(term("log age", "log", 50), "log(`log age`)")
  expect_error(term("age", "cubic", 50), "^scale must be one of raw, log, inverse")
  # Each term, evaluated on the covariate, is the scale: the same formula drawn in the figure
  # is the one that goes into the model. The strings evaluated are the ones built above.
  s <- hvtiRtemplates:::.lg_scales(m, constant = 50, shift = 1)
  for (id in names(s)) {
    got <- eval(parse(text = term("age", id, 50, shift = 1)), data.frame(age = m))
    expect_equal(got, s[[id]], info = id)
  }
  # And lm's own helpers accept them: reformulate() builds the model formula, and
  # .check_job_columns() finds the covariate inside each term.
  terms <- vapply(names(s), function(id) term("age", id, 50, shift = 1), "")
  d <- data.frame(age = m, outcome = c(0, 1, 0, 1))
  expect_s3_class(stats::reformulate(terms, response = "outcome"), "formula")
  expect_silent(hvtiRtemplates:::.check_job_columns(d, PREDICTORS = terms))
  expect_error(hvtiRtemplates:::.check_job_columns(d, PREDICTORS = term("weight", "inverse", 50)),
               "^PREDICTORS names a column this dataset does not have: weight")
})

test_that("a scale that cannot be computed is drawn empty, with a note, not left out", {
  # The log of a mean at or below the shift.
  s <- hvtiRtemplates:::.lg_scales(c(0, 1, 2), constant = 1)
  expect_identical(names(s), c("raw", "log", "inverse", "inverse_squared", "squared", "exp"))
  expect_true(all(is.na(s$log)))
  expect_match(attr(s, "notes")[["log"]], "^A group mean plus the shift is not positive [(]the smallest is 0[)]")
  # An inverse through zero: the scale is empty for the whole covariate, not just the group at 0.
  expect_true(all(is.na(s$inverse)) && all(is.na(s$inverse_squared)))
  expect_match(attr(s, "notes")[["inverse"]], "^A group mean is 0, so the constant over the mean is undefined")
  expect_match(attr(s, "notes")[["inverse_squared"]], "^A group mean is 0")
  expect_equal(s$raw, c(0, 1, 2))
  expect_equal(s$squared, c(0, 1, 4))
  expect_named(attr(s, "notes"), c("log", "inverse", "inverse_squared"))
  # The shift makes the log safe.
  safe <- hvtiRtemplates:::.lg_scales(c(0, 1, 2), constant = 1, shift = 1)
  expect_equal(safe$log, log(c(1, 2, 3)))
  expect_false("log" %in% names(attr(safe, "notes")))
  # An exponential that overflows.
  big <- hvtiRtemplates:::.lg_scales(c(1, 1000), constant = 1)
  expect_true(all(is.na(big$exp)))
  expect_match(attr(big, "notes")[["exp"]], "^The exponential of the mean over the constant overflows")
})

test_that(".lg_scales() stops on a constant, shift or mean it cannot use", {
  expect_error(hvtiRtemplates:::.lg_scales(c(1, 2), constant = 0), "^constant must be one finite number other than 0")
  expect_error(hvtiRtemplates:::.lg_scales(c(1, 2), constant = NA_real_), "^constant must be one finite number")
  expect_error(hvtiRtemplates:::.lg_scales(c(1, 2), constant = c(1, 2)), "^constant must be one finite number")
  expect_error(hvtiRtemplates:::.lg_scales(c(1, 2), constant = Inf), "^constant must be one finite number")
  expect_error(hvtiRtemplates:::.lg_scales(c(1, 2), constant = 1, shift = NA_real_), "^shift must be one finite number")
  expect_error(hvtiRtemplates:::.lg_scales(c("a", "b"), constant = 1), "^mean must be numeric")
})

test_that("the default constant is the covariate's median to one significant figure", {
  # The SAS jobs typed it by hand: 50 for an age, 80 for a weight.
  const <- hvtiRtemplates:::.lg_constant
  expect_identical(const(c(41, 52, 58, 61, 70)), 60)
  expect_identical(const(c(44, 47, 52, 55, 90)), 50)
  expect_identical(const(c(1, 2, 2, 2, 4, NA)), 2)
  expect_identical(const(c(0.031, 0.04, 0.041, 0.9)), 0.04)
  expect_identical(const(c(1200, 1300, 1900)), 1000)
  expect_error(const(c(NA_real_, NA_real_), "age"), "^`age` has no value")
  expect_error(const(c(0, 0, 0, 5), "los"), "^The median of `los` rounds to 0, so there is no default constant: set constant for it")
})
```

- [ ] **Step 2: Run them.** Expected FAIL: `object '.lg_scales' not found` and the like; `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 52 ]`.

- [ ] **Step 3: Implement.** Append to `R/logit-calibration.R`:

```r
# The six scales a covariate might enter a model on, with the id each is chosen
# by in VARIABLES$chosen. The order is the figure's panel order.
.lg_scale_ids <- c("raw", "log", "inverse", "inverse_squared", "squared", "exp")

.lg_one_number <- function(x) is.numeric(x) && length(x) == 1L && is.finite(x)

# The default scale constant: the covariate's median, rounded to one significant
# figure. The SAS jobs typed it by hand (50 for an age, 80 for a weight); it only
# sets the inverse and exponential scales to a readable range, so a round number
# near the middle of the data does the same work.
.lg_constant <- function(x, name = "x") {
  if (!any(!is.na(x))) stop("`", name, "` has no value to take a median of.", call. = FALSE)
  constant <- signif(stats::median(x, na.rm = TRUE), 1L)
  if (constant == 0) {
    stop("The median of `", name, "` rounds to 0, so there is no default constant: set constant for it in VARIABLES.",
         call. = FALSE)
  }
  constant
}

# The six scales of the group means, one column each and one row per group: raw
# is the mean, log is log(mean + shift), inverse is constant / mean, inverse_squared
# is that squared, squared is (mean / constant)^2 and exp is exp(mean / constant).
# A scale that cannot be computed is NA in every group, not only the group that
# breaks it: a line drawn through the other groups would look like a straight one.
# attr(, "notes") names why, by scale. The log of a mean at or below -shift, an
# inverse through a mean of 0 and an overflowing exponential are the cases.
.lg_scales <- function(mean, constant, shift = 0) {
  if (!is.numeric(mean)) stop("mean must be numeric.", call. = FALSE)
  if (!.lg_one_number(constant) || constant == 0) {
    stop("constant must be one finite number other than 0.", call. = FALSE)
  }
  if (!.lg_one_number(shift)) stop("shift must be one finite number.", call. = FALSE)
  out <- list(
    raw = mean,
    log = suppressWarnings(log(mean + shift)),
    inverse = constant / mean,
    inverse_squared = (constant / mean)^2,
    squared = (mean / constant)^2,
    exp = exp(mean / constant)
  )
  notes <- character()
  if (any(mean + shift <= 0)) {
    notes[["log"]] <- paste0("A group mean plus the shift is not positive (the smallest is ", format(min(mean + shift), digits = 3),
                             "), so the log is undefined. Set shift for this covariate in VARIABLES to move it above 0.")
  }
  if (any(mean == 0)) {
    notes[["inverse"]] <- "A group mean is 0, so the constant over the mean is undefined."
    notes[["inverse_squared"]] <- "A group mean is 0, so the constant over the mean is undefined."
  }
  if (any(!is.finite(out$exp))) {
    notes[["exp"]] <- "The exponential of the mean over the constant overflows. Set a larger constant for this covariate in VARIABLES."
  }
  for (id in names(notes)) out[[id]][] <- NA_real_
  out <- as.data.frame(out)
  attr(out, "notes") <- notes
  out
}

# A variable as a model term: backquoted when its name is not a syntactic one.
.lg_variable_term <- function(name) if (identical(make.names(name), name)) name else paste0("`", name, "`")

# A number as it is written in a term: never in exponent form, never padded.
.lg_number <- function(x) format(x, digits = 15L, scientific = FALSE, trim = TRUE)

# The term for one chosen scale, ready for an lm job's PREDICTORS. Evaluated on
# the covariate it gives the scale .lg_scales() draws, which the tests check.
.lg_term <- function(name, scale, constant, shift = 0) {
  if (!scale %in% .lg_scale_ids) {
    stop("scale must be one of ", paste(.lg_scale_ids, collapse = ", "), ".", call. = FALSE)
  }
  v <- .lg_variable_term(name)
  k <- .lg_number(constant)
  switch(scale,
    raw = v,
    log = if (shift == 0) paste0("log(", v, ")") else paste0("log(", v, if (shift < 0) " - " else " + ", .lg_number(abs(shift)), ")"),
    inverse = paste0("I(", k, " / ", v, ")"),
    inverse_squared = paste0("I((", k, " / ", v, ")^2)"),
    squared = paste0("I((", v, " / ", k, ")^2)"),
    exp = paste0("I(exp(", v, " / ", k, "))")
  )
}
```

- [ ] **Step 4: Run.** Expected PASS: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 112 ]`.

- [ ] **Step 5: Commit.**

```bash
git add R/logit-calibration.R tests/testthat/test-logit-calibration.R
git commit -m "Add .lg_scales(), .lg_term() and the default constant

The six candidate scales of a covariate's group means, the term an lm job's
PREDICTORS takes for each, and the median-to-one-figure constant that replaces
the SAS jobs' hand-typed 50 and 80. A scale that cannot be computed is empty
for the whole covariate, with a note.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Mutation check.** Two mutations, each restored.

```bash
sed -i '' 's|inverse_squared = (constant / mean)^2,|inverse_squared = constant / mean,|' R/logit-calibration.R
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-logit-calibration.R")' | grep "FAIL"
git checkout -- R/logit-calibration.R
sed -i '' 's|for (id in names(notes)) out\[\[id\]\]\[\] <- NA_real_|for (id in character()) out[[id]][] <- NA_real_|' R/logit-calibration.R
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-logit-calibration.R")' | grep "FAIL"
git checkout -- R/logit-calibration.R
```

Expected: `[ FAIL 2 | ... ]` (the term and the scale disagree) and `[ FAIL 3 | ... ]` (an impossible scale is no longer blank). `git status --short` is clean afterwards.

---

## Task 4: `.lg_rsq()` and `.lg_plot()`, the six panels

**Files:**
- Modify: `R/logit-calibration.R` (append)
- Modify: `tests/testthat/test-logit-calibration.R` (append)

**Interfaces:**
- Produces `.lg_rsq(x, y, w)`: the R-squared of the weighted least-squares line of `y` on `x`, computed as the weighted squared correlation. `NA_real_` with fewer than three finite points, or with no spread in either variable.
- Produces `.lg_panel_labels` (named character, the panel titles by scale id).
- Produces `.lg_plot(table, scales, link = c("logit", "hazard"), title = NULL)`: a ggplot of `table$link` against each column of `scales`, six facets in `.lg_scale_ids` order with free x scales, points joined by a line, and a corner label: `R-squared = 0.97`, `R-squared not available`, or `Not computable` for an empty scale (drawn as an empty panel). No fitted line. The y label is `Log of events per unit of follow-up` for `"hazard"` and `Logit of the event rate` for `"logit"`. Stops with `table and scales must have one row for each group.`. Uses `rlang::sym()` instead of the `.data` pronoun, so the package imports nothing new.
- Consumed by: the template (Task 7).

- [ ] **Step 1: Write the failing tests.** Append to `tests/testthat/test-logit-calibration.R`. `lg_panel_text()` reads each panel's corner text from the built plot.

```r
test_that(".lg_rsq() is the R-squared of a straight line fitted with the group sizes as weights", {
  rsq <- hvtiRtemplates:::.lg_rsq
  # Exactly linear: 1, whatever the weights.
  expect_equal(rsq(c(1, 2, 3, 4), c(5, 7, 9, 11), c(10, 1, 1, 30)), 1)
  # Not linear: the weighted squared correlation, worked from its definition.
  x <- c(1, 2, 3, 4)
  y <- c(1, 2, 3, 10)
  w <- c(1, 1, 1, 100)
  mx <- sum(w * x) / sum(w)
  my <- sum(w * y) / sum(w)
  by_hand <- sum(w * (x - mx) * (y - my))^2 / (sum(w * (x - mx)^2) * sum(w * (y - my)^2))
  expect_equal(rsq(x, y, w), by_hand)
  # The weights matter: the unweighted fit of the same points is a different number.
  expect_gt(abs(rsq(x, y, rep(1, 4)) - rsq(x, y, w)), 0.01)
  # A group with no link value is left out of the fit.
  expect_equal(rsq(c(1, 2, 3, 4, 5), c(5, 7, NA, 11, 13), c(1, 1, 1, 1, 1)), 1)
  # Fewer than three points, or no spread, is not a fit worth reporting.
  expect_identical(rsq(c(1, 2), c(1, 2), c(1, 1)), NA_real_)
  expect_identical(rsq(c(1, 2, 3), c(4, NA, 6), c(1, 1, 1)), NA_real_)
  expect_identical(rsq(c(2, 2, 2), c(1, 2, 3), c(1, 1, 1)), NA_real_)
  expect_identical(rsq(c(1, 2, 3), c(4, 4, 4), c(1, 1, 1)), NA_real_)
})

# The text each panel of a figure carries, by panel.
lg_panel_text <- function(p) {
  layer <- which(vapply(p$layers, function(l) inherits(l$geom, "GeomText"), logical(1L)))
  stats::setNames(ggplot2::layer_data(p, layer)$label, ggplot2::layer_data(p, layer)$PANEL)
}

test_that(".lg_plot() draws one panel per scale and reports 1 for points exactly linear on one", {
  skip_if_not_installed("ggplot2")
  means <- c(1, 2, 4, 8, 16)
  tab <- data.frame(group = 1:5, mean = means, n = c(20L, 30L, 25L, 18L, 22L), link = 2 + 3 * log(means))
  scales <- hvtiRtemplates:::.lg_scales(means, constant = 8)
  p <- hvtiRtemplates:::.lg_plot(tab, scales, link = "hazard", title = "Age")
  expect_s3_class(p, "ggplot")
  built <- ggplot2::ggplot_build(p)
  expect_identical(nrow(built$layout$layout), 6L)
  expect_identical(levels(p$data$panel), c("Raw", "Log", "Inverse", "Inverse squared", "Squared", "Exponential"))
  text <- lg_panel_text(p)
  # Log is panel 2: the link is 2 + 3 log(mean), a straight line on that scale.
  expect_identical(unname(text[["2"]]), "R-squared = 1.00")
  expect_false(identical(unname(text[["1"]]), "R-squared = 1.00"))
  expect_equal(hvtiRtemplates:::.lg_rsq(scales$log, tab$link, tab$n), 1)
  expect_match(ggplot2::get_labs(p)$y, "events per unit of follow-up")
})

test_that(".lg_plot() draws a scale that cannot be computed as an empty panel that says so", {
  skip_if_not_installed("ggplot2")
  means <- c(0, 1, 2, 3)
  tab <- data.frame(group = 1:4, mean = means, n = c(10L, 10L, 10L, 10L), link = c(-1, -0.5, 0, 0.4))
  scales <- hvtiRtemplates:::.lg_scales(means, constant = 1)
  p <- hvtiRtemplates:::.lg_plot(tab, scales, link = "logit")
  text <- lg_panel_text(p)
  # Log (2), Inverse (3) and Inverse squared (4) are undefined at a mean of 0.
  expect_identical(unname(text[c("2", "3", "4")]), rep("Not computable", 3L))
  expect_match(text[["1"]], "^R-squared = ")
  # The empty panels are still drawn, so the six stay in their places, and the figure renders.
  expect_identical(nrow(ggplot2::ggplot_build(p)$layout$layout), 6L)
  png <- withr::local_tempfile(fileext = ".png")
  hvtiRtemplates:::.save_figure(p, png, width = 9, height = 6)
  expect_true(file.exists(png) && file.exists(sub("[.]png$", ".pdf", png)))
})

test_that(".lg_plot() leaves a blank link value as a gap and says when no R-squared is available", {
  skip_if_not_installed("ggplot2")
  means <- c(10, 20, 30)
  tab <- data.frame(group = 1:3, mean = means, n = c(5L, 5L, 5L), link = c(-1, NA, 1))
  p <- hvtiRtemplates:::.lg_plot(tab, hvtiRtemplates:::.lg_scales(means, constant = 20), link = "logit")
  expect_true(all(startsWith(lg_panel_text(p), "R-squared not available")))
  expect_error(hvtiRtemplates:::.lg_plot(tab[1:2, ], hvtiRtemplates:::.lg_scales(means, constant = 20)),
               "^table and scales must have one row for each group")
})
```

- [ ] **Step 2: Run them.** Expected FAIL: `object '.lg_rsq' not found` and `object '.lg_plot' not found`; `[ FAIL 4 | WARN 0 | SKIP 0 | PASS 112 ]`.

- [ ] **Step 3: Implement.** Append to `R/logit-calibration.R`:

```r
# The R-squared of a straight line through the group points, weighted by group
# size, which is the weighted squared correlation of x and y. It is guidance for
# "straightest", not a decision: a group of 3 patients should not pull the line
# as hard as a group of 300. NA when fewer than three groups have a link value,
# or when either side has no spread, because two points are always on a line.
# Computed from the correlation rather than summary(lm()), which warns on the
# exact fit this is most often asked to recognize.
.lg_rsq <- function(x, y, w) {
  ok <- is.finite(x) & is.finite(y) & w > 0
  if (sum(ok) < 3L || length(unique(x[ok])) < 2L || length(unique(y[ok])) < 2L) return(NA_real_)
  w <- w[ok]
  dx <- x[ok] - sum(w * x[ok]) / sum(w)
  dy <- y[ok] - sum(w * y[ok]) / sum(w)
  sum(w * dx * dy)^2 / (sum(w * dx^2) * sum(w * dy^2))
}

.lg_panel_labels <- c(raw = "Raw", log = "Log", inverse = "Inverse", inverse_squared = "Inverse squared",
                      squared = "Squared", exp = "Exponential")

# One panel per scale: the group link value against the group mean on that scale,
# the points joined by a line as the SAS plots did, and the weighted R-squared in
# the corner. A scale that cannot be computed is an empty panel that says so. No
# fitted line is drawn: the figure is for reading by eye, and the R-squared is
# its only aid. `table` is .lg_table()'s result and `scales` .lg_scales()'s.
.lg_plot <- function(table, scales, link = c("logit", "hazard"), title = NULL) {
  link <- match.arg(link)
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("The ggplot2 package is needed to draw the figure.", call. = FALSE)
  if (nrow(table) != nrow(scales)) stop("table and scales must have one row for each group.", call. = FALSE)
  ids <- .lg_scale_ids
  panel <- function(id) factor(rep(.lg_panel_labels[[id]], nrow(table)), levels = .lg_panel_labels)
  points <- do.call(rbind, lapply(ids, function(id) data.frame(panel = panel(id), x = scales[[id]], y = table$link)))
  rsq <- vapply(ids, function(id) .lg_rsq(scales[[id]], table$link, table$n), numeric(1L))
  empty <- vapply(ids, function(id) all(is.na(scales[[id]])), logical(1L))
  say <- data.frame(
    panel = factor(unname(.lg_panel_labels), levels = .lg_panel_labels),
    label = ifelse(empty, "Not computable",
                   ifelse(is.na(rsq), "R-squared not available", sprintf("R-squared = %.2f", rsq)))
  )
  # An empty panel has no x to scale on, so it is given the unit range.
  frame <- data.frame(panel = factor(unname(.lg_panel_labels)[empty], levels = .lg_panel_labels))
  blank <- if (nrow(frame)) {
    y <- range(table$link, finite = TRUE, na.rm = TRUE)
    data.frame(panel = rep(frame$panel, each = 2L), x = c(0, 1), y = if (all(is.finite(y))) y else c(0, 1))
  } else {
    data.frame(panel = factor(character(), levels = .lg_panel_labels), x = numeric(), y = numeric())
  }
  ylab <- if (identical(link, "hazard")) "Log of events per unit of follow-up" else "Logit of the event rate"
  ggplot2::ggplot(points, ggplot2::aes(x = !!rlang::sym("x"), y = !!rlang::sym("y"))) +
    ggplot2::geom_blank(data = blank) +
    ggplot2::geom_line(na.rm = TRUE, color = "gray45") +
    ggplot2::geom_point(na.rm = TRUE, size = 2) +
    ggplot2::geom_text(data = say, ggplot2::aes(label = !!rlang::sym("label")), x = -Inf, y = Inf, hjust = -0.1, vjust = 1.6,
                       size = 3.2, inherit.aes = FALSE) +
    ggplot2::facet_wrap("panel", ncol = 3L, scales = "free_x") +
    # Headroom, so the R-squared in the corner never sits on a point.
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0.05, 0.2))) +
    ggplot2::labs(title = title, x = "Group mean of the covariate, on the scale shown", y = ylab) +
    ggplot2::theme_bw() +
    ggplot2::theme(strip.background = ggplot2::element_rect(fill = "gray92"))
}
```

- [ ] **Step 4: Run.** Expected PASS: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 133 ]`.

- [ ] **Step 5: Look at one.** A test cannot say a figure reads well. Draw one on synthetic data and open it:

```bash
R_LIBS=$SCRATCH/lib-lg Rscript -e 'devtools::load_all(quiet=TRUE); set.seed(3); n <- 400; age <- round(rnorm(n, 60, 12)); t <- rexp(n, 1/6); ev <- rbinom(n, 1, plogis(-2 + 0.04 * (age - 60))); tab <- hvtiRtemplates:::.lg_table(age, ev, t, 5L, "continuous", "hazard"); sc <- hvtiRtemplates:::.lg_scales(tab$mean, 60); ggplot2::ggsave(file.path(Sys.getenv("SCRATCH"), "lg-check.png"), hvtiRtemplates:::.lg_plot(tab, sc, "hazard", "Age"), width = 9, height = 6, dpi = 100)'
```

Expected: six panels in two rows of three, titled Raw, Log, Inverse, Inverse squared, Squared and Exponential, five points joined by a line in each, an `R-squared = 0.xx` in the top left of each with clear space above the points.

- [ ] **Step 6: Commit.**

```bash
git add R/logit-calibration.R tests/testthat/test-logit-calibration.R
git commit -m "Add .lg_rsq() and .lg_plot(), the six-panel calibration figure

One panel for each candidate scale, the group link values joined by a line as
in SAS, and the R-squared of a straight line weighted by group size in the
corner. An impossible scale is an empty panel that says so.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Mutation check.** Two mutations, each restored.

```bash
sed -i '' 's|^  w <- w\[ok\]$|  w <- rep(1, sum(ok))|' R/logit-calibration.R
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-logit-calibration.R")' | grep "FAIL"
git checkout -- R/logit-calibration.R
sed -i '' 's|ifelse(empty, "Not computable",|ifelse(FALSE, "Not computable",|' R/logit-calibration.R
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-logit-calibration.R")' | grep "FAIL"
git checkout -- R/logit-calibration.R
```

Expected: `[ FAIL 2 | ... ]` for each (an unweighted fit is a different number; an empty panel no longer says so). `git status --short` is clean afterwards.

---

## Task 5: Catalog row, roadmap, lint key and the template skeleton

**Files:**
- Modify: `inst/extdata/templates.json` (the `"prefix": "lg"` row, near line 566)
- Regenerate: `dev/specs/2026-08-29-template-conversion-roadmap.md`
- Modify: `.lintr` (insert after the `dc-eda.qmd` key)
- Create: `inst/templates/10_descriptive/lg.qmd` (skeleton: front matter through the data chunks, and `provenance`)
- Modify: `tests/testthat/helper-lm.R` (append)
- Create: `tests/testthat/test-lg.R`
- Modify: `tests/testthat/test-template-provenance.R`, `tests/testthat/test-template-data-routes.R`

**Interfaces:**
- Produces the template's settings, all set once here and read by later tasks: `SUBJECT`, `TYPE`, `DATASET`, `ANALYSIS_SET`, `WHERE`, `ID`, `KEY`, `JOIN`, `JOIN_VARS`, `REDUCE`, `JOIN_KEY`, `EVENT`, `LINK`, `TIME`, `INTERVAL`, `VARIABLES`, `SAVE_FIGURES`, `FIGURES`; the closures `set_path(kind, file)` and `save_figure(plot, name, width, height, kind, linked)`; the objects `.in`, `.root`, `.cfg`, `job_data`, `d`, `.provenance_data`.
- Produces the chunk labels, in order: `setup`, `guard-edits`, `guard-partial`, `set`, `edit-study-choices`, `tbl-data`, `data-attrition`, `provenance`. Later tasks insert chunks between `data-attrition` and `provenance`.
- Produces the test helpers `lg_data(n = 400L)` (a synthetic cohort: `ccfid` seven-digit, `age`, `nyha`, `n_prior`, `dead`, `iv_dead`, `hdead`), `lg_chosen_variables` (the lines of a `VARIABLES` block, age with a scale chosen) and `lg_fixture(lines = character(), variables = lg_chosen_variables, data = lg_data(), .local_envir = parent.frame())`, returning `list(root, job)`: each `lines` element replaces the study-choice line starting with its setting's name, and `variables` is the lines of the whole `VARIABLES` data frame (`NULL` leaves the template's own).
- `add_job("lg", subject, type)` writes `<descriptive folder>/lg.<subject>.<type>.qmd`.

- [ ] **Step 1: Write the test helpers and the failing test.** Append to `tests/testthat/helper-lm.R`, at the end of the file:

```r
# lg: a study whose built dataset the lg job calibrates, and the job scaffolded
# and its markers worked. Kept in this file because it calls the lm_* helpers
# above, which object_usage_linter must see.

# Seven-digit identifiers that occur nowhere else, so a report that printed one
# would be caught. `dead` and `iv_dead` are a death and its follow-up in years,
# the risk rising with age and NYHA class; `hdead` is an in-hospital death, the
# binary event; `nyha` is the ordinal covariate; `n_prior` counts prior
# operations and is 0 for most patients, which breaks the log and the inverse.
lg_data <- function(n = 400L) {
  withr::local_seed(11)
  age <- round(stats::rnorm(n, 62, 12))
  nyha <- sample(1:4, n, replace = TRUE, prob = c(0.2, 0.4, 0.3, 0.1))
  t_death <- stats::rexp(n, exp(-3 + 0.03 * (age - 60) + 0.4 * (nyha - 2)))
  censor <- stats::runif(n, 1, 10)
  data.frame(
    ccfid = 8300000L + seq_len(n), age = age, nyha = nyha,
    n_prior = stats::rpois(n, 0.4),
    dead = as.integer(t_death <= censor), iv_dead = round(pmin(t_death, censor), 3) + 0.001,
    hdead = stats::rbinom(n, 1L, stats::plogis(-3 + 0.04 * (age - 60) + 0.5 * (nyha - 2)))
  )
}

# The VARIABLES the fixture's job calibrates unless a test gives others: age, with
# a scale chosen, so the job renders without the warning a blank choice raises.
lg_chosen_variables <- c(
  "VARIABLES <- data.frame(",
  "  name = c(\"age\"),",
  "  chosen = c(\"log\")",
  ")"
)

# A study with an lg job scaffolded into it. Each element of `lines` replaces the
# study-choice line that starts with its setting's name, as lp_fixture() does;
# `variables` is the lines of the whole VARIABLES data frame, since it runs over
# several, and NULL leaves the template's own. Returns the root and the job.
lg_fixture <- function(lines = character(), variables = lg_chosen_variables, data = lg_data(),
                       .local_envir = parent.frame()) {
  root <- lm_study(.local_envir = .local_envir, data = data)
  job <- add_job("lg", "dead", "calibration", dir = root)
  src <- gsub("EDIT:", "REVIEWED:", readLines(job, warn = FALSE), fixed = TRUE)
  for (line in lines) {
    key <- sub(" .*", "", line)
    src[grepl(paste0("^", key, " <- "), src)] <- line
  }
  if (!is.null(variables)) {
    at <- which(src == "VARIABLES <- data.frame(")
    end <- at + which(src[(at + 1L):length(src)] == ")")[[1L]]
    src <- c(src[seq_len(at - 1L)], variables, src[-seq_len(end)])
  }
  writeLines(src, job)
  list(root = root, job = job)
}
```

Create `tests/testthat/test-lg.R`:

```r
# lg: the logit calibration job. The design is
# dev/specs/2026-10-11-lg-template-design.md; its section 5 lists what these
# tests cover. The numerical core has its own tests in test-logit-calibration.R.
# All data are synthetic.

test_that("lg is a descriptive template that add_job() scaffolds, and its catalog row is shipped as Logit calibration", {
  tl <- template_list()
  row <- tl[tl$name == "lg", ]
  expect_identical(nrow(row), 1L)
  expect_identical(row$folder, "descriptive")
  expect_identical(row$call, "add_job(\"lg\", subject = \"dead\", type = \"calibration\")")
  root <- lm_study()
  job <- add_job("lg", "dead", "calibration", dir = root)
  expect_identical(basename(job), "lg.dead.calibration.qmd")
  expect_identical(normalizePath(dirname(job)), normalizePath(hvtiRutilities::study_dir("descriptive", root)))
  src <- readLines(job, warn = FALSE)
  expect_identical(grep("^SUBJECT\\s+<- ", src, value = TRUE), "SUBJECT <- \"dead\"")
  expect_identical(grep("^TYPE\\s+<- ", src, value = TRUE), "TYPE    <- \"calibration\"")
  catalog <- template_catalog()
  entry <- catalog[catalog$prefix == "lg", ]
  expect_identical(nrow(entry), 1L)
  expect_identical(entry$name, "Logit calibration")
  expect_identical(entry$status, "shipped")
  expect_true(is.na(entry$qualifier))
  expect_identical(entry$spec, "dev/specs/2026-10-11-lg-template-design.md")
  expect_identical(entry$downstream[[1L]], "lm")
})
```

- [ ] **Step 2: Run it.**

```bash
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lg.R")'
```

Expected FAIL: `add_job(): unknown template: lg. Available: ac, bc, ...`, and `nrow(row)` 0 with `folder` and `call` empty; `[ FAIL 4 | WARN 0 | SKIP 0 | PASS 0 ]`.

- [ ] **Step 3: Implement the catalog row.** In `inst/extdata/templates.json`, replace the `lg` row's fields from `"qualifier": null` through `"note": null,` with the block below; `sas_breadth_jobs`, `disposition` and `uses` stay as they are (`362`, `"scaffold"`, `[]`).

```json
      "qualifier": null,
      "name": "Logit calibration",
      "description": "Calibrates a continuous or ordinal covariate against an event: it groups the covariate, takes each group's event rate on a logit or constant-hazard scale, and plots it against six candidate scales of the covariate, so the analyst can pick the straightest and save the term for an lm job's PREDICTORS.",
      "folder": "descriptive",
      "family": "descriptive",
      "kind": "job",
      "status": "shipped",
      "batch": 4,
      "sas_breadth": 367,
      "r_exemplars": 0,
      "r_jobs": 0,
      "upstream": [],
      "downstream": [
        "lm"
      ],
      "workflows": [],
      "blocked_on": null,
      "spec": "dev/specs/2026-10-11-lg-template-design.md",
      "note": "A read-only survey on 2026-10-11 found 97% of 220 scanned SAS lg jobs calibrate a covariate against an event with %logit or %logitgr, not trends over time; no study has an R lg job. The 12 lg.trends jobs go to dc-trends.",
```

`r_exemplars` and `r_jobs` stay 0: no study has an R `lg` job yet. The `name` change from "Logit trends" is the spec's. `hvti_taxonomy()` comes from hvtiRutilities and still says "Logit trends"; that row is that package's, and no test here compares the two.

- [ ] **Step 4: Regenerate the roadmap.**

```bash
python3 dev/specs/artifacts/roadmap_render.py
git diff dev/specs/2026-08-29-template-conversion-roadmap.md
```

Expected: `rendered 65 template rows into 2026-08-29-template-conversion-roadmap.md`, and a diff of exactly two changed lines: `**65 templates in scope**, of which 33 exist on disk.` becomes `34` (the count is read from the catalog's shipped rows, so it moves now), and the `lg` row's status `queued` becomes `shipped`.

- [ ] **Step 5: Implement the lint key.** In `.lintr`, after the `"inst/templates/10_descriptive/dc-eda.qmd" = list(...)` entry, insert:

```r
    "inst/templates/10_descriptive/lg.qmd" = list(
      object_name_linter = Inf,
      commented_code_linter = Inf,
      object_usage_linter = Inf
    ),
```

- [ ] **Step 6: Implement the skeleton.** Create `inst/templates/10_descriptive/lg.qmd` with exactly this content:

````markdown
---
title: "Logit calibration"
format:
  html:
    theme: cosmo
    toc: true
    toc-location: left
    page-layout: full
    grid:
      body-width: 2000px
      sidebar-width: 250px
    toc-depth: 3
    code-fold: true
    df-print: default
    embed-resources: true
---

<!-- EDIT: name the SAS job this replaces (descriptive/lg.<outcome>, or the
     tp.lg.hdead or tp.lg.dead.constant template it was copied from) and say
     which event and which link it used. -->

Replaces `descriptive/lg.<outcome>`: say which.

An `lg` job decides which scale a covariate should enter a model on, before it
goes into `PREDICTORS` in an `lm` job. A model of an event rate on a covariate
assumes the rate is straight in the covariate on the link scale, and a covariate
that is skewed, or that acts through its inverse, breaks that quietly: the model
fits and reports a coefficient for a shape the data do not have. This job shows
the shape first.

For each covariate it ranks the patients into groups (usually five), takes the
event rate of each group on a link scale, and plots that against the covariate on
six candidate scales, so the analyst can pick the one that comes out straightest.
It replaces the SAS `%logit` macro, which ranked with `PROC RANK`, and
`%logitgr`, which took each level of an ordinal covariate as a group. The link is
the logit, `log(p / (1 - p))`, for a binary event, or, for time-related death, the
log of the constant hazard rate, `log(events / sum of follow-up)`, which is what
the SAS jobs called with `cox=1`. The R-squared in each panel is the weighted
straight-line fit of the groups, weighted by group size. It is guidance for
"straightest", not a decision: the choice goes in `chosen`, and the job saves it.

```{r}
#| label: setup
# unnumbered: loads packages only
# The study root is the nearest directory above this file holding _study.yml,
# so the job renders the same from the Render button, quarto render, or
# render_job(), at any depth, with no path in this document to edit.
.in <- knitr::current_input(dir = TRUE)
.root <- hvtiRtemplates:::.find_study_root(if (is.null(.in)) getwd() else dirname(.in))
.provenance_data <- list()
for (f in list.files(file.path(.root, "R"), pattern = "[.]R$", full.names = TRUE)) source(f)
suppressPackageStartupMessages(library(hvtiRutilities))
```

```{r}
#| label: guard-edits
#| results: asis
# The markers in this file name work a study author still has to do, and a job
# that still contains one has not been finished. This chunk is what makes that
# TRUE rather than merely stated: an unedited job would otherwise render green
# over placeholder columns.
.tok <- paste0("ED", "IT", ":")
.cur <- knitr::current_input()
if (!is.null(.cur)) {
  .src  <- readLines(.cur, warn = FALSE)
  .hits <- grep(.tok, .src, fixed = TRUE)
  if (length(.hits)) {
    .msg <- paste0(
      length(.hits), " unresolved ", .tok, " marker(s) remain in this job:\n",
      paste0("  - ", trimws(substr(.src[.hits], 1L, 96L)), collapse = "\n"),
      "\nA job that still contains one has not been finished. Work each ",
      "marker and delete it."
    )
    if (tolower(Sys.getenv("HVTI_TEMPLATE_STRICT")) %in% c("", "0", "false", "no")) {
      warning(.msg, "\nRendering as a draft; the banner goes when the last marker does. ",
              "Set HVTI_TEMPLATE_STRICT to 1, true or yes to make this stop.", call. = FALSE)
      cat("\n::: {.callout-important title=\"DRAFT -- this job is unfinished\"}\n")
      cat("Unresolved markers remain. **The numbers below are not",
          "a result.**\n\n```\n", .msg, "\n```\n", sep = "")
      cat(":::\n\n")
    } else {
      stop(.msg, "\nThis render stops because HVTI_TEMPLATE_STRICT is '",
           Sys.getenv("HVTI_TEMPLATE_STRICT"), "'. Unset it, or set it to 0, false ",
           "or no, to render a draft instead.", call. = FALSE)
    }
  }
}
```

```{r}
#| label: guard-partial
#| results: asis
# unnumbered: a callout, printed only when part of the job is left out
# To render a job you have not finished, leave a chunk out with the chunk
# option skip, giving the reason in quotes, or call hvtiRtemplates::stop_here()
# in a chunk to leave out everything below it. A draft lists each one here; a
# final render refuses them, as it refuses an EDIT marker. ?stop_here has more.
hvtiRtemplates:::.guard_partial(knitr::current_input())
```

```{r}
#| label: set
SUBJECT <- "dead"
TYPE    <- "calibration"

.current <- knitr::current_input()
if (!is.null(.current)) {
  .fields <- hvtiRtemplates:::.job_name_fields(.current)
  .name_subject <- if (length(.fields) >= 1L) .fields[[1L]] else NA_character_
  .name_type <- if (length(.fields) >= 2L) .fields[[2L]] else NA_character_
  if (!identical(.name_subject, SUBJECT) || !identical(.name_type, TYPE)) {
    stop("This file is named '", .current, "' (subject '", .name_subject,
         "', type '", .name_type, "'), but declares SUBJECT = \"", SUBJECT,
         "\", TYPE = \"", TYPE, "\". Fix the declaration or the filename before rendering.",
         call. = FALSE)
  }
}

set_path <- function(kind, file) {
  d <- file.path(hvtiRutilities::study_dir(kind, .root),
                 paste0(SUBJECT, "-", TYPE))
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  file.path(d, file)
}

# Saves a figure as <name>.png and <name>.pdf in this set's graphs/ folder (or `kind`'s),
# under the SAVE_FIGURES and FIGURES study choices.
save_figure <- function(plot, name, width = 6, height = 4, kind = "graphs", linked = FALSE) {
  hvtiRtemplates:::.save_figure(plot, set_path(kind, paste0(name, ".png")), width, height,
                                SAVE_FIGURES, FIGURES, linked)
}
```

## Study choices

Edit these values for this study before rendering.

```{r}
#| label: edit-study-choices
# EDIT: the registered dataset this job reads ("built" is the study dataset).
DATASET <- "built"

# EDIT: an hvtiRdatabuild analysis set, or NULL to read the whole dataset.
ANALYSIS_SET <- NULL

# EDIT: rows to keep, dplyr::filter() style, or NULL to keep every row:
#   WHERE <- quote(age >= 18)
#   WHERE <- rlang::exprs(age >= 18, hx_chf == 1)
WHERE <- NULL

# EDIT: the patient identifier. Without "ccfid" the job uses MRN, then eMRN;
# name another column, such as "randid", if the study uses one.
ID <- "ccfid"

# EDIT: what makes a row unique; one row per patient unless repeated measures
# add their visit time or date, for example KEY <- c(ID, "iv_echo").
KEY <- ID

# Optional, and needs no edit: NULL reads the cohort alone. To join one
# registered ancillary dataset (echoes, labs), name it in JOIN. The cohort
# above decides the patients, one row each; the joined records of other
# patients are dropped and counted in the data table.
#   JOIN_VARS: the cohort columns each joined row carries; NULL carries all,
#     and a column both datasets have stops, so list only those the job needs.
#   REDUCE: NULL keeps a row per joined record, keyed on that dataset's key;
#     list(rule = "first", by = "echo_date") keeps one row per patient ("last",
#     or "nearest" with to = a cohort date column). WHERE on a joined column
#     filters the records first, so "last" with WHERE echo_type == "TTE"
#     keeps each patient's last TTE. A tie stops: picking one record
#     silently would be a hidden choice; by = c("echo_date", "echo_seq")
#     breaks it. This job models one row per
#     patient, so a JOIN without REDUCE stops here.
#   JOIN_KEY: overrides the joined dataset's registered key.
JOIN <- NULL
JOIN_VARS <- NULL
REDUCE <- NULL
JOIN_KEY <- NULL

# EDIT: the event, a 0/1 column, 1 for a patient who had it (the SAS macro's
# EVENT=). TRUE and FALSE also work. A patient with no value is ranked with the
# rest, as in SAS, but counts toward no group's rate.
EVENT <- "dead"

# EDIT: the link, the scale the group rates are put on before they are plotted.
# "hazard" is the log of the constant hazard rate, log(events / sum of follow-up),
# for an event with variable follow-up such as death (the SAS call's cox=1).
# "logit" is log(p / (1 - p)), for an event every patient was followed to the same
# point for, such as in-hospital death or a complication.
LINK <- "hazard"

# EDIT: the follow-up column, in the unit the study reports (years here). Only
# "hazard" reads it, and INTERVAL below reads it for either link. A patient with
# no value is left out of a "hazard" calibration, as the SAS macro left them out.
TIME <- "iv_dead"

# EDIT: NULL, or a window on follow-up, c(start, end), such as c(0.25, 5): one phase
# of a hazard, the SAS early, constant or late phase, in the unit of TIME. A patient
# whose follow-up ended before `start` is left out and counted. Everyone else is
# censored at `end`: a patient followed past it counts as followed to `end`, and an
# event after it does not count. Under "hazard" the time at risk is then the time
# inside the window, TIME capped at `end`, less `start`; the SAS template summed it
# from 0. Under "logit" the same patients are kept and an event counts only if it
# falls inside the window. Both counts are reported under the data table.
INTERVAL <- NULL

# EDIT: the covariates to calibrate, one row each. `name` is a column of the data;
# `kind` is "continuous" (ranked into groups) or "ordinal" (each level is a
# group). The other columns are optional, and a covariate that does not give
# one takes the default:
#   groups    5      how many groups a continuous covariate is ranked into
#   constant  the covariate's median to one significant figure; the c in the
#             inverse, inverse squared, squared and exponential scales
#   shift     0      added before the log, for a covariate that can be 0
#   label     the name   the heading over its table and figure
#   chosen    NA     the scale to use: "raw", "log", "inverse",
#                    "inverse_squared", "squared" or "exp". Leave it NA until
#                    you have seen the figure; the job then warns, and a final
#                    render stops until every covariate has one.
VARIABLES <- data.frame(
  name   = c("age"),
  kind   = c("continuous"),
  chosen = c(NA)
)

# Each figure is saved to graphs/ as a PNG (for Word) and a PDF (for the publisher).
# SAVE_FIGURES <- FALSE saves neither; FIGURES keeps only the figures whose names
# start with one of its entries, e.g. FIGURES <- c("lg-age"). The names are the
# file names, listed for each template in the templates README.
SAVE_FIGURES <- TRUE
FIGURES <- NULL
```

## Data

<!-- How this job finds its data. Read this before touching the chunk below.

     A study can offer a job data three ways, and `_study.yml` says which exist:

     1. The study dataset: the file named by `built:`. `DATASET <- "built"`
        with `ANALYSIS_SET <- NULL`.
     2. An additional dataset: any file declared under `additional_datasets:`,
        for example a column subset written for R. Set `DATASET` to its
        name there and `ANALYSIS_SET <- NULL`. It is read as it stands: only
        `WHERE` removes rows.
     3. An analysis set: declared under `analysis_sets:` with the columns kept
        and the rows excluded, then written once with
        `hvtiRdatabuild::write_analysis_set()`. Set `ANALYSIS_SET` to its name
        and leave `DATASET` as "built", because a set is always cut from the
        study dataset. The report shows its exclusions in order.

     A name under `additional_datasets:` is not an analysis set, so putting it
     in `ANALYSIS_SET` stops with "No analysis set". Whichever route is taken,
     the report prints what it read, the identifier it used, the rows each
     `WHERE` condition removed and the rows and patients kept, so a reader
     never has to ask which data a table describes. -->

```{r}
#| label: tbl-data
#| tbl-cap: "The data this job read"
hvtiRutilities::verify_manifest(file.path(.root, "manifest.yaml"))
.cfg <- study_config(start = .root)
job_data <- hvtiRtemplates::read_job_data(.cfg, dataset = DATASET, analysis_set = ANALYSIS_SET,
                                          where = WHERE, id = ID, key = KEY, join = JOIN, join_vars = JOIN_VARS,
                                          reduce = REDUCE, join_key = JOIN_KEY, one_row_per_patient = TRUE)
d <- job_data$data
.provenance_data <- c(if (exists(".provenance_data")) .provenance_data else list(), list(job_data$provenance),
                      if (!is.null(job_data$provenance_join)) list(job_data$provenance_join))
knitr::kable(job_data$record, col.names = c("Data", ""))
```

```{r}
#| label: data-attrition
#| results: asis
# unnumbered: its child chunk carries its own label and caption
if (!is.null(job_data$attrition)) {
  .fence <- strrep("`", 3)
  cat(knitr::knit_child(text = c(
    paste0(.fence, "{r}"), "#| label: tbl-data-attrition",
    paste0("#| tbl-cap: ", encodeString(paste0("Analysis set `", ANALYSIS_SET, "`: exclusions, in order"), quote = "\"")),
    "knitr::kable(job_data$attrition)", .fence
  ), envir = environment(), quiet = TRUE), sep = "\n")
}
```

```{r}
#| label: provenance
#| echo: false
#| results: asis
cat(hvtiRtemplates:::.embed_provenance(
  .in,
  data = .provenance_data,
  extra = list(subject = SUBJECT, type = TYPE)
))
```
````

The `SUBJECT` and `TYPE` lines sit in the `set` chunk, unmarked, as in `dc-stddiff.qmd`: `add_job()` rewrites them, and `test-templates.R` allows a marker only in a chunk labeled `edit-`.

- [ ] **Step 7: Update the three counts the new template moves.** The suite names the templates it expects, so it fails until it is told about this one.

In `tests/testthat/test-template-provenance.R`: change `expect_equal(nrow(templates), 32L)` to `expect_equal(nrow(templates), 33L)`, and in the `expected` vector of `"only templates with a local dataset choice override the dataset"` append `"lg",` after `"lp-mirror"` on the line that ends `"lm-propensity_ordinal", "lp-mirror",`.

In `tests/testthat/test-template-data-routes.R`: in `patient_level_templates`, change `"ac.qmd", "hz.qmd", "dc-stddiff.qmd", "dc-gfup.qmd", "hs-concordance.qmd",` to end `"hs-concordance.qmd", "lg.qmd",` (a calibration job counts one row per patient, so it says so to `read_job_data()` and its `JOIN` comment says a join without `REDUCE` stops); and change `expect_identical(readers, 21L)` to `expect_identical(readers, 22L)`.

- [ ] **Step 8: Run.** The ripple files fail before Step 7 (`nrow(templates)` 33, `readers` 22, the one-row expectations) and pass after.

```bash
for f in test-lg test-template-provenance test-template-data-routes test-templates test-template-catalog test-template-catalog-rules test-roadmap test-taxonomy test-add-job test-template-format test-template-numbering; do echo "== $f"; R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e "devtools::load_all(quiet=TRUE); testthat::test_file('tests/testthat/$f.R')" 2>&1 | grep -E "FAIL [0-9]+ \| WARN"; done
python3 dev/specs/artifacts/check-roadmap-counts.py
python3 dev/specs/artifacts/check-spec-counts.py
python3 dev/specs/artifacts/check-flow-counts.py
```

Expected PASS: FAIL 0 in every file; `Catalog agrees with disk: 65 template rows routed to hvtiRtemplates, 34 on disk.`, `Spec agrees with the map: ...` and `Diagrams agree with the maps: ...`.

- [ ] **Step 9: Commit.**

```bash
git add inst/templates/10_descriptive/lg.qmd inst/extdata/templates.json dev/specs/2026-08-29-template-conversion-roadmap.md .lintr tests/testthat/helper-lm.R tests/testthat/test-lg.R tests/testthat/test-template-provenance.R tests/testthat/test-template-data-routes.R
git commit -m "Scaffold the lg template and ship its ledger row

The lg ledger row becomes shipped and is renamed Logit calibration, with the
roadmap re-rendered from it. The template file carries its settings, guards,
data read and provenance chunk; the calibration follows. .lintr gains its file
key, and the suite's three counts take the new template.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 10: Mutation check.** Set the catalog row back to queued and confirm both gates go red, then restore.

```bash
sed -i '' '/"prefix": "lg"/,/"note"/ s/"status": "shipped"/"status": "queued"/' inst/extdata/templates.json
python3 dev/specs/artifacts/check-roadmap-counts.py; echo "exit $?"
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lg.R")' | grep "FAIL"
git checkout -- inst/extdata/templates.json
```

Expected: the roadmap check fails (a template on disk with a queued row) and `test-lg.R` shows `FAIL 1`. `git status --short` is clean afterwards.

---

## Task 6: The settings checks and the follow-up window

**Files:**
- Modify: `R/logit-calibration.R` (append)
- Modify: `tests/testthat/test-logit-calibration.R` (append)
- Modify: `inst/templates/10_descriptive/lg.qmd` (insert before `provenance`)
- Modify: `tests/testthat/test-lg.R` (append)

**Interfaces:**
- Produces `.lg_variables(variables, d, exclude = character())`: the `VARIABLES` data frame completed and checked against `d`: columns `name`, `kind`, `groups` (integer), `constant` (numeric), `shift`, `label`, `chosen` (character, `NA` for none). A blank in any column but `name`, or a column left out, takes that covariate's default; the constant default is `.lg_constant()` of the covariate in `d`. `exclude` names columns that may not be covariates (the patient identifier). Every message starts `VARIABLES` and none shows a data value.
- Produces `.lg_interval(d, event, time, interval)`: `list(data, event, time, counts)`. `interval = NULL` returns `d`, the event as 0/1 and `d[[time]]` (`NULL` when `time` is `NULL`), and `counts` `NULL`. Otherwise, with `interval = c(start, end)`: a patient with `follow-up < start`, or with no follow-up, is left out (a follow-up of exactly `start` stays); every other patient is censored at `end`: `follow-up > end` has event 0 (even a missing one, as `dead=0` sets it in SAS), and a follow-up of exactly `end` keeps its event. `data` is the rows kept, unchanged; `event` the windowed event for them; `time` is `pmin(follow-up, end) - start`, the time at risk inside the window. `counts` is a data frame `count`, `patients` with the rows `Patients read`, `Left out: follow-up before the start`, `Left out: follow-up missing`, `Patients kept`, `Censored at the end`, `Events after the end, no longer counted`. Stops with `INTERVAL must be NULL or c(start, end) with start below end, such as c(0.25, 5).`, `INTERVAL must have a start of 0 or later: follow-up is measured from 0.`, `<n> patients have negative follow-up in <time>...` (from `.lg_follow_up()`, which the template also calls on `TIME` whenever it reads it, so a negative duration never reaches a hazard or a window), `INTERVAL needs TIME, the follow-up column.`, `TIME names a column this dataset does not have: <time>...`, or `INTERVAL keeps no patient...`.
- Produces in the template, from `derive`: `.id`, `.needs_time`, `.interval`, the filtered `d`, the windowed `.event` and `.time` (the vectors every later table reads in place of `d[[EVENT]]` and `d[[TIME]]`) and `variables`; and the chunks `derive`, `lg-interval` (unnumbered, emits child chunk `tbl-lg-interval` only with an `INTERVAL`) and `tbl-lg-variables`.
- Consumed by: Tasks 7 and 8.

- [ ] **Step 1: Write the failing tests.** Append to `tests/testthat/test-logit-calibration.R`:

```r
test_that(".lg_variables() fills every default from the data and keeps what the author gave", {
  d <- data.frame(age = c(41, 52, 58, 61, 70), nyha = c(1, 2, 2, 3, 4), wt = c(70, 80, 86, 90, 110))
  v <- hvtiRtemplates:::.lg_variables(data.frame(name = c("age", "nyha")), d)
  expect_named(v, c("name", "kind", "groups", "constant", "shift", "label", "chosen"))
  expect_identical(v$name, c("age", "nyha"))
  expect_identical(v$kind, c("continuous", "continuous"))
  expect_identical(v$groups, c(5L, 5L))
  # The median to one significant figure: 58 gives 60, and a median of 2 stays 2.
  expect_identical(v$constant, c(60, 2))
  expect_identical(v$shift, c(0, 0))
  expect_identical(v$label, c("age", "nyha"))
  expect_identical(v$chosen, c(NA_character_, NA_character_))
  # What the author gives wins, row by row, and a blank in a column takes that row's default.
  given <- data.frame(
    name = c("age", "nyha", "wt"), kind = c("continuous", "ordinal", NA), groups = c(4, NA, 6),
    constant = c(50, NA, NA), shift = c(NA, 1, 0), label = c("Age (years)", NA, ""), chosen = c("log", "", NA)
  )
  v <- hvtiRtemplates:::.lg_variables(given, d)
  expect_identical(v$kind, c("continuous", "ordinal", "continuous"))
  expect_identical(v$groups, c(4L, 5L, 6L))
  expect_identical(v$constant, c(50, 2, 90))
  expect_identical(v$shift, c(0, 1, 0))
  expect_identical(v$label, c("Age (years)", "nyha", "wt"))
  expect_identical(v$chosen, c("log", NA, NA))
  # A logical NA, as a one-row data frame writes it, is no choice.
  expect_identical(hvtiRtemplates:::.lg_variables(data.frame(name = "age", chosen = NA), d)$chosen, NA_character_)
})

test_that(".lg_variables() stops on a table, column, name or value it cannot use, naming VARIABLES", {
  d <- data.frame(ccfid = 1:5, age = c(41, 52, 58, 61, 70), sex = c("f", "m", "f", "m", "f"), zero = c(0, 0, 0, 0, 1))
  one <- function(...) hvtiRtemplates:::.lg_variables(data.frame(name = "age", ...), d)
  expect_error(hvtiRtemplates:::.lg_variables("age", d), "^VARIABLES must be a data frame with one row for each covariate")
  expect_error(hvtiRtemplates:::.lg_variables(data.frame(name = character()), d), "^VARIABLES must be a data frame")
  expect_error(hvtiRtemplates:::.lg_variables(data.frame(kind = "ordinal"), d), "^VARIABLES needs a `name` column")
  expect_error(one(color = "red"), "^VARIABLES has a column the job does not use: color. The columns are name, kind")
  expect_error(hvtiRtemplates:::.lg_variables(data.frame(name = c("age", "age")), d),
               "^VARIABLES names a covariate more than once: age")
  expect_error(hvtiRtemplates:::.lg_variables(data.frame(name = c("age", NA)), d), "^VARIABLES has a covariate with no name")
  expect_error(hvtiRtemplates:::.lg_variables(data.frame(name = c("age", "bmi", "bsa")), d),
               "^VARIABLES names columns this dataset does not have: bmi, bsa. Change VARIABLES in edit-study-choices[.]")
  expect_error(hvtiRtemplates:::.lg_variables(data.frame(name = "sex"), d), "^VARIABLES names a column that is not numeric: sex")
  expect_error(hvtiRtemplates:::.lg_variables(data.frame(name = c("age", "ccfid")), d, exclude = "ccfid"),
               "^VARIABLES names the patient identifier [(]`ccfid`[)]")
  expect_error(one(kind = "binary"), "^VARIABLES\\$kind must be \"continuous\" or \"ordinal\"")
  expect_error(one(groups = 1), "^VARIABLES\\$groups must be a whole number of at least 2")
  expect_error(one(groups = 2.5), "^VARIABLES\\$groups must be a whole number of at least 2")
  expect_error(one(groups = "five"), "^VARIABLES\\$groups must be a whole number")
  expect_error(one(constant = 0), "^VARIABLES\\$constant must be a finite number other than 0")
  expect_error(one(constant = Inf), "^VARIABLES\\$constant must be a finite number other than 0")
  expect_error(one(shift = Inf), "^VARIABLES\\$shift must be a finite number")
  expect_error(one(chosen = "cubic"), "^VARIABLES\\$chosen must be NA or one of raw, log, inverse, inverse_squared, squared, exp")
  # A covariate whose median rounds to 0 has no default constant, and says where to set one.
  expect_error(hvtiRtemplates:::.lg_variables(data.frame(name = "zero"), d),
               "^The median of `zero` rounds to 0, so there is no default constant: set constant for it in VARIABLES")
  expect_silent(hvtiRtemplates:::.lg_variables(data.frame(name = "zero", constant = 1), d))
})

test_that(".lg_interval() drops patients who ended before the start and censors the rest at the end", {
  # Eight patients, the window c(0.25, 5), worked by hand:
  #   id   follow-up  event  what happens
  #    1     0.10       1     ended before the start: left out
  #    2     0.25       1     exactly at the start: kept, time at risk 0.25 - 0.25 = 0
  #    3     1.00       0     kept, time at risk 0.75
  #    4     5.00       1     exactly at the end: kept with its event, time at risk 4.75
  #    5     5.50       1     past the end: censored at 5, the event no longer counts, time at risk 4.75
  #    6      NA        1     no follow-up: left out
  #    7     3.00       0     kept, time at risk 2.75
  #    8     8.00       1     past the end: censored, event not counted, time at risk 4.75
  d <- data.frame(id = 1:8, t = c(0.1, 0.25, 1, 5, 5.5, NA, 3, 8), dead = c(1L, 1L, 0L, 1L, 1L, 1L, 0L, 1L))
  got <- hvtiRtemplates:::.lg_interval(d, "dead", "t", c(0.25, 5))
  expect_identical(got$data$id, c(2L, 3L, 4L, 5L, 7L, 8L))
  expect_identical(got$event, c(1L, 0L, 1L, 0L, 0L, 0L))
  expect_equal(got$time, c(0, 0.75, 4.75, 4.75, 2.75, 4.75))
  expect_identical(got$counts$count, c("Patients read", "Left out: follow-up before the start", "Left out: follow-up missing",
                                       "Patients kept", "Censored at the end", "Events after the end, no longer counted"))
  expect_identical(got$counts$patients, c(8L, 1L, 1L, 6L, 2L, 2L))
  # The columns of the data are not changed.
  expect_identical(got$data$dead, c(1L, 0L, 1L, 1L, 0L, 1L))
  # An event of NA past the end is censored too, as `dead=0` sets it in SAS.
  na_event <- hvtiRtemplates:::.lg_interval(transform(d, dead = replace(dead, 8L, NA)), "dead", "t", c(0.25, 5))
  expect_identical(na_event$event[[6L]], 0L)
  # No interval keeps everyone and has nothing to report; the event and follow-up come back as they are.
  none <- hvtiRtemplates:::.lg_interval(d, "dead", "t", NULL)
  expect_identical(none$data, d)
  expect_identical(none$event, d$dead)
  expect_identical(none$time, d$t)
  expect_null(none$counts)
  expect_null(hvtiRtemplates:::.lg_interval(d, "dead", NULL, NULL)$time)
  # A window that starts at 0, the SAS early phase, leaves nobody out for being early.
  early <- hvtiRtemplates:::.lg_interval(d, "dead", "t", c(0, 1))
  expect_identical(early$counts$patients[c(2L, 4L, 5L)], c(0L, 7L, 4L))
  expect_equal(early$time, c(0.1, 0.25, 1, 1, 1, 1, 1))
  expect_error(hvtiRtemplates:::.lg_interval(d, "dead", "t", c(10, 20)), "^INTERVAL keeps no patient")
  for (bad in list(5, c(5, 1), c(1, NA), c(1, 5, 9), "a", c(2, 2))) {
    expect_error(hvtiRtemplates:::.lg_interval(d, "dead", "t", bad), "^INTERVAL must be NULL or c[(]start, end[)]")
  }
  expect_error(hvtiRtemplates:::.lg_interval(d, "dead", "later", c(1, 2)), "^TIME names a column this dataset does not have: later")
  expect_error(hvtiRtemplates:::.lg_interval(d, "dead", NULL, c(1, 2)), "^INTERVAL needs TIME")
  expect_error(hvtiRtemplates:::.lg_interval(d, "died", "t", NULL), "^event must be coded 0 and 1")
})
```

Append to `tests/testthat/test-lg.R`:

```r
test_that("the job checks its choices against the data before any calibration, naming the setting", {
  local_child_chunks()
  run <- function(...) lm_eval_job(lg_fixture(...)$job)
  expect_error(run("LINK <- \"cox\""), "^LINK must be \"logit\" or \"hazard\"")
  expect_error(run("EVENT <- \"died\""), "^EVENT names a column this dataset does not have: died")
  expect_error(run("EVENT <- c(\"dead\", \"hdead\")"), "^EVENT must be one column name")
  expect_error(run("TIME <- \"later\""), "^TIME names a column this dataset does not have: later")
  expect_error(run("EVENT <- \"ccfid\""), "^EVENT and TIME cannot be the patient identifier")
  expect_error(run(variables = c("VARIABLES <- data.frame(", "  name = c(\"age\", \"bmi\")", ")")),
               "^VARIABLES names a column this dataset does not have: bmi. Change VARIABLES in edit-study-choices")
  expect_error(run(variables = c("VARIABLES <- data.frame(", "  name = \"ccfid\"", ")")),
               "^VARIABLES names the patient identifier")
  # TIME is read by the hazard link and by INTERVAL only: a logit job with no INTERVAL need not have it.
  expect_no_error(run(c("LINK <- \"logit\"", "EVENT <- \"hdead\"", "TIME <- \"later\"")))
  expect_error(run(c("LINK <- \"logit\"", "EVENT <- \"hdead\"", "TIME <- \"later\"", "INTERVAL <- c(0, 5)")),
               "^TIME names a column this dataset does not have: later")
})

test_that("INTERVAL drops patients who ended before the start, censors the rest at the end, and reports both counts", {
  local_child_chunks()
  d <- lg_data()
  kept <- d$iv_dead >= 0.25
  past <- kept & d$iv_dead > 5
  s <- lg_fixture("INTERVAL <- c(0.25, 5)")
  env <- lm_eval_job(s$job)
  expect_identical(nrow(env$d), sum(kept))
  # Patients read, left out before the start, left out for no follow-up, kept, censored at the end,
  # and the events that fell after it.
  expect_identical(env$.interval$counts$patients,
                   c(nrow(d), sum(d$iv_dead < 0.25), 0L, sum(kept), sum(past), sum(d$dead[past])))
  expect_gt(sum(d$iv_dead < 0.25), 0L)
  expect_gt(sum(past), 0L)
  # What the tables will read: no event after the end, and the time at risk inside the window.
  expect_identical(env$.event, ifelse(d$iv_dead[kept] > 5, 0L, d$dead[kept]))
  expect_equal(env$.time, pmin(d$iv_dead[kept], 5) - 0.25)
  # The covariates' defaults are those of the patients kept.
  expect_identical(env$variables$constant, signif(stats::median(d$age[kept]), 1L))
  # Without an interval, every patient is calibrated as read and there is nothing to report.
  env <- lm_eval_job(lg_fixture()$job)
  expect_identical(nrow(env$d), nrow(d))
  expect_null(env$.interval$counts)
  expect_identical(env$.event, d$dead)
  expect_equal(env$.time, d$iv_dead)
  expect_identical(env$variables$constant, signif(stats::median(d$age), 1L))
})
```

- [ ] **Step 2: Run them.**

```bash
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-logit-calibration.R")'
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lg.R")'
```

Expected FAIL: the first, `object '.lg_variables' not found` and `object '.lg_interval' not found`, `[ FAIL 3 | WARN 0 | SKIP 0 | PASS 133 ]`; the second, `Expected ... to throw a error` for each setting check and the `INTERVAL` expectations, because the template does not read its settings yet.

- [ ] **Step 3: Implement the functions.** Append to `R/logit-calibration.R`:

```r
# The VARIABLES table, completed and checked against the data. Only `name` is
# required. A blank in any other column, or a column left out, takes that
# covariate's default: continuous, 5 groups, the median-rule constant, no shift,
# the name as its label, and no scale chosen. `exclude` holds columns that may
# not be covariates, the patient identifier. Every message names VARIABLES, the
# setting the author changes; none shows a data value.
.lg_variables <- function(variables, d, exclude = character()) {
  columns <- c("name", "kind", "groups", "constant", "shift", "label", "chosen")
  if (!is.data.frame(variables) || !nrow(variables)) {
    stop("VARIABLES must be a data frame with one row for each covariate and at least a `name` column.", call. = FALSE)
  }
  if (!"name" %in% names(variables)) stop("VARIABLES needs a `name` column.", call. = FALSE)
  unknown <- setdiff(names(variables), columns)
  if (length(unknown)) {
    stop("VARIABLES has a column the job does not use: ", paste(unknown, collapse = ", "),
         ". The columns are ", paste(columns, collapse = ", "), ".", call. = FALSE)
  }
  name <- as.character(variables$name)
  if (anyNA(name) || any(!nzchar(name))) stop("VARIABLES has a covariate with no name.", call. = FALSE)
  if (anyDuplicated(name)) {
    stop("VARIABLES names a covariate more than once: ", paste(unique(name[duplicated(name)]), collapse = ", "), ".",
         call. = FALSE)
  }
  absent <- setdiff(name, names(d))
  if (length(absent)) {
    stop("VARIABLES names ", if (length(absent) == 1L) "a column" else "columns", " this dataset does not have: ",
         paste(absent, collapse = ", "), ". Change VARIABLES in edit-study-choices.", call. = FALSE)
  }
  reached <- intersect(name, exclude)
  if (length(reached)) {
    stop("VARIABLES names the patient identifier (`", reached[[1L]], "`); a calibration cannot use it as a covariate.",
         call. = FALSE)
  }
  text <- name[!vapply(name, function(v) is.numeric(d[[v]]), logical(1L))]
  if (length(text)) {
    stop("VARIABLES names a column that is not numeric: ", paste(text, collapse = ", "),
         ". A calibration ranks the covariate, so recode it as a number first.", call. = FALSE)
  }
  column <- function(field) if (field %in% names(variables)) variables[[field]] else rep(NA, nrow(variables))
  number <- function(field, what) {
    x <- column(field)
    if (!(is.numeric(x) || all(is.na(x)))) stop("VARIABLES$", field, " must be ", what, ".", call. = FALSE)
    as.numeric(x)
  }
  kind <- as.character(column("kind"))
  kind[is.na(kind)] <- "continuous"
  if (!all(kind %in% c("continuous", "ordinal"))) {
    stop("VARIABLES$kind must be \"continuous\" or \"ordinal\".", call. = FALSE)
  }
  groups <- number("groups", "a whole number of at least 2")
  groups[is.na(groups)] <- 5
  if (any(!is.finite(groups) | groups < 2 | groups != round(groups))) {
    stop("VARIABLES$groups must be a whole number of at least 2.", call. = FALSE)
  }
  constant <- number("constant", "a finite number other than 0")
  if (any(!is.na(constant) & (!is.finite(constant) | constant == 0))) {
    stop("VARIABLES$constant must be a finite number other than 0.", call. = FALSE)
  }
  for (i in which(is.na(constant))) constant[[i]] <- .lg_constant(d[[name[[i]]]], name[[i]])
  shift <- number("shift", "a finite number")
  shift[is.na(shift)] <- 0
  if (any(!is.finite(shift))) stop("VARIABLES$shift must be a finite number.", call. = FALSE)
  label <- as.character(column("label"))
  label[is.na(label) | !nzchar(label)] <- name[is.na(label) | !nzchar(label)]
  chosen <- as.character(column("chosen"))
  chosen[!is.na(chosen) & !nzchar(chosen)] <- NA_character_
  if (any(!is.na(chosen) & !chosen %in% .lg_scale_ids)) {
    stop("VARIABLES$chosen must be NA or one of ", paste(.lg_scale_ids, collapse = ", "), ".", call. = FALSE)
  }
  data.frame(name = name, kind = kind, groups = as.integer(groups), constant = constant, shift = shift,
             label = label, chosen = chosen, stringsAsFactors = FALSE)
}

# One phase of follow-up, as the SAS jobs took it (the legacy constant-hazard
# template): INTERVAL = c(start, end).
#   * A patient whose follow-up ended before `start` is left out and counted
#     (`iv_dead < start` deleted them), as is one with no follow-up. A follow-up of
#     exactly `start` stays.
#   * Every other patient is censored at `end`: one followed past it (`iv_dead > end`)
#     has no event and counts as followed to `end`, and an event after `end` is not
#     counted. A follow-up of exactly `end` stays, with its event.
# The follow-up the hazard link sums is then the time at risk inside the window,
# pmin(time, end) - start. The legacy template summed pmin(time, end) from 0, so the
# months before `start` entered every patient's denominator; the shift is the one
# deliberate difference, and it is this line: `pmin(follow, end) - start`.
# The logit link keeps the same patients and the same censored events, and reads
# no follow-up. The columns of `d` are not changed: the adjusted event and
# follow-up come back as vectors for the rows kept. NULL keeps every row, and
# returns the event and follow-up as they are. `counts` reports what was read, left
# out before the start or for want of follow-up, kept, censored at the end and the
# events that fell after it, never a patient.
.lg_interval <- function(d, event, time, interval) {
  e <- .lg_event(d[[event]])
  if (is.null(interval)) {
    return(list(data = d, event = e, time = if (!is.null(time)) d[[time]], counts = NULL))
  }
  if (!is.numeric(interval) || length(interval) != 2L || anyNA(interval) || interval[[1L]] >= interval[[2L]]) {
    stop("INTERVAL must be NULL or c(start, end) with start below end, such as c(0.25, 5).", call. = FALSE)
  }
  if (is.null(time)) stop("INTERVAL needs TIME, the follow-up column.", call. = FALSE)
  if (!time %in% names(d)) {
    stop("TIME names a column this dataset does not have: ", time, ". Change TIME in edit-study-choices.", call. = FALSE)
  }
  start <- interval[[1L]]
  end <- interval[[2L]]
  follow <- d[[time]]
  before <- !is.na(follow) & follow < start
  missing <- is.na(follow)
  kept <- !before & !missing
  if (!any(kept)) {
    stop("INTERVAL keeps no patient: no follow-up reaches ", start, ". Change INTERVAL in edit-study-choices.", call. = FALSE)
  }
  follow <- follow[kept]
  e <- e[kept]
  past <- follow > end
  counts <- data.frame(
    count = c("Patients read", "Left out: follow-up before the start", "Left out: follow-up missing", "Patients kept",
              "Censored at the end", "Events after the end, no longer counted"),
    patients = c(nrow(d), sum(before), sum(missing), sum(kept), sum(past), sum(e[past] == 1, na.rm = TRUE))
  )
  e[past] <- 0L
  list(data = d[kept, , drop = FALSE], event = e, time = pmin(follow, end) - start, counts = counts)
}
```

- [ ] **Step 4: Implement the template chunks.** In `lg.qmd`, insert the following immediately before the `provenance` chunk (the last one, the chunk that starts with `` ```{r} `` and `#| label: provenance`), so it follows `data-attrition`:

````markdown
```{r}
#| label: derive
# unnumbered: checks the choices against the data and shows nothing
# Every choice is checked against the data before any calibration, so a
# misspelled column stops here by name rather than as an error from inside it.
.id <- attr(job_data$record, "selection")$id
if (!identical(LINK, "logit") && !identical(LINK, "hazard")) {
  stop("LINK must be \"logit\" or \"hazard\".", call. = FALSE)
}
one_column <- function(x, setting) {
  if (!(is.character(x) && length(x) == 1L && !is.na(x))) stop(setting, " must be one column name.", call. = FALSE)
}
one_column(EVENT, "EVENT")
# TIME is read by the hazard link and by INTERVAL, and by nothing else.
.needs_time <- identical(LINK, "hazard") || !is.null(INTERVAL)
if (.needs_time) one_column(TIME, "TIME")
hvtiRtemplates:::.check_job_columns(d, EVENT = EVENT, TIME = if (.needs_time) TIME)
if (.id %in% c(EVENT, if (.needs_time) TIME)) {
  stop("EVENT and TIME cannot be the patient identifier.", call. = FALSE)
}
if (.needs_time && !is.numeric(d[[TIME]])) {
  stop("TIME must be a number, the follow-up in years or months: `", TIME, "` is not numeric.", call. = FALSE)
}
# INTERVAL leaves patients out and censors the rest before anything else is
# computed, so the constants and the groups below are those of the patients
# calibrated, and the event and follow-up the tables read are the windowed ones.
.interval <- hvtiRtemplates:::.lg_interval(d, EVENT, if (.needs_time) TIME, INTERVAL)
d <- .interval$data
.event <- .interval$event
.time <- .interval$time
variables <- hvtiRtemplates:::.lg_variables(VARIABLES, d, exclude = .id)
```

```{r}
#| label: lg-interval
#| results: asis
# unnumbered: its child chunk carries its own label and caption
if (!is.null(.interval$counts)) {
  .fence <- strrep("`", 3)
  .cap <- paste0("The window of follow-up from ", INTERVAL[[1L]], " to ", INTERVAL[[2L]], " (INTERVAL): patients left out, ",
                 "and patients censored at its end")
  cat(knitr::knit_child(text = c(
    paste0(.fence, "{r}"), "#| label: tbl-lg-interval",
    paste0("#| tbl-cap: ", encodeString(.cap, quote = "\"")),
    "knitr::kable(.interval$counts, col.names = c(\"\", \"Patients\"))", .fence
  ), envir = environment(), quiet = TRUE), sep = "\n")
}
```

## Covariates

Each covariate with the defaults filled in. The `constant` is the `c` in the
inverse, inverse squared, squared and exponential scales: it only sets them to a
readable range, so the median rounded to one figure does the work the SAS jobs'
hand-typed 50 for an age or 80 for a weight did. Set it, or `shift` for a
covariate that can be 0, in `VARIABLES` to change either.

```{r}
#| label: tbl-lg-variables
#| tbl-cap: "The covariates calibrated, with their defaults"
knitr::kable(variables, col.names = c("Covariate", "Kind", "Groups", "Constant", "Shift", "Label", "Chosen"),
             row.names = FALSE)
```
````

- [ ] **Step 5: Run.** Both commands of Step 2. Expected PASS: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 191 ]` and `FAIL 0 | WARN 0 | SKIP 0` for `test-lg.R`.

- [ ] **Step 6: Commit.**

```bash
git add R/logit-calibration.R inst/templates/10_descriptive/lg.qmd tests/testthat/test-logit-calibration.R tests/testthat/test-lg.R
git commit -m "lg: check VARIABLES and the settings against the data, and apply INTERVAL

VARIABLES is completed with each covariate's defaults, the constant from the
median of the patients calibrated, and every setting that names a column is
checked before any calibration. INTERVAL = c(start, end) leaves out the patients
who ended before start and censors the rest at end, as the SAS constant-phase
template did, with the time at risk counted from start. It reports both counts.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Mutation check.** Five mutations, each restored.

```bash
sed -i '' 's/follow < start/follow <= start/' R/logit-calibration.R
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-logit-calibration.R")' | grep "FAIL"
git checkout -- R/logit-calibration.R
sed -i '' 's/time = pmin(follow, end) - start,/time = pmin(follow, end),/' R/logit-calibration.R
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-logit-calibration.R")' | grep "FAIL"
git checkout -- R/logit-calibration.R
sed -i '' 's/^  e\[past\] <- 0L$/  e[past] <- e[past]/' R/logit-calibration.R
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-logit-calibration.R")' | grep "FAIL"
git checkout -- R/logit-calibration.R
sed -i '' 's/^\.event <- \.interval\$event$/.event <- d[[EVENT]]/' inst/templates/10_descriptive/lg.qmd
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lg.R")' | grep "FAIL"
git checkout -- inst/templates/10_descriptive/lg.qmd
sed -i '' '/^hvtiRtemplates:::.check_job_columns(d, EVENT = EVENT/d' inst/templates/10_descriptive/lg.qmd
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lg.R")' | grep "FAIL"
git checkout -- inst/templates/10_descriptive/lg.qmd
```

Expected: red each time: a patient ending exactly at `start` is left out; the time at risk starts at 0 as the legacy template summed it; an event after `end` still counts; the tables read the unwindowed event; a misspelled column is no longer named. `git status --short` is clean afterwards. (Measured on the finished tree: 6, 1, 2, 3 and 1 failures.)

---

## Task 7: The table and figure for each covariate

**Files:**
- Modify: `inst/templates/10_descriptive/lg.qmd` (insert before `provenance`)
- Modify: `tests/testthat/test-lg.R` (append)
- Modify: `tests/testthat/test-template-figures.R`

**Interfaces:**
- Consumes `variables`, `d`, `.event`, `.time` (the windowed event and follow-up of Task 6, equal to `d[[EVENT]]` and `d[[TIME]]` without an `INTERVAL`), `LINK`, `save_figure()`, `.in`, and Tasks 2 to 4.
- Produces the object `calibration`, a list named by covariate, each `list(table, scales)` (`.lg_table()` and `.lg_scales()` results), and, for each covariate, the saved files `lg-<name>.png` and `lg-<name>.pdf` under `graphs/<subject>-<type>/`, and child chunks `tbl-lg-<slug>` and `fig-lg-<slug>`, where `<slug>` is the name with each run of characters other than letters and digits replaced by one hyphen (`nyha_pr` gives `nyha-pr`), so an underscore is never read as markup in a cross-reference. After the loop `.notes` holds the last covariate's notes (what is printed under its table).
- Consumed by: Tasks 8 and 9.

- [ ] **Step 1: Write the failing tests.** Append to `tests/testthat/test-lg.R`:

```r
# The two variables of the synthetic study the job's tests calibrate: a continuous
# age and an ordinal NYHA class, as a VARIABLES data frame the fixture splices in.
lg_two_variables <- c(
  "VARIABLES <- data.frame(",
  "  name = c(\"age\", \"nyha\"),",
  "  kind = c(\"continuous\", \"ordinal\"),",
  "  chosen = c(\"log\", \"raw\")",
  ")"
)

test_that("the job tabulates each covariate's groups and draws its six-panel figure, saved as PNG and PDF", {
  local_child_chunks()
  s <- lg_fixture(variables = lg_two_variables)
  # What the job's asis chunks would print: the child chunks they knit.
  printed <- character()
  testthat::local_mocked_bindings(
    knit_child = function(text, envir, ...) {
      printed <<- c(printed, text)
      ""
    },
    .package = "knitr"
  )
  env <- lm_eval_job(s$job)
  d <- lg_data()
  # The hazard link of the study's death and follow-up, on five rank groups of age and a group per NYHA class.
  age <- hvtiRtemplates:::.lg_table(d$age, d$dead, d$iv_dead, groups = 5L, link = "hazard")
  expect_equal(env$calibration$age$table, age)
  expect_identical(nrow(age), 5L)
  nyha <- hvtiRtemplates:::.lg_table(d$nyha, d$dead, d$iv_dead, kind = "ordinal", link = "hazard")
  expect_equal(env$calibration$nyha$table, nyha)
  expect_identical(nrow(nyha), 4L)
  expect_equal(env$calibration$age$scales, hvtiRtemplates:::.lg_scales(age$mean, env$variables$constant[[1L]]))
  # One numbered table and one numbered figure for each covariate, in that order.
  labels <- sub("^#\\| label: ", "", grep("^#\\| label: (tbl|fig)-lg-(age|nyha)$", printed, value = TRUE))
  expect_identical(labels, c("tbl-lg-age", "fig-lg-age", "tbl-lg-nyha", "fig-lg-nyha"))
  graphs <- file.path(hvtiRutilities::study_dir("graphs", s$root), "dead-calibration")
  expect_setequal(list.files(graphs), c("lg-age.png", "lg-age.pdf", "lg-nyha.png", "lg-nyha.pdf"))
})

test_that("the logit link calibrates a binary event with no follow-up, and FIGURES keeps only the PDFs it names", {
  local_child_chunks()
  s <- lg_fixture(c("LINK <- \"logit\"", "EVENT <- \"hdead\"", "TIME <- \"later\"", "FIGURES <- c(\"lg-age\")"),
                  variables = lg_two_variables)
  env <- lm_eval_job(s$job)
  d <- lg_data()
  expect_equal(env$calibration$age$table, hvtiRtemplates:::.lg_table(d$age, d$hdead, groups = 5L, link = "logit"))
  graphs <- file.path(hvtiRutilities::study_dir("graphs", s$root), "dead-calibration")
  # The PNG a report shows is always written; the PDF only for a figure FIGURES keeps.
  expect_setequal(list.files(graphs), c("lg-age.png", "lg-age.pdf", "lg-nyha.png"))
})

test_that("a group or scale that cannot be computed is named under its table, and a label never holds an underscore", {
  local_child_chunks()
  # n_prior is 0 for most patients, so its lowest group has a mean of 0.
  s <- lg_fixture(variables = c(
    "VARIABLES <- data.frame(",
    "  name = c(\"n_prior\"),",
    "  constant = c(1),",
    "  chosen = c(\"raw\")",
    ")"
  ))
  printed <- character()
  testthat::local_mocked_bindings(
    knit_child = function(text, envir, ...) {
      printed <<- c(printed, text)
      ""
    },
    .package = "knitr"
  )
  env <- lm_eval_job(s$job)
  # The labels carry hyphens, the file keeps the column's own name.
  expect_true(all(c("#| label: tbl-lg-n-prior", "#| label: fig-lg-n-prior") %in% printed))
  expect_true(file.exists(file.path(hvtiRutilities::study_dir("graphs", s$root), "dead-calibration", "lg-n_prior.png")))
  # The notes the chunk prints under the table: the three scales a mean of 0 breaks.
  expect_named(attr(env$calibration$n_prior$scales, "notes"), c("log", "inverse", "inverse_squared"))
  expect_match(env$.notes, "^Log: A group mean plus the shift is not positive", all = FALSE)
  expect_match(env$.notes, "^Inverse squared: A group mean is 0", all = FALSE)
  expect_false(any(grepl("^Exponential", env$.notes)))
})

test_that("under INTERVAL the hazard sums the time at risk inside the window and the logit counts only events inside it", {
  local_child_chunks()
  d <- lg_data()
  kept <- d$iv_dead >= 0.25
  inside <- ifelse(d$iv_dead[kept] > 5, 0L, d$dead[kept])
  hazard <- lm_eval_job(lg_fixture("INTERVAL <- c(0.25, 5)")$job)
  expected <- hvtiRtemplates:::.lg_table(d$age[kept], inside, pmin(d$iv_dead[kept], 5) - 0.25, groups = 5L, link = "hazard")
  expect_equal(hazard$calibration$age$table, expected)
  expect_lt(sum(expected$events), sum(d$dead[kept]))
  logit <- lm_eval_job(lg_fixture(c("LINK <- \"logit\"", "INTERVAL <- c(0.25, 5)"))$job)
  expect_equal(logit$calibration$age$table, hvtiRtemplates:::.lg_table(d$age[kept], inside, groups = 5L, link = "logit"))
})
```

In `tests/testthat/test-template-figures.R`: add `"lg",` to `figure_templates` after `"lp-mirror",`, and in the `expected` list of `"every printed figure is also saved, under its documented name"` add the line `    lg = "lg-",` after the `lp-mirror` entry (the stem is built from the covariate, so the test looks for the `"lg-"` prefix on a `save_figure(` line, as it does for `nb-boostmtree`'s `"nb-boostmtree-effects-"`).

- [ ] **Step 2: Run them.**

```bash
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lg.R")'
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-template-figures.R")'
```

Expected FAIL: the first, `env$calibration` is `NULL` and the file expectations fail, four new failures (including the `INTERVAL` test); the second, the `"lg-"` expectation (`Expected any(grepl(...)) to be TRUE`).

- [ ] **Step 3: Implement.** In `lg.qmd`, insert the following immediately before the `provenance` chunk, after the `tbl-lg-variables` chunk of Task 6:

````markdown
## Calibration

For each covariate, a table of its groups and the figure of the groups' link
values against six scales of the covariate. Read the figure for the panel that
comes out straightest. The R-squared in each corner is only a guide: it is the
fit of a straight line weighted by group size, so a panel can score high and
still bend. A group whose link value cannot be computed keeps its row in the
table, blank, and is named under it. A scale that cannot be computed for the
covariate is drawn as an empty panel, and named there too.

```{r}
#| label: lg
#| results: asis
# unnumbered: each covariate's child chunks carry their own labels and captions
# The figure is saved as PNG and PDF under graphs/<subject>-<type>/lg-<covariate>,
# and the PNG is the one the report shows.
.fence <- strrep("`", 3)
.kable_na <- options(knitr.kable.NA = "")
calibration <- list()
for (i in seq_len(nrow(variables))) {
  .v <- variables[i, ]
  .tab <- hvtiRtemplates:::.lg_table(d[[.v$name]], .event, if (identical(LINK, "hazard")) .time,
                                     groups = .v$groups, kind = .v$kind, link = LINK)
  .scales <- hvtiRtemplates:::.lg_scales(.tab$mean, .v$constant, .v$shift)
  calibration[[.v$name]] <- list(table = .tab, scales = .scales)
  .plot <- hvtiRtemplates:::.lg_plot(.tab, .scales, LINK, title = .v$label)
  .file <- save_figure(.plot, paste0("lg-", .v$name), width = 9, height = 6, linked = TRUE)
  # This document sits in descriptive/ and the figure is written to graphs/, so
  # the image link is the figure's path relative to this document.
  .link <- xfun::relative_path(.file, if (!is.null(.in)) dirname(.in) else getwd(), error = FALSE)
  # A label holds letters, digits and hyphens, so an underscore in a name cannot
  # be read as markup in a cross-reference.
  .slug <- gsub("[^A-Za-z0-9]+", "-", .v$name)
  .heads <- c("Group", "Mean", "Minimum", "Maximum", "Patients", "Events",
              if (identical(LINK, "hazard")) "Events per unit of follow-up" else "Event rate",
              if (identical(LINK, "hazard")) "Log hazard rate" else "Logit")
  .cap_tbl <- paste0("Groups of ", .v$label, ", with the event rate and its link value")
  .cap_fig <- paste0(.v$label, ": the link value of each group against the covariate on six scales, ",
                     "with the R-squared of a weighted straight line")
  cat("\n### ", .v$label, "\n\n", sep = "")
  cat(knitr::knit_child(text = c(
    paste0(.fence, "{r}"), paste0("#| label: tbl-lg-", .slug),
    paste0("#| tbl-cap: ", encodeString(.cap_tbl, quote = "\"")),
    "knitr::kable(.tab, col.names = .heads, digits = 3, row.names = FALSE)", .fence, "",
    paste0(.fence, "{r}"), paste0("#| label: fig-lg-", .slug),
    paste0("#| fig-cap: ", encodeString(.cap_fig, quote = "\"")),
    "knitr::include_graphics(.link, error = FALSE)", .fence
  ), envir = environment(), quiet = TRUE), sep = "\n")
  .dropped <- attr(.tab, "dropped")
  .scale_notes <- attr(.scales, "notes")
  .left <- c(if (.dropped[["covariate"]] > 0L) paste0(.dropped[["covariate"]], " without a value of the covariate"),
             if (.dropped[["follow_up"]] > 0L) paste0(.dropped[["follow_up"]], " without follow-up"))
  .notes <- c(
    if (length(.left)) paste0("Left out of the groups: ", paste(.left, collapse = ", "), "."),
    if (.dropped[["event"]] > 0L) {
      paste0(.dropped[["event"]], " with no event value are ranked but counted in no group's rate.")
    },
    attr(.tab, "notes"),
    if (length(.scale_notes)) paste0(hvtiRtemplates:::.lg_panel_labels[names(.scale_notes)], ": ", .scale_notes)
  )
  if (length(.notes)) cat("\n", paste0("- ", .notes, collapse = "\n"), "\n", sep = "")
}
options(.kable_na)
```
````

- [ ] **Step 4: Run.** Both commands of Step 2. Expected PASS: `FAIL 0 | WARN 0 | SKIP 0` for `test-lg.R` and `FAIL 0` in `test-template-figures.R`.

- [ ] **Step 5: Commit.**

```bash
git add inst/templates/10_descriptive/lg.qmd tests/testthat/test-lg.R tests/testthat/test-template-figures.R
git commit -m "lg: tabulate and draw each covariate

A numbered group table and a numbered six-panel figure for each covariate in
VARIABLES, the figure saved as PNG and PDF under lg-<covariate>. A group or a
scale that cannot be computed is named under its table.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Mutation check.** Two mutations, each restored.

```bash
sed -i '' 's/link = LINK)$/link = "logit")/' inst/templates/10_descriptive/lg.qmd
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lg.R")' | grep "FAIL"
git checkout -- inst/templates/10_descriptive/lg.qmd
sed -i '' 's/gsub("\[^A-Za-z0-9\]+", "-", .v\$name)/.v$name/' inst/templates/10_descriptive/lg.qmd
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lg.R")' | grep "FAIL"
git checkout -- inst/templates/10_descriptive/lg.qmd
```

Expected: red in the first (the hazard job is calibrated on the logit link), `FAIL 1` or more in the second (an underscore reaches a label). `git status --short` is clean afterwards.

---

## Task 8: `lg-scales.rds`, the `PREDICTORS` line, and the blank-choice rule

**Files:**
- Modify: `R/logit-calibration.R` (append)
- Modify: `tests/testthat/test-logit-calibration.R` (append)
- Modify: `inst/templates/10_descriptive/lg.qmd` (insert before `provenance`)
- Modify: `tests/testthat/test-lg.R` (append)

**Interfaces:**
- Produces `.lg_choices(variables, scales)`: `scales` is a list of `.lg_scales()` results named by covariate; returns `list(table, problems)`. `table` has columns `variable`, `chosen`, `term`, `constant`, `shift`, one row for each covariate with a usable choice. `problems` is a named character vector (names are covariates): `no scale chosen yet`, or `the chosen scale, <id>, cannot be computed: <note>`.
- Produces `.lg_predictors(terms)`: the line `PREDICTORS <- c("log(age)", "nyha")`, one term a line when longer than 100 characters; `No scale is chosen yet, so there is no PREDICTORS line.` for no terms.
- Produces in the template: `choices`, `.predictors`, the saved file `estimates/<subject>-<type>/lg-scales.rds` (the table, with an `hvti_provenance` lineage attribute from `.attach_handoff_lineage()`), and child chunk `tbl-lg-scales` when any covariate is chosen. A problem warns in a draft and stops a final render before anything is saved, by `.strict_render()`, the rule `render_job(final = TRUE)` sets and the `EDIT:` guard obeys.
- Consumed by: Task 9.

- [ ] **Step 1: Write the failing tests.** Append to `tests/testthat/test-logit-calibration.R`:

```r
lg_chosen_fixture <- function() {
  variables <- data.frame(
    name = c("age", "wt", "nyha", "los"), kind = "continuous", groups = 5L, constant = c(50, 80, 2, 1),
    shift = c(0, 1, 0, 0), label = c("age", "wt", "nyha", "los"), chosen = c("log", "inverse", "raw", NA)
  )
  scales <- list(
    age = hvtiRtemplates:::.lg_scales(c(40, 50, 60), 50),
    wt = hvtiRtemplates:::.lg_scales(c(60, 80, 100), 80, 1),
    nyha = hvtiRtemplates:::.lg_scales(c(1, 2, 3), 2),
    los = hvtiRtemplates:::.lg_scales(c(0, 1, 2), 1)
  )
  list(variables = variables, scales = scales)
}

test_that(".lg_choices() gives each chosen scale as the term, constant and shift an lm job takes", {
  f <- lg_chosen_fixture()
  got <- hvtiRtemplates:::.lg_choices(f$variables[1:3, ], f$scales)
  expect_named(got$table, c("variable", "chosen", "term", "constant", "shift"))
  expect_identical(got$table$variable, c("age", "wt", "nyha"))
  expect_identical(got$table$chosen, c("log", "inverse", "raw"))
  expect_identical(got$table$term, c("log(age)", "I(80 / wt)", "nyha"))
  expect_identical(got$table$constant, c(50, 80, 2))
  expect_identical(got$table$shift, c(0, 1, 0))
  expect_length(got$problems, 0L)
})

test_that("a covariate with no choice, or a choice that cannot be computed, is a problem and not a row", {
  f <- lg_chosen_fixture()
  # los has no choice. Its log cannot be computed (a group mean is 0), so choosing it is a problem too.
  got <- hvtiRtemplates:::.lg_choices(f$variables, f$scales)
  expect_identical(got$table$variable, c("age", "wt", "nyha"))
  expect_identical(unname(got$problems), "no scale chosen yet")
  expect_named(got$problems, "los")
  f$variables$chosen[[4L]] <- "log"
  got <- hvtiRtemplates:::.lg_choices(f$variables, f$scales)
  expect_identical(got$table$variable, c("age", "wt", "nyha"))
  expect_named(got$problems, "los")
  expect_match(got$problems[["los"]], "^the chosen scale, log, cannot be computed: A group mean plus the shift is not positive")
  # Nothing chosen at all is an empty table with the same columns, and a problem for each.
  none <- hvtiRtemplates:::.lg_choices(transform(f$variables, chosen = NA_character_), f$scales)
  expect_identical(nrow(none$table), 0L)
  expect_named(none$table, c("variable", "chosen", "term", "constant", "shift"))
  expect_named(none$problems, c("age", "wt", "nyha", "los"))
})

test_that(".lg_predictors() writes the PREDICTORS line to copy into an lm job, and it reads back as the terms", {
  line <- hvtiRtemplates:::.lg_predictors(c("log(age)", "I(80 / wt)", "nyha"))
  expect_identical(line, "PREDICTORS <- c(\"log(age)\", \"I(80 / wt)\", \"nyha\")")
  # The parse() calls read back strings this test built, to show they are valid R and name what was given.
  expect_identical(eval(parse(text = line)), c("log(age)", "I(80 / wt)", "nyha"))
  # A long one goes a term to a line, and still reads back.
  terms <- paste0("I(exp(covariate_number_", 1:6, " / 50))")
  long <- hvtiRtemplates:::.lg_predictors(terms)
  expect_match(long, "^PREDICTORS <- c[(]\n  \"I[(]exp[(]covariate_number_1 / 50[)][)]\",\n")
  expect_match(long, "\n[)]$")
  expect_identical(eval(parse(text = long)), terms)
  expect_identical(hvtiRtemplates:::.lg_predictors(character()), "No scale is chosen yet, so there is no PREDICTORS line.")
})
```

Append to `tests/testthat/test-lg.R`:

```r
test_that("the job saves lg-scales.rds with the term, constant and shift of each chosen scale, and the PREDICTORS line", {
  local_child_chunks()
  d <- lg_data()
  s <- lg_fixture(variables = c(
    "VARIABLES <- data.frame(",
    "  name = c(\"age\", \"nyha\"),",
    "  kind = c(\"continuous\", \"ordinal\"),",
    "  chosen = c(\"log\", \"inverse\")",
    ")"
  ))
  # Nothing is warned when every covariate has a usable choice.
  expect_no_warning(env <- lm_eval_job(s$job))
  saved <- readRDS(file.path(hvtiRutilities::study_dir("estimates", s$root), "dead-calibration", "lg-scales.rds"))
  expect_s3_class(saved, "data.frame")
  expect_named(saved, c("variable", "chosen", "term", "constant", "shift"))
  expect_identical(saved$variable, c("age", "nyha"))
  expect_identical(saved$chosen, c("log", "inverse"))
  expect_identical(saved$constant, c(signif(stats::median(d$age), 1L), signif(stats::median(d$nyha), 1L)))
  expect_identical(saved$shift, c(0, 0))
  # The term is the constant and the name, written as an lm job takes it.
  expect_identical(saved$term, c("log(age)", paste0("I(", saved$constant[[2L]], " / nyha)")))
  expect_identical(env$.predictors, paste0("PREDICTORS <- c(\"log(age)\", \"", saved$term[[2L]], "\")"))
  # The file carries the lineage of the data it came from, and no patient.
  lineage <- attr(saved, "hvti_provenance")
  expect_length(lineage$data, 1L)
  expect_identical(lineage$analysis$event, "dead")
  expect_identical(lineage$analysis$link, "hazard")
  expect_identical(lineage$cohort$patients, nrow(d))
  # The terms go into a model as they stand: lm's own check finds the columns, and the model fits.
  expect_silent(hvtiRtemplates:::.check_job_columns(d, PREDICTORS = saved$term))
  fit <- stats::glm(stats::reformulate(saved$term, response = "hdead"), family = stats::binomial, data = d)
  expect_s3_class(fit, "glm")
})

test_that("a blank chosen warns in a draft, saves only the covariates chosen, and stops a final render", {
  local_child_chunks()
  two <- c(
    "VARIABLES <- data.frame(",
    "  name = c(\"age\", \"nyha\"),",
    "  chosen = c(\"log\", NA)",
    ")"
  )
  s <- lg_fixture(variables = two)
  file <- file.path(hvtiRutilities::study_dir("estimates", s$root), "dead-calibration", "lg-scales.rds")
  expect_warning(env <- lm_eval_job(s$job),
                 "^These covariates have no usable scale chosen: `nyha`: no scale chosen yet. Read each figure")
  expect_identical(names(env$choices$problems), "nyha")
  expect_identical(readRDS(file)$variable, "age")
  expect_identical(env$.predictors, "PREDICTORS <- c(\"log(age)\")")
  unlink(file)
  # A final render, with HVTI_TEMPLATE_STRICT set as render_job(final = TRUE) sets it, stops, and saves nothing.
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "1")
  expect_error(lm_eval_job(s$job), paste0("^These covariates have no usable scale chosen: `nyha`: no scale chosen yet.*",
                                          "This render stops because HVTI_TEMPLATE_STRICT is '1'"))
  expect_false(file.exists(file))
  # Unset, or set to a false word, it is a draft again.
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "false")
  expect_warning(lm_eval_job(s$job), "no usable scale chosen")
})

test_that("the template's own blank chosen is a draft warning for the first covariate", {
  local_child_chunks()
  s <- lg_fixture(variables = NULL)
  expect_warning(env <- lm_eval_job(s$job), "^These covariates have no usable scale chosen: `age`: no scale chosen yet")
  expect_identical(nrow(readRDS(file.path(hvtiRutilities::study_dir("estimates", s$root), "dead-calibration", "lg-scales.rds"))), 0L)
  expect_identical(env$.predictors, "No scale is chosen yet, so there is no PREDICTORS line.")
})

test_that("a chosen scale that cannot be computed warns in a draft and stops a final render", {
  local_child_chunks()
  # n_prior is 0 in its lowest group, so its log is undefined.
  s <- lg_fixture(variables = c(
    "VARIABLES <- data.frame(",
    "  name = c(\"n_prior\"),",
    "  constant = c(1),",
    "  chosen = c(\"log\")",
    ")"
  ))
  expect_warning(lm_eval_job(s$job),
                 "`n_prior`: the chosen scale, log, cannot be computed: A group mean plus the shift is not positive")
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "yes")
  expect_error(lm_eval_job(s$job), "`n_prior`: the chosen scale, log, cannot be computed")
  # A shift makes it computable, and the term says so.
  fixed <- lg_fixture(variables = c(
    "VARIABLES <- data.frame(",
    "  name = c(\"n_prior\"),",
    "  constant = c(1),",
    "  shift = c(1),",
    "  chosen = c(\"log\")",
    ")"
  ))
  env <- lm_eval_job(fixed$job)
  expect_identical(env$choices$table$term, "log(n_prior + 1)")
})
```

- [ ] **Step 2: Run them.** Both files, as in Task 6. Expected FAIL: the first, `object '.lg_choices' not found` and `object '.lg_predictors' not found` (`FAIL 3`); the second, `env$choices` `NULL`, no warning where one is expected, and `gzfile(file, "rb")` cannot open the missing `lg-scales.rds`.

- [ ] **Step 3: Implement the functions.** Append to `R/logit-calibration.R`:

```r
# The choices made, as the table lg-scales.rds holds: variable, chosen, term,
# constant and shift, one row for each covariate with a usable choice. `scales`
# is a list of .lg_scales() results by covariate name. A covariate with no choice,
# or whose chosen scale cannot be computed, is not a row: it is named in
# $problems with the reason, so the job can warn in a draft and stop a final
# render, as an open EDIT marker does.
.lg_choices <- function(variables, scales) {
  problems <- character()
  usable <- logical(nrow(variables))
  for (i in seq_len(nrow(variables))) {
    name <- variables$name[[i]]
    chosen <- variables$chosen[[i]]
    if (is.na(chosen)) {
      problems[[name]] <- "no scale chosen yet"
    } else if (all(is.na(scales[[name]][[chosen]]))) {
      problems[[name]] <- paste0("the chosen scale, ", chosen, ", cannot be computed: ", attr(scales[[name]], "notes")[[chosen]])
    } else {
      usable[[i]] <- TRUE
    }
  }
  kept <- variables[usable, , drop = FALSE]
  terms <- vapply(seq_len(nrow(kept)), function(i) {
    .lg_term(kept$name[[i]], kept$chosen[[i]], kept$constant[[i]], kept$shift[[i]])
  }, character(1L))
  list(
    table = data.frame(variable = kept$name, chosen = kept$chosen, term = terms, constant = kept$constant,
                       shift = kept$shift, stringsAsFactors = FALSE),
    problems = problems
  )
}

# The line an lm job's PREDICTORS takes for these terms: on one line when it fits
# in 100 characters, a term to a line when it does not.
.lg_predictors <- function(terms) {
  if (!length(terms)) return("No scale is chosen yet, so there is no PREDICTORS line.")
  items <- encodeString(terms, quote = "\"")
  one <- paste0("PREDICTORS <- c(", paste(items, collapse = ", "), ")")
  if (nchar(one) <= 100L) return(one)
  paste0("PREDICTORS <- c(\n", paste0("  ", items, collapse = ",\n"), "\n)")
}
```

- [ ] **Step 4: Implement the template chunk.** In `lg.qmd`, insert the following immediately before the `provenance` chunk, after the `lg` chunk of Task 7:

````markdown
## Chosen scales

Once you have read the figures, set `chosen` for each covariate in `VARIABLES`
and render again. The job saves the choice as `lg-scales.rds`, one row for each
covariate: the scale, the term to write for it, and the constant and shift it
used. The term goes into the `PREDICTORS` of an `lm` job as it stands, so the
model is fitted on the scale the figure showed.

A covariate with no choice, or whose chosen scale cannot be computed, is not
saved. In a draft the job warns and lists it here; a final render stops, as it
does for an open marker, so a finished job has chosen every scale.

```{r}
#| label: choices
#| results: asis
# unnumbered: its child chunk carries its own label and caption
choices <- hvtiRtemplates:::.lg_choices(variables, lapply(calibration, `[[`, "scales"))
if (length(choices$problems)) {
  .msg <- paste0("These covariates have no usable scale chosen: ",
                 paste0("`", names(choices$problems), "`: ", choices$problems, collapse = "; "),
                 ". Read each figure above and set chosen for it in VARIABLES.")
  if (hvtiRtemplates:::.strict_render()) {
    stop(.msg, "\nThis render stops because HVTI_TEMPLATE_STRICT is '", Sys.getenv("HVTI_TEMPLATE_STRICT"),
         "': a final report names a scale for every covariate. Unset it, or set it to 0, false or no, ",
         "to render a draft instead.", call. = FALSE)
  }
  warning(.msg, "\nRendering as a draft; the banner goes when every covariate has a choice.", call. = FALSE)
  cat("\n::: {.callout-important title=\"DRAFT -- a scale is not chosen\"}\n", .msg, "\n:::\n\n", sep = "")
}
# What is saved holds the covariates with a usable choice and no patient: the
# scale, its term, constant and shift. Its lineage says which data it came from.
saveRDS(
  hvtiRtemplates:::.attach_handoff_lineage(
    choices$table,
    data = .provenance_data,
    analysis = Filter(Negate(is.null), list(event = EVENT, link = LINK, time = if (.needs_time) TIME, interval = INTERVAL)),
    cohort = list(patients = nrow(d)),
    selection = attr(job_data$record, "selection")
  ),
  set_path("estimates", "lg-scales.rds")
)
if (nrow(choices$table)) {
  .fence <- strrep("`", 3)
  cat(knitr::knit_child(text = c(
    paste0(.fence, "{r}"), "#| label: tbl-lg-scales",
    "#| tbl-cap: \"The scale chosen for each covariate, and the term to write for it in an lm job\"",
    "knitr::kable(choices$table, col.names = c(\"Covariate\", \"Scale\", \"Term\", \"Constant\", \"Shift\"), row.names = FALSE)",
    .fence
  ), envir = environment(), quiet = TRUE), sep = "\n")
}
.predictors <- hvtiRtemplates:::.lg_predictors(choices$table$term)
if (nrow(choices$table)) {
  cat("\nThe line to copy into the `PREDICTORS` of an `lm` job, beside its other predictors:\n\n",
      "```r\n", .predictors, "\n```\n", sep = "")
} else {
  cat("\n", .predictors, "\n", sep = "")
}
```
````

- [ ] **Step 5: Run.** Both files. Expected PASS: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 213 ]` and `FAIL 0 | WARN 0 | SKIP 0` for `test-lg.R`.

- [ ] **Step 6: Commit.**

```bash
git add R/logit-calibration.R inst/templates/10_descriptive/lg.qmd tests/testthat/test-logit-calibration.R tests/testthat/test-lg.R
git commit -m "lg: save the chosen scales and print the PREDICTORS line

lg-scales.rds holds the term, constant and shift of each covariate's chosen
scale, with the lineage of the data, and the job prints the PREDICTORS line to
copy into an lm job. A covariate with no choice, or one whose chosen scale
cannot be computed, warns in a draft and stops a final render before anything
is saved, as an open EDIT marker does.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Mutation check.** Two mutations, each restored.

```bash
sed -i '' 's/if (hvtiRtemplates:::.strict_render()) {/if (FALSE) {/' inst/templates/10_descriptive/lg.qmd
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lg.R")' | grep "FAIL"
git checkout -- inst/templates/10_descriptive/lg.qmd
sed -i '' 's/    if (is.na(chosen)) {/    if (FALSE) {/' R/logit-calibration.R
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-logit-calibration.R")' | grep "FAIL"
git checkout -- R/logit-calibration.R
```

Expected: `[ FAIL 3 | ... ]` (a final render no longer stops) and red (a blank choice is no longer a problem). `git status --short` is clean afterwards.

---

## Task 9: Provenance, the render, and no identifiers

**Files:**
- Modify: `inst/templates/10_descriptive/lg.qmd` (the `provenance` chunk)
- Modify: `tests/testthat/test-lg.R` (append)

**Interfaces:**
- Consumes `.provenance_data`, `.needs_time`, `INTERVAL`, `variables`, `choices`, `d`.
- Produces in the embedded payload, beside `subject` and `type`: `lg`, a list with `event`, `link`, `time` (only when read), `interval` (`start`, `end`, `left_out`, `kept`, `censored`, only with `INTERVAL`), `patients` (the patients calibrated), `variables` (the completed `VARIABLES` table, one entry for each covariate, a scale not yet chosen left out) and `unresolved` (the covariates with no usable choice, when any). `data` carries the dataset the job read; no patient, no identifier.

- [ ] **Step 1: Write the failing test.** Append to `tests/testthat/test-lg.R`. It renders the job through Quarto twice, without and with an `INTERVAL`, and scans the report for every patient identifier, raw and digested. The scan drops `data:` URIs first, since base64 text can spell any digit run, and matches an identifier only as a whole token.

```r
test_that("the job renders two figures and two tables for two covariates, naming no patient", {
  skip_on_cran()
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("quarto")
  skip_if_not(quarto::quarto_available())
  d <- lg_data()
  windows <- list(none = character(), window = "INTERVAL <- c(0.25, 5)")
  for (window in names(windows)) {
    s <- lg_fixture(windows[[window]], variables = c(
      "VARIABLES <- data.frame(",
      "  name = c(\"age\", \"nyha\"),",
      "  kind = c(\"continuous\", \"ordinal\"),",
      "  chosen = c(\"log\", \"raw\")",
      ")"
    ))
    quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = TRUE)
    html <- paste(readLines(sub("[.]qmd$", ".html", s$job), warn = FALSE), collapse = "\n")
    # Two figures and two tables, one of each for each covariate, numbered; the window table only with INTERVAL.
    ids <- function(prefix) {
      found <- regmatches(html, gregexpr(paste0("id=\"", prefix, "-lg-[a-z-]+\""), html))[[1L]]
      sort(unique(sub("^id=\"(.*)\"$", "\\1", found)))
    }
    expect_identical(ids("fig"), c("fig-lg-age", "fig-lg-nyha"), info = window)
    expect_identical(ids("tbl"), sort(c("tbl-lg-age", "tbl-lg-nyha", "tbl-lg-scales", "tbl-lg-variables",
                                        if (window == "window") "tbl-lg-interval")), info = window)
    graphs <- file.path(hvtiRutilities::study_dir("graphs", s$root), "dead-calibration")
    expect_setequal(list.files(graphs), c("lg-age.png", "lg-age.pdf", "lg-nyha.png", "lg-nyha.pdf"))
    # The choices are saved with the right terms, and the report prints the line to copy.
    saved <- readRDS(file.path(hvtiRutilities::study_dir("estimates", s$root), "dead-calibration", "lg-scales.rds"))
    expect_identical(saved$term, c("log(age)", "nyha"), info = window)
    plain <- gsub("<[^>]+>", "", html)
    expect_match(plain, "PREDICTORS &lt;- c(&quot;log(age)&quot;, &quot;nyha&quot;)", fixed = TRUE)
    # No patient identifier, raw or digested, appears in the report. Embedded images and fonts are base64
    # data URIs, whose text can spell any short digit run by chance, so they are dropped before the scan,
    # and an identifier counts only as a whole token. The provenance JSON is not a data URI, so it is scanned.
    text <- gsub("data:[A-Za-z0-9.+/-]+(;[^,\"')]*)?,[^\"') ]*", "", html, perl = TRUE)
    key <- hvtiRtemplates:::.study_id_key(s$root)
    for (id in c(as.character(d$ccfid), hvtiRtemplates:::.id_digest(d$ccfid, key))) {
      at <- regexpr(paste0("(?<![A-Za-z0-9])", id, "(?![A-Za-z0-9])"), text, perl = TRUE)[[1L]]
      # On a hit, show the text around it, so a CI failure says where it came from.
      expect_false(at > 0L, info = if (at > 0L) substring(text, max(1L, at - 120L), at + 120L) else id)
    }
    # The provenance names the data read, the choices and the window, never a patient.
    payload <- hvtiRtemplates:::.extract_provenance(html, managed = TRUE)
    expect_length(payload$data, 1L)
    expect_identical(payload$lg$event, "dead")
    expect_identical(payload$lg$link, "hazard")
    expect_identical(payload$lg$time, "iv_dead")
    expect_identical(vapply(payload$lg$variables, function(v) v$name, ""), c("age", "nyha"))
    expect_identical(vapply(payload$lg$variables, function(v) v$chosen, ""), c("log", "raw"))
    if (window == "window") {
      kept <- d$iv_dead >= 0.25
      expect_identical(unlist(payload$lg$interval), c(start = 0.25, end = 5, left_out = sum(!kept), kept = sum(kept),
                                                      censored = sum(kept & d$iv_dead > 5)))
      expect_identical(payload$lg$patients, sum(kept))
    } else {
      expect_null(payload$lg$interval)
      expect_identical(payload$lg$patients, nrow(d))
    }
  }
})
```

- [ ] **Step 2: Reinstall and run.**

```bash
R_LIBS=$SCRATCH/lib-lg R CMD INSTALL --no-docs -l $SCRATCH/lib-lg .
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lg.R")'
```

Expected FAIL: the figures, tables, saved file and identifier scan pass already, and the payload expectations fail: `payload$lg$event` is `NULL`, and so are `link`, `time`, `variables` and the `interval` ones. About 30 seconds for the two renders.

- [ ] **Step 3: Implement.** In `lg.qmd`, replace the `cat(...)` call in the `provenance` chunk,

```r
cat(hvtiRtemplates:::.embed_provenance(
  .in,
  data = .provenance_data,
  extra = list(subject = SUBJECT, type = TYPE)
))
```

with:

```r
cat(hvtiRtemplates:::.embed_provenance(
  .in,
  data = .provenance_data,
  extra = list(
    subject = SUBJECT,
    type = TYPE,
    lg = Filter(Negate(is.null), list(
      event = EVENT, link = LINK, time = if (.needs_time) TIME,
      interval = if (!is.null(INTERVAL)) {
        .n <- .interval$counts$patients
        list(start = INTERVAL[[1L]], end = INTERVAL[[2L]], left_out = .n[[2L]] + .n[[3L]], kept = .n[[4L]], censored = .n[[5L]])
      },
      patients = nrow(d),
      # The VARIABLES table as the job completed it, one entry for each covariate. A scale not yet chosen is left out.
      variables = lapply(seq_len(nrow(variables)), function(i) Filter(Negate(is.na), as.list(variables[i, ]))),
      unresolved = if (length(choices$problems)) names(choices$problems)
    ))
  )
))
```

- [ ] **Step 4: Reinstall and run.**

```bash
R_LIBS=$SCRATCH/lib-lg R CMD INSTALL --no-docs -l $SCRATCH/lib-lg .
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lg.R")'
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-template-provenance.R")'
```

Expected PASS: `test-lg.R` `FAIL 0`, `SKIP 0`; `test-template-provenance.R` `FAIL 0`.

- [ ] **Step 5: Look at the report.** Render one job by hand and read it, as a study author would:

```bash
R_LIBS=$SCRATCH/lib-lg Rscript -e 'devtools::load_all(quiet=TRUE); source("tests/testthat/helper-lm.R"); s <- lg_fixture(variables = c("VARIABLES <- data.frame(", "  name = c(\"age\", \"nyha\"),", "  kind = c(\"continuous\", \"ordinal\"),", "  chosen = c(\"log\", \"raw\")", ")"), .local_envir = globalenv()); quarto::quarto_render(s$job, execute_dir = dirname(s$job), quiet = TRUE); file.copy(sub("[.]qmd$", ".html", s$job), file.path(Sys.getenv("SCRATCH"), "lg-report.html"), overwrite = TRUE)'
```

Open `$SCRATCH/lg-report.html` and the two PNGs under the study's `graphs/dead-calibration/`. Expected: the data table; the covariates table; for each covariate a heading, a numbered group table, a numbered six-panel figure; a `Chosen scales` section with the scale table and a `PREDICTORS <- c("log(age)", "nyha")` code block; no banner. If a figure or table reads badly, fix it here and rerun Step 4 before committing.

- [ ] **Step 6: Commit.**

```bash
git add inst/templates/10_descriptive/lg.qmd tests/testthat/test-lg.R
git commit -m "lg: record the choices and the window in the provenance

The payload names the event, link and follow-up read, the INTERVAL and what it
kept, and the completed VARIABLES table. A rendered report names no patient,
raw or digested.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Mutation check.** Print one identifier and confirm the render test catches it; restore.

```bash
sed -i '' 's/^calibration <- list()$/calibration <- list()\ncat(d[[.id]][1L], "\\n")/' inst/templates/10_descriptive/lg.qmd
grep -n 'cat(d\[\[.id\]\]\[1L\]' inst/templates/10_descriptive/lg.qmd
R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e 'devtools::load_all(quiet=TRUE); testthat::test_file("tests/testthat/test-lg.R")' | grep "FAIL"
git checkout -- inst/templates/10_descriptive/lg.qmd
```

Expected: `grep` prints the inserted line, and the render test fails on `8300001` (the first identifier) in both passes, `[ FAIL 2 | ... ]`. If BSD `sed` wrote a literal `n`, `grep` prints nothing: insert the line with an editor and rerun. `git status --short` is clean afterwards. No reinstall is needed after the restore: the render reads the template through `add_job()` under `load_all()`, and the installed internals did not change.

---

## Task 10: The gallery job

**Files:**
- Modify: `dev/gallery/family-descriptive.R`
- Modify: `dev/gallery/notes.json`

**Interfaces:** produces the gallery job `lg` (set `dead-calibration`): death against age (continuous, five rank groups) and NYHA class `nyha_pr` (ordinal), `LINK <- "hazard"`, with `chosen` filled in so `render_job(final = TRUE)` accepts it. The gallery is dev tooling with no test file; its verification is the render in Step 3.

- [ ] **Step 1: Add the job.** In `dev/gallery/family-descriptive.R`, replace the `dc-stddiff` job (from its `"dc-stddiff" = list(` line to the `)))` that closes it) with the block below: the same job, followed by a comma and the new one. The template's `VARIABLES` is one value to a line, so each line is replaced whole.

```r
      "dc-stddiff" = list(subject = "approach", type = "balance", choices = c(whole_cohort, demo_id, list(
        "^GROUP <- " = "GROUP <- \"approach\"",
        "^GROUP_1 <- " = "GROUP_1 <- \"transcatheter\"",
        "^GAUSSIAN    <- " = "GAUSSIAN    <- c(\"age\", \"bmi\", \"lvef\")",
        "^NONG_ORD    <- " = "NONG_ORD    <- \"nyha_pr\"",
        "^BINARY      <- " = "BINARY      <- c(\"female\", \"hx_chf\", \"hx_dm\")",
        "^CATEGORICAL <- " = "CATEGORICAL <- \"race_grp\"",
        "^N_PERM <- " = "N_PERM <- 200L"
      ))),
      # Death against age (continuous, five rank groups) and NYHA class (ordinal, a group each), on the
      # constant-hazard link, with the scale chosen for each once the figures were read.
      "lg" = list(subject = "dead", type = "calibration", choices = c(whole_cohort, demo_id, list(
        "^  name   = c\\(\"age\"\\),$" = "  name   = c(\"age\", \"nyha_pr\"),",
        "^  kind   = c\\(\"continuous\"\\),$" = "  kind   = c(\"continuous\", \"ordinal\"),",
        "^  chosen = c\\(NA\\)$" = "  chosen = c(\"raw\", \"raw\")"
      )))
```

The defaults the template already carries are right for the demo cohort: `EVENT <- "dead"`, `LINK <- "hazard"`, `TIME <- "iv_dead"`.

- [ ] **Step 2: Add the gallery note.** In `dev/gallery/notes.json`, after the `"dc-eda"` entry, add:

```json
  "lg": {
    "issues": [],
    "note": "Death against age and NYHA class on the constant-hazard link, with the scale chosen for each. A real study reads the figures before it fills chosen in."
  },
```

Check the file still parses: `python3 -c 'import json; json.load(open("dev/gallery/notes.json"))'` prints nothing.

- [ ] **Step 3: Reinstall and render the job.** Run from the repo root, through `Rscript -e`, so `gallery.R` finds `dev/gallery` from the working directory:

```bash
R_LIBS=$SCRATCH/lib-lg R CMD INSTALL --no-docs -l $SCRATCH/lib-lg .
rm -rf $SCRATCH/lg-gallery
R_LIBS=$SCRATCH/lib-lg Rscript -e 'source("dev/gallery/gallery.R"); root <- gallery_study("'"$SCRATCH"'/lg-gallery/study"); built <- gallery_build(root, only = "lg"); print(built[, c("template", "seconds", "error")], row.names = FALSE); print(list.files(study_dir("graphs", root), recursive = TRUE)); print(readRDS(file.path(study_dir("estimates", root), "dead-calibration", "lg-scales.rds")))'
```

Expected: one row, `error` `NA`; `lg-age.png`, `lg-age.pdf`, `lg-nyha_pr.png` and `lg-nyha_pr.pdf` under `dead-calibration/`; the saved table with `age` and `nyha_pr` both `raw`, terms `age` and `nyha_pr`, constants 60 and 2. Open `lg-age.png`: five points rising with age in every panel, the Raw panel straightest (`R-squared = 0.99` on the demo cohort), which is why the job chooses `raw`.

- [ ] **Step 4: Commit.** `dev/` is build-ignored, so this commit ships nothing.

```bash
git add dev/gallery/family-descriptive.R dev/gallery/notes.json
git commit -m "Gallery: add the lg job

Death against age and NYHA class on the constant-hazard link, with the raw
scale chosen for each once the figures were read, so the job renders as a
final report.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 11: Docs, news fragment, full gates and the pull request

**Files:**
- Modify: `inst/templates/README.md` (template table; figure-name table)
- Create: `news/feat-lg.md`

**Interfaces:** consumes everything above; produces the pull request.

- [ ] **Step 1: README.** In `inst/templates/README.md`: after the row for `10_descriptive/dc-trends.qmd` in the template table, add

```markdown
| `10_descriptive/lg.qmd` | logit calibration: an event's group rates against six scales of a covariate, and the scale chosen for an `lm` job | `10_descriptive/` or `descriptive/` |
```

and in the figure-name table, before the `lp-mirror` row, add

```markdown
| lg | `lg-<covariate>`, one for each covariate in `VARIABLES`, such as `lg-age` |
```

- [ ] **Step 2: News fragment.** Create `news/feat-lg.md`:

```markdown
* New template `lg`, logit calibration: `add_job("lg", subject, type)`, usually
  with the outcome as the subject, as in `lg.dead.calibration`. It decides which
  scale a covariate should enter a model on, before it goes into `PREDICTORS` in
  an `lm` job. Each covariate in `VARIABLES`, continuous or ordinal, is ranked
  into groups as `PROC RANK GROUPS=` does, or takes each level as a group, as
  `%logitgr` did. The job takes each group's event rate on the logit, or, for
  time-related death, the log of the constant hazard, and plots it against the
  covariate on six scales (raw, log, inverse, inverse squared, squared and
  exponential), each panel with the R-squared of a straight line weighted by
  group size. `INTERVAL = c(start, end)` takes one phase of follow-up as the SAS
  early, constant and late jobs did: patients who ended before `start` are left out, the rest are
  censored at `end`, and the hazard sums their time at risk inside the window. The scale chosen for each covariate is
  saved as `lg-scales.rds` with the term to write for it, such as `log(age)` or
  `I(50 / weight)`, and the job prints the `PREDICTORS` line to copy into an
  `lm` job. A blank `chosen` warns in a draft and stops a final render, as an
  open `EDIT:` marker does. A group whose link value cannot be computed keeps
  its row, blank, and is named under its table; a scale that cannot be
  computed for a covariate is drawn as an empty panel. The catalog name of `lg`
  becomes "Logit calibration": the 12 `lg.trends` jobs go to `dc-trends`.
```

- [ ] **Step 3: Commit the docs.**

```bash
git add inst/templates/README.md news/feat-lg.md
git commit -m "Document lg and add its news fragment

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 4: Gate: roxygen leaves no diff.**

```bash
R_LIBS=$SCRATCH/lib-lg Rscript -e 'devtools::document()'
git status --short
```

Expected: `git status --short` prints nothing (the internals carry plain comments, no roxygen).

- [ ] **Step 5: Gate: lint.**

```bash
R_LIBS=$SCRATCH/lib-lg Rscript -e 'l <- lintr::lint_package(); print(l); quit(status = length(l) > 0)'
```

Expected: `No lints found.`, exit 0.

- [ ] **Step 6: Gate: the full suite, one file per command.** Reinstall first, then run every test file:

```bash
R_LIBS=$SCRATCH/lib-lg R CMD INSTALL --no-docs -l $SCRATCH/lib-lg .
for f in tests/testthat/test-*.R; do echo "== $f"; R_LIBS=$SCRATCH/lib-lg NOT_CRAN=true Rscript -e "devtools::load_all(quiet=TRUE); testthat::test_file('$f')" 2>&1 | grep -E "FAIL [0-9]+ \| WARN [0-9]+ \| SKIP [0-9]+ \| PASS [0-9]+"; done
```

Expected: every line `FAIL 0`, apart from anything recorded in Task 0's baseline file, which must be unchanged. `SKIP 0` everywhere on macOS. `WARN 0` everywhere except `test-rf-templates.R`, whose known varPro notices are muffled on CI but can show locally; compare its WARN count with the baseline rather than accepting it unread. Any other WARN, SKIP or FAIL is new and is investigated before going on.

- [ ] **Step 7: Gate: the three count scripts, spelling and identifiers.**

```bash
python3 dev/specs/artifacts/check-roadmap-counts.py
python3 dev/specs/artifacts/check-spec-counts.py
python3 dev/specs/artifacts/check-flow-counts.py
bash tools/check-us-spelling.sh
bash tools/check-no-site-identifiers.sh
```

Expected: `Catalog agrees with disk: 65 template rows routed to hvtiRtemplates, 34 on disk.`, `Spec agrees with the map: ...`, `Diagrams agree with the maps: ...`, and the two shell checks silent or reporting clean; each exits 0.

- [ ] **Step 8: Gate: the news check, after committing.**

```bash
git fetch origin
python3 .github/scripts/news.py check --base origin/main
```

Expected: exit 0, the fragment `news/feat-lg.md` found.

- [ ] **Step 9: Gate: the gallery render.** Rerun Task 10 Step 3 verbatim. Expected: one row, `error` `NA`.

- [ ] **Step 10: Gate: no em-dashes in the added lines.**

```bash
git diff origin/main...HEAD -- . ':!dev/specs/2026-08-29-template-conversion-roadmap.md' | python3 -c 'import sys; hits = [l for l in sys.stdin if l.startswith("+") and "\u2014" in l]; print("".join(hits) or "none")'
```

Expected: `none`. The regenerated roadmap is excluded because its renderer marks an empty cell with that character.

- [ ] **Step 11: Gate: local code review.** Run `/code-review` on the branch diff against `origin/main`. Fix every correctness finding with its own commit, rerun the affected test files and Steps 5 to 8, and record in the PR body that the local review stood in for the bot (AGENTS.md: Copilot reviews only the commit a PR is opened with).

- [ ] **Step 12: Push and open the PR.**

```bash
git push -u origin feat/lg
gh pr create --base main --title "New template: lg" --body "$(cat <<'EOF'
Implements dev/specs/2026-10-11-lg-template-design.md, following dev/specs/2026-10-11-lg-template-plan.md.

- New `inst/templates/10_descriptive/lg.qmd`, logit calibration: for each covariate it groups the patients (`PROC RANK GROUPS=` exactly, or a group per level for an ordinal one), takes each group's event rate on the logit or constant-hazard link, and plots it against six scales of the covariate with the weighted R-squared of a straight line. `INTERVAL = c(start, end)` takes one phase of follow-up as the SAS constant-phase template did: patients who ended before `start` are left out and the rest are censored at `end`. The scale chosen for each covariate is saved as `lg-scales.rds` with its `lm` term, and the job prints the `PREDICTORS` line to copy. A blank `chosen` warns in a draft and stops a final render.
- The numerical core is internal, in `R/logit-calibration.R`, tested on hand-worked fixtures including a 12-row PROC RANK parity fixture with ties.
- The `lg` ledger row is shipped and renamed "Logit calibration"; the roadmap is re-rendered.
- Gallery: an `lg` job on age and NYHA class.

Gates: `devtools::document()` no diff; `lintr::lint_package()` 0; full suite FAIL 0, one file per command, `NOT_CRAN=true`; the three count scripts, the spelling and identifier checks and `news.py check`; gallery render. A local `/code-review` stood in for the Copilot review on every push after the first.

No new dependency and no floor moves. `Version:` untouched.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Do not merge.

---

## Decisions this plan makes where the spec was silent or the code disagreed

1. **The taxonomy name lives in another package.** The spec says the taxonomy name changes from "Logit trends" to "Logit calibration" in `inst/extdata/templates.json`. That file is this package's catalog, and the `name` there is what changes. `hvti_taxonomy()` is re-exported from hvtiRutilities and still reads "Logit trends"; the maintainer is renaming that row in a separate hvtiRutilities PR. No test here compares the two.
2. **`lg-scales.rds` sits in the job's set folder.** The spec says `estimates/lg-scales.rds`. Every template saves into `estimates/<subject>-<type>/` through `set_path()`, and a flat file would collide between two `lg` jobs in one study, so it is `estimates/<subject>-<type>/lg-scales.rds`. It carries the `hvti_provenance` lineage like every other saved artifact, though no job reads it back: an `lm` job takes the printed `PREDICTORS` line.
3. **An impossible scale is empty for the whole covariate.** The spec says a scale that cannot be computed "is drawn empty with a note". The plan reads that as the whole panel, not only the group that breaks it: a line through the other groups of a log scale with one group at 0 would look straight and mean nothing. A chosen scale that is empty is a problem (Task 8).
4. **A patient with no event value is ranked, not counted.** `%logit` deletes a missing covariate (and, with `cox=1`, a missing interval) before `PROC RANK`, but leaves a patient with a missing event in the ranking, where `PROC SUMMARY`'s `N(&EVENT)` simply does not count it. `.lg_table()` does the same, so the groups match SAS exactly, and reports how many it left out and how many it ranked without counting.
5. **`rate` is events per unit of follow-up under `"hazard"`.** The SAS output table's `PROB` column was the plain proportion even with `cox=1`, while the link used `events / sum(interval)`. The spec names one `rate` column, so it is the quantity the link is the log of: the proportion for `"logit"`, events per unit of follow-up for `"hazard"`.
6. **`INTERVAL = c(start, end)` follows the SAS constant-phase template, with one shift.** The maintainer's rule, read against the legacy `tp.lg.dead.constant` (`if iv_dead<(3/12) then delete; if iv_dead>5 then do; dead=0; iv_dead=5; end;`): a patient who ended before `start` is left out and counted (strictly before, so a follow-up of exactly `start` stays, as in `iv_dead<`); a patient with no follow-up is left out too, since SAS deleted a missing `iv_dead` as smaller than `start`; every other patient is censored at `end` (strictly after, so a follow-up of exactly `end` keeps its event, as in `iv_dead>`), with the event set to 0 even when it was missing, as `dead=0` does. Under `"hazard"` the follow-up the log-rate sums is `pmin(TIME, end) - start`, the time at risk inside the window. **That differs from the legacy template:** it set `iv_dead=5` and summed `iv_dead` from time 0, so the first three months entered every patient's denominator and the constant-hazard rate was understated by `start` per patient. The maintainer's stated rule subtracts `start`, so the plan does too; if exact SAS parity is wanted instead, the whole change is the single expression `pmin(follow, end) - start` in `.lg_interval()`, which Task 6's mutation check names. Under `"logit"` the same patients are kept and an event counts only if it fell inside the window. The spec lists `TIME` as read only by `"hazard"`, but `INTERVAL` needs follow-up under either link, so `TIME` is read, and must exist, when the link is `"hazard"` or `INTERVAL` is set. A table under the data table reports both counts (left out before `start`, censored at `end`, and the events that fell after `end`), and the provenance records them.
7. **The blank-choice warning comes last.** `chosen` is read by the closing chunk, after every figure is drawn and saved, so a final render that stops there has still written the figures the author needs to read to make the choice. The stop happens before `lg-scales.rds` is written; a draft writes the covariates that have a usable choice and no others (an empty table when none).
8. **The groups table numbers from 1, `.lg_groups()` from 0.** `.lg_groups()` returns SAS's 0 to `G - 1` so the parity test reads against `PROC RANK` directly; the report's table numbers the groups that exist from 1, because a continuous covariate with heavy ties can leave a rank group empty and a "group 0" heading would read as a mistake.
9. **Internal signatures go past the spec's.** `.lg_plot(table, scales, link, title)` takes the link, to label its y axis, and the title; `.lg_table()` and `.lg_scales()` return their notes as attributes; `.lg_scales()` returns a data frame, not a list. Eight helpers the spec does not name are added because the template would otherwise hold numerical or validation code: `.lg_event()`, `.lg_constant()`, `.lg_term()`, `.lg_rsq()`, `.lg_variables()`, `.lg_interval()`, `.lg_choices()` and `.lg_predictors()`.
10. **R-squared from the correlation, drawn with ggplot2 alone.** `summary(lm())` warns on the exact fit that spec test 4 asks it to recognize, so `.lg_rsq()` computes the weighted squared correlation, which is the same number. The figure uses ggplot2 only, with `rlang::sym()` in place of the `.data` pronoun, so no hvtiPlotR floor moves and the package imports nothing new. Fewer than three groups with a link value gives no R-squared, since two points are always on a line.
11. **`constant` has no default when the median rounds to 0.** A count with a median of 0 would give a constant of 0 and divide by it; the job stops and names `VARIABLES`. A constant of 0 or a non-finite one is refused wherever it is typed.
12. **Labels have hyphens, files keep the column's name.** A Quarto cross-reference id with an underscore can be read as markup, so `nyha_pr` is `tbl-lg-nyha-pr` and `fig-lg-nyha-pr`, while the saved figure is `lg-nyha_pr.png`, the name the README documents as `lg-<covariate>`.
13. **`lg` is a one-row-per-patient reader.** It offers `JOIN` with its three companions like every template that reads its own data, and says `one_row_per_patient = TRUE`, so a join without `REDUCE` stops. The suite's three counts (templates 32 to 33, readers 21 to 22, the one-row list) move with it.
14. **The test helpers go in `helper-lm.R`.** `lg_data()`, `lg_chosen_variables` and `lg_fixture()` call `lm_study()`, `lm_eval_job()` and `lm_chunk()`, and `object_usage_linter` can see those only when they sit in the same file, as the lp-mirror plan found.
15. **The gallery job chooses `raw`.** On the demo cohort the death hazard rises with age, and the raw panel is the straightest (R-squared 0.99), so the job fills `chosen` with `raw` for age and for NYHA class; a real study reads its own figures.

## Spec coverage

| spec section or test | task |
|---|---|
| 1. What `lg` is (the 97% of jobs, the two macros, the six scales, no R tool today) | read in the template's opening prose (5); the ledger row and its note (5) |
| 1. Left out: Gompertz, fitted line, smoother, `lg.trends*` | none built; the `lg.trends*` jobs are named in the ledger note and the news entry (5, 11) |
| 2. Internal functions in `R/logit-calibration.R` | 1, 2, 3, 4 |
| 2. `.lg_groups()`: PROC RANK, ordinal levels, missing counted | 1 |
| 2. `.lg_table()`: logit, hazard, a blank link with a note | 2 |
| 2. `.lg_scales()`: six scales, the term for each, the median constant, `shift`, an empty scale with a note | 3 |
| 2. `.lg_plot()`: one panel per scale, joined points, weighted R-squared | 4 |
| 3. Placement `10_descriptive/lg.qmd`, unqualified, `add_job("lg", subject, type)` | 5 |
| 3. Settings (`DATASET`, `ID`, `WHERE`, `EVENT`, `LINK`, `TIME`, `INTERVAL`, `VARIABLES`, `SAVE_FIGURES`, `FIGURES`) | 5, checked in 6 |
| 3. `VARIABLES` columns and defaults | 6 |
| 3. Output: group table `tbl-lg-<name>` and six-panel figure `fig-lg-<name>`, PNG and PDF | 7 |
| 3. The chosen scales: `lg-scales.rds`, the printed table and `PREDICTORS` line | 8 |
| 3. A blank or impossible `chosen` warns in a draft and stops a final render | 8 |
| 3. Provenance: dataset version, `INTERVAL`, the `VARIABLES` table, no identifier | 9 |
| 4. Ledger row shipped, unqualified, with the note; roadmap re-rendered; the three count scripts | 5, 11 |
| 4. Taxonomy name "Logit calibration" in `templates.json` | 5 (decision 1) |
| 4. `.lintr` file key | 5 |
| 4. Gallery job on `dead`, `iv_dead`, age and NYHA class with `chosen` filled in | 10 |
| 5. Test 1, SAS grouping parity on a 12-row fixture with ties | 1 |
| 5. Test 2, links by hand; a rate of 0 or 1 keeps its row, blank, with a note | 2 |
| 5. Test 3, scales: each formula and term, the median constant, `shift`, an empty log with a note | 3 |
| 5. Test 4, R-squared is 1 for points exactly linear on a scale | 4 |
| 5. Test 5, the template renders two figures and two tables and saves `lg-scales.rds` with the right terms | 7 (evaluated), 8 (saved), 9 (rendered) |
| 5. Test 6, a blank `chosen` warns in a draft and stops a final render | 8 |
| 5. Test 7, `INTERVAL` leaves out the patients who ended before the start, censors the rest at the end, and reports both counts | 6 (the function and the evaluated job), 7 (the tables it feeds), 9 (rendered, with the table and the provenance) |
| 5. Test 8, no identifiers in the rendered report, with the `data:`-dropping whole-token scan | 9 |
| 6. Not in this design: Gompertz, fitted line, smoother, `lg.trends*`, a continuous-outcome counterpart | none built |
