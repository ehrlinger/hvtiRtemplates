# `lg` template: design, 2026-10-11

**Status** Design, approved section by section on 2026-10-11. Not implemented.
**Replaces** the SAS `lg` jobs built on the `%logit` and `%logitgr` macros, and
the legacy templates `tp.lg.hdead` and `tp.lg.dead.constant`.
**Feeds** the `lm` templates. `lg` is how a study author decides which scale a
covariate enters a model on, before it goes into `PREDICTORS`.

## 1. What `lg` is

A read-only survey on 2026-10-11 used the 2026-08-27 job census.
- **The corpus:** 847 SAS `lg` jobs in about 360 studies. No study has an R `lg`
  job; the roadmap row shows 0 R exemplars.
- **The sample:** 46 jobs read in full, one per study across all four trees, and a
  further 220 scanned, one per study. It also read the macro sources in the CORR
  macro library.

**97% of jobs (214 of 220) calibrate a continuous or ordinal covariate against an
event.**
- `%logit` ranks the covariate into groups, usually 5, with `PROC RANK`, ties
  averaged. `%logitgr` treats each level of an ordinal covariate as a group, and
  106 of the 214 use it.
- For each group it takes the event rate on a link scale:
  - the logit, `log(p / (1 - p))`, for a binary event;
  - with `cox=1`, the log of the constant hazard, `log(events / sum(follow-up))`,
    for time-related death. 93 of the 214 jobs do this.
- It plots the group values against six candidate scales of the covariate. The
  analyst picks the straightest by eye.
- **No job records the choice.** It resurfaces later as an `ln_`, `in_` or `in2`
  variable in the study's `vars.sas` and then in a model.

The other jobs are 12 `lg.trends*` jobs in the census (4 of the 220 scanned), which
regress a characteristic on calendar year with `PROC LOGISTIC`. That is the ground
`dc-trends` and `hvtiPlotR::hv_trends()` already cover, so they are not part of
this design.

**Rarely used, and left out:**
- the Gompertz link (0 of 220 jobs);
- a fitted line with a confidence band (1 of 46);
- any smoother (none).

**No R tool does this today.** hvtiPlotR, hvtiRtables and hvtiRutilities export
nothing for a grouped logit or hazard calibration. `TemporalHazard::hzr_deciles()`
and `hzr_calibrate()` group by predicted risk for goodness of fit, not by a
covariate.

The two-study gate is met many times over.

## 2. The computation: internal functions in `R/logit-calibration.R`

These are internal, unit-tested and called from the template, as `.check_job_columns()`
and `.save_figure()` are. They are chosen over a new hvtiPlotR export, which would
need an hvtiPlotR release and a raised floor first, and over code in the
template's own helpers chunk, which would put about 100 lines of numerical code
into every study's copy. If `rg` later needs the same machinery, they move to
hvtiPlotR then.

**`.lg_groups(x, groups = 5, kind = c("continuous", "ordinal"))`**
- Continuous: this is `PROC RANK GROUPS=` exactly. It ranks with ties averaged,
  then assigns group `floor(rank * G / (n + 1))`. A converted job reproduces the
  SAS groups, and tied values share a group.
- Ordinal: each observed level is a group, as in `%logitgr`.
- A missing `x` is dropped and counted.

**`.lg_table(x, event, time = NULL, groups, kind, link = c("logit", "hazard"))`**
returns one row per group: mean, min, max, n, events, rate and link value.
- `logit`: `log(p / (1 - p))`.
- `hazard`: `log(events / sum(time))`.
- A group whose link value cannot be computed (a rate of 0 or 1, or no events
  under `hazard`) keeps its row with a missing link value and is named in a note.
  It is never dropped silently; SAS left a missing point without a word.

**`.lg_scales(mean, constant, shift = 0)`** returns the six candidate scales:

| scale | value | term written for `lm` |
|---|---|---|
| raw | `mean` | `x` |
| log | `log(mean + shift)` | `log(x + shift)`, or `log(x)` when `shift` is 0 |
| inverse | `c / mean` | `I(c / x)` |
| inverse squared | `(c / mean)^2` | `I((c / x)^2)` |
| squared | `(mean / c)^2` | `I((x / c)^2)` |
| exp | `exp(mean / c)` | `I(exp(x / c))` |

- The default `constant` is the covariate's median, rounded to one significant
  figure. The SAS jobs typed it by hand: 50 for age, 80 for weight.
- `shift` makes the log zero-safe.
- A scale that cannot be computed for a covariate is drawn empty with a note, not
  left out. That covers the log of a non-positive value and an inverse through
  zero.

