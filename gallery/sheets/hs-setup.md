# hs-setup: Hazard setup

[← The template
gallery](https://ehrlinger.github.io/hvtiRtemplates/gallery/index.md)

# hs-setup: Hazard setup

Run sheet

## What it does

Patient-level predictions from the hm model, set against the survival of
a matched general population. [See the report it
produces](https://ehrlinger.github.io/hvtiRtemplates/gallery/reports/hs-setup.md)
on the gallery's synthetic study.

## Prerequisites

- **A study.** The job runs inside a study folder set up with
  `_study.yml`. [Start a new
  study](https://ehrlinger.github.io/hvtiRtemplates/articles/new-study.html)
  shows how.
- **The job it reads from.** Render **hm** first, in this same set: the
  same `subject` and `type` as this job, which is how it finds what that
  job saved (`hm.rds`). For a final render, render it final too: a final
  render refuses a hand-off saved from unregistered data.
- **Packages:** `TemporalHazard` (\>= 1.2.12), `hvtiRutilities`,
  `hvtiRlifetables` (\>= 0.1.2), `hvtiPlotR`. The job checks each floor
  when it starts, so an older library stops it at the top rather than
  partway through.

## Outline

These are the job's own sections, in order. The detail lives in the
template: the comments at each `EDIT:` marker say what to set and why,
and [Work a
job](https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html#find-what-you-have-to-change)
shows three ways to find them.

1.  **Above the first section**: 1 choice marked `EDIT:`.
2.  **Study choices**: 3 choices marked `EDIT:`.
3.  **Cohort and model**: reads what **hm** saved (`hm.rds`).
4.  **Predictions**: 1 choice marked `EDIT:`.
5.  **Expected population survival**: 2 choices marked `EDIT:`.
6.  **Save**

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

Generated from the template by hvtiRtemplates, 1.5.2 · built 2026-10-27.
The template holds the details; this sheet is its outline.
