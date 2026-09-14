# EDA templates dc-tables, dc-gfup, dp-postage + SAS-to-R tutorial (hvtiR + hvtiRtemplates)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the `dc-tables`, `dc-gfup` and `dp-postage` job templates in
hvtiRtemplates, flip their catalog rows in hvtiR, and add a vignette that walks a
SAS user from `descriptive/dc.tables*`, `dc.gfup`, `dp.trends` and the EDA
postage stamps to the R job that replaces each.

**Architecture:** Each template is a self-contained Quarto file that is thin over
a package engine named in the catalog's `replaced_by`. `dp-trends` already
shipped (hvtiRtemplates#104) and is only documented here.

| SAS job | R job | template file | engine |
|---|---|---|---|
| `descriptive/dc.tables.ods.sas` (`%desc_tab`) | `dc-tables` | `inst/templates/10_descriptive/dc-tables.qmd` | `hvtiRtables::hv_tbl_summary()`, `hv_man_table()`, `hv_man_table_save()`; correlation variant `hv_correlation_table()` + `hvtiPlotR::hv_correlation_matrix()` |
| `descriptive/dc.gfup.sas` | `dc-gfup` | `inst/templates/10_descriptive/dc-gfup.qmd` | `hvtiRutilities::proc_means()` |
| `graphs/dp.trends.R` | `dp-trends` | `inst/templates/40_graphs/dp-trends.qmd` (**already shipped**) | `hvtiPlotR::hv_trends()` |
| `descriptive/tp.dp.EDA_barplots_scatterplots*.R` | `dp-postage` | `inst/templates/10_descriptive/dp-postage.qmd` | `hvtiPlotR::hv_eda()` (decided 2026-09-14) |

**Tech Stack:** Quarto, hvtiRutilities, hvtiRtables >= 1.0.1 (Plan A), hvtiPlotR >= 2.7.14 (Plan B), patchwork (already an hvtiPlotR Import).

## Global Constraints

- Depends on Plans A, B and D being **merged and version-named** (hvtiRtables 1.0.1, hvtiPlotR 2.7.14, hvtiRdatabuild 0.2.1). Do not start Task 1 before all three are.
- Every template reads data through the shared `data` chunk in Task 1 Step 2: `verify_manifest()` (which stops by default, `stop_on_error = TRUE`), then `hvtiRdatabuild::read_analysis_set(ANALYSIS_SET)`. `read_built()` remains the documented whole-cohort alternative.
- Every render gate runs inside a scratch study made with `hvtiRutilities::study_init()` over a CSV `built`, with an `analysis_sets:` block appended to its `_study.yml` and `hvtiRdatabuild::write_analysis_set()` run once before rendering.
- Spec: hvtiRtemplates `dev/specs/2026-09-09-eda-templates-design.md` section 7 obligations, verbatim:
  - its own **file key** in `.lintr`, never a directory key;
  - exactly one `^ENDPOINT\s+<- ` line and one `^TYPE\s+<- ` line;
  - its own `format:` block;
  - `EDIT:` markers on every study-specific line, with comments saying why;
  - no study identifiers (`test-new-job.R` asserts no `/studies/`, study name, or built-dataset filename);
  - a row in `inst/templates/README.md`;
  - a `NEWS.md` entry under `# hvtiRtemplates (unreleased)`; no `Version:` bump in the template PR;
  - the catalog row flipped to `shipped`, re-rendered.
- EDA set key `(subject, eda)`: `ENDPOINT <- "cohort"`, `TYPE <- "eda"`.
- `id ccfid` (a patient identifier) is **never a default** and ships no export step (spec 8.1).
- One hvtiRtemplates PR carries all three templates: `check-roadmap-counts.py` errors on any `shipped` row whose file is not on disk, so the three flips share one hvtiR tag and one PR.
- hvtiR names a version at most once a day; the catalog flip ships (it lives in `inst/extdata/`), so it gets a NEWS entry.
- Sequencing: A merged + 1.0.1, B merged + 2.7.14, then Task 1-5 here (hvtiRtemplates PR open), then Task 6 (hvtiR flip PR, merge, name 1.1.11, tag), then Task 7 (pin commit on the hvtiRtemplates PR, merge).

---

### Task 0: Branch, plan, dependencies

**Files:** `DESCRIPTION`, `dev/specs/2026-09-14-eda-templates-wave-2-4-plan.md`

- [ ] `cd ~/Documents/GitHub/hvtiRtemplates && git fetch origin && git switch -c feat/eda-templates-dc-tables-gfup-postage origin/main`
- [ ] Copy this plan to `dev/specs/2026-09-14-eda-templates-wave-2-4-plan.md`.
- [ ] `DESCRIPTION`: in `Suggests` set `hvtiPlotR (>= 2.7.14)`, add `hvtiRtables (>= 1.0.1)`, `hvtiRdatabuild (>= 0.2.1)`, `arrow`, `knitr`, `rmarkdown`; add `ehrlinger/hvtiRtables` and `ehrlinger/hvtiRdatabuild` to `Remotes`; add `VignetteBuilder: knitr`.
- [ ] Commit `chore: plan and suggest the EDA engines`.

### Task 1: dc-tables template

**Files:**
- Create: `inst/templates/10_descriptive/dc-tables.qmd`
- Modify: `.lintr` (file key), `inst/templates/README.md` (row)
- Test: `tests/testthat/test-dc-tables-helpers.R`

**Interfaces:**
- Consumes: `hv_tbl_summary(data, by, groups, continuous, binary, categorical, compare, percentiles, overall, continuous_stat)`; `hv_man_table()`; `hv_man_table_save(ft, file)`; `hv_correlation_table(data, vars, with, by, method, conf_level)`; `hv_correlation_matrix(data, vars, labels)`.
- Produces: `classify_buckets(d, vars, overrides = list())` returning `list(continuous =, binary =, categorical =)`, defined in the template's `helpers` chunk.

- [ ] **Step 1: Read the extraction pattern.** `sed -n '1,40p' tests/testthat/test-bh-helpers.R` shows how a template's helper chunk is parsed and sourced into a test. Write `test-dc-tables-helpers.R` the same way, pointing it at `10_descriptive/dc-tables.qmd`, chunk `helpers`, with these expectations:

```r
d <- data.frame(
  age = c(55.5, 61, 70.2, 48, 66, 59, 72.1, 50),
  female = c(0, 1, 1, 0, 1, 0, 0, 1),
  flag = c(TRUE, FALSE, TRUE, TRUE, FALSE, NA, TRUE, FALSE),
  nyha = c(1, 2, 2, 3, 4, 1, 2, 3),
  race = c("W", "B", "W", "O", "W", "W", "B", "W"),
  code = c(1, 2, 1, 2, 2, 1, 1, 2)
)
test_that("classify_buckets sorts by the data", {
  b <- classify_buckets(d, names(d))
  expect_setequal(b$continuous, "age")
  expect_setequal(b$binary, c("female", "flag"))
  expect_setequal(b$categorical, c("nyha", "race", "code"))
})
test_that("overrides win over the data", {
  b <- classify_buckets(d, names(d), overrides = list(continuous = "nyha"))
  expect_true("nyha" %in% b$continuous)
  expect_false("nyha" %in% b$categorical)
})
test_that("every variable lands in exactly one bucket", {
  b <- classify_buckets(d, names(d))
  expect_setequal(unlist(b, use.names = FALSE), names(d))
})
```

  Note on `code`: a 1/2 variable is **categorical**, not binary. `hv_tbl_summary()` only accepts 0/1, logical or Yes/No as `binary`, because the single row it prints needs an unambiguous event.

- [ ] **Step 2: Create the template.** Front matter and the `setup`/`edit-guard` chunks: copy the front matter, the `setup` chunk's root-resolution and `source()` lines, and the whole `edit-guard` chunk **verbatim** from `inst/templates/40_graphs/dp-trends.qmd`. Then change the title and the library/version lines to:

```r
suppressPackageStartupMessages({
  library(hvtiRutilities)
  library(hvtiRtables)
  library(hvtiPlotR)
  library(ggplot2)
})
if (utils::packageVersion("hvtiRtables") < "1.0.1") {
  stop("This job needs hvtiRtables >= 1.0.1 for hv_correlation_table(); ",
       utils::packageVersion("hvtiRtables"), " is installed.", call. = FALSE)
}
if (utils::packageVersion("hvtiPlotR") < "2.7.14") {
  stop("This job needs hvtiPlotR >= 2.7.14 for hv_correlation_matrix(); ",
       utils::packageVersion("hvtiPlotR"), " is installed.", call. = FALSE)
}
```

  Copy the `dp-trends.qmd` lines that set `ENDPOINT`/`TYPE` **verbatim** (the only `^ENDPOINT <- ` and `^TYPE <- ` lines; keep `"cohort"` and `"eda"`), but NOT its `read_built()` line or its year derivation. Read data with this `data` chunk instead; Tasks 2 and 3 use it verbatim:

```r
#| label: data
# The checksum of every dataset in manifest.yaml is checked before anything is
# read, so a result can name the data that produced it. It stops on a mismatch.
hvtiRutilities::verify_manifest(file.path(.root, "manifest.yaml"))
# EDIT: the analysis set this job reads: the columns and the excluded rows,
# declared under analysis_sets: in _study.yml and written once with
# hvtiRdatabuild::write_analysis_set(). A stale set (the built dataset or the
# declaration changed) stops here and names the call that refreshes it. To
# describe the whole study cohort instead, replace both lines with
# d <- read_built().
ANALYSIS_SET <- "eda"
d <- hvtiRdatabuild::read_analysis_set(ANALYSIS_SET)
knitr::kable(attr(d, "attrition"), caption = paste0("Analysis set `", ANALYSIS_SET,
                                                    "`: exclusions, in order"))
