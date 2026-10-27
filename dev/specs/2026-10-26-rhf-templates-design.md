# `rhf` templates: design, 2026-10-26

**Status** Design, approved with John on 2026-10-26. Not implemented.
**Adds** a new prefix, `rhf` (random hazard forest), and two templates under
it, `rhf-fit.qmd` and `rhf-explain.qmd`, both shipped with ledger status
`in-flight`.
**Starts from** the Hsich NIH multicenter study: death on the transplant
waiting list, with 19 serial labs and 16 complication indicators as
time-varying covariates, already built in counting-process form
(`datasets/btvc_labs_comp.parquet`, 1,490,536 segments on 2,386 patients). The
probe that exercised randomForestRHF and the ggRandomForests v4 RHF layer on it
is `/studies/general/_development/rhf-hsich-waitlist-20261026/rhf_probe.R`.
**Takes up** the `rhf` row that `dev/specs/2026-09-19-rf-templates-design.md`
§8 left out to wait for exemplar studies.

## 1. Why in-flight, and what promotes it

The two-study rule (AGENTS.md) holds a template until two studies have
exercised its shape. Hsich is the first study to fit a random hazard forest.
The templates ship now, marked `in-flight` as `vp`, `sid` and `vt` were, so the
Hsich job can be scaffolded from them and become their first real run. A
second study's RHF job promotes them to `shipped`. The candidates named on
2026-10-26 are study 939, COMMENCE, and Penny's outcomes.

## 2. The workflow

Each set runs three jobs, in order:

1. **`rhf-fit`** checks the counting-process rows, tunes the tree size, grows
   the forest and saves `rhf.rds`.
2. **`rhf-explain`** reads `rhf.rds` and reports discrimination over time,
   hazard curves and variable importance. It never grows a forest. The
   importance step builds a VarPro cache and saves it under a stable name.
3. **A VarPro-RHF template**, a later design and not part of this one, reads
   that cache and carries the VarPro work further.

Fitting is slow and changes rarely; explaining is where a study author
iterates. The split is the one `rfs`, `rfc` and `rfr` use, for the same reason.

| file | prefix | qualifier | status |
|---|---|---|---|
| `inst/templates/30_analyses/rhf-fit.qmd` | `rhf` | `fit` | `in-flight` |
| `inst/templates/30_analyses/rhf-explain.qmd` | `rhf` | `explain` | `in-flight` |

`rhf` is wholly qualified, as `check-roadmap-counts.py` requires.

The templates fit with randomForestRHF (`>= 2.1.0`) and plot with
ggRandomForests (`>= 4.0.0`). Neither package's code moves here.

## 3. `rhf-fit`

The layout follows `rfs-fit.qmd`: `setup`, Study choices, Cohort, Forest, "Does
the forest work?", `save`.

### 3.1 Study choices

Every line below is an `EDIT:` choice unless it says otherwise.

- `DATASET`, `ANALYSIS_SET` and `WHERE`, as in `rfs-fit`. `WHERE` must select
  whole patients (§3.2).
- `ID`, `START`, `STOP` and `EVENT`, naming the counting-process columns, and
  `KEY <- c(ID, START)`: many rows per patient.
- `JOIN`, `JOIN_VARS`, `REDUCE` and `JOIN_KEY`, as every template that reads
  its own data offers them (`test-template-data-routes.R` holds all of them
  to it). Here the join is long, with no `REDUCE`: `DATASET` can be the
  one-row cohort and `JOIN` the registered counting-process rows, or
  `DATASET` can name the counting-process rows directly. *(Amended
  2026-10-26 while planning: this read "No `JOIN`" when approved.)*
- `PREDICTORS`, baseline and time-varying columns alike, named rather than
  taken from every column.
- `EVENT` is a cause-specific event. A competing event (transplant, in Hsich)
  is coded 0 and censors. randomForestRHF fits one event; the comment says
  what that choice means for interpretation.
- `NTREE` and `SEED`, with `seed = -abs(SEED)` passed to `rhf()`, as
  `rfs-fit` explains.
- `TREESIZE <- NULL` tunes the tree size with
  `tune.treesize.rhf(perf = "risk")`; a number skips the tuning. The comment
  says what tree size controls in RHF, and why this template tunes it when
  `rfs-fit` tunes nothing (the 2026-09-19 design left `tune.rfsrc()` out).
- `REPAIR <- character()`, see §3.3.
- `REFIT`, `SAVE_FIGURES` and `FIGURES`, unchanged from `rfs-fit`.

