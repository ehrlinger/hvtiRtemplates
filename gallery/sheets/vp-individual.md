# vp-individual: VarPro: individual

[← The template
gallery](https://ehrlinger.github.io/hvtiRtemplates/gallery/index.md)

# vp-individual: VarPro: individual

Run sheet

## What it does

Individual VarPro: each patient's local gradient for each predictor,
from the fit a vp-fit screen saved. It never fits varPro. [See the
report it
produces](https://ehrlinger.github.io/hvtiRtemplates/gallery/reports/vp-individual.md)
on the gallery's synthetic study.

## Prerequisites

- **A study.** The job runs inside a study folder set up with
  `_study.yml`. [Start a new
  study](https://ehrlinger.github.io/hvtiRtemplates/articles/new-study.html)
  shows how.
- **The job it reads from.** Render **vp-fit** first, in this same set:
  the same `subject` and `type` as this job, which is how it finds what
  that job saved (`vp.rds`). For a final render, render it final too: a
  final render refuses a hand-off saved from unregistered data.
- **Packages:** `varPro` (\>= 3.3.0), `ggRandomForests` (\>= 4.0.0),
  `hvtiRutilities`, `randomForestSRC` (\>= 3.7.0). The job checks each
  floor when it starts, so an older library stops it at the top rather
  than partway through.

## Outline

These are the job's own sections, in order. The detail lives in the
template: the comments at each `EDIT:` marker say what to set and why,
and [Work a
job](https://ehrlinger.github.io/hvtiRtemplates/articles/work-a-job.html#find-what-you-have-to-change)
shows three ways to find them.

1.  **Above the first section**: 1 choice marked `EDIT:`.
2.  **Study choices**: 5 choices marked `EDIT:`.
3.  **The screen**: reads what **vp-fit** saved (`vp.rds`).
4.  **Gradients**: fits and caches its results, so a later render
    reloads them (`REFIT <- TRUE` recomputes them).
5.  **Gradient against value**
6.  **Reading the result**

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