```

  The attrition table renders at the top of every job, so a reader sees which rows the set dropped before reading any result. Then add, in this order:

````markdown
<!-- EDIT: name the job this replaces (descriptive/dc.tables.*) and say whether it
     was the overall tables, the by-group tables, or the correlation variant. -->

Replaces `descriptive/dc.tables`: say which variant.

A `dc-tables` job is the formatted descriptive table: every variable the study
reports, grouped under the section headings the SAS `%desc_tab` lists carried as
comments, categorical as `n (%)` and continuous as mean±SD and median (15th,
85th percentile). `%desc_tab` wrote the categorical and continuous tables as two
RTF files; `hv_tbl_summary()` writes one table with both. It describes; with
`BY` set it also tests, and a p-value here is a prompt for an analysis, not a
result.

```{r}
#| label: spec
# EDIT: the variables to report, grouped. Each name is a section heading and
# becomes a row group in the table, in this order. These are the /* Demography */
# style banners from the SAS varlist; carry them across unchanged so the R table
# reads like the SAS one. Commented-out SAS blocks stay out.
GROUPS <- list(
  Demography = c("age", "female"),
  Symptoms   = c("nyha_pr")
)
# EDIT: NULL for the overall table. A column name reproduces the `%macro skip`
# by-group sections (by=, byvalue=): one column per level and a p-value column.
BY <- NULL
# EDIT: force a bucket where the data guess wrong, e.g. an ordinal score you
# want summarised as continuous: list(continuous = c("nyha_pr")). list() for none.
OVERRIDES <- list()
# EDIT: NULL skips the correlation variant (dc.tables.ods_<topic>.sas). To run
# it, name the numeric columns, the anchor to correlate them against (NULL for
# every pair), and an optional stratum:
#   list(vars = c("glu_pr", "creat_pr"), with = "a1c_pr", by = "a1c_grp")
CORR <- NULL
```

```{r}
#| label: helpers
# classify_buckets(): see Task 1 Step 3.
```

## Table

```{r}
#| label: table
b <- classify_buckets(d, unlist(GROUPS, use.names = FALSE), OVERRIDES)
tbl <- hv_tbl_summary(
  d, by = BY, groups = GROUPS,
  continuous = b$continuous, binary = b$binary, categorical = b$categorical,
  # Both statistics, as %desc_tab printed both (perctile=15 50 85 and mean/SD).
  # Pick one when the manuscript is drafted by deleting a row.
  continuous_stat = "both", percentiles = c(15, 85),
  compare = if (is.null(BY)) "none" else "pvalue"
)
tbl
hv_man_table_save(
  hv_man_table(tbl),
  file = set_path("descriptive", paste0(ENDPOINT, "-", TYPE, "-dc-tables.docx"))
)
```

## Correlations

```{r}
#| label: correlation
#| results: asis
if (is.null(CORR)) {
  cat("Correlation variant not requested (`CORR <- NULL`).\n")
} else {
  ct <- hv_correlation_table(d, vars = CORR$vars, with = CORR$with)
  conf_level <- attr(ct, "conf_level")
  if (!is.null(CORR$by)) {
    # The exemplar reports overall AND within each level of the stratum. Only
    # the stratified result carries the `by` column, so the overall rows get
    # one ("Overall") before the two are stacked; rbind() drops the
    # conf_level attribute, which is why it was kept above.
    st <- hv_correlation_table(d, vars = CORR$vars, with = CORR$with,
                               by = CORR$by)
    ct[[CORR$by]] <- "Overall"
    ct <- rbind(ct[names(st)], st)
    attr(ct, "conf_level") <- conf_level
  }
  # 68% Fisher interval by default: the exemplar's alpha=.32.
  print(knitr::kable(ct[setdiff(names(ct), c("estimate", "conf.low", "conf.high"))],
                     caption = sprintf("Spearman and Pearson, %d%% Fisher interval",
                                       round(100 * attr(ct, "conf_level")))))
  cm <- hv_correlation_matrix(d, vars = unique(c(CORR$with, CORR$vars)))
  fname <- "dc-tables-correlation-matrix.png"
  png(set_path("descriptive", fname), width = 10, height = 10, units = "in", res = 150)
  print(plot(cm) + theme_hv_manuscript())
  invisible(dev.off())
  cat("\n![Scatter-plot matrix](", file.path(paste0(ENDPOINT, "-", TYPE), fname), ")\n", sep = "")
}
```
````

  Before merging, confirm `hv_man_table_save()`'s file argument name with `args(hvtiRtables::hv_man_table_save)`, and confirm that `set_path()` and the image-link directory convention match what `dp-trends.qmd` does. Adjust to match; do not invent a new convention.

- [ ] **Step 3: `classify_buckets()`, the one design decision in this template (maintainer's contribution).** In the `helpers` chunk, write `classify_buckets(d, vars, overrides = list())` so that the Step 1 tests pass. Its return shape is fixed: `list(continuous = chr, binary = chr, categorical = chr)`, every variable in exactly one bucket, and `overrides` applied last. The trade-offs are yours:
  - **The continuous/categorical threshold.** `hvtiPlotR::eda_classify_var()` uses 6 distinct values. A lower threshold turns small-integer scales (NYHA 1-4) into continuous; a higher one turns short lab panels into categorical.
  - **What counts as binary.** It must be the set `hv_tbl_summary()` accepts (logical, 0/1, Yes/No) or the table call errors, but you choose whether a 0/1 column that happens to be all-0 in this cohort stays binary.
  - **Character columns** are always categorical.
- [ ] **Step 4: Register it.** In `.lintr`, add a file key for `inst/templates/10_descriptive/dc-tables.qmd` with the same exclusions `dp-trends.qmd` has. In `inst/templates/README.md`, add a row that mirrors the `dp-trends` row.
- [ ] **Step 5: Run** `Rscript -e 'devtools::test()'`. Expected: the new helper tests PASS; `test-new-job.R` and `test-taxonomy.R` PASS (the catalog already files `dc-tables` under `descriptive`).
- [ ] **Step 6: Render gate.** Build a scratch study (no study data, no identifiers):

```r
root <- file.path(tempdir(), "dc-tables-gate")
dir.create(file.path(root, "datasets"), recursive = TRUE)
built <- hvtiPlotR::sample_correlation_data(n = 200)
built$ccfid   <- seq_len(nrow(built))            # synthetic, sequential
built$female  <- rep(0:1, length.out = nrow(built))
built$dead    <- rep(c(0L, 0L, 1L), length.out = nrow(built))
built$iv_dead <- seq_len(nrow(built)) / 40
utils::write.csv(built, file.path(root, "datasets", "built.csv"), row.names = FALSE)
writeLines("project:\n  type: default", file.path(root, "_quarto.yml"))
hvtiRutilities::study_init(root, study = "Gate", built = "built.csv",
                           event = "dead", time = "iv_dead")
