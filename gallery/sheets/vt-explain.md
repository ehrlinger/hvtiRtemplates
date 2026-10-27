# vt-explain: Virtual twins: explain

[← The template
gallery](https://ehrlinger.github.io/hvtiRtemplates/gallery/index.md)

# vt-explain: Virtual twins: explain

Run sheet

## What it does

The twin contrast a vt-fit job saved: by arm, by eligibility rule and by
stratum, with standardized betas and who might benefit. It never grows a
forest. [See the report it
produces](https://ehrlinger.github.io/hvtiRtemplates/gallery/reports/vt-explain.md)
on the gallery's synthetic study.

## Prerequisites

- **A study.** The job runs inside a study folder set up with
  `_study.yml`. [Start a new
  study](https://ehrlinger.github.io/hvtiRtemplates/articles/new-study.html)
  shows how.
- **The study's data.** Its choices name the registered dataset it
  reads. A draft can read a build that is not registered yet, so you can
  start before the build is final, and the report then says it is a
  draft. A final render reads registered data only: register the build
  with `hvtiRutilities::update_manifest()` first.
- **The job it reads from.** Render **vt-fit** first, in this same set:
  the same `subject` and `type` as this job, which is how it finds what
  that job saved (`vt.rds`). For a final render, render it final too: a
  final render refuses a hand-off saved from unregistered data.
- **Optional: the job it can read from.** Some of its choices read a
  saved result from **sid-clusters**. Left as the template sets them,
  the job runs without one. A choice that names one needs that job
  rendered first, in the set the choice names. For a final render,
  render it final too: a final render refuses a hand-off saved from
  unregistered data.
- **Packages:** `hvtiPlotR`, `hvtiRpropensity`, `hvtiRutilities`,
  `ggplot2`. The job checks each floor when it starts, so an older
  library stops it at the top rather than partway through.

## Outline

These are the job's own sections, in order. The detail lives in the
template: the comments at each `EDIT:` marker say what to set and why,
and [Work a
job](https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html#find-what-you-have-to-change)
shows three ways to find them.

1.  **Above the first section**: 1 choice marked `EDIT:`.
2.  **Study choices**: 3 choices marked `EDIT:`.
3.  **The fit**: reads what **vt-fit** saved (`vt.rds`); reads the study
    data.
4.  **The contrast**
5.  **Eligibility rules**
    - **The difference against the distance to the other arm**
6.  **Strata**: reads a saved result from the job its choices name, when
    they name one.
7.  **What goes with the difference**
8.  **Who might benefit from the other arm**
9.  **Reading the result**

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