`setup` sets `options(rf.cores = 1L)` with the reproducibility comment
`rfs-fit` carries.

### 3.2 Counting-process checks

The checks run before any fit, in a new internal function (§5.1). Each defect
stops the render, naming its type, its count and the first few subject ids, so
the dataset job can be fixed:

| defect | why it stops |
|---|---|
| overlapping segments within a subject | `rhf()` rejects them, after the data are loaded and without naming the subject |
| a zero- or negative-length segment | no time at risk |
| an event on a row other than the subject's last | the event would end follow-up mid-record |
| `EVENT` not coded 0/1 | a cause code would be read as an event |
| a missing value in a predictor | `rhf()` has no `na.action`, and dropping a segment opens a hole in the risk set |
| a `WHERE` that removes some, not all, of a patient's segments | it truncates follow-up silently. Checked inside `read_job_data(whole_patients = TRUE)`, the one place holding the rows before and after `WHERE` |

Gaps between a subject's segments are allowed, as `rhf()` allows them, and are
counted in the cohort table. That table also gives patients, segments, events,
and segments per patient.

### 3.3 `REPAIR`: unblocking a job while the dataset fix is in flight

A defect belongs in the dataset build, so that every job in the study reads the
same rows. Waiting on that fix stalls development, so a job may repair two of
the defects itself:

```r
# EDIT: repairs this job makes to the counting-process rows while the dataset
# fix is in flight. Each one marks the report a draft, and a final render
# refuses it: the rows a final result rests on come from the dataset, so every
# job in the study agrees on them.
#   "clip"    clips each overlapping segment's start back to the previous stop
#             and drops any segment left empty (zero length included)
#   "drop_na" drops segments missing a predictor
REPAIR <- character()
```

A repair reports its counts in the cohort table and calls
`.run_mark_draft()`, for example "1 overlapping segment clipped in the job, not
the dataset". The draft callout and the "About this run" table name it, and a
strict (final) render stops on it, by the rule an open `EDIT:` marker, `skip`
and `stop_here()` already follow. The repairs in `rhf_probe.R` are exactly
`REPAIR <- c("clip", "drop_na")`.

An event before the last row and a partial-patient `WHERE` have no repair:
either fix would be a guess about the data.

### 3.4 Forest

- `cache_fit("rhf-treesize", tune.treesize.rhf(...))` when `TREESIZE` is
  `NULL`, then `cache_fit("rhf-forest", rhf(...))`, both in the set's
  estimates folder and under `guard_long_fit()`.
- The formula is `Surv(id, start, stop, event) ~ .` built from the choices,
  with its environment set to `globalenv()` as `rfs-fit` explains.
- The repairs applied are part of the forest's cache key and lineage.
- **The subject id is recoded to 1..n before the fit**, as `nb-boostmtree`
  replaces its ids. `rhf()` needs the id in its data, and a saved forest keeps
  its data, so the study's ids would otherwise be written into `rhf.rds`.
  The forest's ids are therefore job-local numbers that cannot be read back.

### 3.5 Does the forest work?

`gg_tune_rhf()` draws risk over tree size, which shows whether the search found
an interior minimum. A curve still falling at the upper bound says to widen
the search. Discrimination is the explain job's work (§4).

### 3.6 `save`

Writes `rhf.rds` by set, as `rfs-fit` writes `rfs.rds`.

## 4. `rhf-explain`

The layout follows `rfs-explain.qmd`.

### 4.1 The forest

Reads `set_path("estimates", "rhf.rds")` and stops if it does not hold an
`rhf` object. The fit's lineage goes into the data table with
`source = "rhf.rds"`. **A forest grown on repaired rows makes the explain
report a draft too**, so the draft state cannot be lost across the hand-off.

### 4.2 Study choices

- `TAU`, the horizon for AUC(t), in the fit's time units; `NULL` takes the
  package default.
- `N_CURVES <- 20` and `SEED` choose which subjects get hazard curves, sampled
  from the forest's job-local ids (§3.4); there is no way to name a study
  subject, since study ids never reach the forest.
- `MAX_RULES_TREE <- 150` and `MAX_TREE <- 150`, the package defaults for the
  VarPro cache. The comment says that the Hsich probe used 30 and 20 to finish
  on 400 patients, and that the cache is the slow step at full scale.
- `N_TIMES <- 5`, the number of evenly spaced points on the cache's time grid
  at which importance is computed. RHF importance changes over follow-up.