y <- yaml::read_yaml(file.path(root, "_study.yml"))
y$analysis_sets <- list(eda = list(
  id = "ccfid",
  vars = c("a1c", "glucose", "creatinine", "albumin", "female", "dead"),
  exclude = list(list(reason = "Albumin under 3", when = "albumin < 3"))
))
yaml::write_yaml(y, file.path(root, "_study.yml"))
hvtiRdatabuild::write_analysis_set("eda", hvtiRutilities::study_config(root))
hvtiRtemplates::new_job("dc", "cohort", "eda", dir = root, qualifier = "tables")
```

  In the scaffolded `descriptive/cohort-eda-dc-tables.qmd`, resolve every `EDIT:` (GROUPS over those six columns, `CORR <- list(vars = c("glucose", "creatinine", "albumin"), with = "a1c")`), then `quarto render` it. Expected: the attrition table, the summary table, the docx, the correlation table and the matrix PNG all appear. Then re-render once with `BY <- "female"` and confirm the p-value column appears. Delete the scratch dir. Tasks 2 and 3 build their gate studies the same way, from the data sources they name.
- [ ] **Step 7: Commit** `feat: dc-tables job template`.

### Task 2: dc-gfup template

**Files:** Create `inst/templates/10_descriptive/dc-gfup.qmd`; modify `.lintr` and `inst/templates/README.md`.

**Interfaces:** Consumes `proc_means(data, vars, class, stats)`, which returns a data frame with columns `[class], variable, label, <stats...>`.

- [ ] **Step 1: Create the template.** Front matter, `setup` (hvtiRutilities only, no version floor beyond the package's own Imports), `edit-guard` and the data/ENDPOINT/TYPE chunk are copied from `dp-trends.qmd` as in Task 1. Then:

````markdown
<!-- EDIT: name the job this replaces (descriptive/dc.gfup). -->

Replaces `descriptive/dc.gfup`.

A `dc-gfup` job asks whether follow-up is complete enough to trust the
time-related analyses: how long patients were followed for death and for
non-fatal events, against how long they could have been followed by the
close date. The figure is `dp-gfup` (`hv_followup()`); this job is the tables.

```{r}
#| label: spec
# EDIT: the close date of follow-up (SAS: current=mdy(mm,dd,yyyy)). Potential
# follow-up is measured to this date, so a wrong date makes follow-up look
# better or worse than it is.
CLOSE_DATE <- as.Date("2026-01-01")
# EDIT: column names in the built data. The SAS template used dt_surg, iv_dead,
# dead and iv_fup; change any that differ.
COLS <- c(dt_surg = "dt_surg", iv_dead = "iv_dead", dead = "dead", iv_fup = "iv_fup")
# EDIT: event-coding consistency checks, each a set of columns cross-tabulated
# with missing values shown (SAS: proc freq; table a*b*c / list missprint).
# list() for none.
CHECKS <- list(c("dead", "hdeath"))
```

```{r}
#| label: derive
g <- data.frame(
  dt_surg = d[[COLS[["dt_surg"]]]], iv_dead = d[[COLS[["iv_dead"]]]],
  dead = d[[COLS[["dead"]]]], iv_fup = d[[COLS[["iv_fup"]]]]
)
yrs <- function(days) as.numeric(days) / 365.2425
g$maxfup <- ifelse(g$dead == 1, g$iv_dead, yrs(CLOSE_DATE - g$dt_surg))
g$potfup <- ifelse(g$dead == 1, NA_real_,
                   yrs(CLOSE_DATE - (g$dt_surg + g$iv_fup * 365.2425)))
