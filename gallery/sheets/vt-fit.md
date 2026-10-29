# vt-fit: Virtual twins: fit

[← The template
gallery](https://ehrlinger.github.io/hvtiRtemplates/gallery/index.md)

# vt-fit: Virtual twins: fit

Run sheet

## What it does

Per-arm survival forests, swapped-arm twin curves and a per-patient RMST
difference, with eligibility judged by a choice of methods. [See the
report it
produces](https://ehrlinger.github.io/hvtiRtemplates/gallery/reports/vt-fit.md)
on the gallery's synthetic study.

## Prerequisites

- **A study.** The job runs inside a study folder set up with
  `_study.yml`. [Start a new
  study](https://ehrlinger.github.io/hvtiRtemplates/articles/new-study.html)
  shows how.
- **The study's data.** `DATASET` names the registered dataset it reads
  (`"study"` unless you change it). A draft can read a build that is not
  registered yet, so you can start before the build is final, and the
  report then says it is a draft. A final render reads registered data
  only: register the build with `hvtiRutilities::update_manifest()`
  first.
- **Optional: the jobs it can read from.** Some of its choices read a
  saved result from **sid-fit** or **vp-fit**. Left as the template sets
  them, the job runs without one. A choice that names one needs that job
  rendered first, in the set the choice names. For a final render,
  render them final too: a final render refuses a hand-off saved from
  unregistered data.
- **Packages:** `randomForestSRC`, `cluster`, `hvtiRpropensity`,
  `hvtiPlotR`, `hvtiRutilities`. The job checks each floor when it
  starts, so an older library stops it at the top rather than partway
  through.

## Outline

These are the job's own sections, in order. The detail lives in the
template: the comments at each `EDIT:` marker say what to set and why,
and [Work a
job](https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html#find-what-you-have-to-change)
shows three ways to find them.

1.  **Above the first section**: 1 choice marked `EDIT:`.
2.  **Study choices**: 19 choices marked `EDIT:`.
3.  **Cohort**: reads the study data.
4.  **Predictors**: reads a saved result from the job its choices name,
    when they name one.
5.  **The observed outcome**
6.  **Eligibility**: reads a saved result from the job its choices name,
    when they name one.
    - **Who is out of distribution**
7.  **The arm forests**: fits and caches its results, so a later render
    reloads them (`REFIT <- TRUE` recomputes them).
8.  **Twin curves**
9.  **The difference in restricted mean survival time**
10. **Handoff**: saves `vt.rds`, which **vt-explain** reads.

## Run it

**Render a draft as you go.** `render_job(job)` runs the whole job in a
clean R session and writes the report beside it. Render early and often:
while any `EDIT:` marker is left, the report opens with a DRAFT banner
listing them, and its numbers are not a result. [Work a
job](https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html#render-as-you-go)
explains why to render rather than run chunks by hand.

**Then the final.** Once no marker is left,
`render_job(job, final = TRUE)` renders the accepted result. It refuses
an open marker, a skipped chunk, `stop_here()` and unregistered data,
and it records the job's provenance beside the report.

## Where to go next

- **vt-explain** reads what this job saves (`vt.rds`). Add it to the
  same set, with this job's `subject` and `type`, because that shared
  pair is how it finds the file:
  `add_job("vt.explain", subject = "<subject>", type = "<type>")`.

Generated from the template by hvtiRtemplates, 1.5.4 · built 2026-10-29.
The template holds the details; this sheet is its outline.
