# Job progress: how far along is a long render?

**Date:** 2026-10-21
**Status:** designed, not built. Sections approved in conversation 2026-10-21.
**Builds on:** `2026-10-20-background-jobs-design.md` (#366: `submit_job()`, `job_status()`,
`guard_long_fit()`). This branch is stacked on `spec/background-jobs`.
**Packages:** hvtiRtemplates, and boostmtree 2.0.8 (`ehrlinger/boostmtree_src`), shipped with
the partial-prediction work on `fix/predict-extrapolate-memory`.

## 1. The problem

COMMENCE (study #1375) renders `nb-boostmtree` at M = 1000. The M = 200 pass the night
before took 2 h 05 min. While it ran, the only sign of life was knitr's chunk percentage in
the render log (`32% [fit]`), which says which chunk is running but not how far into it,
how long it has taken or how long is left. With Workbench ending sessions after about two
hours, jobs are detached (#366), so the log and the status file are all a user has.

The goal: a user, or Claude on their behalf, asks "how far along is my job?" and gets the
stage, the step within it, the elapsed time and an estimate of what is left; and the log
carries a status line at a steady interval without anyone asking.

## 2. Two facts that shape the design

Both checked on 2026-10-21.

- **boostmtree's `verbose = TRUE` cannot be used.** Its `txtProgressBar()` writes to standard
  output, which knitr captures into the report. Knitting a chunk that drives a progress bar
  put the `\r` bar in the document and nothing in the console. A progress display has to
  bypass knitr's capture.
- **`cat(..., file = stderr())` from inside a chunk reaches the render log, not the
  document,** including from a chunk that forks, under `quarto render`. So a progress line
  written to `stderr()` lands wherever the render's output goes: `<job>.run.log` under
  `submit_job()`, `nohup.out`, or the terminal.

## 3. Where progress lives

### 3a. `<job>.run.progress`

A new YAML file beside the job. It is separate from `<job>.run.yml`: the runner from #366
writes `.run.yml` from its own process, while progress is written from the render's knitr
process, and two processes renaming over one file would overwrite each other's state. The
run record is the pair.

Every write is atomic (a temporary file, then a checked rename), as `.write_status()` does.

```yaml
pid: 48213
host: rsw-03
started: 2026-10-21T07:14:05-0400
updated: 2026-10-21T08:17:40-0400
stage: fit
stage_index: 7
stage_count: 19
stage_started: 2026-10-21T07:26:11-0400
step: 412
steps: 1000
unit: iteration
stages: [edit-study-choices, tbl-data, ..., provenance]
done:
  - {stage: edit-study-choices, elapsed_s: 0}
  - {stage: tbl-data, elapsed_s: 41}
```

`step`, `steps` and `unit` are absent for a stage that reports no steps. The file is
overwritten at the start of each render, so it always describes the current or last run.

### 3b. Stages come from a chunk hook

`.job_setup()` installs a knitr chunk hook, set for every chunk through
`knitr::opts_chunk$set()`, that records each chunk's start and end. `stage_count` and
`stages` come from `knitr::all_labels()`, read once when the hook is installed, less the
`setup` chunk that installs it.

- Every job scaffolded since `.job_setup()` gets stage progress by upgrading hvtiRtemplates,
  with no template edit. That includes the COMMENCE job.
- The hook is active only while knitting (`isTRUE(getOption("knitr.in.progress"))`), never
  in a console session.
- Chunks that `knitr::knit_child()` generates, such as the per-variable figures in
  `nb-boostmtree`, also fire the hook and are recorded under their own labels. They are not
  counted in `stage_count`, which reads the parent document only.

### 3c. Steps come from `.job$progress()`

`.job_setup()` returns one more element, `progress`: a function `progress(unit)` that
returns a callback `function(step, steps)`. A long computation calls the callback once per
step. The callback updates `.run.progress` and decides whether to write a log line.
Outside a render, `.job$progress()` returns `NULL`, so a console run behaves exactly as
today.

### 3d. Log lines, throttled by time

To `stderr()`, one line when a stage starts and ends, and step lines at most once every
`every` minutes:

```
2026-10-21 08:17  fit  iteration 412/1000  51m in stage  ~1h12m left in stage
```

R runs one thing at a time, so no timer can fire from inside a running fit. Each step
checks the clock and writes only if `every` minutes have passed since the last line. Steps
here are short (seconds for a boosting iteration, under an hour for a partial prediction),
so the lines come out close to the clock. A step that stalls leaves the log quiet. §4 shows
how `job_status()` makes that visible.

`every` is an option in minutes, `options(hvtiRtemplates.progress_every = 10)`, default
10, which a study can set in its `.Rprofile`. There is no "every N steps" setting: time
already covers it, and two settings could contradict each other.

### 3e. Estimated time left: the current stage only

Stage elapsed time / steps done × steps left. A whole-job estimate would have to come
from the last run's stage times, and those do not carry over a change of M (200 to 1000
here), so it would mislead in exactly the case that matters. Instead, `job_status()` names
the stages still to come.

## 4. `job_status()`

The states from #366 are unchanged. When `.run.progress` exists, `job_status()` adds a
progress block. It reads the progress file on its own when there is no `.run.yml`, so a
render started with plain `nohup quarto render` still gets an answer.

```
nb.boostmtree.avmngrad.boost.qmd: running (process 48213, since 07:14)
  stage   fit (7 of 19), 51m in stage
  step    iteration 412/1000, ~1h12m left in stage
  done    6 stages, 12m in all
  next    tbl-fit, tbl-fit-summary, ..., effects, fig-traces, save, provenance
  updated 2 min ago
```

- **Staleness.** A live process can still be stuck. If `updated` is older than the larger
  of 3 × `every` and 30 minutes, the line reads
  `updated 47 min ago, no progress since; possibly stalled`. That is a warning, not a new
  state, because a long step that reports no steps looks the same.
- **The returned list** gains `progress`: the parsed file plus `eta_s` and `stale`, so a
  script or Claude can answer "how far along?" without parsing printed text.
- **A finished or failed job** prints a table of stage times from `done`. That table is the
  record of what each step cost, and the next run's planning starts from it.
- **Read errors.** An unreadable or malformed `.run.progress` gets a one-line note naming
  the file. The job's state is still reported from `.run.yml`. Progress is advisory; it
  never stops `job_status()`.

## 5. boostmtree 2.0.8: the `progress` argument

One optional argument, `progress = NULL`, on `boostmtree()` and `partial.plot()`. It takes
a function `function(step, steps)`.

- **Fit:** called in `boostmtree.fit.tree()`'s `for (m in seq_len(M))` loop, as
  `progress(m, M)`. Cross-validation forks inside each iteration, so this loop runs only in
  the parent and the callback is never called from a worker.
- **`partial.plot()`:** called after each per-grid-point prediction (in 2.0.8, `generic.predict.boostmtree(..., .extrapolate = FALSE)`), once per
  (variable, grid point). The grids for all variables are resolved before the loop, so
  `steps` is the total number of predictions from the start and the estimate covers the
  whole step, not one variable. The call stays out of `predict()` itself.
- **Safety:** `NULL` means no calls. An error raised by the callback is caught, turned into
  a single warning, and the callback is not called again, so a progress bug cannot kill a
  fit. The argument is independent of `verbose`.
- **Not hooked:** `vimp.boostmtree()`. Importance took 4 minutes at M = 200 and is reported
  as a stage only.

Coordination, agreed with the session doing the 2.0.8 partial-prediction rewrite: their
branch (`fix/predict-extrapolate-memory`) touches `generic.predict.boostmtree.R` and
`partial_plot.boostmtree.R`, not `boostmtree_fit_tree.R`. This change is committed on top of
their branch once it is done, never alongside it. It adds a NEWS bullet under their
existing 2.0.8 heading and does not bump the version. 2.0.8 is cut and tagged when John
decides.

## 6. `nb-boostmtree`

```r
boostmtree(..., progress = .job$progress("iteration"))
partial.plot(fit, x.var.names = .effect_vars, output = "data", verbose = FALSE,
             progress = .job$progress("prediction"))
```

- `progress` must stay out of `cache_fit()`'s key, as `CORES` does: a callback changes what
  is reported, not what is fitted, and a key that included it would refit every run.
- The template's version check moves from `boostmtree >= 2.0.4` to `>= 2.0.8`, in
  hvtiRtemplates' own bump after 2.0.8 is tagged. Until then the template is unchanged and
  jobs get stage progress only.

## 7. What partial effects cost

The step this design exists for.

| COMMENCE, M = 200, 2026-10-20 | time | share |
|---|---|---|
| read the data and fit | ~12 min | 10% |
| variable importance | ~4 min | 3% |
| **partial effects, 6 variables** | **1 h 47 min** | **86%** |
| run in all | 2 h 05 min | |

- `partial.plot()` makes one prediction over the whole cohort (1,391 patients) for each
  variable × grid point, up to 25 points per variable, so up to 150 predictions. That puts
  one prediction at **43 s or more**, about 18 minutes a variable.
- **A prediction costs a fixed part that grows with T, plus a part that grows with M.**
  Measured on this Mac on 2026-10-21, boostmtree 2.0.7, one `predict(..., partial = TRUE)`
  over n = 1,391 synthetic subjects (4,062 rows, 25 predictors), from one fit:

  | T, time points predicted | M = 10 | M = 20 | M = 40 |
  |---|---|---|---|
  | 250 | 5.5 s | 6.5 s | 8.5 s |
  | 1,000 | 16.5 s | 18.2 s | 21.5 s |

  At T = 1,000 that is about 15 s fixed plus 0.17 s a tree. It reproduces the field figure:
  at M = 200 the model gives 15 + 33 = 48 s, against 43 s or more measured on COMMENCE. The
  fixed part, per-subject matrix-vector loops at the R level, is what the 2.0.8 rewrite
  works on (one partial prediction 15.6 s before, 13.3 s after, on their synthetic ordinal
  fit).
- **At M = 1000 the model gives about 3 minutes a prediction**, 15 + 170 s, if the selected
  iteration count runs to 1000: about 7.5 hours for six variables at 25 points, or about
  3.8 hours for the three the current run uses. **This is an extrapolation from M ≤ 40 and
  T = 1,000, not a measurement.** COMMENCE's T is not known here, and 2.0.8 changes the
  code being timed. The M = 1000 run's own stage table (§4) is the measurement and should
  replace this paragraph.

Not in this design: caching partial effects one variable at a time, so that a lost
process costs one variable rather than all six. For a step that is 86% of the run that is
worth doing, but it is about resuming, not reporting, and is a follow-up.

## 8. Testing

hvtiRtemplates, on top of #366's tests:

- A stand-in render whose chunks sleep briefly: `.run.progress` records the stage sequence,
  `stage_count` and the `done` list; nothing is written outside a render.
- Throttling with a mocked clock: a step line only after `every` minutes; stage lines always.
- `job_status()`: the progress block, the estimate, `updated` ageing into "possibly
  stalled", the finished-job stage table, progress without a `.run.yml`, and a malformed
  progress file reported without stopping.
- Atomic writes: a reader in a loop never sees a partial file.
- Mutation: removing the chunk hook, or the throttle check, turns the matching tests red.

boostmtree:

- The callback is called M times in order for a fit with and without `cv.flag`, and once
  per (variable, grid point) for `partial.plot()`, with `steps` fixed throughout.
- A callback that errors produces one warning, and the fit's result is identical to a fit
  with `progress = NULL`.

## 9. Documentation

Roxygen in Rd markup for the new `job_status()` output and the option; a paragraph in the
"Long-running jobs" section of `inst/templates/README.md`; a news fragment. boostmtree:
`\item{progress}` in both Rd files and the NEWS bullet.

## 10. Approaches not taken

- **`verbose = TRUE`:** goes into the report, not the log (§2).
- **Tracing `setTxtProgressBar()`** to intercept boostmtree's bar without changing it:
  fragile, and still needs `verbose = TRUE`.
- **A watcher process** started by `submit_job()` that logs on the clock, through stalls:
  more to manage and clean up, and only for jobs started with `submit_job()`. Staleness in
  `job_status()` covers the stall case. Not chosen, 2026-10-21.
- **Pushed notifications** (email from the server, or Claude polling the share): not chosen.
  The log heartbeat and `job_status()` are enough for now.
- **Stage records inside `.run.yml`:** two writers to one file (§3a).
