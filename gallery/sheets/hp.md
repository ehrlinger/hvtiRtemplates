# hp: Hazard plot

[← The template
gallery](https://ehrlinger.github.io/hvtiRtemplates/gallery/index.md)

# hp: Hazard plot

Run sheet

## What it does

Nomogram and hazard figures, read from the ac life table and the hz fit
rather than recomputed. [See the report it
produces](https://ehrlinger.github.io/hvtiRtemplates/gallery/reports/hp.md)
on the gallery's synthetic study.

## Prerequisites

- **A study.** The job runs inside a study folder set up with
  `_study.yml`. [Start a new
  study](https://ehrlinger.github.io/hvtiRtemplates/articles/new-study.html)
  shows how.
- **The jobs it reads from.** Render **ac** and **hz** first, in this
  same set: the same `subject` and `type` as this job, which is how it
  finds what they saved (`ac.rds`, `hz.rds`). For a final render, render
  them final too: a final render refuses a hand-off saved from
  unregistered data.
- **Packages:** `TemporalHazard`, `hvtiRutilities`. The job checks each
  floor when it starts, so an older library stops it at the top rather
  than partway through.

## Outline

These are the job's own sections, in order. The detail lives in the
template: the comments at each `EDIT:` marker say what to set and why,
and [Work a
job](https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html#find-what-you-have-to-change)
shows three ways to find them.

1.  **Above the first section**: 1 choice marked `EDIT:`.
2.  **Study choices**: 2 choices marked `EDIT:`.
3.  **Upstream**: reads what **ac** and **hz** saved (`ac.rds`,
    `hz.rds`).
4.  **Prediction grids**: 1 choice marked `EDIT:`.
5.  **Predictions**
6.  **Nomogram**
    - **What these confidence limits are worth**
7.  **Figures**: 1 choice marked `EDIT:`.
    - **Phase decomposition**
8.  **Save**

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

Generated from the template by hvtiRtemplates, 1.5.3 · built 2026-10-28.
The template holds the details; this sheet is its outline.