### 4.3 Discrimination

`auct.rhf()` twice, each cached: cumulative (`marker = "cumhaz"`) and incident
(`marker = "hazard"`, `riskset = "subject"`), as the probe ran them.
`gg_auct()` draws each, and a table gives both iAUCs.

### 4.4 Hazard curves

`gg_rhf(source = "oob")`, drawn as hazard and as cumulative hazard, for the
chosen subjects. **The legend is dropped**: it would print study ids into a
report that leaves the server.

### 4.5 Importance

`varpro.cache.rhf()` cached as `rhf-varpro-cache`, a **stable name** that the
VarPro-RHF template (§2) reads rather than rebuilding. Then `importance.rhf()`
at `N_TIMES` points, cached, drawn with `gg_rhf_importance()` beside a ranked
table.

### 4.6 `provenance`

As in every template.

## 5. Package code, tests and plumbing

### 5.1 `.cp_check()`

The checks and repairs of §3.2 and §3.3 live in a new internal function in
`R/counting-process.R`, not in the template:

```r
.cp_check(d, id, start, stop, event, predictors, repair = character())
```

It returns the rows to fit, a table of counts, and what was repaired. The
partial-patient check is not here: it is `read_job_data(whole_patients =
TRUE)`, a new argument, because only `read_job_data()` holds the rows both
before and after `WHERE` (reading twice would list two reads in "About this
run").
Package code makes each defect unit-testable, as `.lg_choices()` is for `lg`,
and a later time-varying template (a `bh` TVC port, say) can call it too.

### 5.2 Tests

- **`test-counting-process.R`**: one case per defect, each repair and its
  counts, and stop versus draft under strict mode. Proven by mutation: revert
  each check and confirm its test goes red.
- **`test-job-data.R`**: `whole_patients = TRUE` stops on a `WHERE` that keeps
  part of a patient and passes one that keeps whole patients; `FALSE`, the
  default, changes nothing.
- **A saved `rhf.rds` holds no study id**, by the byte scan the `rfs`, `rfc`
  and `rfr` forests already pass (#203).
- **Template smoke test**: a temporary study through `add_job()`, data from
  `randomForestRHF::hazard.simulation(n = 100, nrecords = 7)`, `ntree = 20`,
  fit then explain, chunks run the way the `rfs` template tests run them.
  Asserts `rhf.rds`, each cache file and each plot object. Guarded by
  `skip_on_cran()` and `skip_if_not_installed("randomForestRHF")`. No Windows
  skip, so the Windows leg's count stays where it is.
- The existing suites pick up the two files unchanged: name parsing, the
  `EDIT:` guard, root resolution, catalog `uses` entries being real exports,
  and the scan for study identifiers.

### 5.3 Plumbing, in release order

1. **hvtiRutilities**: an `rhf` row in `hvti_taxonomy()`
   (`"Random hazard forest"`, folder `analyses`, "time-varying covariates,
   counting-process hazard"), then a patch bump. It ships first, because
   `add_job()` places a job by the taxonomy.
2. **hvtiRtemplates**:
   - the hvtiRutilities floor raised to that version, in this package's own
     bump;
   - `randomForestRHF (>= 2.1.0)` in `Suggests`;
   - two catalog rows in `inst/extdata/templates.json` with
     `"status": "in-flight"` and their `uses`, and the ledger row;
   - `.lintr` keys for each **file**;
   - README rows marked "(in flight)", with the figure names `FIGURES`
     accepts;
   - a `news/` fragment.

## 6. Settled while planning

- The partial-`WHERE` check is `read_job_data(whole_patients = TRUE)` (§5.1).
- `hazard.simulation()` returns `id`, `start`, `stop`, `event`, `xtd` and
  `x.1`..`x.p`; the smoke test renames `id` to `ccfid`.
- The `FIGURES` names are `rhf-fit-tuning`, `rhf-explain-auc-cumulative`,
  `rhf-explain-auc-incident`, `rhf-explain-hazard`, `rhf-explain-chf` and
  `rhf-explain-importance`.

## 7. Out of scope

- The VarPro-RHF template, which follows `rhf-explain` in the workflow (§2) and
  gets its own design.
- Building counting-process data, which is a `bd` job's work, and
  `convert.counting()` input.
- Competing risks beyond cause-specific censoring.
- A `bh` TVC template, which could reuse `.cp_check()` but is not designed
  here.