g$pctfup <- g$iv_fup / g$maxfup
g$pctvit <- g$iv_fup / g$iv_dead
```

## Data checks

```{r}
#| label: checks
for (cc in CHECKS) print(as.data.frame(table(d[cc], useNA = "ifany")))
```

## Follow-up for survival

```{r}
#| label: survival
st <- c("n", "nmiss", "mean", "std", "min", "p15", "median", "p85", "max")
proc_means(g, vars = "iv_dead", class = "dead", stats = st)
proc_means(g[g$dead == 0, ], vars = c("iv_dead", "maxfup", "pctfup"), stats = st)
```

## Follow-up for non-fatal events

```{r}
#| label: events
proc_means(g, vars = "iv_fup", class = "dead", stats = st)
proc_means(g[g$dead == 0, ], vars = c("iv_fup", "potfup", "pctfup", "pctvit"),
           stats = st)
```

The SAS job printed every patient, sorted by `dead` and operation date, so an
author could find the incompletely followed ones by `ccfid`. This job prints
none: the percentiles of `pctfup` among survivors answer the same question
without an identifier. Quantiles here are SAS `QNTLDEF=5`; the SAS template's
`proc univariate def=4` gives slightly different tail percentiles.
````

- [ ] **Step 2: Register** the `.lintr` file key and the README row, as in Task 1 Step 4.
- [ ] **Step 3: Render gate** with `hvtiRutilities::generate_survival_data(n = 200)` renamed to the four `COLS` (add a `dt_surg` date column if it has none). Expected: renders, and every table is non-empty.
- [ ] **Step 4: Commit** `feat: dc-gfup job template`.

### Task 3: dp-postage template

**Files:** Create `inst/templates/10_descriptive/dp-postage.qmd`; modify `.lintr` and `inst/templates/README.md`.

**Interfaces:** Consumes `hv_eda(data, x_col, y_col, y_label, unique_limit, show_percent)` returning `hv_eda`; `plot.hv_eda()` returning a bare ggplot; `patchwork::wrap_plots(plots, ncol, nrow)`.

- [ ] **Step 1: Create the template.** Copy the front matter, `setup` and `edit-guard` chunks, then:

````markdown
<!-- EDIT: name the job this replaces (tp.dp.EDA_barplots_scatterplots*.R). -->

A `dp-postage` job is the data-checking sweep over a new build: one small panel
per variable against operation year, bars for categorical variables and points
for continuous ones, pages of them. It is for finding coding errors, drift and
missingness before any analysis. It is not a figure for a manuscript.

```{r}
#| label: spec
# EDIT: the x-axis for every panel, usually operation year.
X_COL <- "year"
# EDIT: the variables to sweep, named by column with a display label. Order is
# page order. hv_eda() decides bar or scatter per variable (6 distinct values or
# fewer is categorical), so a column does not need a type here.
VARS <- c(age = "Age (years)", female = "Female")
# Panels per page. 3 x 3 keeps a label readable on a printed page.
NCOL <- 3L
NROW <- 3L
```

## Pages

```{r}
#| label: pages
#| results: asis
plots <- lapply(names(VARS), function(v) {
  plot(hv_eda(d, x_col = X_COL, y_col = v, y_label = VARS[[v]])) +
    theme_hv_manuscript(base_size = 8)
})
per_page <- NCOL * NROW
pages <- split(plots, ceiling(seq_along(plots) / per_page))
for (i in seq_along(pages)) {
  fname <- sprintf("dp-postage-%02d.png", i)
  png(set_path("descriptive", fname), width = 11, height = 8.5, units = "in", res = 150)
  print(patchwork::wrap_plots(pages[[i]], ncol = NCOL, nrow = NROW))
  invisible(dev.off())
  cat("\n![Page ", i, "](", file.path(paste0(ENDPOINT, "-", TYPE), fname), ")\n", sep = "")
}
```
````

  Check `args(hvtiPlotR::theme_hv_manuscript)` for the base-size argument name before committing.

- [ ] **Step 2: Register** the `.lintr` file key and the README row.
- [ ] **Step 3: Render gate** with `hvtiPlotR::sample_eda_data(n = 300)`, `VARS` set to four of its columns. Expected: one page PNG, mixed bar and scatter panels.
- [ ] **Step 4: Commit** `feat: dp-postage job template on hv_eda()`.

### Task 4: The tutorial vignette

**Files:** Create `vignettes/sas-to-r-descriptive.Rmd`; modify `_pkgdown.yml` (articles), `.Rbuildignore` if needed.

- [ ] **Step 1: Write the vignette** with this outline (house voice per the `ehrlinger-writing` skill; reader is a SAS biostatistician who knows the `tp.dc.*` templates):
  1. *Who this is for*, and what "R equivalent" means here: same numbers where the method is the same, a stated difference where it is not.
  2. *Install once*: `hvtiR::install()` and `hvtiR::status()`.
  3. *The map*: the four-row table from this plan's Architecture section.
  4. *Five steps, every job*: (1) `new_job(prefix, "cohort", "eda", qualifier = ...)` writes `descriptive/cohort-eda-dc-tables.qmd`; (2) work every `EDIT:` marker, since the edit guard stops the render until you do; (3) render with `quarto render`; (4) compare against the SAS `.lst`; (5) file the output under `descriptive/`.
  5. One section per job, each with its SAS call and its R call side by side, run live on sample data behind `if (requireNamespace(...))`:
     - `dc-tables`: the `%desc_tab(vartype=category, ...)` and `vartype=continuous` pair becomes one `hv_tbl_summary()`; `/* banners */` become `GROUPS`; `by=`/`byvalue=` becomes `BY`; `perctile=15 50 85` becomes `continuous_stat = "both"`; the correlation variant becomes `CORR`.
     - `dc-gfup`: `proc means`/`proc univariate` become `proc_means()`; the identified listing is dropped, and why.
     - `dp-trends`: point to the shipped template; `smooth.spline(df = 6)` becomes LOESS, so compare by shape.
     - `dp-postage`: `Function_DataPlotting()` loops become `hv_eda()` over `VARS`.
  6. *Where the numbers will differ*: percentiles (SAS `QNTLDEF=5` is R `type = 2`, and `proc_means`/`gtsummary` already use it; hand-written `quantile()` calls must pin it); N is non-missing N; p-values are non-parametric for continuous variables; correlation intervals are 68% Fisher by default; `%desc_tab`'s two RTFs are one docx.
  7. *What is not ported*: RTF output (docx instead), identified patient listings.
- [ ] **Step 2:** `_pkgdown.yml`: add the article. Run `Rscript -e 'devtools::build_vignettes()'`. Expected: builds with no errors; live chunks skip cleanly if a Suggests package is absent.
- [ ] **Step 3: Commit** `docs: SAS-to-R tutorial for the descriptive jobs`.

### Task 5: NEWS, check, open the PR

- [ ] `NEWS.md`, under `# hvtiRtemplates (unreleased)`:

```markdown
* **Three descriptive job templates ship: `dc-tables`, `dc-gfup` and
  `dp-postage`**, with `vignette("sas-to-r-descriptive")` walking a SAS user
  from `descriptive/dc.tables*`, `dc.gfup`, `dp.trends` and the EDA postage
  stamps to the R job that replaces each. `dc-tables` carries the correlation
  variant on `hvtiRtables::hv_correlation_table()` and
  `hvtiPlotR::hv_correlation_matrix()`; `dp-postage` is thin over
  `hvtiPlotR::hv_eda()`.
```

- [ ] `devtools::test()`, `devtools::check()` 0/0/0, `lintr::lint_package()` clean.
- [ ] Push, `gh pr create`. Expected CI: everything green **except `spec-counts`**, which stays red until Task 7. Do not merge while it is red: it is not a required check, so GitHub will show the PR mergeable anyway.

### Task 6: Flip the catalog (hvtiR)

**Files:** `~/Documents/GitHub/hvtiR/inst/extdata/jobs.json`, `NEWS.md`

- [ ] `cd ~/Documents/GitHub/hvtiR && git fetch origin && git switch -c chore/catalog-ship-eda-wave origin/main`
- [ ] Edit three rows in `inst/extdata/jobs.json`:
  - `dc/tables`: `"status": "shipped"`; append `"hvtiRtables::hv_correlation_table"`, `"hvtiPlotR::hv_correlation_matrix"` to `replaced_by`.
  - `dc/gfup`: `"status": "shipped"`.
  - `dp/postage`: `"status": "shipped"`, `"disposition": "thin"`, `"replaced_by": ["hvtiPlotR::hv_eda"]`; append to `note`: `" Engine decided 2026-09-14: hv_eda() earns the row (option 1 of the Lauren-lane decision), so her EDA report is the prototype this template is thin over."`