**`.lg_plot(table, scales)`** draws one panel per scale, plotting the link value
against the scale value, with points joined by a line as in SAS. Each panel shows
the R-squared of a weighted straight-line fit, weighted by group size. It is
guidance for "straightest", not a decision; the author still chooses.

## 3. The template

**Placement.** `inst/templates/10_descriptive/lg.qmd`, unqualified, in the
descriptive folder the taxonomy gives `lg`. It is scaffolded with
`add_job("lg", subject, type)`, where the subject is usually the outcome, as in
`lg.dead.calibration`.

**Settings:**

| setting | default | `EDIT:` |
|---|---|---|
| `DATASET`, `ID`, `WHERE` | `"built"`, `"ccfid"`, `NULL`; read one row per patient | as in every job |
| `EVENT` | `"dead"` | yes |
| `LINK` | `"hazard"` | yes; `"logit"` for a binary in-hospital or complication outcome |
| `TIME` | `"iv_dead"`, used only by `"hazard"` | yes |
| `INTERVAL` | `NULL`, or a window such as `c(0.25, 5)` | yes. It keeps the patients whose follow-up falls in it: the SAS early, constant and late phases |
| `VARIABLES` | a data frame, one row per covariate | yes |
| `SAVE_FIGURES`, `FIGURES` | as in every template | no |

**`VARIABLES` columns:**
- `name`;
- `kind`: `continuous` or `ordinal`, default `continuous`;
- `groups`: default 5;
- `constant`: default the median rule;
- `shift`: default 0;
- `label`: default the name;
- `chosen`: default `NA`.

The template ships one example row. `chosen` stays empty until the author has seen
the plots.

**Output, for each covariate:**
- a group table (mean, min, max, n, events, rate, link value), numbered
  `tbl-lg-<name>`;
- the six-panel figure, numbered `fig-lg-<name>`, saved as PNG and PDF through
  `.save_figure()`.

**The chosen scales.**
- The job saves `estimates/lg-scales.rds`, a table of `variable`, `chosen`,
  `term`, `constant` and `shift`. `term` is ready to go into `lm`'s
  `PREDICTORS`, for example `log(age)` or `I(50 / weight)`.
- It prints that table, ending with the `PREDICTORS <- c(...)` line to copy into
  an `lm` job.
- A blank `chosen`, or one that names a scale that cannot be computed, warns in a
  draft and stops a final render, as an open `EDIT:` marker does.

**Provenance** records the dataset version, `INTERVAL` and the `VARIABLES` table.
It records no identifiers; every output is per group.

## 4. Catalog, taxonomy, gallery and lint

- **Ledger.** The `lg` ledger row becomes shipped, unqualified, with a note that
  the `lg.trends*` jobs go to `dc-trends`. The roadmap is regenerated with its
  renderer, and the three spec-count scripts must pass.
- **Taxonomy name.** In `inst/extdata/templates.json`, `lg`'s name changes from
  "Logit trends" to "Logit calibration". The description, "variable transformation
  and linearity checks", stays, since 97% of the corpus matches it.
- **`.lintr`** gains a key for the file itself.
- **Gallery.** A new job on the synthetic study's `dead` and `iv_dead`, with
  `LINK = "hazard"`, age (continuous) and NYHA class (ordinal), and `chosen`
  filled in.

## 5. Tests

All fixtures synthetic, no PHI. Each test fails with its code reverted.

1. **SAS grouping parity.** `.lg_groups()` reproduces `PROC RANK GROUPS=5` on a
   12-row fixture with ties. The expected groups are worked out by hand from
   `floor(rank * G / (n + 1))`.
2. **Links.** Logit and hazard values match hand calculations. A group with a
   rate of 0 or 1 keeps its row with a missing link value and a note.
3. **Scales.** Each formula and term string; the median-rule constant; the `shift`
   making the log safe; a non-positive log drawn empty with a note.
4. **R-squared.** It is 1 for points exactly linear on a scale.
5. **Render.** The template renders two figures and two tables and saves
   `lg-scales.rds` with the right terms.
6. **Choices.** A blank `chosen` warns in a draft and stops a final render.
7. **Interval.** `INTERVAL` filters patients and reports how many it kept.
8. **No identifiers** in the rendered report, using the scan from `lp-mirror`
   that drops `data:` URIs and matches whole tokens.

## 6. Not in this design

- the Gompertz link;
- a fitted line or confidence band;
- a smoother;
- the calendar-year `lg.trends*` jobs;
- a continuous-outcome counterpart (`rg`).