- [ ] `NEWS.md`: add a `# hvtiR (unreleased)` heading if absent, with one bullet naming the three flips and the two new engines.
- [ ] `devtools::test()` (the catalog tests validate the schema), `devtools::check()` 0/0/0. PR, maintainer merges.
- [ ] Separate commit, on a day with no other version named: name `1.1.11` (NEWS heading, NEWS DCF `Version:`, DESCRIPTION `Version`/`Date`), PR, merge, then an annotated tag `v1.1.11` on the merge commit.

### Task 7: Pin and merge

- [ ] On the hvtiRtemplates PR branch, move both catalog pins (`.github/workflows/R-CMD-check.yaml`, `.github/workflows/spec-counts.yaml`) to `v1.1.11`, then re-render the roadmap with the invocation in `dev/specs/artifacts/README.md`. Expected: 13 of 43 templates on disk, and `check-roadmap-counts.py` exits 0.
- [ ] Push. Expected: every check green, `spec-counts` included. The maintainer merges.
- [ ] Vault: mark Waves 2-4 in `Claude/Tasks/EDA template batch follow-ups.md` (dc-general is still open), and resolve `Claude/Tasks/Lauren's EDA report engine is not in the job catalog.md` with option 1 and today's date.

## Out of scope, recorded

- `dc-general` and `dp-gfup` (not requested; both unblocked).
- Word output for the correlation table.
- Whether `hv_eda()` should also join `dp-gfup` and `dp-variable`'s `replaced_by` (the vault task's option 1 mentions both).
